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


## Scheduled development ledger

The 3D improvement schedulers must begin by reading `factory/pipeline-progress.json`.
That ledger records the real cross-repository heads, CI runs, Artifact evidence, HOLD
reasons, and the single declared `next_action`. Validate it with:

```bash
python tools/pipeline_progress.py validate
python tools/pipeline_progress.py next
python tools/pipeline_progress.py check-report
```

`docs/PIPELINE_PROGRESS.md` is generated from the same ledger. Scheduled runs should
advance the declared next stage with an actual `codex/*` implementation/build change
and update both ledger evidence and the rendered report. A no-change run is acceptable
only when a recorded safety, permission, Identity, 120-hour, or HEAD-conflict HOLD
prevents a write. Contract tests alone are not a substitute for progressing the real
Godot -> Windows -> MSIX -> QA -> Windows-all-auto manufacturing path.

## Existing candidate promotion and real Godot QA

A candidate is not a product merely because the Python structural validator passes.
When an **existing** candidate is available in `.candidate/project`, run:

```bash
python factory3d.py validate
python factory3d.py qa
python factory3d.py accept
```

The `qa` command requires a locally installed Godot **4.3**, imports the project
headlessly, requires an explicit `PASS:` marker from `tests/test_smoke.gd`,
and launches the main scene for 60 headless frames in a disposable project copy.
Any engine/script error or missing smoke PASS blocks acceptance. It records
a SHA-256 digest and cycle-bound result in `.runtime/candidate-qa.json`.
`accept` now refuses missing, failed or stale QA evidence, as well as violating
the 120-hour acceptance gate. These commands do not create a new game, reserve
a Store Identity, run Windows GPU QA or submit anything to Microsoft.

The Factory source-only and Provisioner v1 handoff use the active
`codex/3d-real-msix-build-path-20261027` branch, matching the 3D Provisioner
allowlist. MSIX building also rejects uncommitted or untracked product changes.
A real `products/<slug>` can be committed only after the candidate passes QA
and acceptance; no template cube is mislabeled as a finished game.

## 3D MSIX → Windows-all-auto artifact contract

When a real accepted product has approved Partner Center Identity, committed
Store PNG assets, and a verified `verified_source_sha`, manually dispatch
`.github/workflows/msix-export.yml` with the exact product slug. The Windows
runner exports a real Godot Windows EXE/PCK, builds a QA_UNSIGNED MSIX with
MakeAppx, and uploads **two separate** artifacts:

- `3d-store-msix-qa-unsigned-<slug>`: raw MSIX and build evidence for QA.
- `factory-msix-handoff-<slug>`: strictly `package.msix` plus
  `handoff.json`, with source repository, Actions HEAD SHA, 3D lane, SHA-256,
  package bytes and embedded Identity values for `Windows-all-auto`.

The 3D bridge accepts only the reviewed workflow path/name and exact active
Factory branch. No Store ID, GPU QA, signing, WACK or publication is inferred.
Until a real product and official Identity exist, this MSIX/transfer path is
implemented but **not end-to-end verified**.


## Import an existing reviewed playable candidate (no new generation)

The Factory currently has no accepted playable 3D product. The rotating-cube
engine template is only a build smoke test and must **not** be sold or
automatically promoted. When an independently reviewed and authorized playable
Godot 4.3 source directory becomes available, stage its exact bytes without
bypassing the five-day acceptance gate:

```bash
python -c "from pathlib import Path; from factory3d import candidate_digest; print(candidate_digest(Path('/absolute/path/to/reviewed-project')))"
python -m tools.stage_existing_candidate \
  --source /absolute/path/to/reviewed-project \
  --expected-sha256 <64-lowercase-hex-digest> \
  --source-reviewed
python factory3d.py validate
python factory3d.py qa
python factory3d.py accept
```

Replace the path and digest with **real** reviewed source evidence. The
`--source-reviewed` flag is a human acknowledgement of rights/gameplay
review, not automated proof of commercial quality. Staging refuses a missing
review acknowledgement, a changed digest, symlinks, hidden Godot caches,
unsupported files, an existing candidate, or an unmet 120-hour gate. It
does not create a new game or update the Factory completion timestamp.

`qa` requires a real Godot 4.3 executable, import, explicit smoke PASS and
60-frame main-scene launch; `accept` rechecks the gate and publishes a
local `products/<slug>/` only after exact-source QA. Review and commit
the accepted product and `factory/state.json` to the authorized `codex/*`
branch before requesting the pinned Provisioner job. Identity lookup,
signed MSIX, GPU QA and Store submission remain separate HOLD gates.
The `.candidate/` and `.runtime/` directories are intentionally ignored
by Git and must never be mistaken for accepted GitHub products.
