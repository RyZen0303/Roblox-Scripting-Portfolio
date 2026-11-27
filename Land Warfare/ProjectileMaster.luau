-- // ProjectileMaster //

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

-- Remote Events
local FireEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("FireEvent")
local RenderBulletEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RenderBullet")
local ProcessDamage = ServerStorage:WaitForChild("Events"):WaitForChild("ProcessDamage")

local reloadingTanks = {}

local function firing(weaponPart, tankModel, aimPoint, clientMuzzlePos, clientLookDirection)
	-- // Attribute Extraction //
	local baseDamage = weaponPart:GetAttribute("Damage") or 140
	local blastRadius = weaponPart:GetAttribute("BlastRadius") or 10
	local damageType = weaponPart:GetAttribute("DamageType") or "Heavy"
	local muzzleVelocity = weaponPart:GetAttribute("MuzzleVelocity") or 800
	local soundName = weaponPart:GetAttribute("SoundName") or "cannon_fire"
	local isExplosive = weaponPart:GetAttribute("IsExplosive")

	-- Locate Cannon part for structural calculations
	local cannon = weaponPart:FindFirstChild("Cannon", true) or weaponPart
	if not cannon then
		warn(" [DEBUG] Cannot find Cannon for: " .. weaponPart.Name)
		return
	end

	-- Muzzle visual reference point
	local muzzle = cannon:FindFirstChild("Muzzle") or cannon

	-- [[ CRITICAL LONG-RANGE DESYNC FIX ]] --
	-- Resolves latency offset between local simulation and authoritative server layer
	local projectileDirection = clientLookDirection or -cannon.CFrame.UpVector
	local finalSpawnPos = clientMuzzlePos or muzzle.Position

	-- Projectile Hitbox Setup
	local bullet = Instance.new("Part")
	bullet.Name = "Projectile_Hitbox"
	bullet.Size = Vector3.new(0.5, 0.5, 0.5)
	bullet.Transparency = 1
	bullet.CanCollide = false

	-- [[ TEAM IDENTIFICATION LOGIC ]] --
	-- Dynamically shifts buckets based on the tank's assigned team string attribute
	local tankTeam = tankModel:GetAttribute("Team") or "Germany"
	if tankTeam == "Germany" then
		bullet.CollisionGroup = "Projectiles_Germany"
	else
		bullet.CollisionGroup = "Projectiles_Britain"
	end

	bullet.Parent = workspace

	bullet.CFrame = CFrame.lookAt(finalSpawnPos, finalSpawnPos + projectileDirection)
	pcall(function() bullet:SetNetworkOwner(nil) end)

	-- Ballistics gravity compensation (Applies 80% counter-force for realistic terminal arc)
	local gravityReducer = Instance.new("VectorForce")
	gravityReducer.Force = Vector3.new(0, bullet:GetMass() * workspace.Gravity * 0.8, 0)
	gravityReducer.Attachment0 = Instance.new("Attachment", bullet)
	gravityReducer.Parent = bullet

	local finalVelocity = projectileDirection * muzzleVelocity
	bullet.AssemblyLinearVelocity = finalVelocity

	-- Visual replication trigger
	RenderBulletEvent:FireAllClients(muzzle, finalSpawnPos, finalVelocity, damageType)

	-- SFX Audio Playback
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fireSound = assets and assets.Sounds:FindFirstChild(soundName)
	if fireSound then
		local sfx = fireSound:Clone()
		sfx.Parent = cannon
		sfx.Volume = (damageType == "Light") and 2.5 or 5.0
		sfx.RollOffMaxDistance = 1000
		sfx:Play()
		Debris:AddItem(sfx, 3)
	end

	-- [[ DYNAMIC RAYCAST CONFIG ]] --
	local raycastParams = RaycastParams.new()
	raycastParams.CollisionGroup = bullet.CollisionGroup -- Apply the projectile's team collision rules.
	raycastParams.FilterDescendantsInstances = {tankModel, bullet} -- Ignore the firing tank and projectile.
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- High-Precision Frame-by-Frame Raycast Loop
	local lastPosition = bullet.Position
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not bullet or not bullet.Parent then
			if connection then connection:Disconnect() end
			return
		end

		local currentPosition = bullet.Position
		local displacement = currentPosition - lastPosition

		-- Engine native broadphase handles filtering base fields automatically based on team collision groups
		local raycastResult = workspace:Raycast(lastPosition, displacement * 1.1, raycastParams)

		if raycastResult then
			connection:Disconnect()
			local hitInstance = raycastResult.Instance

			-- Spawn purely visual explosion if attribute is active
			if isExplosive and blastRadius > 0 then
				local exp = Instance.new("Explosion")
				exp.BlastRadius = blastRadius
				exp.Position = raycastResult.Position
				exp.BlastPressure = 0
				exp.DestroyJointRadiusPercent = 0
				exp.Parent = workspace
			end

			-- [[ COMPREHENSIVE DAMAGE ROUTING SYSTEM ]] --
			local hitCharacter = hitInstance:FindFirstAncestorOfClass("Model")
			local targetHumanoid = hitCharacter and hitCharacter:FindFirstChildOfClass("Humanoid")

			-- Check 1: Direct hit on hostile Main Base Shield Attribute
			if hitInstance:GetAttribute("Health") ~= nil and string.find(hitInstance.Name, "Shield") then
				local currentShieldHP = hitInstance:GetAttribute("Health") or 0
				local structuralDamage = baseDamage * 2 -- Shields take double damage.
				hitInstance:SetAttribute("Health", math.max(currentShieldHP - structuralDamage, 0))
				print(" [SHIELD IMPACT]: Direct hit on " .. hitInstance.Name .. ". Reduced HP by " .. structuralDamage)

				-- Check 2: Direct hit on enemy Infantry personnel
			elseif targetHumanoid and not hitCharacter:GetAttribute("Health") then
				targetHumanoid:TakeDamage(baseDamage)
				print(" [HIT DIRECT]: Infantry hit. Dealt " .. baseDamage .. " damage to " .. hitCharacter.Name)

				-- Check 3: Standard surface/armored target (Route to external module calculator)
			else
				ProcessDamage:Fire(hitInstance, baseDamage, damageType)
			end

			bullet:Destroy()
		end
		lastPosition = currentPosition
	end)

	Debris:AddItem(bullet, 5)
end

-- Connection Listener Monitoring Vehicle Inputs
FireEvent.OnServerEvent:Connect(function(player, weaponName, aimPoint, clientMuzzlePos, clientLookDirection)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart

	if not (seat and seat.Name == "DriverSeat") then return end
	local tankModel = seat:FindFirstAncestorOfClass("Model")
	local weapon = tankModel:FindFirstChild(weaponName, true)

	if weapon and not reloadingTanks[weapon] then
		reloadingTanks[weapon] = true
		firing(weapon, tankModel, aimPoint, clientMuzzlePos, clientLookDirection)
		task.wait(weapon:GetAttribute("ReloadTime") or 0.1)
		reloadingTanks[weapon] = nil
	end
end)
