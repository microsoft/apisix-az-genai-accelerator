from __future__ import annotations

import json
import logging
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import hcl2  # type: ignore[import-not-found]
from tenacity import (  # type: ignore[import-not-found]
    RetryCallState,
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from ._utils import repo_root, run_logged

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class AzureContext:
    subscription_id: str
    tenant_id: str


@dataclass(frozen=True)
class Paths:
    root: Path
    stacks: Path
    observability: Path
    bootstrap: Path
    foundation: Path
    foundry: Path
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
class ObservabilityState:
    location: str
    resource_group: str
    log_analytics_workspace_id: str
    app_insights_connection_string: str
    app_insights_instrumentation_key: str
    azure_monitor_workspace_id: str
    azure_monitor_prometheus_remote_write_endpoint: str
    azure_monitor_prometheus_query_endpoint: str
    azure_monitor_prometheus_dcr_id: str
    gateway_logs_dce_id: str | None
    gateway_logs_dcr_id: str | None
    gateway_logs_ingest_uri: str | None
    gateway_logs_stream_name: str | None
    gateway_logs_table_name: str | None


@dataclass(frozen=True)
class FoundryState:
    provisioned: bool
    state_blob_key: str | None


class StorageRbacPropagationError(Exception):
    """Raised when Storage data plane RBAC has not propagated yet."""


class RequestConflictError(Exception):
    """Raised when Azure reports a transient 409 RequestConflict on apply."""


def _is_storage_rbac_error(exc: subprocess.CalledProcessError) -> bool:
    message = (exc.stderr or "") + (exc.output or "")
    lowered = message.lower()
    return (
        "authorizationpermissionmismatch" in lowered
        or "this request is not authorized to perform this operation" in lowered
        or "status 403" in lowered
    )


def _log_storage_retry(retry_state: RetryCallState) -> None:
    attempt = retry_state.attempt_number
    sleep_for = (
        f"; waiting {retry_state.next_action.sleep:.0f}s"
        if retry_state.next_action and retry_state.next_action.sleep is not None
        else ""
    )
    logger.warning(
        "Terraform init: retrying remote state access after storage 403 "
        "(attempt %d/8)%s",
        attempt,
        sleep_for,
    )


def _is_request_conflict(exc: subprocess.CalledProcessError) -> bool:
    message = (exc.stderr or "") + (exc.output or "")
    lowered = message.lower()
    # If a 400 or other hard validation error is present, do not treat as retryable.
    if (
        "response 400" in lowered
        or "invalidresource" in lowered
        or "insufficientquota" in lowered
    ):
        return False
    return (
        "requestconflict" in lowered
        or "another operation is being performed on the parent resource" in lowered
        or "status code 409" in lowered
        or "response 409" in lowered
    )


def _is_fatal_apply_error(exc: subprocess.CalledProcessError) -> bool:
    message = (exc.stderr or "") + (exc.output or "")
    lowered = message.lower()
    fatal_markers = (
        "invalidresourceproperties",
        "invalid resource properties",
        "not supported by the model",
        "insufficientquota",
        "insufficient quota",
        "quota limit",
    )
    return any(marker in lowered for marker in fatal_markers)


def _log_apply_retry(retry_state: RetryCallState) -> None:
    attempt = retry_state.attempt_number
    sleep_for = (
        f"; waiting {retry_state.next_action.sleep:.0f}s"
        if retry_state.next_action and retry_state.next_action.sleep is not None
        else ""
    )
    logger.warning(
        "Terraform apply: retrying after Azure RequestConflict (attempt %d/5)%s",
        attempt,
        sleep_for,
    )


def configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")


def resolve_paths() -> Paths:
    root = repo_root()
    stacks = root / "infra" / "terraform" / "stacks"
    return Paths(
        root=root,
        stacks=stacks,
        observability=stacks / "05-observability",
        bootstrap=stacks / "00-bootstrap",
        foundation=stacks / "10-platform",
        foundry=stacks / "15-foundry",
        workload=stacks / "20-workload",
        config_dir=root / "config",
        toolkit_root=root / "apim-genai-gateway-toolkit" / "infra",
    )


def load_tfvars(tfvars_path: Path) -> dict[str, Any]:
    with tfvars_path.open() as handle:
        data = hcl2.load(handle)  # type: ignore[attr-defined]
    return data


def _format_value(value: Any, indent: int = 0) -> str:
    pad = "  " * indent
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        inner = ", ".join(_format_value(item, indent) for item in value)
        return f"[{inner}]"
    if isinstance(value, dict):
        lines = ["{"]  # opening brace
        for key, val in value.items():
            lines.append(f"{pad}  {key} = {_format_value(val, indent + 1)}")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    return json.dumps(value)


def _render_tfvars_local(data: dict[str, Any]) -> str:
    lines = []
    for key, value in data.items():
        lines.append(f"{key} = {_format_value(value)}")
    return "\n".join(lines) + "\n"


def _log_tfvars_diff(
    tfvars_path: Path, before: dict[str, Any] | None, after: dict[str, Any]
) -> None:
    if before is None:
        return
    try:
        from deepdiff import DeepDiff  # type: ignore[import-not-found]
    except ImportError:
        logger.debug("DeepDiff not installed; skipping tfvars diff for %s", tfvars_path)
        return
    diff = DeepDiff(before, after, ignore_order=True)
    if diff:
        pretty = json.dumps(json.loads(diff.to_json()), indent=2, sort_keys=True)
        logger.info("Updated tfvars %s:\n%s", tfvars_path.name, pretty)


def _write_tfvars(tfvars_path: Path, data: dict[str, Any]) -> None:
    if tfvars_path.exists():
        try:
            before = load_tfvars(tfvars_path)
        except Exception:
            before = None
    else:
        before = None

    rendered = _render_tfvars_local(data)
    tfvars_path.write_text(rendered)
    _log_tfvars_diff(tfvars_path, before, data)


def set_tfvars(
    tfvars_path: Path, subscription_id: str, tenant_id: str, env: str
) -> None:
    data = load_tfvars(tfvars_path)
    data["subscription_id"] = subscription_id
    data["tenant_id"] = tenant_id
    data["environment_code"] = env
    _write_tfvars(tfvars_path, data)


def update_tfvars(tfvars_path: Path, updates: dict[str, Any]) -> None:
    data = load_tfvars(tfvars_path)
    for key, value in updates.items():
        if value is None:
            continue
        data[key] = value
    _write_tfvars(tfvars_path, data)


def ensure_tfvars(
    stack_dir: Path, env: str, subscription_id: str, tenant_id: str
) -> Path:
    target = stack_dir / f"{env}.tfvars"
    candidates = [
        stack_dir / f"terraform.tfvars.{env}.example",
        stack_dir / f"{env}.tfvars.example",
    ]
    example = next((path for path in candidates if path.exists()), None)

    if not target.exists():
        if example is None:
            raise FileNotFoundError(
                f"No tfvars present for env '{env}' and no example tfvars found in {stack_dir}"
            )
        target.write_text(example.read_text())
        logger.info("Seeded tfvars: %s (from %s)", target, example.name)
        base_data = load_tfvars(target)
    else:
        try:
            current_data = load_tfvars(target)
        except Exception as exc:  # hcl parse error fallback
            logger.warning(
                "Failed to parse existing tfvars %s (%s); regenerating from example",
                target.name,
                exc,
            )
            current_data = {}
        if example is not None:
            # Backfill any missing keys from the example without overwriting existing values.
            base_data = load_tfvars(example)
            base_data.update(current_data)
        else:
            base_data = current_data

    base_data["subscription_id"] = subscription_id
    base_data["tenant_id"] = tenant_id
    base_data["environment_code"] = env

    _write_tfvars(target, base_data)
    return target


def azure_context() -> AzureContext:
    subscription_id = run_logged(
        ["az", "account", "show", "--query", "id", "-o", "tsv"],
        capture_output=True,
        echo="on_error",
    ).stdout.strip()
    tenant_id = run_logged(
        ["az", "account", "show", "--query", "tenantId", "-o", "tsv"],
        capture_output=True,
        echo="on_error",
    ).stdout.strip()
    return AzureContext(subscription_id=subscription_id, tenant_id=tenant_id)


def export_core_tf_env(env: str, ctx: AzureContext) -> None:
    os.environ["TF_VAR_subscription_id"] = ctx.subscription_id
    os.environ["TF_VAR_tenant_id"] = ctx.tenant_id
    os.environ["TF_VAR_environment_code"] = env
    os.environ["ARM_SUBSCRIPTION_ID"] = ctx.subscription_id
    os.environ["ARM_TENANT_ID"] = ctx.tenant_id


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
    run_logged(
        [
            "terraform",
            f"-chdir={stack_dir}",
            "init",
            "-reconfigure",
            f"-backend-config=path={state_path}",
        ],
    )


@retry(
    reraise=True,
    retry=retry_if_exception_type(StorageRbacPropagationError),
    stop=stop_after_attempt(8),
    wait=wait_exponential(multiplier=1, min=2, max=30),
    before_sleep=_log_storage_retry,
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
    try:
        run_logged(
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
            capture_output=True,
            echo="always",
        )
    except subprocess.CalledProcessError as exc:
        if _is_storage_rbac_error(exc):
            raise StorageRbacPropagationError(str(exc)) from exc
        raise


@retry(
    reraise=True,
    retry=retry_if_exception_type(RequestConflictError),
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, min=5, max=60),
    before_sleep=_log_apply_retry,
)
def terraform_apply(stack_dir: Path, tfvars_file: Path) -> None:
    try:
        run_logged(
            [
                "terraform",
                f"-chdir={stack_dir}",
                "apply",
                "-auto-approve",
                f"-var-file={tfvars_file.name}",
            ],
            capture_output=True,
            echo="always",
        )
    except subprocess.CalledProcessError as exc:
        if _is_request_conflict(exc) and not _is_fatal_apply_error(exc):
            raise RequestConflictError(str(exc)) from exc
        raise


def terraform_output(stack_dir: Path) -> dict[str, Any]:
    output = run_logged(
        ["terraform", f"-chdir={stack_dir}", "output", "-json"],
        capture_output=True,
        echo="never",
    ).stdout
    return json.loads(output)


def state_prefix_from_blob(blob_key: str) -> str:
    suffix = "/terraform.tfstate"
    if blob_key.endswith(suffix):
        return blob_key[: -len(suffix)]
    return blob_key


def state_key(prefix: str, filename: str) -> str:
    normalized_prefix = prefix.rstrip("/")
    return (
        f"{normalized_prefix}/{filename}.tfstate"
        if normalized_prefix
        else f"{filename}.tfstate"
    )


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


def observability_state_from_outputs(outputs: dict[str, Any]) -> ObservabilityState:
    return ObservabilityState(
        location=_required_output(outputs, "location"),
        resource_group=_required_output(outputs, "observability_rg_name"),
        log_analytics_workspace_id=_required_output(
            outputs, "log_analytics_workspace_id"
        ),
        app_insights_connection_string=_optional_output(
            outputs, "app_insights_connection_string"
        ),
        app_insights_instrumentation_key=_optional_output(
            outputs, "app_insights_instrumentation_key"
        ),
        azure_monitor_workspace_id=_required_output(
            outputs, "azure_monitor_workspace_id"
        ),
        azure_monitor_prometheus_remote_write_endpoint=_optional_output(
            outputs, "azure_monitor_prometheus_remote_write_endpoint"
        ),
        azure_monitor_prometheus_query_endpoint=_optional_output(
            outputs, "azure_monitor_prometheus_query_endpoint"
        ),
        azure_monitor_prometheus_dcr_id=_optional_output(
            outputs, "azure_monitor_prometheus_dcr_id"
        ),
        gateway_logs_dce_id=_optional_output(outputs, "gateway_logs_dce_id"),
        gateway_logs_dcr_id=_optional_output(outputs, "gateway_logs_dcr_id"),
        gateway_logs_ingest_uri=_optional_output(outputs, "gateway_logs_ingest_uri"),
        gateway_logs_stream_name=_optional_output(outputs, "gateway_logs_stream_name"),
        gateway_logs_table_name=_optional_output(outputs, "gateway_logs_table_name"),
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


def load_observability_state(
    env: str, paths: Paths, ctx: AzureContext, bootstrap_state: BootstrapState
) -> ObservabilityState:
    export_core_tf_env(env, ctx)
    terraform_init_remote(
        paths.observability,
        tenant_id=ctx.tenant_id,
        state_rg=bootstrap_state.resource_group,
        state_sa=bootstrap_state.storage_account,
        state_container=bootstrap_state.container,
        state_key=state_key(bootstrap_state.state_prefix, "05-observability"),
    )
    outputs = terraform_output(paths.observability)
    return observability_state_from_outputs(outputs)


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
