-- Roblox Studio MCP Bridge Plugin v0.5
-- Place this file in your Roblox Plugins folder.

local HttpService          = game:GetService("HttpService")
local Selection            = game:GetService("Selection")
local CollectionService    = game:GetService("CollectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService  = game:GetService("ScriptEditorService")
local ReflectionService = game:GetService("ReflectionService")
local InsertService     = game:GetService("InsertService")
local StudioService     = game:GetService("StudioService")
local LogService        = game:GetService("LogService")
local StudioTestService = game:GetService("StudioTestService")

local BRIDGE_URL    = "http://127.0.0.1:28650"
local CLIENT_ID     = "studio"
local POLL_DELAY    = 0.05
local ERROR_DELAY   = 2
local MAX_LOG_LINES = 50
local RESULT_RETRY_MAX    = 3
local RESULT_RETRY_DELAY  = 0.5

local STUDIO_MODE = "stop"

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local pluginToolbar = plugin:CreateToolbar("Roblox MCP")
local openWidgetButton = pluginToolbar:CreateButton(
	"Roblox MCP",
	"Open Roblox MCP bridge widget",
	""
)
openWidgetButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right, true, false,
	320, 300, 240, 200
)
local widget = plugin:CreateDockWidgetPluginGuiAsync("RobloxMcpBridgeWidget", widgetInfo)
widget.Title = "Roblox MCP Bridge"

local uiPadding = Instance.new("UIPadding")
uiPadding.PaddingTop    = UDim.new(0, 8)
uiPadding.PaddingBottom = UDim.new(0, 8)
uiPadding.PaddingLeft   = UDim.new(0, 8)
uiPadding.PaddingRight  = UDim.new(0, 8)
uiPadding.Parent = widget

local layout = Instance.new("UIListLayout")
layout.Padding   = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent    = widget

local statusLabel = Instance.new("TextLabel")
statusLabel.Size                   = UDim2.new(1, 0, 0, 24)
statusLabel.BackgroundTransparency = 1
statusLabel.TextXAlignment         = Enum.TextXAlignment.Left
statusLabel.Font                   = Enum.Font.SourceSans
statusLabel.TextSize               = 14
statusLabel.TextColor3             = Color3.new(1, 1, 1)
statusLabel.Text                   = "Status: stopped"
statusLabel.LayoutOrder            = 1
statusLabel.Parent                 = widget

local jobCountLabel = Instance.new("TextLabel")
jobCountLabel.Size                   = UDim2.new(1, 0, 0, 18)
jobCountLabel.BackgroundTransparency = 1
jobCountLabel.TextXAlignment         = Enum.TextXAlignment.Left
jobCountLabel.Font                   = Enum.Font.SourceSans
jobCountLabel.TextSize               = 12
jobCountLabel.TextColor3             = Color3.fromRGB(180, 180, 180)
jobCountLabel.Text                   = "Jobs completed: 0"
jobCountLabel.LayoutOrder            = 2
jobCountLabel.Parent                 = widget

local startButton = Instance.new("TextButton")
startButton.Size        = UDim2.new(1, 0, 0, 28)
startButton.Text        = "Start Bridge Polling"
startButton.Font        = Enum.Font.SourceSans
startButton.TextSize    = 14
startButton.LayoutOrder = 3
startButton.Parent      = widget

local stopButton = Instance.new("TextButton")
stopButton.Size        = UDim2.new(1, 0, 0, 28)
stopButton.Text        = "Stop Bridge Polling"
stopButton.Font        = Enum.Font.SourceSans
stopButton.TextSize    = 14
stopButton.LayoutOrder = 4
stopButton.Parent      = widget

local logFrame = Instance.new("ScrollingFrame")
logFrame.Size                = UDim2.new(1, 0, 1, -120)
logFrame.BackgroundColor3    = Color3.fromRGB(30, 30, 30)
logFrame.BorderSizePixel     = 1
logFrame.ScrollBarThickness  = 6
logFrame.CanvasSize          = UDim2.new(0, 0, 0, 0)
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.LayoutOrder         = 5
logFrame.Parent              = widget

local logLayout = Instance.new("UIListLayout")
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent    = logFrame

local logLines = 0

openWidgetButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------
local function log(msg)
	local text = os.date("[%H:%M:%S] ") .. tostring(msg)
	warn("[MCP Bridge] " .. tostring(msg))

	logLines = logLines + 1
	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, -6, 0, 16)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.Code
	label.TextSize               = 12
	label.TextColor3             = Color3.fromRGB(200, 200, 200)
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.TextWrapped            = true
	label.AutomaticSize          = Enum.AutomaticSize.Y
	label.Text                   = text
	label.LayoutOrder            = logLines
	label.Parent                 = logFrame

	local children = logFrame:GetChildren()
	local labels = {}
	for _, c in ipairs(children) do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if #labels > MAX_LOG_LINES then
		table.sort(labels, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, #labels - MAX_LOG_LINES do
			labels[i]:Destroy()
		end
	end
end

local CONSOLE_LOG_LIMIT = 400
local consoleLogs = {}

local function pushConsoleLog(entry)
	entry.timestamp = entry.timestamp or time()
	table.insert(consoleLogs, entry)
	if #consoleLogs > CONSOLE_LOG_LIMIT then
		table.remove(consoleLogs, 1)
	end
end

LogService.MessageOut:Connect(function(message, messageType)
	pushConsoleLog({
		text = tostring(message or ""),
		type = messageType and tostring(messageType.Name) or "Unknown",
		timestamp = time(),
	})
end)

---------------------------------------------------------------------------
-- HttpEnabled
---------------------------------------------------------------------------
local function ensureHttpEnabled()
	if HttpService.HttpEnabled then
		log("HttpEnabled is already true")
		return true
	end
	local ok = pcall(function() HttpService.HttpEnabled = true end)
	if ok and HttpService.HttpEnabled then
		log("HttpEnabled set to true")
		return true
	end
	log("ERROR: Could not enable HttpService! Enable it in Game Settings → Security.")
	return false
end

---------------------------------------------------------------------------
-- HTTP helper
---------------------------------------------------------------------------
local function request(method, url, body)
	local req = { Url = url, Method = method }
	if body ~= nil then
		req.Headers = { ["Content-Type"] = "application/json" }
		req.Body = HttpService:JSONEncode(body)
	end
	return HttpService:RequestAsync(req)
end

---------------------------------------------------------------------------
-- Rich type serialization (Instance property → JSON-safe value)
---------------------------------------------------------------------------
local function serializeValue(value)
	if value == nil then
		return nil
	end

	local t = typeof(value)

	if t == "string" or t == "number" or t == "boolean" then
		return value

	elseif t == "Color3" then
		return {
			_type = "Color3",
			r = math.floor(value.R * 255 + 0.5),
			g = math.floor(value.G * 255 + 0.5),
			b = math.floor(value.B * 255 + 0.5),
		}

	elseif t == "Vector3" then
		return { _type = "Vector3", x = value.X, y = value.Y, z = value.Z }

	elseif t == "Vector2" then
		return { _type = "Vector2", x = value.X, y = value.Y }

	elseif t == "CFrame" then
		local components = { value:GetComponents() }
		return { _type = "CFrame", components = components }

	elseif t == "UDim" then
		return { _type = "UDim", scale = value.Scale, offset = value.Offset }

	elseif t == "UDim2" then
		return {
			_type = "UDim2",
			xScale = value.X.Scale, xOffset = value.X.Offset,
			yScale = value.Y.Scale, yOffset = value.Y.Offset,
		}

	elseif t == "BrickColor" then
		return { _type = "BrickColor", name = value.Name, number = value.Number }

	elseif t == "EnumItem" then
		return {
			_type = "EnumItem",
			enumType = tostring(value.EnumType),
			name = value.Name,
			value = value.Value,
		}

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
				color = {
					r = math.floor(kp.Value.R * 255 + 0.5),
					g = math.floor(kp.Value.G * 255 + 0.5),
					b = math.floor(kp.Value.B * 255 + 0.5),
				},
			})
		end
		return { _type = "ColorSequence", keypoints = keypoints }

	elseif t == "Rect" then
		return {
			_type = "Rect",
			minX = value.Min.X, minY = value.Min.Y,
			maxX = value.Max.X, maxY = value.Max.Y,
		}

	elseif t == "PhysicalProperties" then
		return {
			_type = "PhysicalProperties",
			density = value.Density,
			friction = value.Friction,
			elasticity = value.Elasticity,
			frictionWeight = value.FrictionWeight,
			elasticityWeight = value.ElasticityWeight,
		}

	elseif t == "Ray" then
		return {
			_type = "Ray",
			origin = { x = value.Origin.X, y = value.Origin.Y, z = value.Origin.Z },
			direction = { x = value.Direction.X, y = value.Direction.Y, z = value.Direction.Z },
		}

	elseif t == "Instance" then
		return { _type = "Instance", className = value.ClassName, name = value.Name, fullName = value:GetFullName() }

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
		return {
			_type = "Font",
			family = value.Family,
			weight = value.Weight.Name,
			style = value.Style.Name,
		}

	else
		return { _type = t, stringValue = tostring(value) }
	end
