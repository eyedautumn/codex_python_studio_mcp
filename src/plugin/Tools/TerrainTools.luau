-- Tools/TerrainTools.luau
-- Tools for reading and writing Roblox Terrain (smooth terrain voxels + shape fills)

local History = require(script.Parent.Parent.Utils.History)

local TerrainTools = {}

local terrain = workspace:WaitForChild("Terrain")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Resolve a material string like "Grass" to an Enum.Material value.
local function resolveMaterial(name)
	if not name then return Enum.Material.Grass end
	local ok, mat = pcall(function() return Enum.Material[name] end)
	return (ok and mat) or Enum.Material.Grass
end

-- Convert an {x,y,z} table to Vector3.
local function toV3(t)
	if not t then return Vector3.zero end
	return Vector3.new(t.x or t[1] or 0, t.y or t[2] or 0, t.z or t[3] or 0)
end

-- Convert a {x,y,z} table to CFrame (position only, identity rotation).
local function toCF(t)
	return CFrame.new(toV3(t))
end

-- Serialize a 3D materials/occupancies table returned by ReadVoxels into
-- something JSON-friendly. We return a flat array of voxels only when the
-- region is small enough to avoid enormous payloads.
local VOXEL_LIMIT = 4096   -- max voxels before we summarise instead

local function summariseVoxels(materials, occupancies, resolution, region)
	local size    = region.Size
	local countX  = math.ceil(size.X / resolution)
	local countY  = math.ceil(size.Y / resolution)
	local countZ  = math.ceil(size.Z / resolution)
	local total   = countX * countY * countZ

	local result = {
		resolution  = resolution,
		voxelCount  = total,
		regionMin   = { x = region.Min.X, y = region.Min.Y, z = region.Min.Z },
		regionMax   = { x = region.Max.X, y = region.Max.Y, z = region.Max.Z },
		dimensions  = { x = countX, y = countY, z = countZ },
	}

	if total <= VOXEL_LIMIT then
		-- Flatten into array of {x,y,z,material,occupancy} for small regions.
		local voxels = {}
		for ix = 1, countX do
			for iy = 1, countY do
				for iz = 1, countZ do
					local mat = materials[ix][iy][iz]
					local occ = occupancies[ix][iy][iz]
					if mat ~= Enum.Material.Air or occ > 0 then
						table.insert(voxels, {
							ix = ix, iy = iy, iz = iz,
							material  = tostring(mat.Name),
							occupancy = math.floor(occ * 1000 + 0.5) / 1000,
						})
					end
				end
			end
		end
		result.voxels = voxels
		result.nonAirCount = #voxels
	else
		-- Only return material frequency summary for large regions.
		local freq = {}
		for ix = 1, countX do
			for iy = 1, countY do
				for iz = 1, countZ do
					local name = materials[ix][iy][iz].Name
					freq[name] = (freq[name] or 0) + 1
				end
			end
		end
		result.materialFrequency = freq
		result.note = "Region too large for full voxel dump (" .. total .. " voxels). Increase resolution or shrink region."
	end

	return result
end

-- ---------------------------------------------------------------------------
-- Public tools
-- ---------------------------------------------------------------------------

--- terrain_fill_block: fill a box-shaped region with terrain material. Undoable.
function TerrainTools.terrain_fill_block(args)
	local cframe   = args.cframe
	local size     = args.size
	local material = resolveMaterial(args.material)

	if not cframe or not size then
		return nil, "Required: cframe ({x,y,z} or full 12-component CFrame) and size ({x,y,z})"
	end

	local cf
	if type(cframe) == "table" and cframe.components and #cframe.components == 12 then
		cf = CFrame.new(table.unpack(cframe.components))
	else
		cf = toCF(cframe)
	end
	local sz = toV3(size)

	local recording = History.recordUndo("MCP: Terrain fill block")
	local ok, err = pcall(function() terrain:FillBlock(cf, sz, material) end)
	History.finishUndo(recording, ok)
	if not ok then return nil, "FillBlock failed: " .. tostring(err) end
	return { ok = true, material = material.Name, cframe = { x = cf.X, y = cf.Y, z = cf.Z }, size = { x = sz.X, y = sz.Y, z = sz.Z } }
end

--- terrain_fill_ball: fill a sphere of terrain. Undoable.
function TerrainTools.terrain_fill_ball(args)
	local center   = args.center
	local radius   = tonumber(args.radius)
	local material = resolveMaterial(args.material)

	if not center or not radius then
		return nil, "Required: center ({x,y,z}) and radius (number)"
	end

	local pos = toV3(center)
	local recording = History.recordUndo("MCP: Terrain fill ball")
	local ok, err = pcall(function() terrain:FillBall(pos, radius, material) end)
	History.finishUndo(recording, ok)
	if not ok then return nil, "FillBall failed: " .. tostring(err) end
	return { ok = true, material = material.Name, center = { x = pos.X, y = pos.Y, z = pos.Z }, radius = radius }
