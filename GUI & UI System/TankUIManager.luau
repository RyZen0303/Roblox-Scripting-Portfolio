-- // TankUIManager (Fixed HealthBar Streaming Bug & Isolated Center Reload Bar) //
-- Managed via StarterPlayerScripts
-- Handles Dynamic UI creation, Crosshair-to-World alignment logic, and Combat Stats

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled

-- // 1. COMMUNICATION SETUP //
local TankEvents = script.Parent:WaitForChild("TankEvents", 5) or Instance.new("Folder", script.Parent)
TankEvents.Name = "TankEvents"

local UIUpdateEvent = TankEvents:FindFirstChild("UIUpdate") or Instance.new("BindableEvent", TankEvents)
UIUpdateEvent.Name = "UIUpdate"

local TankCommandEvent = TankEvents:FindFirstChild("TankCommand") or Instance.new("BindableEvent", TankEvents)
TankCommandEvent.Name = "TankCommand"

-- // 2. GUI SETUP //
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TankControlGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false 
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Aim Toggle Button
local aimBtn = Instance.new("TextButton")
aimBtn.Name = "AimToggleButton"
aimBtn.Text = "FREE CAM: ON"
aimBtn.Size = UDim2.new(0, 150, 0, 30)
aimBtn.Position = UDim2.new(0.01, 0, 0.20, 0)
aimBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
aimBtn.BackgroundTransparency = 0.5
aimBtn.TextColor3 = Color3.new(1, 1, 1)
aimBtn.Font = Enum.Font.SourceSansBold
aimBtn.TextSize = 20
aimBtn.Parent = screenGui
Instance.new("UICorner", aimBtn)

-- Zoom Button
local zoomBtn = Instance.new("TextButton")
zoomBtn.Name = "ZoomButton"
zoomBtn.Text = "ZOOM: OFF"
zoomBtn.Size = UDim2.new(0, 75, 0, 75)
zoomBtn.Position = UDim2.new(0.85, 0, 0.3, 0)
zoomBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
zoomBtn.BackgroundTransparency = 0.5
zoomBtn.TextColor3 = Color3.new(1, 1, 1)
zoomBtn.Font = Enum.Font.SourceSansBold
zoomBtn.TextSize = 18
zoomBtn.Visible = false
zoomBtn.Parent = screenGui
local uiCornerZoom = Instance.new("UICorner", zoomBtn)
uiCornerZoom.CornerRadius = UDim.new(1, 0)

-- Fire Button
local fireBtn = Instance.new("TextButton")
fireBtn.Name = "FireButton"
fireBtn.Text = "FIRE"
fireBtn.Size = UDim2.new(0, 75, 0, 75)
fireBtn.Position = UDim2.new(0.75, 0, 0.55, 0)
fireBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
fireBtn.BackgroundTransparency = 0.5
fireBtn.TextColor3 = Color3.new(1, 1, 1)
fireBtn.Font = Enum.Font.SourceSansBold
fireBtn.TextSize = 24
fireBtn.Parent = screenGui
local uiCornerFire = Instance.new("UICorner", fireBtn)
uiCornerFire.CornerRadius = UDim.new(1, 0)

-- Crosshair UI
local crosshair = Instance.new("TextLabel")
crosshair.Name = "Crosshair"
crosshair.Text = "+"
crosshair.TextColor3 = Color3.new(0, 1, 0)
crosshair.BackgroundTransparency = 1
crosshair.Size = UDim2.new(0, 50, 0, 50)
crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.TextSize = 30
crosshair.Visible = false
crosshair.Parent = screenGui

-- Health Status Container (Stays at original top-left corner)
local healthContainer = Instance.new("Frame")
healthContainer.Name = "HealthContainer"
healthContainer.Size = UDim2.new(0, 150, 0, 25)
healthContainer.Position = UDim2.new(0.01, 0, 0.32, 0)
healthContainer.BackgroundTransparency = 1
healthContainer.Visible = false
healthContainer.Parent = screenGui

local icon = Instance.new("TextLabel", healthContainer)
icon.Text = "♥"
icon.TextColor3 = Color3.fromRGB(255, 50, 50)
icon.Size = UDim2.new(0, 25, 1, 0)
icon.BackgroundTransparency = 1
icon.Font = Enum.Font.SourceSansBold
icon.TextSize = 20

