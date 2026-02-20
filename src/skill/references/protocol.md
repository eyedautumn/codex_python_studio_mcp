Overview
The bridge is split into two parts:

MCP server (Python) that exposes tools to the AI client via JSON-RPC over stdio.
Roblox Studio plugin (Lua) that polls the MCP server over HTTP and executes jobs.
The MCP server runs a threaded HTTP server (one thread per request) so that long-poll connections from the plugin do not block result submissions or other requests.

What's New in v0.5
Rich type support – Properties and attributes now use _type objects for complex Roblox types (Color3, Vector3, CFrame, UDim2, BrickColor, EnumItem, NumberRange, etc.).
ScriptEditorService integration – Open, close, and list scripts in the Studio script editor.
ChangeHistoryService integration – Undo, redo, and set named waypoints for grouping changes.
Connection Model
The plugin polls GET /poll in a tight loop. The server holds each poll for up to --poll-timeout seconds (default 5) before returning an empty response.
Each poll marks the client as "seen". The server considers a client connected if it was seen within the last 15 seconds.
Before enqueuing a job, the server checks whether the target client is connected. If not, the tool call fails immediately with a descriptive error instead of waiting for the full job timeout.
The plugin retries failed POST /result submissions up to 3 times with a 0.5-second delay between attempts.
On connection errors, the plugin uses exponential backoff (up to 10 seconds) to avoid spamming.
HTTP Endpoints (Plugin ↔ Server)
GET /ping?client_id=studio
Health check. Also marks the client as seen.

JSON

{ "ok": true, "server_time": 1717000000.0 }
GET /health
Quick server health check that does not block and does not require a client ID.

JSON

{ "ok": true, "uptime": 1717000000.0 }
GET /poll?client_id=studio
Poll endpoint. The server holds the request for up to --poll-timeout seconds (default 5). Returns a job when one is available, or { "ok": true, "job": null } on timeout.

JSON

{
  "ok": true,
  "job": {
    "job_id": "job_a1b2c3d4e5f6",
    "type": "get_children",
    "args": { "path": "Workspace" },
    "created_at": 1717000000.0
  }
}
POST /result
Plugin posts results back for a given job. The plugin retries this up to 3 times on failure.

JSON

{
  "job_id": "job_a1b2c3d4e5f6",
  "ok": true,
  "result": { ... }
}
On error:

JSON

{
  "job_id": "job_...",
  "ok": false,
  "error": "Instance not found"
}
Job Format
JSON

{
  "job_id": "job_<uuid_hex_12>",
  "type": "<handler_name>",
  "args": { ... },
  "created_at": 1717000000.0
}
Job IDs use UUID4 hex prefixes to avoid collisions under concurrent use.

If a job times out (Studio never picks it up), the server removes it from the pending queue to prevent stale job buildup.

Instance Resolution
The plugin resolves instances in this priority order:

id – a GetDebugId() string cached by the plugin from prior calls. The plugin validates that cached IDs still reference live instances (checks that inst.Parent is accessible); stale entries are removed.
pathArray – array of names, e.g. ["Workspace", "Folder", "Part"]. First element is checked as a service name.
path – dot-separated string, e.g. "Workspace.Folder.Part". Leading "game." is stripped automatically.
Prefer pathArray for reliability. Use id for repeat operations on the same object. path is convenient but breaks on names containing dots.

Rich Type System
Reading Properties and Attributes
When reading properties or attributes via get_properties or get_attributes, complex Roblox types are returned as objects with a _type field:

JSON

{
  "Color": { "_type": "Color3", "r": 255, "g": 0, "b": 0 },
  "Position": { "_type": "Vector3", "x": 10, "y": 5, "z": -3 },
  "CFrame": { "_type": "CFrame", "components": [10, 5, -3, 1, 0, 0, 0, 1, 0, 0, 0, 1] },
  "Size": { "_type": "UDim2", "xScale": 0, "xOffset": 100, "yScale": 0, "yOffset": 50 },
  "Material": { "_type": "EnumItem", "enumType": "Material", "name": "Neon" },
  "BrickColor": { "_type": "BrickColor", "name": "Really red" },
  "Range": { "_type": "NumberRange", "min": 0, "max": 10 }
}
Simple types (string, number, boolean) are returned directly.

