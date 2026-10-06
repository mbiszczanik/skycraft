"""Unit tests for run.py's bookkeeping: state, resume, failure handling, recording of decisions
(issue #189), and how it finds what a guide names (search, '+' labels, plain text, collapsed
menu groups). No browser: the page is a small fake (Screen stands in for a frame), and run_step
is scripted where only the order of steps matters.

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

    def test_skip_the_rest_keeps_the_failed_step_out_of_completed(self) -> None:
        r = self.runner(answers=["s"], failing={"9.9.2"})
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

    def __init__(self, closed: bool = False) -> None:
        self.closed = closed
        self.main_frame = Screen()       # an empty screen unless a test patches run.all_frames
        self.frames = [self.main_frame]
        self.now = 0.0                   # seconds; only waits move it (FindOnScreenTests' clock)

    def is_closed(self) -> bool:
        return self.closed

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

    def act(self, answers, element, label="+ New group", exact=None):
        r = run.Runner(FakePage(), STEPS, self.recording, self.args(), ask=Answers(*answers))
        candidates = [run.Candidate("button", "New group"), run.Candidate("link", "Groups"),
                      run.Candidate("button", "Delete group"), run.Candidate("link", "Contoso Ltd"),
                      run.Candidate("menuitem", "Bulk delete")]
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
    label: `label_for`, the input it belongs to; `has_link`, whether it holds a link."""

    def __init__(self, interactive: bool = True, on_click=None, on_fill=None, attrs=None, children=None,
                 rect=None, section=("", "", ""), unreadable: int = 0, tree: str = "", tag: str = "div",
                 text: str = "", fill_fail: Exception | None = None, shown: bool = True,
                 read_only: bool = False, in_header: bool = False, controls_role: str = "",
                 editable: bool = False, uninspectable: bool = False, checked: bool = False,
                 check_error: Exception | None = None, label: "ScreenNode | None" = None,
                 label_for: "ScreenNode | None" = None, has_link: bool = False) -> None:
        super().__init__()
        self.label_for = label_for
        self.has_link = has_link
        self.more_labels: list = []
        self.flips_after: int | None = None
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
        if self.on_click:
            self.on_click()

    def fill(self, value, timeout=None) -> None:
        if self.fill_fail:
            raise self.fill_fail
        self.filled.append(value)
        self.text = value
        if self.on_fill:
            self.on_fill()


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

    def test_a_closed_window_is_not_a_missing_search_box(self) -> None:
        with self.assertRaises(run.PageClosed):
            self.act(Screen(), self.SEARCH, self.ENTRA, page=FakePage(closed=True))

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
        self.assertIn("holds 2 text box(es) and 0 combo box(es)", record["observed"])

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
        expand = ScreenNode(on_click=lambda: screen.add(("link", "Users", users)))
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
        expand = ScreenNode(on_click=lambda: screen.add(("link", "Users", users)))
        screen.add(("button", "Expand all headers", expand))
        record, r = self.act(screen, self.NAVIGATION, "Users")
        self.assertEqual((record["outcome"], users.clicked, expand.clicked, r.ask.prompts), ("match", 1, 1, []))
        found_at = r.page.now - run.SETTLE_MS / 1000                       # clicking Users waits SETTLE_MS
        self.assertLess(found_at, run.SETTLE_MS / 1000 + 0.6)            # not the whole FIND_TIMEOUT_MS

    def test_a_label_that_never_appears_expands_once_and_asks_at_the_deadline(self) -> None:
        expand = ScreenNode()
        screen = Screen(("button", "Expand all headers", expand))
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

    def test_a_search_without_the_search_box_is_unknown(self) -> None:
        record, r = self.act(Screen(), self.SEARCH, "Microsoft Entra ID")
        self.assertEqual(record["outcome"], "unknown")
        self.assertIn("search box is not on screen", record["observed"])
        self.assertEqual(r.ask.prompts, [])


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
