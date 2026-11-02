# Prism Sentinel consumer revision — release PCK hygiene / first-30s clarity

## Immutable provenance
- Previous Sentinel source: `e432d94ed0db22878f61f1a8af140d7d7de2288f` and request `3d-prism-route-3d-e432d94ed0db`. Never overwrite or relabel these.
- Historical Factory Artifact: `12909162367`, PCK SHA256 `3e92b7b6e336a0ab40419448b79f330cf00e0cba4d6bb9ec864ba70b89ecdb03`; this PCK contains four internal resources and is **RELEASE_PCK_CONTENT_HOLD**.
- Historical Identity return commit `11417b75636ee18816028ffd5221884c4c9a9836` is NOT a CAS for either the Sentinel or this consumer revision.
- This revision is `codex/prism-sentinel-consumer-pck-20261102` (Draft PR #15). Its exact **new** source SHA is the final GitHub Actions checkout HEAD; request ID is `3d-prism-route-3d-<new_source_sha[:12]>`. Do not copy a previous SHA/request into this revision.

## Change
- Godot 4.3 `export_presets.cfg` excludes `store/*,tests/*,product-manifest.json` from the consumer PCK. Source/CI retain these files as non-consumer sidecars.
- `main.gd` adds world-space 1/2/3 numerals over each tower and an EN/JA "next tower" HUD. Existing deterministic Sentinel scan/trap/tower order logic is unchanged.
- `tools/prism_consumer_pck_audit.py` parses the **current run's actual Godot-exported PCK bytes**, checks resource MD5, bounds, duplicate/traversal, forbidden internal files, EXE/PCK SHA+size and source/request/build-head. Its only clean result is `PCK_CONTENT_CLEAN_QA_ONLY`, never `SALE_READY`.
- `tests/test_prism_consumer_pck_audit.py` covers wrong PCK, old identity, internal manifests/tests, corrupted bytes and wrong lineage. These fixtures are not product evidence.
- CI exports the real Windows x64 EXE/PCK from the new source and uploads an independent `consumer-pck-audit.json` artifact, plus the three-file Factory export contract.

## Fail-closed acceptance
1. Confirm the workflow ran on the **new** commit SHA, not the old pinned source or a PR synthetic merge ref.
2. Verify Godot 4.3 import, game logic, software-rendered 1024×768 scene smoke and actual Windows export.
3. Verify the new PCK contains no `res://store/*`, `res://tests/*`, `res://product-manifest.json` or other internal pipeline paths. If Godot export glob exclusions do not work, **HOLD** and create a separate consumer-only staging export using only `project.godot`, `export_presets.cfg`, `scenes/main.tscn` and required `scripts/*.gd`; then re-export and rehash under a new recorded source/build contract. Never rename the old PCK.
4. Independently consume new Factory receipt in Provisioner/3D QA. Do not reuse old EXE/PCK or Identity CAS.
5. 36 owner performs official Partner Center Identity recheck/CAS and Package Version gate. This lane does not touch Partner Center or central ledger.
6. Physical Windows 90-second gameplay, 1024×768 at 125%/150% DPI, tower-number readability, scan cone/trap clarity, first-30s objective, failure feedback, Store screenshot originality and commercial quality remain **HOLD** without actual GUI evidence.

No second 3D game, Store submission, signed MSIX, main/release writes, merge or ledger mutation. `SALE_READY=false` until all independent gates pass.
