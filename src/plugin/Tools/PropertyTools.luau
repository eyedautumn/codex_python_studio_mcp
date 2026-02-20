-- Tools/PropertyTools.luau
-- Tools for reading and writing properties and attributes

local ReflectionService = game:GetService("ReflectionService")

local Instances = require(script.Parent.Parent.Utils.Instances)
local Types     = require(script.Parent.Parent.Utils.Types)
local History   = require(script.Parent.Parent.Utils.History)

local PropertyTools = {}

function PropertyTools.get_properties(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local props = {}
	for _, prop in ipairs(args.properties or {}) do
		local ok, value = pcall(function() return inst[prop] end)
		if ok then
			props[prop] = Types.serializeValue(value)
		else
			props[prop] = { _type = "error", message = "Cannot read property" }
		end
	end
	return props
end

function PropertyTools.get_all_properties(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end

	local allCapabilities = SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems()))
	local filter = { Security = allCapabilities, ExcludeInherited = false, ExcludeDisplay = true }
	local reflected = ReflectionService:GetPropertiesOfClass(inst.ClassName, filter)
	if not reflected then return nil, "Unknown class: " .. inst.ClassName end

	local result, skipped = {}, {}
	for _, prop in ipairs(reflected) do
		local name = prop.Name
		local deprecated = prop.Display and prop.Display.DeprecationMessage and prop.Display.DeprecationMessage ~= ""
		if not deprecated then
			local ok, value = pcall(function() return inst[name] end)
			if ok then result[name] = Types.serializeValue(value) else table.insert(skipped, name) end
		end
	end

	return {
		className     = inst.ClassName,
		propertyCount = #result,
		properties    = result,
		skippedCount  = #skipped,
	}
end

function PropertyTools.set_properties(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local recording = History.recordUndo("MCP: Set properties on " .. inst.Name)
	local errors = {}
	for key, value in pairs(args.properties or {}) do
		local ok, err = pcall(function() inst[key] = Types.deserializeValue(value) end)
		if not ok then table.insert(errors, key .. ": " .. tostring(err)) end
	end
	History.finishUndo(recording, true)
	return #errors > 0 and { ok = true, warnings = errors } or { ok = true }
end

function PropertyTools.get_attributes(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local result = {}
	for k, v in pairs(inst:GetAttributes()) do
		result[k] = Types.serializeValue(v)
	end
	return result
end

function PropertyTools.set_attributes(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local recording = History.recordUndo("MCP: Set attributes on " .. inst.Name)
	for key, value in pairs(args.attributes or {}) do
		inst:SetAttribute(key, Types.deserializeValue(value))
	end
	History.finishUndo(recording, true)
	return { ok = true }
end

return PropertyTools
