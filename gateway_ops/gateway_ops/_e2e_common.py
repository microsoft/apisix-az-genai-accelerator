from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from typing import Any

from ._utils import ensure, repo_root

logger = logging.getLogger(__name__)


REPO_ROOT = repo_root()
STACK_DIR = REPO_ROOT / "infra" / "terraform" / "stacks" / "20-workload"
TOOLKIT_TEST_ROOT = REPO_ROOT / "apim-genai-gateway-toolkit" / "end_to_end_tests"
ENV_AUTO_FILE = STACK_DIR / "environment.auto.tfvars.json"
APIM_GATEWAY_LOGS_TABLE = "APISIXGatewayLogs_CL"
CLIENT_KEY_NAMES = (
    "GATEWAY_CLIENT_KEY_0",
    "GATEWAY_CLIENT_KEY_1",
    "GATEWAY_CLIENT_KEY_2",
)


def _run_command(command: list[str]) -> str:
    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed: {' '.join(command)}\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
    return result.stdout.strip()


def _load_auto_tfvars() -> dict[str, Any]:
    if not ENV_AUTO_FILE.exists():
        raise FileNotFoundError(
            f"{ENV_AUTO_FILE} is missing. Run 'uv run sync-env -- <env> [--key-vault <name>]' first."
        )
    return json.loads(ENV_AUTO_FILE.read_text())


def _terraform_outputs() -> dict[str, Any]:
    ensure(["terraform"])
    raw = _run_command(["terraform", f"-chdir={STACK_DIR}", "output", "-json"])
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Unable to parse terraform outputs: {exc}") from exc


def _output_value(outputs: dict[str, Any], key: str) -> Any:
    if key not in outputs:
        raise KeyError(
            f"Terraform output '{key}' is missing. Ensure 20-workload was applied."
        )
    value = outputs[key].get("value")
    if value in (None, ""):
        raise ValueError(f"Terraform output '{key}' is empty.")
    return value


def _workspace_info(workspace_resource_id: str) -> tuple[str, str]:
    ensure(["az"])
    workspace_name = workspace_resource_id.rstrip("/").split("/")[-1]
    customer_id = _run_command(
        [
            "az",
            "monitor",
            "log-analytics",
            "workspace",
            "show",
            "--ids",
            workspace_resource_id,
            "--query",
            "customerId",
            "-o",
            "tsv",
        ]
    )
    if customer_id == "":
        raise RuntimeError("Failed to resolve Log Analytics workspace customerId")
    return customer_id, workspace_name


def _account_context(
    fallback_subscription: str | None = None, fallback_tenant: str | None = None
) -> tuple[str, str]:
    ensure(["az"])
    try:
        account_raw = _run_command(
            [
                "az",
                "account",
                "show",
                "--query",
                "{id:id,tenantId:tenantId}",
                "-o",
                "json",
            ]
        )
        data = json.loads(account_raw)
        return str(data["id"]), str(data["tenantId"])
    except Exception:  # noqa: BLE001
        if fallback_subscription and fallback_tenant:
            return fallback_subscription, fallback_tenant
        raise


def _secret_from_key_vault(vault_name: str, key: str) -> str | None:
    ensure(["az"])
    secret_name = key.lower().replace("_", "-")
    try:
        value = _run_command(
            [
                "az",
                "keyvault",
                "secret",
                "show",
                "--vault-name",
                vault_name,
                "--name",
                secret_name,
                "--query",
                "value",
                "-o",
                "tsv",
            ]
        )
    except RuntimeError:
        return None
    return value if value != "" else None


def _load_client_keys(
    vault_name: str,
    secret_keys: list[str],
    app_settings: dict[str, str],
) -> list[str]:
    keys: list[str] = []
    for key in CLIENT_KEY_NAMES:
        value = None
        if key in secret_keys:
            value = _secret_from_key_vault(vault_name, key)
        if value is None:
            value = app_settings.get(key)
        if value is None:
            value = os.getenv(key)
        if value is None:
            raise RuntimeError(
                f"Client key '{key}' not found in Key Vault '{vault_name}', app settings, or environment."
            )
        keys.append(value)
    return keys


