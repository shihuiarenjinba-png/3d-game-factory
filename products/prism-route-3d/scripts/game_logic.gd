extends RefCounted
## Deterministic offline gameplay; no network or external assets.
const LIMIT_SECONDS = 90.0
const TARGETS = [Vector2i(0, 0), Vector2i(4, 0), Vector2i(4, 4)]
const BLOCKED = [Vector2i(1, 1), Vector2i(3, 1), Vector2i(1, 3), Vector2i(3, 3)]
const TIME_TRAPS = [Vector2i(2, 0), Vector2i(4, 3)]
const WARP_TRAPS = [Vector2i(0, 2), Vector2i(2, 4)]
const TIME_TRAP_PENALTY = 15.0
const WARP_TRAP_PENALTY = 8.0
const START_CELL = Vector2i(2, 2)

var player: Vector2i = START_CELL
var next_target: int = 0
var remaining: float = LIMIT_SECONDS
var status: String = "playing"
var paused: bool = false
var trap_hits: int = 0
var last_event: String = ""
var triggered_time_traps: Array[Vector2i] = []

func reset() -> void:
    player = START_CELL
    next_target = 0
    remaining = LIMIT_SECONDS
    status = "playing"
    paused = false
    trap_hits = 0
    last_event = ""
    triggered_time_traps.clear()

func move(step: Vector2i) -> bool:
    if status != "playing" or paused or abs(step.x) + abs(step.y) != 1:
        return false
    var destination: Vector2i = player + step
    if destination.x < 0 or destination.x > 4 or destination.y < 0 or destination.y > 4:
        return false
    if destination in BLOCKED:
        return false

    last_event = ""
    player = destination
    _apply_trap()

    if status == "playing" and next_target < TARGETS.size() and player == TARGETS[next_target]:
        next_target += 1
        if next_target == TARGETS.size():
            status = "won"
    return true

func _apply_trap() -> void:
    if player in TIME_TRAPS and player not in triggered_time_traps:
        triggered_time_traps.append(player)
        trap_hits += 1
        remaining = maxf(0.0, remaining - TIME_TRAP_PENALTY)
        last_event = "time_trap"
    elif player in WARP_TRAPS:
        trap_hits += 1
        remaining = maxf(0.0, remaining - WARP_TRAP_PENALTY)
        player = START_CELL
        last_event = "warp_trap"

    if remaining <= 0.0:
        status = "failed"

func tick(seconds: float) -> void:
    if status != "playing" or paused or seconds <= 0.0:
        return
    remaining = maxf(0.0, remaining - seconds)
    if remaining <= 0.0:
        status = "failed"

func toggle_pause() -> void:
    if status == "playing":
        paused = not paused

func elapsed() -> float:
    return LIMIT_SECONDS - remaining
