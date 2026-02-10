-- Shared Lua utilities for APISIX GenAI accelerator modules.
-- Keep this file small and dependency-free to avoid require cycles.

local _M = {}

function _M.shallow_copy(t)
	if type(t) ~= "table" then
		return {}
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	return c
end

function _M.first_non_empty_string(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "string" and v ~= "" then
			return v
		end
	end
	return ""
end

function _M.normalize_pending_chunks(pending_chunks)
	if pending_chunks == nil then
		return nil, 0, 0
	end
	if type(pending_chunks) == "string" then
		return { pending_chunks }, 1, 1
	end
	if type(pending_chunks) == "table" then
		return pending_chunks, 1, #pending_chunks
	end
	return nil, 0, 0
end

return _M
