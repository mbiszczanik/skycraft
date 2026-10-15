"""The recordings in recordings/ keep no decision for a control the runner now operates (#342)."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from decide import DECORATIONS, decoration_of  # noqa: E402

RECORDINGS = Path(__file__).resolve().parent.parent / "recordings"


class RecordingWorkaroundTests(unittest.TestCase):
    def test_the_lab_1_3_recording_works_around_no_control_the_runner_operates(self):
        files = sorted(RECORDINGS.glob("*.json"))
        self.assertTrue(files, "no recording found")
        found = []
        for path in files:
            steps = json.loads(path.read_text(encoding="utf-8"))["steps"]
            for step, entry in steps.items():
                for label, decision in entry.get("labels", {}).items():
                    if decision.get("decision") != "use":
                        continue
                    role, name = decision.get("role"), decision.get("name") or ""
                    if role == "radio" and name == "Select":
                        found.append((path.name, step, label, 'radio "Select"'))
                    elif decoration_of(name, label, role) is not None:
                        found.append((path.name, step, label, f'{role} "{name}"'))
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
