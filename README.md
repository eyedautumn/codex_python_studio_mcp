# Roblox Studio MCP Bridge
![Build](https://github.com/eyedautumn/codex_python_studio_mcp/actions/workflows/build.yml/badge.svg)
![Version](https://img.shields.io/github/v/release/eyedautumn/python_roblox_studio_mcp?style=flat-square&display_name=tag)

A Roblox Studio plugin that bridges Studio to an external MCP (Model Context Protocol) server over HTTP, enabling AI tools to read and manipulate your game's hierarchy, scripts, properties, and more.

## Installation

### Option A — Installer script (recommended)

1. Go to the [**Releases**](../../releases) page and download `install.py` (requires Python 3.8+) **or** a standalone executable for your platform:
   - **Linux:** `install-linux`
   - **macOS:** `install-macos` *(right-click → Open on first run to bypass Gatekeeper)*
   - **Windows:** `install-windows.exe`
2. Run the installer — it will walk you through plugin placement and MCP server registration for Claude Desktop, Claude Code, or OpenAI Codex.
3. Open Roblox Studio. The **Roblox MCP** toolbar button will appear.
4. Enable **HTTP Requests** in *Game Settings → Security* (the plugin will attempt this automatically).
5. Click **Start Bridge Polling** in the plugin widget.

### Option B — Manual plugin install

1. Go to the [**Releases**](../../releases) page and download `RobloxMcpBridge.rbxm`.  
   — or —  
   Download the latest build artifact from [**Actions**](../../actions) (no release required).
2. Place `RobloxMcpBridge.rbxm` in your Roblox **Plugins** folder:
   - **Windows:** `%LOCALAPPDATA%\Roblox\Plugins\`
   - **macOS:** `~/Documents/Roblox/Plugins/`
   - **Linux (Sober/Flatpak):** `~/.var/app/org.vinegarhq.Sober/data/roblox/Plugins/`
   - **Linux (Vinegar/Wine):** `~/.var/app/org.vinegarhq.Vinegar/data/prefixes/studio/drive_c/users/<user>/AppData/Local/Roblox/Plugins/`
3. Open Roblox Studio. The **Roblox MCP** toolbar button will appear.
4. Enable **HTTP Requests** in *Game Settings → Security* (the plugin will attempt this automatically).
5. Start your MCP bridge server on `http://127.0.0.1:28650`.
6. Click **Start Bridge Polling** in the plugin widget.

### Option C — Register MCP server manually

If you already have the plugin installed, add this to your AI client's config:

```json
{
  "mcpServers": {
    "roblox-studio-mcp": {
      "command": "python3",
      "args": ["/path/to/roblox_mcp_server.py"]
    }
  }
}
```

- **Claude Desktop:** `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows)
- **Claude Code:** `claude mcp add roblox-studio-mcp --scope user -- python3 /path/to/roblox_mcp_server.py`
- **OpenAI Codex:** `~/.codex/config.toml`

## Building locally (Rojo)

```bash
# Install Rojo (https://rojo.space)
rojo build default.project.json --output RobloxMcpBridge.rbxm
```

The `default.project.json` maps `src/plugin/main.luau` as the root Script, with `Tools/` and `Utils/` as child ModuleScripts — matching how `require(script.Tools.*)` resolves at runtime.

## Project Structure

```
src/plugin/
├── main.luau               # Entry point: UI, polling loop, handler dispatch
├── Tools/
│   ├── InstanceTools.luau  # Instance hierarchy: create, delete, clone, find, tree
│   ├── PropertyTools.luau  # Properties and attributes: get/set
│   ├── TagTools.luau       # CollectionService tags: get/add/remove
│   ├── ScriptTools.luau    # Script I/O: read, write, patch, search, functions
│   ├── EditorTools.luau    # ScriptEditorService: open, list, close scripts
│   ├── HistoryTools.luau   # ChangeHistoryService: undo, redo, waypoints
│   └── StudioTools.luau    # Play mode, run code, insert model, console output
└── Utils/
    ├── Types.luau           # Rich type serialization / deserialization
    ├── Instances.luau       # Instance ID map and path resolution helpers
    ├── History.luau         # ChangeHistoryService recording helpers
    ├── Syntax.luau          # Lua syntax validation utilities
    └── Logger.luau          # Widget log panel helper
```

## Supported Tools

| Category | Tools |
|---|---|
| Instance | `list_services`, `get_children`, `get_descendants`, `get_instance`, `find_instances`, `get_tree`, `create_instance`, `delete_instance`, `clone_instance`, `reparent_instance`, `set_name`, `select_instance`, `get_selection` |
| Properties | `get_properties`, `get_all_properties`, `set_properties`, `get_attributes`, `set_attributes` |
| Tags | `get_tags`, `add_tag`, `remove_tag` |
| Scripts | `read_script`, `write_script`, `patch_script`, `get_script_lines`, `search_script`, `get_script_functions`, `search_across_scripts` |
| Editor | `open_script`, `get_open_scripts`, `close_script` |
| History | `undo`, `redo`, `set_waypoint` |
| Studio | `run_code`, `insert_model`, `get_console_output`, `start_stop_play`, `get_studio_mode`, `run_script_in_play_mode` |

## Adding New Tools

1. Create (or edit) the appropriate module in `src/plugin/Tools/`.
2. Export your handler as a named function from the module.
3. Register it in the `handlers` table in `main.luau`.
