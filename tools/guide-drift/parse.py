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
  * Where a step has '#### Option 1:' or '#### Option A:' headings, only one option's body is
    read: the first option whose body yields at least one item, or the first option when none
    does (#201: 3.2.1's Option A is CLI-only, its Option B is the Portal path). The step's
    "option" is that option's name as its heading gives it ('1', 'A', 'B'); only a step with
    Option headings carries the key, so the steps.json of a run tells its reader, and the
    reviewer of a recording, which path was read. The Expected Result is the first one outside
    any option's body or in the option read; when there is none, the first one in a later
    option (the standard puts a single one after Option 3). An earlier option's Expected Result
    describes that option's path and is never taken: Option B read without one of its own
    has none, not Option A's.
  * '**Expected Result**' may be a list item and may carry a qualifier before the colon
    ('**Expected Result** (if ...):'). When nothing follows the colon, the list right after it
    is the result: its items joined with '; ', markup stripped, and never read as steps. When
    the text after the colon ends with a colon itself, the list is read the same way and
    joined to the text ('Navigate to the resource to verify: Name: platformskycraftswcsa;
    Location: ...', 4.1.2), so '**Contributor** (inherited ...)' after 'Shows the user has:'
    is not a click (1.2.10). The list ends at a blank line or any other line that is not a
    list item, at another Expected Result, at an item indented less than its first item
    (stricter than CommonMark, which keeps an item up to three columns less in the list), and
    at the first item's indent with the other marker kind (numbered or bullet), as the next
    numbered step after a nested list. The first
    Expected Result in a step is kept.
  * A line whose text, markup stripped, ends with the word 'verify:' introduces a check list
    (#224): '3. Verify:' (2.2.11), '1. In **Configuration**, verify:' (4.1.11). After a list
    item, the check list is the list items indented deeper than it; blank lines among them are
    skipped, so it ends at the first non-blank line that is not a deeper item (the next numbered
    step) or is an Expected Result, which is read as usual. After any other line it is the list
    right after it, read as after an Expected Result.
    The checks are not items, so 'Status: **Succeeded**' is never a field to fill; they are
    joined with '; ', markup stripped, and joined to the step's Expected Result, or are its
    Expected Result alone when it has none. The introducing line is read as any other item
    (a click on **Configuration**). A check list is read where items are: one in the body of
    an option that is not read is dropped with it.
  * Checks are joined to an Expected Result text (join_checks) after a space when the text
    ends with '.', '!', '?' or ':' ('Bastion is operational. Status: Succeeded', 2.2.11), and
    after '; ' otherwise, so the text and the first check never meet as '.;' or ':;'. The
    checks themselves are joined with '; ' whatever they end with ('... dev-skycraft-swc-vnet.;
    Production source ...', 5.3.6).
  * Bold spans in list items are UI labels. A list item containing a chain (A → B, A -> B or
    A > B) is one 'navigation' item with several labels; otherwise it is an 'action' item.
    '\\*' inside bold is a literal asterisk; a leading '*' (the Portal's required-field marker)
    is dropped from a label.
  * A step of a chain (the text between two separators, or between a separator and the item's
    start or end) that is one code span names a resource to open (#199): '**Load balancers** →
    `dev-skycraft-swc-lb` → **Backend pools**' (3.2.13). It may follow 'Navigate to', 'Go to',
    'Open' or 'Select' and be followed by a remark in parentheses and a full stop ('`scripts` (or
    any container).', 4.4.3), and it must hold more than spaces. The name, backticks stripped,
    is a label in its place among the bold ones, and the item's '"resources"' lists the indices
    of such labels; only an item with a resource name carries the key. A chain of two or more
    steps counts as a navigation ('**Virtual machines** → `dev-skycraft-swc-world-vm`', 3.2.14);
    a resource name alone is no item. A code span with more in its step is a value or prose, not
    a resource: 'Name: `common`', 'select the modified `config.txt`', 'Open `skycraft-config`
    share' (4.3). Nor is one in an item that starts with a plain label ('Destination: **Send to
    Log Analytics workspace** → `law`', 5.1), whose chain is the label's value. A separator
    inside a bold or code span ('`10.0.0.0/8 → None`') does not split a step.
  * A list item 'Search for **X**' or 'In Azure Portal, search for **X**', optionally followed
    by where to search ('in the search bar', 'in the Azure Portal search', 'in the portal') and
    a full stop, is one 'search' item with the label X. Its scope is 'global' (the runner types X
    into the Portal's top search and opens the result) when the item names the Portal: it starts
    with 'In Azure Portal,', says where in the Portal, or says 'search bar', 'top search' or
    'global search'. Otherwise the scope is 'blade': X is typed into the open blade's or pane's
    own search box ('Search for **"Owner"**' in a role assignment). Anything else after the bold
    ('and click **+ Create**', 'Search for and select **X**') leaves the item an action.
  * A list item '**Label**: value' is a 'field' item when Label is a UI label.
  * A field whose value is not text to type or pick as written carries '"literal": false'
    (value_is_literal, #202): the value starts with an instruction verb (VALUE_INSTRUCTION:
    'Click the "..." button', 'Search for "Allowed locations"', 'Leave default'; also inside an
    opening parenthesis, '(leave blank for now)'), ends with a colon ('Select:' before a list),
    starts with 'Your' (a placeholder without brackets: 'Your subscription') or holds a bracket
    token ('[IP of dev-skycraft-swc-lb-pip]', 'malfurion.stormrage@[yourtenant].onmicrosoft.com').
    The runner types such a value only once the recording's valueOverrides gives the field a
    value, or its placeholders turn the value into a literal ('[yourtenant]'); otherwise it
    reports the field as unknown. tests/Guide-Drift-Recording.Tests.ps1 requires the same of
    every recorded lab. A check box state is a literal: 'checked', '✅ Checked', 'Uncheck'; the
    runner reads it (recording.checkbox_state) and ticks or clears the check box the label
    names rather than typing it. So is a bare 'Leave checked' or 'Leave unchecked'. Check and
    Uncheck are instructions only when a word follows them ('uncheck Use workspace created by
    connection monitor and select ...'), not a remark ('Uncheck (default)'). Words the Portal's own options start with in the guides are not instruction verbs:
    'Allow', 'Apply rule to all blobs ...', 'Disable', 'Do not clone settings', 'Enable public
    access ...', 'Increase count by', 'Limit blobs with filters', 'Scale based on a metric',
    'Use existing public key' and 'Create new' ('Create a container named ...' is an instruction).
  * A list item 'Label: value' whose label is plain text is a 'field' item too (#198) when the
    value starts with one bold or code span: 'Lock type: **Delete**', 'Name: `x` (use
    existing)'. The value is that span, its markup stripped as for any value; a remark after it
    is dropped. The item is read as any other list item instead when the value is plain text
    (in the guides, a line of a list to check: 'Address space: 10.0.0.0/16'); when another bold
    span or a chain follows the span ('Logs: **A** and **B**' stays a click on each); when the
    label starts with an instruction (INSTRUCTION: 'Select your VM:', 'Add tag:', 'Enter:',
    'Search for:'); and when the label is a caption (NON_UI_BOLD: 'Note:', 'Example:'), is
    longer than six words, does not start with a letter, or holds anything but letters (of any
    script), digits, spaces and '()/&-'. An underscore is excluded: it marks italics
    ('_Note_:') or an identifier, not a Portal label.
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
    workspace** → `law`'); such a chain names no resource, so 'Flow log type: ... → `vnet` →
    **Confirm selection**' (5.3.5) does not pick the network.
  * A code span with more words in its chain step names no resource, though some do: 'Browse to
    `common/config.txt`' (4.3.6), 'pick the `platform-skycraft-swc-bv` Backup Vault' (5.2.5).
  * A resource name that opens a chain and is not on screen is looked up in the Portal's global
    search, which finds Azure resources but not what lives inside one: a blob container
    ('public-demo', 4.2.12) or a file share ('skycraft-config', 4.3.6). Later in a chain a name
    is looked for on screen only, where the label before it should have listed it: a container
    ('game-assets', 4.2.11; 'scripts', 4.4.3) or a file share's folder or file ('common',
    'config.txt', 4.3.6). Either is reported as a missing resource whenever it is not on screen
    (#199).
  * 'select `config.txt`' (4.3.6) is read as a resource, so the runner clicks the file's row,
    which may open the file rather than select it.
  * The option read is fixed by the guide, not chosen per run. 3.2.1 reads Option B, which
    creates an SSH key resource, while the items of later 3.2 steps follow Option A (3.2.2
    pastes skycraft-dev.pub); option B appears there only in prose notes, so a run of 3.2
    needs 3.2.1 skipped in its recording (#200) or a per-step choice of option.
  * A caption label whose value holds bold spans turns them into actions (4.2:741, #203).
  * Instructions after a field value are lost (5.3:225, #203).
  * Text before the first option heading, and items under a non-option '####' heading after
    the options, are dropped (#203).
  * NON_UI_BOLD is one global list, so a caption from one lab can hide a real label in another
    (#203).
  * Some values that are not text to type still read as literal; #202 does not cover them, and
    each is found when its lab is recorded (#204): 'empty' (3.3.7),
    'Default (30 GiB)' (3.2.3), relative times ('1 month from now', 'Current time'), a list of
    tag pairs in one field ('Tags: Project = SkyCraft, ...', 5.1-5.3) and an angle-bracket
    placeholder ('Owner = <your name>', 5.3). A table row with an empty value that captions the
    rows below it ('**Remote virtual network**', 2.1.9) is a field with an empty value.
  * Only field values are checked for instructions; a tag value is typed as written.
  * Only 'verify:' and an Expected Result introduce a check list. A list or table after other
    wording is read as before: the Field | Value table after '11. Verify **Encryption**
    settings:' (4.1.2) is three fields to fill, and the list after 'Confirm **Service
    endpoints** shows:' (2.2.21) does not reach the Expected Result (#246).
  * Checks join the step's single Expected Result, which the runner checks at the end of the
    step, though a check list can describe a blade the step then moves on from: 2.3.19 checks
    the Overview and then opens Record sets; 2.3.20 checks the dev load balancer and ends on
    prod.

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
SUBHEADING = re.compile(r"^####\s")
FENCE = re.compile(r"^[ \t]*(?P<run>`{3,}|~{3,})(?P<info>.*)$")
LIST_ITEM = re.compile(r"^\s*(?:\d+\.|[-*])\s+(?P<text>.+)$")
BOLD = re.compile(r"\*\*(?P<text>(?:\\\*|[^*])+?)\*\*")   # '\*' inside bold is a literal '*'
LIST_FIELD = re.compile(r"^\*\*(?P<label>(?:\\\*|[^*])+?)\*\*\s*:\s*(?P<value>.+)$")
# 'Label: **value**' or 'Label: `value`' with a plain label (#198). The label starts with a
# letter and holds letters of any script, digits, spaces and '()/&-', never '_' ([^\W_] is a
# letter or digit). It is greedy, so a line with no colon fails in linear time. A space must
# follow the colon, so 'https://' never splits there.
PLAIN_LABEL = r"(?P<label>[^\W\d_](?:[^\W_]|[ ()/&-])*):\s+"
PLAIN_FIELD = re.compile("^" + PLAIN_LABEL + r"(?P<span>\*\*(?:\\\*|[^*])+?\*\*|`[^`]+`)(?P<rest>.*)$")
# 'Destination: ...': a chain after such a label is its value and names no resource. Only a colon
# with a space after it ends a label, so 'waiting for 02:00: **Protected items** → ...' (5.2.3)
# keeps its resource; the same text with '2 AM:' would lose it.
PLAIN_LABEL_START = re.compile("^" + PLAIN_LABEL)
CODE = re.compile(r"`(?P<text>[^`]+)`")
# A step of a chain that names a resource to open (#199): one code span, after 'Navigate to',
# 'Go to', 'Open' or 'Select' at most, and before nothing but a remark in parentheses and a full
# stop. 'select the modified `config.txt`' (4.3.6) and 'Name: `common`' (4.3.4) are not. The name
# holds a character other than a space. No two quantifiers that can match the same character
# meet, so a step that fails does so in linear time (two '\s*' around an optional group took 300 s
# on 100,000 spaces).
RESOURCE_STEP = re.compile(
    r"^(?:(?:Navigate|Go)\s+to\s+|Open\s+|Select\s+)?`(?P<name>\s*[^`\s][^`]*)`\s*(?:\([^()]*\)\s*)?\.?$",
    re.IGNORECASE)
PLAIN_LABEL_MAX_WORDS = 6      # the longest plain label in the guides has five words
# A plain label that starts with one of these is an instruction ('Select your VM: `x`'), not a
# Portal label. 'Type' alone is the Portal's Type field (5.3), while 'Type the VMSS name to
# confirm: `x`' is an instruction (3.2). 'Check' is not listed: 'Check every' is a field (5.1).
INSTRUCTION = re.compile(
    r"^(?:Add|Choose|Click|Create|Delete|Download|Enter|Go|Link|Navigate|Open|Remove|Run|Search"
    r"|Select|Wait|Type\s)\b", re.IGNORECASE)
# A field value that starts with one of these, after an optional '(', is an instruction, not
# text to type (value_is_literal). Check and Uncheck count only with a word after them, not a
# remark ('Uncheck (default)'): alone they are a check box state. So is a bare 'Leave checked'
# or 'Leave unchecked'; 'Leave default' is an instruction. 'Create new' is the Portal's own
# option (2.2.10).
VALUE_INSTRUCTION = re.compile(
    r"^\(?\s*(?:Browse|Choose|Click|Enter|Leave(?!\s+(?:un)?checked\s*$)|Paste|Search|Select|Type"
    r"|Create(?!\s+new\b)|(?:Un)?check(?=\s+[^\s(]))\b", re.IGNORECASE)
YOUR = re.compile(r"^Your\s", re.IGNORECASE)     # 'Your subscription': a placeholder without brackets
BRACKET_TOKEN = re.compile(r"\[[^\]]+\]")        # '[yourtenant]', '[IP of dev-skycraft-swc-lb-pip]'
EXPECTED = re.compile(r"^\s*(?:(?:[-*]|\d+\.)\s+)?\*\*Expected Result\*\*[^:]*:(?P<text>.*)$")
# A line whose text, markup stripped, ends with the word 'verify:' introduces a check list (#224).
VERIFY_INTRO = re.compile(r"(?<!\w)verify:\s*$", re.IGNORECASE)
ORDERED_ITEM = re.compile(r"^\s*\d+\.\s")    # a numbered list item, as against a bullet
SENTENCE_END = (".", "!", "?", ":")   # check items follow such a text after a space, not '; '
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


def value_is_literal(value: str) -> bool:
    """Whether a field value is text to type or pick as written (#202). False when it starts with
    an instruction verb (VALUE_INSTRUCTION) or with 'Your', ends with a colon, or holds a bracket
    token; the rules are in the module docstring."""
    text = value.strip()
    return not (VALUE_INSTRUCTION.match(text) or YOUR.match(text) or text.endswith(":")
                or BRACKET_TOKEN.search(text))


def field_item(label: str, value: str, number: int) -> dict:
    """A 'field' item; '"literal": false' is added when the value is not text to type."""
    item = {"kind": "field", "label": label, "value": value, "line": number}
    if not value_is_literal(value):
        item["literal"] = False
    return item


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


def option_regions(body: list[tuple[int, str]]) -> tuple[list[str | int], list[str]]:
    """Where each body line sits, and the name of each option ('1', 'A', 'B') in heading order.

    A line is 'step' when the step has no Option headings; otherwise it is the index of the
    option whose body holds it (0 for the first heading), 'outside' (before the first option,
    or under another '####' heading) or 'heading'."""
    if not any(OPTION_HEADING.match(line) for _, line in body):
        return ["step"] * len(body), []
    regions: list[str | int] = []
    options: list[str] = []
    region: str | int = "outside"
    for _, line in body:
        m = OPTION_HEADING.match(line)
        if m:
            region = len(options)
            options.append(m.group("n"))
            regions.append("heading")
        elif SUBHEADING.match(line):
            region = "outside"
            regions.append("heading")
        else:
            regions.append(region)
    return regions, options


def following_list(body: list[tuple[int, str]], start: int) -> tuple[list[str], int]:
    """The item texts of the list at body[start] (blank lines before it are skipped), markup
    stripped as for values, and the index of the first line after it; start when no list
    follows. The list ends at the first line that is not a list item, a blank line included,
    at an item indented less than the first one (stricter than CommonMark, which keeps an item
    up to three columns less in the list) and at the first one's indent with the other marker
    kind (numbered or bullet): the next numbered step after a nested list. An Expected Result
    line ends it too."""
    position = start
    while position < len(body) and (body[position][1] == HIDDEN or not body[position][1].strip()):
        position += 1
    parts: list[str] = []
    after = start
    first: tuple[int, bool] | None = None       # indent and marker kind of the first item
    while position < len(body):
        line = body[position][1].expandtabs(4)
        if line != HIDDEN:
            li = LIST_ITEM.match(line)
            if not li or EXPECTED.match(line):
                break
            shape = (indent_of(line), bool(ORDERED_ITEM.match(line)))
            if first is None:
                first = shape
            elif shape[0] < first[0] or (shape[0] == first[0] and shape[1] != first[1]):
                break
            parts.append(strip_value_markup(li.group("text")))
            after = position + 1
        position += 1
    return parts, after


def expected_text(body: list[tuple[int, str]], index: int) -> tuple[str, int]:
    """The text of the Expected Result on body[index], and the index of the first line after it.

    The text is what follows the colon. When nothing does, it is the list right after the line
    (blank lines between are allowed): its items joined with '; ', markup stripped as for values.
    When the text itself ends with a colon, the list after it is read the same way and joined
    to the text by join_checks (#224): 'to verify: Name: x; Location: y'.
    """
    text = EXPECTED.match(body[index][1]).group("text").strip()
    if text and not text.endswith(":"):
        return text, index + 1
    parts, after = following_list(body, index + 1)
    if not parts:
        return text, index + 1
    return join_checks(text, parts), after


def join_checks(text: str | None, checks: list[str]) -> str | None:
    """An Expected Result text with check items joined to it (#224): the items with '; '
    between them, after a space when the text ends with sentence punctuation (SENTENCE_END) and
    after '; ' otherwise. The text alone when there are no checks, the checks alone when there
    is no text."""
    if not checks:
        return text
    joined = "; ".join(checks)
    if not text:
        return joined
    return f"{text} {joined}" if text.endswith(SENTENCE_END) else f"{text}; {joined}"


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def check_list(body: list[tuple[int, str]], index: int) -> tuple[list[str], int] | None:
    """The check list that the line body[index] introduces by ending with 'verify:' (#224): its
    item texts, markup stripped as for values, and the index of the first line after it. None
    when the line does not end with 'verify:'.

    After a list item, the check list is the list items indented deeper than it; blank lines
    among them are skipped, so the list ends at the first non-blank line that is not a deeper
    list item, or that is an Expected Result. After any other line, it is the list right after
    the line (following_list).
    """
    line = body[index][1].expandtabs(4)
    li = LIST_ITEM.match(line)
    if not VERIFY_INTRO.search(strip_value_markup(li.group("text") if li else line)):
        return None
    if not li:
        return following_list(body, index + 1)
    depth = indent_of(line)
    parts: list[str] = []
    after = position = index + 1
    while position < len(body):
        current = body[position][1].expandtabs(4)
        if current == HIDDEN or not current.strip():
            position += 1
            continue
        item = LIST_ITEM.match(current)
        if not item or indent_of(current) <= depth or EXPECTED.match(current):
            break                              # read_step reads an Expected Result as usual
        parts.append(strip_value_markup(item.group("text")))
        position += 1
        after = position
    return parts, after


def read_step(body: list[tuple[int, str]]) -> tuple[list[dict], str | None, list[str], str | None]:
    """Items, Expected Result and images of one step section, and the name of the option they
    were read from ('1', 'A', 'B'; None when the step has no Option headings).

    The option is the first one whose body yields at least one item, or the first one when none
    does (#201): 3.2.1's Option A is CLI-only and its Option B is the Portal path.
    """
    regions, options = option_regions(body)
    if not options:
        return (*read_option(body, regions, None), None)
    for index, name in enumerate(options):
        read = read_option(body, regions, index)
        if read[0]:
            return (*read, name)
    return (*read_option(body, regions, 0), options[0])


def read_option(body: list[tuple[int, str]], regions: list[str | int],
                chosen: int | None) -> tuple[list[dict], str | None, list[str]]:
    """Items, Expected Result and images of one step section, read through the option at index
    `chosen` of option_regions (None for a step without Option headings).

    Items come from the whole body, or from the chosen option only. The Expected Result is the
    first one in the step that is not inside another option's body; when there is none, the
    first one in a later option (the standard puts a single one after Option 3), never one in
    an earlier option, which describes that option's path. The items of a check list are read
    where items are; they are joined to the Expected Result (join_checks) or, when the step has
    none, are its Expected Result alone.
    """
    item_lines: list[tuple[int, str]] = []
    expected: str | None = None
    fallback: str | None = None
    checks: list[str] = []
    index = 0
    while index < len(body):
        if EXPECTED.match(body[index][1]):
            text, after = expected_text(body, index)
            in_other = isinstance(regions[index], int) and regions[index] != chosen
            earlier = in_other and chosen is not None and regions[index] < chosen
            if text and not in_other and expected is None:
                expected = text
            elif text and fallback is None and not earlier:
                fallback = text
            index = after
            continue
        if regions[index] == "step" or regions[index] == chosen:
            item_lines.append(body[index])     # the line that introduces a check list is read too
            found = check_list(body, index)
            if found and found[0]:
                checks.extend(found[0])
                index = found[1]
                continue
        index += 1
    items, images = parse_items(item_lines)
    result = expected if expected is not None else fallback
    return items, join_checks(result, checks), images


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
    key, value = clean_label(strip_value_markup(cells[0])), strip_value_markup(cells[1])
    if form == "field":
        return field_item(key, value, number)
    return {"kind": "tag", "name": key, "value": value, "line": number}


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
    return field_item(label, strip_value_markup(m.group("span")), number)


def chain_resources(text: str) -> list[tuple[int, str]]:
    """(offset, name) of each step of the chain in `text` that is a resource name (#199): a code
    span on its own (RESOURCE_STEP). A separator inside a bold or code span does not end a step.
    Nothing for an item that starts with a plain label ('Destination: **X** → `law`'), whose
    chain is the label's value, not a way to a blade."""
    if PLAIN_LABEL_START.match(text):
        return []
    masked = BOLD.sub(lambda m: "*" * len(m.group(0)), text)
    masked = CODE.sub(lambda m: "`" + "x" * len(m.group("text")) + "`", masked)
    bounds = [0] + [at for m in CHAIN.finditer(masked) for at in m.span()] + [len(text)]
    found = []
    for start, end in zip(bounds[::2], bounds[1::2]):
        step = RESOURCE_STEP.match(text[start:end].strip())
        if step:
            found.append((text.index("`", start), step.group("name").strip()))
    return found


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
            return field_item(label, strip_value_markup(value), number)
    field = plain_field(text.strip(), number)
    if field:
        return field
    bold = [(b.start(), clean_label(unescape(b.group("text")))) for b in BOLD.finditer(text)]
    bold = [(at, label) for at, label in bold if is_ui_label(label)]
    chain = bool(CHAIN.search(text))
    # A chain's bold labels and resource names, in the order they appear (#199).
    steps = sorted([(at, label, False) for at, label in bold]
                   + [(at, name, True) for at, name in (chain_resources(text) if chain else [])])
    if chain and len(steps) > 1:
        item = {"kind": "navigation", "labels": [label for _, label, _ in steps]}
        resources = [index for index, (_, _, resource) in enumerate(steps) if resource]
        if resources:
            item["resources"] = resources
        item["line"] = number
        return item
    if not bold:
        return None
    return {"kind": "action", "labels": [label for _, label in bold], "line": number}


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
        items, expected, images, option = read_step(raw["body"])
        step = {"id": raw["id"], "title": raw["title"], "line": raw["line"]}
        if option is not None:
            step["option"] = option          # only a step with Option headings carries it
        step.update(portal=bool(items), items=items, expected=expected, images=images)
        steps.append(step)
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
