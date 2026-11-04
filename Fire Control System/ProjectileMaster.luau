-- // ProjectileMaster (Server-Side Weapon Controller - NPC Integrated) //
-- Location: ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

-- Remote Events & Bindables
local Events = ReplicatedStorage:WaitForChild("Events")
local FireEvent = Events:WaitForChild("FireEvent")
local RenderBulletEvent = Events:WaitForChild("RenderBullet")
local DebugRejectEvent = Events:FindFirstChild("DebugRejectEvent") or Instance.new("RemoteEvent", Events)
DebugRejectEvent.Name = "DebugRejectEvent"

local ProcessDamage = ServerStorage:WaitForChild("Events"):WaitForChild("ProcessDamage")

local reloadingTanks = {}

-- Helper function to dispatch debug messages to client
local function notifyReject(player, reason)
	warn(" [FIRE REJECTED]: " .. player.Name .. " -> " .. reason)
	DebugRejectEvent:FireClient(player, " Firing Rejected: " .. reason)
end

-- [[ CORE BALLISTICS ENGINE ]]
local function firing(weaponPart, tankModel, aimPoint, clientMuzzlePos, clientLookDirection, attackerPlayer)
	local baseDamage = weaponPart:GetAttribute("Damage") or 140
	local blastRadius = weaponPart:GetAttribute("BlastRadius") or 10
	local damageType = "Heavy"
	local muzzleVelocity = weaponPart:GetAttribute("MuzzleVelocity") or 800
	local soundName = weaponPart:GetAttribute("SoundName") or "cannon_fire"
	local isExplosive = weaponPart:GetAttribute("IsExplosive")
	local gravityMultiplier = 0.9

	local cannon = weaponPart:FindFirstChild("Cannon", true) or weaponPart
	if not cannon then
		if attackerPlayer then
			notifyReject(attackerPlayer, "Cannon part missing on weapon model")
		end
		return
	end

	local muzzle = cannon:FindFirstChild("Muzzle") or cannon

	-- Use client muzzle position if provided, fallback to server muzzle position
	local spawnOrigin = clientMuzzlePos or muzzle.Position

	-- Preserve exact client look direction without modifying any axis
	local projectileDirection = (clientLookDirection and clientLookDirection.Magnitude > 0)
		and clientLookDirection.Unit
		or (aimPoint - spawnOrigin).Unit

	-- Prevent inverse vector calculation when muzzle overlaps target geometry
	if clientLookDirection and clientLookDirection.Magnitude > 0 then
		local rawVector = (aimPoint - spawnOrigin)
		if rawVector.Magnitude > 0 and clientLookDirection.Unit:Dot(rawVector.Unit) < 0 then
			projectileDirection = clientLookDirection.Unit
		end
	end

	-- Push spawn origin forward along projectile direction to prevent self-intersection when clipping
	local safetyParams = RaycastParams.new()
	safetyParams.FilterType = Enum.RaycastFilterType.Exclude
	safetyParams.FilterDescendantsInstances = {tankModel}

	local finalSpawnPos = spawnOrigin + (projectileDirection * 3)
	local overlapCheck = workspace:Raycast(spawnOrigin, projectileDirection * 5, safetyParams)
	if overlapCheck then
		finalSpawnPos = overlapCheck.Position + (projectileDirection * 1.5)
	end

	local bulletId = HttpService:GenerateGUID(false)

	-- Instantiate physical projectile server hitbox
	local bullet = Instance.new("Part")
	bullet.Name = "Projectile_Hitbox"
	bullet.Size = Vector3.new(0.5, 0.5, 0.5)
	bullet.Transparency = 1
	bullet.CanCollide = false

	local tankTeam = tankModel:GetAttribute("Team") or "Germany"
	bullet.CollisionGroup = (tankTeam == "Germany") and "Projectiles_Germany" or "Projectiles_Britain"

	bullet.Parent = workspace
	bullet.CFrame = CFrame.lookAt(finalSpawnPos, finalSpawnPos + projectileDirection)
	pcall(function() bullet:SetNetworkOwner(nil) end)

	-- Counter-gravity force for realistic drop curve (Strictly relative to World coordinates)
	local gravityReducer = Instance.new("VectorForce")
	gravityReducer.RelativeTo = Enum.ActuatorRelativeTo.World
	gravityReducer.Force = Vector3.new(0, bullet:GetMass() * workspace.Gravity * gravityMultiplier, 0)

	local attachment = Instance.new("Attachment")
	attachment.Parent = bullet
	gravityReducer.Attachment0 = attachment
	gravityReducer.Parent = bullet

	local finalVelocity = projectileDirection * muzzleVelocity
	bullet.AssemblyLinearVelocity = finalVelocity

	-- Replicate visual tracer data to all clients
	RenderBulletEvent:FireAllClients("Spawn", bulletId, muzzle, finalSpawnPos, finalVelocity, damageType, gravityMultiplier)

	-- Play localized audio
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fireSound = assets and assets.Sounds:FindFirstChild(soundName)
	if fireSound then
		local sfx = fireSound:Clone()
		sfx.Parent = cannon
		sfx.Volume = 5.0
		sfx.RollOffMaxDistance = 1000
		sfx:Play()
		Debris:AddItem(sfx, 3)
	end

	-- Procedural recoil animation override
	local recoilJoint = cannon:FindFirstChild("RecoilJoint")
	if recoilJoint then
		local originalC0 = recoilJoint.C0
		local infoRetract = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local infoReturn = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local targetC0 = originalC0 * CFrame.new(0, 0.65, 0)

		local tweenRetract = TweenService:Create(recoilJoint, infoRetract, {C0 = targetC0})
		tweenRetract:Play()
		tweenRetract.Completed:Connect(function()
			TweenService:Create(recoilJoint, infoReturn, {C0 = originalC0}):Play()
		end)
	end

	-- Raycast filtering configuration
	local raycastParams = RaycastParams.new()
	raycastParams.CollisionGroup = bullet.CollisionGroup
	raycastParams.FilterDescendantsInstances = {tankModel, bullet}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local germanyShield = workspace:FindFirstChild("MainBaseShield_Germany", true)
	local britainShield = workspace:FindFirstChild("MainBaseShield_Britain", true)

	local lastPosition = bullet.Position
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not bullet or not bullet.Parent then
			if connection then connection:Disconnect() end
			return
		end

		-- Wake up physics if stalled by network ownership handoff
		if bullet.AssemblyLinearVelocity.Magnitude < 10 then
			bullet:WakeUp()
			bullet.AssemblyLinearVelocity = finalVelocity
		end

		local currentPosition = bullet.Position

		-- Proximity shield dissolve check
		local totalTravelDistance = (currentPosition - finalSpawnPos).Magnitude
		if totalTravelDistance > 800 then
			local enemyShield = (tankTeam == "Germany") and britainShield or germanyShield
			if enemyShield and (currentPosition - enemyShield.Position).Magnitude <= 300 then
				connection:Disconnect()
				RenderBulletEvent:FireAllClients("DestroyVisual", bulletId)

				local airBurst = Instance.new("Explosion")
				airBurst.BlastRadius = 2
				airBurst.Position = currentPosition
				airBurst.Parent = workspace
				bullet:Destroy()
				return
			end
		end

		local displacement = currentPosition - lastPosition

		-- Mathematical displacement fallback during physics hiccups
		if displacement.Magnitude < 0.1 then
			displacement = finalVelocity * dt
			lastPosition = lastPosition + displacement
		else
			lastPosition = currentPosition
		end

		local raycastResult = workspace:Raycast(lastPosition - displacement, displacement * 1.1, raycastParams)

		if raycastResult then
			local hitInstance = raycastResult.Instance

			-- Dynamic bush penetration filter
			if hitInstance.Name == "Bush" or (hitInstance.Parent and hitInstance.Parent.Name == "Bush") then
				raycastParams:AddToFilter(hitInstance)
				return
			end

			connection:Disconnect()
			RenderBulletEvent:FireAllClients("DestroyVisual", bulletId)

			if isExplosive and blastRadius > 0 then
				local exp = Instance.new("Explosion")
				exp.BlastRadius = blastRadius
				exp.Position = raycastResult.Position
				exp.BlastPressure = 0
				exp.Parent = workspace
			end

			local hitCharacter = hitInstance:FindFirstAncestorOfClass("Model")
			local targetHumanoid = hitCharacter and hitCharacter:FindFirstChildOfClass("Humanoid")
			if targetHumanoid and not hitCharacter:GetAttribute("Health") then
				targetHumanoid:TakeDamage(baseDamage)
			else
				ProcessDamage:Fire(hitInstance, baseDamage, damageType, attackerPlayer, weaponPart)
			end

			bullet:Destroy()
		end
	end)

	Debris:AddItem(bullet, 5)
