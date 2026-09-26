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
local tickers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end,
  NewTicker = function(_, fn) table.insert(tickers, fn) end }
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
function SetBindingSpell(k, s) bindings[k] = "SPELL " .. s end
function SetBindingMacro(k, m) bindings[k] = "MACRO " .. m end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end end
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

-- Dialog frames and APIs used by Commands.lua.
local open = {}
local function frame(name) _G[name] = { IsShown = function() return open[name] end } end
for _, n in ipairs({ "ClassTrainerFrame", "GossipFrame", "QuestFrameDetailPanel", "QuestFrameProgressPanel",
  "QuestFrameRewardPanel", "QuestFrameGreetingPanel", "LootFrame", "MerchantFrame" }) do
  frame(n)
end
local calls = {}
local function record(name) return function(...) table.insert(calls, { name, ... }) end end
C_GossipInfo = {
  GetActiveQuests = function() return { { title = "Wolves", questID = 10, isComplete = true } } end,
  GetAvailableQuests = function() return { { title = "Boars", questID = 11 } } end,
  GetOptions = function()
    return { { name = "Train me", gossipOptionID = 2, orderIndex = 2 },
             { name = "Tell me more", gossipOptionID = 1, orderIndex = 1 } }
  end,
  SelectActiveQuest = record("SelectActiveQuest"),
  SelectAvailableQuest = record("SelectAvailableQuest"),
  SelectOption = record("SelectOption"),
}
AcceptQuest, CompleteQuest, GetQuestReward = record("AcceptQuest"), record("CompleteQuest"), record("GetQuestReward")
function IsQuestCompletable() return true end
local questChoices = 0
function GetNumQuestChoices() return questChoices end
function GetQuestItemInfo(_, i) return ({ "Staff", "Robe" })[i] end
function GetNumActiveQuests() return 0 end
function GetNumAvailableQuests() return 0 end
function GetNumLootItems() return 2 end
function GetLootSlotInfo(i) return nil, ({ "Linen Cloth", "Copper Coin" })[i], i end
LootSlot = record("LootSlot")
C_MerchantFrame = { SellAllJunkItems = record("SellAllJunkItems") }
function CanMerchantRepair() return true end
RepairAllItems = record("RepairAllItems")
local services = { { "Frost Nova", "", "available" }, { "Fireball", "Rank 2", "used" },
  { "Frost Armor", "Rank 2", "available" }, { "Blizzard", "", "unavailable" } }
function GetNumTrainerServices() return #services end
function GetTrainerServiceInfo(i) return unpack(services[i]) end
BuyTrainerService = record("BuyTrainerService")
StaticPopup1 = { IsShown = function() return open.StaticPopup1 end,
  button1 = { Click = record("PopupAccept") } }
local function called(name, arg)
  for _, c in ipairs(calls) do if c[1] == name and (arg == nil or c[2] == arg) then return true end end
end

-- Defaults WoW ships with.
bindings["1"], bindings.W, bindings.UP = "ACTIONBUTTON1", "MOVEFORWARD", "MOVEFORWARD"

dofile("addon/WowKeys/Layout.lua")
dofile("addon/WowKeys/Commands.lua")
dofile("addon/WowKeys/WowKeys.lua")
local owner = frames.WowKeysFrame
local function fire(e, ...) owner.scripts.OnEvent(owner, e, ...) end
local function said(pattern)
  for _, p in ipairs(printed) do if p:find(pattern) then return true end end
end
local function check(ok, what) if not ok then error("FAILED: " .. what, 2) end end

fire("PLAYER_ENTERING_WORLD", true, false)

check(bindings.J == "ACTIONBUTTON1", "J bound")
check(GetBindingKey("ACTIONBUTTON1") == "J", "old key 1 unbound from ACTIONBUTTON1")
check(bindings["1"] == "CLICK WowKeysCmd_choose1", "1 picks dialog option 1")
check(bindings.G == "CLICK WowKeysCmd_confirm", "G confirms")
check(bindings["ALT-CTRL-SHIFT-J"] == "SPELL Frost Armor", "world J casts Frost Armor directly")
check(bindings["CTRL-J"] == "MACRO HealthPot", "leader J drinks a potion")
check(bindings["ALT-CTRL-U"] == "OPENALLBAGS", "UI U opens bags")
check(macros.HealthPot and macros.Hearth and macros.Blizzard, "macros created")
check(bindings.E == "MOVEFORWARD" and bindings.W == "STRAFELEFT" and bindings.S == "TURNLEFT", "movement")
check(bindings.UP == nil, "old UP unbound from MOVEFORWARD")
check(bindings["ALT-CTRL-SHIFT-F12"] == "CLICK WowKeysMode_chat", "banner chord")
check(cvars.autoLootDefault == "1", "auto loot on")
check(said("no setting AutoPushSpellToActionBar"), "unknown cvar reported")