Writing Properties and Attributes
When setting properties via set_properties or attributes via set_attributes, use the same _type object format for complex types:

_type	Fields	Example
Color3	r, g, b (0–255)	{"_type":"Color3","r":255,"g":0,"b":0}
Vector3	x, y, z	{"_type":"Vector3","x":1,"y":2,"z":3}
Vector2	x, y	{"_type":"Vector2","x":0.5,"y":0.5}
CFrame	components (12-element array: x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22)	{"_type":"CFrame","components":[0,5,0,1,0,0,0,1,0,0,0,1]}
UDim2	xScale, xOffset, yScale, yOffset	{"_type":"UDim2","xScale":0,"xOffset":100,"yScale":0,"yOffset":50}
UDim	scale, offset	{"_type":"UDim","scale":0.5,"offset":10}
BrickColor	name	{"_type":"BrickColor","name":"Really red"}
EnumItem	enumType, name	{"_type":"EnumItem","enumType":"Material","name":"Neon"}
NumberRange	min, max	{"_type":"NumberRange","min":0,"max":10}
NumberSequence	keypoints (array of {time, value, envelope})	{"_type":"NumberSequence","keypoints":[{"time":0,"value":0,"envelope":0},{"time":1,"value":1,"envelope":0}]}
ColorSequence	keypoints (array of {time, color:{r,g,b}})	{"_type":"ColorSequence","keypoints":[{"time":0,"color":{"r":255,"g":0,"b":0}},{"time":1,"color":{"r":0,"g":0,"b":255}}]}
Rect	minX, minY, maxX, maxY	{"_type":"Rect","minX":0,"minY":0,"maxX":100,"maxY":100}
PhysicalProperties	density, friction, elasticity, frictionWeight, elasticityWeight	{"_type":"PhysicalProperties","density":1,"friction":0.3,"elasticity":0.5,"frictionWeight":1,"elasticityWeight":1}
Simple types (string, number, boolean) are passed directly without wrapping.

MCP Tools
All tools accept an optional client_id parameter (defaults to "studio").

Meta
studio.get_connection_status
Check if the Studio plugin is connected to the bridge. Handled server-side (no round-trip to Studio).

Returns: { connected: bool, client_id: string, last_seen_seconds?: number }

A client is considered connected if it has polled within the last 15 seconds.

Instance Navigation
roblox.list_services
List top-level services in the place (children of game).

roblox.get_children
Get the direct children of an instance.

Param	Type	Description
path / pathArray / id	string / string[] / string	Instance reference
roblox.get_descendants
Get all descendants of an instance. Can be very large – prefer get_tree for overviews.

Param	Type	Description
path / pathArray / id	string / string[] / string	Instance reference
roblox.get_instance
Get info for a single instance: name, className, fullName, id, parentId.

Param	Type	Description
path / pathArray / id	string / string[] / string	Instance reference
roblox.find_instances
Search descendants of an ancestor by name, className, and/or CollectionService tag.

Param	Type	Description
name	string	Exact Name match
className	string	Exact ClassName match
tag	string	Must have this tag
ancestorPath / ancestorPathArray	string / string[]	Search root (default: game)
roblox.get_tree
Get a compact recursive tree view. Efficient way to understand hierarchy without multiple calls.

Param	Type	Default	Description
path / pathArray / id			Root of the tree
maxDepth	integer	5	Maximum depth to recurse
maxChildren	integer	50	Maximum children per node
Each node returns { name, className, children?, childCount?, scriptLineCount?, truncatedChildren? }.

scriptLineCount is included for scripts (LuaSourceContainer).
childCount appears at the depth limit instead of expanding children.
truncatedChildren appears when children are capped by maxChildren.
Instance Manipulation
roblox.create_instance
Create a new instance under a parent. Supports rich type objects in the properties dict.

