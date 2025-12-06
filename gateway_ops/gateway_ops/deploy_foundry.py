from __future__ import annotations

import argparse
import logging

from gateway_ops._utils import ensure

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    FoundationState,
    FoundryState,
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
    update_tfvars,
)
from ._openai_secrets import seed_openai_secrets

logger = logging.getLogger(__name__)


def deploy_foundry(
    env: str,
    *,
    ctx: AzureContext | None = None,
    bootstrap_state: BootstrapState | None = None,
    foundation_state: FoundationState | None = None,
    skip: bool = False,
) -> FoundryState:
    ensure(["az", "terraform"])
    context = ctx if ctx is not None else azure_context()
    paths = resolve_paths()

    if skip:
        logger.info("Skipping 15-foundry (flagged to skip)")
        return FoundryState(provisioned=False, state_blob_key=None)

    if not paths.foundry.exists():
        logger.info("15-foundry stack missing; skipping")
        return FoundryState(provisioned=False, state_blob_key=None)

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
        paths.foundry, env, context.subscription_id, context.tenant_id
    )
    update_tfvars(
        tfvars_file,
        {
            "remote_state_resource_group_name": bootstrap.resource_group,
            "remote_state_storage_account_name": bootstrap.storage_account,
            "remote_state_container_name": bootstrap.container,
            "foundation_state_blob_key": state_key(
                bootstrap.state_prefix, "10-platform"
            ),
        },
    )
    export_foundation_tf_env(env, context, bootstrap, foundation)

    logger.info("==> 15-foundry")
    openai_state_key = state_key(bootstrap.state_prefix, "15-foundry")
    terraform_init_remote(
        paths.foundry,
        tenant_id=context.tenant_id,
        state_rg=bootstrap.resource_group,
        state_sa=bootstrap.storage_account,
        state_container=bootstrap.container,
        state_key=openai_state_key,
    )
    terraform_apply(paths.foundry, tfvars_file)
    seed_summary = seed_openai_secrets(
        env,
        foundation.key_vault_name,
        allow_placeholders=False,
        ctx=context,
        bootstrap_state=bootstrap,
        paths=paths,
    )
    if len(seed_summary["seeded"]) == 0:
        logger.warning(
            "Foundry apply succeeded but no OpenAI secrets were seeded into %s; "
            "rerun deploy-workload after verifying terraform outputs",
            foundation.key_vault_name,
        )
    else:
        logger.info(
            "Seeded %d Azure OpenAI secrets into Key Vault %s",
            len(seed_summary["seeded"]),
            foundation.key_vault_name,
        )

    return FoundryState(provisioned=True, state_blob_key=openai_state_key)


def main(argv: list[str] | None = None) -> int:
    configure_logging()
    parser = argparse.ArgumentParser(
        prog="deploy-foundry",
        description="Deploy the 15-foundry terraform stack (Azure AI Foundry / OpenAI).",
    )
    parser.add_argument("env")
    parser.add_argument("--no-azure-openai", action="store_true")
    args = parser.parse_args(argv)

    deploy_foundry(args.env, skip=args.no_azure_openai)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
