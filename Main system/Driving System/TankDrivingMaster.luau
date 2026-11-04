-- // TankDrivingMaster (Dynamic Shifting & Neutral-Turn Fix) //
-- Location: ServerScriptService
-- Optimized for: Centralized Global Raycast Filter Tracking & Zero-GC Allocations

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TankControlEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("TankControlEvent")

-- [[ CONFIGURATION DEFAULTS ]] --
local DEFAULTS = {
	MaxSpeed = 45,
	MaxReverseSpeed = 15,
	SteerSpeed = 1.2,
	MainHeight = 2.4,
	SprocketHeight = 1.4,
	IdlerHeight = 1.43,
	ServoResponsiveness = 20,
	Acceleration = 18
}

local SERVO_MAX_FORCE = 2500000
local SPHERE_RADIUS = 1.0
local SMOOTH_FACTOR = 0.25
local FIRST_GEAR_THRESHOLD = 12
local MAX_TORQUE_MULT = 4.5
local IDLE_PITCH = 0.85
local MAX_PITCH_ADD = 0.65
local BASE_VOLUME = 2

local tankInputs = {}
local tankCache = {}

-- [[  CENTRALIZED GLOBAL RAYCAST FILTERS ]] --
-- Shared table for raycast exclusions across all tanks; runs one scan to keep CPU usage low.
local GLOBAL_TANK_MODELS = {}
local GLOBAL_VISUAL_WHEELS = {}
local GLOBAL_VISUAL_WHEELS_SET = {}
local globalRaycastParams = RaycastParams.new()
globalRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function registerVisualWheelsRoot(inst)
	if inst.Name ~= "Visual Wheels" or GLOBAL_VISUAL_WHEELS_SET[inst] then return false end
	GLOBAL_VISUAL_WHEELS_SET[inst] = true
	table.insert(GLOBAL_VISUAL_WHEELS, inst)
	return true
end

local function unregisterVisualWheelsRoot(inst)
	if not GLOBAL_VISUAL_WHEELS_SET[inst] then return false end
	GLOBAL_VISUAL_WHEELS_SET[inst] = nil
	for i = #GLOBAL_VISUAL_WHEELS, 1, -1 do
		if GLOBAL_VISUAL_WHEELS[i] == inst then
			table.remove(GLOBAL_VISUAL_WHEELS, i)
			break
		end
	end
	return true
end

for _, inst in ipairs(workspace:GetDescendants()) do
	registerVisualWheelsRoot(inst)
end

local function updateGlobalRadarFilters()
	local excludeList = {game.Workspace.CurrentCamera}
	table.clear(GLOBAL_TANK_MODELS)
	
	local children = game.Workspace:GetChildren()
	for i = 1, #children do
		local object = children[i]
		if object:IsA("Model") then
			-- Identify tank models based on attributes or specific naming conventions
			if object:GetAttribute("IsTank") or object.Name:find("Panzer") or object.Name:find("Tiger") or object.Name:find("Tank") or object:FindFirstChild("Main Hull", true) then
				table.insert(excludeList, object)
				table.insert(GLOBAL_TANK_MODELS, object) -- Track for structural verification
			end
		end
	end

	-- Exclude visual wheel containers directly, including during the brief window
	-- before a newly spawned tank is picked up by the periodic tank scan.
	for i = 1, #GLOBAL_VISUAL_WHEELS do
		local visualWheels = GLOBAL_VISUAL_WHEELS[i]
		if visualWheels:IsDescendantOf(workspace) then
			table.insert(excludeList, visualWheels)
		end
	end

	globalRaycastParams.FilterDescendantsInstances = excludeList
end

workspace.DescendantAdded:Connect(function(inst)
	if registerVisualWheelsRoot(inst) then
		updateGlobalRadarFilters()
	end
end)

workspace.DescendantRemoving:Connect(function(inst)
	if unregisterVisualWheelsRoot(inst) then
		updateGlobalRadarFilters()
	end
end)

-- Update radar centrally every 2 seconds via a single server-wide thread
task.spawn(function()
	while true do
		updateGlobalRadarFilters()
		task.wait(2.0)
	end
end)

-- [[  STATIC PHYSICAL MATRIX CACHING (Zero-GC) ]] --
local CACHED_NORMAL_PHYS = PhysicalProperties.new(0.7, 0.5, 0.3, 1, 1)
local CACHED_HEAVY_PHYS = PhysicalProperties.new(100, 0.7, 0.3, 1, 1)
local CACHED_WHEEL_PHYS = PhysicalProperties.new(0.7, 0.7, 0.3, 1, 1) -- Cached wheel properties to prevent per-frame allocation
local VECTOR_UP = Vector3.new(0, 1, 0)