Param	Type	Required	Description
className	string	✓	Class to create
parentPath / parentPathArray	string / string[]		Parent (default: Workspace)
properties	object		Key/value map of properties to set (including Name, Source, etc.). Use _type objects for rich types.
roblox.delete_instance
Destroy an instance and all its descendants. Undoable via Ctrl+Z.

Param	Type	Description
path / pathArray / id	string / string[] / string	Instance to destroy
roblox.clone_instance
Clone an instance (and its descendants). Optionally reparent and rename the clone. Undoable.

Param	Type	Description
path / pathArray / id		Instance to clone
newParentPath / newParentPathArray	string / string[]	Parent for the clone (default: same parent)
newName	string	Rename the clone
roblox.reparent_instance
Move an instance to a new parent. Undoable.

Param	Type	Required	Description
path / pathArray / id			Instance to move
newParentPath / newParentPathArray	string / string[]	✓	New parent
roblox.set_name
Rename an instance. Undoable.

Param	Type	Required	Description
path / pathArray / id			Instance to rename
name	string	✓	New name
roblox.select_instance
Select an instance in the Studio Explorer panel for visibility.

Param	Type	Description
path / pathArray / id		Instance to select
Selection
roblox.get_selection
Get the instances currently selected in the Studio Explorer. Returns an array of serialized instance info (id, name, className, fullName, parentId).

No required parameters (only optional client_id).

Properties & Attributes
roblox.get_properties
Read specific built-in properties from an instance. Returns rich type objects with _type field for complex types.

Param	Type	Required	Description
path / pathArray / id			Instance
properties	string[]	✓	Property names to read
Returns: { "Size": {"_type":"Vector3","x":4,"y":1,"z":2}, "Anchored": true, ... }

#### `roblox.get_all_properties`
Read ALL properties from an instance using ReflectionService. Returns every readable,
non-deprecated property with its current value as rich type objects. This always reflects
the latest engine properties, including newly added ones from recent Roblox updates.

Use this when you need a complete snapshot of an instance (e.g., saving UI templates).
For reading specific known properties, prefer `get_properties` instead as it returns
less data.

| Param | Type | Description |
|-------|------|-------------|
| path / pathArray / id | string / string[] / string | Instance to read |

