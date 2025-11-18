# syntax=docker/dockerfile:1.7
FROM ghcr.io/astral-sh/uv:alpine3.22

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/root/.local/bin:/work/.venv/bin:$PATH"

WORKDIR /work

# Resolve locked deps for this package only
COPY pyproject.toml uv.lock ./
COPY gateway_config_api/pyproject.toml gateway_config_api/pyproject.toml
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-workspace --no-dev --package gateway_config_api

# Install the package after sources are present (picks up local code)
COPY gateway_config_api/ gateway_config_api/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --package gateway_config_api

EXPOSE 9000
ENTRYPOINT ["uv", "run", "gateway-config-api"]
