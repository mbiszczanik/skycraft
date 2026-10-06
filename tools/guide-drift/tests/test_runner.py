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
    """run_step succeeds unless the step id is in `failing` (fails quietly) or `unknown` (writes
    an unknown record and fails); a step in `interrupt` raises KeyboardInterrupt, as Ctrl+C
    would. Records the order of steps run."""

    def __init__(self, *args, failing=(), unknown=(), interrupt=(), **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.failing = set(failing)
        self.unknown = set(unknown)
        self.interrupt = set(interrupt)
        self.ran: list[str] = []

    def run_step(self, step: dict) -> bool:
        self.ran.append(step["id"])
        if step["id"] in self.interrupt:
            raise KeyboardInterrupt
        if step["id"] in self.unknown:
            record = self.new_record(step, "action", "Missing button")
            record.update(outcome="unknown", observed="not found")
            self.write(record)
            return False
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

    def runner(self, answers=(), failing=(), unknown=(), interrupt=(), state=None, **overrides) -> ScriptedRunner:
        return ScriptedRunner(None, STEPS, self.recording, self.args(**overrides), ask=Answers(*answers),
                              state=state, failing=failing, unknown=unknown, interrupt=interrupt)

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

    def __init__(self, closed: bool = False) -> None:
        self.closed = closed

    def is_closed(self) -> bool:
        return self.closed

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
                      run.Candidate("button", "Delete group"), run.Candidate("link", "Contoso Ltd"),
                      run.Candidate("menuitem", "Bulk delete")]
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

    def test_a_name_that_is_the_label_once_restored_needs_no_decision(self) -> None:
        element = FakeElement()
        record, labels = self.act([], element, label="Contoso Ltd")     # no answers: a prompt would fail
        self.assertEqual((record["outcome"], record["severity"]), ("match", None))
        self.assertEqual((element.clicked, labels), (1, {}))             # exact: nothing to record
        self.assertIsNotNone(self.find_by_name.call_args.args[2].search("Contoso Ltd"))

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

    def test_a_destructive_word_later_in_the_name_is_refused_too(self) -> None:
        element = FakeElement()
        record, labels = self.act(["5"], element)                         # 'Bulk delete'
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("refused: destructive element 'Bulk delete'", record["observed"])
        self.assertEqual((element.clicked, labels), (0, {}))

    def test_a_guide_label_with_the_word_later_in_it_is_allowed(self) -> None:
        element = FakeElement()
        record, _ = self.act([], None, label="Password reset", exact=element)
        self.assertEqual((record["outcome"], record["observed"], element.clicked), ("match", "Password reset", 1))

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


class OneRunAcrossResumeTests(RunnerTestCase):
    def stopped_run(self, **script) -> dict:
        r = self.runner(run_id="first", **script)
        try:
            self.quietly(r.run)
        except KeyboardInterrupt:
            pass                     # main() would return ABORTED here, with the state kept
        return run.load_state(self.tmp / "state.json", LAB)

    def summary(self) -> str:
        return (self.tmp / "logs" / "first" / "summary.md").read_text(encoding="utf-8")

    def test_a_resumed_run_counts_and_lists_what_the_stopped_part_found(self) -> None:
        state = self.stopped_run(answers=["q"], unknown={"9.9.4"})       # step 3 of the portal steps
        self.assertEqual((state["runId"], state["inFlight"]), ("first", "9.9.4"))
        r = self.runner(answers=["y"], resume=True, run_id="second", state=state)
        self.assertEqual(r.run_dir, self.tmp / "logs" / "first")
        self.assertEqual(self.quietly(lambda: r.run(state)), 1)
        self.assertIn("- step 9.9.4 action **Missing button**: not found", self.summary())
        self.assertFalse((self.tmp / "logs" / "second").exists())
        self.assertEqual(sum(1 for x in r.records if x["kind"] == "readability"), 1)   # not checked twice
        self.assertEqual(self.state()["runId"], "first")

    def test_a_step_done_by_hand_keeps_its_findings_across_a_stop(self) -> None:
        state = self.stopped_run(answers=["c"], unknown={"9.9.4"}, interrupt={"9.9.5"})
        self.assertEqual((state["completed"], state["inFlight"]), (["9.9.1", "9.9.2", "9.9.4"], "9.9.5"))
        r = self.runner(answers=["n"], resume=True, run_id="second", state=state)
        self.assertEqual(self.quietly(lambda: r.run(state)), 1)
        summary = self.summary()
        self.assertIn("- step 9.9.4 action **Missing button**: not found", summary)
        self.assertIn("## done by hand (1)\n- step 9.9.4", summary)

    def test_a_redone_step_replaces_its_stopped_attempt(self) -> None:
        state = self.stopped_run(answers=["q"], unknown={"9.9.4"})
        r = self.runner(answers=["n"], resume=True, run_id="second", state=state)
        self.assertEqual(self.quietly(lambda: r.run(state)), 0)
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])
        results = (self.tmp / "logs" / "first" / "results.jsonl").read_text(encoding="utf-8")
        self.assertIn('"outcome": "unknown"', results)      # the file keeps both attempts

    def test_a_cut_short_last_line_is_skipped(self) -> None:
        folder = self.tmp / "logs" / "first"
        folder.mkdir(parents=True)
        (folder / "results.jsonl").write_text('{"step": "9.9.1", "outcome": "match", "kind": "action"}\n{"step": "9.9',
                                               encoding="utf-8")
        r = self.runner(resume=True, state={"runId": "first", "lab": LAB, "completed": [], "inFlight": None})
        self.assertEqual([x["step"] for x in r.records], ["9.9.1"])


