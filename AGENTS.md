# Pixel Night Shift Project Rules

## Product
- Build an original portrait idle-management game titled "Pixel Night Shift".
- Combat is fully automatic. The player's meaningful actions are diagnosing bottlenecks, upgrading operators, choosing patches, and starting a version update.
- Do not reproduce reference-game characters, names, dialogue, UI layouts, story beats, palettes, or recognizable compositions.

## Current milestone
- Preserve the completed 20-stage greybox loop while adding the app shell, local save, and return flow defined in `docs/APP_SHELL_SPEC.md`.
- Include boot routing, one-time first shift, the operations room, gameplay return, settings, conditional offline report, version-update confirmation and summary, onboarding, and explicit save recovery.
- Add versioned local saves, one backup, deterministic offline progress capped by app policy, and Android pause/resume/back/safe-area behavior.
- Do not add departments, incidents, equipment, networking, ads, purchases, analytics, accounts, cloud saves, live events, daily rewards, mail, rankings, or more combat content in this milestone.

## Engine and architecture
- Use Godot 4.7 and typed GDScript.
- Logical resolution is 360x640.
- Keep domain simulation independent from scenes, nodes, files, clocks, and audio.
- `GameSession` is the application boundary. Presentation sends commands to it and reads snapshots; presentation must not mutate domain state directly.
- `AppRoot` is the composition, navigation, simulation-tick, lifecycle, save-timing, and audio-lifecycle owner. It owns exactly one active `GameSession`.
- Persistence stays outside the domain. `GameSession` validates explicit save DTOs; the save repository owns files and the save envelope.
- Keep balance and content values in `game/content/` and validate external data at its loading boundary.
- Avoid global event buses, multiple Autoload singletons, dependency-injection containers, and speculative abstractions.

## Quality
- Tests verify observable behavior, not internal call order.
- Same input state and elapsed time must produce the same combat result.
- Save restoration must be atomic. Invalid or newer data must not partially mutate the active session or silently reset progress.
- Offline results must be saved before their read-only report is shown and must never be applied twice.
- A task is not complete until tests and a headless project launch pass.
- Do not hide errors with silent fallback values or empty catches.
- Preserve unrelated user work and report failed validation honestly.
