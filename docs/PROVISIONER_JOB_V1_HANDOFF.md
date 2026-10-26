# 3D Factory → Local Provisioner v1.0 job handoff

The original `handoff3d.py --output ...` format is a source-only audit record (schema_version integer 1). It is **not** accepted directly by the current `Repository-Provisioner-3D/provisioner.py` job parser, which requires schema_version string `"1.0"` and an exact 12-field contract.

Use the explicit `--format provisioner-job` option to generate a validated, SHA-pinned `GAME_3D` job for the **existing** local Provisioner. No Store ID is generated, reserved, or guessed by this command.

## Safe dry-run (default)

From the approved Factory work branch `codex/3d-provisioner-job-contract-20261027`, with a committed `products/<slug>` Godot project:

```powershell
python handoff3d.py --slug <approved-slug> --display-name "<actual product name>" --format provisioner-job --output local-provisioner-job.json
```

The resulting JSON contains the exact fields required by `Repository-Provisioner-3D/schemas/job-v1.0.schema.json`, including `source_factory="3d-game-factory"`, `source_repository="shihuiarenjinba-png/3d-game-factory"`, pinned `source_sha`, and `dry_run=true`. This only writes a local JSON file. It does not run a Windows build, verify remote HEAD, or fetch Partner Center identity.

## Explicit live request (still no automatic Store action)

```powershell
python handoff3d.py --slug <approved-slug> --display-name "<actual product name>" --format provisioner-job --expected-sha <exact-40-char-commit> --live --output local-provisioner-job.json
```

`--live` is rejected without `--expected-sha`. The local Provisioner must **independently** check GitHub remote HEAD and source tree before any build or Identity return. The generated job requests `BUILD_WINDOWS`, `INSPECT_PACKAGE`, `LOOKUP_OFFICIAL_IDENTITY`, and `PROPOSE_GITHUB_RETURN`, but these actions can HOLD individually if Godot, a valid MSIX, an authenticated Partner Center evidence export, or required GitHub write permission is unavailable.

The return destination is the allowlisted work branch `codex/3d-provisioner-job-contract-20261027`, path `products/<slug>/store/approved-identity.json`. Never write directly to main/release or claim Store readiness without a signed, verified, actual MSIX and Windows GPU QA.

## Scope and validation

- Source-only handoff remains backward-compatible; use `--format provisioner-job` for the actual local CLI.
- Product slug, committed Windows export preset, source SHA and work branch are checked before producing either format.
- Display name must be supplied; do not infer an official product title or Microsoft Identity.
- Tests in `tests/test_handoff3d.py` cover the exact v1.0 field set, safe dry-run, explicit live SHA, and malformed input.
- No new 3D product was generated; the 120-hour production gate is unchanged.
