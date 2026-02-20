-- Utils/Types.luau
-- Rich type serialization and deserialization helpers

local Types = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Resolve a live Instance from a fullName string like "MaterialService.MyVariant".
-- Returns the Instance or nil.
local function resolveByFullName(fullName: string): Instance?
	if not fullName or fullName == "" then return nil end

	-- Strip leading "game." prefix if present
	local path = fullName:gsub("^game%.", "")

	local parts = {}
	for part in path:gmatch("[^%.]+") do
		table.insert(parts, part)
	end
	if #parts == 0 then return nil end

	-- First segment: try as a service name, then as a direct child of game
	local current: Instance = game
	for i, name in ipairs(parts) do
		local next: Instance?
		if current == game then
			-- Try GetService first so "MaterialService", "Workspace", etc. resolve correctly
			local ok, svc = pcall(function() return game:GetService(name) end)
			if ok and svc then
				next = svc
			else
				next = current:FindFirstChild(name)
			end
		else
			next = current:FindFirstChild(name)
		end
		if not next then return nil end
		current = next
	end

	return current
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

function Types.serializeValue(value)
	if value == nil then return nil end

	local t = typeof(value)

	if t == "string" or t == "number" or t == "boolean" then
		return value
	elseif t == "Color3" then
		return { _type = "Color3", r = math.floor(value.R * 255 + 0.5), g = math.floor(value.G * 255 + 0.5), b = math.floor(value.B * 255 + 0.5) }
	elseif t == "Vector3" then
		return { _type = "Vector3", x = value.X, y = value.Y, z = value.Z }
	elseif t == "Vector2" then
		return { _type = "Vector2", x = value.X, y = value.Y }
	elseif t == "CFrame" then
		return { _type = "CFrame", components = { value:GetComponents() } }
	elseif t == "UDim" then
		return { _type = "UDim", scale = value.Scale, offset = value.Offset }
	elseif t == "UDim2" then
		return { _type = "UDim2", xScale = value.X.Scale, xOffset = value.X.Offset, yScale = value.Y.Scale, yOffset = value.Y.Offset }
	elseif t == "BrickColor" then
		return { _type = "BrickColor", name = value.Name, number = value.Number }
	elseif t == "EnumItem" then
		return { _type = "EnumItem", enumType = tostring(value.EnumType), name = value.Name, value = value.Value }
	elseif t == "NumberRange" then
		return { _type = "NumberRange", min = value.Min, max = value.Max }
	elseif t == "NumberSequence" then
		local keypoints = {}
		for _, kp in ipairs(value.Keypoints) do
			table.insert(keypoints, { time = kp.Time, value = kp.Value, envelope = kp.Envelope })
		end
		return { _type = "NumberSequence", keypoints = keypoints }
	elseif t == "ColorSequence" then
		local keypoints = {}
		for _, kp in ipairs(value.Keypoints) do
			table.insert(keypoints, {
				time = kp.Time,
				color = { r = math.floor(kp.Value.R * 255 + 0.5), g = math.floor(kp.Value.G * 255 + 0.5), b = math.floor(kp.Value.B * 255 + 0.5) },
			})
		end
		return { _type = "ColorSequence", keypoints = keypoints }
	elseif t == "Rect" then
		return { _type = "Rect", minX = value.Min.X, minY = value.Min.Y, maxX = value.Max.X, maxY = value.Max.Y }
	elseif t == "PhysicalProperties" then
		return { _type = "PhysicalProperties", density = value.Density, friction = value.Friction, elasticity = value.Elasticity, frictionWeight = value.FrictionWeight, elasticityWeight = value.ElasticityWeight }
	elseif t == "Ray" then
		return { _type = "Ray", origin = { x = value.Origin.X, y = value.Origin.Y, z = value.Origin.Z }, direction = { x = value.Direction.X, y = value.Direction.Y, z = value.Direction.Z } }
	elseif t == "Instance" then
		-- Serialize with enough info to re-resolve the live object later.
		-- fullName is the primary lookup key; className helps the caller understand
		-- what kind of instance is being referenced (e.g. "MaterialVariant").
		return {
			_type     = "Instance",
			className = value.ClassName,
			name      = value.Name,
			fullName  = value:GetFullName(),
		}
	elseif t == "Axes" then
		local axes = {}
		if value.X then table.insert(axes, "X") end
		if value.Y then table.insert(axes, "Y") end
		if value.Z then table.insert(axes, "Z") end
		return { _type = "Axes", axes = axes }
	elseif t == "Faces" then
		local faces = {}
		if value.Top then table.insert(faces, "Top") end
		if value.Bottom then table.insert(faces, "Bottom") end
		if value.Left then table.insert(faces, "Left") end
		if value.Right then table.insert(faces, "Right") end
		if value.Front then table.insert(faces, "Front") end
		if value.Back then table.insert(faces, "Back") end
		return { _type = "Faces", faces = faces }
	elseif t == "Font" then
		return { _type = "Font", family = value.Family, weight = value.Weight.Name, style = value.Style.Name }
	else
		return { _type = t, stringValue = tostring(value) }
	end
end

-- ---------------------------------------------------------------------------
-- Deserialization
-- ---------------------------------------------------------------------------

