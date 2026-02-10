-- Managed Identity (MSI) / Entra ID token helper.
--
-- Used by drivers that need to call Azure backends with Entra ID auth while
-- receiving only static config via ai-proxy(-multi) headers.

local core = require("apisix.core")
local http = require("resty.http")
local os = os

local _M = {}

local INTERNAL_AUTH_MODE_HDR = "x-apisix-ai-auth-mode"
local INTERNAL_TOKEN_RESOURCE_HDR = "x-apisix-ai-token-resource"
local INTERNAL_MSI_CLIENT_ID_HDR = "x-apisix-ai-msi-client-id"
local INTERNAL_MSI_ENDPOINT_HDR = "x-apisix-ai-msi-endpoint"
local INTERNAL_MSI_SECRET_HDR = "x-apisix-ai-msi-secret"

local DEFAULT_TOKEN_RESOURCE = "https://cognitiveservices.azure.com/"
local DEFAULT_MSI_ENDPOINT = "http://169.254.169.254/metadata/identity/oauth2/token"

local token_cache = {} -- cache_key -> { value = <token>, exp = <epoch_seconds> }

local function first_string(v)
	if type(v) == "table" then
		v = v[1]
	end
	if type(v) ~= "string" then
		return nil
	end
	return v
end

local function trim(v)
	local s = first_string(v)
	if not s then
		return nil
	end
	return (s:match("^%s*(.-)%s*$"))
end

local function strip_internal_auth_headers(headers)
	if not headers then
		return
	end
	headers[INTERNAL_AUTH_MODE_HDR] = nil
	headers[INTERNAL_TOKEN_RESOURCE_HDR] = nil
	headers[INTERNAL_MSI_CLIENT_ID_HDR] = nil
	headers[INTERNAL_MSI_ENDPOINT_HDR] = nil
	headers[INTERNAL_MSI_SECRET_HDR] = nil
end

local function resolve_msi_endpoint(headers)
	local from_hdr = trim(headers and headers[INTERNAL_MSI_ENDPOINT_HDR])
	if from_hdr and from_hdr ~= "" then
		return from_hdr
	end
	return os.getenv("MSI_ENDPOINT") or os.getenv("IDENTITY_ENDPOINT") or DEFAULT_MSI_ENDPOINT
end

local function resolve_msi_secret(headers)
	local from_hdr = trim(headers and headers[INTERNAL_MSI_SECRET_HDR])
	if from_hdr and from_hdr ~= "" then
		return from_hdr
	end
	return os.getenv("MSI_SECRET") or os.getenv("IDENTITY_HEADER")
end

local function resolve_msi_client_id(headers)
	local from_hdr = trim(headers and headers[INTERNAL_MSI_CLIENT_ID_HDR])
	if from_hdr and from_hdr ~= "" then
		return from_hdr
	end
	return os.getenv("AZURE_CLIENT_ID") or os.getenv("IDENTITY_CLIENT_ID") or os.getenv("MSI_CLIENT_ID")
end

local function resolve_token_resource(headers)
	local from_hdr = trim(headers and headers[INTERNAL_TOKEN_RESOURCE_HDR])
	if from_hdr and from_hdr ~= "" then
		return from_hdr
	end
	return os.getenv("AZURE_OPENAI_TOKEN_RESOURCE") or DEFAULT_TOKEN_RESOURCE
end

local function build_msi_headers(secret)
	local h = { Metadata = "true" }
	if secret and secret ~= "" then
		h["X-IDENTITY-HEADER"] = secret
		h.secret = secret
	end
	return h
end

local function parse_token_exp(body, now)
	-- IMDS/identity responses vary by platform:
	-- - expires_on: epoch seconds (string)
	-- - expires_in: seconds from now (string)
	local exp_on = body and tonumber(body.expires_on)
	if exp_on then
		return exp_on
	end
	local exp_in = body and tonumber(body.expires_in)
	if exp_in then
		return now + exp_in
	end
	return now + 600
end

local function fetch_entra_token(headers, timeout_ms)
	local resource = resolve_token_resource(headers)
	local msi_endpoint = resolve_msi_endpoint(headers)
	local client_id = resolve_msi_client_id(headers)
	local secret = resolve_msi_secret(headers)

	local cache_key = (msi_endpoint or "") .. "|" .. (client_id or "") .. "|" .. (resource or "")
	local now = ngx.time()
	local cached = token_cache[cache_key]
	if cached and cached.value and (cached.exp - now) > 60 then
		return cached.value, nil
	end

	local httpc = http.new()
	httpc:set_timeout(timeout_ms or 3000)

	local query = {
		resource = resource,
		["api-version"] = "2019-08-01",
	}
	if client_id and client_id ~= "" then
		query.client_id = client_id
	end

	local res, err = httpc:request_uri(msi_endpoint, {
		method = "GET",
		query = query,
		headers = build_msi_headers(secret),
		keepalive = false,
	})

	if not res then
		core.log.error("ai_accel.managed_identity: MSI token HTTP error", " endpoint=", msi_endpoint, " err=", err)
		return nil, "msi_http_error:" .. (err or "unknown")
	end
	if res.status < 200 or res.status > 299 then
		core.log.error("ai_accel.managed_identity: MSI token status ", res.status, " endpoint=", msi_endpoint)
		return nil, "msi_status:" .. tostring(res.status)
	end

	local body, derr = core.json.decode(res.body)
	if not body then
		core.log.error("ai_accel.managed_identity: MSI token decode error: ", derr)
		return nil, "msi_decode_error:" .. (derr or "unknown")
	end

	local token = body.access_token
	if type(token) ~= "string" or token == "" then
		return nil, "msi_missing_access_token"
	end

	token_cache[cache_key] = {
		value = token,
		exp = parse_token_exp(body, now),
	}
	return token, nil
end

function _M.apply_upstream_auth(headers, conf)
	local mode = trim(headers and headers[INTERNAL_AUTH_MODE_HDR])
	if not mode or mode == "" then
		strip_internal_auth_headers(headers)
		return nil
	end

	local mode_l = string.lower(mode)
	if mode_l == "api-key" or mode_l == "apikey" then
		strip_internal_auth_headers(headers)
		return nil
	end

	if mode_l ~= "entra" and mode_l ~= "aad" and mode_l ~= "entra-id" and mode_l ~= "entra_id" then
		strip_internal_auth_headers(headers)
		core.log.warn("ai_accel.managed_identity: unknown upstream auth mode: ", mode)
		return nil
	end

	-- Entra: replace key-based auth with Bearer token.
	if headers then
		headers["api-key"] = nil
	end

	local token, terr = fetch_entra_token(headers, conf and conf.timeout)
	strip_internal_auth_headers(headers)
	if not token then
		return "entra_token_error:" .. (terr or "unknown")
	end
	headers["Authorization"] = "Bearer " .. token
	return nil
end

return _M
