from __future__ import annotations

from pathlib import Path

from .build_and_push import build_cli


def main(argv: list[str] | None = None) -> int:
    return build_cli(
        argv=argv,
        description="Build and push the AoAI API simulator image to Azure Container Registry.",
        target="aoai-api-simulator",
        dockerfile=Path("aoai-api-simulator/src/aoai-api-simulator/Dockerfile"),
        build_context=Path("aoai-api-simulator/src/aoai-api-simulator"),
        include_paths=[Path("aoai-api-simulator")],
        tfvars_key="simulator_image",
    )


if __name__ == "__main__":
    raise SystemExit(main())
