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
    test_ui_state_priority()
    test_failure_reason_guidance()
    test_tower_order_discoverability()
    test_board_visibility_contract()
    test_hud_readability_contract()
    test_bottom_hint_single_line()
    test_first_run_orientation()
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

func test_ui_state_priority() -> void:
    # A stale trap event must not hide Pause, Win, or Time Up. This was
    # especially confusing when focus loss auto-paused just after a trap.
    var scene = MAIN.new()
    scene.status_label = Label.new()
    scene.scan_label = Label.new()
    scene.hint_label = Label.new()
    scene.restart_button = Button.new()
    scene.pause_button = Button.new()
    scene.language_button = Button.new()
    for control in [scene.status_label, scene.scan_label, scene.hint_label,
                    scene.restart_button, scene.pause_button, scene.language_button]:
        scene.add_child(control)
    scene.game.last_event = "time_trap"
    scene.game.toggle_pause()
    scene._refresh_ui()
    check(scene.hint_label.text.begins_with("Paused."), "English pause outranks stale trap")
    scene.language = "ja"
    scene._refresh_ui()
    check(scene.hint_label.text.begins_with("一時停止中"), "Japanese pause outranks stale trap")
    scene.game.toggle_pause()
    scene.game.status = "won"
    scene._refresh_ui()
    check(scene.hint_label.text.begins_with("クリア！"), "Japanese win outranks stale trap")
    scene.language = "en"
    scene._refresh_ui()
    check(scene.hint_label.text.begins_with("Route complete!"), "English win outranks stale trap")
    scene.game.status = "failed"
    scene.game.failure_reason = "timeout"
    scene._refresh_ui()
    check(scene.hint_label.text.begins_with("Time up."), "English failure outranks stale trap")
    scene.language = "ja"
    scene._refresh_ui()
    check(scene.hint_label.text.begins_with("時間切れ"), "Japanese failure outranks stale trap")
    scene.free()


func test_failure_reason_guidance() -> void:
    # Source/headless UI assertions. Real exported PCK screenshots are a
    # separate gate; this is not physical Windows or human play evidence.
    var scene = MAIN.new()
    scene.status_label = Label.new()
    scene.scan_label = Label.new()
    scene.hint_label = Label.new()
    scene.restart_button = Button.new()
    scene.pause_button = Button.new()
    scene.language_button = Button.new()
    for control in [scene.status_label, scene.scan_label, scene.hint_label,
                    scene.restart_button, scene.pause_button, scene.language_button]:
        scene.add_child(control)

    # No trap was hit: stale trap telemetry must not turn timeout into trap advice.
    scene.game.last_event = "time_trap"
    scene.game.tick(91.0)
    check(scene.game.status == "failed" and scene.game.failure_reason == "timeout",
          "natural timeout is terminally classified, even with stale trap event")
    scene.language = "en"
    scene._refresh_ui()
    check(scene.hint_label.text.contains("Time up.") and scene.hint_label.text.contains("1→2→3")
          and not scene.hint_label.text.contains("Trap"),
          "English pure timeout advises tower order, never trap")
    scene.language = "ja"
    scene._refresh_ui()
    check(scene.hint_label.text.contains("時間切れ") and scene.hint_label.text.contains("塔1→2→3")
          and not scene.hint_label.text.contains("罠"),
          "Japanese pure timeout advises tower order, never trap")

    # A trap itself exhausts the clock: show specific trap advice in both locales.
    scene.game.reset()
    check(scene.game.failure_reason.is_empty(), "restart clears terminal cause")
    scene.game.remaining = 10.0
    check(scene.game.move(Vector2i(0, -1)) and scene.game.move(Vector2i(0, -1)),
          "reach orange time trap")
    check(scene.game.status == "failed" and scene.game.failure_reason == "trap",
          "trap exhaustion is terminally classified")
    scene.language = "ja"
    scene._refresh_ui()
    check(scene.hint_label.text.contains("罠") and scene.hint_label.text.contains("橙"),
          "Japanese trap defeat identifies dangerous tile")
    scene.language = "en"
    scene._refresh_ui()
    check(scene.hint_label.text.contains("Trap") and scene.hint_label.text.contains("orange"),
          "English trap defeat identifies dangerous tile")

    # Sentinel scan can also exhaust the clock; do not falsely blame a trap.
    scene.game.reset()
    scene.game.remaining = 5.0
    check(scene.game.move(Vector2i(0, -1)), "enter north scan lane")
    scene.game.tick(4.1)
    check(scene.game.status == "failed" and scene.game.failure_reason == "sentinel",
          "Sentinel exhaustion has its own terminal cause")
    scene.language = "ja"
    scene._refresh_ui()
    check(scene.hint_label.text.contains("Sentinel") and scene.hint_label.text.contains("予告帯"),
          "Japanese Sentinel failure identifies warning lane")
    scene.language = "en"
    scene._refresh_ui()
    check(scene.hint_label.text.contains("Sentinel") and scene.hint_label.text.contains("warning"),
          "English Sentinel failure identifies warning lane")

    # A malformed/unknown terminal state cannot invent a trap or timeout.
    scene.game.reset()
    scene.game.status = "failed"
    scene.language = "en"
    scene._refresh_ui()
    check(scene.hint_label.text.begins_with("Run ended."),
          "unknown English cause stays neutral")
    scene.language = "ja"
    scene._refresh_ui()
    check(scene.hint_label.text.begins_with("失敗しました"),
          "unknown Japanese cause stays neutral")
    # The headless test has no 3D scene; provide the minimal player mesh that
    # _restart uses when synchronizing world state.
    scene.player_mesh = MeshInstance3D.new()
    scene.add_child(scene.player_mesh)
    scene._restart()
    check(scene.game.status == "playing" and scene.game.failure_reason.is_empty()
          and scene.game.remaining == 90.0,
          "retry restores full clock and clears cause")
    scene.free()


