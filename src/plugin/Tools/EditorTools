-- Tools/EditorTools.luau
-- Tools for managing open scripts in the ScriptEditorService

local ScriptEditorService = game:GetService("ScriptEditorService")

local Instances = require(script.Parent.Parent.Utils.Instances)

local EditorTools = {}

function EditorTools.open_script(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local line = args.line or 1
	local ok, err = pcall(function() ScriptEditorService:OpenScriptDocumentAsync(inst) end)
	if not ok then return nil, "Failed to open script: " .. tostring(err) end

	local doc = ScriptEditorService:FindScriptDocument(inst)
	if doc and line > 1 then
		pcall(function() doc:RequestSetSelectionAsync(line, 1, line, 1) end)
	end

	return { ok = true, scriptName = inst:GetFullName(), line = line }
end

function EditorTools.get_open_scripts()
	local docs = ScriptEditorService:GetScriptDocuments()
	local result = {}
	for _, doc in ipairs(docs) do
		if not doc:IsCommandBar() then
			local script = doc:GetScript()
			if script then
				local info = Instances.serializeInstance(script)
				if info then
					info.isModified = doc.ViewingLine ~= nil
					table.insert(result, info)
				end
			end
		end
	end
	return result
end

function EditorTools.close_script(args)
	local inst = Instances.resolveInstance(args)
	if not inst then return nil, "Instance not found" end
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end

	local doc = ScriptEditorService:FindScriptDocument(inst)
	if not doc then return nil, "Script is not open in editor" end

	local ok, err = pcall(function() doc:CloseAsync() end)
	if not ok then return nil, "Failed to close script: " .. tostring(err) end
	return { ok = true }
end

return EditorTools
