import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from handoff3d import BRANCH, build_handoff, main


class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        def run(*args):
            subprocess.run(["git", "-C", str(self.root), *args], check=True,
                           capture_output=True, text=True)
        self.run = run
        run("init", "-b", BRANCH)
        run("config", "user.email", "test@example.invalid")
        run("config", "user.name", "Handoff Test")
        self.slug = "experimental-3d-1"
        p = self.root / "products" / self.slug
        for rel, data in {
            "project.godot": '[application]\nrun/main_scene="res://scenes/main.tscn"\n',
            "export_presets.cfg": '[preset.0]\nname="Windows Desktop"\nplatform="Windows Desktop"\n',
            "scenes/main.tscn": "[gd_scene format=3]\n",
            "scripts/main.gd": "extends Node3D\n",
            "tests/test_smoke.gd": "func test_run(): pass\n",
            "README.md": "Example 3D source\n",
        }.items():
            path = p / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)
        run("add", "products")
        run("commit", "-m", "fixture")

    def test_valid_source_only_handoff(self):
        result = build_handoff(self.root, self.slug, BRANCH)
        self.assertEqual(result["kind"], "3d-game")
        self.assertEqual(result["status"], "GODOT_QA_REQUIRED")
        self.assertFalse(result["remote_head_verified"])
        self.assertIsNone(result["store_id"])
        self.assertFalse(result["msix_created"])
        self.assertEqual(len(result["source_sha"]), 40)
        self.assertEqual(result, build_handoff(self.root, self.slug, BRANCH))

    def test_dirty_product_rejected(self):
        (self.root / "products" / self.slug / "README.md").write_text("changed")
        with self.assertRaisesRegex(ValueError, "uncommitted"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_missing_committed_project_rejected(self):
        with self.assertRaisesRegex(ValueError, "missing, symlinked"):
            build_handoff(self.root, "missing-game", BRANCH)

    def test_missing_windows_export_preset_rejected(self):
        preset = self.root / "products" / self.slug / "export_presets.cfg"
        preset.unlink()
        self.run("add", "-u", "products")
        self.run("commit", "-m", "remove export preset")
        with self.assertRaisesRegex(ValueError, "missing, symlinked"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_non_windows_export_preset_rejected(self):
        preset = self.root / "products" / self.slug / "export_presets.cfg"
        preset.write_text('[preset.0]\nname="Linux"\nplatform="Linux"\n')
        self.run("add", "products")
        self.run("commit", "-m", "wrong export preset")
        with self.assertRaisesRegex(ValueError, "Windows Desktop export preset"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_branch_and_sha_rejected(self):
        with self.assertRaisesRegex(ValueError, "branch mismatch"):
            build_handoff(self.root, self.slug, "main")
        with self.assertRaisesRegex(ValueError, "SHA"):
            build_handoff(self.root, self.slug, BRANCH, "a" * 40)

    def test_committed_symlink_rejected(self):
        path = self.root / "products" / self.slug / "README.md"
        path.unlink()
        path.symlink_to("project.godot")
        self.run("add", "products")
        self.run("commit", "-m", "symlink")
        with self.assertRaisesRegex(ValueError, "symlinked"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_slug_traversal_rejected(self):
        with self.assertRaisesRegex(ValueError, "slug"):
            build_handoff(self.root, "../escape", BRANCH)

    def test_cli_does_not_overwrite(self):
        output = self.root / "handoff.json"
        self.assertEqual(main(["--root", str(self.root), "--slug", self.slug,
                               "--output", str(output)]), 0)
        data = json.loads(output.read_text())
        self.assertEqual(data["source_factory"], "shihuiarenjinba-png/3d-game-factory")
        self.assertEqual(main(["--root", str(self.root), "--slug", self.slug,
                               "--output", str(output)]), 2)


if __name__ == "__main__":
    unittest.main()
