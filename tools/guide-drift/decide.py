"""The one boundary every 'label not found' decision passes through (issue #189).

decide(step, item, label, candidates, deciders) asks each decider in turn and returns the first
answer that is not None. `item` is the parsed guide item the label came from (kind, line, and
value for a field); deciders may use it for context. Two deciders ship:

  ReplayDecider  answers from the committed recording. A recorded 'use' whose element is still
                 on screen, and is the only one with that role and name, is replayed; a recorded
                 'ignore' is replayed; a recorded 'gone' is reported as blocking drift without
                 asking. Anything else falls through.
  HumanDecider   prints the step text, the missing label and the numbered candidates, and
                 reads one answer from the keyboard. Answers every time, 'unknown' on end of
                 input. 'w <number>' uses an element as a workaround (#211): the guide's element
                 is not on screen and the person reached the same place another way (a resumed
                 browser on another blade, a link whose name holds a count). It is misleading
                 drift, as a renamed element is, but proposes no guide edit and is never
                 recorded: replayed, it would be taken for the guide's element under a new name,
                 so the next run asks again. For a field it shows the value the runner will type,
                 as `value_to_type` gives it (#210): run.py passes recording.prompt_value, the
                 value after the recording's placeholders and valueOverrides, with where it came
                 from and the environment variables it was read from; run.py scrubs every line,
                 so a secret shows as '[secret]'. Without `value_to_type`, the guide's value.

A name that is the guide's label plus one of the Portal's decorations (DECORATIONS, #244: 'Select
row X' for a list row's check box, 'X information *' for a field with an info icon that must be
filled in) on a role it decorates is the guide's element, not drift: run.py finds such an element
without asking, and when a decider is asked all the same, a pick of one by number or with 'c' is
plain use, recorded and replayed as such (a recording made before #244 that holds it as cosmetic
drift replays as use too). 'w' still makes it a workaround. The same words on another role are
another element (a button 'X information *', a link 'Select row X') and stay drift.

A model-based decider is a third implementation of the same signature (the Decider protocol);
it is out of scope here and tracked in issue #190. Every decision the runner acts on, except a
workaround, is written back to the recording by run.py, with the rejected candidates, so
supervised runs build the reference set. A person's pick whose name the recording cannot keep (an
id, an address outside the tenant or a secret: scrub would mask it, and replay would never find the
masked name) is made a workaround by run.py (Decision.as_workaround, #315): acted on in this run,
never recorded, and asked about again on the next.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from difflib import SequenceMatcher
from typing import Callable, Protocol

NEAREST = 10   # how many candidates the human sees first, most similar to the label


@dataclass(frozen=True)
class Decoration:
    """Words the Portal adds to an element's accessible name around the label the screen shows
    (#244). `roles` are the roles it is found on (run.find_decorated, decoration_of with a role):
    the decoration names that element, while the same words on another role name something else.
    `fields`: whether a field's lookup takes it too; a list row's check box is selected by an
    action, never filled in as a field."""
    prefix: str
    suffix: str
    roles: tuple[str, ...]
    what: str        # for the reason a guide edit is not proposed (run.Runner.not_proposed)
    fields: bool = True

    def of(self, label: str) -> str:
        return f"{self.prefix}{label}{self.suffix}"


# The fields a label with an info icon or a required marker names (run.FIELD_ROLES).
DECORATED_FIELDS = ("textbox", "combobox", "checkbox", "radio")
# The one list of decorations (#244): an accessible name that is the guide's label plus exactly one
# of these, on a role it decorates, is the guide's element, not drift, and never a guide edit. Only
# decorations a run has seen are listed: a field label with an info icon that must be filled in
# carries both suffixes, in this order ('Email information *', lab 1.1), so the pair is one entry;
# the info icon's suffix alone is not listed (run.py's header, known gap).
DECORATIONS = (
    Decoration("Select row ", "", ("checkbox",), "a list row's check box", fields=False),
    Decoration("", " *", DECORATED_FIELDS, "a required field's marker"),
    Decoration("", " information *", DECORATED_FIELDS, "a field label's info icon and required marker"),
)


def decoration_of(name: str, label: str, role: str | None = None) -> Decoration | None:
    """The decoration `name` adds to `label` (DECORATIONS), or None when `name` is not exactly
    the non-empty `label` plus one of them: the label itself, another case, another label or
    other words around it are no decoration. With a `role`, only a decoration found on that role
    counts (the deciders know the element's role; a proposed edit's text does not)."""
    if not label:
        return None
    return next((d for d in DECORATIONS if name == d.of(label) and (role is None or role in d.roles)), None)


@dataclass
class Candidate:
    role: str
    name: str
    count: int = 1                # how many elements on screen share this role and name
    in_entry: bool = False        # one of them sits in a list's entry (run.py, aria_lines; #317)
    names_entry: bool = False     # its name holds a list entry's name (aria_lines; #317)

    def __str__(self) -> str:
        suffix = f" (x{self.count})" if self.count > 1 else ""
        return f'{self.role} "{self.name}"{suffix}'


@dataclass
class Decision:
    kind: str                     # "use" | "drift" | "ignore" | "unknown"
    name: str | None = None       # use: accessible name to act on; drift: observed text
    role: str | None = None
    severity: str | None = None   # drift only: "blocking" | "misleading" | "cosmetic"
    reason: str | None = None     # unknown only
    decided_by: str = "human"     # "exact" | "replay" | "human" | "none"
    workaround: bool = False      # drift only: used, but not as the guide's element ('w', #211)

    def as_workaround(self) -> Decision:
        """This pick of an element as a workaround, as 'w <number>' makes it (#211): drift of the
        severity the person gave, misleading for a plain use, acted on in this run and never
        recorded. run.py makes a pick one when the recording cannot keep its name (#315)."""
        return replace(self, kind="drift", severity=self.severity or "misleading", workaround=True)

    def to_recording(self, rejected: list[str], at: str) -> dict | None:
        """The shape stored under recording["steps"][id]["labels"][label]; None for unknown,
        which is never recorded because it would replay as 'still unknown' forever, and for a
        workaround, which would replay as the guide's element renamed (#211)."""
        if self.kind == "unknown" or self.workaround:
            return None
        if self.kind == "ignore":
            decision = "ignore"
        elif self.kind == "drift" and self.severity == "blocking":
            decision = "gone"
        else:
            decision = "use"      # use, or a misleading/cosmetic drift that names its element
        return {"decision": decision, "role": self.role, "name": self.name,
                "severity": self.severity, "rejected": rejected,
                "decidedBy": self.decided_by, "at": at}


class Decider(Protocol):
    def __call__(self, step: dict, item: dict, label: str,
                 candidates: list[Candidate]) -> Decision | None: ...


class ReplayDecider:
    def __init__(self, recording: dict) -> None:
        self.recording = recording

    def __call__(self, step: dict, item: dict, label: str,
                 candidates: list[Candidate]) -> Decision | None:
        entry = self.recording.get("steps", {}).get(step["id"], {}).get("labels", {}).get(label)
        if not entry:
            return None
        if entry["decision"] == "ignore":
            return Decision(kind="ignore", decided_by="replay")
        if entry["decision"] == "gone":
            return Decision(kind="drift", severity="blocking", name=None, decided_by="replay")
        if entry["decision"] == "use":
            matches = [c for c in candidates
                       if c.name == entry["name"] and (not entry.get("role") or c.role == entry["role"])]
            if len(matches) != 1 or matches[0].count > 1:
                # Absent: the Portal moved again. Ambiguous: the runner would refuse the click.
                return None
            candidate = matches[0]
            # A decorated name is the guide's element (#244), whatever a recording before it says.
            renamed = candidate.name != label and decoration_of(candidate.name, label, candidate.role) is None
            severity = (entry.get("severity") or "misleading") if renamed else None
            return Decision(kind="drift" if severity else "use", name=candidate.name,
                            role=candidate.role, severity=severity, decided_by="replay")
        return None


class HumanDecider:
    PROMPT = (
        "  [number]   use that element: the guide's, renamed (misleading drift)   g  gone (blocking drift)\n"
        "  c [number] use it, but the difference is cosmetic                      i  ignore (not a UI element)\n"
        "  w [number] use it as a workaround, not as the guide's (no guide edit)  u <why>  unknown, cannot tell\n> "
    )

    def __init__(self, ask: Callable[[str], str] = input, say: Callable[[str], None] = print,
                 value_to_type: Callable[[dict, dict], str] | None = None) -> None:
        self.ask = ask
        self.say = say
        # What a field's 'value to type:' shows, given the step and the item (#210); without it,
        # the guide's value.
        self.value_to_type = value_to_type

    def __call__(self, step: dict, item: dict, label: str,
                 candidates: list[Candidate]) -> Decision:
        self._show(step, item, label, candidates)
        while True:
            try:
                answer = self.ask(self.PROMPT).strip()
            except EOFError:
                return Decision(kind="unknown", reason="no answer (input closed)")
            parts = answer.split(None, 1)
            word = parts[0] if parts else ""
            if answer.isdecimal() and 1 <= int(answer) <= len(candidates):
                return self._pick(candidates[int(answer) - 1], label, cosmetic=False)
            if answer == "g":
                return Decision(kind="drift", severity="blocking")
            if (word in ("c", "w") and len(parts) == 2 and parts[1].isdecimal()
                    and 1 <= int(parts[1]) <= len(candidates)):
                return self._pick(candidates[int(parts[1]) - 1], label, cosmetic=word == "c",
                                  workaround=word == "w")
            if answer == "i":
                return Decision(kind="ignore")
            if word == "u":
                return Decision(kind="unknown",
                                reason=parts[1].strip() if len(parts) == 2 else "operator could not tell")
            self.say("Answer with a number, g, c <number>, w <number>, i or u <why>.")

    @staticmethod
    def _pick(chosen: Candidate, label: str, cosmetic: bool, workaround: bool = False) -> Decision:
        # Nothing differs, or only a decoration the Portal adds to the label (#244): nothing to report.
        if chosen.name == label or (decoration_of(chosen.name, label, chosen.role) is not None and not workaround):
            return Decision(kind="use", name=chosen.name, role=chosen.role)
        return Decision(kind="drift", name=chosen.name, role=chosen.role,
                        severity="cosmetic" if cosmetic else "misleading", workaround=workaround)

    def _show(self, step: dict, item: dict, label: str, candidates: list[Candidate]) -> None:
        self.say(f'\nStep {step["id"]}: {step["title"]}')
        self.say(f'Guide line {item.get("line")} ({item.get("kind")}): **{label}**')
        if item.get("kind") == "field":
            shown = self.value_to_type(step, item) if self.value_to_type else item.get("value")
            self.say(f"  value to type: {shown}")
        self.say("Not found. Visible elements:")
        if not candidates:
            self.say("  (none)")
            return
        # One global numbering by original position, so a number always means the same element;
        # only the order of listing changes: the nearest names first, then the rest.
        wanted = label.casefold()
        ranked = sorted(range(len(candidates)), key=lambda i: -SequenceMatcher(
            None, wanted, candidates[i].name.casefold()).ratio())
        for index in ranked[:NEAREST] + sorted(ranked[NEAREST:]):
            self.say(f"  {index + 1:3d}. {candidates[index]}")


def decide(step: dict, item: dict, label: str, candidates: list[Candidate],
           deciders: list[Decider]) -> Decision:
    for decider in deciders:
        decision = decider(step, item, label, candidates)
        if decision is not None:
            return decision
    return Decision(kind="unknown", reason="no decider answered", decided_by="none")
