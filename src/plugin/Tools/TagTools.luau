-- Tools/TagTools.luau
-- Tools for managing CollectionService tags

local CollectionService = game:GetService("CollectionService")

local Instances = require(script.Parent.Parent.Utils.Instances)
local History   = require(script.Parent.Parent.Utils.History)

local TagTools = {}

function TagTools.get_tags(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	return { tags = CollectionService:GetTags(inst) }
end

function TagTools.add_tag(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not args.tag then return nil, "Missing tag" end
	local recording = History.recordUndo("MCP: Add tag '" .. args.tag .. "' to " .. inst.Name)
	CollectionService:AddTag(inst, args.tag)
	History.finishUndo(recording, true)
	return { ok = true }
end

function TagTools.remove_tag(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not args.tag then return nil, "Missing tag" end
	local recording = History.recordUndo("MCP: Remove tag '" .. args.tag .. "' from " .. inst.Name)
	CollectionService:RemoveTag(inst, args.tag)
	History.finishUndo(recording, true)
	return { ok = true }
end

return TagTools