class GuardAndLookupTests(RunnerTestCase):
    def test_tree_text_reads_text_and_text_boxes_but_never_link_targets(self) -> None:
        snapshot = ('- link "Switch directory":\n'
                    '  - /url: "#@0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d/view/Overview"\n'
                    '- text: Tenant ID\n'
                    '- textbox "Tenant ID" [disabled]: 11111111-2222-3333-4444-555555555555\n'
                    '- textbox "Primary domain": "Contoso.onmicrosoft.com"\n')
        tree = run.tree_text(snapshot)
        self.assertNotIn("0a1b2c3d", tree)
        self.assertIn("11111111-2222-3333-4444-555555555555", tree)
        self.assertIn("contoso.onmicrosoft.com", tree)
        self.assertIn("tenant id", tree)

    def guard(self, visible_text: str, snapshot: str) -> str | None:
        """guard_tenant on a page whose visible text is `visible_text` and whose one frame has
        the accessibility snapshot `snapshot`; the clock runs out after the first look."""
        class Frame:
            def locator(self, selector):
                return self

            def aria_snapshot(self, timeout=None) -> str:
                return snapshot

        class Page:
            def wait_for_timeout(self, ms) -> None:
                pass

        clock = iter(range(0, 1000, 11))
        with mock.patch.object(run.time, "monotonic", lambda: next(clock)), \
                mock.patch.object(run, "all_frames", lambda page: [Frame()]), \
                mock.patch.object(run, "text_on_screen", lambda page, text: text.lower() in visible_text.lower()):
            return run.guard_tenant(Page(), "contoso.onmicrosoft.com", "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")

    def test_the_tenant_guard_accepts_the_tenant_id_as_text_or_text_box_value(self) -> None:
        self.assertIsNone(self.guard("Tenant ID 0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", ""))
        self.assertIsNone(self.guard("Tenant ID", '- textbox "Tenant ID": 0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D'))

    def test_the_tenant_guard_never_accepts_the_domain(self) -> None:
        # The header shows the signed-in account, home domain included, in whatever directory.
        failure = self.guard("admin@contoso.onmicrosoft.com Tenant ID 11111111-2222-3333-4444-555555555555",
                             "- text: admin@contoso.onmicrosoft.com\n"
                             '- textbox "Primary domain": contoso.onmicrosoft.com')
        self.assertIn("does not show tenant ID 0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d", failure)

    def test_destructive_words_anywhere_in_the_name(self) -> None:
        for name in ("Delete", "Delete group", "Bulk delete", "Reset password", "Block sign in", "Purge",
                     "Sign out", "Remove member"):
            with self.subTest(name=name):
                self.assertIsNotNone(run.DESTRUCTIVE.search(name))
        for name in ("Deleted users", "New group", "Blocked", "Signed out", "Removal policy"):
            with self.subTest(name=name):
                self.assertIsNone(run.DESTRUCTIVE.search(name))

    def test_an_element_that_cannot_be_inspected_still_counts(self) -> None:
        class Element:
            def __init__(self, fails: bool) -> None:
                self.fails = fails

            def is_visible(self) -> bool:
                if self.fails:
                    raise run.PlaywrightError("element went away")
                return True

            def bounding_box(self, timeout=None) -> dict:
                return {"x": 10, "y": 5000, "width": 50, "height": 20}

        class Locator:
            items = [Element(False), Element(True)]

            def count(self) -> int:
                return len(self.items)

            def nth(self, index: int):
                return self.items[index]

        self.assertEqual(len(run.visible_in(Locator(), {"width": 1440, "height": 900})), 2)

    def test_same_after_restore(self) -> None:
        r = self.runner()
        tenant = run.Candidate("link", "[yourtenant] Ltd")
        self.assertIs(r.same_after_restore([run.Candidate("button", "New group"), tenant], "Contoso Ltd"), tenant)
        upn = run.Candidate("cell", "khadgar.archmage@[tenantdomain]")
        self.assertIs(r.same_after_restore([upn], "khadgar.archmage@[yourtenant].onmicrosoft.com"), upn)
        self.assertIsNone(r.same_after_restore([run.Candidate("button", "New Group")], "New group"))   # plain case
        self.assertIsNone(r.same_after_restore([tenant, run.Candidate("cell", "[yourtenant] Ltd")], "Contoso Ltd"))
        self.assertIsNone(r.same_after_restore([run.Candidate("link", "[yourtenant] Ltd", count=2)], "Contoso Ltd"))

    def test_wait_for_sign_in_says_it_is_still_waiting_every_minute(self) -> None:
        class Page:
            url = "https://login.microsoftonline.com/common/oauth2"
            waits = 0

            def wait_for_timeout(self, ms) -> None:
                self.waits += 1
                if self.waits == 4:
                    self.url = "https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview"

        clock = iter(range(0, 10_000, 31))                  # 31 s pass between every look at the clock
        said: list[str] = []
        with mock.patch.object(run.time, "monotonic", lambda: next(clock)), \
                mock.patch.object(run, "visible_across_frames", lambda page, make, anywhere=False: ["Tenant ID"]
                                  if page.url.startswith(run.PORTAL) else []):
            run.wait_for_sign_in(Page(), "t", say=said.append)
        self.assertEqual(sum("Still waiting" in line for line in said), 2)


