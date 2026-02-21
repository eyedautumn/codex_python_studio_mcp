# Roblox Luau AI Benchmark (RLAB v3)

> **For agents:** Read this entire file before starting. There is no solution guide for v3. You must reason through every problem yourself.
>
> **For humans:** After the agent completes its run, see the **Human Review Notes** section at the bottom. The Runner script must be executed manually in Studio to validate correctness.

---

## Overview

RLAB v3 is designed to resist pattern-matching and force genuine reasoning. Tasks involve:
- Bugs that are **subtle and non-obvious** — the kind that pass visual inspection
- Implementations that have **edge cases the agent must discover and handle**
- Refactoring tasks where the **correct approach depends on reading the existing code**, not applying a template
- Instance tasks with **interdependencies** that must be resolved in the right order
- A deliberate **red herring** in the fixture code that the agent must identify and leave alone

**There is no `rlab_solution.md`.** The agent is expected to reason, read, and verify.

---

## Strict Rules

- Use only MCP bridge tools. No simulation, no guessing.
- Re-read target lines **immediately before every patch**. Not earlier in the conversation — immediately before.
- Use `patch_script` with `expectedContent`/`expectedContext` for all script edits.
- Do NOT use `write_script` on any script after fixture creation.
- Do NOT touch anything outside `ServerScriptService.RLAB`.
- After every patch, read the patched region back to confirm it applied correctly.
- If a patch returns `CONTENT MISMATCH`, you must re-read and retry. Do not skip.
- The Runner script is **not executed by the agent**. It is left in place for a human to run in Studio's Output window. Write it so it produces clear PASS/FAIL output a human can read.
- There is no cleanup step. Leave the sandbox in place for human review.

---

## Prerequisites

```
1. studio.get_connection_status           → must return connected: true
2. roblox_get_properties path="game"
     properties=["GameId","PlaceId","Name"] → log for run record
3. roblox_set_waypoint name="RLAB_v3_start"
4. Record wall-clock start time
```

---

## Sandbox Layout

Agent creates this structure at the start:

```
ServerScriptService
  └── RLAB                        (Folder)
        ├── DataPipeline           (ModuleScript)
        ├── EventBus               (ModuleScript)
        ├── Scheduler              (ModuleScript)
        ├── Validator              (ModuleScript)
        └── Runner                 (Script)
```

---

## Fixture Code

Create all scripts with `roblox_write_script` exactly as shown. Do not alter fixture content before tasks begin.

### DataPipeline (ModuleScript)

```lua
local DataPipeline = {}

-- Processes a list of records through a chain of transform functions.
-- Each transform receives (record, index) and returns a (possibly modified) record.
-- If a transform returns nil, the record is dropped from the output.
-- Returns the filtered+transformed list and a count of dropped records.
function DataPipeline.Process(records, transforms)
    local out = {}
    local dropped = 0
    for i, record in ipairs(records) do
        local current = record
        for _, fn in ipairs(transforms) do
            current = fn(current, i)
            if current == nil then
                dropped = dropped + 1
                break
            end
        end
        if current ~= nil then
            table.insert(out, current)
        end
    end
    return out, dropped
end

-- Merges two tables. Keys in `b` overwrite keys in `a`.
-- Does NOT recurse into nested tables.
function DataPipeline.Merge(a, b)
    local result = {}
    for k, v in pairs(a) do result[k] = v end
    for k, v in pairs(b) do result[k] = v end
    return result
end

-- Groups a list of records by the value of a given key.
-- Returns a table: { [keyValue] = { records... } }
-- Records missing the key are grouped under the string "nil".
function DataPipeline.GroupBy(records, key)
    local groups = {}
    for _, record in ipairs(records) do
        local k = tostring(record[key])
        if not groups[k] then groups[k] = {} end
        table.insert(groups[k], record)
    end
    return groups
end

-- BUG (hidden): Flattens a list of lists into a single list.
-- Should preserve order. Does not need to handle nesting deeper than 1 level.
function DataPipeline.Flatten(lists)
    local result = {}
    local i = 1
    for _, list in ipairs(lists) do
        for _, v in ipairs(list) do
            result[i] = v
        end
        i = i + 1
    end
    return result
end

-- Returns the first record in `records` for which `predicate(record)` returns true.
-- Returns nil if no match.
function DataPipeline.Find(records, predicate)
    for _, record in ipairs(records) do
        if predicate(record) then
            return record
        end
    end
end

return DataPipeline
```

