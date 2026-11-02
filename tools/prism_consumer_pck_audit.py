"""Fail-closed Godot 4.3 PCK resource audit for the *new* Prism consumer revision.

This script validates bytes from the current GitHub Actions export, never a
historical inventory or a synthetic fixture. CLEAN means payload hygiene only;
it never authorizes Identity CAS, MSIX signing, Store upload, or sale.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct

MAX_PCK = 512 * 1024 * 1024
MAX_ENTRIES = 20000
MAX_PATH = 4096


class PckAuditError(ValueError):
    pass


def require(ok: bool, why: str) -> None:
    if not ok:
        raise PckAuditError(why)


def u32(data: bytes, pos: int) -> int:
    require(0 <= pos <= len(data) - 4, "truncated PCK u32")
    return struct.unpack_from("<I", data, pos)[0]


def u64(data: bytes, pos: int) -> int:
    require(0 <= pos <= len(data) - 8, "truncated PCK u64")
    return struct.unpack_from("<Q", data, pos)[0]


def parse_pck(data: bytes) -> list[str]:
    require(100 <= len(data) <= MAX_PCK, "invalid PCK size")
    require(data[:4] == b"GDPC", "PCK magic mismatch")
    require(u32(data, 4) == 2 and (u32(data, 8), u32(data, 12)) == (4, 3),
            "PCK must be Godot 4.3 format v2")
    require(u32(data, 20) == 0, "unsupported PCK flags")
    base = u64(data, 24)
    require(100 <= base <= len(data), "PCK payload base out of bounds")
    count = u32(data, 96)
    require(0 < count <= MAX_ENTRIES, "PCK directory count invalid")
    pos, seen, intervals = 100, set(), []
    for _ in range(count):
        size = u32(data, pos)
        pos += 4
        require(0 < size <= MAX_PATH and pos + size + 36 <= base, "PCK path bounds invalid")
        try:
            name = data[pos:pos + size].rstrip(b"\0").decode("utf-8", "strict")
        except UnicodeError as exc:
            raise PckAuditError("PCK path encoding invalid") from exc
        pos += size
        require(name.startswith("res://") and "\\" not in name and
                not any(part in ("", ".", "..") for part in name[6:].split("/")) and
                name not in seen, "PCK path unsafe or duplicate")
        seen.add(name)
        offset, length = u64(data, pos), u64(data, pos + 8)
        md5 = data[pos + 16:pos + 32]
        flags = u32(data, pos + 32)
        pos += 36
        require(flags == 0, "unsupported resource flags")
        require(offset <= len(data) - base and length <= len(data) - base - offset,
                "PCK resource out of bounds")
        payload = data[base + offset:base + offset + length]
        require(hashlib.md5(payload).digest() == md5, "PCK resource MD5 mismatch")
        if length:
            intervals.append((offset, offset + length))
    require(pos <= base, "PCK directory overlaps payload")
    intervals.sort()
    require(all(intervals[i][1] <= intervals[i + 1][0]
                for i in range(len(intervals) - 1)), "PCK resources overlap")
    return sorted(seen)


def forbidden(name: str) -> bool:
    path = name.lower()
    return (path == "res://product-manifest.json" or
            path.startswith(("res://tests/", "res://test/", "res://store/",
                             "res://factory/", "res://handoffs/", "res://.github/")) or
            "approved-identity" in path or "product-manifest" in path)


def audit(exe: bytes, pck: bytes, evidence: dict, source: str, branch: str) -> dict:
    require(len(source) == 40 and all(c in "0123456789abcdef" for c in source),
            "source SHA invalid")
    require(branch == "codex/prism-bottom-hint-wrap-20261103",
            "unexpected consumer revision branch")
    request = "3d-prism-route-3d-" + source[:12]
    require(evidence.get("source_sha") == source and
            evidence.get("factory_build_head") == source and
            evidence.get("source_branch") == branch and
            evidence.get("request_id") == request and
            evidence.get("slug") == "prism-route-3d", "Factory lineage mismatch")
    require(len(exe) > 1024 and exe[:2] == b"MZ", "real Windows EXE missing")
    require(evidence.get("exe_sha256") == hashlib.sha256(exe).hexdigest() and
            evidence.get("exe_size_bytes") == len(exe), "EXE SHA/size mismatch")
    require(evidence.get("pck_sha256") == hashlib.sha256(pck).hexdigest() and
            evidence.get("pck_size_bytes") == len(pck), "PCK SHA/size mismatch")
    paths = parse_pck(pck)
    blocked = [p for p in paths if forbidden(p)]
    require(not blocked, "RELEASE_PCK_CONTENT_HOLD: " + ", ".join(blocked))
    require(any(p.startswith("res://scripts/main.") for p in paths),
            "main gameplay script missing from PCK")
    require(any(p.startswith("res://scripts/game_logic.") for p in paths),
            "game logic script missing from PCK")
    require(any("res://assets/fonts/NotoSansJP.ttf" in p for p in paths),
            "RELEASE_JP_FONT_MISSING: Japanese font absent from real PCK")
    require("res://assets/fonts/OFL.txt" in paths,
            "RELEASE_JP_FONT_LICENSE_MISSING: OFL notice absent from real PCK")
    return {
        "schema_version": 1,
        "receipt_type": "PRISM_CONSUMER_NEW_REVISION_REAL_EXPORT_PCK_AUDIT",
        "source_sha": source, "request_id": request, "source_branch": branch,
        "exe_sha256": evidence["exe_sha256"], "exe_size_bytes": len(exe),
        "pck_sha256": evidence["pck_sha256"], "pck_size_bytes": len(pck),
        "pck_resource_count": len(paths), "resource_paths": paths,
        "forbidden_resources": blocked, "all_resource_md5_match": True,
        "evidence_boundary": "CURRENT_RUN_GODOT_EXPORTED_BYTES_NOT_HUMAN_GUI",
        "status": "PCK_CONTENT_CLEAN_QA_ONLY",
        "official_identity_cas": "HOLD", "approved_version": "HOLD",
        "signed_product_msix": "HOLD", "windows_gui": "DEFERRED_LOCAL_GATE",
        "sale_ready": False, "store_submission_allowed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--pck", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        for path in (args.exe, args.pck, args.evidence):
            require(path.is_file() and not path.is_symlink(), "missing or symlinked export input")
        result = audit(args.exe.read_bytes(), args.pck.read_bytes(),
                       json.loads(args.evidence.read_text(encoding="utf-8")),
                       os.environ["SOURCE_SHA"], os.environ["SOURCE_BRANCH"])
        status = 0
    except (OSError, ValueError, TypeError, KeyError) as exc:
        result = {"status": "RELEASE_PCK_CONTENT_HOLD", "reason": str(exc)[:400],
                  "sale_ready": False, "store_submission_allowed": False}
        status = 2
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
