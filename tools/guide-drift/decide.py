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
                 input.

A model-based decider is a third implementation of the same signature (the Decider protocol);
it is out of scope here and tracked in issue #190. Every decision the runner acts on is written
back to the recording by run.py, with the rejected candidates, so supervised runs build the
reference set.
"""
from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Callable, Protocol

NEAREST = 10   # how many candidates the human sees first, most similar to the label


@dataclass
class Candidate:
    role: str
    name: str
    count: int = 1                # how many elements on screen share this role and name

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

    def to_recording(self, rejected: list[str], at: str) -> dict | None:
        """The shape stored under recording["steps"][id]["labels"][label]; None for unknown,
        which is never recorded because it would replay as 'still unknown' forever."""
        if self.kind == "unknown":
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
            severity = (entry.get("severity") or "misleading") if candidate.name != label else None
            return Decision(kind="drift" if severity else "use", name=candidate.name,
                            role=candidate.role, severity=severity, decided_by="replay")
        return None


class HumanDecider:
    PROMPT = (
        "  [number]   use that element (renamed = misleading drift)   g  gone (blocking drift)\n"
        "  c [number] use it, but the difference is cosmetic          i  ignore (not a UI element)\n"
        "  u <why>    unknown, cannot tell\n> "
    )

    def __init__(self, ask: Callable[[str], str] = input, say: Callable[[str], None] = print) -> None:
        self.ask = ask
        self.say = say

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
            if (word == "c" and len(parts) == 2 and parts[1].isdecimal()
                    and 1 <= int(parts[1]) <= len(candidates)):
                return self._pick(candidates[int(parts[1]) - 1], label, cosmetic=True)
            if answer == "i":
                return Decision(kind="ignore")
            if word == "u":
                return Decision(kind="unknown",
                                reason=parts[1].strip() if len(parts) == 2 else "operator could not tell")
            self.say("Answer with a number, g, c <number>, i or u <why>.")

    @staticmethod
    def _pick(chosen: Candidate, label: str, cosmetic: bool) -> Decision:
        if chosen.name == label:      # nothing differs, so there is nothing to report
            return Decision(kind="use", name=chosen.name, role=chosen.role)
        return Decision(kind="drift", name=chosen.name, role=chosen.role,
                        severity="cosmetic" if cosmetic else "misleading")

    def _show(self, step: dict, item: dict, label: str, candidates: list[Candidate]) -> None:
        self.say(f'\nStep {step["id"]}: {step["title"]}')
        self.say(f'Guide line {item.get("line")} ({item.get("kind")}): **{label}**')
        if item.get("kind") == "field":
            self.say(f'  value to type: {item.get("value")}')
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
