from __future__ import annotations

import argparse
import json
import logging
import subprocess
import sys
from pathlib import Path

from tenacity import (
    before_sleep_log,
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    FoundationState,
    Paths,
    azure_context,
    load_bootstrap_state,
    load_foundation_state,
    resolve_paths,
    state_key,
    terraform_init_remote,
    terraform_output,
)
from ._utils import ensure, repo_root, run_logged

logger = logging.getLogger(__name__)


def read_env(path: Path) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    with path.open() as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            pairs.append((key, value))
    return pairs


def resolve_key_vault(env: str, override: str) -> str:
    explicit = override.strip()
    if explicit != "":
        return explicit

    ensure(["terraform"])

    try:
        ctx: AzureContext = azure_context()
        paths: Paths = resolve_paths()
        bootstrap: BootstrapState = load_bootstrap_state(env, paths, ctx)
        foundation: FoundationState = load_foundation_state(env, paths, ctx, bootstrap)
    except (FileNotFoundError, subprocess.CalledProcessError, KeyError) as exc:
        raise RuntimeError(
            "Failed to resolve Key Vault from terraform outputs; supply --key-vault to override."
        ) from exc

    if foundation.key_vault_name != "":
        return foundation.key_vault_name

    raise RuntimeError(
        "Key Vault name missing from terraform outputs. Provide --key-vault to continue."
    )


def _current_object_id() -> str:
    user_info = json.loads(
        run_logged(
            ["az", "account", "show", "--query", "user", "-o", "json"],
            capture_output=True,
        ).stdout
    )
    user_type = user_info.get("type", "")
    user_name = user_info.get("name", "")

    if user_type == "user":
        return run_logged(
            ["az", "ad", "signed-in-user", "show", "--query", "id", "-o", "tsv"],
            capture_output=True,
        ).stdout.strip()

    # service principal flow
    return run_logged(
        ["az", "ad", "sp", "show", "--id", user_name, "--query", "id", "-o", "tsv"],
        capture_output=True,
    ).stdout.strip()


