"""Bounded Godot 4 3D candidate generator and five-day gate.

Writes only drafts to a dedicated branch. No MSIX, Store uploads or sales claims.
"""
import argparse
import hashlib
from datetime import datetime, timezone, timedelta
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parent
EXTENSIONS={".godot",".gd",".tscn",".tres",".md",".json",".cfg"}
NAME=re.compile(r"^[a-z][a-z0-9-]{3,40}$")

def read(path):
    return json.loads(path.read_text(encoding="utf-8"))

def due(state,now):
    if state.get("schema")!=1 or type(state.get("cycle")) is not int or state["cycle"]<1:
        raise ValueError("invalid 3D factory state")
    last=state.get("last_completed_utc")
    if last is None:
        return True
    prior=datetime.fromisoformat(last.replace("Z","+00:00"))
    if prior.tzinfo is None or prior>now:
        raise ValueError("untrusted last completion timestamp")
    return now-prior>=timedelta(days=5)

def prepare(root=ROOT):
    state=read(root/"factory/state.json")
    if not due(state,datetime.now(timezone.utc)):
        raise ValueError("not due for another 3D generation")
    snapshot={"schema":1,"cycle":state["cycle"],"kind":"3d-game","stage":"candidate"}
    runtime=root/".runtime"
    runtime.mkdir(exist_ok=True)
    (root/".candidate").mkdir(exist_ok=True)
    (runtime/"snapshot.json").write_text(json.dumps(snapshot,indent=2))
    prompt="""Write ONE original small but playable Godot 4 3D game under .candidate/project.
    Include project.godot, export_presets.cfg (Windows Desktop preset), scenes/main.tscn, scripts/main.gd, tests/test_smoke.gd and README.md.
    The game must have controls, objectives, restart, failure/success, accessible UI,
    English/Japanese labels when possible, and no third-party assets without licenses.
    Do not write anything outside .candidate/project.
    Avoid network calls, data collection, purchases, native scripts, downloads and plugins.
    Provide a 3D camera, 3D gameplay and a concrete independent automated test.
    GitHub project must not be described as Windows-certified or released.
    """
    (runtime/"PROMPT.md").write_text(prompt)
    return snapshot

def validate(root=ROOT):
    state=read(root/"factory/state.json")
    snap=read(root/".runtime/snapshot.json")
    if snap.get("cycle")!=state.get("cycle") or snap.get("kind")!="3d-game":
        raise ValueError("stale 3D factory stage")
    base=root/".candidate"
    project=base/"project"
    if not project.is_dir() or project.is_symlink():
        raise ValueError("Godot project absent")
    files=[]
    size=0
    for path in base.rglob("*"):
        if path.is_symlink():raise ValueError("symlink rejected")
        if path.is_dir():continue
        rel=path.relative_to(base)
        if any(part.startswith(".") for part in rel.parts) or rel.parts[0]!="project":
            raise ValueError("unexpected candidate path")
        if not path.is_file() or path.suffix.lower() not in EXTENSIONS:
            raise ValueError("disallowed file type")
        # Godot Windows export requires this single known configuration file.
        # Do not permit arbitrary .cfg files to expand the candidate surface.
        if path.suffix.lower()==".cfg" and rel.as_posix()!="project/export_presets.cfg":
            raise ValueError("unexpected Godot configuration file")
        files.append(rel)
        size+=path.stat().st_size
    if not files or len(files)>35 or size>180000:
        raise ValueError("3D candidate exceeded quotas")
    for file in ("project.godot","export_presets.cfg","scenes/main.tscn","scripts/main.gd","tests/test_smoke.gd","README.md"):
        path=project/file
        if not path.is_file() or not path.read_text(encoding="utf-8").strip():
            raise ValueError("missing Godot file: "+file)
    preset_text=(project/"export_presets.cfg").read_text(encoding="utf-8")
    if 'platform="Windows Desktop"' not in preset_text or 'name="Windows Desktop"' not in preset_text:
        raise ValueError("Windows Desktop export preset missing")
    project_text=(project/"project.godot").read_text()
    if "run/main_scene" not in project_text:
        raise ValueError("Godot main scene not configured")
    script=(project/"scripts/main.gd").read_text()
    if "extends Node3D" not in script and "extends CharacterBody3D" not in script:
        raise ValueError("3D gameplay root not implemented")
    if "func test_" not in (project/"tests/test_smoke.gd").read_text():
        raise ValueError("test script must provide test function")
    return snap

def candidate_digest(project: Path) -> str:
    """Hash every candidate source path and byte, never the generated Godot cache."""
    digest=hashlib.sha256()
    for path in sorted(p for p in project.rglob("*") if p.is_file()):
        relative=path.relative_to(project).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\\0")
        digest.update(path.read_bytes())
        digest.update(b"\\0")
    return digest.hexdigest()


