-- Utils/Syntax.luau
-- Lua script syntax validation utilities

local Syntax = {}

-- Basic bracket/parenthesis balance check
function Syntax.validateBasicSyntax(text)
	local openParen, openBrace, openBracket = 0, 0, 0
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

-- Get indentation (leading whitespace) from a line
function Syntax.getIndentation(line)
	return line:match("^(%s*)") or ""
end

-- Detect potential global variable declarations
function Syntax.detectGlobalVariables(code)
	local globals = {}
	local lines = string.split(code, "\n")
	for i, line in ipairs(lines) do
		local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
		local globalMatch = trimmed:match("^([%w_][%w_%.%:]*)%s*=")
		if globalMatch and not trimmed:match("^local%s") and not trimmed:match("^function%s") then
			if not globalMatch:match("^_") and not globalMatch:match("%.") then
				table.insert(globals, { name = globalMatch, line = i })
			end
		end
	end
	return globals
end

local function findCommentStartOutsideStrings(s)
	local inStr, strChar = false, nil
	local i = 1
	while i <= #s - 1 do
		local ch = s:sub(i, i)
		if inStr then
			if ch == "\\" then i = i + 1
			elseif ch == strChar then inStr, strChar = false, nil end
		else
			if ch == "'" or ch == '"' then inStr, strChar = true, ch
			elseif ch == "-" and s:sub(i, i + 1) == "--" then return i end
		end
		i = i + 1
	end
	return nil
end

-- Enhanced syntax validation: checks block structures and keyword balance
function Syntax.validateEnhancedSyntax(text, lines)
	local basicValid, basicError = Syntax.validateBasicSyntax(text)
	if not basicValid then return false, basicError end

	local linesArray = lines or string.split(text, "\n")
	local blockStack = {}
	local inString, stringChar = false, nil
	local inComment = false

	local functionCount, endCount, ifCount, thenCount = 0, 0, 0, 0
	local doCount, repeatCount, untilCount, whileCount = 0, 0, 0, 0

	for lineNum, line in ipairs(linesArray) do
		local codeLine = line

		local singleQuotes = select(2, line:gsub("'", "'"))
		local doubleQuotes = select(2, line:gsub('"', '"'))
		if singleQuotes % 2 == 1 then inString = not inString; stringChar = "'" end
		if doubleQuotes % 2 == 1 and not inString then inString = not inString; stringChar = '"' end

		if codeLine:match("%-%-%[%[") then inComment = true end
		if codeLine:match("%]%]%-%-") then inComment = false end

		if not inComment then
			local commentStart = findCommentStartOutsideStrings(codeLine)
			if commentStart then codeLine = codeLine:sub(1, commentStart - 1) end
		end

		local trimmed = codeLine:gsub("^%s+", ""):gsub("%s+$", "")
		if not inComment and trimmed ~= "" and not inString then
			if trimmed:match("^function%s") or trimmed:match("^local%s+function%s") or
				trimmed:match("%s*=%s*function%s*%(") or trimmed:match("^[%w_%.%:]+%s*=%s*function%s*%(") then
				functionCount = functionCount + 1
				table.insert(blockStack, { type = "function", line = lineNum })
			end
			if trimmed:match("^if%s") or trimmed:match("%s+if%s") then
				ifCount = ifCount + 1
				table.insert(blockStack, { type = "if", line = lineNum })
			end
			if trimmed:match("%s+then%s") or trimmed:match("%s+then%s*$") or trimmed:match("^then%s") then
				thenCount = thenCount + 1
			end
			if trimmed:match("%s+do%s*$") or trimmed:match("%s+do%s+") or trimmed:match("^do%s*$") then
				doCount = doCount + 1
				table.insert(blockStack, { type = "do", line = lineNum })
			end
			if trimmed:match("^while%s") or trimmed:match("%s+while%s") then
				whileCount = whileCount + 1
			end
			if trimmed:match("^repeat%s") or trimmed:match("%s+repeat%s") then
				repeatCount = repeatCount + 1
				table.insert(blockStack, { type = "repeat", line = lineNum })
			end
			if trimmed:match("^until%s") or trimmed:match("%s+until%s") then
				untilCount = untilCount + 1
				for i = #blockStack, 1, -1 do
					if blockStack[i].type == "repeat" then table.remove(blockStack, i); break end
				end
			end
			if trimmed:match("^end%s*$") or trimmed:match("^end%s*,") or trimmed:match("^end%s*%)") or trimmed:match("^end%s+") then
				endCount = endCount + 1
				if #blockStack > 0 then table.remove(blockStack) end
			end
		end

		if not inComment and trimmed ~= "" then
			local lastChar = trimmed:sub(-1)
			if lastChar and (lastChar == "+" or lastChar == "-" or lastChar == "*" or lastChar == "/" or
				lastChar == "=" or lastChar == ">" or lastChar == "<" or lastChar == "&" or lastChar == "|") then
				if not inString then
					if lineNum < #linesArray then
						local nextTrimmed = (linesArray[lineNum + 1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
						if not nextTrimmed:match("^[%w_%[%\"']") and not nextTrimmed:match("^%(") and not nextTrimmed:match("^%-%-") then
							return false, string.format("Potential incomplete statement at line %d: ends with operator '%s'", lineNum, lastChar)
						end
					else
						return false, string.format("Incomplete statement at line %d (last line): ends with operator '%s'", lineNum, lastChar)
					end
				end
			end
		end
	end

	if #blockStack > 0 then
		local unmatched = {}
		for _, block in ipairs(blockStack) do
			table.insert(unmatched, string.format("%s (line %d)", block.type, block.line))
		end
		return false, string.format("Unclosed blocks: %s. Missing 'end' statements.", table.concat(unmatched, ", "))
	end

	local blockStartCount = functionCount + ifCount + doCount
	if math.abs(blockStartCount - endCount) > 10 then
		return false, string.format("Unmatched block starts vs ends: %d starters, %d ends", blockStartCount, endCount)
	end
	if math.abs(ifCount - thenCount) > 5 then
		return false, string.format("Unmatched if/then: %d ifs, %d thens", ifCount, thenCount)
	end
	if doCount > 0 and math.abs(doCount - endCount) > 5 then
		local availableEnds = endCount - functionCount
		if doCount > availableEnds then
			return false, string.format("Unmatched do/end: %d do statements, %d ends available", doCount, availableEnds)
		end
	end
	if math.abs(repeatCount - untilCount) > 0 then
		return false, string.format("Unmatched repeat/until: %d repeat, %d until", repeatCount, untilCount)
	end

	return true
end

return Syntax
