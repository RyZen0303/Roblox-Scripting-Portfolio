-- // GameplayMaster (Server-Side - Combat, Conquest & Terrain Sync) //
-- Location: ServerScriptService
-- Optimized for: Dynamic Out-of-Combat Regen, Strict Conquest Neutralization, and Destructible Physics.

local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataManager = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerDataManager"))

local PointEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("PointStatusUpdate")

-- [[  CONFIGURATION & TUNING ]] --
local CAPTURE_ZONES_FOLDER = workspace:WaitForChild("CaptureZones", 15)
local ASSETS_FOLDER = ServerStorage:WaitForChild("GameAssets", 5)

local CAPTURE_UI_TEMPLATE = ASSETS_FOLDER and ASSETS_FOLDER:WaitForChild("CaptureUI", 5)
local OVERHEAD_TEMPLATE = ASSETS_FOLDER and ASSETS_FOLDER:WaitForChild("TankOverheadUI", 5)
local FLAGS_FOLDER = ASSETS_FOLDER and ASSETS_FOLDER:WaitForChild("FlagIcon", 5)

local BASE_CAPTURE_RATE = 1.5
local REWARD_POINTS = 7
local TANK_KILL_REWARD = 25
local OUT_OF_COMBAT_TIME = 30.0 -- Mandatory damage-free window before healing triggers
local HEAL_TICK_RATE = 2.0      -- Time interval between auto-heal ticks

local TEAM_COLORS = {
	["Germany"] = Color3.fromRGB(245, 190, 40),
	["Britain"] = Color3.fromRGB(45, 120, 230),
	["Neutral"] = Color3.fromRGB(255, 255, 255)
}

-- [[  STATIC INSTANCE REUSE & CACHING ]] --
local zoneOverlapParams = OverlapParams.new()
zoneOverlapParams.FilterType = Enum.RaycastFilterType.Exclude

local cachedShields = {
	["Germany"] = nil,
	["Britain"] = nil
}

local function getLiveShield(baseName, shieldName)
	local base = workspace:FindFirstChild(baseName)
	if base then return base:FindFirstChild(shieldName, true) end
	return nil
end

local function updateShieldReferences()
	cachedShields["Germany"] = getLiveShield("GermanyBase", "MainBaseShield_Germany")
	cachedShields["Britain"] = getLiveShield("BritainBase", "MainBaseShield_Britain")
end

local function initializeShields(isReset)
	updateShieldReferences()
	for faction, shieldPart in pairs(cachedShields) do
		if shieldPart then
			local maxHP = shieldPart:GetAttribute("MaxHealth") or 25000
			if isReset or not shieldPart:GetAttribute("Health") then
				shieldPart:SetAttribute("Health", maxHP)
			end
			print(string.format(" [Server Engine]: %s Shield verified. HP: %s/%s", faction, tostring(shieldPart:GetAttribute("Health")), tostring(maxHP)))
		else
			warn(" [Server Engine]: Shield for " .. faction .. " missing from Workspace structural hierarchy!")
		end
	end
end

local matchActive = true

-- [[  MATCH LIFECYCLE CONTROLLER ]] --
local function endMatchAndReset(winningTeam)
	if not matchActive then return end
	matchActive = false

	print(" [MATCH OVER]: " .. winningTeam:upper() .. " HAS WON THE MATCH!")
	pcall(function() PointEvent:FireAllClients("MATCH_OVER", winningTeam) end)
	task.wait(5.0)

	local wsChildren = workspace:GetChildren()
	for i = 1, #wsChildren do
		local instance = wsChildren[i]
		if instance:IsA("Model") and (instance:GetAttribute("IsTank") or instance.Name:find("Tiger") or instance.Name:find("Panther") or instance.Name:find("Comet")) then
			pcall(function() instance:Destroy() end)
		elseif instance.Name == "Projectile_Hitbox" then
			pcall(function() instance:Destroy() end)
		end
	end

	local zones = CAPTURE_ZONES_FOLDER:GetChildren()
	for i = 1, #zones do
		local zone = zones[i]
		if zone:IsA("BasePart") then
			zone:SetAttribute("Progress", 0)
			zone:SetAttribute("Owner", "Neutral")
			zone:SetAttribute("CapturingTeam", "Neutral")
			zone:SetAttribute("PreviousOwner", "Neutral")
		end
	end

	initializeShields(true)

	local currentPlayers = Players:GetPlayers()
	for i = 1, #currentPlayers do
		local player = currentPlayers[i]
		task.spawn(function() if player and player.Parent then player:LoadCharacter() end end)
	end

	matchActive = true
