-- Utils/PluginUtils.luau
-- Cross-boundary signal helpers using plugin settings as a shared key-value store.
-- The plugin (edit-mode) writes keys; injected scripts (play-mode) read them.

local PluginUtils = {}

-- plugin is the global Studio plugin object, available in the plugin context.
-- We guard against it being nil so this module can be required safely in any context.
local _plugin = (typeof(plugin) ~= "nil") and plugin or nil

function PluginUtils.setSettings(key: string, value: any)
	if not _plugin then
		warn("[PluginUtils] setSettings called outside plugin context – key: " .. tostring(key))
		return
	end
	_plugin:SetSetting(key, value)
end

function PluginUtils.getSettings(key: string): any
	if not _plugin then return nil end
	return _plugin:GetSetting(key)
end

return PluginUtils
