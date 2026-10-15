"""Unit tests for run.py's bookkeeping: state, resume, failure handling, recording of decisions
(issue #189), steps the recording skips (#200), the view a resumed run starts from (#206), the
blade a step starts on and the form its fields are filled in on (#207), and how it finds what a
guide names (search, '+' labels, plain text, collapsed menu groups, a blade still loading, a
resource a chain names, #199, a Portal deployment still running, #328), what results.jsonl and
summary.md keep (#212), and what a step redone across resumes counts (#222). No browser: the page
is a small fake (Screen stands in for a frame), and run_step is scripted where only the order of
steps matters.

run.py imports Playwright at module level and the CI runner does not install it, so a minimal
stub of playwright.sync_api is put in sys.modules when the real one is missing. Nothing here
calls into Playwright. tests/Guide-Drift-Python.Tests.ps1 runs this suite in CI. Run from the
repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import argparse
import io
import json
import re
import sys
import tempfile
import types
import unittest
import contextlib
from contextlib import redirect_stderr, redirect_stdout
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

import decide  # noqa: E402
import run  # noqa: E402

LAB = "9.9"
TENANT_ID = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
STEPS = {
    "lab": LAB,
    "guide": "guide.md",
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
                      run_id="test", tenant_id=TENANT_ID,
                      tenant_domain="contoso.onmicrosoft.com", state=self.tmp / "state.json",
                      auth_state=self.tmp / "auth.json", from_step=None, resume=False, repo_root=self.tmp)
        values.update(overrides)
        return argparse.Namespace(**values)

    def runner(self, answers=(), failing=(), unknown=(), interrupt=(), state=None, page=None,
               **overrides) -> ScriptedRunner:
        return ScriptedRunner(page or FakePage(), STEPS, self.recording, self.args(**overrides),
                              ask=Answers(*answers), state=state, failing=failing, unknown=unknown,
                              interrupt=interrupt)

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

    def test_end_the_lab_keeps_the_failed_step_out_of_completed(self) -> None:
        r = self.runner(answers=["e"], failing={"9.9.2"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2"])
        self.assertEqual(r.first_failure, "9.9.2")
        self.assertEqual(self.state(), {"runId": "test", "lab": LAB, "completed": ["9.9.1"],
                                        "inFlight": "9.9.2", "finished": True, "logDir": str((self.tmp / "logs").resolve())})
        skipped = [(x["step"], x["skippedBecause"]) for x in r.records if x["outcome"] == "skipped"]
        self.assertEqual(skipped, [("9.9.4", "9.9.2"), ("9.9.5", "9.9.2")])

    def test_closed_input_at_the_failure_prompt_skips_the_rest(self) -> None:
        r = self.runner(answers=[], failing={"9.9.1"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1"])
        self.assertEqual(self.state()["inFlight"], "9.9.1")
        self.assertTrue(self.state()["finished"])

    def test_skip_this_step_records_the_reason_and_continues_with_the_next(self) -> None:
        r = self.runner(answers=["s", "", "no spare licences"], unknown={"9.9.2"})
        self.assertEqual(self.quietly(r.run), 1)        # the failure that caused the skip still counts
        self.assertEqual(r.ran, ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertIsNone(r.first_failure)
        self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertIsNone(self.state()["inFlight"])
        self.assertTrue(self.state()["finished"])       # a finished run: the entry point cleans up
        skipped = [(x["step"], x["skippedBecause"], x["observed"]) for x in r.records if x["outcome"] == "skipped"]
        self.assertEqual(skipped, [("9.9.2", "9.9.2", "no spare licences")])
        self.assertEqual(r.ask.prompts[1:], [run.Runner.REASON_PROMPT] * 2)     # an empty reason: asked again
        results = (r.run_dir / "results.jsonl").read_text(encoding="utf-8")
        self.assertIn('"outcome": "skipped"', results)
        summary = (r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## unknown (1)\n- step 9.9.2 action **Missing button**: not found", summary)
        self.assertIn("## skipped (1)\n- step 9.9.2 skipped after it failed: no spare licences\n", summary)

    def test_every_failed_step_after_a_skip_gets_the_same_prompt(self) -> None:
        r = self.runner(answers=["s", "optional in this tenant", "e"], failing={"9.9.2", "9.9.4"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2", "9.9.4"])
        self.assertEqual([p for p in r.ask.prompts if p == run.Runner.FAILURE_PROMPT], [run.Runner.FAILURE_PROMPT] * 2)
        skipped = [(x["step"], x["skippedBecause"]) for x in r.records if x["outcome"] == "skipped"]
        self.assertEqual(skipped, [("9.9.2", "9.9.2"), ("9.9.5", "9.9.4")])
        self.assertEqual((self.state()["completed"], self.state()["inFlight"]), (["9.9.1", "9.9.2"], "9.9.4"))
        summary = (r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("- step 9.9.2 skipped after it failed: optional in this tenant\n"
                      "- step 9.9.5 because step 9.9.4 failed", summary)

    def test_closed_input_at_the_reason_prompt_ends_the_lab(self) -> None:
        r = self.runner(answers=["s"], failing={"9.9.2"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2"])
        self.assertEqual(r.first_failure, "9.9.2")
        self.assertEqual((self.state()["completed"], self.state()["inFlight"]), (["9.9.1"], "9.9.2"))
        self.assertTrue(self.state()["finished"])

    def test_the_reason_for_a_skip_is_redacted(self) -> None:
        r = self.runner(answers=["s", "contoso.onmicrosoft.com has no licences"], failing={"9.9.2"})
        self.quietly(r.run)
        self.assertEqual([x["observed"] for x in r.records if x["outcome"] == "skipped"],
                         ["[tenantdomain] has no licences"])

    def test_s_skips_one_step_in_both_prompts(self) -> None:
        def line(prompt: str, letter: str) -> str:
            return next(text for text in prompt.splitlines() if text.startswith(f"  {letter}  "))
        for prompt in (run.Runner.FAILURE_PROMPT, run.Runner.RESUME_PROMPT):
            with self.subTest(prompt=prompt):
                self.assertIn("continue with the next step", line(prompt, "s"))
        self.assertIn("skip the rest of the lab", line(run.Runner.FAILURE_PROMPT, "e"))
        r = self.runner(answers=["x", "q"])
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(r.ask_after_failure({"id": "9.9.2"}), "q")
        self.assertIn("Answer c, s, e or q.", out.getvalue())

    def test_done_by_hand_marks_the_step_done_and_continues(self) -> None:
        r = self.runner(answers=["x", "c"], failing={"9.9.2"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertEqual(len(r.ask.prompts), 2)     # 'x' is not an answer: asked again

    def test_the_failure_prompt_lists_why_the_step_did_not_go_through(self) -> None:
        r = self.runner(answers=["q"])
        for kind, label, outcome, severity, observed in (
                ("action", "Users", "match", None, "Users"),
                ("field", "User principal name", "unknown", None,
                 "Error: fill('a@contoso.onmicrosoft.com'): not an <input>\n  - waiting for get_by_label()"),
                ("action", "Gone", "drift", "blocking", None),
                ("screenshot", None, "drift", None, "images/Step-9.9.2.png")):
            record = r.new_record({"id": "9.9.2"}, kind, label)
            record.update(outcome=outcome, severity=severity, observed=observed)
            r.records.append(record)
        r.records.append(dict(r.new_record({"id": "9.9.1"}, "action", "Other step"), outcome="unknown"))
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(r.ask_after_failure({"id": "9.9.2"}), "q")
        lines = out.getvalue().splitlines()
        start = lines.index("Step 9.9.2 did not go through:")
        self.assertEqual(lines[start + 1:start + 5], [
            "  field 'User principal name': unknown: Error: fill('a@[tenantdomain]'): not an <input>",
            "  action 'Gone': drift (blocking): -",
            "  screenshot: drift: images/Step-9.9.2.png",                 # no label: the kind alone
            "What now?"])
        self.assertNotIn("contoso.onmicrosoft.com", out.getvalue())

    def test_quit_stops_with_the_failed_step_as_the_resume_point(self) -> None:
        r = self.runner(answers=["q"], failing={"9.9.2"})
        self.assertEqual(self.quietly(r.run), run.ABORTED)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2"])
        self.assertEqual(self.state(), {"runId": "test", "lab": LAB, "completed": ["9.9.1"],
                                        "inFlight": "9.9.2", "finished": False, "logDir": str((self.tmp / "logs").resolve())})
        self.assertTrue((r.run_dir / "summary.md").is_file())

    def test_resume_asks_about_the_step_in_flight_and_brings_the_portal_to_the_next_view(self) -> None:
        # y: the view the step in flight ended on; n: the view before it, to redo it; s: the step
        # after it starts where the skipped step would have ended, as the guide has it.
        self.recording["steps"]["9.9.2"] = {"viewUrl": "https://portal.azure.com/#view/Two"}
        state = {"lab": LAB, "completed": ["9.9.1"], "inFlight": "9.9.2", "finished": False}
        for answer, ran, skipped, view in (("y", ["9.9.4", "9.9.5"], [], "Two"),
                                           ("n", ["9.9.2", "9.9.4", "9.9.5"], [], "One"),
                                           ("s", ["9.9.4", "9.9.5"], ["9.9.2"], "Two")):
            with self.subTest(answer=answer):
                r = self.runner(answers=[answer, ""], resume=True, run_id=f"resume-{answer}")
                out = io.StringIO()
                with redirect_stdout(out):
                    self.assertEqual(r.run(dict(state)), 0)
                self.assertIn(f"Opened the view step {'9.9.1' if view == 'One' else '9.9.2'} ended on:\n"
                              f"  https://portal.azure.com/#view/{view}\n", out.getvalue())
                self.assertEqual(r.page.visited, [f"https://portal.azure.com/#@{TENANT_ID}/view/{view}"])
                self.assertEqual(r.ask.prompts[-1], "> ")                  # waited for Enter
                self.assertEqual(r.ran, ran)
                self.assertEqual([x["step"] for x in r.records if x["outcome"] == "skipped"], skipped)
                self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
                self.assertTrue(self.state()["finished"])

    def test_closed_input_at_the_resume_prompt_runs_nothing(self) -> None:
        state = {"lab": LAB, "completed": ["9.9.1"], "inFlight": "9.9.2", "finished": False}
        r = self.runner(answers=[], resume=True)
        self.assertEqual(self.quietly(lambda: r.run(state)), run.NOT_STARTED)
        self.assertEqual(r.ran, [])
        self.assertEqual(r.records, [])
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
        self.assertEqual(r.ask.prompts, ["> "])

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
    def __init__(self, fail: Exception | None = None, disabled: bool = False, disabled_for: int = 0) -> None:
        self.fail = fail
        self.disabled = disabled              # for good
        self.disabled_for = disabled_for      # for this many looks, as while a blade loads
        self.clicked = 0
        self.calls: list[str] = []

    def scroll_into_view_if_needed(self, timeout=None) -> None:
        self.calls.append("scroll")

    def evaluate(self, script, arg=None, timeout=None):
        raise run.PlaywrightError("a bare element cannot be inspected")     # opens_a_list: not a list

    def click(self, timeout=None) -> None:
        self.calls.append("click")
        if self.fail:
            raise self.fail
        self.clicked += 1

    def is_disabled(self, timeout=None) -> bool:
        self.calls.append("is_disabled")
        if self.disabled_for:
            self.disabled_for -= 1
            return True
        return self.disabled


class FakePage:
    url = "https://portal.azure.com/#@contoso.onmicrosoft.com/view/Two?x=1"
    viewport_size = None             # visible_in() then skips the window-column check

    def __init__(self, closed: bool = False, goto_fails: Exception | None = None) -> None:
        self.closed = closed
        self.goto_fails = goto_fails
        self.visited: list[str] = []     # every address goto() was given
        self.main_frame = Screen()       # an empty screen unless a test patches run.all_frames
        self.frames = [self.main_frame]
        self.now = 0.0                   # seconds; only waits move it (FindOnScreenTests' clock)

    def is_closed(self) -> bool:
        return self.closed

    def goto(self, url, wait_until=None) -> None:
        self.visited.append(url)
        if self.goto_fails:
            raise self.goto_fails
        self.url = url

    def wait_for_timeout(self, ms) -> None:
        self.now += ms / 1000

    def screenshot(self, path, full_page=False) -> None:
        pass


class DecisionRecordingTests(RunnerTestCase):
    STEP = {"id": "9.9.1", "title": "One", "portal": True, "expected": "Group shows", "images": [],
            "items": [{"kind": "action", "labels": ["+ New group"], "line": 3}]}

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n\n2. Click **+ New group**\n", encoding="utf-8")

    def act(self, answers, element, label="+ New group", exact=None, extra=()):
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers(*answers))
        candidates = [run.Candidate("button", "New group"), run.Candidate("link", "Groups"),
                      run.Candidate("button", "Delete group"), run.Candidate("link", "Contoso Ltd"),
                      run.Candidate("menuitem", "Bulk delete"), *extra]
        clock = iter(range(0, 1_000_000, 1))               # 1 s passes between every look at the clock
        with mock.patch.object(run, "find_exact", return_value=exact), \
                mock.patch.object(run, "candidates_on_screen", return_value=candidates), \
                mock.patch.object(run.time, "monotonic", lambda: next(clock)), \
                mock.patch.object(run, "find_by_name", return_value=element) as self.find_by_name:
            record = self.quietly(lambda: r.act_on_label(self.STEP, self.STEP["items"][0], label))
        saved = json.loads((self.tmp / "rec.json").read_text(encoding="utf-8"))
        return record, saved["steps"].get("9.9.1", {}).get("labels", {})

    def test_the_element_is_scrolled_into_view_before_the_click(self) -> None:
        element = FakeElement()
        self.act(["1"], element)
        self.assertEqual(element.calls, ["scroll", "is_disabled", "click"])
        self.assertEqual(self.find_by_name.call_args.args[1:], ("button", "New group"))   # plain: exact

    def test_a_rejected_element_inside_or_named_after_a_list_entry_is_not_recorded(self) -> None:
        # #317: the redacted copy of the candidates keeps aria_lines' flags, so a row's link and a
        # button named after a row (example data: fictional users) stay out of the recording.
        _, labels = self.act(["1"], FakeElement(), extra=[
            run.Candidate("link", "Illidan Stormrage", in_entry=True),
            run.Candidate("button", "Remove Khadgar Archmage", names_entry=True)])
        rejected = labels["+ New group"]["rejected"]
        self.assertIn('link "Groups"', rejected)
        self.assertNotIn('link "Illidan Stormrage"', rejected)
        self.assertNotIn('button "Remove Khadgar Archmage"', rejected)

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

    def test_an_element_that_stays_disabled_is_unknown_without_a_click(self) -> None:
        element = FakeElement(disabled=True)
        record, labels = self.act(["1"], element)
        self.assertEqual((record["outcome"], record["observed"]), ("unknown", "disabled: 'New group'"))
        self.assertEqual((element.clicked, labels), (0, {}))
        self.assertGreater(element.calls.count("is_disabled"), 1)               # asked again until the deadline
        self.assertNotIn("click", element.calls)

    def test_an_element_greyed_out_while_the_blade_loads_is_clicked_once_enabled(self) -> None:
        element = FakeElement(disabled_for=3)
        record, _ = self.act(["1"], element)
        self.assertEqual((record["outcome"], element.clicked), ("drift", 1))     # 'New group' for '+ New group'
        self.assertEqual(element.calls, ["scroll"] + ["is_disabled"] * 4 + ["click"])

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
                     "## stale screenshots (1)", "- step 9.9.2: images/Step-9.9.2.png", "## proposed edits (1)",
                     "guide.md:3", "## no portal part (1)\n- step 9.9.3: Check"):
            self.assertIn(line, summary)
        self.assertNotIn("unreadable", summary)                         # no width limit on screenshots
        self.assertIn("## unknown (1)\n- step 9.9.2 field **Group type**: ambiguous: 2 visible elements match\n\n"
                      "## unconfirmed searches (0)\n- none\n\n## skipped (1)", summary)

    def test_finish_tells_a_step_skipped_after_it_failed_from_one_skipped_on_resume(self) -> None:
        self.add("action", None, outcome="skipped", skippedBecause="9.9.2", observed="no spare licences")
        self.add("action", None, outcome="skipped", skippedBecause="9.9.2")
        self.assertEqual(self.quietly(self.r.finish), 0)        # a skip is no finding of its own
        summary = (self.r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## skipped (2)\n- step 9.9.2 skipped after it failed: no spare licences\n"
                      "- step 9.9.2 skipped on resume\n", summary)

    def test_finish_lists_unconfirmed_searches_after_unknown_without_counting_them(self) -> None:
        observed = run.search_outcome("Owner", before=True, after=True)[1]
        self.add("search", "Owner", outcome="match", observed=observed)
        self.add("search", "Reader", outcome="match", observed="Reader")          # confirmed: not listed
        self.assertEqual(self.quietly(self.r.finish), 0)
        summary = (self.r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## unknown (0)\n- none\n\n## unconfirmed searches (1)\n"
                      f"- step 9.9.2 **Owner**: {observed}\n\n## skipped (0)", summary)
        self.assertNotIn("**Reader**", summary)

    def test_finish_lists_a_drift_whose_edit_is_not_proposed_with_the_reason(self) -> None:
        self.add("action", "Microsoft Entra ID", outcome="drift", severity="misleading",
                 observed="[tenantname] | Overview", notProposed="the Portal's name holds tenant data ([tenantname])")
        # A record a run wrote before #211 has no 'notProposed': not listed, as before.
        old = self.r.new_record({"id": "9.9.2"}, "action", "Groups")
        old.pop("notProposed", None)
        old.update(outcome="drift", severity="cosmetic", observed="groups")
        self.r.records.append(old)
        self.assertEqual(self.quietly(self.r.finish), 0)
        summary = (self.r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## proposed edits (0)\n- none\n\n## not proposed (1)\n- step 9.9.2 action "
                      "**Microsoft Entra ID**: observed '[tenantname] | Overview': the Portal's name holds tenant "
                      "data ([tenantname])\n\nScreenshots", summary)

    def test_tenant_name_is_an_optional_argument_the_redactor_uses(self) -> None:
        base = ["--steps", "s", "--recording", "r", "--log-dir", "l", "--run-id", "i", "--tenant-id", "t",
                "--tenant-domain", "contoso.onmicrosoft.com", "--state", "st", "--auth-state", "a"]
        self.assertEqual(run.parse_args(base).tenant_name, "")
        args = self.args(tenant_name="Contoso Ltd")
        r = ScriptedRunner(None, STEPS, self.recording, args, ask=Answers())
        self.assertEqual(r.redactor.redact("Contoso Ltd"), "[tenantname]")

    def test_finish_says_none_for_empty_sections_and_caps_the_exit_code(self) -> None:
        self.assertEqual(self.quietly(self.r.finish), 0)
        summary = (self.r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## proposed edits (0)\n- none\n\n## not proposed (0)\n- none\n", summary)
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
        r = self.runner(answers=["y", ""], resume=True, run_id="second", state=state)
        self.assertEqual(r.run_dir, self.tmp / "logs" / "first")
        self.assertEqual(self.quietly(lambda: r.run(state)), 1)
        self.assertIn("- step 9.9.4 action **Missing button**: not found", self.summary())
        self.assertFalse((self.tmp / "logs" / "second").exists())
        self.assertEqual(self.state()["runId"], "first")

    def test_a_step_done_by_hand_keeps_its_findings_across_a_stop(self) -> None:
        state = self.stopped_run(answers=["c"], unknown={"9.9.4"}, interrupt={"9.9.5"})
        self.assertEqual((state["completed"], state["inFlight"]), (["9.9.1", "9.9.2", "9.9.4"], "9.9.5"))
        r = self.runner(answers=["n", ""], resume=True, run_id="second", state=state)
        self.assertEqual(self.quietly(lambda: r.run(state)), 1)
        summary = self.summary()
        self.assertIn("- step 9.9.4 action **Missing button**: not found", summary)
        self.assertIn("## done by hand (1)\n- step 9.9.4", summary)

    def test_a_step_skipped_after_it_failed_is_passed_over_and_listed_after_a_stop(self) -> None:
        state = self.stopped_run(answers=["s", "no spare licences", "q"], unknown={"9.9.2", "9.9.4"})
        self.assertEqual((state["completed"], state["inFlight"]), (["9.9.1", "9.9.2"], "9.9.4"))
        r = self.runner(answers=["y", ""], resume=True, run_id="second", state=state)
        self.assertEqual(self.quietly(lambda: r.run(state)), 2)
        self.assertEqual(r.ran, ["9.9.5"])
        self.assertTrue(self.state()["finished"])
        summary = self.summary()
        self.assertIn("## unknown (2)", summary)
        self.assertIn("## skipped (1)\n- step 9.9.2 skipped after it failed: no spare licences\n", summary)

    def test_a_redone_step_replaces_its_stopped_attempt(self) -> None:
        state = self.stopped_run(answers=["q"], unknown={"9.9.4"})
        r = self.runner(answers=["n", ""], resume=True, run_id="second", state=state)
        self.assertEqual(self.quietly(lambda: r.run(state)), 0)
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])
        results = (self.tmp / "logs" / "first" / "results.jsonl").read_text(encoding="utf-8")
        self.assertIn('"outcome": "unknown"', results)      # the file keeps both attempts

    def test_a_cut_short_last_line_is_skipped(self) -> None:
        folder = self.tmp / "logs" / "first"
        folder.mkdir(parents=True)
        record = self.runner().new_record({"id": "9.9.1"}, "action", "OK")
        record.update(outcome="match")
        (folder / "results.jsonl").write_text(json.dumps(record) + '\n{"step": "9.9', encoding="utf-8")
        out = io.StringIO()
        with redirect_stdout(out):
            r = self.runner(resume=True, state={"runId": "first", "lab": LAB, "completed": [], "inFlight": None})
        self.assertEqual([x["step"] for x in r.records], ["9.9.1"])
        self.assertEqual(out.getvalue(), "")        # no warning: a crash leaves such a line


class RedoAcrossResumesTests(RunnerTestCase):
    """A step redone after -Resume counts only its last attempt, however often the run is resumed
    (#222): the redo appends a marker to results.jsonl before its new attempt, and a later resume
    drops the step's records that come before its last marker. The marker itself is never a
    finding."""

    FINDING = "- step 9.9.2 action **Missing button**: not found"

    def part(self, run_id: str, state: dict | None = None, **script) -> tuple[ScriptedRunner, int, dict]:
        """One part of the run: a new run when `state` is None, else a resume of it. Returns the
        runner, its exit code (ABORTED for Ctrl+C, as main() returns it) and the state it left."""
        r = self.runner(run_id=run_id, resume=state is not None, state=state, **script)
        try:
            code = self.quietly(lambda: r.run(state))
        except KeyboardInterrupt:
            code = run.ABORTED
        return r, code, self.state()

    def lines(self, run_id: str) -> list[dict]:
        text = (self.tmp / "logs" / run_id / "results.jsonl").read_text(encoding="utf-8")
        return [json.loads(line) for line in text.splitlines()]

    def summary(self, run_id: str) -> str:
        return (self.tmp / "logs" / run_id / "summary.md").read_text(encoding="utf-8")

    def test_a_redone_step_completed_then_a_second_resume_counts_each_finding_once(self) -> None:
        # 9.9.2 fails, q; -Resume, n: the redo goes through, or fails again and is done by hand (c)
        # or skipped (s); 9.9.4 fails, q; -Resume, y. Before #222 the last part counted 9.9.2's
        # first attempt again: 2 for 1 and 3 for 2.
        for how, answers, unknown, code, by_hand, skipped in (
                ("succeeds", ["n", "", "q"], {"9.9.4"}, 1, 0, []),
                ("c", ["n", "", "c", "q"], {"9.9.2", "9.9.4"}, 2, 1, []),
                ("s", ["n", "", "s", "no spare licences", "q"], {"9.9.2", "9.9.4"}, 2, 0,
                 ["- step 9.9.2 skipped after it failed: no spare licences"])):
            with self.subTest(redo=how):
                run_id = f"resumed-{how}"
                _, stopped, state = self.part(run_id, answers=["q"], unknown={"9.9.2"})
                self.assertEqual((stopped, state["inFlight"]), (run.ABORTED, "9.9.2"))
                second, stopped, state = self.part(run_id, state, answers=answers, unknown=unknown)
                self.assertEqual((stopped, state["inFlight"]), (run.ABORTED, "9.9.4"))
                self.assertEqual(second.ran, ["9.9.2", "9.9.4"])
                third, exit_code, state = self.part(run_id, state, answers=["y", ""])
                self.assertEqual(third.ran, ["9.9.5"])
                self.assertTrue(state["finished"])
                self.assertEqual(exit_code, code)
                summary = self.summary(run_id)
                self.assertIn(f"## unknown ({code})\n", summary)
                self.assertEqual(summary.count(self.FINDING), code - 1)
                self.assertIn("- step 9.9.4 action **Missing button**: not found", summary)
                self.assertIn(f"## done by hand ({by_hand})\n", summary)
                self.assertIn("\n".join([f"## skipped ({len(skipped)})", *(skipped or ["- none"])]) + "\n", summary)
                self.assertNotIn("redo", summary)
                # The file keeps both attempts, with the marker between them.
                kinds = [(x["kind"], x["outcome"]) for x in self.lines(run_id) if x["step"] == "9.9.2"]
                self.assertEqual(kinds[:2], [("action", "unknown"), ("redo", None)])

    def test_the_last_marker_wins_when_a_step_is_redone_twice(self) -> None:
        _, _, state = self.part("twice", answers=["q"], unknown={"9.9.2"})
        _, _, state = self.part("twice", state, answers=["n", "", "q"], unknown={"9.9.2"})
        self.assertEqual(state["inFlight"], "9.9.2")
        _, _, state = self.part("twice", state, answers=["n", "", "q"], unknown={"9.9.4"})
        self.assertEqual(state["inFlight"], "9.9.4")
        _, code, _ = self.part("twice", state, answers=["y", ""])
        self.assertEqual(code, 1)
        self.assertNotIn(self.FINDING, self.summary("twice"))
        self.assertEqual([x["step"] for x in self.lines("twice") if x["kind"] == "redo"], ["9.9.2", "9.9.2"])

    def test_the_marker_survives_scrubbing_and_is_never_a_record(self) -> None:
        _, _, state = self.part("scrub", answers=["q"], unknown={"9.9.2"})
        r, _, state = self.part("scrub", state, answers=["n", "", "q"], unknown={"9.9.4"})
        marker = next(x for x in self.lines("scrub") if x["kind"] == "redo")
        self.assertEqual(r.scrubbed(dict(marker)), marker)
        self.assertEqual((marker["step"], marker["runId"], marker["observed"], marker["screenshot"]),
                         ("9.9.2", "scrub", None, None))
        self.assertNotIn("redo", [x["kind"] for x in r.records])
        resumed = self.runner(run_id="scrub", resume=True, state=state)
        self.assertNotIn("redo", [x["kind"] for x in resumed.records])
        self.assertEqual([(x["step"], x["outcome"]) for x in resumed.records], [("9.9.4", "unknown")])

    def test_a_step_run_for_the_first_time_writes_no_marker(self) -> None:
        self.part("plain", answers=["s", "no spare licences"], unknown={"9.9.2"})
        self.assertEqual([x for x in self.lines("plain") if x["kind"] == "redo"], [])
        # A redo of a step whose stopped attempt left no record has nothing to replace.
        state = {"runId": "plain", "lab": LAB, "completed": ["9.9.1", "9.9.2", "9.9.4"], "inFlight": "9.9.5"}
        r, code, _ = self.part("plain", state, answers=["n", ""])
        self.assertEqual((r.ran, code), (["9.9.5"], 1))
        self.assertEqual([x for x in self.lines("plain") if x["kind"] == "redo"], [])

    def write_results(self, run_id: str, *records: dict) -> None:
        folder = self.tmp / "logs" / run_id
        folder.mkdir(parents=True)
        (folder / "results.jsonl").write_text("".join(json.dumps(x) + "\n" for x in records), encoding="utf-8")

    def record(self, step: str, kind: str, **fields) -> dict:
        record = {"runId": "x", "at": "2026-10-11T10:00:00", "lab": LAB, "step": step, "kind": kind,
                  "label": "Missing button" if kind == "action" else None, "outcome": None, "severity": None,
                  "category": None, "skippedBecause": None, "observed": None, "proposedEdit": None,
                  "screenshot": f"Step-{step}.png" if kind == "action" else None}
        record.update(fields)
        return record

    def test_a_marker_without_later_records_drops_the_step_s_earlier_attempt(self) -> None:
        # A run stopped right after the marker (Ctrl+C before the redo wrote anything): the
        # attempt in flight is the redo, and it found nothing yet.
        self.write_results("cut", self.record("9.9.1", "action", outcome="match"),
                           self.record("9.9.2", "action", outcome="unknown", observed="not found"),
                           self.record("9.9.2", "redo"))
        state = {"runId": "cut", "lab": LAB, "completed": ["9.9.1"], "inFlight": "9.9.2"}
        r, code, _ = self.part("cut", state, answers=["y", ""])
        self.assertEqual([x["step"] for x in r.records if x["step"] in ("9.9.1", "9.9.2")], ["9.9.1"])
        self.assertEqual(code, 0)
        self.assertIn("## unknown (0)\n", self.summary("cut"))
        self.assertNotIn("redo", self.summary("cut"))

    def test_a_results_file_without_markers_is_read_as_before(self) -> None:
        # Written before #222: both attempts of a redone step, no marker. Every record counts.
        self.write_results("old", self.record("9.9.1", "action", outcome="match"),
                           self.record("9.9.2", "action", outcome="unknown", observed="not found"),
                           self.record("9.9.2", "action", outcome="unknown", observed="not found"),
                           self.record("9.9.4", "action", outcome="unknown", observed="not found"))
        state = {"runId": "old", "lab": LAB, "completed": ["9.9.1", "9.9.2"], "inFlight": "9.9.4"}
        r, code, _ = self.part("old", state, answers=["y", ""])
        self.assertEqual(len([x for x in r.records if x["outcome"] == "unknown"]), 3)
        self.assertEqual(code, 3)
        self.assertEqual(self.summary("old").count(self.FINDING), 2)

    def test_a_line_that_is_no_record_of_a_step_is_skipped_with_a_warning(self) -> None:
        # Valid JSON, but not an object, or one without a step id: skipped as a cut-short line is,
        # and said once per line, without its content (it was never scrubbed).
        folder = self.tmp / "logs" / "odd"
        folder.mkdir(parents=True)
        lines = [json.dumps(self.record("9.9.1", "action", outcome="match")), "3", '["9.9.2"]', '"text"',
                 "null", '{"kind": "action", "outcome": "unknown"}', '{"step": ["9.9.2"], "kind": "redo"}',
                 json.dumps(self.record("9.9.2", "action", outcome="unknown", observed="not found"))]
        (folder / "results.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
        state = {"runId": "odd", "lab": LAB, "completed": ["9.9.1", "9.9.2"], "inFlight": None}
        out = io.StringIO()
        with redirect_stdout(out):
            r = self.runner(run_id="odd", resume=True, state=state)
        self.assertEqual([(x["step"], x["outcome"]) for x in r.records], [("9.9.1", "match"), ("9.9.2", "unknown")])
        warnings = out.getvalue().splitlines()
        self.assertEqual(warnings, [f"results.jsonl line {n}: no record of a step; skipped." for n in range(2, 8)])
        self.assertNotIn("text", out.getvalue())
        with redirect_stdout(io.StringIO()):
            _, code, _ = self.part("odd", state, answers=[""])
        self.assertEqual(code, 1)

    def test_a_line_without_a_field_the_summary_reads_is_skipped_with_a_warning(self) -> None:
        # A step id but no outcome (or any other field finish() reads): skipped, so the summary
        # neither raises KeyError nor counts it.
        for field in ("kind", "label", "outcome", "severity", "category", "skippedBecause", "observed"):
            with self.subTest(field=field):
                partial = self.record("9.9.2", "action", outcome="unknown", observed="not found")
                del partial[field]
                run_id = f"partial-{field}"
                self.write_results(run_id, self.record("9.9.1", "action", outcome="match"), partial,
                                   self.record("9.9.4", "action", outcome="unknown", observed="not found"))
                state = {"runId": run_id, "lab": LAB, "completed": ["9.9.1", "9.9.2", "9.9.4"], "inFlight": None}
                out = io.StringIO()
                with redirect_stdout(out):
                    r = self.runner(run_id=run_id, resume=True, state=state)
                self.assertEqual(out.getvalue(), "results.jsonl line 2: no record of a step; skipped.\n")
                self.assertEqual([x["step"] for x in r.records], ["9.9.1", "9.9.4"])
                with redirect_stdout(io.StringIO()):
                    _, code, _ = self.part(run_id, state, answers=[""])
                self.assertEqual(code, 1)
                self.assertNotIn(self.FINDING, self.summary(run_id))

    def test_a_run_that_does_not_start_writes_no_marker(self) -> None:
        # 9.9.2 fails (q) and is skipped in the recording; -Resume, then closed input at the view
        # prompt (254). The skip is taken back and the run resumed: 9.9.2's unknown still counts.
        _, _, state = self.part("refused", answers=["q"], unknown={"9.9.2"})
        self.recording["steps"].setdefault("9.9.2", {})["skip"] = "Optional"
        _, code, state = self.part("refused", state, answers=[])
        self.assertEqual(code, run.NOT_STARTED)
        self.assertEqual([x["kind"] for x in self.lines("refused")], ["action"])
        del self.recording["steps"]["9.9.2"]["skip"]
        _, code, _ = self.part("refused", state, answers=["y", ""])
        self.assertEqual(code, 1)
        self.assertIn(self.FINDING, self.summary("refused"))


class RunLogRedactionTests(RunnerTestCase):
    """results.jsonl and summary.md keep what the failure prompt shows (#212): the first line of
    an error, without Playwright's call log, redacted, with no object id and no typed secret."""

    DOMAIN = "contoso.onmicrosoft.com"
    OBJECT_ID = "9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f"
    PASSWORD = "LoveAzeroth!2004"           # the guide's own value for the 'Password' field
    GENERATED = "Qx7!fake-generated"        # what an auto-generated password field holds
    CALL_LOG = ('\nCall log:\n  - waiting for get_by_role("option", name="malfurion.stormrage@contoso.onmicrosoft.com")\n'
                f'    - locator resolved to <input type="password" value="{GENERATED}"/>\n')
    RAW = f"LookupError: option 'malfurion.stormrage@{DOMAIN}' not found in group {OBJECT_ID}{CALL_LOG}"
    SHOWN = "LookupError: option 'malfurion.stormrage@[tenantdomain]' not found in group <id>"

    def results_text(self, run_id: str = "test") -> str:
        return (self.tmp / "logs" / run_id / "results.jsonl").read_text(encoding="utf-8")

    def summary(self, run_id: str = "test") -> str:
        return (self.tmp / "logs" / run_id / "summary.md").read_text(encoding="utf-8")

    def unknown(self, r: run.Runner, observed: str) -> dict:
        record = r.new_record({"id": "9.9.2"}, "field", "User principal name")
        record.update(outcome="unknown", observed=observed)
        return record

    def assert_no_leak(self, *texts: str) -> None:
        for text in texts:
            # The element's HTML is in the call log; in a first line its value is masked.
            for leak in (self.DOMAIN, self.OBJECT_ID, self.PASSWORD, self.GENERATED, "Call log", "locator resolved"):
                self.assertNotIn(leak, text)

    def test_an_observed_error_is_written_redacted_and_on_one_line(self) -> None:
        r = self.runner()
        r.write(self.unknown(r, self.RAW))
        self.assertEqual(json.loads(self.results_text().splitlines()[-1])["observed"], self.SHOWN)
        self.quietly(r.finish)
        self.assertIn(f"## unknown (1)\n- step 9.9.2 field **User principal name**: {self.SHOWN}\n", self.summary())
        out = io.StringIO()
        with redirect_stdout(out):
            r.ask_after_failure({"id": "9.9.2"})        # input closed: 'e'
        self.assertIn(f"  field 'User principal name': unknown: {self.SHOWN}\n", out.getvalue())
        self.assert_no_leak(self.results_text(), self.summary())

    def test_a_timeout_filling_a_password_leaks_neither_the_password_nor_the_html(self) -> None:
        item = {"kind": "field", "label": "Password", "value": self.PASSWORD, "line": 5}
        steps = dict(STEPS, steps=[dict(STEPS["steps"][0], items=[item])] + STEPS["steps"][1:])
        timeout = type("TimeoutError", (run.PlaywrightError,), {})
        # As Playwright 1.63 raises it for a fill() that never finds an editable element.
        raised = ('Locator.fill: Timeout 8000ms exceeded.\nCall log:\n'
                  '  - waiting for get_by_role("textbox", name="Password")\n'
                  f'    - locator resolved to <input id="p" type="password" value="{self.GENERATED}"/>\n'
                  f'    - fill("{self.PASSWORD}")\n  - attempting fill action\n'
                  '    2 × waiting for element to be visible, enabled and editable\n')
        # A first line that carries the typed value and the element itself.
        in_first_line = (f'Locator.fill: cannot type "{self.PASSWORD}" into '
                         f'<input type="password" value="{self.GENERATED}">\nCall log:\n  - fill("{self.PASSWORD}")\n')
        for run_id, message, shown in (
                ("timeout", raised, "TimeoutError: Locator.fill: Timeout 8000ms exceeded."),
                ("first", in_first_line,
                 'TimeoutError: Locator.fill: cannot type "[secret]" into <input type="password" value="[value]">')):
            with self.subTest(run_id=run_id):
                r = run.Runner(FakePage(), steps, self.recording, self.args(run_id=run_id), ask=Answers())
                field = ScreenNode(tag="input", fill_fail=timeout(message))
                with mock.patch.object(run, "all_frames", lambda page: [Screen(("textbox", "Password", field))]), \
                        mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                        mock.patch.object(run, "candidates_on_screen", return_value=[]):
                    record = self.quietly(lambda: r.act_on_label(steps["steps"][0], item, "Password", self.PASSWORD))
                r.write(record)
                self.quietly(r.finish)
                self.assertEqual(record["observed"], shown)
                self.assertIn(f"- step 9.9.1 field **Password**: {shown}\n", self.summary(run_id))
                self.assert_no_leak(self.results_text(run_id), self.summary(run_id))

    def test_a_proposed_edit_refuses_a_new_label_with_data_and_never_redacts_the_guides_text(self) -> None:
        (self.tmp / "guide.md").write_text("# Lab\n\n2. In the Contoso directory, click **+ New group**\n",
                                           encoding="utf-8")
        r = self.runner()
        edit = r.proposed_edit(3, "+ New group", "New group")
        # 'Contoso' is the tenant prefix, but here it is the guide's word: no '[yourtenant]' for it.
        self.assertEqual(edit, {"line": 3, "old": "2. In the Contoso directory, click **+ New group**",
                                "new": "2. In the Contoso directory, click **New group**"})
        # A new label that holds tenant or personal data once scrubbed is no edit at all (#211).
        for name in (f"New group {self.OBJECT_ID}", "Contoso Ltd", f"admin@{self.DOMAIN}", "someone@fabrikam.com",
                     "[tenantname] | Overview", "${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}"):
            with self.subTest(name=name):
                self.assertIsNone(r.proposed_edit(3, "+ New group", name))

    def test_the_aria_files_mask_ids_and_secret_values_and_keep_every_line(self) -> None:
        r = self.runner()
        # As aria_snapshot() writes a text field: its value after the colon, an auto-generated
        # password's among them.
        tree = ('- listbox:\n  - option "malfurion.stormrage@contoso.onmicrosoft.com"\n'
                f'  - link "Group {self.OBJECT_ID}"\n  - textbox "Password": {self.GENERATED}\n'
                f'  - textbox "Client secret value" [disabled]: {self.PASSWORD}\n  - textbox "Name": bob')
        self.quietly(lambda: r.save_search_tree({"id": "9.9.1"}, tree))
        self.assertEqual((r.run_dir / "search-9.9.1.aria.txt").read_text(encoding="utf-8"),
                         '- listbox:\n  - option "malfurion.stormrage@[tenantdomain]"\n  - link "Group <id>"\n'
                         '  - textbox "Password": [secret]\n  - textbox "Client secret value" [disabled]: [secret]\n'
                         '  - textbox "Name": bob\n')
        outline = [("heading", f"Group {self.OBJECT_ID}"), ("textbox", "Password"), ("link", f"Users of {self.DOMAIN}")]
        self.quietly(lambda: r.save_blade_outline({"id": "9.9.1"}, {"line": 7}, "Missing", outline))
        self.assertEqual((r.run_dir / "blade-9.9.1-7.aria.txt").read_text(encoding="utf-8"),
                         'heading "Group <id>"\ntextbox "Password"\nlink "Users of [tenantdomain]"\n')

    def test_the_aria_files_mask_the_signed_in_account_and_credentials(self) -> None:
        r = self.runner()
        tree = ('- banner:\n  - button "Account manager for marcin.b@fabrikam.example"\n'
                '  - textbox "Primary connection string": DefaultEndpointsProtocol=https;AccountKey=abc==\n'
                '  - text: "SharedAccessKey=xyz="')
        self.quietly(lambda: r.save_search_tree({"id": "9.9.1"}, tree))
        self.assertEqual((r.run_dir / "search-9.9.1.aria.txt").read_text(encoding="utf-8"),
                         '- banner:\n  - button "Account manager for <email>"\n'
                         '  - textbox "Primary connection string": [secret]\n  - text: "SharedAccessKey=[secret]"\n')

    def test_a_search_tree_that_could_not_be_read_keeps_the_error_s_first_line(self) -> None:
        class Dropdown:
            def aria_snapshot(self, timeout=None) -> str:
                raise run.PlaywrightError('Locator.aria_snapshot: Timeout 2000ms exceeded.\nCall log:\n'
                                          '  - waiting for locator("#results")\n'
                                          '    - locator resolved to <div title="marcin.b@fabrikam.example">\n')

        tree = run.tree_of(Dropdown(), None)
        self.assertEqual(tree, f"# the search results: no snapshot ({run.PlaywrightError.__name__}: "
                               "Locator.aria_snapshot: Timeout 2000ms exceeded.)")

    def test_the_summary_scrubs_a_record_that_did_not_come_through_write(self) -> None:
        r = self.runner()
        r.records.append(self.unknown(r, self.RAW))        # as a future path that forgets write() would
        self.quietly(r.finish)
        self.assertIn(f"- step 9.9.2 field **User principal name**: {self.SHOWN}\n", self.summary())
        self.assert_no_leak(self.summary())

    def test_the_summary_names_the_run_folder_without_the_user_s_path(self) -> None:
        r = self.runner()                                   # its log folder is under repo_root
        self.quietly(r.finish)
        self.assertTrue(self.summary().endswith("\nScreenshots and results: logs/test\n"))
        elsewhere = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(elsewhere, ignore_errors=True))
        r = self.runner(log_dir=elsewhere / "logs")
        self.quietly(r.finish)
        summary = (elsewhere / "logs" / "test" / "summary.md").read_text(encoding="utf-8")
        self.assertTrue(summary.endswith("\nScreenshots and results: test\n"))
        self.assertNotIn(str(elsewhere), summary)

    def test_the_candidate_list_is_shown_scrubbed_and_picked_by_number(self) -> None:
        item = {"kind": "action", "labels": ["Owner"], "line": 3}
        step = {"id": "9.9.1", "title": "One", "items": [item], "images": []}
        (self.tmp / "guide.md").write_text("# Lab\n\n2. Click **Owner**\n", encoding="utf-8")
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers("2"))
        candidates = [run.Candidate("link", f"Group {self.OBJECT_ID}"),
                      run.Candidate("button", "Account manager for marcin.b@fabrikam.example"),
                      run.Candidate("link", f"malfurion@{self.DOMAIN}")]
        out = io.StringIO()
        with mock.patch.object(run, "find_exact", return_value=None), \
                mock.patch.object(run, "candidates_on_screen", return_value=candidates), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "find_by_name", return_value=FakeElement()) as find, redirect_stdout(out):
            record = r.act_on_label(step, item, "Owner")
        shown = out.getvalue()
        for line in ("Group <id>", "Account manager for <email>", "malfurion@[tenantdomain]"):
            self.assertIn(line, shown)
        self.assert_no_leak(shown)
        self.assertNotIn("fabrikam", shown)
        # The number picks the candidate the Portal shows, looked up by its name.
        self.assertEqual(record["outcome"], "drift")
        self.assertEqual(find.call_args.args[2], "Account manager for marcin.b@fabrikam.example")

    REASK = ("That text holds an id, an address or a secret, which the recording cannot keep; "
             "type a shorter text, or press Enter if it is not observable.")

    def check_result(self, *answers: str) -> tuple[run.Runner, dict, str, list[str]]:
        """check_result with `answers` at its prompt: the runner, the step's entry, what it
        printed, and every text it looked for on screen."""
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers(*answers))
        entry = r.step_entry({"id": "9.9.1"})
        looked_for: list[str] = []
        out = io.StringIO()
        with mock.patch.object(run, "text_on_screen", lambda page, text: looked_for.append(text) or True), \
                redirect_stdout(out):
            r.check_result({"id": "9.9.1", "expected": "The group shows"}, entry)
        return r, entry, out.getvalue(), looked_for

    def test_a_result_text_with_an_id_or_an_address_is_asked_again_and_never_stored(self) -> None:
        r, entry, out, looked_for = self.check_result(
            f"Group {self.OBJECT_ID} created", "Owner marcin.b@fabrikam.example",
            f"Owner malfurion.stormrage@{self.DOMAIN}")
        self.assertEqual(len(r.ask.prompts), 3)
        self.assertEqual(out.count(self.REASK), 2)
        # Tenant data is a token restore() gives back: the run looks for what is on screen.
        self.assertEqual(entry["result"], {"text": "Owner malfurion.stormrage@[tenantdomain]"})
        self.assertEqual(looked_for, [f"Owner malfurion.stormrage@{self.DOMAIN}"])
        saved = (self.tmp / "rec.json").read_text(encoding="utf-8")
        for kept_out in (self.OBJECT_ID, "fabrikam", "<id>", "<email>", "[secret]", self.DOMAIN):
            self.assertNotIn(kept_out, saved)

    def test_a_result_text_that_cannot_be_kept_then_enter_or_closed_input_stores_nothing(self) -> None:
        _, entry, out, looked_for = self.check_result(f"Group {self.OBJECT_ID} created", "")
        self.assertEqual((entry["result"], entry.get("asked"), looked_for), (None, ["result"], []))
        self.assertIn(self.REASK, out)
        self.recording["steps"]["9.9.1"].pop("asked")           # the same recording, not asked yet
        r, entry, _, looked_for = self.check_result(f"Group {self.OBJECT_ID} created")     # then EOF
        self.assertEqual((entry["result"], entry.get("asked"), looked_for), (None, None, []))   # asked next time
        self.assertEqual(len(r.ask.prompts), 2)

    def test_a_resumed_run_reloads_the_records_as_written_and_cleans_older_ones(self) -> None:
        r = self.runner(run_id="first")
        r.write(self.unknown(r, self.RAW))
        drift = r.new_record({"id": "9.9.2"}, "action", "+ New group")
        drift.update(outcome="drift", severity="cosmetic", observed="[tenantname] | Overview")
        r.write(drift)
        written = [json.loads(line) for line in self.results_text("first").splitlines()]
        # A line a run wrote before #212, as the first lab 1.1 run left it.
        with (self.tmp / "logs" / "first" / "results.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(self.unknown(r, self.RAW)) + "\n")
        state = {"runId": "first", "lab": LAB, "completed": [], "inFlight": None}
        resumed = self.runner(resume=True, state=state, run_id="second")
        self.assertEqual(resumed.records[:2], written)                     # not redacted twice
        self.assertEqual(resumed.records[2]["observed"], self.SHOWN)
        self.quietly(resumed.finish)
        summary = self.summary("first")
        again = self.runner(resume=True, state=state, run_id="third")
        self.assertEqual(again.records, resumed.records)
        self.quietly(again.finish)
        self.assertEqual(self.summary("first"), summary)
        self.assertIn("observed '[tenantname] | Overview'", summary)
        self.assert_no_leak(summary)


class ResumeViewTests(RunnerTestCase):
    """A resumed run's browser is new (#206): before the first step that runs, the Portal is brought
    to the view that step starts from, opened by the run when the recording keeps a view it can
    open, and named with the reason otherwise; and a step done by hand leaves a view too."""

    IN_FLIGHT = {"lab": LAB, "completed": ["9.9.1"], "inFlight": "9.9.2", "finished": False}

    def resume(self, answers, page=None, state=None) -> tuple[ScriptedRunner, str, int]:
        r = self.runner(answers=answers, resume=True, run_id="resume", page=page)
        out = io.StringIO()
        with redirect_stdout(out):
            code = r.run(dict(state or self.IN_FLIGHT))
        return r, out.getvalue(), code

    def test_the_y_answer_says_the_portal_is_brought_to_the_view_the_step_ended_on(self) -> None:
        line = next(text for text in run.Runner.RESUME_PROMPT.splitlines() if text.startswith("  y  "))
        self.assertIn("mark it done, then bring the Portal to the view it ended on", line)
        self.assertNotIn("leave the Portal", run.Runner.RESUME_PROMPT)

    def test_a_view_with_tenant_data_is_opened_restored_and_pinned_to_the_tenant(self) -> None:
        r = self.runner()
        self.assertEqual(r.view_address("https://portal.azure.com/#view/Domains/name/[tenantdomain]"),
                         f"https://portal.azure.com/#@{TENANT_ID}/view/Domains/name/contoso.onmicrosoft.com")

    def test_a_view_that_names_an_object_by_id_or_is_no_portal_view_is_never_opened(self) -> None:
        r = self.runner()
        for view in ("https://portal.azure.com/#view/GroupDetailsMenuBlade/~/Members/groupId/<id>",
                     "https://portal.azure.com/#view/Domains/name/[unknowntoken]",
                     "https://portal.azure.com/#view/Invite/${GUEST}",
                     "https://example.com/#view/One", "http://portal.azure.com/#view/One",
                     "https://portal.azure.com/other#view/One", "https://portal.azure.com/?x=1#view/One",
                     "https://portal.azure.com/#@evil.example/view/One", "https://portal.azure.com/"):
            with self.subTest(view=view):
                self.assertIsNone(r.view_address(view))

    def test_a_view_with_an_object_id_is_named_with_the_reason_and_waited_for(self) -> None:
        self.recording["steps"]["9.9.2"] = {"viewUrl": "https://portal.azure.com/#view/Group/groupId/<id>"}
        r, out, code = self.resume(["y", ""])
        self.assertEqual(code, 0)
        self.assertEqual(r.page.visited, [])
        self.assertIn("Starting at step 9.9.4 (Four). Bring the Portal to the view step 9.9.2 ended on, then "
                      "press Enter (the run cannot open it: it names an object by id, which the recording "
                      "leaves out):\n  https://portal.azure.com/#view/Group/groupId/<id>\n", out)
        self.assertEqual(r.ask.prompts[-1], "> ")
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])

    def test_a_step_without_a_view_is_named_and_waited_for(self) -> None:
        r, out, code = self.resume(["y", ""])          # 9.9.2 has no entry in the recording
        self.assertEqual(code, 0)
        self.assertEqual(r.page.visited, [])
        self.assertIn("No view is recorded for step 9.9.2, the step before it, so the run cannot open it: "
                      "bring the Portal to where step 9.9.2 ends in the guide, then press Enter.", out)
        self.assertEqual(r.ask.prompts[-1], "> ")

    def test_a_view_that_fails_to_open_is_named_with_the_error_and_waited_for(self) -> None:
        self.recording["steps"]["9.9.2"] = {"viewUrl": "https://portal.azure.com/#view/Two"}
        failing = FakePage(goto_fails=run.PlaywrightError(f"net::ERR_ABORTED at https://portal.azure.com/#@{TENANT_ID}/x\nlog"))
        r, out, code = self.resume(["y", ""], page=failing)
        self.assertEqual(code, 0)
        self.assertIn("Bring the Portal to the view step 9.9.2 ended on, then press Enter (the run cannot "
                      "open it: opening it failed: net::ERR_ABORTED at https://portal.azure.com/#@[tenantid]/x):\n"
                      "  https://portal.azure.com/#view/Two\n", out)
        self.assertNotIn(TENANT_ID, out)
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])

    def test_a_view_that_fails_to_open_is_named_with_the_error_scrubbed(self) -> None:
        # #212: the reason is scrubbed as a record is, ids and other addresses included.
        self.recording["steps"]["9.9.2"] = {"viewUrl": "https://portal.azure.com/#view/Two"}
        failing = FakePage(goto_fails=run.PlaywrightError(
            "Page.goto: net::ERR_ABORTED at https://portal.azure.com/#view/G/groupId/9f8e7d6c-5b4a-4c3d-8e2f-"
            "1a0b9c8d7e6f/owner/marcin.b@fabrikam.example\nCall log:\n  - navigating to \"https://x\"\n"))
        r, out, code = self.resume(["y", ""], page=failing)
        self.assertEqual(code, 0)
        self.assertIn("(the run cannot open it: opening it failed: Page.goto: net::ERR_ABORTED at "
                      "https://portal.azure.com/#view/G/groupId/<id>/owner/<email>):\n", out)
        for leak in ("9f8e7d6c", "fabrikam", "Call log"):
            self.assertNotIn(leak, out)

    def test_the_first_step_of_the_lab_needs_no_view_but_the_person_still_confirms(self) -> None:
        r, out, code = self.resume(["n", ""], state={"lab": LAB, "completed": [], "inFlight": "9.9.1"})
        self.assertEqual(code, 0)
        self.assertEqual(r.page.visited, [])
        self.assertIn("Starting at step 9.9.1 (One). No step of the lab comes before it, so it starts where a new run does", out)
        self.assertEqual(r.ran, ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])

    def test_closed_input_at_the_view_prompt_changes_nothing(self) -> None:
        # The answer to 'did it finish?' is kept only once the Portal is on the next step's view.
        for answer in ("y", "s"):
            with self.subTest(answer=answer):
                r, _, code = self.resume([answer])
                self.assertEqual(code, run.NOT_STARTED)
                self.assertEqual((r.ran, r.records), ([], []))
                self.assertFalse((self.tmp / "state.json").exists())

    def test_nothing_is_brought_back_when_every_step_left_is_done(self) -> None:
        self.recording["steps"].update({"9.9.4": {"skip": "Optional"}, "9.9.5": {"skip": "Optional"}})
        r, _, code = self.resume(["y"])
        self.assertEqual(code, 0)
        self.assertEqual((r.page.visited, r.ask.prompts[1:]), ([], []))
        self.assertTrue(self.state()["finished"])

    def test_a_step_done_by_hand_records_the_view_it_ended_on(self) -> None:
        page = FakePage()
        page.url = f"https://portal.azure.com/#@{TENANT_ID}/view/Done/name/contoso.onmicrosoft.com?tab=1"
        r = self.runner(answers=["c"], failing={"9.9.2"}, page=page)
        self.assertEqual(self.quietly(r.run), 0)
        view = "https://portal.azure.com/#view/Done/name/[tenantdomain]"
        self.assertEqual(self.recording["steps"]["9.9.2"]["viewUrl"], view)
        saved = json.loads((self.tmp / "rec.json").read_text(encoding="utf-8"))
        self.assertEqual(saved["steps"]["9.9.2"]["viewUrl"], view)
        # ... which the next resume opens for the step after it.
        r, out, _ = self.resume([""], state={"lab": LAB, "completed": ["9.9.1", "9.9.2"], "inFlight": None})
        self.assertEqual(r.page.visited, [f"https://portal.azure.com/#@{TENANT_ID}/view/Done/name/contoso.onmicrosoft.com"])
        self.assertNotIn("No view is recorded", out)

    def test_an_opened_view_says_the_blades_before_it_are_not_open(self) -> None:
        self.recording["steps"]["9.9.2"] = {"viewUrl": "https://portal.azure.com/#view/Two"}
        _, out, _ = self.resume(["y", ""])
        self.assertIn("The recording keeps no query string, and the blades the guide opened before it "
                      "are not open: if the step needs them, bring the Portal there by hand first.", out)

    def test_a_view_with_a_token_this_run_cannot_fill_in_names_the_token(self) -> None:
        for token in ("${SKYCRAFT_GUIDE_DRIFT_UNSET}", "[unknowntoken]"):
            with self.subTest(token=token):
                self.recording["steps"]["9.9.2"] = {"viewUrl": f"https://portal.azure.com/#view/Invite/{token}"}
                r, out, _ = self.resume(["y", ""])
                self.assertEqual(r.page.visited, [])
                self.assertIn(f"(the run cannot open it: it keeps {token}, which this run cannot fill in "
                              f"(is the environment variable set?))", out)

    def test_after_s_a_skipped_step_without_a_view_falls_back_to_the_view_it_started_from(self) -> None:
        r, out, code = self.resume(["s", ""])          # 9.9.2 failed before: no view of its own
        self.assertEqual(code, 0)
        self.assertEqual(r.page.visited, [f"https://portal.azure.com/#@{TENANT_ID}/view/One"])
        self.assertIn("Opened the view step 9.9.1 ended on:", out)
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])
        # A step finished with y that has no view is not passed over: it is named instead.
        r, out, _ = self.resume(["y", ""])
        self.assertEqual(r.page.visited, [])
        self.assertIn("No view is recorded for step 9.9.2", out)

    def test_a_step_done_by_hand_off_the_portal_leaves_the_recording_as_it_is(self) -> None:
        self.recording["steps"]["9.9.2"] = {"viewUrl": "https://portal.azure.com/#view/Two"}
        page = FakePage()
        page.url = "https://login.microsoftonline.com/common/oauth2/authorize#x"
        r = self.runner(answers=["c"], failing={"9.9.2"}, page=page)
        self.quietly(r.run)
        self.assertEqual(self.recording["steps"]["9.9.2"]["viewUrl"], "https://portal.azure.com/#view/Two")

    def test_a_step_done_by_hand_on_a_view_with_personal_data_records_none(self) -> None:
        self.recording["steps"]["9.9.2"] = {"viewUrl": "https://portal.azure.com/#view/Two"}
        page = FakePage()
        page.url = f"https://portal.azure.com/#@{TENANT_ID}/view/User/upn/someone%40example.com"
        r = self.runner(answers=["c"], failing={"9.9.2"}, page=page)
        self.quietly(r.run)
        self.assertIsNone(self.recording["steps"]["9.9.2"]["viewUrl"])
        saved = (self.tmp / "rec.json").read_text(encoding="utf-8")
        self.assertNotIn("example.com", saved)

    def test_a_step_done_by_hand_in_a_closed_window_records_no_view(self) -> None:
        r = self.runner(answers=["c"], failing={"9.9.2"}, page=FakePage(closed=True))
        self.quietly(r.run)
        self.assertNotIn("viewUrl", self.recording["steps"].get("9.9.2", {}))


class RecordedSkipTests(RunnerTestCase):
    """A step entry with '"skip": "<reason>"' (#200): never performed, listed with its reason,
    passed over on resume, and no cause of anything for the steps after it."""

    REASON = "Optional: creates a CNAME record no later step uses"

    def skip(self, *step_ids: str, **extra) -> None:
        for step_id in step_ids:
            self.recording["steps"].setdefault(step_id, {}).update(skip=self.REASON, **extra)

    def test_a_skipped_step_is_not_performed_and_the_summary_gives_the_reason(self) -> None:
        self.skip("9.9.2")
        r = self.runner()
        self.assertEqual(self.quietly(r.run), 0)        # a skip is no finding
        self.assertEqual(r.ran, ["9.9.1", "9.9.4", "9.9.5"])
        self.assertEqual(r.ask.prompts, [])
        self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])
        self.assertTrue(self.state()["finished"])
        skipped = [(x["step"], x["skippedBecause"], x["observed"], x["category"])
                   for x in r.records if x["outcome"] == "skipped"]
        self.assertEqual(skipped, [("9.9.2", "9.9.2", self.REASON, run.RECORDED_SKIP)])
        self.assertEqual([x["step"] for x in r.records], ["9.9.2"])     # no screenshot, no other record
        summary = (r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn(f"## skipped (1)\n- step 9.9.2 skipped by the recording: {self.REASON}\n", summary)

    def test_a_skipped_step_never_touches_the_page(self) -> None:
        # The plain Runner on no page at all: performing any step would raise AttributeError.
        self.skip("9.9.1", "9.9.2", "9.9.4", "9.9.5")
        r = run.Runner(None, STEPS, self.recording, self.args(), ask=Answers())
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual([x["step"] for x in r.records if x["outcome"] == "skipped"],
                         ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])

    def test_the_skip_wins_over_the_rest_of_the_entry_which_is_kept_as_it_is(self) -> None:
        self.skip("9.9.2", valueOverrides={"Name": "x"}, viewUrl="https://portal.azure.com/#view/Two",
                  result={"text": "Created"}, labels={"Save": {"decision": "use", "role": "button", "name": "Save"}})
        kept = json.loads(json.dumps(self.recording["steps"]["9.9.2"]))
        r = self.runner()
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.4", "9.9.5"])
        self.assertEqual(self.recording["steps"]["9.9.2"], kept)

    def test_the_steps_after_a_skip_run_and_fail_as_usual(self) -> None:
        self.skip("9.9.2")
        r = self.runner(answers=["e"], failing={"9.9.4"})
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual(r.ran, ["9.9.1", "9.9.4"])
        self.assertEqual([(x["step"], x["skippedBecause"]) for x in r.records if x["outcome"] == "skipped"],
                         [("9.9.2", "9.9.2"), ("9.9.5", "9.9.4")])

    def test_after_an_ended_lab_a_skipped_step_keeps_the_recording_s_reason(self) -> None:
        self.skip("9.9.5")
        r = self.runner(answers=["e"], failing={"9.9.2"})
        self.assertEqual(self.quietly(r.run), 0)
        summary = (r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## skipped (2)\n- step 9.9.4 because step 9.9.2 failed\n"
                      f"- step 9.9.5 skipped by the recording: {self.REASON}\n", summary)
        self.assertEqual(self.state()["inFlight"], "9.9.2")

    def test_resume_passes_over_a_skipped_step_and_shows_the_view_before_it(self) -> None:
        self.skip("9.9.2", viewUrl="https://portal.azure.com/#view/Two")    # a skip's own view is not read
        portal = [s for s in STEPS["steps"] if s["portal"]]
        r = self.runner()
        self.assertEqual(r.start_view(portal, 2), ("9.9.1", "https://portal.azure.com/#view/One"))  # 9.9.4: past 9.9.2
        self.skip("9.9.1")
        self.assertEqual(r.start_view(portal, 2), (None, None))
        del self.recording["steps"]["9.9.1"]["skip"]
        state = {"lab": LAB, "completed": ["9.9.1", "9.9.2"], "inFlight": "9.9.4", "finished": False}
        r = self.runner(answers=["n", ""], resume=True, run_id="resume")
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(r.run(state), 0)
        self.assertIn("https://portal.azure.com/#view/One", out.getvalue())
        self.assertEqual(r.page.visited, [f"https://portal.azure.com/#@{TENANT_ID}/view/One"])
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])

    def test_a_step_the_recording_newly_skips_is_skipped_on_resume(self) -> None:
        # Not completed in the stopped part, and skipped in the recording since: not performed.
        self.skip("9.9.4")
        state = {"lab": LAB, "completed": ["9.9.1"], "inFlight": None, "finished": False}
        r = self.runner(answers=[""], resume=True, run_id="resume")
        self.assertEqual(self.quietly(lambda: r.run(state)), 0)
        self.assertEqual(r.ran, ["9.9.2", "9.9.5"])
        self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])

    def test_a_step_in_flight_and_skipped_since_is_not_asked_about_and_its_findings_are_dropped(self) -> None:
        # The step failed, the person stopped (q), added a skip to the recording and resumed.
        first = self.runner(answers=["q"], unknown={"9.9.2"}, run_id="first")
        self.assertEqual(self.quietly(first.run), run.ABORTED)
        state = run.load_state(self.tmp / "state.json", LAB)
        self.assertEqual(state["inFlight"], "9.9.2")
        self.skip("9.9.2")
        r = self.runner(answers=[""], resume=True, run_id="second", state=state)
        self.assertEqual(self.quietly(lambda: r.run(state)), 0)     # the stopped attempt's unknown is gone
        self.assertEqual(r.ask.prompts, ["> "])                     # the view, not 'did it finish?'
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])
        self.assertEqual([(x["step"], x["outcome"], x["category"]) for x in r.records if x["step"] == "9.9.2"],
                         [("9.9.2", "skipped", run.RECORDED_SKIP)])
        summary = (self.tmp / "logs" / "first" / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## unknown (0)", summary)
        self.assertIn(f"## skipped (1)\n- step 9.9.2 skipped by the recording: {self.REASON}\n", summary)
        self.assertEqual(self.state()["completed"], ["9.9.1", "9.9.2", "9.9.4", "9.9.5"])

    def test_a_step_in_flight_and_skipped_since_stays_dropped_after_a_second_resume(self) -> None:
        # As above, but a later step fails and the run is stopped and resumed again (#222): the
        # dropped attempt is behind a marker in results.jsonl, so it is not counted again.
        first = self.runner(answers=["q"], unknown={"9.9.2"}, run_id="first")
        self.quietly(first.run)
        state = run.load_state(self.tmp / "state.json", LAB)
        self.skip("9.9.2")
        second = self.runner(answers=["", "q"], unknown={"9.9.4"}, resume=True, run_id="second", state=state)
        self.assertEqual(self.quietly(lambda: second.run(state)), run.ABORTED)
        state = run.load_state(self.tmp / "state.json", LAB)
        self.assertEqual(state["inFlight"], "9.9.4")
        third = self.runner(answers=["y", ""], resume=True, run_id="third", state=state)
        self.assertEqual(self.quietly(lambda: third.run(state)), 1)
        summary = (self.tmp / "logs" / "first" / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## unknown (1)\n- step 9.9.4 ", summary)
        self.assertIn(f"## skipped (1)\n- step 9.9.2 skipped by the recording: {self.REASON}\n", summary)

    def resume_on_file(self, *records: tuple[str, str, dict]) -> tuple[int, str]:
        """A resume of run 'hand' whose results.jsonl holds `records` (step, kind, fields), with
        9.9.1 and 9.9.2 completed, 9.9.4 in flight (answered y) and 9.9.2 skipped in the recording.
        Returns the exit code and the summary."""
        maker = self.runner()
        lines = []
        for step, kind, fields in records:
            record = maker.new_record({"id": step}, kind, "Missing button" if kind == "action" else None)
            record.update(fields)
            lines.append(json.dumps(record) + "\n")
        folder = self.tmp / "logs" / "hand"
        folder.mkdir(parents=True)
        (folder / "results.jsonl").write_text("".join(lines), encoding="utf-8")
        self.skip("9.9.2")
        state = {"runId": "hand", "lab": LAB, "completed": ["9.9.1", "9.9.2"], "inFlight": "9.9.4"}
        r = self.runner(answers=["y", ""], resume=True, run_id="hand", state=state)
        code = self.quietly(lambda: r.run(state))
        return code, (folder / "summary.md").read_text(encoding="utf-8")

    def test_a_completed_step_with_a_finding_beside_its_recorded_skip_counts_none(self) -> None:
        # Only a step whose records are all recorded skips is left as it is: an unknown beside one
        # is dropped, and the step listed once.
        code, summary = self.resume_on_file(
            ("9.9.1", "action", {"outcome": "match"}),
            ("9.9.2", "action", {"outcome": "unknown", "observed": "not found"}),
            ("9.9.2", "action", {"outcome": "skipped", "skippedBecause": "9.9.2", "observed": self.REASON,
                                 "category": run.RECORDED_SKIP}))
        self.assertEqual(code, 0)
        self.assertIn("## unknown (0)\n", summary)
        self.assertIn(f"## skipped (1)\n- step 9.9.2 skipped by the recording: {self.REASON}\n", summary)

    def test_a_completed_step_without_records_is_still_listed_as_skipped_by_the_recording(self) -> None:
        # Its last line is a marker, so a resume loads no record of it; the skip still lists it.
        code, summary = self.resume_on_file(
            ("9.9.1", "action", {"outcome": "match"}),
            ("9.9.2", "action", {"outcome": "unknown", "observed": "not found"}),
            ("9.9.2", "redo", {"screenshot": None}))
        self.assertEqual(code, 0)
        self.assertIn("## unknown (0)\n", summary)
        self.assertIn(f"## skipped (1)\n- step 9.9.2 skipped by the recording: {self.REASON}\n", summary)

    def test_a_completed_step_skipped_since_drops_its_findings_once(self) -> None:
        # 9.9.2 fails and is done by hand (c), 9.9.4 fails (q); the recording then skips 9.9.2.
        # The skip wins: 9.9.2's unknown is dropped behind a marker, and the step is listed as
        # skipped by the recording, once, however often the run is resumed after that.
        first = self.runner(answers=["c", "q"], unknown={"9.9.2", "9.9.4"}, run_id="first")
        self.quietly(first.run)
        state = run.load_state(self.tmp / "state.json", LAB)
        self.assertEqual((state["completed"], state["inFlight"]), (["9.9.1", "9.9.2"], "9.9.4"))
        self.skip("9.9.2")
        second = self.runner(answers=["y", "", "q"], unknown={"9.9.5"}, resume=True, run_id="second", state=state)
        self.assertEqual(self.quietly(lambda: second.run(state)), run.ABORTED)
        self.assertEqual([(x["step"], x["outcome"]) for x in second.records if x["outcome"] != "match"],
                         [("9.9.4", "unknown"), ("9.9.2", "skipped"), ("9.9.5", "unknown")])
        state = run.load_state(self.tmp / "state.json", LAB)
        third = self.runner(answers=["y", ""], resume=True, run_id="third", state=state)
        self.assertEqual(self.quietly(lambda: third.run(state)), 2)
        summary = (self.tmp / "logs" / "first" / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## unknown (2)\n- step 9.9.4 ", summary)
        self.assertNotIn("- step 9.9.2 action", summary)
        self.assertIn("## done by hand (0)", summary)
        self.assertIn(f"## skipped (1)\n- step 9.9.2 skipped by the recording: {self.REASON}\n", summary)
        lines = [json.loads(x) for x in (self.tmp / "logs" / "first" / "results.jsonl").read_text(
            encoding="utf-8").splitlines()]
        self.assertEqual([(x["kind"], x["outcome"]) for x in lines if x["step"] == "9.9.2"],
                         [("action", "unknown"), ("action", "match"), ("redo", None), ("action", "skipped")])

    def test_starting_at_a_skipped_step_names_the_first_step_that_runs(self) -> None:
        self.skip("9.9.2")
        r = self.runner(answers=[""], from_step="9.9.2")
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(r.run(), 0)
        self.assertIn("Starting at step 9.9.4 (Four) (the recording skips step 9.9.2). Opened the view "
                      "step 9.9.1 ended on:\n  https://portal.azure.com/#view/One\n", out.getvalue())
        self.assertEqual(r.page.visited, [f"https://portal.azure.com/#@{TENANT_ID}/view/One"])
        self.assertEqual(r.ran, ["9.9.4", "9.9.5"])
        self.skip("9.9.4", "9.9.5")                                  # nothing left to run: no view to ask for
        r = self.runner(from_step="9.9.2", run_id="all-skipped")
        self.assertEqual(self.quietly(r.run), 0)
        self.assertEqual((r.ran, r.ask.prompts), ([], []))

    def test_a_skip_after_an_ended_lab_keeps_the_failed_step_in_flight(self) -> None:
        self.skip("9.9.5")
        r = self.runner(answers=["e"], failing={"9.9.2"})
        saved: list[tuple[list[str], str | None]] = []
        save_state = r.save_state
        r.save_state = lambda completed, in_flight, finished=False: (
            saved.append((list(completed), in_flight)), save_state(completed, in_flight, finished))
        self.quietly(r.run)
        self.assertEqual(saved[-2:], [(["9.9.1", "9.9.5"], "9.9.2"), (["9.9.1", "9.9.5"], "9.9.2")])

    def test_main_refuses_a_malformed_skip_before_the_browser_opens(self) -> None:
        (self.tmp / "steps.json").write_text(json.dumps(STEPS), encoding="utf-8")
        argv = ["--steps", str(self.tmp / "steps.json"), "--recording", str(self.tmp / "rec.json"),
                "--log-dir", str(self.tmp / "logs"), "--run-id", "x", "--tenant-id", "t", "--tenant-domain", "d",
                "--state", str(self.tmp / "state.json"), "--auth-state", str(self.tmp / "auth.json")]

        class Console(io.StringIO):
            def reconfigure(self, **kwargs) -> None:
                pass

        for value in ("", "   ", None, True):
            with self.subTest(value=value):
                self.recording["steps"]["9.9.2"] = {"skip": value}
                (self.tmp / "rec.json").write_text(json.dumps(self.recording), encoding="utf-8")
                out = Console()
                with mock.patch.object(run, "sync_playwright") as playwright, redirect_stdout(out):
                    self.assertEqual(run.main(argv), run.NOT_STARTED)
                playwright.assert_not_called()
                self.assertIn("The recording cannot be used: step 9.9.2: 'skip' must be", out.getvalue())


class RunFolderTests(RunnerTestCase):
    """A run without --resume never appends to a results.jsonl another run left in its folder: it
    refuses to start (254) before the browser opens, and the file stays as it was."""

    class Console(io.StringIO):
        def reconfigure(self, **kwargs) -> None:
            pass

    def main(self, *extra: str) -> tuple[int, str, mock.MagicMock]:
        (self.tmp / "steps.json").write_text(json.dumps(STEPS), encoding="utf-8")
        argv = ["--steps", str(self.tmp / "steps.json"), "--recording", str(self.tmp / "rec.json"),
                "--log-dir", str(self.tmp / "logs"), "--run-id", "x", "--tenant-id", "t", "--tenant-domain", "d",
                "--state", str(self.tmp / "state.json"), "--auth-state", str(self.tmp / "auth.json"), *extra]
        out = self.Console()
        with mock.patch.object(run, "sync_playwright") as playwright, redirect_stdout(out), \
                mock.patch.object(run, "open_portal", side_effect=OSError("the browser opened")):
            code = run.main(argv)
        return code, out.getvalue(), playwright

    def test_a_new_run_in_a_folder_with_results_refuses_to_start(self) -> None:
        folder = self.tmp / "logs" / "x"
        folder.mkdir(parents=True)
        (folder / "steps.json").write_text("{}", encoding="utf-8")      # the entry point writes it first
        code, out, playwright = self.main()
        self.assertIn("Could not open the Portal", out)                 # no results.jsonl yet: it starts
        (folder / "results.jsonl").write_text('{"step": "9.9.1"}\n', encoding="utf-8")
        for extra in ((), ("--from-step", "9.9.4")):
            with self.subTest(extra=extra):
                code, out, playwright = self.main(*extra)
                self.assertEqual(code, run.NOT_STARTED)
                playwright.assert_not_called()
                self.assertIn("already holds results.jsonl", out)
                self.assertIn("--resume", out)
                self.assertIn("another --run-id", out)
                self.assertEqual((folder / "results.jsonl").read_text(encoding="utf-8"), '{"step": "9.9.1"}\n')


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


def snapshot_line(role: str, name: str, flags: str = "") -> str:
    """One line of Playwright's aria_snapshot() for an element: the name JSON-escaped in double
    quotes, and the whole key single-quoted, a quote inside it doubled, when YAML needs it, as for
    a ': ' in the name (Playwright's yamlEscapeKeyIfNeeded, for the cases these tests use)."""
    key = f"{role} {json.dumps(name, ensure_ascii=False)}" + (f" {flags}" if flags else "")
    if re.search(r":(\s|$)|\s#|[{}`]", key):
        key = "'" + key.replace("'", "''") + "'"
    return f"- {key}"


class SnapshotKeyTests(unittest.TestCase):
    """snapshot_key: the role and name of one line of an accessibility snapshot, in the form
    Playwright writes it: a YAML key, single-quoted when it holds ': ' or the like (#294)."""

    STANDARD = "Standard: Recommended for most scenarios (general-purpose v2 account)"

    def test_a_quoted_key_gives_its_role_and_name(self) -> None:
        line = "- 'radio \"Standard: Recommended for most scenarios (general-purpose v2 account)\" [checked]'"
        self.assertEqual(snapshot_line("radio", self.STANDARD, "[checked]"), line)     # the fake writes it so
        self.assertEqual(run.snapshot_key(line), ("radio", self.STANDARD))
        self.assertEqual(run.snapshot_key("  - 'radio \"A: b\"':"), ("radio", "A: b"))   # with children

    def test_a_doubled_quote_and_an_escaped_quote_are_undone(self) -> None:
        for name in ("Don't: stop", 'Say "hi": now', "Back\\slash: x", "It's \"quoted\""):
            with self.subTest(name=name):
                self.assertEqual(run.snapshot_key(snapshot_line("button", name)), ("button", name))
        self.assertEqual(run.snapshot_key("- 'button \"Don''t: stop\"'"), ("button", "Don't: stop"))
        self.assertEqual(run.snapshot_key('- button "Say \\"hi\\""'), ("button", 'Say "hi"'))

    def test_a_plain_key_a_text_line_and_other_lines(self) -> None:
        self.assertEqual(run.snapshot_key('- heading "Basics" [level=2]'), ("heading", "Basics"))
        self.assertEqual(run.snapshot_key("- banner:"), ("banner", ""))
        self.assertEqual(run.snapshot_key("- text: Owners"), ("text", ""))
        self.assertEqual(run.snapshot_key("- 'text: Owners: all'"), ("text", ""))
        for line in ('  - /url: "#x"', "", "  plain", "- 'unterminated"):
            with self.subTest(line=line):
                self.assertIsNone(run.snapshot_key(line))

    def test_accessible_name_and_aria_lines_read_quoted_keys(self) -> None:
        self.assertEqual(run.accessible_name(ScreenNode(tree=snapshot_line("radio", self.STANDARD, "[checked]"))),
                         self.STANDARD)
        tree = "\n".join([snapshot_line("radio", self.STANDARD), snapshot_line("radio", "Premium"),
                          snapshot_line("button", "Don't: stop"), snapshot_line("button", 'Say "hi"'),
                          snapshot_line("radio", "Premium"), "- text: x", "- button"])
        with mock.patch.object(run, "all_frames", lambda page: [Screen(tree=tree)]):
            lines = run.aria_lines(FakePage())
        self.assertEqual(lines, [("radio", self.STANDARD, 1, False, False), ("radio", "Premium", 2, False, False),
                                 ("button", "Don't: stop", 1, False, False),
                                 ("button", 'Say "hi"', 1, False, False)])   # no unnamed button

    def test_aria_lines_mark_an_element_inside_a_list_row_but_not_in_a_column_header(self) -> None:
        # #317: a row's link or check box is named after the row's data (example data: the lab's
        # fictional users); a column header's sort button and select-all box are the Portal's labels.
        tree = "\n".join([
            '- button "Add"',
            '- grid "Users":',
            '  - rowgroup:',
            '    - row "Select all Name":',
            '      - columnheader "Select all":',
            '        - checkbox "Select all"',
            '      - columnheader "Name":',
            '        - button "Name"',
            '  - rowgroup:',
            '    - row "Select row Illidan Stormrage Illidan Stormrage":',
            '      - gridcell "Select row Illidan Stormrage":',
            '        - checkbox "Select row Illidan Stormrage"',
            '      - gridcell "Illidan Stormrage":',
            '        - link "Illidan Stormrage":',
            '          - /url: "#x"',
            '    - row "Khadgar Archmage":',
            '      - checkbox "Khadgar Archmage"',
            '      - button "Add"',
            '- link "Illidan Stormrage"',      # also outside a row: the name still counts as a row's
            '- tab "Members"',
        ])
        with mock.patch.object(run, "all_frames", lambda page: [Screen(tree=tree)]):
            lines = run.aria_lines(FakePage())
            candidates = run.candidates_on_screen(FakePage())
        # in_entry, then names_entry, which is looked for only outside an entry: in one, the name
        # is the entry's data already.
        self.assertEqual(lines, [("button", "Add", 2, True, False), ("checkbox", "Select all", 1, False, False),
                                 ("button", "Name", 1, False, False),
                                 ("checkbox", "Select row Illidan Stormrage", 1, True, False),
                                 ("link", "Illidan Stormrage", 2, True, False),
                                 ("checkbox", "Khadgar Archmage", 1, True, False),
                                 ("tab", "Members", 1, False, False)])
        self.assertEqual([(c.in_entry, c.names_entry) for c in candidates], [line[3:] for line in lines])

    def flags(self, *trees: str) -> dict[tuple[str, str], tuple[bool, bool]]:
        """(role, name) -> (in_entry, names_entry) of aria_lines over one frame per tree."""
        with mock.patch.object(run, "all_frames", lambda page: [Screen(tree=t) for t in trees]):
            return {(role, name): (in_entry, names_entry)
                    for role, name, _, in_entry, names_entry in run.aria_lines(FakePage())}

    def in_entry(self, *trees: str) -> dict[tuple[str, str], bool]:
        return {key: flags[0] for key, flags in self.flags(*trees).items()}

    def test_an_option_and_a_tree_item_are_entries_and_a_list_item_is_not(self) -> None:
        # #317 (example data: fictional users and contoso): a picker's selected user is an option
        # holding a 'Remove <user>' button; a tree's item names a resource; a blade menu is a list
        # of links, the Portal's labels.
        tree = "\n".join([
            '- listbox "Selected":',
            '  - option "Illidan Stormrage":',
            '    - button "Remove Illidan Stormrage"',
            '- tree "Management groups":',
            '  - treeitem "Contoso Root Group":',
            '    - link "Contoso Root Group"',
            '- list "Manage":',
            '  - listitem:',
            '    - link "Members"',
        ])
        self.assertEqual(self.in_entry(tree), {("option", "Illidan Stormrage"): False,
                                               ("button", "Remove Illidan Stormrage"): True,
                                               ("treeitem", "Contoso Root Group"): False,
                                               ("link", "Contoso Root Group"): True, ("link", "Members"): False})

    def test_a_name_that_repeats_an_entry_on_screen_names_that_entry(self) -> None:
        # #317 (example data: fictional users): the picker's 'Remove <user>' in a plain list, a
        # profile blade's heading and its breadcrumb repeat the name of a row elsewhere on screen;
        # a short option ('All', under ENTRY_NAME_MIN) does not make every label with 'all' data.
        rows = "\n".join([
            '- grid "Members":',
            '  - row "Khadgar Archmage":',
            '    - gridcell "Khadgar Archmage"',
            '  - row "Chromie Timewalker Guest":',
            '    - rowheader "Chromie Timewalker"',
            '- listbox "Filter":',
            '  - option "All"',
        ])
        blade = "\n".join([
            '- list "Selected":',
            '  - listitem:',
            '    - button "Remove Khadgar Archmage"',
            '- link "Groups | All groups"',
            '- link "Chromie Timewalker"',
            '- heading "chromie timewalker | Overview"',
            '- checkbox "Select all"',
            '- button "Khadgar"',
        ])
        flags = self.flags(rows, blade)
        self.assertEqual({key: names for key, (_, names) in flags.items() if key[0] != "option"},
                         {("button", "Remove Khadgar Archmage"): True, ("link", "Groups | All groups"): False,
                          ("link", "Chromie Timewalker"): True, ("heading", "chromie timewalker | Overview"): True,
                          ("checkbox", "Select all"): False, ("button", "Khadgar"): False})
        self.assertEqual(flags[("button", "Remove Khadgar Archmage")], (False, True))   # in a list item: no entry
        # An option is no label the recording could keep, so its name is not looked for.
        self.assertEqual(self.flags(rows, '- option "Khadgar Archmage"')[("option", "Khadgar Archmage")],
                         (False, False))

    def test_a_row_nested_in_a_column_header_is_a_row_again(self) -> None:
        # #317: the header's flag ends where a new row starts (example data: a fictional user).
        tree = "\n".join([
            '- row "Name":',
            '  - columnheader "Name":',
            '    - button "Name"',
            '    - grid "Filter":',
            '      - row "Illidan Stormrage":',
            '        - link "Illidan Stormrage"',
            '    - button "Sort"',
        ])
        self.assertEqual(self.in_entry(tree), {("button", "Name"): False, ("link", "Illidan Stormrage"): True,
                                             ("button", "Sort"): False})

    def test_a_quoted_ancestor_key_still_opens_a_row(self) -> None:
        # A key with ': ' is single-quoted (snapshot_key); its children are still its own.
        tree = "\n".join([
            "- 'row \"Khadgar Archmage: Guest\"':",
            "  - 'link \"Khadgar Archmage: profile\"'",
            '- link "Home"',
        ])
        self.assertEqual(self.in_entry(tree), {("link", "Khadgar Archmage: profile"): True, ("link", "Home"): False})

    def test_each_frame_starts_outside_every_row(self) -> None:
        first = "\n".join(['- grid "Users":', '  - row "Illidan Stormrage":', '    - link "Illidan Stormrage"'])
        self.assertEqual(self.in_entry(first, '- link "Home"'),
                         {("link", "Illidan Stormrage"): True, ("link", "Home"): False})

    class CountingStack(list):
        """An ancestor stack for snapshot_elements that counts its pushes and pops."""

        def __init__(self) -> None:
            super().__init__()
            self.pushes = self.pops = 0

        def append(self, item) -> None:
            self.pushes += 1
            super().append(item)

        def pop(self, *args):
            self.pops += 1
            return super().pop(*args)

    @staticmethod
    def chain(depth: int) -> str:
        """A chain `depth` deep, one space per level (the smallest snapshot such a chain can be),
        under a row so that every level is in an entry, then a line back at the top."""
        return "\n".join([" " * i + ("- row:" if i == 0 else "- group:") for i in range(depth)]
                         + [" " * depth + '- link "Deepest"', '- link "Top"'])

    def test_the_ancestor_stack_pushes_and_pops_each_line_at_most_once(self) -> None:
        # #317: a line costs O(1) beyond its own length, counted in steps rather than timed, so a
        # busy runner cannot fail it. The chain is 10,000 deep and unwinds all at once at its last
        # line; the flat list has 100,000 lines, each popping its sibling.
        chain = self.chain(10_000)
        flat = "\n".join(f'- button "Action {i}"' for i in range(100_000))
        for name, tree, unwound in (("chain", chain, 10_001), ("flat", flat, 99_999)):
            with self.subTest(snapshot=name):
                stack = self.CountingStack()
                elements = list(run.snapshot_elements(tree, stack))
                lines = len(tree.splitlines())
                self.assertEqual(len(elements), lines)
                self.assertLessEqual(stack.pushes, lines)
                self.assertLessEqual(stack.pops, lines)
                self.assertEqual(stack.pops, unwound)        # the walk does unwind: the bound is reached
        with mock.patch.object(run, "all_frames", lambda page: [Screen(tree=chain)]):
            lines = run.aria_lines(FakePage())
        self.assertEqual({(role, name): inside for role, name, _, inside, _ in lines},
                         {("link", "Deepest"): True, ("link", "Top"): False})


class BladeStillLoadingTests(unittest.TestCase):
    """blade_still_loading: whether a blade's frame is open while its content is not rendered
    yet (issue #233), from the accessibility outline (role, name) in tree order; aria_outline:
    that outline, without the frames parked outside the window."""

    TOP_BAR = [("banner", ""), ("link", "Microsoft Azure"),
               ("combobox", "Search resources, services, and docs (G+/)"), ("button", "Settings")]
    USERS = [("heading", "Users"), ("button", "Close content 'Users'"), ("searchbox", "Search"),
             ("row", "Name User principal name")]
    NEW_USER = [("heading", "Create new user"), ("button", "Close content 'Create new user'")]

    def test_a_close_button_titled_undefined_anywhere_is_loading(self) -> None:
        self.assertEqual(run.blade_still_loading(self.TOP_BAR + [("button", "Close content 'undefined'")]),
                         run.BLADE_UNTITLED)
        self.assertEqual(run.blade_still_loading(self.TOP_BAR + self.USERS + [("button", "Close content 'undefined'")]),
                         run.BLADE_UNTITLED)
        self.assertEqual(run.blade_still_loading(       # not the last close button: a pane opened over it
            self.TOP_BAR + [("button", "Close content 'undefined'")] + self.USERS), run.BLADE_UNTITLED)

    def test_a_titled_blade_with_no_content_after_its_heading_is_loading(self) -> None:
        for header in (self.NEW_USER, self.NEW_USER[::-1]):
            with self.subTest(header=header):
                self.assertEqual(run.blade_still_loading(
                    self.TOP_BAR + self.USERS + header + [("button", "Maximize"), ("link", "Learn more"),
                                                          ("text", "")]), run.BLADE_EMPTY)

    def test_a_blade_with_content_after_its_heading_is_rendered(self) -> None:
        header = [("heading", "New Group"), ("button", "Close content 'New Group'")]
        for role in ("textbox", "searchbox", "combobox", "checkbox", "radio", "row", "tab", "tabpanel",
                     "table", "grid", "paragraph", "term", "definition"):
            with self.subTest(role=role):
                self.assertIsNone(run.blade_still_loading(self.TOP_BAR + header + [("heading", "Basics"), (role, "x")]))

    def test_controls_of_the_top_bar_or_an_older_blade_do_not_count(self) -> None:
        outline = (self.TOP_BAR + [("heading", "New Group"), ("button", "Close content 'New Group'"),
                                   ("textbox", "Group name"), ("heading", "Add members"),
                                   ("button", "Close content 'Add members'")])
        self.assertEqual(run.blade_still_loading(outline), run.BLADE_EMPTY)

    def test_without_a_titled_blade_frame_nothing_is_loading(self) -> None:
        self.assertIsNone(run.blade_still_loading([]))
        self.assertIsNone(run.blade_still_loading(self.TOP_BAR))
        self.assertIsNone(run.blade_still_loading(self.TOP_BAR + [("heading", "Overview")]))      # no frame
        self.assertIsNone(run.blade_still_loading(self.TOP_BAR + [("button", "Close content 'Users'")]))  # no heading

    class Frame:
        """A frame with an accessibility snapshot (None: unreadable) and its iframe's bounding box
        (None: not rendered; 'gone': frame_element() fails)."""

        def __init__(self, snapshot: str | None, box=None) -> None:
            self.snapshot = snapshot
            self.box = box

        def locator(self, selector):
            return self

        def aria_snapshot(self, timeout=None) -> str:
            if self.snapshot is None:
                raise run.PlaywrightError("frame was detached")
            return self.snapshot

        def frame_element(self):
            if self.box == "gone":
                raise run.PlaywrightError("frame was detached")
            return self

        def bounding_box(self) -> dict | None:     # ElementHandle.bounding_box() takes no timeout
            return self.box

        def dispose(self) -> None:
            pass

    def outline(self, *frames, viewport=None) -> list[tuple[str, str]]:
        page = types.SimpleNamespace(viewport_size=viewport)
        with mock.patch.object(run, "all_frames", lambda _page: list(frames)):
            return run.aria_outline(page)

    def test_the_outline_lists_every_line_of_every_frame_in_order(self) -> None:
        outline = self.outline(
            self.Frame('- banner:\n  - button "Settings"\n- heading "New Group" [level=2]\n'),
            self.Frame(None),
            self.Frame('- textbox "Group name"\n- text: Owners\n  - /url: "#x"\n- button "Say \\"hi\\""\n'
                       "- 'heading \"Step 1: Basics\" [level=2]'\n"))
        self.assertEqual(outline, [("banner", ""), ("button", "Settings"), ("heading", "New Group"),
                                   ("textbox", "Group name"), ("text", ""), ("button", 'Say "hi"'),
                                   ("heading", "Step 1: Basics")])

    WINDOW = {"width": 1440, "height": 900}
    HEADER = ('- heading "Create new user" [level=2]\n'
              "- button \"Close content 'Create new user'\"\n")
    USERS_LIST = '- searchbox "Search"\n- row "Name User principal name"\n'

    def test_rows_of_a_blade_parked_off_the_window_do_not_count_as_the_new_blade_content(self) -> None:
        main = self.Frame(self.HEADER, box="never asked")
        parked = self.Frame(self.USERS_LIST, box={"x": -1300, "y": 40, "width": 900, "height": 800})
        hidden = self.Frame(self.USERS_LIST, box=None)
        gone = self.Frame(self.USERS_LIST, box="gone")
        outline = self.outline(main, parked, hidden, gone, viewport=self.WINDOW)
        self.assertEqual(outline, [("heading", "Create new user"), ("button", "Close content 'Create new user'")])
        self.assertEqual(run.blade_still_loading(outline), run.BLADE_EMPTY)

    def test_the_new_blade_form_in_a_frame_within_the_window_counts(self) -> None:
        main = self.Frame(self.HEADER)
        parked = self.Frame(self.USERS_LIST, box={"x": -1300, "y": 40, "width": 900, "height": 800})
        form = self.Frame('- textbox "User principal name"\n', box={"x": 500, "y": 40, "width": 900, "height": 800})
        outline = self.outline(main, parked, form, viewport=self.WINDOW)
        self.assertEqual(outline[-1], ("textbox", "User principal name"))
        self.assertIsNone(run.blade_still_loading(outline))


# The popups MARK_POPUPS_JS recorded as visible before the search was typed; None when there is
# no record (never made, or deleted by UNMARK_POPUPS_JS). `made` counts the records.
POPUP_RECORD: dict = {"popups": None, "made": 0}


class ScreenNode(FakeElement):
    """One element of a Screen. `interactive`: whether plain text is, or sits inside, a link,
    button or other interactive element (what interactive_text() matches in the browser).
    `on_click` and `on_fill` change the screen, as opening a menu or typing into the search box
    does. `attrs`: its HTML attributes (id, role, aria-controls); `children`: the Screen inside
    it; `rect`: its bounding box; `section`: what RESULT_SECTION_JS reads for a search result
    (group name, nearest heading, text of the whole result); `unreadable`: how many reads of
    the section fail first, as for a result the Portal re-renders; `tree`: its accessibility
    snapshot; `tag` and `text`: its HTML tag and its value or text; `fill_fail`: what fill()
    raises; `shown`: whether it is visible; `read_only`: what READ_ONLY_JS answers; `later`:
    (n, text), the text it shows after n more reads, as a field the Portal updates late;
    `in_header`: whether it sits in a table or grid header (a column's sort button);
    `controls_role`: the role of the element its aria-controls or aria-owns names; `editable`:
    contenteditable; `uninspectable`: FIELD_KIND_JS fails on it. As a check box: `checked`, its
    state; `check_error`: what set_checked() raises (Fluent's tick mark intercepting the click);
    `label`: the node label_of() finds for it, and `more_labels` any others it finds; `flips_after`:
    the number of reads after which `checked` turns over, as a click that went through late. As a
    label: `label_for`, the input it belongs to; `has_link`, whether it holds a link. As an option
    of a list: `selects_on_click` turns its aria-selected over on click. `blade`: what BLADE_OF_JS
    reads, the aria-label and left edge of the region it sits in (None: in no region).
    `next_control`: as a text, the control NEXT_CONTROL_JS finds after it (None: other text comes
    first, or no control), which the script marks with the token it is given. `on_scroll`: as a
    list, what LIST_SCROLL_JS answers (true: the list moved); it shows the options of the next page."""

    def __init__(self, interactive: bool = True, on_click=None, on_fill=None, attrs=None, children=None,
                 rect=None, section=("", "", ""), unreadable: int = 0, tree: str = "", tag: str = "div",
                 text: str = "", fill_fail: Exception | None = None, shown: bool = True,
                 read_only: bool = False, in_header: bool = False, controls_role: str = "",
                 editable: bool = False, uninspectable: bool = False, checked: bool = False,
                 check_error: Exception | None = None, label: "ScreenNode | None" = None,
                 label_for: "ScreenNode | None" = None, has_link: bool = False,
                 selects_on_click: bool = False, blade: tuple[str, float] | None = None,
                 next_control: "ScreenNode | None" = None, on_scroll=None) -> None:
        super().__init__()
        self.on_scroll = on_scroll
        self.next_control = next_control
        self.blade = blade
        self.selects_on_click = selects_on_click
        self.label_for = label_for
        self.has_link = has_link
        self.more_labels: list = []
        self.flips_after: int | None = None
        self.in_top_bar = False             # inside the Portal's top bar, [role=banner]
        self.checked = checked
        self.check_error = check_error
        self.label = label
        self.in_header = in_header
        self.controls_role = controls_role
        self.editable = editable
        self.uninspectable = uninspectable
        self.fill_fail = fill_fail
        self.shown = shown
        self.read_only = read_only
        self.later: tuple[int, str] | None = None
        self.interactive = interactive
        self.on_click = on_click
        self.on_fill = on_fill
        self.attrs = attrs or {}
        self.children = children or Screen()
        self.rect = rect or {"x": 0, "y": 0, "width": 100, "height": 20}
        self.section = section
        self.unreadable = unreadable
        self.tree = tree
        self.tag = tag
        self.text = text
        self.filled: list[str] = []
        self.pressed: list[str] = []

    def is_visible(self) -> bool:
        return self.shown

    def bounding_box(self, timeout=None) -> dict:
        return self.rect

    def get_attribute(self, name, timeout=None):
        return self.attrs.get(name)

    def evaluate(self, script, arg=None, timeout=None):
        if script == run.RESULT_SECTION_JS:
            if self.unreadable:
                self.unreadable -= 1
                raise run.PlaywrightError("element was re-rendered")
            return list(self.section)
        if script == run.CONTROL_JS:
            return [self.tag, self.attrs.get("role", ""), self.editable]
        if script == run.NEW_POPUP_JS:
            popups = POPUP_RECORD["popups"]
            return None if popups is None else not any(self is p for p in popups)
        if script == run.READ_ONLY_JS:
            return self.read_only
        if script == run.LABEL_CHECK_JS:
            return [self.label_for is arg, self.has_link]
        if script == run.BLADE_OF_JS:
            return list(self.blade) if self.blade else None
        if script == run.NEXT_CONTROL_JS:
            if self.next_control is None or self.interactive:
                return False
            self.next_control.attrs[run.NEXT_CONTROL_ATTR] = arg
            return True
        if script == run.IN_TOP_BAR_JS:
            return self.in_top_bar
        if script == run.LIST_SCROLL_JS:
            return bool(self.on_scroll()) if self.on_scroll else False
        if script == run.FIELD_KIND_JS:
            if self.uninspectable:
                raise run.PlaywrightError("element was detached")
            return [self.tag, self.attrs.get("role", ""), self.attrs.get("type", "").lower(),
                    self.attrs.get("aria-haspopup", "").lower(), self.editable]
        if script == run.FIELD_CANDIDATE_JS:            # what the browser answers, in Python
            role = self.attrs.get("role", "")
            plain_button = role == "button" or (not role and self.tag == "button")
            names_list = (bool(self.attrs.get("aria-controls") or self.attrs.get("aria-owns"))
                          and self.controls_role in ("listbox", "menu"))
            opens_list = (self.attrs.get("aria-haspopup", "").lower() in ("listbox", "menu", "true")
                          or ("aria-expanded" in self.attrs and names_list))
            return not self.in_header and (not plain_button or opens_list)
        if "tagName" in script:                     # fill_field: [tag, type]
            return [self.tag, self.attrs.get("type", "")]
        raise NotImplementedError(script)

    def aria_snapshot(self, timeout=None) -> str:
        return self.tree

    def element_handle(self, timeout=None):
        return self

    def dispose(self) -> None:
        pass

    def inner_text(self, timeout=None) -> str:
        if self.later:
            reads, text = self.later
            self.later = (reads - 1, text) if reads > 1 else None
            if reads <= 1:
                self.text = text
        return self.text

    def input_value(self, timeout=None) -> str:
        return self.inner_text(timeout)

    def get_by_role(self, role, name=None, exact=None):
        return self.children.get_by_role(role, name=name, exact=exact)

    def get_by_text(self, text, exact=None):
        return self.children.get_by_text(text, exact=exact)

    def locator(self, selector: str):
        if selector.startswith("xpath="):            # label_of(): the check box's label
            return ScreenLocator(([self.label] if self.label else []) + self.more_labels)
        return self.children.locator(selector)

    def is_checked(self, timeout=None) -> bool:
        if self.flips_after is not None:
            self.flips_after -= 1
            if self.flips_after < 0:
                self.checked, self.flips_after = not self.checked, None
        return self.checked

    def set_checked(self, checked: bool, timeout=None) -> None:
        if self.check_error:
            raise self.check_error
        self.checked = checked

    def click(self, timeout=None) -> None:
        super().click(timeout)
        if self.selects_on_click:
            self.attrs["aria-selected"] = "false" if self.attrs.get("aria-selected") == "true" else "true"
        if self.on_click:
            self.on_click()

    def fill(self, value, timeout=None) -> None:
        if self.fill_fail:
            raise self.fill_fail
        self.filled.append(value)
        self.text = value
        if self.on_fill:
            self.on_fill()

    def press(self, key, timeout=None) -> None:
        self.pressed.append(key)


class ScreenLocator:
    def __init__(self, nodes: list) -> None:
        self.nodes = nodes

    def count(self) -> int:
        return len(self.nodes)

    def nth(self, index: int):
        return self.nodes[index]

    def aria_snapshot(self, timeout=None) -> str:
        return self.nodes[0].aria_snapshot(timeout)

    def and_(self, other: "ScreenLocator") -> "ScreenLocator":
        return ScreenLocator([node for node in self.nodes if any(node is o for o in other.nodes)])


class Screen:
    """A frame of a FakePage, or what is inside a ScreenNode: (role, name, node) entries, role
    'text' for plain text (the name is its whole text, child elements included, as get_by_text
    reads it) and 'label' for a field's label. Lookups see the children of every node too, as a
    DOM query does. A name to look up is a string (exact), a pattern (search) or None (any)."""

    ID = re.compile(r'^\[id="([^"]*)"\]$')

    def __init__(self, *entries, tree: str = "") -> None:
        self.entries = list(entries)
        self.tree = tree                 # the frame's accessibility snapshot ('body')

    def add(self, *entries) -> None:
        self.entries.extend(entries)

    def everything(self):
        for role, name, node in self.entries:
            yield role, name, node
            yield from node.children.everything()

    def _find(self, role: str, name) -> ScreenLocator:
        def hit(n: str) -> bool:
            return name is None or (n == name if isinstance(name, str) else bool(name.search(n)))
        return ScreenLocator([node for r, n, node in self.everything() if r == role and hit(n)])

    def get_by_role(self, role, name=None, exact=None) -> ScreenLocator:
        return self._find(role, name)

    def get_by_text(self, text, exact=None) -> ScreenLocator:
        return self._find("text", text)

    def get_by_label(self, text, exact=None) -> ScreenLocator:
        return self._find("label", text)

    def locator(self, selector: str) -> ScreenLocator:
        """interactive_text()'s constraint (every interactive node), '[id="x"]', 'body' and a
        list of '[role=x]' (POPUP_ROLES)."""
        if selector.startswith(":is("):
            return ScreenLocator([node for _, _, node in self.everything() if node.interactive])
        m = re.match(r'^\[(data-[\w-]+)="([^"]*)"\]$', selector)
        if m:
            return ScreenLocator([node for _, _, node in self.everything() if node.attrs.get(m.group(1)) == m.group(2)])
        m = self.ID.match(selector)
        if m:
            return ScreenLocator([node for _, _, node in self.everything() if node.attrs.get("id") == m.group(1)])
        if selector == "body":
            return ScreenLocator([ScreenNode(tree=self.tree)])
        roles = re.findall(r"\[role=(\w+)\]", selector)
        if roles:
            return ScreenLocator([node for r, _, node in self.everything() if r in roles])
        raise NotImplementedError(selector)

    mark_fails = False                   # MARK_POPUPS_JS raises, as on a page that just navigated

    def evaluate(self, script, arg=None):
        """MARK_POPUPS_JS (record the visible popups in POPUP_RECORD) and UNMARK_POPUPS_JS."""
        if script == run.MARK_POPUPS_JS:
            if self.mark_fails:
                raise run.PlaywrightError("Execution context was destroyed")
            roles = re.findall(r"\[role=(\w+)\]", arg)
            POPUP_RECORD["popups"] = [node for role, _, node in self.everything() if role in roles and node.shown]
            POPUP_RECORD["made"] += 1
        elif script == run.UNMARK_POPUPS_JS:
            POPUP_RECORD["popups"] = None
        else:
            raise NotImplementedError(script)


class FindOnScreenTests(RunnerTestCase):
    """act_on_label against a Screen: how the runner finds what the guide names."""

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n", encoding="utf-8")
        POPUP_RECORD.update(popups=None, made=0)

    def act(self, screen: Screen, item: dict, label: str, answers=(), candidates=(), runner=None, page=None,
            value=None):
        r = runner or run.Runner(page or FakePage(), STEPS, self.recording, self.args(), ask=Answers(*answers))
        step = {"id": "9.9.1", "title": "One", "items": [item], "images": []}
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=list(candidates)):
            return self.quietly(lambda: r.act_on_label(step, item, label, value)), r

    SEARCH = {"kind": "search", "labels": ["Microsoft Entra ID"], "line": 2}
    SEARCH_BOX = "Search resources, services, and docs (G+/)"
    ENTRA = "Microsoft Entra ID"

    def search_screen(self, *results, controls: bool = True, tree: str = "- listbox") -> tuple[Screen, ScreenNode]:
        """A page with the global search box, a same-named link outside it (a favourite in the
        portal menu), and, once something is typed, the dropdown holding `results`."""
        self.outside = ScreenNode()
        screen = Screen(("link", self.ENTRA, self.outside))
        dropdown = ScreenNode(attrs={"id": "results"}, children=Screen(*results), tree=tree,
                              rect={"x": 470, "y": 40, "width": 400, "height": 700})
        box = ScreenNode(attrs={"aria-controls": "results"} if controls else {},
                         on_fill=lambda: screen.add(("listbox", "", dropdown)),
                         rect={"x": 470, "y": 5, "width": 400, "height": 30})
        screen.add(("combobox", self.SEARCH_BOX, box))
        return screen, box

    @staticmethod
    def result(heading: str, whole: str = "Microsoft Entra ID", **kwargs) -> ScreenNode:
        return ScreenNode(section=("", heading, whole), **kwargs)

    def tree_file(self) -> Path:
        return self.tmp / "logs" / "test" / "search-9.9.1.aria.txt"

    def test_a_search_opens_the_services_result_inside_the_dropdown(self) -> None:
        market, services = self.result("Marketplace (22)"), self.result("Services (67)")
        screen, box = self.search_screen(("option", self.ENTRA, market), ("option", self.ENTRA, services),
                                         ("text", self.ENTRA, self.result("Documentation (99+)")))
        record, r = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual(box.filled, [self.ENTRA])
        self.assertEqual((record["kind"], record["outcome"], record["observed"]), ("search", "match", self.ENTRA))
        self.assertEqual((services.clicked, market.clicked, self.outside.clicked), (1, 0, 0))
        self.assertEqual(r.ask.prompts, [])
        self.assertFalse(self.tree_file().exists())

    def test_without_aria_controls_the_results_are_the_popup_under_the_search_box(self) -> None:
        services = self.result("Services (67)")
        screen, _ = self.search_screen(("option", self.ENTRA, services), controls=False)
        elsewhere = ScreenNode(rect={"x": 0, "y": 200, "width": 260, "height": 400},
                               children=Screen(("option", self.ENTRA, self.result("Services"))))
        screen.add(("listbox", "", elsewhere))                         # not under the box
        record, _ = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], services.clicked), ("match", 1))

    def test_a_list_already_on_the_page_is_never_taken_for_the_results(self) -> None:
        for controls in (True, False):
            with self.subTest(controls=controls):
                screen, box = self.search_screen(controls=controls)
                box.on_fill = None                                         # the dropdown has not rendered yet
                in_grid = ScreenNode()
                grid = ScreenNode(rect={"x": 470, "y": 300, "width": 900, "height": 400},
                                  children=Screen(("option", self.ENTRA, in_grid)))
                screen.add(("grid", "", grid))                              # below the box, overlapping it
                record, r = self.act(screen, self.SEARCH, self.ENTRA)
                self.assertEqual((record["outcome"], in_grid.clicked, self.outside.clicked), ("unknown", 0, 0))
                self.assertIn("no results list identified", self.tree_file().read_text(encoding="utf-8"))

    def test_a_popup_hidden_before_typing_counts_as_new_and_the_record_is_deleted(self) -> None:
        screen, box = self.search_screen(controls=False)
        services = self.result("Services (67)")
        dropdown = ScreenNode(shown=False, rect={"x": 470, "y": 120, "width": 400, "height": 600},
                              children=Screen(("option", self.ENTRA, services)))
        screen.add(("listbox", "", dropdown))                     # in the DOM, hidden, far from the box
        box.on_fill = lambda: setattr(dropdown, "shown", True)
        record, _ = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], services.clicked), ("match", 1))
        self.assertEqual((POPUP_RECORD["made"], POPUP_RECORD["popups"]), (1, None))   # forgotten afterwards

    def test_without_a_record_of_the_popups_only_one_right_under_the_box_counts(self) -> None:
        for top, clicked in ((40, 1), (120, 0)):                    # the box's bottom edge is at 35
            with self.subTest(top=top):
                POPUP_RECORD.update(popups=None, made=0)
                screen, box = self.search_screen(controls=False)
                Screen.mark_fails = True
                self.addCleanup(setattr, Screen, "mark_fails", False)
                services = self.result("Services (67)")
                dropdown = ScreenNode(rect={"x": 470, "y": top, "width": 400, "height": 600},
                                      children=Screen(("option", self.ENTRA, services)))
                box.on_fill = lambda dropdown=dropdown: screen.add(("listbox", "", dropdown))
                self.act(screen, self.SEARCH, self.ENTRA)
                self.assertEqual((services.clicked, POPUP_RECORD["made"]), (clicked, 0))

    def test_a_result_without_a_section_never_counts_beside_one_with_a_section(self) -> None:
        unsectioned, market = self.result(""), self.result("Marketplace (22)")
        screen, _ = self.search_screen(("option", self.ENTRA, unsectioned), ("option", self.ENTRA, market))
        record, _ = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], unsectioned.clicked, market.clicked), ("unknown", 0, 0))
        self.assertTrue(self.tree_file().is_file())

    def test_one_result_without_a_section_is_taken(self) -> None:
        only = self.result("")
        screen, _ = self.search_screen(("option", self.ENTRA, only))
        record, _ = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], only.clicked), ("match", 1))

    def test_several_results_without_a_section_are_ambiguous(self) -> None:
        first, second = self.result(""), self.result("")
        screen, _ = self.search_screen(("option", self.ENTRA, first), ("option", self.ENTRA, second))
        record, _ = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], first.clicked, second.clicked), ("unknown", 0, 0))
        self.assertIn("ambiguous: 2 visible results match, none of them under Services", record["observed"])
        self.assertTrue(self.tree_file().is_file())

    def test_a_window_closed_while_typing_the_search_stops_the_run(self) -> None:
        screen, box = self.search_screen()
        box.fill_fail = run.PlaywrightError("Target page, context or browser has been closed")
        page = FakePage()
        page.is_closed = lambda: True
        with self.assertRaises(run.PageClosed):
            self.act(screen, self.SEARCH, self.ENTRA, page=page)

    def test_marketplace_and_highlighted_text_never_count_and_the_tree_is_kept(self) -> None:
        protection = self.result("Services (67)", whole="Microsoft Entra ID Protection")
        market = self.result("Marketplace (22)")
        screen, _ = self.search_screen(("text", self.ENTRA, protection), ("option", self.ENTRA, market),
                                       tree='- option "Admin" [ref=x]: admin@contoso.onmicrosoft.com')
        record, r = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], len(r.ask.prompts)), ("unknown", 1))   # the person was asked
        self.assertEqual((protection.clicked, market.clicked, self.outside.clicked), (0, 0, 0))
        tree = self.tree_file().read_text(encoding="utf-8")
        self.assertIn("# the search results", tree)
        self.assertIn("admin@[tenantdomain]", tree)
        self.assertNotIn("contoso.onmicrosoft.com", tree)

    def test_two_results_in_services_stay_ambiguous_and_the_tree_is_kept(self) -> None:
        one, two = self.result("Services (67)"), self.result("Services (67)")
        screen, _ = self.search_screen(("option", self.ENTRA, one), ("option", self.ENTRA, two))
        record, r = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("ambiguous: 2 visible results in Services match", record["observed"])
        self.assertEqual((one.clicked, two.clicked, r.ask.prompts), (0, 0, []))
        self.assertTrue(self.tree_file().is_file())

    def test_a_result_re_rendered_while_it_is_read_is_looked_up_again(self) -> None:
        services = self.result("Services (67)", unreadable=1)
        screen, _ = self.search_screen(("option", self.ENTRA, services))
        record, _ = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], services.clicked), ("match", 1))

    def test_a_search_without_an_exact_result_asks_the_person_as_for_an_action(self) -> None:
        renamed = self.result("Services (67)", whole="Entra ID")
        screen, _ = self.search_screen(("option", "Entra ID", renamed))
        record, r = self.act(screen, self.SEARCH, self.ENTRA, answers=["1"],
                             candidates=[run.Candidate("option", "Entra ID")])
        self.assertEqual(len(r.ask.prompts), 1)
        self.assertEqual((record["kind"], record["outcome"], record["severity"], record["observed"]),
                         ("search", "drift", "misleading", "Entra ID"))
        self.assertEqual(renamed.clicked, 1)
        self.assertEqual(self.recording["steps"]["9.9.1"]["labels"][self.ENTRA]["name"], "Entra ID")
        self.assertTrue(self.tree_file().is_file())

    RG = "Resource groups"
    RM = " Resource Manager"

    def test_resource_groups_resource_manager_is_the_resource_groups_result(self) -> None:
        wanted = self.result("Services (67)", whole="Resource groups Resource Manager")
        keywords = self.result("Services (67)", whole="Subscriptions Keywords: resource groups")
        includes = self.result("Services (67)", whole="Resource Manager Includes: Resource groups")
        offer = self.result("Marketplace (22)", whole="Resource group")
        screen, box = self.search_screen(("option", "Subscriptions Keywords: resource groups", keywords),
                                         ("option", "Resource Manager Includes: Resource groups", includes),
                                         ("option", "Resource groups Resource Manager", wanted),
                                         ("option", "Resource group", offer))
        record, r = self.act(screen, self.SEARCH, self.RG)
        self.assertEqual((record["outcome"], record["kind"]), ("match", "search"))
        self.assertEqual((wanted.clicked, keywords.clicked, includes.clicked, offer.clicked), (1, 0, 0, 0))
        self.assertEqual((r.ask.prompts, box.filled), ([], [self.RG]))
        self.assertFalse(self.tree_file().exists())

    def test_tags_and_management_groups_resource_manager_too(self) -> None:
        for label in ("Tags", "Management groups"):
            with self.subTest(label=label):
                wanted = self.result("Services (67)", whole=f"{label} Resource Manager")
                other = self.result("Services (67)", whole=f"Policy Includes: {label}")
                screen, _ = self.search_screen(("option", f"Policy Includes: {label}", other),
                                               ("option", f"{label} Resource Manager", wanted))
                record, _ = self.act(screen, self.SEARCH, label)
                self.assertEqual((record["outcome"], wanted.clicked, other.clicked), ("match", 1, 0))

    def test_an_exact_result_wins_over_a_category_one(self) -> None:
        exact = self.result("Services (67)", whole=self.RG)
        category = self.result("Services (67)", whole=self.RG + self.RM)
        screen, _ = self.search_screen(("option", self.RG + self.RM, category), ("option", self.RG, exact))
        record, _ = self.act(screen, self.SEARCH, self.RG)
        self.assertEqual((record["outcome"], exact.clicked, category.clicked), ("match", 1, 0))

    def test_a_category_result_outside_services_never_counts(self) -> None:
        market = self.result("Marketplace (22)", whole=self.RG + self.RM)
        docs = self.result("Documentation (99+)", whole=self.RG + self.RM)
        screen, _ = self.search_screen(("option", self.RG + self.RM, market), ("option", self.RG + self.RM, docs))
        record, _ = self.act(screen, self.SEARCH, self.RG)
        self.assertEqual((record["outcome"], market.clicked, docs.clicked), ("unknown", 0, 0))
        self.assertTrue(self.tree_file().is_file())

    def test_two_category_results_in_services_are_ambiguous(self) -> None:
        one, two = (self.result("Services (67)", whole=self.RG + self.RM) for _ in range(2))
        screen, _ = self.search_screen(("option", self.RG + self.RM, one), ("option", self.RG + self.RM, two))
        record, _ = self.act(screen, self.SEARCH, self.RG)
        self.assertEqual((record["outcome"], one.clicked, two.clicked), ("unknown", 0, 0))
        self.assertIn("ambiguous", record["observed"])

    def typed_again_screen(self, appears_on: int):
        """A search whose results list appears only after the `appears_on`th time the label is typed."""
        screen, box = self.search_screen(self.EXACT_ENTRY)
        box.on_fill()                                        # the dropdown the first typing would add:
        listbox = screen.entries.pop()                       # held back until the label is typed again
        typed = []

        def on_fill() -> None:
            if box.text:
                typed.append(box.text)
                if len(typed) == appears_on:
                    screen.add(listbox)
        box.on_fill = on_fill
        return screen, box

    def test_a_search_without_a_results_list_is_typed_again_once(self) -> None:
        self.EXACT_ENTRY = ("option", self.ENTRA, services := self.result("Services (67)"))
        screen, box = self.typed_again_screen(appears_on=2)
        record, r = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], services.clicked), ("match", 1))
        self.assertEqual((box.filled, box.pressed), ([self.ENTRA, "", self.ENTRA], ["Escape"]))
        self.assertEqual(r.ask.prompts, [])
        self.assertFalse(self.tree_file().exists())

    def test_a_second_miss_saves_the_tree_and_asks(self) -> None:
        self.EXACT_ENTRY = ("option", self.ENTRA, services := self.result("Services (67)"))
        screen, box = self.typed_again_screen(appears_on=3)
        record, r = self.act(screen, self.SEARCH, self.ENTRA)
        self.assertEqual((record["outcome"], services.clicked, len(r.ask.prompts)), ("unknown", 0, 1))
        self.assertEqual(box.filled.count(self.ENTRA), 2)       # typed twice, not a third time
        self.assertIn("no results list identified", self.tree_file().read_text(encoding="utf-8"))

    def test_a_closed_window_is_not_a_missing_search_box(self) -> None:
        with self.assertRaises(run.PageClosed):
            self.act(Screen(), self.SEARCH, self.ENTRA, page=FakePage(closed=True))

    @staticmethod
    def box(role: str, name: str = "", placeholder: str = "", top: bool = False) -> dict:
        return {"role": role, "name": name, "placeholder": placeholder, "global": top}

    def test_the_blade_search_box_is_the_only_one_besides_the_top_search(self) -> None:
        top = self.box("searchbox", "Search", top=True)                       # in the top bar
        named_top = self.box("searchbox", "Search resources, services, and docs (G+/)")
        for boxes, expected in (
                ([named_top, self.box("searchbox", "Search by role name")], (1, None)),
                ([named_top], (None, "no search box on the open blade")),
                ([top, self.box("textbox", "Display name"), self.box("searchbox", "Search by role name")], (2, None)),
                ([self.box("textbox", "", "Filter by name"), self.box("textbox", "Group name")], (0, None)),
                ([self.box("textbox", "Search members")], (0, None)),
                ([top, self.box("textbox", "Display name")], (None, "no search box on the open blade")),
                ([], (None, "no search box on the open blade")),
                ([self.box("searchbox", "Search"), top, self.box("textbox", "", "Filter items")],
                 (None, "ambiguous: 2 search boxes ('Search', 'Filter items')"))):
            with self.subTest(boxes=boxes):
                self.assertEqual(run.choose_search_box(boxes), expected)

    BLADE_SEARCH = {"kind": "search", "labels": ["Owner"], "scope": "blade", "line": 191}

    def test_a_blade_search_types_into_its_box_and_checks_the_result_without_clicking_it(self) -> None:
        owner = ScreenNode()
        screen = Screen()
        box = ScreenNode(tag="input", tree='- searchbox "Search by role name, description, or ID"', text="old",
                         on_fill=lambda: screen.add(("text", "Owner", owner)))
        screen.add(("searchbox", "Search by role name, description, or ID", box),
                   ("textbox", "Display name", ScreenNode(tag="input", tree='- textbox "Display name"')))
        record, r = self.act(screen, self.BLADE_SEARCH, "Owner")
        self.assertEqual((record["kind"], record["outcome"], record["observed"]), ("search", "match", "Owner"))
        self.assertEqual((box.filled, owner.clicked, r.ask.prompts), (["Owner"], 0, []))

    def test_a_blade_search_does_not_take_text_listed_before_it_for_its_result(self) -> None:
        screen = Screen(("text", "Owner", ScreenNode()))                        # an unfiltered list's row
        box = ScreenNode(tag="input", tree='- searchbox "Search"')
        screen.add(("searchbox", "Search", box))
        record, _ = self.act(screen, self.BLADE_SEARCH, "Owner")
        self.assertEqual((record["outcome"], record["observed"]),
                         ("match", "'Owner' was listed before the search too; the search's effect is not confirmed"))

    def test_a_blade_search_with_a_results_list_looks_only_there(self) -> None:
        results = ScreenNode(attrs={"id": "roles"})
        box = ScreenNode(tag="input", tree='- searchbox "Search"', attrs={"aria-controls": "roles"},
                         on_fill=lambda: results.children.add(("text", "Owner", ScreenNode())))
        screen = Screen(("text", "Owner", ScreenNode()), ("searchbox", "Search", box), ("grid", "", results))
        record, _ = self.act(screen, self.BLADE_SEARCH, "Owner")
        self.assertEqual((record["outcome"], record["observed"]), ("match", "Owner"))   # the title outside is not it

    def test_a_blade_search_reads_the_list_only_once_it_has_settled(self) -> None:
        screen = Screen()
        box = ScreenNode(tag="input", tree='- searchbox "Search"')
        screen.add(("searchbox", "Search", box))
        page = self.LoadingPage(lambda n: n == 1 and screen.add(("text", "Owner", ScreenNode())))  # rows render late
        record, _ = self.act(screen, self.BLADE_SEARCH, "Owner", page=page)
        self.assertIn(run.UNCONFIRMED, record["observed"])                 # read as listed before the search
        self.assertGreaterEqual(page.now, run.SETTLE_MS / 1000)

    def test_the_top_bars_search_box_is_never_a_blades(self) -> None:
        top = ScreenNode(tag="input", tree='- searchbox "Search"')
        top.in_top_bar = True
        record, _ = self.act(Screen(("searchbox", "Search", top)), self.BLADE_SEARCH, "Owner")
        self.assertEqual((record["outcome"], record["observed"], top.filled),
                         ("unknown", "no search box on the open blade", []))

    def test_search_outcome(self) -> None:
        self.assertEqual(run.search_outcome("Owner", before=False, after=True), ("match", "Owner"))
        self.assertEqual(run.search_outcome("Owner", before=True, after=True),
                         ("match", "'Owner' was listed before the search too; the search's effect is not confirmed"))
        for before in (False, True):
            self.assertEqual(run.search_outcome("Owner", before=before, after=False),
                             ("unknown", "no result for 'Owner' after the search"))

    def test_a_blade_search_without_a_result_or_a_box_or_with_two_boxes_is_unknown(self) -> None:
        box = ScreenNode(tag="input", tree='- searchbox "Search"')
        record, _ = self.act(Screen(("searchbox", "Search", box)), self.BLADE_SEARCH, "Owner")
        self.assertEqual((record["outcome"], record["observed"]), ("unknown", "no result for 'Owner' after the search"))
        record, _ = self.act(Screen(("textbox", "Display name", ScreenNode(tree='- textbox "Display name"'))),
                             self.BLADE_SEARCH, "Owner")
        self.assertEqual((record["outcome"], record["observed"]), ("unknown", "no search box on the open blade"))
        two = Screen(("searchbox", "Search", ScreenNode(tree='- searchbox "Search"')),
                     ("textbox", "Filter", ScreenNode(tree='- textbox "Filter by name"')))
        record, r = self.act(two, self.BLADE_SEARCH, "Owner")
        self.assertEqual((record["outcome"], record["observed"], r.ask.prompts),
                         ("unknown", "ambiguous: 2 search boxes ('Search', 'Filter by name')", []))

    def test_a_search_without_a_scope_is_the_global_search(self) -> None:
        self.assertNotIn("scope", self.SEARCH)                               # steps.json from before scopes
        record, _ = self.act(Screen(), self.SEARCH, self.ENTRA)
        self.assertIn("search box is not on screen", record["observed"])     # search_portal's own reason

    UPN = {"kind": "field", "label": "User principal name", "value": "x", "line": 4}
    UPN_VALUE = "malfurion.stormrage@contoso.onmicrosoft.com"

    def upn_screen(self, shown: str, offered=()) -> tuple[Screen, ScreenNode, ScreenNode]:
        """The Portal's 'User principal name': a labelled <div> holding a text box, an '@' and a
        domain combo box showing `shown`; opening the combo box lists `offered`."""
        local = ScreenNode(tag="input")
        domain = ScreenNode(attrs={"role": "combobox"}, text=shown)
        screen = Screen()

        def open_list() -> None:
            for name in offered:
                screen.add(("option", name, ScreenNode(on_click=lambda name=name: setattr(domain, "text", name))))
        domain.on_click = open_list
        container = ScreenNode(children=Screen(("textbox", "", local), ("text", "@", ScreenNode(interactive=False)),
                                               ("combobox", "", domain)))
        screen.add(("label", "User principal name", container),
                   ("textbox", "User principal name", local))   # the container still wins: it holds the domain
        return screen, local, domain

    def test_a_user_principal_name_is_split_over_name_and_domain(self) -> None:
        screen, local, domain = self.upn_screen("Contoso.onmicrosoft.com")    # preselected, other case
        record, _ = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
        self.assertEqual((record["outcome"], local.filled, domain.clicked), ("match", ["malfurion.stormrage"], 0))

    def test_a_domain_not_shown_is_picked_from_the_combo_box(self) -> None:
        screen, local, domain = self.upn_screen("fabrikam.example", offered=["fabrikam.example", "CONTOSO.onmicrosoft.com"])
        record, _ = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
        self.assertEqual((record["outcome"], local.filled, domain.clicked), ("match", ["malfurion.stormrage"], 1))
        self.assertEqual(domain.text, "CONTOSO.onmicrosoft.com")

    def test_a_domain_not_offered_is_unknown_and_nothing_is_typed(self) -> None:
        screen, local, _ = self.upn_screen("fabrikam.example", offered=["fabrikam.example"])
        record, _ = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
        self.assertEqual((record["outcome"], local.filled), ("unknown", []))     # the domain comes first
        self.assertIn("the domain combo box: option 'contoso.onmicrosoft.com' not found", record["observed"])

    def test_a_domain_option_that_does_not_take_is_unknown(self) -> None:
        screen, _, domain = self.upn_screen("fabrikam.example", offered=["contoso.onmicrosoft.com"])
        domain.on_click = lambda: screen.add(("option", "contoso.onmicrosoft.com", ScreenNode()))   # clicking it changes nothing
        record, _ = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("was clicked, but the field shows 'fabrikam.example'", record["observed"])

    def test_a_domain_the_field_shows_late_is_waited_for(self) -> None:
        screen, local, domain = self.upn_screen("fabrikam.example")
        option = ScreenNode(on_click=lambda: setattr(domain, "later", (3, "contoso.onmicrosoft.com")))
        domain.on_click = lambda: screen.add(("option", "contoso.onmicrosoft.com", option))
        record, _ = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
        self.assertEqual((record["outcome"], option.clicked, local.filled), ("match", 1, ["malfurion.stormrage"]))

    def test_a_column_sort_button_or_a_plain_button_is_never_a_field(self) -> None:
        # Step 1.1.4 on the Users list: the 'User principal name' column header sorts the list.
        for role, node in (("label", ScreenNode(tag="button", in_header=True)),       # sort button
                           ("label", ScreenNode(tag="button")),                       # plain button
                           ("label", ScreenNode(attrs={"role": "button"})),           # role=button
                           ("combobox", ScreenNode(attrs={"role": "combobox"}, in_header=True))):
            with self.subTest(role=role, attrs=node.attrs, in_header=node.in_header):
                screen = Screen((role, "User principal name", node))
                record, r = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
                self.assertEqual((record["outcome"], node.clicked, len(r.ask.prompts)), ("unknown", 0, 1))
                self.assertEqual(record["observed"], "no answer (input closed)")   # asked, not 'option not found'

    DESCRIPTION = {"kind": "field", "label": "Group description", "value": "x", "line": 6}

    def test_of_several_labelled_elements_the_one_that_takes_a_value_is_the_field(self) -> None:
        # Step 1.1.6, New Group: the text area and the info icon next to its label share the name.
        for info in (ScreenNode(tag="button", attrs={"aria-expanded": "false"}),   # a callout button
                     ScreenNode(tag="i"),                                           # an icon container
                     ScreenNode(tag="button", attrs={"aria-haspopup": "true"})):   # opens a callout
            with self.subTest(info=info.attrs, tag=info.tag):
                area = ScreenNode(tag="textarea")
                screen = Screen(("label", "Group description", area), ("label", "Group description", info))
                record, _ = self.act(screen, self.DESCRIPTION, "Group description", value="Admins of SkyCraft")
                self.assertEqual((record["outcome"], area.filled, info.clicked), ("match", ["Admins of SkyCraft"], 0))

    def test_a_button_that_opens_a_list_wins_only_when_nothing_takes_a_value(self) -> None:
        dropdown = ScreenNode(tag="button", attrs={"aria-haspopup": "listbox"})
        icon = ScreenNode(tag="button", attrs={"aria-expanded": "false"})
        with mock.patch.object(run, "all_frames", lambda page: [Screen(("label", "Group type", dropdown),
                                                                     ("label", "Group type", icon))]):
            self.assertIs(run.find_exact(FakePage(), "Group type", field=True), dropdown)

    def test_two_fields_of_one_label_stay_ambiguous_and_say_what_they_are(self) -> None:
        screen = Screen(("label", "Group description", ScreenNode(tag="textarea")),
                        ("label", "Group description", ScreenNode(tag="input", attrs={"type": "text"})),
                        ("label", "Group description", ScreenNode(tag="button", attrs={"aria-haspopup": "true"})))
        record, _ = self.act(screen, self.DESCRIPTION, "Group description", value="x")
        self.assertEqual(record["outcome"], "unknown")
        self.assertEqual(record["observed"], "ambiguous: 3 visible elements match (textarea, input[type=text], button) "
                                             "named 'Group description'")

    def test_an_element_that_cannot_be_inspected_keeps_the_match_ambiguous(self) -> None:
        screen = Screen(("label", "Group description", ScreenNode(tag="textarea")),
                        ("label", "Group description", ScreenNode(tag="input", uninspectable=True)))
        record, _ = self.act(screen, self.DESCRIPTION, "Group description", value="x")
        self.assertEqual((record["outcome"], record["observed"]),
                         ("unknown", "ambiguous: 2 visible elements match (textarea, ?) named 'Group description'"))

    def test_a_contenteditable_element_takes_a_value(self) -> None:
        editor = ScreenNode(editable=True)
        callout = ScreenNode(tag="button", attrs={"aria-haspopup": "true"})
        with mock.patch.object(run, "all_frames", lambda page: [Screen(("label", "Group description", editor),
                                                                     ("label", "Group description", callout))]):
            self.assertIs(run.find_exact(FakePage(), "Group description", field=True), editor)

    def test_a_button_that_opens_a_list_is_a_field(self) -> None:
        for attrs, controls_role in (({"aria-haspopup": "listbox"}, ""), ({"aria-haspopup": "true"}, ""),
                                     ({"aria-haspopup": "menu"}, ""),
                                     ({"aria-expanded": "false", "aria-controls": "list"}, "listbox"),
                                     ({"aria-expanded": "false", "aria-owns": "list"}, "menu")):
            with self.subTest(attrs=attrs):
                dropdown = ScreenNode(tag="button", attrs=attrs, controls_role=controls_role)
                with mock.patch.object(run, "all_frames", lambda page: [Screen(("label", "Group type", dropdown))]):
                    self.assertIs(run.find_exact(FakePage(), "Group type", field=True), dropdown)

    def test_aria_expanded_alone_does_not_make_a_button_a_field(self) -> None:
        for attrs, controls_role in (({"aria-expanded": "false"}, ""),                         # an info callout
                                     ({"aria-expanded": "false", "aria-controls": "tip"}, "dialog")):
            with self.subTest(attrs=attrs):
                button = ScreenNode(tag="button", attrs=attrs, controls_role=controls_role)
                with mock.patch.object(run, "all_frames", lambda page: [Screen(("label", "Group type", button))]):
                    self.assertIsNone(run.find_exact(FakePage(), "Group type", field=True))

    PASSWORD = {"kind": "field", "label": "Auto-generate password", "value": "☐ Unchecked", "line": 7}
    INTERCEPTED = run.PlaywrightError(
        'Timeout 2000ms exceeded.\n  - <i data-icon-name="CheckMark" class="ms-Checkbox-checkmark"> from '
        '<label for="checkbox-72" class="ms-Checkbox-label"> subtree intercepts pointer events')

    def check_box(self, label_toggles: bool = True, has_label: bool = True, error=None):
        """Step 1.1.2's Fluent UI check box, ticked, whose tick mark intercepts the click."""
        box = ScreenNode(tag="input", attrs={"role": "checkbox", "type": "checkbox", "id": "checkbox-72"},
                         checked=True, check_error=error or self.INTERCEPTED)
        if has_label:
            box.label = ScreenNode(on_click=(lambda: setattr(box, "checked", not box.checked)) if label_toggles else None,
                                   label_for=box)
        return Screen(("checkbox", "Auto-generate password", box)), box

    def test_an_intercepted_check_box_is_set_through_its_label_once(self) -> None:
        screen, box = self.check_box()
        record, r = self.act(screen, self.PASSWORD, "Auto-generate password", value="☐ Unchecked")
        self.assertEqual((record["outcome"], box.checked, box.label.clicked, r.ask.prompts), ("match", False, 1, []))

    def test_a_label_click_that_does_not_take_is_unknown_and_never_repeated(self) -> None:
        screen, box = self.check_box(label_toggles=False)
        record, _ = self.act(screen, self.PASSWORD, "Auto-generate password", value="☐ Unchecked")
        self.assertEqual((record["outcome"], box.checked, box.label.clicked), ("unknown", True, 1))
        self.assertIn("its label was clicked to make it unchecked, but it is still checked", record["observed"])

    def test_an_intercepted_check_box_without_a_label_is_unknown(self) -> None:
        screen, box = self.check_box(has_label=False)
        record, _ = self.act(screen, self.PASSWORD, "Auto-generate password", value="☐ Unchecked")
        self.assertEqual((record["outcome"], box.checked), ("unknown", True))
        self.assertIn("was intercepted (Timeout 2000ms exceeded.), and it has no label to click", record["observed"])

    def test_a_label_that_is_not_the_one_for_this_input_is_never_clicked(self) -> None:
        for case, why in (("two", "it has 2 labels on screen, not one"),
                          ("other", "its label belongs to another control"),
                          ("link", "its label holds a link, which a click could follow")):
            with self.subTest(case=case):
                screen, box = self.check_box()
                if case == "two":
                    box.more_labels = [ScreenNode(label_for=box)]
                elif case == "other":
                    box.label.label_for = ScreenNode()
                else:
                    box.label.has_link = True
                record, _ = self.act(screen, self.PASSWORD, "Auto-generate password", value="☐ Unchecked")
                self.assertEqual((record["outcome"], box.checked, box.label.clicked), ("unknown", True, 0))
                self.assertIn(f"was intercepted (Timeout 2000ms exceeded.), and {why}", record["observed"])

    def test_a_late_click_is_waited_for_and_not_toggled_back(self) -> None:
        screen, box = self.check_box()
        box.flips_after = 3                                              # the 4th read shows it cleared
        record, r = self.act(screen, self.PASSWORD, "Auto-generate password", value="☐ Unchecked")
        self.assertEqual((record["outcome"], box.checked, box.label.clicked), ("match", False, 0))

    def test_any_other_check_box_failure_does_not_click_the_label(self) -> None:
        screen, box = self.check_box(error=run.PlaywrightError("Element is not attached to the DOM"))
        record, _ = self.act(screen, self.PASSWORD, "Auto-generate password", value="☐ Unchecked")
        self.assertEqual((record["outcome"], box.label.clicked), ("unknown", 0))
        self.assertIn("Element is not attached to the DOM", record["observed"])

    def test_a_read_only_field_is_unknown_at_once(self) -> None:
        field = ScreenNode(tag="input", read_only=True)
        screen = Screen(("textbox", "Mail nickname", field))
        record, _ = self.act(screen, dict(self.UPN, label="Mail nickname"), "Mail nickname", value="malfurion")
        self.assertEqual((record["outcome"], record["observed"], field.filled),
                         ("unknown", "read-only: 'Mail nickname'", []))
        field.text = "malfurion"                                   # read-only, but already right
        record, _ = self.act(screen, dict(self.UPN, label="Mail nickname"), "Mail nickname", value="malfurion")
        self.assertEqual((record["outcome"], record["observed"]), ("match", "already set"))

    def test_a_domain_offered_twice_is_ambiguous(self) -> None:
        screen, local, _ = self.upn_screen("fabrikam.example", offered=["contoso.onmicrosoft.com"] * 2)
        record, _ = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
        self.assertEqual((record["outcome"], local.filled), ("unknown", []))
        self.assertTrue(record["observed"].startswith("Ambiguous: 2 visible elements match"), record["observed"])

    def test_options_are_looked_up_in_the_list_the_combo_box_controls(self) -> None:
        screen, local, domain = self.upn_screen("fabrikam.example")
        elsewhere = ScreenNode()
        screen.add(("option", "contoso.onmicrosoft.com", elsewhere))       # another list on the page
        in_list = ScreenNode(on_click=lambda: setattr(domain, "text", "contoso.onmicrosoft.com"))
        listbox = ScreenNode(attrs={"id": "domains"}, children=Screen())
        domain.attrs["aria-controls"] = "domains"
        domain.on_click = lambda: (screen.add(("listbox", "", listbox)),
                                   listbox.children.add(("option", "contoso.onmicrosoft.com", in_list)))
        record, _ = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
        self.assertEqual((record["outcome"], in_list.clicked, elsewhere.clicked), ("match", 1, 0))
        self.assertEqual(local.filled, ["malfurion.stormrage"])

    def test_a_labelled_container_with_one_text_box_fills_it(self) -> None:
        inner = ScreenNode(tag="input")
        screen = Screen(("label", "Display name", ScreenNode(children=Screen(("textbox", "", inner)))))
        record, _ = self.act(screen, dict(self.UPN, label="Display name"), "Display name", value="Malfurion")
        self.assertEqual((record["outcome"], inner.filled), ("match", ["Malfurion"]))

    def test_any_other_labelled_container_is_unknown(self) -> None:
        screen = Screen(("label", "Display name", ScreenNode(children=Screen(("textbox", "", ScreenNode(tag="input")),
                                                                             ("textbox", "", ScreenNode(tag="input"))))))
        record, _ = self.act(screen, dict(self.UPN, label="Display name"), "Display name", value="Malfurion")
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("holds 2 text box(es), 0 combo box(es) and 0 radio(s)", record["observed"])

    PERFORMANCE = {"kind": "field", "label": "Performance", "value": "x", "line": 8}

    @staticmethod
    def radio(name: str, native: bool = True, checked: bool = False) -> tuple[str, str, ScreenNode]:
        """One option of a radio group, as Fluent UI's ChoiceGroup draws it (native: an
        <input type=radio> named by its <label for>) or as a [role=radio] element that carries
        aria-checked; either way get_by_role('radio') finds it and aria_snapshot() names it."""
        attrs = {"type": "radio", "id": f"choice-{name}"} if native else {"role": "radio"}
        node = ScreenNode(tag="input" if native else "div", attrs=attrs, checked=checked,
                          tree=snapshot_line("radio", name, "[checked]" if checked else ""))
        return "radio", name, node

    def radio_group(self, *options, extra=()) -> tuple[Screen, list[ScreenNode]]:
        """A storage account's 'Performance': a [role=radiogroup] labelled by the field's label,
        holding `options` (radio()) and anything in `extra`."""
        group = ScreenNode(attrs={"role": "radiogroup"}, children=Screen(*options, *extra))
        return Screen(("label", "Performance", group)), [node for _, _, node in options]

    def test_a_radio_group_picks_the_radio_named_as_the_value(self) -> None:
        for native in (True, False):
            for value in ("Premium", "  premium "):              # regardless of case and surrounding spaces
                with self.subTest(native=native, value=value):
                    screen, (standard, premium) = self.radio_group(self.radio("Standard", native, checked=True),
                                                                   self.radio("Premium", native))
                    record, r = self.act(screen, self.PERFORMANCE, "Performance", value=value)
                    self.assertEqual((record["outcome"], record["observed"], r.ask.prompts),
                                     ("match", "Performance", []))
                    self.assertEqual((premium.checked, standard.clicked, premium.clicked), (True, 0, 0))

    def test_a_radio_already_selected_is_already_set(self) -> None:
        screen, (standard, premium) = self.radio_group(self.radio("Standard", checked=True), self.radio("Premium"))
        standard.check_error = AssertionError("set_checked() called on the radio already selected")
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="standard")
        self.assertEqual((record["outcome"], record["observed"], premium.checked), ("match", "already set", False))

    def test_an_intercepted_radio_is_selected_through_its_label(self) -> None:
        screen, (standard, premium) = self.radio_group(self.radio("Standard", checked=True), self.radio("Premium"))
        premium.check_error = self.INTERCEPTED
        premium.label = ScreenNode(on_click=lambda: setattr(premium, "checked", True), label_for=premium)
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Premium")
        self.assertEqual((record["outcome"], premium.checked, premium.label.clicked), ("match", True, 1))

    ENFORCEMENT = {"kind": "field", "label": "Policy enforcement", "value": "x", "line": 8}

    def enforcement(self, groups: int = 1) -> tuple[Screen, list[ScreenNode], list[ScreenNode]]:
        """Run B's blade-1.3.5: a <label>, a wrapper <div> and `groups` radiogroup(s) of one name,
        'Default (enforcement)' selected among Default, Do not enforce and Enroll."""
        screen = Screen(("label", "Policy enforcement", ScreenNode(tag="label")),
                        ("label", "Policy enforcement", ScreenNode(tag="div")))
        radios, groupnodes = [], []
        for _ in range(groups):
            options = [self.radio("Default (enforcement)", checked=True), self.radio("Do not enforce"),
                       self.radio("Enroll")]
            group = ScreenNode(attrs={"role": "radiogroup"}, children=Screen(*options))
            screen.add(("label", "Policy enforcement", group))
            radios.append([node for _, _, node in options])
            groupnodes.append(group)
        return screen, radios[0], groupnodes

    def test_policy_enforcement_label_div_and_radiogroup_take_the_radiogroup(self) -> None:
        screen, radios, _ = self.enforcement()
        radios[0].check_error = AssertionError("set_checked() called on the radio already selected")
        record, _ = self.act(screen, self.ENFORCEMENT, "Policy enforcement", value="Default (enforcement)")
        self.assertEqual((record["outcome"], record["observed"]), ("match", "already set"))

    def test_do_not_enforce_is_selected(self) -> None:
        screen, radios, _ = self.enforcement()
        record, _ = self.act(screen, self.ENFORCEMENT, "Policy enforcement", value="Do not enforce")
        self.assertEqual((record["outcome"], radios[1].checked, radios[2].checked), ("match", True, False))

    def test_two_radiogroups_of_the_name_stay_ambiguous(self) -> None:
        screen, radios, _ = self.enforcement(groups=2)
        record, _ = self.act(screen, self.ENFORCEMENT, "Policy enforcement", value="Do not enforce")
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("4 visible elements match", record["observed"])
        self.assertFalse(radios[1].checked)

    def test_a_radio_group_without_the_value_names_its_options(self) -> None:
        screen, radios = self.radio_group(self.radio("Standard", checked=True), self.radio("Premium"))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Hot (for daily use)")
        self.assertEqual((record["outcome"], [radio.checked for radio in radios]), ("unknown", [True, False]))
        self.assertEqual(record["observed"], "LookupError: no radio is named 'Hot (for daily use)'; "
                                             "the options are 'Standard', 'Premium'")

    def test_two_radios_of_the_value_are_ambiguous(self) -> None:
        screen, radios = self.radio_group(self.radio("Standard"), self.radio("standard"), self.radio("Premium"))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Standard")
        self.assertEqual((record["outcome"], [radio.checked for radio in radios]), ("unknown", [False, False, False]))
        self.assertEqual(record["observed"], "Ambiguous: 2 radios match 'Standard'")

    def test_a_radio_group_with_a_text_box_picks_a_radio_and_never_types(self) -> None:
        # An 'Other' option with its own text box: the value still names a radio.
        box = ScreenNode(tag="input")
        screen, radios = self.radio_group(self.radio("Standard"), self.radio("Other"), extra=[("textbox", "", box)])
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Other")
        self.assertEqual((record["outcome"], [radio.checked for radio in radios], box.filled),
                         ("match", [False, True], []))
        box = ScreenNode(tag="input")
        screen, radios = self.radio_group(self.radio("Standard"), self.radio("Other"), extra=[("textbox", "", box)])
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Premium")
        self.assertEqual((record["outcome"], [radio.checked for radio in radios], box.filled),
                         ("unknown", [False, False], []))
        self.assertEqual(record["observed"], "LookupError: no radio is named 'Premium'; "
                                             "the options are 'Standard', 'Other'")

    def test_a_user_principal_name_beside_a_radio_is_no_field(self) -> None:
        local, domain = ScreenNode(tag="input"), ScreenNode(attrs={"role": "combobox"}, text="contoso.onmicrosoft.com")
        _, _, radio = self.radio("Invite")
        container = ScreenNode(children=Screen(("textbox", "", local), ("combobox", "", domain),
                                               ("radio", "Invite", radio)))
        screen = Screen(("label", "User principal name", container))
        record, _ = self.act(screen, self.UPN, "User principal name", value=self.UPN_VALUE)
        self.assertEqual((record["outcome"], local.filled, domain.clicked, radio.checked), ("unknown", [], 0, False))
        self.assertIn("holds 1 text box(es), 1 combo box(es) and 1 radio(s)", record["observed"])

    STANDARD = "Standard: Recommended for most scenarios (general-purpose v2 account)"
    PREMIUM = "Premium: Recommended for scenarios that require low latency."

    def test_a_value_names_a_radio_by_the_part_before_its_colon(self) -> None:
        # Step 4.1.2: the Portal names the radios after their description.
        screen, (standard, premium) = self.radio_group(self.radio(self.STANDARD), self.radio(self.PREMIUM))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value=" standard ")
        self.assertEqual((record["outcome"], standard.checked, premium.checked), ("match", True, False))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Standard")
        self.assertEqual((record["outcome"], record["observed"]), ("match", "already set"))

    def test_an_exact_name_wins_over_a_part_before_a_colon(self) -> None:
        screen, (exact, prefixed) = self.radio_group(self.radio("Standard"), self.radio("Standard: legacy"))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Standard")
        self.assertEqual((record["outcome"], exact.checked, prefixed.checked), ("match", True, False))

    def test_two_radios_of_the_part_before_a_colon_are_ambiguous(self) -> None:
        screen, radios = self.radio_group(self.radio("Standard: HDD"), self.radio("Standard: legacy"),
                                          self.radio(self.PREMIUM))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Standard")
        self.assertEqual((record["outcome"], [radio.checked for radio in radios]), ("unknown", [False, False, False]))
        self.assertEqual(record["observed"], "Ambiguous: 2 radios match 'Standard'")

    def test_a_remark_after_the_value_is_dropped_when_nothing_else_matches(self) -> None:
        # Step 3.2.4: '| Public inbound ports | None (NSG already on subnet) |'.
        screen, (none, allow) = self.radio_group(self.radio("None"), self.radio("Allow selected ports"))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="None (NSG already on subnet)")
        self.assertEqual((record["outcome"], none.checked, allow.checked), ("match", True, False))
        screen, (with_remark, bare) = self.radio_group(self.radio("None (NSG already on subnet)"), self.radio("None"))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="None (NSG already on subnet)")
        self.assertEqual((record["outcome"], with_remark.checked, bare.checked), ("match", True, False))   # whole first
        screen, (standard, premium) = self.radio_group(self.radio(self.STANDARD), self.radio(self.PREMIUM))
        record, _ = self.act(screen, self.PERFORMANCE, "Performance", value="Premium (for the lab)")
        self.assertEqual((record["outcome"], standard.checked, premium.checked), ("match", False, True))   # then a part

    def radio_field(self, name: str, checked: bool = False) -> tuple[Screen, ScreenNode, dict]:
        """A radio that find_field finds by its own name: the field's label is the radio's name."""
        _, _, radio = self.radio(name, checked=checked)
        return Screen(("radio", name, radio)), radio, dict(self.PERFORMANCE, label=name)

    def test_a_radio_found_as_the_field_is_selected_by_a_checked_value_or_its_name(self) -> None:
        for value in ("✅ Checked", "Allow selected ports", "allow selected ports (SSH only)"):
            with self.subTest(value=value):
                screen, radio, item = self.radio_field("Allow selected ports")
                record, _ = self.act(screen, item, item["label"], value=value)
                self.assertEqual((record["outcome"], radio.checked), ("match", True))
        screen, radio, item = self.radio_field(self.STANDARD)
        record, _ = self.act(screen, item, item["label"], value="Standard")
        self.assertEqual((record["outcome"], radio.checked), ("match", True))
        for name in ("Disabled", "No"):              # its name is read before the checkbox state
            with self.subTest(name=name):
                screen, radio, item = self.radio_field(name)
                record, _ = self.act(screen, item, item["label"], value=name)
                self.assertEqual((record["outcome"], radio.checked), ("match", True))
        screen, radio, item = self.radio_field("Allow selected ports", checked=True)
        radio.check_error = AssertionError("set_checked() called on a radio already selected")
        record, _ = self.act(screen, item, item["label"], value="Allow selected ports")
        self.assertEqual((record["outcome"], record["observed"]), ("match", "already set"))

    def test_a_radio_found_as_the_field_is_never_cleared(self) -> None:
        screen, radio, item = self.radio_field("Allow selected ports", checked=True)
        radio.check_error = AssertionError("set_checked() called to clear a radio")
        record, _ = self.act(screen, item, item["label"], value="☐ Unchecked")
        self.assertEqual((record["outcome"], radio.checked), ("unknown", True))
        self.assertEqual(record["observed"], "LookupError: a radio cannot be cleared; pick another option")
        screen, radio, item = self.radio_field("Allow selected ports")                  # not selected: nothing to do
        radio.check_error = AssertionError("set_checked() called on a radio not selected")
        record, _ = self.act(screen, item, item["label"], value="☐ Unchecked")
        self.assertEqual((record["outcome"], record["observed"], radio.checked), ("match", "already set", False))

    def test_a_radio_found_as_the_field_with_another_value_is_unknown(self) -> None:
        screen, radio, item = self.radio_field("Allow selected ports")
        record, _ = self.act(screen, item, item["label"], value="HTTPS (443)")
        self.assertEqual((record["outcome"], radio.checked), ("unknown", False))
        self.assertEqual(record["observed"], "LookupError: 'HTTPS (443)' is neither a checkbox state nor "
                                             "this radio's name, 'Allow selected ports'")

    def test_a_text_box_of_the_label_is_preferred_to_a_container(self) -> None:
        for second in ("textbox", "label"):          # named by role, or labelled as well
            with self.subTest(second=second):
                container, input_ = ScreenNode(), ScreenNode(tag="input")
                screen = Screen(("label", "Display name", container), (second, "Display name", input_))
                record, _ = self.act(screen, dict(self.UPN, label="Display name"), "Display name", value="Malfurion")
                self.assertEqual((record["outcome"], input_.filled), ("match", ["Malfurion"]))
        input_ = ScreenNode(tag="input")                  # two labelled containers: the text box still decides
        screen = Screen(("label", "Display name", ScreenNode()), ("label", "Display name", ScreenNode()),
                        ("textbox", "Display name", input_))
        record, _ = self.act(screen, dict(self.UPN, label="Display name"), "Display name", value="Malfurion")
        self.assertEqual((record["outcome"], input_.filled), ("match", ["Malfurion"]))

    def test_a_leading_plus_is_dropped_when_nothing_has_the_full_name(self) -> None:
        item = {"kind": "navigation", "labels": ["+ New user", "Create new user"], "line": 3}
        toolbar = ScreenNode()
        record, r = self.act(Screen(("menuitem", "New user", toolbar)), item, "+ New user")
        self.assertEqual((record["outcome"], record["severity"], record["observed"]), ("match", None, "+ New user"))
        self.assertEqual((toolbar.clicked, r.ask.prompts), (1, []))
        self.assertEqual(self.recording["steps"]["9.9.1"]["labels"], {})     # exact: nothing to record
        full, bare = ScreenNode(), ScreenNode()
        with mock.patch.object(run, "all_frames", lambda page: [Screen(("button", "+ Add", full), ("button", "Add", bare))]):
            self.assertIs(run.find_exact(FakePage(), "+ Add"), full)       # the full name first
        with mock.patch.object(run, "all_frames", lambda page: [Screen(("button", "+", bare))]):
            self.assertIs(run.find_exact(FakePage(), "+"), bare)           # nothing left to look up

    def test_plain_text_counts_only_inside_an_interactive_element(self) -> None:
        caption, link_text = ScreenNode(interactive=False), ScreenNode(interactive=True)
        with mock.patch.object(run, "all_frames", lambda page: [Screen(("text", "Users", caption))]):
            self.assertIsNone(run.find_exact(FakePage(), "Users"))          # the overview's static caption
        with mock.patch.object(run, "all_frames", lambda page: [Screen(("text", "Users", caption),
                                                                     ("text", "Users", link_text))]):
            self.assertIs(run.find_exact(FakePage(), "Users"), link_text)   # the caption does not make it two
        with mock.patch.object(run, "all_frames", lambda page: [Screen(("text", "Users", link_text),
                                                                     ("text", "Users", ScreenNode()))]):
            self.assertIsNone(run.find_exact(FakePage(), "Users"))          # two links: not found, not a guess
        # '<a>Users<span> (preview)</span></a>': the whole text is not 'Users', whatever its own text node says.
        with mock.patch.object(run, "all_frames", lambda page: [Screen(("text", "Users (preview)", link_text))]):
            self.assertIsNone(run.find_exact(FakePage(), "Users"))
        captured = []
        scope = Screen(("text", "Users", link_text))
        with mock.patch.object(Screen, "get_by_text", lambda self, text, exact=None: captured.append((text, exact))
                               or Screen._find(self, "text", text)):
            self.assertEqual(run.interactive_text(scope, "Users").nodes, [link_text])
        self.assertEqual(captured, [("Users", True)])                       # get_by_text, exact: the whole text

    NAVIGATION = {"kind": "navigation", "labels": ["Users", "All users"], "line": 1}

    def test_collapsed_menu_groups_are_expanded_once_before_the_person_is_asked(self) -> None:
        users, all_users = ScreenNode(), ScreenNode()
        screen = Screen(("text", "Users", ScreenNode(interactive=False)))
        expand = ScreenNode(on_click=lambda: screen.add(("link", "Users", users),
                                                        ("button", "Collapse all headers", ScreenNode())))
        screen.add(("button", "Expand all headers", expand), ("button", "Toggle Manage", ScreenNode()))
        record, r = self.act(screen, self.NAVIGATION, "Users")
        self.assertEqual((record["outcome"], record["observed"]), ("match", "Users"))
        self.assertEqual((expand.clicked, users.clicked, r.ask.prompts), (1, 1, []))
        self.assertEqual(self.recording["steps"]["9.9.1"]["labels"], {})     # exact: nothing to record
        # The same item's next label is not on screen: no second expansion, the person is asked.
        record, r = self.act(screen, self.NAVIGATION, "All users", runner=r)
        self.assertEqual((record["outcome"], expand.clicked, len(r.ask.prompts)), ("unknown", 1, 1))
        screen.add(("link", "All users", all_users))
        record, _ = self.act(screen, self.NAVIGATION, "All users", runner=r)
        self.assertEqual((record["outcome"], all_users.clicked), ("match", 1))
        self.assertIsNone(run.DESTRUCTIVE.search(run.EXPAND_ALL))

    def test_without_an_expand_button_the_person_is_asked_at_once(self) -> None:
        toggle = ScreenNode()
        screen = Screen(("text", "Users", ScreenNode(interactive=False)), ("button", "Toggle Manage", toggle))
        record, r = self.act(screen, self.NAVIGATION, "Users", candidates=[run.Candidate("button", "Toggle Manage")])
        self.assertEqual((record["outcome"], toggle.clicked, len(r.ask.prompts)), ("unknown", 0, 1))
        self.assertFalse(r.expanded)

    def test_every_item_of_a_step_may_expand_the_menu_once(self) -> None:
        links = [("link", "Users", ScreenNode()), ("link", "Groups", ScreenNode())]
        screen = Screen()
        expand = ScreenNode(on_click=lambda: screen.add(links.pop(0)))
        screen.add(("button", "Expand all headers", expand))
        step = {"id": "9.9.1", "title": "One", "expected": None, "images": [],
                "items": [{"kind": "action", "labels": ["Users"], "line": 1},
                          {"kind": "action", "labels": ["Groups"], "line": 2}]}
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now):
            self.assertTrue(self.quietly(lambda: r.run_step(step)))
        self.assertEqual(expand.clicked, 2)

    def test_a_label_behind_a_collapsed_group_is_found_soon_after_expanding(self) -> None:
        users = ScreenNode()
        screen = Screen()
        expand = ScreenNode(on_click=lambda: screen.add(("link", "Users", users),
                                                        ("button", "Collapse all headers", ScreenNode())))
        screen.add(("button", "Expand all headers", expand))
        record, r = self.act(screen, self.NAVIGATION, "Users")
        self.assertEqual((record["outcome"], users.clicked, expand.clicked, r.ask.prompts), ("match", 1, 1, []))
        found_at = r.page.now - run.SETTLE_MS / 1000                       # clicking Users waits SETTLE_MS
        self.assertLess(found_at, run.SETTLE_MS / 1000 + 0.6)            # not the whole FIND_TIMEOUT_MS

    def test_a_label_that_never_appears_expands_once_and_asks_at_the_deadline(self) -> None:
        screen = Screen()
        expand = ScreenNode(on_click=lambda: screen.add(("button", "Collapse all headers", ScreenNode())))
        screen.add(("button", "Expand all headers", expand))
        record, r = self.act(screen, self.NAVIGATION, "Users")
        self.assertEqual((record["outcome"], expand.clicked, len(r.ask.prompts)), ("unknown", 1, 1))
        self.assertGreaterEqual(r.page.now, run.FIND_TIMEOUT_MS / 1000)

    class LoadingPage(FakePage):
        """A page whose blade is still rendering: `on_wait(n)` runs at its n-th wait."""

        def __init__(self, on_wait) -> None:
            super().__init__()
            self.waits = 0
            self.on_wait = on_wait

        def wait_for_timeout(self, ms) -> None:
            super().wait_for_timeout(ms)
            self.waits += 1
            self.on_wait(self.waits)

    def test_an_element_that_renders_late_is_used_without_asking(self) -> None:
        create = ScreenNode()
        screen = Screen()
        page = self.LoadingPage(lambda n: n == 2 and screen.add(("button", "Create", create)))
        record, r = self.act(screen, {"kind": "action", "labels": ["Create"], "line": 1}, "Create", page=page)
        self.assertEqual((record["outcome"], create.clicked, r.ask.prompts), ("match", 1, []))
        self.assertEqual(page.waits - 1, 2)                       # found on the third look; then SETTLE_MS
        field = ScreenNode(tag="input")
        screen = Screen()
        page = self.LoadingPage(lambda n: n == 2 and screen.add(("textbox", "Group name", field)))
        record, r = self.act(screen, {"kind": "field", "label": "Group name", "value": "x", "line": 2},
                             "Group name", page=page, value="SkyCraft-Admins")
        self.assertEqual((record["outcome"], field.filled, r.ask.prompts), ("match", ["SkyCraft-Admins"], []))

    def test_an_ambiguity_that_clears_before_the_deadline_is_not_reported(self) -> None:
        kept, gone = ScreenNode(), ScreenNode()
        screen = Screen(("button", "Create", kept), ("button", "Create", gone))
        page = self.LoadingPage(lambda n: n == 1 and screen.entries.pop())   # the old blade goes away
        record, _ = self.act(screen, {"kind": "action", "labels": ["Create"], "line": 1}, "Create", page=page)
        self.assertEqual((record["outcome"], kept.clicked, gone.clicked), ("match", 1, 0))
        screen = Screen(("button", "Create", ScreenNode()), ("button", "Create", ScreenNode()))
        record, r = self.act(screen, {"kind": "action", "labels": ["Create"], "line": 1}, "Create")
        self.assertEqual((record["outcome"], record["observed"], r.ask.prompts),
                         ("unknown", "ambiguous: 2 visible elements match named 'Create'", []))

    TOP_BAR = ('- banner:\n'
               '  - link "Microsoft Azure"\n'
               '  - combobox "Search resources, services, and docs (G+/)"\n'
               '  - button "Settings"\n')
    NEW_GROUP = '- heading "New Group" [level=2]\n' "- button \"Close content 'New Group'\"\n"

    @staticmethod
    def waiting_lines(said) -> list[str]:
        return [str(c.args[0]) for c in said.call_args_list if c.args and "still loading" in str(c.args[0])]

    def blade_outline(self, line: int) -> str:
        """The outline kept for the item on guide line `line` of step 9.9.1, the only one kept."""
        kept = sorted((self.tmp / "logs" / "test").glob("blade-*.aria.txt"))
        self.assertEqual([path.name for path in kept], [f"blade-9.9.1-{line}.aria.txt"])
        return kept[0].read_text(encoding="utf-8")

    def test_a_label_on_a_blade_still_loading_is_waited_for_beyond_the_lookup_time(self) -> None:
        field = ScreenNode(tag="input")
        screen = Screen(tree=self.TOP_BAR + '- heading "Create new user" [level=2]\n'
                                            "- button \"Close content 'Create new user'\"\n")
        rendered_at = run.FIND_TIMEOUT_MS / 1000 + 10                     # past the normal lookup

        def render(_waits: int) -> None:
            if page.now >= rendered_at and not screen.entries:
                screen.add(("textbox", "User principal name", field))
                screen.tree += '- textbox "User principal name"\n'

        page = self.LoadingPage(render)
        item = {"kind": "field", "label": "User principal name", "value": "x", "line": 2}
        with mock.patch("builtins.print") as said:
            record, r = self.act(screen, item, "User principal name", page=page, value="khadgar")
        self.assertEqual((record["outcome"], field.filled, r.ask.prompts), ("match", ["khadgar"], []))
        self.assertGreaterEqual(page.now, rendered_at)
        waiting = self.waiting_lines(said)
        self.assertEqual(len(waiting), 1)                                   # said once, not every look
        self.assertIn("User principal name", waiting[0])
        self.assertIn(f"{run.BLADE_EMPTY_TIMEOUT_MS // 1000} s", waiting[0])
        self.assertEqual(list((self.tmp / "logs" / "test").glob("blade-*")), [])     # found: nothing kept

    def test_a_label_missing_from_a_rendered_blade_is_asked_about_after_the_normal_time(self) -> None:
        screen = Screen(("textbox", "Group name", ScreenNode(tag="input")),
                        tree=self.TOP_BAR + self.NEW_GROUP + '- textbox "Group name"\n')
        item = {"kind": "field", "label": "Group type", "value": "Security", "line": 2}
        reads = mock.Mock(side_effect=run.frame_snapshots)
        with mock.patch("builtins.print") as said, mock.patch.object(run, "frame_snapshots", reads):
            record, r = self.act(screen, item, "Group type", value="Security")
        self.assertEqual((record["outcome"], len(r.ask.prompts)), ("unknown", 1))
        self.assertLess(r.page.now, run.FIND_TIMEOUT_MS / 1000 + 1)
        self.assertFalse(self.waiting_lines(said))
        self.assertEqual(reads.call_count, 1)        # one read for the deployment and the blade, the one kept
        self.assertTrue(self.blade_outline(2).endswith(                    # what the check read
            'heading "New Group"\nbutton "Close content \'New Group\'"\ntextbox "Group name"\n'))

    def test_no_outline_is_kept_for_a_label_the_recording_has_a_decision_for(self) -> None:
        screen = Screen(tree=self.TOP_BAR + self.NEW_GROUP + '- textbox "Group name"\n')
        self.recording["steps"]["9.9.1"]["labels"]["Group type"] = {"decision": "gone", "at": "2026-10-08T10:00:00Z"}
        item = {"kind": "field", "label": "Group type", "value": "Security", "line": 2}
        with mock.patch("builtins.print") as said:
            record, r = self.act(screen, item, "Group type", value="Security")
        self.assertEqual((record["outcome"], record["severity"], r.ask.prompts), ("drift", "blocking", []))
        self.assertEqual(list((self.tmp / "logs" / "test").glob("blade-*")), [])
        self.assertFalse([c for c in said.call_args_list if c.args and "outline" in str(c.args[0])])

    def test_each_item_of_a_step_keeps_its_own_outline(self) -> None:
        screen = Screen(tree=self.TOP_BAR + self.NEW_GROUP + '- textbox "Group name"\n')
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        for line, label in ((3, "Group type"), (4, "Membership type")):
            with mock.patch("builtins.print"):
                self.act(screen, {"kind": "field", "label": label, "value": "x", "line": line}, label, runner=r)
        self.assertEqual(sorted(path.name for path in (self.tmp / "logs" / "test").glob("blade-*")),
                         ["blade-9.9.1-3.aria.txt", "blade-9.9.1-4.aria.txt"])

    def test_a_blade_that_never_gets_its_title_is_asked_about_after_the_longer_limit(self) -> None:
        screen = Screen(tree=self.TOP_BAR + "- button \"Close content 'undefined'\"\n")
        with mock.patch("builtins.print") as said:
            record, r = self.act(screen, {"kind": "action", "labels": ["Create"], "line": 1}, "Create")
        self.assertEqual((record["outcome"], len(r.ask.prompts)), ("unknown", 1))
        limit = (run.FIND_TIMEOUT_MS + run.BLADE_LOAD_TIMEOUT_MS) / 1000
        self.assertGreaterEqual(r.page.now, limit)
        self.assertLess(r.page.now, limit + 1)
        self.assertEqual(len(self.waiting_lines(said)), 1)
        self.assertIn("button \"Close content 'undefined'\"", self.blade_outline(1))

    def test_a_titled_blade_that_stays_empty_is_asked_about_after_the_grace_limit(self) -> None:
        screen = Screen(tree=self.TOP_BAR + self.NEW_GROUP)
        with mock.patch("builtins.print"):
            record, r = self.act(screen, {"kind": "action", "labels": ["Create"], "line": 1}, "Create")
        self.assertEqual((record["outcome"], len(r.ask.prompts)), ("unknown", 1))
        limit = (run.FIND_TIMEOUT_MS + run.BLADE_EMPTY_TIMEOUT_MS) / 1000
        self.assertGreaterEqual(r.page.now, limit)
        self.assertLess(r.page.now, limit + 1)
        self.assertIn('heading "New Group"', self.blade_outline(1))

    def test_a_blade_that_renders_without_the_label_is_asked_about_after_one_more_lookup(self) -> None:
        screen = Screen(tree=self.TOP_BAR + self.NEW_GROUP)
        rendered_at = run.FIND_TIMEOUT_MS / 1000 + 5

        def render(_waits: int) -> None:
            if page.now >= rendered_at and "textbox" not in screen.tree:
                screen.tree += '- textbox "Group name"\n'

        page = self.LoadingPage(render)
        with mock.patch("builtins.print"):
            record, r = self.act(screen, {"kind": "action", "labels": ["Create"], "line": 1}, "Create", page=page)
        self.assertEqual((record["outcome"], len(r.ask.prompts)), ("unknown", 1))
        self.assertGreaterEqual(page.now, rendered_at + run.FIND_TIMEOUT_MS / 1000)   # the normal time again
        self.assertLess(page.now, rendered_at + run.FIND_TIMEOUT_MS / 1000 + 1)      # not the whole limit

    def test_an_ambiguity_on_a_blade_that_has_rendered_is_reported_after_the_normal_time(self) -> None:
        screen = Screen(tree=self.TOP_BAR + self.NEW_GROUP)
        rendered_at = run.FIND_TIMEOUT_MS / 1000 + 5

        def render(_waits: int) -> None:
            if page.now >= rendered_at and not screen.entries:
                screen.add(("button", "Create", ScreenNode()), ("button", "Create", ScreenNode()))
                screen.tree += '- textbox "Group name"\n- button "Create"\n- button "Create"\n'

        page = self.LoadingPage(render)
        with mock.patch("builtins.print"):
            record, r = self.act(screen, {"kind": "action", "labels": ["Create"], "line": 1}, "Create", page=page)
        self.assertEqual((record["outcome"], record["observed"], r.ask.prompts),
                         ("unknown", "ambiguous: 2 visible elements match named 'Create'", []))
        self.assertLess(page.now, rendered_at + run.FIND_TIMEOUT_MS / 1000 + 1)      # not the whole limit

    def test_a_search_without_the_search_box_is_unknown(self) -> None:
        record, r = self.act(Screen(), self.SEARCH, "Microsoft Entra ID")
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("search box is not on screen", record["observed"])
        self.assertEqual(r.ask.prompts, [])


class NewestBladeTests(RunnerTestCase):
    """Two blades show the same menu entry (a resource group list and the pane opened from it, run B
    of #342): the step works on the newest, right-most blade; its collapsed groups are opened."""

    act = FindOnScreenTests.act
    LIST = ("Resource Manager | Resource groups [tenantname]", 0)
    PANE = ("prod-skycraft-swc-rg Resource group", 700)
    ACTION = {"kind": "action", "labels": ["Tags"], "line": 1}

    def blade_screen(self, **kwargs) -> tuple[Screen, dict[str, ScreenNode]]:
        nodes = {"list_tags": ScreenNode(blade=self.LIST), "pane_tags": ScreenNode(blade=self.PANE)}
        return Screen(("link", "Tags", nodes["list_tags"]), ("link", "Tags", nodes["pane_tags"])), nodes

    def test_tags_in_the_list_menu_and_the_open_pane_takes_the_pane(self) -> None:
        screen, nodes = self.blade_screen()
        screen.add(("button", "Close content 'prod-skycraft-swc-rg'", ScreenNode(blade=self.PANE)))
        record, r = self.act(screen, self.ACTION, "Tags")
        self.assertEqual((record["outcome"], nodes["pane_tags"].clicked, nodes["list_tags"].clicked, r.ask.prompts),
                         ("match", 1, 0, []))

    def test_two_matches_in_the_newest_blade_stay_ambiguous(self) -> None:
        screen, nodes = self.blade_screen()
        second = ScreenNode(blade=self.PANE)
        screen.add(("link", "Tags", second))
        record, _ = self.act(screen, self.ACTION, "Tags")
        self.assertEqual(record["outcome"], "unknown")
        self.assertEqual((nodes["pane_tags"].clicked, nodes["list_tags"].clicked, second.clicked), (0, 0, 0))

    def test_a_match_outside_any_region_keeps_it_ambiguous(self) -> None:
        outside = ScreenNode()
        screen = Screen(("link", "Tags", outside), ("link", "Tags", ScreenNode(blade=self.PANE)))
        record, _ = self.act(screen, self.ACTION, "Tags")
        self.assertEqual((record["outcome"], outside.clicked), ("unknown", 0))

    def two_menus(self, entry: str, pane_toggle: str | None = None):
        """The list's and the pane's menus, each with an 'Expand all headers' button; the pane's
        opens its groups and shows `entry` (under `pane_toggle`'s group when given)."""
        screen, nodes = self.blade_screen()
        shown = ScreenNode(blade=self.PANE)
        nodes["entry"] = shown
        nodes["list_expand"] = ScreenNode(blade=self.LIST)
        nodes["pane_expand"] = ScreenNode(blade=self.PANE, on_click=lambda: screen.add(
            ("link", entry, shown), ("button", "Collapse all headers", ScreenNode(blade=self.PANE))))
        screen.add(("button", "Expand all headers", nodes["list_expand"]),
                   ("button", "Expand all headers", nodes["pane_expand"]))
        if pane_toggle:
            screen.add(("button", pane_toggle, ScreenNode(blade=self.PANE)))
        return screen, nodes

    def test_locks_shows_after_the_panes_expand_all_headers(self) -> None:
        screen, nodes = self.two_menus("Locks", "Toggle Settings")
        record, r = self.act(screen, {"kind": "action", "labels": ["Locks"], "line": 1}, "Locks")
        self.assertEqual((record["outcome"], nodes["entry"].clicked, r.ask.prompts), ("match", 1, []))
        self.assertEqual((nodes["pane_expand"].clicked, nodes["list_expand"].clicked), (1, 0))

    def test_budgets_under_the_panes_cost_management_group(self) -> None:
        screen, nodes = self.two_menus("Budgets", "Toggle Cost Management")
        record, r = self.act(screen, {"kind": "navigation", "labels": ["Budgets"], "line": 1}, "Budgets")
        self.assertEqual((record["outcome"], nodes["entry"].clicked, r.ask.prompts), ("match", 1, []))
        self.assertEqual((nodes["pane_expand"].clicked, nodes["list_expand"].clicked), (1, 0))

    def test_an_expand_click_while_the_menu_loads_is_tried_again(self) -> None:
        # Run B, 1.3.15: the click landed while the menu read 'Loading...' and changed nothing.
        monitoring = ScreenNode(blade=self.PANE)
        screen = Screen()
        clicks = []

        def opens() -> None:
            clicks.append(1)
            if len(clicks) == 2:
                screen.add(("link", "Monitoring", monitoring), ("button", "Collapse all headers",
                                                                   ScreenNode(blade=self.PANE)))
        expand = ScreenNode(blade=self.PANE, on_click=opens)
        screen.add(("button", "Expand all headers", expand))
        record, r = self.act(screen, {"kind": "action", "labels": ["Monitoring"], "line": 1}, "Monitoring")
        self.assertEqual((record["outcome"], expand.clicked, monitoring.clicked, r.ask.prompts), ("match", 2, 1, []))

    def test_expand_is_clicked_at_most_three_times(self) -> None:
        expand = ScreenNode(blade=self.PANE)
        screen = Screen(("button", "Expand all headers", expand))
        record, r = self.act(screen, {"kind": "action", "labels": ["Monitoring"], "line": 1}, "Monitoring")
        self.assertEqual((record["outcome"], expand.clicked, len(r.ask.prompts)), ("unknown", run.EXPAND_TRIES, 1))
        self.assertEqual(run.EXPAND_TRIES, 3)
        self.assertFalse(r.expanded)


class DeploymentStateTests(unittest.TestCase):
    """snapshot_text and deployment_state (#328): what one snapshot line shows, and whether the
    screen shows a Portal deployment that is still running or has failed."""

    def test_a_line_shows_its_name_or_else_its_inline_text(self) -> None:
        for line, text in (('- heading "Deployment is in progress" [level=2]', "Deployment is in progress"),
                           ("- 'heading \"Deployment failed: x\" [level=2]'", "Deployment failed: x"),
                           ("- text: Deployment in progress...", "Deployment in progress..."),
                           ("  - paragraph: Your deployment failed", "Your deployment failed"),
                           ('- text: "Resource \'vm\' failed: Conflict"', "Resource 'vm' failed: Conflict"),
                           ("- text: 'It''s done'", "It's done"),
                           ('- button "Go to resource"', "Go to resource"),
                           ("- list:", ""), ("- /url: https://x", ""), ("no line", "")):
            with self.subTest(line=line):
                self.assertEqual(run.snapshot_text(line), text)

    def test_a_running_deployment_is_read_from_the_overview_or_a_notification(self) -> None:
        for text in ("Deployment is in progress", "Deployment in progress...", "deployment is in progress"):
            with self.subTest(text=text):
                self.assertEqual(run.deployment_state(["Home", text, "Deployment name: x"]), (text, []))

    def test_every_failure_comes_once_with_the_text_that_follows_it(self) -> None:
        self.assertEqual(run.deployment_state(["Home", "Your deployment failed", "", "Conflict: subnet in use", "x"]),
                         (None, ["Your deployment failed; Conflict: subnet in use"]))
        self.assertEqual(run.deployment_state(["Deployment failed"]), (None, ["Deployment failed"]))
        self.assertEqual(run.deployment_state(["Deployment failed", "a", "Your deployment failed", "b",
                                               "Deployment failed", "a"]),
                         (None, ["Deployment failed; a", "Your deployment failed; b"]))

    def test_a_running_deployment_comes_with_the_failures_on_screen(self) -> None:
        self.assertEqual(run.deployment_state(["Deployment failed", "Deployment is in progress"]),
                         ("Deployment is in progress", ["Deployment failed"]))

    def test_a_deployment_status_after_a_failure_is_not_its_detail(self) -> None:
        # The detail is the failure's identity: another deployment's status changes as it ends.
        for status in ("Deployment is in progress", "Your deployment is complete", "Deployment succeeded",
                       "Your deployment failed"):
            with self.subTest(status=status):
                self.assertIn("Deployment failed", run.deployment_state(["Deployment failed", "", status])[1])

    def test_a_finished_deployment_and_other_text_are_no_deployment(self) -> None:
        for texts in ([], ["Your deployment is complete", "Go to resource"], ["Deployment succeeded"],
                      ["Deployments", "Deployment name", "Deployment details"],
                      ["How to check the deployment is in progress"]):
            with self.subTest(texts=texts):
                self.assertEqual(run.deployment_state(texts), (None, []))

    def test_a_screen_whose_main_frame_says_nothing_is_no_reading(self) -> None:
        self.assertIsNone(run.texts_of([]))
        self.assertIsNone(run.texts_of([None, '- heading "Deployment is in progress"']))
        self.assertIsNone(run.texts_of(["  \n", '- heading "Deployment is in progress"']))
        self.assertEqual(run.texts_of(['- heading "Home"', None, "- text: x"]), ["Home", "x"])

    def test_the_maximum_wait_is_an_argument_of_30_minutes_by_default(self) -> None:
        required = ["--steps", "s", "--recording", "r", "--log-dir", "l", "--run-id", "i", "--tenant-id", "t",
                    "--tenant-domain", "d", "--state", "s", "--auth-state", "a"]
        self.assertEqual(run.parse_args(required).deployment_timeout_minutes, 30)
        self.assertEqual(run.parse_args(required + ["--deployment-timeout-minutes", "90"]).deployment_timeout_minutes, 90)
        for wrong in ("0", "-5", "ten"):
            with self.subTest(wrong=wrong), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                run.parse_args(required + ["--deployment-timeout-minutes", wrong])


class DeploymentWaitTests(RunnerTestCase):
    """A lookup that finds nothing while the Portal shows a deployment still running waits for it
    to end, up to the maximum (#328): a label, a form's first field, a resource a chain names and
    the Expected Result. A failed deployment is reported as such, and a step with no deployment
    keeps its timing."""

    TOP_BAR = FindOnScreenTests.TOP_BAR
    RUNNING = TOP_BAR + '- heading "Deployment is in progress" [level=2]\n- text: "Deployment name: Microsoft.VM-1"\n'
    COMPLETE = TOP_BAR + '- heading "Your deployment is complete" [level=2]\n- button "Go to resource"\n'
    OBJECT_ID = "11111111-2222-4333-8444-555555555555"
    FAILED = (TOP_BAR + '- heading "Your deployment failed" [level=2]\n'
              f'- text: "Resource {OBJECT_ID} in contoso.onmicrosoft.com failed: Conflict"\n')
    GO = {"kind": "action", "labels": ["Go to resource"], "line": 4}
    STEP = {"id": "9.9.1", "title": "One", "items": [GO], "images": [], "expected": "Deployment succeeds"}

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n", encoding="utf-8")
        POPUP_RECORD.update(popups=None, made=0)

    act = FindOnScreenTests.act
    LoadingPage = FindOnScreenTests.LoadingPage

    def ending(self, screen: Screen, at: float, tree: str, *entries) -> FakePage:
        """A page whose deployment ends `at` seconds after the start: from the first wait at or
        after that moment, the screen shows `tree` and `entries`."""
        def end(_waits: int) -> None:
            if page.now >= at and screen.tree != tree:
                screen.tree = tree
                screen.add(*entries)

        page = self.LoadingPage(end)
        return page

    @staticmethod
    def said(printed) -> list[str]:
        return [str(c.args[0]) for c in printed.call_args_list if c.args]

    def test_a_label_that_shows_once_the_deployment_completes_is_used_without_asking(self) -> None:
        go = ScreenNode()
        screen = Screen(tree=self.RUNNING)
        page = self.ending(screen, 150, self.COMPLETE, ("button", "Go to resource", go))
        with mock.patch("builtins.print") as printed:
            record, r = self.act(screen, self.GO, "Go to resource", page=page)
        self.assertEqual((record["outcome"], go.clicked, r.ask.prompts), ("match", 1, []))
        self.assertGreaterEqual(page.now, 150)
        self.assertLess(page.now, 150 + run.DEPLOYMENT_POLL_MS / 1000 + run.SETTLE_MS / 1000 + 1)
        lines = self.said(printed)
        waiting = [line for line in lines if "deployment is still running" in line]
        self.assertEqual(len(waiting), 1)                                 # said once, not every poll
        self.assertIn("30 min", waiting[0])
        self.assertIn("'Go to resource'", waiting[0])
        self.assertEqual(len([line for line in lines if line.startswith("  still waiting")]), 2)   # each minute
        self.assertIn("Found 'Go to resource' after waiting 2 min 25 s for the deployment.", lines)
        self.assertEqual(self.recording["steps"]["9.9.1"]["labels"], {})

    def test_a_failed_deployment_is_reported_as_such_and_nobody_is_asked(self) -> None:
        screen = Screen(tree=self.RUNNING)
        page = self.ending(screen, 90, self.FAILED)
        with mock.patch("builtins.print") as printed:
            record, r = self.act(screen, self.GO, "Go to resource", page=page)
        self.assertEqual((record["outcome"], record["severity"], r.ask.prompts), ("unknown", None, []))
        self.assertLess(page.now, 90 + run.DEPLOYMENT_POLL_MS / 1000 + 1)
        self.assertTrue(record["observed"].startswith("the Portal's deployment failed: Your deployment failed; "))
        r.write(record)                                                   # scrubbed as any observed text
        written = json.loads((self.tmp / "logs" / "test" / "results.jsonl").read_text(encoding="utf-8"))
        self.assertEqual(written["observed"], "the Portal's deployment failed: Your deployment failed; "
                                              "Resource <id> in [tenantdomain] failed: Conflict")
        self.assertEqual(self.recording["steps"]["9.9.1"]["labels"], {})
        self.assertTrue(any("deployment failed" in line for line in self.said(printed)))

    def test_a_deployment_that_failed_before_the_lookup_ended_is_reported_without_waiting(self) -> None:
        record, r = self.act(Screen(tree=self.FAILED), self.GO, "Go to resource")
        self.assertEqual((record["outcome"], r.ask.prompts), ("unknown", []))
        self.assertIn("the Portal's deployment failed", record["observed"])
        self.assertLess(r.page.now, run.FIND_TIMEOUT_MS / 1000 + 1)

    def test_a_deployment_still_running_at_the_maximum_is_reported_and_nobody_is_asked(self) -> None:
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(deployment_timeout_minutes=2), ask=Answers())
        with mock.patch("builtins.print") as printed:
            record, _ = self.act(Screen(tree=self.RUNNING), self.GO, "Go to resource", runner=r)
        self.assertEqual((record["outcome"], r.ask.prompts), ("unknown", []))
        self.assertEqual(record["observed"], "the Portal's deployment was still running after 2 min, "
                                             "the longest the run waits (-DeploymentTimeoutMinutes)")
        start = run.FIND_TIMEOUT_MS / 1000
        self.assertGreaterEqual(r.page.now, start + 120)
        self.assertLess(r.page.now, start + 120 + run.DEPLOYMENT_POLL_MS / 1000 + 1)
        self.assertTrue(any("2 min" in line for line in self.said(printed) if "still running" in line))

    def test_a_label_missing_without_a_deployment_is_asked_about_after_the_normal_time(self) -> None:
        screen = Screen(tree=self.COMPLETE)                               # a finished deployment is none
        with mock.patch("builtins.print") as printed:
            record, r = self.act(screen, self.GO, "Go to resource")
        self.assertEqual((record["outcome"], len(r.ask.prompts)), ("unknown", 1))
        self.assertLess(r.page.now, run.FIND_TIMEOUT_MS / 1000 + 1)
        self.assertFalse([line for line in self.said(printed) if "deployment" in line])

    def test_a_label_still_missing_after_the_deployment_is_asked_about_after_one_more_lookup(self) -> None:
        screen = Screen(tree=self.RUNNING)
        page = self.ending(screen, 60, self.COMPLETE)                     # no 'Go to resource' after all
        with mock.patch("builtins.print") as printed:
            record, r = self.act(screen, self.GO, "Go to resource", page=page)
        self.assertEqual((record["outcome"], len(r.ask.prompts)), ("unknown", 1))
        self.assertIn("The deployment has ended after 55 s: looking for 'Go to resource' again.", self.said(printed))
        self.assertGreaterEqual(page.now, 60 + run.FIND_TIMEOUT_MS / 1000)
        self.assertLess(page.now, 60 + run.DEPLOYMENT_POLL_MS / 1000 + run.FIND_TIMEOUT_MS / 1000 + 1)

    def on(self, screen: Screen, r: run.Runner, call):
        """`call()` with `screen` as the page's only frame and the page's clock for time."""
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]), mock.patch("builtins.print"):
            return call()

    def test_a_form_field_and_a_resource_wait_for_the_deployment_too(self) -> None:
        field = ScreenNode(tag="input")
        screen = Screen(tree=self.RUNNING)
        page = self.ending(screen, 100, self.COMPLETE + '- textbox "Name"\n', ("textbox", "Name", field))
        r = run.Runner(page, STEPS, self.recording, self.args(), ask=Answers())
        item = {"kind": "field", "label": "Name", "value": "x", "line": 5}
        record = self.on(screen, r, lambda: r.act_on_label(self.STEP, item, "Name", "web-01", form_start=True))
        self.assertEqual((record["outcome"], field.filled, r.ask.prompts, r.records), ("match", ["web-01"], [], []))
        self.assertGreaterEqual(page.now, 100)
        link = ScreenNode()
        screen = Screen(tree=self.RUNNING)
        page = self.ending(screen, 100, self.COMPLETE, ("link", "dev-skycraft-swc-lb", link))
        r = run.Runner(page, STEPS, self.recording, self.args(), ask=Answers())
        chain = {"kind": "navigation", "labels": ["dev-skycraft-swc-lb"], "resources": [0], "line": 6}
        record = self.on(screen, r, lambda: r.open_resource(self.STEP, chain, "dev-skycraft-swc-lb"))
        self.assertEqual((record["outcome"], link.clicked), ("match", 1))
        self.assertGreaterEqual(page.now, 100)

    SEARCH_BOX = FindOnScreenTests.SEARCH_BOX
    OLD_FAILURE = '- text: Deployment failed\n- text: "Deployment to resource group \'rg-old\' failed."\n'

    def test_an_earlier_failure_left_on_screen_does_not_fail_a_deployment_that_completes(self) -> None:
        # The race: the running line goes, the old failure stays, and 'Go to resource' renders a moment later.
        go = ScreenNode()
        screen = Screen(tree=self.RUNNING + self.OLD_FAILURE)

        def finish(_waits: int) -> None:
            if page.now >= 60 and "complete" not in screen.tree:
                screen.tree = self.COMPLETE + self.OLD_FAILURE
            if page.now >= 66 and not screen.entries:
                screen.add(("button", "Go to resource", go))

        page = self.LoadingPage(finish)
        with mock.patch("builtins.print") as printed:
            record, r = self.act(screen, self.GO, "Go to resource", page=page)
        self.assertEqual((record["outcome"], go.clicked, r.ask.prompts), ("match", 1, []))
        self.assertIn("The deployment has ended after 55 s: looking for 'Go to resource' again.", self.said(printed))
        self.assertEqual(r.reported_failures, {"Deployment failed; Deployment to resource group 'rg-old' failed."})

    def test_a_stale_failure_right_before_a_running_overview_keeps_its_identity(self) -> None:
        # The failure line has no detail of its own: the overview's status follows it and changes.
        go = ScreenNode()
        screen = Screen(tree=self.TOP_BAR + "- text: Deployment failed\n" + self.RUNNING[len(self.TOP_BAR):])

        def finish(_waits: int) -> None:
            if page.now >= 60 and "complete" not in screen.tree:
                screen.tree = self.TOP_BAR + "- text: Deployment failed\n" + self.COMPLETE[len(self.TOP_BAR):]
            if page.now >= 66 and not screen.entries:
                screen.add(("button", "Go to resource", go))

        page = self.LoadingPage(finish)
        with mock.patch("builtins.print"):
            record, r = self.act(screen, self.GO, "Go to resource", page=page)
        self.assertEqual((record["outcome"], go.clicked, r.ask.prompts), ("match", 1, []))

    def test_a_failure_a_wait_passed_over_is_not_reported_at_the_next_miss(self) -> None:
        go = ScreenNode()
        screen = Screen(tree=self.RUNNING + self.OLD_FAILURE)
        page = self.ending(screen, 60, self.COMPLETE + self.OLD_FAILURE, ("button", "Go to resource", go))
        r = run.Runner(page, STEPS, self.recording, self.args(), ask=Answers())
        with mock.patch("builtins.print"):
            first, _ = self.act(screen, self.GO, "Go to resource", runner=r)
            second, _ = self.act(screen, {"kind": "action", "labels": ["Overview"], "line": 7}, "Overview", runner=r)
        self.assertEqual((first["outcome"], go.clicked), ("match", 1))
        self.assertEqual((second["outcome"], len(r.ask.prompts)), ("unknown", 1))       # asked, not blamed
        self.assertNotIn("deployment failed", second["observed"] or "")

    def test_a_failure_already_reported_lets_the_lookup_go_on_as_usual(self) -> None:
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        first, _ = self.act(Screen(tree=self.FAILED), self.GO, "Go to resource", runner=r)
        self.assertEqual((first["outcome"], r.ask.prompts), ("unknown", []))
        with mock.patch("builtins.print") as printed:           # the person skipped the step; the next one misses
            second, _ = self.act(Screen(tree=self.FAILED), {"kind": "action", "labels": ["Overview"], "line": 7},
                                 "Overview", runner=r)
        self.assertEqual((second["outcome"], len(r.ask.prompts)), ("unknown", 1))       # the person is asked
        self.assertIn("A deployment failure is still on screen, reported already: looking for 'Overview' as usual.",
                      self.said(printed))
        self.assertLess(r.page.now, 2 * (run.FIND_TIMEOUT_MS / 1000 + 1))

    def test_an_answer_about_a_label_looked_up_past_a_failure_is_used_but_never_recorded(self) -> None:
        overview = ScreenNode()
        item = {"kind": "action", "labels": ["Overview"], "line": 7}
        for answer, outcome, clicked in (("1", "drift", 1), ("g", "drift", 0), ("i", "match", 0)):
            with self.subTest(answer=answer):
                self.recording["steps"]["9.9.1"]["labels"] = {}
                r = run.Runner(FakePage(), STEPS, self.recording, self.args(run_id=f"past-{answer}"),
                               ask=Answers(answer))
                self.act(Screen(tree=self.FAILED), self.GO, "Go to resource", runner=r)   # reported: unknown
                overview.clicked = 0
                screen = Screen(("link", "Overview (preview)", overview), tree=self.FAILED)
                with mock.patch("builtins.print") as printed:
                    record, _ = self.act(screen, item, "Overview", runner=r,
                                         candidates=[run.Candidate("link", "Overview (preview)")])
                self.assertEqual((record["outcome"], overview.clicked, len(r.ask.prompts)), (outcome, clicked, 1))
                self.assertIn(run.PAST_FAILURE, self.said(printed))
                self.assertEqual(self.recording["steps"]["9.9.1"]["labels"], {})
                saved = json.loads((self.tmp / "rec.json").read_text(encoding="utf-8"))
                self.assertNotIn("Overview", saved["steps"].get("9.9.1", {}).get("labels", {}))
                if answer == "1":
                    self.assertEqual((record["severity"], record["workaround"], record["proposedEdit"]),
                                     ("misleading", True, None))

    def test_a_failure_already_reported_lets_a_resource_be_searched_for(self) -> None:
        lb = "dev-skycraft-swc-lb"
        screen = Screen(tree=self.FAILED)
        found = ScreenNode(section=("", "Resources", lb))
        ResourceTests.with_search(self, screen, ("option", lb, found))
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        chain = {"kind": "navigation", "labels": [lb], "resources": [0], "line": 6}
        r.reported_failures.add("Your deployment failed; Resource " + self.OBJECT_ID
                                + " in contoso.onmicrosoft.com failed: Conflict")
        record = self.on(screen, r, lambda: r.open_resource(self.STEP, chain, lb, at_start=True))
        self.assertEqual((record["outcome"], record["observed"], found.clicked),
                         ("match", "opened from the Portal's search", 1))

    def test_a_screen_that_cannot_be_read_for_a_while_does_not_end_the_wait(self) -> None:
        go = ScreenNode()

        class Unreadable(Screen):
            """A frame whose snapshot times out while `blind` is set, as on a Portal re-rendering."""
            blind = False

            def locator(self, selector: str):
                if selector == "body" and self.blind:
                    class Body:
                        def aria_snapshot(self, timeout=None):
                            raise run.PlaywrightError("Timeout 2000ms exceeded")
                    return Body()
                return super().locator(selector)

        screen = Unreadable(tree=self.RUNNING)

        def render(_waits: int) -> None:
            screen.blind = 30 <= page.now < 45 or 70 <= page.now < 75
            if page.now >= 50 and screen.tree == self.RUNNING:
                screen.tree = ""                                 # empty for a moment: navigating
            if page.now >= 60 and screen.tree == "":
                screen.tree = self.RUNNING
            if page.now >= 100 and not screen.entries:
                screen.tree = self.COMPLETE
                screen.add(("button", "Go to resource", go))

        page = self.LoadingPage(render)
        with mock.patch("builtins.print") as printed:
            record, r = self.act(screen, self.GO, "Go to resource", page=page)
        self.assertEqual((record["outcome"], go.clicked, r.ask.prompts), ("match", 1, []))
        self.assertFalse([line for line in self.said(printed) if "has ended" in line])

    def check(self, screen: Screen, page: FakePage, **args) -> tuple[dict, run.Runner, list[str]]:
        """check_result for STEP, whose recorded result is 'Your deployment is complete', against
        `screen`: the record written, the runner and what the console said."""
        self.recording["steps"]["9.9.1"]["result"] = {"text": "Your deployment is complete"}
        r = run.Runner(page, STEPS, self.recording, self.args(**args), ask=Answers())
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "text_on_screen", lambda page, text: text in screen.tree), \
                mock.patch("builtins.print") as printed:
            r.check_result(self.STEP, r.step_entry(self.STEP))
        return r.records[-1], r, self.said(printed)

    def test_the_expected_result_waits_for_the_deployment(self) -> None:
        screen = Screen(tree=self.RUNNING)
        page = self.ending(screen, 400, self.COMPLETE)
        record, _, said = self.check(screen, page)
        self.assertEqual((record["kind"], record["outcome"]), ("result", "match"))
        self.assertGreaterEqual(page.now, 400)
        self.assertLess(page.now, 400 + run.DEPLOYMENT_POLL_MS / 1000 + 1)
        self.assertTrue(any("the Expected Result" in line for line in said if "still running" in line))

    def test_the_expected_result_of_a_failed_deployment_is_reported_as_such(self) -> None:
        screen = Screen(tree=self.RUNNING)
        record, _, _ = self.check(screen, self.ending(screen, 30, self.FAILED))
        self.assertEqual((record["outcome"], record["severity"]), ("unknown", None))
        self.assertTrue(record["observed"].startswith(
            "the Portal's deployment failed: Your deployment failed; Resource <id>"))

    def test_an_expected_result_missing_after_the_deployment_says_how_long_it_was_looked_for(self) -> None:
        screen = Screen(tree=self.RUNNING)
        record, _, _ = self.check(screen, self.ending(screen, 100, self.TOP_BAR))
        self.assertEqual((record["outcome"], record["observed"]),
                         ("drift", f"text not on screen within {run.RESULT_TIMEOUT_S} s, 1 min 25 s of waiting "
                                   f"for a deployment, and {run.RESULT_TIMEOUT_S} s after it ended"))

    def test_the_expected_result_of_a_deployment_past_the_maximum_is_unknown(self) -> None:
        record, r, _ = self.check(Screen(tree=self.RUNNING), FakePage(), deployment_timeout_minutes=1)
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("still running after 1 min", record["observed"])
        self.assertGreaterEqual(r.page.now, run.RESULT_TIMEOUT_S + 60)
        self.assertLess(r.page.now, run.RESULT_TIMEOUT_S + 60 + run.DEPLOYMENT_POLL_MS / 1000 + 1)

    def test_an_expected_result_without_a_deployment_keeps_its_timing(self) -> None:
        record, r, said = self.check(Screen(tree=self.TOP_BAR), FakePage())
        self.assertEqual((record["outcome"], record["severity"], record["observed"]),
                         ("drift", "misleading", f"text not on screen within {run.RESULT_TIMEOUT_S} s"))
        self.assertGreaterEqual(r.page.now, run.RESULT_TIMEOUT_S)
        self.assertLess(r.page.now, run.RESULT_TIMEOUT_S + 1)
        self.assertFalse([line for line in said if "deployment" in line])


class ResourceTests(RunnerTestCase):
    """A resource a navigation chain names in a code span (#199): opened as the one link, grid
    cell or row of its exact name, or else, when it opens the chain, as the exact result of the
    Portal's global search; never asked about; and blocking drift of the step, with no proposed
    edit, when it is not found."""

    LB = "dev-skycraft-swc-lb"
    ITEM = {"kind": "navigation", "labels": ["Load balancers", LB, "Backend pools"], "resources": [1], "line": 594}
    STEP = {"id": "9.9.1", "title": "One", "portal": True, "expected": None, "images": ["images/Step-9.9.1.png"],
            "items": [ITEM]}

    SEARCH_BOX = "Search resources, services, and docs (G+/)"

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n", encoding="utf-8")
        POPUP_RECORD.update(popups=None, made=0)

    def with_search(self, screen: Screen, *results) -> ScreenNode:
        """Put the Portal's global search box on `screen`; once something is typed into it, its
        dropdown holds `results`. Returns the box."""
        dropdown = ScreenNode(attrs={"id": "results"}, children=Screen(*results), tree="- listbox")
        box = ScreenNode(attrs={"aria-controls": "results"}, on_fill=lambda: screen.add(("listbox", "", dropdown)))
        screen.add(("combobox", self.SEARCH_BOX, box))
        return box

    @staticmethod
    def result(section: str, whole: str) -> ScreenNode:
        return ScreenNode(section=("", section, whole))

    def open(self, screen: Screen, name: str = LB, at_start: bool = True) -> tuple[dict, run.Runner, mock.MagicMock]:
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]) as candidates:
            record = self.quietly(lambda: r.open_resource(self.STEP, self.ITEM, name, at_start=at_start))
        return record, r, candidates

    def test_the_link_of_that_name_is_clicked_without_asking(self) -> None:
        link, button = ScreenNode(), ScreenNode()
        record, r, _ = self.open(Screen(("button", self.LB, button), ("link", self.LB, link)))
        self.assertEqual((record["kind"], record["label"], record["outcome"]), ("navigation", self.LB, "match"))
        self.assertEqual((link.clicked, button.clicked, r.ask.prompts), (1, 0, []))
        self.assertEqual(self.recording["steps"]["9.9.1"]["labels"], {})        # nothing to replay

    def test_a_grid_cell_or_a_row_of_that_name_counts_too(self) -> None:
        for role in ("gridcell", "row"):
            with self.subTest(role=role):
                node = ScreenNode()
                record, _, _ = self.open(Screen((role, self.LB, node), ("link", self.LB + "-pip", ScreenNode())))
                self.assertEqual((record["outcome"], node.clicked), ("match", 1))

    def test_a_resource_not_on_screen_is_opened_from_the_global_search(self) -> None:
        screen = Screen(("link", self.LB + "-pip", ScreenNode()))
        found, near = self.result("Resources", self.LB), self.result("Resources", self.LB + "-pip")
        box = self.with_search(screen, ("option", self.LB, found), ("option", self.LB + "-pip", near))
        record, r, candidates = self.open(screen)
        self.assertEqual((record["outcome"], record["observed"]), ("match", "opened from the Portal's search"))
        self.assertEqual((box.filled, box.pressed, found.clicked, near.clicked, r.ask.prompts),
                         ([self.LB], [], 1, 0, []))                              # opened: nothing to close
        self.assertGreaterEqual(r.page.now, run.FIND_TIMEOUT_MS / 1000)          # the screen first, as long as a label
        candidates.assert_not_called()

    def test_later_in_a_chain_a_resource_is_looked_for_on_screen_only(self) -> None:
        # The label before it opened a picker or a list (5.3.6, 5.2.3): a search would leave it.
        screen = Screen(("link", self.LB + "-pip", ScreenNode()))
        found = self.result("Resources", self.LB)
        box = self.with_search(screen, ("option", self.LB, found))
        record, r, _ = self.open(screen, at_start=False)
        self.assertEqual((record["outcome"], record["severity"], record["category"]),
                         ("drift", "blocking", run.MISSING_RESOURCE))
        self.assertEqual(record["observed"], f"no link, cell or row named '{self.LB}' on screen")
        self.assertEqual((box.filled, found.clicked, r.ask.prompts), ([], 0, []))
        self.assertFalse((self.tmp / "logs" / "test" / "search-9.9.1.aria.txt").exists())
        on_screen = ScreenNode()
        record, _, _ = self.open(Screen(("gridcell", self.LB, on_screen)), at_start=False)
        self.assertEqual((record["outcome"], record["observed"], on_screen.clicked), ("match", None, 1))

    def test_the_global_search_types_the_name_with_its_placeholders_filled(self) -> None:
        self.recording["placeholders"]["[yourtenant]"] = "contoso"
        screen = Screen()
        vault = self.result("Resources", "contoso-skycraft-kv")
        box = self.with_search(screen, ("option", "contoso-skycraft-kv", vault))
        record, _, _ = self.open(screen, name="[yourtenant]-skycraft-kv")
        self.assertEqual((record["outcome"], box.filled, vault.clicked), ("match", ["contoso-skycraft-kv"], 1))

    def test_a_resource_neither_on_screen_nor_in_the_search_is_blocking_drift_of_the_step(self) -> None:
        button = ScreenNode()
        screen = Screen(("button", self.LB, button), ("link", self.LB + "-pip", ScreenNode()))
        box = self.with_search(screen, ("option", self.LB + "-pip", self.result("Resources", self.LB + "-pip")))
        record, r, candidates = self.open(screen)
        self.assertEqual((record["outcome"], record["severity"], record["category"]),
                         ("drift", "blocking", run.MISSING_RESOURCE))
        self.assertEqual(record["observed"], f"no link, cell or row named '{self.LB}' on screen, "
                                             "and no result of that name in the Portal's search")
        self.assertIsNone(record["proposedEdit"])
        self.assertEqual((r.ask.prompts, button.clicked), ([], 0))               # no candidate prompt, no stand-in
        candidates.assert_not_called()
        self.assertEqual(self.recording["steps"]["9.9.1"]["labels"], {})
        self.assertTrue((self.tmp / "logs" / "test" / "blade-9.9.1-594.aria.txt").is_file())
        self.assertTrue((self.tmp / "logs" / "test" / "search-9.9.1.aria.txt").is_file())
        self.assertEqual((box.filled, box.pressed), ([self.LB, ""], ["Escape"]))   # the search is closed again

    def test_several_exact_results_in_the_search_or_no_search_box_are_unknown(self) -> None:
        screen = Screen()
        first, second = self.result("Resources", self.LB), self.result("Resources", self.LB)
        box = self.with_search(screen, ("option", self.LB, first), ("option", self.LB, second))
        record, r, _ = self.open(screen)
        self.assertEqual((record["outcome"], record["observed"]),
                         ("unknown", f"ambiguous: 2 visible results match, none of them under Services named '{self.LB}'"))
        self.assertEqual((first.clicked, second.clicked, r.ask.prompts), (0, 0, []))
        self.assertEqual((box.filled, box.pressed), ([self.LB, ""], ["Escape"]))   # the search is closed again
        record, _, _ = self.open(Screen())
        self.assertEqual((record["outcome"], record["observed"]),
                         ("unknown", "LookupError: the Portal's search box is not on screen"))

    def test_two_resources_of_that_name_are_unknown_not_a_guess(self) -> None:
        first, second = ScreenNode(), ScreenNode()
        record, _, _ = self.open(Screen(("link", self.LB, first), ("link", self.LB, second)))
        self.assertEqual((record["outcome"], record["observed"]),
                         ("unknown", f"ambiguous: 2 visible elements match named '{self.LB}'"))
        self.assertEqual((first.clicked, second.clicked), (0, 0))

    def test_a_placeholder_is_filled_from_the_recording_and_one_left_is_unknown(self) -> None:
        self.recording["placeholders"]["[yourtenant]"] = "contoso"
        vault = ScreenNode()
        record, _, _ = self.open(Screen(("link", "contoso-skycraft-kv", vault)), name="[yourtenant]-skycraft-kv")
        self.assertEqual((record["outcome"], record["label"], vault.clicked), ("match", "[yourtenant]-skycraft-kv", 1))
        literal = ScreenNode()
        record, r, _ = self.open(Screen(("link", "skycraft-auth-[uniqueID]", literal)), name="skycraft-auth-[uniqueID]")
        self.assertEqual((record["outcome"], literal.clicked, r.ask.prompts), ("unknown", 0, []))
        self.assertEqual(record["observed"], "resource name 'skycraft-auth-[uniqueID]' has an unresolved placeholder; "
                                             "add a placeholder to the recording")

    def test_run_step_opens_the_resources_and_clicks_the_labels_in_order(self) -> None:
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        done: list[tuple] = []

        def acting(how: str, **fields):
            def act(step, item, label, **where):
                done.append((how, label, *(v for k, v in where.items() if k not in ("state", "state_only"))))  # #296
                record = r.new_record(step, item["kind"], label)
                record.update(outcome="match", **fields)
                return record
            return act

        with mock.patch.object(r, "act_on_label", side_effect=acting("label")), \
                mock.patch.object(r, "open_resource", side_effect=acting("resource")):
            self.assertTrue(self.quietly(lambda: r.run_step(self.STEP)))
        self.assertEqual(done, [("label", "Load balancers"), ("resource", self.LB, False), ("label", "Backend pools")])
        done.clear()
        first = dict(self.ITEM, labels=[self.LB, "Backend pools"], resources=[0])
        with mock.patch.object(r, "act_on_label", side_effect=acting("label")), \
                mock.patch.object(r, "open_resource", side_effect=acting("resource")):
            self.assertTrue(self.quietly(lambda: r.run_step(dict(self.STEP, items=[first]))))
        self.assertEqual(done, [("resource", self.LB, True), ("label", "Backend pools")])   # at the start: searchable
        done.clear()
        missing = acting("resource", severity="blocking", category=run.MISSING_RESOURCE)
        with mock.patch.object(r, "act_on_label", side_effect=acting("label")), \
                mock.patch.object(r, "open_resource", side_effect=lambda *a, **k: dict(missing(*a, **k), outcome="drift")):
            self.assertFalse(self.quietly(lambda: r.run_step(self.STEP)))
        self.assertEqual(done, [("label", "Load balancers"), ("resource", self.LB, False)])   # the chain stops there
        screenshot = [x for x in r.records if x["kind"] == "screenshot"][-1]
        self.assertEqual((screenshot["outcome"], screenshot["category"]), ("match", None))   # the images are not stale

    def test_run_step_opens_the_picker_of_a_field_before_its_chain(self) -> None:
        # 'Destination: **Send to Log Analytics workspace** -> `law`' (#250): the field's
        # picker first, then the chain; a resource at the chain's start is inside the picker, so
        # it is looked for on screen only, never in the Portal's search.
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        done: list[tuple] = []

        def acting(how: str, outcome: str = "match"):
            def act(step, item, label, **where):
                done.append((how, label, *(v for k, v in where.items() if k not in ("state", "state_only"))))  # #296
                record = r.new_record(step, item["kind"], label)
                record.update(outcome=outcome)
                return record
            return act

        picker = {"kind": "navigation", "field": "Destination", "labels": ["Send to Log Analytics workspace", "law"],
                  "resources": [1], "line": 236}
        with mock.patch.object(r, "act_on_label", side_effect=acting("label")), \
                mock.patch.object(r, "open_resource", side_effect=acting("resource")):
            self.assertTrue(self.quietly(lambda: r.run_step(dict(self.STEP, items=[picker]))))
        self.assertEqual(done, [("label", "Destination", True), ("label", "Send to Log Analytics workspace"),
                                ("resource", "law", False)])
        done.clear()
        first = dict(picker, field="Backup policy", labels=["SkyCraft-Blob-Policy", "Select"], resources=[0])
        with mock.patch.object(r, "act_on_label", side_effect=acting("label")), \
                mock.patch.object(r, "open_resource", side_effect=acting("resource")):
            self.assertTrue(self.quietly(lambda: r.run_step(dict(self.STEP, items=[first]))))
        self.assertEqual(done, [("label", "Backup policy", True), ("resource", "SkyCraft-Blob-Policy", False),
                                ("label", "Select")])
        done.clear()
        with mock.patch.object(r, "act_on_label", side_effect=acting("label", outcome="unknown")), \
                mock.patch.object(r, "open_resource", side_effect=acting("resource")):
            self.assertFalse(self.quietly(lambda: r.run_step(dict(self.STEP, items=[picker]))))
        self.assertEqual(done, [("label", "Destination", True)])                   # no picker: the chain stops

    def test_a_fields_picker_is_found_as_a_field_and_clicked_not_filled(self) -> None:
        picker = {"kind": "navigation", "field": "Log Analytics workspace", "labels": ["law"], "resources": [0],
                  "line": 236}
        box = ScreenNode(attrs={"role": "combobox"})
        screen = Screen(("combobox", "Log Analytics workspace", box))
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]):
            record = self.quietly(lambda: r.act_on_label(self.STEP, picker, "Log Analytics workspace", open_field=True))
        self.assertEqual((record["kind"], record["label"], record["outcome"]),
                         ("navigation", "Log Analytics workspace", "match"))
        self.assertEqual((box.clicked, box.filled, r.ask.prompts), (1, [], []))

    def test_the_summary_counts_a_missing_resource_as_blocking_and_proposes_no_edit(self) -> None:
        r = self.runner()
        record = r.new_record(self.STEP, "navigation", self.LB)
        record.update(outcome="drift", severity="blocking", category=run.MISSING_RESOURCE,
                      observed=f"no link, cell or row named '{self.LB}' on screen")
        r.records.append(record)
        self.assertEqual(self.quietly(r.finish), 1)
        summary = (r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn(f"## blocking (1)\n- step 9.9.1 navigation `{self.LB}`: no link, cell or row named '{self.LB}' "
                      "on screen (an earlier step or lab, or the view, not the guide)\n", summary)
        self.assertIn("## proposed edits (0)\n- none", summary)


class FieldValueTests(RunnerTestCase):
    """A field value parse.py marked '"literal": false' is never typed unless the recording
    resolves it (#202); the step fails on it like on any unknown, so the person is asked."""

    SCOPE = {"kind": "field", "label": "Scope", "value": 'Click the "..." button', "line": 3, "literal": False}

    def run_field(self, item: dict) -> tuple[bool, run.Runner, mock.MagicMock]:
        step = {"id": "9.9.1", "title": "One", "expected": None, "images": [], "items": [item]}
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        match = r.new_record(step, "field", item["label"])
        match.update(outcome="match")
        with mock.patch.object(run.Runner, "act_on_label", return_value=match) as act, \
                mock.patch.object(run.Runner, "check_result"):
            done = self.quietly(lambda: r.run_step(step))
        return done, r, act

    def test_an_instruction_without_an_override_is_unknown_and_not_typed(self) -> None:
        done, r, act = self.run_field(self.SCOPE)
        self.assertFalse(done)
        act.assert_not_called()
        field = [record for record in r.records if record["kind"] == "field"]
        self.assertEqual([(record["label"], record["outcome"]) for record in field], [("Scope", "unknown")])
        self.assertEqual(field[0]["observed"], "value 'Click the \"...\" button' is an instruction, not text to "
                                               "type; add a valueOverride for this field to the recording")

    def test_with_an_override_the_override_is_typed(self) -> None:
        self.recording["steps"]["9.9.1"]["valueOverrides"]["Scope"] = "dev-skycraft-swc-rg"
        done, _, act = self.run_field(self.SCOPE)
        self.assertTrue(done)
        self.assertEqual(act.call_args.args[-1], "dev-skycraft-swc-rg")

    def test_a_bracket_token_a_placeholder_resolves_is_typed(self) -> None:
        self.recording["placeholders"]["[yourtenant]"] = "contoso"
        done, _, act = self.run_field({"kind": "field", "label": "User principal name", "line": 3, "literal": False,
                                       "value": "malfurion.stormrage@[yourtenant].onmicrosoft.com"})
        self.assertTrue(done)
        self.assertEqual(act.call_args.args[-1], "malfurion.stormrage@contoso.onmicrosoft.com")


class PromptValueTests(RunnerTestCase):
    """The prompt about a field that is not found shows the value the runner types, after the
    recording's placeholders and overrides, scrubbed as the rest of the prompt (#210)."""

    GUEST = "me@example.com"
    PASSWORD = "Fake!Pass9"
    ENV = {"SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL": GUEST, "SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX": "contoso",
           "SKYCRAFT_GUIDE_DRIFT_PASSWORD": PASSWORD}

    def prompt_for(self, label: str, value: str, override: str | None = None, literal: bool = True) -> str:
        """What the console shows when the field `label` with the guide's `value` is not found and
        input is closed at the prompt."""
        item = {"kind": "field", "label": label, "value": value, "line": 3}
        if not literal:
            item["literal"] = False
        step = {"id": "9.9.1", "title": "One", "items": [item], "images": []}
        if override is not None:
            self.recording["steps"]["9.9.1"]["valueOverrides"][label] = override
        self.recording["placeholders"]["[yourtenant]"] = "${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}"
        out = io.StringIO()
        with mock.patch.dict("os.environ", self.ENV):
            r = run.Runner(FakePage(), {**STEPS, "steps": [step]}, self.recording, self.args(), ask=Answers())
            action, typed = run.field_action(self.recording, step, item)
            self.assertEqual(action, "type")
            with mock.patch.object(run, "find_exact", return_value=None), \
                    mock.patch.object(run, "candidates_on_screen", return_value=[run.Candidate("button", "Next")]), \
                    mock.patch.object(run.time, "monotonic", lambda: r.page.now), redirect_stdout(out):
                record = r.act_on_label(step, item, label, typed)
        self.assertEqual((record["outcome"], record["observed"]), ("unknown", "no answer (input closed)"))
        return out.getvalue()

    def test_the_guide_value_when_nothing_changes_it(self) -> None:
        self.assertIn("\n  value to type: Malfurion Stormrage\n", self.prompt_for("Display name", "Malfurion Stormrage"))

    def test_an_override_is_shown_instead_of_the_guide_value(self) -> None:
        shown = self.prompt_for("Group name", "SkyCraft-Admins", override="Contoso-Admins")
        self.assertIn("\n  value to type: Contoso-Admins (from the recording's valueOverrides)\n", shown)
        self.assertNotIn("SkyCraft-Admins", shown)

    def test_a_placeholder_is_filled_and_the_value_scrubbed(self) -> None:
        shown = self.prompt_for("User principal name", "malfurion.stormrage@[yourtenant].onmicrosoft.com", literal=False)
        self.assertIn("\n  value to type: malfurion.stormrage@[tenantdomain] (the guide's, with the recording's "
                      "placeholders; environment variable SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX)\n", shown)
        self.assertNotIn("contoso.onmicrosoft.com", shown)

    def test_an_environment_variable_is_named_and_its_address_redacted(self) -> None:
        shown = self.prompt_for("Email", "guest@example.org", override="${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}")
        self.assertIn("\n  value to type: ${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL} (from the recording's valueOverrides; "
                      "environment variable SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL)\n", shown)
        self.assertNotIn(self.GUEST, shown)
        self.assertNotIn("guest@example.org", shown)

    def test_a_secret_field_shows_its_value_masked(self) -> None:
        shown = self.prompt_for("Password", "LoveAzeroth!2004")
        self.assertIn("\n  value to type: [secret]\n", shown)
        self.assertNotIn("LoveAzeroth!2004", shown)
        shown = self.prompt_for("Password", "LoveAzeroth!2004", override="${SKYCRAFT_GUIDE_DRIFT_PASSWORD}")
        self.assertIn("\n  value to type: [secret] (from the recording's valueOverrides; "
                      "environment variable SKYCRAFT_GUIDE_DRIFT_PASSWORD)\n", shown)
        self.assertNotIn(self.PASSWORD, shown)

    def test_a_plain_field_read_from_the_environment_shows_its_value_masked(self) -> None:
        # Any value read from the environment is a secret, but an address and the tenant prefix.
        self.ENV = {**self.ENV, "SKYCRAFT_TEST_DISPLAY": "Contoso Display"}
        shown = self.prompt_for("Display name", "Malfurion Stormrage", override="${SKYCRAFT_TEST_DISPLAY}")
        self.assertIn("\n  value to type: [secret] (from the recording's valueOverrides; "
                      "environment variable SKYCRAFT_TEST_DISPLAY)\n", shown)
        self.assertNotIn("Contoso Display", shown)

    def run_tag(self, value: str, override: str | None = None, env: dict | None = None):
        """run_step on a step with one tag 'Owner' whose guide value is `value`: whether it went
        through, the tag's record, the fill_tag mock and results.jsonl."""
        item = {"kind": "tag", "name": "Owner", "value": value, "line": 3}
        step = {"id": "9.9.1", "title": "One", "expected": None, "images": [], "items": [item]}
        if override is not None:
            self.recording["steps"]["9.9.1"]["valueOverrides"]["Owner"] = override
        with mock.patch.dict("os.environ", env or {}):
            r = run.Runner(FakePage(), {**STEPS, "steps": [step]}, self.recording, self.args(), ask=Answers())
            with mock.patch.object(run, "fill_tag") as fill, mock.patch.object(run.Runner, "check_result"):
                done = self.quietly(lambda: r.run_step(step))
        [tag] = [record for record in r.records if record["kind"] == "tag"]
        results = (self.tmp / "logs" / "test" / "results.jsonl").read_text(encoding="utf-8")
        return done, tag, fill, results

    def test_a_tag_record_observes_the_value_typed_not_the_guides(self) -> None:
        done, tag, fill, _ = self.run_tag("SkyCraft-Admins", override="Contoso-Admins")
        self.assertTrue(done)
        self.assertEqual(fill.call_args.args[1:], ("Owner", "Contoso-Admins"))
        self.assertEqual((tag["outcome"], tag["observed"]), ("match", "Contoso-Admins"))

    def test_a_tag_value_read_from_the_environment_is_kept_masked(self) -> None:
        done, tag, fill, results = self.run_tag("SkyCraft-Admins", override="${SKYCRAFT_TEST_OWNER}",
                                                env={"SKYCRAFT_TEST_OWNER": "Contoso Owner"})
        self.assertTrue(done)
        self.assertEqual(fill.call_args.args[1:], ("Owner", "Contoso Owner"))
        self.assertEqual((tag["outcome"], tag["observed"]), ("match", "[secret]"))
        self.assertNotIn("Contoso Owner", results)

    def test_a_tag_value_that_is_no_text_to_type_is_never_typed(self) -> None:
        for value, override, outcome, observed in (
                ("IT-001", "[Leave blank]", "match", "left out: [Leave blank]"),
                ("skycraft-[uniqueID]", None, "unknown",
                 "value 'skycraft-[uniqueID]' has an unresolved [token]; add a placeholder or a valueOverride "
                 "to the recording"),
                ('Click the "..." button', None, "unknown",
                 "value 'Click the \"...\" button' is an instruction, not text to type; add a valueOverride for "
                 "this tag to the recording")):
            with self.subTest(value=value):
                self.recording["steps"]["9.9.1"]["valueOverrides"].pop("Owner", None)
                done, tag, fill, _ = self.run_tag(value, override=override)
                fill.assert_not_called()
                self.assertEqual((done, tag["outcome"], tag["observed"]), (outcome == "match", outcome, observed))
                (self.tmp / "logs" / "test" / "results.jsonl").unlink()


GROUPS = "Microsoft_AAD_IAM/GroupsManagementMenuBlade/~/AllGroups"
USERS = "Microsoft_AAD_UsersAndTenants/UserManagementMenuBlade/~/AllUsers"
CREATE_USER = "Microsoft_AAD_UsersAndTenants/CreateUser.ReactView"


def address(view: str) -> str:
    """A Portal view pinned to the tenant, with a query, as the Portal shows it."""
    return f"https://portal.azure.com/#@{TENANT_ID}/{view}?feature.x=1"


def page_on(view: str) -> "FakePage":
    """A FakePage on `view` (address)."""
    page = FakePage()
    page.url = address(view)
    return page


class MovingPage(FakePage):
    """A FakePage whose address changes as time passes, as the Portal's does a moment after a
    Create or Save: after each wait it shows the next of `views`, staying on the last; with
    `cycle`, it starts over instead and never settles."""

    def __init__(self, *views: str, cycle: bool = False) -> None:
        super().__init__()
        self.views = [address(view) for view in views]
        self.cycle = cycle
        self.url = self.views[0]
        self.waits = 0

    def wait_for_timeout(self, ms) -> None:
        super().wait_for_timeout(ms)
        self.waits += 1
        at = self.waits % len(self.views) if self.cycle else min(self.waits, len(self.views) - 1)
        self.url = self.views[at]


class StartBladeTests(RunnerTestCase):
    """The blade a step starts on (#207): recorded once the step's first item went through on it,
    and compared with the open blade before the first item of every later run."""

    STEP = {"id": "9.9.2", "title": "Two", "portal": True, "expected": None, "images": ["images/two.png"],
            "items": [{"kind": "action", "labels": ["+ New group"], "line": 3},
                      {"kind": "action", "labels": ["Create"], "line": 4}]}
    MESSAGE = (f"the step starts on {GROUPS}, the Portal is on {USERS}; "
               "the guide does not say how to get there")

    def run_step(self, page, outcomes=("match", "match"), answers=(), step=None, moves_to=None):
        """run_step with every label and resource 'performed' as `outcomes` says, in turn; the
        first one moves the Portal to `moves_to` when it is given, as a click does. The clock is
        the page's, so waiting costs no time."""
        r = run.Runner(page, STEPS, self.recording, self.args(), ask=Answers(*answers))
        acted: list[str] = []
        left = list(outcomes)

        def act(step, item, label, *rest, **kwargs):
            acted.append(label)
            if moves_to is not None and len(acted) == 1:
                page.url = address(moves_to)
            record = r.new_record(step, item["kind"], label)
            record.update(outcome=left.pop(0) if left else "match")
            return record

        out = io.StringIO()
        with mock.patch.object(r, "act_on_label", side_effect=act), \
                mock.patch.object(r, "open_resource", side_effect=act), \
                mock.patch.object(run.time, "monotonic", lambda: page.now), redirect_stdout(out):
            done = r.run_step(step or self.STEP)
        return r, done, acted, out.getvalue()

    def entry(self) -> dict:
        return self.recording["steps"].get("9.9.2", {})

    @staticmethod
    def wrong_blade(r) -> list[dict]:
        return [x for x in r.records if x.get("category") == run.WRONG_BLADE]

    def test_a_step_without_a_recorded_blade_records_the_redacted_blade_it_started_on(self) -> None:
        page = page_on("view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Members/groupId/"
                       "11111111-2222-3333-4444-555555555555")
        r, done, _, _ = self.run_step(page)
        self.assertTrue(done)
        self.assertEqual(self.entry()["startBlade"], "Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Members")
        saved = json.loads((self.tmp / "rec.json").read_text(encoding="utf-8"))
        self.assertEqual(saved["steps"]["9.9.2"]["startBlade"], "Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Members")
        self.assertEqual((r.ask.prompts, self.wrong_blade(r)), ([], []))

    def test_the_blade_is_recorded_when_a_later_item_fails_too(self) -> None:
        _, done, _, _ = self.run_step(page_on(f"view/{GROUPS}"), outcomes=("match", "unknown"))
        self.assertFalse(done)
        self.assertEqual(self.entry()["startBlade"], GROUPS)

    def test_a_step_whose_first_item_failed_records_no_blade(self) -> None:
        # It may have started on the wrong blade: that is not the one to compare later runs with.
        for outcome, severity in (("unknown", None), ("drift", "blocking")):
            with self.subTest(outcome=outcome):
                self.recording["steps"].pop("9.9.2", None)
                r = run.Runner(page_on(f"view/{USERS}"), STEPS, self.recording, self.args(), ask=Answers())
                failed = r.new_record(self.STEP, "action", "+ New group")
                failed.update(outcome=outcome, severity=severity)
                with mock.patch.object(r, "act_on_label", return_value=failed):
                    self.assertFalse(self.quietly(lambda: r.run_step(self.STEP)))
                self.assertNotIn("startBlade", self.entry())

    def test_the_recorded_blade_the_portal_is_on_is_not_reported(self) -> None:
        for recorded in (GROUPS, GROUPS.lower()):        # compared regardless of case
            with self.subTest(recorded=recorded):
                self.recording["steps"]["9.9.2"] = {"startBlade": recorded}
                r, done, acted, _ = self.run_step(page_on(f"view/{GROUPS}/x/1"))
                self.assertTrue(done)
                self.assertEqual((acted, r.ask.prompts, self.wrong_blade(r)), (["+ New group", "Create"], [], []))
                self.assertEqual(self.entry()["startBlade"], recorded)

    def test_another_blade_is_misleading_drift_and_the_person_brings_the_portal_there(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        r, done, acted, out = self.run_step(page_on(f"view/{USERS}"), answers=[""])
        self.assertTrue(done)                            # misleading: the step goes on
        [drift] = self.wrong_blade(r)
        self.assertEqual((drift["kind"], drift["label"], drift["outcome"], drift["severity"], drift["observed"],
                          drift["proposedEdit"]), ("blade", GROUPS, "drift", "misleading", self.MESSAGE, None))
        self.assertIs(r.records[0], drift)               # before the step's first item
        self.assertIn(f"Step 9.9.2: {self.MESSAGE}.\nBring the Portal to {GROUPS}, then press Enter.", out)
        self.assertEqual((r.ask.prompts, acted), (["> "], ["+ New group", "Create"]))
        self.assertEqual(self.entry()["startBlade"], GROUPS)     # the recording keeps its blade
        screenshot = [x for x in r.records if x["kind"] == "screenshot"][-1]
        self.assertEqual((screenshot["outcome"], screenshot["category"]), ("match", None))   # images not stale

    def test_closed_input_at_the_prompt_goes_on_with_the_step(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        r, done, acted, _ = self.run_step(page_on(f"view/{USERS}"))
        self.assertTrue(done)
        self.assertEqual((len(self.wrong_blade(r)), acted), (1, ["+ New group", "Create"]))

    def test_a_view_the_run_cannot_name_is_neither_compared_nor_recorded(self) -> None:
        for url in ("https://portal.azure.com/#view/UserBlade/upn/someone%40example.com",
                    "https://login.microsoftonline.com/common/oauth2/authorize#x"):
            for recorded in (None, GROUPS):
                with self.subTest(url=url, recorded=recorded):
                    self.recording["steps"]["9.9.2"] = {} if recorded is None else {"startBlade": recorded}
                    page = FakePage()
                    page.url = url
                    r, done, _, _ = self.run_step(page)
                    self.assertTrue(done)
                    self.assertEqual((r.ask.prompts, self.wrong_blade(r)), ([], []))
                    self.assertEqual(self.entry().get("startBlade"), recorded)
                    self.assertNotIn("example.com", (self.tmp / "rec.json").read_text(encoding="utf-8"))

    def test_a_step_that_starts_with_the_global_search_or_a_resource_starts_anywhere(self) -> None:
        for first in ({"kind": "search", "labels": ["Microsoft Entra ID"], "line": 2, "scope": "global"},
                      {"kind": "search", "labels": ["Microsoft Entra ID"], "line": 2},
                      {"kind": "navigation", "labels": ["dev-skycraft-swc-lb", "Backend pools"], "line": 2,
                       "resources": [0]}):
            for recorded in (None, GROUPS):
                with self.subTest(first=first, recorded=recorded):
                    self.recording["steps"]["9.9.2"] = {} if recorded is None else {"startBlade": recorded}
                    r, done, _, _ = self.run_step(page_on(f"view/{USERS}"), step=dict(self.STEP, items=[first]))
                    self.assertTrue(done)
                    self.assertEqual((r.ask.prompts, self.wrong_blade(r)), ([], []))
                    self.assertEqual(self.entry().get("startBlade"), recorded)

    def test_a_picker_chain_that_opens_with_a_resource_does_not_start_anywhere(self) -> None:
        # The resource is looked for in the picker the field opens (#250), never in the global search.
        item = {"kind": "navigation", "labels": ["prod-skycraft-swc-vnet", "Confirm selection"], "line": 2,
                "resources": [0], "field": "Flow log type"}
        self.assertFalse(run.starts_anywhere(item))
        self.assertTrue(run.starts_anywhere({key: value for key, value in item.items() if key != "field"}))

    def test_a_blade_search_does_not_start_anywhere(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        step = dict(self.STEP, items=[{"kind": "search", "labels": ["Owner"], "line": 2, "scope": "blade"}])
        r, _, _, _ = self.run_step(page_on(f"view/{USERS}"), answers=[""], step=step)
        self.assertEqual(len(self.wrong_blade(r)), 1)

    def test_the_summary_lists_a_wrong_blade_under_misleading_and_counts_nothing(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        r, _, _, _ = self.run_step(page_on(f"view/{USERS}"), answers=[""])
        self.assertEqual(self.quietly(r.finish), 0)
        summary = (r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn(f"## misleading (1)\n- step 9.9.2: {self.MESSAGE}\n", summary)
        self.assertIn("## stale screenshots (0)\n- none", summary)
        self.assertIn("## proposed edits (0)\n- none", summary)

    def test_main_refuses_a_malformed_start_blade_before_the_browser_opens(self) -> None:
        (self.tmp / "steps.json").write_text(json.dumps(STEPS), encoding="utf-8")
        argv = ["--steps", str(self.tmp / "steps.json"), "--recording", str(self.tmp / "rec.json"),
                "--log-dir", str(self.tmp / "logs"), "--run-id", "x", "--tenant-id", "t", "--tenant-domain", "d",
                "--state", str(self.tmp / "state.json"), "--auth-state", str(self.tmp / "auth.json")]

        class Console(io.StringIO):
            def reconfigure(self, **kwargs) -> None:
                pass

        for value in ("", "   ", True, 1):
            with self.subTest(value=value):
                self.recording["steps"]["9.9.2"] = {"startBlade": value}
                (self.tmp / "rec.json").write_text(json.dumps(self.recording), encoding="utf-8")
                out = Console()
                with mock.patch.object(run, "sync_playwright") as playwright, redirect_stdout(out), \
                        mock.patch.object(run, "open_portal", side_effect=OSError("the browser opened")):
                    self.assertEqual(run.main(argv), run.NOT_STARTED)
                playwright.assert_not_called()
                self.assertIn("The recording cannot be used: step 9.9.2: 'startBlade' must be", out.getvalue())

    def test_the_blade_recorded_is_the_one_before_the_first_item(self) -> None:
        r, _, _, out = self.run_step(page_on(f"view/{GROUPS}"), moves_to=f"view/{CREATE_USER}")
        self.assertEqual(self.entry()["startBlade"], GROUPS)        # not where the first item led
        self.assertIn(f"Recorded: step 9.9.2 starts on {GROUPS}\n", out)
        self.assertIsNone(r.start_seen)

    def test_the_address_is_read_once_two_readings_agree(self) -> None:
        # Step 1.1.8 ends on AddGroup.ReactView; the Portal shows All groups a moment later.
        page = MovingPage("view/Microsoft_AAD_IAM/AddGroup.ReactView", f"view/{GROUPS}")
        self.run_step(page)
        self.assertEqual(self.entry()["startBlade"], GROUPS)
        self.assertGreaterEqual(page.waits, 2)

    def test_an_address_that_never_settles_records_no_blade(self) -> None:
        page = MovingPage(f"view/{USERS}", f"view/{GROUPS}", cycle=True)
        r, done, _, out = self.run_step(page)
        self.assertTrue(done)
        self.assertNotIn("startBlade", self.entry())
        self.assertNotIn("Recorded:", out)

    def test_another_blade_that_turns_into_the_recorded_one_is_not_reported(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        page = MovingPage("view/Microsoft_AAD_IAM/AddGroup.ReactView", "view/Microsoft_AAD_IAM/AddGroup.ReactView",
                          "view/Microsoft_AAD_IAM/AddGroup.ReactView", f"view/{GROUPS}")
        r, done, _, _ = self.run_step(page)
        self.assertTrue(done)
        self.assertEqual((r.ask.prompts, self.wrong_blade(r)), ([], []))

    def test_a_blade_and_its_overview_are_the_same_blade(self) -> None:
        lb = "resource/subscriptions/<id>/resourceGroups/dev-rg/providers/Microsoft.Network/loadBalancers/dev-lb"
        for recorded, view in ((f"{lb}/overview", lb), (lb, f"{lb}/overview"),
                               ("Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview",
                                "view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade")):
            with self.subTest(recorded=recorded, view=view):
                self.recording["steps"]["9.9.2"] = {"startBlade": recorded}
                r, _, _, _ = self.run_step(page_on(view))
                self.assertEqual((r.ask.prompts, self.wrong_blade(r)), ([], []))

    def test_resource_lists_of_two_types_are_two_blades(self) -> None:
        browse = "HubsExtension/BrowseResource.ReactView/resourceType/"
        self.recording["steps"]["9.9.2"] = {"startBlade": browse + "Microsoft.Network%2FloadBalancers"}
        r, _, _, _ = self.run_step(page_on(f"view/{browse}Microsoft.Network%2FvirtualNetworks"), answers=[""])
        self.assertEqual(len(self.wrong_blade(r)), 1)


class StartBladeExcuseTests(RunnerTestCase):
    """A step whose start is not the guide's doing (#207): the first one after a resume or
    --from-step, whose browser is new, and the first after a step the recording skips."""

    STEPS = {"lab": LAB, "guide": "guide.md", "steps": [
        {"id": f"9.9.{n}", "title": f"Step {n}", "portal": True, "expected": None, "images": [],
         "items": [{"kind": "action", "labels": ["Go"], "line": n}]} for n in (1, 2, 3)]}

    def run_lab(self, page, answers=(), state=None, failing=(), **overrides):
        """r.run() with every step's item performed, except in the steps of `failing` (unknown)."""
        r = run.Runner(page, self.STEPS, self.recording, self.args(**overrides), ask=Answers(*answers), state=state)

        def act(step, item, label, *rest, **kwargs):
            record = r.new_record(step, item["kind"], label)
            record.update(outcome="unknown" if step["id"] in failing else "match")
            return record

        out = io.StringIO()
        with mock.patch.object(r, "act_on_label", side_effect=act), \
                mock.patch.object(run.time, "monotonic", lambda: page.now), redirect_stdout(out):
            code = r.run(state)
        return r, code, out.getvalue()

    @staticmethod
    def wrong_blade(r) -> list[dict]:
        return [x for x in r.records if x.get("category") == run.WRONG_BLADE]

    def test_a_resumed_run_names_the_blade_and_does_not_blame_the_guide(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}      # 9.9.1 ended on view/One
        state = {"lab": LAB, "completed": ["9.9.1"], "inFlight": None, "finished": False}
        r, code, out = self.run_lab(FakePage(), answers=["", ""], state=state, resume=True, run_id="resume")
        self.assertEqual(code, 0)
        self.assertIn(f"Starting at step 9.9.2 (Step 2). It starts on {GROUPS}. Opened the view step 9.9.1 ended on", out)
        self.assertIn(f"Step 9.9.2 starts on {GROUPS}, the Portal is on One (the browser of this run is new: "
                      f"the blades the guide opened before the step are not open).\nBring the Portal to {GROUPS}", out)
        self.assertEqual((self.wrong_blade(r), r.ask.prompts), ([], ["> ", "> "]))
        self.assertEqual(self.recording["steps"]["9.9.3"]["startBlade"], "One")    # later steps as usual

    def test_the_step_after_a_recorded_skip_is_neither_blamed_nor_recorded(self) -> None:
        self.recording["steps"]["9.9.1"] = {"skip": "Optional"}
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        r, code, out = self.run_lab(page_on(f"view/{USERS}"), answers=[""])
        self.assertEqual(code, 0)
        self.assertIn(f"Step 9.9.2 starts on {GROUPS}, the Portal is on {USERS} (the recording skips step 9.9.1, "
                      "the step before it).", out)
        self.assertEqual(self.wrong_blade(r), [])
        del self.recording["steps"]["9.9.2"]["startBlade"]
        self.recording["steps"].pop("9.9.3", None)
        r, _, _ = self.run_lab(page_on(f"view/{USERS}"))
        self.assertNotIn("startBlade", self.recording["steps"]["9.9.2"])     # depends on the skip
        self.assertEqual(self.recording["steps"]["9.9.3"]["startBlade"], USERS)

    def test_the_step_after_one_skipped_with_s_is_neither_blamed_nor_recorded(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        r, code, out = self.run_lab(page_on(f"view/{USERS}"), answers=["s", "no licence", ""], failing={"9.9.1"})
        self.assertEqual(code, 1)                        # 9.9.1's unknown still counts
        self.assertIn(f"Step 9.9.2 starts on {GROUPS}, the Portal is on {USERS} (step 9.9.1 was skipped after "
                      "it failed).", out)
        self.assertEqual(self.wrong_blade(r), [])
        del self.recording["steps"]["9.9.2"]["startBlade"]
        self.recording["steps"].pop("9.9.3", None)
        self.run_lab(page_on(f"view/{USERS}"), answers=["s", "no licence"], failing={"9.9.1"})
        self.assertNotIn("startBlade", self.recording["steps"]["9.9.2"])     # wherever 9.9.1 left the Portal
        self.assertEqual(self.recording["steps"]["9.9.3"]["startBlade"], USERS)

    def test_the_step_after_one_done_by_hand_is_checked_as_usual(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        r, _, _ = self.run_lab(page_on(f"view/{USERS}"), answers=["c", ""], failing={"9.9.1"})
        self.assertEqual([x["step"] for x in self.wrong_blade(r)], ["9.9.2"])


class NoProposedEditTests(RunnerTestCase):
    """A drift proposes a guide edit only when its new text belongs in the guide (#211): never a
    Portal name that holds tenant or personal data. The drift is written to results.jsonl all
    the same, with the reason in 'notProposed', and the summary lists it under 'not proposed'."""

    STEP = {"id": "9.9.2", "title": "Two", "portal": True, "expected": None, "images": [],
            "items": [{"kind": "action", "labels": ["Microsoft Entra ID"], "line": 3}]}
    LINE = "1. Go back to **Microsoft Entra ID** home page"
    # As the lab 1.1 run saw them: the tenant's overview carries its name, and the Users entry
    # the resumed browser offered was the overview's 'View all N users' link.
    CANDIDATES = [run.Candidate("link", "Contoso Ltd | Overview"), run.Candidate("link", "Entra ID"),
                  run.Candidate("link", "View all 5 users"), run.Candidate("link", "someone@fabrikam.com"),
                  run.Candidate("link", "New group 9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f")]
    TOKEN_REASON = "the Portal's name holds tenant or personal data ([tenantname])"

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text(f"# Lab\n\n{self.LINE}\n", encoding="utf-8")

    def runner_for(self, *answers: str, page=None, **overrides) -> run.Runner:
        return run.Runner(page or FakePage(), STEPS, self.recording, self.args(tenant_name="Contoso Ltd", **overrides),
                          ask=Answers(*answers))

    def act(self, r: run.Runner, before=None) -> dict:
        """act_on_label for the step's label, which is not on screen; `before(r)` runs first, under
        the same clock (check_start). The record is written, as run_step writes it; what the run
        printed is in self.console."""
        clock = iter(range(0, 1_000_000, 1))               # 1 s passes between every look at the clock
        self.element = FakeElement()
        self.console = io.StringIO()
        with mock.patch.object(run, "find_exact", return_value=None), \
                mock.patch.object(run, "candidates_on_screen", return_value=self.CANDIDATES), \
                mock.patch.object(run.time, "monotonic", lambda: next(clock)), \
                mock.patch.object(run, "find_by_name", return_value=self.element) as self.find_by_name, \
                redirect_stdout(self.console):
            if before is not None:
                before(r)
            record = r.act_on_label(self.STEP, self.STEP["items"][0], "Microsoft Entra ID")
        r.write(record)
        return record

    def labels(self) -> dict:
        saved = json.loads((self.tmp / "rec.json").read_text(encoding="utf-8"))
        return saved["steps"].get("9.9.2", {}).get("labels", {})

    def summary(self, r: run.Runner) -> str:
        self.quietly(r.finish)
        return (r.run_dir / "summary.md").read_text(encoding="utf-8")

    def test_a_renamed_element_proposes_its_name(self) -> None:
        r = self.runner_for("2")
        record = self.act(r)
        self.assertEqual((record["outcome"], record["severity"], record["observed"], record["notProposed"]),
                         ("drift", "misleading", "Entra ID", None))
        self.assertEqual(record["proposedEdit"], {"line": 3, "old": self.LINE,
                                                  "new": "1. Go back to **Entra ID** home page"})
        self.assertIn("## proposed edits (1)\n- guide.md:3\n", self.summary(r))

    def test_a_cosmetic_difference_proposes_its_name_too(self) -> None:
        # Often a real rename (a change of case): the edit is what fixes the guide.
        record = self.act(self.runner_for("c 2"))
        self.assertEqual((record["severity"], record["notProposed"]), ("cosmetic", None))
        self.assertEqual(record["proposedEdit"]["new"], "1. Go back to **Entra ID** home page")

    def test_a_name_with_the_tenants_name_is_drift_without_an_edit(self) -> None:
        r = self.runner_for("1")
        record = self.act(r)
        self.assertEqual((record["outcome"], record["severity"], record["observed"]),
                         ("drift", "misleading", "[tenantname] | Overview"))
        self.assertEqual((record["proposedEdit"], record["notProposed"]), (None, self.TOKEN_REASON))
        self.assertEqual(self.labels()["Microsoft Entra ID"]["name"], "[tenantname] | Overview")   # replay finds it
        summary = self.summary(r)
        self.assertIn("## misleading (1)\n- step 9.9.2 action **Microsoft Entra ID**: observed "
                      "'[tenantname] | Overview'\n", summary)
        self.assertIn("## proposed edits (0)\n- none\n\n## not proposed (1)\n- step 9.9.2 action "
                      f"**Microsoft Entra ID**: observed '[tenantname] | Overview': {self.TOKEN_REASON}\n", summary)
        results = (r.run_dir / "results.jsonl").read_text(encoding="utf-8")
        self.assertEqual(json.loads(results.splitlines()[-1])["notProposed"], self.TOKEN_REASON)

    def test_a_replayed_name_with_a_token_proposes_no_edit_either(self) -> None:
        self.recording["steps"]["9.9.2"] = {"labels": {"Microsoft Entra ID": {
            "decision": "use", "role": "link", "name": "[tenantname] | Overview", "severity": "misleading"}}}
        r = self.runner_for()                                   # no answers: replay decides
        record = self.act(r)
        self.assertEqual((record["severity"], record["proposedEdit"], record["notProposed"]),
                         ("misleading", None, self.TOKEN_REASON))

    def test_a_replayed_name_that_only_scrub_masks_proposes_no_edit(self) -> None:
        # The Redactor leaves another directory's address and an object id alone; scrub does not.
        # A person's pick of such a name is never recorded since #315, but a recording made before
        # it may hold one (tests/Guide-Drift-Recording.Tests.ps1 fails it in CI).
        for candidate, token in ((self.CANDIDATES[3], "<email>"), (self.CANDIDATES[4], "<id>")):
            with self.subTest(token=token):
                self.recording["steps"]["9.9.2"] = {"labels": {"Microsoft Entra ID": {
                    "decision": "use", "role": candidate.role, "name": candidate.name, "severity": "misleading"}}}
                record = self.act(self.runner_for(run_id=f"scrub-{token[1:-1]}"))     # no answers: replay
                self.assertEqual((record["outcome"], record["workaround"]), ("drift", False))
                self.assertIsNone(record["proposedEdit"])
                self.assertTrue(record["notProposed"].endswith(f"({token})"), record["notProposed"])

    UNRECORDABLE = ("That element's name holds an id, an address or a secret, which the recording cannot keep: "
                    "it is used as a workaround in this run, with no guide edit, and the next run asks again.")

    def test_a_pick_whose_name_holds_an_id_or_an_outside_address_is_a_workaround_never_recorded(self) -> None:
        # #315: replay looks the element up by the name the recording keeps, so a masked name would
        # never be found, and the recording is public. The run acts on it and goes on.
        for answer, severity, name in (("4", "misleading", "someone@fabrikam.com"),
                                       ("c 5", "cosmetic", "New group 9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f")):
            with self.subTest(answer=answer):
                self.recording["steps"].pop("9.9.2", None)
                r = self.runner_for(answer, run_id=f"unrecordable-{answer[-1]}")
                record = self.act(r)
                self.assertEqual(self.element.clicked, 1)
                self.assertEqual(self.find_by_name.call_args.args[1:], ("link", name))   # this run's element
                self.assertEqual((record["outcome"], record["severity"], record["workaround"]),
                                 ("drift", severity, True))
                self.assertEqual((record["proposedEdit"], record["notProposed"]), (None, run.WORKAROUND_REASON))
                self.assertIn(self.UNRECORDABLE, self.console.getvalue())
                self.assertEqual(self.labels(), {})                # asked again on the next run
                saved = (self.tmp / "rec.json").read_text(encoding="utf-8")
                for kept_out in ("fabrikam", "9f8e7d6c", "<id>", "<email>", "[secret]"):
                    self.assertNotIn(kept_out, saved)
                results = (r.run_dir / "results.jsonl").read_text(encoding="utf-8")
                self.assertNotIn("fabrikam", results)
                self.assertNotIn("9f8e7d6c", results)

    def test_a_pick_whose_name_the_recording_keeps_is_recorded_without_the_note(self) -> None:
        record = self.act(self.runner_for("w 4", run_id="w"))      # a workaround already: no note
        self.assertEqual((record["workaround"], self.labels()), (True, {}))
        self.assertNotIn(self.UNRECORDABLE, self.console.getvalue())
        # Tenant data is a token restore() gives back: replay finds such a name, so it is recorded.
        record = self.act(self.runner_for("1"))
        self.assertEqual((record["workaround"], self.labels()["Microsoft Entra ID"]["name"]),
                         (False, "[tenantname] | Overview"))
        self.assertNotIn(self.UNRECORDABLE, self.console.getvalue())

    def test_a_step_whose_first_pick_cannot_be_recorded_goes_through_and_records_no_start_blade(self) -> None:
        r = self.run_whole_step("5")
        self.assertEqual([x["workaround"] for x in r.records if x["kind"] == "action"], [True])
        self.assertNotIn("startBlade", self.recording["steps"].get("9.9.2", {}))
        self.assertEqual(self.recording["steps"].get("9.9.2", {}).get("labels", {}), {})

    def test_the_first_reason_that_applies_is_the_one_given(self) -> None:
        # A workaround, a wrong blade and an excused start come before the token in the name.
        excuse = "the browser of this run is new: the blades the guide opened before the step are not open"
        r = self.runner_for("w 1", run_id="workaround")
        self.assertEqual(self.act(r)["notProposed"], run.WORKAROUND_REASON)
        r = self.runner_for("1", run_id="wrong-blade")
        r.excused["9.9.2"] = excuse
        drift = r.new_record({"id": "9.9.2"}, "blade", GROUPS)
        drift.update(outcome="drift", severity="misleading", category=run.WRONG_BLADE, observed="elsewhere")
        r.write(drift)
        self.assertEqual(self.act(r)["notProposed"], self.WRONG_BLADE_REASON)
        self.recording["steps"].pop("9.9.2", None)
        r = self.runner_for("1", run_id="excused")
        r.excused["9.9.2"] = excuse
        self.assertEqual(self.act(r)["notProposed"],
                         f"the step started where the run, not the guide, left the Portal ({excuse})")

    def run_whole_step(self, *answers: str, step=None, no_form: bool = False) -> run.Runner:
        """run_step on a blade the recording does not know yet, the label not on screen. With
        `no_form`, the step's first item is a field whose form is not open: find_form writes its
        wrong-blade record and, as the person opened the form, takes the blade to record from
        there; the field is then filled without a browser."""
        r = self.runner_for(*answers, page=page_on(f"view/{GROUPS}"), run_id="-".join(answers))

        def form_not_open(step, item, label, value, look, renew=None):
            drift = r.new_record(step, "field", label)
            drift.update(outcome="drift", severity="misleading", category=run.WRONG_BLADE, observed="no form")
            r.write(drift)
            r.start_seen = r.open_blade()
            return None

        clock = iter(range(0, 1_000_000, 1))
        with mock.patch.object(run, "find_exact", return_value=None), \
                mock.patch.object(run, "candidates_on_screen", return_value=self.CANDIDATES), \
                mock.patch.object(run.time, "monotonic", lambda: next(clock)), \
                mock.patch.object(run, "find_by_name", return_value=FakeElement()), \
                mock.patch.object(run, "fill_field", return_value=None), \
                mock.patch.object(r, "find_form", side_effect=form_not_open) as find_form, \
                redirect_stdout(io.StringIO()):
            self.assertTrue(r.run_step(step or self.STEP))
        self.assertEqual(find_form.called, no_form)
        return r

    def test_a_workaround_at_the_first_item_records_no_start_blade(self) -> None:
        # The person reached the guide's place another way: the blade the step began on may not be its own.
        r = self.run_whole_step("w 3")
        self.assertEqual([x["workaround"] for x in r.records if x["kind"] == "action"], [True])
        self.assertNotIn("startBlade", self.recording["steps"].get("9.9.2", {}))
        self.recording["steps"].pop("9.9.2", None)
        r = self.run_whole_step("2")                                 # a rename: recorded as usual
        self.assertEqual([x["workaround"] for x in r.records if x["kind"] == "action"], [False])
        self.assertEqual(self.recording["steps"]["9.9.2"]["startBlade"], GROUPS)

    def test_a_workaround_after_a_form_that_was_not_open_records_no_start_blade(self) -> None:
        step = dict(self.STEP, items=[{"kind": "field", "label": "Microsoft Entra ID", "value": "x", "line": 3}])
        r = self.run_whole_step("w 3", step=step, no_form=True)
        drifts = [(x["category"], x["workaround"]) for x in r.records if x["outcome"] == "drift"]
        self.assertEqual(drifts, [(run.WRONG_BLADE, False), (None, True)])
        self.assertNotIn("startBlade", self.recording["steps"].get("9.9.2", {}))
        self.recording["steps"].pop("9.9.2", None)
        self.run_whole_step("2", step=step, no_form=True)            # the form's blade, as find_form leaves it
        self.assertEqual(self.recording["steps"]["9.9.2"]["startBlade"], GROUPS)

    def test_the_summary_holds_back_an_older_edit_that_brings_a_token_into_the_guide(self) -> None:
        # A record written before #211, reloaded on -Resume, may carry such an edit.
        r = self.runner_for()
        for label, new, observed in (("Microsoft Entra ID", "1. Go back to **[tenantname] | Overview** home page",
                                      "[tenantname] | Overview"),
                                     ("[yourtenant] Ltd", "1. Open **[yourtenant] Limited**", "[yourtenant] Limited")):
            old = r.new_record({"id": "9.9.2"}, "action", label)
            old.pop("notProposed")
            old.update(outcome="drift", severity="misleading", observed=observed,
                       proposedEdit={"line": 3, "old": self.LINE if label == "Microsoft Entra ID"
                                     else "1. Open **[yourtenant] Ltd**", "new": new})
            r.records.append(old)
        summary = self.summary(r)
        # The guide's own '[yourtenant]' stays: the edit brings no token the line did not have.
        self.assertIn("## proposed edits (1)\n- guide.md:3\n  - old: `1. Open **[yourtenant] Ltd**`\n", summary)
        self.assertNotIn("**[tenantname] | Overview**", summary)
        self.assertIn(f"## not proposed (1)\n- step 9.9.2 action **Microsoft Entra ID**: observed "
                      f"'[tenantname] | Overview': {self.TOKEN_REASON}\n", summary)

    def test_an_element_used_as_a_workaround_is_drift_without_an_edit_and_is_not_recorded(self) -> None:
        r = self.runner_for("w 3")
        record = self.act(r)
        self.assertEqual(self.element.clicked, 1)               # acted on all the same
        self.assertEqual((record["outcome"], record["severity"], record["observed"]),
                         ("drift", "misleading", "View all 5 users"))
        reason = "used as a workaround, not as the guide's element"
        self.assertEqual((record["proposedEdit"], record["notProposed"]), (None, reason))
        self.assertEqual(self.labels(), {})     # replay would take it for the guide's element: asked again
        self.assertIn("## proposed edits (0)\n- none\n\n## not proposed (1)\n- step 9.9.2 action "
                      f"**Microsoft Entra ID**: observed 'View all 5 users': {reason}\n", self.summary(r))

    WRONG_BLADE_REASON = "the Portal was not where the guide leads in this step (wrong-blade)"

    def test_a_step_that_started_on_the_wrong_blade_proposes_no_edit(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": GROUPS}
        r = self.runner_for("", "2", page=page_on(f"view/{USERS}"))     # Enter at the blade prompt, then 2
        record = self.act(r, before=lambda r: r.check_start(self.STEP))
        self.assertEqual([x["category"] for x in r.records], [run.WRONG_BLADE, None])
        self.assertEqual((record["severity"], record["observed"]), ("misleading", "Entra ID"))
        self.assertEqual((record["proposedEdit"], record["notProposed"]), (None, self.WRONG_BLADE_REASON))
        self.assertEqual(self.labels()["Microsoft Entra ID"]["name"], "Entra ID")     # the decision stays recorded
        self.assertIn("## proposed edits (0)\n- none\n\n## not proposed (1)\n- step 9.9.2 action "
                      f"**Microsoft Entra ID**: observed 'Entra ID': {self.WRONG_BLADE_REASON}\n", self.summary(r))

    def test_a_form_not_open_in_the_step_counts_as_well_and_another_steps_does_not(self) -> None:
        for step_id, proposed in (("9.9.1", True), ("9.9.2", False)):
            with self.subTest(step=step_id):
                self.recording["steps"].pop("9.9.2", None)
                r = self.runner_for("2", run_id=step_id)
                drift = r.new_record({"id": step_id}, "field", "User principal name")
                drift.update(outcome="drift", severity="misleading", category=run.WRONG_BLADE, observed="no form")
                r.write(drift)
                record = self.act(r)
                self.assertEqual(record["proposedEdit"] is not None, proposed)
                self.assertEqual(record["notProposed"], None if proposed else self.WRONG_BLADE_REASON)

    def test_a_step_whose_start_is_excused_proposes_no_edit(self) -> None:
        # After a resume, a step the recording skips or one skipped with 's': whether or not a
        # blade is recorded to compare with, the blades the guide opened before it are not open.
        excuse = "the browser of this run is new: the blades the guide opened before the step are not open"
        r = self.runner_for("2")
        r.excused["9.9.2"] = excuse
        record = self.act(r)
        reason = f"the step started where the run, not the guide, left the Portal ({excuse})"
        self.assertEqual((record["severity"], record["proposedEdit"], record["notProposed"]),
                         ("misleading", None, reason))
        r.excused = {"9.9.1": excuse}                             # another step's excuse
        self.assertIsNotNone(self.act(r)["proposedEdit"])


class FormOpenTests(RunnerTestCase):
    """Before the first field of a form is filled in, an editable control for it must be on
    screen (#207): a lookup never lands on a list, as step 1.1.4's 'User principal name' did."""

    UPN = {"kind": "field", "label": "User principal name", "value": "x", "line": 4}
    MESSAGE = (f"no form with a field 'User principal name' is open; the Portal is on {USERS}; "
               "the guide does not say how to get there")

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n", encoding="utf-8")

    @staticmethod
    def users_list() -> Screen:
        """The Users list: 'User principal name' is only its column's sort button."""
        return Screen(("label", "User principal name", ScreenNode(tag="button", in_header=True)))

    def form_runner(self, page=None, ask=None) -> run.Runner:
        return run.Runner(page or page_on(f"view/{USERS}"), STEPS, self.recording, self.args(), ask=ask or Answers())

    def act(self, screen: Screen, r: run.Runner | None = None, form_start: bool = True, value: str = "chromie"):
        r = r or self.form_runner()
        step = {"id": "9.9.1", "title": "One", "items": [self.UPN], "images": []}
        out = io.StringIO()
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]), redirect_stdout(out):
            record = r.act_on_label(step, self.UPN, "User principal name", value, form_start=form_start)
        return record, r, out.getvalue()

    @staticmethod
    def opening_the_form(screen: Screen, field: ScreenNode, page=None):
        """The person at the prompt: opens the form (its field appears, the address changes).
        Input is closed at any other prompt."""
        def ask(text: str) -> str:
            ask.prompts.append(text)
            if text != "> ":
                raise EOFError
            screen.add(("textbox", "User principal name", field))
            if page is not None:
                page.url = f"https://portal.azure.com/#@{TENANT_ID}/view/{CREATE_USER}"
            return ""
        ask.prompts = []
        return ask

    def test_a_form_open_at_once_is_filled_without_a_report(self) -> None:
        field = ScreenNode(tag="input")
        record, r, _ = self.act(Screen(("textbox", "User principal name", field)))
        self.assertEqual((record["outcome"], field.filled, r.ask.prompts, r.records), ("match", ["chromie"], [], []))

    def test_a_labelled_container_with_a_text_box_counts_as_a_form(self) -> None:
        local = ScreenNode(tag="input")
        domain = ScreenNode(attrs={"role": "combobox"}, text="contoso.onmicrosoft.com")
        container = ScreenNode(children=Screen(("textbox", "", local), ("combobox", "", domain)))
        record, r, _ = self.act(Screen(("label", "User principal name", container)),
                                value="chromie@contoso.onmicrosoft.com")
        self.assertEqual((record["outcome"], local.filled, r.records), ("match", ["chromie"], []))

    def test_a_list_instead_of_the_form_is_reported_and_the_person_opens_the_form(self) -> None:
        screen, field = self.users_list(), ScreenNode(tag="input")
        record, r, out = self.act(screen, self.form_runner(ask=self.opening_the_form(screen, field)))
        [drift] = r.records
        self.assertEqual((drift["kind"], drift["label"], drift["outcome"], drift["severity"], drift["category"],
                          drift["observed"]),
                         ("field", "User principal name", "drift", "misleading", run.WRONG_BLADE, self.MESSAGE))
        self.assertIn(f"Step 9.9.1: {self.MESSAGE}.\nOpen the form, then press Enter.", out)
        self.assertEqual((r.ask.prompts, record["outcome"], field.filled), (["> "], "match", ["chromie"]))

    def test_a_read_only_field_is_no_form(self) -> None:
        # A user's Overview shows 'User principal name' as a read-only text box.
        screen = Screen(("textbox", "User principal name", ScreenNode(tag="input", read_only=True)))
        record, r, _ = self.act(screen, self.form_runner(ask=Answers("")))
        self.assertEqual([x["category"] for x in r.records], [run.WRONG_BLADE])
        self.assertEqual((record["outcome"], record["observed"]), ("unknown", "read-only: 'User principal name'"))

    def test_a_form_that_does_not_open_goes_on_as_today(self) -> None:
        record, r, _ = self.act(self.users_list())       # input closed at both prompts
        self.assertEqual([x["category"] for x in r.records], [run.WRONG_BLADE])
        self.assertEqual(r.ask.prompts, ["> ", run.HumanDecider.PROMPT])     # then asked about the label
        self.assertEqual((record["outcome"], record["observed"]), ("unknown", "no answer (input closed)"))

    def test_a_later_field_of_the_form_is_not_checked(self) -> None:
        _, r, _ = self.act(self.users_list(), form_start=False)
        self.assertEqual((r.records, r.ask.prompts), ([], [run.HumanDecider.PROMPT]))

    def test_a_first_field_with_a_recorded_decision_is_not_checked(self) -> None:
        self.recording["steps"]["9.9.1"]["labels"]["User principal name"] = {
            "decision": "use", "role": "textbox", "name": "Username", "severity": "misleading"}
        _, r, _ = self.act(self.users_list())
        self.assertEqual([x for x in r.records if x.get("category") == run.WRONG_BLADE], [])

    def test_run_step_checks_the_first_field_acted_on_of_each_form(self) -> None:
        step = {"id": "9.9.1", "title": "One", "portal": True, "expected": None, "images": [], "items": [
            {"kind": "action", "labels": ["+ New user"], "line": 2},
            {"kind": "field", "label": "Usage location", "value": "[Leave blank]", "line": 4},
            {"kind": "field", "label": "User principal name", "value": "x", "line": 5},
            {"kind": "field", "label": "Display name", "value": "y", "line": 6},
            {"kind": "action", "labels": ["Next"], "line": 7},
            {"kind": "field", "label": "Department", "value": "z", "line": 8}]}
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        calls: list[tuple[str, bool]] = []

        def act(step, item, label, value=None, form_start=False, state=None, state_only=False):
            calls.append((label, form_start))
            record = r.new_record(step, item["kind"], label)
            record.update(outcome="match")
            return record

        with mock.patch.object(r, "act_on_label", side_effect=act):
            self.assertTrue(self.quietly(lambda: r.run_step(step)))
        self.assertEqual(calls, [("+ New user", False), ("User principal name", True), ("Display name", False),
                                 ("Next", False), ("Department", True)])

    def test_a_form_opened_at_the_prompt_is_the_blade_the_step_starts_on(self) -> None:
        page = page_on(f"view/{USERS}")
        screen, field = self.users_list(), ScreenNode(tag="input")
        r = self.form_runner(page=page, ask=self.opening_the_form(screen, field, page))
        step = {"id": "9.9.2", "title": "Two", "portal": True, "expected": None, "images": [], "items": [self.UPN]}
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]):
            self.assertTrue(self.quietly(lambda: r.run_step(step)))
        self.assertEqual(self.recording["steps"]["9.9.2"]["startBlade"], CREATE_USER)

    def test_only_a_text_field_is_held_back_by_read_only(self) -> None:
        # fill_field picks, ticks or opens these: aria-readonly does not stop it.
        for node in (ScreenNode(attrs={"role": "combobox"}, read_only=True),
                     ScreenNode(tag="button", attrs={"aria-haspopup": "listbox"}, read_only=True),
                     ScreenNode(tag="input", attrs={"type": "checkbox"}, read_only=True),
                     ScreenNode(attrs={"role": "switch"}, read_only=True),
                     ScreenNode(tag="select", read_only=True)):
            with self.subTest(tag=node.tag, attrs=node.attrs):
                self.assertTrue(run.editable(node, "x"))
        self.assertFalse(run.editable(ScreenNode(tag="input", read_only=True, text="y"), "x"))
        self.assertFalse(run.editable(ScreenNode(tag="textarea", read_only=True), "x"))

    def test_a_read_only_text_field_that_already_shows_the_value_is_a_form(self) -> None:
        field = ScreenNode(tag="input", read_only=True, text="chromie")
        record, r, _ = self.act(Screen(("textbox", "User principal name", field)))
        self.assertEqual((record["outcome"], record["observed"], r.records), ("match", "already set", []))

    def test_a_labelled_container_holding_any_control_that_takes_a_value_is_a_form(self) -> None:
        radios = ScreenNode(children=Screen(("radio", "Assigned", ScreenNode(tag="input", attrs={"type": "radio"})),
                                            ("radio", "Dynamic", ScreenNode(tag="input", attrs={"type": "radio"}))))
        self.assertTrue(run.editable(radios, "Assigned"))
        _, r, _ = self.act(Screen(("label", "User principal name", radios)))
        self.assertEqual(r.records, [])                  # no form drift; filling it is fill_parts' business
        self.assertFalse(run.editable(ScreenNode(children=Screen(("text", "x", ScreenNode()))), "x"))

    def test_a_wrong_blade_and_a_missing_form_of_one_cause_make_one_record(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": CREATE_USER}
        page = page_on(f"view/{USERS}")
        r = self.form_runner(page=page, ask=Answers("", ""))
        step = {"id": "9.9.2", "title": "Two", "portal": True, "expected": None, "images": [], "items": [self.UPN]}
        out = io.StringIO()
        with mock.patch.object(run, "all_frames", lambda page: [self.users_list()]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]), redirect_stdout(out):
            r.run_step(step)
        self.assertEqual([x["kind"] for x in r.records if x.get("category") == run.WRONG_BLADE], ["blade"])
        self.assertIn(f"Step 9.9.2: no form with a field 'User principal name' is open; the Portal is on {USERS}.\n"
                      "Open the form, then press Enter.", out.getvalue())

    def test_a_form_missing_later_in_the_step_changes_neither_the_recorded_blade_nor_the_record_s_cause(self) -> None:
        page = page_on(f"view/{USERS}")
        field = ScreenNode(tag="input")
        screen = self.users_list()
        screen.add(("button", "+ New user",
                    ScreenNode(on_click=lambda: setattr(page, "url", address(f"view/{USERS}/new")))))
        r = self.form_runner(page=page, ask=self.opening_the_form(screen, field, page))
        step = {"id": "9.9.2", "title": "Two", "portal": True, "expected": None, "images": [], "items": [
            {"kind": "action", "labels": ["+ New user"], "line": 3}, self.UPN]}
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]):
            self.assertTrue(self.quietly(lambda: r.run_step(step)))
        self.assertEqual(self.recording["steps"]["9.9.2"]["startBlade"], USERS)    # not the form's blade
        self.assertIsNone(r.start_seen)
        self.assertEqual([x["kind"] for x in r.records if x.get("category") == run.WRONG_BLADE], ["field"])

    def run_two_items(self, page, answers=(), excuse=None) -> tuple[run.Runner, Screen]:
        """A runner and the Users list with a '+ New user' button whose click changes nothing,
        for run_items; step 9.9.2 is excused when `excuse` is given."""
        screen = self.users_list()
        screen.add(("button", "+ New user", ScreenNode()))
        r = self.form_runner(page=page, ask=Answers(*answers))
        if excuse:
            r.excused["9.9.2"] = excuse
        return r, screen

    def run_items(self, r, screen, items) -> None:
        step = {"id": "9.9.2", "title": "Two", "portal": True, "expected": None, "images": [], "items": items}
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]):
            self.quietly(lambda: r.run_step(step))

    def test_a_form_missing_after_a_reported_start_at_a_later_item_is_its_own_cause(self) -> None:
        self.recording["steps"]["9.9.2"] = {"startBlade": CREATE_USER}
        r, screen = self.run_two_items(page_on(f"view/{USERS}"), answers=["", ""])
        self.run_items(r, screen, [{"kind": "action", "labels": ["+ New user"], "line": 3}, self.UPN])
        self.assertEqual([x["kind"] for x in r.records if x.get("category") == run.WRONG_BLADE], ["blade", "field"])

    def test_an_excused_step_on_the_right_blade_or_none_recorded_still_reports_a_missing_form(self) -> None:
        for recorded in (USERS, None):
            with self.subTest(recorded=recorded):
                self.recording["steps"]["9.9.2"] = {} if recorded is None else {"startBlade": recorded}
                r, screen = self.run_two_items(page_on(f"view/{USERS}"), answers=[""], excuse="the run was resumed")
                self.run_items(r, screen, [self.UPN])
                self.assertEqual([x["kind"] for x in r.records if x.get("category") == run.WRONG_BLADE], ["field"])


class StopTests(RunnerTestCase):
    def test_a_closed_window_stops_before_the_candidate_prompt(self) -> None:
        r = run.Runner(FakePage(closed=True), STEPS, self.recording, self.args(), ask=Answers())
        step = {"id": "9.9.1", "title": "One", "items": [], "images": []}
        with mock.patch.object(run, "find_exact", return_value=None), self.assertRaises(run.PageClosed):
            r.act_on_label(step, {"kind": "action", "line": 1}, "+ New group")
        self.assertEqual(r.ask.prompts, [])

    def main(self, *patches) -> tuple[int, str, str]:
        """run.main() on the test steps with Playwright faked and `patches` applied: the exit
        code, what it printed and what it wrote to stderr."""
        (self.tmp / "steps.json").write_text(json.dumps(STEPS), encoding="utf-8")
        argv = ["--steps", str(self.tmp / "steps.json"), "--recording", str(self.tmp / "rec.json"),
                "--log-dir", str(self.tmp / "logs"), "--run-id", "x", "--tenant-id", TENANT_ID,
                "--tenant-domain", "contoso.onmicrosoft.com", "--state", str(self.tmp / "state.json"),
                "--auth-state", str(self.tmp / "auth.json")]

        class Playwright:
            def __enter__(self):
                return self

            def __exit__(self, *exc) -> bool:
                return False

        class Console(io.StringIO):
            def reconfigure(self, **kwargs) -> None:
                pass

        out, err = Console(), io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(mock.patch.object(run, "sync_playwright", Playwright))
            for patch in patches:
                stack.enter_context(patch)
            stack.enter_context(redirect_stdout(out))
            stack.enter_context(redirect_stderr(err))
            code = run.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_main_reports_a_failure_to_open_the_portal_as_not_started(self) -> None:
        code, out, _ = self.main(mock.patch.object(run, "open_portal", side_effect=OSError("disk full")))
        self.assertEqual(code, run.NOT_STARTED)
        self.assertIn("Could not open the Portal: OSError: disk full", out)

    # What a Playwright error carries (#212): tenant data in its first line, and a call log with
    # the element's HTML (an auto-generated password's value) and the value typed.
    CRASH = ("Locator.fill: Target page, context or browser has been closed: option "
             "'malfurion.stormrage@contoso.onmicrosoft.com' in 9f8e7d6c-5b4a-4c3d-8e2f-1a0b9c8d7e6f\nCall log:\n"
             '  - locator resolved to <input type="password" value="Qx7!fake-generated"/>\n'
             '  - fill("LoveAzeroth!2004")\n')
    SHOWN = (f"{run.PlaywrightError.__name__}: Locator.fill: Target page, context or browser has been closed: option "
             "'malfurion.stormrage@[tenantdomain]' in <id>")

    def assert_no_leak(self, text: str) -> None:
        for leak in ("contoso.onmicrosoft.com", "9f8e7d6c", TENANT_ID, "Qx7!fake-generated",
                     "LoveAzeroth!2004", "Call log", "<input"):
            self.assertNotIn(leak, text)

    def test_main_prints_a_browser_error_before_the_first_step_scrubbed(self) -> None:
        for error in (run.PlaywrightError(self.CRASH), SystemExit(f"GUARD FAILED: no tenant ID {TENANT_ID}")):
            with self.subTest(error=type(error).__name__):
                code, out, err = self.main(mock.patch.object(run, "open_portal", side_effect=error))
                self.assertEqual(code, run.NOT_STARTED)
                self.assert_no_leak(out + err)
        self.assertIn(f"The browser stopped before the first step: {self.SHOWN}\n",
                      self.main(mock.patch.object(run, "open_portal", side_effect=run.PlaywrightError(self.CRASH)))[1])

    def test_main_prints_a_crash_mid_run_as_frames_and_a_scrubbed_first_line(self) -> None:
        def crash(runner, state=None):
            raise run.PlaywrightError(self.CRASH)

        def summary_fails(runner):
            raise LookupError("summary of contoso.onmicrosoft.com")

        code, out, err = self.main(mock.patch.object(run, "open_portal", return_value=(mock.Mock(), FakePage())),
                                   mock.patch.object(run.Runner, "run", crash),
                                   mock.patch.object(run.Runner, "finish", summary_fails))
        self.assertEqual(code, run.ABORTED)
        self.assertIn(f"Stopped ({self.SHOWN}). Progress is in", out)
        # Enough to debug: the frames, the type and the first line of each error.
        self.assertIn("Traceback (most recent call last):\n", err)
        self.assertRegex(err, r'File ".*test_runner\.py", line \d+, in crash\n')
        self.assertIn(f"{self.SHOWN}\n", err)
        self.assertIn("LookupError: summary of [tenantdomain]\n", err)
        self.assert_no_leak(out + err)

    def test_once_the_runner_exists_main_scrubs_with_its_redactor_and_secrets(self) -> None:
        def crash(runner, state=None):
            runner.secrets.add("Fresh!Secret7")         # what only the runner knows
            raise LookupError("could not type Fresh!Secret7")

        code, out, err = self.main(mock.patch.object(run, "open_portal", return_value=(mock.Mock(), FakePage())),
                                   mock.patch.object(run.Runner, "run", crash))
        self.assertEqual(code, run.ABORTED)
        self.assertIn("Stopped (LookupError: could not type [secret]).", out)
        self.assertNotIn("Fresh!Secret7", out + err)

    def test_the_traceback_follows_the_chain_of_errors(self) -> None:
        redactor = run.Redactor("contoso.onmicrosoft.com", TENANT_ID)
        try:
            try:
                raise run.PlaywrightError(self.CRASH)
            except run.PlaywrightError as error:
                raise LookupError("the domain combo box: contoso.onmicrosoft.com") from error
        except LookupError as error:
            text = run.redacted_traceback(error, redactor, {"LoveAzeroth!2004"})
        self.assertLess(text.index(self.SHOWN), text.index("LookupError: the domain combo box: [tenantdomain]"))
        self.assertEqual(text.count("Traceback (most recent call last):"), 2)
        self.assert_no_leak(text)


class StatedStateTests(RunnerTestCase):
    """An action or navigation label the guide gives a state ('Check **X**', 'Uncheck **X**',
    parse.py's "checked" and "unchecked", #296): a check box, switch or radio found for it is set
    to that state, never toggled; any other element is clicked as before."""

    LABEL = "Send to Log Analytics workspace"
    ITEM = {"kind": "action", "labels": [LABEL], "checked": [0], "line": 4}

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n", encoding="utf-8")

    def act(self, screen: Screen, state: bool | None, item: dict | None = None, label: str = LABEL,
            state_only: bool = False):
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        item = item or self.ITEM
        step = {"id": "9.9.1", "title": "One", "items": [item], "images": []}
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]):
            return self.quietly(lambda: r.act_on_label(step, item, label, state=state, state_only=state_only))

    def box(self, checked: bool, role: str = "checkbox", native: bool = True) -> tuple[Screen, ScreenNode]:
        """A check box (an <input type=checkbox> or a [role=checkbox]) or a [role=switch] named LABEL."""
        attrs = {"type": "checkbox", "id": "checkbox-1"} if native and role == "checkbox" else {"role": role}
        node = ScreenNode(tag="input" if native and role == "checkbox" else "button", attrs=attrs, checked=checked)
        return Screen((role, self.LABEL, node)), node

    def test_a_box_already_in_the_state_is_already_set_and_never_clicked(self) -> None:
        for state in (True, False):
            for role, native in (("checkbox", True), ("checkbox", False), ("switch", False)):
                with self.subTest(state=state, role=role, native=native):
                    screen, node = self.box(checked=state, role=role, native=native)
                    node.check_error = AssertionError("set_checked() called on a box already in the state")
                    record = self.act(screen, state)
                    self.assertEqual((record["outcome"], record["observed"]), ("match", "already set"))
                    self.assertEqual((node.checked, node.clicked), (state, 0))

    def test_a_box_in_the_other_state_is_set_to_the_one_asked_for(self) -> None:
        for state in (True, False):
            for role, native in (("checkbox", True), ("checkbox", False), ("switch", False)):
                with self.subTest(state=state, role=role, native=native):
                    screen, node = self.box(checked=not state, role=role, native=native)
                    record = self.act(screen, state)
                    self.assertEqual((record["outcome"], record["observed"]), ("match", self.LABEL))
                    self.assertEqual((node.checked, node.clicked), (state, 0))   # set_checked(), no plain click

    def test_an_intercepted_box_is_set_through_its_label_once(self) -> None:
        screen, node = self.box(checked=False)
        node.check_error = run.PlaywrightError("Timeout 2000ms exceeded.\n  - <label> intercepts pointer events")
        node.label = ScreenNode(on_click=lambda: setattr(node, "checked", not node.checked), label_for=node)
        record = self.act(screen, True)
        self.assertEqual((record["outcome"], node.checked, node.label.clicked), ("match", True, 1))

    def test_a_box_whose_state_does_not_change_is_unknown(self) -> None:
        screen, node = self.box(checked=True)
        node.set_checked = lambda checked, timeout=None: None      # returns, but nothing changed
        record = self.act(screen, False)
        self.assertEqual((record["outcome"], node.checked), ("unknown", True))
        self.assertIn("it is still checked", record["observed"])

    def test_any_other_element_is_clicked_as_before(self) -> None:
        for state in (True, False, None):
            with self.subTest(state=state):
                button = ScreenNode(tag="button")
                record = self.act(Screen(("button", self.LABEL, button)), state)
                self.assertEqual((record["outcome"], button.clicked), ("match", 1))

    def test_a_disabled_box_already_in_the_state_is_already_set(self) -> None:
        # A box the Portal greys out in the state the guide asks for is no failure.
        for state in (True, False):
            with self.subTest(state=state):
                screen, node = self.box(checked=state)
                node.disabled = True
                record = self.act(screen, state)
                self.assertEqual((record["outcome"], record["observed"], node.clicked), ("match", "already set", 0))
                self.assertNotIn("is_disabled", node.calls)
        screen, node = self.box(checked=False)                 # in the other state: it cannot be set
        node.disabled = True
        record = self.act(screen, True)
        self.assertEqual((record["outcome"], record["observed"], node.checked),
                         ("unknown", f"disabled: '{self.LABEL}'", False))

    def test_a_state_only_label_that_is_no_toggle_is_unknown_and_never_clicked(self) -> None:
        # 'Toggle **X** to **Enabled**', 'Leave **X** unchecked': the words are no click.
        for state in (True, False):
            with self.subTest(state=state):
                button = ScreenNode(tag="button")
                record = self.act(Screen(("button", self.LABEL, button)), state, state_only=True)
                wanted = "checked" if state else "unchecked"
                self.assertEqual((record["outcome"], record["observed"], button.clicked),
                                 ("unknown", f"the guide sets '{self.LABEL}' to {wanted}, but it is no switch, "
                                             "check box or radio", 0))
        screen, node = self.box(checked=True, role="switch", native=False)     # a switch is set as usual
        record = self.act(screen, False, state_only=True)
        self.assertEqual((record["outcome"], node.checked, node.clicked), ("match", False, 0))

    def test_switches_are_looked_up_and_listed_as_candidates(self) -> None:
        self.assertIn("switch", run.ACTION_ROLES)
        self.assertIn("switch", run.CANDIDATE_ROLES)

    def test_a_box_without_a_state_is_clicked_as_before(self) -> None:
        screen, node = self.box(checked=True)
        node.check_error = AssertionError("set_checked() called for a label without a state")
        record = self.act(screen, None)
        self.assertEqual((record["outcome"], node.clicked), ("match", 1))

    def test_a_radio_is_selected_by_checked_and_never_cleared(self) -> None:
        def radio(checked: bool) -> tuple[Screen, ScreenNode]:
            node = ScreenNode(tag="input", attrs={"type": "radio", "id": "choice-1"}, checked=checked,
                              tree=snapshot_line("radio", self.LABEL, "[checked]" if checked else ""))
            return Screen(("radio", self.LABEL, node)), node

        screen, node = radio(checked=False)
        record = self.act(screen, True)
        self.assertEqual((record["outcome"], node.checked, node.clicked), ("match", True, 0))
        screen, node = radio(checked=True)
        node.check_error = AssertionError("set_checked() called on a radio already selected")
        record = self.act(screen, True)
        self.assertEqual((record["outcome"], record["observed"]), ("match", "already set"))
        record = self.act(screen, False)                       # 'Uncheck' on a selected radio
        self.assertEqual((record["outcome"], node.checked, node.clicked), ("unknown", True, 0))
        self.assertEqual(record["observed"], "LookupError: a radio cannot be cleared; pick another option")
        screen, node = radio(checked=False)
        node.check_error = AssertionError("set_checked() called on a radio not selected")
        record = self.act(screen, False)
        self.assertEqual((record["outcome"], record["observed"], node.checked), ("match", "already set", False))

    def option(self, selected: bool | None, role: str = "option", selects: bool = True) -> tuple[Screen, ScreenNode]:
        """An entry of a multi-select list (1.3.9's 'North Europe') whose state is aria-selected."""
        attrs = {"role": role} if selected is None else {"role": role, "aria-selected": str(selected).lower()}
        node = ScreenNode(tag="div", attrs=attrs, selects_on_click=selects)
        return Screen((role, self.LABEL, node)), node

    def test_an_option_already_selected_is_already_set_and_not_clicked(self) -> None:
        for role in ("option", "treeitem"):
            with self.subTest(role=role):
                screen, node = self.option(True, role)
                record = self.act(screen, True)
                self.assertEqual((record["outcome"], record["observed"], node.clicked), ("match", "already set", 0))

    def test_toggle_kind_reads_the_state_of_every_option_role(self) -> None:
        for role in run.OPTION_ROLES:
            for attr in ("aria-selected", "aria-checked"):
                with self.subTest(role=role, attr=attr):
                    node = ScreenNode(tag="div", attrs={"role": role, attr: "true"})
                    self.assertEqual(run.toggle_kind(node)[0], "option")
                    self.assertTrue(run.toggle_state(node, "option"))

    def test_an_unselected_option_is_clicked_once_and_read_back(self) -> None:
        screen, node = self.option(False)
        record = self.act(screen, True)
        self.assertEqual((record["outcome"], record["observed"], node.clicked), ("match", self.LABEL, 1))
        self.assertEqual(node.attrs["aria-selected"], "true")

    def test_an_option_whose_state_does_not_change_is_unknown(self) -> None:
        screen, node = self.option(False, selects=False)
        record = self.act(screen, True)
        self.assertEqual((record["outcome"], node.clicked), ("unknown", 1))
        self.assertIn("it was clicked to make it checked, but it is still unchecked", record["observed"])

    def test_unchecked_clears_a_selected_option(self) -> None:
        screen, node = self.option(True)
        record = self.act(screen, False)
        self.assertEqual((record["outcome"], node.clicked, node.attrs["aria-selected"]), ("match", 1, "false"))
        screen, node = self.option(False)                      # already clear: left as it is
        record = self.act(screen, False)
        self.assertEqual((record["outcome"], record["observed"], node.clicked), ("match", "already set", 0))

    def test_an_option_holding_one_check_box_sets_the_box(self) -> None:
        box = ScreenNode(tag="input", attrs={"type": "checkbox"}, checked=False)
        node = ScreenNode(tag="div", attrs={"role": "option"}, children=Screen(("checkbox", "", box)))
        record = self.act(Screen(("option", self.LABEL, node)), True)
        self.assertEqual((record["outcome"], box.checked, node.clicked), ("match", True, 0))
        box.check_error = AssertionError("set_checked() called on a box already in the state")
        record = self.act(Screen(("option", self.LABEL, node)), True)
        self.assertEqual((record["outcome"], record["observed"]), ("match", "already set"))

    def test_an_option_without_a_state_attribute_is_clicked_as_before(self) -> None:
        screen, node = self.option(None)
        record = self.act(screen, True)
        self.assertEqual((record["outcome"], node.clicked), ("match", 1))
        screen, node = self.option(None)                       # stateOnly: the words are no click
        record = self.act(screen, True, state_only=True)
        self.assertEqual((record["outcome"], node.clicked), ("unknown", 0))

    def test_run_step_gives_each_label_the_state_the_item_marks(self) -> None:
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        items = [{"kind": "navigation", "labels": ["Upload", "Overwrite if files already exist", "Upload"],
                  "checked": [1], "line": 5},
                 {"kind": "navigation", "field": "Type", "labels": ["A", "B"], "unchecked": [0], "line": 6},
                 {"kind": "action", "labels": ["Recovery", "Enable soft delete for blobs"], "checked": [1], "line": 7},
                 {"kind": "action", "labels": ["Save"], "line": 8},
                 {"kind": "action", "labels": ["Admin user", "Health"], "checked": [0], "unchecked": [1],
                  "stateOnly": [1], "line": 9}]
        step = {"id": "9.9.1", "title": "One", "portal": True, "items": items, "expected": None, "images": []}
        calls = []

        def act_on_label(runner, step, item, label, value=None, form_start=False, open_field=False, state=None,
                         state_only=False):
            calls.append((label, state) + (("only",) if state_only else ()))
            record = runner.new_record(step, item["kind"], label)
            record.update(outcome="match", observed=None)
            return record

        with mock.patch.object(run.Runner, "act_on_label", act_on_label), \
                mock.patch.object(run.Runner, "check_start", return_value=None), \
                mock.patch.object(run.Runner, "check_result"):
            self.assertTrue(self.quietly(lambda: r.run_step(step)))
        self.assertEqual(calls, [("Upload", None), ("Overwrite if files already exist", True), ("Upload", None),
                                 ("Type", None), ("A", False), ("B", None),
                                 ("Recovery", None), ("Enable soft delete for blobs", True), ("Save", None),
                                 ("Admin user", True), ("Health", False, "only")])


class DecoratedNameTests(RunnerTestCase):
    """An element whose accessible name is the guide's label plus one of the Portal's decorations
    (decide.DECORATIONS: a list row's check box 'Select row X' for an action, a required field's
    marker 'X *', a field label's info icon and marker 'X information *') is the guide's element
    (#244): the lookup finds it once SETTLE_MS of looking has not found the plain name, the record
    is a match, nobody is asked, nothing is recorded and no guide edit is proposed."""

    MEMBER = "Khadgar Archmage"
    PICK = {"kind": "action", "labels": [MEMBER], "line": 3}
    EMAIL = {"kind": "field", "label": "Email", "value": "chromie@contoso.com", "line": 4}

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n\n4. Search for and select **Khadgar Archmage**\n"
                                           "   - **Email**: `chromie@contoso.com`\n", encoding="utf-8")

    @staticmethod
    def find(screen: Screen, label: str, field: bool = False):
        with mock.patch.object(run, "all_frames", lambda page: [screen]):
            return run.find_exact(FakePage(), label, field)

    @staticmethod
    def listed(screen: Screen) -> list:
        """What candidates_on_screen() reads off `screen`: its named elements of a candidate role."""
        counts: dict = {}
        for role, name, _ in screen.everything():
            if name and role in run.CANDIDATE_ROLES:
                counts[(role, name)] = counts.get((role, name), 0) + 1
        return [run.Candidate(role, name, count) for (role, name), count in counts.items()]

    def act(self, screen: Screen, item: dict, label: str, value=None, state=None, r=None):
        r = r or run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        step = {"id": "9.9.1", "title": "One", "items": [item], "images": []}
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=self.listed(screen)):
            record = self.quietly(lambda: r.act_on_label(step, item, label, value, form_start=item["kind"] == "field",
                                                         state=state))
        return record, r

    def picker(self, *more) -> tuple[Screen, ScreenNode]:
        """A member picker: each row shows the member's name as plain text and holds a check box
        named 'Select row <name>'."""
        box = ScreenNode(attrs={"role": "checkbox"})
        return Screen(("text", self.MEMBER, ScreenNode(interactive=False)),
                      ("checkbox", f"Select row {self.MEMBER}", box),
                      ("text", "Chromie Timewalker", ScreenNode(interactive=False)),
                      ("checkbox", "Select row Chromie Timewalker", ScreenNode()), *more), box

    def assertMatchWithoutAsking(self, record: dict, r: run.Runner) -> None:
        self.assertEqual((record["outcome"], record["severity"], record.get("proposedEdit")), ("match", None, None))
        self.assertEqual(r.ask.prompts, [])
        self.assertEqual(self.recording["steps"]["9.9.1"]["labels"], {})       # exact: nothing to record

    def test_a_row_s_check_box_is_the_member_the_guide_selects(self) -> None:
        screen, box = self.picker()
        self.assertIs(self.find(screen, self.MEMBER), box)
        record, r = self.act(screen, self.PICK, self.MEMBER)
        self.assertMatchWithoutAsking(record, r)
        self.assertEqual((record["observed"], box.clicked), (self.MEMBER, 1))

    def test_each_suffix_of_a_field_label_is_the_field(self) -> None:
        for suffix in (" *", " information *"):
            with self.subTest(suffix=suffix):
                field = ScreenNode(tag="input")
                screen = Screen(("button", "information", ScreenNode(tag="button")),   # the info icon itself
                                ("textbox", f"Email{suffix}", field), ("textbox", "Display name", ScreenNode(tag="input")))
                self.assertIs(self.find(screen, "Email", field=True), field)
                self.recording["steps"]["9.9.1"]["labels"] = {}
                record, r = self.act(screen, self.EMAIL, "Email", value="chromie@contoso.com")
                self.assertMatchWithoutAsking(record, r)
                self.assertEqual((field.filled, r.records), (["chromie@contoso.com"], []))   # a form: no wrong-blade

    def test_the_info_icon_s_suffix_alone_is_no_decoration(self) -> None:
        # Known gap: no run has seen a field named 'Email information', so the person is asked.
        screen = Screen(("textbox", "Email information", ScreenNode(tag="input")))
        self.assertIsNone(self.find(screen, "Email", field=True))

    def test_a_decorated_name_is_matched_whole(self) -> None:
        for role, name, label, field in (("textbox", "Work Email information *", "Email", True),
                                         ("textbox", "Work Email *", "Email", True),
                                         ("textbox", "Email information * (optional)", "Email", True),
                                         ("checkbox", f"Select row {self.MEMBER} Jr", self.MEMBER, False),
                                         ("checkbox", f"Select rows {self.MEMBER}", self.MEMBER, False)):
            with self.subTest(name=name):
                self.assertIsNone(self.find(Screen((role, name, ScreenNode(tag="input"))), label, field=field))

    def test_a_slash_in_the_label_is_escaped_for_the_browser(self) -> None:
        # Playwright hands the pattern to the browser as a literal '/.../': an unescaped '/' ends it.
        box, patterns = ScreenNode(), []
        screen = Screen(("checkbox", "Select row Read/Write", box))
        with mock.patch.object(Screen, "get_by_role", lambda self, role, name=None, exact=None:
                               patterns.append(name) or Screen._find(self, role, name)):
            self.assertIs(self.find(screen, "Read/Write"), box)
        decorated = [p.pattern for p in patterns if isinstance(p, re.Pattern)]
        self.assertTrue(decorated)
        for pattern in decorated:
            self.assertIsNone(re.search(r"(?<!\\)/", pattern), pattern)

    def test_an_option_compared_regardless_of_case_escapes_a_slash_for_the_browser(self) -> None:
        # pick_option's pattern (ignore_case) goes to the browser as a literal '/.../' too.
        box, patterns = ScreenNode(text="10.1.0.0/16"), []
        option = ScreenNode(on_click=lambda: setattr(box, "text", "10.0.0.0/16"))
        screen = Screen(("combobox", "Address space", box))
        box.on_click = lambda: screen.add(("option", "10.0.0.0/16", option), ("option", "10.1.0.0/16", ScreenNode()))
        page = FakePage()
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: page.now), \
                mock.patch.object(Screen, "get_by_role", lambda self, role, name=None, exact=None:
                                  patterns.append(name) or Screen._find(self, role, name)):
            self.assertIsNone(run.pick_option(page, box, "div", "10.0.0.0/16", ignore_case=True))
        self.assertEqual((option.clicked, box.text), (1, "10.0.0.0/16"))
        [pattern] = {p.pattern for p in patterns if isinstance(p, re.Pattern)}
        self.assertIsNone(re.search(r"(?<!\\)/", pattern), pattern)

    def test_a_row_s_check_box_is_never_a_field(self) -> None:
        screen = Screen(("checkbox", "Select row Email", ScreenNode(tag="input", attrs={"type": "checkbox"})))
        self.assertIsNone(self.find(screen, "Email", field=True))
        self.assertIsNotNone(self.find(screen, "Email"))                    # an action selects the row

    def test_a_decoration_counts_only_on_the_roles_it_decorates(self) -> None:
        # The info icon is a button named 'Email information': clicking it opens a callout, not the field.
        for name in ("Email information", "Email information *", "Email *"):
            with self.subTest(name=name):
                info = Screen(("button", name, ScreenNode(tag="button")))
                self.assertIsNone(self.find(info, "Email"))
                self.assertIsNone(self.find(info, "Email", field=True))
        for role in ("button", "link", "row", "cell"):          # only a check box is a row's 'Select row'
            with self.subTest(role=role):
                self.assertIsNone(self.find(Screen((role, f"Select row {self.MEMBER}", ScreenNode())), self.MEMBER))
        self.assertEqual(decide.DECORATED_FIELDS, run.FIELD_ROLES)  # a field's decorations: on every field role
        # An action is never looked up in a text box, decorated or not.
        self.assertIsNone(self.find(Screen(("textbox", "Email *", ScreenNode(tag="input"))), "Email"))

    def test_the_plain_label_wins_over_a_decorated_one(self) -> None:
        link = ScreenNode()
        screen, _ = self.picker(("link", self.MEMBER, link))
        self.assertIs(self.find(screen, self.MEMBER), link)
        text = ScreenNode(interactive=True)                     # plain text inside a link counts as well
        screen, _ = self.picker(("text", self.MEMBER, text))
        self.assertIs(self.find(screen, self.MEMBER), text)
        plain, starred = ScreenNode(tag="input"), ScreenNode(tag="input")
        screen = Screen(("textbox", "Group name *", starred), ("textbox", "Group name", plain))
        self.assertIs(self.find(screen, "Group name", field=True), plain)
        bare = ScreenNode()                                      # '+ New user': the bare name is plain too
        screen = Screen(("checkbox", "Select row + New user", ScreenNode()), ("menuitem", "New user", bare))
        self.assertIs(self.find(screen, "+ New user"), bare)

    def test_a_plain_label_on_screen_twice_is_still_not_found(self) -> None:
        # As before #244: two links of the label are not found, and the person decides.
        screen, box = self.picker(("text", self.MEMBER, ScreenNode()), ("text", self.MEMBER, ScreenNode()))
        self.assertIsNone(self.find(screen, self.MEMBER))
        record, r = self.act(screen, self.PICK, self.MEMBER)
        self.assertEqual((record["outcome"], r.ask.prompts, box.clicked), ("unknown", [run.HumanDecider.PROMPT], 0))

    def test_two_decorated_matches_are_ambiguous(self) -> None:
        screen, box = self.picker(("checkbox", f"Select row {self.MEMBER}", ScreenNode()))
        with self.assertRaises(run.Ambiguous):
            self.find(screen, self.MEMBER)
        record, r = self.act(screen, self.PICK, self.MEMBER)
        self.assertEqual((record["outcome"], record["observed"], box.clicked),
                         ("unknown", f"ambiguous: 2 visible elements match named '{self.MEMBER}'", 0))
        self.assertEqual(r.ask.prompts, [])
        screen = Screen(("textbox", "Email *", ScreenNode(tag="input")),         # two decorations, one each
                        ("textbox", "Email information *", ScreenNode(tag="input")))
        with self.assertRaises(run.Ambiguous):
            self.find(screen, "Email", field=True)

    def test_decorated_matches_of_every_role_are_collected_together(self) -> None:
        screen = Screen(("textbox", "Email *", ScreenNode(tag="input")),
                        ("checkbox", "Email information *", ScreenNode(tag="input", attrs={"type": "checkbox"})))
        with self.assertRaises(run.Ambiguous):
            self.find(screen, "Email", field=True)
        screen, _ = self.picker(("radio", f"{self.MEMBER} *", ScreenNode()))
        with self.assertRaises(run.Ambiguous):
            self.find(screen, self.MEMBER)

    def test_of_a_decorated_container_and_its_input_the_input_is_the_field(self) -> None:
        # A combo box's container and the input inside it, both named 'Region *': one_field decides.
        container, input_ = ScreenNode(tag="div"), ScreenNode(tag="input")
        screen = Screen(("combobox", "Region *", container), ("textbox", "Region *", input_))
        self.assertIs(self.find(screen, "Region", field=True), input_)

    def test_a_plain_name_a_blade_shows_a_moment_later_wins_over_a_decorated_one(self) -> None:
        screen, box = self.picker()
        link = ScreenNode()

        class Rendering(FakePage):
            def wait_for_timeout(self, ms) -> None:      # the blade renders the plain link after the first look
                super().wait_for_timeout(ms)
                if not any(node is link for _, _, node in screen.everything()):
                    screen.add(("link", DecoratedNameTests.MEMBER, link))

        r = run.Runner(Rendering(), STEPS, self.recording, self.args(), ask=Answers())
        record, _ = self.act(screen, self.PICK, self.MEMBER, r=r)
        self.assertEqual((record["outcome"], link.clicked, box.clicked), ("match", 1, 0))

    def test_the_settle_time_starts_again_once_a_loading_blade_has_rendered(self) -> None:
        # The blade is still loading past the normal lookup time; once it has rendered, its rows'
        # check boxes come first and the member's name as a link a moment later.
        screen = Screen(tree=FindOnScreenTests.TOP_BAR + FindOnScreenTests.NEW_GROUP)
        box, link = ScreenNode(attrs={"role": "checkbox"}), ScreenNode()
        rendered_at = run.FIND_TIMEOUT_MS / 1000 + 5

        def render(_waits: int) -> None:
            if "row" not in screen.tree:
                if page.now >= rendered_at:
                    screen.tree += f'- row "{self.MEMBER}"\n'
            elif not screen.entries:
                screen.add(("checkbox", f"Select row {self.MEMBER}", box))
            elif len(screen.entries) == 1 and page.now >= rendered_at + 0.5:
                screen.add(("link", self.MEMBER, link))

        page = FindOnScreenTests.LoadingPage(render)
        r = run.Runner(page, STEPS, self.recording, self.args(), ask=Answers())
        with mock.patch("builtins.print"):
            record, _ = self.act(screen, self.PICK, self.MEMBER, r=r)
        self.assertEqual((record["outcome"], link.clicked, box.clicked), ("match", 1, 0))

    def test_the_settle_time_starts_again_once_the_person_has_opened_the_form(self) -> None:
        screen = FormOpenTests.users_list()
        decorated, plain = ScreenNode(tag="input"), ScreenNode(tag="input")
        opened = []

        def ask(text: str) -> str:
            if text != "> ":
                raise EOFError
            opened.append(page.now)                  # the form opens: its required marker's name first
            screen.add(("textbox", "User principal name *", decorated))
            return ""

        def render(_waits: int) -> None:
            if opened and page.now >= opened[0] + 0.5 and not plain.filled and len(screen.entries) == 2:
                screen.add(("textbox", "User principal name", plain))

        page = FindOnScreenTests.LoadingPage(render)
        r = run.Runner(page, STEPS, self.recording, self.args(), ask=ask)
        item = {"kind": "field", "label": "User principal name", "value": "x", "line": 4}
        with mock.patch("builtins.print"):
            record, _ = self.act(screen, item, "User principal name", value="khadgar", r=r)
        self.assertEqual((record["outcome"], plain.filled, decorated.filled), ("match", ["khadgar"], []))

    UPN = {"kind": "field", "label": "User principal name", "value": "x", "line": 4}
    UNTITLED = FindOnScreenTests.TOP_BAR + "- button \"Close content 'undefined'\"\n"
    NEW_USER = (FindOnScreenTests.TOP_BAR + '- heading "New user" [level=2]\n'
                "- button \"Close content 'New user'\"\n" '- textbox "Display name"\n')

    def form_blade_rendering(self, *fields) -> tuple[Screen, FakePage]:
        """A form's blade still loading (its title reads 'undefined') past the normal lookup time;
        once it has rendered, `fields` ((name, node) of text boxes) appear one per poll."""
        screen = Screen(tree=self.UNTITLED)
        rendered_at = run.FIND_TIMEOUT_MS / 1000 + 5
        waiting = list(fields)

        def render(_waits: int) -> None:
            if screen.tree == self.UNTITLED:
                if page.now >= rendered_at:
                    screen.tree = self.NEW_USER
            elif waiting:
                name, node = waiting.pop(0)
                screen.add(("textbox", name, node))

        page = FindOnScreenTests.LoadingPage(render)
        return screen, page

    def test_on_a_form_that_renders_late_a_plain_field_after_a_decorated_one_wins(self) -> None:
        decorated, plain = ScreenNode(tag="input"), ScreenNode(tag="input")
        screen, page = self.form_blade_rendering(("User principal name *", decorated), ("User principal name", plain))
        r = run.Runner(page, STEPS, self.recording, self.args(), ask=Answers())
        with mock.patch("builtins.print"):
            record, _ = self.act(screen, self.UPN, "User principal name", value="khadgar", r=r)
        self.assertEqual((record["outcome"], plain.filled, decorated.filled, r.records), ("match", ["khadgar"], [], []))
        self.assertGreater(page.now, run.FIND_TIMEOUT_MS / 1000 + 5)        # found on the rendered blade

    def test_on_a_form_that_renders_late_a_read_only_field_is_still_no_form(self) -> None:
        read_only = ScreenNode(tag="input", read_only=True)
        screen, page = self.form_blade_rendering(("User principal name", read_only))
        r = run.Runner(page, STEPS, self.recording, self.args(), ask=Answers(""))
        with mock.patch("builtins.print"):
            record, _ = self.act(screen, self.UPN, "User principal name", value="khadgar", r=r)
        self.assertEqual([x["category"] for x in r.records], [run.WRONG_BLADE])
        self.assertEqual((record["outcome"], read_only.filled), ("unknown", []))

    def test_a_row_found_through_its_decoration_is_clicked_as_before(self) -> None:
        # 'Search for and select **X**' states no state (parse.py, #296), so the check box is
        # clicked, as when the person picked it: a row already ticked is cleared by that click.
        screen, box = self.picker()
        box.checked = True
        record, _ = self.act(screen, self.PICK, self.MEMBER)
        self.assertEqual((record["outcome"], box.calls[-1], box.clicked), ("match", "click", 1))
        # 'Check **X**' states one: a row already ticked is left as it is.
        screen, box = self.picker()
        box.checked = True
        record, _ = self.act(screen, dict(self.PICK, checked=[0]), self.MEMBER, state=True)
        self.assertEqual((record["outcome"], record["observed"], box.clicked), ("match", "already set", 0))

    def test_a_decorated_name_never_proposes_a_guide_edit(self) -> None:
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        step = {"id": "9.9.1", "title": "One", "items": [self.PICK], "images": []}
        self.assertIsNone(r.proposed_edit(3, self.MEMBER, f"Select row {self.MEMBER}"))
        self.assertIsNone(r.proposed_edit(4, "Email", "Email information *"))
        self.assertIsNotNone(r.proposed_edit(3, self.MEMBER, "Khadgar"))           # a rename still proposes
        drift = run.Decision(kind="drift", name=f"Select row {self.MEMBER}", role="checkbox", severity="cosmetic")
        self.assertEqual(r.not_proposed(step, drift, self.MEMBER),
                         "the Portal's name only decorates the guide's label (a list row's check box)")
        self.assertIsNone(r.not_proposed(step, run.Decision(kind="drift", name="Khadgar", severity="cosmetic"),
                                         self.MEMBER))

    def test_the_summary_holds_back_an_older_edit_that_only_decorates_the_label(self) -> None:
        # A results.jsonl written before #244, reloaded on -Resume, proposes 'Select row X'.
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        old = r.new_record({"id": "9.9.1"}, "action", self.MEMBER)
        line = "4. Search for and select **Khadgar Archmage**"
        old.update(outcome="drift", severity="cosmetic", observed=f"Select row {self.MEMBER}",
                   proposedEdit={"line": 3, "old": line, "new": line.replace("**Khadgar", "**Select row Khadgar")})
        r.records.append(old)
        self.quietly(r.finish)
        summary = (r.run_dir / "summary.md").read_text(encoding="utf-8")
        self.assertIn("## proposed edits (0)\n- none", summary)
        self.assertIn(f"## not proposed (1)\n- step 9.9.1 action **{self.MEMBER}**: observed "
                      f"'Select row {self.MEMBER}': the Portal's name only decorates the guide's label "
                      "(a list row's check box)", summary)

    def test_a_replay_of_lab_1_1_finds_the_decorated_elements_and_reports_no_cosmetic_drift(self) -> None:
        # The four elements lab 1.1's replay of 2026-10-08 reported as cosmetic drift, on screens
        # like the ones the run saw, with the recording as committed: nobody is asked, nothing is
        # recorded, and the summary has no drift and no proposed edit.
        lab = Path(__file__).resolve().parent.parent / "recordings" / "lab-1.1.json"
        self.recording = json.loads(lab.read_text(encoding="utf-8"))
        (self.tmp / "rec.json").write_text(json.dumps(self.recording), encoding="utf-8")
        before = json.dumps(self.recording, sort_keys=True)
        for step_id, entry in self.recording["steps"].items():
            for label, decision in entry["labels"].items():
                self.assertIsNone(run.decoration_of(decision.get("name") or "", label), (step_id, label))
        guide = ["# Lab 1.1", "", "   - **Email**: `istormrage@illidari.com`",
                 "2. Search for and select **Malfurion Stormrage**", "4. Search for and select **Khadgar Archmage**",
                 "4. Search for and select **Chromie Timewalker**"]
        (self.tmp / "guide.md").write_text("\n".join(guide) + "\n", encoding="utf-8")
        steps = {"lab": "1.1", "guide": "guide.md", "steps": [
            {"id": step_id, "title": step_id, "portal": True, "items": [], "expected": None, "images": []}
            for step_id in ("1.1.5", "1.1.7", "1.1.8", "1.1.9")]}
        r = run.Runner(FakePage(), steps, self.recording, self.args(), ask=Answers())
        email = ScreenNode(tag="input")
        invite = Screen(("textbox", "Email information *", email), ("button", "information", ScreenNode(tag="button")),
                        ("button", "information", ScreenNode(tag="button")),
                        ("textbox", "Display name", ScreenNode(tag="input")),
                        ("textbox", "Invite redirect URL information *", ScreenNode(tag="input")))
        record, _ = self.act(invite, {"kind": "field", "label": "Email", "value": "x", "line": 3}, "Email",
                             value="istormrage@illidari.com", r=r)
        r.write(record)
        clicked = []
        for step_id, line, member, other in (("1.1.7", 4, "Malfurion Stormrage", "Illidan Stormrage"),
                                             ("1.1.8", 5, "Khadgar Archmage", "Chromie Timewalker"),
                                             ("1.1.9", 6, "Chromie Timewalker", "Khadgar Archmage")):
            box = ScreenNode()
            screen = Screen(("text", member, ScreenNode(interactive=False)), ("checkbox", f"Select row {member}", box),
                            ("text", other, ScreenNode(interactive=False)),
                            ("checkbox", f"Select row {other}", ScreenNode()),
                            ("button", "Group name information", ScreenNode(tag="button")),
                            ("checkbox", "Select row Azure Resource Manager", ScreenNode()))
            item = {"kind": "action", "labels": [member], "line": line}
            step = {"id": step_id, "title": step_id, "items": [item], "images": []}
            with mock.patch.object(run, "all_frames", lambda page, screen=screen: [screen]), \
                    mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                    mock.patch.object(run, "candidates_on_screen", return_value=self.listed(screen)):
                r.write(self.quietly(lambda: r.act_on_label(step, item, member)))
            clicked.append(box.clicked)
        self.assertEqual(([x["outcome"] for x in r.records], email.filled, clicked),
                         (["match"] * 4, ["istormrage@illidari.com"], [1, 1, 1]))
        self.assertEqual(r.ask.prompts, [])
        self.assertEqual(json.dumps(json.loads((self.tmp / "rec.json").read_text(encoding="utf-8")), sort_keys=True),
                         before)
        self.assertEqual(self.quietly(r.finish), 0)
        summary = (r.run_dir / "summary.md").read_text(encoding="utf-8")
        for section in ("blocking", "misleading", "cosmetic", "unknown", "proposed edits", "not proposed"):
            self.assertIn(f"## {section} (0)\n- none", summary)


class PickerRowTests(RunnerTestCase):
    """A policy picker's row names its policy in a cell and holds a radio named 'Select' (1.3.5,
    1.3.9; #342): that radio is the element the guide's 'select **X**' names (find_row_control),
    a match with nobody asked, nothing recorded and no guide edit."""

    PICK = {"kind": "action", "labels": ["Allowed locations"], "line": 3}

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n\n3. Select **Allowed locations**\n", encoding="utf-8")

    @staticmethod
    def radio(checked: bool = False) -> ScreenNode:
        return ScreenNode(attrs={"role": "radio"}, tag="input", checked=checked, tree='- radio "Select"')

    @staticmethod
    def box(name: str = "Select") -> ScreenNode:
        return ScreenNode(attrs={"role": "checkbox"}, tag="input", tree=f'- checkbox "{name}"')

    @staticmethod
    def row(name: str, *controls: tuple[str, ScreenNode], cell: str = "gridcell") -> tuple[str, str, ScreenNode]:
        parts = [(role, "Select", node) for role, node in controls] + [(cell, name, ScreenNode(interactive=False))]
        return "row", f"Select {name} 1.1.0 General BuiltIn", ScreenNode(children=Screen(*parts))

    HEADER = ("row", "Name Version Category Type",
              ScreenNode(children=Screen(("columnheader", "Name", ScreenNode()), ("columnheader", "Version", ScreenNode()))))

    @staticmethod
    def find(screen: Screen, label: str = "Allowed locations"):
        with mock.patch.object(run, "all_frames", lambda page: [screen]):
            return run.find_exact(FakePage(), label)

    def act(self, screen: Screen, state=None):
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        step = {"id": "9.9.1", "title": "One", "items": [self.PICK], "images": []}
        listed = [run.Candidate(role, name) for role, name, _ in screen.everything() if name]
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=listed):
            record = self.quietly(lambda: r.act_on_label(step, self.PICK, "Allowed locations", state=state))
        return record, r

    def test_a_picker_row_is_selected_by_its_select_radio(self) -> None:
        radio = self.radio()
        screen = Screen(self.HEADER, self.row("Require a tag on resource groups", ("radio", ScreenNode())),
                        self.row("Allowed locations", ("radio", radio)))
        self.assertIs(self.find(screen), radio)
        record, r = self.act(screen)
        self.assertEqual((record["outcome"], record["severity"], record.get("proposedEdit")), ("match", None, None))
        self.assertEqual((r.ask.prompts, self.recording["steps"]["9.9.1"]["labels"]), ([], {}))
        self.assertTrue(radio.checked)

    def test_the_row_named_exactly_wins_among_three(self) -> None:
        radio = self.radio()
        screen = Screen(self.HEADER,
                        self.row("Azure Cosmos DB allowed locations", ("radio", ScreenNode())),
                        self.row("Allowed locations", ("radio", radio)),
                        self.row("Allowed locations for resource groups", ("radio", ScreenNode())))
        self.assertIs(self.find(screen), radio)

    def test_a_cell_role_row_counts_as_well(self) -> None:
        radio = self.radio()
        self.assertIs(self.find(Screen(self.row("Allowed locations", ("radio", radio), cell="cell"))), radio)

    def test_two_rows_of_that_exact_name_are_ambiguous(self) -> None:
        screen = Screen(self.row("Allowed locations", ("radio", self.radio())),
                        self.row("Allowed locations", ("radio", self.radio())))
        with self.assertRaises(run.Ambiguous):
            self.find(screen)

    def test_a_row_already_selected_is_already_set(self) -> None:
        radio = self.radio(checked=True)
        record, _ = self.act(Screen(self.row("Allowed locations", ("radio", radio))))
        self.assertEqual((record["outcome"], record["observed"], radio.clicked), ("match", "already set", 0))

    def test_a_check_box_row_is_ticked_never_cleared(self) -> None:
        box = self.box()
        box.checked = True
        record, _ = self.act(Screen(self.row("Allowed locations", ("checkbox", box))))
        self.assertEqual((record["outcome"], record["observed"], box.checked, box.clicked), ("match", "already set", True, 0))
        box = self.box()
        record, _ = self.act(Screen(self.row("Allowed locations", ("checkbox", box))))
        self.assertEqual((record["outcome"], box.checked), ("match", True))

    def test_a_check_box_that_only_decorates_the_label_is_no_row_control(self) -> None:
        screen = Screen(self.row("Allowed locations", ("checkbox", self.box("Allowed locations *"))))
        self.assertIsNone(self.find(screen))

    def test_a_row_without_one_selection_control_is_not_found(self) -> None:
        for controls in ((), (("radio", self.radio()), ("radio", self.radio())),
                         (("checkbox", self.box()), ("checkbox", self.box()))):
            with self.subTest(controls=len(controls)):
                self.assertIsNone(self.find(Screen(self.row("Allowed locations", *controls))))

    def test_the_header_row_is_no_row(self) -> None:
        header = ("row", "Allowed locations",
                  ScreenNode(children=Screen(("columnheader", "Allowed locations", ScreenNode()),
                                             ("gridcell", "Allowed locations", ScreenNode()),
                                             ("radio", "Select", self.radio()))))
        self.assertIsNone(self.find(Screen(header)))

    def test_a_hidden_row_is_no_row(self) -> None:
        hidden = self.row("Allowed locations", ("radio", self.radio()))
        hidden[2].shown = False
        self.assertIsNone(self.find(Screen(hidden)))

    def test_the_plain_name_still_wins_over_a_row(self) -> None:
        link = ScreenNode()
        screen = Screen(("link", "Allowed locations", link), self.row("Allowed locations", ("radio", self.radio())))
        self.assertIs(self.find(screen), link)


class TextLabelTests(RunnerTestCase):
    """A field whose label is plain text beside it, not its accessible name (1.3.7's unnamed
    combo boxes under 'Category', 'Sub-category', 'Impact level'; 1.3.15's 'Name' above a text
    box named by its placeholder; #342): find_by_text_label, the guide's element, nothing recorded."""

    @staticmethod
    def label(text: str, control: ScreenNode | None) -> tuple[str, str, ScreenNode]:
        return "text", text, ScreenNode(interactive=False, next_control=control)

    @staticmethod
    def combo() -> ScreenNode:
        return ScreenNode(attrs={"role": "combobox"}, tag="div")

    def advisor(self) -> tuple[Screen, list[ScreenNode]]:
        """Run B's Create Advisor Alerts iframe: three combo boxes without a name; their labels
        are the text before each (Step-1.3.7.png)."""
        boxes = [self.combo() for _ in range(3)]
        screen = Screen(("radiogroup", "Configured by", ScreenNode()),
                        self.label("Category", boxes[0]), ("combobox", "", boxes[0]),
                        self.label("Sub-category", boxes[1]), ("combobox", "", boxes[1]),
                        self.label("Impact level", boxes[2]), ("combobox", "", boxes[2]))
        return screen, boxes

    @staticmethod
    def find(screen: Screen, label: str, field: bool = True, **kwargs):
        with mock.patch.object(run, "all_frames", lambda page: [screen]):
            return run.find_exact(FakePage(), label, field=field, **kwargs)

    def test_category_is_the_unnamed_combobox_after_its_text(self) -> None:
        screen, boxes = self.advisor()
        for text, box in zip(("Category", "Sub-category", "Impact level"), boxes):
            with self.subTest(label=text):
                self.assertIs(self.find(screen, text), box)

    def test_name_is_the_textbox_named_by_its_placeholder(self) -> None:
        # blade-1.3.16: textbox "Enter a unique name" under the text "Name"
        box = ScreenNode(attrs={"role": "textbox"}, tag="input")
        screen = Screen(self.label("Name", box), ("textbox", "Enter a unique name", box))
        self.assertIs(self.find(screen, "Name"), box)

    def test_text_with_other_text_before_the_control_is_no_label(self) -> None:
        screen = Screen(self.label("Category", None), ("text", "Choose carefully", ScreenNode(interactive=False)),
                        ("combobox", "", self.combo()))
        self.assertIsNone(self.find(screen, "Category"))

    def test_a_text_label_on_screen_twice_is_ambiguous(self) -> None:
        first, second = self.combo(), self.combo()
        screen = Screen(self.label("Category", first), ("combobox", "", first),
                        self.label("Category", second), ("combobox", "", second))
        with self.assertRaises(run.Ambiguous):
            self.find(screen, "Category")

    def test_a_field_named_by_its_accessible_name_still_wins(self) -> None:
        named, other = ScreenNode(attrs={"role": "textbox"}, tag="input"), self.combo()
        screen = Screen(self.label("Name", other), ("textbox", "Name", named))
        self.assertIs(self.find(screen, "Name"), named)

    def test_it_counts_only_once_the_decorated_names_may(self) -> None:
        screen, _ = self.advisor()
        self.assertIsNone(self.find(screen, "Category", decorated=False))

    def test_interactive_text_is_no_label(self) -> None:
        screen = Screen(("text", "Category", ScreenNode(interactive=True, next_control=self.combo())))
        self.assertIsNone(self.find(screen, "Category"))

    def test_the_newest_blade_wins_among_equal_labels(self) -> None:
        old, new = self.combo(), self.combo()
        old.blade, new.blade = ("Earlier", 0.0), ("Newest", 500.0)
        screen = Screen(self.label("Category", old), ("combobox", "", old),
                        self.label("Category", new), ("combobox", "", new))
        self.assertIs(self.find(screen, "Category"), new)

    def test_an_action_uses_it_only_for_a_control_that_opens_a_list(self) -> None:
        box, button = self.combo(), ScreenNode(attrs={"role": "button"}, tag="button")
        self.assertIs(self.find(Screen(self.label("Category", box), ("combobox", "", box)), "Category", field=False), box)
        self.assertIsNone(self.find(Screen(self.label("Category", button), ("button", "", button)), "Category", field=False))
        listbox = ScreenNode(attrs={"role": "button", "aria-haspopup": "listbox"}, tag="button")
        self.assertIs(self.find(Screen(self.label("Category", listbox), ("button", "", listbox)), "Category", field=False), listbox)

    FIELD = {"kind": "field", "label": "Name", "value": "budget", "line": 4}

    def test_a_form_whose_first_field_is_found_by_its_text_is_open(self) -> None:
        (self.tmp / "guide.md").write_text("# Lab\n", encoding="utf-8")
        box = ScreenNode(attrs={"role": "textbox"}, tag="input")
        screen = Screen(self.label("Name", box), ("textbox", "Enter a unique name", box))
        r = run.Runner(page_on(f"view/{USERS}"), STEPS, self.recording, self.args(), ask=Answers())
        step = {"id": "9.9.1", "title": "One", "items": [self.FIELD], "images": []}
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]):
            record = self.quietly(lambda: r.act_on_label(step, self.FIELD, "Name", "budget", form_start=True))
        self.assertEqual((record["outcome"], box.filled, r.ask.prompts, r.records, self.recording["steps"]["9.9.1"]["labels"]),
                         ("match", ["budget"], [], [], {}))


class ListOptionTests(RunnerTestCase):
    """A list option picked by its name (#342): the roles option and treeitem, a region prefix
    ('(Europe) Sweden Central'), a filter box, a list that scrolls, and the list's tree kept when
    the option is missing."""

    @staticmethod
    def pick(page, box, value, tag="div", **kwargs):
        with mock.patch.object(run.time, "monotonic", lambda: page.now):
            return run.pick_option(page, box, tag, value, **kwargs)

    def opened(self, role: str, names: list[str], owned: bool = False):
        """A combo box that shows `names` as `role` entries once clicked; an option sets its text."""
        screen, page = Screen(), FakePage()
        box = ScreenNode(attrs={"role": "combobox"}, tag="div")
        options = {}
        for name in names:
            options[name] = ScreenNode(on_click=lambda name=name: setattr(box, "text", name))
        if owned:
            box.attrs["aria-controls"] = "list"
            popup = ScreenNode(attrs={"id": "list"}, children=Screen(*((role, n, o) for n, o in options.items())))
            box.on_click = lambda: screen.add(("tree", "List of options", popup))
        else:
            box.on_click = lambda: screen.add(*((role, n, o) for n, o in options.items()))
        screen.add(("combobox", "Field", box))
        return screen, page, box, options

    def test_reset_period_monthly_is_a_treeitem_under_calendar_months(self) -> None:
        # blade-1.3.16: combobox "Reset period", dialog > tree "List of options" > treeitem "Monthly"
        names = ["Billing month", "Monthly", "Quarterly", "Annually"]
        for owned in (False, True):
            with self.subTest(owned=owned):
                screen, page, box, options = self.opened("treeitem", names, owned)
                with mock.patch.object(run, "all_frames", lambda page: [screen]):
                    self.assertIsNone(self.pick(page, box, "Monthly"))
                self.assertEqual((options["Monthly"].clicked, options["Quarterly"].clicked, box.text), (1, 0, "Monthly"))

    def test_region_sweden_central_finds_the_europe_prefixed_option(self) -> None:
        # Step-1.3.6.png: a list of '(Europe) North Europe', '(Europe) Sweden Central', ...
        names = ["(Europe) North Europe", "(Europe) Sweden Central", "(US) East US"]
        screen, page, box, options = self.opened("option", names)
        with mock.patch.object(run, "all_frames", lambda page: [screen]):
            self.assertIsNone(self.pick(page, box, "Sweden Central"))
        self.assertEqual((options["(Europe) Sweden Central"].clicked, options["(Europe) North Europe"].clicked,
                          box.text), (1, 0, "(Europe) Sweden Central"))

    def test_an_exact_name_wins_over_a_prefixed_one(self) -> None:
        screen, page, box, options = self.opened("option", ["Sweden Central", "(Europe) Sweden Central"])
        with mock.patch.object(run, "all_frames", lambda page: [screen]):
            self.assertIsNone(self.pick(page, box, "Sweden Central"))
        self.assertEqual((options["Sweden Central"].clicked, options["(Europe) Sweden Central"].clicked), (1, 0))

    def test_a_field_showing_the_prefixed_name_is_already_set(self) -> None:
        screen, page, box, options = self.opened("option", ["(Europe) Sweden Central"])
        box.text = "(Europe) Sweden Central"
        with mock.patch.object(run, "all_frames", lambda page: [screen]):
            self.assertEqual(self.pick(page, box, "Sweden Central"), "already set")
        self.assertEqual(box.clicked, 0)

    def test_two_options_after_removing_the_prefix_are_ambiguous(self) -> None:
        screen, page, box, options = self.opened("option", ["(Europe) Sweden Central", "(Asia Pacific) Sweden Central"])
        with mock.patch.object(run, "all_frames", lambda page: [screen]), self.assertRaises(run.Ambiguous):
            self.pick(page, box, "Sweden Central")
        self.assertEqual([o.clicked for o in options.values()], [0, 0])

    def test_the_filter_box_is_typed_into_first(self) -> None:
        for editable in (False, True):
            with self.subTest(editable=editable):
                screen, page = Screen(), FakePage()
                box = ScreenNode(attrs={"role": "combobox", "aria-controls": "list"}, tag="input" if editable else "div")
                option = ScreenNode(on_click=lambda: setattr(box, "text", "(Europe) Sweden Central"))
                children = Screen()
                popup = ScreenNode(attrs={"id": "list"}, children=children)
                filter_box = ScreenNode(tag="input", on_fill=lambda: children.add(
                    ("option", "(Europe) Sweden Central", option)))
                if editable:        # the combo box is the filter: the popup has no text box of its own
                    box.on_fill = filter_box.on_fill
                else:
                    children.add(("searchbox", "Filter", filter_box))
                box.on_click = lambda: screen.add(("listbox", "Regions", popup))
                screen.add(("combobox", "Region", box))
                with mock.patch.object(run, "all_frames", lambda page: [screen]):
                    self.assertIsNone(self.pick(page, box, "(Europe) Sweden Central", tag=box.tag))
                typed = box.filled if editable else filter_box.filled
                self.assertEqual((typed, option.clicked), (["Sweden Central"], 1))

    def paged(self, pages: list[list[str]], end_scrolls: bool = True):
        """A list that shows pages[0], and the next page after each scroll (`state['scrolls']`
        counts them); with `end_scrolls` False the last page cannot be scrolled past."""
        screen, page, state = Screen(), FakePage(), {"scrolls": 0}
        box = ScreenNode(attrs={"role": "combobox", "aria-controls": "list"}, tag="div")
        children, options = Screen(), {}

        def show(index: int) -> None:
            children.entries.clear()
            for name in pages[index]:
                options[name] = ScreenNode(on_click=lambda name=name: setattr(box, "text", name))
                children.add(("option", name, options[name]))

        def scroll() -> bool:
            state["scrolls"] += 1
            if state["scrolls"] >= len(pages) and not end_scrolls:
                return False
            show(min(state["scrolls"], len(pages) - 1))
            return True

        popup = ScreenNode(attrs={"id": "list"}, children=children, on_scroll=scroll)
        show(0)
        box.on_click = lambda: screen.add(("listbox", "Regions", popup))
        screen.add(("combobox", "Region", box))
        return screen, page, box, options, state, popup

    def test_an_option_shown_only_after_scrolling_is_found(self) -> None:
        screen, page, box, options, state, _ = self.paged([["(Europe) North Europe"], ["(Europe) Norway East"],
                                                           ["(Europe) Sweden Central"]])
        with mock.patch.object(run, "all_frames", lambda page: [screen]):
            self.assertIsNone(self.pick(page, box, "Sweden Central"))
        self.assertEqual((state["scrolls"], options["(Europe) Sweden Central"].clicked), (2, 1))

    def test_scrolling_stops_after_twenty_pages(self) -> None:
        pages = [[f"(Europe) Region {n}"] for n in range(40)]
        screen, page, box, _, state, _ = self.paged(pages)
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                self.assertRaisesRegex(LookupError, "option 'Sweden Central' not found"):
            self.pick(page, box, "Sweden Central")
        self.assertEqual((state["scrolls"], run.LIST_SCROLL_PAGES), (20, 20))

    def test_scrolling_stops_when_the_list_does_not_move(self) -> None:
        screen, page, box, _, state, _ = self.paged([["(Europe) North Europe"], ["(Europe) Norway East"]],
                                                    end_scrolls=False)
        with mock.patch.object(run, "all_frames", lambda page: [screen]), self.assertRaises(LookupError):
            self.pick(page, box, "Sweden Central")
        self.assertEqual(state["scrolls"], 2)       # the second scroll found the end: nothing moved

    def test_a_missing_option_saves_the_list_tree_scrubbed(self) -> None:
        tree = ('- listbox "Regions":\n  - option "(Europe) North Europe"\n'
                '  - option "Item 3f2a9c1e-8b4d-4e6f-9a1b-2c3d4e5f6a7b"')
        screen, page, box, _, _, popup = self.paged([["(Europe) North Europe"]])
        popup.tree = tree
        seen = []
        with mock.patch.object(run, "all_frames", lambda page: [screen]), self.assertRaises(LookupError):
            self.pick(page, box, "Sweden Central", diagnose=seen.append)
        self.assertEqual(len(seen), 1)
        self.assertIn("(Europe) North Europe", seen[0])
        # the runner keeps it as list-<step>-<line>.aria.txt, scrubbed as the blade outlines are
        (self.tmp / "guide.md").write_text("# Lab\n", encoding="utf-8")
        r = run.Runner(page_on(f"view/{USERS}"), STEPS, self.recording, self.args(), ask=Answers())
        step = {"id": "9.9.1", "title": "One", "items": [], "images": []}
        self.quietly(lambda: r.save_list_tree(step, {"line": 7}, seen[0]))
        saved = (r.run_dir / "list-9.9.1-7.aria.txt").read_text(encoding="utf-8")
        self.assertIn("(Europe) North Europe", saved)
        self.assertNotIn("3f2a9c1e", saved)
        self.assertIn("<id>", saved)



class OpenedListTests(RunnerTestCase):
    """A multi-select list opened by the label before it (1.3.9's 'Allowed locations' above the
    combo box 'Location'; #342): the item's later labels are options of that list, set to the
    state the guide gives them, and the list is closed when the item ends."""

    ITEM = {"kind": "action", "labels": ["Allowed locations", "Sweden Central", "North Europe"],
            "checked": [1, 2], "line": 5}

    def setUp(self) -> None:
        super().setUp()
        (self.tmp / "guide.md").write_text("# Lab\n", encoding="utf-8")

    def parameters(self, ticked=(), late=()):
        """Run B's Parameters tab: the text 'Allowed locations' before the combo box 'Location'; once
        clicked, it opens a list with a Filter box and check box options under a heading (Europe).
        Options in `late` appear only after the filter box is typed into. Returns (screen, combo box,
        options by name, filter box)."""
        screen, combo = Screen(), ScreenNode(attrs={"role": "combobox", "aria-controls": "locations"}, tag="div")
        options = {name: ScreenNode(attrs={"role": "option", "aria-selected": "true" if name in ticked else "false"},
                                    selects_on_click=True)
                   for name in ("North Europe", "Sweden Central", "West Europe")}
        children = Screen(("text", "Europe", ScreenNode(interactive=False)))
        for name, option in options.items():
            if name not in late:
                children.add(("option", name, option))

        def type_in_filter() -> None:
            for name in late:
                if all(entry[2] is not options[name] for entry in children.entries):
                    children.add(("option", name, options[name]))

        filter_box = ScreenNode(tag="input", on_fill=type_in_filter)
        children.add(("searchbox", "Filter", filter_box))
        popup = ScreenNode(attrs={"id": "locations"}, children=children)
        shown = ("listbox", "Location", popup)
        combo.on_click = lambda: shown in screen.entries or screen.add(shown)

        def press(key, timeout=None) -> None:
            combo.pressed.append(key)
            if key == "Escape" and shown in screen.entries:
                screen.entries.remove(shown)

        combo.press = press
        screen.add(("text", "Allowed locations", ScreenNode(interactive=False, next_control=combo)),
                   ("combobox", "Location", combo))
        return screen, combo, options, filter_box

    def perform(self, screen: Screen, items: list[dict] | None = None):
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers())
        step = {"id": "9.9.1", "title": "One", "expected": None, "images": [], "items": items or [self.ITEM]}
        with mock.patch.object(run, "all_frames", lambda page: [screen]), \
                mock.patch.object(run.time, "monotonic", lambda: r.page.now), \
                mock.patch.object(run, "candidates_on_screen", return_value=[]):
            done = self.quietly(lambda: r.run_step(step))
        return r, done

    @staticmethod
    def outcomes(r: run.Runner) -> list[tuple[str, str]]:
        return [(x["label"], x["outcome"]) for x in r.records if x["kind"] == "action"]

    def test_allowed_locations_opens_the_location_combobox_and_ticks_both_regions(self) -> None:
        screen, combo, options, _ = self.parameters()
        r, done = self.perform(screen)
        self.assertTrue(done)
        self.assertEqual(self.outcomes(r), [("Allowed locations", "match"), ("Sweden Central", "match"),
                                            ("North Europe", "match")])
        self.assertEqual((combo.clicked, options["Sweden Central"].clicked, options["North Europe"].clicked,
                          options["West Europe"].clicked), (1, 1, 1, 0))
        self.assertEqual([options[n].attrs["aria-selected"] for n in ("Sweden Central", "North Europe", "West Europe")],
                         ["true", "true", "false"])
        self.assertEqual((r.ask.prompts, self.recording["steps"]["9.9.1"]["labels"]), ([], {}))

    def test_north_europe_already_ticked_stays_ticked(self) -> None:
        # Run B clicked North Europe, which was ticked already, and unticked it.
        screen, _, options, _ = self.parameters(ticked=("North Europe",))
        r, done = self.perform(screen)
        self.assertTrue(done)
        self.assertEqual((options["North Europe"].clicked, options["North Europe"].attrs["aria-selected"]), (0, "true"))
        self.assertEqual((options["Sweden Central"].clicked, options["Sweden Central"].attrs["aria-selected"]), (1, "true"))
        self.assertEqual([x["observed"] for x in r.records if x["label"] == "North Europe"], ["already set"])

    def test_sweden_central_appears_after_typing_in_the_filter_box(self) -> None:
        screen, _, options, filter_box = self.parameters(late=("Sweden Central",))
        r, done = self.perform(screen)
        self.assertTrue(done)
        self.assertEqual((filter_box.filled, options["Sweden Central"].clicked, options["North Europe"].clicked),
                         (["Sweden Central"], 1, 1))

    def test_the_list_is_closed_after_the_item(self) -> None:
        screen, combo, _, _ = self.parameters()
        self.perform(screen, [dict(self.ITEM, labels=["Allowed locations", "Sweden Central"], checked=[1])])
        self.assertEqual((combo.pressed, [e for e in screen.entries if e[0] == "listbox"]), (["Escape"], []))

    def test_a_list_the_last_label_opened_stays_open_for_the_next_item(self) -> None:
        screen, combo, _, _ = self.parameters()
        self.perform(screen, [{"kind": "action", "labels": ["Allowed locations"], "line": 5}])
        self.assertEqual((combo.clicked, combo.pressed), (1, []))

    def test_a_list_that_closed_itself_is_not_closed_again(self) -> None:
        screen, combo, options, _ = self.parameters()
        options["Sweden Central"].on_click = lambda: screen.entries.remove(
            next(e for e in screen.entries if e[0] == "listbox"))
        self.perform(screen, [dict(self.ITEM, labels=["Allowed locations", "Sweden Central"], checked=[1])])
        self.assertEqual(combo.pressed, [])

    def test_a_label_not_in_the_list_is_looked_for_on_screen(self) -> None:
        screen, combo, options, _ = self.parameters()
        save = ScreenNode()
        screen.add(("button", "Save", save))
        item = {"kind": "action", "labels": ["Allowed locations", "Sweden Central", "Save"], "checked": [1], "line": 5}
        r, done = self.perform(screen, [item])
        self.assertTrue(done)
        self.assertEqual((save.clicked, options["Sweden Central"].clicked), (1, 1))

    def test_the_list_is_forgotten_with_the_item(self) -> None:
        screen, combo, options, _ = self.parameters()
        other = ScreenNode()
        screen.add(("button", "North Europe", other))
        first = {"kind": "action", "labels": ["Allowed locations", "Sweden Central"], "checked": [1], "line": 5}
        second = {"kind": "action", "labels": ["North Europe"], "line": 6}
        r, done = self.perform(screen, [first, second])
        self.assertTrue(done)
        self.assertEqual((options["North Europe"].clicked, other.clicked), (0, 1))


if __name__ == "__main__":
    unittest.main()
