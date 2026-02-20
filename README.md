# Roblox Studio MCP Bridge Plugin

A Roblox Studio plugin that bridges Studio to an external MCP (Model Context Protocol) server over HTTP, enabling AI tools to read and manipulate your game's hierarchy, scripts, properties, and more.

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

## Setup

1. Copy the contents of `src/plugin/` into your Roblox Plugins folder (preserving the `Tools/` and `Utils/` subdirectories).
2. Rename `main.luau` to a `.lua` file if your Studio version requires it, or use a plugin build tool like [Rojo](https://rojo.space/).
3. Open Roblox Studio. The **Roblox MCP** toolbar button will appear.
4. Enable **HTTP Requests** in *Game Settings → Security* (the plugin will attempt this automatically).
5. Start your MCP bridge server on `http://127.0.0.1:28650`.
6. Click **Start Bridge Polling** in the plugin widget.

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
