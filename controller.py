"""Fail-closed 120-hour 3D project state machine. No network or Store actions."""
import argparse
import json
import os
import re
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
ROUTES = {
    ("PROVISIONING", "PROVISIONED"): "BUILDING",
    ("BUILDING", "BUILD_PASSED"): "AUTO_QA",
    ("AUTO_QA", "AUTO_QA_PASSED"): "WAIT_HUMAN_QA",
    ("WAIT_HUMAN_QA", "HUMAN_APPROVED"): "HANDOFF_REVIEW",
}
REPO = re.compile(r"^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$")
REQUIRED = {"PROVISIONED": "repository_full_name", "BUILD_PASSED": "build_run_id",
            "AUTO_QA_PASSED": "qa_run_id", "HUMAN_APPROVED": "approval_reference"}


def parse_time(value):
    x = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if x.tzinfo is None or x.utcoffset() is None:
        raise ValueError("timezone-aware ISO time required")
    return x


def _id(value):
    return isinstance(value, str) and ID.fullmatch(value) is not None


def initialize(request_id, start_at):
    if not _id(request_id):
        raise ValueError("invalid request_id")
    start = parse_time(start_at)
    return {
        "schema_version": "1.0", "request_id": request_id,
        "source_factory": "3d-game-factory", "product_type": "GAME_3D",
        "started_at": start.isoformat(), "deadline_at": (start + timedelta(days=5)).isoformat(),
        "phase": "PROVISIONING", "last_at": start.isoformat(),
        "seen_events": {}, "evidence": {},
        "submission_authorized": False,
    }


def advance(state, event, now_at):
    """Return new state; caller must persist it with single-writer/CAS protection."""
    now = parse_time(now_at)
    if state.get("schema_version") != "1.0" or state.get("source_factory") != "3d-game-factory":
        raise ValueError("invalid state")
    if not isinstance(event, dict) or not _id(event.get("event_id")):
        raise ValueError("event_id required")
    import hashlib
    digest = hashlib.sha256(json.dumps(event, sort_keys=True).encode("utf-8")).hexdigest()
    previous = state.get("seen_events", {}).get(event["event_id"])
    if previous is not None:
        if previous != digest:
            raise ValueError("same event_id with different payload")
        return dict(state)
    if now < parse_time(state["last_at"]):
        raise ValueError("time cannot go backwards")
    phase = state["phase"]
    updated = json.loads(json.dumps(state))
    deadline = parse_time(state["deadline_at"])
    if now > deadline and phase not in ("WAIT_HUMAN_QA", "HANDOFF_REVIEW", "HOLD"):
        updated["phase"] = "HOLD"
        updated["hold_reason"] = "five-day development window expired"
    elif event.get("type") == "TICK":
        # Pure heartbeat; does not assert that any build/provisioner work ran.
        pass
    elif event.get("type") == "FAIL":
        updated["phase"] = "HOLD"
        updated["hold_reason"] = str(event.get("reason", "manual investigation needed"))[:256]
    else:
        next_phase = ROUTES.get((phase, event.get("type")))
        if not next_phase:
            raise ValueError(f"invalid transition from {phase}")
        required = REQUIRED[event["type"]]
        if not (_id(event.get(required)) if required != "repository_full_name" else
                isinstance(event.get(required), str) and REPO.fullmatch(event[required])):
            raise ValueError(f"{required} is required")
        updated["phase"] = next_phase
        updated["evidence"][event["type"]] = event[required]
    updated["seen_events"][event["event_id"]] = digest
    updated["last_at"] = now.isoformat()
    updated["submission_authorized"] = False
    return updated


def _save(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Atomic on one filesystem. Cross-worker locking and durable storage are not provided.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as f:
        json.dump(state, f, ensure_ascii=False, sort_keys=True, indent=2)
        f.write("\n")
        temp_name = f.name
    os.replace(temp_name, path)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    sp = p.add_subparsers(dest="op", required=True)
    init = sp.add_parser("init")
    init.add_argument("state_file", type=Path)
    init.add_argument("request_id")
    init.add_argument("start_at")
    step = sp.add_parser("event")
    step.add_argument("state_file", type=Path)
    step.add_argument("event_json", type=Path)
    step.add_argument("now_at")
    args = p.parse_args(argv)
    if args.op == "init":
        if args.state_file.exists():
            raise SystemExit("HOLD: state already exists; refusing overwrite")
        result = initialize(args.request_id, args.start_at)
    else:
        result = advance(json.loads(args.state_file.read_text(encoding="utf-8")),
                         json.loads(args.event_json.read_text(encoding="utf-8")), args.now_at)
    _save(args.state_file, result)
    print(json.dumps({"request_id": result["request_id"], "phase": result["phase"],
                      "deadline_at": result["deadline_at"], "submission_authorized": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
