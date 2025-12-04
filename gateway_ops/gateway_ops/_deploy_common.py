from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import hcl2
from pytfvars import tfvars

from ._utils import repo_root

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class AzureContext:
    subscription_id: str
    tenant_id: str


@dataclass(frozen=True)
class Paths:
    root: Path
    stacks: Path
    bootstrap: Path
    foundation: Path
    openai: Path
    workload: Path
    config_dir: Path
    toolkit_root: Path


@dataclass(frozen=True)
class BootstrapState:
    resource_group: str
    storage_account: str
    container: str
    state_prefix: str


@dataclass(frozen=True)
class FoundationState:
    location: str
    platform_resource_group: str
    acr_name: str
    key_vault_name: str
    aca_identity_id: str


@dataclass(frozen=True)
class OpenAIState:
    provisioned: bool
    state_blob_key: str | None


def configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")


def resolve_paths() -> Paths:
    root = repo_root()
    stacks = root / "infra" / "terraform" / "stacks"
    return Paths(
        root=root,
        stacks=stacks,
        bootstrap=stacks / "00-bootstrap",
        foundation=stacks / "10-platform",
        openai=stacks / "15-openai",
        workload=stacks / "20-workload",
        config_dir=root / "config",
        toolkit_root=root / "apim-genai-gateway-toolkit" / "infra",
    )


def read_env(path: Path) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    with path.open() as handle:
        for raw in handle:
            line = raw.strip()
            if line == "" or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            pairs.append((key, value))
    return pairs


def load_tfvars(tfvars_path: Path) -> dict[str, Any]:
    with tfvars_path.open() as handle:
        data = hcl2.load(handle)  # type: ignore[attr-defined]
    return data


def set_tfvars(
    tfvars_path: Path, subscription_id: str, tenant_id: str, env: str
) -> None:
    data = load_tfvars(tfvars_path)
    data["subscription_id"] = subscription_id
    data["tenant_id"] = tenant_id
    data["environment_code"] = env

    rendered = tfvars.convert(data)
    tfvars_path.write_text(f"{rendered}\n")


def ensure_tfvars(
    stack_dir: Path, env: str, subscription_id: str, tenant_id: str
) -> Path:
    target = stack_dir / f"{env}.tfvars"
    if target.exists():
        return target

    candidates = [
        stack_dir / f"terraform.tfvars.{env}.example",
        stack_dir / f"{env}.tfvars.example",
        stack_dir / "terraform.tfvars.example",
    ]

    example = next((path for path in candidates if path.exists()), None)
    if example is None:
        raise FileNotFoundError(
            f"No tfvars present for env '{env}' and no example tfvars found in {stack_dir}"
        )

    target.write_text(example.read_text())
    set_tfvars(target, subscription_id, tenant_id, env)
    logger.info("Seeded tfvars: %s (from %s)", target, example.name)
    return target


def azure_context() -> AzureContext:
    subscription_id = subprocess.run(
        ["az", "account", "show", "--query", "id", "-o", "tsv"],
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()
    tenant_id = subprocess.run(
        ["az", "account", "show", "--query", "tenantId", "-o", "tsv"],
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()
    return AzureContext(subscription_id=subscription_id, tenant_id=tenant_id)


def export_core_tf_env(env: str, ctx: AzureContext) -> None:
    os.environ["TF_VAR_subscription_id"] = ctx.subscription_id
    os.environ["TF_VAR_tenant_id"] = ctx.tenant_id
    os.environ["TF_VAR_environment_code"] = env


def export_foundation_tf_env(
    env: str, ctx: AzureContext, bootstrap: BootstrapState, foundation: FoundationState
) -> None:
    export_core_tf_env(env, ctx)
    os.environ["TF_VAR_location"] = foundation.location
    os.environ["TF_VAR_platform_resource_group_name"] = (
        foundation.platform_resource_group
    )
    os.environ["TF_VAR_platform_acr_name"] = foundation.acr_name
    os.environ["TF_VAR_state_resource_group_name"] = bootstrap.resource_group
    os.environ["TF_VAR_state_storage_account_name"] = bootstrap.storage_account
    os.environ["TF_VAR_state_container_name"] = bootstrap.container
    os.environ["TF_VAR_remote_state_resource_group_name"] = bootstrap.resource_group
    os.environ["TF_VAR_remote_state_storage_account_name"] = bootstrap.storage_account
    os.environ["TF_VAR_remote_state_container_name"] = bootstrap.container
    os.environ["TF_VAR_foundation_state_blob_key"] = state_key(
        bootstrap.state_prefix, "10-platform"
    )
    os.environ["TF_VAR_key_vault_name"] = foundation.key_vault_name
    os.environ["TF_VAR_aca_managed_identity_id"] = foundation.aca_identity_id


def terraform_init_local(stack_dir: Path, state_path: Path) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "terraform",
            f"-chdir={stack_dir}",
            "init",
            "-reconfigure",
            f"-backend-config=path={state_path}",
        ],
        text=True,
        check=True,
    )


