-- HussHub | Huss Valley
-- Made by @avongg6
-- Discord - discord.gg/fRymbb9g

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============ CONFIG ============
local CONFIG = {
    -- Runner
    RunnerEnabled = true,
    AutoRevive = true,
    AutoGems = true,
    AutoDash = true,
    AvoidCatchers = true,
    SpeedMultiplier = 1.0,
    CustomSpeed = false,
    ReviveBeforeGems = true,
    
    -- Catcher
    CatcherChase = true,
    AutoTackle = true,
    AutoMelee = true,
    SmartPriority = true,
    CatcherSpeedMultiplier = 1.0,
    CatcherCustomSpeed = false,
    AttackPriority = "Smart",
    
    -- Wheel
    AutoSpinWheel = false,
    WheelInterval = 6,
    WheelMinCredits = 1,
    
    -- Journey
    AutoClaimJourney = false,
    
    -- Map Vote
    AutoMapVote = false,
    MapVoteSelection = "Map 1",
    
    -- Utility
    DisableAFK = false,
    AntiIdleKick = true,
    
    -- Visuals
    ShowGoal = true,
    ShowThreats = true,
    ShowHitboxes = true,
    ShowESP = false,
    ESPColor = Color3.fromRGB(255, 182, 255),
    TracerESP = false,
    TracerColor = Color3.fromRGB(255, 182, 255),
    TracerThickness = 0.15,
    HitboxSize = 5,
    HitboxTransparency = 0.5,
}

-- ============ SERVICII JOC ============
local COH = ReplicatedStorage:WaitForChild("ChickenOrHero", 10)
if not COH then
    warn("[HussHub] Joc nesuportat! Rulează scriptul în Huss Valley.")
    return
end

local Movement = COH:WaitForChild("Movement")
local MovementProfiles = require(Movement:WaitForChild("MovementProfiles"))
local BoostInput = require(Movement:WaitForChild("BoostInput"))
local Game = COH:WaitForChild("Game")
local Session = Game:WaitForChild("Session")
local MapVoteState = Game:WaitForChild("MapVoteState")
local MapVoteEvent = Game:WaitForChild("MapVoteEvent")
local ContactCatchConfig = require(Game:WaitForChild("ContactCatchConfig"))
local TacklePrediction = require(Game:WaitForChild("TacklePrediction"))
local MeleeEvent = Game:WaitForChild("MeleeEvent")
local RescueConfig = require(Game:WaitForChild("RescueConfig"))
local RescueEvent = Game:WaitForChild("RescueEvent")
local SpinWheelEvent = COH:WaitForChild("SpinWheelEvent")
local JourneyConfig = require(COH:WaitForChild("Progression"):WaitForChild("JourneyConfig"))
local JourneyEvent = COH:WaitForChild("Progression"):WaitForChild("JourneyEvent")
local PlayerPreferences = COH:WaitForChild("Game"):WaitForChild("PlayerPreferences")

local RESCUE_RANGE = math.max(3, tonumber(RescueConfig.Range) or 6) - 0.25
local RESCUE_HOLD = math.max(0.1, tonumber(RescueConfig.HoldSeconds) or 1.2)

-- ============ STATE ============
local State = {
    currentTarget = nil,
    currentGoal = nil,
    goalMode = "SafeZone",
    path = Vector3.zero,
    threatCount = 0,
    threats = {},
    catchers = {},
    runnerTargets = {},
    catcherTarget = nil,
    dashReady = true,
    lastDash = 0,
    lastMelee = 0,
    lastTackle = 0,
    reviveTarget = nil,
    reviveStarted = false,
    reviveStartTime = 0,
    gemTarget = nil,
    gemIgnored = {},
    safezones = {a = nil, b = nil},
    safezonesCached = false,
    lastPosition = nil,
    lastMoveTime = 0,
    stuck = false,
    wheelCredits = 0,
    wheelSpinning = false,
    wheelNextAttempt = 0,
    journeyLoaded = false,
    journeyTier = 1,
    journeyClaims = {}, 
    journeyClaiming = false,
    mapVotePhase = "Waiting",
    mapVoteToken = nil,
    mapVoteOptionIds = {},
    mapVoteLastAction = 0,
    afkOverride = false,
    afkLastRequest = 0,
}

-- ============ FLAGS UI (setate din Obsidian) ============
getgenv().HussHub = getgenv().HussHub or {}
local Flags = getgenv().HussHub
-- ============ HELPER FUNCTIONS ============
local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function getCharacter(plr)
    return (plr or LocalPlayer).Character
end

local function getHumanoid(plr)
    local c = getCharacter(plr)
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot(plr)
    local c = getCharacter(plr)
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

local function getRole()
    return LocalPlayer:GetAttribute("GameRole") or "Lobby"
end

local function getRunState()
    return LocalPlayer:GetAttribute("RunState") or "Idle"
end

local function isRunnerActive()
    if LocalPlayer:GetAttribute("InMatch") ~= true then return false end
    if getRole() ~= "Runner" then return false end
    return getRunState() == "Active"
end

local function isCatcherActive()
    if LocalPlayer:GetAttribute("InMatch") ~= true then return false end
    if getRole() ~= "Catcher" then return false end
    return getRunState() == "Active"
end

local function canMove()
    if LocalPlayer:GetAttribute("ClientReady") ~= true then return false end
    if Session:GetAttribute("GlobalPaused") == true then return false end
    if Session:GetAttribute("MapChanging") == true then return false end
    local c = getCharacter()
    if not c then return false end
    if c:GetAttribute("Ragdolled") == true then return false end
    if c:GetAttribute("GearMotion") == true then return false end
    if c:GetAttribute("MovementLocked") == true then return false end
    local h = getHumanoid()
    if not h or h.Health <= 0 then return false end
    if h.PlatformStand or h.Sit then return false end
    return true
end

local function getBaseSpeed(role)
    role = role or getRole()
    local ok, profile = pcall(MovementProfiles.get, role, LocalPlayer)
    if ok and profile then return profile.MaxSpeed or 16 end
    return 16
end

local function getRunnerSpeed()
    local speed = math.max(getBaseSpeed("Runner"), 1)
    if CONFIG.CustomSpeed then
        speed *= math.clamp(CONFIG.SpeedMultiplier, 1, 2)
    end
    return speed
end

