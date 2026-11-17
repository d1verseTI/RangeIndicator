-- RangeIndicator: shows the estimated range to your target, plus which PvP
-- "zone" you are in relative to it (melee range, hunter dead zone, shooting
-- range, out of range).
-- Range comes from LibRangeCheck-3.0 (bundled copy, Forever-patched), which
-- combines spell, item and interact-distance checks into a "min - max" estimate.

local ADDON = ...
local rc = LibStub("LibRangeCheck-3.0")

local UPDATE_INTERVAL = 0.1
local DEFAULTS = { point = "CENTER", x = 0, y = -150, locked = false, scale = 1 }

-- Zone boundaries in yards (classic rules).
local MELEE_RANGE   = 5     -- melee attacks reach this far
local MELEE_LEEWAY  = 2.66  -- extra melee reach while BOTH of you are moving
local HUNTER_MIN    = 8     -- Auto Shot / Aimed Shot / etc. minimum range
local HUNTER_MAX    = 41    -- 35 yd base + 6 yd from the Hawk Eye talent

-- Color legend (the distance number is colored by zone):
local COLOR = {
  melee    = { 1, 0.25, 0.25 },  -- red:    in melee, they can hit you
  edge     = { 1, 0.82, 0 },     -- yellow: on a boundary, can't tell which side
  deadzone = { 0, 1, 0.75 },     -- teal:   hunter dead zone (5-8 yd)
  shoot    = { 1, 0.55, 0.1 },   -- orange: hunter can shoot you
  safe     = { 0.2, 1, 0.2 },    -- green:  out of melee / out of hunter range
  neutral  = { 1, 1, 1 },        -- white:  friendly or non-attackable target
  unknown  = { 0.6, 0.6, 0.6 },  -- grey:   range unknown
}

local function Secret(v) return issecretvalue and issecretvalue(v) end

local db
local frame = CreateFrame("Frame", "RangeIndicatorFrame", UIParent)
frame:SetSize(120, 30)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.45)

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
text:SetPoint("CENTER")

local function ApplyLock()
  frame:EnableMouse(not db.locked)
  bg:SetShown(not db.locked)
end

local function ApplyLayout()
  frame:ClearAllPoints()
  frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
  frame:SetScale(db.scale)
end

frame:SetScript("OnDragStart", function(self)
  if not db.locked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, _, x, y = self:GetPoint()
  db.point, db.x, db.y = point, x, y
end)

-- Exact distance in yards. The client only gives coordinates for yourself and
-- your party/raid members (and not inside instances), so this returns nil for
-- enemies and most NPCs; those fall back to the LibRangeCheck bracket.
local function ExactDistance(unit)
  if UnitIsUnit(unit, "player") then return 0 end
  if not (UnitInParty(unit) or UnitInRaid(unit)) then return nil end
  local py, px, _, pi = UnitPosition("player")
  local ty, tx, _, ti = UnitPosition(unit)
  if not (py and ty) or Secret(py) or Secret(ty) or Secret(pi) or Secret(ti) then return nil end
  if pi ~= ti then return nil end
  local dx, dy = tx - px, ty - py
  return math.sqrt(dx * dx + dy * dy)
end

local function IsMoving(unit)
  local speed = GetUnitSpeed(unit)
  return speed and not Secret(speed) and speed > 0
end

-- Decides the zone from a [lo, hi] distance bracket (hi = nil: beyond all checks).
-- When the bracket straddles a boundary we can't tell which side you're on, so
-- we say so instead of guessing.
local function Zone(lo, hi, isHunter)
  local meleeReach = MELEE_RANGE
  if IsMoving("player") and IsMoving("target") then
    meleeReach = MELEE_RANGE + MELEE_LEEWAY
  end

  if hi and hi <= meleeReach then return COLOR.melee end
  if lo < meleeReach then return COLOR.edge end

  if isHunter == nil then
    -- Class hidden (battlegrounds): 5-8 yd is safe from melee AND hunters,
    -- so the dead-zone color is right for any class. Beyond that we can't know.
    if hi and hi <= HUNTER_MIN then return COLOR.deadzone end
    return COLOR.safe
  end
  if isHunter then
    if hi and hi <= HUNTER_MIN then return COLOR.deadzone end
    if lo < HUNTER_MIN then return COLOR.edge end
    if hi and hi <= HUNTER_MAX then return COLOR.shoot end
    if lo < HUNTER_MAX then return COLOR.edge end
  end
  return COLOR.safe
end

local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function ItemsRestricted()
  local _, instanceType = IsInInstance()
  return instanceType == "pvp" or instanceType == "arena" or InCombatLockdown()
end

-- Errors are caught (no error spam / slowdown) and the distinct ones are kept
-- in RangeIndicatorDB.errors so they can be read from the SavedVariables file.
local function LogProblem(msg)
  if not db then return end
  msg = tostring(msg)
  db.errors = db.errors or {}
  local _, instanceType = IsInInstance()
  local key = msg:sub(1, 300)
  local entry = db.errors[key]
  if entry then
    entry.count = entry.count + 1
  else
    local n = 0
    for _ in pairs(db.errors) do n = n + 1 end
    if n >= 20 then return end
    db.errors[key] = { count = 1, first = date("%H:%M:%S"), zone = instanceType or "?",
      inCombat = InCombatLockdown() and true or false }
  end
