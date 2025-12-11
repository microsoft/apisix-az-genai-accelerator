from __future__ import annotations

from pathlib import Path

from .build_and_push import build_cli


def main(argv: list[str] | None = None) -> int:
    return build_cli(
        argv=argv,
        description="Build and push the gateway-config-api image to Azure Container Registry.",
        target="gateway-config-api",
        dockerfile=Path("gateway_config_api/Dockerfile"),
        build_context=Path("."),
        include_paths=[
            Path("gateway_config_api"),
            Path("pyproject.toml"),
            Path("uv.lock"),
        ],
        tfvars_key="config_api_image",
    )


if __name__ == "__main__":
    raise SystemExit(main())