func test_tower_order_discoverability() -> void:
    # Pure headless UI state checks; the real Label3D render remains a separate
    # software-rendered/physical-Windows gate, not a human usability PASS.
    var scene = MAIN.new()
    scene.status_label = Label.new()
    scene.scan_label = Label.new()
    scene.hint_label = Label.new()
    scene.restart_button = Button.new()
    scene.pause_button = Button.new()
    scene.language_button = Button.new()
    for control in [scene.status_label, scene.scan_label, scene.hint_label,
                    scene.restart_button, scene.pause_button, scene.language_button]:
        scene.add_child(control)
    scene._refresh_ui()
    check(scene.status_label.text.contains("NEXT Tower 1"), "first-frame next tower number")
    check(scene.hint_label.text.contains("1→2→3"), "first-frame tower order instructions")
    check(scene._tower_marker_color(0) != scene._tower_marker_color(1),
          "current tower must be visually distinguished from later towers")
    scene.game.next_target = 1
    scene._refresh_ui()
    check(scene.status_label.text.contains("NEXT Tower 2"), "next target updates after tower 1")
    check(scene._tower_marker_color(0) != scene._tower_marker_color(1),
          "completed and current tower colors differ")
    scene.language = "ja"
    scene._refresh_ui()
    check(scene.status_label.text.contains("次の塔 2"), "Japanese next tower state")
    check(scene.hint_label.text.contains("1→2→3"), "Japanese tower order instructions")
    scene.game.next_target = 3
    scene.game.status = "won"
    scene._refresh_ui()
    check(scene.status_label.text.contains("次の塔 --"), "no next tower after completion")
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

func test_board_visibility_contract() -> void:
    # Source-level framing guard only. Real exported PCK screenshot and
    # physical Windows 125%/150% DPI remain independent release gates.
    var camera_distance: float = MAIN.BOARD_CAMERA_POSITION.length()
    check(camera_distance > 8.5 and camera_distance < 10.0,
          "camera must fill more of the 1024x768 play area without clipping HUD")
    check(MAIN.BOARD_CAMERA_FOV >= 70.0 and MAIN.BOARD_CAMERA_FOV <= 73.0,
          "consumer camera field of view pinned")
    var scene = MAIN.new()
    var warning: Color = scene._scan_marker_color()
    check(warning.g > 0.85 and warning.b < 0.4 and warning.a >= 0.7,
          "Sentinel warning is bright yellow, not orange time-trap color")
    scene.game.tick(4.1)
    var active: Color = scene._scan_marker_color()
    check(active.r > 0.9 and active.g < 0.3 and active.a >= 0.8,
          "active scan must be clearly red and more opaque than warning")
    check(active != warning, "warning and active scan colors differ")
    scene.free()

func hud_has_sufficient_contrast(text_color: Color, panel_color: Color) -> bool:
    return text_color.get_luminance() - panel_color.get_luminance() >= 0.70

func test_hud_readability_contract() -> void:
    # Source/headless regression; actual 1024x768 PCK frames and physical DPI
    # must be separately reviewed. This is not human legibility evidence.
    check(hud_has_sufficient_contrast(MAIN.HUD_TEXT_COLOR, MAIN.HUD_PANEL_COLOR),
          "gameplay HUD white text contrasts with dark opaque panel")
    check(not hud_has_sufficient_contrast(Color(0.5, 0.5, 0.5), Color(0.25, 0.25, 0.25)),
          "reject low-contrast gray-on-gray HUD regression")
    var scene = MAIN.new()
    var panel := PanelContainer.new()
    var button := Button.new()
    scene.add_child(panel)
    scene.add_child(button)
    scene._style_gameplay_hud_panel(panel)
    scene._style_gameplay_hud_button(button)
    var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
    check(style != null and style.bg_color == MAIN.HUD_PANEL_COLOR,
          "HUD panel uses opaque high-contrast background")
    check(button.get_theme_font_size("font_size") >= 19,
          "HUD controls must have legible minimum font size")
    scene.free()

