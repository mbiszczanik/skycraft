import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import report  # noqa: E402


def git(repo, *args, date=None):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
    if date:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"{date}T12:00:00+00:00"
    subprocess.run(["git", "-C", str(repo), *args], check=True, env=env, capture_output=True)


class ReportTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = Path(self._tmp.name)
        git(self.repo, "init", "-q")
        lab = self.repo / "module-1-test" / "1.1-lab"
        (lab / "images").mkdir(parents=True)
        (lab / "images" / "old.png").write_bytes(b"a")
        (lab / "images" / "fresh.png").write_bytes(b"b")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "png", date="2026-10-01")
        (lab / "images" / "fresh.png").write_bytes(b"c")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "retake", date="2026-11-05")
        (lab / "lab-guide-1.1.md").write_text(
            "![a](./images/old.png)\n![b](images/fresh.png)\n"
            '<img src="images/ghost.png" alt="x">\n', encoding="utf-8")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "guide", date="2026-11-02")

    def rows(self):
        return {r["png"].rsplit("/", 1)[1]: r
                for r in report.build_rows(self.repo, self.repo / "module-1-test", "2026-10-18")}

    def test_older_png_is_flagged_older_and_not_retaken(self):
        self.assertEqual(self.rows()["old.png"]["flags"], ["older", "not retaken"])

    def test_current_png_has_no_flags(self):
        self.assertEqual(self.rows()["fresh.png"]["flags"], [])

    def test_png_without_history_is_unknown_and_counted(self):
        rows = self.rows()
        self.assertEqual(rows["ghost.png"]["flags"], ["unknown"])
        self.assertIn("1 unknown", report.summary_line(1, list(rows.values())))

    def test_missing_module_directory_exits_2_naming_the_cause(self):
        err = io.StringIO()
        old, sys.stderr = sys.stderr, err
        try:
            code = report.main(["--repo", str(self.repo), "--module", "9"])
        finally:
            sys.stderr = old
        self.assertEqual(code, 2)
        self.assertIn("module-9-*", err.getvalue())

    def test_complete_report_exits_0_with_older_pngs(self):
        out = io.StringIO()
        report.run(self.repo, [1], "2026-10-18", out=out)
        self.assertIn("module 1: 3 PNGs, 1 older, 1 not retaken, 1 unknown", out.getvalue())
        self.assertEqual(report.main(["--repo", str(self.repo), "--module", "1"]), 0)

    def test_not_a_git_checkout_exits_2(self):
        with tempfile.TemporaryDirectory() as plain:
            (Path(plain) / "module-1-x").mkdir()
            self.assertEqual(report.main(["--repo", plain, "--module", "1"]), 2)


if __name__ == "__main__":
    unittest.main()
