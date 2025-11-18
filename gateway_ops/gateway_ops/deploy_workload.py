from __future__ import annotations

import argparse
import json
import logging
import os
import re
import secrets
import subprocess
import sys
from pathlib import Path
from typing import Any

from gateway_ops._utils import ensure

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    FoundationState,
    OpenAIState,
    Paths,
    azure_context,
    configure_logging,
    ensure_tfvars,
    export_foundation_tf_env,
    load_bootstrap_state,
    load_foundation_state,
    read_env,
    resolve_paths,
    state_key,
    terraform_apply,
    terraform_init_remote,
    terraform_output,
)

logger = logging.getLogger(__name__)


def deploy_workload(
    env: str,
    *,
    ctx: AzureContext | None = None,
    bootstrap_state: BootstrapState | None = None,
    foundation_state: FoundationState | None = None,
    openai_state: OpenAIState | None = None,
    deploy_e2e: bool = False,
    no_image_build: bool = False,
    local_docker: bool = False,
    skip_openai: bool = False,
) -> None:
    ensure(["az", "terraform"])
    context = ctx if ctx is not None else azure_context()
    paths = resolve_paths()

    bootstrap = (
        bootstrap_state
        if bootstrap_state is not None
        else load_bootstrap_state(env, paths, context)
    )
    foundation = (
        foundation_state
        if foundation_state is not None
        else load_foundation_state(env, paths, context, bootstrap)
    )
    tfvars_file = ensure_tfvars(
        paths.workload, env, context.subscription_id, context.tenant_id
    )

    export_foundation_tf_env(env, context, bootstrap, foundation)

    openai_info = (
        openai_state
        if openai_state is not None
        else _detect_openai_state(
            env,
            context,
            bootstrap,
            foundation,
            paths,
            skip_openai=skip_openai,
        )
    )
    if openai_info.provisioned:
        os.environ["TF_VAR_use_provisioned_azure_openai"] = "true"
        if openai_info.state_blob_key:
            os.environ["TF_VAR_openai_state_blob_key"] = openai_info.state_blob_key
    else:
        os.environ["TF_VAR_use_provisioned_azure_openai"] = "false"
        os.environ.pop("TF_VAR_openai_state_blob_key", None)

    _sync_environment(env, foundation.key_vault_name, openai_info.provisioned)

    images = (
        _images_from_tfvars(tfvars_file, deploy_e2e)
        if no_image_build
        else _build_images(deploy_e2e, local_docker)
    )
    os.environ["TF_VAR_gateway_image"] = images["gateway"]
    os.environ["TF_VAR_hydrenv_image"] = images["hydrenv"]

    if deploy_e2e:
        _configure_e2e(images)
    else:
        os.environ["TF_VAR_gateway_e2e_test_mode"] = "false"

    export_foundation_tf_env(env, context, bootstrap, foundation)

    logger.info("==> 20-workload")
    terraform_init_remote(
        paths.workload,
        tenant_id=context.tenant_id,
        state_rg=bootstrap.resource_group,
        state_sa=bootstrap.storage_account,
        state_container=bootstrap.container,
        state_key=state_key(bootstrap.state_prefix, "20-workload"),
    )
    terraform_apply(paths.workload, tfvars_file)

    if deploy_e2e:
        _emit_toolkit_outputs(paths.workload, paths.toolkit_root)

    _print_gateway_keys(paths.config_dir / f"secrets.{env}.env")


def _detect_openai_state(
    env: str,
    ctx: AzureContext,
    bootstrap: BootstrapState,
    foundation: FoundationState,
    paths: Paths,
    *,
    skip_openai: bool,
) -> OpenAIState:
    if skip_openai or not paths.openai.exists():
        logger.info("Treating Azure OpenAI as disabled for workload deployment")
        return OpenAIState(provisioned=False, state_blob_key=None)

    export_foundation_tf_env(env, ctx, bootstrap, foundation)
    openai_state_key = state_key(bootstrap.state_prefix, "15-openai")
    try:
        terraform_init_remote(
            paths.openai,
            tenant_id=ctx.tenant_id,
            state_rg=bootstrap.resource_group,
            state_sa=bootstrap.storage_account,
            state_container=bootstrap.container,
            state_key=openai_state_key,
        )
        terraform_output(paths.openai)
    except subprocess.CalledProcessError:
        logger.info(
            "Azure OpenAI state not found; continuing without provisioned OpenAI"
        )
        return OpenAIState(provisioned=False, state_blob_key=None)

    return OpenAIState(provisioned=True, state_blob_key=openai_state_key)


