local Selection = game:GetService("Selection")
local selected = Selection:Get()[1]

if not selected or not (selected:IsA("Folder") or selected:IsA("Model")) then
	warn("Please select a Folder or Model in Explorer first!")
	return
end

local bodyPart = selected:FindFirstChild("Body", true) or selected:FindFirstChild("Main Hull", true) or selected.PrimaryPart

if not bodyPart or not bodyPart:IsA("BasePart") then
	warn("Could not find a BasePart named 'Body' or 'Main Hull' in the selected folder!")
	return
end

local count = 0
for _, desc in ipairs(selected:GetDescendants()) do
	if desc:IsA("BasePart") and desc ~= bodyPart then
		-- Remove any duplicate or existing WeldConstraints first
		for _, child in ipairs(desc:GetChildren()) do
			if child:IsA("WeldConstraint") then
				child:Destroy()
			end
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bodyPart
		weld.Part1 = desc
		weld.Parent = desc
		count += 1
	end
end

print("[Weld Complete]: Successfully welded " .. count .. " parts to " .. bodyPart.Name)
