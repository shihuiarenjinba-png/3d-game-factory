extends SceneTree
const LOGIC = preload("res://scripts/game_logic.gd")
const SAVE = preload("res://scripts/save_store.gd")
const MAIN = preload("res://scripts/main.gd")

func check(value: bool, message: String) -> void:
    if not value:
        push_error("FAIL: " + message)
        assert(false, message)
        quit(1)

func _initialize() -> void:
    test_gameplay()
    test_traps()
    test_sentinel()
    test_save()
    test_focus_pause()
    print("PASS: Prism Route 3D gameplay, visible traps, telegraphed Sentinel, pause, win, timeout, restart, corrupt/empty save, focus-loss pause, EN/JA")
    quit(0)

func test_gameplay() -> void:
    var game = LOGIC.new()
    check(game.status == "playing" and game.player == Vector2i(2, 2), "initial state")
    check(game.remaining == 90.0, "90 second pressure clock")
    check(not game.move(Vector2i(2, 0)), "reject non-unit input")
    check(game.move(Vector2i(0, -1)), "move to (2,1)")
    check(not game.move(Vector2i(-1, 0)), "blocked obstacle")
    game.toggle_pause()
    var before: float = game.remaining
    check(not game.move(Vector2i(0, -1)), "paused movement")
    game.tick(30.0)
    check(game.remaining == before, "paused timer")
    game.toggle_pause()
    check(game.move(Vector2i(0, -1)), "move to first time trap")
    check(game.remaining == 75.0 and game.last_event == "time_trap", "time trap penalty")
    check(game.move(Vector2i(-1, 0)) and game.move(Vector2i(-1, 0)), "first target")
    check(game.next_target == 1, "first beacon")
    for i in range(4):
        check(game.move(Vector2i(1, 0)), "top row")
    check(game.next_target == 2, "second beacon")
    for i in range(4):
        check(game.move(Vector2i(0, 1)), "right edge")
    check(game.status == "won" and game.next_target == 3, "completion")
    check(game.trap_hits == 2 and game.remaining == 60.0, "two strategic time traps")
    check(not game.move(Vector2i(-1, 0)), "no movement after win")
    game.reset()
    check(game.status == "playing" and game.next_target == 0 and game.trap_hits == 0, "restart")
    game.tick(91.0)
    check(game.status == "failed" and game.remaining == 0.0, "timeout")
    check(not game.move(Vector2i(0, 1)), "no movement after failure")

func test_traps() -> void:
    var game = LOGIC.new()
    check(game.move(Vector2i(0, -1)), "approach time trap")
    check(game.move(Vector2i(0, -1)), "enter time trap")
    check(game.remaining == 75.0 and game.trap_hits == 1, "time trap triggered")
    check(game.move(Vector2i(-1, 0)), "leave time trap")
    check(game.move(Vector2i(1, 0)), "re-enter time trap")
    check(game.remaining == 75.0 and game.trap_hits == 1, "time trap only triggers once per run")

    game.reset()
    check(game.move(Vector2i(-1, 0)), "approach warp trap")
    check(game.move(Vector2i(-1, 0)), "enter warp trap")
    check(game.player == Vector2i(2, 2), "warp returns player to center")
    check(game.remaining == 82.0 and game.trap_hits == 1 and game.last_event == "warp_trap", "warp trap penalty")