### EventBus (ModuleScript)

```lua
local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
    local self = setmetatable({}, EventBus)
    self._handlers = {}
    self._onceHandlers = {}
    return self
end

-- Subscribe to an event. Returns a handle (opaque value) that can be passed to Off().
function EventBus:On(event, callback)
    if not self._handlers[event] then
        self._handlers[event] = {}
    end
    local handle = { event = event, callback = callback }
    table.insert(self._handlers[event], handle)
    return handle
end

-- Subscribe to an event for ONE firing only. Auto-unsubscribes after first fire.
function EventBus:Once(event, callback)
    if not self._onceHandlers[event] then
        self._onceHandlers[event] = {}
    end
    local handle = { event = event, callback = callback, once = true }
    table.insert(self._onceHandlers[event], handle)
    return handle
end

-- Unsubscribe using a handle returned by On() or Once().
-- BUG (hidden): has a subtle flaw that causes silent failure in one specific case.
function EventBus:Off(handle)
    local list = self._handlers[handle.event]
    if list then
        for i, h in ipairs(list) do
            if h == handle then
                table.remove(list, i)
                return
            end
        end
    end
end

-- Fire an event, calling all registered handlers with the given arguments.
-- Once-handlers fire and are removed. Regular handlers persist.
-- BUG (hidden): fires in a way that has a subtle ordering/mutation problem.
function EventBus:Fire(event, ...)
    local args = { ... }
    local handlers = self._handlers[event] or {}
    for _, h in ipairs(handlers) do
        h.callback(table.unpack(args))
    end
    local once = self._onceHandlers[event]
    if once then
        self._onceHandlers[event] = nil
        for _, h in ipairs(once) do
            h.callback(table.unpack(args))
        end
    end
end

return EventBus
```

### Scheduler (ModuleScript)

```lua
-- Scheduler: a priority queue of tasks ordered by scheduled tick.
-- Tasks with a lower tick value execute first.
-- Tasks at the same tick execute in insertion order (FIFO).
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
    local self = setmetatable({}, Scheduler)
    self._queue = {}   -- array of { tick, id, fn }
    self._nextId = 1
    self._currentTick = 0
    return self
end

-- Schedule a function to run at a specific tick.
-- Returns a task ID that can be used to cancel.
function Scheduler:Schedule(tick, fn)
    local id = self._nextId
    self._nextId = self._nextId + 1
    table.insert(self._queue, { tick = tick, id = id, fn = fn })
    -- Keep queue sorted by tick, then by id (insertion order)
    table.sort(self._queue, function(a, b)
        if a.tick == b.tick then return a.id < b.id end
        return a.tick < b.tick
    end)
    return id
end

-- Cancel a scheduled task by ID. Returns true if found and removed, false if not found.
function Scheduler:Cancel(id)
    for i, task in ipairs(self._queue) do
        if task.id == id then
            table.remove(self._queue, i)
            return true
        end
    end
    return false
end

-- Advance to `tick` and execute all tasks scheduled at or before that tick.
-- Updates self._currentTick. Tasks are removed after execution.
-- BUG (hidden): has a flaw when tasks scheduled during execution affect the current run.
function Scheduler:Advance(tick)
    self._currentTick = tick
    local i = 1
    while i <= #self._queue do
        local task = self._queue[i]
        if task.tick <= tick then
            table.remove(self._queue, i)
            task.fn()
        else
            i = i + 1
        end
    end
end

-- Returns the number of pending tasks.
function Scheduler:PendingCount()
    return #self._queue
end

-- Returns the tick at which the next task is scheduled, or nil if queue is empty.
function Scheduler:NextTick()
    if #self._queue == 0 then return nil end
    return self._queue[1].tick
end

return Scheduler
```

### Validator (ModuleScript)

