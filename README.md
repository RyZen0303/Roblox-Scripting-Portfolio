# Roblox Gameplay Scripting Portfolio

Selected gameplay systems from **Land Warfare**, an independently developed and playable Roblox game.

## Gameplay Showcase

https://github.com/user-attachments/assets/99c36c64-ab07-4a4f-b8c8-8a21a72f0f06

## Development Process

My development process is based on identifying problems through implementation and playtesting, investigating their causes, and validating solutions in the actual game.

1. **Identify the problem** — Implement or playtest a feature, observe unexpected behavior, and define the specific issue.
2. **Investigate the cause** — Inspect script behavior, output logs, relevant Roblox systems, and interactions between components. I form and test possible explanations rather than assuming the first suggestion is correct.
3. **Isolate and test** — Reduce unrelated variables where possible, use debugging output or temporary changes, and test hypotheses against the behavior in-game.
4. **Implement the solution** — Make changes based on the cause identified, while considering how the affected systems interact with the rest of the project.
5. **Validate and refine** — Playtest the result, check relevant edge cases and supported devices, and revise the implementation if problems remain.

This process is iterative. A proposed fix is not treated as correct until its behavior has been tested. For example, during vehicle suspension development, I investigated a tank-flipping issue by isolating the suspension and tracing physics network ownership across server-side systems. The investigation led to separating client-side suspension behavior from server-side validation.

## Relevant Work — Gun Clan Systems

For a focused breakdown of Land Warfare code relevant to weapon combat, server validation, persistent player data, progression, objectives, and multiplayer physics, see **[Relevant Systems — Gun Clan Role](Relevant-Work/Gun-Clan-Systems.md)**.

The page includes selected code excerpts, links to their original source files, and a clear distinction between directly demonstrated systems and features that would still need to be built for an infantry FPS.

## AI-Assisted Workflow

I use AI tools as coding and investigation assistance. I remain responsible for system design, evaluating suggestions, integrating changes into the project, testing behavior, identifying root causes, and refining the implementation. AI-generated suggestions are treated as hypotheses to verify, not as automatically correct solutions.

This is an AI-assisted development workflow, not a claim that every line was written without assistance.

## Code Context

The scripts in this repository are selected from a larger game project. Some rely on the original game's instances, attributes, RemoteEvents, and asset hierarchy, so they are provided for code review rather than as standalone drop-in packages.
