-- ProjectileMaster.server.luau
-- Server-side Raycast, Damage, Ammo, Hitmarker & Chambering Reload Handler

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- == Module Imports ==
local Modules = ReplicatedStorage:WaitForChild("Modules")
local WeaponConfigLoader = require(Modules:WaitForChild("WeaponConfigLoader") :: ModuleScript)

-- == Setup Folders & Remote Events ==
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local fireWeaponEvent = eventsFolder:FindFirstChild("FireWeaponEvent")
if not fireWeaponEvent then
	fireWeaponEvent = Instance.new("RemoteEvent")
	fireWeaponEvent.Name = "FireWeaponEvent"
	fireWeaponEvent.Parent = eventsFolder
end

local reloadWeaponEvent = eventsFolder:FindFirstChild("ReloadWeaponEvent")
if not reloadWeaponEvent then
	reloadWeaponEvent = Instance.new("RemoteEvent")
	reloadWeaponEvent.Name = "ReloadWeaponEvent"
	reloadWeaponEvent.Parent = eventsFolder
end

local visualEvent = eventsFolder:FindFirstChild("BulletVisualEvent")
if not visualEvent then
	visualEvent = Instance.new("RemoteEvent")
	visualEvent.Name = "BulletVisualEvent"
	visualEvent.Parent = eventsFolder
end

local hitmarkerEvent = eventsFolder:FindFirstChild("HitmarkerEvent")
if not hitmarkerEvent then
	hitmarkerEvent = Instance.new("RemoteEvent")
	hitmarkerEvent.Name = "HitmarkerEvent"
	hitmarkerEvent.Parent = eventsFolder
end

-- Remote Event for syncing fire mode switching across network
local toggleFireModeEvent = eventsFolder:FindFirstChild("ToggleFireModeEvent")
if not toggleFireModeEvent then
	toggleFireModeEvent = Instance.new("RemoteEvent")
	toggleFireModeEvent.Name = "ToggleFireModeEvent"
	toggleFireModeEvent.Parent = eventsFolder
end

-- Remote Event for cycling the bolt on bolt-action weapons
local cycleBoltEvent = eventsFolder:FindFirstChild("CycleBoltEvent")
if not cycleBoltEvent then
	cycleBoltEvent = Instance.new("RemoteEvent")
	cycleBoltEvent.Name = "CycleBoltEvent"
	cycleBoltEvent.Parent = eventsFolder
end

-- == Default Configurations ==
local DEFAULT_CONFIG = {
	Damage = 20,
	HeadshotMultiplier = 2.0,
	FireRate = 0.1,
	AmmoPerMag = 30,
	MaxReserveAmmo = 120,
	ReloadTime = 2.0,
	AllowChambering = true,
	BoltAction = false,
	SFX = "AK-47_Fire",
}

local lastFireTime = {}

local function initializeToolAmmo(tool: Tool, config: { [any]: any }?)
	local maxMag = (config and config.AmmoPerMag) or DEFAULT_CONFIG.AmmoPerMag
	local maxReserve = (config and config.MaxReserveAmmo) or DEFAULT_CONFIG.MaxReserveAmmo
	local defaultMode = (config and config.FireModes and config.FireModes.DefaultMode) or "Auto"
	local isBoltAction = if config and config.BoltAction ~= nil then config.BoltAction else DEFAULT_CONFIG.BoltAction

	if tool:GetAttribute("Ammo") == nil then
		tool:SetAttribute("Ammo", maxMag)
	end
	if tool:GetAttribute("ReserveAmmo") == nil then
		tool:SetAttribute("ReserveAmmo", maxReserve)
	end
	if tool:GetAttribute("IsReloading") == nil then
		tool:SetAttribute("IsReloading", false)
	end
	if tool:GetAttribute("FireMode") == nil then
		tool:SetAttribute("FireMode", defaultMode)
	end
	if isBoltAction and tool:GetAttribute("BoltNeedsCycle") == nil then
		tool:SetAttribute("BoltNeedsCycle", false)
	elseif not isBoltAction then
		tool:SetAttribute("BoltNeedsCycle", false)
	end
end

local function emitMuzzleSmoke(tool: Tool)
	local muzzlePoint = tool:FindFirstChild("GunMuzzlePoint", true) :: Attachment?
	if muzzlePoint and muzzlePoint:IsA("Attachment") then
		local smokeEmitter = muzzlePoint:FindFirstChildOfClass("ParticleEmitter")

		if smokeEmitter then
			smokeEmitter:Emit(5)
		else
			local dynamicSmoke = Instance.new("ParticleEmitter")
			dynamicSmoke.Name = "MuzzleSmoke"
			dynamicSmoke.Texture = "rbxassetid://258122325"
			dynamicSmoke.Lifetime = NumberRange.new(0.15, 0.3)
			dynamicSmoke.Rate = 0
			dynamicSmoke.Speed = NumberRange.new(5, 12)
			dynamicSmoke.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1.2)
			})
			dynamicSmoke.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 1)
			})
			dynamicSmoke.Parent = muzzlePoint

			dynamicSmoke:Emit(6)
			task.delay(0.5, function()
				dynamicSmoke:Destroy()
			end)
		end
	end
end

