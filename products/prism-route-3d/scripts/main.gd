extends Node3D
## Floating tower network with deterministic Sentinel scan, traps, pause, restart, EN/JA and local best.
const LOGIC = preload("res://scripts/game_logic.gd")
const SAVE = preload("res://scripts/save_store.gd")
const SAVE_PATH = "user://prism_route_progress.cfg"
var game = LOGIC.new()
var language: String = "en"
var best_seconds: float = -1.0
var player_mesh: MeshInstance3D
var targets: Array[MeshInstance3D] = []
var status_label: Label
var hint_label: Label
var restart_button: Button
var pause_button: Button
var language_button: Button
var recorded_win: bool = false
var scan_markers: Array[MeshInstance3D] = []
var scan_marker_directions: Array[int] = []
var scan_label: Label

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

func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed or event.echo:
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
    camera.position = Vector3(6.5, 9.0, 8.0)
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
    for target in LOGIC.TARGETS:
        var pos := Vector3(float(target.x - 2) * 1.3, 0.48, float(target.y - 2) * 1.3)
        targets.append(_box(pos, Vector3(0.55, 0.8, 0.55), Color(0.94, 0.73, 0.24)))
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

func _sync_world() -> void:
    player_mesh.position = Vector3(float(game.player.x - 2) * 1.3, 0.53, float(game.player.y - 2) * 1.3)
    for i in range(targets.size()):
        targets[i].material_override = _material(Color(0.17, 0.65, 0.32) if i < game.next_target else Color(0.95, 0.72, 0.17))

func _sync_scan_world() -> void:
    var direction: int = game.scan_direction()
    var beam_color := Color(1.0, 0.19, 0.24, 0.72) if game.scan_active() else Color(1.0, 0.69, 0.15, 0.58)
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

func _refresh_ui() -> void:
    if status_label == null:
        return
    var progress: String = "%d/3" % game.next_target
    var best: String = "--" if best_seconds < 0.0 else "%.1fs" % best_seconds
    var remaining: int = int(ceil(game.remaining))
    var scan_direction_name: String = LOGIC.SCAN_DIRECTION_NAMES[game.scan_direction()]
    var scan_countdown: float = game.scan_seconds_until_change()
    if language == "ja":
        status_label.text = "Prism Route 3D | 塔 %s | 残り %d秒 | 罠 %d | 最速 %s" % [progress, remaining, game.trap_hits, best]
        scan_label.text = "Sentinel %s | %s %.1f秒 | 被弾 %d" % [scan_direction_name, "照射中・終了まで" if game.scan_active() else "予告・照射まで", scan_countdown, game.scan_hits]
        hint_label.text = "塔を順番に起動。橙=-15秒、紫=-8秒+中央転送。Sentinelの予告帯は照射前に離れよう。"
        if game.last_event == "sentinel_scan":
            hint_label.text = "Sentinel照射！ 6秒失い中央へ押し戻されました。予告帯を避けよう。"
        elif game.last_event == "time_trap":
            hint_label.text = "時間罠！ 15秒失いました。短い道ほど安全とは限りません。"
        elif game.last_event == "warp_trap":
            hint_label.text = "ワープ罠！ 8秒失い、中央へ戻されました。"
        elif game.status == "won":
            hint_label.text = "クリア！ R または再スタートで再挑戦できます。"
        elif game.status == "failed":
            hint_label.text = "時間切れ。罠を避けるルートを考えて再挑戦。"
        elif game.paused:
            hint_label.text = "一時停止中。P または再開ボタンで続行。"
        pause_button.text = "再開 (P)" if game.paused else "一時停止 (P)"
        restart_button.text = "再スタート (R)"
        language_button.text = "English (L)"
    else:
        status_label.text = "Prism Route 3D | Towers %s | %ds left | Traps %d | Best %s" % [progress, remaining, game.trap_hits, best]
        scan_label.text = "Sentinel %s | %s %.1fs | Hits %d" % [scan_direction_name, "SCAN ends in" if game.scan_active() else "warning, fires in", scan_countdown, game.scan_hits]
        hint_label.text = "Activate towers in order. Orange=-15s, purple=-8s+warp. Leave the Sentinel's warned lane before it fires."
        if game.last_event == "sentinel_scan":
            hint_label.text = "Sentinel scan! Lost 6 seconds and pushed to center. Avoid the warned lane."
        elif game.last_event == "time_trap":
            hint_label.text = "Time trap! Lost 15 seconds. The shortest route is not always the safest."
        elif game.last_event == "warp_trap":
            hint_label.text = "Warp trap! Lost 8 seconds and returned to the center."
        elif game.status == "won":
            hint_label.text = "Route complete! Press R or Restart to play again."
        elif game.status == "failed":
            hint_label.text = "Time up. Plan a safer route and try again."
        elif game.paused:
            hint_label.text = "Paused. Press P or Resume to continue."
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
