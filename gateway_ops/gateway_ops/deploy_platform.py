from __future__ import annotations

import argparse
import logging

from gateway_ops._utils import ensure

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    FoundationState,
    azure_context,
    configure_logging,
    ensure_tfvars,
    export_core_tf_env,
    foundation_state_from_outputs,
    load_bootstrap_state,
    resolve_paths,
    state_key,
    terraform_apply,
    terraform_init_remote,
    terraform_output,
)

logger = logging.getLogger(__name__)


def deploy_platform(
    env: str,
    *,
    ctx: AzureContext | None = None,
    bootstrap_state: BootstrapState | None = None,
) -> FoundationState:
    ensure(["az", "terraform"])
    context = ctx if ctx is not None else azure_context()
    paths = resolve_paths()
    bootstrap = (
        bootstrap_state
        if bootstrap_state is not None
        else load_bootstrap_state(env, paths, context)
    )

    tfvars_file = ensure_tfvars(
        paths.foundation, env, context.subscription_id, context.tenant_id
    )

    export_core_tf_env(env, context)

    logger.info("==> 10-platform")
    terraform_init_remote(
        paths.foundation,
        tenant_id=context.tenant_id,
        state_rg=bootstrap.resource_group,
        state_sa=bootstrap.storage_account,
        state_container=bootstrap.container,
        state_key=state_key(bootstrap.state_prefix, "10-platform"),
    )
    terraform_apply(paths.foundation, tfvars_file)

    outputs = terraform_output(paths.foundation)
    return foundation_state_from_outputs(outputs)


def main(argv: list[str] | None = None) -> int:
    configure_logging()
    parser = argparse.ArgumentParser(
        prog="deploy-platform",
        description="Deploy the 10-platform terraform stack.",
    )
    parser.add_argument("env")
    args = parser.parse_args(argv)

    deploy_platform(args.env)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
