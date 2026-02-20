-- Utils/Instances.luau
-- Instance ID map, resolution, and serialization helpers

local Types = require(script.Parent.Types)

local Instances = {}

local idMap = {}

function Instances.registerInstance(inst)
	if not inst then return nil end
	local ok, debugId = pcall(function() return inst:GetDebugId(0) end)
	if ok and debugId then
		idMap[debugId] = inst
		return debugId
	end
	return nil
end

function Instances.resolveById(id)
	local inst = id and idMap[id] or nil
	if inst then
		local ok = pcall(function() return inst.Parent end)
		if not ok then
			idMap[id] = nil
			return nil
		end
	end
	return inst
end

function Instances.resolveByPathArray(pathArray)
	local current = game
	for _, name in ipairs(pathArray) do
		if name == "game" then
			current = game
		elseif name == "workspace" or name == "Workspace" then
			current = workspace
		else
			if current == game then
				local ok, svc = pcall(function() return game:GetService(name) end)
				if ok and svc then
					current = svc
				else
					current = current:FindFirstChild(name)
				end
			else
				current = current:FindFirstChild(name)
			end
		end
		if not current then return nil end
	end
	return current
end

function Instances.resolveByPath(path)
	if not path or path == "" then return nil end
	if path == "game" then return game end
	path = path:gsub("^game%.", "")
	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	return Instances.resolveByPathArray(parts)
end

function Instances.resolveInstance(args)
	if args.id then
		local inst = Instances.resolveById(args.id)
		if inst then return inst end
	end
	if args.pathArray then
		local inst = Instances.resolveByPathArray(args.pathArray)
		if inst then return inst end
	end
	if args.path then return Instances.resolveByPath(args.path) end
	return nil
end

function Instances.serializeInstance(inst)
	if not inst then return nil end
	local id = Instances.registerInstance(inst)
	local parent = inst.Parent
	local parentId = parent and Instances.registerInstance(parent) or nil
	return {
		id        = id,
		name      = inst.Name,
		className = inst.ClassName,
		fullName  = inst:GetFullName(),
		parentId  = parentId,
	}
end

function Instances.serializeInstances(list)
	local out = {}
	for _, inst in ipairs(list) do
		local info = Instances.serializeInstance(inst)
		if info then table.insert(out, info) end
	end
	return out
end

return Instances