end

--- terrain_fill_cylinder: fill a cylinder of terrain. Undoable.
function TerrainTools.terrain_fill_cylinder(args)
	local cframe   = args.cframe
	local height   = tonumber(args.height)
	local radius   = tonumber(args.radius)
	local material = resolveMaterial(args.material)

	if not cframe or not height or not radius then
		return nil, "Required: cframe ({x,y,z}), height (number), radius (number)"
	end

	local cf
	if type(cframe) == "table" and cframe.components and #cframe.components == 12 then
		cf = CFrame.new(table.unpack(cframe.components))
	else
		cf = toCF(cframe)
	end

	local recording = History.recordUndo("MCP: Terrain fill cylinder")
	local ok, err = pcall(function() terrain:FillCylinder(cf, height, radius, material) end)
	History.finishUndo(recording, ok)
	if not ok then return nil, "FillCylinder failed: " .. tostring(err) end
	return { ok = true, material = material.Name, height = height, radius = radius }
end

--- terrain_replace_material: replace one terrain material with another inside a region. Undoable.
function TerrainTools.terrain_replace_material(args)
	local regionMin = args.regionMin
	local regionMax = args.regionMax
	local from      = resolveMaterial(args.from)
	local to        = resolveMaterial(args.to)
	local resolution = tonumber(args.resolution) or 4

	if not regionMin or not regionMax then
		return nil, "Required: regionMin ({x,y,z}) and regionMax ({x,y,z})"
	end

	local minV = toV3(regionMin)
	local maxV = toV3(regionMax)
	local region = Region3.new(minV, maxV)

	-- Snap resolution to a valid voxel resolution (must be >= 4 and a multiple of 4)
	resolution = math.max(4, math.floor(resolution / 4) * 4)

	local ok, materials, occupancies = pcall(function()
		return terrain:ReadVoxels(region, resolution)
	end)
	if not ok then return nil, "ReadVoxels failed: " .. tostring(materials) end

	local size = materials.Size
	local changed = 0

	for ix = 1, size.X do
		for iy = 1, size.Y do
			for iz = 1, size.Z do
				if materials[ix][iy][iz] == from then
					materials[ix][iy][iz] = to
					changed = changed + 1
				end
			end
		end
	end

	local recording = History.recordUndo("MCP: Terrain replace material " .. from.Name .. " → " .. to.Name)
	local ok2, err2 = pcall(function() terrain:WriteVoxels(region, resolution, materials, occupancies) end)
	History.finishUndo(recording, ok2)
	if not ok2 then return nil, "WriteVoxels failed: " .. tostring(err2) end

	return { ok = true, changedVoxels = changed, from = from.Name, to = to.Name }
end

--- terrain_read_voxels: read terrain voxel data from a region.
function TerrainTools.terrain_read_voxels(args)
	local regionMin  = args.regionMin
	local regionMax  = args.regionMax
	local resolution = tonumber(args.resolution) or 4

	if not regionMin or not regionMax then
		return nil, "Required: regionMin ({x,y,z}) and regionMax ({x,y,z})"
	end

	local minV = toV3(regionMin)
	local maxV = toV3(regionMax)
	local region = Region3.new(minV, maxV)
	resolution   = math.max(4, math.floor(resolution / 4) * 4)

	local ok, materials, occupancies = pcall(function()
		return terrain:ReadVoxels(region, resolution)
	end)
	if not ok then return nil, "ReadVoxels failed: " .. tostring(materials) end

	return summariseVoxels(materials, occupancies, resolution, region)
end

--- terrain_clear_region: remove all terrain within a region. Undoable.
function TerrainTools.terrain_clear_region(args)
	local regionMin = args.regionMin
	local regionMax = args.regionMax

	if not regionMin or not regionMax then
		return nil, "Required: regionMin ({x,y,z}) and regionMax ({x,y,z})"
	end

	local minV = toV3(regionMin)
	local maxV = toV3(regionMax)

	local recording = History.recordUndo("MCP: Terrain clear region")
	local ok, err = pcall(function()
		terrain:FillRegion(Region3.new(minV, maxV), 4, Enum.Material.Air)
	end)
	History.finishUndo(recording, ok)
	if not ok then return nil, "Clear failed: " .. tostring(err) end

	return { ok = true }
end

return TerrainTools