local function getCatcherSpeed()
    local speed = math.max(getBaseSpeed("Catcher"), 1)
    if CONFIG.CatcherCustomSpeed then
        speed *= math.clamp(CONFIG.CatcherSpeedMultiplier, 1, 2)
    end
    return speed
end

-- ============ MAP + SAFEZONES ============
local mapCache = nil
local mapCacheAt = 0

local function getMap()
    local now = os.clock()
    if now - mapCacheAt < 0.35 then return mapCache end
    mapCacheAt = now
    local handle = Game:FindFirstChild("ActiveMap")
    if handle and handle:IsA("ObjectValue") and handle.Value and handle.Value:IsDescendantOf(workspace) then
        mapCache = handle.Value
        return mapCache
    end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:FindFirstChild("Field") then
            mapCache = obj
            return mapCache
        end
    end
    mapCache = nil
    return nil
end

local function findZone(parent, names)
    for _, name in ipairs(names) do
        local direct = parent:FindFirstChild(name)
        if direct then return direct end
    end
    for _, obj in ipairs(parent:GetDescendants()) do
        local lower = obj.Name:lower()
        for _, name in ipairs(names) do
            if lower == name:lower() then return obj end
        end
    end
    return nil
end

local function getBounds(instance)
    if not instance then return nil end
    local minP = Vector3.new(math.huge, math.huge, math.huge)
    local maxP = Vector3.new(-math.huge, -math.huge, -math.huge)
    local found = false
    local function add(part)
        local p = part.Position
        local h = part.Size * 0.5
        minP = Vector3.new(math.min(minP.X, p.X-h.X), math.min(minP.Y, p.Y-h.Y), math.min(minP.Z, p.Z-h.Z))
        maxP = Vector3.new(math.max(maxP.X, p.X+h.X), math.max(maxP.Y, p.Y+h.Y), math.max(maxP.Z, p.Z+h.Z))
        found = true
    end
    if instance:IsA("BasePart") then add(instance) end
    for _, obj in ipairs(instance:GetDescendants()) do
        if obj:IsA("BasePart") then add(obj) end
    end
    if not found then return nil end
    return minP, maxP
end

local function buildZone(instance)
    local minP, maxP = getBounds(instance)
    if not minP then return nil end
    return {
        instance = instance,
        name = instance.Name,
        min = minP,
        max = maxP,
        center = (minP + maxP) * 0.5,
    }
end

local function refreshSafezones()
    local map = getMap()
    if State.safezonesCached and State.safezones.a and State.safezones.b
        and State.safezones.a.instance.Parent and State.safezones.b.instance.Parent then
        return
    end
    State.safezonesCached = true
    State.safezones.a = nil
    State.safezones.b = nil
    local field = map and map:FindFirstChild("Field")
    if not field then return end
    local a = findZone(field, {"SafezoneASide", "SafeZoneASide"})
    local b = findZone(field, {"SafezoneBSide", "SafeZoneBSide"})
    State.safezones.a = buildZone(a)
    State.safezones.b = buildZone(b)
end

local function inZone(position, zone)
    if not zone then return false end
    return position.X >= zone.min.X and position.X <= zone.max.X
        and position.Z >= zone.min.Z and position.Z <= zone.max.Z
        and position.Y >= zone.min.Y - 8 and position.Y <= zone.max.Y + 8
end

local function getZoneCenter(zone, y)
    if not zone then return nil end
    return Vector3.new(zone.center.X, y, zone.center.Z)
end

-- ============ GEMS ============
local function isGemObject(obj)
    local name = obj.Name:lower()
    return obj:IsA("BasePart") and (
        name:sub(1,4) == "gem_" or name == "gem" or name == "gems" or name:find("gempickup", 1, true) ~= nil
    )
end

local function refreshGems(position)
    local folder = workspace:FindFirstChild("LocalRunnerGems")
    local best, bestDist
    if folder then
        for _, obj in ipairs(folder:GetChildren()) do
            if isGemObject(obj) and obj.Parent then
                local d = flat(obj.Position - position).Magnitude
                local ignored = State.gemIgnored[obj]
                if d <= 220 and (not ignored or os.clock() >= ignored) then
                    if not bestDist or d < bestDist then
                        best = obj
                        bestDist = d
                    end
                end
            end
        end
    end
    State.gemTarget = best
end

-- ============ REVIVE ============
local function findDownedPlayer(position)
    local best, bestDist
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Parent then
            local c = plr.Character
            local root = c and c:FindFirstChild("HumanoidRootPart")
            if root and c:GetAttribute("RescueAvailable") == true and c:GetAttribute("Ragdolled") == true then
                local helper = c:GetAttribute("RescueHelperId")
                if helper == nil or helper == LocalPlayer.UserId then
                    local d = flat(root.Position - position).Magnitude
                    if d <= 220 and (not bestDist or d < bestDist) then
                        best = plr
                        bestDist = d
                    end
                end
            end
        end
    end
    return best
end

local function cancelRevive()
    if State.reviveTarget and State.reviveStarted then
        pcall(function()
            RescueEvent:FireServer("Cancel", State.reviveTarget.UserId)
        end)
    end
    State.reviveTarget = nil
    State.reviveStarted = false
    State.reviveStartTime = 0
end

local function updateRevive(now, position)
    if not CONFIG.AutoRevive then
        cancelRevive()
        return nil
    end
    local target = State.reviveTarget
    local root = target and getRoot(target)
    if not target or not target.Parent or not root 
        or target.Character:GetAttribute("RescueAvailable") ~= true 
        or target.Character:GetAttribute("Ragdolled") ~= true then
        cancelRevive()
        target = nil
    end
    if not target then
        target = findDownedPlayer(position)
        if not target then return nil end
        State.reviveTarget = target
    end
    root = getRoot(target)
    if not root then cancelRevive() return nil end
    State.goalMode = "Revive"
    local distance = flat(root.Position - position).Magnitude
    if distance > 220 then cancelRevive() return nil end
    if distance <= RESCUE_RANGE then
        if not State.reviveStarted then
            State.reviveStarted = true
            State.reviveStartTime = now
            pcall(function()
                RescueEvent:FireServer("Begin", target.UserId)
            end)
        elseif now - State.reviveStartTime >= RESCUE_HOLD then
            pcall(function()
                RescueEvent:FireServer("Finish", target.UserId)
            end)
            State.reviveStarted = false
            State.reviveStartTime = now + 0.5
        end
    elseif State.reviveStarted then
        cancelRevive()
    end
    return root.Position
