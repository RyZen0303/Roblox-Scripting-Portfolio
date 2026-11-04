-- // Visual Tracer Manager (Client-Side) //
-- Handles both Muzzle Smoke and Bullet Tracers with precise positioning
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local RenderBulletEvent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RenderBullet")

-- [ASSETS PATH]: Direct access to the ParticleEmitter
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Visuals = Assets:WaitForChild("Visuals")
local MuzzleParticle = Visuals:WaitForChild("MuzzleEffects")

-- // ACTIVE TRACERS //
local activeTracers = {}

RenderBulletEvent.OnClientEvent:Connect(function(action, bulletId, muzzle, spawnPos, velocity, damageType, gravityMultiplier)
	-- // 1. DESTROY BULLET TRACER //
	if action == "DestroyVisual" then
		local tracerData = activeTracers[bulletId]

		if tracerData then
			tracerData.Part:Destroy()
			activeTracers[bulletId] = nil
		end

		return
	end

	-- // 2. VALIDATE BULLET DATA //
	if action ~= "Spawn" then
		return
	end

	if typeof(bulletId) ~= "string"
		or typeof(spawnPos) ~= "Vector3"
		or typeof(velocity) ~= "Vector3"
		or typeof(damageType) ~= "string" then
		return
	end

	-- // 3. MUZZLE SMOKE EFFECT //
	-- Smoke spawns exactly at the muzzle position
	if MuzzleParticle and MuzzleParticle:IsA("ParticleEmitter") and muzzle then
		local muzzlePos

		if muzzle:IsA("Attachment") then
			muzzlePos = muzzle.WorldPosition
		elseif muzzle:IsA("BasePart") then
			muzzlePos = muzzle.Position
		end

		if muzzlePos then
			local effectPart = Instance.new("Part")
			effectPart.Name = "Temp_MuzzlePoint"
			effectPart.Size = Vector3.new(0.1, 0.1, 0.1)
			effectPart.Transparency = 1
			effectPart.CanCollide = false
			effectPart.CanQuery = false
			effectPart.CanTouch = false
			effectPart.Anchored = true

			-- Place exactly at the muzzle position
			effectPart.CFrame = CFrame.lookAt(muzzlePos, muzzlePos + velocity)
			effectPart.Parent = workspace

			local pClone = MuzzleParticle:Clone()
			pClone.Parent = effectPart

			-- Emit particles based on your Attribute
			pClone:Emit(pClone:GetAttribute("EmitCount") or 45)

			-- Cleanup the smoke anchor
			Debris:AddItem(effectPart, 2)
		end
	end

	-- // 4. BULLET TRACER RENDERING //
	-- Tracer starts at the offset position to avoid clipping
	local isMG = (damageType == "Light")
	local bulletSize = isMG and Vector3.new(0.15, 0.15, 4) or Vector3.new(0.5, 0.5, 1.5)
	local bulletColor = isMG and BrickColor.new("Neon orange") or BrickColor.new("Bright yellow")

	local tracer = Instance.new("Part")
	tracer.Name = "Visual_Tracer"
	tracer.Size = bulletSize
	tracer.BrickColor = bulletColor
	tracer.Material = Enum.Material.Neon
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.Anchored = true

	-- Align tracer with firing direction starting from the spawn point
	tracer.CFrame = CFrame.lookAt(spawnPos, spawnPos + velocity)
	tracer.Parent = workspace

	-- Store trajectory data for client-side rendering
	activeTracers[bulletId] = {
		Part = tracer,
		StartPosition = spawnPos,
		StartVelocity = velocity,
		StartTime = os.clock(),
		GravityMultiplier = gravityMultiplier or 0.9
	}

	-- Safety cleanup if the server never sends DestroyVisual
	task.delay(5, function()
		local tracerData = activeTracers[bulletId]

		if tracerData and tracerData.Part == tracer then
			activeTracers[bulletId] = nil
			tracer:Destroy()
		end
	end)
end)

-- // 5. BULLET TRAJECTORY RENDERING //
-- Match the server projectile's reduced gravity
RunService.RenderStepped:Connect(function()
	for bulletId, tracerData in pairs(activeTracers) do
		local tracer = tracerData.Part

		if not tracer.Parent then
			activeTracers[bulletId] = nil
			continue
		end

		local elapsed = os.clock() - tracerData.StartTime
		local gravity = workspace.Gravity * (1 - tracerData.GravityMultiplier)

		local currentPosition = tracerData.StartPosition
			+ tracerData.StartVelocity * elapsed
		- Vector3.new(0, 0.5 * gravity * elapsed * elapsed, 0)

		local currentVelocity = tracerData.StartVelocity
		- Vector3.new(0, gravity * elapsed, 0)

		-- Keep the tracer aligned with its current flight direction
		if currentVelocity.Magnitude > 0 then
			tracer.CFrame = CFrame.lookAt(
				currentPosition,
				currentPosition + currentVelocity
			)
		else
			tracer.Position = currentPosition
		end
	end
end)
