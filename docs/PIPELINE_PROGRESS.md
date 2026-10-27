# 3D Pipeline Progress

- Ledger schema: `1.0`
- Updated UTC: `2026-10-27T03:35:03Z`
- New-product gate: **HOLD** — No accepted 3D candidate baseline is recorded; scheduler must improve QA/build/transport instead of generating a new game.
- Next stage: `msix_byte_qa`
- Next repository: `shihuiarenjinba-png/3d-build-qa`
- Next branch: `codex/3d-msix-zip-path-safety-20261027-1235`

## Stage status

| Stage | State | Auto-actionable | Result |
| --- | --- | --- | --- |
| `template_windows_export` | **DONE** | no | Godot 4.3 Windows x64 EXE/PCK export succeeds and produces a real QA artifact. |
| `factory_product_materialization` | **HOLD** | yes | No independently reviewed playable 3D source exists. Factory acceptance now preserves late symlinks, re-audits the copied product tree for Windows safety and checks both the copied bytes and original source against the exact real Godot QA digest before publication. Product acceptance and real Godot candidate QA remain HOLD. |
| `provisioner_windows_build` | **IN_PROGRESS** | yes | Local 3D manufacturing now accepts a real Godot Windows EXE/PCK export as pre-MSIX payload evidence, preserves its SHA/signature status, requires official Store ID/Identity/Publisher/Version/PFN/Package SID evidence, and returns the full request/product/source correlation key to Factory. Final Identity-to-package match is deliberately deferred to the Factory MSIX. |
| `official_identity_roundtrip` | **IN_PROGRESS** | yes | 3D Identity return no longer targets a stale hard-coded Factory branch: it validates the exact active codex/* source_branch, requires original source_sha == expected_head_sha, checks live HEAD and commits with GitHub CAS. Linux/Windows offline tests pass. No real authenticated Partner Center Identity has been supplied or returned; actual Identity stage remains HOLD. |
| `factory_msix_build` | **IN_PROGRESS** | yes | Factory MSIX builder now consumes the returned 3D correlation/provenance record, keeps the original product source_sha immutable, records the later GitHub packaging commit separately as factory_build_head, and carries local package SHA plus Store ID/PFN/SID into the strict handoff. PowerShell syntax and Factory quality gates pass. |
| `msix_byte_qa` | **IN_PROGRESS** | yes | 3D MSIX QA now rejects Windows-ambiguous ZIP entries (traversal, DOS devices, ADS, case collisions, file/directory conflicts, symlinks), unsupported/encrypted entries and expansion bombs before reading manifest/executable bytes. Synthetic offline tests and CI pass. No actual Factory 3D MSIX has been produced or inspected; MSIX byte QA and real-device QA remain HOLD for a real product. |
| `windows_all_auto_intake` | **IN_PROGRESS** | yes | 3D intake now validates the complete manufacturing correlation key and treats source_sha as the immutable original product SHA while separately binding factory_build_head to the exact successful Actions run. It rechecks MSIX bytes/Identity and rejects lane/request/branch/provenance mixing. Ubuntu and Windows offline CI pass. |
| `local_windows_gpu_qa` | **HOLD** | no | Not executed. |
| `signing_and_store_validation` | **HOLD** | no | Not executed. |
| `local_submission_automation` | **OUT_OF_SCOPE** | no | Final upload is intentionally local after download and preflight. |

## Next action

Maintain the 3D-only MSIX byte and Windows ZIP safety gate without duplicating the 05-minute Factory candidate-acceptance work. The next evidence-based step is to obtain the first authentic Factory 3D MSIX and verify actual artifact bytes, manifest, immutable source_sha/request_id and Identity. Until a reviewed playable source and Partner Center Identity exist, keep E2E transport and local GPU QA HOLD; do not fabricate a candidate or treat offline tests as product PASS.

Acceptance:
- 3D QA remains isolated from GAME/APP: product_type GAME_3D, source_factory 3d-game-factory and Windows-all-auto type 3d-game must remain unchanged.
- All MSIX ZIP entries pass Windows path/collision/symlink/encryption/expansion preflight; package SHA and manifest executable/Identity are checked against real bytes.
- Factory→Provisioner→Windows→Factory→MSIX→Windows-all-auto retains request_id, source_repository, source_branch, source_sha and slug; HEAD mismatch is CONFLICT and replay only same request_id plus same source_sha.
- Real Factory MSIX Artifact, official Partner Center Identity, GPU QA, signing and Store validation remain individually HOLD until independently evidenced.
- Official Identity return uses only the exact active safe codex/* Factory source branch and expected HEAD CAS; stale hard-coded branch targets are rejected.

## Evidence pins

- **factory** — `shihuiarenjinba-png/3d-game-factory` / `codex/3d-qa-zip-ledger-20261027-1235` / `e7682c3ba54241b0962d3dedec10fbad51200384` / run `40442791871`
- **provisioner** — `shihuiarenjinba-png/Repository-Provisioner-3D` / `codex/3d-local-identity-provenance-20261027` / `a1727307884176bfa97f714c47705281240d83c3` / run `40431389877`
- **template** — `shihuiarenjinba-png/3d-game-template` / `codex/3d-template-godot-bootstrap-20261026` / `e5462d0aa1f5d0a50fa484ad1544c11ce8a6085a` / run `40360649193`; artifact `godot-3d-windows-x64-qa-unsigned`
- **qa** — `shihuiarenjinba-png/3d-build-qa` / `codex/3d-msix-zip-path-safety-20261027-1235` / `a918834a3122d8f74684b43102ad9070f606c527` / run `40444730016`
- **intake** — `shihuiarenjinba-png/Windows-all-auto` / `codex/3d-identity-active-branch-cas-20261027-1235` / `681538cb65ffecc9959fec1f021f8a49ee22810c` / run `40444968185`

## Automation rule

Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.
