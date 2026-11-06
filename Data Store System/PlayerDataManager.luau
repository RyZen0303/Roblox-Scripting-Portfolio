-- ServerScriptService/Modules/PlayerDataManager.lua

local DataStoreService = game:GetService("DataStoreService")

local PlayerDataManager = {}

-- Configuration
local DATA_STORE_NAME = "PlayerData_v1"
local MAX_RETRIES = 3
local RETRY_DELAY = 2

local STARTING_CASH = 0

local playerDataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

-- [Player] = {
--     Data = {
--         Cash = number,
--         OwnedSkills = table,
--         EquippedSkill = string?,
--         StartingCashCompensated = boolean,
--     },
--     IsLoaded = boolean,
--     LoadFailed = boolean,
-- }
local sessionData = {}

local function debugCash(stage, player, cash)
	print(string.format(
		"[CASH DEBUG][SERVER][%s] Player=%s | Cash=%s",
		stage,
		player.Name,
		tostring(cash)
		))
end

local function executeWithRetry(operationName, callback)
	local lastError

	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(callback)

		if success then
			return true, result
		end

		lastError = result

		warn(string.format(
			"[PlayerDataManager] %s failed (attempt %d/%d): %s",
			operationName,
			attempt,
			MAX_RETRIES,
			tostring(result)
			))

		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY * attempt)
		end
	end

	return false, lastError
end

local function createDefaultData()
	return {
		Cash = STARTING_CASH,
		OwnedSkills = {},
		EquippedSkill = nil,
		StartingCashCompensated = false,
	}
end

local function validateAndSanitize(rawData)
	if typeof(rawData) ~= "table" then
		return createDefaultData()
	end

	local data = createDefaultData()

	if typeof(rawData.Cash) == "number" then
		data.Cash = math.max(0, math.floor(rawData.Cash))
	end

	if typeof(rawData.OwnedSkills) == "table" then
		for skillName, owned in pairs(rawData.OwnedSkills) do
			if typeof(skillName) == "string" and owned == true then
				data.OwnedSkills[skillName] = true
			end
		end
	end

	if typeof(rawData.EquippedSkill) == "string"
		and data.OwnedSkills[rawData.EquippedSkill] == true
	then
		data.EquippedSkill = rawData.EquippedSkill
	end

	-- Retain the legacy field for compatibility.
	-- It no longer grants compensation cash.
	data.StartingCashCompensated =
		rawData.StartingCashCompensated == true

	return data
end

local function syncPlayerAttributes(player, data)
	player:SetAttribute("Cash", data.Cash)

	-- Reset skill unlock attributes before syncing saved ownership.
	for _, attributeName in ipairs(player:GetAttributes()) do
		-- Attributes are returned as a dictionary, so this loop is
		-- intentionally handled below using the attribute name.
	end

	for skillName, owned in pairs(data.OwnedSkills) do
		if owned then
			player:SetAttribute("UnlockedSkill_" .. skillName, true)
		end
	end

	player:SetAttribute("EquippedSkill", data.EquippedSkill)
end

function PlayerDataManager.LoadData(player)
	if sessionData[player] and sessionData[player].IsLoaded then
		return true
	end

	local key = "Player_" .. player.UserId

	print(string.format(
		"[PlayerDataManager] Loading data for %s | Key=%s",
		player.Name,
		key
		))

	local success, savedData = executeWithRetry("LoadData", function()
		return playerDataStore:GetAsync(key)
	end)

	if not success then
		sessionData[player] = {
			Data = createDefaultData(),
			IsLoaded = false,
			LoadFailed = true,
		}

		warn(string.format(
			"[PlayerDataManager] Could not load data for %s. Purchases disabled.",
			player.Name
			))

		return false
	end

	local data

	if savedData == nil then
		data = createDefaultData()

		print(string.format(
			"[PlayerDataManager] New player %s receives %d Cash",
			player.Name,
			STARTING_CASH
			))
	else
		data = validateAndSanitize(savedData)
	end

	sessionData[player] = {
		Data = data,
		IsLoaded = true,
		LoadFailed = false,
	}

	syncPlayerAttributes(player, data)
	debugCash("DATASTORE LOAD", player, data.Cash)

	print(string.format(
		"[PlayerDataManager] Loaded %s | OwnedSkills=%d | EquippedSkill=%s",
		player.Name,
		(function()
			local count = 0
			for _ in pairs(data.OwnedSkills) do
				count += 1
			end
			return count
		end)(),
		tostring(data.EquippedSkill)
		))

	return true
end

