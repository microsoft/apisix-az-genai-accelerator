from __future__ import annotations

import argparse
from pathlib import Path

from .build_and_push import build_and_push


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="build-and-push-gateway-config-api",
        description="Build and push the gateway-config-api image to Azure Container Registry.",
    )
    parser.add_argument(
        "--local-docker", action="store_true", help="Build locally with docker"
    )
    args = parser.parse_args(argv)

    build_and_push(
        target="gateway-config-api",
        dockerfile=Path("gateway_config_api/Dockerfile"),
        build_context=Path("."),
        include_paths=[
            Path("gateway_config_api"),
            Path("pyproject.toml"),
            Path("uv.lock"),
        ],
        tfvars_key="config_api_image",
        local_docker=args.local_docker,
        tfvars_path=None,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
