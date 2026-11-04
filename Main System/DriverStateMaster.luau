-- // DriverStateMaster (Authoritative Pre-Entry Block + Ghost + Deferred Safe Exit + Camouflage + Destructible Trees) //
-- Location: ServerScriptService

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local TANK_GROUP = "Tanks"
local DRIVER_GROUP = "Drivers"
local DESPAWN_TIME = 40
local TREE_RESPAWN_TIME = 30

pcall(function()
	if not PhysicsService:IsCollisionGroupRegistered(TANK_GROUP) then PhysicsService:RegisterCollisionGroup(TANK_GROUP) end
	if not PhysicsService:IsCollisionGroupRegistered(DRIVER_GROUP) then PhysicsService:RegisterCollisionGroup(DRIVER_GROUP) end
	PhysicsService:CollisionGroupSetCollidable(TANK_GROUP, DRIVER_GROUP, false)
end)

local globalSoundAnchor = workspace:FindFirstChild("GlobalSoundAnchor") or Instance.new("Part")
if not globalSoundAnchor.Parent then
	globalSoundAnchor.Name = "GlobalSoundAnchor"
	globalSoundAnchor.Anchored = true
	globalSoundAnchor.CanCollide = false
	globalSoundAnchor.CanTouch = false
	globalSoundAnchor.CanQuery = false
	globalSoundAnchor.Transparency = 1
	globalSoundAnchor.Size = Vector3.new(1, 1, 1)
	globalSoundAnchor.Position = Vector3.new(0, -100, 0)
	globalSoundAnchor.Parent = workspace
end

local function getRootTankModel(seat)
	local current = seat
	while current and current ~= workspace do
		if current:IsA("Model") and (current:GetAttribute("IsTank") == true or current:GetAttribute("Owner") ~= nil or current:GetAttribute("IsNPC") == true) then
			return current
		end
		current = current.Parent
	end
	return seat:FindFirstAncestorOfClass("Model")
end

local function setPhysics(char, isDriving)
	if not char then return end
	local group = isDriving and DRIVER_GROUP or "Default"
	local props = isDriving and PhysicalProperties.new(0.01, 0.01, 0, 0, 0) or nil
	local inverseDriving = not isDriving

	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Massless = isDriving
			part.CollisionGroup = group
			part.CanCollide = inverseDriving
			part.CanTouch = inverseDriving
			part.CanQuery = inverseDriving
			part.CustomPhysicalProperties = props
		end
	end
end

local function handleTreeCollision(part)
	local treeModel = (part.Name == "TreePart" and part.Parent) or (part.Parent and part.Parent.Name == "Tree" and part.Parent)
	if not treeModel or not treeModel:IsA("Model") or treeModel:GetAttribute("IsFallen") then return end

	treeModel:SetAttribute("IsFallen", true)

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local collapseSound = assets and assets.Sounds:FindFirstChild("tree_collapse")

	if collapseSound and part and part.Parent then
		local sfx = collapseSound:Clone()
		sfx.Parent = part
		sfx.Volume = 4.5
		sfx.RollOffMaxDistance = 800
		sfx.TimePosition = 1
		sfx:Play()

		Debris:AddItem(sfx, 4)
	end

	local cachedStates = {}
	local descendants = treeModel:GetDescendants()

	for i = 1, #descendants do
		local descendant = descendants[i]
		if descendant:IsA("BasePart") then
			cachedStates[descendant] = {
				Transparency = descendant.Transparency,
				CanCollide = descendant.CanCollide,
				CanTouch = descendant.CanTouch,
				CanQuery = descendant.CanQuery
			}
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	task.delay(TREE_RESPAWN_TIME, function()
		if treeModel and treeModel.Parent then
			for basePart, state in pairs(cachedStates) do
				if basePart and basePart.Parent then
					basePart.Transparency = state.Transparency
					basePart.CanCollide = state.CanCollide
					basePart.CanTouch = state.CanTouch
					basePart.CanQuery = state.CanQuery
				end
			end
			treeModel:SetAttribute("IsFallen", nil)
		end
	end)
end

