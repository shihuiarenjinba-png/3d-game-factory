import json
from datetime import datetime,timezone,timedelta
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from factory3d import due,prepare,validate,accept

class FiveDayTests(unittest.TestCase):
    def test_first_run_due(self):
        self.assertTrue(due({"schema":1,"cycle":1,"last_completed_utc":None},datetime(2026,10,26,tzinfo=timezone.utc)))
    def test_not_before_five_days(self):
        now=datetime(2026,10,26,tzinfo=timezone.utc)
        state={"schema":1,"cycle":2,"last_completed_utc":(now-timedelta(days=4,hours=23)).isoformat()}
        self.assertFalse(due(state,now))
    def test_exact_five_days_due(self):
        now=datetime(2026,10,26,tzinfo=timezone.utc)
        state={"schema":1,"cycle":2,"last_completed_utc":(now-timedelta(days=5)).isoformat()}
        self.assertTrue(due(state,now))
    def test_future_timestamp_rejected(self):
        with self.assertRaises(ValueError):
            due({"schema":1,"cycle":1,"last_completed_utc":"2090-01-01T00:00:00Z"},datetime(2026,10,26,tzinfo=timezone.utc))
    def test_invalid_state_rejected(self):
        with self.assertRaises(ValueError):
            due({"schema":2,"cycle":1,"last_completed_utc":None},datetime.now(timezone.utc))
    def test_candidate_requires_actual_3d_game(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            (root/"factory").mkdir()
            (root/"factory/state.json").write_text('{"schema":1,"cycle":1,"last_completed_utc":null}')
            prepare(root)
            with self.assertRaisesRegex(ValueError,"Godot project absent"):
                validate(root)
    def test_headless_project_and_unique_checkpoint(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            (root/"factory").mkdir()
            (root/"factory/state.json").write_text('{"schema":1,"cycle":1,"last_completed_utc":null}')
            prepare(root)
            proj=root/".candidate/project"
            for name,text in {
               "project.godot":'[application]\nrun/main_scene="res://scenes/main.tscn"\n',
               "scenes/main.tscn":'[gd_scene format=3]\n[node name="Main" type="Node3D"]\n',
               "scripts/main.gd":"extends Node3D\n",
               "tests/test_smoke.gd":"func test_run():\n  pass\n",
               "README.md":"Basic simulated 3D game"
            }.items():
                p=proj/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
            # A concurrent or resumed run can complete the previous cycle after
            # prepare() but before accept(); acceptance must recheck the gate.
            state_path=root/"factory/state.json"
            state=json.loads(state_path.read_text())
            state["last_completed_utc"]=(datetime.now(timezone.utc)-timedelta(hours=1)).isoformat()
            state_path.write_text(json.dumps(state))
            with self.assertRaisesRegex(ValueError,"not due"):
                accept(root)
            self.assertFalse((root/"products"/"experimental-3d-1").exists())
            state["last_completed_utc"]=None
            state_path.write_text(json.dumps(state))
            validate(root)
            slug=accept(root)
            self.assertTrue((root/"products"/slug/"project.godot").exists())
            self.assertEqual(json.loads((root/"factory/state.json").read_text())["cycle"],2)
            with self.assertRaises(ValueError):accept(root)

    def test_concurrent_accept_lock_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            (root/"factory").mkdir()
            (root/"factory/state.json").write_text(
                '{"schema":1,"cycle":1,"last_completed_utc":null}')
            prepare(root)
            lock=root/".runtime/accept.lock"
            lock.mkdir()
            with self.assertRaisesRegex(ValueError,"already in progress"):
                accept(root)
            self.assertTrue(lock.is_dir())
            self.assertFalse((root/"products").exists())
            self.assertEqual(json.loads((root/"factory/state.json").read_text())["cycle"],1)

    def test_partial_copy_never_publishes_product(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            (root/"factory").mkdir()
            (root/"factory/state.json").write_text(
                '{"schema":1,"cycle":1,"last_completed_utc":null}')
            prepare(root)
            project=root/".candidate/project"
            for name,text in {
                "project.godot":'[application]\nrun/main_scene="res://scenes/main.tscn"\n',
                "scenes/main.tscn":'[gd_scene format=3]\n[node name="Main" type="Node3D"]\n',
                "scripts/main.gd":"extends Node3D\n",
                "tests/test_smoke.gd":"func test_run():\n  pass\n",
                "README.md":"3D QA candidate"
            }.items():
                path=project/name
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_text(text)
            def broken_copy(src,dst):
                dst.mkdir(parents=True)
                (dst/"partial.txt").write_text("incomplete")
                raise OSError("simulated copy failure")
            with patch("factory3d.shutil.copytree",side_effect=broken_copy):
                with self.assertRaisesRegex(OSError,"simulated copy failure"):
                    accept(root)
            self.assertFalse((root/"products/experimental-3d-1").exists())
            self.assertFalse((root/".runtime/accept.lock").exists())
            self.assertEqual(json.loads((root/"factory/state.json").read_text())["cycle"],1)

if __name__=="__main__":unittest.main()
