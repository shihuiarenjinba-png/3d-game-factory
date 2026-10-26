"""Bounded Godot 4 3D candidate generator and five-day gate.

Writes only drafts to a dedicated branch. No MSIX, Store uploads or sales claims.
"""
import argparse
from datetime import datetime, timezone, timedelta
import json
from pathlib import Path
import re
import shutil
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
    parser.add_argument("command",choices=("due","plan","validate","accept"))
    opts=parser.parse_args()
    try:
        if opts.command=="due":
            result=due(read(ROOT/"factory/state.json"),datetime.now(timezone.utc))
            print("DUE" if result else "NOT_DUE")
            return 0 if result else 3
        if opts.command=="plan":print(prepare())
        if opts.command=="validate":print(validate())
        if opts.command=="accept":print(accept())
        return 0
    except (ValueError,OSError,KeyError,TypeError) as e:
        print("HOLD:",str(e),file=sys.stderr)
        return 2

if __name__=="__main__":
    sys.exit(main())