end

-- ============ CATCHERS ============
local catcherCacheAt = 0

local function refreshCatchers()
    local now = os.clock()
    if now - catcherCacheAt < 0.12 then return end
    catcherCacheAt = now
    table.clear(State.catchers)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Parent
            and plr:GetAttribute("GameRole") == "Catcher"
            and plr:GetAttribute("RunState") == "Active" then
            local c = plr.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and r
                and c:GetAttribute("Ragdolled") ~= true
                and c:GetAttribute("MovementLocked") ~= true then
                table.insert(State.catchers, plr)
            end
        end
    end
end

local function refreshRunnerTargets()
    local now = os.clock()
    if now - catcherCacheAt < 0.15 then return end
    table.clear(State.runnerTargets)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Parent
            and plr:GetAttribute("GameRole") == "Runner"
            and plr:GetAttribute("RunState") == "Active" then
            local c = plr.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and r and c:GetAttribute("Ragdolled") ~= true then
                table.insert(State.runnerTargets, plr)
            end
        end
    end
end

-- ============ THREATS (predictie) ============
local threatHistory = {}
local threatAt = 0

local function updateThreats(now, position)
    if now - threatAt < 0.045 then return State.threats end
    threatAt = now
    table.clear(State.threats)
    local runRoot = getRoot()
    local runVelocity = runRoot and flat(runRoot.AssemblyLinearVelocity) or Vector3.zero
    local runSpeed = math.max(getRunnerSpeed(), 1)
    if runVelocity.Magnitude < 3 and State.path.Magnitude > 0.05 then
        runVelocity = State.path.Unit * runSpeed
    end

    for _, plr in ipairs(State.catchers) do
        local root = getRoot(plr)
        if root then
            local current = flat(root.Position)
            local offset = current - position
            local distance = offset.Magnitude
            if distance <= 105 then
                local velocity = flat(root.AssemblyLinearVelocity)
                local history = threatHistory[plr]
                if not history then
                    history = {position = current, velocity = velocity, time = now}
                    threatHistory[plr] = history
                end
                local historyDt = now - history.time
                local acceleration = Vector3.zero
                if historyDt > 0.025 and historyDt < 0.25 then
                    acceleration = (velocity - history.velocity) / historyDt
                    if acceleration.Magnitude > 70 then
                        acceleration = acceleration.Unit * 70
                    end
                end
                history.position = current
                history.velocity = velocity
                history.time = now

                local relative = current - position
                local relativeVel = velocity - runVelocity
                local relSq = relativeVel:Dot(relativeVel)
                local closestTime = 0
                if relSq > 0.25 then
                    closestTime = math.clamp(-relative:Dot(relativeVel) / relSq, 0, 1.8)
                end

                local prediction = math.clamp(0.65 + (LocalPlayer:GetNetworkPing() * 0.5) * 0.85, 0.28, 1.15)
                local predictionPos = current + velocity * prediction + acceleration * (0.5 * prediction * prediction)
                local futureDist = (predictionPos - (position + runVelocity * prediction)).Magnitude

                local danger = 8 + (tonumber(ContactCatchConfig.MinForward) or 0)
                    + math.max(0, tonumber(ContactCatchConfig.HandRadius) or 0)
                    + math.max(0, tonumber(ContactCatchConfig.ContactPadding) or 0)
                    + math.max(0, tonumber(ContactCatchConfig.RunnerRadius) or 0)

                local closing = distance > 0.05 and math.max(0, velocity:Dot(-offset.Unit)) or 0
                local timeToDanger = math.huge
                if closing > 0.5 then
                    timeToDanger = math.max(0, (distance - danger) / closing)
                elseif distance <= danger then
                    timeToDanger = 0
                end

                local interceptTime = math.min(closestTime, prediction)
                if timeToDanger < interceptTime then interceptTime = timeToDanger end
                local interceptCatcher = current + velocity * interceptTime + acceleration * (0.5 * interceptTime * interceptTime)
                local interceptRunner = position + runVelocity * interceptTime
                local interceptGap = flat(interceptCatcher - interceptRunner).Magnitude

                table.insert(State.threats, {
                    player = plr,
                    position = current,
                    velocity = velocity,
                    distance = distance,
                    closing = closing,
                    predicted = predictionPos,
                    intercept = interceptCatcher,
                    interceptGap = interceptGap,
                    interceptTime = interceptTime,
                    danger = danger,
                    timeToDanger = timeToDanger,
                    collisionRisk = timeToDanger <= math.min(prediction + 0.04, 0.72) or interceptGap <= danger * 1.35,
                })
            end
        end
    end

    table.sort(State.threats, function(a, b)
        if a.collisionRisk ~= b.collisionRisk then return a.collisionRisk end
        if a.timeToDanger ~= b.timeToDanger then return a.timeToDanger < b.timeToDanger end
        return a.interceptGap < b.interceptGap
    end)

    for plr, history in pairs(threatHistory) do
        if not plr.Parent or now - history.time > 1.2 then
            threatHistory[plr] = nil
        end
    end

    State.threatCount = #State.threats
    return State.threats
end

-- ============ ROUTE CLEAR ============
local function routeClear(position, direction, threats)
    if direction.Magnitude < 0.05 then return -math.huge end
    local dir = direction.Unit
    local speed = math.max(getRunnerSpeed(), 1)
    local clearance = math.huge
    local samples = {0.10, 0.22, 0.36, 0.52, 0.70, 0.90}
    for _, t in ipairs(samples) do
        local runner = position + dir * speed * t
        for _, threat in ipairs(threats) do
            local catchPos = threat.position + threat.velocity * t
            local safe = flat(runner - catchPos).Magnitude - threat.danger
            if safe < clearance then clearance = safe end
        end
    end
    return clearance
end

-- ============ MOVEMENT STUCK DETECTION ============
local function checkStuck(now, position)
    if not State.lastPosition then
        State.lastPosition = position
        State.lastMoveTime = now
        State.stuck = false
        return
    end
    if flat(position - State.lastPosition).Magnitude >= 0.5 then
        State.lastPosition = position
        State.lastMoveTime = now
        State.stuck = false
    elseif now - State.lastMoveTime > 0.55 then
        State.stuck = true
        State.lastMoveTime = now
        State.lastPosition = position
    end
