-- [[ TANK SELECTION UI CONTROLLER - CENTRALIZED UIMASTER ]] --
-- Location: StarterGui / TankSelectionUI / TankSelectionUIController
-- Description: Handles live button inputs, popups, and bridges data rendering into UIMaster.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIMaster = require(ReplicatedStorage:WaitForChild("UIMaster"))

local player = game.Players.LocalPlayer
local mainFrame = script.Parent
local gui = mainFrame.Parent

-- Start closed before any WaitForChild can yield. The server may authorize an
-- opening later through UIMaster after it has attached the pad context.
gui.Enabled = false

local function hasAuthorizedPadContext()
	local playerTeam = player.Team and player.Team.Name
	local padName = gui:GetAttribute("CurrentPad")
	local contextTeam = gui:GetAttribute("Team")
	local requiresCapture = gui:GetAttribute("RequiresCapture")

	if not playerTeam or contextTeam ~= playerTeam
		or typeof(padName) ~= "string" or padName == ""
		or typeof(requiresCapture) ~= "boolean" then
		return false
	end

	if requiresCapture then
		local captureZones = workspace:FindFirstChild("CaptureZones")
		local zoneName = gui:GetAttribute("CaptureZone")
		local zone = captureZones and typeof(zoneName) == "string"
			and captureZones:FindFirstChild(zoneName)

		if not zone or zone:GetAttribute("Owner") ~= playerTeam then
			return false
		end

		local pad = zone:FindFirstChild(padName, true)
		return pad ~= nil
			and pad:IsA("BasePart")
			and pad:GetAttribute("Team") == playerTeam
	end

	-- A non-capture TankSelectionUI is only valid inside a permanent base.
	-- Do not use a workspace-wide recursive name lookup as authorization.
	for _, candidate in ipairs(workspace:GetDescendants()) do
		if candidate:IsA("BasePart") and candidate.Name == padName then
			local current = candidate
			while current and current ~= workspace do
				if current.Name == "MainBase" then
					local requiredTeam = candidate:GetAttribute("Team")
					if not requiredTeam or requiredTeam == "Neutral" or requiredTeam == playerTeam then
						return true
					end
					break
				elseif current.Name == "GermanyBase" then
					if playerTeam == "Germany" then return true end
					break
				elseif current.Name == "BritainBase" then
					if playerTeam == "Britain" then return true end
					break
				end
				current = current.Parent
			end
		end
	end

	return false
end

-- Initialize framework centering constraints via centralized module
UIMaster.InitCenter(gui, mainFrame)

local function getUI(parent, name)
	local obj = parent:FindFirstChild(name)
	if not obj then warn(" Missing UI Element: " .. name .. " in " .. parent.Name) end
	return obj
end

local tankList = getUI(mainFrame, "TankList")
local categories = getUI(mainFrame, "Categories")
local leftPanel = getUI(mainFrame, "LeftPanel")
local spawnBtn = getUI(leftPanel, "SpawnButton")
local closeBtn = mainFrame:WaitForChild("CloseButton")
local tankImageLabel = getUI(leftPanel, "ImageLabel")
local pointsLabel = (closeBtn and closeBtn:FindFirstChild("PointsLabel"))

local addonTemplate = mainFrame:WaitForChild("AddonTemplate")
local sandbagsBtn = addonTemplate and getUI(addonTemplate, "Sandbags_Button")
local bothBtn = addonTemplate and getUI(addonTemplate, "Sandbags+Logs_Button")

local TanksFolder = ReplicatedStorage:WaitForChild("Tanks")
local EventsFolder = ReplicatedStorage:WaitForChild("Events")

local selectedTankName = ""
local selectedAddOn = "None"
local buttonConnections = {}
local activeCostLabel = nil
local costConnection = nil

local lastActivePage = nil
local activeMarkerLayoutOrder = nil

local updateCostDisplay

local function updateAddonTexts()
	if not sandbagsBtn or not bothBtn then return end
	if selectedAddOn == "Sandbags" then
		sandbagsBtn.Text = "[X] Sandbags"
		bothBtn.Text = "[] Sandbags + Logs"
	elseif selectedAddOn == "Both" then
		sandbagsBtn.Text = "[] Sandbags"
		bothBtn.Text = "[X] Sandbags + Logs"
	else
		sandbagsBtn.Text = "[] Sandbags"
		bothBtn.Text = "[] Sandbags + Logs"
	end
