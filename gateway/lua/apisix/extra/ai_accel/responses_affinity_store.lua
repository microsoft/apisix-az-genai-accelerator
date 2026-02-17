local core = require("apisix.core")
local redis = require("resty.redis")

local _M = {}

local LOG_PREFIX = "[responses_affinity_store] "
local KEEPALIVE_TIMEOUT_MS = 60000
local KEEPALIVE_POOL_SIZE = 100

local function get_env(name, default_value)
	local value = os.getenv(name)
	if type(value) ~= "string" or value == "" then
		return default_value
	end
	return value
end

local function parse_positive_int(raw, default_value)
	local numeric = tonumber(raw)
	if not numeric or numeric <= 0 then
		return default_value
	end
	return math.floor(numeric)
end

local function load_config()
	local host = get_env("RESPONSES_AFFINITY_REDIS_HOST", nil)
	if not host then
		return nil, "responses_affinity_redis_host_missing"
	end

	local password = get_env("RESPONSES_AFFINITY_REDIS_PASSWORD", nil)
	if not password then
		return nil, "responses_affinity_redis_password_missing"
	end

	local config = {
		host = host,
		port = parse_positive_int(get_env("RESPONSES_AFFINITY_REDIS_PORT", "6379"), 6379),
		password = password,
		timeout_ms = parse_positive_int(get_env("RESPONSES_AFFINITY_REDIS_TIMEOUT_MS", "1000"), 1000),
		ttl_seconds = parse_positive_int(get_env("RESPONSES_AFFINITY_TTL_SECONDS", "86400"), 86400),
	}

	return config, nil
end

local function connect_client()
	local config, config_err = load_config()
	if config_err then
		return nil, nil, config_err
	end

	local client = redis:new()
	if not client then
		return nil, nil, "responses_affinity_redis_client_init_failed"
	end
	local timeout_ms = (config and config.timeout_ms) or 1000
	client:set_timeout(timeout_ms)

	local host = (config and config.host) or ""
	local port = (config and config.port) or 6379
	local ok, connect_err = client:connect(host, port)
	if not ok then
		core.log.error(LOG_PREFIX, "redis connect failed: ", connect_err)
		return nil, nil, "responses_affinity_redis_connect_failed"
	end

	local password = (config and config.password) or ""
	local auth_ok, auth_err = client:auth(password)
	if not auth_ok then
		core.log.error(LOG_PREFIX, "redis auth failed: ", auth_err)
		return nil, nil, "responses_affinity_redis_auth_failed"
	end

	local ttl_seconds = (config and config.ttl_seconds) or 86400
	return client, ttl_seconds, nil
end

local function release_client(client)
	if not client then
		return
	end

	local ok, keepalive_err = client:set_keepalive(KEEPALIVE_TIMEOUT_MS, KEEPALIVE_POOL_SIZE)
	if not ok then
		core.log.warn(LOG_PREFIX, "redis keepalive failed: ", keepalive_err)
		client:close()
	end
end

local function to_redis_key(key_item)
	if type(key_item) ~= "table" then
		return nil
	end

	local value = key_item.value
	if type(value) ~= "string" or value == "" then
		return nil
	end

	local kind = key_item.kind
	if kind == "response_id" then
		return "responses_affinity:response_id:" .. value
	end
	if kind == "conversation" then
		return "responses_affinity:conversation:" .. value
	end

	return nil
end

function _M.append_key(keys, kind, value)
	if type(keys) ~= "table" then
		return
	end
	if type(value) ~= "string" or value == "" then
		return
	end

	core.table.insert(keys, { kind = kind, value = value })
end

local function normalize_keys(keys)
	if type(keys) ~= "table" then
		return {}
	end

	local seen = {}
	local normalized = {}
	for _, key_item in ipairs(keys) do
		local redis_key = to_redis_key(key_item)
		if redis_key and not seen[redis_key] then
			seen[redis_key] = true
			core.table.insert(normalized, redis_key)
		end
	end
	return normalized
end

function _M.ensure_available()
	local client, _, connect_err = connect_client()
	if connect_err then
		return nil, connect_err
	end
	if not client then
		return nil, "responses_affinity_redis_client_unavailable"
	end

	local pong, ping_err = client:ping()
	release_client(client)

	if ping_err then
		core.log.error(LOG_PREFIX, "redis ping failed: ", ping_err)
		return nil, "responses_affinity_redis_ping_failed"
	end
	if pong ~= "PONG" then
		core.log.error(LOG_PREFIX, "unexpected redis ping response: ", tostring(pong))
		return nil, "responses_affinity_redis_ping_unexpected"
	end

	return true, nil
end

function _M.get_backend(keys)
	local redis_keys = normalize_keys(keys)
	if #redis_keys == 0 then
		return nil, nil
	end

	local client, _, connect_err = connect_client()
	if connect_err then
		return nil, connect_err
	end
	if not client then
		return nil, "responses_affinity_redis_client_unavailable"
	end

	for _, redis_key in ipairs(redis_keys) do
		local value, get_err = client:get(redis_key)
		if get_err then
			release_client(client)
			core.log.error(LOG_PREFIX, "redis get failed for ", redis_key, ": ", get_err)
			return nil, "responses_affinity_redis_get_failed"
		end
		if value and value ~= ngx.null and value ~= "" then
			release_client(client)
			return tostring(value), nil
		end
	end

	release_client(client)
	return nil, nil
end

function _M.set_backend(keys, backend_identifier)
	if type(backend_identifier) ~= "string" or backend_identifier == "" then
		return nil, "responses_affinity_backend_identifier_missing"
	end

	local redis_keys = normalize_keys(keys)
	if #redis_keys == 0 then
		return true, nil
	end

	local client, ttl_seconds, connect_err = connect_client()
	if connect_err then
		return nil, connect_err
	end
	if not client then
		return nil, "responses_affinity_redis_client_unavailable"
	end

	for _, redis_key in ipairs(redis_keys) do
		local ok, set_err = client:setex(redis_key, ttl_seconds, backend_identifier)
		if not ok then
			release_client(client)
			core.log.error(LOG_PREFIX, "redis setex failed for ", redis_key, ": ", set_err)
			return nil, "responses_affinity_redis_set_failed"
		end
	end

	release_client(client)
	return true, nil
end

return _M
