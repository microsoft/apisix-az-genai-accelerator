-- Dynamic Azure OpenAI driver with transparent transport.
-- Success path: stream status/headers/body from the FINAL successful backend.
-- Error path (429/5xx): DO NOT proxy; return status only so ai-proxy-multi can retry
-- another instance within the same request (APISIX 3.14+).
--
-- Zero-defaulting policy:
-- - No default api-version, no default Content-Type, no default scheme/port.
-- - Pass through caller/config/endpoints as-is; backend enforces its own rules.
--
-- Parity policy:
-- - Always run plugin.lua_response_filter (SSE chunks and non-SSE body),
--   matching openai-base.lua behavior while keeping transparent transport.

local base   = require("apisix.plugins.ai-drivers.openai-base")
local core   = require("apisix.core")
local http   = require("resty.http")
local plugin = require("apisix.plugin")
local sse    = require("apisix.plugins.ai-drivers.sse")
local url    = require("socket.url")

local _M     = {}
local mt     = { __index = _M }

-- Register custom variables for backend error tracking in prometheus metrics
-- This allows $backend_error_status and $backend_identifier to be used in prometheus extra_labels
core.ctx.register_var("backend_error_status", function(ctx)
    return ctx.backend_error_status or ""
end)

core.ctx.register_var("backend_identifier", function(ctx)
    return ctx.backend_identifier or ""
end)

-- ===== Request header filtering (proxy-safe) =====

local HOP_BY_HOP_REQ = {
    ["connection"] = true,
    ["keep-alive"] = true,
    ["proxy-authenticate"] = true,
    ["proxy-authorization"] = true,
    ["te"] = true,
    ["trailer"] = true,
    ["transfer-encoding"] = true,
    ["upgrade"] = true,
}

local BLOCKED_REQ    = {
    ["host"] = true,
    ["content-length"] = true,
    ["x-forwarded-for"] = true,
    ["x-real-ip"] = true,
    ["x-forwarded-proto"] = true,
    ["x-forwarded-host"] = true,
}

local function should_forward_req_header(name)
    if not name then return false end
    local n = string.lower(name)
    return not (HOP_BY_HOP_REQ[n] or BLOCKED_REQ[n])
end

local function collect_user_headers(ctx)
    local h = (core.request.headers and core.request.headers(ctx)) or ngx.req.get_headers() or {}
    local out = {}
    for k, v in pairs(h) do
        if should_forward_req_header(k) then
            out[k] = v
        end
    end
    return out
end

-- ===== Response header filtering (transparent but protocol-safe) =====

local HOP_BY_HOP_RES = {
    ["connection"] = true,
    ["keep-alive"] = true,
    ["proxy-authenticate"] = true,
    ["proxy-authorization"] = true,
    ["te"] = true,
    ["trailer"] = true,
    ["transfer-encoding"] = true,
    ["upgrade"] = true,
    ["content-length"] = true,
}

local function sanitize_and_apply_resp_headers(res_headers)
    if not res_headers then return end
    for k, v in pairs(res_headers) do
        local lk = string.lower(k)
        if not HOP_BY_HOP_RES[lk] then
            ngx.header[k] = v
        end
    end
end

-- ===== Utilities =====

local function shallow_copy(t)
    if type(t) ~= "table" then return {} end
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local function method_allows_body(method)
    if not method then
        return false
    end
    local upper = string.upper(method)
    return upper == "POST" or upper == "PUT" or upper == "PATCH"
end

local function classify_request(path)
    if type(path) ~= "string" then
        return nil
    end

    if string.find(path, "/chat/completions", 1, true) then
        return "ai_chat"
    end

    if string.find(path, "/embeddings", 1, true) then
        return "ai_embeddings"
    end

    if string.find(path, "/responses", 1, true) then
        return "ai_responses"
    end

    return nil
end

local function normalize_endpoint(ep)
    local parsed = url.parse(ep or "")
    if not parsed or not parsed.host or not parsed.scheme then
        return nil, "override.endpoint must include scheme and host (e.g. https://<resource>.openai.azure.com)"
    end
    local base_s = parsed.scheme .. "://" .. parsed.host .. (parsed.port and (":" .. parsed.port) or "")
    return base_s, parsed
