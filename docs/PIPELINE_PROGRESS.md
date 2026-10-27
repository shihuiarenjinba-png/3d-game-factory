# 3D Pipeline Progress

- Ledger schema: `1.0`
- Updated UTC: `2026-10-27T03:11:40Z`
- New-product gate: **HOLD** — No accepted 3D candidate baseline is recorded; scheduler must improve QA/build/transport instead of generating a new game.
- Next stage: `factory_product_materialization`
- Next repository: `shihuiarenjinba-png/3d-game-factory`
- Next branch: `codex/3d-accept-qa-snapshot-20261027-1209`

## Stage status

| Stage | State | Auto-actionable | Result |
| --- | --- | --- | --- |
| `template_windows_export` | **DONE** | no | Godot 4.3 Windows x64 EXE/PCK export succeeds and produces a real QA artifact. |
| `factory_product_materialization` | **HOLD** | yes | No independently reviewed playable 3D source exists. Factory acceptance now preserves late symlinks, re-audits the copied product tree for Windows safety and checks both the copied bytes and original source against the exact real Godot QA digest before publication. Product acceptance and real Godot candidate QA remain HOLD. |
| `provisioner_windows_build` | **IN_PROGRESS** | yes | Local 3D manufacturing now accepts a real Godot Windows EXE/PCK export as pre-MSIX payload evidence, preserves its SHA/signature status, requires official Store ID/Identity/Publisher/Version/PFN/Package SID evidence, and returns the full request/product/source correlation key to Factory. Final Identity-to-package match is deliberately deferred to the Factory MSIX. |
| `official_identity_roundtrip` | **IN_PROGRESS** | yes | 3D Identity return now preserves request_id, GAME_3D product type, Factory/repository/branch/source SHA/slug, local package SHA/kind/signature status, and official Store ID/Identity/Publisher/Version/PFN/Package SID. Existing records are reusable only when the whole manufacturing provenance matches. |
| `factory_msix_build` | **IN_PROGRESS** | yes | Factory MSIX builder now consumes the returned 3D correlation/provenance record, keeps the original product source_sha immutable, records the later GitHub packaging commit separately as factory_build_head, and carries local package SHA plus Store ID/PFN/SID into the strict handoff. PowerShell syntax and Factory quality gates pass. |
| `msix_byte_qa` | **IN_PROGRESS** | yes | MSIX SHA/manifest/Identity/executable payload checks are implemented. |
| `windows_all_auto_intake` | **IN_PROGRESS** | yes | 3D intake now validates the complete manufacturing correlation key and treats source_sha as the immutable original product SHA while separately binding factory_build_head to the exact successful Actions run. It rechecks MSIX bytes/Identity and rejects lane/request/branch/provenance mixing. Ubuntu and Windows offline CI pass. |
| `local_windows_gpu_qa` | **HOLD** | no | Not executed. |
| `signing_and_store_validation` | **HOLD** | no | Not executed. |
| `local_submission_automation` | **OUT_OF_SCOPE** | no | Final upload is intentionally local after download and preflight. |

## Next action

Find an independently reviewed authorized playable Godot 4.3 project outside Factory, stage its exact SHA-256 and run real engine QA before accepting. Acceptance now binds the actual copied product bytes to QA evidence; no reviewed game is available, so continue hardening manufacturing/QA/transport without inventing a candidate.

Acceptance:
- Source ownership, licensing and gameplay are independently reviewed; source_reviewed is explicit and no source is invented.
- Pre/post-copy audits, expected source digest, Windows-safe paths, no symlinks/cache, quotas, 120-hour gate and no overwrite hold.
- Real Godot 4.3 import/smoke/60-frame main-scene QA binds exact source digest to the same cycle.
- Acceptance rechecks the staged product and original source digest against QA evidence before publication; mismatches HOLD with no product or state advancement.
- After real acceptance, proceed to Provisioner/official Identity/MSIX/Artifact intake; never infer Store Identity or declare E2E PASS without real MSIX.

## Evidence pins

- **factory** — `shihuiarenjinba-png/3d-game-factory` / `codex/3d-accept-qa-snapshot-20261027-1209` / `f5d9ded36e686780c3854e5343328b6990b49e2f` / run `40442744751`
- **provisioner** — `shihuiarenjinba-png/Repository-Provisioner-3D` / `codex/3d-local-identity-provenance-20261027` / `a1727307884176bfa97f714c47705281240d83c3` / run `40431389877`
- **template** — `shihuiarenjinba-png/3d-game-template` / `codex/3d-template-godot-bootstrap-20261026` / `e5462d0aa1f5d0a50fa484ad1544c11ce8a6085a` / run `40360649193`; artifact `godot-3d-windows-x64-qa-unsigned`
- **qa** — `shihuiarenjinba-png/3d-build-qa` / `codex/3d-msix-executable-payload-20261027` / `04f2b1f74674159197cc3f8fa7503705b4febcfb` / run `40417351553`
- **intake** — `shihuiarenjinba-png/Windows-all-auto` / `codex/3d-e2e-trace-contract-20261027` / `d0ad76c0312669e9cb8ff67dfd893dd61539388b` / run `40431368563`

## Automation rule

Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.
