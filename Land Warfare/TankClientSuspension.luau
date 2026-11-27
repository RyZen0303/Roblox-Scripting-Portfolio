-- ============================================================================
-- // TankClientSuspension (Client Vehicle Controller Engine) //
-- // Location: StarterPlayerScripts
-- ============================================================================

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

-- [[ Constants & Tuning Baselines ]] --
local SPHERE_RADIUS = 1.0
local SERVO_MAX_FORCE = 2500000

local FIRST_GEAR_THRESHOLD = 12
local MAX_TORQUE_MULT = 4.5
local DRIVE_DEFAULT_ACCEL = 18

local activeSuspensionData = {}
local currentTankModel = nil

-- [[ Raycast Parameters Setup ]] --
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true -- Penetrate terrain water surface to prevent floating

local waterCheckParams = RaycastParams.new()
waterCheckParams.FilterType = Enum.RaycastFilterType.Exclude
waterCheckParams.IgnoreWater = false -- Dedicated filter to detect terrain water surface level

-- [[ Reusable Static Matrix Caches ]] --
local STATIC_FRICTION = PhysicalProperties.new(0.7, 0.7, 0.3, 1, 1)

-- [[ Node Caches ]] --
local cachedHull = nil
local cachedWheelConfig = nil
local cachedDriveLV = nil
local cachedSteerAV = nil
local cachedTerrainAlign = nil
local cachedTerrainAttachment = nil
local smoothedTerrainUp = nil

-- [[ Client Tracking State ]] --
local driveState = {
	throttleVel = 0,
	steerVel = 0,
	lastDir = 0,
	shiftTimer = 0,
	isShifting = false
}

local isEngineDrowned = false

-- ============================================================================
-- // Utility Functions //
-- ============================================================================

local function moveTowards(current, target, maxDelta)
	if math.abs(target - current) <= maxDelta then 
		return target 
	end
	return current + math.sign(target - current) * maxDelta
end

local function cleanLocalSuspension()
	for i = 1, #activeSuspensionData do
		local sData = activeSuspensionData[i]
		if sData.servo and sData.servo.Parent then
			sData.servo.Name = "SuspensionServo"
		end
	end

	table.clear(activeSuspensionData)
	currentTankModel = nil
	cachedHull = nil
	cachedWheelConfig = nil
	cachedDriveLV = nil
	cachedSteerAV = nil
	if cachedTerrainAlign then
		cachedTerrainAlign:Destroy()
		cachedTerrainAlign = nil
	end
	if cachedTerrainAttachment then
		cachedTerrainAttachment:Destroy()
		cachedTerrainAttachment = nil
	end
	smoothedTerrainUp = nil

	driveState.throttleVel = 0
	driveState.steerVel = 0
	isEngineDrowned = false

	-- State-guarded attribute reset to prevent RemoteEvent/Network Exhaustion
	if player:GetAttribute("TankEngineDrowned") ~= nil then
		player:SetAttribute("TankEngineDrowned", nil)
	end
end

local function getIsolatedExcludeList(tankModel)
	local excludeList = {tankModel, player.Character}
	local allPlayers = Players:GetPlayers()

	for i = 1, #allPlayers do
		local p = allPlayers[i]
		if p ~= player and p.Character then
			table.insert(excludeList, p.Character)
		end
	end

	local taggedBushes = CollectionService:GetTagged("Bush")
	for i = 1, #taggedBushes do
		table.insert(excludeList, taggedBushes[i])
	end

	local environmentFolder = workspace:FindFirstChild("Environment")
	if environmentFolder then
		local children = environmentFolder:GetChildren()
		for i = 1, #children do
			local item = children[i]
			if item.Name == "Bush" then
				table.insert(excludeList, item)
			end
		end
	end

	return excludeList
end

