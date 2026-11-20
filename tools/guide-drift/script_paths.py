#!/usr/bin/env python3
"""Print the pass sheet of a module's scripted paths: one row per script block of each lab guide.

Standard library only, offline, read-only (issue #335). Usage from the repository root:

    python3 -X utf8 tools/guide-drift/script_paths.py module-1-identities-governance

Each fenced block whose language is powershell, pwsh, bash or azurecli gets a row: guide, line of
the opening fence, the nearest preceding '### Step X.Y.N' id (the section heading when no step
precedes it), the language and the first command line. Blocks with another or no language are
skipped. Exit 1 when the module has no lab guide or a guide has no such block.
"""
import re
import sys
from pathlib import Path

LANGUAGES = ("powershell", "pwsh", "bash", "azurecli")
STEP = re.compile(r"^###\s+Step\s+(\d+\.\d+\.\d+[a-z]?)\b", re.IGNORECASE)
HEADING = re.compile(r"^#{1,2}\s+(.*\S)\s*$")
FENCE = re.compile(r"^\s*(`{3,}|~{3,})\s*(.*)$")


def extract_rows(text: str) -> list[dict]:
    """Rows of the script blocks in one guide's text, in document order."""
    rows: list[dict] = []
    where = ""
    fence = None  # (marker char, run length) while inside a block
    block: dict | None = None
    for number, line in enumerate(text.splitlines(), start=1):
        m = FENCE.match(line)
        if fence is None:
            if m:
                marker, info = m.group(1), m.group(2).strip()
                fence = (marker[0], len(marker))
                language = info.split()[0].lower() if info else ""
                block = {"line": number, "where": where, "language": language, "lines": []} \
                    if language in LANGUAGES else None
                continue
            step = STEP.match(line)
            if step:
                where = step.group(1)
                continue
            heading = HEADING.match(line)
            if heading:
                where = heading.group(1)
            continue
        closes = m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1] and not m.group(2).strip()
        if closes:
            if block is not None:
                rows.append({"line": block["line"], "where": block["where"], "language": block["language"],
                             "command": first_command(block["lines"])})
            fence, block = None, None
        elif block is not None:
            block["lines"].append(line)
    return rows


def first_command(lines: list[str]) -> str:
    """First non-blank line that is not a comment; the first non-blank line when all are comments."""
    stripped = [ln.strip() for ln in lines if ln.strip()]
    for ln in stripped:
        if not ln.startswith("#"):
            return ln
    return stripped[0] if stripped else ""


def cell(value: str) -> str:
    return value.replace("|", "\\|")


def render(guide: str, rows: list[dict]) -> str:
    out = [f"### {guide}", "", "| Guide | Line | Step | Language | First command |", "| --- | --- | --- | --- | --- |"]
    for r in rows:
        out.append(f"| {cell(guide)} | {r['line']} | {cell(r['where'])} | {r['language']} | `{cell(r['command'])}` |")
    out += ["", f"{guide}: {len(rows)} script block(s)", ""]
    return "\n".join(out)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: script_paths.py <module folder>", file=sys.stderr)
        return 2
    module = Path(argv[1])
    guides = sorted(module.glob("*/lab-guide-*.md"))
    if not guides:
        print(f"FAIL: no lab guide under {module}", file=sys.stderr)
        return 1
    failed = False
    for guide in guides:
        rows = extract_rows(guide.read_text(encoding="utf-8"))
        name = guide.as_posix()
        if not rows:
            print(f"FAIL: no {'/'.join(LANGUAGES)} code block in {name}", file=sys.stderr)
            failed = True
            continue
        print(render(name, rows))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