end

local function handle_error(err)
    if err and string.find(tostring(err), "timeout", 1, true) then
        return ngx.HTTP_GATEWAY_TIMEOUT
    end
    return ngx.HTTP_INTERNAL_SERVER_ERROR
end

-- Case-insensitive header lookup
local function hget(h, name)
    if not h then return nil end
    local v = h[name]
    if v ~= nil then return v end
    local lname = string.lower(name)
    for k, vv in pairs(h) do
        if string.lower(k) == lname then
            return vv
        end
    end
    return nil
end

local function apply_responses_usage(ctx, usage)
    if type(usage) ~= "table" then
        return
    end

    ctx.llm_raw_usage = usage
    ctx.ai_token_usage = ctx.ai_token_usage or {}

    local prompt_tokens = usage.input_tokens or ctx.ai_token_usage.prompt_tokens or 0
    local completion_tokens = usage.output_tokens or ctx.ai_token_usage.completion_tokens or 0
    local total_tokens = usage.total_tokens or (prompt_tokens + completion_tokens)
    local reasoning_tokens = 0
    if type(usage.output_tokens_details) == "table" then
        reasoning_tokens = usage.output_tokens_details.reasoning_tokens or 0
    end

    ctx.ai_token_usage.prompt_tokens = prompt_tokens
    ctx.ai_token_usage.completion_tokens = completion_tokens
    ctx.ai_token_usage.total_tokens = total_tokens
    ctx.ai_token_usage.reasoning_tokens = reasoning_tokens

    ctx.var.llm_prompt_tokens = prompt_tokens
    ctx.var.llm_completion_tokens = completion_tokens
end

local function extract_responses_text(output, accumulator)
    if type(output) ~= "table" then
        return accumulator or {}
    end

    local buffer = accumulator or {}
    for _, item in ipairs(output) do
        if type(item) == "table" and type(item.content) == "table" then
            for _, content in ipairs(item.content) do
                if type(content) == "table" then
                    local text = content.text
                    if type(text) == "string" and text ~= "" then
                        core.table.insert(buffer, text)
                    end
                end
            end
        end
    end
    return buffer
end

local function set_responses_text(ctx, pieces)
    if type(pieces) ~= "table" or #pieces == 0 then
        return
    end
    ctx.var.llm_response_text = table.concat(pieces, "")
end

local function handle_chat_stream(ctx, res, body_reader, conf, httpc, contents)
    -- Azure OpenAI chat SSE invariants (2023-05-15 GA onward):
    --   - Each chunk decodes to events containing choices[].delta.content
    --   - usage.{prompt_tokens, completion_tokens, total_tokens} may appear on the
    --     final message event. We only rely on those stable fields so older and
    --     newer api-version payloads continue to work.
    contents = contents or {}
    while true do
        local chunk, err = body_reader()
        ctx.var.apisix_upstream_response_time = math.floor((ngx.now() - ctx.llm_request_start_time) * 1000)

        if err then
            core.log.warn("failed to read response chunk: ", err)
            if conf.keepalive then
                local ok2, kerr = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
                if not ok2 then core.log.warn("failed to keepalive connection after SSE error: ", kerr) end
            end
            return handle_error(err)
        end

        if not chunk then
            if conf.keepalive then
                local ok2, kerr = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
                if not ok2 then core.log.warn("failed to keepalive connection: ", kerr) end
            end
            return
        end

        if ctx.var.llm_time_to_first_token == "0" then
            ctx.var.llm_time_to_first_token = math.floor((ngx.now() - ctx.llm_request_start_time) * 1000)
        end

        local events = sse.decode(chunk)
        ctx.llm_response_contents_in_chunk = {}
        for _, event in ipairs(events) do
            if event.type == "message" then
                local data, derr = core.json.decode(event.data)
                if not data then
                    core.log.warn("failed to decode SSE data: ", derr)
                    goto CONTINUE
                end

                if type(data.choices) == "table" and #data.choices > 0 then
                    for _, choice in ipairs(data.choices) do
                        if type(choice) == "table"
                            and type(choice.delta) == "table"
                            and type(choice.delta.content) == "string" then
                            core.table.insert(contents, choice.delta.content)
                            core.table.insert(ctx.llm_response_contents_in_chunk, choice.delta.content)
                        end
                    end
                end

                if type(data.usage) == "table" then
                    core.log.info("got token usage from ai service: ", core.json.delay_encode(data.usage))
                    ctx.llm_raw_usage             = data.usage
                    ctx.ai_token_usage            = {
                        prompt_tokens     = data.usage.prompt_tokens or 0,
                        completion_tokens = data.usage.completion_tokens or 0,
                        total_tokens      = data.usage.total_tokens or 0,
                    }
                    ctx.var.llm_prompt_tokens     = ctx.ai_token_usage.prompt_tokens
                    ctx.var.llm_completion_tokens = ctx.ai_token_usage.completion_tokens
                    ctx.var.llm_response_text     = table.concat(contents, "")
                end
            elseif event.type == "done" then
                ctx.var.llm_request_done = true
            end
            ::CONTINUE::
        end

        plugin.lua_response_filter(ctx, res.headers, chunk)
    end