end

---------------------------------------------------------------------------
-- Rich type deserialization (JSON value → Roblox type)
---------------------------------------------------------------------------
local function deserializeValue(value)
	if type(value) ~= "table" then
		return value
	end

	local vtype = value._type

	if not vtype then
		return value
	end

	if vtype == "Color3" then
		if value.r and value.g and value.b then
			-- Accept both 0-255 and 0-1 ranges
			local r, g, b = value.r, value.g, value.b
			if r > 1 or g > 1 or b > 1 then
				return Color3.fromRGB(r, g, b)
			else
				return Color3.new(r, g, b)
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
			local pos = Vector3.new(value.position.x or 0, value.position.y or 0, value.position.z or 0)
			local look = Vector3.new(value.lookAt.x or 0, value.lookAt.y or 0, value.lookAt.z or 0)
			return CFrame.lookAt(pos, look)
		elseif value.x and value.y and value.z then
			return CFrame.new(value.x, value.y, value.z)
		end

	elseif vtype == "UDim" then
		return UDim.new(value.scale or 0, value.offset or 0)

	elseif vtype == "UDim2" then
		return UDim2.new(
			value.xScale or 0, value.xOffset or 0,
			value.yScale or 0, value.yOffset or 0
		)

	elseif vtype == "BrickColor" then
		if value.name then
			return BrickColor.new(value.name)
		elseif value.number then
			return BrickColor.new(value.number)
		end

	elseif vtype == "EnumItem" then
		if value.enumType and value.name then
			local ok, enumType = pcall(function() return Enum[value.enumType] end)
			if ok and enumType then
				local ok2, enumItem = pcall(function() return enumType[value.name] end)
				if ok2 and enumItem then
					return enumItem
				end
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
				local c = kp.color
				local color
				if c.r > 1 or c.g > 1 or c.b > 1 then
					color = Color3.fromRGB(c.r, c.g, c.b)
				else
					color = Color3.new(c.r, c.g, c.b)
				end
				table.insert(kps, ColorSequenceKeypoint.new(kp.time, color))
			end
			return ColorSequence.new(kps)
		end

	elseif vtype == "Rect" then
		return Rect.new(value.minX or 0, value.minY or 0, value.maxX or 0, value.maxY or 0)

	elseif vtype == "PhysicalProperties" then
		return PhysicalProperties.new(
			value.density or 1,
			value.friction or 0.3,
			value.elasticity or 0.5,
			value.frictionWeight or 1,
			value.elasticityWeight or 1
		)

	elseif vtype == "Ray" then
		local origin = Vector3.new(value.origin.x or 0, value.origin.y or 0, value.origin.z or 0)
		local direction = Vector3.new(value.direction.x or 0, value.direction.y or 0, value.direction.z or 0)
		return Ray.new(origin, direction)

	elseif vtype == "Font" then
		local family = value.family or "rbxasset://fonts/families/SourceSansPro.json"
		local weight = Enum.FontWeight[value.weight or "Regular"] or Enum.FontWeight.Regular
		local style = Enum.FontStyle[value.style or "Normal"] or Enum.FontStyle.Normal
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
	end

	-- Fallback: return the raw value
	return value
end

---------------------------------------------------------------------------
-- Instance id map & resolution
---------------------------------------------------------------------------
local idMap = {}

local function registerInstance(inst)
	if not inst then return nil end
	local ok, debugId = pcall(function() return inst:GetDebugId(0) end)
	if ok and debugId then
		idMap[debugId] = inst
		return debugId
	end
	return nil
end

local function resolveById(id)
	local inst = id and idMap[id] or nil
	if inst then
		local ok, _ = pcall(function() return inst.Parent end)
		if not ok then
			idMap[id] = nil
			return nil
		end
	end
	return inst
end

local function resolveByPathArray(pathArray)
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

local function resolveByPath(path)
	if not path or path == "" then return nil end
	if path == "game" then return game end
	path = path:gsub("^game%.", "")
	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	return resolveByPathArray(parts)
end

local function resolveInstance(args)
	if args.id then
		local inst = resolveById(args.id)
		if inst then return inst end
	end
	if args.pathArray then
		local inst = resolveByPathArray(args.pathArray)
		if inst then return inst end
	end
	if args.path then return resolveByPath(args.path) end
	return nil
end

---------------------------------------------------------------------------
-- Serialization
---------------------------------------------------------------------------
local function serializeInstance(inst)
	if not inst then return nil end
	local id = registerInstance(inst)
	local parent = inst.Parent
	local parentId = parent and registerInstance(parent) or nil
	return {
		id        = id,
		name      = inst.Name,
		className = inst.ClassName,
		fullName  = inst:GetFullName(),
		parentId  = parentId,
	}
end

local function serializeInstances(list)
	local out = {}
	for _, inst in ipairs(list) do
		local info = serializeInstance(inst)
		if info then table.insert(out, info) end
	end
	return out
end

---------------------------------------------------------------------------
-- ChangeHistoryService helpers
---------------------------------------------------------------------------
local function recordUndo(name)
	local recording = ChangeHistoryService:TryBeginRecording(name or "MCP Bridge Action")
	return recording
end

local function finishUndo(recording, success)
	if not recording then return end
	if success ~= false then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
	end
end

---------------------------------------------------------------------------
-- Instance handlers
---------------------------------------------------------------------------
local function getServices()
	return serializeInstances(game:GetChildren())
