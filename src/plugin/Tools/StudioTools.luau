-- Tools/StudioTools.luau
-- Tools for play mode control, code execution, model insertion, and console output

local HttpService       = game:GetService("HttpService")
local InsertService     = game:GetService("InsertService")
local LogService        = game:GetService("LogService")
local StudioTestService = game:GetService("StudioTestService")

local History = require(script.Parent.Parent.Utils.History)

local StudioTools = {}

---------------------------------------------------------------------------
-- Console log buffer
---------------------------------------------------------------------------
local CONSOLE_LOG_LIMIT = 400
local consoleLogs = {}

LogService.MessageOut:Connect(function(message, messageType)
	table.insert(consoleLogs, {
		text      = tostring(message or ""),
		type      = messageType and tostring(messageType.Name) or "Unknown",
		timestamp = time(),
	})
	if #consoleLogs > CONSOLE_LOG_LIMIT then table.remove(consoleLogs, 1) end
end)

---------------------------------------------------------------------------
-- Play mode state
---------------------------------------------------------------------------
local STUDIO_MODE = "stop"

local function currentRunMode() return STUDIO_MODE end
local function isStudioPlayMode(mode) return (mode or currentRunMode()) == "start_play" end

---------------------------------------------------------------------------
-- Code execution helpers
---------------------------------------------------------------------------
local function compileLuaChunk(code, chunkName)
	if load then return load(code, chunkName, "t", _G) end
	if loadstring then
		local chunk, err = loadstring(code)
		if chunk and setfenv then setfenv(chunk, _G) end
		return chunk, err
	end
	return nil, "load/loadstring is unavailable in this Studio build"
end

local function argumentToString(value)
	if value == nil then return "nil" end
	if typeof(value) == "table" then
		local ok, encoded = pcall(function() return HttpService:JSONEncode(value) end)
		if ok then return encoded end
	end
	return tostring(value)
end

local function toStringList(pack)
	local out = {}
	for i = 1, pack.n do out[i] = argumentToString(pack[i]) end
	return out
end

local function addToOutput(output, header, pack)
	return output .. header .. " " .. table.concat(toStringList(pack), "\t") .. "\n"
end

local function runChunkWithOutput(chunk)
	local output = ""
	local chunkEnv = (getfenv and getfenv(chunk)) or _G
	local backup   = { print = chunkEnv.print, warn = chunkEnv.warn, error = chunkEnv.error }

	local function wrapFn(header, original)
		return function(...)
			output = addToOutput(output, header, table.pack(...))
			if original then original(...) end
		end
	end

	local function run()
		chunkEnv.print = wrapFn("[OUTPUT]", backup.print or print)
		chunkEnv.warn  = wrapFn("[WARNING]", backup.warn or warn)
		chunkEnv.error = function(...)
			output = addToOutput(output, "[ERROR]", table.pack(...))
			local errFn = backup.error or error
			return errFn(...)
		end
		local results = table.pack(chunk())
		if results.n > 0 then
			output = addToOutput(output, "[RETURNED RESULTS]", table.pack(table.unpack(results, 1, results.n)))
		end
		return output
	end

	local ok, err = pcall(run)
	-- Restore env
	for key, value in pairs(backup) do chunkEnv[key] = value end
	if not ok then output = addToOutput(output, "[UNEXPECTED ERROR]", table.pack(err)) end
	return output
end

---------------------------------------------------------------------------
-- Public tool functions
---------------------------------------------------------------------------
function StudioTools.run_code(args)
	local code = args.code or args.script or args.source
	if not code or code == "" then return nil, "Missing code argument" end
	local chunk, err = compileLuaChunk(code, "MCP.run_code")
	if not chunk then return nil, err end
	return { result = runChunkWithOutput(chunk) }
end

function StudioTools.insert_model(args)
	local assetId = tonumber(args.assetId or args.asset_id or args.id or args.asset)
	if not assetId then return nil, "Missing assetId" end
	local recording = History.recordUndo("MCP: Insert asset " .. tostring(assetId))
	local ok, inserted = pcall(function() return InsertService:LoadAsset(assetId) end)
	if not ok then History.finishUndo(recording, false); return nil, tostring(inserted) end
	if not inserted then History.finishUndo(recording, false); return nil, "InsertService returned nothing" end
	inserted.Parent = workspace
	History.finishUndo(recording, true)

	local Instances = require(script.Parent.Parent.Utils.Instances)
	return Instances.serializeInstance(inserted)
end

function StudioTools.get_console_output(args)
	local since      = args.since or 0
	local maxEntries = math.min(args.maxEntries or CONSOLE_LOG_LIMIT, CONSOLE_LOG_LIMIT)
	local result = {}
	for i = #consoleLogs, 1, -1 do
		local entry = consoleLogs[i]
		if entry and entry.timestamp >= since then
			table.insert(result, 1, entry)
		end
		if #result >= maxEntries then break end
	end
	return {
		logs            = result,
		count           = #result,
		latestTimestamp = consoleLogs[#consoleLogs] and consoleLogs[#consoleLogs].timestamp,
	}
end

function StudioTools.start_stop_play(args)
	local requested = args.mode or args.action or args.state or args.command or args.name
	if not requested then return nil, "Unknown Studio mode (supported: start_play, stop, run_server)" end

	if requested == "start_play" then
		STUDIO_MODE = "start_play"
		task.spawn(function() StudioTestService:ExecutePlayModeAsync({}) end)
		return { mode = "start_play", message = "Started play" }
	elseif requested == "run_server" then
		STUDIO_MODE = "run_server"
		task.spawn(function() StudioTestService:ExecuteRunModeAsync({}) end)
		return { mode = "run_server", message = "Ran server" }
	elseif requested == "stop" then
		StudioTestService:EndTest({})
		STUDIO_MODE = "stop"
		return { mode = "stop", message = "Stopped play" }
	end

	return nil, "Unknown Studio mode (supported: start_play, stop, run_server)"
end

function StudioTools.get_studio_mode()
	local mode = currentRunMode()
	return { mode = mode or "Unknown", isPlay = isStudioPlayMode(mode) }
end

function StudioTools.run_script_in_play_mode(args)
	if not isStudioPlayMode() then return nil, "Studio must be in Play or Run mode" end
	local code = args.code or args.script or args.source
	if not code or code == "" then return nil, "Missing code argument" end
	local chunk, err = compileLuaChunk(code, "MCP.run_script_in_play_mode")
	if not chunk then return nil, err end
	return { result = runChunkWithOutput(chunk) }
end

return StudioTools
