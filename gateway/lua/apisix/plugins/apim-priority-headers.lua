-- APIM-style priority header adapter for test/E2E parity
-- Adds x-gw-priority and x-gw-remaining-tokens response headers without
-- mutating production paths.

local core = require("apisix.core")
local ngx = ngx

local plugin_name = "apim-priority-headers"

local schema = {
    type = "object",
    properties = {},
}

local _M = {
    version = 0.1,
    priority = -200,
    name = plugin_name,
    schema = schema,
}

local function sanitize_priority(header_value)
    if not header_value then
        return "high"
    end

    local trimmed = header_value:match("^%s*(.-)%s*$") or header_value
    local lowered = trimmed:lower()

    if lowered == "low" then
        return "low"
    end

    return "high"
end

local function first_matching_header(headers, candidates)
    for _, name in ipairs(candidates) do
        local direct = headers[name] or headers[name:lower()]
        if direct then
            if type(direct) == "table" then
                return direct[1]
            end
            return direct
        end
    end

    for key, value in pairs(headers) do
        local lower_key = key:lower()
        for _, name in ipairs(candidates) do
            local prefix = name:lower()
            if lower_key:sub(1, #prefix) == prefix then
                if type(value) == "table" then
                    return value[1]
                end
                return value
            end
        end
    end

    return nil
end

function _M:new(deps)
    local instance = {
        version = self.version,
        priority = self.priority,
        name = self.name,
        schema = self.schema,
        deps = deps or {},
    }
    return setmetatable(instance, { __index = _M })
end

local singleton

function _M:get_instance(deps)
    if not singleton then
        singleton = _M:new(deps)
    end
    return singleton
end

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.header_filter(conf, ctx)
    local priority_value = sanitize_priority(core.request.header(ctx, "x-priority"))
    local headers = ngx.resp.get_headers(0, true) or {}
    local remaining = first_matching_header(headers, {
        "X-AI-RateLimit-Remaining",
        "X-RateLimit-Remaining",
    })

    core.response.set_header("x-gw-priority", priority_value)
    core.response.set_header("x-gw-remaining-tokens", remaining or "0")
end

return _M
