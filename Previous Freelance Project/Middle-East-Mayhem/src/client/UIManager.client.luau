-- UIManager.client.luau
-- Centralized Client UI Manager for FPS Crosshair, Ammo Display, Reload Progress Bar & Dynamic Hitmarker

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local weaponsConfigFolder = ReplicatedStorage:WaitForChild("WeaponsConfig", 5) or ReplicatedStorage:WaitForChild("Weapons Config", 5)

-- Events Reference
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local hitmarkerEvent = eventsFolder:WaitForChild("HitmarkerEvent")

-- Hide standard system mouse cursor
UserInputService.MouseIconEnabled = false
UserInputService.WindowFocused:Connect(function()
	UserInputService.MouseIconEnabled = false
end)

-- Track Aiming State
local isAiming = false

-- Weapon Config Cache & Retriever
local cachedConfigs = {}

local function getWeaponConfig(weaponName: string)
	if cachedConfigs[weaponName] then
		return cachedConfigs[weaponName]
	end

	if not weaponsConfigFolder then return nil end

	for _, descendant in ipairs(weaponsConfigFolder:GetDescendants()) do
		if descendant:IsA("ModuleScript") and descendant.Name == weaponName then
			local success, configData = pcall(require, descendant)
			if success and type(configData) == "table" then
				cachedConfigs[weaponName] = configData
				return configData
			end
		end
	end

	return nil
end

-- == Master ScreenGui Container ==
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "UIManagerGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- =========================================================================
-- 1. CROSSHAIR SYSTEM COMPONENTS
-- =========================================================================
local crosshairCenterFrame = Instance.new("Frame")
crosshairCenterFrame.Name = "CrosshairContainer"
crosshairCenterFrame.Size = UDim2.fromScale(1, 1)
crosshairCenterFrame.BackgroundTransparency = 1
crosshairCenterFrame.Parent = screenGui

-- Default Diamond Crosshair (Unarmed)
local defaultCrosshair = Instance.new("Frame")
defaultCrosshair.Name = "DefaultCrosshair"
defaultCrosshair.Size = UDim2.fromOffset(6, 6)
defaultCrosshair.AnchorPoint = Vector2.new(0.5, 0.5)
defaultCrosshair.Position = UDim2.fromScale(0.5, 0.5)
defaultCrosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
defaultCrosshair.Rotation = 45
defaultCrosshair.BorderSizePixel = 0
defaultCrosshair.Parent = crosshairCenterFrame

local defaultCorner = Instance.new("UICorner")
defaultCorner.CornerRadius = UDim.new(0, 1)
defaultCorner.Parent = defaultCrosshair

-- Weapon Target Reticle (Equipped)
local weaponCrosshair = Instance.new("Frame")
weaponCrosshair.Name = "WeaponCrosshair"
weaponCrosshair.Size = UDim2.fromScale(1, 1)
weaponCrosshair.BackgroundTransparency = 1
weaponCrosshair.Visible = false
weaponCrosshair.Parent = crosshairCenterFrame

local centerDot = Instance.new("Frame")
centerDot.Name = "CenterDot"
centerDot.Size = UDim2.fromOffset(3, 3)
centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
centerDot.Position = UDim2.fromScale(0.5, 0.5)
centerDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
centerDot.BorderSizePixel = 0
centerDot.Parent = weaponCrosshair

local gap = 8
local lineLength = 10
local thickness = 2

local function createCrosshairLine(name: string, anchor: Vector2, posOffset: UDim2, size: UDim2)
	local line = Instance.new("Frame")
	line.Name = name
	line.AnchorPoint = anchor
	line.Position = UDim2.new(0.5, posOffset.X.Offset, 0.5, posOffset.Y.Offset)
	line.Size = size
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BorderSizePixel = 0
	line.Parent = weaponCrosshair
	return line
end

