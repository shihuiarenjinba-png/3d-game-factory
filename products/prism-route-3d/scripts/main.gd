extends Node3D
## Floating tower network with deterministic Sentinel scan, traps, pause, restart, EN/JA and local best.
const LOGIC = preload("res://scripts/game_logic.gd")
const SAVE = preload("res://scripts/save_store.gd")
const SAVE_PATH = "user://prism_route_progress.cfg"
# The previous camera (6.5, 9, 8) made the 5x5 route only ~330px wide at
# 1024x768. This framing targets ~500px while preserving HUD clearance.
const BOARD_CAMERA_POSITION = Vector3(4.5, 6.2, 5.5)
const BOARD_CAMERA_FOV = 72.0
var game = LOGIC.new()
var language: String = "en"
var best_seconds: float = -1.0
var player_mesh: MeshInstance3D
var targets: Array[MeshInstance3D] = []
var tower_order_labels: Array[Label3D] = []
var status_label: Label
var hint_label: Label
var restart_button: Button
var pause_button: Button
var language_button: Button
var recorded_win: bool = false
var scan_markers: Array[MeshInstance3D] = []
var scan_marker_directions: Array[int] = []
var scan_label: Label
# The 90-second clock starts only after the player has read the first-run guide.
var onboarding_active: bool = true
var onboarding_panel: PanelContainer
var onboarding_title: Label
var onboarding_details: Label
var start_button: Button

func _ready() -> void:
    var saved: Dictionary = SAVE.load_data(SAVE_PATH)
    best_seconds = saved["best_seconds"]
    language = saved["language"]
    _build_world()
    _build_ui()
    _sync_world()
    _refresh_ui()

func _process(delta: float) -> void:
    var hits_before: int = game.scan_hits
    if not onboarding_active:
        game.tick(delta)
    if game.scan_hits != hits_before:
        _sync_world()
    _sync_scan_world()
    if game.status == "won" and not recorded_win:
        recorded_win = true
        var score: float = game.elapsed()
        if best_seconds < 0.0 or score < best_seconds:
            best_seconds = score
        _persist()
    _refresh_ui()

# A timed route must not expire while Windows focus is elsewhere. Do not
# automatically resume on focus return: the player chooses when it is safe.
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and game != null and game.status == "playing" and not game.paused:
        game.toggle_pause()
        _refresh_ui()

func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return
    if onboarding_active:
        if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
            _start_run()
        elif event.keycode == KEY_L:
            _toggle_language()
        get_viewport().set_input_as_handled()
        return
    var step := Vector2i.ZERO
    match event.keycode:
        KEY_W, KEY_UP:
            step = Vector2i(0, -1)
        KEY_S, KEY_DOWN:
            step = Vector2i(0, 1)
        KEY_A, KEY_LEFT:
            step = Vector2i(-1, 0)
        KEY_D, KEY_RIGHT:
            step = Vector2i(1, 0)
        KEY_R:
            _restart()
        KEY_P, KEY_ESCAPE:
            _toggle_pause()
        KEY_L:
            _toggle_language()
    if step != Vector2i.ZERO and game.move(step):
        _sync_world()
    _refresh_ui()
    get_viewport().set_input_as_handled()

func _material(color: Color) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.65
    return mat

func _box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.material_override = _material(color)
    node.position = pos
    add_child(node)
    return node

