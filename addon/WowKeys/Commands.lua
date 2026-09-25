-- WowKeys commands: keyboard control of NPC dialogs, loot, popups and
-- vendors, bound through layout.toml as "wowkeys:<name>".
--
-- Which dialog is open is read from Blizzard's frames at the moment you
-- press the key, so event order never leaves it confused.

local function shown(name)
  local f = _G[name]
  return f and f:IsShown()
end

local function say(msg)
  print("WowKeys: " .. msg)
end

-- Numbered choices ---------------------------------------------------------
-- Each returns a list of { label, pick } in the order the numbers use.

local function gossipEntries()
  local list = {}
  for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
    local label = q.title .. (q.isComplete and " (turn in)" or " (in progress)")
    table.insert(list, { label, function() C_GossipInfo.SelectActiveQuest(q.questID) end })
  end
  for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
    table.insert(list, { q.title .. " (new)", function() C_GossipInfo.SelectAvailableQuest(q.questID) end })
  end
  local options = C_GossipInfo.GetOptions() or {}
  table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
  for _, o in ipairs(options) do
    table.insert(list, { o.name, function() C_GossipInfo.SelectOption(o.gossipOptionID) end })
  end
  return list
end

-- Older-style NPCs that list several quests without gossip text.
local function greetingEntries()
  local list = {}
  for i = 1, GetNumActiveQuests() do
    table.insert(list, { GetActiveTitle(i) .. " (active)", function() SelectActiveQuest(i) end })
  end
  for i = 1, GetNumAvailableQuests() do
    table.insert(list, { GetAvailableTitle(i) .. " (new)", function() SelectAvailableQuest(i) end })
  end
  return list
end

local function rewardEntries()
  local list = {}
  for i = 1, GetNumQuestChoices() do
    local name = GetQuestItemInfo("choice", i)
    table.insert(list, { name or ("reward " .. i), function() GetQuestReward(i) end })
  end
  return list
end

local function lootEntries()
  local list = {}
  for i = 1, GetNumLootItems() do
    local _, name, quantity = GetLootSlotInfo(i)
    local label = (name or "?") .. ((quantity or 0) > 1 and (" x" .. quantity) or "")
    table.insert(list, { label, function() LootSlot(i) end })
  end
  return list
end

local function currentEntries()
  if shown("LootFrame") then return lootEntries() end
  if shown("QuestFrameRewardPanel") then return rewardEntries() end
  if shown("QuestFrameGreetingPanel") then return greetingEntries() end
  if shown("GossipFrame") then return gossipEntries() end
end

local function printEntries()
  local entries = currentEntries()
  if not entries or #entries < 2 then return end
  for i, e in ipairs(entries) do
    print(("  |cffffd200%d|r  %s"):format(i, e[1]))
  end
end

local function choose(n)
  local entries = currentEntries()
  if not entries then
    say("no dialog open")
  elseif not entries[n] then
    say(("only %d option(s)"):format(#entries))
  else
    entries[n][2]()
  end
end

-- Confirm ------------------------------------------------------------------

-- StaticPopup's first button moved around between client versions.
local function popupButton()
  local p = StaticPopup1
  if not (p and p:IsShown()) then return end
  return p.button1 or _G.StaticPopup1Button1
    or (p.ButtonContainer and p.ButtonContainer.Buttons and p.ButtonContainer.Buttons[1])
end

local function confirm()
  local button = popupButton()
  if button then
    button:Click()
  elseif shown("QuestFrameDetailPanel") then
    AcceptQuest()
  elseif shown("QuestFrameProgressPanel") then
    if IsQuestCompletable() then CompleteQuest() else say("quest isn't complete yet") end
  elseif shown("QuestFrameRewardPanel") then
    local n = GetNumQuestChoices()
    if n > 1 then say(("pick a reward with 1-%d"):format(n)) else GetQuestReward(n) end
  elseif shown("LootFrame") then
    for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
  else
    local entries = currentEntries()
    if entries and #entries == 1 then
      entries[1][2]()
    else
      say("nothing to confirm")
    end
  end
end

-- Vendor -------------------------------------------------------------------

local function vendor()
  if not shown("MerchantFrame") then
    say("talk to a vendor first")
    return
  end
  if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
    C_MerchantFrame.SellAllJunkItems()
  end
  if CanMerchantRepair() then
    RepairAllItems()
  end
  say("sold junk" .. (CanMerchantRepair() and ", repaired" or ""))
end

-- Wiring -------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_COMPLETE", "LOOT_OPENED" }) do
  events:RegisterEvent(e)
end
-- Let the frames show first, then list what the numbers pick.
events:SetScript("OnEvent", function() C_Timer.After(0, printEntries) end)

WowKeysCommands = {
  confirm = confirm,
  vendor = vendor,
}
for n = 1, 9 do
  WowKeysCommands["choose" .. n] = function() choose(n) end
end
