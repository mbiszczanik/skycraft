"""Scores a decider on the reference set the recordings hold (issue #190). Offline, stdlib only.

The reference set is every label decision under tools/guide-drift/recordings/ with decidedBy
'human': the step id, the label, what the person chose (a name, or ignore, or gone) and the
rejected candidates the recording kept. A recording keeps names and roles of the rejected
elements as 'role "name"', and no step title, so a case's step has an empty title.

A decider is a callable with the Decider signature of decide.py. The baseline, no model and
always ask, is `ask_always`. Reported: accuracy (a decision that is not made counts as wrong, and
accuracy of the decisions made is given too), a calibration table (confidence buckets against
accuracy, with the expected calibration error), coverage and accuracy at each confidence
threshold, and the latency per decision.

    python tools/guide-drift/evaluate.py                      # the baseline
    python tools/guide-drift/evaluate.py --decider mod:name   # a decider callable in an importable module

Exits 1 when the reference set holds no human decision.
"""
from __future__ import annotations

import argparse
import importlib
import json
import re
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from decide import Candidate, Decider, Decision  # noqa: E402

RECORDINGS = Path(__file__).resolve().parent / "recordings"
BUCKETS = 10
THRESHOLDS = (0.5, 0.7, 0.8, 0.9, 0.95, 0.97, 0.99)
CANDIDATE = re.compile(r'^(\S+) "(.*)"$', re.DOTALL)


