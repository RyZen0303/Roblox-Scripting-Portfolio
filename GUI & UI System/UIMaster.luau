-- // UIMaster Module //
-- Location: ReplicatedStorage / UIMaster
-- Description: Unified UI Controller Framework handling layout, page setup, 
--              server remote listeners, pad bounds, and streaming previews.

local UIMaster = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

-- [[ 1. SERVER UI TOGGLE EVENT LISTENER (From File 1) ]]
task.spawn(function()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then return end

	local openUIEvent = eventsFolder:WaitForChild("OpenUI", 10)
	if openUIEvent then
		openUIEvent.OnClientEvent:Connect(function(guiName, context)
			UIMaster.Open(guiName, context)
		end)
	end
end)

function UIMaster.Open(guiName, context)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(guiName)

	if not gui then
		warn("[UIMaster] GUI not found: " .. tostring(guiName))
		return
	end

	if context and context.Close then
		UIMaster.Close(gui)
		return
	end

	if guiName == "TankSelectionUI" then
		local player = Players.LocalPlayer
		local playerTeam = player.Team and player.Team.Name

		-- A TankSelectionUI open must carry the server-approved pad context.
		if not context or not context.CurrentPad or not playerTeam
			or context.Team ~= playerTeam then
			UIMaster.Close(gui)
			return
		end

		-- Recheck the exact zone named by the server, not a recursive pad-name
		-- search that can accidentally resolve a different pad with the same name.
		if context.RequiresCapture then
			local captureZones = workspace:FindFirstChild("CaptureZones")
			local captureZone = captureZones and context.CaptureZone
				and captureZones:FindFirstChild(context.CaptureZone)

			if not captureZone or captureZone:GetAttribute("Owner") ~= playerTeam then
				UIMaster.Close(gui)
				return
			end
		end
	end

	if context then
		for attributeName, value in pairs(context) do
			gui:SetAttribute(attributeName, value)
		end
	end

	gui.Enabled = true
end

function UIMaster.Close(gui)
	if not gui then return end
	gui.Enabled = false
	gui:SetAttribute("CurrentPad", nil)
	gui:SetAttribute("Team", nil)
	gui:SetAttribute("RequiresCapture", nil)
	gui:SetAttribute("CaptureZone", nil)
end

-- [[ 2. CORE LAYOUT & NAVIGATION CONSTRAINTS ]]

function UIMaster.InitCenter(gui, mainFrame)
	gui.IgnoreGuiInset = true 
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5) 
	mainFrame.Position = UDim2.new(0.5, 0, 0.54, 0) 
end

function UIMaster.SetupPages(pages, categories, defaultCategory)
	local defaultName = defaultCategory or "Light"

	local function showPage(categoryName)
		for name, page in pairs(pages) do
			if page:IsA("GuiObject") then
				page.Visible = (name == categoryName)
			end
		end
	end

	for name, button in pairs(categories) do
		if button and button:IsA("GuiButton") then
			button.MouseButton1Click:Connect(function() showPage(name) end)
		end
	end

	showPage(defaultName)
	return defaultName
end

function UIMaster.SelectDefault(pageFrame, callback)
	if not pageFrame then return end

	local firstButton = nil
	for _, child in ipairs(pageFrame:GetChildren()) do
		if child:IsA("GuiButton") and child.Visible then
			firstButton = child
			break
		end
	end

	if firstButton and callback then
		callback(firstButton)
	end
end

-- [[ 3. PHYSICAL PAD TOUCH SYSTEM (Unified & Cleaned) ]]

function UIMaster.ConnectPads(gui, onOpenCallback, padNames)
	local player = Players.LocalPlayer
	local debounce = false

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			local isMatch = false
			for _, name in ipairs(padNames) do
				if obj.Name == name then 
					isMatch = true 
					break 
				end
			end

			if isMatch then
				obj.Touched:Connect(function(hit)
					if debounce or gui.Enabled then return end

					local character = player.Character
					if character and hit:IsDescendantOf(character) then
						-- Team Security Check directly on pad
						local padTeam = obj:GetAttribute("Team")
						local playerTeam = player.Team and player.Team.Name

						if padTeam and padTeam ~= "Neutral" and padTeam ~= playerTeam then
							return -- Ignore touch if pad is for another team
						end

						debounce = true
						gui:SetAttribute("CurrentPad", obj.Name)
						gui.Enabled = true

						if onOpenCallback then 
							onOpenCallback(obj) 
						end

						task.wait(1.5)
						debounce = false
					end
				end)
			end
		end
	end
end

-- [[ 4. DATA & LEADERSTATS SYNC ]]

