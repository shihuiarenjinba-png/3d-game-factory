# 3D Pipeline Progress

- Ledger schema: `1.0`
- Updated UTC: `2026-10-27T00:10:00Z`
- New-product gate: **HOLD** — No accepted 3D candidate baseline is recorded; scheduler must improve QA/build/transport instead of generating a new game.
- Next stage: `factory_product_materialization`
- Next repository: `shihuiarenjinba-png/3d-game-factory`
- Next branch: `codex/3d-real-msix-build-path-20261027`

## Stage status

| Stage | State | Auto-actionable | Result |
| --- | --- | --- | --- |
| `template_windows_export` | **DONE** | no | Godot 4.3 Windows x64 EXE/PCK export succeeds and produces a real QA artifact. |
| `factory_product_materialization` | **HOLD** | yes | No accepted 3D candidate or committed products/<slug> exists. Factory acceptance now requires real Godot 4.3 import and smoke QA evidence bound to candidate SHA-256 and cycle. |
| `provisioner_windows_build` | **IN_PROGRESS** | yes | Pinned Godot Windows export is implemented; Provisioner now allowlists the active Factory MSIX branch and returns verified_source_sha in reviewed Identity JSON. |
| `official_identity_roundtrip` | **IN_PROGRESS** | yes | Identity routing/atomic return exists and now records verified_source_sha. |
| `factory_msix_build` | **IN_PROGRESS** | yes | Factory Godot→MakeAppx code now emits QA_UNSIGNED MSIX plus strict two-file handoff (package.msix/handoff.json) with source SHA, embedded Identity, bytes and SHA-256. Code/CI pass; no real product or approved Identity. |
| `msix_byte_qa` | **IN_PROGRESS** | yes | MSIX SHA/manifest/Identity/executable payload checks are implemented. |
| `windows_all_auto_intake` | **IN_PROGRESS** | yes | 3D artifact polling now recognizes exact 3D Factory workflow name, active branch and strict factory-msix-handoff prefix. Offline CI passes; no real 3D artifact has been received. |
| `local_windows_gpu_qa` | **HOLD** | no | Not executed. |
| `signing_and_store_validation` | **HOLD** | no | Not executed. |
| `local_submission_automation` | **OUT_OF_SCOPE** | no | Final upload is intentionally local after download and preflight. |

## Next action

Locate and validate one existing authorized playable 3D candidate. If none exists, keep product materialization on HOLD and do not promote the rotating-cube template or generate a new game without the 120-hour gate.

Acceptance:
- An existing playable candidate has complete Godot 4.3 sources, Windows Desktop export preset and independent smoke test.
- Godot 4.3 headless import and smoke test PASS with SHA-256/cycle-bound QA evidence before accept.
- Factory 120-hour gate is checked again during accept and only the accepted product is committed under products/<slug>/.
- No Store Identity, price, security declaration, certification result or Windows GPU QA is fabricated.

## Evidence pins

- **factory** — `shihuiarenjinba-png/3d-game-factory` / `codex/3d-real-msix-build-path-20261027` / `acd1ce496c53ae85af094b6dd4af6221440d8d07` / run `40424533287`
- **provisioner** — `shihuiarenjinba-png/Repository-Provisioner-3D` / `codex/3d-pck-payload-guard-20261027` / `05a525f1b06f62b83c02e683755a84eb4f8a4c14` / run `40424203464`
- **template** — `shihuiarenjinba-png/3d-game-template` / `codex/3d-template-godot-bootstrap-20261026` / `e5462d0aa1f5d0a50fa484ad1544c11ce8a6085a` / run `40360649193`; artifact `godot-3d-windows-x64-qa-unsigned`
- **qa** — `shihuiarenjinba-png/3d-build-qa` / `codex/3d-msix-executable-payload-20261027` / `04f2b1f74674159197cc3f8fa7503705b4febcfb` / run `40417351553`
- **intake** — `shihuiarenjinba-png/Windows-all-auto` / `codex/3d-identity-source-sha-20261027` / `e7313d99893fed9b4d32d5022be2d3fdc9d67248` / run `40424564014`

## Automation rule

Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.