```lua
-- Validator: validates data records against a schema.
-- A schema is a table of field definitions:
--   { fieldName = { type="string"|"number"|"boolean"|"table", required=true|false, min=n, max=n } }
local Validator = {}

-- Validate a single record against a schema.
-- Returns: ok (bool), errors (list of strings describing each failure)
function Validator.Check(record, schema)
    local errors = {}
    for field, rules in pairs(schema) do
        local value = record[field]
        if value == nil then
            if rules.required then
                table.insert(errors, field .. ": required field is missing")
            end
        else
            if rules.type and type(value) ~= rules.type then
                table.insert(errors, field .. ": expected " .. rules.type .. ", got " .. type(value))
            end
            if rules.type == "number" and type(value) == "number" then
                if rules.min and value < rules.min then
                    table.insert(errors, field .. ": value " .. value .. " is below minimum " .. rules.min)
                end
                if rules.max and value > rules.max then
                    table.insert(errors, field .. ": value " .. value .. " exceeds maximum " .. rules.max)
                end
            end
            -- BUG (hidden): string length validation is implemented but silently wrong.
            if rules.type == "string" and type(value) == "string" then
                if rules.min and #value < rules.min then
                    table.insert(errors, field .. ": string length " .. #value .. " is below minimum " .. rules.min)
                end
                if rules.max and #value > rules.max then
                    table.insert(errors, field .. ": string length " .. #value .. " exceeds maximum " .. rules.max)
                end
            end
        end
    end
    return #errors == 0, errors
end

-- Validate a list of records. Returns only the valid records and a list of
-- { index, errors } for each invalid record.
function Validator.CheckAll(records, schema)
    local valid = {}
    local invalid = {}
    for i, record in ipairs(records) do
        local ok, errs = Validator.Check(record, schema)
        if ok then
            table.insert(valid, record)
        else
            table.insert(invalid, { index = i, errors = errs })
        end
    end
    return valid, invalid
end

-- RED HERRING: This function looks wrong but is intentionally correct.
-- Do not modify it.
-- Counts how many records in `records` pass all rules for a single `field`.
function Validator.CountPassingField(records, field, rules)
    local count = 0
    for _, record in ipairs(records) do
        local value = record[field]
        local pass = true
        if value == nil then
            if rules.required then pass = false end
        else
            if rules.type and type(value) ~= rules.type then pass = false end
            if rules.type == "number" and type(value) == "number" then
                if rules.min and value < rules.min then pass = false end
                if rules.max and value > rules.max then pass = false end
            end
        end
        if pass then count = count + 1 end
    end
    return count
end

return Validator
```

### Runner (Script)

