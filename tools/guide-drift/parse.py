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
    body is read. The Expected Result is the first one outside any option's body or in the first
    option; when there is none, the first one in another option (the standard puts a single
    one after Option 3).
  * '**Expected Result**' may be a list item and may carry a qualifier before the colon
    ('**Expected Result** (if ...):'). When nothing follows the colon, the list right after it
    is the result: its items joined with '; ', markup stripped, and never read as steps. The
    first one in a step is kept.
  * Bold spans in list items are UI labels. A list item containing a chain (A → B, A -> B or
    A > B) is one 'navigation' item with several labels; otherwise it is an 'action' item.
    '\\*' inside bold is a literal asterisk; a leading '*' (the Portal's required-field marker)
    is dropped from a label.
  * A list item 'Search for **X**' or 'In Azure Portal, search for **X**', optionally followed
    by where to search ('in the search bar', 'in the Azure Portal search', 'in the portal') and
    a full stop, is one 'search' item with the label X. Its scope is 'global' (the runner types X
    into the Portal's top search and opens the result) when the item names the Portal: it starts
    with 'In Azure Portal,', says where in the Portal, or says 'search bar', 'top search' or
    'global search'. Otherwise the scope is 'blade': X is typed into the open blade's or pane's
    own search box ('Search for **"Owner"**' in a role assignment). Anything else after the bold
    ('and click **+ Create**', 'Search for and select **X**') leaves the item an action.
  * A list item '**Label**: value' is a 'field' item when Label is a UI label. A field whose
    value is prose rather than a literal ("Click the ... button", "1 month from now") is typed
    as written; the recording's valueOverrides is where a supervised run supplies the literal.
  * A list item 'Label: value' whose label is plain text is a 'field' item too (#198) when the
    value starts with one bold or code span: 'Lock type: **Delete**', 'Name: `x` (use
    existing)'. The value is that span; a remark after it is dropped. The item is read as any
    other list item instead when the value is plain text (in the guides, a line of a list to
    check: 'Address space: 10.0.0.0/16'); when another bold span or a chain follows the span
    ('Logs: **A** and **B**' stays a click on each); when the label starts with an instruction
    (INSTRUCTION: 'Select your VM:', 'Add tag:', 'Enter:', 'Search for:'); and when the label is
    a caption (NON_UI_BOLD: 'Note:', 'Example:'), is longer than six words, or holds anything
    but letters, digits, spaces and '()/&-'.
  * Bold spans that are not UI elements are dropped by NON_UI_BOLD and by the colon rule
    (bold text ending with ':' is a caption, not a label).
  * Tables whose second header cell is 'Value' are forms. When the first header is Field,
    Property or Setting, each row becomes a 'field' item (label, value). When it is Name or Tag,
    each row becomes a 'tag' item (name, value), typed into the Portal's Tags grid by row rather
    than looked up as a labelled control. Backticks and bold are stripped from both cells.
    Every other table is informational and is not read.
  * A step with no item left is emitted with portal=false and is not checked by the runner.

Known gaps. Spec #189 records only lab 1.1; fix these before another lab is recorded
(#204 tracks labs 1.2-3.2):

  * Of the list items whose label is not bold, only 'Label: **value**' and 'Label: `value`'
    are read as fields (#198). An instruction before the colon is dropped ('Select your VM:
    `x`', 'Choose resource group: `x`'), and two values or a chain after a plain label stay
    clicks ('Frequency: **Daily** at **02:00 AM**', 'Destination: **Send to Log Analytics
    workspace** → `law`').
  * Code-span steps drop out of navigation chains:
    '**Virtual Networks** > `vnet` > **Subnets**' (#199).
  * The first-option rule skips 3.2.1's Portal path, because its Option A is CLI-only (#201).
  * A caption label whose value holds bold spans turns them into actions (4.2:741, #203).
  * Instructions after a field value are lost (5.3:225, #203).
  * Text before the first option heading, and items under a non-option '####' heading after
    the options, are dropped (#203).
  * NON_UI_BOLD is one global list, so a caption from one lab can hide a real label in another
    (#203).

Usage: python parse.py <path/to/lab-guide-X.Y.md> [--out steps.json] [--repo-root <dir>]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Patterns that capture to the end of a line use '.*' and strip in code: a lazy '.+?' followed
# by '\s*$' is quadratic on a long line (a 100,000-character line took 72 seconds).
STEP_HEADING = re.compile(r"^###\s+Step\s+(?P<id>\d+\.\d+\.\d+):(?P<title>.*)$")
SECTION_END = re.compile(r"^#{1,3}\s")
OPTION_HEADING = re.compile(r"^####\s+Option\s+(?P<n>\d+|[A-Z])\b")
FIRST_OPTIONS = {"1", "A"}
SUBHEADING = re.compile(r"^####\s")
FENCE = re.compile(r"^[ \t]*(?P<run>`{3,}|~{3,})(?P<info>.*)$")
LIST_ITEM = re.compile(r"^\s*(?:\d+\.|[-*])\s+(?P<text>.+)$")
BOLD = re.compile(r"\*\*(?P<text>(?:\\\*|[^*])+?)\*\*")   # '\*' inside bold is a literal '*'
LIST_FIELD = re.compile(r"^\*\*(?P<label>(?:\\\*|[^*])+?)\*\*\s*:\s*(?P<value>.+)$")
# 'Label: **value**' or 'Label: `value`' with a plain label (#198). The label starts with a
# letter and is greedy, so a line with no colon fails in linear time. A space must follow the
# colon, so 'https://' never splits there.
PLAIN_FIELD = re.compile(
    r"^(?P<label>[^\W\d_][\w ()/&-]*):\s+"
    r"(?:\*\*(?P<bold>(?:\\\*|[^*])+?)\*\*|`(?P<code>[^`]+)`)(?P<rest>.*)$")
PLAIN_LABEL_MAX_WORDS = 6      # the longest plain label in the guides has five words
# A plain label that starts with one of these is an instruction ('Select your VM: `x`'), not a
# Portal label. 'Type' alone is the Portal's Type field (5.3), while 'Type the VMSS name to
# confirm: `x`' is an instruction (3.2). 'Check' is not listed: 'Check every' is a field (5.1).
INSTRUCTION = re.compile(
    r"^(?:Add|Choose|Click|Create|Delete|Download|Enter|Go|Link|Navigate|Open|Remove|Run|Search"
    r"|Select|Wait|Type\s)\b", re.IGNORECASE)
EXPECTED = re.compile(r"^\s*(?:(?:[-*]|\d+\.)\s+)?\*\*Expected Result\*\*[^:]*:(?P<text>.*)$")
TABLE_ROW = re.compile(r"^\s*\|(?P<cells>.+)\|\s*$")
SEPARATOR_CELL = re.compile(r"^:?-+:?$")   # every non-empty cell of a separator row; not "--name"
IMAGE = re.compile(r"!\[[^\]]*\]\(\s*\.?/?(?P<path>images/[^)\s]+)\s*\)")
CHAIN = re.compile(r"→|->|\s>\s")   # navigation chain separators: arrow, ASCII arrow, " > "
# 'Search for **X**', or 'In Azure Portal, search for **X**' (Azure Portal may be bold), and
# nothing after it but where to search and a full stop.
SEARCH_FOR = re.compile(
    r"^(?P<portal>In\s+(?:\*\*)?Azure\s+Portal(?:\*\*)?,\s*)?"
    r"Search\s+for\s+\*\*(?P<label>(?:\\\*|[^*])+?)\*\*"
    r"(?P<where>\s+in\s+(?:the\s+)?(?:(?:top|global)\s+)?"
    r"(?:(?:Azure\s+)?Portal(?:\s+search(?:\s+(?:bar|box))?)?|search(?:\s+(?:bar|box))?))?"
    r"\s*\.?\s*$", re.IGNORECASE)
# What makes a search the Portal's global one rather than the open blade's own search box.
GLOBAL_SEARCH = re.compile(r"search\s+bar|top\s+search|global\s+search", re.IGNORECASE)

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
    "Example",                                 # 3.3: caption ("Example: `skycraft-auth-...`")
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
    return text.strip("“”\"'").strip()


def is_ui_label(text: str) -> bool:
    return bool(text) and text not in NON_UI_BOLD and not text.endswith(":")


def strip_value_markup(text: str) -> str:
    text = text.strip()
    text = BOLD.sub(lambda m: unescape(m.group("text")), text)
    return text.replace("`", "").strip()      # code spans anywhere, not only around the value


def split_steps(lines: list[str]) -> list[dict]:
    """Return raw step sections: id, title, heading line (1-based) and body lines with numbers."""
    steps: list[dict] = []
    current: dict | None = None
    for number, line in enumerate(lines, start=1):
        m = STEP_HEADING.match(line)
        if m:
            current = {"id": m.group("id"), "title": m.group("title").strip(), "line": number,
                       "body": []}
            steps.append(current)
            continue
        if current is not None and SECTION_END.match(line):
            current = None
            continue
        if current is not None:
            current["body"].append((number, line))
    return steps


def option_regions(body: list[tuple[int, str]]) -> list[str]:
    """Where each body line sits: 'step' for every line when the step has no Option headings;
    otherwise 'first' (the Option 1 or A body), 'other' (another option's body), 'outside'
    (before the first option, or under another '####' heading) or 'heading'."""
    if not any(OPTION_HEADING.match(line) for _, line in body):
        return ["step"] * len(body)
    regions: list[str] = []
    region = "outside"
    for _, line in body:
        m = OPTION_HEADING.match(line)
        if m:
            region = "first" if m.group("n") in FIRST_OPTIONS else "other"
            regions.append("heading")
        elif SUBHEADING.match(line):
            region = "outside"
            regions.append("heading")
        else:
            regions.append(region)
    return regions


def expected_text(body: list[tuple[int, str]], index: int) -> tuple[str, int]:
    """The text of the Expected Result on body[index], and the index of the first line after it.

    The text is what follows the colon. When nothing does, it is the list right after the line
    (blank lines between are allowed): its items joined with '; ', markup stripped as for values.
    """
    text = EXPECTED.match(body[index][1]).group("text").strip()
    if text:
        return text, index + 1
    position = index + 1
    while position < len(body) and (body[position][1] == HIDDEN or not body[position][1].strip()):
        position += 1
    parts: list[str] = []
    after = index + 1
    while position < len(body):
        line = body[position][1]
        if line != HIDDEN:
            li = LIST_ITEM.match(line)
            if not li:
                break
            parts.append(strip_value_markup(li.group("text")))
            after = position + 1
        position += 1
    return "; ".join(parts), after


def read_step(body: list[tuple[int, str]]) -> tuple[list[dict], str | None, list[str]]:
    """Items, Expected Result and images of one step section.

    Items come from the whole body, or from the first option only. The Expected Result is the
    first one in the step that is not inside another option's body; when there is none, the
    first one anywhere (the standard puts a single one after Option 3).
    """
    regions = option_regions(body)
    item_lines: list[tuple[int, str]] = []
    expected: str | None = None
    fallback: str | None = None
    index = 0
    while index < len(body):
        if EXPECTED.match(body[index][1]):
            text, after = expected_text(body, index)
            if text and regions[index] != "other" and expected is None:
                expected = text
            elif text and fallback is None:
                fallback = text
            index = after
            continue
        if regions[index] in ("step", "first"):
            item_lines.append(body[index])
        index += 1
    items, images = parse_items(item_lines)
    return items, expected if expected is not None else fallback, images


def table_form(header: list[str]) -> str | None:
    """'field' or 'tag' when a table's header row makes it a form; None for any other table."""
    if len(header) < 2 or strip_value_markup(header[1]).lower() != "value":
        return None
    first = strip_value_markup(header[0]).lower()
    if first in FIELD_FIRST_HEADERS:
        return "field"
    if first in TAG_FIRST_HEADERS:
        return "tag"
    return None


def table_row_item(cells: list[str], form: str | None, number: int) -> dict | None:
    """The field or tag item for one data row of a form table; None for any other row."""
    if not form or len(cells) < 2 or not cells[0]:
        return None
    key = "label" if form == "field" else "name"
    return {"kind": form, key: clean_label(strip_value_markup(cells[0])),
            "value": strip_value_markup(cells[1]), "line": number}


def plain_field(text: str, number: int) -> dict | None:
    """The field item for 'Label: **value**' or 'Label: `value`' whose label is plain text
    (#198); None for any other item. The rules are in the module docstring."""
    m = PLAIN_FIELD.match(text)
    if not m:
        return None
    label = m.group("label").strip()
    if (not is_ui_label(label) or INSTRUCTION.match(label)
            or len(label.split()) > PLAIN_LABEL_MAX_WORDS):
        return None
    if BOLD.search(m.group("rest")) or CHAIN.search(m.group("rest")):
        return None                                # two values or a chain: read as actions
    bold = m.group("bold")
    value = unescape(bold) if bold is not None else m.group("code")
    return {"kind": "field", "label": label, "value": value.strip(), "line": number}


def list_item(text: str, number: int) -> dict | None:
    """The field, search, navigation or action item for the text of one list item; None for
    none."""
    s = SEARCH_FOR.match(text.strip())
    if s:
        label = clean_label(unescape(s.group("label")))
        if is_ui_label(label):
            names_portal = bool(s.group("portal")) or "portal" in (s.group("where") or "").lower()
            scope = "global" if names_portal or GLOBAL_SEARCH.search(text) else "blade"
            return {"kind": "search", "labels": [label], "scope": scope, "line": number}
    f = LIST_FIELD.match(text)
    if f:
        label = clean_label(unescape(f.group("label")))
        if is_ui_label(label):
            value = f.group("value").strip()
            if value.endswith("."):
                value = value[:-1]                 # before the markup, so "`staging`." works
            return {"kind": "field", "label": label, "value": strip_value_markup(value),
                    "line": number}
    field = plain_field(text.strip(), number)
    if field:
        return field
    labels =[clean_label(unescape(b.group("text"))) for b in BOLD.finditer(text)]
    labels = [label for label in labels if is_ui_label(label)]
    if not labels:
        return None
    kind = "navigation" if CHAIN.search(text) and len(labels) > 1 else "action"
    return {"kind": kind, "labels": labels, "line": number}


def parse_items(lines: list[tuple[int, str]]) -> tuple[list[dict], list[str]]:
    """Items and image paths of the lines a step is read from, in document order."""
    items: list[dict] = []
    images: list[str] = []
    in_table = False
    form: str | None = None               # "field", "tag" or None (informational) for this table
    for number, line in lines:
        if line == HIDDEN:
            continue                      # a commented-out line neither ends nor extends a table
        images.extend(img.group("path") for img in IMAGE.finditer(line))
        row = TABLE_ROW.match(line)
        if row:
            cells = [c.strip() for c in row.group("cells").split("|")]
            filled = [c for c in cells if c]
            if filled and all(SEPARATOR_CELL.match(c) for c in filled):
                continue
            if not in_table:
                in_table, form = True, table_form(cells)   # the header row
                continue
            item = table_row_item(cells, form, number)
        else:
            in_table = False
            li = LIST_ITEM.match(line)
            item = list_item(li.group("text"), number) if li else None
        if item:
            items.append(item)
    return items, images


def parse_guide(guide: Path, repo_root: Path | None = None) -> dict:
    text = guide.read_text(encoding="utf-8-sig")
    lines = strip_hidden(text.splitlines())
    lab_match = re.search(r"lab-guide-(\d+\.\d+)\.md$", guide.name)
    lab = lab_match.group(1) if lab_match else ""
    steps = []
    for raw in split_steps(lines):
        items, expected, images = read_step(raw["body"])
        steps.append({
            "id": raw["id"], "title": raw["title"], "line": raw["line"],
            "portal": bool(items), "items": items, "expected": expected, "images": images,
        })
    guide_rel = guide.relative_to(repo_root).as_posix() if repo_root else guide.as_posix()
    return {"lab": lab, "guide": guide_rel, "steps": steps}


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
