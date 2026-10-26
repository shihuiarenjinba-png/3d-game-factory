"""Regression guard: 3D verification must test the triggering commit, not a stale branch."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "five-day-3d.yml"


class WorkflowCheckoutTests(unittest.TestCase):
    def test_dispatch_checkout_is_pinned_to_event_sha(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("ref: ${{ github.sha }}", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertNotIn("ref: codex/3d-factory-bootstrap-20261026", workflow)

    def test_dispatch_is_not_a_generation_cron(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotIn("schedule:", workflow)


if __name__ == "__main__":
    unittest.main()