local barBg = Instance.new("Frame", healthContainer)
barBg.Name = "BarBackground"
barBg.Size = UDim2.new(0, 120, 0, 15)
barBg.Position = UDim2.new(0.2, 0, 0.2, 0)
barBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
barBg.BackgroundTransparency = 0.6
barBg.BorderSizePixel = 0

local barFill = Instance.new("Frame", barBg)
barFill.Name = "BarFill"
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
barFill.BorderSizePixel = 0

-- [[ FIXED: Text parented to barBg to prevent scaling artifacts, Text color set to PURE BLACK ]]
local healthText = Instance.new("TextLabel", barBg) -- Parented to barBg so it remains static and doesn't shrink with the health bar
healthText.Size = UDim2.new(1, 0, 1, 0)
healthText.BackgroundTransparency = 1
healthText.TextColor3 = Color3.new(255, 255, 255) -- 💥 Changed text color to pure black as requested
healthText.Font = Enum.Font.SourceSansBold
healthText.TextSize = 12
healthText.ZIndex = 3 -- Brought to the topmost layer to ensure it isn't hidden by the red bar
healthText.Text = "100 / 100"

-- [[ ISOLATED CENTER RELOAD BAR ]]
-- Parented to the tank control ScreenGui so it hides when the player exits the tank.
local reloadBg = Instance.new("Frame")
reloadBg.Name = "ReloadBackground"
reloadBg.Size = UDim2.new(0, 150, 0, 4) -- Clean sleek 150px layout
reloadBg.BorderSizePixel = 0
reloadBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0) -- Pure black track
reloadBg.BackgroundTransparency = 0.7 -- Translucent look when depleted
reloadBg.Visible = false -- Shown while seated or while the tracked tank is reloading.

-- Anchored and centered perfectly at the lower third of the viewport
reloadBg.Position = UDim2.new(0.5, 0, 0.9, 0) 
reloadBg.AnchorPoint = Vector2.new(0.5, 0.5)
reloadBg.Parent = screenGui

local reloadFill = Instance.new("Frame", reloadBg)
reloadFill.Name = "ReloadFill"
reloadFill.Size = UDim2.new(1, 0, 1, 0) -- Initially spawns filled (ready to fire)
reloadFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- Tactical solid white bar
reloadFill.BorderSizePixel = 0

-- [[ FOLDABLE TACTICAL CONTROL GUIDE HUD (ULTRA COMPACT & RE-POSITIONED) ]]
-- Optimized size and heightened Y-axis position to prevent screen edge clipping based on image_dcb34a.jpg
local controlHelpBg = Instance.new("Frame")
controlHelpBg.Name = "ControlHelpBackground"
controlHelpBg.Size = UDim2.new(0, 120, 0, 20) -- Ultra-compact starting size (120x20px)
controlHelpBg.Position = UDim2.new(0.5, 0, 1, 0)
controlHelpBg.AnchorPoint = Vector2.new(0.5, 1)
controlHelpBg.BackgroundColor3 = Color3.fromRGB(0, 40, 10)
controlHelpBg.BackgroundTransparency = 0.5
controlHelpBg.BorderSizePixel = 0
controlHelpBg.ClipsDescendants = true
controlHelpBg.Parent = screenGui

local uiCornerHelp = Instance.new("UICorner", controlHelpBg)
uiCornerHelp.CornerRadius = UDim.new(0, 4)

-- 1. HEADER TOGGLE BUTTON (Smaller, clean typography)
local toggleHelpBtn = Instance.new("TextButton")
toggleHelpBtn.Name = "ToggleHelpButton"
toggleHelpBtn.Size = UDim2.new(1, 0, 0, 20)
toggleHelpBtn.BackgroundTransparency = 1
toggleHelpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleHelpBtn.Font = Enum.Font.SourceSansBold
toggleHelpBtn.TextSize = 12 -- Reduced font size for micro appearance
toggleHelpBtn.Text = "[ + ] CONTROLS"
toggleHelpBtn.Parent = controlHelpBg

-- 2. CONTENT CONTAINER
local helpContentFrame = Instance.new("Frame")
helpContentFrame.Name = "HelpContentFrame"
helpContentFrame.Size = UDim2.new(1, 0, 0, 60)
helpContentFrame.Position = UDim2.new(0, 0, 0, 20)
helpContentFrame.BackgroundTransparency = 1
helpContentFrame.BorderSizePixel = 0
helpContentFrame.Parent = controlHelpBg

