#!/usr/bin/env python3
"""Turn a SkyCraft lab guide into the steps JSON the guide drift runner performs.

Standard library only, so tests/Guide-Drift-Parser.Tests.ps1 can run it on the CI runner
without a browser. Rules (issue #189):

  * Only '### Step X.Y.N: Title' sections are read. Text before the first step and after the
    last step's section (the next '##' or '###' heading) is ignored.
  * Fenced code blocks are removed first, so a heading or a bold span quoted in a snippet never
    counts.
  * Where a step has '#### Option N:' headings, only the Option 1 body is read, plus the
    step's '**Expected Result**' line wherever it sits (the standard puts it after Option 3).
  * Bold spans in list items are UI labels. A list item containing an arrow chain (A -> B) is
    one 'navigation' item with several labels; otherwise it is an 'action' item.
  * Bold spans that are not UI elements are dropped by NON_UI_BOLD and by the colon rule
    (bold text ending with ':' is a caption, not a label).
  * 'Field | Value' tables become 'field' items; backticks and bold are stripped from the value.
  * A step with no item left is emitted with portal=false and is not checked by the runner.

Usage: python parse.py <path/to/lab-guide-X.Y.md> [--out steps.json]
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from pathlib import Path

STEP_HEADING = re.compile(r"^###\s+Step\s+(?P<id>\d+\.\d+\.\d+):\s*(?P<title>.+?)\s*$")
SECTION_END = re.compile(r"^#{1,3}\s")
OPTION_HEADING = re.compile(r"^####\s+Option\s+(?P<n>\d+)\b")
SUBHEADING = re.compile(r"^####\s")
FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})")
LIST_ITEM = re.compile(r"^\s*(?:\d+\.|[-*])\s+(?P<text>.+)$")
BOLD = re.compile(r"\*\*(?P<text>[^*]+?)\*\*")
EXPECTED = re.compile(r"^\*\*Expected Result\*\*\s*:\s*(?P<text>.+?)\s*$")
TABLE_ROW = re.compile(r"^\s*\|(?P<cells>.+)\|\s*$")
TABLE_SEPARATOR = re.compile(r"^\s*\|?\s*:?-{2,}")
IMAGE = re.compile(r"!\[[^\]]*\]\(\s*\.?/?(?P<path>images/[^)\s]+)\s*\)")
ARROW = "→"

NON_UI_BOLD = {
    "Expected Result", "Note", "Tip", "Important", "Warning", "Why", "SkyCraft Choice",
}


def strip_fences(lines: list[str]) -> list[str]:
    """Blank out fenced code blocks, keeping line numbers stable."""
    out: list[str] = []
    fence: str | None = None
    for line in lines:
        m = FENCE.match(line)
        if fence is None and m:
            fence = m.group(1)[0]
            out.append("")
            continue
        if fence is not None:
            if m and m.group(1)[0] == fence:
                fence = None
            out.append("")
            continue
        out.append(line)
    return out


def clean_label(text: str) -> str:
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'“”":
        text = text[1:-1].strip()
    return text.strip("“”\"'").strip()


def is_ui_label(text: str) -> bool:
    return bool(text) and text not in NON_UI_BOLD and not text.endswith(":")


def strip_value_markup(text: str) -> str:
    text = text.strip()
    text = BOLD.sub(lambda m: m.group("text"), text)
    return text.strip("`").strip()


def png_width(path: Path) -> int | None:
    """Width from the IHDR chunk; None when the file is not a PNG."""
    try:
        with path.open("rb") as handle:
            head = handle.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">I", head[16:20])[0]


def split_steps(lines: list[str]) -> list[dict]:
    """Return raw step sections: id, title, heading line (1-based) and body lines with numbers."""
    steps: list[dict] = []
    current: dict | None = None
    for number, line in enumerate(lines, start=1):
        m = STEP_HEADING.match(line)
        if m:
            current = {"id": m.group("id"), "title": m.group("title"), "line": number, "body": []}
            steps.append(current)
            continue
        if current is not None and SECTION_END.match(line):
            current = None
            continue
        if current is not None:
            current["body"].append((number, line))
    return steps


def option_one_body(body: list[tuple[int, str]]) -> list[tuple[int, str]]:
    """The whole body when there are no Option headings; otherwise Option 1 only, plus the
    Expected Result line from anywhere in the step."""
    has_options = any(OPTION_HEADING.match(line) for _, line in body)
    if not has_options:
        return body
    kept: list[tuple[int, str]] = []
    inside = False
    for number, line in body:
        m = OPTION_HEADING.match(line)
        if m:
            inside = m.group("n") == "1"
            continue
        if SUBHEADING.match(line):
            inside = False
            continue
        if inside or EXPECTED.match(line):
            kept.append((number, line))
    return kept


def parse_items(body: list[tuple[int, str]]) -> tuple[list[dict], str | None, list[str]]:
    items: list[dict] = []
    expected: str | None = None
    images: list[str] = []
    in_table = False
    for number, line in body:
        e = EXPECTED.match(line)
        if e:
            expected = e.group("text")
            continue
        for img in IMAGE.finditer(line):
            images.append(img.group("path"))
        row = TABLE_ROW.match(line)
        if row:
            cells = [c.strip() for c in row.group("cells").split("|")]
            if TABLE_SEPARATOR.match(line):
                continue
            if not in_table:
                in_table = True          # header row: Field | Value, Property | Value
                continue
            if len(cells) >= 2 and cells[0]:
                label = clean_label(BOLD.sub(lambda m: m.group("text"), cells[0]))
                items.append({"kind": "field", "label": label,
                              "value": strip_value_markup(cells[1]), "line": number})
            continue
        in_table = False
        li = LIST_ITEM.match(line)
        if not li:
            continue
        labels = [clean_label(b.group("text")) for b in BOLD.finditer(li.group("text"))]
        labels = [l for l in labels if is_ui_label(l)]
        if not labels:
            continue
        kind = "navigation" if ARROW in li.group("text") and len(labels) > 1 else "action"
        items.append({"kind": kind, "labels": labels, "line": number})
    return items, expected, images


def parse_guide(guide: Path, repo_root: Path | None = None) -> dict:
    text = guide.read_text(encoding="utf-8-sig")
    lines = strip_fences(text.splitlines())
    lab_match = re.search(r"lab-guide-(\d+\.\d+)\.md$", guide.name)
    lab = lab_match.group(1) if lab_match else ""
    steps = []
    for raw in split_steps(lines):
        items, expected, images = parse_items(option_one_body(raw["body"]))
        steps.append({
            "id": raw["id"], "title": raw["title"], "line": raw["line"],
            "portal": bool(items), "items": items, "expected": expected, "images": images,
        })
    images_dir = guide.parent / "images"
    all_images = []
    if images_dir.is_dir():
        for png in sorted(images_dir.glob("*.png")):
            width = png_width(png)
            if width is not None:
                all_images.append({"path": f"images/{png.name}", "width": width})
    guide_rel = guide.relative_to(repo_root).as_posix() if repo_root else guide.as_posix()
    return {"lab": lab, "guide": guide_rel, "images": all_images, "steps": steps}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("guide", type=Path)
    parser.add_argument("--out", type=Path, help="write JSON here instead of stdout")
    parser.add_argument("--repo-root", type=Path, help="make the guide path relative to this")
    args = parser.parse_args(argv)
    if not args.guide.is_file():
        print(f"guide not found: {args.guide}", file=sys.stderr)
        return 2
    result = parse_guide(args.guide.resolve(), args.repo_root.resolve() if args.repo_root else None)
    payload = json.dumps(result, indent=2, ensure_ascii=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
