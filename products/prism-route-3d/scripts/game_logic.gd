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
# One stationary Prism Sentinel projects a deterministic, telegraphed scan lane.
# The player is never chased; a scan hit costs time and safely resets position.
const SCAN_TELEGRAPH_SECONDS = 4.0
const SCAN_ACTIVE_SECONDS = 2.0
const SCAN_CYCLE_SECONDS = SCAN_TELEGRAPH_SECONDS + SCAN_ACTIVE_SECONDS
const SCAN_PENALTY_SECONDS = 6.0
const SCAN_DIRECTION_NAMES = ["N", "E", "S", "W"]

var player: Vector2i = START_CELL
var next_target: int = 0
var remaining: float = LIMIT_SECONDS
var status: String = "playing"
var paused: bool = false
var trap_hits: int = 0
var last_event: String = ""
var triggered_time_traps: Array[Vector2i] = []
var scan_elapsed: float = 0.0
var scan_hits: int = 0
var last_scan_hit_cycle: int = -1

func reset() -> void:
    player = START_CELL
    next_target = 0
    remaining = LIMIT_SECONDS
    status = "playing"
    paused = false
    trap_hits = 0
    last_event = ""
    triggered_time_traps.clear()
    scan_elapsed = 0.0
    scan_hits = 0
    last_scan_hit_cycle = -1

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

func scan_direction() -> int:
    return int(floor(scan_elapsed / SCAN_CYCLE_SECONDS)) % 4

func scan_active() -> bool:
    return fposmod(scan_elapsed, SCAN_CYCLE_SECONDS) >= SCAN_TELEGRAPH_SECONDS

func scan_seconds_until_change() -> float:
    var phase: float = fposmod(scan_elapsed, SCAN_CYCLE_SECONDS)
    return SCAN_CYCLE_SECONDS - phase if scan_active() else SCAN_TELEGRAPH_SECONDS - phase

func scan_cells(direction: int) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    for distance in range(1, 3):
        match direction:
            0:
                cells.append(START_CELL + Vector2i(0, -distance))
            1:
                cells.append(START_CELL + Vector2i(distance, 0))
            2:
                cells.append(START_CELL + Vector2i(0, distance))
            3:
                cells.append(START_CELL + Vector2i(-distance, 0))
    return cells

func tick(seconds: float) -> void:
    if status != "playing" or paused or seconds <= 0.0:
        return
    remaining = maxf(0.0, remaining - seconds)
    if remaining <= 0.0:
        status = "failed"
        return
    # A stalled frame can cross an entire two-second scan. Check every
    # active interval intersected by the tick, not only the ending phase.
    var previous_scan_elapsed: float = scan_elapsed
    scan_elapsed += seconds
    var first_cycle: int = int(floor(previous_scan_elapsed / SCAN_CYCLE_SECONDS))
    var last_cycle: int = int(floor(scan_elapsed / SCAN_CYCLE_SECONDS))
    for cycle in range(first_cycle, last_cycle + 1):
        var active_start: float = float(cycle) * SCAN_CYCLE_SECONDS + SCAN_TELEGRAPH_SECONDS
        var active_end: float = float(cycle + 1) * SCAN_CYCLE_SECONDS
        if previous_scan_elapsed >= active_end or scan_elapsed < active_start:
            continue
        if last_scan_hit_cycle == cycle or player not in scan_cells(cycle % 4):
            continue
        last_scan_hit_cycle = cycle
        scan_hits += 1
        remaining = maxf(0.0, remaining - SCAN_PENALTY_SECONDS)
        player = START_CELL
        last_event = "sentinel_scan"
        if remaining <= 0.0:
            status = "failed"
            break

func toggle_pause() -> void:
    if status == "playing":
        paused = not paused

func elapsed() -> float:
    return LIMIT_SECONDS - remaining
