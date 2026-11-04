-- [[ GameLogic (ModuleScript) ]] --
local GameLogic = {}

-- [[ CONFIGURATION ]] --
local CAPTURE_ZONES_FOLDER = workspace:WaitForChild("CaptureZones", 10)

-- [[ CHECK OWNERSHIP ]] --
-- Safely returns true if the specified team owns the targeted tactical node
function GameLogic.IsPointOwnedByTeam(pointName, teamName)
	local zone = CAPTURE_ZONES_FOLDER:FindFirstChild(pointName)
	if zone then
		-- Directly check the real-time attribute managed by GameplayMaster
		return zone:GetAttribute("Owner") == teamName
	end
	return false
end

return GameLogic