class StopTests(RunnerTestCase):
    def test_a_closed_window_stops_before_the_candidate_prompt(self) -> None:
        r = run.Runner(FakePage(closed=True), STEPS, self.recording, self.args(), ask=Answers())
        step = {"id": "9.9.1", "title": "One", "items": [], "images": []}
        with mock.patch.object(run, "find_exact", return_value=None), self.assertRaises(run.PageClosed):
            r.act_on_label(step, {"kind": "action", "line": 1}, "+ New group")
        self.assertEqual(r.ask.prompts, [])

    def test_main_reports_a_failure_to_open_the_portal_as_not_started(self) -> None:
        steps = dict(STEPS)
        (self.tmp / "steps.json").write_text(json.dumps(steps), encoding="utf-8")
        argv = ["--steps", str(self.tmp / "steps.json"), "--recording", str(self.tmp / "rec.json"),
                "--log-dir", str(self.tmp / "logs"), "--run-id", "x", "--tenant-id", "t", "--tenant-domain", "d",
                "--state", str(self.tmp / "state.json"), "--auth-state", str(self.tmp / "auth.json")]

        class Playwright:
            def __enter__(self):
                return self

            def __exit__(self, *exc) -> bool:
                return False

        class Console(io.StringIO):
            def reconfigure(self, **kwargs) -> None:
                pass

        out = Console()
        with mock.patch.object(run, "sync_playwright", Playwright), \
                mock.patch.object(run, "open_portal", side_effect=OSError("disk full")), redirect_stdout(out):
            self.assertEqual(run.main(argv), run.NOT_STARTED)
        self.assertIn("Could not open the Portal: OSError: disk full", out.getvalue())


if __name__ == "__main__":
    unittest.main()
