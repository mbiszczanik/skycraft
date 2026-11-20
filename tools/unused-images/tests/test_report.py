import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import report  # noqa: E402

GUIDE = 'module-1-x/1.1-y/lab-guide-1.1.md'
IMG = 'module-1-x/1.1-y/images/'
PNG = b'\x89PNG\x00'


def make_repo(files):
    tmp = tempfile.TemporaryDirectory()
    root = Path(tmp.name)
    subprocess.run(['git', 'init', '-q', str(root)], check=True)
    for rel, content in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(content if isinstance(content, bytes) else content.encode())
    subprocess.run(['git', '-C', str(root), 'add', '-A'], check=True)
    return tmp, root


def run(root, *extra):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = report.main(['--root', str(root), *extra])
    return code, out.getvalue(), err.getvalue()


class ReportTests(unittest.TestCase):
    def repo(self, files):
        tmp, root = make_repo(files)
        self.addCleanup(tmp.cleanup)
        return root

    def test_unused_png_is_listed(self):
        root = self.repo({GUIDE: 'no images', IMG + 'step-1.png': PNG})
        code, out, _ = run(root)
        self.assertEqual(code, 0)
        self.assertIn(IMG + 'step-1.png', out)
        self.assertIn('Unused PNGs: 1', out)

    def test_used_png_is_not_listed(self):
        root = self.repo({GUIDE: '![s](./images/step-1.png)', IMG + 'step-1.png': PNG})
        code, out, _ = run(root)
        self.assertEqual(code, 0)
        self.assertIn('Unused PNGs: 0', out)
        self.assertIn('Missing image references: 0', out)

    def test_missing_reference_is_listed(self):
        root = self.repo({GUIDE: '![s](./images/gone.png)\n<img src="images/gone2.png">'})
        code, out, _ = run(root)
        self.assertEqual(code, 0)
        self.assertIn('Missing image references: 2', out)
        self.assertIn('gone2.png', out)

    def test_strict_exit_codes(self):
        dirty = self.repo({GUIDE: 'x', IMG + 'a.png': PNG})
        self.assertEqual(run(dirty, '--strict')[0], 1)
        clean = self.repo({GUIDE: '![s](./images/a.png)', IMG + 'a.png': PNG})
        self.assertEqual(run(clean, '--strict')[0], 0)

    def test_empty_root_exits_2_and_names_root(self):
        root = self.repo({'README.md': 'nothing'})
        code, out, err = run(root)
        self.assertEqual(code, 2)
        self.assertIn(str(root.resolve()), err)
        self.assertEqual(out, '')

    def test_nothing_is_written(self):
        root = self.repo({GUIDE: 'x', IMG + 'a.png': PNG})

        def tree():
            return sorted(p.relative_to(root).as_posix() for p in root.rglob('*') if '.git' not in p.parts)

        before = tree()
        run(root)
        self.assertEqual(before, tree())


if __name__ == '__main__':
    unittest.main()
