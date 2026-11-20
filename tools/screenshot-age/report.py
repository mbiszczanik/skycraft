"""Report how old each lab-guide screenshot is against its guide (issue #486).

Lists, per module, every PNG a lab guide references with the date of the PNG's last commit,
the date of the guide's last commit, and the flags: older (PNG predates the guide), not retaken
(PNG predates --since), unknown (no history in the checkout). Candidates, not proof of drift.
Exit 0 when the report is complete, 2 when a module directory is missing or git cannot run.

    python tools/screenshot-age/report.py --module 1 --module 4 [--since 2026-10-18]
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_SINCE = "2026-10-18"
_MD_IMG = re.compile(r"!\[[^\]]*\]\(\s*<?([^)\s>]+\.png)>?[^)]*\)", re.IGNORECASE)
_HTML_IMG = re.compile(r"<img\b[^>]*?\bsrc=[\"']([^\"']+\.png)[\"']", re.IGNORECASE)


class ReportError(Exception):
    """A cause that makes the report unusable (exit 2)."""


def last_commit_date(repo, path):
    """Date (YYYY-MM-DD) of the last commit touching path, or None when it has no history."""
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), "log", "-1", "--format=%cs", "--", Path(path).as_posix()],
            capture_output=True, text=True, check=False)
    except OSError as exc:
        raise ReportError(f"cannot run git: {exc}")
    if out.returncode != 0:
        raise ReportError(f"git log failed (exit {out.returncode}): {out.stderr.strip()}")
    return out.stdout.strip() or None


def referenced_pngs(guide_text):
    """PNG paths a guide references, in order, without duplicates."""
    found = [m.group(1) for m in _MD_IMG.finditer(guide_text)]
    found += [m.group(1) for m in _HTML_IMG.finditer(guide_text)]
    seen, result = set(), []
    for ref in found:
        if "://" in ref or ref in seen:
            continue
        seen.add(ref)
        result.append(ref)
    return result


def find_module_dir(repo, number):
    matches = sorted(p for p in Path(repo).glob(f"module-{number}-*") if p.is_dir())
    if not matches:
        raise ReportError(f"module directory module-{number}-* not found in {repo}")
    return matches[0]


def check_git(repo):
    try:
        out = subprocess.run(["git", "-C", str(repo), "rev-parse", "--git-dir"],
                             capture_output=True, text=True, check=False)
    except OSError as exc:
        raise ReportError(f"cannot run git: {exc}")
    if out.returncode != 0:
        raise ReportError(f"{repo} is not a git checkout: {out.stderr.strip()}")


def build_rows(repo, module_dir, since):
    repo = Path(repo)
    rows = []
    for guide in sorted(module_dir.glob("*/lab-guide-*.md")):
        guide_rel = guide.relative_to(repo)
        guide_date = last_commit_date(repo, guide_rel)
        text = guide.read_text(encoding="utf-8")
        for ref in referenced_pngs(text):
            png_rel = (guide.parent / ref).resolve().relative_to(repo.resolve())
            png_date = last_commit_date(repo, png_rel)
            flags = []
            if png_date is None:
                flags.append("unknown")
            else:
                if guide_date and png_date < guide_date:
                    flags.append("older")
                if png_date < since:
                    flags.append("not retaken")
            rows.append({"guide": guide_rel.as_posix(), "png": png_rel.as_posix(),
                         "png_date": png_date or "-", "guide_date": guide_date or "-",
                         "flags": flags})
    return rows


def summary_line(number, rows):
    def count(flag):
        return sum(1 for r in rows if flag in r["flags"])
    return (f"module {number}: {len(rows)} PNGs, {count('older')} older, "
            f"{count('not retaken')} not retaken, {count('unknown')} unknown")


def run(repo, modules, since, out=sys.stdout):
    check_git(repo)
    summaries = []
    for number in modules:
        module_dir = find_module_dir(repo, number)
        rows = build_rows(repo, module_dir, since)
        print(f"== module {number} ({module_dir.name})", file=out)
        for r in rows:
            flags = ", ".join(r["flags"]) if r["flags"] else "current"
            print(f"{r['png']}\tpng {r['png_date']}\tguide {r['guide_date']}\t{flags}", file=out)
        summaries.append(summary_line(number, rows))
    print("; ".join(summaries), file=out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--module", type=int, action="append", required=True)
    parser.add_argument("--since", default=DEFAULT_SINCE)
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parents[2]))
    args = parser.parse_args(argv)
    try:
        run(Path(args.repo), args.module, args.since)
    except ReportError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