end

local function clearConnections()
	for _, conn in ipairs(buttonConnections) do conn:Disconnect() end
	buttonConnections = {}
	if costConnection then
		costConnection:Disconnect()
		costConnection = nil
	end
end

local function hideAddon()
	if addonTemplate and addonTemplate.Visible then
		addonTemplate.Visible = false
		addonTemplate.Parent = mainFrame

		if lastActivePage and activeMarkerLayoutOrder then
			for _, child in ipairs(lastActivePage:GetChildren()) do
				if child:IsA("GuiButton") and child.LayoutOrder > activeMarkerLayoutOrder then
					child.LayoutOrder = child.LayoutOrder - 1
				end
			end
		end
	end
	lastActivePage = nil
	activeMarkerLayoutOrder = nil
end

local function attachAddonToButton(targetButton)
	if not addonTemplate then return end
	hideAddon()

	local page = targetButton.Parent
	if not page then return end

	lastActivePage = page
	activeMarkerLayoutOrder = targetButton.LayoutOrder

	for _, child in ipairs(page:GetChildren()) do
		if child:IsA("GuiButton") and child.LayoutOrder > targetButton.LayoutOrder then
			child.LayoutOrder = child.LayoutOrder + 1
		end
	end

	local layoutSpacer = page:FindFirstChild("AddonLayoutSpacer")
	if not layoutSpacer then
		layoutSpacer = Instance.new("Frame")
		layoutSpacer.Name = "AddonLayoutSpacer"
		layoutSpacer.BackgroundTransparency = 1
		layoutSpacer.Size = UDim2.new(targetButton.Size.X.Scale, targetButton.Size.X.Offset, 0, addonTemplate.Size.Y.Offset)
	end
	layoutSpacer.Parent = page
	layoutSpacer.LayoutOrder = targetButton.LayoutOrder + 1
	layoutSpacer.Visible = true

	addonTemplate.Parent = mainFrame

	local buttonAbsolutePos = targetButton.AbsolutePosition
	local frameAbsolutePos = mainFrame.AbsolutePosition
	local relativeX = buttonAbsolutePos.X - frameAbsolutePos.X
	local relativeY = buttonAbsolutePos.Y - frameAbsolutePos.Y

	addonTemplate.Position = UDim2.new(0, relativeX, 0, relativeY + targetButton.AbsoluteSize.Y + 5)
	addonTemplate.Visible = true

	local runServiceConnection
	runServiceConnection = game:GetService("RunService").RenderStepped:Connect(function()
		if not addonTemplate.Visible or addonTemplate.Parent ~= mainFrame or not targetButton:IsDescendantOf(gui) then
			if runServiceConnection then runServiceConnection:Disconnect() end
			if layoutSpacer then layoutSpacer.Visible = false end
			return
		end
		local liveBtnPos = targetButton.AbsolutePosition
		local liveFramePos = mainFrame.AbsolutePosition
		addonTemplate.Position = UDim2.new(0, liveBtnPos.X - liveFramePos.X, 0, liveBtnPos.Y - liveFramePos.Y + targetButton.AbsoluteSize.Y + 5)
	end)
end

function updateCostDisplay(tankName)
	if costConnection then costConnection:Disconnect() end
	UIMaster.RenderPreview(tankName, TanksFolder, tankImageLabel, activeCostLabel, selectedAddOn)
	costConnection = UIMaster.BindCostListener(tankName, TanksFolder, function()
		UIMaster.RenderPreview(tankName, TanksFolder, tankImageLabel, activeCostLabel, selectedAddOn)
	end)
end