end

local function UpdateTextUnsafe()
  if not UnitExists("target") then
    frame:Hide()
    return
  end
  frame:Show()

  local lo, hi
  local exact = ExactDistance("target")
  if exact then
    lo, hi = exact, exact
    text:SetFormattedText("%.1f yd", exact)
  else
    -- No cache: re-check every update so the bracket follows movement closely.
    -- In a PvP match or in combat, item range checks on enemies are restricted
    -- on Forever (they error / get blocked), so only spells are used there.
    lo, hi = rc:GetRange("target", false, ItemsRestricted(), 0)
    if Secret(lo) or Secret(hi) then lo, hi = nil, nil end
    if not lo then
      text:SetText("?? yd")
    elseif not hi then
      text:SetFormattedText("%d+ yd", lo)
    else
      text:SetFormattedText("%d - %d yd", lo, hi)
    end
  end

  if not lo then
    SetColor(text, COLOR.unknown)
    return
  end

  -- Zones only matter for something that can fight you.
  local canAttack = UnitCanAttack("player", "target")
  if Secret(canAttack) then canAttack = true end   -- hidden: assume enemy
  if canAttack then
    -- In a PvP match the client hides the enemy's class (and maybe whether
    -- it's a player). Hidden -> isHunter = nil ("unknown").
    local isPlayer = UnitIsPlayer("target")
    local _, class = UnitClass("target")
    local isHunter
    if Secret(isPlayer) or Secret(class) then
      isHunter = nil
    else
      isHunter = (isPlayer and class == "HUNTER") and true or false
    end
    SetColor(text, Zone(lo, hi, isHunter))
  else
    SetColor(text, COLOR.neutral)
  end
end

local function UpdateText()
  local ok, err = pcall(UpdateTextUnsafe)
  if not ok then
    LogProblem(err)
    text:SetText("?? yd")
    SetColor(text, COLOR.unknown)
  end
end

local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + dt
  if elapsed < UPDATE_INTERVAL then return end
  elapsed = 0
  UpdateText()
end)

-- OnUpdate only runs while shown, so target changes drive show/hide.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Blocked calls don't raise Lua errors; record them too (for any addon).
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(self, event, arg1, arg2)
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    LogProblem(("%s: %s -> %s"):format(event, tostring(arg1), tostring(arg2)))
    return
  end
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    RangeIndicatorDB = RangeIndicatorDB or {}
    db = RangeIndicatorDB
    db.errors = nil   -- keep only this session's errors
    db.zones = nil    -- old setting, no longer used
    for k, v in pairs(DEFAULTS) do
      if db[k] == nil then db[k] = v end
    end
    ApplyLayout()
    ApplyLock()
    self:UnregisterEvent("ADDON_LOADED")
  elseif db then
    UpdateText()
  end
end)

local function Print(msg) print("|cff33ff99RangeIndicator|r: " .. msg) end

SLASH_RANGEINDICATOR1 = "/ri"
SLASH_RANGEINDICATOR2 = "/rangeindicator"
SlashCmdList.RANGEINDICATOR = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "lock" then
    db.locked = true; ApplyLock()
    Print("locked.")
  elseif cmd == "unlock" then
    db.locked = false; ApplyLock()
    Print("unlocked - drag to move.")
  elseif cmd == "scale" and tonumber(arg) then
    db.scale = math.min(3, math.max(0.5, tonumber(arg))); ApplyLayout()
    Print("scale " .. db.scale)
  elseif cmd == "colors" or cmd == "legend" then
    local function line(c, desc)
      print(("  |cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, desc))
    end
    Print("color legend:")
    line(COLOR.melee,    "Red - in melee, they can hit you")
    line(COLOR.edge,     "Yellow - on a boundary (step back / closer)")
    line(COLOR.deadzone, "Teal - hunter dead zone (5-8 yd), hunter can't hit you")
    line(COLOR.shoot,    "Orange - hunter can shoot you (8-41 yd)")
    line(COLOR.safe,     "Green - out of melee / out of hunter range")
    line(COLOR.neutral,  "White - friendly target")
    line(COLOR.unknown,  "Grey - range unknown")
  elseif cmd == "info" then
    -- Lists the yard steps the bracket can resolve right now. More steps =
    -- more precise. In combat, item checks on enemies are blocked, so only
    -- your spells (and interact distances) remain.
    local function list(iter, label)
      local ranges = {}
      for range in iter do ranges[#ranges + 1] = range end
      table.sort(ranges)
      print(("  %s: %s"):format(label, #ranges > 0 and table.concat(ranges, ", ") or "none"))
    end
    Print("measurable distances (yd):")
    list(rc:GetHarmCheckers(false), "Enemy, out of combat")
    list(rc:GetHarmCheckers(true), "Enemy, in combat")
    list(rc:GetFriendCheckers(false), "Friendly, out of combat")
    list(rc:GetFriendCheckers(true), "Friendly, in combat")
    print("  Party/raid members: exact distance when the game allows it.")
    print("  Dead zone needs a check at 5 and at 8 yd to be shown reliably.")
  elseif cmd == "reset" then
    for k, v in pairs(DEFAULTS) do db[k] = v end
    ApplyLayout(); ApplyLock()
    Print("position reset.")
  else
    Print("commands: /ri lock | unlock | scale <0.5-3> | colors | info | reset")
  end
end
