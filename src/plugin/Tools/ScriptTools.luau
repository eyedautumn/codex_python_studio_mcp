-- Tools/ScriptTools.luau
-- Tools for reading, writing, patching, and searching Lua scripts

local ScriptEditorService = game:GetService("ScriptEditorService")

local Instances = require(script.Parent.Parent.Utils.Instances)
local History   = require(script.Parent.Parent.Utils.History)
local Syntax    = require(script.Parent.Parent.Utils.Syntax)

local ScriptTools = {}

-- Ensure open ScriptEditorService documents reflect source changes
local function updateScriptEditorDocument(inst)
	local doc = ScriptEditorService:FindScriptDocument(inst)
	if doc then
		task.spawn(function()
			task.wait(0.01)
			pcall(function()
				local currentDoc = ScriptEditorService:FindScriptDocument(inst)
				if currentDoc then local _ = currentDoc:GetScript() end
			end)
		end)
	end
end

-- Normalize text for comparison (trim trailing whitespace and trailing blank lines)
local function normalizeForComparison(text)
	local result = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		table.insert(result, (line:gsub("%s+$", "")))
	end
	while #result > 0 and result[#result] == "" do table.remove(result) end
	return table.concat(result, "\n")
end

function ScriptTools.read_script(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end
	return { source = inst.Source }
end

function ScriptTools.write_script(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local newSource = args.source or ""
	local syntaxValid, syntaxError = Syntax.validateBasicSyntax(newSource)
	if not syntaxValid then
		return nil, string.format("SYNTAX VALIDATION FAILED: %s\nThe script source has invalid syntax.", syntaxError)
	end

	local recording = History.recordUndo("MCP: Write script " .. inst.Name)
	inst.Source = newSource
	updateScriptEditorDocument(inst)
	History.finishUndo(recording, true)
	return { ok = true }
end

function ScriptTools.get_script_lines(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local lines = string.split(inst.Source or "", "\n")
	local startLine, endLine = args.startLine, args.endLine
	if not startLine and not endLine then return { totalLines = #lines } end

	startLine = math.max(1, math.min(startLine or 1, #lines))
	endLine   = math.max(startLine, math.min(endLine or #lines, #lines))

	local result = {}
	for i = startLine, endLine do
		table.insert(result, { lineNumber = i, text = lines[i] })
	end
	return { totalLines = #lines, startLine = startLine, endLine = endLine, lines = result }
end

function ScriptTools.search_script(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local lines = string.split(inst.Source or "", "\n")
	local query = args.query
	if not query then return nil, "Missing query" end

	local usePattern    = args.usePattern or false
	local caseSensitive = args.caseSensitive
	if caseSensitive == nil then caseSensitive = true end
	local contextLines = args.contextLines or 0
	local maxResults   = args.maxResults or 50

	local searchQuery = caseSensitive and query or query:lower()
	local matchedNums = {}
	for i, line in ipairs(lines) do
		local searchLine = caseSensitive and line or line:lower()
		local found = usePattern and string.find(searchLine, searchQuery) or string.find(searchLine, searchQuery, 1, true)
		if found then
			table.insert(matchedNums, i)
			if #matchedNums >= maxResults then break end
		end
	end

	local matchSet, included, results = {}, {}, {}
	for _, n in ipairs(matchedNums) do matchSet[n] = true end
	for _, num in ipairs(matchedNums) do
		local s, e = math.max(1, num - contextLines), math.min(#lines, num + contextLines)
		for i = s, e do
			if not included[i] then
				included[i] = true
				table.insert(results, { lineNumber = i, text = lines[i], isMatch = matchSet[i] == true })
			end
		end
	end
	table.sort(results, function(a, b) return a.lineNumber < b.lineNumber end)
	return { totalLines = #lines, matchCount = #matchedNums, results = results }
end

function ScriptTools.get_script_functions(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local lines = string.split(inst.Source or "", "\n")
	local functions = {}
	for i, line in ipairs(lines) do
		local trimmed = line:match("^%s*(.-)%s*$") or ""
		local name, ftype

		name = trimmed:match("^local%s+function%s+([%w_%.%:]+)%s*%(")
		if name then ftype = "local" end

		if not name then
			name = trimmed:match("^function%s+([%w_%.%:]+)%s*%(")
			if name then ftype = name:find(":") and "method" or "function" end
		end
		if not name then
			name = trimmed:match("^([%w_%.%:%[%]\"']+)%s*=%s*function%s*%(")
			if name then ftype = "assigned" end
		end

		if name and ftype then
			table.insert(functions, { name = name, line = i, type = ftype })
		end
	end

	return { totalLines = #lines, functionCount = #functions, functions = functions }
end

function ScriptTools.search_across_scripts(args)
	local ancestor
	if args.ancestorPath or args.ancestorPathArray then
		ancestor = Instances.resolveInstance({ path = args.ancestorPath, pathArray = args.ancestorPathArray })
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

	local searchQuery    = caseSensitive and query or query:lower()
	local scriptResults  = {}
	local scriptsSearched = 0

	for _, inst in ipairs(ancestor:GetDescendants()) do
		if not inst:IsA("LuaSourceContainer") then continue end
		scriptsSearched = scriptsSearched + 1
		if #scriptResults >= maxScripts then continue end

		local lines = string.split(inst.Source or "", "\n")
		local matches = {}
		for i, line in ipairs(lines) do
			local searchLine = caseSensitive and line or line:lower()
			local found = usePattern and string.find(searchLine, searchQuery) or string.find(searchLine, searchQuery, 1, true)
			if found then
				table.insert(matches, { lineNumber = i, text = line })
				if #matches >= maxMatchesPerScript then break end
			end
		end

		if #matches > 0 then
			local info = Instances.serializeInstance(inst)
			info.matchCount = #matches
			info.matches    = matches
			table.insert(scriptResults, info)
		end
	end

	return { scriptsSearched = scriptsSearched, scriptsWithMatches = #scriptResults, results = scriptResults }
end

function ScriptTools.patch_script(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local lines   = string.split(inst.Source or "", "\n")
	local patches = args.patches or {}

	for patchIndex, patch in ipairs(patches) do
		local op = patch.op

		if op == "append" then
			for _, l in ipairs(string.split(patch.content or "", "\n")) do
				table.insert(lines, l)
			end

		elseif op == "prepend" then
			local newLines = string.split(patch.content or "", "\n")
			for i = #newLines, 1, -1 do table.insert(lines, 1, newLines[i]) end

		elseif op == "insert" then
			local at = math.max(1, math.min(patch.lineStart or 1, #lines + 1))
			if patch.expectedContext == nil then
				return nil, string.format(
					"SAFETY ERROR in patch #%d (insert at line %d): 'expectedContext' is REQUIRED for insert operations.",
					patchIndex, at
				)
			end
			local contextLine = at > 1 and lines[at - 1] or ""
			if normalizeForComparison(contextLine) ~= normalizeForComparison(patch.expectedContext) then
				return nil, string.format(
					"CONTEXT MISMATCH in patch #%d (insert at line %d).\n=== EXPECTED ===\n%s\n=== ACTUAL ===\n%s",
					patchIndex, at, patch.expectedContext, contextLine
				)
			end
			local baseIndent = Syntax.getIndentation(contextLine)
			local newLines   = string.split(patch.content or "", "\n")
			for i, l in ipairs(newLines) do
				local lineToInsert = (l:match("^%S") and baseIndent ~= "") and (baseIndent .. l) or l
				table.insert(lines, at + i - 1, lineToInsert)
			end

		elseif op == "replace" then
			local s = math.max(1, patch.lineStart or 1)
			local e = math.min(#lines, patch.lineEnd or s)
			if patch.expectedContent ~= nil then
				local actual = table.concat({ table.unpack(lines, s, e) }, "\n")
				if normalizeForComparison(actual) ~= normalizeForComparison(patch.expectedContent) then
					return nil, string.format(
						"CONTENT MISMATCH in patch #%d (replace lines %d-%d).\n=== EXPECTED ===\n%s\n=== ACTUAL ===\n%s",
						patchIndex, s, e, patch.expectedContent, actual
					)
				end
			end
			local preservedIndent = s <= #lines and Syntax.getIndentation(lines[s]) or ""
			for _ = s, e do if s <= #lines then table.remove(lines, s) end end
			local newLines = string.split(patch.content or "", "\n")
			for i, l in ipairs(newLines) do
				local lineToInsert = (i == 1 and l:match("^%S") and preservedIndent ~= "" and not patch.content:match("^%s"))
					and (preservedIndent .. l) or l
				table.insert(lines, s + i - 1, lineToInsert)
			end

		elseif op == "delete" then
			local s = math.max(1, patch.lineStart or 1)
			local e = math.min(#lines, patch.lineEnd or s)
			if patch.expectedContent then
				local globals = Syntax.detectGlobalVariables(patch.expectedContent)
				if #globals > 0 then
					local names = {}
					for _, g in ipairs(globals) do table.insert(names, string.format("%s (line %d)", g.name, g.line)) end
					return nil, string.format(
						"SAFETY WARNING in patch #%d (delete lines %d-%d): Potential globals detected:\n%s",
						patchIndex, s, e, table.concat(names, "\n")
					)
				end
				local actual = table.concat({ table.unpack(lines, s, e) }, "\n")
				if normalizeForComparison(actual) ~= normalizeForComparison(patch.expectedContent) then
					return nil, string.format(
						"CONTENT MISMATCH in patch #%d (delete lines %d-%d).\n=== EXPECTED ===\n%s\n=== ACTUAL ===\n%s",
						patchIndex, s, e, patch.expectedContent, actual
					)
				end
			end
			for _ = s, e do if s <= #lines then table.remove(lines, s) end end
		end
	end

	local newSource = table.concat(lines, "\n")
	local syntaxValid, syntaxError = Syntax.validateEnhancedSyntax(newSource, lines)
	if not syntaxValid then
		local basicValid, basicError = Syntax.validateBasicSyntax(newSource)
		if not basicValid then
			return nil, string.format("SYNTAX VALIDATION FAILED: %s", basicError or syntaxError)
		end
		warn("[MCP Bridge] WARN: Enhanced syntax validation failed (" .. tostring(syntaxError) .. "); proceeding with basic validation only.")
	end

	local recording = History.recordUndo("MCP: Patch script " .. inst.Name)
	inst.Source = newSource
	updateScriptEditorDocument(inst)
	History.finishUndo(recording, true)
	return { ok = true, newLineCount = #lines }
end

return ScriptTools