end
-- ============ RUNNER LOGIC ============
local function runnerGoal(position, now)
    refreshSafezones()
    local a = State.safezones.a
    local b = State.safezones.b
    if not a or not b then return nil end

    if not State.currentGoal then
        local inA = inZone(position, a)
        local inB = inZone(position, b)
        local start = inA and not inB and a or (inB and not inA and b or (flat(position - a.center).Magnitude <= flat(position - b.center).Magnitude and a or b))
        local target = start == a and b or a
        State.currentGoal = getZoneCenter(target, position.Y)
        State.goalMode = "SafeZone"
    end
    return State.currentGoal
end

local function chooseRunnerDirection(position, goal, threats)
    local desired = flat(goal - position)
    if desired.Magnitude < 0.05 then return Vector3.zero end
    desired = desired.Unit

    if not CONFIG.AvoidCatchers or #threats == 0 then
        return desired
    end

    local candidates = {desired}
    for _, angle in ipairs({15, -15, 30, -30, 45, -45, 60, -60, 75, -75, 90, -90}) do
        local r = math.rad(angle)
        local c = math.cos(r)
        local s = math.sin(r)
        table.insert(candidates, Vector3.new(desired.X*c - desired.Z*s, 0, desired.X*s + desired.Z*c))
    end

    local best = desired
    local bestScore = -math.huge
    for _, candidate in ipairs(candidates) do
        local progress = candidate:Dot(desired)
        local clearance = routeClear(position, candidate, threats)
        local score = progress * 10 + math.min(clearance, 20) * 2.4
        if clearance < 0 then score -= math.abs(clearance) * 18 end
        for _, threat in ipairs(threats) do
            local away = flat(position - threat.intercept)
            if away.Magnitude > 0.05 then
                local urgency = math.clamp(1 - threat.interceptGap / (threat.danger * 3), 0, 1)
                score += candidate:Dot(away.Unit) * urgency * (threat.collisionRisk and 14 or 4.5)
            end
        end
        if score > bestScore then
            bestScore = score
            best = candidate
        end
    end
    return best.Unit
end

local function requestDash(now)
    if not CONFIG.AutoDash or not isRunnerActive() then return false end
    local character = getCharacter()
    if not character then return false end
    local cooldown = tonumber(character:GetAttribute("DashCooldownUntil")) or 0
    if os.clock() < cooldown then return false end
    if now - State.lastDash < 0.85 then return false end
    local ok, available = pcall(BoostInput.available, LocalPlayer)
    if not ok or available ~= true then return false end
    local ok2, result = pcall(BoostInput.request, nil)
    if ok2 and result ~= false then
        State.lastDash = now
        return true
    end
    return false
end

local function runnerStep(now, dt)
    if not CONFIG.RunnerEnabled then return end
    if not isRunnerActive() then
        State.path = Vector3.zero
        State.currentGoal = nil
        cancelRevive()
        return
    end
    if not canMove() then return end

    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum then return end

    refreshCatchers()
    local position = root.Position
    local threats = updateThreats(now, position)
    local goal = runnerGoal(position, now)
    if not goal then return end

    -- Revive check
    local reviveGoal = nil
    if CONFIG.AutoRevive then
        local target = findDownedPlayer(position)
        if target then
            local targetRoot = getRoot(target)
            if targetRoot then
                if CONFIG.ReviveBeforeGems or State.goalMode ~= "Gem" then
                    reviveGoal = targetRoot.Position
                    State.goalMode = "Revive"
                end
            end
        end
    end

    -- Gem check
    local gemGoal = nil
    if CONFIG.AutoGems and not reviveGoal then
        refreshGems(position)
        if State.gemTarget and State.gemTarget.Parent then
            local d = flat(State.gemTarget.Position - position).Magnitude
            if d <= 220 then
                gemGoal = State.gemTarget.Position
                State.goalMode = "Gem"
            end
        end
    end

    local movementGoal = reviveGoal or gemGoal or goal
    if not movementGoal then
        hum:Move(Vector3.zero, false)
        State.path = Vector3.zero
        return
    end

    local distance = flat(movementGoal - position).Magnitude
    if distance <= 2.5 then
        if State.goalMode == "Gem" then
            State.gemIgnored[State.gemTarget] = now + 0.7
            State.gemTarget = nil
        elseif State.goalMode == "SafeZone" then
            State.currentGoal = nil
        end
        State.goalMode = "SafeZone"
    end

    local direction = flat(movementGoal - position)
    if direction.Magnitude < 0.05 then
        hum:Move(Vector3.zero, false)
        State.path = Vector3.zero
        return
    end
    direction = direction.Unit

    if CONFIG.AvoidCatchers and #threats > 0 then
        direction = chooseRunnerDirection(position, movementGoal, threats)
    end

    checkStuck(now, position)
    if State.stuck then
        local center = getZoneCenter(State.safezones.b, position.Y) or getZoneCenter(State.safezones.a, position.Y)
        if center then
            direction = flat(center - position).Unit
        end
    end

    State.path = direction
    hum.AutoRotate = true
    hum:Move(direction, false)

    -- Dash dacă e pericol
    if #threats > 0 then
        for _, threat in ipairs(threats) do
            if threat.collisionRisk and threat.timeToDanger <= 0.5 then
                requestDash(now)
                break
            end
        end
    end
end

-- ============ CATCHER LOGIC ============
local function selectCatcherTarget(now, myPosition)
    refreshRunnerTargets()
    local best, bestScore
    for _, plr in ipairs(State.runnerTargets) do
        local root = getRoot(plr)
        if root then
            local position = root.Position
            local velocity = flat(root.AssemblyLinearVelocity)
            local predicted = position + velocity * 0.45
            local distance = flat(predicted - myPosition).Magnitude
            local safe = inZone(position, State.safezones.a) or inZone(position, State.safezones.b)
            local score = distance + (safe and 18 or 0)
            if not bestScore or score < bestScore then
                best = plr
                bestScore = score
            end
        end
    end
    State.catcherTarget = best
    return best
end

