from __future__ import annotations

from pathlib import Path

from .build_and_push import build_cli


def main(argv: list[str] | None = None) -> int:
    return build_cli(
        argv=argv,
        description="Build and push the hydrenv image to Azure Container Registry.",
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
    )


if __name__ == "__main__":
    raise SystemExit(main())