end

-- // CORE SHIELD MONITORING THREAD //
task.spawn(function()
	while true do
		task.wait(0.5)
		if not matchActive then continue end

		local shieldGermany = cachedShields["Germany"]
		local shieldBritain = cachedShields["Britain"]

		if shieldGermany and (shieldGermany:GetAttribute("Health") or 1) <= 0 then endMatchAndReset("Britain") continue end
		if shieldBritain and (shieldBritain:GetAttribute("Health") or 1) <= 0 then endMatchAndReset("Germany") continue end
	end
end)

-- [[  TANK INITIALIZATION SYSTEM ]] --
local function setupTankOverhead(tank)
	if not OVERHEAD_TEMPLATE then return end
	local teamName = tank:GetAttribute("Team") or tank:GetAttribute("OwnerTeam")
	if not teamName then return end

	local mainPart = tank:FindFirstChild("Main Hull", true) or tank:FindFirstChild("MainHull", true) or tank.PrimaryPart
	if not mainPart or mainPart:FindFirstChild("TankOverheadUI") then return end

	local newUI = OVERHEAD_TEMPLATE:Clone()
	newUI.Name = "TankOverheadUI"
	newUI.Adornee = mainPart
	newUI.Parent = mainPart

	if FLAGS_FOLDER then
		local flagAsset = FLAGS_FOLDER:FindFirstChild(teamName)
		local flagDisplay = newUI:FindFirstChild("FlagDisplay", true)
		if flagAsset and flagDisplay then flagDisplay.Image = flagAsset.Texture end
	end

	tank:SetAttribute("LastDamageTime", 0)
end

-- [[  STRATEGIC POINT UI SYSTEM ]] --
local function setupCaptureUI(zone)
	if not CAPTURE_UI_TEMPLATE then return end
	local uiAnchor = zone:FindFirstChild("UIAnchor") or Instance.new("Attachment", zone)
	uiAnchor.Name = "UIAnchor"
	if uiAnchor:IsA("Attachment") then uiAnchor.Position = Vector3.new(0, 6, 0) end

	local ui = CAPTURE_UI_TEMPLATE:Clone()
	ui.Adornee = uiAnchor
	ui.Parent = zone

	local background = ui:WaitForChild("Background", 5)
	local bar = background and background:WaitForChild("ProgressBar", 5)
	local label = ui:FindFirstChild("PointName", true)

	if background then background.BackgroundTransparency = 1 end
	if bar then bar.BackgroundTransparency = 1 end
	if label then
		label.Text = zone.Name
		label.BackgroundColor3 = TEAM_COLORS[zone:GetAttribute("Owner") or "Neutral"]
	end

	zone:GetAttributeChangedSignal("Progress"):Connect(function()
		local p = zone:GetAttribute("Progress") or 0
		local owner = zone:GetAttribute("Owner") or "Neutral"
		local capturingTeam = zone:GetAttribute("CapturingTeam") or "Neutral"

		local isContested = (p > 0 and p < 100) or (owner == "Neutral" and p > 0)
		if background then background.BackgroundTransparency = isContested and 0.3 or 1 end
		if bar then bar.BackgroundTransparency = isContested and 0 or 1 end

		if bar then
			TweenService:Create(bar, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(p/100, 0, 1, 0)}):Play()
			bar.BackgroundColor3 = TEAM_COLORS[capturingTeam] or TEAM_COLORS["Neutral"]
		end
	end)

	-- [[  REAL-TIME SPAWN PAD FACTION SYNC ]] --
	zone:GetAttributeChangedSignal("Owner"):Connect(function()
		local owner = zone:GetAttribute("Owner") or "Neutral"
		pcall(function() PointEvent:FireAllClients(zone.Name, owner) end)

		local clr = TEAM_COLORS[owner] or TEAM_COLORS["Neutral"]
		if label then label.BackgroundColor3 = clr end
		zone.Color = clr

		-- [[  AUTOMATED SPAWN PAD FACTION ALIGNMENT ]] --
		-- Recursively scan all descendants of this captured zone to find its interactive pad
		for _, child in ipairs(zone:GetDescendants()) do
			if child:IsA("BasePart") and (child.Name:find("SpawnPad") or child.Name:find("ButtonPad")) then
				-- Authoritatively overwrite the pad's team affiliation to deny old owners instantly
				child:SetAttribute("Team", owner)
				print(string.format(" [Faction Sync]: Automatically converted %s alignment to: %s", child.Name, owner))
			end
		end
		
	end)

