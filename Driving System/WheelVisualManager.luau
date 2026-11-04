-- [[ TankVisuals Controller (Client-Side Optimization - Fixed Wheel Movement) ]] --
-- Location: StarterPlayerScripts / Client Modules

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local DEFAULT_RADIUS = 1.85
local DEFAULT_RAY = 5.0
local DEFAULT_COMPRESSION = 0.4
local DEFAULT_TRACK_WIDTH = 4.3

local MAX_RENDER_DISTANCE = 400
local FORCE_RENDER_DISTANCE = 120 
local VISIBILITY_FRAME_STEP = 4 

local PRIMARY_PART_TIMEOUT = 10
local REPLICATION_SETTLE_TIMEOUT = 5
local SETTLE_CHECK_INTERVAL = 0.1
local SETTLE_STABLE_CHECKS = 3
local PENDING_RETRY_INTERVAL = 0.5
local PENDING_RETRY_MAX_DURATION = 8

local function waitForPrimaryPart(tank, timeout)
	local startTime = os.clock()
	while not tank.PrimaryPart do
		if (os.clock() - startTime) > timeout then return nil end
		task.wait(0.1)
	end
	return tank.PrimaryPart
end

local function waitForReplicationSettle(instance, timeout)
	local startTime = os.clock()
	local lastCount = -1
	local stableChecks = 0

	while (os.clock() - startTime) < timeout do
		local count = #instance:GetDescendants()
		if count == lastCount then
			stableChecks += 1
			if stableChecks >= SETTLE_STABLE_CHECKS then return true end
		else
			stableChecks = 0
			lastCount = count
		end
		task.wait(SETTLE_CHECK_INTERVAL)
	end
	return false
end