local function moveTowards(current, target, maxDelta)
	if math.abs(target - current) <= maxDelta then return target end
	return current + math.sign(target - current) * maxDelta
end

-- Process inbound player inputs and perform ownership validation
TankControlEvent.OnServerEvent:Connect(function(player, throttle, steer, aimPos)
	local char = player.Character
	local seat = char and char:FindFirstChildOfClass("Humanoid") and char.Humanoid.SeatPart

	if seat and (seat:IsA("Seat") or seat.Name == "DriverSeat") then
		local tankRoot = seat:FindFirstAncestorOfClass("Model")
		if tankRoot and (tankRoot:GetAttribute("IsTank") or tankRoot.Name:find("Tiger") or tankRoot.Name:find("Panther") or tankRoot.Name:find("Panzer")) then
			if not tankInputs[tankRoot] then
				tankInputs[tankRoot] = {t = 0, s = 0, aim = Vector3.new()}
			end
			if throttle ~= nil then tankInputs[tankRoot].t = math.clamp(throttle, -1, 1) end
			if steer ~= nil then tankInputs[tankRoot].s = math.clamp(steer, -1, 1) end
			if typeof(aimPos) == "Vector3" then tankInputs[tankRoot].aim = aimPos end
		end
	end
end)

local function setupTank(tank)
	local rootPart = tank.PrimaryPart or tank:FindFirstChild("Main Hull", true)
	if rootPart and rootPart.Anchored then
		while rootPart.Anchored do task.wait(0.1) end
	else
		task.wait(0.5)
	end

	local hull = tank:FindFirstChild("Main Hull", true) or tank:FindFirstChild("MainHull", true) or tank:FindFirstChild("Hull", true)
	local seat = tank:FindFirstChildOfClass("Seat") or tank:FindFirstChild("DriverSeat", true)
	local wheelConfig = tank:FindFirstChild("Physics Wheel", true) or tank:FindFirstChild("Physics Wheels", true) or tank

	if not hull or not seat then
		warn(" [Master Physics]: Missing Hull or Seat structure inside: " .. tank.Name)
		return
	end

	local driveLV = hull:FindFirstChild("DriveVelocity") or Instance.new("LinearVelocity", hull)
	driveLV.Name = "DriveVelocity"
	driveLV.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	driveLV.Attachment0 = hull:FindFirstChild("Attachment", true) or Instance.new("Attachment", hull)

	local steerAV = hull:FindFirstChild("SteerVelocity") or Instance.new("AngularVelocity", hull)
	steerAV.Name = "SteerVelocity"
	steerAV.Attachment0 = driveLV.Attachment0

	local engineSound = nil
	pcall(function()
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local sound = assets and assets.Sounds:FindFirstChild("engine_sound")
		if sound then
			engineSound = sound:Clone()
			engineSound.Parent = hull
			engineSound.Looped = true
			engineSound.Volume = BASE_VOLUME
			engineSound:Play()
		end
	end)

	local suspensionData = {}
	local descendants = tank:GetDescendants()
	for i = 1, #descendants do
		local part = descendants[i]
		if part:IsA("BasePart") then
			local name = part.Name:lower()
			if name:find("wheel") or name:find("inner") or name:find("sprocket") or name:find("idler") then
				local att0 = part:FindFirstChild("Attachment0")
				if att0 then
					local lv = att0:FindFirstChild("SuspensionServo") or Instance.new("LinearVelocity", att0)
					lv.Name = "SuspensionServo"
					lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
					lv.LineDirection = VECTOR_UP
					lv.MaxForce = SERVO_MAX_FORCE
					lv.Attachment0 = att0

					table.insert(suspensionData, {
						part = part,
						servo = lv,
						att = att0,
						lastV = 0,
						wType = name:find("sprocket") and "Sprocket" or (name:find("idler") and "Idler" or "Road")
					})
					part.CanCollide, part.CanQuery = false, false
				end
			end
		end
	end

	hull.CustomPhysicalProperties = CACHED_NORMAL_PHYS

	tankCache[tank] = {
		hull = hull, seat = seat, driveLV = driveLV, steerAV = steerAV,
		engineSound = engineSound, suspension = suspensionData,
		config = {
			MaxSpeed = wheelConfig:GetAttribute("MaxSpeed") or DEFAULTS.MaxSpeed,
			MaxRev = wheelConfig:GetAttribute("MaxReverseSpeed") or DEFAULTS.MaxReverseSpeed,
			SteerSpeed = wheelConfig:GetAttribute("SteerSpeed") or DEFAULTS.SteerSpeed,
			SteerAccel = wheelConfig:GetAttribute("SteerAcceleration") or 4.0,
			Accel = wheelConfig:GetAttribute("Acceleration") or DEFAULTS.Acceleration,
			MainH = wheelConfig:GetAttribute("MainHeight") or DEFAULTS.MainHeight,
			SprocketH = wheelConfig:GetAttribute("SprocketHeight") or DEFAULTS.SprocketHeight,
			IdlerH = wheelConfig:GetAttribute("IdlerHeight") or DEFAULTS.IdlerHeight,
			ServoResp = wheelConfig:GetAttribute("ServoResponsiveness") or DEFAULTS.ServoResponsiveness,
			BrakeDelta = wheelConfig:GetAttribute("BrakeDelta") or 14
		},
		state = {
			throttleVel = 0, steerVel = 0, lastDir = 0, shiftTimer = 0, isShifting = false,
			steerCacheVector = Vector3.new() -- Cache turning vector to prevent per-frame allocation
		}
	}

	-- Update radar immediately upon tank spawning
	updateGlobalRadarFilters()
