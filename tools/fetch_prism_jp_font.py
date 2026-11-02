"""Fetch the immutable OFL-licensed Noto Sans JP font for the Prism consumer build.

Build-time only. The Windows game never downloads fonts or requires networking.
Refuse modified font/license bytes and fail closed before Godot import/export.
"""
from __future__ import annotations
import hashlib
from pathlib import Path
import urllib.request

COMMIT = "295d98a7a0c17c68f1341eaeea354e7960ea70d3"
BASE = f"https://raw.githubusercontent.com/google/fonts/{COMMIT}/ofl/notosansjp/"
ROOT = Path(__file__).resolve().parents[1] / "products/prism-route-3d/assets/fonts"
ASSETS = (
    ("NotoSansJP.ttf", "NotoSansJP%5Bwght%5D.ttf", "cdd8f083c1f5928ff3361f8cda4d3fc9462cbe89"),
    ("OFL.txt", "OFL.txt", "1c9f43281b8f216c5461fe9ac729afbade7724e4"),
)

def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\\0" + data).hexdigest()

def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    for filename, upstream, expected in ASSETS:
        target = ROOT / filename
        if target.is_symlink():
            raise RuntimeError(f"Refuse symlink: {target}")
        if target.is_file() and blob_sha(target.read_bytes()) == expected:
            print(f"Verified existing {filename}: {expected}")
            continue
        with urllib.request.urlopen(BASE + upstream, timeout=60) as response:
            data = response.read(16_000_000)
        if blob_sha(data) != expected:
            raise RuntimeError(f"Upstream byte mismatch for {filename}; build HOLD")
        temp = target.with_suffix(target.suffix + ".tmp")
        temp.write_bytes(data)
        temp.replace(target)
        print(f"Verified immutable OFL asset {filename}: {expected} ({len(data)} bytes)")
    if (ROOT / "NotoSansJP.ttf").stat().st_size < 1_000_000:
        raise RuntimeError("Japanese font suspiciously small; build HOLD")

if __name__ == "__main__":
    main()
