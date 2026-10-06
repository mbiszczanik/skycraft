#!/usr/bin/env python3
"""The one boundary every 'label not found' decision passes through (issue #189).

decide(step, label, candidates, deciders) asks each decider in turn and returns the first
answer that is not None. Two deciders ship:

  ReplayDecider  answers from the committed recording. A recorded 'use' whose element is still
                 on screen is replayed; a recorded 'ignore' is replayed; a recorded 'gone' is
                 reported as blocking drift without asking. Anything else falls through.
  HumanDecider   prints the step text, the missing label and the numbered candidates, and
                 reads one answer from the keyboard. Always answers.

A model-based decider is a third implementation of the same signature; it is out of scope here
and tracked in issue #190. Every decision the runner acts on is written back to the recording by
run.py, with the rejected candidates, so supervised runs build the reference set.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict


@dataclass
class Candidate:
    role: str
    name: str

    def __str__(self) -> str:
        return f'{self.role} "{self.name}"'


@dataclass
class Decision:
    kind: str                     # "use" | "drift" | "ignore" | "unknown"
    name: str | None = None       # use: accessible name to act on; drift: observed text
    role: str | None = None
    severity: str | None = None   # drift only: "blocking" | "misleading" | "cosmetic"
    reason: str | None = None     # unknown only
    decided_by: str = "human"     # "exact" | "replay" | "human"

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


class ReplayDecider:
    def __init__(self, recording: dict) -> None:
        self.recording = recording

    def __call__(self, step: dict, label: str, candidates: list[Candidate]) -> Decision | None:
        entry = self.recording.get("steps", {}).get(step["id"], {}).get("labels", {}).get(label)
        if not entry:
            return None
        if entry["decision"] == "ignore":
            return Decision(kind="ignore", decided_by="replay")
        if entry["decision"] == "gone":
            return Decision(kind="drift", severity="blocking", name=None, decided_by="replay")
        if entry["decision"] == "use":
            for candidate in candidates:
                if candidate.name == entry["name"] and (not entry.get("role") or candidate.role == entry["role"]):
                    severity = (entry.get("severity") or "misleading") if candidate.name != label else None
                    kind = "drift" if severity else "use"
                    return Decision(kind=kind, name=candidate.name, role=candidate.role,
                                    severity=severity, decided_by="replay")
        return None   # recorded element is not on screen: the Portal moved again, ask


class HumanDecider:
    PROMPT = (
        "  [number]   use that element (renamed = misleading drift)   g  gone (blocking drift)\n"
        "  c [number] use it, but the difference is cosmetic          i  ignore (not a UI element)\n"
        "  u <why>    unknown, cannot tell\n> "
    )

    def __init__(self, ask=input, say=print) -> None:
        self.ask = ask
        self.say = say

    def __call__(self, step: dict, label: str, candidates: list[Candidate]) -> Decision:
        self.say(f'\nStep {step["id"]}: {step["title"]}')
        self.say(f'Guide says: **{label}**   (line {step.get("line")})')
        self.say("Not found. Visible elements:")
        for index, candidate in enumerate(candidates, start=1):
            self.say(f"  {index:3d}. {candidate}")
        while True:
            answer = self.ask(self.PROMPT).strip()
            if answer.isdigit() and 1 <= int(answer) <= len(candidates):
                chosen = candidates[int(answer) - 1]
                severity = "misleading" if chosen.name != label else None
                return Decision(kind="drift" if severity else "use", name=chosen.name,
                                role=chosen.role, severity=severity)
            if answer == "g":
                return Decision(kind="drift", severity="blocking")
            if answer.startswith("c ") and answer[2:].strip().isdigit() and 1 <= int(answer[2:]) <= len(candidates):
                chosen = candidates[int(answer[2:]) - 1]
                return Decision(kind="drift", name=chosen.name, role=chosen.role, severity="cosmetic")
            if answer == "i":
                return Decision(kind="ignore")
            if answer.startswith("u"):
                return Decision(kind="unknown", reason=answer[1:].strip() or "operator could not tell")
            self.say("Answer with a number, g, c <number>, i or u <why>.")


def decide(step: dict, label: str, candidates: list[Candidate], deciders) -> Decision:
    for decider in deciders:
        decision = decider(step, label, candidates)
        if decision is not None:
            return decision
    return Decision(kind="unknown", reason="no decider answered", decided_by="replay")
