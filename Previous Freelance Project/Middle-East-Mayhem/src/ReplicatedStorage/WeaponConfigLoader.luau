-- WeaponConfigLoader.luau
-- Centralized Utility for Searching, Requiring, and Caching Weapon Configuration Modules

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponsConfigFolder = ReplicatedStorage:WaitForChild("WeaponsConfig", 5) 
	or ReplicatedStorage:WaitForChild("Weapons Config", 5)

local WeaponConfigLoader = {}
local cachedConfigs: { [string]: any } = {}

function WeaponConfigLoader.GetConfig(weaponName: string)
	if not weaponName or weaponName == "" then
		return nil
	end

	-- Return cached config if available
	if cachedConfigs[weaponName] then
		return cachedConfigs[weaponName]
	end

	if not weaponsConfigFolder then
		warn("[WeaponConfigLoader] WeaponsConfig folder not found in ReplicatedStorage!")
		return nil
	end

	-- Search recursively for the ModuleScript
	local configModule = weaponsConfigFolder:FindFirstChild(weaponName, true) :: ModuleScript?
	if configModule and configModule:IsA("ModuleScript") then
		local success, configData = pcall(require, configModule)
		if success and type(configData) == "table" then
			cachedConfigs[weaponName] = configData
			return configData
		else
			warn("[WeaponConfigLoader] Failed to require config module for: " .. weaponName)
		end
	end

	return nil
end

-- Optional utility to wipe cache if configs are updated dynamically at runtime
function WeaponConfigLoader.ClearCache()
	table.clear(cachedConfigs)
end

return WeaponConfigLoader