from __future__ import annotations

import argparse
from pathlib import Path

from .build_and_push import build_and_push


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="build-and-push-hydrenv",
        description="Build and push the hydrenv image to Azure Container Registry.",
    )
    parser.add_argument(
        "--local-docker", action="store_true", help="Build locally with docker"
    )
    args = parser.parse_args(argv)

    build_and_push(
        target="hydrenv",
        dockerfile=Path("hydrenv/Dockerfile"),
        build_context=Path("."),
        include_paths=[
            Path("hydrenv"),
            Path("pyproject.toml"),
            Path("uv.lock"),
            Path("templates/config"),
            Path("gateway/lua/apisix/extra"),
            Path("gateway/lua/apisix/plugins"),
        ],
        tfvars_key="hydrenv_image",
        local_docker=args.local_docker,
        tfvars_path=None,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