```lua
-- RLAB v3 Runner
-- DO NOT execute this automatically. A human must run this in Studio (Play Solo or Command Bar).
-- Read output in the Studio Output window.
-- Each test prints PASS or FAIL with a description.

local SSS = game:GetService("ServerScriptService")
local RLAB = SSS:WaitForChild("RLAB", 5)

local DataPipeline  = require(RLAB:WaitForChild("DataPipeline", 5))
local EventBus      = require(RLAB:WaitForChild("EventBus", 5))
local Scheduler     = require(RLAB:WaitForChild("Scheduler", 5))
local Validator     = require(RLAB:WaitForChild("Validator", 5))

local passed, failed = 0, 0

local function test(label, cond)
    if cond then
        passed = passed + 1
        print("PASS  " .. label)
    else
        failed = failed + 1
        warn("FAIL  " .. label)
    end
end

local function approx(a, b)
    return math.abs(a - b) < 0.0001
end

-- ── DataPipeline ────────────────────────────────────────────

-- Flatten: basic
local flat = DataPipeline.Flatten({{1,2},{3,4},{5}})
test("Flatten basic order",   flat[1]==1 and flat[2]==2 and flat[3]==3 and flat[4]==4 and flat[5]==5)
test("Flatten count",         #flat == 5)

-- Flatten: empty sublists
local flat2 = DataPipeline.Flatten({{},{1},{},{2,3}})
test("Flatten empty sublists count", #flat2 == 3)
test("Flatten empty sublists order", flat2[1]==1 and flat2[2]==2 and flat2[3]==3)

-- Flatten: empty outer
local flat3 = DataPipeline.Flatten({})
test("Flatten empty outer", #flat3 == 0)

-- Process: drop on nil
local recs = {{v=1},{v=2},{v=3},{v=4}}
local out, dropped = DataPipeline.Process(recs, {
    function(r) return r.v % 2 == 0 and r or nil end
})
test("Process drop odd", #out == 2 and dropped == 2)
test("Process keeps even values", out[1].v == 2 and out[2].v == 4)

-- Process: index passed correctly
local indices = {}
DataPipeline.Process({{},{},{}}, {function(r, i) table.insert(indices, i) return r end})
test("Process index 1-based", indices[1]==1 and indices[2]==2 and indices[3]==3)

-- GroupBy: missing key goes to "nil"
local grecs = {{t="a"},{t="b"},{t="a"},{x=1}}
local groups = DataPipeline.GroupBy(grecs, "t")
test("GroupBy groups a",   #groups["a"] == 2)
test("GroupBy groups b",   #groups["b"] == 1)
test("GroupBy nil key",    #groups["nil"] == 1)

-- ── EventBus ────────────────────────────────────────────────

local bus = EventBus.new()

-- Basic On/Fire
local fireCount = 0
bus:On("test", function() fireCount = fireCount + 1 end)
bus:Fire("test")
bus:Fire("test")
test("EventBus On fires", fireCount == 2)

-- Once fires exactly once
local onceCount = 0
bus:Once("once_ev", function() onceCount = onceCount + 1 end)
bus:Fire("once_ev")
bus:Fire("once_ev")
test("EventBus Once fires once", onceCount == 1)

-- Off removes handler
local offCount = 0
local h = bus:On("off_ev", function() offCount = offCount + 1 end)
bus:Fire("off_ev")
bus:Off(h)
bus:Fire("off_ev")
test("EventBus Off stops firing", offCount == 1)

-- Off on a Once handle (must not error and must prevent firing)
local onceCancelled = 0
local oh = bus:Once("cancel_once", function() onceCancelled = onceCancelled + 1 end)
bus:Off(oh)
bus:Fire("cancel_once")
test("EventBus Off cancels Once", onceCancelled == 0)

-- Fire with args
local gotArgs = nil
bus:On("args_ev", function(a, b) gotArgs = {a, b} end)
bus:Fire("args_ev", 42, "hello")
test("EventBus Fire args", gotArgs and gotArgs[1]==42 and gotArgs[2]=="hello")

-- Handler added during Fire does NOT fire in the same Fire call
local sideEffect = 0
bus:On("cascade", function()
    bus:On("cascade", function() sideEffect = sideEffect + 1 end)
end)
bus:Fire("cascade")
test("EventBus no cascade fire", sideEffect == 0)

-- ── Scheduler ───────────────────────────────────────────────

local sch = Scheduler.new()

-- Basic ordering
local order = {}
sch:Schedule(10, function() table.insert(order, "b") end)
sch:Schedule(5,  function() table.insert(order, "a") end)
sch:Schedule(15, function() table.insert(order, "c") end)
sch:Advance(12)
test("Scheduler order a-b",  order[1]=="a" and order[2]=="b")
test("Scheduler not c yet",  #order == 2)
sch:Advance(20)
test("Scheduler c fires",    order[3]=="c")

-- Same-tick FIFO
local fifo = {}
local s2 = Scheduler.new()
s2:Schedule(1, function() table.insert(fifo, 1) end)
s2:Schedule(1, function() table.insert(fifo, 2) end)
s2:Schedule(1, function() table.insert(fifo, 3) end)
s2:Advance(1)
test("Scheduler FIFO same tick", fifo[1]==1 and fifo[2]==2 and fifo[3]==3)

-- Cancel
local cancelFired = false
local s3 = Scheduler.new()
local cid = s3:Schedule(5, function() cancelFired = true end)
s3:Cancel(cid)
s3:Advance(10)
test("Scheduler Cancel works", not cancelFired)
test("Scheduler Cancel returns false after removal", s3:Cancel(cid) == false)

-- Task scheduled DURING Advance at same tick should NOT run in that Advance call
local lateRan = false
local s4 = Scheduler.new()
s4:Schedule(1, function()
    s4:Schedule(1, function() lateRan = true end)
end)
s4:Advance(1)
test("Scheduler no late-tick same-advance", not lateRan)

-- PendingCount and NextTick
local s5 = Scheduler.new()
s5:Schedule(3, function() end)
s5:Schedule(7, function() end)
test("Scheduler PendingCount", s5:PendingCount() == 2)
test("Scheduler NextTick", s5:NextTick() == 3)

-- ── Validator ───────────────────────────────────────────────

local schema = {
    name  = { type="string",  required=true,  min=2, max=20 },
    age   = { type="number",  required=true,  min=0, max=150 },
    notes = { type="string",  required=false, max=100 },
}

-- Valid record
local ok, errs = Validator.Check({name="Alice", age=30}, schema)
test("Validator valid record", ok and #errs==0)

-- Missing required
ok, errs = Validator.Check({age=30}, schema)
test("Validator missing required", not ok and #errs==1)

-- Wrong type
ok, errs = Validator.Check({name="Bob", age="old"}, schema)
test("Validator wrong type", not ok)

-- Number out of range
ok, errs = Validator.Check({name="Bob", age=200}, schema)
test("Validator number max", not ok)

ok, errs = Validator.Check({name="Bob", age=-1}, schema)
test("Validator number min", not ok)

-- String too short (min=2 for name)
ok, errs = Validator.Check({name="X", age=25}, schema)
test("Validator string min length", not ok)

-- String too long (max=20 for name)
ok, errs = Validator.Check({name=string.rep("a", 21), age=25}, schema)
test("Validator string max length", not ok)

-- Optional field absent: should be fine
ok, errs = Validator.Check({name="Alice", age=30}, schema)
test("Validator optional absent ok", ok)

-- Optional field present and valid
ok, errs = Validator.Check({name="Alice", age=30, notes="hello"}, schema)
test("Validator optional present valid", ok)

-- CheckAll
local records = {
    {name="Alice", age=30},
    {name="X", age=25},
    {name="Bob", age=200},
    {name="Carol", age=40},
}
local valid, invalid = Validator.CheckAll(records, schema)
test("Validator CheckAll valid count",   #valid == 2)
test("Validator CheckAll invalid count", #invalid == 2)

-- CountPassingField: intentionally correct, do not change
local cprecs = {{score=5},{score=15},{score=8},{score=nil}}
local passing = Validator.CountPassingField(cprecs, "score",
    {type="number", required=false, min=1, max=10})
test("Validator CountPassingField", passing == 2)

-- ── Summary ─────────────────────────────────────────────────
print(string.rep("─", 50))
print(string.format("RLAB v3 Results: %d passed  /  %d failed  /  %d total",
    passed, failed, passed + failed))
print(string.rep("─", 50))
```