local function catcherAttack(target, now, root)
    if not target or not root then return end
    local c = getCharacter()
    if c and c:GetAttribute("TackleActive") == true then return end
    local targetRoot = getRoot(target)
    if not targetRoot then return end
    local targetVel = flat(targetRoot.AssemblyLinearVelocity)
    local meleePos = targetRoot.Position + targetVel * 0.15
    local tacklePos = targetRoot.Position + targetVel * 0.1

    local meleeReady = CONFIG.AutoMelee and now - State.lastMelee >= 0.35
        and flat(meleePos - root.Position).Magnitude <= 9
    local tackleReady = CONFIG.AutoTackle and now - State.lastTackle >= 1.2
        and flat(tacklePos - root.Position).Magnitude <= 12

    if CONFIG.AttackPriority == "Tackle First" then
        if tackleReady then
            pcall(TacklePrediction.request)
            State.lastTackle = now
            return
        end
        if meleeReady then
            pcall(MeleeEvent.FireServer, MeleeEvent, math.random(1, 100000))
            State.lastMelee = now
        end
    elseif CONFIG.AttackPriority == "Melee First" then
        if meleeReady then
            pcall(MeleeEvent.FireServer, MeleeEvent, math.random(1, 100000))
            State.lastMelee = now
            return
        end
        if tackleReady then
            pcall(TacklePrediction.request)
            State.lastTackle = now
        end
    else
        if tackleReady and targetVel.Magnitude >= 5 then
            pcall(TacklePrediction.request)
            State.lastTackle = now
        elseif meleeReady then
            pcall(MeleeEvent.FireServer, MeleeEvent, math.random(1, 100000))
            State.lastMelee = now
        elseif tackleReady then
            pcall(TacklePrediction.request)
            State.lastTackle = now
        end
    end
end

local function catcherStep(now, dt)
    if not isCatcherActive() then
        State.catcherTarget = nil
        return
    end
    if not CONFIG.CatcherChase and not CONFIG.AutoTackle and not CONFIG.AutoMelee then return end

    local root = getRoot()
    local hum = getHumanoid()
    if not root or not hum or hum.Health <= 0 or hum.PlatformStand or hum.Sit then return end

    local target = selectCatcherTarget(now, root.Position)
    if not target then return end
    local targetRoot = getRoot(target)
    if not targetRoot then return end

    if CONFIG.CatcherChase then
        local direction = flat(targetRoot.Position - root.Position)
        if direction.Magnitude > 0.05 then
            hum.AutoRotate = true
            hum:Move(direction.Unit, false)
        end
    end

    if CONFIG.AutoTackle or CONFIG.AutoMelee then
        catcherAttack(target, now, root)
    end
end

-- ============ SPEED OVERRIDE ============
local function applySpeedOverride()
    local hum = getHumanoid()
    local char = getCharacter()
    if not hum or not char then return end
    if char:GetAttribute("MovementState") == "Dashing" or char:GetAttribute("MovementState") == "Boosting" then return end
    local native = tonumber(char:GetAttribute("MovementSpeed"))
    if not native or native <= 0 then return end
    local role = getRole()
    local speed = native
    if role == "Runner" and CONFIG.CustomSpeed then
        speed = native * math.clamp(CONFIG.SpeedMultiplier, 1, 2)
    elseif role == "Catcher" and CONFIG.CatcherCustomSpeed then
        speed = native * math.clamp(CONFIG.CatcherSpeedMultiplier, 1, 2)
    end
    if math.abs(hum.WalkSpeed - speed) > 0.05 then
        hum.WalkSpeed = speed
    end
end
-- ============ OBSIDIAN UI ============
local repo = "https://raw.githubusercontent.com/majeskooooo/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options

-- Theme negru/alb
Library.Scheme.AccentColor = Color3.fromRGB(255, 255, 255)
Library.Scheme.BackgroundColor = Color3.fromRGB(0, 0, 0)
Library.Scheme.MainColor = Color3.fromRGB(0, 0, 0)
Library.Scheme.OutlineColor = Color3.fromRGB(50, 50, 50)
Library.Scheme.FontColor = Color3.fromRGB(255, 255, 255)

local Window = Library:CreateWindow({
    Title = "HussHub",
    Footer = "HussHub | discord.gg/fRymbb9g",
    FooterLeft = "v1.0.0",
    FooterRight = "By @avongg6 @@og.gg.66",
    Icon = 74169651953690,
    NotifySide = "Right",
    ShowCustomCursor = true,
    Size = UDim2.fromOffset(700, 850),
    Center = true,
    Resizable = true,
    SidebarCompacted = false,
    ShowMobileButtons = false,
    CornerRadius = 10,
    Font = Enum.Font.Gotham,
})

local Tabs = {
    Info = Window:AddTab("Info", "info"),
    Runner = Window:AddTab("Runner", "footprints"),
    Catcher = Window:AddTab("Catcher", "crosshair"),
    Wheel = Window:AddTab("Wheel", "rotate-cw"),
    Journey = Window:AddTab("Journey", "gift"),
    MapVote = Window:AddTab("Map Vote", "map"),
    Utilities = Window:AddTab("Utilities", "wrench"),
    Settings = Window:AddTab("Settings", "settings"),
}

Library:SetDPIScale(95)

-- ============ INFO TAB ============
local InfoLeft = Tabs.Info:AddLeftGroupbox("HussHub", "info")
InfoLeft:AddLabel("HussHub v1.0.0", true)
InfoLeft:AddLabel("Made by @avongg6 @@og.gg.66", true)
InfoLeft:AddLabel("Discord: discord.gg/fRymbb9g", true)
InfoLeft:AddDivider()
InfoLeft:AddButton({
    Text = "📋 Copy Discord Link",
    Func = function()
        pcall(function()
            setclipboard("discord.gg/fRymbb9g")
            Library:Notify({ Title = "HussHub", Text = "Discord copied!", Time = 3 })
        end)
    end,
})

local InfoRight = Tabs.Info:AddRightGroupbox("Status", "activity")
InfoRight:AddLabel("Role: Lobby", true)
InfoRight:AddLabel("State: Idle", true)
InfoRight:AddLabel("Game: Huss Valley", true)

-- ============ RUNNER TAB ============
local RunnerBox = Tabs.Runner:AddLeftGroupbox("Auto Run", "play")

RunnerBox:AddToggle("RunnerEnabled", {
    Text = "Auto Run",
    Default = true,
    Callback = function(v) CONFIG.RunnerEnabled = v end,
})

RunnerBox:AddToggle("AutoRevive", {
    Text = "Auto Revive Players",
    Default = true,
    Callback = function(v) CONFIG.AutoRevive = v end,
})

RunnerBox:AddToggle("ReviveBeforeGems", {
    Text = "Revive Before Gems",
    Default = true,
    Callback = function(v) CONFIG.ReviveBeforeGems = v end,
})