end

-- [[  SPATIAL DETECTION SYSTEM ]] --
local function getTanksInZone(zone)
	local detectedTanks = {}
	zoneOverlapParams.FilterDescendantsInstances = {zone}

	local overlappingParts = workspace:GetPartsInPart(zone, zoneOverlapParams)
	local processedSubTrees = {}

	for i = 1, #overlappingParts do
		local part = overlappingParts[i]
		local current = part

		while current and current ~= workspace do
			if processedSubTrees[current] then break end
			if current:IsA("Model") and current:GetAttribute("Team") then
				processedSubTrees[current] = true

				local seat = current:FindFirstChildOfClass("VehicleSeat") or current:FindFirstChildOfClass("Seat") or current:FindFirstChild("DriverSeat", true)
				if seat and seat.Occupant then
					local player = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
					if player then detectedTanks[current] = current:GetAttribute("Team") end
				end
				break
			end
			current = current.Parent
		end
	end
	return detectedTanks
end

-- [[  DESTRUCTIBLE TERRAIN INFRASTRUCTURE ]] --
local function handleDestructibleDamage(part)
	if not part:IsA("BasePart") then return end
	part:GetAttributeChangedSignal("Health"):Connect(function()
		local hp = part:GetAttribute("Health") or 0
		if hp <= 0 and part.Anchored then
			part.Anchored = false
			part.CanCollide = true
			part.CanTouch = false
			part.CanQuery = false

			local blastVector = Vector3.new(math.random(-20, 20), math.random(25, 55), math.random(-20, 20))
			part:ApplyImpulse(blastVector * part:GetMass())

			task.delay(6.0, function() pcall(function() part:Destroy() end) end)
		end
	end)
end

local function initializeDestructibleTerrain()
	local terrainFolder = workspace:FindFirstChild("DestructibleTerrain")
	if terrainFolder then
		for _, part in ipairs(terrainFolder:GetDescendants()) do
			if part:IsA("BasePart") then
				if not part:GetAttribute("MaxHealth") then part:SetAttribute("MaxHealth", 500) end
				if not part:GetAttribute("Health") then part:SetAttribute("Health", part:GetAttribute("MaxHealth")) end
				handleDestructibleDamage(part)
			end
		end
	end
end

-- Execute core initialization maps
initializeShields(false)
initializeDestructibleTerrain()

local initZones = CAPTURE_ZONES_FOLDER:GetChildren()
for i = 1, #initZones do
	local zone = initZones[i]
	if zone:IsA("BasePart") then
		local startingOwner = zone:GetAttribute("Owner") or "Neutral"
		zone:SetAttribute("Owner", startingOwner)
		zone:SetAttribute("PreviousOwner", startingOwner)
		zone:SetAttribute("CapturingTeam", startingOwner)
		zone:SetAttribute("Progress", startingOwner == "Neutral" and 0 or 100)
		setupCaptureUI(zone)
	end
end

workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("Model") and obj:GetAttribute("Team") then
		task.defer(function() setupTankOverhead(obj) end)
	end
end)

