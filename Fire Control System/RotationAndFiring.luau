-- // RotationAndFiring (Client-Side - Smooth Prediction & Fixed Mobile Touch) //
-- Location: StarterPlayerScripts / TankPlayerController
-- Optimized to work safely with Server-owned vehicle physics [SetNetworkOwner(nil)]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local isTouch = UserInputService.TouchEnabled
local camera = workspace.CurrentCamera
local originalFOVMode = camera.FieldOfViewMode
local player = Players.LocalPlayer

-- // Resource Links //
local TankModule = require(ReplicatedStorage:WaitForChild("TankModule"))
local UpdateEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("UpdateTurret")
local FireEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("FireEvent")

-- // UI & Signal Communication //
local TankEvents = script.Parent:WaitForChild("TankEvents")
local UIUpdateEvent = TankEvents:WaitForChild("UIUpdate")
local TankCommandEvent = TankEvents:FindFirstChild("TankCommand") or Instance.new("BindableEvent", TankEvents)
TankCommandEvent.Name = "TankCommand"

-- // Configuration & Timers //
local updateRate = 1/30
local lastUpdate = 0

-- // States //
local isFreeCam, isCurrentlyDriving = true, false
local currentWeapon = "Cannon"
local isFiring = false
local currentAimPoint = Vector3.new(0,0,0)

-- [[ FOV CONFIGURATION ]]
local FOV_DEFAULT = 70
local FOV_MIN = 12
local currentFOV = 70

-- [[ PERFORMANCE CACHE REGISTERS ]] --
local cachedModel = nil
local cachedScopePart = nil
local cachedMuzzleParts = {}
local staticRayParams = RaycastParams.new()

-- [[ MOBILE TOUCH SMOOTHING REGISTERS ]] --
local lastTouchPos = nil
local touchDeltaX, touchDeltaY = 0, 0
-- Combined Sensitivity Base for Mobile vs PC
local sensitivityBase = 0.25
local mobileSensitivity = 0.85

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isTouch then return end
	if input.UserInputType == Enum.UserInputType.Touch then
		lastTouchPos = input.Position
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if processed or not isTouch or not lastTouchPos then return end
	if input.UserInputType == Enum.UserInputType.Touch then
		local currentPos = input.Position
		-- Accumulate deltas continuously to guarantee smooth tracking on mobile screens
		touchDeltaX = touchDeltaX + (currentPos.X - lastTouchPos.X)
		touchDeltaY = touchDeltaY + (currentPos.Y - lastTouchPos.Y)
		lastTouchPos = currentPos
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		lastTouchPos = nil
	end
end)

-- // UI Syncing //
local function syncUI()
	UIUpdateEvent:Fire({Type = "UpdateAimMode", IsFreeCam = isFreeCam})
	UIUpdateEvent:Fire({Type = "UpdateZoomValue", Value = currentFOV})
	UIUpdateEvent:Fire({Type = "MobileButtons", IsFreeCam = isFreeCam})
	UIUpdateEvent:Fire({Type = "UpdateWeapon", Weapon = currentWeapon})
end

-- // Action Handlers //
local function toggleAim()
	if not isCurrentlyDriving then return end
	isFreeCam = not isFreeCam
	if not isTouch then
		UserInputService.MouseIconEnabled = isFreeCam
		UserInputService.MouseBehavior = isFreeCam and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
	end
	if isFreeCam then currentFOV = FOV_DEFAULT end
	syncUI()
end

local function toggleZoom()
	if not isCurrentlyDriving or isFreeCam then return end
	currentFOV = (currentFOV >= FOV_DEFAULT) and FOV_MIN or FOV_DEFAULT
	syncUI()
end

UserInputService.InputChanged:Connect(function(input, gpe)
	if gpe or isFreeCam or not isCurrentlyDriving or isTouch then return end
	if currentFOV < FOV_DEFAULT and input.UserInputType == Enum.UserInputType.MouseWheel then
		if input.Position.Z > 0 then
			currentFOV = math.clamp(currentFOV - 4, FOV_MIN, FOV_DEFAULT)
		else
			currentFOV = math.clamp(currentFOV + 4, FOV_MIN, FOV_DEFAULT)
		end
		syncUI()
	end
end)