---

## Tasks

Complete in order. No hints are provided beyond what is visible in the fixture code and the test cases in Runner.

---

### Category A — Find and Fix Hidden Bugs

The fixtures contain **5 hidden bugs** across `DataPipeline`, `EventBus`, `Scheduler`, and `Validator`. One comment in `Validator` explicitly marks a function as a **red herring** — do not modify it. Your job is to:

1. Read the code carefully and reason about what each function is supposed to do.
2. Read the corresponding test cases in Runner to understand the expected behaviour.
3. Identify each bug by reading the actual code logic — not just the comments.
4. Fix each bug using `patch_script` with `expectedContent`.
5. After each fix, read the patched lines back to confirm.

**The bugs are in these locations:**
- `DataPipeline.Flatten` — one bug
- `EventBus:Off` — one bug, silently fails in one specific case
- `EventBus:Fire` — one bug, mutation-during-iteration problem
- `Scheduler:Advance` — one bug, tasks scheduled during execution corrupt the current run
- `Validator.Check` — one bug in string length validation

**Self-check for each fix:** After patching, use `search_script` to confirm the old buggy line no longer exists.

---

### Category B — Non-Trivial Implementations

#### B1 · DataPipeline.Reduce

Add a new function `DataPipeline.Reduce(records, fn, initial)` to `DataPipeline` (before `return DataPipeline`):

- Applies `fn(accumulator, record, index)` across records left to right.
- Starts with `accumulator = initial`.
- If `records` is empty, returns `initial`.
- If `fn` errors on any record, `Reduce` must catch the error and **skip that record**, continuing with the previous accumulator value. The number of skipped records is returned as a second return value.

