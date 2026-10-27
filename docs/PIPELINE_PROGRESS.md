# 3D Pipeline Progress

- Ledger schema: `1.0`
- Updated UTC: `2026-10-27T09:21:58Z`
- New-product gate: **HOLD** — No accepted 3D candidate baseline or explicit new_product_allowed=true authorization exists; generation and new staging remain HOLD while existing QA/build/transport are improved.
- Next stage: `msix_byte_qa`
- Next repository: `shihuiarenjinba-png/3d-build-qa`
- Next branch: `codex/3d-msix-zip-path-safety-20261027-1235`
- Next HEAD: `cb53c79ea5a49b78044e273c8c40c3a3509bc123`

## Stage status

| Stage | State | Auto-actionable | Result |
| --- | --- | --- | --- |
| `template_windows_export` | **DONE** | no | Godot 4.3 Windows x64 EXE/PCK export succeeds and produces a real QA artifact. |
| `factory_product_materialization` | **HOLD** | yes | No independently reviewed playable 3D source exists. Factory acceptance now preserves late symlinks, re-audits the copied product tree for Windows safety and checks both the copied bytes and original source against the exact real Godot QA digest before publication. Product acceptance and real Godot candidate QA remain HOLD. New generation/acceptance/staging now also checks an explicit READY/new_product_allowed=true ledger gate and absent active_product, independently of the 120-hour timestamp. |
| `provisioner_windows_build` | **IN_PROGRESS** | yes | Local 3D manufacturing now accepts a real Godot Windows EXE/PCK export as pre-MSIX payload evidence, preserves its SHA/signature status, requires official Store ID/Identity/Publisher/Version/PFN/Package SID evidence, and returns the full request/product/source correlation key to Factory. Final Identity-to-package match is deliberately deferred to the Factory MSIX. |
| `official_identity_roundtrip` | **IN_PROGRESS** | yes | 3D Identity return no longer targets a stale hard-coded Factory branch: it validates the exact active codex/* source_branch, requires original source_sha == expected_head_sha, checks live HEAD and commits with GitHub CAS. Linux/Windows offline tests pass. No real authenticated Partner Center Identity has been supplied or returned; actual Identity stage remains HOLD. |
| `factory_msix_build` | **IN_PROGRESS** | yes | Factory MSIX builder now consumes the returned 3D correlation/provenance record, keeps the original product source_sha immutable, records the later GitHub packaging commit separately as factory_build_head, and carries local package SHA plus Store ID/PFN/SID into the strict handoff. PowerShell syntax and Factory quality gates pass. |
| `msix_byte_qa` | **IN_PROGRESS** | yes | Offline 3D MSIX ZIP QA rejects unsafe paths, special files, encryption, expansion hazards and CRC/decompression corruption of all ZIP members. Manifest parser now requires the canonical Windows foundation namespace for Package, Identity, Applications and Application, rejecting lookalike XML elements; synthetic regression and PR #4 CI 40480201284 PASS. Full AppxBlockMap hash coverage, actual Factory MSIX byte QA and Windows installation remain unverified/HOLD. |
| `windows_all_auto_intake` | **IN_PROGRESS** | yes | 3D intake now validates the complete manufacturing correlation key and treats source_sha as the immutable original product SHA while separately binding factory_build_head to the exact successful Actions run. It rechecks MSIX bytes/Identity and rejects lane/request/branch/provenance mixing. Ubuntu and Windows offline CI pass. |
| `local_windows_gpu_qa` | **HOLD** | no | Not executed. |
| `signing_and_store_validation` | **HOLD** | no | Not executed. |
| `local_submission_automation` | **OUT_OF_SCOPE** | no | Final upload is intentionally local after download and preflight. |

## Next action

3D QA PR #4 HEAD cb53c79ea5a49b78044e273c8c40c3a3509bc123 rejects forged MSIX manifest namespaces; synthetic tests and CI run 40480201284 PASS. Next reproduce and implement AppxBlockMap structural/hash coverage with bounded synthetic fixtures; do not label this real MSIX verification. Windows-all-auto PR #14 HEAD 12c28af9e9103367f5ac03c168f9881cbec46370 CI 40476649944 PASS; 3D CAS branch remains diverged (39 ahead / 20 behind), no automatic merge. Factory dispatch PR #12 HEAD 7cdfd08525c22ff75fa8c6f752a9342a1f7fc23b CI 40473680867 PASS. Await authorized accepted playable Godot source, authenticated Partner Center Identity and first real Factory 3D MSIX. 120-hour gate HOLD, new_product_allowed=false, active_product=null; Godot template EXE/PCK remains QA-only.

Acceptance:
- 3D QA remains isolated from GAME/APP: product_type GAME_3D, source_factory 3d-game-factory and Windows-all-auto type 3d-game must remain unchanged.
- All MSIX ZIP entries pass Windows path/collision/symlink/encryption/expansion preflight; package SHA and manifest executable/Identity are checked against real bytes.
- Factory→Provisioner→Windows→Factory→MSIX→Windows-all-auto retains request_id, source_repository, source_branch, source_sha and slug; HEAD mismatch is CONFLICT and replay only same request_id plus same source_sha.
- Real Factory MSIX Artifact, official Partner Center Identity, GPU QA, signing and Store validation remain individually HOLD until independently evidenced.
- Official Identity return uses only the exact active safe codex/* Factory source branch and expected HEAD CAS; stale hard-coded branch targets are rejected.
- Reject Win32 superscript COM¹/²/³ and LPT¹/²/³ device filenames in all ZIP entries, even with extensions; PR #4 CI success is not real MSIX verification.
- Reject CRC-corrupt ZIP members even when receipt package SHA matches the tampered archive; offline CI PASS is not real MSIX E2E PASS.
- Reject forged XML namespaces for MSIX Package, Identity, Applications and Application; synthetic CI PASS does not establish AppxBlockMap integrity or real MSIX installability.

## Evidence pins

- **factory** — `shihuiarenjinba-png/3d-game-factory` / `codex/3d-dispatch-guard-current-ledger-20261027-1628` / `7cdfd08525c22ff75fa8c6f752a9342a1f7fc23b` / run `40473680867`
- **provisioner** — `shihuiarenjinba-png/Repository-Provisioner-3D` / `codex/e2e-belt-connection-20261027` / `70600e77f2dd4278a989604314eebfa662e05c33` / run `40454089167`
- **template** — `shihuiarenjinba-png/3d-game-template` / `codex/3d-template-godot-bootstrap-20261026` / `e5462d0aa1f5d0a50fa484ad1544c11ce8a6085a` / run `40360649193`; artifact `godot-3d-windows-x64-qa-unsigned`
- **qa** — `shihuiarenjinba-png/3d-build-qa` / `codex/3d-msix-zip-path-safety-20261027-1235` / `cb53c79ea5a49b78044e273c8c40c3a3509bc123` / run `40480201284`
- **intake** — `shihuiarenjinba-png/Windows-all-auto` / `codex/e2e-belt-connection-20261027` / `12c28af9e9103367f5ac03c168f9881cbec46370` / run `40476649944`
- **windows_data** — `shihuiarenjinba-png/Windows-data` / `codex/msix-auto-build-identity-20261025` / `664b9afcbed63539b89f594892d831d97b9d4118` / run `40259906737`; artifact `MSIXAutoBuildIdentity-Windows-QA`

## Automation rule

Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.
