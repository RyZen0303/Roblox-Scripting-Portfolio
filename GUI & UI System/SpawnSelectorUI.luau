-- [[ SPAWN SELECTOR UI CONTROLLER - RE-SPAWN RESILIENT VERSION ]] --
-- Location: StarterGui / SpawnSelectorUI / SpawnSelectorUIController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIMaster = require(ReplicatedStorage:WaitForChild("UIMaster"))
local PointEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("PointStatusUpdate")
local SpawnFunction = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RequestTankSpawnFunction")

local player = game.Players.LocalPlayer
local mainFrame = script.Parent
local gui = mainFrame.Parent

local selectedBaseName = "MainBase"

-- Initialize framework centering constraints via centralized module
UIMaster.InitCenter(gui, mainFrame)

-- Bind physical workspace touch pads to trigger the Spawn Selector UI
UIMaster.ConnectPads(gui, nil, {"SpawnSelector_1", "SpawnSelector_2"})

-- Core layout elements mapping
local leftPanel = mainFrame:WaitForChild("LeftPanel")
local selectBtn = leftPanel:WaitForChild("SelectButton")
local spawnImageLabel = leftPanel:FindFirstChild("ImageLabel")

-- Explicit references to team-isolated button hierarchies
local teamPages = {
	["Germany"] = mainFrame:WaitForChild("GermanySpawnList"),
	["Britain"] = mainFrame:WaitForChild("BritainSpawnList")
}

local clickConnections = {}
local updateSpawnPreview
local updateSpawnUILayout

-- Forward declaration for rendering wrappers
function updateSpawnPreview(baseName)
	UIMaster.RenderPreview(baseName, nil, spawnImageLabel, nil, "None")
end

-- Evaluates local container variables to force automatic fallback selection within the accurate active grid
local function autoSelectDefaultSpawn(realPageFrame)
	if not realPageFrame then return end
	selectedBaseName = "MainBase"

	UIMaster.SelectDefault(realPageFrame, function(btn)
		local detectedName = string.gsub(btn.Name, "_Button", "")
		if detectedName and detectedName ~= "" then
			selectedBaseName = detectedName
		end
	end)

	updateSpawnPreview(selectedBaseName)
end

-- [[ 🔄 CORE ARCHITECTURE FUNCTION: CONTAINER SWAPPING ROUTINE ]] --
function updateSpawnUILayout()
	for _, conn in ipairs(clickConnections) do conn:Disconnect() end
	clickConnections = {}

	local currentTeam = (player.Team and player.Team.Name) or "Germany"

	for teamName, frame in pairs(teamPages) do
		if frame then
			frame.Visible = (teamName == currentTeam)
		end
	end

	local activePageFrame = teamPages[currentTeam]
	if not activePageFrame then return end

	local realPage = activePageFrame:FindFirstChild("SpawnPointPage") or activePageFrame

	for _, button in ipairs(realPage:GetChildren()) do
		if button:IsA("GuiButton") then
			local conn = button.MouseButton1Click:Connect(function()
				selectedBaseName = string.gsub(button.Name, "_Button", "")
				updateSpawnPreview(selectedBaseName)
			end)
			table.insert(clickConnections, conn)
		end
	end

	autoSelectDefaultSpawn(realPage)
end

-- [[ 🔄 REAL-TIME NETWORK VISIBILITY EVALUATION ]] --
local function evaluateCapturePointNodeVisibility(pointName, owner)
	local cleanPointName = string.gsub(pointName, " Point", "")

	for teamName, frame in pairs(teamPages) do
		if frame then
			local button = frame:FindFirstChild(cleanPointName .. " Point_Button", true)
			if button then
				button.Visible = (owner == teamName)
			end
		end
	end
end

PointEvent.OnClientEvent:Connect(function(pointName, owner)
	evaluateCapturePointNodeVisibility(pointName, owner)

	local currentTeam = (player.Team and player.Team.Name) or "Germany"
	if gui.Enabled then 
		local activePageFrame = teamPages[currentTeam]
		local realPage = activePageFrame and (activePageFrame:FindFirstChild("SpawnPointPage") or activePageFrame)
		autoSelectDefaultSpawn(realPage) 
	end
end)

selectBtn.MouseButton1Click:Connect(function()
	if selectedBaseName ~= "" then
		local success = SpawnFunction:InvokeServer("TeleportPlayer", selectedBaseName)
		if success then
			UIMaster.Close(gui) -- Clean shutdown via UIMaster
			selectedBaseName = "MainBase" 
		else
			warn("❌ Server rejected teleport request or spawn point validation failed.")
		end
	else
		warn("⚠️ UX WARNING: Execution halted due to empty selectedBaseName index state.")
	end
end)

-- [[ 🚀 INITIALIZATION ARCHITECTURE THREAD ]]
task.spawn(function()
	local timeout = 0
	while not player.Team and timeout < 5 do
		task.wait(0.1)
		timeout = timeout + 0.1
	end

	player:GetPropertyChangedSignal("Team"):Connect(function()
		updateSpawnUILayout()
	end)

	local captureZones = workspace:FindFirstChild("CaptureZones")
	if captureZones then
		for _, zone in ipairs(captureZones:GetChildren()) do
			local zoneOwner = zone:GetAttribute("Owner") or ""
			evaluateCapturePointNodeVisibility(zone.Name, zoneOwner)
		end
	end

	updateSpawnUILayout()
end)

gui:GetAttributeChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then updateSpawnUILayout() end
end)

mainFrame.CloseButton.MouseButton1Click:Connect(function() 
	UIMaster.Close(gui) 
end)

UIMaster.SyncLeaderstats(player, mainFrame:WaitForChild("CloseButton"):WaitForChild("PointsLabel"))
gui.Enabled = false

UIMaster.PreloadMapPreviews()
