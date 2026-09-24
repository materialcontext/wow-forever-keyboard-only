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

local function showMode()
  banner:SetText("-- " .. current.label .. " --")
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

-- Bindings ----------------------------------------------------------------

local function applyBindings()
  -- Unbind other keys from the commands we own (e.g. `1` from
  -- ACTIONBUTTON1), so button labels show our key, not the old one.
  local ours = {}
  for _, b in ipairs(L.bindings) do
    ours[b[2]] = ours[b[2]] or {}
    ours[b[2]][b[1]] = true
  end
  for command, keys in pairs(ours) do
    for _, key in ipairs({ GetBindingKey(command) }) do
      if not keys[key] then
        SetBinding(key)
      end
    end
  end

  for _, b in ipairs(L.bindings) do
    SetBinding(b[1], b[2])
  end
  for _, mode in ipairs(L.modes) do
    SetBindingClick(mode.key, modeButtonName(mode))
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
    local index = GetMacroIndexByName(b.macro)
    if index == 0 then
      CreateMacro(b.macro, "INV_MISC_QUESTIONMARK", b.body, true)
    else
      EditMacro(index, b.macro, nil, b.body)
    end
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

-- Bindings, bars and settings can't change in combat; queue until it ends.
local pending = {}

local function outOfCombat(fn)
  if InCombatLockdown() then
    pending[fn] = true
  else
    fn()
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
    for fn in pairs(pending) do
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

SLASH_WOWKEYS1 = "/wowkeys"
SlashCmdList.WOWKEYS = function(arg)
  if arg == "bars" then
    outOfCombat(applyBarsVerbose)
  else
    print("WowKeys: mode " .. current.label .. ", layout " .. L.revision)
    print("  /wowkeys bars  re-place spells and macros on the bars")
  end
end
