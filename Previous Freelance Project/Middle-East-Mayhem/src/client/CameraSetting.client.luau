-- CameraController.client.luau
-- Clean Procedural Fall Impact Camera System (Single-Tilt Heavy Roll)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Spring = require(Modules:WaitForChild("Spring"))

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid", 5) :: Humanoid?
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
local Camera = Workspace.CurrentCamera

--------------------------------------------------------------------------------
-- SETTINGS & SPRINGS
--------------------------------------------------------------------------------

local SETTINGS = {
	MinFallHeight = 10,     -- Minimum fall height in studs required to trigger impact
	MaxFallHeight = 40,     -- Maximum fall height limit for calculating max impact force
	SideRollIntensity = 5, -- Intense side roll angle multiplier
	YawIntensity = 0.4,      -- Subtle side sway on the Yaw axis
}

-- Impact Spring: Vector3(Pitch, Yaw, Roll)
local ImpactSpring = Spring.new(Vector3.new(0, 0, 0))
ImpactSpring.s = 35   -- Speed: Snappy response upon landing
ImpactSpring.d = 0.85 -- Damping: High value prevents lingering oscillations (single punchy tilt)

--------------------------------------------------------------------------------
-- FALL HEIGHT & IMPACT LOGIC
--------------------------------------------------------------------------------

local startFallY = 0
local isFalling = false

local function BindCharacterEvents(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid", 5) :: Humanoid?
	HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?

	if not Humanoid or not HumanoidRootPart then return end

	-- Detect fall initiation and landing impact based on vertical distance
	Humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Freefall then
			if not isFalling then
				isFalling = true
				startFallY = HumanoidRootPart.Position.Y
			end
		elseif newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
			if isFalling then
				isFalling = false
				local landY = HumanoidRootPart.Position.Y
				local fallDistance = startFallY - landY

				-- Require fall distance to exceed MinFallHeight threshold
				if fallDistance >= SETTINGS.MinFallHeight then
					local alpha = math.clamp(
						(fallDistance - SETTINGS.MinFallHeight) / (SETTINGS.MaxFallHeight - SETTINGS.MinFallHeight),
						0.2,
						1
					)

					-- Randomize side roll direction (Left or Right)
					local sideDirection = (math.random() > 0.5 and 1 or -1)
					local rollKick = sideDirection * alpha * SETTINGS.SideRollIntensity
					local yawKick = -sideDirection * alpha * SETTINGS.YawIntensity

					-- Impulse vector applied to spring
					ImpactSpring:Accelerate(Vector3.new(0, yawKick, rollKick))
				end
			end
		end
	end)
end

if Character then BindCharacterEvents(Character) end
Player.CharacterAdded:Connect(BindCharacterEvents)

--------------------------------------------------------------------------------
-- MAIN CAMERA UPDATE LOOP
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt: number)
	ImpactSpring:Update(dt)

	if Character and HumanoidRootPart and Humanoid and Humanoid.Health > 0 then
		local offset = ImpactSpring.p
		-- Apply transformation using CFrame.Angles(Pitch, Yaw, Roll)
		local impactAngles = CFrame.Angles(offset.X, offset.Y, offset.Z)

		Camera.CFrame = Camera.CFrame * impactAngles
	end
end)