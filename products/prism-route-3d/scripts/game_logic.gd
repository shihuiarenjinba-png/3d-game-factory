extends RefCounted
## Deterministic offline gameplay; no network or external assets.
const LIMIT_SECONDS = 120.0
const TARGETS = [Vector2i(0, 0), Vector2i(4, 0), Vector2i(4, 4)]
const BLOCKED = [Vector2i(1, 1), Vector2i(3, 1), Vector2i(1, 3), Vector2i(3, 3)]
var player: Vector2i = Vector2i(2, 2)
var next_target: int = 0
var remaining: float = LIMIT_SECONDS
var status: String = "playing"
var paused: bool = false

func reset() -> void:
    player = Vector2i(2, 2)
    next_target = 0
    remaining = LIMIT_SECONDS
    status = "playing"
    paused = false

func move(step: Vector2i) -> bool:
    if status != "playing" or paused or abs(step.x) + abs(step.y) != 1:
        return false
    var destination: Vector2i = player + step
    if destination.x < 0 or destination.x > 4 or destination.y < 0 or destination.y > 4:
        return false
    if destination in BLOCKED:
        return false
    player = destination
    if next_target < TARGETS.size() and player == TARGETS[next_target]:
        next_target += 1
        if next_target == TARGETS.size():
            status = "won"
    return true

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