def build_test_environment() -> dict[str, str]:
    auto = _load_auto_tfvars()
    outputs = _terraform_outputs()

    gateway_url = str(_output_value(outputs, "gateway_url")).rstrip("/")
    resource_group_name = str(_output_value(outputs, "resource_group_name"))
    workspace_resource_id = str(_output_value(outputs, "log_analytics_workspace_id"))
    workspace_id, workspace_name = _workspace_info(workspace_resource_id)
    subscription_id, tenant_id = _account_context(
        fallback_subscription=str(auto.get("subscription_id", "")),
        fallback_tenant=str(auto.get("tenant_id", "")),
    )

    simulator_api_key = str(_output_value(outputs, "simulator_api_key"))
    simulator_ptu1 = str(_output_value(outputs, "simulator_ptu1_fqdn"))
    simulator_payg1 = str(_output_value(outputs, "simulator_payg1_fqdn"))
    simulator_payg2 = str(_output_value(outputs, "simulator_payg2_fqdn"))

    app_insights_connection_string = (
        str(_output_value(outputs, "app_insights_connection_string"))
        if "app_insights_connection_string" in outputs
        else ""
    )

    secret_keys = auto.get("secret_keys", [])
    app_settings = auto.get("app_settings", {})
    vault_name = auto.get("key_vault_name")
    if vault_name is None or vault_name == "":
        raise RuntimeError("key_vault_name missing from environment.auto.tfvars.json")

    client_keys = _load_client_keys(vault_name, secret_keys, app_settings)

    env = {
        "APIM_SUBSCRIPTION_ONE_KEY": client_keys[0],
        "APIM_SUBSCRIPTION_TWO_KEY": client_keys[1],
        "APIM_SUBSCRIPTION_THREE_KEY": client_keys[2],
        "APIM_ENDPOINT": gateway_url,
        "APP_INSIGHTS_NAME": "",
        "APP_INSIGHTS_CONNECTION_STRING": app_insights_connection_string,
        "SIMULATOR_ENDPOINT_PTU1": simulator_ptu1,
        "SIMULATOR_ENDPOINT_PAYG1": simulator_payg1,
        "SIMULATOR_ENDPOINT_PAYG2": simulator_payg2,
        "SIMULATOR_API_KEY": simulator_api_key,
        "LOG_ANALYTICS_WORKSPACE_ID": workspace_id,
        "LOG_ANALYTICS_WORKSPACE_NAME": workspace_name,
        "APIM_GATEWAY_LOGS_TABLE": APIM_GATEWAY_LOGS_TABLE,
        "TENANT_ID": tenant_id,
        "SUBSCRIPTION_ID": subscription_id,
        "RESOURCE_GROUP_NAME": resource_group_name,
        "OTEL_SERVICE_NAME": "locust",
        "OTEL_METRIC_EXPORT_INTERVAL": "10000",
        "LOCUST_WEB_PORT": "8091",
    }
    return env


def _locust_host(base_endpoint: str, endpoint_path: str) -> str:
    base = base_endpoint.rstrip("/")
    path = endpoint_path.strip("/")
    return f"{base}/{path}/"


def run_locust(
    *,
    test_file: str,
    endpoint_path: str,
    user_count: int,
    run_time: str | None,
    extra_env: dict[str, str] | None = None,
    base_env: dict[str, str] | None = None,
) -> None:
    env = dict(base_env or build_test_environment())
    env["ENDPOINT_PATH"] = endpoint_path
    if extra_env:
        env.update({k: v for k, v in extra_env.items() if v is not None})

    host = _locust_host(env["APIM_ENDPOINT"], endpoint_path)

    cmd: list[str] = [
        sys.executable,
        "-m",
        "locust",
        "-f",
        str(TOOLKIT_TEST_ROOT / test_file),
        "-H",
        host,
        "--autostart",
        "--autoquit",
        "0",
    ]
    if user_count >= 0:
        if run_time is None:
            raise RuntimeError(
                f"run_time must be provided when user_count is non-negative for {endpoint_path}"
            )
        cmd.extend(["--users", str(user_count), "--run-time", run_time])

    logger.info(
        "Running locust scenario '%s' (users=%s, run_time=%s)",
        endpoint_path,
        user_count,
        run_time,
    )
    subprocess.run(cmd, check=True, env={**os.environ, **env}, cwd=TOOLKIT_TEST_ROOT)


__all__ = ["build_test_environment", "run_locust"]
