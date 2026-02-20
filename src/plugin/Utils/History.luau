-- Utils/History.luau
-- ChangeHistoryService recording helpers

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local History = {}

function History.recordUndo(name)
	return ChangeHistoryService:TryBeginRecording(name or "MCP Bridge Action")
end

function History.finishUndo(recording, success)
	if not recording then return end
	if success ~= false then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
	end
end

return History
