-- GunVisualClient.client.luau
-- Client-Driven Firing Loop, Weapon Config Reading, Sounds, Recoil Trigger, Bullet Hole & Visual/SFX Handler

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- == Module Imports ==
local Modules = ReplicatedStorage:WaitForChild("Modules")
local RecoilController = require(Modules:WaitForChild("RecoilController") :: ModuleScript)
local WeaponConfigLoader = require(Modules:WaitForChild("WeaponConfigLoader") :: ModuleScript)

-- == Folder & Event References ==
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local fireWeaponEvent = eventsFolder:WaitForChild("FireWeaponEvent")
local reloadWeaponEvent = eventsFolder:WaitForChild("ReloadWeaponEvent")
local visualEvent = eventsFolder:WaitForChild("BulletVisualEvent")
local sfxFolder = ReplicatedStorage:WaitForChild("SFX", 5)

-- Default Fallback Configurations
local DEFAULT_CONFIG = {
	FireRate = 0.1,
	SFX = "AK-47_Fire",
	AmmoPerMag = 30,
	BoltAction = false,
}

-- Firing state tracking
local isFiring = false
local canShootSemi = true

-- == Helper Function: Play SFX ==
local function playSFX(soundNameOrId: string?)
	if not soundNameOrId or soundNameOrId == "" then return end

	local soundTemplate: Sound? = nil
	if sfxFolder then
		soundTemplate = sfxFolder:FindFirstChild(soundNameOrId, true) :: Sound?
	end

	if soundTemplate and soundTemplate:IsA("Sound") then
		local sound = soundTemplate:Clone()
		sound.Parent = SoundService
		sound.Volume = soundTemplate.Volume * 1.5
		sound.PlaybackSpeed = soundTemplate.PlaybackSpeed + ((math.random() * 2 - 1) * 0.04)
		sound:Play()

		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		return
	end

	if string.find(soundNameOrId, "rbxassetid://") or tonumber(soundNameOrId) then
		local sound = Instance.new("Sound")
		sound.SoundId = string.find(soundNameOrId, "rbxassetid://") and soundNameOrId or ("rbxassetid://" .. soundNameOrId)
		sound.Volume = 1.2
		sound.Parent = SoundService
		sound:Play()

		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	else
		warn("[GunVisualClient] Sound not found in SFX folder or invalid ID: " .. tostring(soundNameOrId))
	end
end

-- == Helper Function: Trigger Reload SFX Sequence ==
local function playReloadSequence(config)
	if not config or not config.Sounds or not config.Sounds.Reload then return end

	local reloadSounds = config.Sounds.Reload
	local delays = (config.Sounds and config.Sounds.ReloadDelays) or {}

	if type(reloadSounds) == "string" then
		playSFX(reloadSounds)
	elseif type(reloadSounds) == "table" then
		if reloadSounds.MagOut then
			task.delay(delays.MagOut or 0.2, function()
				playSFX(reloadSounds.MagOut)
			end)
		end

		if reloadSounds.MagIn then
			task.delay(delays.MagIn or 1.8, function()
				playSFX(reloadSounds.MagIn)
			end)
		end

		if reloadSounds.Bolt then
			task.delay(delays.Bolt or 2.4, function()
				playSFX(reloadSounds.Bolt)
			end)
		end
	end
end

-- == Helper Function: Locate Fire Point Attachment & Tool ==
local function getLocalFirePoint()
	local character = localPlayer.Character
	if not character then return nil, nil end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then return nil, nil end

	local firePoint: Attachment? = camera:FindFirstChild("GunFirePoint", true) :: Attachment?
	if not firePoint then
		firePoint = tool:FindFirstChild("GunFirePoint", true) :: Attachment?
	end

	return firePoint, tool
end

-- == Helper Function: Emit Local Muzzle Smoke ==
local function emitLocalMuzzleSmoke(tool: Tool)
	local muzzlePoint = camera:FindFirstChild("GunMuzzlePoint", true) or tool:FindFirstChild("GunMuzzlePoint", true)
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

-- == Helper Function: Create Bullet Hole Decal ==
local function createBulletHole(hitPart: BasePart, hitPosition: Vector3, hitNormal: Vector3)
	if hitPart.Parent:FindFirstChildOfClass("Humanoid") or (hitPart.Parent.Parent and hitPart.Parent.Parent:FindFirstChildOfClass("Humanoid")) then
		return
	end

	local holePart = Instance.new("Part")
	holePart.Name = "BulletHole"
	holePart.Size = Vector3.new(0.6, 0.6, 0.05)
	holePart.Transparency = 1
	holePart.CanCollide = false
	holePart.CanQuery = false
	holePart.CanTouch = false
	holePart.Anchored = false

	holePart.CFrame = CFrame.lookAt(hitPosition, hitPosition + hitNormal)

	local decal = Instance.new("Decal")
	decal.Texture = "rbxassetid://2859765692"
	decal.Face = Enum.NormalId.Front
	decal.Parent = holePart

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = holePart
	weld.Part1 = hitPart
	weld.Parent = holePart

	holePart.Parent = Workspace

	Debris:AddItem(holePart, 10)
