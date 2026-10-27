# 3D Pipeline Progress

- Ledger schema: `1.0`
- Updated UTC: `2026-10-27T08:27:21Z`
- New-product gate: **HOLD** — No accepted 3D candidate baseline or explicit new_product_allowed=true authorization exists; generation and new staging remain HOLD while existing QA/build/transport are improved.
- Next stage: `msix_byte_qa`
- Next repository: `shihuiarenjinba-png/3d-build-qa`
- Next branch: `codex/3d-msix-zip-path-safety-20261027-1235`
- Next HEAD: `349eb9b285818272b72ecbce34e5b1fed67afbb2`

## Stage status

| Stage | State | Auto-actionable | Result |
| --- | --- | --- | --- |
| `template_windows_export` | **DONE** | no | Godot 4.3 Windows x64 EXE/PCK export succeeds and produces a real QA artifact. |
| `factory_product_materialization` | **HOLD** | yes | No independently reviewed playable 3D source exists. Factory acceptance now preserves late symlinks, re-audits the copied product tree for Windows safety and checks both the copied bytes and original source against the exact real Godot QA digest before publication. Product acceptance and real Godot candidate QA remain HOLD. New generation/acceptance/staging now also checks an explicit READY/new_product_allowed=true ledger gate and absent active_product, independently of the 120-hour timestamp. |
| `provisioner_windows_build` | **IN_PROGRESS** | yes | Local 3D manufacturing now accepts a real Godot Windows EXE/PCK export as pre-MSIX payload evidence, preserves its SHA/signature status, requires official Store ID/Identity/Publisher/Version/PFN/Package SID evidence, and returns the full request/product/source correlation key to Factory. Final Identity-to-package match is deliberately deferred to the Factory MSIX. |
| `official_identity_roundtrip` | **IN_PROGRESS** | yes | 3D Identity return no longer targets a stale hard-coded Factory branch: it validates the exact active codex/* source_branch, requires original source_sha == expected_head_sha, checks live HEAD and commits with GitHub CAS. Linux/Windows offline tests pass. No real authenticated Partner Center Identity has been supplied or returned; actual Identity stage remains HOLD. |
| `factory_msix_build` | **IN_PROGRESS** | yes | Factory MSIX builder now consumes the returned 3D correlation/provenance record, keeps the original product source_sha immutable, records the later GitHub packaging commit separately as factory_build_head, and carries local package SHA plus Store ID/PFN/SID into the strict handoff. PowerShell syntax and Factory quality gates pass. |
| `msix_byte_qa` | **IN_PROGRESS** | yes | Offline 3D MSIX ZIP QA rejects Windows path/collision, special-file, encryption and expansion hazards. It now streams every ZIP member to reject CRC/decompression corruption even in unrelated assets when the overall package SHA matches its receipt. Synthetic regression and CI pass on QA PR #4 HEAD 349eb9b28581, run 40473547781; no actual Factory 3D MSIX has been produced or inspected, so real byte QA remains HOLD. |
| `windows_all_auto_intake` | **IN_PROGRESS** | yes | 3D intake now validates the complete manufacturing correlation key and treats source_sha as the immutable original product SHA while separately binding factory_build_head to the exact successful Actions run. It rechecks MSIX bytes/Identity and rejects lane/request/branch/provenance mixing. Ubuntu and Windows offline CI pass. |
| `local_windows_gpu_qa` | **HOLD** | no | Not executed. |
| `signing_and_store_validation` | **HOLD** | no | Not executed. |
| `local_submission_automation` | **OUT_OF_SCOPE** | no | Final upload is intentionally local after download and preflight. |

## Next action

3D QA PR #4 HEAD 349eb9b285818272b72ecbce34e5b1fed67afbb2 added bounded streaming CRC/decompression checks for every ZIP member, including non-executable assets; corrupt-asset regression passed CI run 40473547781. Next inspect MSIX block-map/manifest coverage and integration contract without claiming real product byte PASS. Windows-all-auto PR #14 HEAD be633094bd38bbc6423dca886a53778f0c33ce50 passed CI run 40470013777; 3D CAS branch remains diverged (37 ahead / 20 behind), do not merge automatically. Factory dispatch guard PR #12 CI 40467528271 SUCCESS. Await authorized accepted playable Godot source, authenticated Partner Center Identity and first real 3D MSIX. Keep 120-hour generation gate HOLD, new_product_allowed=false, active_product=null; template EXE/PCK is QA-only.

Acceptance:
- 3D QA remains isolated from GAME/APP: product_type GAME_3D, source_factory 3d-game-factory and Windows-all-auto type 3d-game must remain unchanged.
- All MSIX ZIP entries pass Windows path/collision/symlink/encryption/expansion preflight; package SHA and manifest executable/Identity are checked against real bytes.
- Factory→Provisioner→Windows→Factory→MSIX→Windows-all-auto retains request_id, source_repository, source_branch, source_sha and slug; HEAD mismatch is CONFLICT and replay only same request_id plus same source_sha.
- Real Factory MSIX Artifact, official Partner Center Identity, GPU QA, signing and Store validation remain individually HOLD until independently evidenced.
- Official Identity return uses only the exact active safe codex/* Factory source branch and expected HEAD CAS; stale hard-coded branch targets are rejected.
- Reject Win32 superscript COM¹/²/³ and LPT¹/²/³ device filenames in all ZIP entries, even with extensions; PR #4 CI success is not real MSIX verification.
- Reject CRC-corrupt ZIP members even when receipt package SHA matches the tampered archive; offline CI PASS is not real MSIX E2E PASS.

## Evidence pins

- **factory** — `shihuiarenjinba-png/3d-game-factory` / `codex/3d-dispatch-guard-integration-20261027-1452` / `273b4bcd750432e2ba899414107de7177166848d` / run `40457985405`
- **provisioner** — `shihuiarenjinba-png/Repository-Provisioner-3D` / `codex/e2e-belt-connection-20261027` / `70600e77f2dd4278a989604314eebfa662e05c33` / run `40454089167`
- **template** — `shihuiarenjinba-png/3d-game-template` / `codex/3d-template-godot-bootstrap-20261026` / `e5462d0aa1f5d0a50fa484ad1544c11ce8a6085a` / run `40360649193`; artifact `godot-3d-windows-x64-qa-unsigned`
- **qa** — `shihuiarenjinba-png/3d-build-qa` / `codex/3d-msix-zip-path-safety-20261027-1235` / `349eb9b285818272b72ecbce34e5b1fed67afbb2` / run `40473547781`
- **intake** — `shihuiarenjinba-png/Windows-all-auto` / `codex/e2e-belt-connection-20261027` / `be633094bd38bbc6423dca886a53778f0c33ce50` / run `40470013777`
- **windows_data** — `shihuiarenjinba-png/Windows-data` / `codex/msix-auto-build-identity-20261025` / `664b9afcbed63539b89f594892d831d97b9d4118` / run `40259906737`; artifact `MSIXAutoBuildIdentity-Windows-QA`

## Automation rule

Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.