local function toggleWeapon()
	if not isCurrentlyDriving then return end
	currentWeapon = (currentWeapon == "Cannon") and "CoaxialMG" or "Cannon"
	syncUI()
end

-- // CORE FIRE HANDLER //
local function handleFire(inputState)
	if inputState == Enum.UserInputState.Begin and isCurrentlyDriving then
		if isFiring then return end
		isFiring = true
		task.spawn(function()
			while isFiring and isCurrentlyDriving do
				local char = player.Character
				local tankData = TankModule.GetTankData(char and char:FindFirstChildOfClass("Humanoid"))
				if tankData then
					local currentMuzzle = cachedMuzzleParts[currentWeapon]

					if currentMuzzle then
						local clientMuzzlePos = currentMuzzle.Position
						local weaponPart = cachedModel:FindFirstChild(currentWeapon, true)
						local cannon = weaponPart and (weaponPart:FindFirstChild("Cannon", true) or weaponPart)
						local directionVector = cannon and -cannon.CFrame.UpVector.Unit or -currentMuzzle.CFrame.UpVector.Unit

						FireEvent:FireServer(currentWeapon, currentAimPoint, clientMuzzlePos, directionVector)
					else
						local lookDir = (currentAimPoint - camera.CFrame.Position).Unit
						FireEvent:FireServer(currentWeapon, currentAimPoint, currentAimPoint, lookDir)
					end
				else
					isFiring = false break
				end
				if currentWeapon == "CoaxialMG" then task.wait(0.1) else isFiring = false end
			end
		end)
	elseif inputState == Enum.UserInputState.End then
		isFiring = false
	end
end

-- // COMMAND LISTENER //
TankCommandEvent.Event:Connect(function(data)
	if not isCurrentlyDriving then return end
	if data.InputType == Enum.UserInputType.MouseButton2 then return end

	if data.Type == "TriggerAim" then toggleAim()
	elseif data.Type == "TriggerZoom" then toggleZoom()
	elseif data.Type == "TriggerFire" then handleFire(data.State and Enum.UserInputState.Begin or Enum.UserInputState.End)
	elseif data.Type == "ToggleWeapon" then toggleWeapon()
	end
end)

