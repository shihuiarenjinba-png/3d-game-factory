"""Machine-readable 3D pipeline progress ledger.

Schedulers/agents should read factory/pipeline-progress.json first, validate it,
then select the declared next_action. This file does not submit to Store or
invent Identity; it only validates and renders the repository-local ledger.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LEDGER = ROOT / "factory" / "pipeline-progress.json"
DEFAULT_REPORT = ROOT / "docs" / "PIPELINE_PROGRESS.md"

SHA40 = re.compile(r"^[0-9a-f]{40}$")
REPO = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
ALLOWED_STATES = {"DONE", "IN_PROGRESS", "HOLD", "NOT_STARTED", "OUT_OF_SCOPE"}


class LedgerError(ValueError):
    pass


def load(path: Path) -> dict:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise LedgerError(f"cannot read progress ledger: {exc}") from exc
    if not isinstance(raw, dict):
        raise LedgerError("progress ledger root must be an object")
    return raw


def _require_text(value: object, label: str, max_len: int = 1000) -> str:
    if not isinstance(value, str) or not value or len(value) > max_len or any(c in value for c in "\r\n\0"):
        raise LedgerError(f"invalid {label}")
    return value


def validate(data: dict) -> None:
    if data.get("schema_version") != "1.0":
        raise LedgerError("unsupported schema_version")
    if data.get("lane") != "3d-game":
        raise LedgerError("ledger belongs to the wrong lane")

    policy = data.get("policy")
    if not isinstance(policy, dict):
        raise LedgerError("policy missing")
    required_policy = {
        "new_product_min_interval_hours": 120,
        "store_submission_allowed": False,
        "identity_guessing_allowed": False,
        "openai_api_required": False,
        "ollama_required": False,
        "main_release_write_allowed": False,
        "unsigned_msix_is_store_ready": False,
    }
    for key, expected in required_policy.items():
        if policy.get(key) != expected:
            raise LedgerError(f"unsafe or unexpected policy value: {key}")

    generation = data.get("generation_gate")
    if not isinstance(generation, dict) or generation.get("state") not in {"HOLD", "READY"}:
        raise LedgerError("invalid generation_gate")
    last = generation.get("last_accepted_candidate_utc")
    if last is not None and not isinstance(last, str):
        raise LedgerError("invalid last accepted candidate timestamp")
    _require_text(generation.get("reason"), "generation gate reason", 2000)
    allowed = generation.get("new_product_allowed")
    if type(allowed) is not bool:
        raise LedgerError("new_product_allowed must be an explicit boolean")
    if (generation["state"] == "HOLD" and allowed) or (generation["state"] == "READY" and not allowed):
        raise LedgerError("generation state and new_product_allowed disagree")
    if "active_product" not in data:
        raise LedgerError("active_product field missing")
    active = data["active_product"]
    if active is not None and not isinstance(active, dict):
        raise LedgerError("invalid active_product")
    if active is not None and allowed:
        raise LedgerError("cannot authorize new generation while active_product exists")

    repos = data.get("repositories")
    if not isinstance(repos, dict) or not repos:
        raise LedgerError("repository evidence missing")
    for name, item in repos.items():
        if not isinstance(item, dict):
            raise LedgerError(f"invalid repository evidence: {name}")
        repo = _require_text(item.get("repo"), f"{name}.repo", 200)
        if not REPO.fullmatch(repo):
            raise LedgerError(f"invalid repository name: {name}")
        _require_text(item.get("branch"), f"{name}.branch", 240)
        head = item.get("head")
        if not isinstance(head, str) or not SHA40.fullmatch(head):
            raise LedgerError(f"invalid repository head: {name}")
        run = item.get("ci_run_id")
        if not isinstance(run, int) or run <= 0:
            raise LedgerError(f"invalid CI run id: {name}")
        artifact = item.get("artifact")
        if artifact is not None:
            _require_text(artifact, f"{name}.artifact", 240)

    order = data.get("stage_order")
    stages = data.get("stages")
    if not isinstance(order, list) or not order or not all(isinstance(x, str) for x in order):
        raise LedgerError("stage_order missing")
    if len(order) != len(set(order)):
        raise LedgerError("duplicate stage id")
    if not isinstance(stages, dict) or set(stages) != set(order):
        raise LedgerError("stage_order and stages must contain exactly the same ids")

    for stage_id in order:
        stage = stages[stage_id]
        if not isinstance(stage, dict):
            raise LedgerError(f"invalid stage: {stage_id}")
        if stage.get("state") not in ALLOWED_STATES:
            raise LedgerError(f"invalid stage state: {stage_id}")
        if type(stage.get("auto_actionable")) is not bool:
            raise LedgerError(f"auto_actionable must be boolean: {stage_id}")
        owner = _require_text(stage.get("owner_repo"), f"{stage_id}.owner_repo", 200)
        if owner != "local-windows" and not REPO.fullmatch(owner):
            raise LedgerError(f"invalid owner repo: {stage_id}")
        _require_text(stage.get("result"), f"{stage_id}.result", 3000)
        for key in ("evidence", "remaining"):
            values = stage.get(key)
            if not isinstance(values, list) or not all(isinstance(v, str) and v for v in values):
                raise LedgerError(f"invalid {key}: {stage_id}")

    next_action = data.get("next_action")
    if not isinstance(next_action, dict):
        raise LedgerError("next_action missing")
    stage_id = next_action.get("stage_id")
    if stage_id not in stages:
        raise LedgerError("next_action points to unknown stage")
    stage = stages[stage_id]
    if stage["state"] in {"DONE", "OUT_OF_SCOPE"} or stage["auto_actionable"] is not True:
        raise LedgerError("next_action is not an actionable unfinished stage")
    repo = _require_text(next_action.get("repo"), "next_action.repo", 200)
    if repo != stage["owner_repo"]:
        raise LedgerError("next_action repo does not own the selected stage")
    _require_text(next_action.get("branch"), "next_action.branch", 240)
    if not SHA40.fullmatch(str(next_action.get("expected_head_sha", ""))):
        raise LedgerError("invalid next_action.expected_head_sha")
    _require_text(next_action.get("goal"), "next_action.goal", 3000)
    acceptance = next_action.get("acceptance")
    if not isinstance(acceptance, list) or not acceptance or not all(isinstance(x, str) and x for x in acceptance):
        raise LedgerError("next_action acceptance missing")


def render_report(data: dict) -> str:
    validate(data)
    gate = data["generation_gate"]
    next_action = data["next_action"]
    lines = [
        "# 3D Pipeline Progress",
        "",
        f"- Ledger schema: `{data['schema_version']}`",
        f"- Updated UTC: `{data['updated_at_utc']}`",
        f"- New-product gate: **{gate['state']}** — {gate['reason']}",
        f"- Next stage: `{next_action['stage_id']}`",
        f"- Next repository: `{next_action['repo']}`",
        f"- Next branch: `{next_action['branch']}`",
        f"- Next HEAD: `{next_action['expected_head_sha']}`",
        "",
        "## Stage status",
        "",
        "| Stage | State | Auto-actionable | Result |",
        "| --- | --- | --- | --- |",
    ]
    for stage_id in data["stage_order"]:
        stage = data["stages"][stage_id]
        result = stage["result"].replace("|", r"\|").replace("\n", " ")
        lines.append(f"| `{stage_id}` | **{stage['state']}** | {'yes' if stage['auto_actionable'] else 'no'} | {result} |")

    lines += [
        "",
        "## Next action",
        "",
        next_action["goal"],
        "",
        "Acceptance:",
    ]
    lines.extend(f"- {item}" for item in next_action["acceptance"])
    lines += ["", "## Evidence pins", ""]
    for name, item in data["repositories"].items():
        suffix = f"; artifact `{item['artifact']}`" if item.get("artifact") else ""
        lines.append(
            f"- **{name}** — `{item['repo']}` / `{item['branch']}` / "
            f"`{item['head']}` / run `{item['ci_run_id']}`{suffix}"
        )

    lines += [
        "",
        "## Automation rule",
        "",
        "Scheduled agents must read and validate `factory/pipeline-progress.json` before choosing work. "
        "They should advance the declared next stage with a real `codex/*` GitHub change and CI/build evidence. "
        "A no-change run is acceptable only when a recorded HOLD/permission/conflict/safety gate prevents a write. "
        "Do not fabricate Store Identity, price, security declarations, signing results, GPU QA, certification, or Store submission.",
        "",
    ]
    return "\n".join(lines)


def next_action(data: dict) -> dict:
    validate(data)
    return data["next_action"]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("validate", "next", "render", "check-report"))
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args(argv)
    try:
        data = load(args.ledger)
        if args.command == "validate":
            validate(data)
            print("PIPELINE_PROGRESS_VALID")
        elif args.command == "next":
            print(json.dumps(next_action(data), ensure_ascii=False, indent=2))
        elif args.command == "render":
            rendered = render_report(data)
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(rendered, encoding="utf-8", newline="\n")
            print(f"PIPELINE_PROGRESS_RENDERED {args.report}")
        else:
            expected = render_report(data)
            actual = args.report.read_text(encoding="utf-8")
            if actual != expected:
                raise LedgerError("progress report is stale; run: python tools/pipeline_progress.py render")
            print("PIPELINE_PROGRESS_REPORT_CURRENT")
        return 0
    except (OSError, LedgerError) as exc:
        print(f"PIPELINE_PROGRESS_HOLD: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
