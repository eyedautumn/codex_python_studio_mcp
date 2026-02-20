-- Utils/Logger.luau
-- Log output helpers (widget log panel + warn)

local MAX_LOG_LINES = 50

local Logger = {}
Logger.__index = Logger

function Logger.new(logFrame)
	local self = setmetatable({}, Logger)
	self.logFrame = logFrame
	self.logLines = 0
	return self
end

function Logger:log(msg)
	local text = os.date("[%H:%M:%S] ") .. tostring(msg)
	warn("[MCP Bridge] " .. tostring(msg))

	self.logLines = self.logLines + 1
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
	label.LayoutOrder            = self.logLines
	label.Parent                 = self.logFrame

	local children = self.logFrame:GetChildren()
	local labels = {}
	for _, c in ipairs(children) do
		if c:IsA("TextLabel") then table.insert(labels, c) end
	end
	if #labels > MAX_LOG_LINES then
		table.sort(labels, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, #labels - MAX_LOG_LINES do labels[i]:Destroy() end
	end
end

return Logger