Add tests for this function to Runner **before the `-- ── Summary` line** using the same `test(label, cond)` pattern. Your tests must cover: basic sum, empty list, error-skip behaviour (at least one record causes `fn` to error).

#### B2 · EventBus:WaitFor

Add a method `EventBus:WaitFor(event, timeout)` that:

- Yields until the named event fires or `timeout` seconds elapse.
- Returns the arguments passed to the fired event if it fires in time, or `nil` if it times out.
- Must not leave any persistent handler registered after it returns — clean up either path.
- Must work correctly if the event fires on the same frame.

Implement using only `bus:Once`, `task.wait`, and a timeout accumulator. Do not use `task.delay` or `BindableEvent`.

Add at least 2 tests to Runner. Because `WaitFor` is async, wrap tests in `task.spawn` and use a shared result table. Add a `task.wait(0.5)` in the main thread before the Summary so async results have time to resolve.

#### B3 · Scheduler:Repeat

Add a method `Scheduler:Repeat(startTick, interval, fn)` that:

- Schedules `fn` to run at `startTick`, then every `interval` ticks thereafter, indefinitely.
- Returns a cancel function (a zero-argument callable) that stops all future firings.
- Re-schedules **before** calling `fn()` so that if `fn` invokes the cancel function, no future task is left in the queue.
- Errors with `"Repeat: interval must be positive"` if `interval <= 0`.

Add 3 tests to Runner: fires on correct ticks, cancel stops future fires, `interval=0` errors.

#### B4 · Validator.Compose

Add a function `Validator.Compose(schemaA, schemaB)` that:

- Returns a new schema that is the union of both schemas.
- If the same field appears in both: `required` is `true` if either requires it; `type` from `schemaB` wins; `min` takes the **stricter** (higher for numbers, higher for string length) value; `max` takes the **stricter** (lower) value.
- Does not mutate the original schemas.

Add tests: composed schema has fields from both, conflicting min/max resolves strictly, required union.

---

### Category C — Structural Changes

#### C1 · DataPipeline Pipeline Builder

Add a `DataPipeline.Builder()` constructor returning a chainable builder:

```lua
local out, dropped = DataPipeline.Builder()
    :Filter(function(r) return r.v > 2 end)
    :Map(function(r) return { v = r.v * 10 } end)
    :Run(records)
```

- `:Filter(fn)` — drops records where `fn(record)` is falsy.
- `:Map(fn)` — replaces each record with `fn(record)`.
- `:Run(records)` — executes via `DataPipeline.Process` internally, returns `(out, dropped)`.
- Each method except `:Run` returns `self` for chaining.
- Calling `:Run` twice with different inputs must produce independent results.

Add 3 tests to Runner.

#### C2 · EventBus Wildcard Subscriptions

Extend `EventBus:On` and `EventBus:Fire` to support the wildcard event name `"*"`:

- `bus:On("*", fn)` receives all fired events, with the event name prepended as the first argument: `fn(eventName, ...)`.
- Wildcard handlers do NOT fire when the literal event name `"*"` is fired.
- `bus:Off(handle)` must remove wildcard handles correctly.
- `bus:Once("*", fn)` must also work.

Do not break any existing tests when modifying `:Fire`.

Add 3 tests to Runner.

---

### Category D — Instance Reasoning

These tasks involve querying state before acting. Do not hardcode any values you can read from Studio.

#### D1 · Config Folder

Create this structure under `ServerScriptService.RLAB`:

```
RLAB
  └── Config (Folder)
        ├── Debug      (BoolValue,   Value=false)
        ├── Version    (StringValue, Value="3.0.0")
        └── MaxRetries (IntValue,    Value=3)
```

Read back each `Value` property with `roblox_get_properties` and confirm it matches before proceeding.

#### D2 · Attribute Contract

On the `RLAB` folder itself, set these custom attributes:
- `"BenchmarkVersion"` → `"3.0.0"` (string)
- `"Strict"` → `true` (boolean)
- `"TaskCount"` → the **actual number of top-level children of RLAB** at the time you set this attribute. You must call `roblox_get_children` on RLAB first and count — do not hardcode.

Self-check: `get_attributes` on RLAB and verify all three values.

---

