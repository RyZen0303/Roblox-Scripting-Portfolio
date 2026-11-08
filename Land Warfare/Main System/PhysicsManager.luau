-- // PhysicsManager: Global Collision & Physics Settings //
local PhysicsService = game:GetService("PhysicsService")

-- [[ REGISTRATION ]] --
local groups = {
	"Tanks",
	"Players",
	"Zones",
	"Projectiles_Germany",
	"Projectiles_Britain",
	"Shields_Germany",
	"Shields_Britain"
}

for _, groupName in ipairs(groups) do
	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
end

-- [[ SET BASE COLLISION RULES ]] --
PhysicsService:CollisionGroupSetCollidable("Tanks", "Players", false)       -- No player body-blocking tanks

-- [[ GERMAN SHELL RULES ]] --
PhysicsService:CollisionGroupSetCollidable("Projectiles_Germany", "Players", true)
PhysicsService:CollisionGroupSetCollidable("Projectiles_Germany", "Tanks", true)
PhysicsService:CollisionGroupSetCollidable("Projectiles_Germany", "Zones", false)
-- One-Way Logic: Germany shoots THROUGH Germany shields, but HITS British shields
PhysicsService:CollisionGroupSetCollidable("Projectiles_Germany", "Shields_Germany", false)
PhysicsService:CollisionGroupSetCollidable("Projectiles_Germany", "Shields_Britain", true)

-- [[ BRITISH SHELL RULES ]] --
PhysicsService:CollisionGroupSetCollidable("Projectiles_Britain", "Players", true)
PhysicsService:CollisionGroupSetCollidable("Projectiles_Britain", "Tanks", true)
PhysicsService:CollisionGroupSetCollidable("Projectiles_Britain", "Zones", false)
-- One-Way Logic: Britain shoots THROUGH British shields, but HITS German shields
PhysicsService:CollisionGroupSetCollidable("Projectiles_Britain", "Shields_Britain", false)
PhysicsService:CollisionGroupSetCollidable("Projectiles_Britain", "Shields_Germany", true)


-- [[ AUTOMATIC HIERARCHY MAPPER ]] --
local function initializeMapElements()
	-- 1. Map Capture Zones
	local captureZones = workspace:FindFirstChild("CaptureZones") or workspace:FindFirstChild("Zones")
	if captureZones then
		for _, part in ipairs(captureZones:GetDescendants()) do
			if part:IsA("BasePart") then part.CollisionGroup = "Zones" end
		end
		captureZones.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then descendant.CollisionGroup = "Zones" end
		end)
	end

	-- 2. Map Base Shields Natively by Name
	-- Looks for names like "MainBaseShield_Germany" or parts inside a folder with that name
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") then
			if string.find(instance.Name, "Germany") and string.find(instance.Name, "Shield") then
				instance.CollisionGroup = "Shields_Germany"
			elseif string.find(instance.Name, "Britain") and string.find(instance.Name, "Shield") then
				instance.CollisionGroup = "Shields_Britain"
			end
		end
	end
end

-- Run initialization
initializeMapElements()
print(" [SYSTEM]: Global Physics & Team Shield Groups initialized successfully.")