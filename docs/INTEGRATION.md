# 3D factory — five-day orchestration boundary

**Present stage:** offline state machine only. **Not** a self-running 3D engine, not proven to run for five days, not a Windows build system.

`controller.py init state.json project-001 2026-10-26T09:00:00+09:00` creates a five-day, timezone-aware deadline. The job transitions only after explicit evidence events, and moves to HOLD if development expires. HUMAN_APPROVED can happen after the five-day window: this separates weekday production from a weekend playtest.

Event types: PROVISIONED (repository_full_name), BUILD_PASSED (build_run_id), AUTO_QA_PASSED (qa_run_id), HUMAN_APPROVED (approval_reference), FAIL (reason). Same event ID/payload is idempotent; conflicts are rejected. Neither the event input nor state proves independent evidence: downstream verification remains required. No Store submission or public release is authorized by this system.

**Do not run scheduled GitHub Actions workflows that write ephemeral local state files.** A durable, compare-and-swap backed store/queue and a single active lease per request are prerequisites. This CLI uses atomic local file replacement but not distributed locking. Configure a cloud-backed Windows GPU build worker and trusted evidence adapters separately. 3D asset storage must be external and garbage collection explicitly scoped to disposable build data; approved archives are protected. No project files need persist on the user's local PC except a human QA copy.

Provisioner-3D remains locally owned and may have a different contract: adapt only after its reviewed handoff. Avoid creating repositories or moving to a new stage based on a synthetic event. UI project specifications intentionally remain out of scope.