local function setupTankVisuals(tank)
	local hull = waitForPrimaryPart(tank, PRIMARY_PART_TIMEOUT)
	if not hull then return end

	waitForReplicationSettle(tank, REPLICATION_SETTLE_TIMEOUT)

	local attrSource = tank:FindFirstChild("Visual Wheels", true) or tank
	local visualData = {}
	local boundModels = {}
	local pendingVisualModels = {}
	local processedWheelParts = {}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {tank}

	local hullAttachments = {}
	local function refreshHullAttachments()
		table.clear(hullAttachments)
		for _, child in ipairs(hull:GetDescendants()) do
			if child:IsA("Attachment") then
				table.insert(hullAttachments, child)
			end
		end
	end
	refreshHullAttachments()

	local function bindSingleVisualModel(vModel)
		if boundModels[vModel] then return true end

		local isModel = vModel:IsA("Model")
		local isPart = vModel:IsA("BasePart")
		if not (isModel or isPart) then return false end
		if not vModel.Name:lower():find("_visual") then return false end

		local vPos = isModel and vModel:GetPivot().Position or vModel.Position
		local targetAtt = nil
		local isInner = vModel.Name:lower():find("inner")

		if isInner then
			local attName = vModel.Name:gsub("_Inner_Visual", "_Att"):gsub("_inner_visual", "_Att")
			targetAtt = hull:FindFirstChild(attName, true)
		end

		if not targetAtt and #hullAttachments > 0 then
			local shortestDistance = math.huge
			for _, att in ipairs(hullAttachments) do
				local dist = (vPos - att.WorldPosition).Magnitude
				if dist < shortestDistance then
					shortestDistance = dist
					targetAtt = att
				end
			end
		end

		if not targetAtt then return false end

		-- Anchor and disable collision for Visual parts to save physics performance
		if isModel then
			for _, p in ipairs(vModel:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
				end
			end
		else
			vModel.Anchored, vModel.CanCollide, vModel.CanTouch, vModel.CanQuery = true, false, false, false
		end

		local localPosOffset = targetAtt.Position
		local relativeRot = targetAtt.CFrame.Rotation

		local nameLower = vModel.Name:lower()
		local sideSign = (nameLower:find("_l_") or nameLower:find("left")) and -1 or 1
		if not (nameLower:find("_l_") or nameLower:find("left") or nameLower:find("_r_") or nameLower:find("right")) then
			sideSign = math.sign(localPosOffset.X)
		end

		local yFlip = (sideSign == 1) and math.pi or 0

		table.insert(visualData, {
			instance = vModel,
			isModel = isModel,
			localOffset = localPosOffset,
			hullRelativeRot = relativeRot,
			currentRotation = 0,
			side = sideSign,
			yFlip = yFlip,
			name = vModel.Name,
			lastOffset = 0,
			isSprocketOrIdler = nameLower:find("sprocket") or nameLower:find("idler")
		})

		boundModels[vModel] = true
		pendingVisualModels[vModel] = nil
		return true
	end

	local function isolatePhysicalWheel(part)
		if processedWheelParts[part] or not part:IsA("BasePart") then return end
		local nameLower = part.Name:lower()
		if (nameLower:find("wheel") or nameLower:find("sprocket") or nameLower:find("idler")) and not part.Name:find("_Visual") then
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
			part.Transparency = 1
			processedWheelParts[part] = true
		end
	end

	for _, child in ipairs(tank:GetDescendants()) do
		if child.Name:lower():find("_visual") then
			if not bindSingleVisualModel(child) then
				pendingVisualModels[child] = true
			end
		end
	end

	for _, part in ipairs(tank:GetDescendants()) do
		isolatePhysicalWheel(part)
	end

	local function retryPending()
		if not next(pendingVisualModels) then return end
		for vModel in pairs(pendingVisualModels) do
			bindSingleVisualModel(vModel)
		end
	end

	local reconcileQueued = false
	local function scheduleReconcile()
		if reconcileQueued then return end
		reconcileQueued = true
		task.defer(function()
			reconcileQueued = false
			refreshHullAttachments()
			retryPending()
		end)
	end

	local connections = {}

	connections.descendantAdded = tank.DescendantAdded:Connect(function(inst)
		if inst:IsA("Attachment") then
			scheduleReconcile()
		elseif inst.Name:lower():find("_visual") then
			pendingVisualModels[inst] = true
			scheduleReconcile()
		elseif inst:IsA("BasePart") then
			isolatePhysicalWheel(inst)
			if next(pendingVisualModels) then scheduleReconcile() end
		end
	end)

	task.spawn(function()
		local elapsed = 0
		while elapsed < PENDING_RETRY_MAX_DURATION and next(pendingVisualModels) and tank:IsDescendantOf(workspace) do
			task.wait(PENDING_RETRY_INTERVAL)
			elapsed += PENDING_RETRY_INTERVAL
			refreshHullAttachments()
			retryPending()
		end
	end)

	local function computeWheelCFrame(hullCF, data)
		local offset = data.localOffset + Vector3.new(0, data.lastOffset, 0)
		return hullCF * CFrame.new(offset) * CFrame.Angles(data.currentRotation, data.yFlip, 0) * data.hullRelativeRot
	end

	local clientFrameOffset = 0
	local visibilityCounter = 0
	local isCulled = false

	connections.renderStepped = RunService.RenderStepped:Connect(function(dt)
		if not tank:IsDescendantOf(workspace) or not hull.Parent then return end

		local hullCF = hull.CFrame
		local myChar = localPlayer.Character
		local myRoot = myChar and myChar.PrimaryPart

		local refPos = myRoot and myRoot.Position or (camera and camera.CFrame.Position or Vector3.zero)
		local isMyTank = (myChar and tank:IsAncestorOf(myChar)) or (tank:GetAttribute("Owner") == localPlayer.Name)

		local distToHull = (hullCF.Position - refPos).Magnitude

		if isMyTank or distToHull <= FORCE_RENDER_DISTANCE then
			isCulled = false
		else
			visibilityCounter = (visibilityCounter + 1) % VISIBILITY_FRAME_STEP
			if visibilityCounter == 0 then
				isCulled = (distToHull > MAX_RENDER_DISTANCE)
			end
		end

		if isCulled then
			for _, data in ipairs(visualData) do
				if data.instance and data.instance.Parent then
					local targetCF = computeWheelCFrame(hullCF, data)
					if data.isModel then
						data.instance:PivotTo(targetCF)
					else
						data.instance.CFrame = targetCF
					end
				end
			end
			return
		end

		local radius = attrSource:GetAttribute("WheelRadius") or DEFAULT_RADIUS
		local rayL = attrSource:GetAttribute("RayLength") or DEFAULT_RAY
		local compress = attrSource:GetAttribute("MaxCompression") or DEFAULT_COMPRESSION
		local tWidth = attrSource:GetAttribute("TrackWidth") or DEFAULT_TRACK_WIDTH

		local velocityPart = tank:FindFirstChild("DriverSeat", true) or tank.PrimaryPart or hull
		local forwardVel = velocityPart.AssemblyLinearVelocity:Dot(hullCF.LookVector)
		local turningVel = (velocityPart.AssemblyAngularVelocity.Y * (tWidth / 2)) * 12

		clientFrameOffset = (clientFrameOffset + 1) % 2

		for idx, data in ipairs(visualData) do
			if data.instance and data.instance.Parent then
				-- Calculate wheel rotation based on vehicle speed
				data.currentRotation = data.currentRotation - (((forwardVel + (turningVel * data.side)) / radius) * dt)

				-- Raycast to check ground clearance (alternate frames to save CPU)
				if not data.isSprocketOrIdler then
					if (idx % 2) == clientFrameOffset then
						local origin = hullCF:PointToWorldSpace(data.localOffset)
						local ray = workspace:Raycast(origin, -hullCF.UpVector * rayL, params)
						if ray then
							local targetOffset = math.clamp(((ray.Position + (hullCF.UpVector * radius)) - origin):Dot(hullCF.UpVector), 0, compress)
							data.lastOffset = data.lastOffset + (targetOffset - data.lastOffset) * 0.35
						else
							data.lastOffset = data.lastOffset + (0 - data.lastOffset) * 0.35
						end
					end
				end

				-- Update wheel position relative to the hull
				local targetCF = computeWheelCFrame(hullCF, data)
				if data.isModel then
					data.instance:PivotTo(targetCF)
				else
					data.instance.CFrame = targetCF
				end
			end
		end
	end)

	local function cleanup()
		for _, conn in pairs(connections) do
			conn:Disconnect()
		end
	end

	tank.Destroying:Connect(cleanup)
	tank.AncestryChanged:Connect(function(_, parent)
		if not parent then cleanup() end
	end)
end

local function onModelAdded(m)
	if m:IsA("Model") and m.Parent == workspace and m:GetAttribute("IsTank") then
		task.spawn(setupTankVisuals, m)
	end
end

for _, m in ipairs(workspace:GetChildren()) do onModelAdded(m) end
workspace.ChildAdded:Connect(onModelAdded)
