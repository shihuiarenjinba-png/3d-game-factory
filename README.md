# 3D Game Factory — Godot 4 game experiments

Creates **at most one accepted Godot 4 3D prototype per five elapsed days**, not a game every day of a calendar month. Daily UTC 18:15 scheduler only starts generation when 120 hours have elapsed since the last *successfully validated and committed* candidate.

- State is stored in factory/state.json on the active `codex/3d-provisioner-job-contract-20261027` work branch. The 120-hour gate remains unchanged.
- Codex writes .candidate/project containing project.godot, scenes/main.tscn, scripts/main.gd, tests/test_smoke.gd and README.
- A separate job validates source and runs a real Godot 4 headless import and smoke launch before checkpointing a project.
- No new prototype when the five-day gate is not met. No overwrites of previous products.
- The output is **3D source code for testing**, not an installable or certified Windows MSIX.
- MSIX packaging, approved Identity, licensing, screenshots, real Windows GPU QA and transfer to Windows-all-auto require additional validated build steps.
- Must not publish to Microsoft Store, guess Store ID, or reuse unlicensed art.

The existing `five-day-3d.yml` is manually dispatched for deterministic source checks only; it does not create games, call paid model APIs, or submit to the Store. Any future production scheduler requires a separately reviewed implementation and authorization.

Related: https://github.com/shihuiarenjinba-png/3d-game-template and https://github.com/shihuiarenjinba-png/3d-build-qa are reserved for future engine template and Windows QA wiring. Current repository does not yet use them automatically.