local uiList = Instance.new("UIListLayout", helpContentFrame)
uiList.SortOrder = Enum.SortOrder.LayoutOrder
uiList.Padding = UDim.new(0, 2)
uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- Helper function to generate micro vertical line entries securely
local function createHelpLine(text, order)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.85, 0, 0, 16) -- Micro height line
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = order
	label.Parent = helpContentFrame
end

-- Generate compact multi-line entries
createHelpLine("• Fire/M1 = [ F ]", 1)
createHelpLine("• Zoom    = [ X ]", 2)
createHelpLine("• Aim/Cam = [ L ]", 3)

-- 3. INTERACTION LOGIC (Smooth size tween transitions)
local TweenService = game:GetService("TweenService")
local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local isHelpOpen = false

toggleHelpBtn.MouseButton1Click:Connect(function()
	isHelpOpen = not isHelpOpen

	-- Open height matches the text contents, close height shrinks back to header standard
	local targetSize = isHelpOpen and UDim2.new(0, 120, 0, 80) or UDim2.new(0, 120, 0, 20)
	toggleHelpBtn.Text = isHelpOpen and "[ - ] CONTROLS" or "[ + ] CONTROLS"

	TweenService:Create(controlHelpBg, tweenInfo, {Size = targetSize}):Play()
end)

-- // 3. MOBILE DRIVE CONTROLS (WASD) //
local driveFrame = Instance.new("Frame")
driveFrame.Name = "DriveFrame"
driveFrame.Size = UDim2.new(0, 200, 0, 200)
driveFrame.Position = UDim2.new(0, 0.025, 0.4, 0) 
driveFrame.BackgroundTransparency = 1
driveFrame.Visible = isTouch
driveFrame.Active = false 
driveFrame.Parent = screenGui

local function createDriveBtn(name, text, pos)
	local btn = Instance.new("TextButton")
	btn.Name = name .. "Button"
	btn.Text = text
	btn.Size = UDim2.new(0, 60, 0, 60)
	btn.Position = pos
	btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	btn.BackgroundTransparency = 0.5
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.SourceSansBold
	btn.TextSize = 24
	btn.Active = true
	btn.Parent = driveFrame
	Instance.new("UICorner", btn)

	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			UIUpdateEvent:Fire({Type = "DriveInput", Key = name, State = true})
			btn.BackgroundTransparency = 0.2 
		end
	end)

	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			UIUpdateEvent:Fire({Type = "DriveInput", Key = name, State = false})
			btn.BackgroundTransparency = 0.5
		end
	end)

	return btn
end

local btnW = createDriveBtn("W", "▲", UDim2.new(0.35, 0, 0, 0))
local btnA = createDriveBtn("A", "◀", UDim2.new(0, 0, 0.35, 0))
local btnS = createDriveBtn("S", "▼", UDim2.new(0.35, 0, 0.7, 0))
local btnD = createDriveBtn("D", "▶", UDim2.new(0.7, 0, 0.35, 0))

-- // 4. UI UPDATE LOGIC //
UIUpdateEvent.Event:Connect(function(data)
	if data.Type == "ToggleScreen" then
		screenGui.Enabled = data.Value
	elseif data.Type == "UpdateAimMode" then
		aimBtn.Text = data.IsFreeCam and "FREE CAM: ON" or "AIMING: LOCK"
		aimBtn.BackgroundColor3 = data.IsFreeCam and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(200, 0, 0)
		crosshair.Visible = not data.IsFreeCam
	elseif data.Type == "UpdateZoomValue" then
		local isZoomedActive = data.Value < 70
		zoomBtn.Text = isZoomedActive and "ZOOM: ON" or "ZOOM: OFF"
		zoomBtn.BackgroundColor3 = isZoomedActive and Color3.fromRGB(0, 150, 0) or Color3.fromRGB(0, 0, 0)
	elseif data.Type == "MobileButtons" then
		fireBtn.Visible = isTouch
		zoomBtn.Visible = isTouch and not data.IsFreeCam
		aimBtn.Visible = true
		driveFrame.Visible = isTouch
	end
end)

-- // TANK HEALTH & WEAPON STATUS TRACKING //
local currentTrackingConnection = nil
local currentReloadConnection = nil
local currentTrackedTank = nil
local isTankSeated = false

