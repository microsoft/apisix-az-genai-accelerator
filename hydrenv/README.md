````markdown
# hydrenv

Enterprise-grade Jinja2 template renderer driven by environment variables.

## Core Concept

`hydrenv` renders Jinja2 templates using environment variables as context. It supports custom grouping strategies for numbered environment variables.

## Installation

```bash
uv add hydrenv
```

Or in a workspace:

```toml
[tool.uv.sources]
hydrenv = { workspace = true }
```

## Basic Usage

```bash
hydrenv --render /path/to/config.yaml.j2=/output/config.yaml
```

This renders `/path/to/config.yaml.j2` to `/output/config.yaml` using all environment variables as context.

## Grouping Strategies

Group numbered environment variables into structured data for templates.

### Indexed Strategy

Collects groups by numbered suffix (gaps allowed). Use `--indexed` flag with JSON config.

```bash
--indexed '{
  "prefix": "AZURE_OPENAI_",
  "required_keys": ["ENDPOINT"],
  "optional_keys": ["KEY", "PRIORITY", "WEIGHT"]
}'
```

**Environment:**

```bash
AZURE_OPENAI_ENDPOINT_1=https://api-1.openai.azure.com
AZURE_OPENAI_KEY_1=secret1
AZURE_OPENAI_ENDPOINT_2=https://api-2.openai.azure.com
# Index 2 has no KEY - that's fine (optional)
```

**Result:** `azure_openai_backends = [{"endpoint": "...", "key": "secret1"}, {"endpoint": "...", "key": None}]`

### Sequential Strategy

Collects groups starting at index 0, stops at first missing required key. Use `--sequential` flag with JSON config.

```bash
--sequential '{
  "prefix": "GATEWAY_CLIENT_",
  "required_keys": ["NAME", "KEY"],
  "optional_keys": ["RATE_LIMIT"]
}'
```

**Environment:**

```bash
GATEWAY_CLIENT_NAME_0=web
GATEWAY_CLIENT_KEY_0=abc123
GATEWAY_CLIENT_RATE_LIMIT_0=100
GATEWAY_CLIENT_NAME_1=mobile
GATEWAY_CLIENT_KEY_1=def456
# Index 1 has no RATE_LIMIT - collected anyway (optional)
# Index 2 missing NAME - stops here
```

**Result:** `gateway_clients = [{"name": "web", "key": "abc123", "rate_limit": "100"}, {"name": "mobile", "key": "def456", "rate_limit": None}]`

## Options

| Flag                       | Description                                     | Example                                           |
| -------------------------- | ----------------------------------------------- | ------------------------------------------------- |
| `--render TEMPLATE=OUTPUT` | Render template to file                         | `--render /path/config.yaml.j2=/out/config.yaml`  |
| `--indexed JSON`           | Indexed grouping (gaps allowed). Repeatable.    | `--indexed '{"prefix":"AZURE_OPENAI_",...}'`      |
| `--sequential JSON`        | Sequential grouping (stops at gap). Repeatable. | `--sequential '{"prefix":"GATEWAY_CLIENT_",...}'` |
| `--dest-root DIR`          | Base directory for relative outputs             | `--dest-root /output`                             |
| `--mode OCTAL`             | File permissions (default: `0644`)              | `--mode 0600`                                     |
| `--verbose`, `-v`          | Enable debug logging                            | `-v`                                              |

## Docker Usage

The official way to use `hydrenv` in containers:

**Dockerfile:**

```dockerfile
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .
ENTRYPOINT ["uv", "run", "hydrenv"]
```

**Compose:**

```yaml
services:
  renderer:
    build: .
    environment:
      - AZURE_OPENAI_ENDPOINT_1=https://...
    volumes:
      - ./templates:/templates:ro
      - ./output:/output
    command:
      - --render
      - /templates/config.yaml.j2=/output/config.yaml
```

## Shell Script Wrapper

For complex setups, wrap `hydrenv` in a shell script:

```bash
#!/bin/bash
set -euo pipefail

OUT="${OUTPUT_DIR:-/output}"
TEMPLATES="${TEMPLATES_DIR:-/templates}"

hydrenv \
  --render "$TEMPLATES/gateway/config.yaml.j2=$OUT/gateway/config.yaml" \
  --render "$TEMPLATES/database/schema.sql.j2=$OUT/database/schema.sql" \
  --indexed '{"prefix":"AZURE_OPENAI_","required_keys":["ENDPOINT"],"optional_keys":["KEY","PRIORITY"]}' \
  --sequential '{"prefix":"DB_REPLICA_","required_keys":["HOST"],"optional_keys":["PORT"]}'
```

## Template Context

Templates receive:

- `env`: Raw environment dict (`os.environ`)
- All normalized env vars (lowercase keys, type-coerced values)
- Custom groups from `--group-strategy` (e.g., `azure_openai_backends`, `gateway_clients`)

**Example template:**

```jinja
{% for backend in azure_openai_backends %}
- endpoint: {{ backend.endpoint }}
  {% if backend.key %}
  key: {{ backend.key }}
  {% endif %}
{% endfor %}
```

## Best Practices

1. **Use absolute paths**: Explicit template paths avoid ambiguity
2. **Name groups clearly**: Use descriptive names like `azure_openai_backends` instead of `indexed`
3. **Fail fast**: Let missing required keys error early rather than defaulting to empty strings
4. **Shell wrappers**: Commit a `render.sh` for complex multi-strategy setups
5. **Test locally**: Run `hydrenv` directly before containerizing
````
