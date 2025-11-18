# syntax=docker/dockerfile:1.7
FROM ghcr.io/astral-sh/uv:alpine3.22

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/root/.local/bin:/work/.venv/bin:$PATH"

WORKDIR /work

# Install hydrenv
COPY pyproject.toml uv.lock ./
COPY hydrenv/pyproject.toml hydrenv/pyproject.toml
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-workspace --no-dev --package hydrenv
COPY hydrenv/ hydrenv/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --package hydrenv

# Bake config templates into the image
COPY templates/config/ /templates/config/

# Bake Lua assets into the image (two subtrees)
# - extra/ (contains ai_accel/hook.lua, etc.)
# - apisix/plugins/* (azure-openai-auth.lua, ai-drivers/…)
COPY gateway/lua/apisix/extra/   /assets/lua/extra/
COPY gateway/lua/apisix/plugins/ /assets/lua/extra/apisix/plugins/

# Runner
COPY hydrenv/render-templates.sh /usr/local/bin/render-templates.sh
RUN chmod 755 /usr/local/bin/render-templates.sh

ENTRYPOINT ["/usr/local/bin/render-templates.sh"]