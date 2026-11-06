-- [[ PLAYER SKILL MANAGER - SERVER AUTHORITATIVE VERSION ]] --
-- Location: ServerScriptService / Modules / PlayerSkillManager
-- Description: Skill catalog, ownership validation, equip state, and passive stat bonus calculation.

local Players = game:GetService("Players")

local PlayerDataManager = require(script.Parent:WaitForChild("PlayerDataManager"))

local PlayerSkillManager = {}

-- ==========================================
-- CONFIGURATION & CONSTANTS
-- ==========================================

-- Passive Skill Catalog Configuration
local PASSIVE_SKILL_CATALOG = {
	["Blitzkrieg"] = {
		Price = 2500,
		Category = "Skill",
		Stats = {
			MaxSpeed = 0.05,
			Damage = 0.05,
			ReloadTime = 0.02,
		}
	},

	["Overextend"] = {
		Price = 2500,
		Category = "Skill",
		Stats = {
			MaxHealth = 0.05,
			ReloadTime = 0.05,
			MaxReverseSpeed = 0.05,
		}
	}
}

-- ==========================================
-- PRIVATE HELPER FUNCTIONS
-- ==========================================

local function getPlayerSession(player: Player)
	if not player or not player:IsA("Player") then
		return false, "Invalid player"
	end

	if not PlayerDataManager.IsDataLoaded(player) then
		return false, "Player data is not loaded yet"
	end

	return true, nil
end

local function getSkillData(skillName: string)
	if typeof(skillName) ~= "string" then
		return nil
	end

	return PASSIVE_SKILL_CATALOG[skillName]
end

-- ==========================================
-- PUBLIC MODULE METHODS
-- ==========================================

-- Retrieves a skill's configuration from the Server catalog
function PlayerSkillManager.GetSkillData(skillName: string)
	return getSkillData(skillName)
end

-- Retrieves the complete skill catalog
function PlayerSkillManager.GetCatalog()
	return PASSIVE_SKILL_CATALOG
end

-- Checks whether the player owns a valid skill
function PlayerSkillManager.HasSkill(player: Player, skillName: string): boolean
	if not getSkillData(skillName) then
		return false
	end

	if not PlayerDataManager.IsDataLoaded(player) then
		return false
	end

	return PlayerDataManager.HasSkill(player, skillName)
end

-- Retrieves the currently equipped skill
function PlayerSkillManager.GetEquippedSkill(player: Player): string?
	local success = getPlayerSession(player)
	if not success then
		return nil
	end

	local equippedSkill = player:GetAttribute("EquippedSkill")

	if typeof(equippedSkill) ~= "string" then
		return nil
	end

	-- Never return a skill that the player does not own.
	if not PlayerDataManager.HasSkill(player, equippedSkill) then
		return nil
	end

	if not getSkillData(equippedSkill) then
		return nil
	end

	return equippedSkill
end

-- Retrieves the status of one skill for the Shop UI
function PlayerSkillManager.GetStatus(player: Player, skillName: string)
	local success, message = getPlayerSession(player)
	if not success then
		return false, message
	end

	if not getSkillData(skillName) then
		return false, "Skill does not exist in catalog"
	end

	local isOwned = PlayerDataManager.HasSkill(player, skillName)
	local equippedSkill = PlayerSkillManager.GetEquippedSkill(player)

	return true, {
		Owned = isOwned,
		Equipped = isOwned and equippedSkill == skillName
	}
end

-- Equips an owned skill on the Server
-- This implementation supports one equipped passive skill at a time.
function PlayerSkillManager.Equip(player: Player, skillName: string)
	local success, message = getPlayerSession(player)
	if not success then
		return false, message
	end

	if not getSkillData(skillName) then
		return false, "Skill does not exist in catalog"
	end

	if not PlayerDataManager.HasSkill(player, skillName) then
		return false, "Skill has not been unlocked"
	end

	if PlayerSkillManager.GetEquippedSkill(player) == skillName then
		return true, "Skill is already equipped"
	end

	-- Record the active skill on the Server.
	-- Gameplay systems must read this state to apply the bonuses.
	player:SetAttribute("EquippedSkill", skillName)

	print(string.format(
		"🛡️ [PLAYER SKILL MANAGER]: %s equipped %s",
		player.Name,
		skillName
		))

	return true, "Skill equipped successfully"
end

-- Unequips the currently equipped passive skill
function PlayerSkillManager.Unequip(player: Player)
	local success, message = getPlayerSession(player)
	if not success then
		return false, message
	end

	player:SetAttribute("EquippedSkill", nil)

	return true, "Skill unequipped successfully"
end

-- Retrieves the stat bonuses for the currently equipped skill
function PlayerSkillManager.GetEquippedStats(player: Player)
	local equippedSkill = PlayerSkillManager.GetEquippedSkill(player)

	if not equippedSkill then
		return {}
	end

	local skillData = getSkillData(equippedSkill)
	if not skillData or typeof(skillData.Stats) ~= "table" then
		return {}
	end

	-- Return a copy so callers cannot modify the Server catalog.
	local statsCopy = {}

	for statName, bonus in pairs(skillData.Stats) do
		statsCopy[statName] = bonus
	end

	return statsCopy
end

-- Retrieves the bonus for one stat from the equipped skill
function PlayerSkillManager.GetStatBonus(player: Player, statName: string): number
	if typeof(statName) ~= "string" then
		return 0
	end

	local stats = PlayerSkillManager.GetEquippedStats(player)
	local bonus = stats[statName]

	if typeof(bonus) ~= "number" then
		return 0
	end

	return bonus
end

-- Clears temporary equipped state when a player leaves
function PlayerSkillManager.RemovePlayer(player: Player)
	if player and player:IsA("Player") then
		player:SetAttribute("EquippedSkill", nil)
	end
end

Players.PlayerRemoving:Connect(function(player)
	PlayerSkillManager.RemovePlayer(player)
end)

return PlayerSkillManager