createCrosshairLine("Top", Vector2.new(0.5, 1), UDim2.fromOffset(0, -gap), UDim2.fromOffset(thickness, lineLength))
createCrosshairLine("Bottom", Vector2.new(0.5, 0), UDim2.fromOffset(0, gap), UDim2.fromOffset(thickness, lineLength))
createCrosshairLine("Left", Vector2.new(1, 0.5), UDim2.fromOffset(-gap, 0), UDim2.fromOffset(lineLength, thickness))
createCrosshairLine("Right", Vector2.new(0, 0.5), UDim2.fromOffset(gap, 0), UDim2.fromOffset(lineLength, thickness))

-- =========================================================================
-- 2. HITMARKER SYSTEM COMPONENTS (CENTER SCREEN & SLIM LINES)
-- =========================================================================
local hitmarkerFrame = Instance.new("Frame")
hitmarkerFrame.Name = "HitmarkerContainer"
hitmarkerFrame.Size = UDim2.fromOffset(20, 20)
hitmarkerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
hitmarkerFrame.Position = UDim2.fromScale(0.5, 0.5) 
hitmarkerFrame.BackgroundTransparency = 1
hitmarkerFrame.Visible = false
hitmarkerFrame.Parent = screenGui

local hitmarkerLines = {}
local lineAngles = {45, 135, 225, 315}

for i, angle in ipairs(lineAngles) do
	local line = Instance.new("Frame")
	line.Name = "HitmarkerLine" .. i
	line.Size = UDim2.fromOffset(6, 1)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.new(0.5, math.cos(math.rad(angle)) * 6, 0.5, math.sin(math.rad(angle)) * 6)
	line.Rotation = angle
	line.BorderSizePixel = 0
	line.Parent = hitmarkerFrame
	table.insert(hitmarkerLines, line)
end

local activeHitmarkerThread: thread? = nil

local function showHitmarker(isHeadshot: boolean)
	local markerColor = if isHeadshot then Color3.fromRGB(255, 35, 35) else Color3.fromRGB(255, 255, 255)

	for _, line in ipairs(hitmarkerLines) do
		line.BackgroundColor3 = markerColor
	end

	hitmarkerFrame.Visible = true

	if activeHitmarkerThread then
		task.cancel(activeHitmarkerThread)
	end

	activeHitmarkerThread = task.spawn(function()
		task.wait(0.1)
		hitmarkerFrame.Visible = false
	end)
end

hitmarkerEvent.OnClientEvent:Connect(showHitmarker)

-- =========================================================================
-- 3. AMMO & RELOAD UI SYSTEM COMPONENTS
-- =========================================================================
local ammoMainFrame = Instance.new("Frame")
ammoMainFrame.Name = "AmmoContainer"
ammoMainFrame.Size = UDim2.fromOffset(200, 75)
ammoMainFrame.AnchorPoint = Vector2.new(1, 1)
ammoMainFrame.Position = UDim2.new(1, -30, 1, -30)
ammoMainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
ammoMainFrame.BackgroundTransparency = 0.25
ammoMainFrame.BorderSizePixel = 0
ammoMainFrame.Visible = false
ammoMainFrame.Parent = screenGui

local ammoCorner = Instance.new("UICorner")
ammoCorner.CornerRadius = UDim.new(0, 6)
ammoCorner.Parent = ammoMainFrame

local ammoStroke = Instance.new("UIStroke")
ammoStroke.Color = Color3.fromRGB(255, 255, 255)
ammoStroke.Transparency = 0.85
ammoStroke.Thickness = 1
ammoStroke.Parent = ammoMainFrame

local weaponLabel = Instance.new("TextLabel")
weaponLabel.Name = "WeaponName"
weaponLabel.Size = UDim2.new(1, -20, 0, 16)
weaponLabel.Position = UDim2.fromOffset(10, 8)
weaponLabel.BackgroundTransparency = 1
weaponLabel.Font = Enum.Font.GothamBold
weaponLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
weaponLabel.TextSize = 12
weaponLabel.TextXAlignment = Enum.TextXAlignment.Left
weaponLabel.Text = "WEAPON"
weaponLabel.Parent = ammoMainFrame