**Returns:**
```json
{
  "className": "UIStroke",
  "propertyCount": 12,
  "properties": {
    "Color": { "_type": "Color3", "r": 255, "g": 255, "b": 255 },
    "Thickness": 1,
    "Transparency": 0,
    "LineJoinMode": { "_type": "EnumItem", "enumType": "LineJoinMode", "name": "Round" },
    "ApplyStrokeMode": { "_type": "EnumItem", "enumType": "ApplyStrokeMode", "name": "Contextual" },
    "Name": "UIStroke",
    "ClassName": "UIStroke"
  },
  "skippedCount": 2
}

roblox.set_properties
Set built-in properties on an instance. Undoable. Use _type objects for complex types (see Rich Type System).

Param	Type	Required	Description
path / pathArray / id			Instance
properties	object	✓	Key/value map of properties to set
roblox.get_attributes
Get all custom attributes on an instance. Returns rich type objects for complex attribute values.

Returns: { "Health": 100, "Team": "Red", ... }

roblox.set_attributes
Set custom attributes on an instance. Undoable. Pass null/nil as a value to remove an attribute. Supports rich type objects.

Param	Type	Required	Description
path / pathArray / id			Instance
attributes	object	✓	Key/value map
Tags (CollectionService)
roblox.get_tags
Get all CollectionService tags on an instance.

Returns: { "tags": ["Enemy", "Damageable"] }

roblox.add_tag
Add a tag to an instance. Undoable.

Param	Type	Required	Description
path / pathArray / id			Instance
tag	string	✓	Tag to add
roblox.remove_tag
Remove a tag from an instance. Undoable.

Param	Type	Required	Description
path / pathArray / id			Instance
tag	string	✓	Tag to remove
Script Tools
roblox.read_script
Read the full Source of a Script, LocalScript, or ModuleScript.

Use sparingly on large scripts – prefer get_script_lines or search_script to reduce context.

Returns: { "source": "local x = 1\n..." }

roblox.write_script
Overwrite the full Source of a script. Undoable. Automatically updates ScriptEditorService if the script is open, so you don't need to close and reopen scripts. Basic syntax validation (bracket/parenthesis matching) is performed before applying changes.

WARNING: For partial edits on existing scripts, use patch_script instead. write_script replaces the entire source and can corrupt unrelated code if you reconstruct the source from memory. Only use for small scripts or when creating new scripts.

Param	Type	Required	Description
path / pathArray / id			Script instance
source	string	✓	Complete new source
roblox.get_script_lines
Read a specific line range from a script. If startLine and endLine are omitted, returns only the total line count (no content) – useful as a first probe.

Param	Type	Default	Description
path / pathArray / id			Script instance
startLine	integer	1	1-indexed start line
endLine	integer	last	1-indexed inclusive end line
Returns:

JSON

{
  "totalLines": 250,
  "startLine": 10,
  "endLine": 20,
  "lines": [
    { "lineNumber": 10, "text": "local x = 1" },
    { "lineNumber": 11, "text": "local y = 2" }
  ]
}
roblox.search_script
Search a script's source for a plain string or Lua pattern. Returns matching lines with line numbers and optional surrounding context.

Param	Type	Default	Description
path / pathArray / id			Script instance
query	string	✓ (required)	Text or pattern to find
usePattern	boolean	false	Treat query as a Lua string pattern
caseSensitive	boolean	true	If false, search case-insensitively
contextLines	integer	0	Lines of context around each match
maxResults	integer	50	Maximum matches to return
Returns:

JSON

{
  "totalLines": 250,
  "matchCount": 3,
  "results": [
    { "lineNumber": 42, "text": "function onDamage()", "isMatch": true },
    { "lineNumber": 43, "text": "  local hp = self.Health", "isMatch": false }
  ]
}
roblox.get_script_functions
List all function definitions in a script with their line numbers and types. Use this to understand the structure of a script before editing.

Param	Type	Description
path / pathArray / id		Script instance
Detects these patterns:

local function name(...) → type "local"
function name(...) → type "function"
function Class:method(...) → type "method"
name = function(...) → type "assigned"
Returns:

JSON

{
  "totalLines": 350,
  "functionCount": 12,
  "functions": [
    { "name": "module.Init", "line": 15, "type": "function" },
    { "name": "handleDamage", "line": 42, "type": "local" },
    { "name": "module:Cleanup", "line": 180, "type": "method" },
    { "name": "self.onHit", "line": 200, "type": "assigned" }
  ]
}
roblox.search_across_scripts
Search ALL scripts under an ancestor for a query string. Returns which scripts contain matches with line numbers. Useful for finding where a function, variable, or string is used across the codebase.

Param	Type	Default	Description
query	string	✓ (required)	Text or pattern to find
ancestorPath / ancestorPathArray	string / string[]	game	Root to search under
usePattern	boolean	false	Treat query as a Lua string pattern
caseSensitive	boolean	true	If false, search case-insensitively
maxScripts	integer	200	Max scripts with matches to return
maxMatchesPerScript	integer	10	Max matches to return per script
Returns:

JSON

{
  "scriptsSearched": 85,
  "scriptsWithMatches": 3,
  "results": [
    {
      "id": "...",
      "name": "CashService",
      "className": "ModuleScript",
      "fullName": "ServerStorage.Modules.CashService",
      "matchCount": 2,
      "matches": [
        { "lineNumber": 45, "text": "function CashService:ClaimCash(player, slotId)" },
        { "lineNumber": 180, "text": "\tlocal claimed = CashService:ClaimCash(plr, id)" }
      ]
    }
  ]
}
roblox.patch_script
Apply line-based patches to a script without rewriting the entire source. Undoable. Automatically updates ScriptEditorService if the script is open, so you don't need to close and reopen scripts. Patches are applied sequentially – line numbers in later patches refer to the script state after earlier patches.

Content validation: For replace and delete ops, always provide expectedContent. If the actual lines at lineStart..lineEnd don't match, the operation fails safely and returns the actual content so you can see what's really there. This prevents blind overwrites when line numbers are stale.

SAFETY: For insert operations, expectedContext is REQUIRED. This prevents unsafe insertions inside functions by validating the line before the insertion point. Indentation is automatically preserved. Basic syntax validation (bracket/parenthesis matching) is performed before applying patches.

Param	Type	Required	Description
path / pathArray / id			Script instance
patches	array	✓	Array of patch operations
Each patch object:

Field	Type	Description
op	string	"insert", "replace", "delete", "append", or "prepend"
lineStart	integer	1-indexed line number (for insert, replace, delete)
lineEnd	integer	1-indexed inclusive end line (for replace, delete; defaults to lineStart)
content	string	Text to insert/replace/append/prepend. May contain \n for multiple lines.
expectedContent	string	For replace/delete: the text you expect at lineStart..lineEnd. Fails safely on mismatch. Always provide this.
expectedContext	string	For insert: REQUIRED. The exact content of the line before the insertion point. Prevents unsafe mid-function insertions.
Operations:

Op	Behavior
insert	Insert content before lineStart. Existing lines shift down. REQUIRES expectedContext for safety.
replace	Replace lines lineStart..lineEnd (inclusive) with content. Indentation preserved.
delete	Delete lines lineStart..lineEnd (inclusive).
append	Add content at the end of the script.
prepend	Add content at the beginning of the script.
Returns: { "ok": true, "newLineCount": 245 }

On content mismatch:

text

CONTENT MISMATCH in patch #1 (replace lines 10-12).
=== EXPECTED ===
local x = 1
local y = 2
local z = 3
=== ACTUAL ===
-- this is different
local a = 99
local b = 100
=== END ===
The script may have changed. Re-read the lines and retry.
Example – replace lines 10-12 and insert a line before line 20:

JSON

{
  "patches": [
    {
      "op": "replace",
      "lineStart": 10,
      "lineEnd": 12,
      "expectedContent": "local x = 1\nlocal y = 2\nlocal z = 3",
      "content": "-- replaced\nlocal x = 42"
    },
    {
      "op": "insert",
      "lineStart": 19,
      "expectedContext": "local result = calculate()",
      "content": "-- new line here"
    }
  ]
}
Note: After the first patch (replacing 3 lines with 2), line numbers shift by -1. The insert uses 19 instead of 20 to account for this. To avoid shift math, work bottom-to-top or use one patch per call. The insert operation REQUIRES expectedContext to prevent unsafe insertions.

ScriptEditorService
roblox.open_script
Open a script in the Studio script editor tab and optionally navigate to a specific line. Uses ScriptEditorService:OpenScriptDocumentAsync.

Param	Type	Default	Description
path / pathArray / id			Script instance
line	integer	1	Line number to navigate to
roblox.get_open_scripts
List all scripts currently open in the Studio script editor.

No required parameters (only optional client_id).

Returns: An array of script info objects with id, name, className, and fullName.

roblox.close_script
Close a script's tab in the Studio script editor.

Param	Type	Description
path / pathArray / id		Script instance to close
ChangeHistoryService
roblox.undo
Undo the last action in Studio. Equivalent to Ctrl+Z.

No required parameters (only optional client_id).

roblox.redo
Redo the last undone action in Studio. Equivalent to Ctrl+Y.

No required parameters (only optional client_id).

roblox.set_waypoint
Set a named undo/redo waypoint. All MCP mutations already create automatic waypoints, but you can add explicit ones to group a series of changes under a single undo step.

Param	Type	Description
name	string	Waypoint name (shown in undo history)

Studio helper tools
roblox.run_code
Execute arbitrary Lua code inside Studio and return a serialized result using the rich type format described above.

roblox.insert_model
Insert a Marketplace asset into `Workspace` via `InsertService:LoadAsset` and return the inserted model's serialized metadata.

roblox.get_console_output
Fetch the buffered Output log. Pass `since` (Unix timestamp) and `maxEntries` to limit the slice. Entries include `text`, `type`, and `timestamp`.

roblox.start_stop_play
Switch Studio's run mode (Edit, Play, Run, Test). `stop` maps to Edit, `start` maps to Play. Returns the mode that Studio moved into.

roblox.get_studio_mode
Return `StudioService:GetRunMode()`'s name and a boolean `isPlay` flag that indicates whether a Play/Run session is active.

roblox.run_script_in_play_mode
Execute Lua while Studio is in Play or Run mode. Requires `code` and errors if Studio is stopped.

Server Configuration
Flag	Default	Description
--http-bind	"" (all interfaces)	Address to bind the HTTP server to
--http-port	28650	HTTP port for the plugin to connect to
--poll-timeout	5	Seconds to hold a /poll request before returning empty
--job-timeout	30	Seconds to wait for Studio to complete a job
--quiet	off	Suppress HTTP request logging
Recommended Workflows
Exploring a place
text

list_services
  → get_tree  path="Workspace"  maxDepth=3
  → get_tree  path="ServerScriptService"  maxDepth=2
Understanding a script's structure
text

1. get_script_functions  path="ServerStorage.Modules.CashService"
   → see all functions with line numbers
2. get_script_lines  startLine=42  endLine=80
   → read the function you care about
Finding usage across codebase
text

1. search_across_scripts  query="ClaimCash"
   → find all scripts that reference ClaimCash
2. For each result, get_script_lines to read context
Safe script editing (REQUIRED workflow)
text

1. get_script_lines                                → get total line count
2. search_script  query="function onDamage"        → find line 142
3. get_script_lines  startLine=140  endLine=160    → read exact content
4. patch_script  patches=[{
     op: "replace",
     lineStart: 145,
     lineEnd: 150,
     expectedContent: "<the exact 6 lines from step 3>",
     content: "<your replacement>"
   }]
If step 4 fails with CONTENT MISMATCH: go back to step 3, re-read, and retry.

Creating a new scripted object
text

1. create_instance  className="Part"  parentPath="Workspace"
     properties={"Name":"Lava","BrickColor":{"_type":"BrickColor","name":"Really red"}}
2. create_instance  className="Script"  parentPath="Workspace.Lava"
     properties={"Name":"DamageScript","Source":"..."}
3. add_tag  path="Workspace.Lava"  tag="Hazard"
Duplicating and modifying with rich types
text

1. clone_instance  path="Workspace.Template"  newName="Copy1"
2. set_properties  path="Workspace.Copy1"  properties={
     "Position": {"_type":"Vector3","x":10,"y":0,"z":0},
     "Color": {"_type":"Color3","r":255,"g":128,"b":0},
     "Material": {"_type":"EnumItem","enumType":"Material","name":"Neon"}
   }
Working with the user's selection
text

1. get_selection
   → see what the user has selected
2. Operate on the returned instances by id
Using the script editor
text

1. open_script  path="ServerScriptService.MainScript"  line=42
   → opens the script and jumps to line 42
2. get_open_scripts
   → see all currently open script tabs
3. close_script  path="ServerScriptService.MainScript"
   → close the tab when done
Undo/Redo workflow
text

1. set_waypoint  name="Before refactor"
2. ... make multiple changes ...
3. undo  → reverts to the last waypoint
4. redo  → re-applies the undone changes
Troubleshooting
Symptom	Likely Cause	Fix
"Studio is not connected" on every tool call	Plugin not running or not polling	Open widget, click "Start Bridge Polling", check widget shows "connected"
"Timed out waiting for Studio to respond"	Plugin is polling but job was lost	Check for POST result errors in plugin log; ensure port 28650 is free
Frequent connection-lost flapping	Poll timeout too long for Roblox HTTP budget	Use default --poll-timeout 5 or lower
CONTENT MISMATCH on patch	Script was edited between read and patch	Re-read the target lines and retry
"Could not enable HttpService"	Studio security setting	Enable HTTP requests in Game Settings → Security
Rich type not applying	Incorrect _type format or field names	Check the Rich Type System table for correct format
Script editor tool fails	ScriptEditorService not available	Ensure you're using a recent version of Roblox Studio