-- // Main Update Loop Setup //
local lastDrivingState = false
local currentTraverse, currentElevation = 0, 0

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local tankData = TankModule.GetTankData(humanoid)
	isCurrentlyDriving = (tankData ~= nil)

	if not isCurrentlyDriving then
		if lastDrivingState then
			UserInputService.MouseIconEnabled = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfViewMode = originalFOVMode
			camera.CameraSubject = humanoid
			if humanoid then humanoid.CameraOffset = Vector3.new(0, 0, 0) end
			UIUpdateEvent:Fire({Type = "ToggleScreen", Value = false})
			isFreeCam, isFiring = true, false
			currentFOV = FOV_DEFAULT
			camera.FieldOfView = FOV_DEFAULT

			cachedModel, cachedScopePart = nil, nil
			table.clear(cachedMuzzleParts)

			lastDrivingState = false
		end
		return
	end

	local model = tankData.Model
	local turretHinge = tankData.TurretHinge
	local elevHinge = tankData.ElevationHinge

	if not lastDrivingState then
		cachedModel = model
		cachedScopePart = model:FindFirstChild("ScopePart", true)

		local cannonPart = model:FindFirstChild("Cannon", true)
		local mgPart = model:FindFirstChild("CoaxialMG", true)

		cachedMuzzleParts["Cannon"] = cannonPart and (cannonPart:FindFirstChild("Muzzle", true) or cannonPart)
		cachedMuzzleParts["CoaxialMG"] = mgPart and (mgPart:FindFirstChild("Muzzle", true) or mgPart)

		-- [[  FIXED: ลอจิกเจาะกำแพงล่องหน CaptureZones ]]
		staticRayParams.FilterType = Enum.RaycastFilterType.Exclude
		
		local excludeList = {model, char}
		local captureZonesFolder = workspace:FindFirstChild("CaptureZones")
		if captureZonesFolder then
			table.insert(excludeList, captureZonesFolder) -- จับยัดโฟลเดอร์โซนเข้าลิสต์ล่องหน
		end
		
		staticRayParams.FilterDescendantsInstances = excludeList

		local camHeight = model:GetAttribute("CamHeight") or 10
		UIUpdateEvent:Fire({Type = "ToggleScreen", Value = true})
		syncUI()
		if humanoid then
			camera.CameraSubject = humanoid
			humanoid.CameraOffset = Vector3.new(0, camHeight, 0)
		end
		if turretHinge then currentTraverse = turretHinge.CurrentAngle end
		if elevHinge then currentElevation = elevHinge.CurrentAngle end
		lastDrivingState = true
	end

	local gunRoot = model:FindFirstChild("GunRoot", true)
	local maxElev = gunRoot and gunRoot:GetAttribute("MaxElevation") or 20
	local maxDep = gunRoot and gunRoot:GetAttribute("MaxDepression") or -15

	local scopePart = cachedScopePart
	local muzzle = cachedMuzzleParts[currentWeapon]

	if not isFreeCam and currentFOV < (FOV_DEFAULT - 10) and scopePart then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
		camera.CFrame = scopePart.CFrame
		camera.FieldOfView = currentFOV

		local fovRatio = (currentFOV / FOV_DEFAULT)
		local currentSens = sensitivityBase * fovRatio
		local finalDeltaX, finalDeltaY = 0, 0

		if isTouch then
			-- [[ FIXED MOBILE TOUCH DELTA GATHERING ]] --
			finalDeltaX = touchDeltaX * mobileSensitivity * currentSens
			finalDeltaY = touchDeltaY * mobileSensitivity * currentSens
			touchDeltaX, touchDeltaY = 0, 0
		else
			local pcDelta = UserInputService:GetMouseDelta()
			finalDeltaX = pcDelta.X * currentSens
			finalDeltaY = pcDelta.Y * currentSens
		end

		currentTraverse = currentTraverse - finalDeltaX
		currentElevation = math.clamp(currentElevation - finalDeltaY, maxDep, maxElev)

		currentAimPoint = muzzle and muzzle.Position + (-muzzle.CFrame.UpVector * 1000) or scopePart.Position + (scopePart.CFrame.LookVector * 1000)
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfViewMode = isFreeCam and originalFOVMode or Enum.FieldOfViewMode.Vertical
		camera.FieldOfView = isFreeCam and FOV_DEFAULT or currentFOV
		if not isFreeCam then
			local screenRay = camera:ViewportPointToRay(camera.ViewportSize.X/2, camera.ViewportSize.Y/2)

			local castResult = workspace:Raycast(screenRay.Origin, screenRay.Direction * 1000, staticRayParams)
			local mouseWorldPoint = castResult and castResult.Position or (screenRay.Origin + screenRay.Direction * 1000)
			local traverse, elevation = TankModule.CalculateAnglesToPoint(mouseWorldPoint, turretHinge, elevHinge)

			currentTraverse = traverse
			currentElevation = math.clamp(elevation, maxDep, maxElev)
			currentAimPoint = muzzle and muzzle.Position + (-muzzle.CFrame.UpVector * 1000) or mouseWorldPoint
		end
	end

	-- [[ CLIENT-SIDE VISUAL PREDICTION REPLICATION ]] --
	if turretHinge then turretHinge.TargetAngle = currentTraverse end
	if elevHinge then elevHinge.TargetAngle = currentElevation end

	-- Send the target markers upstream on set intervals
	lastUpdate = lastUpdate + dt
	if lastUpdate >= updateRate then
		lastUpdate = 0
		UpdateEvent:FireServer(model, currentTraverse, currentElevation)
	end
end)
