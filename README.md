# 3d-game-factory

5-day development coordinator for independent 3D game repositories. This branch currently includes a **fail-closed offline controller**, not an operating autonomous factory.

- Product intake is separate from APP and GAME. This factory uses type `GAME_3D`.
- Project content is specified later; no fixed game concept is embedded.
- Development window: 120 hours; human weekend playtest is a separate, explicit gate.
- Repository creation is delegated to `Repository-Provisioner-3D` (local team).
- Build and GPU QA will be delegated to `3d-build-qa`.
- Artifact handoff is delegated to `3d-artifact-bridge`.
- Windows-all-auto receives evidence-review candidates only; never auto-publish.

```bash
python -m unittest discover -s tests -v
python controller.py init state.json project-001 2026-10-26T09:00:00+09:00
```

Full constraints: [docs/INTEGRATION.md](docs/INTEGRATION.md).
