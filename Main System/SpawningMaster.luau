-- // ServerScriptService/SpawningMaster.lua //

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- [[ MODULE & INFRASTRUCTURE ROUTING ]] --
local GameLogic = require(ReplicatedStorage:WaitForChild("GameLogic"))
local SpawningModule = require(ReplicatedStorage:WaitForChild("SpawningModule"))

local TankFolder = ReplicatedStorage:WaitForChild("Tanks")
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local SpawnFunction = eventsFolder:WaitForChild("RequestTankSpawnFunction")

local PROTECTION_TIME = 40 

-- // PRIVATE UTILITY: TELEPORT TO TEAM SPECIFIC LOBBY //
local function teleportToLobby(player, character)
	if not player or not character then return end

	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoidRootPart then return end

	local teamName = player.Team and player.Team.Name
	local targetLobbyName = ""

	if teamName == "Germany" then
		targetLobbyName = "GermanySpawn"
	elseif teamName == "Britain" then
		targetLobbyName = "BritainSpawn"
	else
		targetLobbyName = "GermanySpawn" 
	end

	local lobbyPart = Workspace:FindFirstChild(targetLobbyName, true)

	if lobbyPart and humanoidRootPart then
		task.wait(0.1) 
		character:PivotTo(lobbyPart.CFrame * CFrame.new(0, 5, 0))
	end
end

-- // GLOBAL PLAYER LIFE CYCLE INITIALIZERS //
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		teleportToLobby(player, character)
	end)
end)