local ammoLabel = Instance.new("TextLabel")
ammoLabel.Name = "AmmoDisplay"
ammoLabel.Size = UDim2.new(1, -20, 0, 32)
ammoLabel.Position = UDim2.fromOffset(10, 22)
ammoLabel.BackgroundTransparency = 1
ammoLabel.Font = Enum.Font.GothamBlack
ammoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ammoLabel.TextSize = 28
ammoLabel.TextXAlignment = Enum.TextXAlignment.Left
ammoLabel.Text = "30 / 30"
ammoLabel.Parent = ammoMainFrame

local reloadBarBg = Instance.new("Frame")
reloadBarBg.Name = "ReloadBarBackground"
reloadBarBg.Size = UDim2.new(1, -20, 0, 12)
reloadBarBg.Position = UDim2.fromOffset(10, 55)
reloadBarBg.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
reloadBarBg.BorderSizePixel = 0
reloadBarBg.Visible = false
reloadBarBg.Parent = ammoMainFrame

local reloadBarBgCorner = Instance.new("UICorner")
reloadBarBgCorner.CornerRadius = UDim.new(0, 3)
reloadBarBgCorner.Parent = reloadBarBg

local reloadBarFill = Instance.new("Frame")
reloadBarFill.Name = "Fill"
reloadBarFill.Size = UDim2.fromScale(0, 1)
reloadBarFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
reloadBarFill.BorderSizePixel = 0
reloadBarFill.Parent = reloadBarBg

local reloadBarFillCorner = Instance.new("UICorner")
reloadBarFillCorner.CornerRadius = UDim.new(0, 3)
reloadBarFillCorner.Parent = reloadBarBg

local reloadText = Instance.new("TextLabel")
reloadText.Name = "ReloadText"
reloadText.Size = UDim2.fromScale(1, 1)
reloadText.BackgroundTransparency = 1
reloadText.Font = Enum.Font.GothamBold
reloadText.TextColor3 = Color3.fromRGB(0, 0, 0)
reloadText.TextSize = 10
reloadText.ZIndex = 2
reloadText.Text = "RELOADING 0.0s"
reloadText.Parent = reloadBarBg

-- Fire Mode Indicator Container (Positioned horizontally right above Ammo Box)
local fireModeContainer = Instance.new("Frame")
fireModeContainer.Name = "FireModeContainer"
fireModeContainer.Size = UDim2.fromOffset(60, 16)
fireModeContainer.AnchorPoint = Vector2.new(1, 1)
fireModeContainer.Position = UDim2.new(1, -30, 1, -112)
fireModeContainer.BackgroundTransparency = 1
fireModeContainer.Visible = false
fireModeContainer.Parent = screenGui

local fireModeLayout = Instance.new("UIListLayout")
fireModeLayout.FillDirection = Enum.FillDirection.Horizontal
fireModeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
fireModeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
fireModeLayout.Padding = UDim.new(0, 4)
fireModeLayout.Parent = fireModeContainer

-- Create 3 Vertical Bars for Fire Modes (I I I)
local fireModeBars = {}
for i = 1, 3 do
	local bar = Instance.new("Frame")
	bar.Name = "Bar" .. i
	bar.Size = UDim2.fromOffset(4, 14)
	bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bar.BackgroundTransparency = 0.75
	bar.BorderSizePixel = 0
	bar.Parent = fireModeContainer

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 1)
	barCorner.Parent = bar

	table.insert(fireModeBars, bar)
end

