-- WowKeys: applies Layout.lua (generated from layout.toml) and shows the
-- current kanata mode, like Vim's `-- INSERT --`.
--
-- Bindings are override bindings, set fresh on every login from the layout,
-- so the layout file is always the truth. WoW's keybinding menu still shows
-- the base bindings underneath. Bars are only re-placed when the layout's
-- buttons change (or on `/wowkeys bars`), since that moves things around.

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

-- Bindings ----------------------------------------------------------------

local function applyBindings()
  ClearOverrideBindings(owner)
  for _, b in ipairs(L.bindings) do
    SetOverrideBinding(owner, false, b[1], b[2])
  end
  for _, mode in ipairs(L.modes) do
    SetOverrideBindingClick(owner, true, mode.key, modeButtonName(mode))
  end
end

-- Bars --------------------------------------------------------------------

local pickupSpell = C_Spell and C_Spell.PickupSpell or PickupSpell

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

local function applyBars()
  local missing = {}
  for _, b in ipairs(L.buttons) do
    ClearCursor()
    pickup(b)
    if GetCursorInfo() then
      PlaceAction(b.slot) -- whatever was there lands on the cursor...
      ClearCursor()       -- ...and is dropped (the spell itself is untouched)
    else
      table.insert(missing, b.spell or b.macro)
    end
  end
  WowKeysDB.revision = L.revision
  if #missing > 0 then
    print("WowKeys: couldn't place " .. table.concat(missing, ", ")
      .. " (not known? check spell names in layout.toml)")
  else
    print("WowKeys: bars placed")
  end
end

-- Wiring ------------------------------------------------------------------

-- Bindings and bars can't change in combat; queue until it ends.
local pending = {}

local function outOfCombat(fn)
  if InCombatLockdown() then
    pending[fn] = true
  else
    fn()
  end
end

owner:RegisterEvent("PLAYER_ENTERING_WORLD")
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:SetScript("OnEvent", function(_, event, isInitialLogin, isReload)
  if event == "PLAYER_ENTERING_WORLD" then
    if isInitialLogin or isReload then
      WowKeysDB = WowKeysDB or {}
      outOfCombat(applyBindings)
      if WowKeysDB.revision ~= L.revision then
        outOfCombat(applyBars)
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
  end
end)

showMode()

SLASH_WOWKEYS1 = "/wowkeys"
SlashCmdList.WOWKEYS = function(arg)
  if arg == "bars" then
    outOfCombat(applyBars)
  else
    print("WowKeys: mode " .. current.label .. ", layout " .. L.revision)
    print("  /wowkeys bars  re-place spells and macros on the bars")
  end
end
