-- ServerScriptService/ShopServerHandler

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent:WaitForChild("Modules")
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local PlayerSkillManager = require(Modules:WaitForChild("PlayerSkillManager"))

local Events = ReplicatedStorage:WaitForChild("Events")

-- RemoteFunction references
local PurchaseItemFunction = Events:FindFirstChild("PurchaseItemFunction")

if not PurchaseItemFunction then
	PurchaseItemFunction = Instance.new("RemoteFunction")
	PurchaseItemFunction.Name = "PurchaseItemFunction"
	PurchaseItemFunction.Parent = Events
end

local SkillActionFunction = Events:FindFirstChild("SkillActionFunction")

if not SkillActionFunction then
	SkillActionFunction = Instance.new("RemoteFunction")
	SkillActionFunction.Name = "SkillActionFunction"
	SkillActionFunction.Parent = Events
end

-- PlayerSkillManager is the single source of skill configuration.
local PASSIVE_SKILL_CATALOG = PlayerSkillManager.GetCatalog()

-- Restore the previously equipped skill after player data finishes loading.
local function restoreEquippedSkill(player)
	task.spawn(function()
		while player.Parent and not PlayerDataManager.IsDataLoaded(player) do
			task.wait(0.25)
		end

		if not player.Parent or not PlayerDataManager.IsDataLoaded(player) then
			return
		end

		local savedSkill = PlayerDataManager.GetEquippedSkill(player)

		if typeof(savedSkill) ~= "string" then
			print(string.format(
				"[SKILL RESTORE] %s has no saved equipped skill",
				player.Name
				))
			return
		end

		-- Never restore a skill that is missing from the catalog or not owned.
		if not PASSIVE_SKILL_CATALOG[savedSkill]
			or not PlayerDataManager.HasSkill(player, savedSkill)
		then
			warn(string.format(
				"[SKILL RESTORE] Invalid saved skill for %s: %s",
				player.Name,
				savedSkill
				))

			PlayerDataManager.SetEquippedSkill(player, nil)
			PlayerDataManager.SaveData(player)
			return
		end

		local success, message = PlayerSkillManager.Equip(player, savedSkill)

		if success then
			player:SetAttribute("EquippedSkill", savedSkill)

			print(string.format(
				"[SKILL RESTORE] Restored %s for %s",
				savedSkill,
				player.Name
				))
		else
			warn(string.format(
				"[SKILL RESTORE] Could not equip %s for %s: %s",
				savedSkill,
				player.Name,
				tostring(message)
				))
		end
	end)
end

Players.PlayerAdded:Connect(restoreEquippedSkill)

-- Handle players who joined before this script connected.
for _, player in ipairs(Players:GetPlayers()) do
	restoreEquippedSkill(player)
end

-- Purchase handling
PurchaseItemFunction.OnServerInvoke = function(player: Player, itemName: string)
	if typeof(itemName) ~= "string" then
		return false, "Invalid skill parameters"
	end

	local skillData = PASSIVE_SKILL_CATALOG[itemName]

	if not skillData then
		return false, "Skill does not exist in catalog"
	end

	if not PlayerDataManager.IsDataLoaded(player) then
		return false, "Player data is not loaded yet"
	end

	if PlayerSkillManager.HasSkill(player, itemName) then
		return false, "Skill already unlocked"
	end

	local success, message = PlayerDataManager.PurchaseSkill(
		player,
		itemName,
		skillData.Price
	)

	if not success then
		return false, message
	end

	print(string.format(
		"[SERVER SHOP] %s unlocked skill %s for $%d",
		player.Name,
		itemName,
		skillData.Price
		))

	return true, message
end

-- Skill status and equip authorization
SkillActionFunction.OnServerInvoke = function(
	player: Player,
	action: string,
	itemName: string
)
	if typeof(action) ~= "string" or typeof(itemName) ~= "string" then
		return false, "Invalid skill action parameters"
	end

	if not PlayerDataManager.IsDataLoaded(player) then
		return false, "Player data is not loaded yet"
	end

	if not PASSIVE_SKILL_CATALOG[itemName] then
		return false, "Skill does not exist in catalog"
	end

	if action == "GetStatus" then
		return PlayerSkillManager.GetStatus(player, itemName)
	end

	if action == "Equip" then
		-- The server checks ownership before equipping.
		if not PlayerDataManager.HasSkill(player, itemName) then
			return false, "Skill not owned"
		end

		local success, message = PlayerSkillManager.Equip(player, itemName)

		if not success then
			return false, message
		end

		local saved, saveMessage =
			PlayerDataManager.SetEquippedSkill(player, itemName)

		if not saved then
			warn(string.format(
				"[SKILL EQUIP] Equip succeeded but session update failed for %s: %s",
				player.Name,
				tostring(saveMessage)
				))

			return false, saveMessage
		end

		-- Save immediately so the choice survives leaving the game.
		local saveSuccess = PlayerDataManager.SaveData(player)

		if not saveSuccess then
			warn(string.format(
				"[SKILL EQUIP] Could not persist equipped skill for %s",
				player.Name
				))

			return false, "Equip succeeded, but saving failed. Please try again."
		end

		print(string.format(
			"[SKILL EQUIP] %s equipped and saved %s",
			player.Name,
			itemName
			))

		return true, message
	end

	return false, "Unknown skill action"
end