local function hookLocalSuspension(tankModel)
	cleanLocalSuspension()

	currentTankModel = tankModel
	cachedHull = tankModel:FindFirstChild("Main Hull", true) or tankModel:FindFirstChild("MainHull", true) or tankModel:FindFirstChild("Hull", true)
	cachedWheelConfig = tankModel:FindFirstChild("Physics Wheel", true) or tankModel

	if cachedHull then
		cachedDriveLV = cachedHull:FindFirstChild("DriveVelocity")
		cachedSteerAV = cachedHull:FindFirstChild("SteerVelocity")
	end

	if cachedHull and cachedHull:IsA("BasePart") then
		cachedTerrainAttachment = Instance.new("Attachment")
		cachedTerrainAttachment.Name = "ClientTerrainAlignmentAttachment"
		cachedTerrainAttachment.Parent = cachedHull

		cachedTerrainAlign = Instance.new("AlignOrientation")
		cachedTerrainAlign.Name = "ClientTerrainAlignment"
		cachedTerrainAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
		cachedTerrainAlign.Attachment0 = cachedTerrainAttachment
		cachedTerrainAlign.RigidityEnabled = false
		cachedTerrainAlign.ReactionTorqueEnabled = false
		cachedTerrainAlign.Responsiveness = cachedWheelConfig:GetAttribute("TerrainAlignResponsiveness") or 7
		cachedTerrainAlign.MaxTorque = cachedWheelConfig:GetAttribute("TerrainAlignMaxTorque") or 5000000
		cachedTerrainAlign.MaxAngularVelocity = math.rad(90)
		cachedTerrainAlign.Enabled = true
		cachedTerrainAlign.Parent = cachedHull
	end

	local excludeList = getIsolatedExcludeList(tankModel)
	raycastParams.FilterDescendantsInstances = excludeList
	waterCheckParams.FilterDescendantsInstances = excludeList

	local descendants = tankModel:GetDescendants()
	for i = 1, #descendants do
		local part = descendants[i]
		if part:IsA("BasePart") then
			local name = part.Name:lower()
			if name:find("wheel") or name:find("inner") or name:find("sprocket") or name:find("idler") then
				part.CustomPhysicalProperties = STATIC_FRICTION
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false

				local att0 = part:FindFirstChild("Attachment0")
				if att0 then
					local localServo = att0:FindFirstChild("SuspensionServo") or att0:FindFirstChild("ClientSuspensionServo")
					if not localServo then
						localServo = Instance.new("LinearVelocity")
						localServo.Parent = att0
					end

					localServo.Name = "ClientSuspensionServo"
					localServo.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
					localServo.RelativeTo = Enum.ActuatorRelativeTo.World
					localServo.LineDirection = Vector3.new(0, 1, 0)
					localServo.MaxForce = SERVO_MAX_FORCE
					localServo.Attachment0 = att0
					localServo.Enabled = true

					table.insert(activeSuspensionData, {
						part = part,
						servo = localServo,
						att = att0,
						lastV = 0,
						wType = name:find("sprocket") and "Sprocket" or (name:find("idler") and "Idler" or "Road")
					})
				end
			end
		end
	end
end

-- ============================================================================
-- // REALTIME CLIENT DRIVING LOOP //
-- ============================================================================