function PlayerDataManager.SaveData(player)
	local playerSession = sessionData[player]

	if not playerSession or not playerSession.IsLoaded then
		warn(string.format(
			"[PlayerDataManager] Skipping save for %s because data is not loaded",
			player.Name
			))
		return false
	end

	local key = "Player_" .. player.UserId
	local session = playerSession.Data

	local dataToSave = {
		Cash = math.max(0, math.floor(session.Cash)),
		OwnedSkills = {},
		StartingCashCompensated =
			session.StartingCashCompensated == true,
	}

	for skillName, owned in pairs(session.OwnedSkills) do
		if typeof(skillName) == "string" and owned == true then
			dataToSave.OwnedSkills[skillName] = true
		end
	end

	if typeof(session.EquippedSkill) == "string"
		and dataToSave.OwnedSkills[session.EquippedSkill] == true
	then
		dataToSave.EquippedSkill = session.EquippedSkill
	end

	local success, result = executeWithRetry("SaveData", function()
		return playerDataStore:UpdateAsync(key, function(currentData)
			-- Preserve existing ownership records.
			-- This protects previously saved purchases.
			if typeof(currentData) == "table"
				and typeof(currentData.OwnedSkills) == "table"
			then
				for skillName, owned in pairs(currentData.OwnedSkills) do
					if typeof(skillName) == "string" and owned == true then
						dataToSave.OwnedSkills[skillName] = true
					end
				end
			end

			-- Preserve the legacy marker if it already exists.
			if typeof(currentData) == "table"
				and currentData.StartingCashCompensated == true
			then
				dataToSave.StartingCashCompensated = true
			end

			return dataToSave
		end)
	end)

	if not success then
		warn(string.format(
			"[PlayerDataManager] Failed to save data for %s: %s",
			player.Name,
			tostring(result)
			))
		return false
	end

	local skillCount = 0

	for _ in pairs(dataToSave.OwnedSkills) do
		skillCount += 1
	end

	print(string.format(
		"[PlayerDataManager] Saved %s | Cash=%d | OwnedSkills=%d | EquippedSkill=%s",
		player.Name,
		dataToSave.Cash,
		skillCount,
		tostring(dataToSave.EquippedSkill)
		))

	return true
end

function PlayerDataManager.GetCash(player)
	local playerSession = sessionData[player]

	if not playerSession or not playerSession.IsLoaded then
		return nil
	end

	return playerSession.Data.Cash
end

function PlayerDataManager.IsDataLoaded(player)
	local playerSession = sessionData[player]

	return playerSession ~= nil
		and playerSession.IsLoaded == true
		and playerSession.LoadFailed ~= true
end

function PlayerDataManager.HasSkill(player, skillName)
	local playerSession = sessionData[player]

	if not playerSession or not playerSession.IsLoaded then
		return false
	end

	return playerSession.Data.OwnedSkills[skillName] == true
end

function PlayerDataManager.GetEquippedSkill(player)
	local playerSession = sessionData[player]

	if not playerSession or not playerSession.IsLoaded then
		return nil
	end

	return playerSession.Data.EquippedSkill
end

function PlayerDataManager.SetEquippedSkill(player, skillName)
	local playerSession = sessionData[player]

	if not playerSession or not playerSession.IsLoaded then
		return false, "DataNotLoaded"
	end

	if skillName ~= nil then
		if typeof(skillName) ~= "string" then
			return false, "InvalidSkillName"
		end

		if playerSession.Data.OwnedSkills[skillName] ~= true then
			return false, "SkillNotOwned"
		end
	end

	playerSession.Data.EquippedSkill = skillName
	player:SetAttribute("EquippedSkill", skillName)

	return true, "EquippedSkillUpdated"
end

function PlayerDataManager.PurchaseSkill(player, skillName, price)
	local playerSession = sessionData[player]

	if not playerSession or not playerSession.IsLoaded then
		return false, "DataNotLoaded"
	end

	if typeof(skillName) ~= "string"
		or typeof(price) ~= "number"
		or price < 0
	then
		return false, "InvalidArguments"
	end

	price = math.floor(price)

	if playerSession.Data.OwnedSkills[skillName] then
		return false, "AlreadyOwned"
	end

	if playerSession.Data.Cash < price then
		return false, "NotEnoughCash"
	end

	playerSession.Data.Cash -= price
	playerSession.Data.OwnedSkills[skillName] = true

	player:SetAttribute("Cash", playerSession.Data.Cash)
	player:SetAttribute("UnlockedSkill_" .. skillName, true)

	debugCash("PURCHASE SKILL", player, playerSession.Data.Cash)

	return true, "Purchased"
end

function PlayerDataManager.AddCash(player, amount)
	local playerSession = sessionData[player]

	if not playerSession or not playerSession.IsLoaded then
		return false
	end

	if typeof(amount) ~= "number" or amount <= 0 then
		return false
	end

	amount = math.floor(amount)

	if amount <= 0 then
		return false
	end

	playerSession.Data.Cash += amount
	player:SetAttribute("Cash", playerSession.Data.Cash)

	debugCash("ADD CASH", player, playerSession.Data.Cash)

	return true
end

function PlayerDataManager.RemoveCash(player, amount)
	local playerSession = sessionData[player]

	if not playerSession or not playerSession.IsLoaded then
		return false
	end

	if typeof(amount) ~= "number" or amount <= 0 then
		return false
	end

	amount = math.floor(amount)

	if amount <= 0 or playerSession.Data.Cash < amount then
		return false
	end

	playerSession.Data.Cash -= amount
	player:SetAttribute("Cash", playerSession.Data.Cash)

	debugCash("REMOVE CASH", player, playerSession.Data.Cash)

	return true
end

function PlayerDataManager.RemoveSession(player)
	sessionData[player] = nil
end

return PlayerDataManager