end

-- [[ GLOBAL PHYSICS ENGINE LOOP ]] --
RunService.Heartbeat:Connect(function(dt)
	for tank, data in pairs(tankCache) do
		if not tank.Parent then tankCache[tank] = nil continue end

		local seat, hull, cfg, st = data.seat, data.hull, data.config, data.state
		local isNPC = tank:GetAttribute("IsNPC") == true
		local input
		if isNPC then
			input = {
				t = math.clamp(tank:GetAttribute("AIDriveThrottle") or 0, -1, 1),
				s = math.clamp(tank:GetAttribute("AIDriveSteer") or 0, -1, 1)
			}
		else
			input = tankInputs[tank] or {t = 0, s = 0}
		end

		-- =========================================================================
		-- [[ CRITICAL FIX: DYNAMIC NETWORK HANDOFF AUTHORITY ]]
		-- =========================================================================
		if seat.Occupant then
			local activeDriver = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
			if activeDriver then
				local rootPart = tank.PrimaryPart or hull
				if rootPart and rootPart:GetNetworkOwner() ~= activeDriver then
					pcall(function() rootPart:SetNetworkOwner(activeDriver) end)
				end

				data.driveLV.MaxForce = 0
				data.steerAV.MaxTorque = 0
				
				-- Iterate through array for high-performance processing in Luau
				local suspensions = data.suspension
				for i = 1, #suspensions do
					suspensions[i].servo.Enabled = false
				end

				if data.engineSound then
					local curSpeed = hull.AssemblyLinearVelocity.Magnitude
					local sRatio = math.clamp(curSpeed / cfg.MaxSpeed, 0, 1)
					data.engineSound.PlaybackSpeed = IDLE_PITCH + (sRatio * MAX_PITCH_ADD)
					data.engineSound.Volume = BASE_VOLUME + (sRatio * 1.5)
				end

				local currentDir = math.sign(input.t)
				st.lastDir = (currentDir ~= 0) and currentDir or 0
				continue
			end
		else
			-- [[ LOGIC EXECUTED ONLY WHEN THE TANK IS UNOCCUPIED ]] --
			if not isNPC then
				input.t, input.s = 0, 0
			end
			if not isNPC then
				st.throttleVel = moveTowards(st.throttleVel, 0, 200 * dt)
			end

			local rootPart = tank.PrimaryPart or hull
			if rootPart and rootPart:GetNetworkOwner() ~= nil then
				pcall(function() rootPart:SetNetworkOwner(nil) end)
			end

			local suspensions = data.suspension
			for i = 1, #suspensions do
				suspensions[i].servo.Enabled = true
			end
		end

		local curSpeed = hull.AssemblyLinearVelocity.Magnitude
		local inputDir = math.sign(input.t)

		local forwardVelocity = hull.CFrame.LookVector:Dot(hull.AssemblyLinearVelocity)
		local isSpunStationary = math.abs(forwardVelocity) < 1.0

		if inputDir ~= 0 and st.lastDir ~= 0 and inputDir ~= st.lastDir and not isSpunStationary then
			st.isShifting = true
		end

		if st.isShifting then
			if math.abs(forwardVelocity) < 0.4 then
				st.shiftTimer = st.shiftTimer + dt
				if st.shiftTimer >= 0.1 then st.isShifting = false; st.shiftTimer = 0; st.lastDir = inputDir end
			else
				st.shiftTimer = 0
			end
		else
			st.lastDir = (inputDir ~= 0) and inputDir or 0
		end

		local effectiveT = st.isShifting and 0 or input.t
		-- [ OPTIMIZATION]: math.sqrt() is more efficient than ^0.5 in Luau physics loops
		local torqueMult = math.clamp(MAX_TORQUE_MULT * (1 - math.sqrt(curSpeed / FIRST_GEAR_THRESHOLD)), 1, MAX_TORQUE_MULT)
		local goalVel = effectiveT * ((effectiveT >= 0) and cfg.MaxSpeed or cfg.MaxRev)

		local isActiveBrake = (math.sign(input.t) ~= math.sign(st.throttleVel) and input.t ~= 0) or (not seat.Occupant and not isNPC) or st.isShifting
		local brakeForce = cfg.BrakeDelta

		if isActiveBrake then
			local inverseSpeedRatio = 1.0 - math.clamp(curSpeed / cfg.MaxSpeed, 0, 1)
			brakeForce = cfg.BrakeDelta * (1.0 + (inverseSpeedRatio * inverseSpeedRatio) * 2.5) -- Manual multiplication is faster than exponentiation
		end

		st.throttleVel = moveTowards(st.throttleVel, goalVel, (isActiveBrake and brakeForce or (cfg.Accel * torqueMult)) * dt)

		data.driveLV.MaxForce = isActiveBrake and 6000000 or (2000000 * torqueMult)
		data.driveLV.VectorVelocity = hull.CFrame.LookVector * st.throttleVel

		local finalSteerSpeed = cfg.SteerSpeed
		if input.t ~= 0 and input.s ~= 0 then finalSteerSpeed = cfg.SteerSpeed * 0.55 end

		local speedRatio = math.clamp(curSpeed / cfg.MaxSpeed, 0, 1)
		local stableTurnFactor = math.clamp(1.0 - (speedRatio * 0.4), 0.6, 1.0)
		local targetSteerVel = -input.s * (finalSteerSpeed * stableTurnFactor)

		st.steerVel = moveTowards(st.steerVel, targetSteerVel, cfg.SteerAccel * dt)
		data.steerAV.MaxTorque = 30000000
		
		-- Update angular velocity directly on the existing vector; avoids creating new object instances
		data.steerAV.AngularVelocity = Vector3.new(0, st.steerVel, 0)

		if data.engineSound then
			local sRatio = math.clamp(curSpeed / cfg.MaxSpeed, 0, 1)
			data.engineSound.PlaybackSpeed = IDLE_PITCH + (sRatio * MAX_PITCH_ADD)
			data.engineSound.Volume = BASE_VOLUME + (sRatio * 1.5)
		end

		-- =========================================================================
		-- [[ SUSPENSION CALCULATIONS FOR IDLE/PARKED STATE ]]
		-- =========================================================================
		local hullCF = hull.CFrame
		local up = hullCF.UpVector
		local look = hullCF.LookVector

		local suspensions = data.suspension
		for i = 1, #suspensions do
			local sData = suspensions[i]
			sData.part.CustomPhysicalProperties = CACHED_WHEEL_PHYS -- Use constant cache; prevents RAM churn

			local tH = (sData.wType == "Sprocket" and cfg.SprocketH) or (sData.wType == "Idler" and cfg.IdlerH) or cfg.MainH
			local castDirection = -up

			if sData.wType == "Sprocket" then
				castDirection = (-up * 1.0) + (look * 0.35)
			elseif sData.wType == "Idler" then
				castDirection = (-up * 1.0) - (look * 0.35)
			end

			castDirection = castDirection.Unit
			-- Utilize centralized global RaycastParams to optimize cross-tank raycasting
			local cast = workspace:Spherecast(sData.att.WorldPosition + (up * 2), SPHERE_RADIUS, castDirection * (tH + 4), globalRaycastParams)

			if cast then
				local pVel = hull:GetVelocityAtPosition(sData.att.WorldPosition):Dot(-castDirection)
				local targetV = ((tH - (cast.Distance - 2)) * cfg.ServoResp) - (pVel * 1.4)
				sData.lastV = sData.lastV + (targetV - sData.lastV) * SMOOTH_FACTOR
				sData.servo.LineVelocity = sData.lastV
			else
				sData.servo.LineVelocity = -25
			end
		end

		hull:ApplyImpulse(Vector3.new(0, -((effectiveT > 0 and 20 or 60) * hull.AssemblyMass * dt), 0))
	end
end)

-- Initialize tank when added to workspace
local function onCheck(m)
	if m:IsA("Model") and m.Parent == workspace then
		if m:GetAttribute("IsTank") or m.Name:find("Tiger") or m.Name:find("Panther") or m.Name:find("Panzer") then setupTank(m) end
	end
end
workspace.ChildAdded:Connect(onCheck)

local wsChildren = workspace:GetChildren()
for i = 1, #wsChildren do onCheck(wsChildren[i]) end