func _build_world() -> void:
    var camera := Camera3D.new()
    camera.name = "GameplayCamera"
    camera.position = BOARD_CAMERA_POSITION
    camera.fov = BOARD_CAMERA_FOV
    add_child(camera)
    camera.look_at(Vector3.ZERO, Vector3.UP)
    camera.current = true
    var sun := DirectionalLight3D.new()
    sun.rotation = Vector3(-0.8, -0.6, 0.0)
    sun.light_energy = 1.7
    add_child(sun)
    for x in range(5):
        for z in range(5):
            var cell := Vector2i(x, z)
            var pos := Vector3(float(x - 2) * 1.3, -0.18, float(z - 2) * 1.3)
            _box(pos, Vector3(1.23, 0.3, 1.23), Color(0.12, 0.22, 0.30) if (x + z) % 2 == 0 else Color(0.16, 0.29, 0.36))
            if cell in LOGIC.TIME_TRAPS:
                _box(pos + Vector3(0, 0.18, 0), Vector3(1.0, 0.08, 1.0), Color(0.96, 0.43, 0.10))
            elif cell in LOGIC.WARP_TRAPS:
                _box(pos + Vector3(0, 0.18, 0), Vector3(1.0, 0.08, 1.0), Color(0.55, 0.20, 0.72))
            if cell in LOGIC.BLOCKED:
                _box(pos + Vector3(0, 0.55, 0), Vector3(0.85, 0.9, 0.85), Color(0.48, 0.16, 0.18))
    for i in range(LOGIC.TARGETS.size()):
        var target: Vector2i = LOGIC.TARGETS[i]
        var pos := Vector3(float(target.x - 2) * 1.3, 0.48, float(target.y - 2) * 1.3)
        targets.append(_box(pos, Vector3(0.55, 0.8, 0.55), Color(0.94, 0.73, 0.24)))
        # World-space, camera-facing numerals make the required 1 -> 2 -> 3
        # order visible without relying on HUD text or color perception.
        var order_label := Label3D.new()
        order_label.name = "TowerOrder%d" % (i + 1)
        order_label.text = str(i + 1)
        order_label.position = pos + Vector3(0, 0.93, 0)
        order_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        order_label.no_depth_test = true
        order_label.font_size = 70
        order_label.pixel_size = 0.009
        order_label.outline_size = 12
        order_label.modulate = Color(1, 0.94, 0.68)
        add_child(order_label)
        tower_order_labels.append(order_label)
    player_mesh = _box(Vector3(0, 0.53, 0), Vector3(0.7, 0.85, 0.7), Color(0.22, 0.84, 0.90))
    # One stationary elevated Sentinel. Its warning tiles are visible before firing.
    _box(Vector3(0.0, 1.85, 0.0), Vector3(0.62, 0.62, 0.62), Color(0.70, 0.33, 0.87))
    for direction in range(4):
        for cell in game.scan_cells(direction):
            var pos := Vector3(float(cell.x - 2) * 1.3, 0.11, float(cell.y - 2) * 1.3)
            var marker := _box(pos, Vector3(1.03, 0.035, 1.03), Color(1.0, 0.65, 0.14, 0.58))
            marker.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            marker.visible = false
            scan_markers.append(marker)
            scan_marker_directions.append(direction)
    _sync_scan_world()

func _tower_marker_color(index: int) -> Color:
    if index < game.next_target:
        return Color(0.32, 0.93, 0.49)
    if index == game.next_target:
        return Color(0.29, 0.96, 1.0)
    return Color(1.0, 0.85, 0.42)

func _sync_world() -> void:
    player_mesh.position = Vector3(float(game.player.x - 2) * 1.3, 0.53, float(game.player.y - 2) * 1.3)
    for i in range(targets.size()):
        targets[i].material_override = _material(Color(0.17, 0.65, 0.32) if i < game.next_target else Color(0.95, 0.72, 0.17))
        tower_order_labels[i].text = str(i + 1)
        tower_order_labels[i].modulate = _tower_marker_color(i)

func _scan_marker_color() -> Color:
    # Yellow telegraph is distinguishable from orange time traps; active
    # crimson scan is distinguishable from both. No random instant damage.
    return Color(1.0, 0.19, 0.24, 0.85) if game.scan_active() else Color(1.0, 0.94, 0.22, 0.76)