end

local function handle_responses_stream(ctx, res, body_reader, conf, httpc)
    -- Responses SSE events (2025-03-01-preview onward) emit delta-style updates.
    -- We focus on response.output_text.delta and response.output_item.added for
    -- text aggregation, and response.completed / *.usage for stable token counts.
    local buffer = {}
    local last_usage
    local last_response

    while true do
        local chunk, err = body_reader()
        ctx.var.apisix_upstream_response_time = math.floor((ngx.now() - ctx.llm_request_start_time) * 1000)

        if err then
            core.log.warn("failed to read responses stream chunk: ", err)
            if conf.keepalive then
                local ok2, kerr = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
                if not ok2 then core.log.warn("failed to keepalive connection after responses SSE error: ", kerr) end
            end
            return handle_error(err)
        end

        if not chunk then
            if last_response and type(last_response.output_text) == "string" and last_response.output_text ~= "" then
                buffer = { last_response.output_text }
            elseif last_response and type(last_response.output) == "table" then
                buffer = extract_responses_text(last_response.output, {})
            end
            if last_usage then
                apply_responses_usage(ctx, last_usage)
            end
            set_responses_text(ctx, buffer)
            if conf.keepalive then
                local ok2, kerr = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
                if not ok2 then core.log.warn("failed to keepalive connection: ", kerr) end
            end
            return
        end

        if ctx.var.llm_time_to_first_token == "0" then
            ctx.var.llm_time_to_first_token = math.floor((ngx.now() - ctx.llm_request_start_time) * 1000)
        end

        local events = sse.decode(chunk)
        ctx.llm_response_contents_in_chunk = {}
        for _, event in ipairs(events) do
            local event_data, derr = core.json.decode(event.data)
            if not event_data then
                core.log.warn("failed to decode responses SSE data: ", derr)
                goto STREAM_CONTINUE
            end

            local event_type = event.type or event_data.type

            if event_type == "response.output_text.delta" then
                local delta = event_data.delta
                if type(delta) == "string" and delta ~= "" then
                    core.table.insert(buffer, delta)
                    core.table.insert(ctx.llm_response_contents_in_chunk, delta)
                    set_responses_text(ctx, buffer)
                end
            elseif event_type == "response.output_item.added" then
                if type(event_data.item) == "table" then
                    buffer = extract_responses_text({ event_data.item }, buffer)
                    set_responses_text(ctx, buffer)
                end
            elseif event_type == "response.completed" then
                local response_obj = event_data.response
                if type(response_obj) == "table" then
                    last_response = response_obj
                    if type(response_obj.usage) == "table" then
                        core.log.info("got responses usage from ai service: ", core.json.delay_encode(response_obj.usage))
                        last_usage = response_obj.usage
                        apply_responses_usage(ctx, response_obj.usage)
                    end
                    local combined = {}
                    if type(response_obj.output_text) == "string" and response_obj.output_text ~= "" then
                        core.table.insert(combined, response_obj.output_text)
                    end
                    if type(response_obj.output) == "table" then
                        combined = extract_responses_text(response_obj.output, combined)
                    end
                    if #combined > 0 then
                        buffer = combined
                        set_responses_text(ctx, buffer)
                    end
                    ctx.var.llm_request_done = true
                end
            elseif event_type == "response.failed" or event_type == "response.error" then
                core.log.error("responses stream reported error event: ", core.json.delay_encode(event_data))
                if type(event_data.response) == "table" and event_data.response.status then
                    ctx.backend_error_status = tostring(event_data.response.status)
                elseif type(event_data.error) == "table" and event_data.error.code then
                    ctx.backend_error_status = tostring(event_data.error.code)
                else
                    ctx.backend_error_status = tostring(res.status)
                end
            elseif event_type == "response.incomplete" then
                core.log.warn("responses stream incomplete: ", core.json.delay_encode(event_data))
            elseif type(event_data.usage) == "table" then
                core.log.info("got responses usage from ai service: ", core.json.delay_encode(event_data.usage))
                apply_responses_usage(ctx, event_data.usage)
            end

            ::STREAM_CONTINUE::
        end

        plugin.lua_response_filter(ctx, res.headers, chunk)
    end
