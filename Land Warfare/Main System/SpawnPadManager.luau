-- // ServerScript: Secure UI Pad Interaction Manager //
-- Location: ServerScriptService / SpawnPadManager
-- Description: Handles physical UI pads on the server, validates access,
--              then tells the client which UI is allowed to open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GameLogic = require(ReplicatedStorage:WaitForChild("GameLogic"))

local eventsFolder = ReplicatedStorage:FindFirstChild("Events")

if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

local openUIEvent = eventsFolder:FindFirstChild("OpenUI")

if not openUIEvent then
	openUIEvent = Instance.new("RemoteEvent")
	openUIEvent.Name = "OpenUI"
	openUIEvent.Parent = eventsFolder
end

-- The client SpawnMessageController waits for this RemoteEvent.
local showSpawnMessageEvent = eventsFolder:FindFirstChild("ShowSpawnMessageEvent")

if not showSpawnMessageEvent then
	showSpawnMessageEvent = Instance.new("RemoteEvent")
	showSpawnMessageEvent.Name = "ShowSpawnMessageEvent"
	showSpawnMessageEvent.Parent = eventsFolder
end

local interactionDebounce = {}

local function debounceInteraction(player)
	interactionDebounce[player.UserId] = true

	-- Touched fires for multiple character body parts; suppress repeat warnings/open attempts.
	task.delay(2.5, function()
		interactionDebounce[player.UserId] = nil
	end)
end

local function getCaptureZoneForPad(padPart)
	local captureZones = Workspace:FindFirstChild("CaptureZones")
	if not captureZones then
		return nil
	end

	-- A capture zone may itself be the LinkedArea target, or the target/pad
	-- may be nested beneath the zone. Walk upward to the direct zone child.
	local function findZone(instance)
		local current = instance

		while current and current ~= Workspace do
			if current.Parent == captureZones and current:IsA("BasePart") then
				return current
			end

			current = current.Parent
		end

		return nil
	end

	local linkedValue = padPart:FindFirstChild("LinkedArea", true)
	local linkedArea = linkedValue and linkedValue:IsA("ObjectValue") and linkedValue.Value

	return findZone(linkedArea) or findZone(padPart)
end

local PAD_CONFIG = {
	SpawnSelector_1 = {
		UI = "SpawnSelectorUI"
	},

	SpawnSelector_2 = {
		UI = "SpawnSelectorUI"
	},

	ShopPad_1 = {
		UI = "ShopUI"
	},

	ShopPad_2 = {
		UI = "ShopUI"
	}
}

local function getBaseContext(padPart)
	local current = padPart
	while current and current ~= Workspace do
		if current.Name == "MainBase" then
			return true, padPart:GetAttribute("Team")
		elseif current.Name == "GermanyBase" then
			return true, "Germany"
		elseif current.Name == "BritainBase" then
			return true, "Britain"
		end
		current = current.Parent
	end
	return false, nil
end

local function getPadConfig(padPart)
	local config = PAD_CONFIG[padPart.Name]

	if config then
		return config
	end

	if padPart.Name:find("SpawnPad") or padPart.Name:find("ButtonPad") then
		return {
			UI = "TankSelectionUI",
			RequireTeam = true
		}
	end

	return nil
end

local function handlePadTouch(padPart, player)
	if not player or not padPart then return end
	if interactionDebounce[player.UserId] then return end

	local config = getPadConfig(padPart)

	if not config then
		return
	end

	local playerTeam = player.Team and player.Team.Name
	local padTeam = padPart:GetAttribute("Team")

	local isMainBasePad, baseTeam = getBaseContext(padPart)
	local captureZone = nil

	-- MainBase is a permanent home spawn, not a capturable objective.
	-- Only field pads require capture ownership.
	if config.UI == "TankSelectionUI" and not isMainBasePad then
		captureZone = getCaptureZoneForPad(padPart)

		-- Fail closed for field pads: no resolved zone or no ownership means no menu.
		if not playerTeam or not captureZone
			or not GameLogic.IsPointOwnedByTeam(captureZone.Name, playerTeam) then
				debounceInteraction(player)
				openUIEvent:FireClient(player, config.UI, {Close = true})

				if showSpawnMessageEvent:IsA("RemoteEvent") then
					showSpawnMessageEvent:FireClient(player, "Capture the zone first!")
				else
					warn("[SpawnPadManager] ShowSpawnMessageEvent exists but is not a RemoteEvent.")
				end
				return
		end
	end

	if config.RequireTeam then
		if not playerTeam then
			openUIEvent:FireClient(player, config.UI, {Close = true})
			return
		end

		if isMainBasePad then
			local requiredBaseTeam = baseTeam or padTeam
			if requiredBaseTeam and requiredBaseTeam ~= "Neutral" and requiredBaseTeam ~= playerTeam then
				openUIEvent:FireClient(player, config.UI, {Close = true})
				return
			end
		elseif not padTeam or padTeam == "Neutral" or padTeam ~= playerTeam then
			openUIEvent:FireClient(player, config.UI, {Close = true})
			return
		end
	elseif padTeam and padTeam ~= "Neutral" and padTeam ~= playerTeam then
		openUIEvent:FireClient(player, config.UI, {Close = true})
		return
	end

	debounceInteraction(player)

	openUIEvent:FireClient(player, config.UI, {
		CurrentPad = padPart.Name,
		Team = playerTeam,
		RequiresCapture = config.UI == "TankSelectionUI" and not isMainBasePad,
		CaptureZone = captureZone and captureZone.Name or nil
	})
end

local function bindPad(padPart)
	if not padPart:IsA("BasePart") then return end
	if padPart:GetAttribute("UIPadBound") then return end

	local config = getPadConfig(padPart)

	if not config then
		return
	end

	padPart:SetAttribute("UIPadBound", true)

	padPart.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)

		if player then
			handlePadTouch(padPart, player)
		end
	end)
end

local function bindAllPads()
	for _, element in ipairs(Workspace:GetDescendants()) do
		bindPad(element)
	end
end

task.spawn(function()
	task.wait(2)
	bindAllPads()
end)

Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("BasePart") then
		bindPad(instance)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	interactionDebounce[player.UserId] = nil
end)