end

-- == Core Visual & SFX Function ==
local function renderTracer(origin: Vector3, targetPos: Vector3, sfxName: string)
	local distance = (targetPos - origin).Magnitude
	if distance < 0.1 then return end

	local BULLET_SPEED = 900
	local MIN_BULLET_LENGTH = 3.5
	local BULLET_THICKNESS = 0.2

	local initialLength = math.min(MIN_BULLET_LENGTH, distance)

	local bullet = Instance.new("Part")
	bullet.Name = "FPS_TracerBullet"
	bullet.Material = Enum.Material.Neon
	bullet.Color = Color3.fromRGB(255, 230, 80)
	bullet.CanCollide = false
	bullet.CanQuery = false
	bullet.CanTouch = false
	bullet.CastShadow = false
	bullet.Anchored = true

	local a0 = Instance.new("Attachment", bullet)
	local a1 = Instance.new("Attachment", bullet)
	a0.Position = Vector3.new(0, BULLET_THICKNESS / 2, 0)
	a1.Position = Vector3.new(0, -BULLET_THICKNESS / 2, 0)

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0))
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.0),
		NumberSequenceKeypoint.new(1, 1.0)
	})
	trail.Lifetime = 0.08
	trail.FaceCamera = true
	trail.Parent = bullet

	bullet.Size = Vector3.new(BULLET_THICKNESS, BULLET_THICKNESS, initialLength)
	bullet.CFrame = CFrame.lookAt(origin, targetPos) * CFrame.new(0, 0, -initialLength / 2)
	bullet.Parent = workspace.CurrentCamera

	local prevPos = origin
	local currentDistance = 0
	local isFirstFrame = true

	local connection
	connection = RunService.RenderStepped:Connect(function(deltaTime: number)
		local frameTravel = BULLET_SPEED * deltaTime
		currentDistance += frameTravel
		local alpha = math.clamp(currentDistance / distance, 0, 1)

		local nextPos = origin:Lerp(targetPos, alpha)

		if isFirstFrame then
			isFirstFrame = false
			local rawLength = (nextPos - origin).Magnitude
			local segmentLength = math.min(distance, math.max(initialLength, rawLength))
			local midPoint = origin:Lerp(nextPos, 0.5)

			bullet.Size = Vector3.new(BULLET_THICKNESS, BULLET_THICKNESS, segmentLength)
			bullet.CFrame = CFrame.lookAt(midPoint, nextPos)
			prevPos = nextPos
		else
			local segment = nextPos - prevPos
			local rawLength = segment.Magnitude
			local segmentLength = math.min(distance, math.max(initialLength, rawLength))

			if segmentLength > 0 then
				local midPoint = prevPos:Lerp(nextPos, 0.5)
				bullet.Size = Vector3.new(BULLET_THICKNESS, BULLET_THICKNESS, segmentLength)
				bullet.CFrame = CFrame.lookAt(midPoint, nextPos)
			end
			prevPos = nextPos
		end

		if alpha >= 1 then
			connection:Disconnect()

			local direction = (targetPos - origin).Unit
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude

			-- Add camera (Viewmodel) into the filter
			local filterList = { camera, bullet }
			if localPlayer.Character then
				table.insert(filterList, localPlayer.Character)
			end
			raycastParams.FilterDescendantsInstances = filterList

			local result = Workspace:Raycast(origin, direction * (distance + 1), raycastParams)
			if result and result.Instance then
				createBulletHole(result.Instance, result.Position, result.Normal)
			end

			task.delay(0.03, function()
				if bullet and bullet.Parent then
					bullet:Destroy()
				end
			end)
		end
	end)

	playSFX(sfxName)
end

-- == Helper Function: Get Active Fire Mode Safe Fallback ==
local function getActiveFireMode(tool: Tool, config: { [any]: any }?): string
	local mode = tool:GetAttribute("FireMode")
	if mode == "Auto" or mode == "Semi" or mode == "Burst" then
		return mode
	end

	-- Fallback to config default, or hard fallback to "Auto"
	if config and config.FireModes and config.FireModes.DefaultMode then
		return config.FireModes.DefaultMode
	end

	return "Auto"
end