check(actions[1][2] == 116 and actions[4][2] == 133, "known spells placed")
check(actions[6] == nil and actions[7] == nil, "duplicate Frostbolt/Fireball cleared")
check(actions[3] == nil and actions[5] == nil, "stray spells cleared from managed slots")
check(actions[10][1] == "item" and actions[12][1] == "item", "items left alone")
check(actions[8][1] == "macro", "Blizzard macro")
check(actions[182][2] == 116 and actions[181] == nil, "controller: Frostbolt on D-pad Up; unlearned Fire Blast slot empty")
check(actions[189][1] == "macro" and actions[190][1] == "macro", "controller: Poly and Blizzard macros on LT face buttons")
check(actions[202][2] == 168 and actions[203][2] == 1459, "controller: buffs on LT+RT")
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

-- Dialogs. A gossip NPC with a quest to turn in, a new quest, two options.
local cmd = function(name) frames["WowKeysCmd_" .. name].scripts.OnClick() end
open.GossipFrame = true
printed = {}
cmd("choose1")
check(called("SelectActiveQuest", 10), "1 turns in the active quest")
cmd("choose2")
check(called("SelectAvailableQuest", 11), "2 picks the new quest")
cmd("choose3")
check(called("SelectOption", 1), "3 is the first gossip option by orderIndex")
cmd("choose9")
check(said("only 4 option"), "out-of-range pick explains itself")
open.GossipFrame = nil

open.QuestFrameDetailPanel = true
cmd("confirm")
check(called("AcceptQuest"), "G accepts a quest")
open.QuestFrameDetailPanel = nil

open.QuestFrameRewardPanel, questChoices = true, 2
calls = {}
cmd("confirm")
check(not called("GetQuestReward") and said("pick a reward with 1%-2"), "G asks to pick a reward")
cmd("choose2")
check(called("GetQuestReward", 2), "2 takes the second reward")
open.QuestFrameRewardPanel, questChoices = nil, 0

open.StaticPopup1, open.LootFrame = true, true
cmd("confirm")
check(called("PopupAccept") and not called("LootSlot"), "popups come first")
open.StaticPopup1 = nil
cmd("confirm")
check(called("LootSlot", 1) and called("LootSlot", 2), "G loots everything")
open.LootFrame = nil