end

local function handle_responses_json(ctx, headers, raw_res_body)
    -- Responses JSON schema supplies output_text, output[], and usage token totals.
    -- We keep processing minimal (text aggregation + token metrics) to remain
    -- compatible across preview versions and the forthcoming GA release.
    ctx.var.request_type = "ai_responses"

    local res_body, derr = core.json.decode(raw_res_body)
    if derr then
        core.log.warn("invalid responses body from ai service: ", raw_res_body, " err: ", derr)
        return
    end

    if type(res_body.status) == "string" and res_body.status ~= "in_progress" then
        ctx.var.llm_request_done = true
    end

    if type(res_body.usage) == "table" then
        core.log.info("got responses usage from ai service: ", core.json.delay_encode(res_body.usage))
        apply_responses_usage(ctx, res_body.usage)
    end

    local pieces = {}
    if type(res_body.output_text) == "string" and res_body.output_text ~= "" then
        core.table.insert(pieces, res_body.output_text)
    end
    if type(res_body.output) == "table" then
        pieces = extract_responses_text(res_body.output, pieces)
    end
    set_responses_text(ctx, pieces)
end

local function handle_chat_json(ctx, headers, raw_res_body)
    -- Chat completions JSON response (GA 2023-05-15+) always includes
    -- choices[].message.content and usage totals. Matching openai-base.lua, we log
    -- those fields and avoid touching optional structures (tool_calls, etc.).
    -- Embeddings reuse this handler: the schema shares the usage block, but the
    -- choices array is absent, so the logic gracefully skips response_text.
    local res_body, derr = core.json.decode(raw_res_body)
    if derr then
        core.log.warn("invalid response body from ai service: ", raw_res_body,
            " err: ", derr, ", it will cause token usage not available")
        return
    end

    core.log.info("got token usage from ai service: ", core.json.delay_encode(res_body.usage))
    ctx.ai_token_usage = {}
    if type(res_body.usage) == "table" then
        ctx.llm_raw_usage                    = res_body.usage
        ctx.ai_token_usage.prompt_tokens     = res_body.usage.prompt_tokens or 0
        ctx.ai_token_usage.completion_tokens = res_body.usage.completion_tokens or 0
        ctx.ai_token_usage.total_tokens      = res_body.usage.total_tokens or 0
    end
    ctx.var.llm_prompt_tokens     = ctx.ai_token_usage.prompt_tokens or 0
    ctx.var.llm_completion_tokens = ctx.ai_token_usage.completion_tokens or 0

    if type(res_body.choices) == "table" and #res_body.choices > 0 then
        local contents = {}
        for _, choice in ipairs(res_body.choices) do
            if type(choice) == "table"
                and type(choice.message) == "table"
                and type(choice.message.content) == "string" then
                core.table.insert(contents, choice.message.content)
            end
        end
        ctx.var.llm_response_text = table.concat(contents, " ")
    end