func test_sentinel() -> void:
    var game = LOGIC.new()
    check(game.scan_direction() == 0 and not game.scan_active(), "north scan is visibly telegraphed")
    check(game.scan_cells(0) == [Vector2i(2, 1), Vector2i(2, 0)], "north beam geometry")
    check(game.scan_cells(1) == [Vector2i(3, 2), Vector2i(4, 2)], "east beam geometry")
    check(game.move(Vector2i(0, -1)), "enter north danger lane")
    game.tick(3.9)
    check(not game.scan_active() and game.scan_hits == 0, "no damage during warning")
    game.toggle_pause()
    var frozen: float = game.scan_elapsed
    game.tick(10.0)
    check(game.scan_elapsed == frozen and game.scan_hits == 0, "pause freezes Sentinel")
    game.toggle_pause()
    game.tick(0.2)
    check(game.scan_active() and game.scan_hits == 1, "predictable active scan hit")
    check(game.player == Vector2i(2, 2) and game.last_event == "sentinel_scan", "nonlethal center knockback")
    check(absf(game.remaining - 79.9) < 0.01, "six-second scan penalty")
    game.tick(0.2)
    check(game.scan_hits == 1, "no repeat hit during same scan")
    game.tick(1.9)
    check(game.scan_direction() == 1 and not game.scan_active(), "next warning rotates clockwise")
    game.reset()
    check(game.scan_elapsed == 0.0 and game.scan_hits == 0 and game.last_scan_hit_cycle == -1, "restart resets Sentinel")
    game.move(Vector2i(0, -1))
    game.tick(4.1)
    check(game.scan_hits == 1, "new run may be hit again")

    # A frame stall that skips past the two-second active window must not
    # silently let the player escape an already-telegraphed scan.
    var stalled = LOGIC.new()
    check(stalled.move(Vector2i(0, -1)), "stalled-frame player enters north lane")
    stalled.tick(6.1)
    check(stalled.scan_direction() == 1 and not stalled.scan_active(), "stalled frame ends in east warning")
    check(stalled.scan_hits == 1 and stalled.player == LOGIC.START_CELL, "crossed active scan still hits once")
    check(absf(stalled.remaining - 77.9) < 0.01, "stalled frame charges time plus one scan penalty")
    stalled.tick(0.1)
    check(stalled.scan_hits == 1, "no duplicate hit after crossed active scan")

    var boundary = LOGIC.new()
    check(boundary.move(Vector2i(0, -1)), "boundary player enters north lane")
    boundary.tick(6.0)
    check(boundary.scan_hits == 1, "scan ending exactly at cycle boundary is not skipped")

func test_focus_pause() -> void:
    # Simulate Windows losing foreground focus while the timed run is active.
    # A second focus-out must not resume an already paused game.
    var scene = MAIN.new()
    check(not scene.game.paused, "initially active before focus loss")
    scene.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
    check(scene.game.paused, "focus loss auto-pauses gameplay")
    var frozen: float = scene.game.remaining
    scene.game.tick(5.0)
    check(scene.game.remaining == frozen, "focus loss freezes timer")
    scene.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
    check(scene.game.paused, "repeat focus loss does not toggle back to playing")
    scene.game.toggle_pause()
    check(not scene.game.paused, "player explicitly resumes")
    scene.free()

func test_save() -> void:
    var path := "user://prism_route_smoke_test.cfg"
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    var missing: Dictionary = SAVE.load_data(path)
    check(missing["best_seconds"] == -1.0 and missing["language"] == "en", "missing save")
    var file := FileAccess.open(path, FileAccess.WRITE)
    check(file != null, "corrupt fixture")
    file.store_string("corrupt@@[not a config")
    file.close()
    check(SAVE.load_data(path)["best_seconds"] == -1.0, "corrupt fallback")
    file = FileAccess.open(path, FileAccess.WRITE)
    check(file != null, "empty fixture")
    file.close()
    check(SAVE.load_data(path)["language"] == "en", "empty fallback")
    check(SAVE.save_data(path, 19.5, "ja"), "save score/language")
    var loaded: Dictionary = SAVE.load_data(path)
    check(loaded["best_seconds"] == 19.5 and loaded["language"] == "ja", "restore")
    check(not SAVE.save_data(path, -4.0, "en"), "invalid best")
    check(not SAVE.save_data(path, 10.0, "xx"), "invalid language")
    DirAccess.remove_absolute(absolute)
