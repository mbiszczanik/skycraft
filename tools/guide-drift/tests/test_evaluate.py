"""Unit tests for evaluate.py, the offline scorer of deciders (issue #190). Stub deciders only.

Run by hand from the repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import evaluate  # noqa: E402
from decide import Decision  # noqa: E402


def recording(labels: dict) -> dict:
    return {"lab": "9.9", "steps": {"9.9.1": {"labels": labels}}}


def entry(decision="use", name="Groups", by="human", rejected=('link "Users"', 'button "Help"')):
    return {"decision": decision, "role": "link", "name": name, "severity": None,
            "rejected": list(rejected), "decidedBy": by, "at": "2026-11-16T00:00:00Z"}


def folder(*recordings) -> tempfile.TemporaryDirectory:
    tmp = tempfile.TemporaryDirectory()
    for i, data in enumerate(recordings):
        Path(tmp.name, f"lab-{i}.json").write_text(json.dumps(data), encoding="utf-8")
    return tmp


def pick(name, confidence):
    """A stub decider that always picks `name` with `confidence`."""
    return lambda step, item, label, candidates: Decision(kind="use", name=name, decided_by="model",
                                                          confidence=confidence)


class LoadReference(unittest.TestCase):
    def test_only_human_decisions_with_their_fields(self):
        tmp = folder(recording({"Groups": entry(), "Users": entry(name="Users", by="model"),
                                "Old": entry(by="replay")}))
        self.addCleanup(tmp.cleanup)
        cases = evaluate.load_reference(Path(tmp.name))
        self.assertEqual(1, len(cases))
        case = cases[0]
        self.assertEqual(("9.9.1", "Groups", "use", "Groups"), (case.step_id, case.label, case.decision, case.name))
        self.assertEqual(['link "Users"', 'button "Help"'], case.rejected)

    def test_candidates_hold_chosen_and_rejected(self):
        case = evaluate.Case("9.9", "9.9.1", "Groups", "use", "Groups", "link", ['link "Users"', 'button "Help"'])
        names = [(c.role, c.name) for c in case.candidates()]
        self.assertEqual(3, len(names))
        self.assertIn(("link", "Groups"), names)
        self.assertIn(("button", "Help"), names)

    def test_the_shipped_recordings_hold_human_decisions(self):
        self.assertTrue(evaluate.load_reference())


class Scoring(unittest.TestCase):
    def setUp(self):
        self.cases = [evaluate.Case("9.9", f"9.9.{i}", "Groups", "use", "Groups", "link", ['link "Users"'])
                      for i in range(4)]

    def test_baseline_always_asks(self):
        report = evaluate.evaluate(evaluate.ask_always, self.cases)
        self.assertEqual(0.0, report.accuracy)
        self.assertEqual([], report.answered)
        self.assertEqual((0.0, None), report.at_threshold(0.5))

    def test_accuracy_counts_a_decision_not_made_as_wrong(self):
        answers = iter(["Groups", "Users", None, "Groups"])

        def decider(step, item, label, candidates):
            name = next(answers)
            return None if name is None else Decision(kind="use", name=name, confidence=0.9)

        report = evaluate.evaluate(decider, self.cases)
        self.assertEqual(0.5, report.accuracy)
        self.assertAlmostEqual(2 / 3, report.accuracy_answered)

    def test_ignore_and_gone_cases(self):
        ignore = evaluate.Case("9.9", "9.9.1", "X", "ignore", None, None, [])
        gone = evaluate.Case("9.9", "9.9.2", "Y", "gone", None, None, [])
        report = evaluate.evaluate(lambda s, i, label, c: Decision(
            kind="ignore" if label == "X" else "drift", severity="blocking"), [ignore, gone])
        self.assertEqual(1.0, report.accuracy)

    def test_calibration_table_and_ece(self):
        results = iter([("Groups", 0.95), ("Groups", 0.95), ("Users", 0.95), ("Groups", 0.55)])

        def decider(step, item, label, candidates):
            name, confidence = next(results)
            return Decision(kind="use", name=name, confidence=confidence)

        report = evaluate.evaluate(decider, self.cases)
        rows = report.calibration()
        self.assertEqual([(0.5, 0.6, 1), (0.9, 1.0, 3)], [(r[0], r[1], r[2]) for r in rows])
        self.assertAlmostEqual(2 / 3, rows[1][3])
        # |1 - .55| * 1/4 + |2/3 - .95| * 3/4
        self.assertAlmostEqual(0.45 / 4 + abs(2 / 3 - 0.95) * 3 / 4, report.ece())

    def test_coverage_and_accuracy_at_threshold(self):
        results = iter([("Groups", 0.99), ("Users", 0.92), ("Groups", 0.6), ("Groups", 0.97)])

        def decider(step, item, label, candidates):
            name, confidence = next(results)
            return Decision(kind="use", name=name, confidence=confidence)

        report = evaluate.evaluate(decider, self.cases)
        self.assertEqual((0.75, 2 / 3), report.at_threshold(0.9))
        self.assertEqual((0.5, 1.0), report.at_threshold(0.97))

    def test_latency_is_measured_per_decision(self):
        report = evaluate.evaluate(pick("Groups", 1.0), self.cases)
        mean, median, worst = report.latency_ms()
        self.assertTrue(0 <= mean <= worst and 0 <= median <= worst)
        self.assertEqual(4, len(report.outcomes))

    def test_a_raising_decider_counts_as_asked(self):
        def broken(step, item, label, candidates):
            raise RuntimeError("down")

        report = evaluate.evaluate(broken, self.cases)
        self.assertEqual(0.0, report.accuracy)
        self.assertTrue(all(o.failed for o in report.outcomes))

    def test_text_names_every_measure(self):
        text = evaluate.evaluate(pick("Groups", 0.9), self.cases).text()
        for words in ("Accuracy", "Calibration", "Expected calibration error", "coverage", "Latency per decision"):
            self.assertIn(words, text)


class Main(unittest.TestCase):
    def test_no_human_decision_exits_non_zero_without_a_score(self):
        tmp = folder(recording({"Groups": entry(by="replay")}), {"lab": "x", "steps": {}})
        self.addCleanup(tmp.cleanup)
        lines = []
        code = evaluate.main(["--recordings", tmp.name], out=lines.append)
        self.assertEqual(1, code)
        self.assertIn("No human decision", lines[0])
        self.assertNotIn("Accuracy", "\n".join(lines))

    def test_empty_folder_exits_non_zero(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.assertEqual(1, evaluate.main(["--recordings", tmp.name], out=lambda s: None))

    def test_baseline_run_exits_zero_and_prints_a_score(self):
        tmp = folder(recording({"Groups": entry()}))
        self.addCleanup(tmp.cleanup)
        lines = []
        self.assertEqual(0, evaluate.main(["--recordings", tmp.name], out=lines.append))
        self.assertIn("Accuracy", lines[0])


class NoModelLibrary(unittest.TestCase):
    def test_nothing_imports_a_model_library_or_the_network(self):
        for module in (evaluate, sys.modules["decide"]):
            source = Path(module.__file__).read_text(encoding="utf-8")
            for word in ("openai", "anthropic", "urllib", "requests", "socket", "http"):
                self.assertNotIn(f"import {word}", source)


if __name__ == "__main__":
    unittest.main()
