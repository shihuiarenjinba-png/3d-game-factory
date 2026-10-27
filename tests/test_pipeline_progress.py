import copy
from pathlib import Path
import unittest

from tools.pipeline_progress import (
    LedgerError,
    load,
    next_action,
    render_report,
    validate,
)

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "factory" / "pipeline-progress.json"
REPORT = ROOT / "docs" / "PIPELINE_PROGRESS.md"


class PipelineProgressTests(unittest.TestCase):
    def setUp(self):
        self.data = load(LEDGER)

    def test_current_ledger_is_safe_and_actionable(self):
        validate(self.data)
        action = next_action(self.data)
        stage = self.data["stages"][action["stage_id"]]
        self.assertTrue(stage["auto_actionable"])
        self.assertNotIn(stage["state"], ("DONE", "OUT_OF_SCOPE"))
        self.assertEqual(action["repo"], stage["owner_repo"])

    def test_generated_report_is_current(self):
        self.assertEqual(REPORT.read_text(encoding="utf-8"), render_report(self.data))

    def test_store_submission_cannot_be_enabled_in_factory_ledger(self):
        changed = copy.deepcopy(self.data)
        changed["policy"]["store_submission_allowed"] = True
        with self.assertRaisesRegex(LedgerError, "store_submission_allowed"):
            validate(changed)

    def test_new_product_gate_cannot_be_shortened(self):
        changed = copy.deepcopy(self.data)
        changed["policy"]["new_product_min_interval_hours"] = 30
        with self.assertRaisesRegex(LedgerError, "new_product_min_interval_hours"):
            validate(changed)

    def test_new_generation_requires_explicit_boolean(self):
        changed = copy.deepcopy(self.data)
        del changed["generation_gate"]["new_product_allowed"]
        with self.assertRaisesRegex(LedgerError, "new_product_allowed"):
            validate(changed)
        changed["generation_gate"]["new_product_allowed"] = True
        with self.assertRaisesRegex(LedgerError, "generation state"):
            validate(changed)

    def test_active_product_cannot_coexist_with_new_generation(self):
        changed = copy.deepcopy(self.data)
        changed["generation_gate"]["state"] = "READY"
        changed["generation_gate"]["new_product_allowed"] = True
        changed["active_product"] = {"slug": "unfinished-3d"}
        with self.assertRaisesRegex(LedgerError, "active_product"):
            validate(changed)

    def test_next_action_head_is_pinned(self):
        changed = copy.deepcopy(self.data)
        changed["next_action"]["expected_head_sha"] = "not-a-sha"
        with self.assertRaisesRegex(LedgerError, "expected_head_sha"):
            validate(changed)

    def test_done_stage_cannot_be_selected_as_next_action(self):
        changed = copy.deepcopy(self.data)
        changed["next_action"]["stage_id"] = "template_windows_export"
        changed["next_action"]["repo"] = "shihuiarenjinba-png/3d-game-template"
        with self.assertRaisesRegex(LedgerError, "not an actionable unfinished stage"):
            validate(changed)


if __name__ == "__main__":
    unittest.main()