-- // SERVER INVOKE TRANSACTION INTERFACE //
SpawnFunction.OnServerInvoke = function(player, actionType, data1, data2, addOnType)

	-- ==========================================
	-- ACTION BLOCK: SECURED INFANTRY TELEPORTATION
	-- ==========================================
	if actionType == "TeleportPlayer" then
		local selectedBaseName = data1 
		local teamName = (player.Team and player.Team.Name) or ""
		local targetPointName = ""
		local isMainBase = false

		if teamName == "" then
			warn(" Transaction Refused: Player contains no valid native team assignment reference.")
			return false
		end

		selectedBaseName = string.gsub(selectedBaseName, "_Button", "")

		if selectedBaseName == "MainBase" then
			local randomSpawnIndex = math.random(1, 3)
			targetPointName = teamName .. "_MainBase_" .. randomSpawnIndex
			isMainBase = true
		else
			local zoneLetter = string.gsub(selectedBaseName, " Point", "")
			targetPointName = zoneLetter
		end

		if not isMainBase then
			if not GameLogic.IsPointOwnedByTeam(targetPointName, teamName) then
				warn(" Security Alert! " .. player.Name .. " bypassed client UI on point: " .. tostring(targetPointName))
				return false 
			end
			targetPointName = "Spawn_" .. targetPointName
		end

		local spawnPart = Workspace:FindFirstChild(targetPointName, true)
		if spawnPart and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			player.Character:PivotTo(spawnPart.CFrame * CFrame.new(0, 5, 0))
			return true 
		end

		if isMainBase then
			local fallbackPart = Workspace:FindFirstChild(teamName .. "_MainBase_1", true)
			if fallbackPart and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				player.Character:PivotTo(fallbackPart.CFrame * CFrame.new(0, 5, 0))
				return true
			end
		end

		return false

		-- ==========================================
		-- ACTION BLOCK: FACTORY TANK PRODUCTION DEPLOYMENT
		-- ==========================================
	elseif actionType == "SpawnTank" or not actionType then
		local rawTankName = (actionType == "SpawnTank") and data1 or actionType
		local buttonPad = (actionType == "SpawnTank") and data2 or data1 

		-- [[  PLAYER SPAWN RATE LIMITER ]] --
		local lastSpawnTime = player:GetAttribute("LastTankSpawnTime") or 0
		local currentTime = os.time()
		local SPAWN_COOLDOWN_TIME = 30

		if (currentTime - lastSpawnTime) < SPAWN_COOLDOWN_TIME then
			local remainingTime = SPAWN_COOLDOWN_TIME - (currentTime - lastSpawnTime)
			warn(string.format(" Cooldown Active: %s must wait %d more seconds.", player.Name, remainingTime))

			local messageEvent = eventsFolder:WaitForChild("ShowSpawnMessageEvent", 5)
			if messageEvent then
				messageEvent:FireClient(player, string.format("Wait for %d seconds", math.ceil(remainingTime)))
			end

			return false
		end

		if not addOnType then addOnType = "None" end

		local tankName = string.gsub(rawTankName, "_Button", "") 
		local tankTemplate = TankFolder:FindFirstChild(tankName)

		local linkedValue = buttonPad:FindFirstChild("LinkedArea", true)
		local realSpawnArea = (linkedValue and linkedValue.Value)

		if not realSpawnArea then
			realSpawnArea = buttonPad
		end

		if not tankTemplate or not realSpawnArea then
			warn(" Production Error: Missing assets for " .. buttonPad.Name)
			return false
		end

		-- CAPTURE ZONE ALIGNMENT VALIDATION
		local zoneModel = realSpawnArea.Parent
		if zoneModel and zoneModel.Parent and zoneModel.Parent.Name == "CaptureZones" then
			local zoneName = zoneModel.Name 
			local playerTeam = player.Team and player.Team.Name

			if not playerTeam or not GameLogic.IsPointOwnedByTeam(zoneName, playerTeam) then
				warn(string.format(" Spawn Denied: %s attempts to deploy tank at contested/hostile Zone %s", player.Name, zoneName))

				local messageEvent = eventsFolder:FindFirstChild("ShowSpawnMessageEvent")
				if messageEvent and messageEvent:IsA("RemoteEvent") then
					messageEvent:FireClient(player, "Capture the zone first!")
				end

				return false, "Capture the zone first!"
			end
			print(string.format(" Spawn Authorized: Node %s ownership verified for Team %s", zoneName, playerTeam))
		end

		-- CALCULATE FINANCIAL COST
		local stats = player:FindFirstChild("leaderstats")
		local pPoints = stats and stats:FindFirstChild("Points")

		local baseCost = tankTemplate:GetAttribute("Cost") or 0
		local surcharge = (addOnType == "Sandbags" and 1) or (addOnType == "Both" and 2) or 0
		local totalCost = baseCost + surcharge

		if pPoints and pPoints.Value >= totalCost then
			local trackerKey = realSpawnArea:GetFullName()
			local buffPercent = (addOnType == "Sandbags" and 0.05) or (addOnType == "Both" and 0.10) or 0

			-- Pass raw pad CFrame; HeightOffset is handled internally by SpawningModule
			local newTank, trackerData = SpawningModule.SpawnTank(tankTemplate, realSpawnArea.CFrame, {
				IsNPC = false,
				OwnerPlayer = player,
				TeamName = player.Team and player.Team.Name,
				BuffPercent = buffPercent,
				SpawnAreaSize = realSpawnArea.Size,
				TrackerKey = trackerKey,
				ProtectionTime = PROTECTION_TIME,
				AnchorHoldTime = 1.0,
				HeightOffset = 5
			})

			if not newTank then
				return false, "Spawn pad locked or occupied"
			end

			-- Deduct Points & Update Cooldown Timestamp
			pPoints.Value -= totalCost 
			player:SetAttribute("LastTankSpawnTime", os.time())

			-- =========================================================================
			-- [[  VISUAL ADD-ON CONFIGURATION ]]
			-- =========================================================================
			local function applyVisibility(targetInstance)
				if targetInstance:IsA("BasePart") then targetInstance.Transparency = 0 end
				for _, descendant in ipairs(targetInstance:GetDescendants()) do
					if descendant:IsA("BasePart") then descendant.Transparency = 0 end
				end
			end

			local addonModel = newTank:FindFirstChild("Add-on", true)
			if addonModel then
				if addOnType == "None" then
					addonModel:Destroy()
				else
					local sandbags = addonModel:FindFirstChild("Sandbags")
					local logs = addonModel:FindFirstChild("Logs")

					if addOnType == "Sandbags" then
						if sandbags then applyVisibility(sandbags) end
						if logs then logs:Destroy() end
					elseif addOnType == "Both" then
						if sandbags then applyVisibility(sandbags) end
						if logs then 
							applyVisibility(logs)
							local rope = logs:FindFirstChild("Rope")
							if rope then applyVisibility(rope) end
						end
					end
				end
			end

			-- =========================================================================
			-- [[  BILLBOARD UI & NETWORK OWNER SETTING ]]
			-- =========================================================================
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "SpawnTimerUI"
			billboard.Size = UDim2.new(12, 0, 3, 0) 
			billboard.StudsOffset = Vector3.new(0, 6, 0)
			billboard.Adornee = buttonPad 
			billboard.Enabled = false 
			billboard.Parent = buttonPad

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeTransparency = 0
			label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			label.TextScaled = true 
			label.Font = Enum.Font.GothamBold
			label.Text = "" 
			label.Parent = billboard

			-- NETWORK OWNER SETTING
			local hull = newTank:FindFirstChild("Main Hull", true) or newTank.PrimaryPart
			if hull and hull:IsA("BasePart") then
				pcall(function() hull:SetNetworkOwner(player) end)
			end

			-- DYNAMIC TIMER & EXIT DETECTION THREAD
			task.spawn(function()
				local currentTank = newTank
				local padCenter = realSpawnArea.Position
				local allowedX = (realSpawnArea.Size.X / 2) + 1
				local allowedZ = 4
				local exitThresholdX = allowedX + 4
				local exitThresholdZ = allowedZ + 4

				task.wait(0.5)

				if billboard and label then
					label.Text = "Protection: " .. PROTECTION_TIME .. "s"
					billboard.Enabled = true
				end

				for i = PROTECTION_TIME, 0, -1 do
					if not currentTank or not currentTank.Parent then break end

					local currentRoot = currentTank.PrimaryPart or currentTank:FindFirstChild("Main Hull", true) or currentTank:FindFirstChildWhichIsA("BasePart", true)
					if currentRoot then
						local currentPos = currentRoot.Position
						local currentDiffX = math.abs(padCenter.X - currentPos.X)
						local currentDiffZ = math.abs(padCenter.Z - currentPos.Z)

						if currentDiffX > exitThresholdX or currentDiffZ > exitThresholdZ then
							break
						end
					end

					label.Text = "Protection: " .. i .. "s"
					task.wait(1)
				end

				SpawningModule.ClearTracker(trackerKey)

				if billboard and billboard.Parent then
					billboard:Destroy()
				end
			end)

			return true
		else
			warn(" Surcharge Lockout: Transacting client carries insufficient points balance " .. tostring(totalCost))
			return false, "Insufficient Points"
		end
	end
	return false, "Cannot spawn vehicle at this moment"
end

-- // RUNTIME CONTEXT ASSURANCE FOR FAST LOADING CLIENTS //
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		teleportToLobby(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		teleportToLobby(player, character)
	end)
end
