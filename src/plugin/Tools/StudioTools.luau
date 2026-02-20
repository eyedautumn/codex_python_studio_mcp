-- Tools/StudioTools.luau
-- Tools for play mode control, code execution, model insertion, and console output

local HttpService       = game:GetService("HttpService")
local InsertService     = game:GetService("InsertService")
local LogService        = game:GetService("LogService")
local StudioTestService = game:GetService("StudioTestService")

---------------------------------------------------------------------------
-- Insert model helpers (mirrors official Roblox MCP plugin approach)
---------------------------------------------------------------------------
local INSERT_MAX_SEARCH_DEPTH = 2048
local INSERT_MAX_DISTANCE_AWAY = 20

-- Raycast from the centre of the current camera viewport to find a good
-- world-space insertion point, falling back to a point directly in front.
local function getInsertPosition()
	local camera = workspace.CurrentCamera
	local vp = camera.ViewportSize / 2
	local unitRay = camera:ViewportPointToRay(vp.X, vp.Y, 0)
	local params = RaycastParams.new()
	params.BruteForceAllSlow = true
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * INSERT_MAX_SEARCH_DEPTH, params)
	if result then
		return result.Position
	else
		return camera.CFrame.Position + unitRay.Direction * INSERT_MAX_DISTANCE_AWAY
	end
end

-- Convert a query string to TitleCase with no spaces (e.g. "red car" → "RedCar")
local function toTitleCase(str)
	local result = str:gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end)
	return result:gsub("%s+", "")
end

-- Group a list of loaded objects into a single container.
-- Physical objects (PVInstances) → Model; multiple non-physical → Folder; single → as-is.
local function collapseIntoContainer(objects)
	if #objects == 0 then return nil end
	local hasPhysical = false
	for _, obj in ipairs(objects) do
		if obj:IsA("PVInstance") then hasPhysical = true; break end
	end
	if hasPhysical then
		local model = Instance.new("Model")
		for _, obj in ipairs(objects) do obj.Parent = model end
		return model
	end
	if #objects > 1 then
		local folder = Instance.new("Folder")
		for _, obj in ipairs(objects) do obj.Parent = folder end
		return folder
	end
	return objects[1]
end

-- Load an asset by numeric ID using game:GetObjects (more reliable than LoadAsset).
local function loadAssetById(assetId)
	local objects = game:GetObjects("rbxassetid://" .. tostring(assetId))
	return collapseIntoContainer(objects)
end

-- Search the Marketplace for free models matching a query; returns up to 6 asset IDs.
local function searchFreeModels(query)
	local ok, results = pcall(function()
		return InsertService:GetFreeModels(query, 0)
	end)
	if not ok or not results or not results[1] then return {} end
	local ids = {}
	for i, item in ipairs(results[1].Results or {}) do
		if i > 6 then break end
		table.insert(ids, item.AssetId)
	end
	return ids
end

-- Return a workspace-unique name based on a base name.
local function uniqueWorkspaceName(base)
	if not workspace:FindFirstChild(base) then return base end
	local i = 1
	while workspace:FindFirstChild(base .. i) do i += 1 end
	return base .. i
end

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
	-- Accepts either a direct asset ID or a search query string.
	-- query / assetId are both valid arg names.
	local query   = args.query or args.name or args.search
	local assetId = tonumber(args.assetId or args.asset_id or args.id or args.asset)

	if not query and not assetId then
		return nil, "Provide either 'query' (search string) or 'assetId' (numeric ID)"
	end

	local recording = History.recordUndo("MCP: Insert model")

	-- Resolve asset ID from search if not provided directly
	if not assetId then
		local ids = searchFreeModels(query)
		if #ids == 0 then
			History.finishUndo(recording, false)
			return nil, "No free models found for query: " .. tostring(query)
		end
		assetId = ids[1]
	end

	-- Load via game:GetObjects (handles both free models and private assets)
	local ok, instance = pcall(loadAssetById, assetId)
	if not ok or not instance then
		History.finishUndo(recording, false)
		return nil, "Failed to load asset " .. tostring(assetId) .. ": " .. tostring(instance)
	end

	-- Give it a clean workspace-unique name
	local baseName = query and toTitleCase(query) or ("Asset" .. tostring(assetId))
	instance.Name  = uniqueWorkspaceName(baseName)
	instance.Parent = workspace

	-- Place physical models at the camera look-at point
	if instance:IsA("Model") then
		local ok2 = pcall(function()
			instance:PivotTo(CFrame.new(getInsertPosition()))
		end)
		if not ok2 then
			-- PivotTo failed (e.g. no primary part yet) — silently ignore
		end
	end

	History.finishUndo(recording, true)

	local Instances = require(script.Parent.Parent.Utils.Instances)
	local info = Instances.serializeInstance(instance)
	info.assetId = assetId
	return info
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
