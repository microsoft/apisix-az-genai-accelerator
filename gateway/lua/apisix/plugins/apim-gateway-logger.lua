-- APIM-style gateway log forwarder for APISIX
-- Sends per-request records to Azure Monitor Logs via DCR/DCE (Logs Ingestion API)

local core = require("apisix.core")
local http = require("resty.http")
local batch_processor = require("apisix.utils.batch-processor")
local ngx = ngx
local os = os
local plugin_name = "apim-gateway-logger"

local default_msi_endpoint = "http://169.254.169.254/metadata/identity/oauth2/token"
local monitor_resource = "https://monitor.azure.com"

local schema = {
	type = "object",
	properties = {
		dcr_ingest_uri = { type = "string", minLength = 1 },
		stream = { type = "string", default = "Custom-APISIXGatewayLogs" },
		subscription_header = { type = "string", default = "ocp-apim-subscription-key" },
		api_id = { type = "string" },
		operation_name = { type = "string" },
		product_id = { type = "string" },
		gateway_id = { type = "string" },
		include_req_body = { type = "boolean", default = false },
		batch_max_size = { type = "integer", default = 100, minimum = 1 },
		batch_max_retry = { type = "integer", default = 2, minimum = 0 },
		batch_flush_interval = { type = "integer", default = 5, minimum = 1 },
		timeout_ms = { type = "integer", default = 3000, minimum = 500 },
		msi_client_id = { type = "string" },
		msi_endpoint = { type = "string" },
		msi_secret = { type = "string" },
	},
	required = { "dcr_ingest_uri" },
}

local _M = {
	version = 0.1,
	priority = 900,
	name = plugin_name,
	schema = schema,
}

local token_cache = {
	value = nil,
	exp = 0,
}

local function to_number(val)
	if not val then
		return nil
	end
	return tonumber(val)
end

local function to_ms(seconds_str)
	local num = tonumber(seconds_str)
	if not num then
		return nil
	end
	return math.floor(num * 1000)
end

local function now_rfc3339()
	return ngx.utctime()
end

local function resolve_msi_client_id(conf)
	if conf.msi_client_id and conf.msi_client_id ~= "" then
		return conf.msi_client_id
	end

	local env_client_id = os.getenv("APIM_GATEWAY_LOGS_MSI_CLIENT_ID")
		or os.getenv("AZURE_CLIENT_ID")
		or os.getenv("IDENTITY_CLIENT_ID")
		or os.getenv("MSI_CLIENT_ID")

	if env_client_id and env_client_id ~= "" then
		return env_client_id
	end

	return nil
end

local function resolve_msi_endpoint(conf)
	return conf.msi_endpoint or os.getenv("MSI_ENDPOINT") or os.getenv("IDENTITY_ENDPOINT") or default_msi_endpoint
end

local function build_msi_headers(conf)
	local secret = conf.msi_secret or os.getenv("MSI_SECRET") or os.getenv("IDENTITY_HEADER")

	local headers = { Metadata = "true" }

	if secret and secret ~= "" then
		headers["X-IDENTITY-HEADER"] = secret
		headers.secret = secret
	end

	return headers, secret ~= nil and secret ~= ""
end

local function fetch_token(conf)
	local now = ngx.time()
	if token_cache.value and token_cache.exp - now > 60 then
		return token_cache.value
	end

	local msi_endpoint = resolve_msi_endpoint(conf)
	local client_id = resolve_msi_client_id(conf)
	local headers, has_secret = build_msi_headers(conf)

	local httpc = http.new()
	httpc:set_timeout(conf.timeout_ms)

	local query = {
		resource = monitor_resource,
		["api-version"] = "2019-08-01",
	}
	if client_id and client_id ~= "" then
		query.client_id = client_id
	end

	local res, err = httpc:request_uri(msi_endpoint, {
		method = "GET",
		query = query,
		headers = headers,
		keepalive = false,
	})

	if not res then
		core.log.error(
			plugin_name .. ": MSI HTTP error",
			" endpoint=",
			msi_endpoint,
			" has_secret=",
			has_secret,
			" err=",
			err
		)
		return nil, "msi_http_error:" .. (err or "unknown")
	end
	if res.status < 200 or res.status > 299 then
		core.log.error(
			plugin_name .. ": MSI status ",
			res.status,
			" endpoint=",
			msi_endpoint,
			" has_secret=",
			has_secret
		)
		return nil, "msi_status:" .. res.status
	end

	local body, decode_err = core.json.decode(res.body)
	if not body then
		return nil, "decode_error:" .. (decode_err or "unknown")
	end

	local token = body.access_token
	local exp = tonumber(body.expires_on) or (now + 600)

	token_cache.value = token
	token_cache.exp = exp

	return token
end

local function build_record(conf, ctx)
	local req_headers = core.request.headers(ctx) or {}
	local resp_headers = ngx.resp.get_headers(0, true) or {}

	local record = {
		TimeGenerated = now_rfc3339(),
		OperationName = conf.operation_name or ctx.var.route_id,
		ApiId = conf.api_id,
		ProductId = conf.product_id,
		SubscriptionId = req_headers[conf.subscription_header] or req_headers[conf.subscription_header:lower()],
		BackendId = ctx.var.backend_identifier or ctx.var.upstream_host or ctx.var.upstream_addr,
		ResponseCode = ngx.status,
		BackendResponseCode = to_number(ctx.var.upstream_status),
		TotalTime = to_ms(ctx.var.request_time),
		BackendTime = to_ms(ctx.var.upstream_response_time),
		Method = ngx.req.get_method(),
		Url = ctx.var.request_uri,
		GatewayId = conf.gateway_id,
		CallerIpAddress = ctx.var.remote_addr,
		CorrelationId = core.request.header(ctx, "X-Request-ID"),
		RequestId = ctx.var.request_id,
		RequestHeaders = req_headers,
		ResponseHeaders = resp_headers,
	}

	if conf.include_req_body then
		record.RequestBody = core.request.get_body()
	end

	return record
end

local function send_batch(conf, entries)
	local token, terr = fetch_token(conf)
	if not token then
		return false, terr
	end

	local httpc = http.new()
	httpc:set_timeout(conf.timeout_ms)

	local payload = core.json.encode(entries)
	local res, err = httpc:request_uri(conf.dcr_ingest_uri, {
		method = "POST",
		body = payload,
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. token,
		},
		keepalive = true,
	})

	if not res then
		return false, "ingest_http_error:" .. (err or "unknown")
	end
	if res.status < 200 or res.status > 299 then
		return false, "ingest_status:" .. res.status
	end
	return true
end

local function create_processor(conf)
	local config = {
		name = plugin_name,
		retry_delay = 1,
		batch_max_size = conf.batch_max_size,
		inactive_timeout = conf.batch_flush_interval,
		buffer_duration = conf.batch_flush_interval,
		max_batch_size = conf.batch_max_size,
		max_retry_count = conf.batch_max_retry,
	}

	local func = function(entries)
		return send_batch(conf, entries)
	end

	return batch_processor:new(func, config)
end

function _M.check_schema(conf)
	return core.schema.check(schema, conf)
end

function _M.log(conf, ctx)
	if not conf._processor then
		conf._processor = create_processor(conf)
	end

	local record = build_record(conf, ctx)
	local ok, err = conf._processor:push(record)
	if not ok then
		core.log.error(plugin_name .. ": failed to enqueue log batch: ", err)
	end
end

return _M