def _sync_environment(env: str, key_vault: str, use_provisioned_openai: bool) -> None:
    sync_cmd = ["uv", "run", "sync-env", env]
    if key_vault != "":
        sync_cmd.extend(["--key-vault", key_vault])
    identifier = os.environ.get("TF_VAR_identifier")
    if identifier is not None and identifier != "":
        sync_cmd.extend(["--identifier", identifier])
    if use_provisioned_openai:
        sync_cmd.append("--use-provisioned-openai")
    subprocess.run(sync_cmd, text=True, check=True)


def _configure_e2e(images: dict[str, str]) -> None:
    os.environ["TF_VAR_gateway_e2e_test_mode"] = "true"

    config_api_secret = os.environ.get("CONFIG_API_SHARED_SECRET", "")
    if config_api_secret == "":
        config_api_secret = secrets.token_hex(16)
        logger.info("Generated CONFIG_API_SHARED_SECRET for test mode")
    os.environ["TF_VAR_config_api_shared_secret"] = config_api_secret
    os.environ["TF_VAR_config_api_image"] = images["gateway-config-api"]

    os.environ["TF_VAR_simulator_image"] = images["aoai-api-simulator"]
    simulator_api_key = os.environ.get("SIMULATOR_API_KEY", "")
    if simulator_api_key == "":
        simulator_api_key = secrets.token_hex(16)
        logger.info("Generated SIMULATOR_API_KEY for test mode: %s", simulator_api_key)
    os.environ["TF_VAR_simulator_api_key"] = simulator_api_key
    simulator_port = os.environ.get("SIMULATOR_PORT", "8000")
    os.environ["TF_VAR_simulator_port"] = simulator_port


def _build_images(deploy_e2e: bool, local_docker: bool) -> dict[str, str]:
    logger.info("Building container images (capturing image names for Terraform)")

    def run_build(command: list[str]) -> str:
        full_cmd = ["uv", "run", *command]
        if local_docker:
            full_cmd.append("--local-docker")
        result = subprocess.run(full_cmd, text=True, capture_output=True, check=True)
        if result.stdout:
            sys.stdout.write(result.stdout)
        if result.stderr:
            sys.stderr.write(result.stderr)
        image = _last_non_empty_line(result.stdout)
        if image == "":
            raise RuntimeError(f"Failed to parse image from build output: {full_cmd}")
        logger.info("Built %s", image)
        return image

    images: dict[str, str] = {
        "gateway": run_build(["build-and-push-gateway"]),
        "hydrenv": run_build(["build-and-push-hydrenv"]),
    }
    if deploy_e2e:
        images["gateway-config-api"] = run_build(["build-and-push-gateway-config-api"])
        images["aoai-api-simulator"] = run_build(["build-and-push-aoai-api-simulator"])
    return images


def _images_from_tfvars(tfvars_path: Path, deploy_e2e: bool) -> dict[str, str]:
    logger.info("Using pre-built images from tfvars (no image build requested)")
    if not tfvars_path.exists():
        raise FileNotFoundError(f"tfvars file not found: {tfvars_path}")

    content = tfvars_path.read_text()

    def read(key: str) -> str:
        match = re.search(
            rf'^{key}\s*=\s*"([^"]+)"', content, flags=re.MULTILINE | re.DOTALL
        )
        return match.group(1) if match else ""

    images = {
        "gateway": read("gateway_image"),
        "hydrenv": read("hydrenv_image"),
    }
    if deploy_e2e:
        images["gateway-config-api"] = read("config_api_image")
        images["aoai-api-simulator"] = read("simulator_image")

    missing = [name for name, value in images.items() if value == ""]
    if missing:
        raise ValueError(
            "Missing required image values in tfvars (needed because --no-image-build is set): "
            + ", ".join(missing)
        )
    return images


