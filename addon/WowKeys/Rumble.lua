-- Controller rumble for things worth feeling: a Fingers of Frost proc,
-- your enemy target starting a cast you can Counterspell, low health,
-- and combat starting outside combat mode or arrangement 1 (WowKeys.lua
-- calls ns.rumble for that one).
--
-- Midnight hides some combat values from addons ("secret values"); an
-- alert that can't read its value stays quiet rather than guess.

local _, ns = ...

-- Each alert is a list of pulses { strength 0-1, seconds }, with GAP
-- seconds between them. Tune or remove alerts here.
local ALERTS = {
  proc = { { 0.4, 0.15 } },
  cast = { { 0.6, 0.1 }, { 0.6, 0.1 } },
  lowHealth = { { 1, 0.4 } },
  wrongSetup = { { 0.8, 0.15 }, { 0.8, 0.15 }, { 0.8, 0.15 } },
}
local GAP = 0.08
local MOTOR = "High" -- C_GamePad.SetVibration's type; "Low" is the other motor
local PROC_AURA = "Fingers of Frost"
-- Rumble below 35% health; again only after healing past 50%.
local LOW_HEALTH, HEALTH_REARM = 0.35, 0.5

local function vibrate(strength)
  return pcall(C_GamePad.SetVibration, MOTOR, strength)
end

local function stop()
  pcall(C_GamePad.StopVibration)
end

-- A newer alert cuts off an older one.
local generation = 0

function ns.rumble(name)
  local pulses = ALERTS[name]
  if not (pulses and C_GamePad and C_GamePad.SetVibration) then return end
  generation = generation + 1
  local mine = generation
  local function play(i)
    if mine ~= generation or not pulses[i] then return end
    vibrate(pulses[i][1])
    C_Timer.After(pulses[i][2], function()
      if mine ~= generation then return end
      stop()
      C_Timer.After(GAP, function() play(i + 1) end)
    end)
  end
  play(1)
end

local function readable(v)
  return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- Fingers of Frost: rumble when it appears or gains a stack.
local procStacks = 0

local function checkProc()
  local find = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
  if not find then return end
  local ok, aura = pcall(find, "player", PROC_AURA, "HELPFUL")
  if not ok then return end
  local stacks = 0
  if aura then
    if not readable(aura.applications) then return end
    stacks = math.max(aura.applications, 1)
  end
  if stacks > procStacks then ns.rumble("proc") end
  procStacks = stacks
end

-- An enemy target starts a cast or channel. Skipped when the game says it
-- can't be interrupted; if it won't say, rumble anyway.
local function checkCast(event)
  if not UnitCanAttack("player", "target") then return end
  local shielded
  if event == "UNIT_SPELLCAST_START" then
    shielded = select(8, UnitCastingInfo("target"))
  else
    shielded = select(7, UnitChannelInfo("target"))
  end
  if readable(shielded) and shielded then return end
  ns.rumble("cast")
end

local lowWarned = false

local function checkHealth()
  if UnitIsDeadOrGhost("player") then return end
  local health, max = UnitHealth("player"), UnitHealthMax("player")
  if not (readable(health) and readable(max)) or max == 0 then return end
  local ratio = health / max
  if ratio < LOW_HEALTH and not lowWarned then
    lowWarned = true
    ns.rumble("lowHealth")
  elseif ratio >= HEALTH_REARM then
    lowWarned = false
  end
end

local watcher = CreateFrame("Frame")
watcher:RegisterUnitEvent("UNIT_AURA", "player")
watcher:RegisterUnitEvent("UNIT_HEALTH", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")

local handlers = {
  UNIT_AURA = checkProc,
  UNIT_HEALTH = checkHealth,
  UNIT_SPELLCAST_START = checkCast,
  UNIT_SPELLCAST_CHANNEL_START = checkCast,
}

-- An alert that breaks (a renamed API, a value the client hides) must
-- never break the others or spam errors mid-fight.
watcher:SetScript("OnEvent", function(_, event)
  pcall(handlers[event], event)
end)

ns.addSlash("rumble", "rumble [alert]", "feel an alert: proc, cast, lowHealth, wrongSetup (default cast)",
  function(rest)
    local name = rest ~= "" and rest or "cast"
    if not (C_GamePad and C_GamePad.SetVibration) then
      print("WowKeys: this client has no C_GamePad.SetVibration")
    elseif not ALERTS[name] then
      print("WowKeys: no alert " .. name)
    else
      local ok, err = vibrate(0)
      print(("WowKeys: rumble %s; GamePadVibrationStrength = %s%s"):format(name,
        ns.safeString(ns.getCVar("GamePadVibrationStrength")), ok and "" or ("; error: " .. ns.safeString(err))))
      ns.rumble(name)
    end
  end)
