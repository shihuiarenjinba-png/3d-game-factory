# Prism Route 3D — single-product Factory canary

Original offline Godot 4.3 route puzzle. Visit three golden towers in order before 120 seconds; red pillars block movement. WASD/arrows move, P pauses, R restarts, L switches English/Japanese; all three also have mouse-accessible UI buttons. Best completion time and language are stored only in user://prism_route_progress.cfg. Missing/empty/corrupt/invalid saves safely reset. Primitive 3D geometry only; no external API, login, telemetry, purchases, network requirement or third-party assets.

1024x768 anchored HUD and instructions. Headless gameplay regression: godot --headless --path . --script res://tests/test_smoke.gd; import: godot --headless --editor --path . --import; launch: godot --headless --path . --quit-after 60.

**Only one canary authorized.** This is an explicit one-product exception to the old 120-hour generation gate, NOT a global reopening or authorization for a second product. This source starts as CANDIDATE_PENDING_REAL_GODOT_QA. Godot EXE/PCK and MakeAppx outputs are QA-only until independent Factory Artifact/Provisioner provenance, real Partner Center Identity and later local gates are proven. Never promote this product as Store-ready from fixture or CI alone.