end

local function getChildren(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	return serializeInstances(inst:GetChildren())
end

local function getDescendants(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	return serializeInstances(inst:GetDescendants())
end

local function getInstance(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	return serializeInstance(inst)
end

local function findInstances(args)
	local ancestor
	if args.ancestorPathArray or args.ancestorPath then
		ancestor = resolveInstance({ path = args.ancestorPath, pathArray = args.ancestorPathArray })
	else
		ancestor = game
	end
	if not ancestor then return nil, "Ancestor not found" end

	local matches = {}
	for _, inst in ipairs(ancestor:GetDescendants()) do
		if args.name and inst.Name ~= args.name then continue end
		if args.className and inst.ClassName ~= args.className then continue end
		if args.tag and not CollectionService:HasTag(inst, args.tag) then continue end
		table.insert(matches, inst)
	end
	return serializeInstances(matches)
end

local function getTree(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local maxDepth    = args.maxDepth or 5
	local maxChildren = args.maxChildren or 50

	local function buildNode(obj, depth)
		local node = {
			name      = obj.Name,
			className = obj.ClassName,
		}
		if obj:IsA("LuaSourceContainer") then
			local src = obj.Source or ""
			node.scriptLineCount = select(2, src:gsub("\n", "")) + 1
		end
		local children = obj:GetChildren()
		if depth < maxDepth then
			if #children > 0 then
				node.children = {}
				local limit = math.min(#children, maxChildren)
				for i = 1, limit do
					table.insert(node.children, buildNode(children[i], depth + 1))
				end
				if #children > limit then
					node.truncatedChildren = #children - limit
				end
			end
		else
			if #children > 0 then
				node.childCount = #children
			end
		end
		return node
	end

	return buildNode(inst, 0)
end

local function createInstance(args)
	local className = args.className
	if not className then return nil, "Missing className" end
	local parent
	if args.parentPath or args.parentPathArray then
		parent = resolveInstance({ path = args.parentPath, pathArray = args.parentPathArray })
	else
		parent = workspace
	end
	if not parent then return nil, "Parent not found" end

	local recording = recordUndo("MCP: Create " .. className)
	local inst = Instance.new(className)
	for key, value in pairs(args.properties or {}) do
		pcall(function() inst[key] = deserializeValue(value) end)
	end
	inst.Parent = parent
	finishUndo(recording, true)
	return serializeInstance(inst)
end

local function deleteInstance(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local recording = recordUndo("MCP: Delete " .. inst.Name)
	inst:Destroy()
	finishUndo(recording, true)
	return { ok = true }
end

local function cloneInstance(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end

	local recording = recordUndo("MCP: Clone " .. inst.Name)
	local clone = inst:Clone()
	if not clone then
		finishUndo(recording, false)
		return nil, "Clone failed (instance may be non-archivable)"
	end

	if args.newParentPath or args.newParentPathArray then
		local parent = resolveInstance({ path = args.newParentPath, pathArray = args.newParentPathArray })
		clone.Parent = parent or inst.Parent
	else
		clone.Parent = inst.Parent
	end

	if args.newName then
		clone.Name = args.newName
	end

	finishUndo(recording, true)
	return serializeInstance(clone)
end

local function reparentInstance(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local parent = resolveInstance({ path = args.newParentPath, pathArray = args.newParentPathArray })
	if not parent then return nil, "New parent not found" end
	local recording = recordUndo("MCP: Reparent " .. inst.Name)
	inst.Parent = parent
	finishUndo(recording, true)
	return { ok = true }
end

local function setName(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local recording = recordUndo("MCP: Rename " .. inst.Name .. " → " .. (args.name or ""))
	inst.Name = args.name or inst.Name
	finishUndo(recording, true)
	return { ok = true }
end

local function selectInstance(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	Selection:Set({ inst })
	return { ok = true }
end

---------------------------------------------------------------------------
-- Property / Attribute handlers (with rich type support)
---------------------------------------------------------------------------
local function getProperties(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local props = {}
	for _, prop in ipairs(args.properties or {}) do
		local ok, value = pcall(function() return inst[prop] end)
		if ok then
			props[prop] = serializeValue(value)
		else
			props[prop] = { _type = "error", message = "Cannot read property" }
		end
	end
	return props
end

local function getAllProperties(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end

	local allCapabilities = SecurityCapabilities.new(
		table.unpack(Enum.SecurityCapability:GetEnumItems())
	)

	local filter = {
		Security = allCapabilities,
		ExcludeInherited = false,
		ExcludeDisplay = true,
	}

	local reflected = ReflectionService:GetPropertiesOfClass(inst.ClassName, filter)
	if not reflected then return nil, "Unknown class: " .. inst.ClassName end

	local result = {}
	local skipped = {}

	for _, prop in ipairs(reflected) do
		local name = prop.Name

		-- Skip properties that require higher security to read
		-- and skip deprecated ones
		local deprecated = prop.Display
			and prop.Display.DeprecationMessage
			and prop.Display.DeprecationMessage ~= ""

		if not deprecated then
			local ok, value = pcall(function() return inst[name] end)
			if ok then
				result[name] = serializeValue(value)
			else
				table.insert(skipped, name)
			end
		end
	end

	return {
		className = inst.ClassName,
		propertyCount = #result,
		properties = result,
		skippedCount = #skipped,
	}
end

local function setProperties(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local recording = recordUndo("MCP: Set properties on " .. inst.Name)
	local errors = {}
	for key, value in pairs(args.properties or {}) do
		local deserialized = deserializeValue(value)
		local ok, err = pcall(function() inst[key] = deserialized end)
		if not ok then
			table.insert(errors, key .. ": " .. tostring(err))
		end
	end
	finishUndo(recording, true)
	if #errors > 0 then
		return { ok = true, warnings = errors }
	end
	return { ok = true }
end

local function getAttributes(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local attrs = inst:GetAttributes()
	local result = {}
	for k, v in pairs(attrs) do
		result[k] = serializeValue(v)
	end
	return result
end

local function setAttributes(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	local recording = recordUndo("MCP: Set attributes on " .. inst.Name)
	for key, value in pairs(args.attributes or {}) do
		inst:SetAttribute(key, deserializeValue(value))
	end
	finishUndo(recording, true)
	return { ok = true }
end

---------------------------------------------------------------------------
-- Tag handlers
---------------------------------------------------------------------------
local function getTags(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	return { tags = CollectionService:GetTags(inst) }
end

local function addTag(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not args.tag then return nil, "Missing tag" end
	local recording = recordUndo("MCP: Add tag '" .. args.tag .. "' to " .. inst.Name)
	CollectionService:AddTag(inst, args.tag)
	finishUndo(recording, true)
	return { ok = true }
end

local function removeTag(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not args.tag then return nil, "Missing tag" end
	local recording = recordUndo("MCP: Remove tag '" .. args.tag .. "' from " .. inst.Name)
	CollectionService:RemoveTag(inst, args.tag)
	finishUndo(recording, true)
	return { ok = true }
end

---------------------------------------------------------------------------
-- Script handlers
---------------------------------------------------------------------------
local function readScript(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end
	return { source = inst.Source }
end

---------------------------------------------------------------------------
-- Helper functions for script operations
---------------------------------------------------------------------------
-- Helper to ensure ScriptEditorService document is updated if script is open
-- In Roblox Studio, setting inst.Source automatically updates open ScriptEditorService documents.
-- This function verifies the document exists and triggers a refresh if needed.
local function updateScriptEditorDocument(inst, newSource)
	local doc = ScriptEditorService:FindScriptDocument(inst)
	if doc then
		-- Document is open - ensure it gets the updated source
		-- Setting Source should automatically update, but we spawn a task to ensure
		-- the update propagates even if there are timing issues
		task.spawn(function()
			-- Small delay to let the Source property change propagate
			task.wait(0.01)
			-- Force a refresh by reading the document (triggers update check)
			pcall(function()
				local currentDoc = ScriptEditorService:FindScriptDocument(inst)
				if currentDoc then
					-- Accessing the document should trigger Studio to sync with Source
					local _ = currentDoc:GetScript()
				end
			end)
		end)
	end
end

-- Basic syntax validation: check for balanced brackets/parentheses
local function validateBasicSyntax(text)
	local openParen = 0
	local openBrace = 0
	local openBracket = 0
	for char in text:gmatch(".") do
		if char == "(" then openParen = openParen + 1
		elseif char == ")" then openParen = openParen - 1
		elseif char == "{" then openBrace = openBrace + 1
		elseif char == "}" then openBrace = openBrace - 1
		elseif char == "[" then openBracket = openBracket + 1
		elseif char == "]" then openBracket = openBracket - 1
		end
		if openParen < 0 or openBrace < 0 or openBracket < 0 then
			return false, "Unmatched closing bracket/parenthesis"
		end
	end
	if openParen ~= 0 or openBrace ~= 0 or openBracket ~= 0 then
		return false, "Unmatched opening bracket/parenthesis"
	end
	return true
end

-- Get indentation from a line (leading whitespace)
local function getIndentation(line)
	local indent = line:match("^(%s*)")
	return indent or ""
end

-- Detect if a line is likely inside a function (heuristic-based)
local function isLikelyInsideFunction(lines, lineNum)
	if lineNum < 1 or lineNum > #lines then return false end

	local functionDepth = 0
	local inString = false
	local stringChar = nil

	for i = 1, lineNum do
		local line = lines[i] or ""
		local trimmed = line:gsub("%s+", " ")

		-- Simple string detection (not perfect but helps)
		for char in line:gmatch(".") do
			if char == '"' or char == "'" then
				if not inString then
					inString = true
					stringChar = char
				elseif char == stringChar then
					inString = false
					stringChar = nil
				end
			end
		end

		if not inString then
			-- Check for function start
			if trimmed:match("^function%s") or trimmed:match("^local%s+function%s") or
				trimmed:match("%s*=%s*function%s*%(") or trimmed:match("^[%w_%.%:]+%s*=%s*function%s*%(") then
				functionDepth = functionDepth + 1
			end

			-- Check for function end
			if trimmed:match("^end%s*$") or trimmed:match("^end%s*,") or trimmed:match("^end%s*%)") then
				functionDepth = math.max(0, functionDepth - 1)
			end
		end
	end

	return functionDepth > 0
end

-- Detect potential global variable declarations in code
local function detectGlobalVariables(code)
	local globals = {}
	local lines = string.split(code, "\n")

	for i, line in ipairs(lines) do
		local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")

		-- Detect global variable assignments (not local)
		local globalMatch = trimmed:match("^([%w_][%w_%.%:]*)%s*=")
		if globalMatch and not trimmed:match("^local%s") and not trimmed:match("^function%s") then
			-- Exclude common patterns that aren't globals
			if not globalMatch:match("^_") and not globalMatch:match("%.") then
				table.insert(globals, {name = globalMatch, line = i})
			end
		end
	end

	return globals
end

-- Enhanced syntax validation with comprehensive checks
local function validateEnhancedSyntax(text, lines)
	-- First do basic bracket matching
	local basicValid, basicError = validateBasicSyntax(text)
	if not basicValid then
		return false, basicError
	end

	-- Check for common syntax issues
	local linesArray = lines or string.split(text, "\n")

	-- Track block structures with a stack for accurate matching
	local blockStack = {}
	local inString = false
	local stringChar = nil
	local inComment = false

	local function findCommentStartOutsideStrings(s)
		local inStr = false
		local strChar = nil
		local i = 1
		while i <= #s - 1 do
			local ch = s:sub(i, i)
			if inStr then
				if ch == "\\" then
					i = i + 1
				elseif ch == strChar then
					inStr = false
					strChar = nil
				end
			else
				if ch == "'" or ch == "\"" then
					inStr = true
					strChar = ch
				elseif ch == "-" and s:sub(i, i + 1) == "--" then
					return i
				end
			end
			i = i + 1
		end
		return nil
	end

	-- Count keywords (for overall balance check)
	local functionCount = 0
	local endCount = 0
	local ifCount = 0
	local thenCount = 0
	local doCount = 0
	local repeatCount = 0
	local untilCount = 0
	local whileCount = 0

	for lineNum, line in ipairs(linesArray) do
		local codeLine = line

		-- Track string state (simple heuristic - not perfect but helps)
		local singleQuotes = select(2, line:gsub("'", "'"))
		local doubleQuotes = select(2, line:gsub('"', '"'))
		-- If odd number of quotes, toggle string state (simplified)
		if singleQuotes % 2 == 1 then
			inString = not inString
			stringChar = "'"
		end
		if doubleQuotes % 2 == 1 and not inString then
			inString = not inString
			stringChar = '"'
		end

		-- Track comments (block comments)
		if codeLine:match("%-%-%[%[") then
			inComment = true
		end
		if codeLine:match("%]%]%-%-") then
			inComment = false
		end

		-- Strip inline comments when not inside a block comment
		if not inComment then
			local commentStart = findCommentStartOutsideStrings(codeLine)
			if commentStart then
				codeLine = codeLine:sub(1, commentStart - 1)
			end
		end

		local trimmed = codeLine:gsub("^%s+", ""):gsub("%s+$", "")

		-- Skip syntax checking for pure comments/empty lines
		if inComment or trimmed == "" then
			-- Skip to next iteration
		else

			-- Only check syntax if not in string or comment
			if not inString then
				-- Count function declarations
				if trimmed:match("^function%s") or trimmed:match("^local%s+function%s") or
					trimmed:match("%s*=%s*function%s*%(") or trimmed:match("^[%w_%.%:]+%s*=%s*function%s*%(") then
					functionCount = functionCount + 1
					table.insert(blockStack, {type = "function", line = lineNum})
				end

				-- Count if statements
				if trimmed:match("^if%s") or trimmed:match("%s+if%s") then
					ifCount = ifCount + 1
					table.insert(blockStack, {type = "if", line = lineNum})
				end

				-- Count then keywords
				if trimmed:match("%s+then%s") or trimmed:match("%s+then%s*$") or trimmed:match("^then%s") then
					thenCount = thenCount + 1
				end

				-- Count do keywords (for loops)
				if trimmed:match("%s+do%s*$") or trimmed:match("%s+do%s+") or trimmed:match("^do%s*$") then
					doCount = doCount + 1
					table.insert(blockStack, {type = "do", line = lineNum})
				end

				-- Count while loops
				if trimmed:match("^while%s") or trimmed:match("%s+while%s") then
					whileCount = whileCount + 1
				end

				-- Count repeat loops
				if trimmed:match("^repeat%s") or trimmed:match("%s+repeat%s") then
					repeatCount = repeatCount + 1
					table.insert(blockStack, {type = "repeat", line = lineNum})
				end

				-- Count until keywords
				if trimmed:match("^until%s") or trimmed:match("%s+until%s") then
					untilCount = untilCount + 1
					-- Pop matching repeat from stack
					for i = #blockStack, 1, -1 do
						if blockStack[i].type == "repeat" then
							table.remove(blockStack, i)
							break
						end
					end
				end

				-- Count end keywords and match with blocks
				if trimmed:match("^end%s*$") or trimmed:match("^end%s*,") or trimmed:match("^end%s*%)") or trimmed:match("^end%s+") then
					endCount = endCount + 1
					-- Pop matching block from stack
					if #blockStack > 0 then
						table.remove(blockStack)
					end
				end
			end -- end of "if not inString"

			-- Check for incomplete statements (lines ending with operators - potential syntax error)
			-- This check happens regardless of string/comment state
			if not inComment and trimmed ~= "" then
				local lastChar = trimmed:sub(-1)
				if lastChar and (lastChar == "+" or lastChar == "-" or lastChar == "*" or lastChar == "/" or
					lastChar == "=" or lastChar == ">" or lastChar == "<" or lastChar == "&" or lastChar == "|") then
					-- Allow if it's part of a string
					if not inString then
						-- Check if next line exists and might continue the statement
						if lineNum < #linesArray then
							local nextTrimmed = (linesArray[lineNum + 1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
							-- If next line doesn't look like a continuation, this might be an error
							if not nextTrimmed:match("^[%w_%[%\"']") and not nextTrimmed:match("^%(") and not nextTrimmed:match("^%-%-") then
								return false, string.format(
									"Potential incomplete statement at line %d: line ends with operator '%s' without continuation",
									lineNum, lastChar
								)
							end
						else
							-- Last line ending with operator is likely an error
							return false, string.format(
								"Incomplete statement at line %d (last line): line ends with operator '%s'",
								lineNum, lastChar
							)
						end
					end
				end
			end

		end -- end of comment check
	end

	-- Check for unmatched blocks (strict validation)
	if #blockStack > 0 then
		local unmatched = {}
		for _, block in ipairs(blockStack) do
			table.insert(unmatched, string.format("%s (line %d)", block.type, block.line))
		end
		return false, string.format(
			"Unclosed blocks detected: %s. Missing 'end' statements.",
			table.concat(unmatched, ", ")
		)
	end

	local blockStartCount = functionCount + ifCount + doCount
	-- Check for significant mismatches (stricter than before)
	local blockDiff = math.abs(blockStartCount - endCount)
	if blockDiff > 10 then
		return false, string.format(
			"Unmatched block starts vs ends: %d starters (functions/ifs/do), %d ends (difference: %d)",
			blockStartCount, endCount, blockDiff
		)
	end

	local IF_THEN_TOLERANCE = 5
	if math.abs(ifCount - thenCount) > IF_THEN_TOLERANCE then
		return false, string.format(
			"Unmatched if/then blocks: %d ifs, %d thens (difference: %d)",
			ifCount, thenCount, math.abs(ifCount - thenCount)
		)
	end

	local DO_END_TOLERANCE = 5
	if math.abs(doCount - endCount) > DO_END_TOLERANCE and doCount > 0 then
		-- Note: do blocks also use 'end', so we check if there are more do's than available ends
		local availableEnds = endCount - functionCount
		if doCount > availableEnds then
			return false, string.format(
				"Unmatched do/end blocks: %d do statements, but only %d ends available for loops",
				doCount, availableEnds
			)
		end
	end

	if math.abs(repeatCount - untilCount) > 0 then
		return false, string.format(
			"Unmatched repeat/until blocks: %d repeat statements, %d until statements",
			repeatCount, untilCount
		)
	end

	return true
end

local function writeScript(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local newSource = args.source or ""

	-- Basic syntax validation
	local syntaxValid, syntaxError = validateBasicSyntax(newSource)
	if not syntaxValid then
		return nil, string.format(
			"SYNTAX VALIDATION FAILED: %s\n" ..
				"The script source has invalid syntax. Please review your changes.",
			syntaxError
		)
	end

	local recording = recordUndo("MCP: Write script " .. inst.Name)
	inst.Source = newSource

	-- Update ScriptEditorService document if script is open
	updateScriptEditorDocument(inst, newSource)

	finishUndo(recording, true)
	return { ok = true }
end

local function getScriptLines(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local source = inst.Source or ""
	local lines  = string.split(source, "\n")

	local startLine = args.startLine
	local endLine   = args.endLine

	if not startLine and not endLine then
		return { totalLines = #lines }
	end

	startLine = math.max(1, math.min(startLine or 1, #lines))
	endLine   = math.max(startLine, math.min(endLine or #lines, #lines))

	local result = {}
	for i = startLine, endLine do
		table.insert(result, { lineNumber = i, text = lines[i] })
	end

	return {
		totalLines = #lines,
		startLine  = startLine,
		endLine    = endLine,
		lines      = result,
	}
end

local function searchScript(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local source = inst.Source or ""
	local lines  = string.split(source, "\n")
	local query  = args.query
	if not query then return nil, "Missing query" end

	local usePattern    = args.usePattern or false
	local caseSensitive = args.caseSensitive
	if caseSensitive == nil then caseSensitive = true end
	local contextLines = args.contextLines or 0
	local maxResults   = args.maxResults or 50

	local searchQuery = query
	if not caseSensitive then
		searchQuery = query:lower()
	end

	local matchedNums = {}
	for i, line in ipairs(lines) do
		local searchLine = caseSensitive and line or line:lower()
		local found
		if usePattern then
			found = string.find(searchLine, searchQuery)
		else
			found = string.find(searchLine, searchQuery, 1, true)
		end
		if found then
			table.insert(matchedNums, i)
			if #matchedNums >= maxResults then break end
		end
	end

	local matchSet = {}
	for _, n in ipairs(matchedNums) do matchSet[n] = true end

	local included = {}
	local results  = {}
	for _, num in ipairs(matchedNums) do
		local s = math.max(1, num - contextLines)
		local e = math.min(#lines, num + contextLines)
		for i = s, e do
			if not included[i] then
				included[i] = true
				table.insert(results, {
					lineNumber = i,
					text       = lines[i],
					isMatch    = matchSet[i] == true,
				})
			end
		end
	end
	table.sort(results, function(a, b) return a.lineNumber < b.lineNumber end)

	return {
		totalLines = #lines,
		matchCount = #matchedNums,
		results    = results,
	}
end

---------------------------------------------------------------------------
-- Patch script
---------------------------------------------------------------------------
local function normalizeForComparison(text)
	local result = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(result, (line:gsub("%s+$", "")))
	end
	while #result > 0 and result[#result] == "" do
		table.remove(result)
	end
	return table.concat(result, "\n")
end

local function patchScript(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local source  = inst.Source or ""
	local lines   = string.split(source, "\n")
	local patches = args.patches or {}

	for patchIndex, patch in ipairs(patches) do
		local op = patch.op

		if op == "append" then
			local newLines = string.split(patch.content or "", "\n")
			for _, l in ipairs(newLines) do
				table.insert(lines, l)
			end

		elseif op == "prepend" then
			local newLines = string.split(patch.content or "", "\n")
			for i = #newLines, 1, -1 do
				table.insert(lines, 1, newLines[i])
			end

		elseif op == "insert" then
			local at = math.max(1, math.min(patch.lineStart or 1, #lines + 1))

			-- SAFETY: Require expectedContext for insert to prevent unsafe mid-function insertions
			if patch.expectedContext == nil then
				return nil, string.format(
					"SAFETY ERROR in patch #%d (insert at line %d): 'expectedContext' is REQUIRED for insert operations.\n" ..
						"This prevents unsafe insertions inside functions. Provide the exact content of the line BEFORE the insertion point.\n" ..
						"Example: If inserting after line 10, provide expectedContext with the exact content of line 10.",
					patchIndex, at
				)
			end

			-- Validate expectedContext matches the line before insertion point
			local contextLine = at > 1 and lines[at - 1] or ""
			if normalizeForComparison(contextLine) ~= normalizeForComparison(patch.expectedContext) then
				return nil, string.format(
					"CONTEXT MISMATCH in patch #%d (insert at line %d).\n=== EXPECTED CONTEXT ===\n%s\n=== ACTUAL CONTEXT ===\n%s\n=== END ===\n" ..
						"The line before the insertion point doesn't match. Re-read the script and retry.",
					patchIndex, at, patch.expectedContext, contextLine
				)
			end

			-- Preserve indentation from the context line
			-- Note: Insertions inside functions are allowed - syntax validation at the end will catch any errors
			local baseIndent = getIndentation(contextLine)
			local newLines = string.split(patch.content or "", "\n")
			for i, l in ipairs(newLines) do
				-- If the line doesn't already have indentation, use the base indent
				local lineToInsert = l
				if l:match("^%S") and baseIndent ~= "" then
					lineToInsert = baseIndent .. l
				end
				table.insert(lines, at + i - 1, lineToInsert)
			end

		elseif op == "replace" then
			local s = math.max(1, patch.lineStart or 1)
			local e = math.min(#lines, patch.lineEnd or s)

			if patch.expectedContent ~= nil then
				local actualLines = {}
				for i = s, e do
					table.insert(actualLines, lines[i] or "")
				end
				local actual = table.concat(actualLines, "\n")
				if normalizeForComparison(actual) ~= normalizeForComparison(patch.expectedContent) then
					return nil, string.format(
						"CONTENT MISMATCH in patch #%d (replace lines %d-%d).\n=== EXPECTED ===\n%s\n=== ACTUAL ===\n%s\n=== END ===\nThe script may have changed. Re-read the lines and retry.",
						patchIndex, s, e, patch.expectedContent, actual
					)
				end
			end

			-- Preserve indentation from first line being replaced if new content doesn't have it
			local preservedIndent = ""
			if s <= #lines then
				local firstLine = lines[s]
				preservedIndent = getIndentation(firstLine)
			end

			for _ = s, e do
				if s <= #lines then
					table.remove(lines, s)
				end
			end
			local newLines = string.split(patch.content or "", "\n")
			for i, l in ipairs(newLines) do
				-- If line doesn't have indentation and we have preserved indent, apply it
				local lineToInsert = l
				if i == 1 and l:match("^%S") and preservedIndent ~= "" and not patch.content:match("^%s") then
					lineToInsert = preservedIndent .. l
				end
				table.insert(lines, s + i - 1, lineToInsert)
			end

		elseif op == "delete" then
			local s = math.max(1, patch.lineStart or 1)
			local e = math.min(#lines, patch.lineEnd or s)

			-- SAFETY: Check for potential global variables being deleted
			if patch.expectedContent then
				local globals = detectGlobalVariables(patch.expectedContent)
				if #globals > 0 then
					local globalNames = {}
					for _, g in ipairs(globals) do
						table.insert(globalNames, string.format("%s (line %d)", g.name, g.line))
					end
					return nil, string.format(
						"SAFETY WARNING in patch #%d (delete lines %d-%d): Potential global variables detected in code to delete:\n%s\n" ..
							"Deleting global variables can break other parts of the code. Verify these are safe to delete or use replace instead.",
						patchIndex, s, e, table.concat(globalNames, "\n")
					)
				end
			end

			if patch.expectedContent ~= nil then
				local actualLines = {}
				for i = s, e do
					table.insert(actualLines, lines[i] or "")
				end
				local actual = table.concat(actualLines, "\n")
				if normalizeForComparison(actual) ~= normalizeForComparison(patch.expectedContent) then
					return nil, string.format(
						"CONTENT MISMATCH in patch #%d (delete lines %d-%d).\n=== EXPECTED ===\n%s\n=== ACTUAL ===\n%s\n=== END ===\nThe script may have changed. Re-read the lines and retry.",
						patchIndex, s, e, patch.expectedContent, actual
					)
				end
			end

			for _ = s, e do
				if s <= #lines then
					table.remove(lines, s)
				end
			end
		end
	end

	-- Build final source and validate enhanced syntax
	local newSource = table.concat(lines, "\n")
	local syntaxValid, syntaxError = validateEnhancedSyntax(newSource, lines)
	if not syntaxValid then
		local basicValid, basicError = validateBasicSyntax(newSource)
		if not basicValid then
			return nil, string.format(
				"SYNTAX VALIDATION FAILED: %s\n" ..
					"The patch would create invalid syntax. Please review your changes and ensure all blocks are properly closed.",
				basicError or syntaxError
			)
		end
		log("WARN: Enhanced syntax validation failed (" .. tostring(syntaxError) .. "); proceeding with basic validation only.")
	end

	-- Apply changes with undo support
	local recording = recordUndo("MCP: Patch script " .. inst.Name)
	inst.Source = newSource

	-- Update ScriptEditorService document if script is open
	updateScriptEditorDocument(inst, newSource)

	finishUndo(recording, true)
	return { ok = true, newLineCount = #lines }
end

---------------------------------------------------------------------------
-- get_script_functions
---------------------------------------------------------------------------
local function getScriptFunctions(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local source = inst.Source or ""
	local lines  = string.split(source, "\n")
	local functions = {}

	for i, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$") or ""
		local name = nil
		local ftype = nil

		name = trimmed:match("^local%s+function%s+([%w_%.%:]+)%s*%(")
		if name then
			ftype = "local"
		end

		if not name then
			name = trimmed:match("^function%s+([%w_%.%:]+)%s*%(")
			if name then
				ftype = name:find(":") and "method" or "function"
			end
		end

		if not name then
			name = trimmed:match("^([%w_%.%:%[%]\"']+)%s*=%s*function%s*%(")
			if name then
				ftype = "assigned"
			end
		end

		if name and ftype then
			table.insert(functions, {
				name = name,
				line = i,
				type = ftype,
			})
		end
	end

	return {
		totalLines    = #lines,
		functionCount = #functions,
		functions     = functions,
	}
end

---------------------------------------------------------------------------
-- search_across_scripts
---------------------------------------------------------------------------
local function searchAcrossScripts(args)
	local ancestor
	if args.ancestorPath or args.ancestorPathArray then
		ancestor = resolveInstance({ path = args.ancestorPath, pathArray = args.ancestorPathArray })
	else
		ancestor = game
	end
	if not ancestor then return nil, "Ancestor not found" end

	local query = args.query
	if not query then return nil, "Missing query" end

	local usePattern          = args.usePattern or false
	local caseSensitive       = args.caseSensitive
	if caseSensitive == nil then caseSensitive = true end
	local maxScripts          = args.maxScripts or 200
	local maxMatchesPerScript = args.maxMatchesPerScript or 10

	local searchQuery = query
	if not caseSensitive then
		searchQuery = query:lower()
	end

	local scriptResults = {}
	local scriptsSearched = 0

	for _, inst in ipairs(ancestor:GetDescendants()) do
		if not inst:IsA("LuaSourceContainer") then continue end
		scriptsSearched = scriptsSearched + 1
		if #scriptResults >= maxScripts then continue end

		local source = inst.Source or ""
		local lines = string.split(source, "\n")
		local matches = {}

		for i, line in ipairs(lines) do
			local searchLine = caseSensitive and line or line:lower()
			local found
			if usePattern then
				found = string.find(searchLine, searchQuery)
			else
				found = string.find(searchLine, searchQuery, 1, true)
			end
			if found then
				table.insert(matches, { lineNumber = i, text = line })
				if #matches >= maxMatchesPerScript then break end
			end
		end

		if #matches > 0 then
			local info = serializeInstance(inst)
			info.matchCount = #matches
			info.matches    = matches
			table.insert(scriptResults, info)
		end
	end

	return {
		scriptsSearched    = scriptsSearched,
		scriptsWithMatches = #scriptResults,
		results            = scriptResults,
	}
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------
local function getSelection()
	return serializeInstances(Selection:Get())
end

---------------------------------------------------------------------------
-- ScriptEditorService handlers
---------------------------------------------------------------------------
local function openScript(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local line = args.line or 1
	local ok, err = pcall(function()
		ScriptEditorService:OpenScriptDocumentAsync(inst)
	end)
	if not ok then
		return nil, "Failed to open script: " .. tostring(err)
	end

	-- Try to navigate to the line if the document is open
	local doc = ScriptEditorService:FindScriptDocument(inst)
	if doc and line > 1 then
		pcall(function()
			doc:RequestSetSelectionAsync(line, 1, line, 1)
		end)
	end

	return { ok = true, scriptName = inst:GetFullName(), line = line }
end

local function getOpenScripts()
	local docs = ScriptEditorService:GetScriptDocuments()
	local result = {}
	for _, doc in ipairs(docs) do
		if not doc:IsCommandBar() then
			local script = doc:GetScript()
			if script then
				local info = serializeInstance(script)
				if info then
					info.isModified = doc.ViewingLine ~= nil -- rough heuristic; not perfect
					table.insert(result, info)
				end
			end
		end
	end
	return result
end

local function closeScript(args)
	local inst = resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local doc = ScriptEditorService:FindScriptDocument(inst)
	if not doc then
		return nil, "Script is not open in editor"
	end

	local ok, err = pcall(function()
		doc:CloseAsync()
	end)
	if not ok then
		return nil, "Failed to close script: " .. tostring(err)
	end

	return { ok = true }
end

---------------------------------------------------------------------------
-- ChangeHistoryService handlers
---------------------------------------------------------------------------
local function undo(args)
	local ok, err = pcall(function()
		ChangeHistoryService:Undo()
	end)
	if not ok then return nil, "Undo failed: " .. tostring(err) end
	return { ok = true }
end

local function redo(args)
	local ok, err = pcall(function()
		ChangeHistoryService:Redo()
	end)
	if not ok then return nil, "Redo failed: " .. tostring(err) end
	return { ok = true }
end

local function setWaypoint(args)
	local name = args.name or "MCP Waypoint"
	local recording = recordUndo(name)
	if recording then
		finishUndo(recording, true)
	end
	return { ok = true, name = name }
end

---------------------------------------------------------------------------
-- Extended studio helpers
---------------------------------------------------------------------------
local function compileLuaChunk(code, chunkName)
	if load then
		return load(code, chunkName, "t", _G)
	end
	if loadstring then
		local chunk, err = loadstring(code)
		if chunk and setfenv then
			setfenv(chunk, _G)
		end
		return chunk, err
	end
	return nil, "load/loadstring is unavailable in this Studio build"
end

local function argumentToString(value)
	if value == nil then
		return "nil"
	end
	if typeof(value) == "table" then
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(value)
		end)
		if ok then
			return encoded
		end
	end
	if typeof(value) == "userdata" then
		return tostring(value)
	end
	return tostring(value)
end

local function toStringList(pack)
	local output = {}
	for i = 1, pack.n do
		output[i] = argumentToString(pack[i])
	end
	return output
end

local function addToOutput(output, header, pack)
	local entries = toStringList(pack)
	output ..= header .. " " .. table.concat(entries, "\t") .. "\n"
	return output
end

local function restoreEnv(env, backup)
	for key, value in pairs(backup) do
		env[key] = value
	end
end

local function runChunkWithOutput(chunk)
	local output = ""
	local chunkEnv = (getfenv and getfenv(chunk)) or _G
	local backup = {
		print = chunkEnv.print,
		warn = chunkEnv.warn,
		error = chunkEnv.error,
	}

	local function addOutput(header, ...)
		return addToOutput(output, header, table.pack(...))
	end

	local function wrapFn(header, original)
		return function(...)
			output = addOutput(header, ...)
			if original then
				return original(...)
			end
		end
	end

	local function run()
		chunkEnv.print = wrapFn("[OUTPUT]", backup.print or print)
		chunkEnv.warn = wrapFn("[WARNING]", backup.warn or warn)
		chunkEnv.error = function(...)
			output = addOutput("[ERROR]", ...)
			local errFn = backup.error or error
			return errFn(...)
		end

		local results = table.pack(chunk())
		if results.n > 0 then
			output = addOutput("[RETURNED RESULTS]", table.unpack(results, 1, results.n))
		end
		return output
	end

	local ok, err = pcall(run)
	restoreEnv(chunkEnv, backup)
	if not ok then
		output = addOutput("[UNEXPECTED ERROR]", err)
	end
	return output
end

local function runCode(args)
	local code = args.code or args.script or args.source
	if not code or code == "" then return nil, "Missing code argument" end
	local chunk, err = compileLuaChunk(code, "MCP.run_code")
	if not chunk then return nil, err end
	return { result = runChunkWithOutput(chunk) }
end

local function insertModel(args)
	local assetCandidate = args.assetId or args.asset_id or args.id or args.asset
	local assetId = assetCandidate and tonumber(assetCandidate)
	if not assetId then return nil, "Missing assetId" end
	local recording = recordUndo("MCP: Insert asset " .. tostring(assetId))
	local ok, inserted = pcall(function() return InsertService:LoadAsset(assetId) end)
	if not ok then
		finishUndo(recording, false)
		return nil, tostring(inserted)
	end
	if not inserted then
		finishUndo(recording, false)
		return nil, "InsertService failed to return an asset"
	end
	inserted.Parent = workspace
	finishUndo(recording, true)
	return serializeInstance(inserted)
end

local function getConsoleOutput(args)
	local since = args.since or 0
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
		logs = result,
		count = #result,
		latestTimestamp = consoleLogs[#consoleLogs] and consoleLogs[#consoleLogs].timestamp,
	}
en

local function currentRunMode()
	return STUDIO_MODE
end

local function isStudioPlayMode(mode)
	mode = mode or currentRunMode()
	
	if mode == "start_play" then
		return true
	end
	
	return false
end

local function stopPlay()
	StudioTestService:EndTest({})
end

local function startPlay(): string?
	STUDIO_MODE = "start_play"
	task.spawn(function()
		StudioTestService:ExecutePlayModeAsync({})
	end)
	return {mode = "start_play", message = "Started play"}
end

local function stop(): string?
	stopPlay()
	STUDIO_MODE = "stop"
	return {mode = "stop", message = "Stopped play"}
end

local function runServer(): string?
	STUDIO_MODE = "run_server"
	task.spawn(function()
		StudioTestService:ExecuteRunModeAsync({})
	end)
	return {mode = "run_server", message = "Ran server"}
end

local function startStopPlay(args)
	local requested = args.mode or args.action or args.state or args.command or args.name
	
	if not requested then
		return nil, "Unknown Studio mode (supported: start_play, stop, run_server)"
	end
	
	if requested == "start_play" then
		return startPlay()
	elseif requested == "run_server" then
		return runServer()
	elseif requested == "stop" then
		return stop()
	end
	
	return nil, "Unknown Studio mode (supported: start_play, stop, run_server)"
end

local function getStudioMode()
	local mode = currentRunMode()
	return {
		mode = mode or "Unknown",
		isPlay = isStudioPlayMode(mode),
	}
end

local function runScriptInPlayMode(args)
	if not isStudioPlayMode() then return nil, "Studio must be in Play or Run mode" end
	local code = args.code or args.script or args.source
	if not code or code == "" then return nil, "Missing code argument" end
	local chunk, err = compileLuaChunk(code, "MCP.run_script_in_play_mode")
	if not chunk then return nil, err end
	return { result = runChunkWithOutput(chunk) }
end

---------------------------------------------------------------------------
-- Handler dispatch table
---------------------------------------------------------------------------
local handlers = {
	-- Instance
	list_services     = getServices,
	get_children      = getChildren,
	get_descendants   = getDescendants,
	get_instance      = getInstance,
	find_instances    = findInstances,
	get_tree          = getTree,
	create_instance   = createInstance,
	delete_instance   = deleteInstance,
	clone_instance    = cloneInstance,
	reparent_instance = reparentInstance,
	set_name          = setName,
	select_instance   = selectInstance,
	-- Properties / Attributes
	get_properties    = getProperties,

	get_all_properties = getAllProperties,
	set_properties    = setProperties,
	get_attributes    = getAttributes,
	set_attributes    = setAttributes,
	-- Tags
	get_tags          = getTags,
	add_tag           = addTag,
	remove_tag        = removeTag,
	-- Scripts
	read_script            = readScript,
	write_script           = writeScript,
	patch_script           = patchScript,
	get_script_lines       = getScriptLines,
	search_script          = searchScript,
	get_script_functions   = getScriptFunctions,
	search_across_scripts  = searchAcrossScripts,
	-- Extended helpers
	run_code                = runCode,
	insert_model            = insertModel,
	get_console_output      = getConsoleOutput,
	start_stop_play         = startStopPlay,
	get_studio_mode         = getStudioMode,
	run_script_in_play_mode = runScriptInPlayMode,
	-- Selection
	get_selection          = getSelection,
	-- ScriptEditorService
	open_script            = openScript,
	get_open_scripts       = getOpenScripts,
	close_script           = closeScript,
	-- ChangeHistoryService
	undo                   = undo,
	redo                   = redo,
	set_waypoint           = setWaypoint,
}

---------------------------------------------------------------------------
-- Polling
---------------------------------------------------------------------------
local running       = false
local connected     = false
local jobsCompleted = 0

local function updateStatus(text)
	statusLabel.Text = text
end

local function updateJobCount()
	jobCountLabel.Text = "Jobs completed: " .. tostring(jobsCompleted)
end

local function postResultWithRetry(payload)
	for attempt = 1, RESULT_RETRY_MAX do
		local postOk, postResp = pcall(function()
			return request("POST", BRIDGE_URL .. "/result", payload)
		end)
		if postOk and postResp and postResp.Success then
			return true
		end
		if attempt < RESULT_RETRY_MAX then
			log("POST result attempt " .. attempt .. " failed, retrying...")
			task.wait(RESULT_RETRY_DELAY)
		else
			log("POST result FAILED after " .. RESULT_RETRY_MAX .. " attempts")
			if not postOk then
				log("  Error: " .. tostring(postResp))
			elseif postResp then
				log("  HTTP " .. tostring(postResp.StatusCode))
			end
		end
	end
	return false
end

local function pollLoop()
	local consecutiveErrors = 0

	while running do
		local pollUrl = BRIDGE_URL .. "/poll?client_id=" .. CLIENT_ID
		local ok, resp = pcall(function()
			return request("GET", pollUrl)
		end)

		if ok and resp and resp.Success then
			consecutiveErrors = 0

			if not connected then
				connected = true
				updateStatus("Status: running (connected)")
				log("Connected to bridge")
			end

			local decodeOk, payload = pcall(function()
				return HttpService:JSONDecode(resp.Body)
			end)

			if decodeOk and payload and payload.job then
				local job = payload.job
				log("Job: " .. tostring(job.type) .. " [" .. tostring(job.job_id) .. "]")

				local handler = handlers[job.type]
				local result, err
				if handler then
					local okH, hResult, hErr = pcall(handler, job.args or {})
					if okH then
						result, err = hResult, hErr
					else
						err = tostring(hResult)
						log("Handler error (" .. tostring(job.type) .. "): " .. err)
					end
				else
					err = "Unknown job type: " .. tostring(job.type)
					log(err)
				end

				local resPayload = {
					job_id = job.job_id,
					ok     = err == nil,
					result = result,
					error  = err,
				}

				postResultWithRetry(resPayload)

				jobsCompleted = jobsCompleted + 1
				updateJobCount()
			end
			task.wait(POLL_DELAY)
		else
			consecutiveErrors = consecutiveErrors + 1

			if connected then
				connected = false
				if not ok then
					log("Connection lost: " .. tostring(resp))
				elseif resp then
					log("Connection lost (HTTP " .. tostring(resp.StatusCode) .. ")")
				end
				updateStatus("Status: running (connection lost)")
			end

			local delay = math.min(ERROR_DELAY * consecutiveErrors, 10)
			task.wait(delay)
		end
	end
	updateStatus("Status: stopped")
end

local function startPolling()
	if running then
		log("Already running")
		return
	end
	if not ensureHttpEnabled() then
		updateStatus("Status: ERROR – HttpEnabled is false")
		return
	end
	running   = true
	connected = false
	updateStatus("Status: starting...")
	log("Starting → " .. BRIDGE_URL)
	task.spawn(pollLoop)
end

local function stopPolling()
	if not running then return end
	running = false
	log("Polling stopped")
end

startButton.MouseButton1Click:Connect(startPolling)
stopButton.MouseButton1Click:Connect(stopPolling)

log("MCP Bridge plugin v0.5 loaded. Press 'Start Bridge Polling' to begin.")