func guide_copy_within_budget(copy: String) -> bool:
    var lines := copy.split("\n")
    if lines.size() != 4:
        return false
    for line in lines:
        if line.strip_edges().is_empty() or line.length() > 65:
            return false
    return true

func test_first_run_orientation() -> void:
    # This is a source/headless contract, not a human first-30s usability pass.
    var scene = MAIN.new()
    check(scene.onboarding_active, "first-run guide visible before the 90s clock")
    scene._process(30.0)
    check(scene.game.remaining == 90.0 and scene.game.scan_elapsed == 0.0,
          "reading the guide never consumes time or advances Sentinel")
    scene.onboarding_title = Label.new()
    scene.onboarding_details = Label.new()
    scene.start_button = Button.new()
    for control in [scene.onboarding_title, scene.onboarding_details, scene.start_button]:
        scene.add_child(control)
    scene._refresh_onboarding()
    check(scene.onboarding_title.text.contains("1 → 2 → 3") and scene.onboarding_details.text.contains("YELLOW") and scene.onboarding_details.text.contains("ORANGE") and scene.onboarding_details.text.contains("PURPLE"),
          "English guide prioritizes numbered goal, warning colors, and both trap types")
    check(guide_copy_within_budget(scene.onboarding_details.text),
          "English first-run copy must fit four readable lines")
    check(scene.start_button.text.contains("Enter"), "keyboard start discoverable")
    scene.language = "ja"
    scene._refresh_onboarding()
    check(scene.onboarding_title.text.contains("1 → 2 → 3") and scene.onboarding_details.text.contains("黄色") and scene.onboarding_details.text.contains("赤") and scene.onboarding_details.text.contains("橙") and scene.onboarding_details.text.contains("紫"),
          "Japanese guide prioritizes numbered goal, warning colors, and both trap types")
    check(guide_copy_within_budget(scene.onboarding_details.text),
          "Japanese first-run copy must fit four readable lines")
    check(not guide_copy_within_budget("one\ntwo\nthree\nfour\nfive"),
          "reject a five-line onboarding regression fixture")
    check(not guide_copy_within_budget("This excessively detailed instruction line is far too long to fit a small consumer display.\nmove\nscan\nstart"),
          "reject a long-line onboarding regression fixture")
    check(not guide_copy_within_budget("move\n\nscan\nstart"),
          "reject a blank instruction line regression fixture")
    check(scene.start_button.text.contains("開始"), "Japanese start action discoverable")
    scene._start_run()
    check(not scene.onboarding_active, "Start dismisses guide")
    scene._process(1.0)
    check(scene.game.remaining < 90.0 and scene.game.scan_elapsed > 0.0,
          "90s clock and scan resume only after Start")
    scene._start_run()
    check(not scene.onboarding_active, "duplicate Start is idempotent")
    scene.free()

func test_bottom_hint_single_line() -> void:
    # Actual Noto JP font metrics at the minimum 1024px viewport, not
    # character counts: avoid the observed Japanese orphan "う。" and
    # the short English second line. Physical Windows DPI is a separate gate.
    var font := load("res://assets/fonts/NotoSansJP.ttf") as Font
    check(font != null, "consumer JP font is available for hint width QA")
    var scene = MAIN.new()
    scene.status_label = Label.new()
    scene.scan_label = Label.new()
    scene.hint_label = Label.new()
    scene.restart_button = Button.new()
    scene.pause_button = Button.new()
    scene.language_button = Button.new()
    for control in [scene.status_label, scene.scan_label, scene.hint_label,
                    scene.restart_button, scene.pause_button, scene.language_button]:
        scene.add_child(control)
    # 1024 viewport - 16px left/right panel offsets - safety margin.
    # The live hint uses 20px type and smart autowrap.
    var safe_width := 960.0
    for locale in ["ja", "en"]:
        scene.language = locale
        scene._refresh_ui()
        var actual_width := font.get_string_size(scene.hint_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
        check(actual_width <= safe_width,
              "%s initial HUD hint must fit on one line at 1024px (%.1f > %.1f)" % [locale, actual_width, safe_width])
    var old_orphan_copy := "頭上の番号 1→2→3 の順に塔へ。WASD/矢印で移動。橙=-15秒、紫=-8秒+転送。光るSentinel予告帯を避けよう。"
    check(font.get_string_size(old_orphan_copy, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x > safe_width,
          "negative fixture: old Japanese hint must fail the width gate")
    scene.free()