@dataclass
class Case:
    lab: str
    step_id: str
    label: str
    decision: str                 # the recording's: "use" | "ignore" | "gone"
    name: str | None              # use: the chosen accessible name
    role: str | None
    rejected: list[str]

    def candidates(self) -> list[Candidate]:
        """The chosen element in the middle of the rejected ones, so position tells nothing."""
        rejected = []
        for text in self.rejected:
            match = CANDIDATE.match(text)
            rejected.append(Candidate(match.group(1), match.group(2)) if match else Candidate("", text))
        if self.decision == "use" and self.name is not None:
            rejected.insert(len(rejected) // 2, Candidate(self.role or "", self.name))
        return rejected


def load_reference(directory: Path = RECORDINGS) -> list[Case]:
    cases = []
    for path in sorted(directory.glob("*.json")):
        recording = json.loads(path.read_text(encoding="utf-8"))
        for step_id, step in recording.get("steps", {}).items():
            for label, entry in (step.get("labels") or {}).items():
                if entry.get("decidedBy") == "human":
                    cases.append(Case(recording.get("lab", path.stem), step_id, label, entry["decision"],
                                      entry.get("name"), entry.get("role"), list(entry.get("rejected") or [])))
    return cases


def ask_always(step: dict, item: dict, label: str, candidates: list[Candidate]) -> Decision | None:
    """The baseline: no model, the person is asked every time."""
    return None


def is_correct(case: Case, decision: Decision) -> bool:
    if case.decision == "ignore":
        return decision.kind == "ignore"
    if case.decision == "gone":
        return decision.kind == "drift" and decision.severity == "blocking"
    return decision.kind in ("use", "drift") and decision.severity != "blocking" and decision.name == case.name


@dataclass
class Outcome:
    case: Case
    answered: bool
    correct: bool
    confidence: float | None
    seconds: float
    failed: bool = False


@dataclass
class Report:
    outcomes: list[Outcome] = field(default_factory=list)

    @property
    def total(self) -> int:
        return len(self.outcomes)

    @property
    def answered(self) -> list[Outcome]:
        return [o for o in self.outcomes if o.answered]

    @property
    def accuracy(self) -> float:
        return sum(o.correct for o in self.outcomes) / self.total

    @property
    def accuracy_answered(self) -> float | None:
        answered = self.answered
        return sum(o.correct for o in answered) / len(answered) if answered else None

    def calibration(self) -> list[tuple[float, float, int, float, float]]:
        """(low, high, n, accuracy, mean confidence) per non-empty bucket."""
        rows = []
        scored = [o for o in self.answered if o.confidence is not None]
        for b in range(BUCKETS):
            low, high = b / BUCKETS, (b + 1) / BUCKETS
            members = [o for o in scored if low <= o.confidence < high or (b == BUCKETS - 1 and o.confidence == 1.0)]
            if members:
                rows.append((low, high, len(members), sum(o.correct for o in members) / len(members),
                             sum(o.confidence for o in members) / len(members)))
        return rows

    def ece(self) -> float | None:
        rows = self.calibration()
        n = sum(r[2] for r in rows)
        return sum(r[2] * abs(r[3] - r[4]) for r in rows) / n if n else None

    def at_threshold(self, threshold: float) -> tuple[float, float | None]:
        """(coverage over all cases, accuracy of the decisions made at or above the threshold)."""
        kept = [o for o in self.answered if o.confidence is not None and o.confidence >= threshold]
        return len(kept) / self.total, (sum(o.correct for o in kept) / len(kept) if kept else None)

    def latency_ms(self) -> tuple[float, float, float]:
        ms = sorted(o.seconds * 1000 for o in self.outcomes)
        return sum(ms) / len(ms), ms[len(ms) // 2], ms[-1]

    def text(self) -> str:
        pct = lambda v: "n/a" if v is None else f"{v:.1%}"  # noqa: E731
        failed = sum(o.failed for o in self.outcomes)
        mean, median, worst = self.latency_ms()
        lines = [f"Cases: {self.total}   decided: {len(self.answered)}   asked: {self.total - len(self.answered)}"
                 f"   raised: {failed}",
                 f"Accuracy (a decision not made is wrong): {pct(self.accuracy)}",
                 f"Accuracy of the decisions made: {pct(self.accuracy_answered)}",
                 "", "Calibration (confidence bucket: n, accuracy, mean confidence)"]
        rows = self.calibration()
        lines += [f"  {lo:.1f}-{hi:.1f}: n={n}  accuracy={pct(acc)}  confidence={conf:.3f}"
                  for lo, hi, n, acc, conf in rows] or ["  (no decision carries a confidence)"]
        ece = self.ece()
        lines += [f"Expected calibration error: {'n/a' if ece is None else f'{ece:.3f}'}",
                  "", "Threshold: coverage, accuracy of the decisions kept"]
        for t in THRESHOLDS:
            coverage, accuracy = self.at_threshold(t)
            lines.append(f"  >= {t:.2f}: coverage={pct(coverage)}  accuracy={pct(accuracy)}")
        lines += ["", f"Latency per decision: mean {mean:.3f} ms, median {median:.3f} ms, max {worst:.3f} ms"]
        return "\n".join(lines)


def evaluate(decider: Decider, cases: list[Case]) -> Report:
    report = Report()
    for case in cases:
        step = {"id": case.step_id, "title": ""}
        item = {"kind": "action", "line": None, "labels": [case.label]}
        failed = False
        started = time.perf_counter()
        try:
            decision = decider(step, item, case.label, case.candidates())
        except Exception:
            decision, failed = None, True
        seconds = time.perf_counter() - started
        answered = decision is not None and decision.kind != "unknown"
        report.outcomes.append(Outcome(case, answered, answered and is_correct(case, decision),
                                       decision.confidence if answered else None, seconds, failed))
    return report


def main(argv: list[str] | None = None, out=print) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--recordings", type=Path, default=RECORDINGS)
    parser.add_argument("--decider", help="module:name of a decider callable; default is the baseline")
    args = parser.parse_args(argv)
    cases = load_reference(args.recordings)
    if not cases:
        out(f"No human decision in the recordings under {args.recordings}: nothing to score.")
        return 1
    if args.decider:
        module, _, name = args.decider.partition(":")
        decider = getattr(importlib.import_module(module), name)
    else:
        decider = ask_always
    out(evaluate(decider, cases).text())
    return 0


if __name__ == "__main__":
    sys.exit(main())