-- Helper Function to Highlight Fire Mode Bars based on active mode
local function updateFireModeDisplay(mode: string?)
	local activeCount = 3

	if mode == "Semi" then
		activeCount = 1
	elseif mode == "Burst" then
		activeCount = 2
	elseif mode == "Auto" then
		activeCount = 3
	end

	for index, bar in ipairs(fireModeBars) do
		if index <= activeCount then
			bar.BackgroundTransparency = 0
		else
			bar.BackgroundTransparency = 0.75
		end
	end
end

-- =========================================================================
-- 4. UNIFIED STATE CONTROL & LISTENERS
-- =========================================================================
local activeTool = nil
local reloadConnection = nil
local attributeConnections = {}

local function cleanupConnections()
	if reloadConnection then
		reloadConnection:Disconnect()
		reloadConnection = nil
	end

	for _, conn in ipairs(attributeConnections) do
		conn:Disconnect()
	end
	table.clear(attributeConnections)
end

local function updateUI()
	if not activeTool then
		-- Unarmed State
		defaultCrosshair.Visible = true
		weaponCrosshair.Visible = false
		ammoMainFrame.Visible = false
		fireModeContainer.Visible = false
		return
	end

	-- Armed State
	defaultCrosshair.Visible = false
	weaponCrosshair.Visible = not isAiming
	ammoMainFrame.Visible = true
	fireModeContainer.Visible = true

	local currentMode = activeTool:GetAttribute("FireMode") or "Auto"
	updateFireModeDisplay(currentMode)

	weaponLabel.Text = string.upper(activeTool.Name)

	local config = getWeaponConfig(activeTool.Name)
	local maxAmmo = (config and config.AmmoPerMag) or 30
	local currentAmmo = activeTool:GetAttribute("Ammo")
	if currentAmmo == nil then
		currentAmmo = maxAmmo
	end

	ammoLabel.Text = string.format("%d / %d", currentAmmo, maxAmmo)

	local isReloading = activeTool:GetAttribute("IsReloading") == true

	if isReloading then
		if not reloadBarBg.Visible then
			reloadBarBg.Visible = true

			local reloadTime = (config and config.ReloadTime) or 2.5
			local startTime = os.clock()

			reloadBarFill.Size = UDim2.fromScale(0, 1)

			if reloadConnection then reloadConnection:Disconnect() end

			reloadConnection = RunService.RenderStepped:Connect(function()
				local elapsed = os.clock() - startTime
				local alpha = math.clamp(elapsed / reloadTime, 0, 1)
				local remaining = math.max(0, reloadTime - elapsed)

				reloadBarFill.Size = UDim2.fromScale(alpha, 1)
				reloadText.Text = string.format("RELOADING %.1fs", remaining)

				if alpha >= 1 then
					if reloadConnection then
						reloadConnection:Disconnect()
						reloadConnection = nil
					end
					reloadBarBg.Visible = false
				end
			end)
		end
	else
		if reloadConnection then
			reloadConnection:Disconnect()
			reloadConnection = nil
		end
		reloadBarBg.Visible = false
	end
end

-- Input Listeners for Aiming (Right Click)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isAiming = true
		updateUI()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isAiming = false
		updateUI()
	end
end)

local function onToolEquipped(tool: Tool)
	cleanupConnections()
	activeTool = tool

	table.insert(attributeConnections, tool:GetAttributeChangedSignal("Ammo"):Connect(updateUI))
	table.insert(attributeConnections, tool:GetAttributeChangedSignal("IsReloading"):Connect(updateUI))
	table.insert(attributeConnections, tool:GetAttributeChangedSignal("FireMode"):Connect(updateUI))

	updateUI()
end

local function onToolUnequipped()
	cleanupConnections()
	activeTool = nil
	isAiming = false
	updateUI()
end

local function setupCharacter(character: Model)
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		onToolEquipped(tool)
	else
		onToolUnequipped()
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolEquipped(child)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			onToolUnequipped()
		end
	end)
end

if localPlayer.Character then
	setupCharacter(localPlayer.Character)
end

localPlayer.CharacterAdded:Connect(setupCharacter)