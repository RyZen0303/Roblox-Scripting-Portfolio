-- // ServerScript: Team & Stats Management //
-- Location: ServerScriptService
-- Description: Handles secure team allocation, leaderstats lifecycle registration,
--              and interaction triggers for Lobby Team Change Pads with dynamic auto-balance enforcement.
--              [FIXED]: Resolved thread-crashing on LoadCharacter and added forced UI cleanup.

local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Define factions
local FACTIONS = {
	{Name = "Germany", Color = BrickColor.new("Gold")},
	{Name = "Britain", Color = BrickColor.new("Bright blue")}
}

-- Initialize Teams
for _, data in ipairs(FACTIONS) do
	local team = Teams:FindFirstChild(data.Name) or Instance.new("Team", Teams)
	team.Name = data.Name
	team.TeamColor = data.Color
	team.AutoAssignable = false
end

-- Setup player leaderstats
local function setupLeaderstats(player)
	local stats = player:FindFirstChild("leaderstats") or Instance.new("Folder", player)
	stats.Name = "leaderstats"

	local points = stats:FindFirstChild("Points")
	if not points then
		points = Instance.new("IntValue")
		points.Name = "Points"
		points.Value = 20 -- Default starting value
		points.Parent = stats
	end
end

-- Auto-balance logic for first-time joiners
local function getSmallestTeam()
	local counts = {}
	for _, team in ipairs(Teams:GetTeams()) do
		counts[team.Name] = #team:GetPlayers()
	end
	return (counts["Germany"] or 0) <= (counts["Britain"] or 0) and Teams:FindFirstChild("Germany") or Teams:FindFirstChild("Britain")
end

-- Handle new players
Players.PlayerAdded:Connect(function(player)
	setupLeaderstats(player)
	player.Team = getSmallestTeam()

	-- Enforce absolute balance limits during runtime context modifications
	player:GetPropertyChangedSignal("Team"):Connect(function()
		local germany = Teams:FindFirstChild("Germany")
		local britain = Teams:FindFirstChild("Britain")
		if not germany or not britain then return end

		local gCount = #germany:GetPlayers()
		local bCount = #britain:GetPlayers()
		local diff = math.abs(gCount - bCount)

		if diff >= 2 then
			if player.Team == germany and gCount > bCount then
				player.Team = britain
			elseif player.Team == britain and bCount > gCount then
				player.Team = germany
			end
		end
	end)
end)

-- =========================================================================
-- [[  LOBBY TEAM CHANGE PAD INTERACTION ]]
-- =========================================================================
local debounceRegistry = {}

local function setupTeamChangePad(padPart, targetTeamName)
	if not padPart or not padPart:IsA("BasePart") then return end

	padPart.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)

		if not player then return end

		-- Debounce tracking to prevent thread spamming from high velocity parts
		if debounceRegistry[player.UserId] then return end
		debounceRegistry[player.UserId] = true

		task.delay(1, function()
			debounceRegistry[player.UserId] = nil
		end)

		local currentTeam = player.Team
		local targetTeam = Teams:FindFirstChild(targetTeamName)

		if not currentTeam or not targetTeam or currentTeam == targetTeam then return end

		-- Fetch real-time active player counts across both teams
		local germanyTeam = Teams:FindFirstChild("Germany")
		local britainTeam = Teams:FindFirstChild("Britain")
		if not germanyTeam or not britainTeam then return end

		local gCount = #germanyTeam:GetPlayers()
		local bCount = #britainTeam:GetPlayers()

		-- Simulate virtual counts as if the switch has already occurred
		local virtualTargetCount = #targetTeam:GetPlayers() + 1
		local virtualCurrentCount = #currentTeam:GetPlayers() - 1

		-- Strict Balance Logic Check
		local balanceDifference = virtualTargetCount - virtualCurrentCount

		if balanceDifference <= 1 then
			print(string.format(" [Team Transfer]: Approved %s moving to %s (Balance Diff: %d)", player.Name, targetTeamName, balanceDifference))
			player.Team = targetTeam

			-- =========================================================================
			-- [[  FIXED: FORCE CLIENT INTERFACE CLEANUP BEFORE RESET ]]
			-- =========================================================================
			-- Pulls down any visible selector menus down on the client to prevent ghost button leaks
			local playerGui = player:FindFirstChild("PlayerGui")
			if playerGui then
				local spawnUI = playerGui:FindFirstChild("SpawnSelectorUI")
				if spawnUI and spawnUI:IsA("ScreenGui") then
					spawnUI.Enabled = false
				end
				local tankUI = playerGui:FindFirstChild("TankSelectionUI")
				if tankUI and tankUI:IsA("ScreenGui") then
					tankUI.Enabled = false
				end
			end

			-- [THREAD-SAFE FIX]: Defer character load execution into the next cycle frame
			--                   to completely prevent physics engine crashes and red highlights.
			task.defer(function()
				if player and player.Parent then
					player:LoadCharacter()
				end
			end)
			-- =========================================================================

		else
			warn(string.format(" [Transfer Blocked]: %s switch denied. %s team would overflow. (Diff: %d)", player.Name, targetTeamName, balanceDifference))
		end
	end)
end

-- [[ BIND TOUCH CONTROLLERS TO WORKSPACE LOBBY CONFIGURATIONS ]]
task.spawn(function()
	task.wait(1)

	local lobby1 = Workspace:FindFirstChild("Lobby1", true)
	if lobby1 then
		local pad1 = lobby1:FindFirstChild("TeamChangePad_1", true)
		setupTeamChangePad(pad1, "Britain")
	end

	local lobby2 = Workspace:FindFirstChild("Lobby2", true)
	if lobby2 then
		local pad2 = lobby2:FindFirstChild("TeamChangePad_2", true)
		setupTeamChangePad(pad2, "Germany")
	end
end)
