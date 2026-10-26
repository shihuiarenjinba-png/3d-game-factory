import unittest
from datetime import datetime, timedelta
from controller import advance, initialize


class ProjectTest(unittest.TestCase):
    def setUp(self):
        self.start = "2026-10-26T09:00:00+09:00"
        self.state = initialize("project-1", self.start)

    def test_five_day_deadline(self):
        self.assertEqual(self.state["deadline_at"], "2026-10-31T09:00:00+09:00")
        self.assertFalse(self.state["submission_authorized"])

    def test_happy_path_waits_for_human(self):
        s = self.state
        events = [
            ("PROVISIONED", "repository_full_name", "org/demo-repo", "2026-10-26T10:00:00+09:00"),
            ("BUILD_PASSED", "build_run_id", "run-123", "2026-10-27T10:00:00+09:00"),
            ("AUTO_QA_PASSED", "qa_run_id", "qa-123", "2026-10-30T10:00:00+09:00"),
        ]
        for index, (type_, key, value, now) in enumerate(events):
            s = advance(s, {"event_id": f"evt-{index}", "type": type_, key: value}, now)
        self.assertEqual(s["phase"], "WAIT_HUMAN_QA")
        self.assertFalse(s["submission_authorized"])
        s = advance(s, {"event_id": "weekend", "type": "HUMAN_APPROVED",
                        "approval_reference": "approval-001"}, "2026-11-01T10:00:00+09:00")
        self.assertEqual(s["phase"], "HANDOFF_REVIEW")
        self.assertFalse(s["submission_authorized"])

    def test_no_fake_progression(self):
        with self.assertRaises(ValueError):
            advance(self.state, {"event_id": "x", "type": "AUTO_QA_PASSED",
                                 "qa_run_id": "fake"}, self.start)

    def test_deadline_holds(self):
        s = advance(self.state, {"event_id": "late", "type": "PROVISIONED",
                                 "repository_full_name": "org/repo"},
                    "2026-11-02T00:00:00+09:00")
        self.assertEqual(s["phase"], "HOLD")

    def test_duplicate_event_is_idempotent(self):
        ev = {"event_id": "e1", "type": "PROVISIONED", "repository_full_name": "org/repo"}
        s = advance(self.state, ev, "2026-10-26T10:00:00+09:00")
        self.assertEqual(s, advance(s, ev, "2026-10-26T11:00:00+09:00"))

    def test_duplicate_event_conflict_blocks(self):
        ev = {"event_id": "e1", "type": "PROVISIONED", "repository_full_name": "org/repo"}
        s = advance(self.state, ev, "2026-10-26T10:00:00+09:00")
        with self.assertRaises(ValueError):
            advance(s, {**ev, "repository_full_name": "other/repo"}, "2026-10-26T10:05:00+09:00")

    def test_480_quarter_hour_ticks_and_expiry(self):
        s = self.state
        start = datetime.fromisoformat(self.start)
        for index in range(1, 481):
            ts = (start + timedelta(minutes=15 * index)).isoformat()
            s = advance(s, {"event_id": f"tick-{index}", "type": "TICK"}, ts)
        self.assertEqual(s["phase"], "PROVISIONING")
        self.assertEqual(len(s["seen_events"]), 480)
        overdue = (start + timedelta(minutes=15 * 481)).isoformat()
        s = advance(s, {"event_id": "tick-481", "type": "TICK"}, overdue)
        self.assertEqual(s["phase"], "HOLD")
        self.assertFalse(s["submission_authorized"])

    def test_weekend_wait_is_not_auto_rejected(self):
        s = self.state
        for event, key, val, ts in [
            ("PROVISIONED", "repository_full_name", "org/repo", "2026-10-27T09:00:00+09:00"),
            ("BUILD_PASSED", "build_run_id", "run-1", "2026-10-28T09:00:00+09:00"),
            ("AUTO_QA_PASSED", "qa_run_id", "qa-1", "2026-10-30T09:00:00+09:00"),
        ]:
            s = advance(s, {"event_id": event, "type": event, key: val}, ts)
        s = advance(s, {"event_id": "weekend-tick", "type": "TICK"},
                    "2026-11-01T09:00:00+09:00")
        self.assertEqual(s["phase"], "WAIT_HUMAN_QA")

    def test_timezone_required(self):
        with self.assertRaises(ValueError):
            initialize("p", "2026-10-26T09:00:00")

    def test_backward_time_rejected(self):
        with self.assertRaises(ValueError):
            advance(self.state, {"event_id": "e", "type": "FAIL"}, "2026-10-25T00:00:00+09:00")

    def test_fail_to_hold(self):
        s = advance(self.state, {"event_id": "e", "type": "FAIL", "reason": "worker failure"},
                    "2026-10-26T10:00:00+09:00")
        self.assertEqual(s["phase"], "HOLD")


if __name__ == "__main__":
    unittest.main()
