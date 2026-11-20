"""Unit tests for script_paths.py (issue #335), on fixture text written here, not the real guides.
Run from the repository root:

    python -X utf8 -m unittest discover -s tools/guide-drift/tests
"""
import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import script_paths  # noqa: E402

FENCE = "`" * 3

TWO_STEPS = f"""# Lab X

## Section 1

### Step 1.1.1: First

{FENCE}powershell
# a comment
Get-AzContext
{FENCE}

### Step 1.1.2: Second

{FENCE}bash
az account show
{FENCE}
"""


class ExtractRowsTests(unittest.TestCase):
    def test_two_blocks_under_two_steps(self) -> None:
        rows = script_paths.extract_rows(TWO_STEPS)
        self.assertEqual([(r["where"], r["language"], r["command"], r["line"]) for r in rows],
                         [("1.1.1", "powershell", "Get-AzContext", 7),
                          ("1.1.2", "bash", "az account show", 14)])

    def test_a_block_before_any_step_takes_the_section_heading(self) -> None:
        text = f"# Lab X\n\n## Prerequisites\n\n{FENCE}pwsh\nConnect-MgGraph\n{FENCE}\n"
        rows = script_paths.extract_rows(text)
        self.assertEqual([(r["where"], r["language"], r["command"]) for r in rows],
                         [("Prerequisites", "pwsh", "Connect-MgGraph")])

    def test_a_block_with_an_unlisted_language_is_skipped(self) -> None:
        text = (f"### Step 1.1.1: A\n\n{FENCE}json\n{{}}\n{FENCE}\n\n{FENCE}\nplain\n{FENCE}\n\n"
                f"{FENCE}azurecli\naz group list\n{FENCE}\n")
        rows = script_paths.extract_rows(text)
        self.assertEqual([(r["language"], r["command"]) for r in rows], [("azurecli", "az group list")])

    def test_an_indented_block_and_a_longer_fence_are_read(self) -> None:
        text = f"### Step 1.2.3: A\n\n  {FENCE}powershell\n  Get-AzRole\n  {FENCE}\n\n````bash\n{FENCE}\nx\n````\n"
        rows = script_paths.extract_rows(text)
        self.assertEqual([(r["language"], r["command"]) for r in rows],
                         [("powershell", "Get-AzRole"), ("bash", "```")])

    def test_a_pipe_in_a_command_is_escaped_in_the_table(self) -> None:
        out = script_paths.render("g.md", [{"line": 1, "where": "1.1.1", "language": "bash", "command": "a | b"}])
        self.assertIn("`a \\| b`", out)
        self.assertIn("g.md: 1 script block(s)", out)


class MainTests(unittest.TestCase):
    def run_main(self, files: dict[str, str]) -> int:
        with tempfile.TemporaryDirectory() as tmp:
            module = Path(tmp) / "module-x"
            for name, text in files.items():
                path = module / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return script_paths.main(["script_paths.py", str(module)])

    def test_a_guide_with_blocks_exits_0(self) -> None:
        self.assertEqual(self.run_main({"1.1-a/lab-guide-1.1.md": TWO_STEPS}), 0)

    def test_no_guide_exits_non_zero(self) -> None:
        self.assertEqual(self.run_main({"1.1-a/README.md": "x"}), 1)

    def test_a_guide_without_a_script_block_exits_non_zero(self) -> None:
        good, empty = {"1.1-a/lab-guide-1.1.md": TWO_STEPS}, {"1.2-b/lab-guide-1.2.md": "# only text\n"}
        self.assertEqual(self.run_main({**good, **empty}), 1)
        self.assertEqual(self.run_main(empty), 1)


if __name__ == "__main__":
    unittest.main()
