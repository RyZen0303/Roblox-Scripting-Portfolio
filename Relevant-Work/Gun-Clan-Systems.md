# Relevant Systems — Gun Clan Role

Selected implementation evidence from **Land Warfare**, a solo-developed Roblox game. These examples are relevant to the requested Gun Clan systems. They are excerpts from the original project, not standalone packages.

> **Scope note:** Land Warfare is a vehicle-combat game. Its cannon controller demonstrates projectile simulation, server-side hit detection, damage dispatch, reload gating, and mechanical recoil. It is not presented as a completed infantry FPS weapon system.

## 1. Weapon firing, hit registration, damage, reload, and recoil

**Source:** [ProjectileMaster.luau](https://github.com/RyZen0303/Land-Warfare-Project/blob/main/Fire%20Control%20System/ProjectileMaster.luau)

The server creates and simulates the projectile, raycasts along its displacement to detect impacts, and dispatches damage. The same controller gates repeated firing during reload and animates the cannon's recoil joint.

### Server-side projectile hit detection

```lua
local displacement = currentPosition - lastPosition

local raycastResult = workspace:Raycast(
    lastPosition - displacement,
    displacement * 1.1,
    raycastParams
)

if raycastResult then
    local hitInstance = raycastResult.Instance
    connection:Disconnect()
    RenderBulletEvent:FireAllClients("DestroyVisual", bulletId)

    local hitCharacter = hitInstance:FindFirstAncestorOfClass("Model")
    local targetHumanoid = hitCharacter
        and hitCharacter:FindFirstChildOfClass("Humanoid")

    if targetHumanoid and not hitCharacter:GetAttribute("Health") then
        targetHumanoid:TakeDamage(baseDamage)
    else
        ProcessDamage:Fire(
            hitInstance,
            baseDamage,
            damageType,
            attackerPlayer,
            weaponPart
        )
    end

    bullet:Destroy()
end
```

### Reload lock and timer

```lua
if reloadingTanks[weapon] then
    notifyReject(player, "Weapon is currently reloading.")
    return
end

reloadingTanks[weapon] = true

local success, err = pcall(function()
    firing(weapon, tankModel, aimPoint, clientMuzzlePos,
        clientLookDirection, player)

    local maxReload = weapon:GetAttribute("ReloadTime") or 3
    tankModel:SetAttribute("MaxReloadTime", maxReload)

    local timeLeft = maxReload
    while timeLeft > 0 do
        tankModel:SetAttribute("ReloadTime", timeLeft)
        timeLeft -= RunService.Heartbeat:Wait()
    end

    tankModel:SetAttribute("ReloadTime", 0)
end)

if not success then
    warn("[RELOAD ERROR]: " .. tostring(err))
end

reloadingTanks[weapon] = nil
```

### Mechanical recoil

```lua
local recoilJoint = cannon:FindFirstChild("RecoilJoint")
if recoilJoint then
    local originalC0 = recoilJoint.C0
    local retract = TweenInfo.new(
        0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out
    )
    local recover = TweenInfo.new(
        0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut
    )

    local targetC0 = originalC0 * CFrame.new(0, 0.65, 0)
    local tween = TweenService:Create(
        recoilJoint, retract, {C0 = targetC0}
    )
    tween:Play()
    tween.Completed:Connect(function()
        TweenService:Create(
            recoilJoint, recover, {C0 = originalC0}
        ):Play()
    end)
end
```

**Relevance:** Strong overlap with firing flow, projectile/hit registration, damage handling, reload state, and weapon feedback. The recoil shown here is cannon/joint recoil, not first-person camera recoil. Infantry ADS, magazine/ammo handling, and FPS viewmodel behavior would still need implementation.

## 2. Persistent player data

**Source:** [PlayerDataManager.luau](https://github.com/RyZen0303/Land-Warfare-Project/blob/main/Data%20Store%20System/PlayerDataManager.luau)

Uses DataStoreService, per-player keys, retry handling, validation/sanitization, and UpdateAsync saves.

### Load with retry and validation

```lua
local key = "Player_" .. player.UserId

local success, savedData = executeWithRetry("LoadData", function()
    return playerDataStore:GetAsync(key)
end)

if not success then
    sessionData[player] = {
        Data = createDefaultData(),
        IsLoaded = false,
        LoadFailed = true,
    }
    return false
end

local data = savedData == nil
    and createDefaultData()
    or validateAndSanitize(savedData)
```

### Save while preserving existing ownership records

```lua
local success, result = executeWithRetry("SaveData", function()
    return playerDataStore:UpdateAsync(key, function(currentData)
        if typeof(currentData) == "table"
            and typeof(currentData.OwnedSkills) == "table"
        then
            for skillName, owned in pairs(currentData.OwnedSkills) do
                if typeof(skillName) == "string" and owned == true then
                    dataToSave.OwnedSkills[skillName] = true
                end
            end
        end

        return dataToSave
    end)
end)
```

**Relevance:** Direct experience with persistent player progression and safe data loading/saving. The current schema stores Cash, OwnedSkills, and EquippedSkill; it does not yet store the Gun Clan-specific K/D or leaderboard statistics.

## 3. Server-authoritative shop and skill validation

**Source:** [ShopServerHandler.luau](https://github.com/RyZen0303/Land-Warfare-Project/blob/main/Shop%20Systems/ShopServerHandler.luau)

The server validates incoming purchase requests against types, the server-side catalog, loaded player data, and ownership before calling the data manager.

```lua
PurchaseItemFunction.OnServerInvoke = function(player, itemName)
    if typeof(itemName) ~= "string" then
        return false, "Invalid skill parameters"
    end

    local skillData = PASSIVE_SKILL_CATALOG[itemName]
    if not skillData then
        return false, "Skill does not exist in catalog"
    end

    if not PlayerDataManager.IsDataLoaded(player) then
        return false, "Player data is not loaded yet"
    end

    if PlayerSkillManager.HasSkill(player, itemName) then
        return false, "Skill already unlocked"
    end

    return PlayerDataManager.PurchaseSkill(
        player, itemName, skillData.Price
    )
end
```

**Relevance:** Directly relevant to server-side validation and persistent player progression. The same pattern can be applied to unlocks, loadouts, and other player-owned content.

## 4. Skill ownership and equip authorization

**Source:** [PlayerSkillManager.luau](https://github.com/RyZen0303/Land-Warfare-Project/blob/main/Data%20Store%20System/PlayerSkillManager.luau)

The manager checks that a skill exists in the server catalog, player data is loaded, and the player owns the skill before equipping it.

```lua
function PlayerSkillManager.Equip(player, skillName)
    local success, message = getPlayerSession(player)
    if not success then
        return false, message
    end

    if not getSkillData(skillName) then
        return false, "Skill does not exist in catalog"
    end

    if not PlayerDataManager.HasSkill(player, skillName) then
        return false, "Skill has not been unlocked"
    end

    player:SetAttribute("EquippedSkill", skillName)
    return true, "Skill equipped successfully"
end
```

**Relevance:** Demonstrates server-side ownership and equip-state management that can transfer to weapon unlocks or loadout selection.

## 5. Team objective ownership

**Source:** [GameLogic.luau](https://github.com/RyZen0303/Land-Warfare-Project/blob/main/Main%20System/GameLogic.luau)

```lua
function GameLogic.IsPointOwnedByTeam(pointName, teamName)
    local zone = CAPTURE_ZONES_FOLDER:FindFirstChild(pointName)
    if zone then
        return zone:GetAttribute("Owner") == teamName
    end
    return false
end
```

**Relevance:** A small, direct example of querying team ownership for capture-point logic. This is not a complete match-scoring, timer, rotating-terminal, or payload objective framework.

## 6. Vehicle physics, input validation, and runtime optimization

**Source:** [TankDrivingMaster.luau](https://github.com/RyZen0303/Land-Warfare-Project/blob/main/Driving%20System/TankDrivingMaster.luau)

The controller validates the seated player before accepting tank input, clamps control values, caches per-tank state, and processes active tanks in a shared Heartbeat loop.

### Input validation and clamping

```lua
TankControlEvent.OnServerEvent:Connect(function(
    player, throttle, steer, aimPos
)
    local char = player.Character
    local seat = char
        and char:FindFirstChildOfClass("Humanoid")
        and char.Humanoid.SeatPart

    if seat and (seat:IsA("Seat") or seat.Name == "DriverSeat") then
        local tankRoot = seat:FindFirstAncestorOfClass("Model")
        if tankRoot and tankRoot:GetAttribute("IsTank") then
            if not tankInputs[tankRoot] then
                tankInputs[tankRoot] = {
                    t = 0, s = 0, aim = Vector3.new()
                }
            end

            if throttle ~= nil then
                tankInputs[tankRoot].t = math.clamp(throttle, -1, 1)
            end
            if steer ~= nil then
                tankInputs[tankRoot].s = math.clamp(steer, -1, 1)
            end
            if typeof(aimPos) == "Vector3" then
                tankInputs[tankRoot].aim = aimPos
            end
        end
    end
end)
```

**Relevance:** Transferable experience with multiplayer physics, server-side input checks, state caching, and frame-loop performance. This is vehicle control, not infantry movement code.

---

## Requirement coverage summary

| Gun Clan requirement | Evidence from Land Warfare |
|---|---|
| Firing / hit registration / damage | **Direct, vehicle cannon implementation** |
| Reload behavior | **Direct, cannon reload lock and timer** |
| Recoil feedback | **Direct, mechanical cannon recoil** |
| Server-side validation | **Direct, firing, shop, and vehicle input checks** |
| Persistent player data | **Direct, DataStore load/save and progression** |
| Team objectives | **Partial, capture-point ownership query** |
| Multiplayer performance / physics | **Transferable, custom tank physics and caching** |
| Infantry ADS / FPS camera recoil / viewmodels | **Not demonstrated in this project** |
| Match lifecycle / scoreboard / results / payload | **Not demonstrated in these selected files** |

**Project context:** Land Warfare was developed independently as an end-to-end solo project. The code excerpts above are selected from the larger project and depend on its original Roblox instances, attributes, RemoteEvents, and asset hierarchy.