def verify_candidate_qa(root=ROOT, godot_executable=None):
    """Run real Godot import and smoke test in a disposable copy before acceptance.

    No candidate source, Factory state, or GitHub branch is changed. The QA
    evidence is bound to the exact source bytes and generation cycle.
    """
    snap=validate(root)
    godot=godot_executable or shutil.which("godot") or shutil.which("godot4")
    if not godot:
        raise ValueError("Godot 4.3 executable not available for candidate QA")
    project=root/".candidate/project"
    before=candidate_digest(project)
    try:
        version=subprocess.run([str(godot),"--version"],capture_output=True,text=True,
                               timeout=20,check=False)
    except (OSError,subprocess.TimeoutExpired) as exc:
        raise ValueError("cannot run Godot version check") from exc
    if version.returncode or not version.stdout.strip().startswith("4.3"):
        raise ValueError("candidate QA requires Godot 4.3")
    with tempfile.TemporaryDirectory(prefix="godot-qa-") as temp:
        work=Path(temp)/"project"
        shutil.copytree(project,work)
        for args,label in (
            (["--headless","--editor","--path",str(work),"--import"],"import"),
            (["--headless","--path",str(work),"--script","res://tests/test_smoke.gd"],"smoke"),
        ):
            try:
                result=subprocess.run([str(godot),*args],capture_output=True,text=True,
                                      timeout=180,check=False)
            except (OSError,subprocess.TimeoutExpired) as exc:
                raise ValueError(f"Godot candidate {label} did not finish") from exc
            if result.returncode:
                raise ValueError(f"Godot candidate {label} failed (exit {result.returncode})")
    if candidate_digest(project)!=before:
        raise ValueError("candidate source changed during Godot QA")
    evidence={
        "schema_version":1,
        "cycle":snap["cycle"],
        "candidate_sha256":before,
        "godot_version":version.stdout.strip(),
        "import":"PASS",
        "smoke":"PASS",
        "verified_utc":datetime.now(timezone.utc).isoformat(),
    }
    target=root/".runtime/candidate-qa.json"
    with tempfile.NamedTemporaryFile(mode="w",encoding="utf-8",prefix=".qa-",
            suffix=".tmp",dir=target.parent,delete=False) as stream:
        temporary=Path(stream.name)
        json.dump(evidence,stream,indent=2)
        stream.write("\\n")
    temporary.replace(target)
    return evidence


def require_candidate_qa(root: Path, cycle: int) -> None:
    path=root/".runtime/candidate-qa.json"
    if not path.is_file():
        raise ValueError("Godot candidate QA evidence missing; run 'qa' first")
    try:
        evidence=read(path)
    except (OSError,ValueError,json.JSONDecodeError) as exc:
        raise ValueError("Godot candidate QA evidence unreadable") from exc
    if (evidence.get("schema_version")!=1
            or evidence.get("cycle")!=cycle
            or evidence.get("import")!="PASS"
            or evidence.get("smoke")!="PASS"
            or not str(evidence.get("godot_version","")).startswith("4.3")
            or evidence.get("candidate_sha256")!=candidate_digest(root/".candidate/project")):
        raise ValueError("Godot candidate QA evidence is stale or mismatched")


def accept(root=ROOT):
    # A directory lock prevents two accept processes from passing the same
    # five-day gate concurrently. Stale locks require explicit inspection.
    runtime=root/".runtime"
    lock=runtime/"accept.lock"
    try:
        lock.mkdir()
    except FileExistsError as exc:
        raise ValueError("3D acceptance already in progress; inspect stale lock") from exc
    try:
        snap=validate(root)
        require_candidate_qa(root,snap["cycle"])
        state_path=root/"factory/state.json"
        state=read(state_path)
        if not due(state, datetime.now(timezone.utc)):
            raise ValueError("not due for another 3D generation")
        slug="experimental-3d-"+str(state["cycle"])
        if not NAME.fullmatch(slug):raise ValueError("invalid game slug")
        dest=root/"products"/slug
        if dest.exists():raise ValueError("cannot overwrite existing game")
        dest.parent.mkdir(exist_ok=True)
        # Never publish a partially copied product if copying fails.
        with tempfile.TemporaryDirectory(prefix="accept-",dir=runtime) as stage:
            staged=Path(stage)/"project"
            shutil.copytree(root/".candidate/project",staged)
            if dest.exists():raise ValueError("cannot overwrite existing game")
            staged.rename(dest)
        # Replace the state file atomically; a failure after publication
        # leaves the product visible and forces HOLD on the next attempt,
        # rather than silently duplicating it or corrupting the state JSON.
        state["last_completed_utc"]=datetime.now(timezone.utc).isoformat()
        state["cycle"]+=1
        temp_state=None
        try:
            with tempfile.NamedTemporaryFile(mode="w",encoding="utf-8",
                    prefix=".state-",suffix=".tmp",dir=state_path.parent,
                    delete=False) as stream:
                temp_state=Path(stream.name)
                stream.write(json.dumps(state,indent=2)+"\n")
            temp_state.replace(state_path)
        finally:
            if temp_state is not None:
                temp_state.unlink(missing_ok=True)
        return slug
    finally:
        lock.rmdir()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("command",choices=("due","plan","validate","qa","accept"))
    opts=parser.parse_args()
    try:
        if opts.command=="due":
            result=due(read(ROOT/"factory/state.json"),datetime.now(timezone.utc))
            print("DUE" if result else "NOT_DUE")
            return 0 if result else 3
        if opts.command=="plan":print(prepare())
        if opts.command=="validate":print(validate())
        if opts.command=="qa":print(verify_candidate_qa())
        if opts.command=="accept":print(accept())
        return 0
    except (ValueError,OSError,KeyError,TypeError) as e:
        print("HOLD:",str(e),file=sys.stderr)
        return 2

if __name__=="__main__":
    sys.exit(main())
