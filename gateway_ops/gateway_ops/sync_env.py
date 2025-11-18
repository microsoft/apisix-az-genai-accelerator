from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    FoundationState,
    Paths,
    azure_context,
    load_bootstrap_state,
    load_foundation_state,
    resolve_paths,
)
from ._utils import ensure, repo_root


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

    if secrets_file.exists():
        for key, value in read_env(secrets_file):
            secret_keys.append(key)
            secret_name = key.lower().replace("_", "-")
            subprocess.run(
                [
                    "az",
                    "keyvault",
                    "secret",
                    "set",
                    "--vault-name",
                    key_vault,
                    "--name",
                    secret_name,
                    "--value",
                    value,
                ],
                text=True,
                check=True,
            )

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