end

-- [[ INBOUND FIRE REQUEST LISTENER (PLAYERS) ]]
FireEvent.OnServerEvent:Connect(function(player, weaponName, aimPoint, clientMuzzlePos, clientLookDirection)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")

	-- Primary Seat Validation
	local seat = (humanoid and humanoid.SeatPart)

	-- Secondary Fallback: Weld inspection for network desync resilience
	if not seat and char and char:FindFirstChild("HumanoidRootPart") then
		for _, child in ipairs(char.HumanoidRootPart:GetChildren()) do
			if child:IsA("Weld") or child:IsA("WeldConstraint") then
				if child.Part0 and (child.Part0.Name == "DriverSeat" or child.Part0:IsA("VehicleSeat")) then
					seat = child.Part0
					break
				elseif child.Part1 and (child.Part1.Name == "DriverSeat" or child.Part1:IsA("VehicleSeat")) then
					seat = child.Part1
					break
				end
			end
		end
	end

	-- Tertiary Fallback: Check Authoritative Driver Attribute from DriverStateMaster
	local isAuthoritativeDriver = player:GetAttribute("IsDrivingTank") == true

	if not (seat and (seat.Name == "DriverSeat" or seat:IsA("VehicleSeat"))) and not isAuthoritativeDriver then
		notifyReject(player, "Server failed to verify DriverSeat occupation.")
		return
	end

	-- Find tank model via seat or fallback to current tank attribute
	local tankModel = seat and seat:FindFirstAncestorOfClass("Model")
	if not tankModel then
		local tankName = player:GetAttribute("CurrentTank")
		for _, model in ipairs(workspace:GetChildren()) do
			if model:IsA("Model") and model.Name == tankName and model:GetAttribute("CurrentDriver") == player.Name then
				tankModel = model
				break
			end
		end
	end

	if not tankModel then
		notifyReject(player, "Server failed to resolve vehicle model.")
		return
	end

	local weapon = tankModel:FindFirstChild("Cannon", true) or tankModel:FindFirstChild(weaponName, true)

	if not weapon then
		notifyReject(player, "Weapon part '" .. tostring(weaponName) .. "' not found on vehicle.")
		return
	end

	if reloadingTanks[weapon] then
		notifyReject(player, "Weapon is currently reloading.")
		return
	end

	-- Execute fire routine within protected call to guarantee state cleanup
	reloadingTanks[weapon] = true

	local success, err = pcall(function()
		firing(weapon, tankModel, aimPoint, clientMuzzlePos, clientLookDirection, player)

		local maxReload = weapon:GetAttribute("ReloadTime") or 3
		tankModel:SetAttribute("MaxReloadTime", maxReload)

		local timeLeft = maxReload
		while timeLeft > 0 do
			tankModel:SetAttribute("ReloadTime", timeLeft)
			timeLeft = timeLeft - RunService.Heartbeat:Wait()
		end

		tankModel:SetAttribute("ReloadTime", 0)
	end)

	if not success then
		warn(" [RELOAD ERROR]: " .. tostring(err))
	end

	reloadingTanks[weapon] = nil -- Always reset locking state
end)

