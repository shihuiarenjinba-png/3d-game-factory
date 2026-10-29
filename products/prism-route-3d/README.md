# Prism Route 3D — single-product Factory canary

Original offline Godot 4.3 route puzzle. Visit three golden towers in order before 90 seconds while choosing between risky shortcuts and safer detours. Red pillars block movement. Two visible orange time-trap cells remove 15 seconds the first time they are stepped on; two visible purple warp-trap cells remove 8 seconds and return the player to the center. This makes the shortest route different from the safest route and adds route-planning pressure without hidden or random punishment.

WASD/arrows move, P pauses, R restarts, L switches English/Japanese; all three also have mouse-accessible UI buttons. Best completion time and language are stored only in user://prism_route_progress.cfg. Missing/empty/corrupt/invalid saves safely reset. Primitive 3D geometry only; no external API, login, telemetry, purchases, network requirement or third-party assets.

1024x768 anchored HUD and instructions. Headless gameplay regression: godot --headless --path . --script res://tests/test_smoke.gd; import: godot --headless --editor --path . --import; launch: godot --headless --path . --quit-after 60.

**Only one canary authorized.** This is an explicit one-product exception to the old 120-hour generation gate, NOT a global reopening or authorization for a second product. The trap-tension revision is a new gameplay revision based on the already-returned Partner Center Identity; it requires fresh Factory/Provisioner provenance and package QA before Store packaging. Never treat the earlier immutable source SHA as the new gameplay source. Godot EXE/PCK and MakeAppx outputs remain QA-only until the new revision is rebuilt and verified. Never promote this product as Store-ready from fixture or CI alone.