end

-- ===== Driver object =====

function _M.new(opts)
    local self = {
        host = opts and opts.host,
        port = opts and opts.port,
        path = opts and opts.path,
    }
    return setmetatable(self, mt)
end

-- Reuse APISIX upstream JSON/content-type validation & request body decode
_M.validate_request = base.validate_request

-- ===== Core request =====

function _M.request(self, ctx, conf, request_table, extra_opts)
    extra_opts = extra_opts or {}

    -- Initialize LLM request tracking (for TTFT and response time calculations)
    ctx.llm_request_start_time = ngx.now()
    ctx.var.llm_time_to_first_token = "0" -- Initialize to "0" string per APISIX convention
    ctx.backend_error_status = ""         -- Track backend errors before failover for observability
    ctx.backend_identifier = ""           -- Track which backend returned the error

    -- Hard requirement: endpoint must include scheme+host
    if not extra_opts.endpoint then
        core.log.error("Azure OpenAI: missing override.endpoint")
        return ngx.HTTP_BAD_REQUEST, core.json.encode({
            error = { message = "Azure OpenAI: set override.endpoint (e.g. https://<resource>.openai.azure.com)" }
        })
    end

    local endpoint_base, parsed_ep = normalize_endpoint(extra_opts.endpoint)
    if not endpoint_base then
        return ngx.HTTP_BAD_REQUEST, core.json.encode({ error = { message = parsed_ep } })
    end
    extra_opts.endpoint = endpoint_base

    -- Store backend identifier for observability (extract hostname from endpoint)
    if parsed_ep and parsed_ep.host then
        ctx.backend_identifier = parsed_ep.host
    end

    -- Transparent path & query
    local path = ctx.var.upstream_uri
        or ctx.upstream_uri
        or ngx.var.upstream_uri
        or ctx.var.uri
        or ""
    local in_query     = core.request.get_uri_args(ctx) or {}
    local query_params = shallow_copy(in_query)
    local request_kind = classify_request(path)

    if type(request_table) ~= "table" then
        request_table = {}
    end

    local method     = string.upper(ctx.var.request_method or "POST")
    local has_body   = method_allows_body(method)

    -- Headers: user (filtered) + configured (config wins). No defaults.
    local user_hdrs  = collect_user_headers(ctx)
    local configured = extra_opts.headers or {}
    local headers    = {}
    for k, v in pairs(user_hdrs) do headers[k] = v end
    for k, v in pairs(configured) do headers[k] = v end

    -- Apply model_options into the request body (plugin contract; pure merge)
    if has_body then
        local model_opts = shallow_copy(extra_opts.model_options)
        for opt, val in pairs(model_opts) do
            request_table[opt] = val
        end
    end

    -- Capture model for observability (metrics/logs)
    local model_name = request_table.model
    if model_name then
        ctx.var.request_llm_model = model_name
        ctx.var.llm_model = model_name
    end

    -- Optional parity alignment with base: allow removing model if requested
    if extra_opts.remove_model and has_body then
        request_table.model = nil
    end

    local req_json
    if has_body then
        local jerr
        req_json, jerr = core.json.encode(request_table)
        if not req_json then
            core.log.warn("failed to encode request body to json: ", jerr)
            return ngx.HTTP_INTERNAL_SERVER_ERROR
        end
        headers["Content-Type"] = headers["Content-Type"] or "application/json"
    end

    -- Connect & send
    local httpc, cerr = http.new()
    if not httpc then
        core.log.error("failed to create http client: ", cerr)
        return ngx.HTTP_INTERNAL_SERVER_ERROR
    end
    httpc:set_timeout(conf.timeout)

    local ok, conn_err = httpc:connect({
        scheme = parsed_ep.scheme,
        host = parsed_ep.host,
        port = parsed_ep.port or (parsed_ep.scheme == "https" and 443 or 80),
        ssl_verify = conf.ssl_verify,
        ssl_server_name = parsed_ep.host,
    })
    if not ok then
        core.log.warn("failed to connect to LLM server: ", conn_err)
        return handle_error(conn_err)
    end

    local params = {
        method     = method,
        path       = path,
        query      = query_params,
        headers    = headers,
        ssl_verify = conf.ssl_verify,
    }
    if has_body then
        params.body = req_json
    end

    local res, req_err = httpc:request(params)
    if not res then
        core.log.warn("failed to send request to LLM server: ", req_err)
        return handle_error(req_err)
    end

    local status = tonumber(res.status) or 0

    -- Track backend response status for observability (before failover)
    -- This captures what the backend actually returned, even if APISIX retries to another backend
    if status ~= 200 and status ~= 0 then
        ctx.backend_error_status = tostring(status)
    end

    -- Retry contract aligned with base driver: return status only for 429/5xx
    if status == 429 or (status >= 500 and status < 600) then
        local body, berr = res:read_body() -- keep error text if all retries fail
        if not body and berr then
            core.log.warn("failed to read non-2xx body: ", berr)
        end
        if conf.keepalive then
            local ok2, kerr = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
            if not ok2 then core.log.warn("failed to keepalive connection (non-2xx): ", kerr) end
        end
        return status, body
    end

    -- Success or non-retryable 4xx: manual streaming with response filter parity.
    -- 1) Status and transparent headers (sanitized)
    ngx.status = res.status
    sanitize_and_apply_resp_headers(res.headers)

    -- 2) Content-Type and SSE detection
    local content_type = hget(res.headers, "Content-Type")
    local is_sse = content_type and string.find(string.lower(content_type), "text/event-stream", 1, true)

    if is_sse then
        -- SSE streaming: read chunk-by-chunk, update metrics, invoke response filter (parity)
        ctx.var.request_type = "ai_stream"
        local body_reader = res.body_reader
        if not body_reader then
            core.log.warn("AI service sent no response body (SSE)")
            if conf.keepalive then
                local ok2, kerr = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
                if not ok2 then core.log.warn("failed to keepalive connection: ", kerr) end
            end
            return ngx.HTTP_INTERNAL_SERVER_ERROR
        end

        local stream_res
        if request_kind == "ai_responses" then
            stream_res = handle_responses_stream(ctx, res, body_reader, conf, httpc)
        else
            stream_res = handle_chat_stream(ctx, res, body_reader, conf, httpc, {})
        end
        return stream_res
    end

    -- Non-SSE: read entire body, update metrics/usage once, filter parity
    if request_kind then
        ctx.var.request_type = request_kind
    end
    local raw_res_body, rerr = res:read_body()
    if not raw_res_body then
        core.log.warn("failed to read response body: ", rerr)
        if conf.keepalive then
            local ok2, kerr = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
            if not ok2 then core.log.warn("failed to keepalive connection after non-SSE error: ", kerr) end
        end
        return handle_error(rerr)
    end

    -- Timing/metrics
    ctx.var.llm_time_to_first_token = math.floor((ngx.now() - ctx.llm_request_start_time) * 1000)
    ctx.var.apisix_upstream_response_time = ctx.var.llm_time_to_first_token

    if request_kind == "ai_responses" then
        handle_responses_json(ctx, res.headers, raw_res_body)
    else
        -- Token usage + response text extraction
        handle_chat_json(ctx, res.headers, raw_res_body)
    end

    -- Always invoke APISIX response filter (parity with base)
    plugin.lua_response_filter(ctx, res.headers, raw_res_body)

    if conf.keepalive then
        local ok2, kerr = httpc:set_keepalive(conf.keepalive_timeout, conf.keepalive_pool)
        if not ok2 then
            core.log.warn("failed to keepalive connection: ", kerr)
        end
    end

    -- Response already sent (status, headers, body) from the successful backend.
    return
end

return _M
