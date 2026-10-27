# 3D Pipeline Progress

- Ledger schema: `1.0`
- Updated UTC: `2026-10-27T19:37:20Z`
- New-product gate: **HOLD** — No accepted 3D candidate baseline or explicit new_product_allowed=true authorization exists; generation and new staging remain HOLD while existing QA/build/transport are improved.
- Next stage: `msix_byte_qa`
- Next repository: `shihuiarenjinba-png/3d-build-qa`
- Next branch: `codex/3d-msix-zip-path-safety-20261027-1235`
- Next HEAD: `4f70c0454fa5b44fb054c2171b8de397e77aa951`

## Stage status

| Stage | State | Auto-actionable | Result |
| --- | --- | --- | --- |
| `template_windows_export` | **DONE** | no | Godot 4.3 Windows x64 EXE/PCK export succeeds and produces a real QA artifact. |
| `factory_product_materialization` | **HOLD** | yes | No independently reviewed playable 3D source exists. Factory acceptance now preserves late symlinks, re-audits the copied product tree for Windows safety and checks both the copied bytes and original source against the exact real Godot QA digest before publication. Product acceptance and real Godot candidate QA remain HOLD. New generation/acceptance/staging now also checks an explicit READY/new_product_allowed=true ledger gate and absent active_product, independently of the 120-hour timestamp. |
| `provisioner_windows_build` | **IN_PROGRESS** | yes | Local 3D manufacturing now accepts a real Godot Windows EXE/PCK export as pre-MSIX payload evidence, preserves its SHA/signature status, requires official Store ID/Identity/Publisher/Version/PFN/Package SID evidence, and returns the full request/product/source correlation key to Factory. Final Identity-to-package match is deliberately deferred to the Factory MSIX. |
| `official_identity_roundtrip` | **IN_PROGRESS** | yes | 3D Identity return no longer targets a stale hard-coded Factory branch: it validates the exact active codex/* source_branch, requires original source_sha == expected_head_sha, checks live HEAD and commits with GitHub CAS. Linux/Windows offline tests pass. No real authenticated Partner Center Identity has been supplied or returned; actual Identity stage remains HOLD. |
| `factory_msix_build` | **IN_PROGRESS** | yes | Factory MSIX builder now consumes the returned 3D correlation/provenance record, keeps the original product source_sha immutable, records the later GitHub packaging commit separately as factory_build_head, and carries local package SHA plus Store ID/PFN/SID into the strict handoff. PowerShell syntax and Factory quality gates pass. |
| `msix_byte_qa` | **IN_PROGRESS** | yes | Real Windows SDK MakeAppx 10.0.26100 unsigned non-product fixture was packed and inspected on windows-latest: ZIP GPBF bit-3 64-bit descriptors without ZIP64 sentinels, OPC default .xml manifest MIME, b4 ignorable namespace, b4 whole-file FileHash, multi-block SHA-256, and exact deflate 03 00 trailer compatibility all pass. Forged actual MakeAppx ZIP64 descriptor rejected. QA PR4 HEAD 4f70c0454fa5b44fb054c2171b8de397e77aa951 CI 40570709568 PASS 78/78 Python tests plus Windows fixture. This is fixture byte-contract evidence only, not accepted Godot product, official Identity, install, GPU/GUI, signing or Store readiness. |
| `windows_all_auto_intake` | **IN_PROGRESS** | yes | 3D intake now validates the complete manufacturing correlation key and treats source_sha as the immutable original product SHA while separately binding factory_build_head to the exact successful Actions run. It rechecks MSIX bytes/Identity and rejects lane/request/branch/provenance mixing. Ubuntu and Windows offline CI pass. |
| `local_windows_gpu_qa` | **HOLD** | no | Not executed. |
| `signing_and_store_validation` | **HOLD** | no | Not executed. |
| `local_submission_automation` | **OUT_OF_SCOPE** | no | Final upload is intentionally local after download and preflight. |

## Next action

3D QA PR4 4f70c0454fa5b44fb054c2171b8de397e77aa951 CI 40570709568 SUCCESS (78/78 synthetic regressions + actual Windows SDK MakeAppx unsigned 133878-byte multi-block fixture, Artifact 12764902990, SHA-256 a4cbceb7bb5828714f8859bd3164833201bf584a640856b4056afaff412eb413). ZIP64 data descriptor, MakeAppx OPC manifest default, b4 FileHash, compressed trailer verified; forged descriptor rejected. Next strengthen realistic Godot EXE/PCK-to-MSIX payload contract without generating new product; retain all safety checks. 36min Windows owner: reconcile central other_lanes.GAME_3D factory_branch/head/CI to Factory PR12 current ledger and QA PR4 4f70c0454fa5b44fb054c2171b8de397e77aa951, keep 3D queue isolated and request_id/source_sha/factory_build_head immutable. No accepted 3D product, official Identity, product MSIX, Windows GPU/GUI or commercial QA; 120h generation HOLD, active_product=null, new_product_allowed=false.

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

## Evidence pins

- **factory** — `shihuiarenjinba-png/3d-game-factory` / `codex/3d-dispatch-guard-current-ledger-20261027-1628` / `ed99cfc49d0295e0945d8a7e641757df2771335b` / run `40560589315`
- **provisioner** — `shihuiarenjinba-png/Repository-Provisioner-3D` / `codex/e2e-belt-connection-20261027` / `70600e77f2dd4278a989604314eebfa662e05c33` / run `40454089167`
- **template** — `shihuiarenjinba-png/3d-game-template` / `codex/3d-template-godot-bootstrap-20261026` / `e5462d0aa1f5d0a50fa484ad1544c11ce8a6085a` / run `40360649193`; artifact `godot-3d-windows-x64-qa-unsigned`
- **qa** — `shihuiarenjinba-png/3d-build-qa` / `codex/3d-msix-zip-path-safety-20261027-1235` / `4f70c0454fa5b44fb054c2171b8de397e77aa951` / run `40570709568`; artifact `makeappx-3d-offline-unsigned-fixture-not-product`
- **intake** — `shihuiarenjinba-png/Windows-all-auto` / `codex/e2e-belt-connection-20261027` / `a1a8d084f843107ba73f964a399eb14387092bba` / run `40570514472`
- **windows_data** — `shihuiarenjinba-png/Windows-data` / `codex/msix-auto-build-identity-20261025` / `664b9afcbed63539b89f594892d831d97b9d4118` / run `40259906737`; artifact `MSIXAutoBuildIdentity-Windows-QA`

## Automation rule

Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.