local function setupHealthTracking(tankModel)
	-- Disconnect previous listeners to prevent memory leaks and thread overlap
	if currentTrackingConnection then currentTrackingConnection:Disconnect() currentTrackingConnection = nil end
	if currentReloadConnection then currentReloadConnection:Disconnect() currentReloadConnection = nil end

	currentTrackedTank = tankModel
	isTankSeated = true
	healthContainer.Visible = false
	reloadBg.Visible = false

	-- Updates the Core Structural Health Gauge
	local function updateBar()
		local currentH = tankModel:GetAttribute("Health")
		local maxH = tankModel:GetAttribute("MaxHealth")

		if not currentH or not maxH then return end

		local percent = math.clamp(currentH / maxH, 0, 1)
		barFill:TweenSize(UDim2.new(percent, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, 0.1, true)
		barFill.BackgroundColor3 = percent > 0.3 and Color3.fromRGB(200, 0, 0) or Color3.fromRGB(150, 0, 0)
		healthText.Text = math.floor(currentH) .. " / " .. maxH
	end

	-- Updates the Main Cannon Reload Indicator (Tactical Center Bar)
	local function updateReload()
		local reloadTime = tankModel:GetAttribute("ReloadTime")
		local maxReload = tankModel:GetAttribute("MaxReloadTime") or 3

		if reloadTime == nil then
			reloadBg.Visible = isTankSeated
			if not isTankSeated and currentReloadConnection then
				currentReloadConnection:Disconnect()
				currentReloadConnection = nil
			end
			return
		end

		reloadBg.Visible = isTankSeated or reloadTime > 0

		if reloadTime > 0 then
			-- System Reloading: Fills from left to right as time depletes
			local percent = math.clamp(1 - (reloadTime / maxReload), 0, 1)
			reloadFill:TweenSize(UDim2.new(percent, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, 0.05, true)
			reloadFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		else
			-- Reload Complete: Locks into full bar state while seated.
			reloadFill:TweenSize(UDim2.new(1, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, 0.05, true)
			reloadFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			if not isTankSeated then
				reloadBg.Visible = false
				if currentReloadConnection then
					currentReloadConnection:Disconnect()
					currentReloadConnection = nil
				end
			end
		end
	end

	-- Sync each UI independently: reload progress must not wait for health attributes.
	currentTrackingConnection = tankModel:GetAttributeChangedSignal("Health"):Connect(function()
		local hasHealth = tankModel:GetAttribute("Health") ~= nil
		healthContainer.Visible = isTankSeated and hasHealth
		updateBar()
	end)
	currentReloadConnection = tankModel:GetAttributeChangedSignal("ReloadTime"):Connect(updateReload)

	healthContainer.Visible = isTankSeated and tankModel:GetAttribute("Health") ~= nil
	updateBar()
	updateReload()
end

-- // SEAT DETECTION LOGIC //
local function onSeatedChanged(isSeated, seat)
	if isSeated and seat and seat:IsA("Seat") then
		local tankModel = seat:FindFirstAncestorWhichIsA("Model")
		if tankModel then
			setupHealthTracking(tankModel)
		else
			warn("TankUIManager: Seat detected, but NO Model found as an ancestor!")
		end
	else
		-- Hide tank UI on exit. ReloadTime is read again immediately if the player re-enters.
		isTankSeated = false
		healthContainer.Visible = false
		reloadBg.Visible = false
		if currentTrackingConnection then currentTrackingConnection:Disconnect() currentTrackingConnection = nil end
		if currentReloadConnection then currentReloadConnection:Disconnect() currentReloadConnection = nil end
	end
end

-- Securely bind the active monitoring architecture to character mutations
local function hookHumanoid(char)
	local humanoid = char:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Seated:Connect(onSeatedChanged)
		if humanoid.SeatPart then
			onSeatedChanged(true, humanoid.SeatPart)
		end
	end
end

player.CharacterAdded:Connect(hookHumanoid)
if player.Character then hookHumanoid(player.Character) end

-- // 5. UI INPUT PASS-THROUGH //
aimBtn.MouseButton1Click:Connect(function() 
	TankCommandEvent:Fire({Type = "TriggerAim"}) 
end)

fireBtn.Activated:Connect(function()
	TankCommandEvent:Fire({Type = "TriggerFire", State = true, IsExternal = true})
	task.wait(0.1) 
	TankCommandEvent:Fire({Type = "TriggerFire", State = false, IsExternal = true})
end)

zoomBtn.MouseButton1Click:Connect(function()
	TankCommandEvent:Fire({Type = "TriggerZoom"})
end)