RunService.Heartbeat:Connect(function(rawDt)
	local dt = math.min(rawDt, 0.05)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local tankRoot = nil

	if seat and (seat:IsA("Seat") or seat.Name == "DriverSeat") then
		local model = seat:FindFirstAncestorOfClass("Model")
		if model and (model:GetAttribute("IsTank") or model.Name:find("Tiger") or model.Name:find("Panther") or model.Name:find("Panzer")) then
			tankRoot = model
		end
	end

	if not tankRoot then
		if currentTankModel then 
			cleanLocalSuspension() 
		end
		return
	end

	if tankRoot ~= currentTankModel then
		hookLocalSuspension(tankRoot)
	end

	local hull = cachedHull
	local wheelConfig = cachedWheelConfig
	local driveLV = cachedDriveLV
	local steerAV = cachedSteerAV

	if not hull or not wheelConfig or not driveLV or not steerAV then 
		return 
	end

	local inputThrottle = player:GetAttribute("TankThrottle") or 0
	local inputSteer = player:GetAttribute("TankSteer") or 0
	local hullCF = hull.CFrame
	local up = hullCF.UpVector
	local look = hullCF.LookVector
	local curSpeed = hull.AssemblyLinearVelocity.Magnitude

	-- [[ POWERTRAIN ENGINE ]] --
	if isEngineDrowned then
		-- Permanent Engine Shutdown Logic when vehicle is flooded
		driveState.throttleVel = 0
		driveState.steerVel = 0
		driveLV.MaxForce = 0
		driveLV.VectorVelocity = Vector3.zero
		steerAV.MaxTorque = 0
		steerAV.AngularVelocity = Vector3.zero
	else
		local inputDir = math.sign(inputThrottle)
		if inputDir ~= 0 and driveState.lastDir ~= 0 and inputDir ~= driveState.lastDir then 
			driveState.isShifting = true 
		end

		if driveState.isShifting then
			-- Cancel a pending reversal if the driver returns to the current gear.
			if inputDir ~= 0 and inputDir == driveState.lastDir then
				driveState.isShifting = false
				driveState.shiftTimer = 0
			elseif curSpeed < 0.4 then
				driveState.shiftTimer = driveState.shiftTimer + dt
				if driveState.shiftTimer >= 0.1 then 
					driveState.isShifting = false
					driveState.shiftTimer = 0
					driveState.lastDir = inputDir 
				end
			else 
				driveState.shiftTimer = 0 
			end
		elseif inputDir ~= 0 then 
			driveState.lastDir = inputDir 
		end

		local cfgMaxSpeed = wheelConfig:GetAttribute("MaxSpeed") or 45
		local cfgMaxRev = wheelConfig:GetAttribute("MaxReverseSpeed") or 15
		local cfgSteerSpeed = wheelConfig:GetAttribute("SteerSpeed") or 1.2
		local cfgSteerAccel = wheelConfig:GetAttribute("SteerAcceleration") or 4.0
		local cfgAccel = wheelConfig:GetAttribute("Acceleration") or DRIVE_DEFAULT_ACCEL
		local cfgBrakeDelta = wheelConfig:GetAttribute("BrakeDelta") or 14

		local effectiveT = driveState.isShifting and 0 or inputThrottle
		local torqueMult = math.clamp(MAX_TORQUE_MULT * (1 - math.sqrt(curSpeed / FIRST_GEAR_THRESHOLD)), 1, MAX_TORQUE_MULT)
		local goalVel = effectiveT * ((effectiveT >= 0) and cfgMaxSpeed or cfgMaxRev)

		local isActiveBrake = (math.sign(inputThrottle) ~= math.sign(driveState.throttleVel) and inputThrottle ~= 0) or driveState.isShifting
		local brakeForce = cfgBrakeDelta

		if isActiveBrake then
			local inverseSpeedRatio = 1.0 - math.clamp(curSpeed / cfgMaxSpeed, 0, 1)
			brakeForce = cfgBrakeDelta * (1.0 + (inverseSpeedRatio * inverseSpeedRatio) * 2.5)
		end

		driveState.throttleVel = moveTowards(driveState.throttleVel, goalVel, (isActiveBrake and brakeForce or (cfgAccel * torqueMult)) * dt)
		local forwardVelocity = look:Dot(hull.AssemblyLinearVelocity)

		if math.abs(effectiveT) > 0.1 and not isActiveBrake then
			if goalVel > 0 then
				local maxForwardCap = math.max(12, forwardVelocity + 10)
				if driveState.throttleVel > maxForwardCap then 
					driveState.throttleVel = maxForwardCap 
				end
			elseif goalVel < 0 then
				local minReverseCap = math.min(-12, forwardVelocity - 10)
				if driveState.throttleVel < minReverseCap then 
					driveState.throttleVel = minReverseCap 
				end
			end
		end

		driveLV.MaxForce = isActiveBrake and 6000000 or (2000000 * torqueMult)
		driveLV.VectorVelocity = look * driveState.throttleVel

		local speedRatio = math.clamp(curSpeed / cfgMaxSpeed, 0, 1)
		local stableTurnFactor = math.clamp(1.0 - (speedRatio * 0.4), 0.6, 1.0)
		local targetSteerVel = -inputSteer * (cfgSteerSpeed * stableTurnFactor)

		driveState.steerVel = moveTowards(driveState.steerVel, targetSteerVel, cfgSteerAccel * dt)
		steerAV.MaxTorque = 30000000
		steerAV.AngularVelocity = Vector3.new(0, driveState.steerVel, 0)

		-- Dynamic downforce to keep vehicle grounded smoothly on terrain
		local impulseY = -((effectiveT > 0 and 15 or 45) * hull.AssemblyMass * dt)
		impulseY = math.clamp(impulseY, -hull.AssemblyMass * 2.5, 0)
		hull:ApplyImpulse(Vector3.new(0, impulseY, 0))
	end

	-- [[ CLIENT SUSPENSION ENGINE & WATER SUBMERGENCE MONITOR ]] --
	local cfgMainH = wheelConfig:GetAttribute("MainHeight") or 2.4
	local cfgSprocketH = wheelConfig:GetAttribute("SprocketHeight") or 1.4
	local cfgIdlerH = wheelConfig:GetAttribute("IdlerHeight") or 1.43
	local cfgServoResp = wheelConfig:GetAttribute("ServoResponsiveness") or 20
	local cfgSphereRadius = SPHERE_RADIUS

	local lookOffset = look * 0.35
	local sprocketDir = (-up + lookOffset).Unit
	local idlerDir = (-up - lookOffset).Unit
	local dynamicAlpha = math.clamp(dt * 12, 0.05, 1.0)

	-- Single raycast sample per frame to check for global terrain water surface elevation
	local waterHit = workspace:Raycast(hull.Position + Vector3.new(0, 15, 0), Vector3.new(0, -30, 0), waterCheckParams)
	local waterSurfaceY = (waterHit and waterHit.Material == Enum.Material.Water) and waterHit.Position.Y or nil

	-- PASS 1: Sample wheel contacts, water submergence, and compute ground distance averages
	local submergedWheelCount = 0
	local accumulatedNormal = Vector3.zero
	local validNormalCount = 0
	local castResults = {}

	for i = 1, #activeSuspensionData do
		local sData = activeSuspensionData[i]
		local wType = sData.wType
		local tH = (wType == "Road" and cfgMainH) or (wType == "Sprocket" and cfgSprocketH) or cfgIdlerH
		local castDirection = (wType == "Road" and -up) or (wType == "Sprocket" and sprocketDir) or idlerDir
		local worldPos = sData.att.WorldPosition

		-- Check if individual wheel position is under terrain water surface
		local isSubmerged = false
		if waterSurfaceY and worldPos.Y <= (waterSurfaceY + 0.3) then
			isSubmerged = true
			submergedWheelCount = submergedWheelCount + 1
		end

		local cast = workspace:Spherecast(worldPos + (up * 2), cfgSphereRadius, castDirection * (tH + 4), raycastParams)

		-- Disable suspension lift for submerged wheels or direct water hits
		if isSubmerged or (cast and cast.Material == Enum.Material.Water) then
			cast = nil
		end

		castResults[i] = cast

		if cast then
			-- Ignore near-vertical surfaces so walls/obstacles cannot roll the hull.
			if cast.Normal.Y > 0.25 then
				accumulatedNormal = accumulatedNormal + cast.Normal
				validNormalCount = validNormalCount + 1
			end
		end
	end

	-- Trigger permanent engine drowning if more than 50% of active wheels are submerged
	if not isEngineDrowned and (#activeSuspensionData > 0) and (submergedWheelCount > (#activeSuspensionData / 2)) then
		isEngineDrowned = true
		-- State-guarded attribute update (fires only ONCE to prevent RemoteEvent / Network Exhaustion)
		if player:GetAttribute("TankEngineDrowned") ~= true then
			player:SetAttribute("TankEngineDrowned", true)
		end
	end

	-- Align the hull to the averaged surface normal instead of distance-delta pitch bias.
	if validNormalCount > 0 and cachedTerrainAlign then
		local averageNormal = accumulatedNormal.Unit
		if smoothedTerrainUp then
			smoothedTerrainUp = smoothedTerrainUp:Lerp(averageNormal, dynamicAlpha).Unit
		else
			smoothedTerrainUp = averageNormal
		end

		-- Preserve the current heading while projecting it onto the target terrain plane.
		local heading = hull.CFrame.LookVector
		local projectedLook = heading - smoothedTerrainUp * heading:Dot(smoothedTerrainUp)
		if projectedLook.Magnitude < 0.001 then
			projectedLook = hull.CFrame.RightVector:Cross(smoothedTerrainUp)
		end

		if projectedLook.Magnitude > 0.001 then
			local targetCF = CFrame.lookAt(hull.Position, hull.Position + projectedLook.Unit, smoothedTerrainUp)
			cachedTerrainAlign.CFrame = targetCF
		end
	end

	-- PASS 2: Apply perpendicular suspension forces
	for i = 1, #activeSuspensionData do
		local sData = activeSuspensionData[i]
		local cast = castResults[i]
		local wType = sData.wType
		local tH = (wType == "Road" and cfgMainH) or (wType == "Sprocket" and cfgSprocketH) or cfgIdlerH
		local castDirection = (wType == "Road" and -up) or (wType == "Sprocket" and sprocketDir) or idlerDir

		-- Match the working server suspension formula while the driver owns the tank.
		if cast then
			local pVel = hull:GetVelocityAtPosition(sData.att.WorldPosition):Dot(-castDirection)
			local targetV = ((tH - (cast.Distance - 2)) * cfgServoResp) - (pVel * 1.4)
			sData.lastV = sData.lastV + (targetV - sData.lastV) * 0.25
			sData.servo.LineVelocity = sData.lastV
		else
			sData.servo.LineVelocity = -25
		end
	end
end)
