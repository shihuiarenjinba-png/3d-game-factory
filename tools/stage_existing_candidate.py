"""Stage an existing, explicitly reviewed Godot 4.3 project for real QA.

This does not generate a game, accept a product, modify the 120-hour gate,
create a Store Identity, or assert that a game is commercially playable.
The caller supplies the exact source digest and explicit review acknowledgement.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile

from factory3d import ROOT, EXTENSIONS, candidate_digest, due, prepare, read, validate, require_generation_gate

SHA256 = re.compile(r"^[0-9a-f]{64}$")
MAX_FILES = 35
MAX_BYTES = 180000
WINDOWS_RESERVED = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}
WINDOWS_FORBIDDEN = set('<>:"|?*') | {chr(92)}


def require_windows_safe_path(relative: Path, seen: set[str]) -> None:
    """Reject paths that cannot survive a case-insensitive Windows export.

    Check directories as well as files: Linux checkouts may contain both
    scenes/Level and scenes/level, which alias on typical NTFS.
    """
    name = relative.as_posix()
    if len(name) > 240:
        raise ValueError("candidate path exceeds Windows-safe length")
    key = name.casefold()
    if key in seen:
        raise ValueError("Windows path collision in candidate source")
    seen.add(key)
    for part in relative.parts:
        if (not part or len(part) > 240 or part.endswith((" ", "."))
                or any(char in WINDOWS_FORBIDDEN or ord(char) < 32 for char in part)):
            raise ValueError("Windows-unsafe candidate path component")
        if part.split(".", 1)[0].upper() in WINDOWS_RESERVED:
            raise ValueError("Windows reserved device name in candidate source")




def audit_source_tree(source: Path) -> None:
    """Audit source and the copied snapshot before publishing any candidate."""
    count = 0
    total = 0
    seen_windows_paths: set[str] = set()
    for path in source.rglob("*"):
        if path.is_symlink():
            raise ValueError("source contains a symlink")
        if not path.is_dir() and not path.is_file():
            raise ValueError("source contains unsupported filesystem entry")
        relative = path.relative_to(source)
        require_windows_safe_path(relative, seen_windows_paths)
        if any(part.startswith(".") for part in relative.parts):
            raise ValueError("hidden/cache paths are not allowed in source")
        if path.is_file():
            if path.suffix.lower() not in EXTENSIONS:
                raise ValueError("unsupported source file extension")
            if path.suffix.lower() == ".cfg" and relative.as_posix() != "export_presets.cfg":
                raise ValueError("only export_presets.cfg is permitted")
            count += 1
            total += path.stat().st_size
            if count > MAX_FILES or total > MAX_BYTES:
                raise ValueError("source exceeds candidate quotas")
    if count == 0:
        raise ValueError("source contains no project files")



def stage_existing_candidate(
    root: Path,
    source: Path,
    expected_sha256: str,
    *,
    source_reviewed: bool = False,
) -> dict:
    """Atomically stage one external, reviewed source tree; fail closed.

    A new source can only be imported when the Factory's 120-hour acceptance
    gate permits work. Existing .candidate/project is never overwritten.
    """
    if source_reviewed is not True:
        raise ValueError("explicit --source-reviewed acknowledgement required")
    if not isinstance(expected_sha256, str) or not SHA256.fullmatch(expected_sha256):
        raise ValueError("expected source SHA-256 must be 64 lowercase hex characters")

    root = root.resolve(strict=True)
    source = Path(source).expanduser()
    if source.is_symlink() or not source.is_dir():
        raise ValueError("source must be a real existing directory, not a symlink")
    source = source.resolve(strict=True)
    if source == root or root in source.parents:
        raise ValueError("source must be external to Factory checkout")

    require_generation_gate(root)
    state = read(root / "factory/state.json")
    if not due(state, datetime.now(timezone.utc)):
        raise ValueError("120-hour acceptance gate is not due")

    audit_source_tree(source)

    candidate_root = root / ".candidate"
    dest = candidate_root / "project"
    if candidate_root.is_symlink() or dest.exists() or dest.is_symlink():
        raise ValueError("candidate already exists; never overwrite")

    runtime = root / ".runtime"
    snapshot_path = runtime / "snapshot.json"
    if snapshot_path.exists():
        snap = read(snapshot_path)
        if snap.get("cycle") != state["cycle"] or snap.get("kind") != "3d-game":
            raise ValueError("existing generation snapshot is stale")
    else:
        prepare(root)
    candidate_root.mkdir(exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="existing-3d-", dir=runtime) as temp:
        staged = Path(temp) / "project"
        # Preserve late-appearing links rather than following them outside source.
        # The second audit catches mutations between preflight and copy.
        shutil.copytree(source, staged, symlinks=True)
        audit_source_tree(staged)
        digest = candidate_digest(staged)
        if digest != expected_sha256:
            raise ValueError("source SHA-256 mismatch; no candidate imported")
        if dest.exists() or dest.is_symlink():
            raise ValueError("candidate appeared concurrently; refuse overwrite")
        staged.rename(dest)
        try:
            validate(root)
            if candidate_digest(dest) != expected_sha256:
                raise ValueError("source changed while staging")
        except Exception:
            shutil.rmtree(dest)
            raise

    # A prior cycle's evidence must never be reused for a new source.
    (runtime / "candidate-qa.json").unlink(missing_ok=True)
    return {
        "schema_version": 1,
        "status": "GODOT_QA_REQUIRED",
        "cycle": state["cycle"],
        "candidate_sha256":expected_sha256,
        "next_command": "python factory3d.py qa",
        "accepted": False,
        "msix_created": False,
        "store_identity_status": "UNKNOWN",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True,
                        help="External existing reviewed Godot project directory")
    parser.add_argument("--expected-sha256", required=True,
                        help="Digest of project relative paths and bytes from factory3d.candidate_digest")
    parser.add_argument("--source-reviewed", action="store_true",
                        help="Operator explicitly reviewed ownership, licenses and gameplay")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    try:
        result = stage_existing_candidate(
            args.root, args.source, args.expected_sha256,
            source_reviewed=args.source_reviewed,
        )
        print(json.dumps(result, indent=2))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"STAGE_HOLD: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
