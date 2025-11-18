# syntax=docker/dockerfile:1.7
FROM apache/apisix:3.14.1-debian

# Work as root only for copying files
USER root

# Preserve the stock APISIX conf as a reusable seed. This is needed because
# e2e mode mounts an EmptyDir on /usr/local/apisix/conf.
RUN mkdir -p /opt/apisix-seed/conf \
    && cp -a /usr/local/apisix/conf/. /opt/apisix-seed/conf/

# Ensure curl is available for Docker healthchecks
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Lua hook + plugins (readable by runtime user)
# config.yaml expects:
#   extra_lua_path: "/usr/local/apisix/extra/?.lua"
#   lua_module_hook: "ai_accel.hook"
COPY --chown=apisix:apisix --chmod=755 gateway/lua/apisix/extra/    /usr/local/apisix/extra/
COPY --chown=apisix:apisix --chmod=755 gateway/lua/apisix/plugins/  /usr/local/apisix/extra/apisix/plugins/

# Startup script that copies rendered configs from /shared-configs then execs APISIX
COPY --chown=apisix:apisix --chmod=755 gateway/gateway-entrypoint.sh /usr/local/bin/gateway-entrypoint.sh

# Drop back to unprivileged user provided by the base image
USER apisix

# Optional (base exposes these already)
EXPOSE 9080 9443 9091

CMD ["gateway-entrypoint.sh"]
