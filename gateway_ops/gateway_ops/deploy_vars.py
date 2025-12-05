from __future__ import annotations

import argparse
import json
import logging
import subprocess
import sys
from typing import Any

from ._deploy_common import (
    resolve_paths,
)
from ._openai_secrets import seed_openai_secrets, set_secret_with_retry
from ._utils import ensure, read_env, repo_root, run_logged

logger = logging.getLogger(__name__)


def resolve_key_vault(env: str, override: str) -> str:
    explicit = override.strip()
    if explicit != "":
        return explicit

    # Prefer the locally cached tfvars (written by deploy-vars after first apply)
    tfvars_path = (
        repo_root()
        / "infra"
        / "terraform"
        / "stacks"
        / "20-workload"
        / "environment.auto.tfvars.json"
    )
    if tfvars_path.exists():
        try:
            data = json.loads(tfvars_path.read_text())
            kv = str(data.get("key_vault_name", "")).strip()
            if kv:
                return kv
        except Exception:
            pass

    raise RuntimeError(
        "Key Vault name not found. Provide --key-vault or ensure environment.auto.tfvars.json exists with key_vault_name."
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


def _infer_openai_secret_names(app_settings: dict[str, str]) -> list[str]:
    indices: set[int] = set()
    prefix = "AZURE_OPENAI_"
    for key in app_settings:
        if not key.startswith(prefix):
            continue
        maybe_index = key.rsplit("_", 1)[-1]
        if maybe_index.isdigit():
            indices.add(int(maybe_index))
    return [f"azure-openai-key-{idx}" for idx in sorted(indices)]


def _log_openai_seed_summary(summary: dict[str, list[str]]) -> None:
    seeded = len(summary["seeded"])
    placeholders = len(summary["placeholders"])
    unchanged = len(summary["unchanged"])
    skipped = len(summary["skipped"])
    logger.info(
        "OpenAI secret sync result: seeded=%d placeholders=%d unchanged=%d skipped=%d",
        seeded,
        placeholders,
        unchanged,
        skipped,
    )


def _load_workload_outputs(env: str) -> dict[str, Any]:
    ensure(["terraform"])
    root = repo_root()
    stack_dir = root / "infra" / "terraform" / "stacks" / "20-workload"
    raw = run_logged(
        ["terraform", f"-chdir={stack_dir}", "output", "-json"],
        capture_output=True,
    ).stdout
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"Unable to parse workload terraform outputs for env '{env}': {exc}"
        ) from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="deploy-vars",
        description="Sync config/appsettings.<env>.env and secrets.<env>.env into Key Vault and environment.auto.tfvars.json, then apply terraform (unless --no-apply).",
    )
    parser.add_argument("env")
    parser.add_argument(
        "--key-vault",
        default="",
        help="Override Key Vault name; defaults to terraform output",
    )
    parser.add_argument("--identifier", default="")
    parser.add_argument("--use-provisioned-openai", action="store_true")
    parser.add_argument(
        "--no-apply",
        action="store_true",
        help="Skip Terraform apply; only update tfvars and Key Vault.",
    )
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
    paths = resolve_paths()

    key_vault = resolve_key_vault(args.env, args.key_vault)
    ensure_kv_secrets_officer(key_vault)

    if secrets_file.exists():
        for key, value in read_env(secrets_file):
            secret_keys.append(key)
            secret_name = key.lower().replace("_", "-")
            set_secret_with_retry(key_vault, secret_name, value)

    openai_secret_names = _infer_openai_secret_names(app_settings)
    should_seed_openai = (
        paths.foundry.exists()
        or args.use_provisioned_openai
        or len(openai_secret_names) > 0
    )
    if should_seed_openai:
        summary = seed_openai_secrets(
            args.env,
            key_vault,
            expected_secret_names=openai_secret_names,
            allow_placeholders=True,
            paths=paths,
        )
        _log_openai_seed_summary(summary)

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
    if args.no_apply:
        print("Skipped Terraform apply (--no-apply).")
        return 0

    ensure(["terraform"])
    print("Applying workload stack to roll a new revision with updated env vars ...")
    tfvars_candidates = [
        workload_dir / f"terraform.tfvars.{args.env}",
        workload_dir / f"{args.env}.tfvars",
        workload_dir / f"{args.env}.tfvars.json",
        workload_dir / "terraform.tfvars",
    ]
    var_file_args: list[str] = []
    for candidate in tfvars_candidates:
        if candidate.exists():
            var_file_args.extend(["-var-file", str(candidate)])
            break

    run_logged(
        [
            "terraform",
            f"-chdir={workload_dir}",
            "apply",
            *var_file_args,
            "-auto-approve",
            "-input=false",
            "-compact-warnings",
        ],
        capture_output=False,
    )
    print("✓ Terraform apply completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
