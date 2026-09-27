-- WowKeys diagnostics: /wowkeys probes for learning how the game (and
-- Forever's Gamepad UI) works. They only run when typed; the layout never
-- depends on them. Each one registers itself at the bottom of this file.

local _, ns = ...
local getCVar, spellName, padArrangement, safeString =
  ns.getCVar, ns.spellName, ns.padArrangement, ns.safeString

-- Lists binding commands matching some text, so addon bindings (Auctionator,
-- DBM, ...) can go into layout.toml by their exact command name.
local function findBindings(text)
  text = text:lower()
  local shown = 0
  for i = 1, GetNumBindings() do
    local command, _, key1, key2 = GetBinding(i)
    local name = command and GetBindingName(command) or ""
    -- HEADER_* entries are section titles in the keybinding menu, not bindings.
    local isHeader = command and command:find("^HEADER_")
    if command and not isHeader
      and (command:lower():find(text, 1, true) or name:lower():find(text, 1, true)) then
      shown = shown + 1
      if shown <= 40 then
        local keys = key1 and (" [" .. key1 .. (key2 and (", " .. key2) or "") .. "]") or ""
        print(("  %s  |cff999999%s%s|r"):format(command, name, keys))
      end
    end
  end
  print(("WowKeys: %d binding(s) match \"%s\"%s"):format(shown, text, shown > 40 and " (first 40 shown)" or ""))
end

-- Lists everything bound to a controller button, plus the controller
-- settings, to learn how Forever's gamepad UI stores its bindings.
local GAMEPAD_CVARS = { "GamePadEnable", "GamePadEmulateShift", "GamePadEmulateCtrl",
  "GamePadEmulateAlt", "GamePadEmulateEsc", "GamePadFaceMovementMaxAngle",
  "GamePadFaceMovementMaxAngleCombat" }

local function padBindings()
  local shown = 0
  for i = 1, GetNumBindings() do
    local command, _, key1, key2 = GetBinding(i)
    for _, key in ipairs({ key1, key2 }) do
      -- The key itself (after any modifiers) must start with PAD, so numpad
      -- keys like NUMPAD5 don't count as controller buttons.
      local base = key and key:match("[^-]+$")
      if command and base and base:find("^PAD") then
        shown = shown + 1
        print(("  %s  ->  %s"):format(key, command))
      end
    end
  end
  print(("WowKeys: %d controller binding(s)"):format(shown))
  for _, name in ipairs(GAMEPAD_CVARS) do
    local value = getCVar(name)
    if value ~= nil then
      print(("  %s = %s"):format(name, value))
    end
  end
  -- Every setting whose name mentions GamePad, to find ones we don't know.
  local all = C_Console and C_Console.GetAllCommands and C_Console.GetAllCommands() or {}
  local names = {}
  for _, c in ipairs(all) do
    if c.command and c.command:lower():find("gamepad", 1, true) then
      table.insert(names, c.command)
    end
  end
  table.sort(names)
  if #names > 0 then print("  all GamePad settings: " .. table.concat(names, ", ")) end
end

-- Lists every filled action slot with its id, to learn which slots the
-- controller's bars (12 bars of 8) use. The classic range is 1-180; scan
-- well past it in case the controller bars live higher.
local function listSlots()
  local shown = 0
  for slot = 1, 1000 do
    local kind, id = GetActionInfo(slot)
    if kind then
      shown = shown + 1
      local name = (kind == "spell" and spellName(id))
        or (kind == "macro" and GetMacroInfo and GetMacroInfo(id))
        or tostring(id)
      print(("  %3d  %s  %s"):format(slot, kind, name or "?"))
    end
  end
  print(("WowKeys: %d filled action slot(s)"):format(shown))
end

-- Lists every frame that shows an action slot above 180 (the controller
-- bars) with a short name and its on-screen centre, to learn which slot is
-- which controller input. The Gamepad UI has a main bar frame and an edit
-- frame for the same slots; only the main one is listed when present.
local function frameName(frame)
  return (frame.GetDebugName and frame:GetDebugName()) or frame:GetName() or "?"
end

local function shortName(name)
  local bar, n = name:match("Anchor(%a+)BarActionButton(%d+)$")
  return bar and (bar .. "." .. n) or name
end

local function listPadButtons()
  local rows, hasMain = {}, false
  local frame = EnumerateFrames()
  while frame do
    local ok, slot = pcall(function()
      return frame.action or (frame.GetAttribute and frame:GetAttribute("action"))
    end)
    if ok and type(slot) == "number" and slot > 180 then
      local name = frameName(frame)
      local x, y -- (`a and f()` would keep only f's first result)
      if frame.GetCenter then x, y = frame:GetCenter() end
      local isMain = name:find("GamepadMainActionBar", 1, true) ~= nil
      hasMain = hasMain or isMain
      table.insert(rows, { slot, name, x, y, isMain })
    end
    frame = EnumerateFrames(frame)
  end
  table.sort(rows, function(a, b) return a[1] < b[1] end)
  local shown = 0
  for _, r in ipairs(rows) do
    if r[5] or not hasMain then
      shown = shown + 1
      local where = (r[3] and r[4]) and ("  (%d, %d)"):format(r[3], r[4]) or ""
      print(("  %3d  %s%s"):format(r[1], shortName(r[2]), where))
    end
  end
  print(("WowKeys: %d button(s) on slots above 180"):format(shown))
end

-- Calls fn(frame, name) for every named frame. Frames whose name isn't
-- plain text (some addons' frames, values the client hides) are skipped,
-- and one bad frame never stops the scan.
local function eachNamedFrame(fn)
  local frame = EnumerateFrames()
  while frame do
    local ok, name = pcall(frame.GetName, frame)
    if ok and type(name) == "string" then pcall(fn, frame, name) end
    frame = EnumerateFrames(frame)
  end
end

local function isShown(frame)
  return frame.IsShown and frame:IsShown() or false
end

local function printFrames(rows, what)
  table.sort(rows)
  for i = 1, math.min(#rows, 60) do print(rows[i]) end
  print(("WowKeys: %d frame(s) %s%s"):format(#rows, what, #rows > 60 and " (first 60 shown)" or ""))
end

local function frameRow(frame, name)
  local kind = frame.GetObjectType and frame:GetObjectType() or "?"
  return ("  %s  |cff999999%s, %s|r"):format(name, kind, isShown(frame) and "shown" or "hidden")
end

-- Lists named frames whose name contains some text, with their type and
-- whether they're shown, to find Blizzard buttons a CLICK binding can press
-- (e.g. the Gamepad UI's next/previous arrangement controls).
local function findFrames(text)
  text = text:lower()
  local rows = {}
  eachNamedFrame(function(frame, name)
    if name:lower():find(text, 1, true) then table.insert(rows, frameRow(frame, name)) end
  end)
  printFrames(rows, ("match \"%s\""):format(text))
end

-- Notes which named frames are shown now, waits, then lists the ones shown
-- since. For menus that close when chat opens: run it, then open the menu
-- and hold it until the list prints.
local function newFrames(seconds)
  local before = {}
  eachNamedFrame(function(frame, name) before[name] = isShown(frame) end)
  print(("WowKeys: open the menu now; listing new frames in %d s"):format(seconds))
  C_Timer.After(seconds, function()
    local rows = {}
    eachNamedFrame(function(frame, name)
      if isShown(frame) and not before[name] then table.insert(rows, frameRow(frame, name)) end
    end)
    printFrames(rows, ("appeared in the last %d s"):format(seconds))
  end)
end

-- The frame named exactly `text`, or the only named frame containing it.
local function frameByName(text)
  if type(_G[text]) == "table" and _G[text].GetObjectType then return _G[text] end
  local found, names = nil, {}
  eachNamedFrame(function(frame, name)
    if name:lower():find(text:lower(), 1, true) then
      found = frame
      table.insert(names, name)
    end
  end)
  if #names == 1 then return found end
  if #names == 0 then
    print(("WowKeys: no frame named like \"%s\""):format(text))
  else
    printFrames(names, ("match \"%s\"; name one"):format(text))
  end
end

-- Prints names in lines of a few each.
local function printList(label, list)
  table.sort(list)
  if #list == 0 then return end
  print(("  |cffffd200%s|r (%d)"):format(label, #list))
  for i = 1, #list, 5 do
    print("    " .. table.concat(list, ", ", i, math.min(i + 4, #list)))
  end
end


-- Parent keys of a frame's table fields, so unnamed children get a label.
local function parentKeys(frame)
  local keyOf = {}
  for k, v in pairs(frame) do
    if type(k) == "string" and type(v) == "table" then keyOf[v] = k end
  end
  return keyOf
end

-- Adds "path Type [hidden] ["text"]" for each child, two levels deep.
local function listChildren(frame, prefix, rows, depth)
  local keyOf = parentKeys(frame)
  for _, child in ipairs({ frame:GetChildren() }) do
    local ok, row = pcall(function()
      local label = prefix .. (keyOf[child] or child:GetName() or "?")
      local text = child.GetText and child:GetText()
      if depth > 1 then listChildren(child, label .. ".", rows, depth - 1) end
      return ("%s %s%s%s"):format(label, child:GetObjectType(),
        isShown(child) and "" or " hidden", text and (" \"" .. safeString(text) .. "\"") or "")
    end)
    table.insert(rows, ok and row or (prefix .. "? (error)"))
  end
end

-- Shows a frame's own fields, its functions (mixin methods, not the widget
-- API) and its children, to find how the Gamepad UI pages its bars.
local function inspectFrame(frame, title)
  local fields, functions = {}, {}
  for k, v in pairs(frame) do
    if type(k) == "string" then
      if type(v) == "function" then
        table.insert(functions, k)
      elseif type(v) == "table" then
        table.insert(fields, k .. "=" .. (v.GetObjectType and safeString(v:GetObjectType()) or "table"))
      else
        table.insert(fields, k .. "=" .. safeString(v))
      end
    end
  end
  print("WowKeys: " .. title .. " (" .. frame:GetObjectType() .. ")")
  printList("fields", fields)
  printList("functions", functions)
  local children = {}
  listChildren(frame, "", children, 2)
  printList("children", children)
end

-- The Gamepad UI's page tracker and shortcut menu, where a change-page
-- button would live.
local function inspectPageControls()
  local unit = GamepadMainActionBarFramePageUnit
  if not unit then
    print("WowKeys: no Gamepad UI page unit (is the Gamepad UI on?)")
    return
  end
  for _, key in ipairs({ "PageTracker", "ShortcutsActionBar" }) do
    if unit[key] then inspectFrame(unit[key], key) else print("WowKeys: no " .. key) end
  end
end

-- Prints the Gamepad UI's current page (arrangement) and its pageable bars.
-- Read-only: calling SetCurrentPage from an addon is blocked ("only
-- available to the Blizzard UI"), tested in game.
local function probePage()
  local unit = GamepadMainActionBarFramePageUnit
  if not (unit and unit.GetCurrentPage) then
    print("WowKeys: no Gamepad UI page unit (is the Gamepad UI on?)")
    return
  end
  local ok, page = pcall(unit.GetCurrentPage, unit)
  print(("WowKeys: GetCurrentPage -> %s; bars show arrangement %s"):format(
    ok and tostring(page) or ("error: " .. tostring(page)), tostring(padArrangement())))
  for k, v in pairs(unit.pageableActionBarsIndexOrder or {}) do
    local name = type(v) == "table" and v.GetName and v:GetName() or tostring(v)
    print(("  page order %s: %s"):format(tostring(k), tostring(name)))
  end
end

-- Registration ------------------------------------------------------------

local slash = ns.addSlash
slash("find", "find <text>", "list binding commands matching text (names for layout.toml)", findBindings)
slash("pad", "pad", "list controller bindings and GamePad settings", padBindings)
slash("slots", "slots", "list filled action slots by id", listSlots)
slash("padbuttons", "padbuttons", "list controller-bar buttons with slot and screen position", listPadButtons)
slash("page", "page", "show the controller bar arrangement (page)", probePage)
slash("pagecontrols", "pagecontrols", "inspect the controller page tracker and shortcut menu",
  inspectPageControls)
slash("frames", "frames <text>", "list named frames containing text, shown or hidden", findFrames)
slash("newframes", "newframes [s]", "list frames that appear within s seconds (default 5)",
  function(rest) newFrames(tonumber(rest) or 5) end)
slash("inspect", "inspect <name>", "list a frame's fields, functions and children", function(rest)
  local frame = frameByName(rest)
  if frame then inspectFrame(frame, frame:GetName() or rest) end
end)
