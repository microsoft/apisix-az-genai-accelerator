from __future__ import annotations

import argparse
import logging
from pathlib import Path

from gateway_ops._utils import ensure

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    azure_context,
    bootstrap_state_from_outputs,
    configure_logging,
    ensure_tfvars,
    export_core_tf_env,
    resolve_paths,
    terraform_apply,
    terraform_init_local,
    terraform_output,
)

logger = logging.getLogger(__name__)


def deploy_bootstrap(
    env: str, *, ctx: AzureContext | None = None, state_path: Path | None = None
) -> BootstrapState:
    ensure(["az", "terraform"])
    context = ctx if ctx is not None else azure_context()
    paths = resolve_paths()

    tfvars_file = ensure_tfvars(
        paths.bootstrap, env, context.subscription_id, context.tenant_id
    )

    export_core_tf_env(env, context)
    backend_state_path = (
        state_path
        if state_path is not None
        else paths.bootstrap / ".state" / env / "bootstrap.tfstate"
    )

    logger.info("==> 00-bootstrap")
    terraform_init_local(paths.bootstrap, backend_state_path)
    terraform_apply(paths.bootstrap, tfvars_file)

    outputs = terraform_output(paths.bootstrap)
    return bootstrap_state_from_outputs(outputs)


def main(argv: list[str] | None = None) -> int:
    configure_logging()
    parser = argparse.ArgumentParser(
        prog="deploy-bootstrap", description="Deploy the 00-bootstrap terraform stack."
    )
    parser.add_argument("env")
    args = parser.parse_args(argv)

    deploy_bootstrap(args.env)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
