from __future__ import annotations

from pathlib import Path

from .build_and_push import build_cli


def main(argv: list[str] | None = None) -> int:
    return build_cli(
        argv=argv,
        description="Build and push the APISIX gateway image to Azure Container Registry.",
        target="gateway",
        dockerfile=Path("gateway/Dockerfile"),
        build_context=Path("."),
        include_paths=[Path("gateway")],
        tfvars_key="gateway_image",
    )


if __name__ == "__main__":
    raise SystemExit(main())