RunnerBox:AddToggle("AutoGems", {
    Text = "Auto Collect Gems",
    Default = true,
    Callback = function(v) CONFIG.AutoGems = v end,
})

RunnerBox:AddToggle("AvoidCatchers", {
    Text = "Avoid Catchers",
    Default = true,
    Callback = function(v) CONFIG.AvoidCatchers = v end,
})

RunnerBox:AddToggle("AutoDash", {
    Text = "Auto Dash",
    Default = true,
    Callback = function(v) CONFIG.AutoDash = v end,
})

local RunnerSpeedBox = Tabs.Runner:AddLeftGroupbox("Speed", "gauge")

RunnerSpeedBox:AddToggle("CustomSpeed", {
    Text = "Custom Speed",
    Default = false,
    Callback = function(v) CONFIG.CustomSpeed = v end,
})

RunnerSpeedBox:AddSlider("SpeedMultiplier", {
    Text = "Speed Multiplier",
    Default = 1.0,
    Min = 1.0,
    Max = 2.0,
    Rounding = 1,
    Callback = function(v) CONFIG.SpeedMultiplier = v end,
})

local RunnerVisualsBox = Tabs.Runner:AddRightGroupbox("Visuals", "eye")

RunnerVisualsBox:AddToggle("ShowGoal", {
    Text = "Show Goal",
    Default = true,
    Callback = function(v) CONFIG.ShowGoal = v end,
})

RunnerVisualsBox:AddToggle("ShowThreats", {
    Text = "Show Threats",
    Default = true,
    Callback = function(v) CONFIG.ShowThreats = v end,
})

RunnerVisualsBox:AddToggle("ShowESP", {
    Text = "ESP Players",
    Default = false,
    Callback = function(v) CONFIG.ShowESP = v end,
}):AddColorPicker("ESPColor", {
    Default = Color3.fromRGB(255, 182, 255),
    Title = "ESP Color",
    Callback = function(v) CONFIG.ESPColor = v end,
})

RunnerVisualsBox:AddToggle("TracerESP", {
    Text = "Tracer ESP",
    Default = false,
    Callback = function(v) CONFIG.TracerESP = v end,
}):AddColorPicker("TracerColor", {
    Default = Color3.fromRGB(255, 182, 255),
    Title = "Tracer Color",
    Callback = function(v) CONFIG.TracerColor = v end,
})

RunnerVisualsBox:AddSlider("TracerThickness", {
    Text = "Tracer Thickness",
    Default = 0.15,
    Min = 0.05,
    Max = 1,
    Rounding = 2,
    Callback = function(v) CONFIG.TracerThickness = v end,
})

RunnerVisualsBox:AddToggle("ShowHitboxes", {
    Text = "Hitbox Expander",
    Default = false,
    Callback = function(v) CONFIG.ShowHitboxes = v end,
})

RunnerVisualsBox:AddSlider("HitboxSize", {
    Text = "Hitbox Size",
    Default = 5,
    Min = 1,
    Max = 15,
    Rounding = 0,
    Callback = function(v) CONFIG.HitboxSize = v end,
})

-- ============ CATCHER TAB ============
local CatcherBox = Tabs.Catcher:AddLeftGroupbox("Auto Chase", "crosshair")

CatcherBox:AddToggle("CatcherChase", {
    Text = "Auto Chase",
    Default = true,
    Callback = function(v) CONFIG.CatcherChase = v end,
})

CatcherBox:AddToggle("AutoTackle", {
    Text = "Auto Tackle",
    Default = true,
    Callback = function(v) CONFIG.AutoTackle = v end,
})

CatcherBox:AddToggle("AutoMelee", {
    Text = "Auto Melee",
    Default = true,
    Callback = function(v) CONFIG.AutoMelee = v end,
})

CatcherBox:AddDropdown("AttackPriority", {
    Values = {"Smart", "Tackle First", "Melee First"},
    Default = "Smart",
    Text = "Attack Priority",
    Callback = function(v) CONFIG.AttackPriority = v end,
})

local CatcherSpeedBox = Tabs.Catcher:AddRightGroupbox("Speed", "gauge")

CatcherSpeedBox:AddToggle("CatcherCustomSpeed", {
    Text = "Custom Speed",
    Default = false,
    Callback = function(v) CONFIG.CatcherCustomSpeed = v end,
})

CatcherSpeedBox:AddSlider("CatcherSpeedMultiplier", {
    Text = "Speed Multiplier",
    Default = 1.0,
    Min = 1.0,
    Max = 2.0,
    Rounding = 1,
    Callback = function(v) CONFIG.CatcherSpeedMultiplier = v end,
})

-- ============ WHEEL TAB ============
local WheelBox = Tabs.Wheel:AddLeftGroupbox("Auto Spin", "rotate-cw")

WheelBox:AddToggle("AutoSpinWheel", {
    Text = "Auto Spin Wheel",
    Default = false,
    Callback = function(v) CONFIG.AutoSpinWheel = v end,
})

WheelBox:AddSlider("WheelInterval", {
    Text = "Spin Interval (s)",
    Default = 6,
    Min = 5.5,
    Max = 30,
    Rounding = 1,
    Callback = function(v) CONFIG.WheelInterval = v end,
})

WheelBox:AddSlider("WheelMinCredits", {
    Text = "Minimum Credits",
    Default = 1,
    Min = 1,
    Max = 50,
    Rounding = 0,
    Callback = function(v) CONFIG.WheelMinCredits = v end,
})

local WheelStatusBox = Tabs.Wheel:AddRightGroupbox("Status", "info")
WheelStatusBox:AddLabel("Credits: 0", true)
WheelStatusBox:AddLabel("Spins: 0", true)

-- ============ JOURNEY TAB ============
local JourneyBox = Tabs.Journey:AddLeftGroupbox("Rewards", "gift")

JourneyBox:AddToggle("AutoClaimJourney", {
    Text = "Auto Claim Rewards",
    Default = false,
    Callback = function(v) CONFIG.AutoClaimJourney = v end,
})

JourneyBox:AddButton({
    Text = "Claim Now",
    Func = function()
        pcall(function()
            JourneyEvent:FireServer("ClaimAll", nil, JourneyConfig.SeasonId)
        end)
        Library:Notify({ Title = "Journey", Text = "Claim request sent!", Time = 3 })
    end,
})

-- ============ MAP VOTE TAB ============
local MapVoteBox = Tabs.MapVote:AddLeftGroupbox("Voting", "map")