-- [[  DYNAMIC MULTI-POINT CONQUEST SYSTEM ]] --
task.spawn(function()
	local function rewardTeam(teamName)
		local currentPlayers = Players:GetPlayers()
		for i = 1, #currentPlayers do
			local player = currentPlayers[i]
			if player.Team and player.Team.Name == teamName then
				local stats = player:FindFirstChild("leaderstats")
				local p = stats and stats:FindFirstChild("Points")
				if p then p.Value += REWARD_POINTS end
			end
		end
	end

	while task.wait(0.5) do
		if not matchActive then continue end

		local zones = CAPTURE_ZONES_FOLDER:GetChildren()
		for zIdx = 1, #zones do
			local zone = zones[zIdx]
			if not zone:IsA("BasePart") then continue end

			local tanksFound = getTanksInZone(zone)
			local countGER = 0
			local countBR = 0

			-- Aggregate physical presence data inside zone mapping
			for _, team in pairs(tanksFound) do
				if team == "Germany" then countGER = countGER + 1
				elseif team == "Britain" then countBR = countBR + 1 end
			end

			local currentProgress = zone:GetAttribute("Progress") or 0
			local capturingTeam = zone:GetAttribute("CapturingTeam") or "Neutral"
			local previousOwner = zone:GetAttribute("PreviousOwner") or "Neutral"

			if countGER > 0 or countBR > 0 then
				-- [[ FIELD ACTIVE ]: Players present in area boundary ]]
				if countGER == countBR then
					-- [[ CASE 3 ]: Balanced contest state. Lock progress ratio exactly in place.
					zone:SetAttribute("Owner", "Neutral") -- Force drop capture title under challenge
					-- Skip modifications; mathematical change rate equals zero
				else
					local dominantTeam = (countGER > countBR) and "Germany" or "Britain"
					local netAdvantage = math.abs(countGER - countBR)
					local rate = netAdvantage * BASE_CAPTURE_RATE

					if capturingTeam == "Neutral" or currentProgress == 0 then
						capturingTeam = dominantTeam
						zone:SetAttribute("CapturingTeam", dominantTeam)
					end

					if capturingTeam == dominantTeam then
						-- [[ CASE 1 ]: Pushing team's corresponding scale metrics upwards
						currentProgress = math.min(currentProgress + rate, 100)
						if currentProgress >= 100 then
							-- [[  DYNAMIC CAPTURE REWARD LOGIC ]] --
							if zone:GetAttribute("Owner") ~= dominantTeam then
								local prevOwner = zone:GetAttribute("PreviousOwner") or "Neutral"

								if prevOwner == "Neutral" then
									-- Captured a completely uncontested/neutral zone
									local currentPlayers = Players:GetPlayers()
									for pIdx = 1, #currentPlayers do
										local player = currentPlayers[pIdx]
										if player.Team and player.Team.Name == dominantTeam then
											local stats = player:FindFirstChild("leaderstats")
											local p = stats and stats:FindFirstChild("Points")
											if p then p.Value += 5 end
										end
									end
									print(string.format(" [Conquest]: %s captured Neutral zone. Awarded 5 points.", dominantTeam))
								elseif prevOwner ~= dominantTeam then
									-- Successfully recaptured/stole the zone back from the Enemy faction
									local currentPlayers = Players:GetPlayers()
									for pIdx = 1, #currentPlayers do
										local player = currentPlayers[pIdx]
										if player.Team and player.Team.Name == dominantTeam then
											local stats = player:FindFirstChild("leaderstats")
											local p = stats and stats:FindFirstChild("Points")
											if p then p.Value += 10 end
										end
									end
									print(string.format(" [Conquest]: %s recaptured enemy zone from %s! Awarded 10 points.", dominantTeam, prevOwner))
								end
							end

							zone:SetAttribute("Owner", dominantTeam)
							zone:SetAttribute("PreviousOwner", dominantTeam)
						else
							zone:SetAttribute("Owner", "Neutral") -- Enforce strict uncapped neutralization
						end
					else
						-- Depleting enemy progress down toward zero threshold
						currentProgress = math.max(currentProgress - rate, 0)
						zone:SetAttribute("Owner", "Neutral") -- Instant title removal
						if currentProgress <= 0 then
							capturingTeam = dominantTeam
							zone:SetAttribute("CapturingTeam", dominantTeam)
						end
					end
				end
			else
				-- [[ FIELD VACANT ]: Automatic Decay / Recovery Routine ]
				if capturingTeam ~= "Neutral" and currentProgress > 0 then
					if capturingTeam == previousOwner then
						-- [[ CASE 2 ]: Recharging back to original 100% threshold
						currentProgress = math.min(currentProgress + 3, 100)
						if currentProgress >= 100 then zone:SetAttribute("Owner", capturingTeam) else zone:SetAttribute("Owner", "Neutral") end
					else
						-- Incomplete attackers vacated. Decay progress down to neutral void state.
						currentProgress = math.max(currentProgress - 3, 0)
						zone:SetAttribute("Owner", "Neutral")
						if currentProgress <= 0 then
							capturingTeam = "Neutral"
							zone:SetAttribute("CapturingTeam", "Neutral")
						end
					end
				end
			end

			zone:SetAttribute("Progress", currentProgress)
		end
	end
end)

-- [[  OUT-OF-COMBAT AUTOMATED REGENERATION THREAD ]] --
task.spawn(function()
	while true do
		task.wait(HEAL_TICK_RATE)
		if not matchActive then continue end

		local allModels = workspace:GetChildren()
		local currentTime = os.clock()

		for i = 1, #allModels do
			local tank = allModels[i]
			if tank:IsA("Model") and tank:GetAttribute("IsTank") and not tank:GetAttribute("IsDestroyed") then
				local currentHP = tank:GetAttribute("Health")
				local maxHP = tank:GetAttribute("MaxHealth") or 750
				local lastDamage = tank:GetAttribute("LastDamageTime") or 0

				if currentHP and currentHP < maxHP and (currentTime - lastDamage) >= OUT_OF_COMBAT_TIME then
					local healPulse = math.ceil(maxHP * 0.05)
					local newHP = math.min(maxHP, currentHP + healPulse)

					tank:SetAttribute("Health", newHP)

					local mainHull = tank:FindFirstChild("Main Hull", true) or tank:FindFirstChild("MainHull", true) or tank.PrimaryPart
					local overhead = mainHull and mainHull:FindFirstChild("TankOverheadUI")
					local bg = overhead and overhead:FindFirstChild("HealthBarBG")
					local bar = bg and bg:FindFirstChild("HealthBar")

					if bg and bar then
						bg.Visible = true
						bg.BackgroundTransparency = 0
						bar.BackgroundTransparency = 0
						bar.Size = UDim2.new(newHP / maxHP, 0, 1, 0)

						local fadeTag = tick()
						tank:SetAttribute("LastHealFadeTag", fadeTag)
						task.delay(4, function()
							if tank and tank:GetAttribute("LastHealFadeTag") == fadeTag and bg then bg.Visible = false end
						end)
					end
				end
			end
		end
	end
end)

-- [[  PASSIVE REWARD SYSTEM ]] --
task.spawn(function()
	while true do
		task.wait(120) -- Loop executes every 120 seconds (2 minutes) to distribute passive points
		if matchActive then
			local currentPlayers = Players:GetPlayers()
			for i = 1, #currentPlayers do
				local player = currentPlayers[i]
				local stats = player:FindFirstChild("leaderstats")
				local p = stats and stats:FindFirstChild("Points")
				if p then
					p.Value += 3
				end
			end
		end
	end
end)


-- [[  PASSIVE CASH REWARD SYSTEM ]] --
-- Pays $100 for every 90 seconds a player remains in this server.
-- Rewards are granted by the server and stored in PlayerDataManager's session data.
local CASH_REWARD_INTERVAL = 90
local CASH_REWARD_AMOUNT = 100
local cashRewardRunning = {}

local function startPassiveCashRewards(player)
	if cashRewardRunning[player] then return end
	cashRewardRunning[player] = true

	task.spawn(function()
		-- Do not start the player's timer until their saved data has loaded.
		while player.Parent and not PlayerDataManager.IsDataLoaded(player) do
			task.wait(0.25)
		end

		if not player.Parent then
			cashRewardRunning[player] = nil
			return
		end

		while player.Parent do
			task.wait(CASH_REWARD_INTERVAL)

			if not player.Parent then break end

			if PlayerDataManager.IsDataLoaded(player) then
				local success = PlayerDataManager.AddCash(player, CASH_REWARD_AMOUNT)
				if success then
					print(string.format(
						"[PASSIVE CASH] Awarded $%d to %s after %d seconds.",
						CASH_REWARD_AMOUNT,
						player.Name,
						CASH_REWARD_INTERVAL
					))
				end
			end
		end

		cashRewardRunning[player] = nil
	end)
end

Players.PlayerAdded:Connect(startPassiveCashRewards)
Players.PlayerRemoving:Connect(function(player)
	cashRewardRunning[player] = nil
end)

-- Handle players already present if this script starts after they joined.
for _, player in ipairs(Players:GetPlayers()) do
	startPassiveCashRewards(player)
end
