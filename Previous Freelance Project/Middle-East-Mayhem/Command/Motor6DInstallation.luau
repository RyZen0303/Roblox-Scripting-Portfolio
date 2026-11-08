local vm = game:GetService("Selection"):Get()[1]
if not vm then 
	warn("Please click and select Viewmodel_AK-47 in the Explorer before running the script!") 
	return 
end

-- 1. Find the main part of the gun (Body or Handle)
local gunBody = vm:FindFirstChild("Body", true) or vm:FindFirstChild("Handle", true)
if not gunBody then
	warn("Could not find a part named 'Body' or 'Handle'!")
	return
end

-- 2. Delete old Motor6Ds first to prevent conflicts
for _, desc in ipairs(vm:GetDescendants()) do
	if desc:IsA("Motor6D") then
		desc:Destroy()
	end
end

-- 3. Find left and right arms across all hierarchical levels (recursive = true)
local leftArm = vm:FindFirstChild("LeftArm", true) or vm:FindFirstChild("Left Arm", true)
local rightArm = vm:FindFirstChild("RightArm", true) or vm:FindFirstChild("Right Arm", true)

local count = 0

-- 4. Function to create Motor6D while automatically calculating C0
local function attachWithMotor(arm, name)
	if arm and arm:IsA("BasePart") then
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = arm
		motor.Part1 = gunBody
		-- Calculate C0 from the current actual position so parts do not warp
		motor.C0 = arm.CFrame:ToObjectSpace(gunBody.CFrame)
		motor.C1 = CFrame.new()
		motor.Parent = arm
		count += 1
	end
end

attachWithMotor(leftArm, "LeftArmToGun")
attachWithMotor(rightArm, "RightArmToGun")

if count > 0 then
	print(string.format("[SUCCESS]: Successfully bound Motor6D for %d arm(s)! Original positions are preserved.", count))
else
	warn("Arms not found! Please check that the part names are 'LeftArm' and 'RightArm'.")
end