def _last_non_empty_line(output: str) -> str:
    for line in reversed(output.splitlines()):
        stripped = line.strip()
        if stripped != "":
            return stripped
    return ""


def _emit_toolkit_outputs(workload_dir: Path, toolkit_root: Path) -> None:
    outputs = terraform_output(workload_dir)

    def write_json(path: Path, data: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2))
        logger.info("Wrote %s", path)

    sims_out = toolkit_root / "simulators" / "output-simulators.json"
    sims_keys = toolkit_root / "simulators" / "generated-keys.json"
    apim_out = toolkit_root / "apim-genai" / "output.json"

    sim_key = outputs.get("simulator_api_key", {}).get("value")
    sim_ptu1 = outputs.get("simulator_ptu1_fqdn", {}).get("value")
    sim_payg1 = outputs.get("simulator_payg1_fqdn", {}).get("value")
    sim_payg2 = outputs.get("simulator_payg2_fqdn", {}).get("value")
    gateway_url = outputs.get("gateway_url", {}).get("value")

    has_sim_key = sim_key is not None and str(sim_key) != ""
    has_ptu1 = sim_ptu1 is not None and str(sim_ptu1) != ""
    has_payg1 = sim_payg1 is not None and str(sim_payg1) != ""
    has_payg2 = sim_payg2 is not None and str(sim_payg2) != ""
    if has_sim_key and has_ptu1 and has_payg1 and has_payg2:
        write_json(
            sims_out,
            {
                "payg1Fqdn": str(sim_payg1).replace("https://", ""),
                "payg2Fqdn": str(sim_payg2).replace("https://", ""),
                "ptu1Fqdn": str(sim_ptu1).replace("https://", ""),
                "resourceGroupName": outputs.get("resource_group_name", {}).get(
                    "value"
                ),
            },
        )
        write_json(sims_keys, {"simulatorApiKey": sim_key})

    if gateway_url is not None and str(gateway_url) != "":
        if apim_out.exists():
            apim_data = json.loads(apim_out.read_text())
        else:
            apim_data = {
                "apiManagementGatewayHostname": "",
                "apiManagementAzureOpenAIProductSubscriptionOneKey": "dummy-sub-1",
                "apiManagementAzureOpenAIProductSubscriptionTwoKey": "dummy-sub-2",
                "apiManagementAzureOpenAIProductSubscriptionThreeKey": "dummy-sub-3",
            }
        apim_data["apiManagementGatewayHostname"] = gateway_url
        write_json(apim_out, apim_data)


def _print_gateway_keys(path: Path) -> None:
    if not path.exists():
        logger.info("Gateway client keys: none specified in %s", path)
        return

    logger.info("Gateway client keys (from %s):", path)
    found = False
    for key, value in read_env(path):
        if key.startswith("GATEWAY_CLIENT_KEY_"):
            logger.info("%s=%s", key, value)
            found = True
    if not found:
        logger.info("  (none specified)")


def main(argv: list[str] | None = None) -> int:
    configure_logging()
    parser = argparse.ArgumentParser(
        prog="deploy-workload",
        description="Deploy the 20-workload terraform stack (and related images/config).",
    )
    parser.add_argument("env")
    parser.add_argument("--deploy-e2e", action="store_true")
    parser.add_argument("--no-image-build", action="store_true")
    parser.add_argument("--local-docker", action="store_true")
    parser.add_argument("--no-azure-openai", action="store_true")
    args = parser.parse_args(argv)

    deploy_workload(
        args.env,
        deploy_e2e=args.deploy_e2e,
        no_image_build=args.no_image_build,
        local_docker=args.local_docker,
        skip_openai=args.no_azure_openai,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
