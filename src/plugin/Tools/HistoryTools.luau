-- Tools/HistoryTools.luau
-- Tools for Studio undo/redo and waypoint management

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local History = require(script.Parent.Parent.Utils.History)

local HistoryTools = {}

function HistoryTools.undo()
	local ok, err = pcall(function() ChangeHistoryService:Undo() end)
	if not ok then return nil, "Undo failed: " .. tostring(err) end
	return { ok = true }
end

function HistoryTools.redo()
	local ok, err = pcall(function() ChangeHistoryService:Redo() end)
	if not ok then return nil, "Redo failed: " .. tostring(err) end
	return { ok = true }
end

function HistoryTools.set_waypoint(args)
	local name = args.name or "MCP Waypoint"
	local recording = History.recordUndo(name)
	if recording then History.finishUndo(recording, true) end
	return { ok = true, name = name }
end

return HistoryTools
