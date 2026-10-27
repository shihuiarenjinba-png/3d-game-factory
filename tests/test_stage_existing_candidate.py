import json
import os
from datetime import datetime, timezone
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from factory3d import candidate_digest
from tools.stage_existing_candidate import audit_source_tree, stage_existing_candidate


def fixture(root: Path, source: Path):
    (root / "factory").mkdir()
    (root / "factory/state.json").write_text(
        '{"schema":1,"cycle":1,"last_completed_utc":null}', encoding="utf-8")
    files = {
        "project.godot": '[application]\nrun/main_scene="res://scenes/main.tscn"\n',
        "export_presets.cfg": '[preset.0]\nname="Windows Desktop"\nplatform="Windows Desktop"\n',
        "scenes/main.tscn": '[gd_scene format=3]\n[node name="Main" type="Node3D"]\n',
        "scripts/main.gd": 'extends Node3D\n',
        "tests/test_smoke.gd": 'func test_run():\n  pass\n',
        "README.md": 'Existing reviewed Godot project (QA fixture only)\n',
    }
    for name, data in files.items():
        target = source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(data, encoding="utf-8")


class StageExistingCandidateTests(unittest.TestCase):
    def test_stages_existing_source_without_acceptance_or_identity(self):
        with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
            root, source = Path(factory_dir), Path(src_dir)
            fixture(root, source)
            digest = candidate_digest(source)
            result = stage_existing_candidate(root, source, digest, source_reviewed=True)
            self.assertEqual(result["status"], "GODOT_QA_REQUIRED")
            self.assertFalse(result["accepted"])
            self.assertFalse(result["msix_created"])
            self.assertEqual(candidate_digest(root / ".candidate/project"), digest)
            self.assertEqual(json.loads((root / "factory/state.json").read_text())["cycle"], 1)
            self.assertFalse((root / "products").exists())
            self.assertFalse((root / ".runtime/candidate-qa.json").exists())
            with self.assertRaisesRegex(ValueError, "never overwrite"):
                stage_existing_candidate(root, source, digest, source_reviewed=True)

    def test_requires_explicit_review(self):
        with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
            root, source = Path(factory_dir), Path(src_dir)
            fixture(root, source)
            with self.assertRaisesRegex(ValueError, "source-reviewed"):
                stage_existing_candidate(root, source, candidate_digest(source))
            self.assertFalse((root / ".candidate").exists())

    def test_digest_mismatch_never_publishes_candidate(self):
        with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
            root, source = Path(factory_dir), Path(src_dir)
            fixture(root, source)
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                stage_existing_candidate(root, source, "0" * 64, source_reviewed=True)
            self.assertFalse((root / ".candidate/project").exists())

    def test_five_day_gate_cannot_be_bypassed(self):
        with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
            root, source = Path(factory_dir), Path(src_dir)
            fixture(root, source)
            state = json.loads((root / "factory/state.json").read_text())
            state["last_completed_utc"] = datetime.now(timezone.utc).isoformat()
            (root / "factory/state.json").write_text(json.dumps(state))
            with self.assertRaisesRegex(ValueError, "120-hour"):
                stage_existing_candidate(root, source, candidate_digest(source), source_reviewed=True)
            self.assertFalse((root / ".candidate").exists())

    def test_rejects_symlink_and_hidden_source(self):
        with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
            root, source = Path(factory_dir), Path(src_dir)
            fixture(root, source)
            (source / ".godot").mkdir()
            with self.assertRaisesRegex(ValueError, "hidden/cache"):
                stage_existing_candidate(root, source, candidate_digest(source), source_reviewed=True)
            (source / ".godot").rmdir()
            try:
                (source / "scripts/link.gd").symlink_to(source / "scripts/main.gd")
            except (OSError, NotImplementedError):
                self.skipTest("symlinks unavailable on this filesystem")
            with self.assertRaisesRegex(ValueError, "symlink"):
                stage_existing_candidate(root, source, candidate_digest(source), source_reviewed=True)
            self.assertFalse((root / ".candidate").exists())

    def test_reaudits_snapshot_when_files_appear_during_copy(self):
        with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
            root, source = Path(factory_dir), Path(src_dir)
            fixture(root, source)
            digest = candidate_digest(source)
            original_audit = audit_source_tree

            def audit_then_add_cache(path):
                original_audit(path)
                if Path(path) == source:
                    cache = source / ".godot"
                    cache.mkdir()
                    (cache / "late.json").write_text("unexpected", encoding="utf-8")

            with mock.patch("tools.stage_existing_candidate.audit_source_tree",
                            side_effect=audit_then_add_cache):
                with self.assertRaisesRegex(ValueError, "hidden/cache"):
                    stage_existing_candidate(root, source, digest, source_reviewed=True)
            self.assertFalse((root / ".candidate/project").exists())
            self.assertFalse((root / "products").exists())

    @unittest.skipIf(os.name == "nt", "symlink fixture requires Unix")
    def test_does_not_follow_symlink_added_after_preflight(self):
        with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
            root, source = Path(factory_dir), Path(src_dir)
            fixture(root, source)
            digest = candidate_digest(source)
            outside = root / "outside.gd"
            outside.write_text("external bytes", encoding="utf-8")
            link = source / "scripts/late.gd"
            try:
                link.symlink_to(outside)
                link.unlink()
            except (OSError, NotImplementedError):
                self.skipTest("symlinks unavailable")
            original_audit = audit_source_tree

            def audit_then_add_link(path):
                original_audit(path)
                if Path(path) == source:
                    link.symlink_to(outside)

            with mock.patch("tools.stage_existing_candidate.audit_source_tree",
                            side_effect=audit_then_add_link):
                with self.assertRaisesRegex(ValueError, "symlink"):
                    stage_existing_candidate(root, source, digest, source_reviewed=True)
            self.assertFalse((root / ".candidate/project").exists())

    @unittest.skipIf(os.name == "nt", "requires a case-sensitive fixture filesystem")
    def test_rejects_casefold_collision_before_staging(self):
        with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
            root, source = Path(factory_dir), Path(src_dir)
            fixture(root, source)
            (source / "README.MD").write_text("duplicate case-insensitive path", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Windows path collision"):
                stage_existing_candidate(root, source, candidate_digest(source), source_reviewed=True)
            self.assertFalse((root / ".candidate").exists())

    @unittest.skipIf(os.name == "nt", "requires names forbidden on Windows")
    def test_rejects_reserved_and_unsafe_windows_paths(self):
        for invalid in ("scripts/CON.gd", "scripts/bad:name.gd", "scenes/trailing./main.tscn"):
            with self.subTest(invalid=invalid):
                with tempfile.TemporaryDirectory() as factory_dir, tempfile.TemporaryDirectory() as src_dir:
                    root, source = Path(factory_dir), Path(src_dir)
                    fixture(root, source)
                    target = source / invalid
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text("invalid path", encoding="utf-8")
                    with self.assertRaisesRegex(ValueError, "Windows"):
                        stage_existing_candidate(root, source, candidate_digest(source), source_reviewed=True)
                    self.assertFalse((root / ".candidate").exists())


if __name__ == "__main__":
    unittest.main()
