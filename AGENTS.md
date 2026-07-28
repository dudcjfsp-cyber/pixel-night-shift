# Pixel Night Shift Project Rules

## Product
- Build an original portrait idle-management game titled "Pixel Night Shift".
- Combat is fully automatic. The player's meaningful actions are diagnosing bottlenecks, upgrading operators, choosing patches, and starting a version update.
- Do not reproduce reference-game characters, names, dialogue, UI layouts, story beats, palettes, or recognizable compositions.

## Current milestone
- Raise the completed 20-stage loop into the production hybrid-combat vertical slice defined in `docs/COMBAT_HYBRID_SPEC.md`.
- Preserve the completed app shell, local save, recovery, offline progress, version-update flow, and Android lifecycle behavior defined in `docs/APP_SHELL_SPEC.md`.
- Adopt role differentiation, boss-only operator durability and process-down, automatic QA rescue, evidence-based diagnosis, and factual operator appeals without adding manual combat input.
- Do not add new operators, patches, enemies, bosses, stages, departments, incidents, equipment, networking, ads, purchases, analytics, accounts, cloud saves, live events, daily rewards, mail, or rankings in this milestone.

## Engine and architecture
- Use Godot 4.7 and typed GDScript.
- Logical resolution is 360x640.
- Keep domain simulation independent from scenes, nodes, files, clocks, and audio.
- `ProductLoopSession` is the current application boundary. Presentation sends commands to it and reads snapshots; presentation must not mutate domain state directly. Legacy `GameSession` is retained only to validate and migrate schema 1·2 saves and for regression coverage.
- `AppRoot` is the composition, navigation, simulation-tick, lifecycle, save-timing, and audio-lifecycle owner. It owns exactly one active `ProductLoopSession`.
- Persistence stays outside the domain. `ProductLoopSession` validates explicit schema 3 save DTOs; `ProductV2SaveMigrator` coordinates legacy validation and candidate conversion; the save repository owns files and the save envelope.
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

## Windows headless execution
- Run automated Godot commands through `tools/run_godot_headless.ps1`; do not invoke the GUI executable or `godot.bat` directly for tests.
- Never run two Godot test processes in parallel. The runner enforces a project-scoped mutex and process-specific log file.
- Give the shell timeout enough margin for the selected suite. After any timeout, confirm that no matching Godot process remains before retrying.
- The runner intentionally isolates `APPDATA`, `LOCALAPPDATA`, logs, and `user://` under `.godot/` so automated tests cannot contend with the editor or production save data. Native faults still return a failing exit code and log, but must not block automation with a Windows error dialog.
