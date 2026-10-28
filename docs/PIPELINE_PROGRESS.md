# 3D Pipeline Progress

- Ledger schema: `1.0`
- Updated UTC: `2026-10-28T00:21:10.446Z`
- New-product gate: **HOLD** — No accepted 3D candidate baseline or explicit new_product_allowed=true authorization exists; generation and new staging remain HOLD while existing QA/build/transport are improved.
- Next stage: `provisioner_windows_build`
- Next repository: `shihuiarenjinba-png/Repository-Provisioner-3D`
- Next branch: `codex/e2e-belt-connection-20261027`
- Next HEAD: `651e630de3a60cf59bf5d865cdf1cb004ae8a8f4`

## Stage status

| Stage | State | Auto-actionable | Result |
| --- | --- | --- | --- |
| `template_windows_export` | **DONE** | no | Godot 4.3 Windows x64 EXE/PCK export is real, and the same workflow run packages those exact independently hashed template bytes with Windows SDK MakeAppx. Pinned 3d-build-qa e84c448e strict ZIP/CRC/BlockMap/OPC/manifest and EXE/PCK SHA contract passes; a repacked tampered PCK is rejected. Template QA fixture is unsigned and is NOT an accepted/sellable 3D product. |
| `factory_product_materialization` | **HOLD** | yes | No independently reviewed playable 3D source exists. Factory acceptance now preserves late symlinks, re-audits the copied product tree for Windows safety and checks both the copied bytes and original source against the exact real Godot QA digest before publication. Product acceptance and real Godot candidate QA remain HOLD. New generation/acceptance/staging now also checks an explicit READY/new_product_allowed=true ledger gate and absent active_product, independently of the 120-hour timestamp. |
| `provisioner_windows_build` | **IN_PROGRESS** | yes | Provisioner PR7 rejects a non-Windows EXE lacking the MZ header both immediately after Godot export and during independent local package inspection. RED Ubuntu CI 40608097409 reproduced 2 accepted-invalid-EXE cases; final Windows/Ubuntu CI 40608121189 SUCCESS (78 tests). This is a minimal EXE magic guard only, not full PE validation, independent Factory provenance, an accepted product, Identity, or Windows install/GUI QA. |
| `official_identity_roundtrip` | **IN_PROGRESS** | yes | 3D Identity return no longer targets a stale hard-coded Factory branch: it validates the exact active codex/* source_branch, requires original source_sha == expected_head_sha, checks live HEAD and commits with GitHub CAS. Linux/Windows offline tests pass. No real authenticated Partner Center Identity has been supplied or returned; actual Identity stage remains HOLD. |
| `factory_msix_build` | **IN_PROGRESS** | yes | Factory MSIX builder now consumes the returned 3D correlation/provenance record, keeps the original product source_sha immutable, records the later GitHub packaging commit separately as factory_build_head, and carries local package SHA plus Store ID/PFN/SID into the strict handoff. PowerShell syntax and Factory quality gates pass. |
| `msix_byte_qa` | **IN_PROGRESS** | yes | Real Godot 4.3 Windows template EXE/PCK (not synthetic bytes) were independently hashed by the template export job, downloaded within the SAME workflow run, and packaged with real Windows SDK MakeAppx. Pinned 3d-build-qa PR4 e84c448e verifies actual MSIX ZIP/CRC/BlockMap/OPC/manifest plus EXE/PCK SHA; a valid repack with modified PCK fails only the independent Godot export SHA check. Template PR1 404214de CI 40586209393 SUCCESS, non-product fixture artifact 12772561732. QA PR4 CI 40578299666 SUCCESS 84/84. This proves template byte compatibility, not an accepted product, Partner Center Identity, Windows install/GPU/GUI, signing, E2E or commercial readiness. |
| `windows_all_auto_intake` | **IN_PROGRESS** | yes | 3D intake now validates the complete manufacturing correlation key and treats source_sha as the immutable original product SHA while separately binding factory_build_head to the exact successful Actions run. It rechecks MSIX bytes/Identity and rejects lane/request/branch/provenance mixing. Ubuntu and Windows offline CI pass. |
| `local_windows_gpu_qa` | **HOLD** | no | Not executed. |
| `signing_and_store_validation` | **HOLD** | no | Not executed. |
| `local_submission_automation` | **OUT_OF_SCOPE** | no | Final upload is intentionally local after download and preflight. |

## Next action

Provisioner PR7 651e630d CI 40608121189 SUCCESS (78 tests, Windows/Ubuntu). Next: implement independently authenticated Factory export receipt cross-check of request_id/source_sha/slug and exact EXE/PCK SHA, with immutable source_sha distinct from factory_build_head. No new product, no Partner Center Identity lookup by 3D owner. 36min Windows owner: read latest Factory/Provisioner refs, keep 3D queue isolated and central handoff read-only.

Acceptance:
- 3D QA remains isolated from GAME/APP: product_type GAME_3D, source_factory 3d-game-factory and Windows-all-auto type 3d-game must remain unchanged.
- All MSIX ZIP entries pass Windows path/collision/symlink/encryption/expansion preflight; package SHA and manifest executable/Identity are checked against real bytes.
- Factory→Provisioner→Windows→Factory→MSIX→Windows-all-auto retains request_id, source_repository, source_branch, source_sha and slug; HEAD mismatch is CONFLICT and replay only same request_id plus same source_sha.
- Real Factory MSIX Artifact, official Partner Center Identity, GPU QA, signing and Store validation remain individually HOLD until independently evidenced.
- Official Identity return uses only the exact active safe codex/* Factory source branch and expected HEAD CAS; stale hard-coded branch targets are rejected.
- Reject Win32 superscript COM¹/²/³ and LPT¹/²/³ device filenames in all ZIP entries, even with extensions; PR #4 CI success is not real MSIX verification.
- Reject CRC-corrupt ZIP members even when receipt package SHA matches the tampered archive; offline CI PASS is not real MSIX E2E PASS.
- Reject forged XML namespaces for MSIX Package, Identity, Applications and Application; synthetic CI PASS does not establish AppxBlockMap integrity or real MSIX installability.
- AppxBlockMap root namespace, SHA-256 method, complete file coverage, exact LFH sizes and all 64-KiB payload hashes must match MSIX bytes; synthetic PASS is not authenticated signing or E2E.
- Reject absent/forged OPC [Content_Types].xml, missing or conflicting per-part declarations, duplicate case-insensitive extensions/overrides, unknown parts, encoded path separators and incorrect manifest/BlockMap MIME types; synthetic PASS is not real MakeAppx evidence.
- Reject ZIP local-header filename/flags/compression method disagreement with central-directory entries, including directories; offline CI PASS does not establish real MSIX E2E.
- AppxBlockMap File Name must exactly match the corresponding ZIP member with canonical Windows backslashes and original case; reject slash and case aliases before trusting block hashes. Synthetic PASS is not real MakeAppx validation.
- Reject unexpected AppxBlockMap BlockMap/File/Block attributes and non-whitespace text; allow indentation whitespace. CI 40520471059 synthetic 65/65 PASS does not prove real MakeAppx MSIX compatibility.
- Reject contradictory ZIP local CRC/compressed/uncompressed sizes when data-descriptor bit is absent; preserve ZIP64 sentinel compatibility pending real MakeAppx evidence. CI 40530733297 is synthetic, not product E2E.
- ZIP64 local 0xffffffff size sentinels require an actual local ZIP64 extra field with 64-bit uncompressed/compressed sizes matching the central directory; malformed/forged values are rejected, valid force_zip64 fixture passes. QA 40540481221 68/68 synthetic tests PASS, not real MakeAppx evidence.
- For GPBF bit 3, reject forged ZIP data-descriptor CRC and compressed/uncompressed sizes, including ZIP64 variants; Python non-seekable ZIP fixtures PASS 70/70 on CI 40550405898 but real MakeAppx compatibility remains unproven.
- For GPBF bit 3, accept both signed and signatureless ZIP data descriptors for 32-bit and ZIP64 fixtures; reject forged nonzero local CRC or nonzero/non-ZIP64 local size placeholders. RED CI 40560260636 and GREEN CI 40560378006 (72 tests) are synthetic only, not MakeAppx/E2E proof.
- Actual Windows SDK MakeAppx fixture is unsigned/non-product: 78/78 regressions and ZIP/CRC/BlockMap/b4/OPC byte checks PASS, forged descriptor BLOCKED, but official Identity, real product E2E and Store readiness remain HOLD.
- When independently pinned Godot export evidence is supplied, the exact manifest EXE and optional external GDPC PCK bytes must match expected SHA-256. Missing/tampered PCK blocks; embedded PCK mode permits EXE-only. Synthetic MakeAppx PASS never proves real Godot export provenance, E2E, GPU/GUI or commercial readiness.
- Real Godot 4.3 template EXE/PCK -> MakeAppx fixture PASS on CI 40586209393; valid MakeAppx repack with modified PCK is BLOCKED by independently pinned SHA. Artifact 12772561732 is QA-only and must not be promoted to accepted product or product E2E.
- Provisioner PCK SHA is LOCAL_EXPORT_NOT_INDEPENDENT; only matching a separate pinned Factory export receipt and immutable request_id/source_sha/slug can upgrade provenance, never template fixture or Identity status.
- Godot EXE MZ header must be present at export and inspection (RED 40608097409, GREEN 40608121189); MZ alone does not prove valid PE architecture, Windows GPU/GUI or sellable product.

## Evidence pins

- **factory** — `shihuiarenjinba-png/3d-game-factory` / `codex/3d-dispatch-guard-current-ledger-20261027-1628` / `88d0c9bcf3d1e140f81f73f00a92c75831029a35` / run `40602534889`
- **provisioner** — `shihuiarenjinba-png/Repository-Provisioner-3D` / `codex/e2e-belt-connection-20261027` / `651e630de3a60cf59bf5d865cdf1cb004ae8a8f4` / run `40608121189`
- **template** — `shihuiarenjinba-png/3d-game-template` / `codex/3d-template-godot-bootstrap-20261026` / `404214de6610b118f043b7ca8f62bf12f4b813b1` / run `40586209393`; artifact `godot-4-3-real-export-makeappx-fixture-not-product`
- **qa** — `shihuiarenjinba-png/3d-build-qa` / `codex/3d-msix-zip-path-safety-20261027-1235` / `e84c448e48105d15d2040f87fb279835ddd0119b` / run `40578299666`; artifact `makeappx-3d-offline-unsigned-fixture-not-product`
- **intake** — `shihuiarenjinba-png/Windows-all-auto` / `codex/e2e-belt-connection-20261027` / `cc4c6c5866539aa131bc5eafc0f76e259f6ed891` / run `40597008603`
- **windows_data** — `shihuiarenjinba-png/Windows-data` / `codex/msix-auto-build-identity-20261025` / `664b9afcbed63539b89f594892d831d97b9d4118` / run `40259906737`; artifact `MSIXAutoBuildIdentity-Windows-QA`

## Automation rule

Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.
