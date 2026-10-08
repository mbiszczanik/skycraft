"""Unit tests for decide.py, the decision boundary of the guide drift tool (issue #189).

Standard library unittest only; tests/Guide-Drift-Python.Tests.ps1 runs this suite in CI.
Run by hand from the repository root:

    python -B -m unittest discover -s tools/guide-drift/tests -v
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from decide import Candidate, Decision, HumanDecider, ReplayDecider, decide  # noqa: E402

STEP = {"id": "1.1.6", "title": "Create First Group"}
ITEM = {"kind": "action", "line": 155, "labels": ["+ New group"]}
FIELD = {"kind": "field", "label": "Group name", "value": "SkyCraft-Admins", "line": 161}
AT = "2026-10-07T10:00:00Z"
LABEL = "+ New group"
CANDIDATES = [
    Candidate("link", "Groups"),
    Candidate("button", "New group"),
    Candidate("button", LABEL),
]


def human(*answers, say=None):
    """A HumanDecider fed from a fixed list of answers; prompts and output are collected."""
    remaining = iter(answers)
    prompts: list[str] = []
    said: list[str] = [] if say is None else say

    def ask(prompt):
        prompts.append(prompt)
        try:
            return next(remaining)
        except StopIteration:
            raise EOFError from None

    decider = HumanDecider(ask=ask, say=said.append)
    decider.prompts, decider.said = prompts, said
    return decider


def recording_for(decision, label=LABEL):
    entry = decision.to_recording([], AT)
    return {"steps": {STEP["id"]: {"labels": {label: entry}}}}


class RoundTrip(unittest.TestCase):
    """An answer, recorded and replayed on the same screen, decides the same thing."""

    def roundtrip(self, answer, label=LABEL, candidates=CANDIDATES):
        given = human(answer)(STEP, ITEM, label, candidates)
        replayed = ReplayDecider(recording_for(given, label))(STEP, ITEM, label, candidates)
        return given, replayed

    def assertSame(self, given, replayed):
        self.assertIsNotNone(replayed)
        self.assertEqual((given.kind, given.severity, given.role, given.name),
                         (replayed.kind, replayed.severity, replayed.role, replayed.name))
        self.assertEqual(replayed.decided_by, "replay")

    def test_number_renamed_is_misleading_drift(self):
        given, replayed = self.roundtrip("2")
        self.assertEqual((given.kind, given.severity, given.name), ("drift", "misleading", "New group"))
        self.assertSame(given, replayed)

    def test_number_same_name_is_use(self):
        given, replayed = self.roundtrip("3")
        self.assertEqual((given.kind, given.severity, given.name), ("use", None, LABEL))
        self.assertSame(given, replayed)

    def test_c_number_renamed_is_cosmetic_drift(self):
        given, replayed = self.roundtrip("c 2")
        self.assertEqual((given.kind, given.severity), ("drift", "cosmetic"))
        self.assertSame(given, replayed)

    def test_c_number_same_name_is_plain_use(self):
        given, replayed = self.roundtrip("c 3")
        self.assertEqual((given.kind, given.severity), ("use", None))
        self.assertSame(given, replayed)

    def test_gone_is_blocking_and_replays_without_candidates(self):
        given, replayed = self.roundtrip("g")
        self.assertEqual((given.kind, given.severity), ("drift", "blocking"))
        self.assertSame(given, replayed)
        self.assertEqual(recording_for(given)["steps"][STEP["id"]]["labels"][LABEL]["decision"], "gone")
        self.assertIsNotNone(ReplayDecider(recording_for(given))(STEP, ITEM, LABEL, []))

    def test_ignore_replays(self):
        given, replayed = self.roundtrip("i")
        self.assertEqual(given.kind, "ignore")
        self.assertSame(given, replayed)

    def test_unknown_is_never_recorded(self):
        given = human("u not sure")(STEP, ITEM, LABEL, CANDIDATES)
        self.assertEqual((given.kind, given.reason), ("unknown", "not sure"))
        self.assertIsNone(given.to_recording([], AT))
        self.assertIsNone(ReplayDecider({"steps": {}})(STEP, ITEM, LABEL, CANDIDATES))

    def test_recording_carries_rejected_decider_and_time(self):
        entry = Decision("use", name="Groups", role="link").to_recording(["Groups (preview)"], AT)
        self.assertEqual(entry, {"decision": "use", "role": "link", "name": "Groups", "severity": None,
                                 "rejected": ["Groups (preview)"], "decidedBy": "human", "at": AT})


class Replay(unittest.TestCase):
    def replay(self, entry, candidates=CANDIDATES, step=STEP, label=LABEL):
        recording = {"steps": {"1.1.6": {"labels": {LABEL: entry}}}}
        return ReplayDecider(recording)(step, ITEM, label, candidates)

    USE = {"decision": "use", "role": "button", "name": "New group", "severity": "misleading"}

    def test_recorded_element_absent_asks(self):
        self.assertIsNone(self.replay(self.USE, [Candidate("link", "Groups")]))

    def test_role_differs_asks(self):
        self.assertIsNone(self.replay(self.USE, [Candidate("link", "New group")]))

    def test_step_missing_asks(self):
        self.assertIsNone(self.replay(self.USE, step={"id": "9.9.9", "title": "x"}))

    def test_label_missing_asks(self):
        self.assertIsNone(self.replay(self.USE, label="Something else"))

    def test_ambiguous_candidate_asks(self):
        self.assertIsNone(self.replay(self.USE, [Candidate("button", "New group", count=2)]))

    def test_same_name_twice_in_the_list_asks(self):
        twice = [Candidate("button", "New group"), Candidate("button", "New group")]
        self.assertIsNone(self.replay(self.USE, twice))

    def test_recorded_severity_is_kept_and_defaults_to_misleading(self):
        cosmetic = dict(self.USE, severity="cosmetic")
        self.assertEqual(self.replay(cosmetic).severity, "cosmetic")
        self.assertEqual(self.replay(dict(self.USE, severity=None)).severity, "misleading")

    def test_empty_recording_asks(self):
        self.assertIsNone(ReplayDecider({})(STEP, ITEM, LABEL, CANDIDATES))


class Asking(unittest.TestCase):
    def test_invalid_answers_reprompt_then_accept_a_valid_one(self):
        for bad in ("0", "999", "c", "c 0", "x", "use 3", "²", "c 999", "cc 1", "ignore", "go", ""):
            with self.subTest(bad=bad):
                decider = human(bad, "2")
                decision = decider(STEP, ITEM, LABEL, CANDIDATES)
                self.assertEqual(decision.name, "New group")
                self.assertEqual(len(decider.prompts), 2)
                self.assertTrue(any(line.startswith("Answer with") for line in decider.said))

    def test_unknown_without_a_reason_gets_a_default(self):
        self.assertEqual(human("u")(STEP, ITEM, LABEL, CANDIDATES).reason, "operator could not tell")

    def test_answers_are_trimmed(self):
        self.assertEqual(human("  g  ")(STEP, ITEM, LABEL, CANDIDATES).severity, "blocking")

    def test_no_candidates_rejects_numbers_and_accepts_gone(self):
        decider = human("1", "c 1", "g")
        decision = decider(STEP, ITEM, LABEL, [])
        self.assertEqual((decision.kind, decision.severity), ("drift", "blocking"))
        self.assertEqual(len(decider.prompts), 3)
        self.assertIn("  (none)", decider.said)

    def test_end_of_input_is_unknown(self):
        decision = human()(STEP, ITEM, LABEL, CANDIDATES)
        self.assertEqual(decision.kind, "unknown")
        self.assertEqual(decision.reason, "no answer (input closed)")

    def test_end_of_input_after_a_bad_answer_is_unknown(self):
        self.assertEqual(human("x")(STEP, ITEM, LABEL, CANDIDATES).kind, "unknown")

    def test_keyboard_interrupt_is_not_swallowed(self):
        def ask(_):
            raise KeyboardInterrupt
        with self.assertRaises(KeyboardInterrupt):
            HumanDecider(ask=ask, say=lambda _: None)(STEP, ITEM, LABEL, CANDIDATES)


class Listing(unittest.TestCase):
    def test_prompt_names_step_line_kind_label_and_field_value(self):
        decider = human("g")
        decider(STEP, FIELD, "Group name", CANDIDATES)
        text = "\n".join(decider.said)
        self.assertIn("Step 1.1.6: Create First Group", text)
        self.assertIn("Guide line 161 (field): **Group name**", text)
        self.assertIn("SkyCraft-Admins", text)

    def test_value_is_not_shown_for_an_action(self):
        decider = human("g")
        decider(STEP, ITEM, LABEL, CANDIDATES)
        self.assertNotIn("value to type", "\n".join(decider.said))

    def test_ambiguous_candidate_shows_its_count(self):
        self.assertEqual(str(Candidate("button", "New group", count=2)), 'button "New group" (x2)')
        self.assertEqual(str(Candidate("button", "New group")), 'button "New group"')

    def test_nearest_ten_come_first_and_numbers_stay_global(self):
        # 25 elements; the one that matches the label is last in screen order.
        names = [f"Zzz{i:02d}" for i in range(24)] + ["new group"]
        candidates = [Candidate("button", n) for n in names]
        decider = human("25")
        decision = decider(STEP, ITEM, "New group", candidates)
        listed = [line for line in decider.said if line.startswith("  ") and ". " in line]
        self.assertEqual(len(listed), 25)
        self.assertTrue(listed[0].strip().startswith("25. "), listed[0])   # nearest first, still number 25
        self.assertEqual(decision.name, "new group")                  # 25 means that element
        numbers = [int(line.split(".")[0]) for line in listed]
        self.assertEqual(sorted(numbers), list(range(1, 26)))
        self.assertEqual(numbers[10:], sorted(numbers[10:]))          # the rest in screen order
        for line in listed:
            number = int(line.split(".")[0])
            self.assertIn(f'"{names[number - 1]}"', line)             # number matches the element

    def test_nearest_is_case_insensitive(self):
        candidates = [Candidate("link", "Other"), Candidate("button", "NEW GROUP")]
        decider = human("2")
        decider(STEP, ITEM, "new group", candidates)
        listed = [line for line in decider.said if line.startswith("  ") and ". " in line]
        self.assertTrue(listed[0].strip().startswith("2. "), listed[0])


class Chain(unittest.TestCase):
    def test_returns_first_answer_and_does_not_call_later_deciders(self):
        calls = []

        def make(name, result):
            def decider(step, item, label, candidates):
                calls.append(name)
                return result
            return decider

        answer = Decision("ignore", decided_by="replay")
        got = decide(STEP, ITEM, LABEL, CANDIDATES,
                     [make("a", None), make("b", answer), make("c", Decision("use"))])
        self.assertIs(got, answer)
        self.assertEqual(calls, ["a", "b"])

    def test_replay_miss_falls_through_to_the_person(self):
        got = decide(STEP, ITEM, LABEL, CANDIDATES, [ReplayDecider({}), human("i")])
        self.assertEqual((got.kind, got.decided_by), ("ignore", "human"))

    def test_nobody_answering_is_unknown_decided_by_none(self):
        got = decide(STEP, ITEM, LABEL, CANDIDATES, [])
        self.assertEqual((got.kind, got.decided_by), ("unknown", "none"))


if __name__ == "__main__":
    unittest.main()
