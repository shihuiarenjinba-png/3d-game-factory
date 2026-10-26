# 3D Pipeline Progress

- Ledger schema: `1.0`
- Updated UTC: `2026-10-26T23:40:00Z`
- New-product gate: **HOLD** — No accepted 3D candidate baseline is recorded; scheduler must improve QA/build/transport instead of generating a new game.
- Next stage: `factory_product_materialization`
- Next repository: `shihuiarenjinba-png/3d-game-factory`
- Next branch: `codex/3d-real-msix-build-path-20261027`

## Stage status

| Stage | State | Auto-actionable | Result |
| --- | --- | --- | --- |
| `template_windows_export` | **DONE** | no | Godot 4.3 Windows x64 EXE/PCK export succeeds and produces a real QA artifact. |
| `factory_product_materialization` | **HOLD** | yes | Factory has no committed products/<slug>/ product yet on the active work branch. |
| `provisioner_windows_build` | **IN_PROGRESS** | yes | Pinned product-scoped Godot export and EXE/PCK completeness guards are implemented. |
| `official_identity_roundtrip` | **IN_PROGRESS** | yes | Identity routing/atomic return exists and now records verified_source_sha. |
| `factory_msix_build` | **IN_PROGRESS** | yes | A fail-closed Godot -> AppxManifest -> MakeAppx unsigned MSIX workflow is implemented and syntax-tested. |
| `msix_byte_qa` | **IN_PROGRESS** | yes | MSIX SHA/manifest/Identity/executable payload checks are implemented. |
| `windows_all_auto_intake` | **IN_PROGRESS** | yes | 3d-game lane is separated from app/game intake and source provenance is checked. |
| `local_windows_gpu_qa` | **HOLD** | no | Not executed. |
| `signing_and_store_validation` | **HOLD** | no | Not executed. |
| `local_submission_automation` | **OUT_OF_SCOPE** | no | Final upload is intentionally local after download and preflight. |

## Next action

Materialize one existing accepted 3D candidate under products/<slug>/ so the real Provisioner/MSIX path can be exercised.

Acceptance:
- No new 3D product is generated unless the 120-hour policy gate is satisfied.
- Committed product contains a real Godot project and Windows Desktop export preset.
- Source SHA is pinned and can be handed to Repository-Provisioner-3D.
- No Store Identity, price, security declaration, or certification result is fabricated.

## Evidence pins

- **factory** — `shihuiarenjinba-png/3d-game-factory` / `codex/3d-real-msix-build-path-20261027` / `bf80da05a01bea502ee12aaa1968f9bc61f016b3` / run `40419346456`
- **provisioner** — `shihuiarenjinba-png/Repository-Provisioner-3D` / `codex/3d-pck-payload-guard-20261027` / `fa2852c735a5fa74f27ae509dc272ed212b96e1a` / run `40409424715`
- **template** — `shihuiarenjinba-png/3d-game-template` / `codex/3d-template-godot-bootstrap-20261026` / `e5462d0aa1f5d0a50fa484ad1544c11ce8a6085a` / run `40360649193`; artifact `godot-3d-windows-x64-qa-unsigned`
- **qa** — `shihuiarenjinba-png/3d-build-qa` / `codex/3d-msix-executable-payload-20261027` / `04f2b1f74674159197cc3f8fa7503705b4febcfb` / run `40417351553`
- **intake** — `shihuiarenjinba-png/Windows-all-auto` / `codex/3d-identity-source-sha-20261027` / `bbf0f6f17a3f431e1f93c363d353b1c0613aacad` / run `40419153935`

## Automation rule

Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.
