-- WowKeys: applies Layout.lua (generated from layout.toml) and shows the
-- current kanata mode, like Vim's `-- INSERT --`.
--
-- On every login it rewrites the bindings from the layout and saves them,
-- so the layout file always wins and WoW's own UI (button hotkey labels,
-- the keybinding menu) shows the real keys. Bars are re-placed when the
-- layout's buttons change, when you learn a spell, or on `/wowkeys bars`.

local L = WowKeysLayout
local home = L.modes[1]
local owner = CreateFrame("Frame", "WowKeysFrame", UIParent)
local current = home

-- Mode banner -------------------------------------------------------------

local banner = owner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
banner:SetPoint("TOP", UIParent, "TOP", 0, -12)

-- Which controller bar arrangement is on screen (1-3), read from the slot
-- the Gamepad UI's first bar button shows: 181, 209 or 237. Nil when the
-- Gamepad UI isn't showing.
local PAD_FIRST_BUTTON = "GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton1"

local function padArrangement()
  local button = _G[PAD_FIRST_BUTTON]
  if not (button and button:IsVisible()) then return nil end
  local slot = button.action or (button.GetAttribute and button:GetAttribute("action"))
  if type(slot) ~= "number" or slot < 181 then return nil end
  return math.floor((slot - 181) / 28) + 1
end

local shownArrangement

local function showMode()
  shownArrangement = padArrangement()
  local suffix = shownArrangement and (" · BAR " .. shownArrangement) or ""
  banner:SetText("-- " .. current.label .. suffix .. " --")
  if InCombatLockdown() and current ~= home then
    banner:SetTextColor(1, 0.2, 0.2)
  else
    banner:SetTextColor(1, 0.82, 0)
  end
end

-- One hidden button per mode; kanata's banner chord "clicks" it.
local function modeButtonName(mode)
  return "WowKeysMode_" .. mode.name
end

for _, mode in ipairs(L.modes) do
  local button = CreateFrame("Button", modeButtonName(mode), owner)
  button:SetScript("OnClick", function()
    current = mode
    showMode()
  end)
end

-- Addon commands --------------------------------------------------------

-- One hidden button per command in Commands.lua; bindings "click" it.
local function commandButtonName(name)
  return "WowKeysCmd_" .. name
end

for name, fn in pairs(WowKeysCommands) do
  local button = CreateFrame("Button", commandButtonName(name), owner)
  button:SetScript("OnClick", fn)
end

-- Settings ----------------------------------------------------------------

local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
local setCVar = C_CVar and C_CVar.SetCVar or SetCVar

local function applyCVars()
  for _, c in ipairs(L.cvars) do
    if getCVar(c[1]) == nil then
      print("WowKeys: this client has no setting " .. c[1])
    else
      setCVar(c[1], c[2])
    end
  end
end

-- Macros ------------------------------------------------------------------

local function applyMacros()
  for _, m in ipairs(L.macros) do
    local name, body = m[1], m[2]
    local index = GetMacroIndexByName(name)
    if index == 0 then
      local ok = pcall(CreateMacro, name, "INV_MISC_QUESTIONMARK", body, true)
      if not ok then
        print("WowKeys: couldn't create macro " .. name .. " (macro slots full?)")
      end
    else
      EditMacro(index, name, nil, body)
    end
  end
end

-- Bindings ----------------------------------------------------------------

-- Commands in Layout.lua: a WoW binding command, "SPELL <name>",
-- "MACRO <name>", or "wowkeys:<command>".
local function bind(key, command)
  local addonCommand = command:match("^wowkeys:(.+)$")
  local spell = command:match("^SPELL (.+)$")
  local macro = command:match("^MACRO (.+)$")
  if addonCommand then
    SetBindingClick(key, commandButtonName(addonCommand))
  elseif spell then
    SetBindingSpell(key, spell)
  elseif macro then
    SetBindingMacro(key, macro)
  else
    SetBinding(key, command)
  end
end

local function isPlainCommand(command)
  return not (command:find("^wowkeys:") or command:find("^SPELL ") or command:find("^MACRO "))
end

local function applyBindings()
  -- Unbind other keys from the commands we own (e.g. `1` from
  -- ACTIONBUTTON1), so button labels show our key, not the old one.
  local ours = {}
  for _, b in ipairs(L.bindings) do
    if isPlainCommand(b[2]) then
      ours[b[2]] = ours[b[2]] or {}
      ours[b[2]][b[1]] = true
    end
  end
  for command, keys in pairs(ours) do
    for _, key in ipairs({ GetBindingKey(command) }) do
      if not keys[key] then
        SetBinding(key)
      end
    end
  end

  for _, b in ipairs(L.bindings) do
    bind(b[1], b[2])
  end
  for _, mode in ipairs(L.modes) do
    if mode.key then -- one-shot modes have no banner
      SetBindingClick(mode.key, modeButtonName(mode))
    end
  end
  SaveBindings(GetCurrentBindingSet())
end

