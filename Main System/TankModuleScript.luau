local TankModule = {}

-- 1. Function to retrieve the tank and its components (Shared by Turret and Cannon)
function TankModule.GetTankData(humanoid)
	local seat = humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then return nil end

	local tankModel = seat:FindFirstAncestorOfClass("Model")
	if not tankModel or tankModel == workspace then return nil end

	return {
		Model = tankModel,
		Cannon = tankModel:FindFirstChild("Cannon", true),
		TurretRoot = tankModel:FindFirstChild("TurretRoot", true),
		GunRoot = tankModel:FindFirstChild("GunRoot", true),
		-- Pre-fetch Hinges to avoid repetitive searching
		TurretHinge = tankModel:FindFirstChild("TurretRoot", true) and tankModel:FindFirstChild("TurretRoot", true):FindFirstChild("HingeConstraint", true),
		ElevationHinge = tankModel:FindFirstChild("GunRoot", true) and tankModel:FindFirstChild("GunRoot", true):FindFirstChild("HingeConstraint", true)
	}
end

-- 2. Function to calculate turret angles
function TankModule.CalculateAngles(lookDirection, turretHinge, elevationHinge)
	if not turretHinge or not elevationHinge then return 0, 0 end

	-- Horizontal (Left/Right Traverse)
	local angle = math.atan2(-lookDirection.X, -lookDirection.Z)
	local hullRotation = math.rad(turretHinge.Attachment0.WorldOrientation.Y)
	local finalTraverse = math.deg(angle - hullRotation)

	-- Vertical (Up/Down Elevation)
	local elevationAngle = math.asin(lookDirection.Y)
	local turretPitch = math.rad(elevationHinge.Attachment0.WorldOrientation.X)
	local finalElevation = math.deg(elevationAngle - turretPitch)

	return finalTraverse, finalElevation
end

return TankModule