MapVoteBox:AddDropdown("MapVoteSelection", {
    Values = {"Map 1", "Map 2", "Map 3"},
    Default = "Map 1",
    Text = "Preferred Map",
    Callback = function(v) CONFIG.MapVoteSelection = v end,
})

MapVoteBox:AddToggle("AutoMapVote", {
    Text = "Auto Vote",
    Default = false,
    Callback = function(v) CONFIG.AutoMapVote = v end,
})

MapVoteBox:AddButton({
    Text = "Vote Now",
    Func = function()
        if State.mapVoteToken and State.mapVotePhase == "Voting" then
            local idx = tonumber(CONFIG.MapVoteSelection:match("%d+"))
            local optionId = State.mapVoteOptionIds[idx]
            if optionId then
                pcall(function()
                    MapVoteEvent:FireServer("Vote", optionId, State.mapVoteToken)
                end)
                Library:Notify({ Title = "Map Vote", Text = "Voted " .. CONFIG.MapVoteSelection, Time = 3 })
            end
        end
    end,
})

-- ============ UTILITIES TAB ============
local UtilBox = Tabs.Utilities:AddLeftGroupbox("General", "wrench")

UtilBox:AddToggle("AntiIdleKick", {
    Text = "Anti Idle Kick",
    Default = true,
    Callback = function(v) CONFIG.AntiIdleKick = v end,
})

UtilBox:AddToggle("DisableAFK", {
    Text = "Disable Built-in AFK",
    Default = false,
    Callback = function(v) CONFIG.DisableAFK = v end,
})

UtilBox:AddButton({
    Text = "Rejoin Server",
    Func = function()
        pcall(function()
            game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
        end)
    end,
})

-- ============ SETTINGS TAB ============
local SettingsBox = Tabs.Settings:AddLeftGroupbox("Menu", "settings")

SettingsBox:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", {
    Default = "RightShift",
    NoUI = true,
    Text = "Menu keybind",
})

SettingsBox:AddButton({
    Text = "Unload Script",
    Func = function()
        Library:Unload()
    end,
})

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("HussHub")
SaveManager:SetFolder("HussHub/HussValley")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

