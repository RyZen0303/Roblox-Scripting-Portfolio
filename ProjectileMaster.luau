
-- Connected Discord-GitHub

--[[ Overall:
ProjectileMaster is a script located in ServerScriptService.
Its role is to handle all kind of ballistic projectile while
making itself optimized by using raycast system.

While the current version still focus on just ballistic projectile.
Its capability is beyond just handle single kind of weapon and
can be scale into something bigger using OOP such as inheritance
to make in accountable for missile, torpedoes and others rather
than ballistic projectile alone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

-- Connected remote and bindables events those stay inside ReplicatedStorage
local Events = ReplicatedStorage:WaitForChild("Events")
local FireEvent = Events:WaitForChild("FireEvent") :: RemoteEvent
local RenderBulletEvent = Events:WaitForChild("RenderBullet") :: RemoteEvent
local DebugRejectEvent = Events:FindFirstChild("DebugRejectEvent") or Instance.new("RemoteEvent", Events) -- Use to detect the cause for firing rejection as a debug (No longer implement on real game)
DebugRejectEvent.Name = "DebugRejectEvent"
local ProcessDamage = ServerStorage:WaitForChild("Events"):WaitForChild("ProcessDamage") :: BindableEvent -- Send damage to process to another script

local reloadingTanks: {[Instance]: boolean} = {} -- Empty the table to hold reloadTime

-- Helper function to dispatch debug messages to client
local function notifyReject(player: Player, reason: string): ()
	warn(" [FIRE REJECTED]: " .. player.Name .. " -> " .. reason)
	DebugRejectEvent:FireClient(player, " Firing Rejected: " .. reason)
end

-- [[ CORE BALLISTICS ENGINE ]]
local function firing(weaponPart: Instance, tankModel: Model, aimPoint: Vector3, clientMuzzlePos: Vector3?, clientLookDirection: Vector3?, attackerPlayer: Player?): ()
	local baseDamage = weaponPart:GetAttribute("Damage") or 140
	local blastRadius = weaponPart:GetAttribute("BlastRadius") or 10
	local damageType = "Heavy"
	local muzzleVelocity = weaponPart:GetAttribute("MuzzleVelocity") or 800
	local soundName = weaponPart:GetAttribute("SoundName") or "cannon_fire"
	local isExplosive = weaponPart:GetAttribute("IsExplosive") == true
	local gravityMultiplier = 0.9

	local cannon = weaponPart:FindFirstChild("Cannon", true) or weaponPart
	local muzzle = cannon:FindFirstChild("Muzzle") or cannon

	if not muzzle:IsA("BasePart") then
		if attackerPlayer then
			notifyReject(attackerPlayer, "Muzzle part missing or invalid on weapon model")
		end
		return
	end

	-- Use client muzzle position if provided, fallback to server muzzle position
	local spawnOrigin = clientMuzzlePos or muzzle.Position

	-- Preserve exact client look direction without modifying any axis
	local projectileDirection = (clientLookDirection and clientLookDirection.Magnitude > 0)
		and clientLookDirection.Unit
		or (aimPoint - spawnOrigin).Unit

	if projectileDirection.Magnitude == 0 then
		projectileDirection = muzzle.CFrame.LookVector
	end

	-- Prevent inverse vector calculation when muzzle overlaps target geometry
	if clientLookDirection and clientLookDirection.Magnitude > 0 then
		local rawVector = aimPoint - spawnOrigin
		if rawVector.Magnitude > 0 and clientLookDirection.Unit:Dot(rawVector.Unit) < 0 then -- This line check if overlap occurs
			projectileDirection = clientLookDirection.Unit
		end
	end

	-- If overlap true, push spawn origin forward along projectile direction to as a prevention when muzzle clipping
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
	pcall(function(): () bullet:SetNetworkOwner(nil) end)

	-- Reduce gravity force for better bullet fall
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

	-- Play localized audio (Unfixed yet, better located at BulletVisualManager)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local fireSound = sounds and sounds:FindFirstChild(soundName)
	if fireSound and fireSound:IsA("Sound") then
		local sfx = fireSound:Clone()
		sfx.Parent = cannon
		sfx.Volume = 5.0
		sfx.RollOffMaxDistance = 1000
		sfx:Play()
		Debris:AddItem(sfx, 3)
	end

	-- Procedural recoil animation override using motor6D on tank's model
	local recoilJoint = cannon:FindFirstChild("RecoilJoint")
	if recoilJoint and recoilJoint:IsA("Motor6D") then
		local originalC0 = recoilJoint.C0
		local infoRetract = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local infoReturn = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local targetC0 = originalC0 * CFrame.new(0, 0.65, 0)

		local tweenRetract = TweenService:Create(recoilJoint, infoRetract, {C0 = targetC0})
		tweenRetract:Play()
		tweenRetract.Completed:Connect(function(): ()
			if recoilJoint.Parent then
				TweenService:Create(recoilJoint, infoReturn, {C0 = originalC0}):Play()
			end
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
	connection = RunService.Heartbeat:Connect(function(dt: number): ()
		if not bullet.Parent then
			if connection then connection:Disconnect() end
			return
		end

		-- Restore velocity if physics stalls
		if bullet.AssemblyLinearVelocity.Magnitude < 10 then
			bullet.AssemblyLinearVelocity = finalVelocity
		end

		local currentPosition = bullet.Position

		-- Proximity shield dissolve check
		local totalTravelDistance = (currentPosition - finalSpawnPos).Magnitude
		if totalTravelDistance > 800 then
			local enemyShield = (tankTeam == "Germany") and britainShield or germanyShield
			if enemyShield and enemyShield:IsA("BasePart") and (currentPosition - enemyShield.Position).Magnitude <= 300 then
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
			local bush = hitInstance.Name == "Bush" and hitInstance or hitInstance:FindFirstAncestor("Bush")
			if bush then
				raycastParams:AddToFilter(bush)
				return
			end

			connection:Disconnect()
			RenderBulletEvent:FireAllClients("DestroyVisual", bulletId)

			if isExplosive and blastRadius > 0 then
				local exp = Instance.new("Explosion")
				exp.BlastRadius = blastRadius
				exp.Position = raycastResult.Position
				exp.BlastPressure = 0 --Set to 0 to avoid ruining terrain
				exp.Parent = workspace
			end

			local hitCharacter = hitInstance:FindFirstAncestorOfClass("Model")
			local targetHumanoid = hitCharacter and hitCharacter:FindFirstChildOfClass("Humanoid")
			if targetHumanoid and hitCharacter:GetAttribute("Health") == nil then
				targetHumanoid:TakeDamage(baseDamage)
			else
				ProcessDamage:Fire(hitInstance, baseDamage, damageType, attackerPlayer, weaponPart)
			end

			bullet:Destroy()
		end
	end)

	Debris:AddItem(bullet, 5)
end

-- Shared weapon reload routine
local function reloadWeapon(weapon: Instance, tankModel: Model, defaultReload: number): ()
	local maxReload = weapon:GetAttribute("ReloadTime") or defaultReload
	tankModel:SetAttribute("MaxReloadTime", maxReload)

	local timeLeft = maxReload
	while timeLeft > 0 do
		tankModel:SetAttribute("ReloadTime", timeLeft)
		timeLeft = timeLeft - RunService.Heartbeat:Wait()
	end

	tankModel:SetAttribute("ReloadTime", 0)
end

-- [[ INBOUND FIRE REQUEST LISTENER (PLAYERS) ]]
FireEvent.OnServerEvent:Connect(function(
	player: Player,
	weaponName: string,
	aimPoint: Vector3,
	clientMuzzlePos: Vector3?,
	clientLookDirection: Vector3?
): ()
	if typeof(weaponName) ~= "string" or typeof(aimPoint) ~= "Vector3" then
		notifyReject(player, "Invalid firing request arguments.")
		return
	end

	if clientMuzzlePos ~= nil and typeof(clientMuzzlePos) ~= "Vector3" then
		notifyReject(player, "Invalid muzzle position.")
		return
	end

	if clientLookDirection ~= nil and typeof(clientLookDirection) ~= "Vector3" then
		notifyReject(player, "Invalid projectile direction.")
		return
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")

	-- Primary Seat Validation
	local seat = humanoid and humanoid.SeatPart

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

	-- Check Authoritative Driver Attribute from DriverStateMaster, preventing anyone else who is not on the tank shoot
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
	local success, err = pcall(function(): ()
		firing(weapon, tankModel, aimPoint, clientMuzzlePos, clientLookDirection, player)
		reloadWeapon(weapon, tankModel, 3)
	end)

	if not success then
		warn(" [RELOAD ERROR]: " .. tostring(err))
	end

	reloadingTanks[weapon] = nil
end)

-- [[ NPC AUTOMATIC FIRING INTEGRATION ]]
task.spawn(function(): ()
	while true do
		task.wait(0.1)

		for _, tankModel in ipairs(workspace:GetChildren()) do
			if tankModel:IsA("Model") and tankModel:GetAttribute("IsNPC") == true and not tankModel:GetAttribute("IsDestroyed") then
				local shouldFire = tankModel:GetAttribute("AIFireCommand")
				local targetPos = tankModel:GetAttribute("AITargetPosition")

				if shouldFire and typeof(targetPos) == "Vector3" then
					local weapon = tankModel:FindFirstChild("Cannon", true) or tankModel:FindFirstChildWhichIsA("BasePart", true)

					if weapon and not reloadingTanks[weapon] then
						reloadingTanks[weapon] = true

						task.spawn(function(): ()
							local cannon = weapon:FindFirstChild("Cannon", true) or weapon
							local muzzle = cannon:FindFirstChild("Muzzle") or cannon

							if not muzzle:IsA("BasePart") then
								reloadingTanks[weapon] = nil
								return
							end

							local spawnPos = muzzle.Position
							local fireDir = targetPos - spawnPos
							if fireDir.Magnitude > 0 then
								fireDir = fireDir.Unit
							else
								fireDir = muzzle.CFrame.LookVector
							end

							local success, err = pcall(function(): ()
								firing(weapon, tankModel, targetPos, spawnPos, fireDir, nil)
								reloadWeapon(weapon, tankModel, 4)
							end)

							if not success then
								warn(" [RELOAD ERROR]: " .. tostring(err))
							end

							reloadingTanks[weapon] = nil
						end)
					end
				end
			end
		end
	end
end)
