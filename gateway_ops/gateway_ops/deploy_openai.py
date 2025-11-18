from __future__ import annotations

import argparse
import logging
import os

from gateway_ops._utils import ensure

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    FoundationState,
    OpenAIState,
    azure_context,
    configure_logging,
    ensure_tfvars,
    export_foundation_tf_env,
    load_bootstrap_state,
    load_foundation_state,
    resolve_paths,
    state_key,
    terraform_apply,
    terraform_init_remote,
)

logger = logging.getLogger(__name__)


def deploy_openai(
    env: str,
    *,
    ctx: AzureContext | None = None,
    bootstrap_state: BootstrapState | None = None,
    foundation_state: FoundationState | None = None,
    skip: bool = False,
) -> OpenAIState:
    ensure(["az", "terraform"])
    context = ctx if ctx is not None else azure_context()
    paths = resolve_paths()

    if skip:
        logger.info("Skipping 15-openai (flagged to skip)")
        os.environ["TF_VAR_use_provisioned_azure_openai"] = "false"
        return OpenAIState(provisioned=False, state_blob_key=None)

    if not paths.openai.exists():
        logger.info("15-openai stack missing; skipping")
        os.environ["TF_VAR_use_provisioned_azure_openai"] = "false"
        return OpenAIState(provisioned=False, state_blob_key=None)

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
        paths.openai, env, context.subscription_id, context.tenant_id
    )
    export_foundation_tf_env(env, context, bootstrap, foundation)

    logger.info("==> 15-openai")
    openai_state_key = state_key(bootstrap.state_prefix, "15-openai")
    terraform_init_remote(
        paths.openai,
        tenant_id=context.tenant_id,
        state_rg=bootstrap.resource_group,
        state_sa=bootstrap.storage_account,
        state_container=bootstrap.container,
        state_key=openai_state_key,
    )
    terraform_apply(paths.openai, tfvars_file)

    os.environ["TF_VAR_use_provisioned_azure_openai"] = "true"
    os.environ["TF_VAR_openai_state_blob_key"] = openai_state_key
    return OpenAIState(provisioned=True, state_blob_key=openai_state_key)


def main(argv: list[str] | None = None) -> int:
    configure_logging()
    parser = argparse.ArgumentParser(
        prog="deploy-openai", description="Deploy the 15-openai terraform stack."
    )
    parser.add_argument("env")
    parser.add_argument("--no-azure-openai", action="store_true")
    args = parser.parse_args(argv)

    deploy_openai(args.env, skip=args.no_azure_openai)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
