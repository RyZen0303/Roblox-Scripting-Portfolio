-- // Health Damage Master (Faction Warfare Edition) //
-- Location: ServerScriptService
-- Focuses strictly on calculating damage processing for tank vehicles, mutating textures,
-- team alignment verification, instant crew execution, and base shields.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Events = ServerStorage:WaitForChild("Events")
local ProcessDamageEvent = Events:WaitForChild("ProcessDamage")

--  [NETWORK LINK]: Gateway to replicate kill confirmation metrics straight to the killer's screen
local PointEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("PointStatusUpdate")

local GameAssets = ServerStorage:WaitForChild("GameAssets")
local TankOverheadTemplate = GameAssets:WaitForChild("TankOverheadUI")

-- UI Texture Configuration
local AXIS_IMAGE = "rbxassetid://94230202846614"
local ALLIED_IMAGE = "rbxassetid://138619583021783"

print(" [SYSTEM]:  Damage Listener is LIVE. Mode: Faction Warfare (Match Edition).")

ProcessDamageEvent.Event:Connect(function(hitPart, damage, damageType, attackerPlayer)
	if not hitPart or not damage then return end

	-- // 1. IDENTIFY THE TARGET (MODEL OR BASEPART SHIELD) WITH ATTRIBUTES //
	local target = nil
	local isShield = false
	local current = hitPart

	-- Upward traversal: Look for ANY Instance containing the "Health" attribute (Handles both Tank Models and BasePart Shields)
	while current and current ~= workspace do
		if current:GetAttribute("Health") then
			target = current

			-- Explicit string matching to intercept base shield instances immediately
			if current.Name == "MainBaseShield_Germany" or current.Name == "MainBaseShield_Britain" then
				isShield = true
			end
			break
		end
		current = current.Parent
	end

	-- Secondary fallback: If the hitPart itself or its immediate Parent is named as a shield but missing attributes
	if not target then
		if hitPart.Name == "MainBaseShield_Germany" or hitPart.Name == "MainBaseShield_Britain" then
			target = hitPart
			isShield = true
		elseif hitPart.Parent and (hitPart.Parent.Name == "MainBaseShield_Germany" or hitPart.Parent.Name == "MainBaseShield_Britain") then
			target = hitPart.Parent
			isShield = true
		end
	end

	if not target then return end

	-- Fetch target faction early for validation matrices
	local targetFaction = target:GetAttribute("Team") or "Germany"

	-- // 2. INTERCEPT DATA FOR BASE SHIELD LOGIC & TEAM INTEGRITY CHECK //
	if isShield then
		-- Strict Faction Shield Protection: Block attackers from dealing damage to their own home base shields
		if attackerPlayer and attackerPlayer:IsA("Player") and attackerPlayer.Team then
			local attackerTeamName = attackerPlayer.Team.Name
			if (target.Name:find("Germany") and attackerTeamName == "Germany") or (target.Name:find("Britain") and attackerTeamName == "Britain") then
				return -- Absorb damage silently, preventing friendly base destruction sabotage
			end
		end

		local currentShieldHP = tonumber(target:GetAttribute("Health"))
		local damageValue = tonumber(damage)

		-- Structural recovery if attributes were cleared or not initialized properly in explorer
		if not currentShieldHP then
			local maxHP = tonumber(target:GetAttribute("MaxHealth")) or 5000
			target:SetAttribute("MaxHealth", maxHP)
			target:SetAttribute("Health", maxHP)
			currentShieldHP = maxHP
		end

		local newShieldHP = math.max(0, currentShieldHP - damageValue)
		target:SetAttribute("Health", newShieldHP)

		print(" [SHIELD DAMAGE]: " .. target.Name .. " sustained hit! | HP Equation: " .. currentShieldHP .. " - " .. damageValue .. " = " .. newShieldHP)

		-- Abort further tank-specific execution because shields do not have crew or overhead instances
		return
	end

	-- // 3. STANDARD TANK DAMAGE CALCULATION & TEAM FIRE VERIFICATION //
	if target:GetAttribute("IsDestroyed") then return end -- Prevent double processing on dying frames

	-- -------------------------------------------------------------------------
	-- [[  ANTI-TEAMKILL & ANTI-SUICIDE PRODUCTION VALIDATION ]]
	-- -------------------------------------------------------------------------
	local vehicleOwnerName = target:GetAttribute("Owner") or "Unknown Crew"

	if attackerPlayer and attackerPlayer:IsA("Player") then
		-- Prevent Suicide: Disallow players from destroying their own spawned vehicle infrastructure
		if attackerPlayer.Name == vehicleOwnerName then
			warn(string.format(" [Damage Denied]: %s attempted self-harm on owned vehicle asset.", attackerPlayer.Name))
			return
		end

		-- Prevent Friendly Fire: Block damage execution if the attacker is on the exact same team roster
		if attackerPlayer.Team and attackerPlayer.Team.Name == targetFaction then
			warn(string.format(" [Friendly Fire Blocked]: %s tried to attack allied %s asset.", attackerPlayer.Name, targetFaction))
			return
		end
	end
	-- -------------------------------------------------------------------------

	local currentHealth = tonumber(target:GetAttribute("Health"))
	local damageValue = tonumber(damage)

	if not currentHealth or not damageValue then
		warn(" [TANK MATH ERROR]: Calculation failed. Health or Damage is not a valid number!")
		return
	end

	-- Authoritatively bind the killer's name to the tank instance via Attribute for KillFeed processing
	if attackerPlayer and attackerPlayer:IsA("Player") then
		target:SetAttribute("LastDamageDealer", attackerPlayer.Name)
	else
		target:SetAttribute("LastDamageDealer", "Field Artillery")
	end

	local newHealth = math.max(0, currentHealth - damageValue)
	target:SetAttribute("Health", newHealth)

	print(" [TANK MATH CHECK]: " .. target.Name .. " (" .. targetFaction .. ") | Attacker: " .. (target:GetAttribute("LastDamageDealer")) .. " | Equation: " .. currentHealth .. " - " .. damageValue .. " = " .. newHealth)

	-- // 4. TANK OVERHEAD UI HANDLING //
	local mainHull = target:FindFirstChild("Main Hull", true) or target:FindFirstChild("MainHull", true) or target.PrimaryPart
	if mainHull then
		local overhead = mainHull:FindFirstChild("TankOverheadUI")
		if not overhead then
			overhead = TankOverheadTemplate:Clone()
			overhead.Name = "TankOverheadUI"

			local flag = overhead:FindFirstChild("FlagDisplay", true)
			if flag then
				flag.Image = (targetFaction == "Britain") and ALLIED_IMAGE or AXIS_IMAGE
			end

			overhead.Adornee = mainHull
			overhead.Parent = mainHull

			-- -------------------------------------------------------------------------
			-- [[  LIVE VISUAL SYNC: ATTRIBUTE SIGNAL BINDING ]]
			-- -------------------------------------------------------------------------
			-- Bind a dynamic listener to update the UI element whenever the core health state mutates (Damage or Heal)
			target:GetAttributeChangedSignal("Health"):Connect(function()
				if not target or not overhead then return end
				local bg = overhead:FindFirstChild("HealthBarBG")
				local bar = bg and bg:FindFirstChild("HealthBar")

				if bg and bar then
					local currentHP = tonumber(target:GetAttribute("Health")) or 0
					local maxHealth = tonumber(target:GetAttribute("MaxHealth")) or 1300
					local healthPercent = math.clamp(currentHP / maxHealth, 0, 1)

					-- Realtime dynamic scale adjustment
					bar.Size = UDim2.new(healthPercent, 0, 1, 0)
				end
			end)
			-- -------------------------------------------------------------------------
		end

		-- Visibility & Auto-Hide handling on hit
		local bg = overhead:FindFirstChild("HealthBarBG")
		if bg then
			bg.Visible = true
			bg.BackgroundTransparency = 0
			local bar = bg:FindFirstChild("HealthBar")
			if bar then bar.BackgroundTransparency = 0 end

			-- Force initial frame update straight after creation/hit
			local maxHealth = tonumber(target:GetAttribute("MaxHealth")) or 1300
			local healthPercent = math.clamp(newHealth / maxHealth, 0, 1)
			local bar = bg:FindFirstChild("HealthBar")
			if bar then bar.Size = UDim2.new(healthPercent, 0, 1, 0) end

			local hitTag = tick()
			target:SetAttribute("LastHitTag", hitTag)
			task.delay(15, function()
				if target and target:GetAttribute("LastHitTag") == hitTag and bg then
					bg.Visible = false
				end
			end)
		end
	end

	-- // 5. AUTHORITATIVE TANK DESTRUCTION LOGIC & DYNAMIC REWARDS //
	if newHealth <= 0 then
		target:SetAttribute("IsDestroyed", true)

		local victimName = vehicleOwnerName
		local killerName = target:GetAttribute("LastDamageDealer") or "Field Artillery"
		local tankModelName = target.Name
		local unitType = target:GetAttribute("UnitType") or "Light"

		-- [[  Strict Unit Type Reward Multipliers ]]
		local killReward = 2 -- Baseline fallback
		if unitType == "Heavy" then
			killReward = 7
		elseif unitType == "Medium" then
			killReward = 4
		end

		print(" [DESTRUCTION]: " .. tankModelName .. " vaporized by " .. killerName .. "! Routing data...")

		-- Security enforcement: Enforce validation to prevent dynamic exploit scoring updates
		if killerName ~= "Field Artillery" and killerName ~= victimName then
			local killerPlayerInstance = Players:FindFirstChild(killerName)
			if killerPlayerInstance then
				-- 1. Allocate score to leaderstats
				local stats = killerPlayerInstance:FindFirstChild("leaderstats")
				local points = stats and stats:FindFirstChild("Points")
				if points then
					points.Value += killReward
				end

				-- 2. Fire Personal Client Event (Visual kill indicator pops up)
				pcall(function()
					PointEvent:FireClient(killerPlayerInstance, "TANK_KILLED", {
						Victim = victimName,
						Weapon = tankModelName,
						RewardPoints = killReward
					})
				end)
			end
		end

		-- Execute infantry and crew inside the vehicle instances instantly
		for _, obj in ipairs(target:GetDescendants()) do
			if obj:IsA("Seat") or obj:IsA("VehicleSeat") then
				if obj.Occupant then
					local humanoid = obj.Occupant
					humanoid.Health = 0
					humanoid:TakeDamage(9999)
				end
			end
		end

		-- Mutate tank physical textures to wrecked status
		for _, obj in ipairs(target:GetDescendants()) do
			if obj:IsA("BasePart") and not (obj:IsA("Seat") or obj:IsA("VehicleSeat")) then
				obj.Material = Enum.Material.CorrodedMetal
				obj.Color = Color3.fromRGB(55, 55, 55)
			end
		end

		-- Authoritative cleanup delay
		task.delay(5, function()
			if target and target.Parent then
				target:Destroy()
				print(" [DESPAWN]: " .. tankModelName .. " clean up sequence completed.")
			end
		end)
	end
end)
