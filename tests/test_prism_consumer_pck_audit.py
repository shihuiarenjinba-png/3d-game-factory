"""Synthetic negative tests only; never claim a fixture is the real Godot export."""
import hashlib
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.prism_consumer_pck_audit import PckAuditError, audit, parse_pck

SHA = "a" * 40
BRANCH = "codex/prism-hud-contrast-20261102"
EXE = b"MZ" + b"x" * 2048


def pack(resources):
    directory = bytearray()
    payload = bytearray()
    for name, content in resources:
        raw = name.encode() + b"\0"
        raw += b"\0" * (-len(raw) % 4)
        directory += struct.pack("<I", len(raw)) + raw
        directory += struct.pack("<QQ", len(payload), len(content))
        directory += hashlib.md5(content).digest() + struct.pack("<I", 0)
        payload += content
    base = 100 + len(directory)
    header = bytearray(100)
    header[:4] = b"GDPC"
    struct.pack_into("<III", header, 4, 2, 4, 3)
    struct.pack_into("<Q", header, 24, base)
    struct.pack_into("<I", header, 96, len(resources))
    return bytes(header + directory + payload)


def evidence(pck):
    return dict(source_sha=SHA, factory_build_head=SHA,
                source_branch=BRANCH, request_id="3d-prism-route-3d-" + SHA[:12],
                slug="prism-route-3d",
                exe_sha256=hashlib.sha256(EXE).hexdigest(),
                exe_size_bytes=len(EXE),
                pck_sha256=hashlib.sha256(pck).hexdigest(),
                pck_size_bytes=len(pck))


CLEAN = [("res://scripts/main.gdc", b"main"),
         ("res://scripts/game_logic.gdc", b"logic"),
         ("res://scenes/main.tscn", b"scene"),
         ("res://assets/fonts/NotoSansJP.ttf.remap", b"font"),
         ("res://assets/fonts/OFL.txt", b"license")]


class PckGateTests(unittest.TestCase):
    def test_clean_fixture_is_only_qa_not_store_ready(self):
        pck = pack(CLEAN)
        result = audit(EXE, pck, evidence(pck), SHA, BRANCH)
        self.assertEqual(result["status"], "PCK_CONTENT_CLEAN_QA_ONLY")
        self.assertFalse(result["sale_ready"])
        self.assertEqual(result["official_identity_cas"], "HOLD")

    def test_previous_revision_branch_is_not_this_product(self):
        pck = pack(CLEAN)
        with self.assertRaisesRegex(PckAuditError, "unexpected consumer revision branch"):
            audit(EXE, pck, evidence(pck), SHA, "codex/prism-consumer-jp-font-20261102")

    def test_font_and_license_missing_must_hold(self):
        for missing in ("res://assets/fonts/NotoSansJP.ttf.remap",
                        "res://assets/fonts/OFL.txt"):
            with self.subTest(missing=missing):
                pck = pack([(name, payload) for name, payload in CLEAN if name != missing])
                with self.assertRaisesRegex(PckAuditError, "RELEASE_JP_FONT"):
                    audit(EXE, pck, evidence(pck), SHA, BRANCH)

    def test_forbidden_internal_payloads(self):
        for name in ("res://store/approved-identity.json",
                     "res://product-manifest.json",
                     "res://tests/test_smoke.gdc",
                     "res://tests/test_smoke.gd.remap",
                     "res://factory/internal.json"):
            with self.subTest(name=name):
                pck = pack(CLEAN + [(name, b"secret")])
                with self.assertRaisesRegex(PckAuditError, "RELEASE_PCK_CONTENT_HOLD"):
                    audit(EXE, pck, evidence(pck), SHA, BRANCH)

    def test_wrong_pck_even_with_correct_source(self):
        pck = pack(CLEAN)
        wrong = pack(CLEAN + [("res://textures/new.png", b"extra")])
        with self.assertRaisesRegex(PckAuditError, "PCK SHA/size mismatch"):
            audit(EXE, wrong, evidence(pck), SHA, BRANCH)

    def test_wrong_lineage_and_unsigned_fixture_promotion(self):
        pck = pack(CLEAN)
        e = evidence(pck)
        e["request_id"] = "3d-prism-route-3d-OLD"
        with self.assertRaisesRegex(PckAuditError, "Factory lineage mismatch"):
            audit(EXE, pck, e, SHA, BRANCH)
        with self.assertRaisesRegex(PckAuditError, "Windows EXE"):
            audit(b"unsigned fixture", pck, evidence(pck), SHA, BRANCH)

    def test_corruption_and_duplicate_paths(self):
        pck = pack(CLEAN)
        damaged = bytearray(pck)
        damaged[-1] ^= 1
        with self.assertRaisesRegex(PckAuditError, "MD5 mismatch"):
            parse_pck(bytes(damaged))
        with self.assertRaisesRegex(PckAuditError, "duplicate"):
            parse_pck(pack(CLEAN + [CLEAN[0]]))


if __name__ == "__main__":
    unittest.main()
