extends SceneTree
const LOGIC = preload("res://scripts/game_logic.gd")
const SAVE = preload("res://scripts/save_store.gd")

func check(value: bool, message: String) -> void:
    if not value:
        push_error("FAIL: " + message)
        assert(false, message)
        quit(1)

func _initialize() -> void:
    test_gameplay()
    test_traps()
    test_save()
    print("PASS: Prism Route 3D gameplay, visible traps, pause, win, timeout, restart, corrupt/empty save, EN/JA")
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