-- == 1. Fire Weapon Request Handler ==
fireWeaponEvent.OnServerEvent:Connect(function(player: Player, clientOrigin: Vector3, direction: Vector3, weaponName: string)
	local character = player.Character
	if not character then return end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool.Name ~= weaponName then return end

	local config = WeaponConfigLoader.GetConfig(weaponName)
	initializeToolAmmo(tool, config)

	if tool:GetAttribute("IsReloading") == true then return end

	local isBoltAction = if config and config.BoltAction ~= nil then config.BoltAction else DEFAULT_CONFIG.BoltAction
	if isBoltAction and tool:GetAttribute("BoltNeedsCycle") == true then
		return
	end

	local currentAmmo = tool:GetAttribute("Ammo")
	if currentAmmo <= 0 then return end

	local fireRate = (config and config.FireRate) or DEFAULT_CONFIG.FireRate
	local now = os.clock()
	if lastFireTime[player] and (now - lastFireTime[player]) < (fireRate * 0.8) then
		return
	end
	lastFireTime[player] = now

	tool:SetAttribute("Ammo", currentAmmo - 1)

	if isBoltAction then
		tool:SetAttribute("BoltNeedsCycle", true)
	end

	local firePoint = tool:FindFirstChild("GunFirePoint", true) :: Attachment?
	local actualOrigin = clientOrigin

	if firePoint and firePoint:IsA("Attachment") then
		actualOrigin = firePoint.WorldPosition
	end

	emitMuzzleSmoke(tool)

	local baseDamage = (config and config.Damage) or DEFAULT_CONFIG.Damage
	local headMultiplier = (config and config.HeadshotMultiplier) or DEFAULT_CONFIG.HeadshotMultiplier
	local sfxName = (config and config.Sounds and config.Sounds.Fire) or (config and config.SFX) or DEFAULT_CONFIG.SFX

	-- Direction vector provided directly by the client
	local normalizedDirection = direction.Magnitude > 0 and direction.Unit or Vector3.new(0, 0, -1)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true

	-- Extended fixed raycast distance (10,000 Studs) to prevent limit issues and floating point overflow
	local raycastResult = Workspace:Raycast(actualOrigin, normalizedDirection * 10000, raycastParams)
	local targetPosition = actualOrigin + (normalizedDirection * 10000)

	if raycastResult then
		targetPosition = raycastResult.Position
		local hitPart = raycastResult.Instance
		local hitModel = hitPart:FindFirstAncestorOfClass("Model")

		if hitModel then
			local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local isHeadshot = (hitPart.Name == "Head")
				local finalDamage = if isHeadshot then (baseDamage * headMultiplier) else baseDamage

				humanoid:TakeDamage(finalDamage)

				-- Trigger Hitmarker on attacker screen
				hitmarkerEvent:FireClient(player, isHeadshot)
			end
		end
	end

	-- Replicate bullet visual trajectory to other clients
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			visualEvent:FireClient(otherPlayer, actualOrigin, targetPosition, sfxName)
		end
	end
end)

-- == 2. Reload Request Handler ==
reloadWeaponEvent.OnServerEvent:Connect(function(player: Player, weaponName: string)
	local character = player.Character
	if not character then return end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool.Name ~= weaponName then return end

	local config = WeaponConfigLoader.GetConfig(weaponName)
	initializeToolAmmo(tool, config)

	if tool:GetAttribute("IsReloading") == true then return end

	local currentAmmo = tool:GetAttribute("Ammo")
	local reserveAmmo = tool:GetAttribute("ReserveAmmo")
	local maxMag = (config and config.AmmoPerMag) or DEFAULT_CONFIG.AmmoPerMag
	local allowChambering = if config and config.AllowChambering ~= nil then config.AllowChambering else DEFAULT_CONFIG.AllowChambering
	local reloadTime = (config and config.ReloadTime) or DEFAULT_CONFIG.ReloadTime

	local targetCapacity = maxMag
	if allowChambering and currentAmmo > 0 then
		targetCapacity = maxMag + 1
	end

	if currentAmmo >= targetCapacity or reserveAmmo <= 0 then return end

	tool:SetAttribute("IsReloading", true)

	task.wait(reloadTime)

	if tool and tool.Parent == character then
		local ammoNeeded = targetCapacity - currentAmmo
		local ammoToReload = math.min(ammoNeeded, reserveAmmo)

		tool:SetAttribute("Ammo", currentAmmo + ammoToReload)
		tool:SetAttribute("ReserveAmmo", reserveAmmo - ammoToReload)
		tool:SetAttribute("IsReloading", false)
	end
end)

-- == 3. Toggle Fire Mode Request Handler ==
toggleFireModeEvent.OnServerEvent:Connect(function(player: Player, weaponName: string, requestedMode: string)
	local character = player.Character
	if not character then return end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool.Name ~= weaponName then return end

	local config = WeaponConfigLoader.GetConfig(weaponName)

	-- Validate requested fire mode against config or fallback valid modes
	local isValid = requestedMode == "Semi" or requestedMode == "Burst" or requestedMode == "Auto"
	if config and config.FireModes and config.FireModes.Available then
		isValid = config.FireModes.Available[requestedMode] == true
	end

	if isValid then
		tool:SetAttribute("FireMode", requestedMode)
	end
end)

-- == 4. Cycle Bolt Request Handler ==
cycleBoltEvent.OnServerEvent:Connect(function(player: Player, weaponName: string)
	local character = player.Character
	if not character then return end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool.Name ~= weaponName then return end

	local config = WeaponConfigLoader.GetConfig(weaponName)
	local isBoltAction = if config and config.BoltAction ~= nil then config.BoltAction else DEFAULT_CONFIG.BoltAction
	if not isBoltAction then return end
	if tool:GetAttribute("IsReloading") == true then return end
	if tool:GetAttribute("BoltNeedsCycle") ~= true then return end

	tool:SetAttribute("BoltNeedsCycle", false)
end)