def terraform_init_remote(
    stack_dir: Path,
    *,
    tenant_id: str,
    state_rg: str,
    state_sa: str,
    state_container: str,
    state_key: str,
) -> None:
    subprocess.run(
        [
            "terraform",
            f"-chdir={stack_dir}",
            "init",
            "-reconfigure",
            "-backend-config=use_azuread_auth=true",
            f"-backend-config=tenant_id={tenant_id}",
            f"-backend-config=resource_group_name={state_rg}",
            f"-backend-config=storage_account_name={state_sa}",
            f"-backend-config=container_name={state_container}",
            f"-backend-config=key={state_key}",
        ],
        text=True,
        check=True,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )


def terraform_apply(stack_dir: Path, tfvars_file: Path) -> None:
    subprocess.run(
        [
            "terraform",
            f"-chdir={stack_dir}",
            "apply",
            "-auto-approve",
            f"-var-file={tfvars_file.name}",
        ],
        text=True,
        check=True,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )


def terraform_output(stack_dir: Path) -> dict[str, Any]:
    output = subprocess.run(
        ["terraform", f"-chdir={stack_dir}", "output", "-json"],
        text=True,
        capture_output=True,
        check=True,
    ).stdout
    return json.loads(output)


def state_prefix_from_blob(blob_key: str) -> str:
    suffix = "/terraform.tfstate"
    if blob_key.endswith(suffix):
        return blob_key[: -len(suffix)]
    return blob_key


def state_key(prefix: str, filename: str) -> str:
    return f"{prefix}/{filename}.tfstate"


def bootstrap_state_from_outputs(outputs: dict[str, Any]) -> BootstrapState:
    state_rg = _required_output(outputs, "state_rg_name")
    state_sa = _required_output(outputs, "storage_account_name")
    state_container = _required_output(outputs, "state_container_name")
    state_blob_key = _required_output(outputs, "state_blob_key")
    return BootstrapState(
        resource_group=state_rg,
        storage_account=state_sa,
        container=state_container,
        state_prefix=state_prefix_from_blob(state_blob_key),
    )


def foundation_state_from_outputs(outputs: dict[str, Any]) -> FoundationState:
    return FoundationState(
        location=_required_output(outputs, "location"),
        platform_resource_group=_required_output(
            outputs, "platform_resource_group_name"
        ),
        acr_name=_required_output(outputs, "platform_acr_name"),
        key_vault_name=_optional_output(outputs, "key_vault_name"),
        aca_identity_id=_optional_output(outputs, "aca_managed_identity_id"),
    )


def _required_output(outputs: dict[str, Any], key: str) -> str:
    value = outputs.get(key, {}).get("value")
    if value is None:
        raise KeyError(f"Missing terraform output '{key}'")
    return str(value)


def _optional_output(outputs: dict[str, Any], key: str) -> str:
    value = outputs.get(key, {}).get("value")
    if value is None:
        return ""
    return str(value)


def load_bootstrap_state(env: str, paths: Paths, ctx: AzureContext) -> BootstrapState:
    state_path = paths.bootstrap / ".state" / env / "bootstrap.tfstate"
    if not state_path.exists():
        raise FileNotFoundError(
            f"Bootstrap state not found at {state_path}. Run deploy-bootstrap for env '{env}' first."
        )
    export_core_tf_env(env, ctx)
    terraform_init_local(paths.bootstrap, state_path)
    outputs = terraform_output(paths.bootstrap)
    return bootstrap_state_from_outputs(outputs)


def load_foundation_state(
    env: str, paths: Paths, ctx: AzureContext, bootstrap_state: BootstrapState
) -> FoundationState:
    export_core_tf_env(env, ctx)
    terraform_init_remote(
        paths.foundation,
        tenant_id=ctx.tenant_id,
        state_rg=bootstrap_state.resource_group,
        state_sa=bootstrap_state.storage_account,
        state_container=bootstrap_state.container,
        state_key=state_key(bootstrap_state.state_prefix, "10-platform"),
    )
    outputs = terraform_output(paths.foundation)
    return foundation_state_from_outputs(outputs)