func _sync_scan_world() -> void:
    var direction: int = game.scan_direction()
    var beam_color := _scan_marker_color()
    for i in range(scan_markers.size()):
        scan_markers[i].visible = scan_marker_directions[i] == direction and game.status == "playing"
        if scan_markers[i].visible:
            scan_markers[i].material_override.albedo_color = beam_color

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var top := PanelContainer.new()
    top.anchor_right = 1.0
    top.offset_left = 16
    top.offset_top = 12
    top.offset_right = -16
    top.offset_bottom = 164
    layer.add_child(top)
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 8)
    top.add_child(stack)
    status_label = Label.new()
    status_label.add_theme_font_size_override("font_size", 19)
    stack.add_child(status_label)
    scan_label = Label.new()
    scan_label.add_theme_font_size_override("font_size", 16)
    stack.add_child(scan_label)
    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 12)
    stack.add_child(buttons)
    restart_button = Button.new()
    restart_button.custom_minimum_size = Vector2(155, 42)
    restart_button.pressed.connect(_restart)
    buttons.add_child(restart_button)
    pause_button = Button.new()
    pause_button.custom_minimum_size = Vector2(155, 42)
    pause_button.pressed.connect(_toggle_pause)
    buttons.add_child(pause_button)
    language_button = Button.new()
    language_button.custom_minimum_size = Vector2(155, 42)
    language_button.pressed.connect(_toggle_language)
    buttons.add_child(language_button)
    var bottom := PanelContainer.new()
    bottom.anchor_top = 1.0
    bottom.anchor_right = 1.0
    bottom.anchor_bottom = 1.0
    bottom.offset_left = 16
    bottom.offset_right = -16
    bottom.offset_top = -96
    bottom.offset_bottom = -12
    layer.add_child(bottom)
    hint_label = Label.new()
    hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hint_label.add_theme_font_size_override("font_size", 17)
    bottom.add_child(hint_label)

    # Deliberate, bilingual first-30-second orientation: no clock pressure
    # until Start. It is a product UI, not a debug panel or tutorial fixture.
    onboarding_panel = PanelContainer.new()
    onboarding_panel.name = "FirstRunGuide"
    onboarding_panel.set_anchors_preset(Control.PRESET_CENTER)
    onboarding_panel.offset_left = -335
    onboarding_panel.offset_top = -185
    onboarding_panel.offset_right = 335
    onboarding_panel.offset_bottom = 185
    var guide_style := StyleBoxFlat.new()
    guide_style.bg_color = Color(0.07, 0.10, 0.14, 0.98)
    guide_style.border_color = Color(0.26, 0.78, 0.90)
    guide_style.set_border_width_all(2)
    guide_style.set_corner_radius_all(12)
    onboarding_panel.add_theme_stylebox_override("panel", guide_style)
    layer.add_child(onboarding_panel)
    var guide_margin := MarginContainer.new()
    guide_margin.add_theme_constant_override("margin_left", 24)
    guide_margin.add_theme_constant_override("margin_right", 24)
    guide_margin.add_theme_constant_override("margin_top", 20)
    guide_margin.add_theme_constant_override("margin_bottom", 20)
    onboarding_panel.add_child(guide_margin)
    var guide_stack := VBoxContainer.new()
    guide_stack.add_theme_constant_override("separation", 15)
    guide_margin.add_child(guide_stack)
    onboarding_title = Label.new()
    onboarding_title.add_theme_font_size_override("font_size", 24)
    onboarding_title.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
    onboarding_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    guide_stack.add_child(onboarding_title)
    onboarding_details = Label.new()
    onboarding_details.add_theme_font_size_override("font_size", 19)
    onboarding_details.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
    onboarding_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    guide_stack.add_child(onboarding_details)
    start_button = Button.new()
    start_button.custom_minimum_size = Vector2(220, 52)
    start_button.add_theme_font_size_override("font_size", 20)
    start_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
    var start_style := StyleBoxFlat.new()
    start_style.bg_color = Color(0.07, 0.48, 0.61)
    start_style.set_corner_radius_all(8)
    var hover_style := start_style.duplicate() as StyleBoxFlat
    hover_style.bg_color = Color(0.11, 0.62, 0.73)
    start_button.add_theme_stylebox_override("normal", start_style)
    start_button.add_theme_stylebox_override("hover", hover_style)
    start_button.add_theme_stylebox_override("pressed", hover_style)
    start_button.pressed.connect(_start_run)
    guide_stack.add_child(start_button)

    # Font bytes and OFL notice are pinned and embedded at export time.
    # No font download or system-installed Japanese font is needed at runtime.
    var consumer_font := load("res://assets/fonts/NotoSansJP.ttf") as Font
    if consumer_font == null or not consumer_font.has_char(0x65E5):
        push_error("RELEASE_JP_FONT_MISSING: refuse consumer GUI promotion")
    else:
        var consumer_theme := Theme.new()
        consumer_theme.default_font = consumer_font
        top.theme = consumer_theme
        bottom.theme = consumer_theme
        onboarding_panel.theme = consumer_theme
    _refresh_onboarding()

func _refresh_onboarding() -> void:
    if onboarding_title == null:
        return
    if language == "ja":
        onboarding_title.text = "90秒で3つの塔を起動！"
        onboarding_details.text = "目的：塔の番号 1 → 2 → 3 の順に到達。\n操作：WASD / 矢印キーで移動。\nSentinel：黄色は予告、赤は照射（被弾で6秒減）。\n罠：橙は15秒減、紫は8秒減＋中央へ転送。\n準備ができたら開始。時計は開始まで止まります。"
        start_button.text = "ゲーム開始 (Enter)"
    else:
        onboarding_title.text = "Activate 3 towers in 90 seconds!"
        onboarding_details.text = "GOAL: Reach towers 1 → 2 → 3 in order.\nMOVE: WASD or arrow keys.\nSENTINEL: Yellow warns; red scans (hit costs 6s).\nTRAPS: Orange costs 15s; purple costs 8s + warp.\nPress Start when ready. The clock waits for you."
        start_button.text = "Start Game (Enter)"

