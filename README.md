# Roblox Gameplay Scripting Portfolio

Selected Luau systems from **Land Warfare**, an independently developed Roblox game.

This portfolio focuses on gameplay engineering, server/client architecture, physics, and performance-conscious implementation.

## Featured code samples

### 1. Tank Driving System
**File:** [`TankDrivingMaster.luau`](Main%20system/TankDrivingMaster.luau)

A tank movement and suspension controller. This sample demonstrates:

- Centralized raycast filtering shared across tanks, with periodic refresh and descendant tracking.
- Cached physical properties and per-tank state/configuration to reduce repeated work and allocations.
- Heartbeat-driven movement, steering, braking, and suspension calculations.
- Dynamic network ownership handoff between the active driver and server.
- Input handling for player-controlled tanks and attribute-driven NPC movement.

### 2. Projectile / Fire Control System
**File:** [`ProjectileMaster.luau`](Main%20system/ProjectileMaster.luau)

A server-side projectile controller featuring:

- Server-created projectile hitboxes and server-side raycast hit detection.
- Collision-group assignment and filtering for projectile interactions.
- Remote-event request handling with driver/vehicle checks.
- Reload-state control, damage routing, and NPC firing integration.
- Client tracer replication, projectile cleanup, and optional explosive impact behavior.

### 3. Bullet Visual System
**File:** [`BulletVisualManager.luau`](Main%20system/BulletVisualManager.luau)

The client-side visual counterpart to the projectile controller:

- Receives replicated projectile spawn/destruction events.
- Renders and animates lightweight visual tracers locally.
- Calculates tracer movement from initial velocity and adjusted gravity.
- Cleans up visual instances when the server reports impact or after a safety timeout.
- Creates muzzle particle effects on the client.

The projectile controller and visual manager are designed to work together: the server handles gameplay-relevant projectile behavior, while clients render the visual tracer.

## Project context

**Land Warfare** is a playable Roblox game developed independently. These files are selected examples rather than a copy of the complete game source. They depend on project-specific instances, attributes, RemoteEvents, collision groups, and asset hierarchy, so they are intended as code-review samples rather than drop-in packages.

## Development approach

I use AI tools as coding assistance during development. I am responsible for the game and system design, integrating the code into the project, testing behavior, investigating issues, and refining the implementation. The samples should be evaluated as part of that AI-assisted development workflow, not as a claim that every line was written without assistance.

## Repository structure

```
Main system/
├── TankDrivingMaster.luau
├── ProjectileMaster.luau
└── BulletVisualManager.luau
```
