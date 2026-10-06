"""Unit tests for run.py's bookkeeping: state, resume, failure handling, recording of decisions
(issue #189). No browser: the page is a small fake, and run_step is scripted where only the
order of steps matters.

run.py imports Playwright at module level and the CI runner does not install it, so a minimal
stub of playwright.sync_api is put in sys.modules when the real one is missing. Nothing here
calls into Playwright. Run from the repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import argparse
import io
import json
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

try:
    import playwright.sync_api  # noqa: F401
except ImportError:
    class _StubError(Exception):
        """Stands in for playwright.sync_api.Error (TimeoutError is a subclass of it)."""

    _stub = types.ModuleType("playwright.sync_api")
    _stub.Browser = _stub.Frame = _stub.Locator = _stub.Page = object
    _stub.Error = _StubError
    _stub.sync_playwright = None
    sys.modules["playwright"] = types.ModuleType("playwright")
    sys.modules["playwright.sync_api"] = _stub

import run  # noqa: E402

LAB = "9.9"
STEPS = {
    "lab": LAB,
    "guide": "guide.md",
    "images": [{"path": "images/Step-9.9.2.png", "width": 2000}, {"path": "images/ok.png", "width": 800}],
    "steps": [
        {"id": "9.9.1", "title": "One", "portal": True, "items": [], "expected": None, "images": []},
        {"id": "9.9.2", "title": "Two", "portal": True, "items": [], "expected": None, "images": []},
        {"id": "9.9.3", "title": "Check", "portal": False, "items": [], "expected": None, "images": []},
        {"id": "9.9.4", "title": "Four", "portal": True, "items": [], "expected": None, "images": []},
        {"id": "9.9.5", "title": "Five", "portal": True, "items": [], "expected": None, "images": []},
    ],
}


class Answers:
    """Plays the person at the keyboard: one scripted answer per prompt, EOF when they run out."""

    def __init__(self, *answers: str) -> None:
        self.answers = list(answers)
        self.prompts: list[str] = []

    def __call__(self, text: str) -> str:
        self.prompts.append(text)
        if not self.answers:
            raise EOFError
        return self.answers.pop(0)


class ScriptedRunner(run.Runner):
    """run_step succeeds unless the step id is in `failing`; records the order of steps run."""

    def __init__(self, *args, failing=(), **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.failing = set(failing)
        self.ran: list[str] = []

    def run_step(self, step: dict) -> bool:
        self.ran.append(step["id"])
        return step["id"] not in self.failing


class RunnerTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(self.tmp, ignore_errors=True))
        self.recording = {"lab": LAB, "guide": "guide.md", "placeholders": {}, "steps": {
            "9.9.1": {"valueOverrides": {}, "viewUrl": "https://portal.azure.com/#view/One", "result": None, "labels": {}}}}
        (self.tmp / "rec.json").write_text(json.dumps(self.recording), encoding="utf-8")

    def args(self, **overrides) -> argparse.Namespace:
        values = dict(steps=self.tmp / "steps.json", recording=self.tmp / "rec.json", log_dir=self.tmp / "logs",
                      run_id="test", tenant_id="0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
                      tenant_domain="contoso.onmicrosoft.com", state=self.tmp / "state.json",
                      auth_state=self.tmp / "auth.json", from_step=None, resume=False, repo_root=self.tmp)
        values.update(overrides)
        return argparse.Namespace(**values)

    def runner(self, answers=(), failing=(), **overrides) -> ScriptedRunner:
        return ScriptedRunner(None, STEPS, self.recording, self.args(**overrides),
                              ask=Answers(*answers), failing=failing)

    def quietly(self, call):
        with redirect_stdout(io.StringIO()):
            return call()

    def state(self) -> dict:
        return json.loads((self.tmp / "state.json").read_text(encoding="utf-8"))


class RunBookkeepingTests(RunnerTestCase):
    def test_a_clean_run_completes_every_portal_step_and_finishes_the_state(self) -> None:
        r = self.runner()
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertIsNone(self.state()["inFlight"])
        self.assertTrue(self.state()["finished"])
        self.assertEqual([x["label"] for x in r.records if x["kind"] == "readability"], ["images/Step-9.9.2.png"])

    def test_skip_the_rest_keeps_the_failed_step_out_of_completed(self) -> None:
        r = self.runner(answers=["s"], failing={"9.9.2"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2"])
        self.assertEqual(r.first_failure, "9.9.2")
        self.assertEqual(self.state(), {"runId": "test", "lab": LAB, "completed": ["9.9.1"],
                                        "inFlight": "9.9.2", "finished": True})
        skipped = [(x["step"], x["skippedBecause"]) for x in r.records if x["outcome"] == "skipped"]
        self.assertEqual(skipped, [("9.9.4", "9.9.2"), ("9.9.5", "9.9.2")])

    def test_closed_input_at_the_failure_prompt_skips_the_rest(self) -> None:
        r = self.runner(answers=[], failing={"9.9.1"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1"])
        self.assertEqual(self.state()["inFlight"], "9.9.1")
        self.assertTrue(self.state()["finished"])

    def test_done_by_hand_marks_the_step_done_and_continues(self) -> None:
        r = self.runner(answers=["x", "c"], failing={"9.9.2"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertEqual(len(r.ask.prompts), 2)     # 'x' is not an answer: asked again

    def test_quit_stops_with_the_failed_step_as_the_resume_point(self) -> None:
        r = self.runner(answers=["q"], failing={"9.9.2"})
        self.assertEqual(self.quietly(r.run), run.ABORTED)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2"])
        self.assertEqual(self.state(), {"runId": "test", "lab": LAB, "completed": ["9.9.1"],
                                        "inFlight": "9.9.2", "finished": False})
        self.assertTrue((r.run_dir / "summary.md").is_file())

    def test_resume_asks_about_the_step_in_flight_and_shows_the_view_before_it(self) -> None:
        state = {"lab": LAB, "completed": ["9.9.1"], "inFlight": "9.9.2", "finished": False}
        for answer, ran, skipped in (("y", ["9.9.4", "9.9.5"], []), ("n", ["9.9.2", "9.9.4", "9.9.5"], []),
                                     ("s", ["9.9.4", "9.9.5"], ["9.9.2"])):
            with self.subTest(answer=answer):
                r = self.runner(answers=[answer], resume=True, run_id=f"resume-{answer}")
                out = io.StringIO()
                with redirect_stdout(out):
                    self.assertEqual(r.run(dict(state)), 0)
                self.assertIn("https://portal.azure.com/#view/One", out.getvalue())
                self.assertEqual(r.ran, ran)
                self.assertEqual([x["step"] for x in r.records if x["outcome"] == "skipped"], skipped)
                self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
                self.assertTrue(self.state()["finished"])

    def test_closed_input_at_the_resume_prompt_runs_nothing(self) -> None:
        state = {"lab": LAB, "completed": ["9.9.1"], "inFlight": "9.9.2", "finished": False}
        r = self.runner(answers=[], resume=True)
        self.assertEqual(self.quietly(lambda: r.run(state)), run.NOT_STARTED)
        self.assertEqual(r.ran, [])
        self.assertEqual(r.records, [])            # not even the readability check
        self.assertFalse((self.tmp / "state.json").exists())

    def test_resume_without_a_step_in_flight_starts_at_the_first_step_not_completed(self) -> None:
        state = {"lab": LAB, "completed": ["9.9.1", "9.9.2"], "inFlight": None, "finished": False}
        r = self.runner(answers=[""], resume=True)
        self.assertEqual(self.quietly(lambda: r.run(state)), 0)
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])
        r = self.runner(answers=[], resume=True, run_id="eof")
        self.assertEqual(self.quietly(lambda: r.run(state)), run.NOT_STARTED)
        self.assertEqual(r.ran, [])

    def test_from_step_starts_there_after_the_person_confirms_the_view(self) -> None:
        r = self.runner(answers=[""], from_step="9.9.4")
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])

    def test_an_unknown_from_step_runs_nothing(self) -> None:
        r = self.runner(from_step="9.9.3")         # not a portal step
        self.assertEqual(self.quietly(r.run), run.NOT_STARTED)
        self.assertEqual(r.ran, [])


class StateTests(RunnerTestCase):
    def test_load_state_refuses_what_cannot_be_resumed(self) -> None:
        path = self.tmp / "state.json"
        with self.assertRaisesRegex(run.StateError, "no state"):
            run.load_state(path, LAB)
        for content, message in (("{not json", "cannot be read"), ("[]", "not a guide drift state"),
                                 (json.dumps({"lab": "1.1", "completed": []}), "belongs to lab 1.1"),
                                 (json.dumps({"lab": LAB, "completed": [], "finished": True}), "finished")):
            with self.subTest(message=message):
                path.write_text(content, encoding="utf-8")
                with self.assertRaisesRegex(run.StateError, message):
                    run.load_state(path, LAB)
        path.write_text(json.dumps({"lab": LAB, "completed": ["9.9.1"], "inFlight": "9.9.2"}), encoding="utf-8")
        self.assertEqual(run.load_state(path, LAB)["inFlight"], "9.9.2")

    def test_start_point(self) -> None:
        ids = ["9.9.1", "9.9.2", "9.9.4"]
        none = {"completed": [], "inFlight": None}
        self.assertEqual(run.start_point(ids, none, None, False), (0, False))
        self.assertEqual(run.start_point(ids, none, "9.9.2", False), (1, False))
        self.assertEqual(run.start_point(ids, {"completed": ["9.9.1"], "inFlight": "9.9.2"}, None, True), (1, True))
        self.assertEqual(run.start_point(ids, {"completed": ["9.9.1"], "inFlight": None}, None, True), (1, False))
        for state, from_step in ((none, "9.9.3"), ({"completed": ids, "inFlight": None}, None),
                                 ({"completed": [], "inFlight": "1.1.1"}, None)):
            with self.subTest(state=state, from_step=from_step), self.assertRaises(ValueError):
                run.start_point(ids, state, from_step, True)

    def test_state_and_recording_are_written_whole(self) -> None:
        r = self.runner()
        r.save_state(["9.9.1"], "9.9.2")
        r.save_recording()
        self.assertEqual(self.state()["inFlight"], "9.9.2")
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir() if p.suffix == ".tmp"), [])


class FakeElement:
    def __init__(self, fail: Exception | None = None, disabled: bool = False) -> None:
        self.fail = fail
        self.disabled = disabled
        self.clicked = 0
        self.calls: list[str] = []

    def scroll_into_view_if_needed(self, timeout=None) -> None:
        self.calls.append("scroll")

    def click(self, timeout=None) -> None:
        self.calls.append("click")
        if self.fail:
            raise self.fail
        self.clicked += 1

    def is_disabled(self, timeout=None) -> bool:
        return self.disabled


class FakePage:
    url = "https://portal.azure.com/#@contoso.onmicrosoft.com/view/Two?x=1"

    def wait_for_timeout(self, ms) -> None:
        pass

    def screenshot(self, path, full_page=False) -> None:
        pass


class DecisionRecordingTests(RunnerTestCase):
    STEP = {"id": "9.9.1", "title": "One", "portal": True, "expected": "Group shows", "images": [],
            "items": [{"kind": "action", "labels": ["+ New group"], "line": 3}]}

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n\n2. Click **+ New group**\n", encoding="utf-8")

    def act(self, answers, element, label="+ New group", exact=None):
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers(*answers))
        candidates = [run.Candidate("button", "New group"), run.Candidate("link", "Groups"),
                      run.Candidate("button", "Delete group"), run.Candidate("link", "Contoso Ltd")]
        with mock.patch.object(run, "find_exact", return_value=exact), \
                mock.patch.object(run, "candidates_on_screen", return_value=candidates), \
                mock.patch.object(run, "find_by_name", return_value=element) as self.find_by_name:
            record = self.quietly(lambda: r.act_on_label(self.STEP, self.STEP["items"][0], label))
        saved = json.loads((self.tmp / "rec.json").read_text(encoding="utf-8"))
        return record, saved["steps"].get("9.9.1", {}).get("labels", {})

    def test_the_element_is_scrolled_into_view_before_the_click(self) -> None:
        element = FakeElement()
        self.act(["1"], element)
        self.assertEqual(element.calls, ["scroll", "click"])
        self.assertEqual(self.find_by_name.call_args.args[1:], ("button", "New group"))   # plain: exact

    def test_a_redacted_choice_is_looked_up_regardless_of_case(self) -> None:
        record, labels = self.act(["4"], FakeElement())
        self.assertEqual(labels["+ New group"]["name"], "[yourtenant] Ltd")    # what the recording keeps
        role, name = self.find_by_name.call_args.args[1:]
        self.assertEqual(role, "link")
        self.assertIsNotNone(name.search("Contoso Ltd"))                      # what the screen shows
        self.assertIsNone(name.search("Contoso Ltd 2"))

    def test_a_destructive_element_is_refused_unless_the_guide_names_one(self) -> None:
        element = FakeElement()
        record, labels = self.act(["3"], element)
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("refused: destructive element 'Delete group'", record["observed"])
        self.assertEqual((element.clicked, labels), (0, {}))
        record, _ = self.act([], None, label="Delete", exact=element)    # the guide says Delete
        self.assertEqual((record["outcome"], element.clicked), ("match", 1))

    def test_a_disabled_element_is_unknown_without_waiting(self) -> None:
        element = FakeElement(disabled=True)
        record, labels = self.act(["1"], element)
        self.assertEqual((record["outcome"], record["observed"]), ("unknown", "disabled: 'New group'"))
        self.assertEqual((element.clicked, labels), (0, {}))

    def test_a_chosen_element_is_recorded_once_the_click_went_through(self) -> None:
        record, labels = self.act(["1"], FakeElement())
        self.assertEqual((record["outcome"], record["severity"], record["observed"]), ("drift", "misleading", "New group"))
        self.assertEqual(record["proposedEdit"]["new"], "2. Click **New group**")
        self.assertEqual(labels["+ New group"]["name"], "New group")

    def test_a_chosen_element_whose_click_failed_is_not_recorded(self) -> None:
        record, labels = self.act(["1"], FakeElement(fail=run.PlaywrightError("timed out")))
        self.assertEqual(record["outcome"], "unknown")
        self.assertNotIn("+ New group", labels)

    def test_a_chosen_element_no_longer_on_screen_is_not_recorded(self) -> None:
        record, labels = self.act(["1"], None)
        self.assertEqual(record["outcome"], "unknown")
        self.assertNotIn("+ New group", labels)

    def test_gone_and_ignore_are_recorded_at_once(self) -> None:
        record, labels = self.act(["g"], None)
        self.assertEqual((record["outcome"], record["severity"]), ("drift", "blocking"))
        self.assertEqual(labels["+ New group"]["decision"], "gone")
        self.recording["steps"]["9.9.1"]["labels"].clear()     # or replay answers 'gone'
        record, labels = self.act(["i"], None)
        self.assertEqual(record["outcome"], "match")
        self.assertEqual(labels["+ New group"]["decision"], "ignore")

    def test_a_failed_step_keeps_its_view_and_is_not_checked_for_its_result(self) -> None:
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        unknown = r.new_record(self.STEP, "action", "+ New group")
        unknown.update(outcome="unknown", observed="not found")
        with mock.patch.object(run.Runner, "act_on_label", return_value=unknown), \
                mock.patch.object(run.Runner, "check_result") as check:
            self.assertFalse(self.quietly(lambda: r.run_step(self.STEP)))
        check.assert_not_called()
        self.assertEqual(self.recording["steps"]["9.9.1"]["viewUrl"], "https://portal.azure.com/#view/One")
        match = dict(unknown, outcome="match", observed="+ New group")
        with mock.patch.object(run.Runner, "act_on_label", return_value=match), \
                mock.patch.object(run.Runner, "check_result") as check:
            self.assertTrue(self.quietly(lambda: r.run_step(self.STEP)))
        check.assert_called_once()
        self.assertEqual(self.recording["steps"]["9.9.1"]["viewUrl"], "https://portal.azure.com/#view/Two")


class SummaryTests(RunnerTestCase):
    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n\n2. Click **+ New group**\n3. Open the blade\n", encoding="utf-8")
        self.r = self.runner()

    def add(self, kind, label, **fields) -> None:
        record = self.r.new_record({"id": "9.9.2"}, kind, label)
        record.update(fields)
        self.r.records.append(record)

    def test_proposed_edit_replaces_the_bold_label_or_proposes_nothing(self) -> None:
        self.assertEqual(self.r.proposed_edit(3, "+ New group", "New group"),
                         {"line": 3, "old": "2. Click **+ New group**", "new": "2. Click **New group**"})
        self.assertIsNone(self.r.proposed_edit(4, "Blade", "Blades"))      # not in bold on that line
        self.assertIsNone(self.r.proposed_edit(99, "+ New group", "New group"))

    def test_finish_lists_every_section_and_counts_blocking_and_unknown(self) -> None:
        self.r.readability()
        self.add("action", "+ New group", outcome="drift", severity="misleading", observed="New group",
                 proposedEdit={"line": 3, "old": "2. Click **+ New group**", "new": "2. Click **New group**"})
        self.add("action", "Groups", outcome="drift", severity="cosmetic", observed="groups")
        self.add("action", "Gone", outcome="drift", severity="blocking")
        self.add("field", "Group type", outcome="unknown", observed="ambiguous: 2 visible elements match")
        self.add("screenshot", None, outcome="drift", category="stale", observed="images/Step-9.9.2.png")
        self.add("action", None, outcome="skipped", skippedBecause="9.9.1")
        self.add("action", "OK", outcome="match", observed="OK")
        self.assertEqual(self.quietly(self.r.finish), 2)
        summary = (self.r.run_dir / "summary.md").read_text(encoding="utf-8")
        for line in ("## blocking (1)", "**Gone**: gone from the Portal", "## misleading (1)", "## cosmetic (1)",
                     "## unknown (1)", "## skipped (1)", "- step 9.9.2 because step 9.9.1 failed",
                     "## stale screenshots (1)", "## unreadable screenshots, wider than 1722 px (1)",
                     "images/Step-9.9.2.png: 2000 px wide", "## proposed edits (1)", "guide.md:3"):
            self.assertIn(line, summary)

    def test_finish_says_none_for_empty_sections_and_caps_the_exit_code(self) -> None:
        self.assertEqual(self.quietly(self.r.finish), 0)
        summary = (self.r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## proposed edits (0)\n- none", summary)
        for _ in range(300):
            self.add("action", "x", outcome="unknown", observed="not found")
        self.assertEqual(self.quietly(self.r.finish), 250)


if __name__ == "__main__":
    unittest.main()
