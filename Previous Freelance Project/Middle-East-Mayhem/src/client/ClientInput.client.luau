-- ClientInput.client.luau
-- Keyboard & Mouse Input Listener for Weapon Handling & Movement

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local reloadWeaponEvent = eventsFolder:WaitForChild("ReloadWeaponEvent")
local toggleFireModeEvent = eventsFolder:WaitForChild("ToggleFireModeEvent")
local cycleBoltEvent = eventsFolder:WaitForChild("CycleBoltEvent")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local WeaponConfigLoader = require(Modules:WaitForChild("WeaponConfigLoader") :: ModuleScript)

-- Movement Configuration Defaults (Temporary fallback before PlayerStatGuard)
local DEFAULT_WALK_SPEED = 16
local DEFAULT_SPRINT_SPEED = 25

local function getEquippedTool()
	local character = localPlayer.Character
	if not character then return nil end

	return character:FindFirstChildOfClass("Tool")
end

-- Helper to extract active available fire modes array from config
local function getAvailableFireModes(config)
	local availableModes = {}
	if config and config.FireModes and config.FireModes.Available then
		local modes = config.FireModes.Available
		if modes.Semi then table.insert(availableModes, "Semi") end
		if modes.Burst then table.insert(availableModes, "Burst") end
		if modes.Auto then table.insert(availableModes, "Auto") end
	else
		availableModes = { "Semi", "Auto" }
	end
	return availableModes
end

-- Initializes weapon DefaultMode on equip if attribute is missing
local function initializeWeaponMode(tool: Tool)
	local config = WeaponConfigLoader.GetConfig(tool.Name)
	if not config then return end

	if tool:GetAttribute("FireMode") == nil then
		local availableModes = getAvailableFireModes(config)
		local defaultMode = (config.FireModes and config.FireModes.DefaultMode) or availableModes[1] or "Auto"
		tool:SetAttribute("FireMode", defaultMode)
	end
end

-- Cycles through active firing modes based on weapon configuration
local function cycleFireMode(tool: Tool)
	if tool:GetAttribute("IsReloading") == true then return end

	local config = WeaponConfigLoader.GetConfig(tool.Name)
	local availableModes = getAvailableFireModes(config)

	if #availableModes == 0 then return end

	local defaultMode = (config and config.FireModes and config.FireModes.DefaultMode) or availableModes[1]
	local currentMode = tool:GetAttribute("FireMode") or defaultMode

	local nextIndex = 1
	for index, mode in ipairs(availableModes) do
		if mode == currentMode then
			nextIndex = (index % #availableModes) + 1
			break
		end
	end

	local newMode = availableModes[nextIndex]
	tool:SetAttribute("FireMode", newMode)

	toggleFireModeEvent:FireServer(tool.Name, newMode)
end

-- Pull/cycle the bolt on bolt-action weapons after a shot
local function cycleBolt(tool: Tool)
	if tool:GetAttribute("IsReloading") == true then return end

	local config = WeaponConfigLoader.GetConfig(tool.Name)
	if not config or config.BoltAction ~= true then return end
	if tool:GetAttribute("BoltNeedsCycle") ~= true then return end

	-- Server clears BoltNeedsCycle after validating the request.
	-- Keep the local state locked until that replicated change arrives.
	cycleBoltEvent:FireServer(tool.Name)
end

-- Updates character movement speed based on sprint state
local function setSprinting(isSprinting: boolean)
	local character = localPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	character:SetAttribute("IsSprinting", isSprinting)
	humanoid.WalkSpeed = isSprinting and DEFAULT_SPRINT_SPEED or DEFAULT_WALK_SPEED
end

-- Listen for tool equipping and character setup
local function setupCharacter(character: Model)
	character:SetAttribute("IsSprinting", false)

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			initializeWeaponMode(child)
		end
	end)

	local currentTool = character:FindFirstChildOfClass("Tool")
	if currentTool then
		initializeWeaponMode(currentTool)
	end
end

if localPlayer.Character then
	setupCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(setupCharacter)

-- Key & Mouse Input Listener (Began)
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	-- Left Shift: Start Sprinting
	if input.KeyCode == Enum.KeyCode.LeftShift then
		setSprinting(true)
	end

	local tool = getEquippedTool()
	if not tool then return end

	-- R Key: Reload Action
	if input.KeyCode == Enum.KeyCode.R then
		if tool:GetAttribute("IsReloading") == true then return end
		reloadWeaponEvent:FireServer(tool.Name)
	end

	-- V Key: Toggle Fire Mode
	if input.KeyCode == Enum.KeyCode.V then
		cycleFireMode(tool)
	end

	-- T Key: Cycle/Pull Bolt for bolt-action weapons
	if input.KeyCode == Enum.KeyCode.T then
		cycleBolt(tool)
	end
end)

-- Key & Mouse Input Listener (Ended)
UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	-- Left Shift Release: Stop Sprinting
	if input.KeyCode == Enum.KeyCode.LeftShift then
		setSprinting(false)
	end
end)