-- // MainHUDController (Client-Side Explicit Script) //
-- Location: StarterGui / MainBaseHUD / MainHUDController
-- Description: Monitors and updates base shields by reading exact replicated values from Server attributes.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HUD = script.Parent
local TopBar = HUD:WaitForChild("TopBarFrame")

local GermanyBG = TopBar:WaitForChild("GermanyHPBG")
local BritainBG = TopBar:WaitForChild("BritainHPBG")

local GermanyFill = GermanyBG:WaitForChild("GermanyFill")
local GermanyTicketsText = GermanyBG:WaitForChild("GermanyTickets")

local BritainFill = BritainBG:WaitForChild("BritainFill")
local BritainTicketsText = BritainBG:WaitForChild("BritainTickets")

local shieldGermany = nil
local shieldBritain = nil

local function fetchShields()
	local germanyBase = Workspace:WaitForChild("GermanyBase", 15)
	if germanyBase then
		shieldGermany = germanyBase:FindFirstChild("MainBaseShield_Germany", true)
	end

	local britainBase = Workspace:WaitForChild("BritainBase", 15)
	if britainBase then
		shieldBritain = britainBase:FindFirstChild("MainBaseShield_Britain", true)
	end
end

fetchShields()

local function updateGermanyUI()
	if not shieldGermany then fetchShields() end

	-- FIXED: Defaulting to 15000 to match your design properties
	local current = shieldGermany and shieldGermany:GetAttribute("Health") or 15000
	local max = shieldGermany and shieldGermany:GetAttribute("MaxHealth") or 15000

	GermanyTicketsText.Text = string.format("%d/%d", current, max)
	local ratio = math.clamp(current / max, 0, 1)
	GermanyFill.Size = UDim2.new(ratio, 0, 1, 0)
end

local function updateBritainUI()
	if not shieldBritain then fetchShields() end

	local current = shieldBritain and shieldBritain:GetAttribute("Health") or 15000
	local max = shieldBritain and shieldBritain:GetAttribute("MaxHealth") or 15000

	BritainTicketsText.Text = string.format("%d/%d", current, max)
	local ratio = math.clamp(current / max, 0, 1)
	BritainFill.Size = UDim2.new(ratio, 0, 1, 0)
end

-- // ASYNC LISTENERS WITH EXPLICIT SIGNALS //
task.spawn(function()
	while true do
		if shieldGermany then break end
		fetchShields()
		task.wait(0.5)
	end

	shieldGermany:GetAttributeChangedSignal("Health"):Connect(updateGermanyUI)
	shieldGermany:GetAttributeChangedSignal("MaxHealth"):Connect(updateGermanyUI)
	updateGermanyUI()
end)

task.spawn(function()
	while true do
		if shieldBritain then break end
		fetchShields()
		task.wait(0.5)
	end

	shieldBritain:GetAttributeChangedSignal("Health"):Connect(updateBritainUI)
	shieldBritain:GetAttributeChangedSignal("MaxHealth"):Connect(updateBritainUI)
	updateBritainUI()
end)

updateGermanyUI()
updateBritainUI()