-- [[  FIXED NATION DETECTOR: TRUST THE ACTUAL PLAYER TEAM ]] --
local function updateNationUI()
	local currentTeam = player.Team and player.Team.Name or "Germany"

	if tankList then
		for _, nation in ipairs(tankList:GetChildren()) do
			if nation:IsA("Frame") then
				nation.Visible = (nation.Name == currentTeam)
			end
		end
	end

	local nationFrame = tankList and tankList:FindFirstChild(currentTeam)
	if not nationFrame then return end

	activeCostLabel = nationFrame:FindFirstChild("CostLabel")

	hideAddon()
	clearConnections()

	local pages = {
		["Heavy"] = nationFrame:FindFirstChild("HeavyPage"),
		["Medium"] = nationFrame:FindFirstChild("MediumPage"),
		["Light"] = nationFrame:FindFirstChild("LightPage")
	}

	local defaultPageName = UIMaster.SetupPages(pages, {
		["Heavy"] = categories and categories:FindFirstChild("Heavy"),
		["Medium"] = categories and categories:FindFirstChild("Medium"),
		["Light"] = categories and categories:FindFirstChild("Light")
	}, "Light")

	if categories then
		for _, catButton in ipairs(categories:GetChildren()) do
			if catButton:IsA("GuiButton") then
				local catConn = catButton.MouseButton1Click:Connect(function()
					hideAddon()
				end)
				table.insert(buttonConnections, catConn)
			end
		end
	end

	for _, page in pairs(pages) do
		if page then
			for _, button in ipairs(page:GetChildren()) do
				if button:IsA("GuiButton") then
					local conn = button.MouseButton1Click:Connect(function()
						local targetName = string.gsub(button.Name, "_Button", "")

						if addonTemplate then
							if addonTemplate.Visible and selectedTankName == targetName then
								hideAddon()
								selectedAddOn = "None"
							else
								selectedTankName = targetName
								selectedAddOn = "None"
								attachAddonToButton(button)
							end
							updateAddonTexts()
						else
							selectedTankName = targetName
						end

						updateCostDisplay(selectedTankName)
					end)
					table.insert(buttonConnections, conn)
				end
			end
		end
	end

	local defaultPageFrame = pages[defaultPageName]
	if defaultPageFrame then
		UIMaster.SelectDefault(defaultPageFrame, function(btn)
			selectedTankName = string.gsub(btn.Name, "_Button", "")
			selectedAddOn = "None"
			updateCostDisplay(selectedTankName)

			if addonTemplate then
				attachAddonToButton(btn)
				updateAddonTexts()
			end
		end)
	else
		selectedTankName = ""
		selectedAddOn = "None"
		updateCostDisplay(selectedTankName)
		hideAddon()
	end
end

if sandbagsBtn then
	sandbagsBtn.MouseButton1Click:Connect(function()
		selectedAddOn = (selectedAddOn == "Sandbags") and "None" or "Sandbags"
		updateAddonTexts()
		updateCostDisplay(selectedTankName)
	end)
end

if bothBtn then
	bothBtn.MouseButton1Click:Connect(function()
		selectedAddOn = (selectedAddOn == "Both") and "None" or "Both"
		updateAddonTexts()
		updateCostDisplay(selectedTankName)
	end)
end

if spawnBtn then
	spawnBtn.MouseButton1Click:Connect(function()
		local padName = gui:GetAttribute("CurrentPad")
		local padPart = padName and workspace:FindFirstChild(padName, true)

		if selectedTankName ~= "" and padPart then
			local spawnFunction = EventsFolder:WaitForChild("RequestTankSpawnFunction")
			local success = spawnFunction:InvokeServer("SpawnTank", selectedTankName, padPart, selectedAddOn)

			if success then
				UIMaster.Close(gui)
				selectedTankName = ""
				selectedAddOn = "None"
				hideAddon()
			else
				warn("Spawn rejected by server.")
			end
		end
	end)
end

if closeBtn then
	closeBtn.MouseButton1Click:Connect(function()
		UIMaster.Close(gui)
		hideAddon()
	end)
end

if pointsLabel then
	UIMaster.SyncLeaderstats(player, pointsLabel)
end

-- [[  ADD THIS TO CLIENT CONTROLLER FOR INSTANT FACTION REFLECT ]] --
-- Trigger instant UI refresh whenever the player's engine-level team changes
player:GetPropertyChangedSignal("Team"):Connect(updateNationUI)

-- Enabled is a property, not an attribute. Guard every opening path, including
-- any accidental direct gui.Enabled = true outside UIMaster.
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		if not hasAuthorizedPadContext() then
			warn("[TankSelectionUI] Rejected opening without valid server pad/ownership context.")
			UIMaster.Close(gui)
			return
		end
		updateNationUI()
	else
		hideAddon()
	end
end)

-- The server event can arrive while this LocalScript is still initializing.
-- Validate once after installing the property listener to cover that race too.
if gui.Enabled and not hasAuthorizedPadContext() then
	UIMaster.Close(gui)
end

updateNationUI()

UIMaster.PreloadTankPreviews(TanksFolder)
