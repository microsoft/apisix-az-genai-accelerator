from __future__ import annotations

import argparse
import logging

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    azure_context,
    configure_logging,
    ensure_tfvars,
    export_core_tf_env,
    load_bootstrap_state,
    resolve_paths,
    state_key,
    terraform_apply,
    terraform_init_remote,
)
from ._utils import ensure

logger = logging.getLogger(__name__)


def deploy_observability(
    env: str,
    *,
    ctx: AzureContext | None = None,
    bootstrap_state: BootstrapState | None = None,
) -> None:
    ensure(["az", "terraform"])
    context = ctx if ctx is not None else azure_context()
    paths = resolve_paths()

    bootstrap = (
        bootstrap_state
        if bootstrap_state is not None
        else load_bootstrap_state(env, paths, context)
    )

    tfvars_file = ensure_tfvars(
        paths.observability, env, context.subscription_id, context.tenant_id
    )

    export_core_tf_env(env, context)

    logger.info("==> 05-observability")
    terraform_init_remote(
        paths.observability,
        tenant_id=context.tenant_id,
        state_rg=bootstrap.resource_group,
        state_sa=bootstrap.storage_account,
        state_container=bootstrap.container,
        state_key=state_key(bootstrap.state_prefix, "05-observability"),
    )
    terraform_apply(paths.observability, tfvars_file)


def main(argv: list[str] | None = None) -> int:
    configure_logging()
    parser = argparse.ArgumentParser(
        prog="deploy-observability",
        description="Deploy the 05-observability terraform stack.",
    )
    parser.add_argument("env")
    args = parser.parse_args(argv)

    deploy_observability(args.env)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
