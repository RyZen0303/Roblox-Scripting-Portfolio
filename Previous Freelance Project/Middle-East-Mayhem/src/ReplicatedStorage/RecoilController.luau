-- RecoilController.luau
-- Spring-based Procedural Camera and Weapon Model Recoil System (Cone-based)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Spring = require(Modules:WaitForChild("Spring") :: ModuleScript)

-- Primary Camera Springs
local CamRotSpring = Spring.new(Vector3.zero)
local CamTransSpring = Spring.new(Vector3.zero)

-- Weapon Model Viewmodel Springs
local ModelRotSpring = Spring.new(Vector3.zero)
local ModelTransSpring = Spring.new(Vector3.zero)

local RecoilController = {}
local consecutiveShots = 0

-- Helper: Calculate Pitch and Yaw using Cone-based Distribution (Degrees)
local function rollKick(axisConfig)
	if not axisConfig then return 0, 0 end

	local growth = math.min(
		consecutiveShots * (axisConfig.SpreadGrowthPerShot or 0),
		(axisConfig.MaxSpreadAngle or axisConfig.KickAngleRange) - axisConfig.KickAngleRange
	)
	local coneWidth = axisConfig.KickAngleRange + growth

	local kickAngle = math.rad(math.random(-coneWidth, coneWidth))
	local mag = axisConfig.KickMagnitude[1] + (math.random() * (axisConfig.KickMagnitude[2] - axisConfig.KickMagnitude[1]))

	local pitch = math.cos(kickAngle) * mag
	local yaw = math.sin(kickAngle) * mag

	return pitch, yaw
end

function RecoilController.Fire(recoilConfig)
	if not recoilConfig or not recoilConfig.Camera then return end

	consecutiveShots += 1

	-- 1. Apply Camera Recoil
	local camConfig = recoilConfig.Camera
	if camConfig.Physics then
		CamRotSpring.s = camConfig.Physics.Speed or 35
		CamRotSpring.d = camConfig.Physics.Damping or 0.85
		CamTransSpring.s = camConfig.Physics.Speed or 35
		CamTransSpring.d = camConfig.Physics.Damping or 0.85
	end

	local camPitch, camYaw = rollKick(camConfig)
	local camRoll = math.rad(math.random() * (camConfig.Roll[2] - camConfig.Roll[1]) + camConfig.Roll[1])
	local pushBack = camConfig.PushBack or 0.1

	-- Directly feed Radians to Spring (Pitch & Yaw from rollKick are converted to Radians here)
	CamRotSpring:Accelerate(Vector3.new(math.rad(camPitch), math.rad(camYaw), camRoll))
	CamTransSpring:Accelerate(Vector3.new(0, 0, pushBack))

	-- 2. Apply Weapon Model Recoil (If configured)
	local modelConfig = recoilConfig.Model
	if modelConfig then
		if modelConfig.Physics then
			ModelRotSpring.s = modelConfig.Physics.Speed or 18
			ModelRotSpring.d = modelConfig.Physics.Damping or 0.55
			ModelTransSpring.s = modelConfig.Physics.Speed or 18
			ModelTransSpring.d = modelConfig.Physics.Damping or 0.55
		end

		local modPitch, modYaw = rollKick(modelConfig)
		local modRoll = math.rad(math.random() * (modelConfig.Roll[2] - modelConfig.Roll[1]) + modelConfig.Roll[1])
		local kickBack = modelConfig.Kickback or 0.4

		ModelRotSpring:Accelerate(Vector3.new(math.rad(modPitch), math.rad(modYaw), modRoll))
		ModelTransSpring:Accelerate(Vector3.new(0, 0, kickBack))
	end
end

function RecoilController.ResetShotCount()
	consecutiveShots = 0
end

function RecoilController.Update(dt: number)
	local camRot = CamRotSpring:Update(dt)
	local camTrans = CamTransSpring:Update(dt)
	local modelRot = ModelRotSpring:Update(dt)
	local modelTrans = ModelTransSpring:Update(dt)

	return camRot, camTrans, modelRot, modelTrans
end

return RecoilController