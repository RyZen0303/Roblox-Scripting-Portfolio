-- // TankInput Controller (Turbo Optimized & Chorded-Input Edition) //
-- Managed via StarterPlayerScripts
-- Controls movement input logic, network throttling, and combat action piping

local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Player = game.Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- [[ DEVICE & STATE CONFIGURATIONS ]] --
local isTouch = UIS.TouchEnabled 
local isAimModeActive = false   

-- [[ NETWORKING & COMMUNICATION SETUP ]] --
local EventsFolder = ReplicatedStorage:WaitForChild("Events")
local TankControlEvent = EventsFolder:WaitForChild("TankControlEvent")
local TankEvents = script.Parent:WaitForChild("TankEvents", 10)
local UIUpdateEvent = TankEvents:WaitForChild("UIUpdate")

local TankCommandEvent = TankEvents:FindFirstChild("TankCommand") or Instance.new("BindableEvent", TankEvents)
TankCommandEvent.Name = "TankCommand"

-- [[ INPUT ACCUMULATION STATE ]] --
local throttle, steer = 0, 0
local keysHeld = {[Enum.KeyCode.W] = false, [Enum.KeyCode.S] = false, [Enum.KeyCode.A] = false, [Enum.KeyCode.D] = false}

local lastSentThrottle, lastSentSteer = 0, 0
local lastSentTarget = Vector3.new()
local lastNetworkUpdate = 0
local NETWORK_TICK_RATE = 1 / 20 -- Strict 20Hz baseline (0.05s) to eliminate packet race-conditions

-- [[ RETICLE & WORLD POSITION CALCULATION ]] --
local function getTargetPosition()
	if isTouch and isAimModeActive then
		return Camera.CFrame.Position + (Camera.CFrame.LookVector * 1000)
	end

	local screenCenter = Camera.ViewportSize / 2
	local unitRay = Camera:ScreenPointToRay(screenCenter.X, screenCenter.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {Player.Character, workspace:FindFirstChild("Tanks")} 
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)
	return result and result.Position or (unitRay.Origin + (unitRay.Direction * 1000))
end

-- Replace sendNetworkUpdate in TankInput
local function sendNetworkUpdate(force)
	local now = tick()
	if now - lastNetworkUpdate < NETWORK_TICK_RATE and not force then return end -- Strictly throttle rate

	local currentTarget = getTargetPosition()
	local inputChanged = (throttle ~= lastSentThrottle or steer ~= lastSentSteer)
	local targetMoved = (currentTarget - lastSentTarget).Magnitude > 3

	if force or inputChanged or targetMoved then
		TankControlEvent:FireServer(throttle, steer, currentTarget)
		lastSentThrottle = throttle
		lastSentSteer = steer
		lastSentTarget = currentTarget
		lastNetworkUpdate = now
	end
end

-- [[ CORE INPUT ACCUMULATION ENGINE ]] --
local function updateInputs()
	-- Extract stable instantaneous states from key registry map
	local w = keysHeld[Enum.KeyCode.W] and 1 or 0
	local s = keysHeld[Enum.KeyCode.S] and 1 or 0
	local a = keysHeld[Enum.KeyCode.A] and 1 or 0
	local d = keysHeld[Enum.KeyCode.D] and 1 or 0

	throttle = w - s

	-- [[ FIXED: Uniform steering input mapping matrix ]]
	-- Completely eliminated the dynamic inverse steering lookup during backward throttling.
	-- This prevents vector toggling glitches that trick the server-side transmission master into an infinite shifting lockout.
	-- Pressing D strictly processes positive right-steer (1) and A processes negative left-steer (-1) uniformly.
	steer = d - a 

	-- Sync variables to network engine safely
	Player:SetAttribute("TankThrottle", throttle)
	Player:SetAttribute("TankSteer", steer)
end

-- [[ PC HARDWARE CONTROLS LISTENERS ]] --
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end

	if keysHeld[input.KeyCode] ~= nil then
		keysHeld[input.KeyCode] = true
		updateInputs()
		sendNetworkUpdate(false) -- Wiped aggressive hard forcing to let multi-key binds buffer cleanly in frame
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.F then 
		TankCommandEvent:Fire({Type = "TriggerFire", State = true})
	elseif input.KeyCode == Enum.KeyCode.L then 
		TankCommandEvent:Fire({Type = "TriggerAim"}) 
	elseif input.KeyCode == Enum.KeyCode.C then 
		TankCommandEvent:Fire({Type = "ToggleWeapon"}) 
	elseif input.KeyCode == Enum.KeyCode.X then 
		TankCommandEvent:Fire({Type = "TriggerZoom"}) 
	end
end)

UIS.InputEnded:Connect(function(input)
	if keysHeld[input.KeyCode] ~= nil then
		keysHeld[input.KeyCode] = false
		updateInputs()
		sendNetworkUpdate(false)
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.F then
		TankCommandEvent:Fire({Type = "TriggerFire", State = false})
	end
end)

-- // MOBILE & CROSS-INTERFACE UI TRANSLATION LISTENERS //
UIUpdateEvent.Event:Connect(function(data)
	if data.Type == "DriveInput" then
		local keyName = data.Key and string.upper(data.Key)
		local key = Enum.KeyCode[keyName]

		if key and keysHeld[key] ~= nil then
			keysHeld[key] = data.State 
			updateInputs()
			sendNetworkUpdate(false)
		end

	elseif data.Type == "TriggerFire" then
		TankCommandEvent:Fire({Type = "TriggerFire", State = data.State})

	elseif data.Type == "TriggerAim" or data.Type == "TriggerZoom" or data.Type == "ToggleWeapon" then
		TankCommandEvent:Fire(data)

	elseif data.Type == "UpdateAimMode" then
		isAimModeActive = not data.IsFreeCam
	end
end)

-- [[ FRAME-RATE INDEPENDENT TICK REPLICATION LOOP ]] --
RunService.Heartbeat:Connect(function()
	-- Cleanly streams physics position vectors without micro-stutter pipeline floods
	sendNetworkUpdate(false)
end)