-- [[ MAIN TANK MONITOR ]] --
local function monitorDriver(seat)
	local model = getRootTankModel(seat)
	if not model then return end

	local isNPC = model:GetAttribute("IsNPC") == true

	-- Enable seat for NPC scripts to call seat:Sit(), disable auto-touch ONLY for player vehicles
	if isNPC then
		seat.Disabled = false
	else
		seat.Disabled = true
	end

	local foundHull = model:FindFirstChild("Main Hull", true) or model:FindFirstChild("MainHull", true) or model:FindFirstChild("Hull", true)
	local mainHull = (foundHull and foundHull:IsA("Model")) and foundHull.PrimaryPart or foundHull
	local lastCharacter = nil
	local despawnThread = nil

	local connections = {}
	local activeBushes = {}

	local function disconnectAll()
		for i = 1, #connections do
			local conn = connections[i]
			if conn then conn:Disconnect() end
		end
		table.clear(connections)
		table.clear(activeBushes)
		if despawnThread then task.cancel(despawnThread) end
	end

	table.insert(connections, model.Destroying:Connect(disconnectAll))

	local descendants = model:GetDescendants()
	for i = 1, #descendants do
		local p = descendants[i]
		if p:IsA("BasePart") and not (p:IsA("Seat") or p:IsA("VehicleSeat")) then
			p.CollisionGroup = TANK_GROUP
		end
	end

	-- [[ PROXIMITY PROMPT FOR PLAYERS ONLY ]] --
	local prompt = nil
	if not isNPC then
		local promptParent = mainHull or seat
		prompt = promptParent:FindFirstChild("EntryPrompt") or Instance.new("ProximityPrompt")
		prompt.Name = "EntryPrompt"
		prompt.ActionText = "Drive " .. model.Name
		prompt.ObjectText = "Vehicle"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 25
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptParent

		-- Spawn Guard: Disable the prompt for the first 4 seconds
		prompt.Enabled = false

		task.delay(3, function()
			-- After 3 seconds, if the seat is still empty, enable the prompt for normal use
			if prompt and prompt.Parent and not seat.Occupant and not model:GetAttribute("IsDestroyed") then
				prompt.Enabled = true
			end
		end)

		table.insert(connections, prompt.Triggered:Connect(function(player)
			if model:GetAttribute("IsDestroyed") then return end
			local tankOwner = model:GetAttribute("Owner")

			if tankOwner and player.Name ~= tankOwner then
				warn(string.format("[Anti-Theft Block]: Prevented %s from sitting.", player.Name))
				local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
				local alertEvent = eventsFolder and eventsFolder:FindFirstChild("ServerAlertNotification")
				if alertEvent then
					alertEvent:FireClient(player, "This vehicle belongs to " .. tankOwner .. "!")
				end
				return
			end

			if not seat.Occupant and player.Character then
				local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then seat:Sit(humanoid) end
			end
		end))
	end

	-- [[ TIMER LOGIC ]] --
	local function startTimer()
		-- Re-check IsNPC attribute dynamically
		local currentIsNPC = model:GetAttribute("IsNPC") == true or isNPC == true

		if currentIsNPC then
			-- Scope-Lock Fix: Permanently destroy CountdownText so the timer loop can NEVER activate for NPCs
			local label = model:FindFirstChild("CountdownText", true)
			if label then
				label:Destroy()
			end
			return
		end -- NPCs manage their own lifespan

		if despawnThread then task.cancel(despawnThread) end
		despawnThread = task.spawn(function()
			local timer = DESPAWN_TIME
			while timer > 0 do
				if model:GetAttribute("IsDestroyed") then return end
				local label = model:FindFirstChild("CountdownText", true)
				if label and label:IsA("TextLabel") then
					label.Visible = true
					label.Text = "Despawning in: " .. timer
				end
				task.wait(1)
				timer -= 1
				if seat.Occupant then
					if label then label.Visible = false end
					return
				end
			end
			if not seat.Occupant and not model:GetAttribute("IsDestroyed") then model:Destroy() end
		end)
	end

	-- [[ BUSH CAMOUFLAGE LOGIC ]] --
	local function setOverheadState(isEnabled)
		local overheadUI = model:FindFirstChild("TankOverheadUI", true)
		if overheadUI and overheadUI:IsA("BillboardGui") then overheadUI.Enabled = isEnabled end
	end

	local function getBushInstance(part)
		if part.Name == "Bush" then return part end
		if part.Parent and part.Parent:IsA("Model") and part.Parent.Name == "Bush" then return part.Parent end
		return nil
	end

	if mainHull then
		table.insert(connections, mainHull.Touched:Connect(function(otherPart)
			local bush = getBushInstance(otherPart)
			if bush then
				activeBushes[bush] = true
				setOverheadState(false)
			end
			handleTreeCollision(otherPart)
		end))

		table.insert(connections, mainHull.TouchEnded:Connect(function(otherPart)
			local bush = getBushInstance(otherPart)
			if bush then
				activeBushes[bush] = nil
				if next(activeBushes) == nil then
					setOverheadState(true)
				end
			end
		end))
	end

	table.insert(connections, model:GetAttributeChangedSignal("Health"):Connect(function()
		local currentHealth = model:GetAttribute("Health") or 100
		local maxHealth = model:GetAttribute("MaxHealth") or 100
		if currentHealth < maxHealth and not model:GetAttribute("IsDestroyed") then
			table.clear(activeBushes)
			setOverheadState(true)
		end
	end))

	-- [[ SEAT OCCUPANT LISTENER TREE ]] --
	table.insert(connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if model:GetAttribute("IsDestroyed") then
			if prompt then prompt.Enabled = false end
			if despawnThread then task.cancel(despawnThread) end
			return
		end

		local humanoid = seat.Occupant
		if prompt then prompt.Enabled = (humanoid == nil) end

		if humanoid then
			local char = humanoid.Parent
			local player = Players:GetPlayerFromCharacter(char)

			-- Player-only Anti-Theft Check (Skip for NPCs)
			if player and not isNPC then
				local tankOwner = model:GetAttribute("Owner")
				if tankOwner and player.Name ~= tankOwner then
					seat:Sit(nil)
					task.defer(function()
						local hrp = char:FindFirstChild("HumanoidRootPart")
						if hrp then hrp.CFrame = hrp.CFrame * CFrame.new(0, 5, 5) end
					end)
					return
				end
			end

			-- Authoritative driving state binding
			if player then
				player:SetAttribute("IsDrivingTank", true)
				player:SetAttribute("CurrentTank", model.Name)
				model:SetAttribute("CurrentDriver", player.Name)
			end

			if despawnThread then task.cancel(despawnThread); despawnThread = nil end
			local label = model:FindFirstChild("CountdownText", true)
			if label then label.Visible = false end

			lastCharacter = char
			task.wait(0.1)
			setPhysics(char, true)

			if player and mainHull then pcall(function() mainHull:SetNetworkOwner(nil) end) end
		else
			startTimer()
			if lastCharacter then
				local char = lastCharacter
				lastCharacter = nil
				setPhysics(char, false)

				local player = Players:GetPlayerFromCharacter(char)
				if player then
					player:SetAttribute("IsDrivingTank", nil)
					player:SetAttribute("CurrentTank", nil)
				end
				model:SetAttribute("CurrentDriver", nil)

				task.defer(function()
					if char and char.Parent and char:FindFirstChild("HumanoidRootPart") then
						local hrp = char.HumanoidRootPart
						hrp.CFrame = hrp.CFrame * CFrame.new(-10, 5, 0)
					end
				end)
			end
		end
	end))

	if not seat.Occupant then startTimer() end
end

local function setup(desc)
	if desc:IsA("VehicleSeat") or (desc:IsA("Seat") and desc.Name == "DriverSeat") then
		monitorDriver(desc)
	end
end

workspace.DescendantAdded:Connect(setup)
for _, desc in pairs(workspace:GetDescendants()) do setup(desc) end

-- [[ LISTEN TO WAVE SPAWN EVENT ]] --
local eventsFolder = ReplicatedStorage:WaitForChild("Events", 5)
local waveEvent = eventsFolder and eventsFolder:WaitForChild("NPCsSpawnedWave", 5)
if waveEvent then
	waveEvent.Event:Connect(function(spawnedTanks)
		for _, tank in ipairs(spawnedTanks) do
			for _, desc in ipairs(tank:GetDescendants()) do
				setup(desc)
			end
		end
	end)
end
