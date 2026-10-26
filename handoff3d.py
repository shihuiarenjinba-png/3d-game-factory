"""Create a pinned, source-only 3D handoff for the local Windows Provisioner.

This is NOT proof of remote GitHub HEAD, Store registration, Windows QA or MSIX.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

FACTORY = "shihuiarenjinba-png/3d-game-factory"
BRANCH = "codex/3d-factory-bootstrap-20261026"
SLUG = re.compile(r"^[a-z][a-z0-9-]{3,39}$")
SHA = re.compile(r"^[a-f0-9]{40}$")
REQUIRED = ("project.godot", "export_presets.cfg", "scenes/main.tscn",
            "scripts/main.gd", "tests/test_smoke.gd", "README.md")


def git(root: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                            text=True, encoding="utf-8", timeout=20, check=False)
    if result.returncode:
        raise ValueError("Git verification failed; no handoff produced")
    return result.stdout.strip()


def build_handoff(root: Path, slug: str, branch: str, expected_sha: str | None = None) -> dict:
    if not isinstance(slug, str) or not SLUG.fullmatch(slug):
        raise ValueError("invalid product slug")
    if branch != BRANCH:
        raise ValueError("3D Factory work branch mismatch")
    sha = git(root, "rev-parse", "HEAD")
    if not SHA.fullmatch(sha) or (expected_sha is not None and sha != expected_sha):
        raise ValueError("source SHA does not match checked-out commit")
    actual_branch = git(root, "symbolic-ref", "--quiet", "--short", "HEAD")
    if actual_branch != branch:
        raise ValueError("source checkout is not the approved work branch")
    product = f"products/{slug}"
    if git(root, "status", "--porcelain", "--", product):
        raise ValueError("uncommitted product changes; refuse handoff")
    for rel in REQUIRED:
        # Inspect the exact committed Git tree: symlinks are not valid products.
        entry = git(root, "ls-tree", sha, "--", f"{product}/{rel}")
        if not entry.startswith("100644 blob ") and not entry.startswith("100755 blob "):
            raise ValueError("missing, symlinked or invalid committed product file")
        git(root, "cat-file", "-e", f"{sha}:{product}/{rel}")
    project_text = git(root, "show", f"{sha}:{product}/project.godot")
    if "run/main_scene" not in project_text:
        raise ValueError("committed Godot project has no main scene")
    preset_text = git(root, "show", f"{sha}:{product}/export_presets.cfg")
    if ('platform="Windows Desktop"' not in preset_text
            or 'name="Windows Desktop"' not in preset_text):
        raise ValueError("committed Godot project has no Windows Desktop export preset")
    return {
        "schema_version": 1,
        "request_id": f"3d-{slug}-{sha[:12]}",
        "kind": "3d-game",
        "product_type": "GAME_3D",
        "slug": slug,
        "status": "GODOT_QA_REQUIRED",
        "source_factory": FACTORY,
        "source_repository": FACTORY,
        "source_branch": branch,
        "source_sha": sha,
        "product_path": product,
        "store_identity_status": "UNKNOWN",
        "store_id": None,
        "msix_created": False,
        "remote_head_verified": False,
        "next_stage": "LOCAL_PROVISIONER_3D_VERIFY_REMOTE_HEAD",
    }



def build_provisioner_job(root: Path, slug: str, branch: str,
                          display_name: str, expected_sha: str | None = None,
                          *, dry_run: bool = True) -> dict:
    """Convert a verified 3D source handoff into the local Provisioner v1.0 job.

    The original source-only handoff remains available for existing consumers.
    This is an instruction to the local Provisioner, not proof of Store ID,
    Windows build, GitHub remote HEAD or Microsoft Store readiness.
    """
    if (not isinstance(display_name, str) or not display_name
            or len(display_name) > 100
            or any(char in display_name for char in "\\r\\n\\x00")):
        raise ValueError("invalid product display name")
    if type(dry_run) is not bool:
        raise ValueError("dry_run must be a boolean")
    source = build_handoff(root, slug, branch, expected_sha)
    return {
        "schema_version": "1.0",
        "request_id": source["request_id"],
        "product_type": "GAME_3D",
        "source_factory": "3d-game-factory",
        "source_repository": FACTORY,
        "source_branch": branch,
        "source_sha": source["source_sha"],
        "slug": slug,
        "display_name": display_name,
        "target_owner": "shihuiarenjinba-png",
        "dry_run": dry_run,
        "requested_actions": [
            "BUILD_WINDOWS",
            "INSPECT_PACKAGE",
            "LOOKUP_OFFICIAL_IDENTITY",
            "PROPOSE_GITHUB_RETURN",
        ],
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--slug", required=True)
    parser.add_argument("--branch", default=BRANCH)
    parser.add_argument("--expected-sha")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--format", choices=("source-handoff", "provisioner-job"),
                        default="source-handoff")
    parser.add_argument("--display-name",
                        help="Required for provisioner-job; never guessed from slug")
    parser.add_argument("--live", action="store_true",
                        help="Explicitly request a non-dry-run Provisioner job")
    args = parser.parse_args(argv)
    try:
        if args.format == "provisioner-job":
            if args.live and not args.expected_sha:
                raise ValueError("live Provisioner job requires --expected-sha")
            result = build_provisioner_job(
                args.root, args.slug, args.branch, args.display_name,
                args.expected_sha, dry_run=not args.live)
        else:
            if args.live or args.display_name is not None:
                raise ValueError("--live/--display-name require --format provisioner-job")
            result = build_handoff(args.root, args.slug, args.branch, args.expected_sha)
        if args.output.exists():
            raise ValueError("handoff destination exists; refuse overwrite")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8") as stream:
            json.dump(result, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        print("PROVISIONER_JOB_CREATED" if args.format == "provisioner-job" else "SOURCE_HANDOFF_CREATED",
              "; remote HEAD and Store identity remain HOLD")
        return 0
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print("HANDOFF_HOLD:", str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
