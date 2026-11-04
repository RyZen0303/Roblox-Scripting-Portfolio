-- // [SERVER] TurretMaster (Network Stability & Anti-Jitter Architecture) //
-- Location: ServerScriptService
-- Synchronizes turret mechanics without fighting default physics constraints

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UpdateEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("UpdateTurret")

-- [[ 1. RIGID COMPONENT OPTIMIZATION ]] --
local function optimizeTankPhysics(tankModel)
	local hull = tankModel:FindFirstChild("Main Hull", true) or tankModel:FindFirstChild("MainHull", true) or tankModel:FindFirstChild("Hull", true)
	local turretRoot = tankModel:FindFirstChild("TurretRoot", true)

	if not hull then return end

	-- Strip physics artifacts to prevent dynamic weight imbalances during replication
	for _, p in ipairs(tankModel:GetDescendants()) do
		if p:IsA("BasePart") then
			local name = p.Name:lower()

			-- Massless components eliminate dynamic torque friction during network lag spikes
			if name:find("turret") or name:find("gun") or name:find("barrel") or name:find("mantlet") then
				p.Massless = true
				p.CanCollide = false 
				p.CanTouch = false
				p.CanQuery = false

				-- Rigidly bind NoCollision constraints to suppress internal clipping explosions
				if turretRoot then
					local nc = Instance.new("NoCollisionConstraint")
					nc.Part0 = p
					nc.Part1 = hull
					nc.Parent = turretRoot
				end
			end
		end
	end
end

-- [[ 2. REMOTE RECEIVER & REPLICATION HUB ]] --
UpdateEvent.OnServerEvent:Connect(function(player, tankModel, traverseAngle, elevationAngle)
	if not (tankModel and player.Character and tankModel:IsDescendantOf(workspace)) then return end

	-- Driver Seat Logic Validation Guard
	local seat = tankModel:FindFirstChildOfClass("Seat") or tankModel:FindFirstChild("DriverSeat", true)
	if not (seat and seat.Occupant and seat.Occupant.Parent == player.Character) then 
		return 
	end

	-- Run optimization matrix once upon initial spawn validation
	if not tankModel:GetAttribute("PhysicsOptimized") then
		optimizeTankPhysics(tankModel)
		tankModel:SetAttribute("PhysicsOptimized", true)
	end

	-- [[ THE PHYSICS FIX ]]: Hand-off network ownership smoothly to the active driver
	local rootPart = tankModel.PrimaryPart or tankModel:FindFirstChildWhichIsA("BasePart", true)
	if rootPart then
		local success, currentOwner = pcall(function() return rootPart:GetNetworkOwner() end)
		if success and currentOwner ~= player then
			-- Assign exclusive ownership of the ENTIRE vehicle assembly directly to the client player
			-- This guarantees 0ms driving physics latency and totally eradicates the jitter/stutter glitch
			pcall(function() rootPart:SetNetworkOwner(player) end)
		end
	end

	-- Component Targeting Pipeline
	local turretRoot = tankModel:FindFirstChild("TurretRoot", true)
	local gunRoot = tankModel:FindFirstChild("GunRoot", true)

	if turretRoot and gunRoot then
		local traverseHinge = turretRoot:FindFirstChildOfClass("HingeConstraint")
		local elevationHinge = gunRoot:FindFirstChildOfClass("HingeConstraint")

		if traverseHinge and elevationHinge then
			-- Extract and bound physical limitation degrees using dynamic attributes
			local maxElev = gunRoot:GetAttribute("MaxElevation") or 20
			local maxDep = gunRoot:GetAttribute("MaxDepression") or -8
			local clampedElevation = math.clamp(elevationAngle, maxDep, maxElev)

			-- Set TargetAngles on Server as standard replication fallback for non-driving clients
			if traverseHinge.ActuatorType ~= Enum.ActuatorType.Servo then traverseHinge.ActuatorType = Enum.ActuatorType.Servo end
			if elevationHinge.ActuatorType ~= Enum.ActuatorType.Servo then elevationHinge.ActuatorType = Enum.ActuatorType.Servo end

			traverseHinge.TargetAngle = traverseAngle
			elevationHinge.TargetAngle = clampedElevation

			-- Replicate structural positioning data safely across global state attributes
			tankModel:SetAttribute("TargetTurretAngle", traverseAngle)
			tankModel:SetAttribute("TargetGunAngle", clampedElevation)
		end
	end
end)

-- [[ 3. HIERARCHY INITIALIZER ]] --
local function onCheck(m)
	if m:IsA("Model") and m.Parent == workspace then
		if m:GetAttribute("IsTank") or m.Name:find("Tiger") or m.Name:find("Panther") then
			task.defer(function()
				if not m.Parent then return end
				optimizeTankPhysics(m)
			end)
		end
	end
end

workspace.ChildAdded:Connect(onCheck)
for _, m in ipairs(workspace:GetChildren()) do onCheck(m) end