-- ============ ANTI-IDLE ============
local idleConnection = LocalPlayer.Idled:Connect(function()
    if CONFIG.AntiIdleKick then
        pcall(function()
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
    end
end)

-- ============ AFK OVERRIDE ============
task.spawn(function()
    while LocalPlayer.Parent do
        task.wait(0.5)
        if CONFIG.DisableAFK and LocalPlayer:GetAttribute("InMatch") ~= true then
            local now = os.clock()
            if now - State.afkLastRequest > 2 then
                State.afkLastRequest = now
                pcall(function()
                    PlayerPreferences:FireServer("SetAFK", false)
                end)
            end
        end
    end
end)
-- ============ VISUALS (Goal, Threats, ESP, Hitboxes) ============
local Visuals = {
    goal = nil,
    threats = {},
    esp = {},
    hitboxes = {},
}

local function cleanupVisuals()
    if Visuals.goal and Visuals.goal.Parent then Visuals.goal:Destroy() end
    Visuals.goal = nil
    for _, part in pairs(Visuals.threats) do if part.Parent then part:Destroy() end end
    table.clear(Visuals.threats)
    for _, part in pairs(Visuals.esp) do if part.Parent then part:Destroy() end end
    table.clear(Visuals.esp)
    for _, part in pairs(Visuals.hitboxes) do if part.Parent then part:Destroy() end end
    table.clear(Visuals.hitboxes)
end

local function ensurePart(store, key, size, color, transparency)
    local part = store[key]
    if part and part.Parent then return part end
    part = Instance.new("Part")
    part.Name = "HussHub_Visual"
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(size, size, size)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.ForceField
    part.Color = color
    part.Transparency = transparency
    part.Parent = workspace
    store[key] = part
    return part
end

local function updateVisuals()
    -- Goal
    if CONFIG.ShowGoal and State.currentGoal then
        local part = Visuals.goal
        if not part or not part.Parent then
            part = Instance.new("Part")
            part.Name = "HussHub_Goal"
            part.Shape = Enum.PartType.Ball
            part.Size = Vector3.new(2.5, 2.5, 2.5)
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.CastShadow = false
            part.Material = Enum.Material.ForceField
            part.Color = Color3.fromRGB(80, 200, 255)
            part.Transparency = 0.45
            part.Parent = workspace
            Visuals.goal = part
        end
        part.CFrame = CFrame.new(State.currentGoal)
    elseif Visuals.goal then
        Visuals.goal:Destroy()
        Visuals.goal = nil
    end

    -- Threats
    if CONFIG.ShowThreats and isRunnerActive() then
        local threats = State.threats
        for i = 1, math.min(#threats, 8) do
            local threat = threats[i]
            local part = ensurePart(Visuals.threats, i, threat.danger * 2, Color3.fromRGB(255, 90, 90), 0.82)
            part.CFrame = CFrame.new(threat.position)
        end
        for i = #threats + 1, 20 do
            local part = Visuals.threats[i]
            if part then part:Destroy() Visuals.threats[i] = nil end
        end
    else
        for i, part in pairs(Visuals.threats) do
            if part.Parent then part:Destroy() end
            Visuals.threats[i] = nil
        end
    end

    -- ESP
    if CONFIG.ShowESP then
        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local root = plr.Character:FindFirstChild("HumanoidRootPart")
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                if root and hum and hum.Health > 0 then
                    seen[plr] = true
                    local highlight = plr.Character:FindFirstChild("HussHub_ESP")
                    if not highlight then
                        highlight = Instance.new("Highlight", plr.Character)
                        highlight.Name = "HussHub_ESP"
                    end
                    highlight.FillColor = CONFIG.ESPColor
                    highlight.OutlineColor = CONFIG.ESPColor
                    highlight.FillTransparency = 0.7
                    highlight.OutlineTransparency = 0
                end
            end
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if not seen[plr] and plr.Character then
                local h = plr.Character:FindFirstChild("HussHub_ESP")
                if h then h:Destroy() end
            end
        end
    else
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then
                local h = plr.Character:FindFirstChild("HussHub_ESP")
                if h then h:Destroy() end
            end
        end
    end

    -- Hitbox Expander
    if CONFIG.ShowHitboxes and (isRunnerActive() or isCatcherActive()) then
        local role = getRole()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local targetRole = plr:GetAttribute("GameRole")
                local relevant = (role == "Runner" and targetRole == "Catcher")
                    or (role == "Catcher" and targetRole == "Runner")
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if relevant and hrp then
                    local size = CONFIG.HitboxSize
                    hrp.Size = Vector3.new(size, size, size)
                    hrp.Transparency = 0.5
                    hrp.CanCollide = false
                    hrp.Material = Enum.Material.ForceField
                    Visuals.hitboxes[plr] = true
                elseif Visuals.hitboxes[plr] and hrp then
                    hrp.Size = Vector3.new(2, 2, 1)
                    hrp.Transparency = 1
                    hrp.Material = Enum.Material.Plastic
                    Visuals.hitboxes[plr] = nil
                end
            end
        end
    else
        for plr, _ in pairs(Visuals.hitboxes) do
            if plr.Character then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.Size = Vector3.new(2, 2, 1)
                    hrp.Transparency = 1
                    hrp.Material = Enum.Material.Plastic
                end
            end
        end
        table.clear(Visuals.hitboxes)
    end
end

-- ============ MAIN LOOPS ============
local RENDER_NAME = "HussHub_MainLoop"
RunService:UnbindFromRenderStep(RENDER_NAME)

local lastControllerTick = os.clock()
local controllerInterval = UserInputService.TouchEnabled and (1/30) or 0

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Input.Value, function(dt)
    local now = os.clock()
    if now - lastControllerTick >= controllerInterval then
        local controllerDt = math.max(dt, now - lastControllerTick)
        lastControllerTick = now

        pcall(runnerStep, now, controllerDt)
        pcall(catcherStep, now, controllerDt)
        pcall(applySpeedOverride)
    end

    -- Update visuals (mai rar)
    if now - (Visuals._lastUpdate or 0) >= 0.1 then
        Visuals._lastUpdate = now
        pcall(updateVisuals)
    end
end)

-- ============ SAFEZONE REFRESH ============
task.spawn(function()
    while LocalPlayer.Parent do
        task.wait(5)
        State.safezonesCached = false
    end
end)

-- ============ WHEEL AUTO-SPIN ============
task.spawn(function()
    while LocalPlayer.Parent do
        task.wait(1)
        if CONFIG.AutoSpinWheel and LocalPlayer:GetAttribute("InMatch") ~= true and not State.wheelSpinning then
            local now = os.clock()
            if now >= State.wheelNextAttempt then
                pcall(function()
                    SpinWheelEvent:FireServer("State")
                end)
                if State.wheelCredits >= CONFIG.WheelMinCredits then
                    State.wheelSpinning = true
                    pcall(function()
                        SpinWheelEvent:FireServer("Spin")
                    end)
                    State.wheelNextAttempt = now + math.clamp(CONFIG.WheelInterval, 5.5, 30)
                    task.delay(1, function() State.wheelSpinning = false end)
                end
            end
        end
    end
end)

-- ============ WHEEL STATE LISTENER ============
SpinWheelEvent.OnClientEvent:Connect(function(kind, payload)
    if kind == "State" and type(payload) == "table" then
        State.wheelCredits = tonumber(payload.credits) or 0
    end
end)

-- ============ JOURNEY LISTENER ============
JourneyEvent.OnClientEvent:Connect(function(action, data)
    if action == "State" and type(data) == "table" then
        State.journeyLoaded = data.loaded == true
        State.journeyTier = tonumber(data.tier) or 1
        State.journeyClaims = data.claims or {}
        if CONFIG.AutoClaimJourney and State.journeyLoaded
            and LocalPlayer:GetAttribute("InMatch") ~= true
            and not State.journeyClaiming then
            State.journeyClaiming = true
            task.delay(1, function()
                pcall(function()
                    JourneyEvent:FireServer("ClaimAll", nil, JourneyConfig.SeasonId)
                end)
                State.journeyClaiming = false
            end)
        end
    end
end)

task.spawn(function()
    while LocalPlayer.Parent do
        task.wait(3)
        if LocalPlayer:GetAttribute("InMatch") ~= true then
            pcall(function()
                JourneyEvent:FireServer("Get")
            end)
        end
    end
end)

-- ============ MAP VOTE LISTENER ============
if MapVoteState and MapVoteState:IsA("StringValue") then
    local function readState()
        local ok, state = pcall(function()
            return HttpService:JSONDecode(MapVoteState.Value)
        end)
        if ok and type(state) == "table" then
            State.mapVotePhase = tostring(state.phase or "Waiting")
            State.mapVoteToken = state.token
            local opts = state.options or {}
            State.mapVoteOptionIds = {}
            for i = 1, math.min(#opts, 3) do
                local o = opts[i]
                if type(o) == "table" then
                    State.mapVoteOptionIds[i] = o.id or o.Id or o.key
                end
            end
            if CONFIG.AutoMapVote and State.mapVotePhase == "Voting" then
                local idx = tonumber(CONFIG.MapVoteSelection:match("%d+"))
                local optId = State.mapVoteOptionIds[idx]
                if optId and State.mapVoteToken and os.clock() - State.mapVoteLastAction > 1 then
                    State.mapVoteLastAction = os.clock()
                    pcall(function()
                        MapVoteEvent:FireServer("Vote", optId, State.mapVoteToken)
                    end)
                end
            end
        end
    end
    readState()
    MapVoteState.Changed:Connect(readState)
end

-- ============ CHARACTER RESET ============
LocalPlayer.CharacterAdded:Connect(function()
    State.currentGoal = nil
    State.gemTarget = nil
    State.reviveTarget = nil
    State.reviveStarted = false
    State.stuck = false
    State.lastPosition = nil
    State.path = Vector3.zero
    State.safezonesCached = false
    table.clear(State.threats)
    threatHistory = {}
    cleanupVisuals()
end)

-- ============ UNLOAD ============
local function unload()
    pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
    pcall(cleanupVisuals)
    pcall(cancelRevive)
    if idleConnection then idleConnection:Disconnect() end
    pcall(function() Library:Unload() end)
    getgenv().HussHub = nil
end

getgenv().HussHubUnload = unload

-- ============ NOTIFICATION ============
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "HussHub",
        Text = "Loaded! By @avongg6 @@og.gg.66",
        Duration = 4,
    })
end)

Library:Notify({
    Title = "HussHub",
    Text = "Loaded successfully!",
    Time = 4,
})

