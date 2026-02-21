-- Tools/DataModelTools.luau
-- Tools for reading and manipulating DataModel / place-level metadata.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local StarterGui        = game:GetService("StarterGui")
local StarterPlayer     = game:GetService("StarterPlayer")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")
local Teams             = game:GetService("Teams")
local Workspace         = workspace

local Types    = require(script.Parent.Parent.Utils.Types)
local History  = require(script.Parent.Parent.Utils.History)
local Instances = require(script.Parent.Parent.Utils.Instances)

local DataModelTools = {}

-- ---------------------------------------------------------------------------
-- get_place_info
-- Returns metadata about the current open place: PlaceId, GameId, name,
-- lighting properties, gravity, and a summary of top-level service child counts.
-- ---------------------------------------------------------------------------
function DataModelTools.get_place_info()
	local lightingProps = {}
	for _, propName in ipairs({
		"Ambient", "Brightness", "ColorShift_Bottom", "ColorShift_Top",
		"EnvironmentDiffuseScale", "EnvironmentSpecularScale",
		"ExposureCompensation", "FogColor", "FogEnd", "FogStart",
		"GeographicLatitude", "GlobalShadows", "OutdoorAmbient",
		"ShadowSoftness", "Technology", "TimeOfDay",
	}) do
		local ok, v = pcall(function() return Lighting[propName] end)
		if ok then lightingProps[propName] = Types.serializeValue(v) end
	end

	local serviceSummary = {}
	local serviceNames = {
		"Workspace", "ReplicatedStorage", "ReplicatedFirst",
		"ServerScriptService", "ServerStorage",
		"StarterGui", "StarterPlayer", "StarterPack",
		"Teams", "SoundService", "Lighting",
	}
	for _, name in ipairs(serviceNames) do
		local ok, svc = pcall(function() return game:GetService(name) end)
		if ok and svc then
			serviceSummary[name] = #svc:GetChildren()
		end
	end

	return {
		placeId    = game.PlaceId,
		gameId     = game.GameId,
		name       = game.Name,
		placeVersion = game.PlaceVersion,
		gravity    = workspace.Gravity,
		streamingEnabled = workspace.StreamingEnabled,
		lighting   = lightingProps,
		serviceChildCounts = serviceSummary,
	}
end

-- ---------------------------------------------------------------------------
-- set_lighting
-- Set one or more Lighting service properties. Undoable.
-- ---------------------------------------------------------------------------
function DataModelTools.set_lighting(args)
	local props = args.properties
	if not props then return nil, "Missing 'properties' map" end

	local recording = History.recordUndo("MCP: Set Lighting properties")
	local errors = {}

	for key, rawValue in pairs(props) do
		local ok, err = pcall(function()
			Lighting[key] = Types.deserializeValue(rawValue)
		end)
		if not ok then
			table.insert(errors, key .. ": " .. tostring(err))
		end
	end

	History.finishUndo(recording, true)
	return #errors > 0 and { ok = true, warnings = errors } or { ok = true }
end

-- ---------------------------------------------------------------------------
-- get_workspace_info
-- Returns key Workspace-level settings useful for AI-assisted level design.
-- ---------------------------------------------------------------------------
function DataModelTools.get_workspace_info()
	local props = {
		"Gravity", "StreamingEnabled", "StreamingMinRadius",
		"StreamingTargetRadius", "AirDensity", "FluidForces",
		"GlobalWindDirection", "GlobalWindSpeed",
	}
	local result = {}
	for _, p in ipairs(props) do
		local ok, v = pcall(function() return Workspace[p] end)
		if ok then result[p] = Types.serializeValue(v) end
	end
	result.currentCameraPosition = Types.serializeValue(
		Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame or CFrame.identity
	)
	return result
end

-- ---------------------------------------------------------------------------
-- get_team_list
-- Returns all teams in the Teams service with their colors and players.
-- ---------------------------------------------------------------------------
function DataModelTools.get_team_list()
	local teams = {}
	for _, team in ipairs(Teams:GetTeams()) do
		table.insert(teams, {
			name       = team.Name,
			teamColor  = Types.serializeValue(team.TeamColor),
			autoAssignable = team.AutoAssignable,
		})
	end
	return { teams = teams }
end

-- ---------------------------------------------------------------------------
-- get_lighting_effects
-- Returns all post-processing/lighting effects under the Lighting service.
-- ---------------------------------------------------------------------------
function DataModelTools.get_lighting_effects()
	local effects = {}
	for _, child in ipairs(Lighting:GetChildren()) do
		local info = Instances.serializeInstance(child)
		if info then
			-- Also read common effect properties
			local propsToRead = { "Enabled", "Intensity", "Size", "Threshold", "Speed", "Density", "Weight" }
			local props = {}
			for _, p in ipairs(propsToRead) do
				local ok, v = pcall(function() return child[p] end)
				if ok then props[p] = Types.serializeValue(v) end
			end
			info.properties = props
			table.insert(effects, info)
		end
	end
	return { effects = effects }
end

return DataModelTools
