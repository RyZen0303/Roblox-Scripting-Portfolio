# Roblox Gameplay Scripting Portfolio

Selected gameplay systems from **Land Warfare**, an independently developed and playable Roblox game.

This portfolio highlights gameplay engineering and performance-conscious Luau implementation.

## Main system

### Driving System

The complete `Driving System` folder is included:

- `TankDrivingMaster.luau` — tank movement, steering, braking, server-side input checks, network ownership handoff, and shared raycast filtering.
- `TankClientSuspension.luau` — client-side suspension/physics handling.
- `WheelVisualManager.luau` — wheel visual behavior.

Together, these scripts demonstrate vehicle gameplay systems, physics integration, raycasting, and performance-oriented data/state handling.

### Fire Control System (selected files)

Two related files are included:

- `ProjectileMaster.luau` — server-side projectile simulation, hit detection, driver/vehicle validation, reload control, damage routing, and NPC firing.
- `BulletVisualManager.luau` — client-side tracer rendering, trajectory updates, muzzle effects, and visual cleanup.

The server owns gameplay-relevant projectile behavior; clients render the replicated tracer visuals.

## Project context

These are selected code samples from **Land Warfare**, not a copy of the complete game. They rely on project-specific instances, attributes, RemoteEvents, collision groups, and asset hierarchy, so they are provided for code review rather than as drop-in packages.

## Development approach

I use AI tools as coding assistance. I am responsible for the game and system design, integrating the code into the project, testing behavior, investigating issues, and refining the implementation. This is an AI-assisted development workflow, not a claim that every line was written without assistance.

## Repository structure

```
Main system/
├── Driving System/
│   ├── TankClientSuspension.luau
│   ├── TankDrivingMaster.luau
│   └── WheelVisualManager.luau
└── Fire Control System/
    ├── ProjectileMaster.luau
    └── BulletVisualManager.luau
```
