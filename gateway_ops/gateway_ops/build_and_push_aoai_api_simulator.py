from __future__ import annotations

import argparse
from pathlib import Path

from .build_and_push import build_and_push


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="build-and-push-aoai-api-simulator",
        description="Build and push the AoAI API simulator image to Azure Container Registry.",
    )
    parser.add_argument(
        "--local-docker", action="store_true", help="Build locally with docker"
    )
    args = parser.parse_args(argv)

    build_and_push(
        target="aoai-api-simulator",
        dockerfile=Path("aoai-api-simulator/src/aoai-api-simulator/Dockerfile"),
        build_context=Path("aoai-api-simulator/src/aoai-api-simulator"),
        include_paths=[Path("aoai-api-simulator")],
        tfvars_key="simulator_image",
        local_docker=args.local_docker,
        tfvars_path=None,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
