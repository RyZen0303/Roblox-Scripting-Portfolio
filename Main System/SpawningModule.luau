-- // ReplicatedStorage/SpawningModule.lua //
local SpawningModule = {}

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local ActiveTankTracker = {}

-- Helper: Pre-clean non-essential collisions and set Network Owner
local function optimizeTankPhysics(tankModel, isNPC)
	for _, inst in ipairs(tankModel:GetDescendants()) do
		if inst:IsA("BasePart") then
			local lowerName = inst.Name:lower()
			local isAddon = inst:IsDescendantOf(tankModel:FindFirstChild("Add-on", true) or tankModel)
			local isVisualWheel = lowerName:find("_visual") or lowerName:find("track")

			if isVisualWheel or isAddon then
				inst.CanCollide = false
				inst.CanTouch = false
				inst.CanQuery = false
				inst.Massless = true
			end
		elseif inst:IsA("WeldConstraint") or inst:IsA("Weld") or inst:IsA("Motor6D") then
			local parentName = inst.Parent and inst.Parent.Name:lower() or ""
			if parentName:find("_visual") then
				inst:Destroy()
			end
		end
	end

	-- NPC Network Owner force to server
	if isNPC then
		local hull = tankModel:FindFirstChild("Main Hull", true) or tankModel.PrimaryPart
		if hull and hull:IsA("BasePart") then
			pcall(function()
				hull:SetNetworkOwner(nil)
			end)
		end
	end
end

-- Helper: Apply temporary anchor protection to prevent falling through floor or wheel physics tearing
local function applyAnchorProtection(tankModel, holdTime)
	holdTime = holdTime or 1.0
	local originalAnchorMap = {}

	for _, part in ipairs(tankModel:GetDescendants()) do
		if part:IsA("BasePart") then
			originalAnchorMap[part] = part.Anchored
			part.Anchored = true
		end
	end

	task.delay(holdTime, function()
		if not tankModel or not tankModel.Parent then return end
		for part, isAnchored in pairs(originalAnchorMap) do
			if part and part.Parent then
				part.Anchored = isAnchored
			end
		end
	end)
end

local function checkOrPurgeBlockingVehicles(spawnCFrame, spawnAreaSize, skipIfOccupied)
	local padPos = spawnCFrame.Position
	local allowedX = (spawnAreaSize.X / 2) + 5
	local allowedZ = (spawnAreaSize.Z / 2) + 5
	local maxVerticalHeight = 20

	for _, object in ipairs(Workspace:GetChildren()) do
		if object:IsA("Model") and not Players:GetPlayerFromCharacter(object) then
			local rootPart = object.PrimaryPart 
				or object:FindFirstChild("Main Hull", true) 
				or object:FindFirstChildWhichIsA("BasePart", true)

			if rootPart then
				local tankPos = rootPart.Position
				local diffX = math.abs(padPos.X - tankPos.X)
				local diffZ = math.abs(padPos.Z - tankPos.Z)
				local verticalDistance = tankPos.Y - padPos.Y

				if diffX <= allowedX and diffZ <= allowedZ and verticalDistance >= -3 and verticalDistance <= maxVerticalHeight then
					if object:GetAttribute("IsTank") == true 
						or object.Name:find("Panzer") 
						or object.Name:find("Tiger") 
						or object.Name:find("Tank") 
						or object:FindFirstChild("Main Hull", true) then

						if skipIfOccupied then
							print("⚠ [SpawningModule]: Space occupied by " .. object.Name .. ". Skipping spawn.")
							return true
						else
							print("💥 [SpawningModule Radar]: Vaporized blocking vehicle: " .. object.Name)
							object:Destroy()
						end
					end
				end
			end
		end
	end
	return false
end

local function setupTankUI(tankModel, isNPC)
	local overheadUI = tankModel:FindFirstChild("TankOverheadUI", true)
	if overheadUI then
		local countdownText = overheadUI:FindFirstChild("CountdownText", true)
		if countdownText then
			if isNPC then
				countdownText:Destroy()
			else
				countdownText.Visible = false
				if countdownText:IsA("TextLabel") then
					countdownText.TextTransparency = 1
				end
			end
		end
	end
end

function SpawningModule.SpawnTank(tankTemplate, baseCFrame, options)
	options = options or {}
	local isNPC = options.IsNPC or false
	local ownerPlayer = options.OwnerPlayer
	local teamName = options.TeamName
	local spawnAreaSize = options.SpawnAreaSize or Vector3.new(10, 5, 15)
	local trackerKey = options.TrackerKey
	local protectionTime = options.ProtectionTime or 40
	local skipIfOccupied = options.SkipIfOccupied or false
	local anchorHoldTime = options.AnchorHoldTime or 1.0
	local heightOffset = options.HeightOffset or 5 -- Default 5 studs above target surface

	-- A. TRACKER CHECK
	if trackerKey and ActiveTankTracker[trackerKey] then
		local trackerData = ActiveTankTracker[trackerKey]
		local timeElapsed = os.time() - trackerData.SpawnTime

		if timeElapsed < protectionTime then
			print("🚫 [SpawningModule]: Spawn aborted due to protection lockout window.")
			return nil, "Protection Active"
		end

		if trackerData.Tank and trackerData.Tank.Parent then
			trackerData.Tank:Destroy()
		end
	end

	-- B. BOUNDING-BOX CHECK (Checked at base CFrame before offset)
	local isOccupied = checkOrPurgeBlockingVehicles(baseCFrame, spawnAreaSize, skipIfOccupied)
	if isOccupied and skipIfOccupied then
		return nil, "Area Occupied"
	end

	-- C. CALCULATE TARGET CFRAME WITH VERTICAL OFFSET
	local finalSpawnCFrame = baseCFrame * CFrame.new(0, heightOffset, 0)

	-- D. CLONE & SET ATTRIBUTES
	local newTank = tankTemplate:Clone()

	newTank:SetAttribute("IsTank", true)
	newTank:SetAttribute("IsNPC", isNPC)
	newTank:SetAttribute("SpawnTime", os.time())

	if ownerPlayer then
		newTank:SetAttribute("Owner", ownerPlayer.Name)
	end
	if teamName then
		newTank:SetAttribute("Team", teamName)
		newTank:SetAttribute("Nation", teamName)
	end

	-- E. HEALTH CALCULATIONS
	local baseMaxHealth = newTank:GetAttribute("MaxHealth") or 750
	local buffPercent = options.BuffPercent or 0
	local newMax = math.ceil(baseMaxHealth * (1 + buffPercent))

	newTank:SetAttribute("MaxHealth", newMax)
	newTank:SetAttribute("Health", newMax)

	-- F. CLEAN UI & OPTIMIZE PHYSICS
	setupTankUI(newTank, isNPC)
	optimizeTankPhysics(newTank, isNPC)

	-- G. PIVOT, APPLY ANCHOR SAFETY & PARENT
	newTank:PivotTo(finalSpawnCFrame)
	applyAnchorProtection(newTank, anchorHoldTime)
	newTank.Parent = Workspace

	-- H. REGISTER TRACKER
	if trackerKey then
		ActiveTankTracker[trackerKey] = {
			Tank = newTank,
			SpawnTime = os.time()
		}
	end

	return newTank, ActiveTankTracker[trackerKey]
end

function SpawningModule.ClearTracker(trackerKey)
	if trackerKey and ActiveTankTracker[trackerKey] then
		ActiveTankTracker[trackerKey] = nil
	end
end

return SpawningModule