-- Trainer: numbers pick among spells you can learn now; G learns the first.
open.ClassTrainerFrame = true
printed = {}
for _, fn in ipairs(timers) do fn() end
timers = {}
cmd("choose2")
check(called("BuyTrainerService", 3), "2 learns the second available spell (list row 3)")
check(#timers == 1, "list printed again after learning")
timers[1](); timers = {}
check(said("Frost Nova") and said("Frost Armor %(Rank 2%)") and not said("Fireball"), "only learnable spells listed")
calls = {}
cmd("confirm")
check(called("BuyTrainerService", 1), "G learns the first available spell")
open.ClassTrainerFrame = nil
cmd("choose1")
check(said("nothing to pick from"), "explains where numbers work")

cmd("vendor")
check(said("talk to a vendor first"), "vendor needs a vendor")
open.MerchantFrame = true
cmd("vendor")
check(called("SellAllJunkItems") and called("RepairAllItems"), "vendor sells junk and repairs")

-- /wowkeys find lists binding commands for layout.toml.
local allBindings = { { "MOVEFORWARD", "HEADER", "E" }, { "HEADER_AUCTIONATOR", "ADDONS" },
  { "AUCTIONATOR_POST", "ADDONS" }, { "AUCTIONATOR_CANCEL", "ADDONS" } }
function GetNumBindings() return #allBindings end
function GetBinding(i) return unpack(allBindings[i]) end
function GetBindingName(c) return ({ AUCTIONATOR_POST = "Post item" })[c] or c end
printed = {}
SlashCmdList.WOWKEYS("find auctionator")
check(said("AUCTIONATOR_POST.*Post item") and said("2 binding%(s%) match"), "find lists matching bindings")
check(not said("HEADER_AUCTIONATOR"), "find skips keybinding-menu headers")

-- /wowkeys pad lists controller bindings and gamepad CVars.
allBindings = { { "JUMP", "MOVEMENT", "SPACE", "PAD1" }, { "ACTIONBUTTON1", "ACTIONBAR", "J", "SHIFT-PAD2" },
  { "VEHICLEEXIT", "VEHICLE", "NUMPAD5" } }
cvars.GamePadEnable, cvars.GamePadEmulateShift = "1", "PADLTRIGGER"
printed = {}
SlashCmdList.WOWKEYS("pad")
check(said("PAD1  %->  JUMP") and said("SHIFT%-PAD2  %->  ACTIONBUTTON1"), "pad lists pad bindings")
check(said("2 controller binding") and said("GamePadEmulateShift = PADLTRIGGER"), "pad shows gamepad cvars")
check(not said("NUMPAD5"), "numpad keys aren't controller buttons")

-- /wowkeys slots lists filled action slots by id.
printed = {}
SlashCmdList.WOWKEYS("slots")
check(said("  1  spell  Frostbolt"), "slots lists a spell slot by id")
check(said("filled action slot"), "slots prints a count")

-- /wowkeys padbuttons lists frames pointing at slots above 180.
local fakeFrames = {
  { action = 197, GetDebugName = function() return "GamepadMainActionBarFramePageUnitRightCenteredAnchorRightBarActionButton5" end,
    GetCenter = function() return 900.4, 120.6 end },
  { action = 197, GetDebugName = function() return "GamepadActionBarEditFramePageUnitRightCenteredAnchorRightBarActionButton5" end },
  { action = 5 },
  { action = 182, GetDebugName = function() return "GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton2" end },
}
function EnumerateFrames(after)
  if not after then return fakeFrames[1] end
  for i, f in ipairs(fakeFrames) do if f == after then return fakeFrames[i + 1] end end
end
printed = {}
SlashCmdList.WOWKEYS("padbuttons")
check(said("182  Top.2") and said("197  Right.5  %(900, 120%)"), "padbuttons shows short names and positions")
check(said("2 button%(s%) on slots above 180"), "padbuttons skips keyboard slots and edit-frame duplicates")

-- /wowkeys frames lists named frames matching some text.
fakeFrames = {
  { GetName = function() return "GamepadShortcutNextPageButton" end, GetObjectType = function() return "Button" end,
    IsShown = function() return false end },
  { GetName = function() return "PlayerFrame" end },
  { GetName = function() return nil end },
}
printed = {}
SlashCmdList.WOWKEYS("frames page")
check(said("GamepadShortcutNextPageButton.*Button, hidden") and said("1 frame%(s%) match"), "frames finds named frames")

-- /wowkeys newframes lists frames shown after a delay that weren't before.
local menuUp = false
fakeFrames[1].IsShown = function() return menuUp end
fakeFrames[2].IsShown = function() return true end
printed, timers = {}, {}
SlashCmdList.WOWKEYS("newframes 3")
check(#timers == 1 and said("listing new frames in 3 s"), "newframes waits")
menuUp = true
timers[1](); timers = {}
check(said("GamepadShortcutNextPageButton.*shown") and not said("PlayerFrame")
  and said("1 frame%(s%) appeared in the last 3 s"), "newframes lists only frames that appeared")

-- /wowkeys inspect shows a frame's fields, functions and children.
local nextButton = { GetName = function() end, GetObjectType = function() return "Button" end,
  IsShown = function() return true end, GetText = function() return "Next" end }
local shortcuts = { currentPage = 2, NextPage = function() end, Next = nextButton,
  GetName = function() return "GamepadMainActionBarFramePageUnitShortcutsActionBar" end,
  GetObjectType = function() return "Frame" end, GetChildren = function() return nextButton end }
fakeFrames = { shortcuts, { GetName = function() return "PlayerFrame" end } }
printed = {}
SlashCmdList.WOWKEYS("inspect ShortcutsActionBar")
check(said("currentPage=2") and said("NextPage") and said("Next Button \"Next\""), "inspect lists fields, functions, children")
printed = {}
SlashCmdList.WOWKEYS("inspect Frame")
check(said("2 frame%(s%) match"), "inspect asks to pick when several frames match")

-- /wowkeys page probes the Gamepad UI's page functions.
local pageNow = 1
GamepadMainActionBarFramePageUnit = {
  GetCurrentPage = function() return pageNow end,
  SetCurrentPage = function(_, n) pageNow = n end,
  pageableActionBarsIndexOrder = { { GetName = function() return "PageBar1" end } },
}
printed = {}
SlashCmdList.WOWKEYS("page")
check(said("GetCurrentPage %-> 1") and said("page order 1: PageBar1"), "page shows the current page")
printed = {}
SlashCmdList.WOWKEYS("page 2")
check(said("SetCurrentPage%(2%) ran") and said("GetCurrentPage %-> 2"), "page n switches")
GamepadMainActionBarFramePageUnit.SetCurrentPage = function() error("blocked") end
printed = {}
SlashCmdList.WOWKEYS("page 3")
check(said("SetCurrentPage%(3%) failed: .*blocked"), "page reports a blocked switch")
GamepadMainActionBarFramePageUnit = nil

-- Controller arrangement shows in the banner, and updates when it changes.
frames.WowKeysMode_combat.scripts.OnClick()
check(banner == "-- COMBAT --", "no arrangement shown without the Gamepad UI")
local padButton = { action = 209, IsVisible = function() return true end }
_G.GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton1 = padButton
for _, fn in ipairs(tickers) do fn() end
check(banner == "-- COMBAT · BAR 2 --", "banner shows arrangement 2")
padButton.action = 181
for _, fn in ipairs(tickers) do fn() end
check(banner == "-- COMBAT · BAR 1 --", "banner follows arrangement changes")
_G.GamepadMainActionBarFramePageUnitTopCenteredAnchorTopBarActionButton1 = nil
for _, fn in ipairs(tickers) do fn() end

-- Chat banner, then combat starts: warning sound.
frames.WowKeysMode_chat.scripts.OnClick()
check(banner == "-- CHAT --", "banner")
combat = true
fire("PLAYER_REGEN_DISABLED")
check(sounds == 1, "combat warning")
combat = false
fire("PLAYER_REGEN_ENABLED")

io.write("dry run ok\n")