function UIMaster.SyncLeaderstats(player, label)
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats", 10)
		local p = stats and stats:WaitForChild("Points", 10)
		if not p then return end
		local function update()
			if label and label.Parent then label.Text = "Points: " .. tostring(p.Value) end
		end
		p:GetPropertyChangedSignal("Value"):Connect(update)
		update()
	end)
end

-- [[ 5. STREAMING-SAFE PREVIEW RENDERER ]]

function UIMaster.RenderPreview(assetName, tanksFolder, imageLabel, costLabel, selectedAddOn)
	if assetName == "" then
		if costLabel then costLabel.Text = "Cost: --" end
		if imageLabel then imageLabel.Image = "rbxassetid://0" end
		return
	end

	local previewID = "rbxassetid://0"
	local totalCost = 0
	local isSpawnPoint = false
	local targetAsset = nil

	local player = Players.LocalPlayer
	local captureZones = workspace:WaitForChild("CaptureZones", 5)

	if assetName == "MainBase" then
		local playerTeam = player.Team and player.Team.Name or ""
		if playerTeam == "Germany" then
			targetAsset = workspace:WaitForChild("GermanyBase", 3)
		elseif playerTeam == "Britain" or playerTeam == "Great Britain" then
			targetAsset = workspace:WaitForChild("BritainBase", 3)
		else
			targetAsset = workspace:FindFirstChild("GermanyBase") or workspace:FindFirstChild("BritainBase")
		end
		isSpawnPoint = true
	elseif string.find(assetName, " Point") then
		local cleanZoneName = string.gsub(assetName, " Point", "")
		if captureZones then
			targetAsset = captureZones:WaitForChild(cleanZoneName, 3)
		end
		isSpawnPoint = true
	end

	if targetAsset then
		previewID = targetAsset:GetAttribute("PreviewID") or "rbxassetid://0"
	else
		local tankTemplate = tanksFolder and tanksFolder:FindFirstChild(assetName)
		if tankTemplate then
			local baseCost = tankTemplate:GetAttribute("Cost") or 0
			previewID = tankTemplate:GetAttribute("PreviewID") or "rbxassetid://0"

			local addOnSurcharge = 0
			if selectedAddOn == "Sandbags" then
				addOnSurcharge = 1
			elseif selectedAddOn == "Both" then
				addOnSurcharge = 2
			end
			totalCost = baseCost + addOnSurcharge
		end
	end

	if imageLabel then 
		imageLabel.Image = previewID 
	end

	if costLabel then
		if isSpawnPoint then
			costLabel.Text = "Cost: Free"
		else
			costLabel.Text = "Cost: " .. tostring(totalCost)
		end
	end
end

function UIMaster.BindCostListener(tankName, tanksFolder, onRefreshCallback)
	if tankName == "" then return nil end
	local tankTemplate = tanksFolder:FindFirstChild(tankName)
	if tankTemplate then
		return tankTemplate:GetAttributeChangedSignal("Cost"):Connect(onRefreshCallback)
	end
	return nil
end

function UIMaster.PreloadTankPreviews(tanksFolder)
	task.spawn(function()
		local assetsToLoad = {}
		for _, tank in ipairs(tanksFolder:GetChildren()) do
			local previewID = tank:GetAttribute("PreviewID")
			if previewID and previewID ~= "" then
				local temp = Instance.new("ImageLabel")
				temp.Image = previewID
				table.insert(assetsToLoad, temp)
			end
		end
		if #assetsToLoad > 0 then 
			ContentProvider:PreloadAsync(assetsToLoad) 
		end
	end)
end

function UIMaster.PreloadMapPreviews()
	task.spawn(function()
		local assetsToLoad = {}
		local captureZones = workspace:WaitForChild("CaptureZones", 10)

		local bases = {"GermanyBase", "BritainBase"}
		for _, baseName in ipairs(bases) do
			local basePart = workspace:WaitForChild(baseName, 5)
			local previewID = basePart and basePart:GetAttribute("PreviewID")
			if previewID and previewID ~= "" then
				local temp = Instance.new("ImageLabel")
				temp.Image = previewID
				table.insert(assetsToLoad, temp)
			end
		end

		if captureZones then
			for _, zone in ipairs(captureZones:GetChildren()) do
				local previewID = zone:GetAttribute("PreviewID")
				if previewID and previewID ~= "" then
					local temp = Instance.new("ImageLabel")
					temp.Image = previewID
					table.insert(assetsToLoad, temp)
				end
			end
		end

		if #assetsToLoad > 0 then
			ContentProvider:PreloadAsync(assetsToLoad)
		end
	end)
end

return UIMaster
