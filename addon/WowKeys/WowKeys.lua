-- WowKeys: applies Layout.lua (generated from layout.toml) and shows the
-- current kanata mode, like Vim's `-- INSERT --`. Also strafe mode and
-- controller bar paging. Probes for learning how the game works live in
-- Diagnostics.lua. Files share the addon's private namespace `ns`.
--
-- On every login it rewrites the bindings from the layout and saves them,
-- so the layout file always wins and WoW's own UI (button hotkey labels,
-- the keybinding menu) shows the real keys. Bars are re-placed when the
-- layout's buttons change, when you learn a spell, or on `/wowkeys bars`.

local _, ns = ...
local L = ns.layout
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

-- Controller strafe mode, via the Gamepad UI's "face movement" angle. In
-- Forever 0 (the default) turns the character toward the stick; 180 keeps
-- it facing ahead, so the stick strafes left/right and backpedals
-- (tested: the owner found our first guess, 0 = strafe, backwards).
local FACE_CVARS = { "GamePadFaceMovementMaxAngle", "GamePadFaceMovementMaxAngleCombat" }
local STRAFE_ANGLE = "180"
local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
local setCVar = C_CVar and C_CVar.SetCVar or SetCVar

local function strafing()
  return (tonumber(getCVar(FACE_CVARS[1])) or 0) >= tonumber(STRAFE_ANGLE)
end

local function showMode()
  shownArrangement = padArrangement()
  local suffix = (shownArrangement and (" · BAR " .. shownArrangement) or "")
    .. (strafing() and " · STRAFE" or "")
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

-- Toggles strafe mode, restoring the angles you had before (saved per
-- character; 0 if none were saved).
ns.commands.strafe = function()
  if getCVar(FACE_CVARS[1]) == nil then
    print("WowKeys: this client has no " .. FACE_CVARS[1] .. "; try /wowkeys pad for the gamepad settings")
    return
  end
  WowKeysDB = WowKeysDB or {}
  local db = WowKeysDB
  local turning = not strafing()
  if turning then db.faceAngles = {} end
  for _, name in ipairs(FACE_CVARS) do
    local value = getCVar(name)
    if value ~= nil then
      if turning then
        db.faceAngles[name] = value
        setCVar(name, STRAFE_ANGLE)
      else
        local saved = db.faceAngles and tonumber(db.faceAngles[name])
        setCVar(name, (saved and saved < tonumber(STRAFE_ANGLE)) and tostring(saved) or "0")
      end
    end
  end
  showMode()
end

-- One hidden button per command (Commands.lua, plus strafe above);
-- bindings "click" it.
local function commandButtonName(name)
  return "WowKeysCmd_" .. name
end

for name, fn in pairs(ns.commands) do
  local button = CreateFrame("Button", commandButtonName(name), owner)
  button:SetScript("OnClick", fn)
end

-- Settings ----------------------------------------------------------------

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

-- Warns about binding commands the game doesn't know (a typo, or a name
-- that differs in Forever); CLICK commands name our own buttons instead.
local function reportUnknownCommands()
  if not GetNumBindings then return end
  local known, unknown = {}, {}
  for i = 1, GetNumBindings() do
    local command = GetBinding(i)
    if command then known[command] = true end
  end
  for _, b in ipairs(L.bindings) do
    local command = b[2]
    if isPlainCommand(command) and not command:find("^CLICK ") and not known[command] then
      table.insert(unknown, command)
    end
  end
  if #unknown > 0 then
    print("WowKeys: the game has no binding command " .. table.concat(unknown, ", ")
      .. " (find the right name with /wowkeys find)")
  end
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
  reportUnknownCommands()
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
  -- Our macros in a slot the layout now gives to something else are
  -- leftovers from an older layout; other macros and items are yours.
  local ourMacros = {}
  for _, m in ipairs(L.macros) do ourMacros[m[1]] = true end
  for _, b in ipairs(L.buttons) do
    ClearCursor()
    pickup(b)
    if GetCursorInfo() then
      PlaceAction(b.slot) -- whatever was there lands on the cursor...
      ClearCursor()       -- ...and is dropped (the spell itself is untouched)
    else
      table.insert(missing, b.spell or b.macro)
      local kind, id = GetActionInfo(b.slot)
      local macroName = kind == "macro" and GetMacroInfo(id)
      if kind == "spell" or (macroName and ourMacros[macroName] and macroName ~= b.macro) then
        table.insert(cleared, macroName or spellName(id) or tostring(id))
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

-- WowKeysPage: a secure button that clicks the Gamepad UI's own
-- change-page button, so a bound key ("CLICK WowKeysPage:LeftButton")
-- cycles controller arrangements as Blizzard code would. Calling
-- SetCurrentPage from an addon is blocked (tested). Secure buttons can
-- only be set up out of combat, and the Gamepad UI may appear later.
local pageButtonReady = false

local function setUpPageButton()
  local unit = GamepadMainActionBarFramePageUnit
  local target = unit and unit.PageTracker and unit.PageTracker.ChangePageButton
  if not target then return false end
  local button = CreateFrame("Button", "WowKeysPage", UIParent, "SecureActionButtonTemplate")
  -- Both transitions; the template acts on the one ActionButtonUseKeyDown picks.
  button:RegisterForClicks("AnyUp", "AnyDown")
  button:SetAttribute("type", "click")
  button:SetAttribute("clickbutton", target)
  return true
end

-- The Gamepad UI has no event we know of for arrangement changes, so check
-- a few times a second and redraw only when it changes.
C_Timer.NewTicker(0.25, function()
  if not pageButtonReady and not InCombatLockdown() then
    pageButtonReady = setUpPageButton()
  end
  if padArrangement() ~= shownArrangement then showMode() end
end)

-- /wowkeys ----------------------------------------------------------------

-- Helpers Diagnostics.lua shares.
ns.getCVar, ns.spellName, ns.padArrangement = getCVar, spellName, padArrangement

-- tostring that survives values the client hides from addons.
function ns.safeString(v)
  local ok, s = pcall(function() return tostring(v) end)
  return ok and s or "?"
end

-- Subcommands: name -> { usage, help, run(rest) }. A usage with <...>
-- needs an argument. Diagnostics.lua registers its probes here too.
ns.slash = {}

function ns.addSlash(name, usage, help, run)
  ns.slash[name] = { usage = usage, help = help, run = run }
end

ns.addSlash("bars", "bars", "re-place spells and macros on the bars",
  function() outOfCombat(applyBarsVerbose) end)

local function dispatch(arg)
  local name, rest = arg:match("^(%S*)%s*(.-)%s*$")
  local entry = ns.slash[name]
  if entry and not (entry.usage:find("<", 1, true) and rest == "") then
    entry.run(rest)
    return
  end
  print("WowKeys: mode " .. current.label .. ", layout " .. L.revision)
  local names = {}
  for n in pairs(ns.slash) do table.insert(names, n) end
  table.sort(names)
  for _, n in ipairs(names) do
    print(("  /wowkeys %s  |cff999999%s|r"):format(ns.slash[n].usage, ns.slash[n].help))
  end
end

SLASH_WOWKEYS1 = "/wowkeys"
-- A failing command prints its error instead of failing silently.
SlashCmdList.WOWKEYS = function(arg)
  local ok, err = pcall(dispatch, arg)
  if not ok then print("WowKeys error: " .. ns.safeString(err)) end
end