-- Bars --------------------------------------------------------------------

local pickupSpell = C_Spell and C_Spell.PickupSpell or PickupSpell
local spellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo

local function pickup(b)
  if b.spell then
    pickupSpell(b.spell)
  else
    PickupMacro(b.macro)
  end
end

-- Puts every layout button in its slot. A slot whose spell you haven't
-- learned yet is emptied of any other spell, so nothing shows up twice;
-- items and macros there are left alone.
local function applyBars(verbose)
  local missing, cleared = {}, {}
  for _, b in ipairs(L.buttons) do
    ClearCursor()
    pickup(b)
    if GetCursorInfo() then
      PlaceAction(b.slot) -- whatever was there lands on the cursor...
      ClearCursor()       -- ...and is dropped (the spell itself is untouched)
    else
      table.insert(missing, b.spell or b.macro)
      local kind, id = GetActionInfo(b.slot)
      if kind == "spell" then
        table.insert(cleared, spellName(id) or tostring(id))
        PickupAction(b.slot)
        ClearCursor()
      end
    end
  end
  WowKeysDB.revision = L.revision

  if #cleared > 0 then
    print("WowKeys: took off the bars (not in layout.toml): " .. table.concat(cleared, ", "))
  end
  if verbose then
    if #missing > 0 then
      print("WowKeys: not learned yet: " .. table.concat(missing, ", "))
    else
      print("WowKeys: bars placed")
    end
  end
end

-- Wiring ------------------------------------------------------------------

-- Bindings, bars and settings can't change in combat; queue until it ends,
-- in order (macros must exist before bindings use them).
local pending = {}

local function outOfCombat(fn)
  if not InCombatLockdown() then
    fn()
  elseif not tContains(pending, fn) then
    table.insert(pending, fn)
  end
end

local function applyBarsVerbose() applyBars(true) end
local function applyBarsQuiet() applyBars(false) end

owner:RegisterEvent("PLAYER_ENTERING_WORLD")
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
-- The "learned a spell" event was renamed in 11.0; take whichever exists.
pcall(owner.RegisterEvent, owner, "LEARNED_SPELL_IN_SKILL_LINE")
pcall(owner.RegisterEvent, owner, "LEARNED_SPELL_IN_TAB")

owner:SetScript("OnEvent", function(_, event, isInitialLogin, isReload)
  if event == "PLAYER_ENTERING_WORLD" then
    if isInitialLogin or isReload then
      WowKeysDB = WowKeysDB or {}
      outOfCombat(applyCVars)
      outOfCombat(applyMacros) -- before bindings and bars that use them
      outOfCombat(applyBindings)
      if WowKeysDB.revision ~= L.revision then
        outOfCombat(applyBarsVerbose)
      end
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    showMode()
    if current ~= home then
      PlaySound(SOUNDKIT.RAID_WARNING)
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    for _, fn in ipairs(pending) do
      fn()
    end
    pending = {}
    showMode()
  else -- learned a spell
    -- Wait a moment so WoW finishes any bar changes of its own first.
    C_Timer.After(1, function() outOfCombat(applyBarsQuiet) end)
  end
end)

showMode()

-- The Gamepad UI has no event we know of for arrangement changes, so check
-- a few times a second and redraw only when it changes.
C_Timer.NewTicker(0.25, function()
  if padArrangement() ~= shownArrangement then showMode() end
end)

SLASH_WOWKEYS1 = "/wowkeys"
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
  "GamePadEmulateAlt", "GamePadEmulateEsc" }

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

-- Calls fn(frame, name) for every named frame.
local function eachNamedFrame(fn)
  local frame = EnumerateFrames()
  while frame do
    local ok, name = pcall(frame.GetName, frame)
    if ok and name then fn(frame, name) end
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

SlashCmdList.WOWKEYS = function(arg)
  local text = arg:match("^find%s+(.+)$")
  local frameText = arg:match("^frames%s+(.+)$")
  local newWait = arg:match("^newframes%s*(%d*)$")
  if arg == "bars" then
    outOfCombat(applyBarsVerbose)
  elseif arg == "pad" then
    padBindings()
  elseif arg == "slots" then
    listSlots()
  elseif arg == "padbuttons" then
    listPadButtons()
  elseif newWait then
    newFrames(tonumber(newWait) or 5)
  elseif frameText then
    findFrames(frameText)
  elseif text then
    findBindings(text)
  else
    print("WowKeys: mode " .. current.label .. ", layout " .. L.revision)
    print("  /wowkeys bars         re-place spells and macros on the bars")
    print("  /wowkeys find <text>  list binding commands to use in layout.toml")
    print("  /wowkeys pad          list controller bindings and settings")
    print("  /wowkeys slots        list filled action slots by id")
    print("  /wowkeys padbuttons   list controller-bar buttons and their slots")
    print("  /wowkeys frames <text> list named frames (find buttons to click)")
    print("  /wowkeys newframes [s] list frames that appear within s seconds (default 5)")
  end
end
