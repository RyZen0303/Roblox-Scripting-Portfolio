-- ViewmodelController.client.luau
-- Client-side FPS Viewmodel & ADS Handler

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = (workspace.CurrentCamera or workspace:WaitForChild("Camera")) :: Camera

-- == Folders & References ==
local weaponsConfigFolder = ReplicatedStorage:WaitForChild("WeaponsConfig", 5)
local viewModelFolder = ReplicatedStorage:WaitForChild("Viewmodel", 5)

-- == Default Configuration (Fallback) ==
local DEFAULT_CONFIG = {
	ViewModel = {
		ModelName = "Viewmodel_AK-47",
		HipfireOffset = CFrame.new(0.6, -0.6, -1.2),
		ADS_FOV = 40,
		ADS_Speed = 20,
	}
}

local DEFAULT_FOV = 70
local cachedConfigs = {}

local currentVM: Model? = nil
local currentConfig: { [any]: any }? = nil
local isAiming = false
local aimProgress = 0

-- == Helper Functions ==

-- Search and cache weapon ModuleScript configurations dynamically
local function getWeaponConfig(weaponName: string)
	if cachedConfigs[weaponName] then
		return cachedConfigs[weaponName]
	end

	if not weaponsConfigFolder then return DEFAULT_CONFIG end

	for _, descendant in ipairs(weaponsConfigFolder:GetDescendants()) do
		if descendant:IsA("ModuleScript") and descendant.Name == weaponName then
			local success, configData = pcall(require, descendant)
			if success and type(configData) == "table" then
				cachedConfigs[weaponName] = configData
				return configData
			else
				warn("[ViewmodelController] Failed to require config module for: " .. weaponName)
			end
		end
	end

	return DEFAULT_CONFIG
end

-- Calculate CFrame Offset between AimPart and Gun Body/Handle
local function getAimOffset(vm: Model): CFrame
	local aimPart = vm:FindFirstChild("AimPart", true) :: BasePart?
	local primaryPart: BasePart? = vm.PrimaryPart
		or (vm:FindFirstChild("Body", true) :: BasePart?)
		or (vm:FindFirstChild("Handle", true) :: BasePart?)

	if aimPart and primaryPart then
		return aimPart.CFrame:ToObjectSpace(primaryPart.CFrame)
	end
	return CFrame.new()
end

-- Equip & Spawn Viewmodel based on Weapon Name
local function equipViewModel(weaponName: string)
	local config = getWeaponConfig(weaponName)
	currentConfig = config

	local vmName = (config.ViewModel and config.ViewModel.ModelName) or ("Viewmodel_" .. weaponName)
	local vmTemplate = viewModelFolder:FindFirstChild(vmName, true) or ReplicatedStorage:FindFirstChild(vmName, true)

	if not vmTemplate then
		warn("[ViewmodelController] ViewModel model not found for: " .. vmName)
		return
	end

	-- Clear Existing ViewModel
	if currentVM then
		currentVM:Destroy()
		currentVM = nil
	end

	-- Clone & Setup ViewModel
	local newVM = vmTemplate:Clone() :: Model

	local bodyPart = newVM:FindFirstChild("Body", true) :: BasePart?
	local handlePart = newVM:FindFirstChild("Handle", true) :: BasePart?
	newVM.PrimaryPart = bodyPart or handlePart or newVM.PrimaryPart

	newVM.Parent = camera
	currentVM = newVM

	-- Disable Collision and Shadows
	for _, part in ipairs(newVM:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CastShadow = false
		end
	end
end

-- Unequip ViewModel
local function unequipViewModel()
	if currentVM then
		currentVM:Destroy()
		currentVM = nil
	end
	currentConfig = nil
	isAiming = false
	aimProgress = 0
	camera.FieldOfView = DEFAULT_FOV
end

-- == Input Handler (ADS Right Click) ==
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not currentConfig then return end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isAiming = true
		local targetFOV = (currentConfig.ViewModel and currentConfig.ViewModel.ADS_FOV) or 40
		TweenService:Create(camera, TweenInfo.new(0.2), {FieldOfView = targetFOV}):Play()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		isAiming = false
		TweenService:Create(camera, TweenInfo.new(0.2), {FieldOfView = DEFAULT_FOV}):Play()
	end
end)

-- == Character Equipment Listener ==
local function onCharacterAdded(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			equipViewModel(child.Name)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			unequipViewModel()
		end
	end)

	local currentTool = character:FindFirstChildOfClass("Tool")
	if currentTool then
		equipViewModel(currentTool.Name)
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- == Main Render Loop ==
RunService.RenderStepped:Connect(function(deltaTime: number)
	if not currentVM or not currentVM.PrimaryPart or not currentConfig then return end

	local vmSettings = currentConfig.ViewModel or DEFAULT_CONFIG.ViewModel
	local adsSpeed = vmSettings.ADS_Speed or 20
	local hipfireOffset = vmSettings.HipfireOffset or CFrame.new(0.6, -0.6, -1.2)

	local targetProgress = isAiming and 1 or 0
	aimProgress = math.clamp(aimProgress + ((targetProgress - aimProgress) * (deltaTime * adsSpeed)), 0, 1)

	local finalHipfireCFrame = camera.CFrame * hipfireOffset
	local aimOffset = getAimOffset(currentVM)
	local finalADSCFrame = camera.CFrame * aimOffset

	local finalCFrame = finalHipfireCFrame:Lerp(finalADSCFrame, aimProgress)
	currentVM:PivotTo(finalCFrame)
end)