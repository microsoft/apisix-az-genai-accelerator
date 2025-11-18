from __future__ import annotations

import argparse
from pathlib import Path

from .build_and_push import build_and_push


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="build-and-push-gateway",
        description="Build and push the APISIX gateway image to Azure Container Registry.",
    )
    parser.add_argument(
        "--local-docker", action="store_true", help="Build locally with docker"
    )
    args = parser.parse_args(argv)

    build_and_push(
        target="gateway",
        dockerfile=Path("gateway/Dockerfile"),
        build_context=Path("."),
        include_paths=[Path("gateway")],
        tfvars_key="gateway_image",
        local_docker=args.local_docker,
        tfvars_path=None,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