function Types.deserializeValue(value)
	if type(value) ~= "table" then return value end
	local vtype = value._type
	if not vtype then return value end

	if vtype == "Color3" then
		if value.r and value.g and value.b then
			if value.r > 1 or value.g > 1 or value.b > 1 then
				return Color3.fromRGB(value.r, value.g, value.b)
			else
				return Color3.new(value.r, value.g, value.b)
			end
		end
	elseif vtype == "Vector3" then
		return Vector3.new(value.x or 0, value.y or 0, value.z or 0)
	elseif vtype == "Vector2" then
		return Vector2.new(value.x or 0, value.y or 0)
	elseif vtype == "CFrame" then
		if value.components and #value.components == 12 then
			return CFrame.new(unpack(value.components))
		elseif value.position and value.lookAt then
			local pos  = Vector3.new(value.position.x or 0, value.position.y or 0, value.position.z or 0)
			local look = Vector3.new(value.lookAt.x  or 0, value.lookAt.y  or 0, value.lookAt.z  or 0)
			return CFrame.lookAt(pos, look)
		elseif value.x and value.y and value.z then
			return CFrame.new(value.x, value.y, value.z)
		end
	elseif vtype == "UDim" then
		return UDim.new(value.scale or 0, value.offset or 0)
	elseif vtype == "UDim2" then
		return UDim2.new(value.xScale or 0, value.xOffset or 0, value.yScale or 0, value.yOffset or 0)
	elseif vtype == "BrickColor" then
		if value.name   then return BrickColor.new(value.name)   end
		if value.number then return BrickColor.new(value.number) end
	elseif vtype == "EnumItem" then
		if value.enumType and value.name then
			local ok, enumType = pcall(function() return Enum[value.enumType] end)
			if ok and enumType then
				local ok2, enumItem = pcall(function() return enumType[value.name] end)
				if ok2 and enumItem then return enumItem end
			end
		end
	elseif vtype == "NumberRange" then
		return NumberRange.new(value.min or 0, value.max or 1)
	elseif vtype == "NumberSequence" then
		if value.keypoints then
			local kps = {}
			for _, kp in ipairs(value.keypoints) do
				table.insert(kps, NumberSequenceKeypoint.new(kp.time, kp.value, kp.envelope or 0))
			end
			return NumberSequence.new(kps)
		end
	elseif vtype == "ColorSequence" then
		if value.keypoints then
			local kps = {}
			for _, kp in ipairs(value.keypoints) do
				local c     = kp.color
				local color = (c.r > 1 or c.g > 1 or c.b > 1) and Color3.fromRGB(c.r, c.g, c.b) or Color3.new(c.r, c.g, c.b)
				table.insert(kps, ColorSequenceKeypoint.new(kp.time, color))
			end
			return ColorSequence.new(kps)
		end
	elseif vtype == "Rect" then
		return Rect.new(value.minX or 0, value.minY or 0, value.maxX or 0, value.maxY or 0)
	elseif vtype == "PhysicalProperties" then
		return PhysicalProperties.new(
			value.density          or 1,
			value.friction         or 0.3,
			value.elasticity       or 0.5,
			value.frictionWeight   or 1,
			value.elasticityWeight or 1
		)
	elseif vtype == "Ray" then
		return Ray.new(
			Vector3.new(value.origin.x    or 0, value.origin.y    or 0, value.origin.z    or 0),
			Vector3.new(value.direction.x or 0, value.direction.y or 0, value.direction.z or 0)
		)
	elseif vtype == "Font" then
		local family = value.family or "rbxasset://fonts/families/SourceSansPro.json"
		local weight = Enum.FontWeight[value.weight or "Regular"] or Enum.FontWeight.Regular
		local style  = Enum.FontStyle[value.style   or "Normal"]  or Enum.FontStyle.Normal
		return Font.new(family, weight, style)
	elseif vtype == "Axes" then
		local args = {}
		if value.axes then
			for _, a in ipairs(value.axes) do
				if Enum.Axis[a] then table.insert(args, Enum.Axis[a]) end
			end
		end
		return Axes.new(unpack(args))
	elseif vtype == "Faces" then
		local args = {}
		if value.faces then
			for _, f in ipairs(value.faces) do
				if Enum.NormalId[f] then table.insert(args, Enum.NormalId[f]) end
			end
		end
		return Faces.new(unpack(args))

	elseif vtype == "Instance" then
		-- Resolve a live Instance by its fullName path.
		-- Supports three forms the caller may provide:
		--   1. fullName  – e.g. "MaterialService.MyVariant"  (preferred)
		--   2. path      – alias for fullName
		--   3. name      – bare name; tried as a child of every likely parent
		--                  (MaterialService, Workspace, game) as a last resort

		-- Form 1 / 2: fullName or path
		local fullName = value.fullName or value.path
		if fullName then
			local inst = resolveByFullName(fullName)
			if inst then return inst end
		end

		-- Form 3: bare name with optional className hint —
		-- try MaterialService first (covers the MaterialVariant case), then game
		if value.name then
			local candidates = {
				function() return game:GetService("MaterialService"):FindFirstChild(value.name) end,
				function() return game:FindFirstChild(value.name, true) end,
			}
			for _, try in ipairs(candidates) do
				local ok, inst = pcall(try)
				if ok and inst then
					-- If caller gave a className hint, make sure it matches
					if not value.className or inst.ClassName == value.className then
						return inst
					end
				end
			end
		end

		-- Could not resolve – return nil so the property assignment is skipped
		-- rather than writing a raw table to the property.
		return nil
	end

	return value
end

return Types