-- [[ NPC AUTOMATIC FIRING INTEGRATION ]]
task.spawn(function()
	while true do
		task.wait(0.1)

		for _, tankModel in ipairs(workspace:GetChildren()) do
			if tankModel:IsA("Model") and tankModel:GetAttribute("IsNPC") == true and not tankModel:GetAttribute("IsDestroyed") then
				local shouldFire = tankModel:GetAttribute("AIFireCommand")
				local targetPos = tankModel:GetAttribute("AITargetPosition")

				if shouldFire and targetPos then
					local weapon = tankModel:FindFirstChild("Cannon", true) or tankModel:FindFirstChildOfClass("BasePart")

					if weapon and not reloadingTanks[weapon] then
						reloadingTanks[weapon] = true

						task.spawn(function()
							local cannon = weapon:FindFirstChild("Cannon", true) or weapon
							local muzzle = cannon:FindFirstChild("Muzzle") or cannon
							local spawnPos = muzzle.Position
							local fireDir = (targetPos - spawnPos).Unit

							firing(weapon, tankModel, targetPos, spawnPos, fireDir, nil)

							-- NPC Reload logic
							local maxReload = weapon:GetAttribute("ReloadTime") or 4
							tankModel:SetAttribute("MaxReloadTime", maxReload)

							local timeLeft = maxReload
							while timeLeft > 0 do
								tankModel:SetAttribute("ReloadTime", timeLeft)
								timeLeft = timeLeft - RunService.Heartbeat:Wait()
							end

							tankModel:SetAttribute("ReloadTime", 0)
							reloadingTanks[weapon] = nil
						end)
					end
				end
			end
		end
	end
end)