-- == Single Shot Execution ==
local function executeShot(tool: Tool, config: { [any]: any })
	local firePoint, _ = getLocalFirePoint()
	local sfxName = (config and config.Sounds and config.Sounds.Fire) or (config and config.SFX) or DEFAULT_CONFIG.SFX

	local origin = Vector3.zero
	if firePoint then
		origin = firePoint.WorldPosition
	else
		local handle = tool:FindFirstChild("Handle") or tool.PrimaryPart
		if handle then
			origin = handle.Position
		end
	end

	if origin == Vector3.zero then return end

	local cameraCFrame = camera.CFrame
	local maxDistance = 500

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Add camera (Viewmodel) into the filter
	local filterList = { camera }
	if localPlayer.Character then
		table.insert(filterList, localPlayer.Character)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local camRayResult = Workspace:Raycast(cameraCFrame.Position, cameraCFrame.LookVector * maxDistance, raycastParams)
	local targetPos = if camRayResult then camRayResult.Position else (cameraCFrame.Position + (cameraCFrame.LookVector * maxDistance))
	local direction = (targetPos - origin).Unit

	if config and config.Recoil then
		RecoilController.Fire(config.Recoil)
	end

	emitLocalMuzzleSmoke(tool)
	renderTracer(origin, targetPos, sfxName)

	-- Lock the next shot locally immediately so rapid clicks cannot bypass the bolt cycle before server replication.
	if config and config.BoltAction == true then
		tool:SetAttribute("BoltNeedsCycle", true)
	end

	fireWeaponEvent:FireServer(origin, direction, tool.Name)
end

-- == Core Fire Routine ==
local function tryFireWeapon()
	local _, tool = getLocalFirePoint()
	if not tool or isFiring then return end

	local config = WeaponConfigLoader.GetConfig(tool.Name)
	local isReloading = tool:GetAttribute("IsReloading") or false
	local currentAmmo = tool:GetAttribute("Ammo")
	if currentAmmo == nil then
		currentAmmo = (config and config.AmmoPerMag) or DEFAULT_CONFIG.AmmoPerMag
	end

	if currentAmmo <= 0 or isReloading then return end

	if config and config.BoltAction == true and tool:GetAttribute("BoltNeedsCycle") == true then
		return
	end

	local fireMode = getActiveFireMode(tool, config)
	local fireRate = (config and config.FireRate) or DEFAULT_CONFIG.FireRate

	if fireMode == "Semi" then
		if not canShootSemi then return end
		canShootSemi = false
		executeShot(tool, config)
		task.wait(fireRate)

	elseif fireMode == "Burst" then
		isFiring = true
		local burstCount = (config and config.FireModes and config.FireModes.BurstCount) or 3
		local burstDelay = (config and config.FireModes and config.FireModes.BurstDelay) or 0.25

		for i = 1, burstCount do
			local checkAmmo = tool:GetAttribute("Ammo") or currentAmmo
			local checkReload = tool:GetAttribute("IsReloading") or false
			if checkAmmo <= 0 or checkReload then break end
			if config and config.BoltAction == true and tool:GetAttribute("BoltNeedsCycle") == true then break end

			executeShot(tool, config)
			task.wait(fireRate)
		end

		task.wait(burstDelay)
		isFiring = false

	else -- Default to "Auto"
		isFiring = true
		task.spawn(function()
			while isFiring and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
				local checkAmmo = tool:GetAttribute("Ammo") or currentAmmo
				local checkReload = tool:GetAttribute("IsReloading") or false
				if checkAmmo <= 0 or checkReload then break end
				if config and config.BoltAction == true and tool:GetAttribute("BoltNeedsCycle") == true then break end

				executeShot(tool, config)
				task.wait(fireRate)
			end
			isFiring = false
		end)
	end
end

-- == Equipment & Sound Handlers ==
local function setupToolListeners(tool: Tool)
	tool.Equipped:Connect(function()
		RecoilController.ResetShotCount()
		local config = WeaponConfigLoader.GetConfig(tool.Name)
		local defaultMode = (config and config.FireModes and config.FireModes.DefaultMode) or "Auto"

		if tool:GetAttribute("FireMode") == nil then
			tool:SetAttribute("FireMode", defaultMode)
		end

		if config and config.BoltAction == true then
			if tool:GetAttribute("BoltNeedsCycle") == nil then
				tool:SetAttribute("BoltNeedsCycle", false)
			end
		else
			tool:SetAttribute("BoltNeedsCycle", false)
		end

		local equipSound = config and config.Sounds and config.Sounds.Equip
		if equipSound then
			playSFX(equipSound)
		end
	end)
end

local function onCharacterAdded(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			setupToolListeners(child)
		end
	end)

	local currentTool = character:FindFirstChildOfClass("Tool")
	if currentTool then
		setupToolListeners(currentTool)
	end
end

if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(onCharacterAdded)

-- == Input Listeners ==
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		canShootSemi = true
		tryFireWeapon()
	elseif input.KeyCode == Enum.KeyCode.R then
		local _, tool = getLocalFirePoint()
		if tool then
			local config = WeaponConfigLoader.GetConfig(tool.Name)
			local isReloading = tool:GetAttribute("IsReloading") or false

			if not isReloading then
				playReloadSequence(config)
				reloadWeaponEvent:FireServer(tool.Name)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isFiring = false
		canShootSemi = true
		RecoilController.ResetShotCount()
	end
end)

-- Receive visual effects from OTHER players
visualEvent.OnClientEvent:Connect(renderTracer)
