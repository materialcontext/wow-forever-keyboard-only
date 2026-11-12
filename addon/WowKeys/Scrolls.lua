-- Mage scrolls (WoW: Forever). Mages decipher "Scroll: KWYJIBO"-style
-- drops with Comprehend Scroll (5 s cast, from level 6) into "Scroll of
-- ..." items: weapon imbues and familiars (1 hour each), plus situational
-- ones. WowKeys rewrites two macros out of combat so one key does the next
-- useful thing on every press:
--
--   Decipher  /cast Comprehend Scroll + /use the next undeciphered scroll.
--             A failed read (you turn into a sheep, the scroll stays) moves
--             on to the other scrolls before trying it again.
--   Scrolls   /use the best deciphered scroll whose effect you don't have:
--             one weapon imbue and one familiar at a time.
--
-- With nothing to do, both run /wowkeys scrolls, which says why.

local _, ns = ...

-- Families (name fragments, any case) best first; within a family,
-- Greater beats plain beats Lesser. Frost imbues first for a Frost mage.
local PREFER = { "frost", "flame", "cat", "frog", "rat" }
-- Scrolls the Scrolls key never uses: situational (mana, skill, locks)
-- or crafting (the Saber and Blade scrolls), and dagger imbues.
local NEVER = { "evocation", "comprehension", "unlocking", "saber", "blade", "knife" }
local UNREAD, READ = "^Scroll: ", "^Scroll of "
local DECIPHER_SPELL = "Comprehend Scroll"
local FAMILIAR_SECONDS = 3600
local IDLE = "/wowkeys scrolls"

local function lower(s) return type(s) == "string" and s:lower() or "" end

-- Index of the first fragment in `list` that `name` contains, or nil.
local function rank(name, list)
  local n = lower(name)
  for i, part in ipairs(list) do
    if n:find(part, 1, true) then return i end
  end
end

-- Every item in your bags (backpack, four bags, reagent bag) in bag order.
local function score(name)
  local n = lower(name)
  local tier = n:find("greater", 1, true) and 0 or n:find("lesser", 1, true) and 2 or 1
  return (rank(name, PREFER) or #PREFER + 1) * 3 + tier
end

local function bagItems()
  local items = {}
  for bag = 0, 5 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local name = info and C_Item.GetItemNameByID(info.itemID)
      if name then
        table.insert(items, { bag = bag, slot = slot, id = info.itemID, name = name })
      end
    end
  end
  return items
end

local function readable(v)
  return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- A buff on you whose name contains `part` (or equals it, if exact).
local function hasAura(part, exact)
  for i = 1, 40 do
    local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
    if not aura then return false end
    if readable(aura.name) then
      local n = lower(aura.name)
      if (exact and n == part) or (not exact and n:find(part, 1, true)) then return true end
    end
  end
  return false
end

-- Familiars may be summons rather than buffs, so also remember casting one.
local familiarUntil = 0

-- Which effects can't stack: all imbues share the weapon, all familiars
-- the one companion; any other scroll is its own group.
local function group(item)
  local spell = C_Item.GetItemSpell(item.id)
  item.spell = spell
  if lower(item.name):find("imbue", 1, true) or lower(spell):find("^imbue") then return "imbue" end
  if lower(item.name):find("familiar", 1, true) then return "familiar" end
  return "own"
end

local function active(kind, item)
  if kind == "imbue" then return (GetWeaponEnchantInfo()) == true end
  if kind == "familiar" then return time() < familiarUntil or hasAura("familiar") end
  return item.spell ~= nil and hasAura(lower(item.spell), true)
end

local function nextBuff()
  local best, bestRank
  for _, item in ipairs(bagItems()) do
    if item.name:find(READ) and not rank(item.name, NEVER) then
      local kind = group(item)
      if not active(kind, item) then
        local r = score(item.name)
        if not best or r < bestRank then best, bestRank = item, r end
      end
    end
  end
  return best
end

-- Item IDs deciphering was tried on; skipped until every scroll was tried.
local tried, target = {}, nil

local function nextUnread()
  local first, fresh
  for _, item in ipairs(bagItems()) do
    if item.name:find(UNREAD) then
      first = first or item
      if not tried[item.id] then fresh = item break end
    end
  end
  if first and not fresh then tried = {} end
  return fresh or first
end

local function macroBody(name)
  if GetMacroBody then return GetMacroBody(name) end
  return select(3, GetMacroInfo(name))
end

-- Macros can only change out of combat; WowKeys.lua creates them at login.
local function setBody(name, body)
  if GetMacroIndexByName(name) == 0 or macroBody(name) == body then return end
  pcall(EditMacro, GetMacroIndexByName(name), name, nil, body)
end

local function refresh()
  if InCombatLockdown() then return end
  target = nextUnread()
  setBody("Decipher", target
    and ("#showtooltip %s\n/cast %s\n/use %d %d"):format(DECIPHER_SPELL, DECIPHER_SPELL, target.bag, target.slot)
    or IDLE)
  local buff = nextBuff()
  setBody("Scrolls", buff and ("#showtooltip %s\n/use %d %d"):format(buff.name, buff.bag, buff.slot) or IDLE)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("BAG_UPDATE_DELAYED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterUnitEvent("UNIT_AURA", "player")
watcher:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

watcher:SetScript("OnEvent", function(_, event, _, _, spellID)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    local name = lower(ns.spellName(spellID))
    if name == lower(DECIPHER_SPELL) and target then tried[target.id] = true end
    if name:find("familiar", 1, true) then familiarUntil = time() + FAMILIAR_SECONDS end
  end
  if event == "PLAYER_ENTERING_WORLD" then
    -- After WowKeys.lua has (re)created the macros.
    C_Timer.After(1, function() pcall(refresh) end)
  else
    pcall(refresh)
  end
end)

-- Imbues and familiars wear off without an event we can count on.
C_Timer.NewTicker(15, function() pcall(refresh) end)

ns.addSlash("scrolls", "scrolls", "mage scrolls: what the Decipher and Scrolls keys will do next",
  function()
    local unread = 0
    for _, item in ipairs(bagItems()) do
      if item.name:find(UNREAD) then unread = unread + 1 end
    end
    local t, buff = nextUnread(), nextBuff()
    print(("WowKeys: %d scroll(s) to decipher%s"):format(unread, t and ("; next: " .. t.name) or ""))
    if buff then
      print("WowKeys: Scrolls key uses " .. buff.name .. " next")
    else
      print(("WowKeys: no scroll to use (imbue %s, familiar %s)"):format(
        (GetWeaponEnchantInfo()) and "on" or "off",
        (time() < familiarUntil or hasAura("familiar")) and "out" or "not out"))
    end
    pcall(refresh)
  end)
