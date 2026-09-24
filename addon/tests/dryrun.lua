-- Offline dry run of WowKeys against stubbed WoW APIs.
-- Run from the repo root: lua5.1 addon/tests/dryrun.lua
-- Scenario: a level 5 mage whose bars WoW already filled.

local combat, cursor = false, nil
local frames, bindings, macros, cvars, timers = {}, {}, {}, { autoLootDefault = "0" }, {}
local printed, sounds, banner = {}, 0, nil
local spells = { [116] = "Frostbolt", [133] = "Fireball", [168] = "Frost Armor", [1459] = "Arcane Intellect" }
local known = { Frostbolt = 116, Fireball = 133, ["Frost Armor"] = 168, ["Arcane Intellect"] = 1459 }
-- What WoW put on the bars before WowKeys ran (the user's screenshot).
local actions = {
  [1] = { "spell", 116 }, [3] = { "spell", 168 }, [4] = { "spell", 133 },
  [5] = { "spell", 1459 }, [6] = { "spell", 116 }, [7] = { "spell", 133 },
  [10] = { "item", 1 }, [11] = { "item", 2 }, [12] = { "item", 3 },
}

function CreateFrame(_, name)
  local f = { scripts = {} }
  function f:CreateFontString()
    return { SetPoint = function() end, SetText = function(_, t) banner = t end, SetTextColor = function() end }
  end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:RegisterEvent(e)
    if e == "LEARNED_SPELL_IN_TAB" then error("unknown event") end
  end
  if name then frames[name] = f end
  return f
end
UIParent, SOUNDKIT = {}, { RAID_WARNING = 1 }
function PlaySound() sounds = sounds + 1 end
function InCombatLockdown() return combat end
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
C_CVar = {
  GetCVar = function(n) return cvars[n] end,
  SetCVar = function(n, v) cvars[n] = v end,
}
function GetBindingKey(command)
  local keys = {}
  for k, c in pairs(bindings) do if c == command then table.insert(keys, k) end end
  table.sort(keys)
  return unpack(keys)
end
function SetBinding(k, c) bindings[k] = c end
function SetBindingClick(k, b) bindings[k] = "CLICK " .. b end
function GetCurrentBindingSet() return 1 end
function SaveBindings() end
C_Spell = {
  PickupSpell = function(s) cursor = known[s] and { "spell", known[s] } or nil end,
  GetSpellName = function(id) return spells[id] end,
}
function GetMacroIndexByName(n) return macros[n] and 1 or 0 end
function CreateMacro(n, _, body) macros[n] = body end
function EditMacro(_, n, _, body) macros[n] = body end
function PickupMacro(n) cursor = macros[n] and { "macro", n } end
function GetCursorInfo() return cursor end
function ClearCursor() cursor = nil end
function PlaceAction(slot) cursor, actions[slot] = actions[slot], cursor end
function PickupAction(slot) cursor, actions[slot] = actions[slot], nil end
function GetActionInfo(slot) local a = actions[slot]; if a then return a[1], a[2] end end
function print(msg) table.insert(printed, msg) end
SlashCmdList = {}

-- Defaults WoW ships with.
bindings["1"], bindings.W, bindings.UP = "ACTIONBUTTON1", "MOVEFORWARD", "MOVEFORWARD"

dofile("addon/WowKeys/Layout.lua")
dofile("addon/WowKeys/WowKeys.lua")
local owner = frames.WowKeysFrame
local function fire(e, ...) owner.scripts.OnEvent(owner, e, ...) end
local function said(pattern)
  for _, p in ipairs(printed) do if p:find(pattern) then return true end end
end
local function check(ok, what) if not ok then error("FAILED: " .. what, 2) end end

fire("PLAYER_ENTERING_WORLD", true, false)

check(bindings.J == "ACTIONBUTTON1", "J bound")
check(bindings["1"] == nil, "old key 1 unbound from ACTIONBUTTON1")
check(bindings.E == "MOVEFORWARD" and bindings.W == "TURNLEFT", "movement")
check(bindings.UP == nil, "old UP unbound from MOVEFORWARD")
check(bindings["ALT-CTRL-SHIFT-F12"] == "CLICK WowKeysMode_chat", "banner chord")
check(cvars.autoLootDefault == "1", "auto loot on")
check(said("no setting AutoPushSpellToActionBar"), "unknown cvar reported")

check(actions[1][2] == 116 and actions[4][2] == 133, "known spells placed")
check(actions[6] == nil and actions[7] == nil, "duplicate Frostbolt/Fireball cleared")
check(actions[3] == nil and actions[5] == nil, "stray spells cleared from managed slots")
check(actions[10][1] == "item" and actions[12][1] == "item", "items left alone")
check(actions[68][2] == 168 and actions[69][2] == 1459, "buffs on G/B")
check(actions[8][1] == "macro", "Blizzard macro")
check(said("took off the bars.*Frostbolt"), "reports what it cleared")
check(said("not learned yet: .*Ice Lance"), "reports unlearned spells")

-- Level 6: learn Fire Blast; WoW drops it in empty slot 6 on its own.
known["Fire Blast"], spells[2136] = 2136, "Fire Blast"
actions[6] = { "spell", 2136 }
printed = {}
fire("LEARNED_SPELL_IN_SKILL_LINE")
for _, fn in ipairs(timers) do fn() end
check(actions[3][2] == 2136, "Fire Blast lands on L")
check(actions[6] == nil, "WoW's extra copy cleared")
check(not said("not learned yet"), "quiet on learn")

-- Chat banner, then combat starts: warning sound.
frames.WowKeysMode_chat.scripts.OnClick()
check(banner == "-- CHAT --", "banner")
combat = true
fire("PLAYER_REGEN_DISABLED")
check(sounds == 1, "combat warning")
combat = false
fire("PLAYER_REGEN_ENABLED")

io.write("dry run ok\n")
