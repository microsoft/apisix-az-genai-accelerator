#!/usr/bin/env sh
set -eu
umask 022

OUT="${SHARED_ROOT:-/shared-configs}"
# Always render into the shared volume; gateway-entrypoint copies into
# /usr/local/apisix/conf with the right ownership/permissions.
GATEWAY_CONF_OUT="${OUT}/gateway"

echo "=========================================="
echo "hydrenv: rendering into $OUT"
echo "=========================================="

# Enable Key Vault context for template rendering
# This provides Key Vault-related variables to templates

mkdir -p "$OUT/otel-collector" "$GATEWAY_CONF_OUT"

hydrenv \
  --render /templates/config/gateway/apisix.yaml.j2="$GATEWAY_CONF_OUT/apisix.yaml" \
  --render /templates/config/gateway/config.yaml.j2="$GATEWAY_CONF_OUT/config.yaml" \
  --render /templates/config/otel-collector/config.yaml.j2="$OUT/otel-collector/config.yaml" \
  --indexed '{"prefix":"AZURE_OPENAI_","required_keys":["ENDPOINT"],"optional_keys":["KEY","PRIORITY","WEIGHT","NAME"]}' \
  --sequential '{"prefix":"GATEWAY_CLIENT_","required_keys":["NAME","KEY"],"require_when_env":"GATEWAY_REQUIRE_AUTH"}' \
  --enable-key-vault \
  --verbose

if [ "${GATEWAY_E2E_TEST_MODE:-false}" = "true" ]; then
  # apisix-conf is an EmptyDir in E2E; make it writable by the apisix runtime user (uid 636).
  install -d -o 636 -g 636 -m 0755 /usr/local/apisix/conf
fi

echo "=========================================="
echo "✓ All configs rendered"
echo "=========================================="
