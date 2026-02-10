-- Boot hook: extend ai-proxy provider enums without forking schema files
local ok, schema = pcall(require, "apisix.plugins.ai-proxy.schema")
if not ok or type(schema) ~= "table" then
	return -- nothing to do (defensive)
end

local function add(enum_tbl, name)
	if type(enum_tbl) ~= "table" or name == nil then
		return
	end
	for _, v in ipairs(enum_tbl) do
		if v == name then
			return
		end
	end
	table.insert(enum_tbl, name)
end

-- single-provider plugin enum
local ai_proxy = schema.ai_proxy_schema
if ai_proxy and ai_proxy.properties and ai_proxy.properties.provider then
	add(ai_proxy.properties.provider.enum, "dynamic-azure-openai")
end

-- multi-provider instance enum
local multi = schema.ai_proxy_multi_schema
local inst = multi and multi.properties and multi.properties.instances
inst = inst and inst.items and inst.items.properties
local prov = inst and inst.provider
if prov then
	add(prov.enum, "dynamic-azure-openai")
end