def ensure_kv_secrets_officer(vault_name: str) -> None:
    kv_id = run_logged(
        ["az", "keyvault", "show", "-n", vault_name, "--query", "id", "-o", "tsv"],
        capture_output=True,
    ).stdout.strip()
    principal_id = _current_object_id()
    try:
        run_logged(
            [
                "az",
                "role",
                "assignment",
                "create",
                "--assignee-object-id",
                principal_id,
                "--role",
                "Key Vault Secrets Officer",
                "--scope",
                kv_id,
                "--only-show-errors",
                "-o",
                "none",
            ],
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        msg = (exc.stderr or "") + (exc.stdout or "")
        if "Existing role assignment" in msg or "already exists" in msg:
            return
        raise


class RbacPropagationError(Exception):
    """Raised when Key Vault RBAC propagation has not completed yet."""


def _is_forbidden_by_rbac(exc: subprocess.CalledProcessError) -> bool:
    msg = (exc.stderr or "") + (exc.stdout or "")
    lowered = msg.lower()
    return (
        "forbiddenbyrbac" in lowered
        or "caller is not authorized" in lowered
        or ("forbidden" in lowered and "keyvault" in lowered)
    )


@retry(
    reraise=True,
    retry=retry_if_exception_type(RbacPropagationError),
    stop=stop_after_attempt(8),
    wait=wait_exponential(multiplier=1, min=2, max=30),
    before_sleep=before_sleep_log(logger, logging.WARNING),
)
def set_secret_with_retry(vault_name: str, secret_name: str, value: str) -> None:
    try:
        run_logged(
            [
                "az",
                "keyvault",
                "secret",
                "set",
                "--vault-name",
                vault_name,
                "--name",
                secret_name,
                "--value",
                value,
            ],
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        if _is_forbidden_by_rbac(exc):
            raise RbacPropagationError(str(exc)) from exc
        raise


def _sync_foundry_secrets(env: str, vault_name: str) -> None:
    paths = resolve_paths()
    ctx = azure_context()
    bootstrap = load_bootstrap_state(env, paths, ctx)
    # Foundry stack is optional; skip silently if missing.
    if not paths.foundry.exists():
        logger.info("15-foundry stack not present; skipping provisioned OpenAI secrets sync")
        return

    foundry_state_key = state_key(bootstrap.state_prefix, "15-foundry")
    try:
        terraform_init_remote(
            paths.foundry,
            tenant_id=ctx.tenant_id,
            state_rg=bootstrap.resource_group,
            state_sa=bootstrap.storage_account,
            state_container=bootstrap.container,
            state_key=foundry_state_key,
        )
        outputs = terraform_output(paths.foundry)
    except Exception as exc:
        logger.info(
            "Skipping provisioned OpenAI secret sync (could not read 15-foundry state: %s)",
            exc,
        )
        return

    secret_names = outputs.get("azure_openai_key_vault_secret_names", {}).get("value") or []
    secret_values = outputs.get("azure_openai_primary_keys", {}).get("value") or []

    if not secret_names or not secret_values:
        logger.info(
            "No provisioned OpenAI secrets found in 15-foundry outputs; skipping sync"
        )
        return

    if len(secret_names) != len(secret_values):
        logger.warning(
            "Mismatch between OpenAI secret names and values (%d vs %d); skipping sync",
            len(secret_names),
            len(secret_values),
        )
        return

    logger.info("Syncing %d provisioned OpenAI secrets into Key Vault %s", len(secret_names), vault_name)
    for name, value in zip(secret_names, secret_values):
        set_secret_with_retry(vault_name, name, value)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="sync-env",
        description="Sync config/appsettings.<env>.env and secrets.<env>.env into Key Vault and environment.auto.tfvars.json.",
    )
    parser.add_argument("env")
    parser.add_argument(
        "--key-vault",
        default="",
        help="Override Key Vault name; defaults to terraform output",
    )
    parser.add_argument("--identifier", default="")
    parser.add_argument("--use-provisioned-openai", action="store_true")
    args = parser.parse_args(argv)

    ensure(["az"])

    root = repo_root()
    config_dir = root / "config"
    workload_dir = root / "infra" / "terraform" / "stacks" / "20-workload"
    tfvars_out = workload_dir / "environment.auto.tfvars.json"

    app_file = config_dir / f"appsettings.{args.env}.env"
    if not app_file.exists():
        sys.stderr.write(f"missing {app_file}\n")
        return 1

    app_settings: dict[str, str] = {}
    for key, value in read_env(app_file):
        app_settings[key] = value

    secrets_file = config_dir / f"secrets.{args.env}.env"
    secret_keys: list[str] = []

    key_vault = resolve_key_vault(args.env, args.key_vault)
    ensure_kv_secrets_officer(key_vault)

    if secrets_file.exists():
        for key, value in read_env(secrets_file):
            secret_keys.append(key)
            secret_name = key.lower().replace("_", "-")
            set_secret_with_retry(key_vault, secret_name, value)

    if args.use_provisioned_openai:
        _sync_foundry_secrets(args.env, key_vault)

    unique_keys: list[str] = []
    for key in secret_keys:
        if key not in unique_keys:
            unique_keys.append(key)

    data = {
        "key_vault_name": key_vault,
        "identifier": args.identifier,
        "use_provisioned_azure_openai": args.use_provisioned_openai,
        "secret_keys": unique_keys,
        "app_settings": app_settings,
    }

    tfvars_out.write_text(json.dumps(data, indent=2) + "\n")

    settings_count = len(app_settings)
    print(
        f"Synced env '{args.env}' (settings: {settings_count}, secrets tracked: {len(unique_keys)})"
    )
    print(f"Wrote {tfvars_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
