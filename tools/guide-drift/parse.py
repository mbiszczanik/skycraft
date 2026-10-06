#!/usr/bin/env python3
"""Turn a SkyCraft lab guide into the steps JSON the guide drift runner performs.

Standard library only, so tests/Guide-Drift-Parser.Tests.ps1 can run it on the CI runner
without a browser. Rules (issue #189):

  * Only '### Step X.Y.N: Title' sections are read. Text before the first step and after the
    last step's section (the next '##' or '###' heading) is ignored.
  * Fenced code blocks and HTML comments (<!-- ... -->, also across lines) are removed first, so a
    heading or a bold span quoted in a snippet or commented out never counts. As in CommonMark, a
    fence closes only on a run of its own character at least as long as the opener, followed by
    nothing but whitespace, so a 4-backtick fence can quote a 3-backtick one.
  * Where a step has '#### Option 1:' or '#### Option A:' headings, only the first option's
    body is read. Its own '**Expected Result**' wins; when it has none, the first Expected Result
    anywhere in the step is taken (the standard puts a single one after Option 3).
  * '**Expected Result**' may be a list item and may carry a qualifier before the colon
    ('**Expected Result** (if ...):'). The first one in a step is kept.
  * Bold spans in list items are UI labels. A list item containing a chain (A → B, A -> B or
    A > B) is one 'navigation' item with several labels; otherwise it is an 'action' item.
    '\\*' inside bold is a literal asterisk; a leading '*' (the Portal's required-field marker)
    is dropped from a label.
  * A list item '**Label**: value' is a 'field' item when Label is a UI label. A field whose
    value is prose rather than a literal ("Click the ... button", "1 month from now") is typed
    as written; the recording's valueOverrides is where a supervised run supplies the literal.
  * Bold spans that are not UI elements are dropped by NON_UI_BOLD and by the colon rule
    (bold text ending with ':' is a caption, not a label).
  * Tables whose second header cell is 'Value' are forms. When the first header is Field,
    Property or Setting, each row becomes a 'field' item (label, value). When it is Name or Tag,
    each row becomes a 'tag' item (name, value), typed into the Portal's Tags grid by row rather
    than looked up as a labelled control. Backticks and bold are stripped from both cells.
    Every other table is informational and is not read.
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
OPTION_HEADING = re.compile(r"^####\s+Option\s+(?P<n>\d+|[A-Z])\b")
FIRST_OPTIONS = {"1", "A"}
SUBHEADING = re.compile(r"^####\s")
FENCE = re.compile(r"^[ \t]*(?P<run>`{3,}|~{3,})(?P<info>.*)$")
LIST_ITEM = re.compile(r"^\s*(?:\d+\.|[-*])\s+(?P<text>.+)$")
BOLD = re.compile(r"\*\*(?P<text>(?:\\\*|[^*])+?)\*\*")   # '\*' inside bold is a literal '*'
LIST_FIELD = re.compile(r"^\*\*(?P<label>(?:\\\*|[^*])+?)\*\*\s*:\s*(?P<value>.+)$")
EXPECTED = re.compile(
    r"^\s*(?:(?:[-*]|\d+\.)\s+)?\*\*Expected Result\*\*[^:]*:\s*(?P<text>.+?)\s*$")
TABLE_ROW = re.compile(r"^\s*\|(?P<cells>.+)\|\s*$")
SEPARATOR_CELL = re.compile(r"^:?-+:?$")   # every non-empty cell of a separator row; not "--name"
IMAGE = re.compile(r"!\[[^\]]*\]\(\s*\.?/?(?P<path>images/[^)\s]+)\s*\)")
CHAIN = re.compile(r"→|->|\s>\s")   # navigation chain separators: arrow, ASCII arrow, " > "

# A table is a form when its header is '<one of these> | Value'.
# 'Parameter | Value' lists CLI flags and is not a form.
FIELD_FIRST_HEADERS = {"field", "property", "setting"}   # rows become 'field' items
TAG_FIRST_HEADERS = {"name", "tag"}                        # rows become 'tag' items

NON_UI_BOLD = {
    "Expected Result", "Note", "Tip", "Important", "Warning", "Why", "SkyCraft Choice",
    # Captions and prose emphasis found in the guides, each with the lab it came from. Only text
    # that is clearly not a Portal element is listed; a supervised run answers the rest once.
    "Azure Portal",                            # 1.1-5.2: "Open **Azure Portal**", the site itself
    "group",                                   # 1.2: "Select the **group** (not individual users)"
    "WITHOUT",                                 # 1.3: emphasis
    "resource",                                # 1.3: "Locks at **resource** level"
    "fully private",                           # 2.2: emphasis
    "private IP",                              # 2.2: emphasis
    "Install Bicep CLI",                       # 3.1: caption of a local-tools step
    "Install VS Code Extension",               # 3.1: caption of a local-tools step
    "Review generated Bicep file",             # 3.1: caption
    "(Optional)",                              # 3.2: caption
    "zone-redundant by default",               # 3.2: emphasis
    "Simulating zone failure",                 # 3.2: caption in a conceptual step
    "Verifying traffic routing",               # 3.2: caption in a conceptual step
    "Restoring service",                       # 3.2: caption in a conceptual step
    "Version: 2.0 (Staging)",                  # 3.4: text of the local index.html
    "Blue",                                    # 3.4: colour of the local index.html
    "Validation",                              # 3.4: caption ("**Validation**: Add the TXT ...")
    "Bind",                                    # 3.4: caption ("**Bind**: Once validated, ...")
    "always enabled",                          # 4.1: emphasis
    "Find the account-level switch",           # 4.2: caption
    "Create the `public-demo` container - Private",  # 4.2: caption
    "Prove the container is not anonymous",    # 4.2: caption
    "Result",                                  # 4.2: caption ("**Result**: PublicAccess...")
    "See the container-level switch",          # 4.2: caption
    "backup instance",                         # 5.2: emphasis
    "Fallback",                                # 5.3: caption
    "Dev fallback source",                     # 5.3: caption of an expected outcome
    "Production source",                       # 5.3: caption of an expected outcome
}


# Stands in for a line that held nothing but an HTML comment. Unlike "" it does not end a table,
# so a commented-out row in the middle of a form table leaves the rest of the table readable.
HIDDEN = chr(0)


def strip_hidden(lines: list[str]) -> list[str]:
    """Blank out fenced code blocks and HTML comments, keeping line numbers stable.

    A fenced line becomes "". A line that held only comment text becomes HIDDEN; a line that
    is partly commented keeps the text outside the comment.
    """
    out: list[str] = []
    fence: str | None = None          # the opening run, e.g. "````"
    in_comment = False
    for line in lines:
        if not in_comment:
            m = FENCE.match(line)
            if fence is None and m:
                fence = m.group("run")
                out.append("")
                continue
            if fence is not None:
                if (m and m.group("run")[0] == fence[0] and len(m.group("run")) >= len(fence)
                        and not m.group("info").strip()):
                    fence = None
                out.append("")
                continue
        kept: list[str] = []
        position = 0
        touched = in_comment
        while position < len(line):
            if in_comment:
                close = line.find("-->", position)
                if close < 0:
                    position = len(line)
                else:
                    in_comment = False
                    position = close + 3
            else:
                open_at = line.find("<!--", position)
                if open_at < 0:
                    kept.append(line[position:])
                    position = len(line)
                else:
                    kept.append(line[position:open_at])
                    in_comment = True
                    touched = True
                    position = open_at + 4
                    # '<!-->' and '<!--->' are complete, empty comments (HTML spec)
                    for abrupt in (">", "->"):
                        if line.startswith(abrupt, position):
                            in_comment = False
                            position += len(abrupt)
                            break
        text = "".join(kept)
        out.append(HIDDEN if touched and not text.strip() else text)
    return out


def unescape(text: str) -> str:
    return text.replace("\\*", "*")


def clean_label(text: str) -> str:
    text = text.strip().lstrip("*").strip()      # a leading '*' is the Portal's required marker
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'“”":
        text = text[1:-1].strip()
    return text.strip("“”\"'").strip()


def is_ui_label(text: str) -> bool:
    return bool(text) and text not in NON_UI_BOLD and not text.endswith(":")


def strip_value_markup(text: str) -> str:
    text = text.strip()
    text = BOLD.sub(lambda m: unescape(m.group("text")), text)
    return text.replace("`", "").strip()      # code spans anywhere, not only around the value


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
    """The whole body when there are no Option headings. Otherwise the first option (1 or A),
    plus Expected Result lines outside the other options' bodies; when none of those exists,
    the first Expected Result anywhere in the step."""
    has_options = any(OPTION_HEADING.match(line) for _, line in body)
    if not has_options:
        return body
    kept: list[tuple[int, str]] = []
    first_expected: tuple[int, str] | None = None
    region = "outside"                    # "outside" | "first" | "other"
    for number, line in body:
        m = OPTION_HEADING.match(line)
        if m:
            region = "first" if m.group("n") in FIRST_OPTIONS else "other"
            continue
        if SUBHEADING.match(line):
            region = "outside"
            continue
        is_expected = bool(EXPECTED.match(line))
        if is_expected and first_expected is None:
            first_expected = (number, line)
        if region == "first" or (is_expected and region == "outside"):
            kept.append((number, line))
    if first_expected is not None and not any(EXPECTED.match(line) for _, line in kept):
        kept = sorted(kept + [first_expected])
    return kept


def parse_items(body: list[tuple[int, str]]) -> tuple[list[dict], str | None, list[str]]:
    items: list[dict] = []
    expected: str | None = None
    images: list[str] = []
    in_table = False
    form: str | None = None               # "field", "tag" or None (informational) for this table
    for number, line in body:
        if line == HIDDEN:
            continue                      # a commented-out line neither ends nor extends a table
        e = EXPECTED.match(line)
        if e:
            if expected is None:
                expected = e.group("text")    # the first one in the step wins
            continue
        for img in IMAGE.finditer(line):
            images.append(img.group("path"))
        row = TABLE_ROW.match(line)
        if row:
            cells = [c.strip() for c in row.group("cells").split("|")]
            filled = [c for c in cells if c]
            if filled and all(SEPARATOR_CELL.match(c) for c in filled):
                continue
            if not in_table:
                in_table = True          # header row: a form only when the second cell is "Value"
                first = strip_value_markup(cells[0]).lower()
                form = None
                if len(cells) >= 2 and strip_value_markup(cells[1]).lower() == "value":
                    if first in FIELD_FIRST_HEADERS:
                        form = "field"
                    elif first in TAG_FIRST_HEADERS:
                        form = "tag"
                continue
            if form and len(cells) >= 2 and cells[0]:
                key = "label" if form == "field" else "name"
                items.append({"kind": form, key: clean_label(strip_value_markup(cells[0])),
                              "value": strip_value_markup(cells[1]), "line": number})
            continue
        in_table = False
        li = LIST_ITEM.match(line)
        if not li:
            continue
        f = LIST_FIELD.match(li.group("text"))
        if f:
            label = clean_label(unescape(f.group("label")))
            if is_ui_label(label):
                value = f.group("value").strip()
                if value.endswith("."):
                    value = value[:-1]             # before the markup, so "`staging`." works
                value = strip_value_markup(value)
                items.append({"kind": "field", "label": label, "value": value, "line": number})
                continue
        labels = [clean_label(unescape(b.group("text"))) for b in BOLD.finditer(li.group("text"))]
        labels = [l for l in labels if is_ui_label(l)]
        if not labels:
            continue
        kind = "navigation" if CHAIN.search(li.group("text")) and len(labels) > 1 else "action"
        items.append({"kind": kind, "labels": labels, "line": number})
    return items, expected, images


def parse_guide(guide: Path, repo_root: Path | None = None) -> dict:
    text = guide.read_text(encoding="utf-8-sig")
    lines = strip_hidden(text.splitlines())
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
        with args.out.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(payload + "\n")
    else:
        # A piped stdout on Windows defaults to the locale code page; the JSON is always UTF-8.
        sys.stdout.reconfigure(encoding="utf-8")
        print(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
