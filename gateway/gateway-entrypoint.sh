#!/usr/bin/env sh
set -eu

SRC="${GATEWAY_SHARED_DIR:-/shared-configs/gateway}"
DST="/usr/local/apisix/conf"
SEED="/opt/apisix-seed/conf"

echo "=========================================="
echo "Gateway: copying rendered configs from ${SRC} → ${DST}"
echo "=========================================="

mkdir -p "${DST}"

# Ensure base config files exist when the conf dir is an EmptyDir volume
if [ -d "${SEED}" ]; then
  echo "Seeding conf directory from ${SEED} (base files only, no overwrite)"
  for seed_file in "${SEED}"/*; do
    base="$(basename "${seed_file}")"
    case "${base}" in
      config.yaml|apisix.yaml) continue ;;
    esac
    if [ -d "${seed_file}" ]; then
      cp -an --no-preserve=ownership "${seed_file}" "${DST}/" || true
    elif [ -f "${seed_file}" ]; then
      cp -n --no-preserve=ownership "${seed_file}" "${DST}/${base}" || true
    fi
  done
fi

copy_atomic() {
  src="$1"; dest="$2"
  if [ -f "$src" ]; then
    tmp="$(mktemp "${dest}.XXXXXX")"
    cp "$src" "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$dest"
    echo "Updated $(basename "$dest")"
  else
    echo "WARN: missing $src"
  fi
}

copy_atomic "${SRC}/config.yaml" "${DST}/config.yaml"
copy_atomic "${SRC}/apisix.yaml"  "${DST}/apisix.yaml"

# Background task: wait for APISIX to be responding (any status), then touch config
# This works around APISIX bug where workers don't detect pre-existing config files
# Reference: https://github.com/apache/apisix/issues/12662
# 
# Detection strategy: We check for worker_events.sock creation, which happens during
# worker initialization after the file watcher background timer is created.
# This is more reliable than parsing logs (which are sent to Docker's log driver
# and not accessible from within the container's background tasks).
(
  echo "Waiting for APISIX workers to initialize..."
  
  # Wait for worker_events.sock to appear (indicates workers are initialized)
  timeout 30 sh -c '
    while ! [ -S /usr/local/apisix/logs/worker_events.sock ]; do
      echo "Still waiting for worker_events.sock..."
      sleep 1
    done
  ' && WORKERS_READY=true || WORKERS_READY=false
  
  if [ "$WORKERS_READY" = "true" ]; then
    echo "Workers initialized, touching config to notify them..."
    touch "${DST}/apisix.yaml"
      
    # Poll health endpoint until workers reload config (typically 1-2 seconds)
    echo "Waiting for workers to reload configuration..."
    timeout 10 sh -c '
      while ! curl -fsS http://127.0.0.1:7085/status/ready >/dev/null 2>&1; do
        echo "Checking /status/ready..."
        sleep 1
      done
    ' && echo "SUCCESS: Gateway healthy after touch" || echo "WARN: Gateway still unhealthy after touch (this may be cosmetic - gateway is functional)"
  else
    echo "WARN: APISIX workers did not initialize within 30s"
  fi
) &

exec /docker-entrypoint.sh docker-start
