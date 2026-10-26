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
        self.assertEqual(action["stage_id"], "factory_product_materialization")
        self.assertEqual(action["repo"], "shihuiarenjinba-png/3d-game-factory")

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

    def test_done_stage_cannot_be_selected_as_next_action(self):
        changed = copy.deepcopy(self.data)
        changed["next_action"]["stage_id"] = "template_windows_export"
        changed["next_action"]["repo"] = "shihuiarenjinba-png/3d-game-template"
        with self.assertRaisesRegex(LedgerError, "not an actionable unfinished stage"):
            validate(changed)


if __name__ == "__main__":
    unittest.main()
