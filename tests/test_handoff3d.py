import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from handoff3d import BRANCH, build_handoff, build_provisioner_job, main


class HandoffTests(unittest.TestCase):
    def test_active_factory_branch_contract(self):
        self.assertEqual(BRANCH, "codex/3d-provisioner-job-contract-20261027")

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


    def test_rejects_oversized_committed_asset(self):
        path = self.root / "products" / self.slug / "README.md"
        path.write_text("x" * 180_001)
        self.run("add", "products")
        self.run("commit", "-m", "oversized source")
        with self.assertRaisesRegex(ValueError, "source quota"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_rejects_unapproved_committed_binary(self):
        path = self.root / "products" / self.slug / "bin" / "native.exe"
        path.parent.mkdir(parents=True)
        path.write_bytes(b"MZ")
        self.run("add", "products")
        self.run("commit", "-m", "unapproved binary")
        with self.assertRaisesRegex(ValueError, "disallowed committed product file"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_rejects_extra_committed_symlink(self):
        path = self.root / "products" / self.slug / "assets" / "link.md"
        path.parent.mkdir(parents=True)
        path.symlink_to("../README.md")
        self.run("add", "products")
        self.run("commit", "-m", "linked asset")
        with self.assertRaisesRegex(ValueError, "symlink"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_rejects_extra_committed_cfg(self):
        path = self.root / "products" / self.slug / "unsafe.cfg"
        path.write_text("unexpected=true")
        self.run("add", "products")
        self.run("commit", "-m", "extra config")
        with self.assertRaisesRegex(ValueError, "disallowed committed product file"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_rejects_hidden_committed_file(self):
        path = self.root / "products" / self.slug / ".hidden.json"
        path.write_text("{}")
        self.run("add", "products")
        self.run("commit", "-m", "hidden file")
        with self.assertRaisesRegex(ValueError, "unsafe committed product path"):
            build_handoff(self.root, self.slug, BRANCH)

    def test_provisioner_v1_job_contract(self):
        job = build_provisioner_job(self.root, self.slug, BRANCH, "Demo 3D Game")
        self.assertEqual(set(job), {
            "schema_version", "request_id", "product_type", "source_factory",
            "source_repository", "source_branch", "source_sha", "slug",
            "display_name", "target_owner", "dry_run", "requested_actions",
        })
        self.assertEqual(job["schema_version"], "1.0")
        self.assertEqual(job["product_type"], "GAME_3D")
        self.assertEqual(job["source_factory"], "3d-game-factory")
        self.assertEqual(job["source_repository"], "shihuiarenjinba-png/3d-game-factory")
        self.assertEqual(job["source_branch"], BRANCH)
        self.assertEqual(job["display_name"], "Demo 3D Game")
        self.assertTrue(job["dry_run"])
        self.assertEqual(job["requested_actions"], [
            "BUILD_WINDOWS", "INSPECT_PACKAGE",
            "LOOKUP_OFFICIAL_IDENTITY", "PROPOSE_GITHUB_RETURN",
        ])
        self.assertNotIn("store_id", job)
        self.assertEqual(job, build_provisioner_job(
            self.root, self.slug, BRANCH, "Demo 3D Game"))

    def test_provisioner_job_rejects_missing_or_unsafe_display_name(self):
        for value in (None, "", "x" * 101, "bad\nname", "bad\rname", "bad\x00name"):
            with self.subTest(value=repr(value)):
                with self.assertRaisesRegex(ValueError, "display name"):
                    build_provisioner_job(self.root, self.slug, BRANCH, value)

    def test_provisioner_cli_requires_explicit_live_sha(self):
        output = self.root / "provisioner-job.json"
        args = ["--root", str(self.root), "--slug", self.slug, "--output", str(output),
                "--format", "provisioner-job", "--display-name", "Demo 3D Game"]
        self.assertEqual(main(args + ["--live"]), 2)
        self.assertFalse(output.exists())
        self.assertEqual(main(args), 0)
        self.assertTrue(json.loads(output.read_text())["dry_run"])
        output.unlink()
        sha = build_handoff(self.root, self.slug, BRANCH)["source_sha"]
        self.assertEqual(main(args + ["--live", "--expected-sha", sha]), 0)
        self.assertFalse(json.loads(output.read_text())["dry_run"])

    def test_provisioner_job_rejects_uncommitted_product(self):
        (self.root / "products" / self.slug / "README.md").write_text("dirty")
        with self.assertRaisesRegex(ValueError, "uncommitted"):
            build_provisioner_job(self.root, self.slug, BRANCH, "Demo 3D Game")


if __name__ == "__main__":
    unittest.main()