### Category E — Meta: Self-Verification

#### E1 · Audit Runner

After all other tasks are complete, read the entire Runner script using `get_script_lines` in chunks of at most 50 lines at a time. Count every occurrence of the pattern `test(` in the script. Store the count as a StringValue attribute `"TestCount"` on the RLAB folder (e.g. `"34"`).

Self-check: `search_script query='test('` in Runner — the count of matches reported must equal the number you stored.

#### E2 · Patch Integrity Record

For each of the 4 modules, call `get_script_lines` with no range to get the total line count. Store as attributes on the RLAB folder:
- `"Lines_DataPipeline"` → number
- `"Lines_EventBus"` → number
- `"Lines_Scheduler"` → number
- `"Lines_Validator"` → number

These serve as a tamper-evidence record for human review.

---

## Human Review Notes

After the agent completes its run, do the following in Roblox Studio:

1. **Run the Runner script.** Open `ServerScriptService.RLAB.Runner` in the Script Editor and run Play Solo, or paste contents into the Command Bar (server-side). Read the Output window.

2. **PASS/FAIL count.** Note the total and any failing tests. Record which module each failure belongs to.

3. **Red herring check.** Verify that `Validator.CountPassingField` was **not** modified. If it was, apply the −10 red herring penalty.

4. **TestCount attribute.** Read the `TestCount` attribute on the RLAB folder. Count `test(` occurrences in Runner manually (Ctrl+F). If the agent's count is wrong, note the discrepancy.

5. **TaskCount attribute.** Count the actual top-level children of RLAB manually. If it doesn't match the attribute, the agent hardcoded instead of querying.

6. **Lines_* attributes.** No expected values — use your judgment on whether the counts are plausible for the code you see.

7. **Config folder.** Confirm `Debug`, `Version`, `MaxRetries` exist with correct class and Value.

8. **Cleanup.** Delete `ServerScriptService.RLAB` manually when review is complete.

---

## Run Record Template

```json
{
  "benchmark": "RLAB_v3",
  "model": "",
  "timestamp": "",
  "duration_sec": 0,
  "scores": {
    "A_bugs": {
      "A_flatten_bug": false,
      "A_eventbus_off_bug": false,
      "A_eventbus_fire_bug": false,
      "A_scheduler_advance_bug": false,
      "A_validator_string_bug": false,
      "A_red_herring_untouched": false
    },
    "B_implementations": {
      "B1_reduce": false,
      "B2_waitfor": false,
      "B3_repeat": false,
      "B4_compose": false
    },
    "C_structural": {
      "C1_builder": false,
      "C2_wildcard": false
    },
    "D_instances": {
      "D1_config_folder": false,
      "D2_attributes": false,
      "D2_taskcount_queried": false
    },
    "E_meta": {
      "E1_testcount_correct": false,
      "E2_line_counts_present": false
    }
  },
  "tool_hygiene": {
    "read_before_every_patch": false,
    "expected_content_always_provided": false,
    "expected_context_always_provided": false,
    "no_write_script_on_existing": false,
    "no_outside_modifications": false,
    "self_checks_performed": false
  },
  "human_review": {
    "runner_tests_passed": 0,
    "runner_tests_failed": 0,
    "runner_tests_total": 0,
    "red_herring_untouched": false,
    "testcount_attribute_correct": false,
    "taskcount_attribute_correct": false,
    "notes": ""
  }
}
```

---

## Scoring Rubric

| Category | Points | Notes |
|----------|--------|-------|
| A — Bug Fixes (5 bugs) | 25 | 5 pts each. |
| B — Implementations | 40 | 10 pts each. Partial credit for B2/B3 if logic is right but async edge cases fail. |
| C — Structural | 20 | 10 pts each. |
| D — Instances | 10 | 5 pts each. D2 TaskCount: 0 pts if hardcoded. |
| E — Meta | 10 | 5 pts each. E1 validated by human against actual Runner test count. |
| **Subtotal** | **105** | |
| Tool Hygiene bonus | +10 | All 6 hygiene checks true. |
| Red herring penalty | −10 | If `CountPassingField` was modified. |
| Outside-modification penalty | −30 | Any changes outside `ServerScriptService.RLAB`. |

**Maximum score: 115**
