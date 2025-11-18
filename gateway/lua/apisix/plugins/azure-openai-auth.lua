--[[
Azure OpenAI Authentication Plugin

Purpose:
  Custom APISIX authentication plugin that supports both Azure OpenAI and OpenAI v1 SDK
  authentication methods transparently, allowing clients to use either header format
  without gateway configuration changes.

Supported Authentication Methods:
  1. Authorization: Bearer <key> (OpenAI v1 SDK - checked first)
     - Modern standard used by official OpenAI Python SDK
     - Example: Authorization: Bearer sk-proj-abc123...

  2. api-key: <key> (Azure OpenAI SDK - legacy fallback)
     - Traditional Azure OpenAI header format
     - Example: api-key: abc123def456...

Authentication Flow:
  1. Extract key from Authorization: Bearer header (if present)
  2. Fall back to api-key header (if Authorization not found)
  3. Validate extracted key against APISIX consumer credentials
  4. Optionally remove both auth headers before forwarding to upstream (hide_credentials)

Configuration:
  Route level:
    azure-openai-auth:
      hide_credentials: true    # Remove auth headers before upstream (default: false)

  Consumer level:
    consumers:
      - username: client-name
        plugins:
          azure-openai-auth:
            key: "your-gateway-api-key"

Design Decisions:
  - Priority order: Bearer auth checked first (newer standard, more common)
  - No configurable header names: hardcoded for Azure OpenAI compatibility
  - Pattern precompiled at module load for performance
  - Both headers removed when hide_credentials=true (prevents credential leakage)

Gateway Flow:
  Client -(api-key OR Bearer)-> Gateway -(validates)-> Gateway -(backend-key)-> Azure OpenAI

  Client auth keys ≠ Backend auth keys
  Gateway validates clients, then uses separate backend credentials for upstream requests
]] --

local core = require("apisix.core")
local consumer_mod = require("apisix.consumer")
local plugin_name = "azure-openai-auth"
local schema_def = require("apisix.schema_def")

-- Azure OpenAI authentication header constants
-- These can be easily modified to support different header names
local BEARER_AUTH_HEADER = "Authorization"
local BEARER_AUTH_SCHEME = "Bearer"
local API_KEY_HEADER = "api-key"
local APIM_KEY_HEADER = "ocp-apim-subscription-key"

-- Precompiled pattern for Bearer token extraction (compiled once at module load)
local BEARER_PATTERN = "^" .. BEARER_AUTH_SCHEME .. "%s+(.+)$"

local schema = {
    type = "object",
    properties = {
        hide_credentials = {
            type = "boolean",
            default = false,
            description = "Remove authentication headers before forwarding to upstream",
        },
        anonymous_consumer = schema_def.anonymous_consumer_schema,
    },
}

local consumer_schema = {
    type = "object",
    properties = {
        key = { type = "string" },
    },
    encrypt_fields = { "key" },
    required = { "key" },
}


local _M = {
    version = 0.1,
    priority = 2500,
    type = 'auth',
    name = plugin_name,
    schema = schema,
    consumer_schema = consumer_schema,
}


function _M.check_schema(conf, schema_type)
    if schema_type == core.schema.TYPE_CONSUMER then
        return core.schema.check(consumer_schema, conf)
    else
        return core.schema.check(schema, conf)
    end
end

local function extract_key(ctx, conf)
    -- Azure OpenAI supports two authentication headers:
    -- 1. Authorization: Bearer <key> (used by OpenAI v1 SDK - newer, check first)
    -- 2. api-key: <key> (used by Azure OpenAI SDK - legacy)

    local key, from_header

    -- Try Authorization: Bearer header first (newer standard)
    local auth_header = core.request.header(ctx, BEARER_AUTH_HEADER)
    if auth_header then
        -- Extract token from "Bearer <token>" format using precompiled pattern
        key = auth_header:match(BEARER_PATTERN)
        if key then
            from_header = BEARER_AUTH_HEADER
            core.log.debug("extracted key from ", BEARER_AUTH_HEADER, " header")
            return key, from_header
        end
    end

    -- Fall back to api-key header (legacy)
    key = core.request.header(ctx, API_KEY_HEADER)
    if key then
        from_header = API_KEY_HEADER
        core.log.debug("extracted key from ", API_KEY_HEADER, " header")
        return key, from_header
    end

    -- APIM compatibility header
    key = core.request.header(ctx, APIM_KEY_HEADER)
    if key then
        from_header = APIM_KEY_HEADER
        core.log.debug("extracted key from ", APIM_KEY_HEADER, " header")
    end

    return key, from_header
end


local function find_consumer(ctx, conf)
    local key, from_header = extract_key(ctx, conf)

    if not key then
        core.log.debug("authentication rejected: no API key found in request headers")
        return nil, nil, "Missing API key in request"
    end

    local consumer, consumer_conf, err = consumer_mod.find_consumer(plugin_name, "key", key)
    if not consumer then
        core.log.debug("authentication rejected: invalid API key")
        return nil, nil, "Invalid API key in request"
    end

    core.log.debug("authentication successful for consumer: ", consumer.username)

    if conf.hide_credentials then
        -- Remove both possible authentication headers
        core.request.set_header(ctx, API_KEY_HEADER, nil)
        core.request.set_header(ctx, BEARER_AUTH_HEADER, nil)
        core.request.set_header(ctx, APIM_KEY_HEADER, nil)
        core.log.debug("credentials hidden from upstream request")
    end

    return consumer, consumer_conf
end


function _M.rewrite(conf, ctx)
    core.log.debug("azure-openai-auth plugin executing in rewrite phase")

    local consumer, consumer_conf, err = find_consumer(ctx, conf)
    if not consumer then
        if not conf.anonymous_consumer then
            core.log.debug("rejecting request with 401: ", err)
            return 401, { message = err }
        end
        core.log.debug("attempting anonymous consumer fallback")
        consumer, consumer_conf, err = consumer_mod.get_anonymous_consumer(conf.anonymous_consumer)
        if not consumer then
            -- Error level: anonymous consumer misconfiguration (should not happen in production)
            core.log.error("anonymous consumer configuration error: ", err)
            return 401, { message = "Invalid user authorization" }
        end
        core.log.debug("anonymous consumer authentication successful")
    end
    consumer_mod.attach_consumer(ctx, consumer, consumer_conf)
end

return _M
