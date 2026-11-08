-- WeaponConfigTemplate.luau
-- Template ModuleScript containing generic weapon specifications, fire modes, and recoil parameters

local Config = {
	-- Core Specs
	FireRate = 0.1, -- Seconds per shot (e.g., 0.1 for 600 RPM)
	BaseDamage = 35,
	AmmoPerMag = 30,
	MaxReserveAmmo = 240,
	ReloadTime = 3,
	BoltAction = false, -- Set true for weapons that require T to cycle the bolt after every shot

	-- Supported Fire Modes (Toggle features via Booleans)
	FireModes = {
		Available = {
			Semi = true,   -- Single shot mode enabled
			Auto = true,   -- Fully automatic mode enabled
			Burst = false, -- Burst fire mode enabled/disabled
		},
		DefaultMode = "Auto", -- Default selected mode upon equip

		-- Burst Fire Settings (Used only if Burst = true)
		BurstCount = 3,      -- Shots per burst
		BurstDelay = 0.25,   -- Cooldown delay between bursts (seconds)
	},

	-- Base Spread (Hipfire & ADS)
	Spread = {
		Hipfire = 1.8,
		ADS = 0.25,
	},

	-- Advanced Decoupled Procedural Recoil System (Phantom Forces Architecture)
	Recoil = {
		-- 1. Camera Recoil (Affects actual aiming - Tight & Controlled)
		Camera = {
			Pitch = {3.0, 4.5},    -- Upward camera pitch rotation (degrees)
			Yaw = {-1.2, 1.2},     -- Horizontal camera yaw rotation (degrees)
			Roll = {-0.8, 0.8},    -- Rotational camera roll angle (degrees)
			PushBack = 0.1,        -- Camera backward displacement force (studs)

			Physics = {
				Speed = 35,          -- Kick Stiffness (Fast reaction)
				RecoverySpeed = 50,  -- Recovery Stiffness (Ultra fast snap-back)
				Damping = 0.85,      -- High Damping (Prevents camera wobble)
			},
		},

		-- 2. Viewmodel Recoil (Pure Visual Juice - Heavy & Punchy)
		Model = {
			Pitch = {7.0, 10.0},   -- Gun barrel kick upward (degrees) - Punchy!
			Yaw = {-2.5, 2.5},     -- Gun model side sway (degrees)
			Roll = {-3.5, 3.5},    -- Gun model roll rotation (degrees)
			Kickback = 0.4,        -- Gun backward kick force into shoulder (studs)

			Physics = {
				Speed = 18,          -- Lower Stiffness (Allows big visual displacement)
				RecoverySpeed = 35,  -- Smooth recoil recovery
				Damping = 0.55,      -- Medium Damping (Juicy oscillation)
			},
		},
	},

	-- Viewmodel Animation IDs
	VM_Animations = {
		Idle = "rbxassetid://0",
		Fire = "rbxassetid://0",
		Reload = "rbxassetid://0",
		Equip = "rbxassetid://0",
		Holster = "rbxassetid://0",
		HoldDown = "rbxassetid://0",
	},

	-- Character Stance Animation IDs
	Animations = {
		Idle = "rbxassetid://0",
		Fire = "rbxassetid://0",
		Reload = "rbxassetid://0",
		Equip = "rbxassetid://0",
		Holster = "rbxassetid://0",
		HoldDown = "rbxassetid://0",
	},

	-- Audio IDs & Sound Names
	Sounds = {
		Fire = "Weapon_Fire",
		Reload = {
			MagOut = "Weapon_MagOut",
			MagIn = "Weapon_MagIn",
			Bolt = "Weapon_Bolt",
		},
		ReloadDelays = {
			MagOut = 0.2,
			MagIn = 1.8,
			Bolt = 2.4,
		},
		Equip = "Weapon_Equip",
	},

	-- Viewmodel & Aiming Settings
	ViewModel = {
		ModelName = "Viewmodel_Template",
		HipfireOffset = CFrame.new(0.6, -0.6, -1.2) * CFrame.Angles(0, math.rad(-90), 0),
		ADS_FOV = 40,
		ADS_Speed = 20,
	}
}

return Config