func _start_run() -> void:
    if not onboarding_active:
        return
    onboarding_active = false
    if onboarding_panel != null:
        onboarding_panel.hide()
    _refresh_ui()

func _refresh_ui() -> void:
    _refresh_onboarding()
    if status_label == null:
        return
    var progress: String = "%d/3" % game.next_target
    var next_tower: String = str(game.next_target + 1) if game.next_target < LOGIC.TARGETS.size() else "--"
    var best: String = "--" if best_seconds < 0.0 else "%.1fs" % best_seconds
    var remaining: int = int(ceil(game.remaining))
    var scan_direction_name: String = LOGIC.SCAN_DIRECTION_NAMES[game.scan_direction()]
    var scan_countdown: float = game.scan_seconds_until_change()
    if language == "ja":
        status_label.text = "Prism Route 3D | 次の塔 %s | 完了 %s | 残り %d秒 | 最速 %s" % [next_tower, progress, remaining, best]
        scan_label.text = "Sentinel %s | %s %.1f秒 | 被弾 %d" % [scan_direction_name, "照射中・終了まで" if game.scan_active() else "予告・照射まで", scan_countdown, game.scan_hits]
        hint_label.text = "頭上の番号 1→2→3 の順に塔へ。WASD/矢印で移動。橙=-15秒、紫=-8秒+転送。光るSentinel予告帯を避けよう。"
        # Current state must outrank a stale trap/scan event, otherwise pause
        # and completion can be invisible immediately after a penalty.
        if game.status == "won":
            hint_label.text = "クリア！ R または再スタートで再挑戦できます。"
        elif game.status == "failed":
            hint_label.text = "時間切れ。罠を避けるルートを考えて再挑戦。"
        elif game.paused:
            hint_label.text = "一時停止中。P または再開ボタンで続行。"
        elif game.last_event == "sentinel_scan":
            hint_label.text = "Sentinel照射！ 6秒失い中央へ押し戻されました。予告帯を避けよう。"
        elif game.last_event == "time_trap":
            hint_label.text = "時間罠！ 15秒失いました。短い道ほど安全とは限りません。"
        elif game.last_event == "warp_trap":
            hint_label.text = "ワープ罠！ 8秒失い、中央へ戻されました。"
        pause_button.text = "再開 (P)" if game.paused else "一時停止 (P)"
        restart_button.text = "再スタート (R)"
        language_button.text = "English (L)"
    else:
        status_label.text = "Prism Route 3D | NEXT Tower %s | Done %s | %ds left | Best %s" % [next_tower, progress, remaining, best]
        scan_label.text = "Sentinel %s | %s %.1fs | Hits %d" % [scan_direction_name, "SCAN ends in" if game.scan_active() else "warning, fires in", scan_countdown, game.scan_hits]
        hint_label.text = "Follow tower numbers 1→2→3. WASD/arrows move. Orange=-15s, purple=-8s+warp. Avoid the glowing Sentinel warning lane."
        if game.status == "won":
            hint_label.text = "Route complete! Press R or Restart to play again."
        elif game.status == "failed":
            hint_label.text = "Time up. Plan a safer route and try again."
        elif game.paused:
            hint_label.text = "Paused. Press P or Resume to continue."
        elif game.last_event == "sentinel_scan":
            hint_label.text = "Sentinel scan! Lost 6 seconds and pushed to center. Avoid the warned lane."
        elif game.last_event == "time_trap":
            hint_label.text = "Time trap! Lost 15 seconds. The shortest route is not always the safest."
        elif game.last_event == "warp_trap":
            hint_label.text = "Warp trap! Lost 8 seconds and returned to the center."
        pause_button.text = "Resume (P)" if game.paused else "Pause (P)"
        restart_button.text = "Restart (R)"
        language_button.text = "日本語 (L)"

func _restart() -> void:
    game.reset()
    recorded_win = false
    _sync_world()
    _sync_scan_world()
    _refresh_ui()

func _toggle_pause() -> void:
    game.toggle_pause()
    _refresh_ui()

func _toggle_language() -> void:
    language = "ja" if language == "en" else "en"
    _persist()
    _refresh_ui()

func _persist() -> void:
    if not SAVE.save_data(SAVE_PATH, best_seconds, language):
        push_warning("Local progress could not be saved; play remains offline.")
