# Guide Drift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** issue #189. This file is the implementation plan for that issue. It lives at the root of
branch `feature/guide-drift`, is ticked off in commits as the work progresses, and is deleted in the
PR's last commit (Task 13), so it never reaches `main`.

**Goal:** An on-demand tool, `tools/Invoke-GuideDrift.ps1`, that performs one lab guide's portal
steps in a visible browser, checks every step against the live Azure Portal, and reports what no
longer matches. First lab: 1.1.

**Architecture:** A PowerShell entry point (same shape as `tools/Invoke-LabCycle.ps1`: mandatory
`-SubscriptionId` compared by id, JSONL results, state file, `-Resume`, gitignored logs) drives
three Python files under `tools/guide-drift/`: `parse.py` turns a guide into step JSON using the
standard library only, so CI can test it without a browser; `run.py` drives Chromium through
Playwright and performs the steps; `decide.py` is the one boundary every "label not found"
decision passes through, with two implementations: replay from a committed recording, and ask the
person at the keyboard. Every decision is written back to the recording, so the next run asks less.

**Tech Stack:** PowerShell 7 + Pester 5 (CI on `ubuntu-latest`, `python3` 3.12 preinstalled),
Python 3.10+ standard library for the parser, Playwright for Python (`playwright>=1.49`, needed
for `aria_snapshot`) for the runner. Az.Accounts for the subscription check. Nothing new in CI.

**Conventions that apply:** `docs/powershell-standards.md` (comment-based help with `.SYNOPSIS`,
`.DESCRIPTION`, `.NOTES`; `#Requires -Version 7.0`; `[CmdletBinding()]`;
`$ErrorActionPreference = 'Stop'`; no aliases), enforced for every `tools/*.ps1` by
`tests/Script-Standards.Tests.ps1` and `tests/Cbh-Coverage.Tests.ps1`. Pester 5 test files compute
`-ForEach` case data at discovery time (file scope); everything else an `It` block reads
(fixtures, helpers, parsed results) comes from a `BeforeAll` as `$script:` variables, because
file-scope variables are not visible in the run phase. Parser output is always read through
`--out <file>` with `Get-Content -Raw -Encoding utf8`, never from stdout: on Windows a piped
stdout is decoded with the console code page, and guides contain `→`, `✅`, `☐`. Commit titles are
Conventional Commits (release-please). Every artifact is in English. No `Co-Authored-By` lines.
All work happens in the worktree `C:\2_Areas\Repositories\mbiszczanik\skycraft-guide-drift`
(branch `feature/guide-drift`, created from `origin/main` at `7f7622f`, upstream unset); never
commit in the main checkout.

**Verification commands used throughout** (run from the worktree root):

```powershell
Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests -Output Normal          # whole suite, ~1 min
./tools/Invoke-DryRun.ps1                           # parse + analyzer + bicep, mirrors CI
```

On Windows the Python interpreter is `python`; on the Linux CI runner it is `python3`. The tests
and the entry point both resolve it with the same rule (`if ($IsWindows) { 'python' } else { 'python3' }`).

---

## File structure

```text
tools/Invoke-GuideDrift.ps1                   entry point; resolves lab, checks Python, guards the
                                              subscription, runs parse.py then run.py, hands off
                                              to the lab's own cleanup, exits with the run's code
tools/guide-drift/parse.py                    guide markdown -> steps JSON (stdlib only)
tools/guide-drift/decide.py                   Decision, ReplayDecider, HumanDecider, decide()
tools/guide-drift/run.py                      Playwright runner: browser, guards, steps, results
tools/guide-drift/requirements.txt            playwright>=1.49
tools/guide-drift/recordings/lab-1.1.json     committed recording (seeded in Task 6, filled in Task 12)
tests/Guide-Drift-Parser.Tests.ps1            parser against fixtures and all 17 guides
tests/Guide-Drift-Recording.Tests.ps1         every recording refers only to steps/labels the parser finds

modified:
.gitignore                                    + tools/guide-drift-logs/, tools/.guide-drift-state.json,
                                                tools/.guide-drift-auth.json
tests/Gitignore.Tests.ps1                     + the three paths above; + the tool stays tracked
CONTRIBUTING.md                               + one sentence: a guide edit that changes a portal label
                                                updates the lab's recording in the same PR
```

### Data shapes (defined once here, used by every task)

**Steps JSON** (`parse.py` output):

```json
{
  "lab": "1.1",
  "guide": "module-1-identities-governance/1.1-entra-users-groups/lab-guide-1.1.md",
  "images": [ { "path": "images/Step-1.1.7.png", "width": 2279 } ],
  "steps": [
    {
      "id": "1.1.6",
      "title": "Create First Group (Admins)",
      "line": 152,
      "portal": true,
      "items": [
        { "kind": "navigation", "labels": ["Groups", "All groups"], "line": 154 },
        { "kind": "action",     "labels": ["+ New group"],          "line": 155 },
        { "kind": "field", "label": "Group type", "value": "Security", "line": 160 },
        { "kind": "field", "label": "Group name", "value": "SkyCraft-Admins", "line": 161 }
      ],
      "expected": null,
      "images": []
    }
  ]
}
```

A `Name | Value` or `Tag | Value` table is a list of tags, not labelled fields: each row is
`{ "kind": "tag", "name": "Environment", "value": "Development", "line": 200 }`, typed into the
Portal's Tags grid by row (Task 4 parses it, Task 8 fills it).

`line` is 1-based and points at the guide line the item came from, so a proposed edit can name it.
`images` at the root is every `*.png` under the guide's `images/` directory with its pixel width;
`images` per step is the paths referenced inside that step's section.

**Recording** (`tools/guide-drift/recordings/lab-X.Y.json`, committed):

```json
{
  "lab": "1.1",
  "guide": "module-1-identities-governance/1.1-entra-users-groups/lab-guide-1.1.md",
  "portalLanguage": "en",
  "viewport": [1440, 900],
  "placeholders": { "[yourtenant]": "${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}" },
  "steps": {
    "1.1.5": {
      "valueOverrides": { "Email": "${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}" },
      "viewUrl": null,
      "result": null,
      "labels": {}
    },
    "1.1.6": {
      "valueOverrides": {},
      "viewUrl": "https://portal.azure.com/#view/Microsoft_AAD_IAM/GroupsManagementMenuBlade/~/AllGroups",
      "result": { "text": "SkyCraft-Admins" },
      "labels": {
        "Groups": { "decision": "use", "role": "link", "name": "Groups", "severity": null,
                    "rejected": ["Groups (preview)"], "decidedBy": "human", "at": "2026-10-07T10:00:00Z" },
        "+ New group": { "decision": "use", "role": "button", "name": "New group", "severity": "misleading",
                         "rejected": [], "decidedBy": "human", "at": "2026-10-07T10:01:00Z" }
      }
    }
  }
}
```

`${NAME}` in a placeholder or override value is expanded from the environment by `run.py` at the
moment the value is typed; a missing variable stops the run before the step. That keeps the
maintainer's guest address and tenant prefix out of this public repository. `labels` is keyed by
the guide's label text; `decision` is `use` (act on the element named `name`; when `name`
differs from the label the recorded `severity`, misleading or cosmetic, is reported as drift),
`ignore` (the bold text is not a UI element in this step) or `gone` (the element no longer
exists; replay reports blocking drift without asking). An `unknown` answer is never recorded. `asked` lists the questions already put to the person for this step (today only `"result"`), so
an answer of "nothing observable" is not asked again. Names and texts in a recording carry
`[tenantdomain]` and `[tenantid]` instead of the real values (the runner's `Redactor`), and
`viewUrl` has no tenant pin, query string or object id.
`result` is `null` when the expected result names nothing
observable, or `{ "text": "..." }` for text the runner looks for after the step.

**Result record** (`<log dir>/<run id>/results.jsonl`, one line per check):

```json
{ "runId": "20261007-100000", "at": "2026-10-07T10:02:11Z", "lab": "1.1", "step": "1.1.6",
  "kind": "action", "label": "+ New group", "outcome": "drift", "severity": "misleading",
  "category": null, "skippedBecause": null, "observed": "New group",
  "proposedEdit": { "line": 155, "old": "2. Click **+ New group**", "new": "2. Click **New group**" },
  "screenshot": "Step-1.1.6.png" }
```

`kind` is `navigation | action | field | tag | result | screenshot | readability`. `outcome` is
`match | drift | unknown | skipped`. `severity` is `blocking | misleading | cosmetic | null`.
`category` is `stale` (a `screenshot` record for a step that has both an image and a drift) or
`unreadable` (a `readability` record for an image wider than 1722 px), otherwise `null`. Exit code
of the run = count of `blocking` drifts + count of `unknown`, capped at 250.

**Decision** (`decide.py`):

```python
@dataclass
class Decision:
    kind: str                  # "use" | "drift" | "ignore" | "unknown"
    name: str | None = None    # accessible name to act on (use), or observed text (drift)
    role: str | None = None
    severity: str | None = None  # drift only: "blocking" | "misleading" | "cosmetic"
    reason: str | None = None    # unknown only
    decided_by: str = "human"    # "exact" | "replay" | "human"
```

---

### Task 1: Gitignore the run artefacts

**Files:**

- Modify: `.gitignore` (after line 85, the lab cycle block)
- Modify: `tests/Gitignore.Tests.ps1` (inside `Describe '.gitignore - required ignore patterns'`)

- [x] **Step 1: Write the failing tests**

Add after the `It 'ignores every lab cycle run artefact'` block in `tests/Gitignore.Tests.ps1`:

```powershell
    It 'ignores every guide drift run artefact' {
        # Screenshots show the tenant name, user principal names and the subscription id; the saved
        # sign-in state is a session. Only the recording under tools/guide-drift/recordings/ is
        # committed (issue #189).
        $artefacts = @(
            'tools/guide-drift-logs/20261007-100000/results.jsonl'
            'tools/guide-drift-logs/20261007-100000/Step-1.1.6.png'
            'tools/.guide-drift-state.json'
            'tools/.guide-drift-auth.json'
        )
        Push-Location $script:RepoRoot
        try {
            foreach ($artefact in $artefacts) {
                git check-ignore -q $artefact
                $LASTEXITCODE | Should -Be 0 -Because "$artefact is a run artefact and must never reach history"
            }
        } finally { Pop-Location }
    }
```

And extend the `foreach ($tracked in ...)` list in `It 'does not ignore the orchestrator itself'`:

```powershell
            foreach ($tracked in 'tools/Invoke-LabCycle.ps1', 'tools/Remove-LabCycle.ps1', 'tools/lab-cycle-manifest.psd1',
                                 'tools/Invoke-GuideDrift.ps1', 'tools/guide-drift/parse.py', 'tools/guide-drift/recordings/lab-1.1.json') {
```

- [x] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path ./tests/Gitignore.Tests.ps1 -Output Detailed`
Expected: `ignores every guide drift run artefact` FAILS (exit code 1 from `git check-ignore`).

- [x] **Step 3: Add the patterns**

Append to `.gitignore` directly after the `tools/.lab-cycle-state.json` line:

```gitignore

# Guide drift run artefacts (issue #189): screenshots and results carry tenant names, UPNs and
# the subscription id; the auth file is a browser session. Recordings are committed, these are not.
tools/guide-drift-logs/
tools/.guide-drift-state.json
tools/.guide-drift-auth.json
```

- [x] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path ./tests/Gitignore.Tests.ps1 -Output Detailed`
Expected: all green, including `does not ignore the orchestrator itself` (the three new tracked
paths do not exist yet, but `git check-ignore` answers from patterns, not from the tree).

- [x] **Step 5: Commit**

```powershell
git add .gitignore tests/Gitignore.Tests.ps1
git commit -m "chore(guide-drift): gitignore the run artefacts of the guide drift tool"
```

---

### Task 2: Parser core: step sections, fences, Option 1, bold labels

**Files:**

- Create: `tools/guide-drift/parse.py`
- Create: `tests/Guide-Drift-Parser.Tests.ps1`

The parser is a command line tool: `python parse.py <guide.md>` prints the steps JSON to stdout.
The tests write a fixture guide to a temp file, call the parser, and read the JSON back.

- [x] **Step 1: Write the failing fixture tests**

Create `tests/Guide-Drift-Parser.Tests.ps1` (four backticks below because the fixture itself
contains a code fence):

````powershell
<#
.SYNOPSIS
    Pester 5 tests for tools/guide-drift/parse.py, the guide-to-steps parser of the guide drift tool.

.DESCRIPTION
    The parser is Python standard library only, so this suite runs on the ubuntu-latest runner
    without a browser. Two kinds of test:

      FIXTURES - small guides written here, parsed through a temp file, asserting the rules of
      issue #189: only '### Step X.Y.N:' sections are read; fenced code is skipped; where a step
      has '#### Option N:' headings only Option 1 is read (plus the step's Expected Result);
      bold spans that are not UI elements are dropped; 'A -> B' chains become navigation;
      Field | Value tables become fields; images are collected with their pixel width.

      THE 17 GUIDES - every module-*/X.Y-*/lab-guide-X.Y.md parses, its step ids match its
      headings in order, and every step marked portal has at least one label. This does NOT
      enforce the multi-modal structure of docs/lab-guide-standards.md section 5; only 3 guides
      use it today.

    Cases are computed at discovery time (file scope), as every suite in this directory does.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Drift-Parser.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #189
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Parser   = Join-Path $RepoRoot 'tools/guide-drift/parse.py'
$Python   = if ($IsWindows) { 'python' } else { 'python3' }

# Parses markdown text through a temp file and returns the steps object. Images are resolved
# relative to the temp file's directory, so fixtures that need images create them beside it.
function ConvertFrom-GuideFixture {
    param([string]$Markdown, [string]$Directory = (Join-Path ([System.IO.Path]::GetTempPath()) ("guide-drift-" + [guid]::NewGuid())))
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $guide = Join-Path $Directory 'lab-guide-9.9.md'
    Set-Content -LiteralPath $guide -Value $Markdown -Encoding utf8 -NoNewline
    $json = & $Python $Parser $guide 2>&1
    if ($LASTEXITCODE -ne 0) { throw "parse.py failed: $json" }
    ($json -join "`n") | ConvertFrom-Json
}

$CoreFixture = @'
# Lab 9.9: Fixture

**Situation**: bold outside any step is ignored.

### Step 9.9.1: Navigate and act

1. In the left sidebar, click **Users** → **All users**
2. Click **+ New user** → **Create new user**
3. Search for **"Microsoft Entra ID"** in the search bar
4. **Note**: a **Tip** is not a UI element, nor is **Important** or **Why** or **SkyCraft Choice** or **Remember:**

```powershell
Write-Host "**InFence** is never read"
```

**Expected Result**: New user appears in the list.

### Step 9.9.2: Options

#### Option 1: Azure Portal (GUI)

1. Navigate to **Storage accounts**
2. Click **+ File share**

#### Option 2: Azure CLI

1. Run **OnlyInCli** here

**Expected Result**: Share appears.

### Step 9.9.3: No portal part

1. Run the script and read the output.

## Checklist

- [ ] **NotAStep** bold after the last step is ignored
'@

$Core = ConvertFrom-GuideFixture -Markdown $CoreFixture

Describe 'parse.py - step sections' {
    It 'reads exactly the "### Step X.Y.N:" sections, in order' {
        @($Core.steps.id) | Should -Be @('9.9.1', '9.9.2', '9.9.3')
        $Core.steps[0].title | Should -Be 'Navigate and act'
        $Core.lab | Should -Be '9.9'
    }

    It 'splits an arrow chain into one navigation item with several labels' {
        $nav = $Core.steps[0].items[0]
        $nav.kind | Should -Be 'navigation'
        @($nav.labels) | Should -Be @('Users', 'All users')
        $nav.line | Should -Be 7    # line 1 is the title, line 5 the step heading, line 7 the first item
    }

    It 'keeps a leading "+" in a label and strips surrounding quotes' {
        @($Core.steps[0].items[1].labels) | Should -Be @('+ New user', 'Create new user')
        @($Core.steps[0].items[2].labels) | Should -Be @('Microsoft Entra ID')
        $Core.steps[0].items[2].kind | Should -Be 'action'
    }

    It 'drops bold spans that are not UI elements, and bold inside code fences' {
        $labels = @($Core.steps[0].items | ForEach-Object { $_.labels })
        @($Core.steps[0].items).Count | Should -Be 3 -Because 'the Note item has no UI label left and is dropped'
        foreach ($notUi in 'Note', 'Tip', 'Important', 'Why', 'SkyCraft Choice', 'Remember:', 'InFence', 'Expected Result') {
            $labels | Should -Not -Contain $notUi
        }
    }

    It 'captures the Expected Result text' {
        $Core.steps[0].expected | Should -Be 'New user appears in the list.'
    }

    It 'reads only Option 1 of a multi-option step, plus its Expected Result' {
        $labels = @($Core.steps[1].items | ForEach-Object { $_.labels })
        $labels | Should -Be @('Storage accounts', '+ File share')
        $Core.steps[1].expected | Should -Be 'Share appears.'
    }

    It 'marks a step with no UI element as portal: false' {
        $Core.steps[2].portal | Should -BeFalse
        $Core.steps[0].portal | Should -BeTrue
    }

    It 'ignores bold text before the first step and after the last section' {
        $all = @($Core.steps | ForEach-Object { $_.items } | ForEach-Object { $_.labels })
        $all | Should -Not -Contain 'Situation'
        $all | Should -Not -Contain 'NotAStep'
    }
}
````

- [x] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed`
Expected: discovery throws `parse.py failed` (file not found). That is the failing state.

- [x] **Step 3: Write the parser core**

Create `tools/guide-drift/parse.py`:

```python
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
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed`
Expected: 8 passed. If `Microsoft Entra ID` comes back with quotes, check `clean_label`
handles the curly quotes the guide uses (`“ ”`) as well as straight ones.

- [x] **Step 5: Commit**

```powershell
git add tools/guide-drift/parse.py tests/Guide-Drift-Parser.Tests.ps1
git commit -m "feat(guide-drift): parse lab guide steps into labels, chains and options"
```

---

### Task 3: Parser: form tables only, HTML comments, images and widths

**Files:**

- Modify: `tests/Guide-Drift-Parser.Tests.ps1` (append a Describe)
- Modify: `tools/guide-drift/parse.py`

**Why this task changed after review of Task 2.** The Task 2 parser turns *every* table into
`field` items. A survey of the 17 guides shows ~70 table shapes, of which only these are forms a
learner fills in: `Field | Value` (108), `Name | Value` (15), `Tag | Value` (3),
`Property | Value` (1), `Parameter | Value | ...` (1), `Field | Value | Notes` (1). Everything
else is informational (`Subnet Name | Starting Address | Size`, `Issue | Why It Happens | Fix`,
`Scenario | Expected Behavior`, `Property | Expected Value`, ...), and the runner would try to type
into it. Rule: **a table is a form only when its second header cell, with markup stripped, is
exactly `Value` (case-insensitive)**. Also: a commented-out row in 4.1.8 currently yields the field
label `<!--`; HTML comments are invisible to learners and must be removed like fenced code; and
field labels keep backticks today (values already strip them).

**Pester 5 scoping (learned in Task 2).** File-scope variables and functions are visible during
discovery only; `It` blocks cannot see them. Fixtures and helpers that `It` blocks use go in a
`BeforeAll` and are stored as `$script:` variables. The file already has a file-level `BeforeAll`
defining `ConvertFrom-GuideFixture` (it takes `-Markdown` and an optional `-Directory`, runs
`parse.py <guide> --out <tmp>` and reads the JSON as UTF-8); a Describe-level `BeforeAll` can call
it. Use `$TestDrive` for temporary files. Check the helper's actual signature in the file before
using it.

- [x] **Step 1: Write the failing tests**

Append to `tests/Guide-Drift-Parser.Tests.ps1`:

```powershell
Describe 'parse.py - form tables, HTML comments and images' {
    BeforeAll {
        # A PNG header is enough: parse.py reads the width from IHDR (bytes 16..19) and never decodes.
        function New-PngFixture {
            param([string]$Path, [int]$Width)
            $widthBytes = [System.BitConverter]::GetBytes([int32]$Width)
            [array]::Reverse($widthBytes)   # IHDR is big-endian
            $bytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52) +
                     $widthBytes + [byte[]](0, 0, 0, 1, 8, 2, 0, 0, 0)
            [System.IO.File]::WriteAllBytes($Path, $bytes)
        }

        $tableFixture = @'
# Lab 9.9: Tables

### Step 9.9.1: Fill a form

1. Click **+ New group**
2. Fill in:

| Field             | Value                     |
| ----------------- | ------------------------- |
| Group type        | Security                  |
| `Group name`      | `SkyCraft-Admins`         |
<!-- | Hidden field | never read | -->
| Tier              | **Hot**                   |

3. Click **Create**

<!--
1. Click **CommentedOut**
-->

![Create group](./images/Step-9.9.1.png)
![Other](images/Step-9.9.1b.png)

### Step 9.9.2: Informational tables are not forms

| Subnet Name | Starting Address | Size |
| ----------- | ---------------- | ---- |
| AppSubnet   | 10.0.1.0         | /24  |

| Property  | Expected Value |
| --------- | -------------- |
| Location  | swedencentral  |

| Name   | Value        | Notes                       |
| ------ | ------------ | --------------------------- |
| Region | `westeurope` | three columns, still a form |

1. Click **Review + create**
'@
        $dir = Join-Path $TestDrive 'tables'
        New-Item -ItemType Directory -Path (Join-Path $dir 'images') -Force | Out-Null
        New-PngFixture -Path (Join-Path $dir 'images/Step-9.9.1.png') -Width 861
        New-PngFixture -Path (Join-Path $dir 'images/Step-9.9.1b.png') -Width 2279
        $script:Table = ConvertFrom-GuideFixture -Markdown $tableFixture -Directory $dir
    }

    It 'turns Field | Value rows into fields, stripping markup from label and value' {
        $fields = @($script:Table.steps[0].items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Group type', 'Group name', 'Tier')
        @($fields.value) | Should -Be @('Security', 'SkyCraft-Admins', 'Hot')
    }

    It 'keeps actions before and after the table in document order' {
        @($script:Table.steps[0].items.kind) | Should -Be @('action', 'field', 'field', 'field', 'action')
        @($script:Table.steps[0].items[4].labels) | Should -Be @('Create')
    }

    It 'never reads text inside an HTML comment' {
        $all = @($script:Table.steps | ForEach-Object { $_.items } | ForEach-Object { if ($_.kind -eq 'field') { $_.label } else { $_.labels } })
        $all | Should -Not -Contain 'Hidden field'
        $all | Should -Not -Contain 'CommentedOut'
        @($all | Where-Object { $_ -like '<!--*' }) | Should -BeNullOrEmpty
    }

    It 'treats only tables whose second header is "Value" as forms' {
        $fields = @($script:Table.steps[1].items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Region') -Because 'Subnet Name | Starting Address and Property | Expected Value are informational'
        $fields[0].value | Should -Be 'westeurope'
    }

    It 'collects the images a step references, with and without "./"' {
        @($script:Table.steps[0].images) | Should -Be @('images/Step-9.9.1.png', 'images/Step-9.9.1b.png')
    }

    It 'lists every PNG under images/ with its pixel width' {
        $widths = @{}
        foreach ($image in $script:Table.images) { $widths[$image.path] = $image.width }
        $widths['images/Step-9.9.1.png']  | Should -Be 861
        $widths['images/Step-9.9.1b.png'] | Should -Be 2279
    }
}
```

- [x] **Step 2: Run the tests to verify they fail for the right reasons**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed"`
Expected: the earlier tests still pass; in the new Describe, `turns Field | Value rows` fails
(label `` `Group name` `` keeps backticks), `never reads text inside an HTML comment` fails, and
`treats only tables whose second header is "Value"` fails (informational rows become fields).
The image tests pass already. Quote the failures in your report.

- [x] **Step 3: Implement in parse.py**

1. HTML comments: extend `strip_fences` (rename it `strip_hidden`, update its caller and
   docstring) so that, outside fenced code, any text between `<!--` and `-->` is blanked,
   including comments spanning several lines and a comment that occupies part of a line. Line
   numbers must stay stable (a fully hidden line becomes `""`; a partly commented line keeps
   the text outside the comment).
2. Form tables: in `parse_items`, when a table's header row is read, decide whether it is a
   form: the second header cell, after `strip_value_markup`, equals `value` case-insensitively.
   Rows of a non-form table are skipped. A blank or non-table line ends a table, as now.
3. Field labels: pass the first cell through `strip_value_markup` and then `clean_label`, so
   backticks and bold are removed from labels as from values.
4. Update the module docstring: "'Field | Value' tables" becomes "tables whose second header
   cell is 'Value' (Field | Value, Name | Value, Tag | Value, ...)", and say that HTML comments
   are removed together with fenced code.

- [x] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed"`
Expected: all green.

Then confirm the real guide kept its forms: parse lab 1.1 with `--out` and check step 1.1.6
still has the fields `Group type`, `Group name`, `Group description`, `Membership type`, and
step 1.1.10 has `Job title`, `Department`, `Office`, `Manager` (header `Property | Value`).

- [x] **Step 5: Commit**

```powershell
git add tests/Guide-Drift-Parser.Tests.ps1 tools/guide-drift/parse.py PLAN.md
git commit -m "feat(guide-drift): read only form tables and ignore HTML comments in guides"
```

---

### Task 4: Parser: real-guide forms, then all 17 guides

**Files:**

- Modify: `tests/Guide-Drift-Parser.Tests.ps1` (append Describes)
- Modify: `tools/guide-drift/parse.py`

**Why this task changed after review of Task 2.** Running the parser over the 17 real guides
showed these gaps, each with a real example:

| Gap | Real example | Today |
|---|---|---|
| Fields written as list items `- **Label**: value` (104 in-step items, 3.3/3.4/1.3/5.x) | 3.3:215 `- **Region**: **Sweden Central**` | becomes an action that clicks both bold spans |
| Escaped asterisk in bold, Portal's required-field marker | 3.3:216 `**\*Deployment source**: **Container Image**` | whole item dropped |
| Expected Result inside a list item, or with a qualifier before the colon | 1.3:144 `6. **Expected Result**: Shows ...`; 2.2:607 `**Expected Result** (if ...):` | missed |
| Several Expected Results in one step (one per option) | probe | the last one wins; Option 1's should |
| Lettered options | 3.2:219 `#### Option A:` / `#### Option B:` | both options read |
| Tag tables: every `Name \| Value` and `Tag \| Value` table (72 fields in 8 guides) follows "click **Tags**" | 1.3 `Add the following tags: \| Name \| Value \| Environment \| Development \|` | emitted as fields labelled `Environment`, `Project`; the runner would look for a control with that label 72 times |
| Fence closing | a 4-backtick fence containing a 3-backtick one | inner content leaks; CommonMark closes only on a run of the same character at least as long as the opener, followed by nothing but whitespace |

**Pester 5 scoping and encoding (learned in Task 2).** `-ForEach` case data is built at file
scope during discovery, so anything the case list needs (repo root, interpreter, parser path, a
discovery-time helper) must be defined at file scope, as `tests/Guide-Step-Numbering.Tests.ps1`
does; the file-level `BeforeAll` from Task 2 is not run at discovery. Values `It` blocks need
beyond the case data go in a `BeforeAll` as `$script:` variables. Always read parser output
through `--out <file>` and `Get-Content -Raw -Encoding utf8`, never from stdout: on Windows a
piped stdout is decoded with the console code page and real guides contain `→`, `✅`, `☐`.
`$TestDrive` exists only in the run phase; at discovery use a temp file from
`[System.IO.Path]::GetTempFileName()` and delete it.

- [x] **Step 1: Write the failing fixture tests**

Append to `tests/Guide-Drift-Parser.Tests.ps1`:

`````powershell
Describe 'parse.py - forms and markers found in the real guides' {
    BeforeAll {
        $fixture = @'
# Lab 9.9: Real-guide shapes

### Step 9.9.1: List-item fields

1. Click **+ Create** → **Container App**
2. On the **Basics** tab:
   - **Resource group**: `dev-skycraft-swc-rg`
   - **Region**: **Sweden Central**
   - **\*Deployment source**: **Container Image**
   - **Note**: this is a caption, not a field
3. **Expected Result**: The app is created.

**Expected Result** (if the quota allows): A second result that must not win.

### Step 9.9.2: Lettered options

#### Option A: Portal

1. Click **Generate new key pair**

**Expected Result**: Option A result.

#### Option B: Store the key in Azure

1. Click **OnlyInOptionB**

**Expected Result**: Option B result.

### Step 9.9.3: Long fences

````markdown
```bash
echo inner
```
1. Click **LeakedFromFence**
````

1. Click **AfterFence**

### Step 9.9.4: Tags

1. Click **Tags**

| Name        | Value         |
| ----------- | ------------- |
| Environment | `Development` |
| Project     | SkyCraft      |

| Field | Value  |
| ----- | ------ |
| Owner | `ops`  |
'@
        $script:Real = ConvertFrom-GuideFixture -Markdown $fixture
    }

    It 'reads "- **Label**: value" list items as fields' {
        $fields = @($script:Real.steps[0].items | Where-Object kind -eq 'field')
        @($fields.label) | Should -Be @('Resource group', 'Region', 'Deployment source')
        @($fields.value) | Should -Be @('dev-skycraft-swc-rg', 'Sweden Central', 'Container Image')
    }

    It 'does not turn a caption such as **Note** into a field' {
        @($script:Real.steps[0].items | Where-Object { $_.kind -eq 'field' -and $_.label -eq 'Note' }) | Should -BeNullOrEmpty
    }

    It 'keeps chains and actions around list-item fields' {
        @($script:Real.steps[0].items[0].labels) | Should -Be @('+ Create', 'Container App')
        $script:Real.steps[0].items[0].kind | Should -Be 'navigation'
        @($script:Real.steps[0].items[1].labels) | Should -Be @('Basics')
    }

    It 'takes the first Expected Result, including one written as a list item' {
        $script:Real.steps[0].expected | Should -Be 'The app is created.'
    }

    It 'reads only Option A of a lettered-option step, and its own Expected Result' {
        $labels = @($script:Real.steps[1].items | ForEach-Object { $_.labels })
        $labels | Should -Be @('Generate new key pair')
        $script:Real.steps[1].expected | Should -Be 'Option A result.'
    }

    It 'reads Name | Value and Tag | Value tables as tag pairs, and Field | Value as fields' {
        $items = @($script:Real.steps[3].items)
        @($items.kind) | Should -Be @('action', 'tag', 'tag', 'field')
        @(($items | Where-Object kind -eq 'tag').name)  | Should -Be @('Environment', 'Project')
        @(($items | Where-Object kind -eq 'tag').value) | Should -Be @('Development', 'SkyCraft')
        ($items | Where-Object kind -eq 'field').label  | Should -Be 'Owner'
    }

    It 'closes a fence only on a run at least as long as its opener' {
        $labels = @($script:Real.steps[2].items | ForEach-Object { $_.labels })
        $labels | Should -Not -Contain 'LeakedFromFence'
        $labels | Should -Contain 'AfterFence'
    }
}
`````

Note the five-backtick fence around this block in the plan: the fixture itself contains a
four-backtick and a three-backtick fence. The PowerShell here-string carries them verbatim.

- [x] **Step 2: Run the tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed"`
Expected: every new test except possibly `does not turn a caption` fails, each for the gap in
the table above. Quote the failures.

- [x] **Step 3: Implement in parse.py**

1. `BOLD`: accept an escaped asterisk inside bold, `\*\*(?P<text>(?:\\\*|[^*])+?)\*\*`, and
   unescape `\*` to `*` in the captured text. In `clean_label`, strip a leading `*` (the
   Portal's required-field marker) and surrounding whitespace.
2. List-item fields: before the action/navigation branch, if the list item text matches
   `^\*\*(?P<label>(?:\\\*|[^*])+?)\*\*\s*:\s*(?P<value>.+)$` and the cleaned label is a UI label
   (`is_ui_label`), emit `{"kind": "field", "label": <clean label>, "value": <value through
   strip_value_markup, trailing '.' removed>, "line": n}`. If the label is `Expected Result`,
   treat the line as the Expected Result (rule 3). Otherwise fall through to the existing
   bold-span handling, which drops captions.
   Add to the module docstring: a field whose value is prose rather than a literal ("Click the
   ... button", "1 month from now") is typed as written; the recording's `valueOverrides` is
   where a supervised run supplies the literal.
3. Expected Result: match `^\s*(?:(?:[-*]|\d+\.)\s+)?\*\*Expected Result\*\*[^:]*:\s*(?P<text>.+?)\s*$`
   and keep the FIRST match in the step (do not overwrite).
4. Options: `OPTION_HEADING` accepts `#### Option 1:` and `#### Option A:`; the first option is
   `1` or `A`. With options present, keep the Option-1/A body plus Expected Result lines from
   outside the other options' bodies OR, when Option 1/A has none, the first Expected Result
   anywhere in the step (the standard places a single one after Option 3). Make the
   `Option A result.` test and the Task 2 `Share appears.` test both pass.
5. Tags: a form table whose first header cell (markup stripped, case-insensitive) is `name` or
   `tag` emits `{"kind": "tag", "name": <first cell, cleaned like a label>, "value": <second
   cell through strip_value_markup>, "line": n}` per row; `field`, `property` and `setting`
   tables keep emitting fields. A step whose only items are tags is still `portal: true`.
   Document the tag kind in the module docstring.
6. Fences: in `strip_hidden`, record the opener's character and run length; close only on a line
   whose fence run uses the same character, is at least as long, and is followed only by
   whitespace (no info string).

- [x] **Step 4: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed"`
Expected: all green, including every Task 2 and Task 3 test.

- [x] **Step 5: Commit the parser hardening**

```powershell
git add tests/Guide-Drift-Parser.Tests.ps1 tools/guide-drift/parse.py PLAN.md
git commit -m "feat(guide-drift): read list-item fields, lettered options and long fences from guides"
```

- [x] **Step 6: Write the 17-guide tests**

Append to `tests/Guide-Drift-Parser.Tests.ps1`:

```powershell
# Discovery-time state for the per-guide cases. The file-level BeforeAll does not run at
# discovery, so these are defined here at file scope, as Guide-Step-Numbering.Tests.ps1 does.
$DiscoveryRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$DiscoveryParser   = Join-Path $DiscoveryRepoRoot 'tools/guide-drift/parse.py'
$DiscoveryPython   = if ($IsWindows) { 'python' } else { 'python3' }

# The step regex is the one tests/Guide-Step-Numbering.Tests.ps1 uses, narrowed to '###', so the
# parser is held to the same reading of a guide as the numbering test.
$GuideCases = Get-ChildItem -Path $DiscoveryRepoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+-' } |
    ForEach-Object {
        $num   = [regex]::Match($_.Name, '^\d+\.\d+').Value
        $guide = Join-Path $_.FullName "lab-guide-$num.md"
        if (-not (Test-Path -LiteralPath $guide)) { return }
        $text  = Get-Content -Raw -LiteralPath $guide
        $text  = [regex]::Replace($text, '(?ms)^[ \t]*(`{3,}|~{3,}).*?^[ \t]*\1[ \t]*\r?$', '')
        # Closed HTML comments only (non-greedy): an unclosed '<!--' leaves later headings counted
        # here while the parser hides them, so the id comparison below catches it.
        $text  = [regex]::Replace($text, '(?s)<!--.*?-->', '')
        $headingIds = @([regex]::Matches($text, '(?m)^###[ \t]+Step[ \t]+(\d+\.\d+\.\d+):') | ForEach-Object { $_.Groups[1].Value })
        $out = [System.IO.Path]::GetTempFileName()
        try {
            $stderr = & $DiscoveryPython $DiscoveryParser $guide --out $out --repo-root $DiscoveryRepoRoot 2>&1
            $exit   = $LASTEXITCODE
            $parsed = if ($exit -eq 0) { Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json }
        } finally { Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue }
        $fieldLabels = @($parsed.steps | ForEach-Object { $_.items } | Where-Object kind -eq 'field' | ForEach-Object label)
        @{
            lab         = $num
            exitCode    = $exit
            output      = ($stderr -join "`n")
            headingIds  = $headingIds
            parsedIds   = @($parsed.steps.id)
            emptyPortal = @($parsed.steps | Where-Object { $_.portal -and @($_.items).Count -eq 0 } | ForEach-Object id)
            badFields   = @($fieldLabels | Where-Object { $_ -match '^<!--|`|\*\*' })
            guidePath   = $parsed.guide
        }
    }

Describe 'parse.py - every lab guide' {
    It 'has guides to check' -ForEach @(@{ count = @($GuideCases).Count }) {
        $count | Should -Be 17
    }

    It "'<lab>' parses" -ForEach $GuideCases {
        $exitCode | Should -Be 0 -Because $output
    }

    It "'<lab>' yields the same step ids as its headings, in order" -ForEach $GuideCases {
        $parsedIds | Should -Be $headingIds
    }

    It "'<lab>' reports a guide path relative to the repo root" -ForEach $GuideCases {
        $guidePath | Should -Match "^module-\d[^/]*/\d+\.\d+-[^/]+/lab-guide-$lab\.md$"
    }

    It "'<lab>' never marks a step portal without a label" -ForEach $GuideCases {
        $emptyPortal | Should -BeNullOrEmpty
    }

    It "'<lab>' yields field labels without markup or comment residue" -ForEach $GuideCases {
        $badFields | Should -BeNullOrEmpty
    }
}

Describe 'parse.py - lab 1.1, the first recorded lab' {
    BeforeAll {
        $guide = Join-Path $script:RepoRoot 'module-1-identities-governance/1.1-entra-users-groups/lab-guide-1.1.md'
        $out   = Join-Path $TestDrive 'lab-1.1.json'
        & $script:Python $script:Parser $guide --out $out --repo-root $script:RepoRoot
        $script:Lab11 = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json
    }

    It 'reads step 1.1.6 as navigation, action, four fields and Create' {
        $step = $script:Lab11.steps | Where-Object id -eq '1.1.6'
        @($step.items.kind) | Should -Be @('navigation', 'action', 'field', 'field', 'field', 'field', 'action')
        @($step.items[0].labels) | Should -Be @('Groups', 'All groups')
        @($step.items[1].labels) | Should -Be @('+ New group')
        @(($step.items | Where-Object kind -eq 'field').label) | Should -Be @('Group type', 'Group name', 'Group description', 'Membership type')
    }

    It 'keeps the guest invitation value of step 1.1.5 verbatim for the recording to override' {
        $email = ($script:Lab11.steps | Where-Object id -eq '1.1.5').items | Where-Object label -eq 'Email'
        $email.value | Should -Be 'istormrage@illidari.com'
    }

    It 'marks every one of the 14 steps as portal' {
        @($script:Lab11.steps | Where-Object portal).Count | Should -Be 14
    }

    It 'lists Step-1.1.7.png as 2279 px wide' {
        ($script:Lab11.images | Where-Object path -eq 'images/Step-1.1.7.png').width | Should -Be 2279
    }
}
```

Check the names the file-level `BeforeAll` actually defines (`$script:RepoRoot`,
`$script:Python`, `$script:Parser` after Task 2's fix) and use those.

- [x] **Step 7: Run the tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed"`
Expected: the lab 1.1 Describe passes. Per-guide failures, if any, show what the next step fixes.

- [x] **Step 8: Grow NON_UI_BOLD from what the guides show**

Dump every label the parser extracts, through `--out` (never stdout):

```powershell
$py = if ($IsWindows) { 'python' } else { 'python3' }
$tmp = [System.IO.Path]::GetTempFileName()
Get-ChildItem module-*/*/lab-guide-*.md | ForEach-Object {
    & $py tools/guide-drift/parse.py $_.FullName --out $tmp
    (Get-Content -Raw -Encoding utf8 $tmp | ConvertFrom-Json).steps.items |
        ForEach-Object { if ($_.kind -eq 'field') { $_.label } else { $_.labels } }
} | Sort-Object -Unique
Remove-Item $tmp
```

Read the list once. Add every entry that is a caption rather than a Portal element (expect
things like `Solution`, `Cause`, `Check`, `Fix`, `Q`, `A`, `Situation`, `Your Task`) to
`NON_UI_BOLD` in `parse.py`, each with the lab it came from in a trailing comment. Do not add
Portal names; when unsure, leave it in (a supervised run answers `i` for it once, and the
recording keeps that). Put the full list you saw, and which entries you added, in your report.

- [x] **Step 9: Run the tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Guide-Drift-Parser.Tests.ps1 -Output Detailed"`
Expected: all green, 17 guides. Also run it once with `PYTHONIOENCODING` removed and the
console code page set to 852, as in Task 2's fix, and confirm green.

- [x] **Step 10: Commit**

```powershell
git add tests/Guide-Drift-Parser.Tests.ps1 tools/guide-drift/parse.py PLAN.md
git commit -m "test(guide-drift): parse all 17 guides and pin lab 1.1's shape"
```

---

### Task 5: Decision boundary: replay and ask the person

**Files:**

- Create: `tools/guide-drift/decide.py`

Not unit-tested in the first version (issue #189, Tests section); verified by the supervised run
in Task 12. Keep it small enough to read.

- [x] **Step 1: Write decide.py**

```python
#!/usr/bin/env python3
"""The one boundary every 'label not found' decision passes through (issue #189).

decide(step, label, candidates, deciders) asks each decider in turn and returns the first
answer that is not None. Two deciders ship:

  ReplayDecider  answers from the committed recording. A recorded 'use' whose element is still
                 on screen is replayed; a recorded 'ignore' is replayed; a recorded 'gone' is
                 reported as blocking drift without asking. Anything else falls through.
  HumanDecider   prints the step text, the missing label and the numbered candidates, and
                 reads one answer from the keyboard. Always answers.

A model-based decider is a third implementation of the same signature; it is out of scope here
and tracked in issue #190. Every decision the runner acts on is written back to the recording by
run.py, with the rejected candidates, so supervised runs build the reference set.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict


@dataclass
class Candidate:
    role: str
    name: str

    def __str__(self) -> str:
        return f'{self.role} "{self.name}"'


@dataclass
class Decision:
    kind: str                     # "use" | "drift" | "ignore" | "unknown"
    name: str | None = None       # use: accessible name to act on; drift: observed text
    role: str | None = None
    severity: str | None = None   # drift only: "blocking" | "misleading" | "cosmetic"
    reason: str | None = None     # unknown only
    decided_by: str = "human"     # "exact" | "replay" | "human"

    def to_recording(self, rejected: list[str], at: str) -> dict | None:
        """The shape stored under recording["steps"][id]["labels"][label]; None for unknown,
        which is never recorded because it would replay as 'still unknown' forever."""
        if self.kind == "unknown":
            return None
        if self.kind == "ignore":
            decision = "ignore"
        elif self.kind == "drift" and self.severity == "blocking":
            decision = "gone"
        else:
            decision = "use"      # use, or a misleading/cosmetic drift that names its element
        return {"decision": decision, "role": self.role, "name": self.name,
                "severity": self.severity, "rejected": rejected,
                "decidedBy": self.decided_by, "at": at}


class ReplayDecider:
    def __init__(self, recording: dict) -> None:
        self.recording = recording

    def __call__(self, step: dict, label: str, candidates: list[Candidate]) -> Decision | None:
        entry = self.recording.get("steps", {}).get(step["id"], {}).get("labels", {}).get(label)
        if not entry:
            return None
        if entry["decision"] == "ignore":
            return Decision(kind="ignore", decided_by="replay")
        if entry["decision"] == "gone":
            return Decision(kind="drift", severity="blocking", name=None, decided_by="replay")
        if entry["decision"] == "use":
            for candidate in candidates:
                if candidate.name == entry["name"] and (not entry.get("role") or candidate.role == entry["role"]):
                    severity = (entry.get("severity") or "misleading") if candidate.name != label else None
                    kind = "drift" if severity else "use"
                    return Decision(kind=kind, name=candidate.name, role=candidate.role,
                                    severity=severity, decided_by="replay")
        return None   # recorded element is not on screen: the Portal moved again, ask


class HumanDecider:
    PROMPT = (
        "  [number]   use that element (renamed = misleading drift)   g  gone (blocking drift)\n"
        "  c [number] use it, but the difference is cosmetic          i  ignore (not a UI element)\n"
        "  u <why>    unknown, cannot tell\n> "
    )

    def __init__(self, ask=input, say=print) -> None:
        self.ask = ask
        self.say = say

    def __call__(self, step: dict, label: str, candidates: list[Candidate]) -> Decision:
        self.say(f'\nStep {step["id"]}: {step["title"]}')
        self.say(f'Guide says: **{label}**   (line {step.get("line")})')
        self.say("Not found. Visible elements:")
        for index, candidate in enumerate(candidates, start=1):
            self.say(f"  {index:3d}. {candidate}")
        while True:
            answer = self.ask(self.PROMPT).strip()
            if answer.isdigit() and 1 <= int(answer) <= len(candidates):
                chosen = candidates[int(answer) - 1]
                severity = "misleading" if chosen.name != label else None
                return Decision(kind="drift" if severity else "use", name=chosen.name,
                                role=chosen.role, severity=severity)
            if answer == "g":
                return Decision(kind="drift", severity="blocking")
            if answer.startswith("c ") and answer[2:].strip().isdigit() and 1 <= int(answer[2:]) <= len(candidates):
                chosen = candidates[int(answer[2:]) - 1]
                return Decision(kind="drift", name=chosen.name, role=chosen.role, severity="cosmetic")
            if answer == "i":
                return Decision(kind="ignore")
            if answer.startswith("u"):
                return Decision(kind="unknown", reason=answer[1:].strip() or "operator could not tell")
            self.say("Answer with a number, g, c <number>, i or u <why>.")


def decide(step: dict, label: str, candidates: list[Candidate], deciders) -> Decision:
    for decider in deciders:
        decision = decider(step, label, candidates)
        if decision is not None:
            return decision
    return Decision(kind="unknown", reason="no decider answered", decided_by="replay")
```

- [x] **Step 2: Check it imports**

Run: `python -c "import sys; sys.path.insert(0,'tools/guide-drift'); import decide; print(decide.Decision('use'))"`
Expected: `Decision(kind='use', name=None, role=None, severity=None, reason=None, decided_by='human')`

- [x] **Step 3: Commit**

```powershell
git add tools/guide-drift/decide.py
git commit -m "feat(guide-drift): decision boundary with replay and ask-the-person deciders"
```

---

### Task 6: Seed recording for lab 1.1 and the recording test

**Files:**

- Create: `tools/guide-drift/recordings/lab-1.1.json`
- Create: `tests/Guide-Drift-Recording.Tests.ps1`

The seed holds only what must exist before the first run: the tenant placeholder and the guest
address override. Labels are filled by the supervised run in Task 12.

**Pester 5 scoping (learned in Task 2).** `$RecordingCases` is `-ForEach` data and is built at
file scope during discovery, which is correct. Anything else an `It` block reads must come from a
`BeforeAll` (`$script:` variables), as the second Describe already does. Commands below use
`pwsh -NoProfile -Command "Invoke-Pester ..."` from the worktree root.

- [x] **Step 1: Write the failing test**

Create `tests/Guide-Drift-Recording.Tests.ps1`:

```powershell
<#
.SYNOPSIS
    Pester 5 tests: every guide drift recording refers only to steps and labels its guide has.

.DESCRIPTION
    tools/guide-drift/recordings/lab-X.Y.json is the committed memory of supervised runs
    (issue #189). A guide edit that renames a portal label must update the recording in the same
    PR, or the next run asks the person again for something already decided - or worse, replays
    a click on the wrong thing. This suite parses each recording's guide with parse.py and
    requires every recorded step id and label to exist there.

    It also pins the two values that must never be literal in this public repository: the
    tenant prefix placeholder and the guest address of step 1.1.5 are environment references.

.EXAMPLE
    Invoke-Pester -Path .\tests\Guide-Drift-Recording.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue:   #189
#>

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Parser   = Join-Path $RepoRoot 'tools/guide-drift/parse.py'
$Python   = if ($IsWindows) { 'python' } else { 'python3' }

$RecordingCases = Get-ChildItem -Path (Join-Path $RepoRoot 'tools/guide-drift/recordings') -Filter 'lab-*.json' |
    ForEach-Object {
        $recording = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
        $guidePath = Join-Path $RepoRoot $recording.guide
        # Read through --out, never stdout: on Windows a piped stdout is decoded with the console
        # code page, and guides contain characters outside it (see Guide-Drift-Parser.Tests.ps1).
        $parsed = $null
        if (Test-Path -LiteralPath $guidePath) {
            $out = [System.IO.Path]::GetTempFileName()
            try {
                & $Python $Parser $guidePath --out $out --repo-root $RepoRoot
                if ($LASTEXITCODE -eq 0) { $parsed = Get-Content -Raw -Encoding utf8 -LiteralPath $out | ConvertFrom-Json }
            } finally { Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue }
        }
        $labelsByStep = @{}
        foreach ($step in @($parsed.steps)) {
            $labelsByStep[$step.id] = @($step.items | ForEach-Object { if ($_.kind -eq 'field') { $_.label } elseif ($_.kind -eq 'tag') { $_.name } else { $_.labels } })
        }
        $malformed = @(
            foreach ($prop in $recording.steps.PSObject.Properties) {
                foreach ($entry in @($prop.Value.labels.PSObject.Properties)) {
                    $d = $entry.Value
                    if ($d.decision -notin 'use', 'ignore', 'gone') { "step $($prop.Name) label '$($entry.Name)': decision '$($d.decision)'" }
                    if ($d.decision -eq 'use' -and (-not $d.name -or -not $d.role)) { "step $($prop.Name) label '$($entry.Name)': 'use' needs a name and a role" }
                    if ($d.decision -eq 'use' -and $d.severity -and $d.severity -notin 'misleading', 'cosmetic') { "step $($prop.Name) label '$($entry.Name)': severity '$($d.severity)'" }
                }
            }
        )
        $missing = @(
            foreach ($prop in $recording.steps.PSObject.Properties) {
                $id = $prop.Name
                if (-not $labelsByStep.ContainsKey($id)) { "step $id is not in the guide"; continue }
                foreach ($label in @($prop.Value.labels.PSObject.Properties.Name)) {
                    if ($labelsByStep[$id] -cnotcontains $label) { "step $id label '$label' is not in the guide" }
                }
                foreach ($field in @($prop.Value.valueOverrides.PSObject.Properties.Name)) {
                    if ($labelsByStep[$id] -cnotcontains $field) { "step $id override '$field' is not a field of the step" }
                }
            }
        )
        @{
            file        = $_.Name
            lab         = $recording.lab
            guideExists = (Test-Path -LiteralPath $guidePath)
            labMatches  = ($recording.lab -eq $parsed.lab)
            missing     = $missing
            malformed   = $malformed
            recording   = $recording
        }
    }

Describe 'Guide drift recordings - every one refers to a real guide' {
    It 'has recordings to check' -ForEach @(@{ count = @($RecordingCases).Count }) {
        $count | Should -BeGreaterThan 0
    }

    It "'<file>' names a guide that exists and carries its lab number" -ForEach $RecordingCases {
        $guideExists | Should -BeTrue
        $labMatches  | Should -BeTrue
    }

    It "'<file>' refers only to steps, labels and fields the parser finds in that guide" -ForEach $RecordingCases {
        $missing | Should -BeNullOrEmpty -Because ($missing -join '; ')
    }
}

Describe 'Guide drift recordings - every decision is one replay can act on' {
    It "'<file>' records only use (with name and role), ignore or gone decisions" -ForEach $RecordingCases {
        # ReplayDecider treats anything else as no answer (or, without a role, as any role), so a
        # hand edit that breaks the shape would silently send the run back to asking - or worse.
        $malformed | Should -BeNullOrEmpty -Because ($malformed -join '; ')
    }
}

Describe 'Guide drift recording for lab 1.1 - nothing tenant-specific is literal' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:Lab11 = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'tools/guide-drift/recordings/lab-1.1.json') | ConvertFrom-Json
    }

    It 'replaces [yourtenant] from the environment' {
        $script:Lab11.placeholders.'[yourtenant]' | Should -Be '${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}'
    }

    It 'overrides the guest address of step 1.1.5 from the environment' {
        $script:Lab11.steps.'1.1.5'.valueOverrides.Email | Should -Be '${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}'
    }

    It 'contains no literal e-mail address' {
        (Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'tools/guide-drift/recordings/lab-1.1.json')) |
            Should -Not -Match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path ./tests/Guide-Drift-Recording.Tests.ps1 -Output Detailed`
Expected: `has recordings to check` fails (0 recordings).

- [x] **Step 3: Write the seed recording**

Create `tools/guide-drift/recordings/lab-1.1.json`:

```json
{
  "lab": "1.1",
  "guide": "module-1-identities-governance/1.1-entra-users-groups/lab-guide-1.1.md",
  "portalLanguage": "en",
  "viewport": [1440, 900],
  "placeholders": {
    "[yourtenant]": "${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}"
  },
  "steps": {
    "1.1.5": {
      "valueOverrides": { "Email": "${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}" },
      "viewUrl": null,
      "result": null,
      "labels": {}
    }
  }
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path ./tests/Guide-Drift-Recording.Tests.ps1 -Output Detailed`
Expected: 7 passed.

- [x] **Step 5: Run the whole suite once**

Run: `Invoke-Pester -Path ./tests -Output Normal`
Expected: green. `Pester-Discovery.Tests.ps1` accepts the two new suites because they sit in
`tests/`. `Markdown-Links.Tests.ps1` scans `PLAN.md` too: it contains no relative links.

- [x] **Step 6: Commit**

```powershell
git add tools/guide-drift/recordings/lab-1.1.json tests/Guide-Drift-Recording.Tests.ps1 PLAN.md
git commit -m "feat(guide-drift): seed the lab 1.1 recording and test recordings against the parser"
```

---

### Task 7: Runner: browser, sign-in, guards

**Files:**

- Create: `tools/guide-drift/requirements.txt`
- Create: `tools/guide-drift/run.py` (first half; Tasks 8 and 9 extend it)

Local prerequisite, once: `python -m pip install -r tools/guide-drift/requirements.txt` and
`python -m playwright install chromium`.

- [x] **Step 1: requirements.txt**

```text
playwright>=1.49
```

- [x] **Step 2: Write run.py: arguments, browser, sign-in, guards**

Create `tools/guide-drift/run.py`:

```python
#!/usr/bin/env python3
"""Perform one lab guide's portal steps in a visible browser and report drift (issue #189).

Driven by tools/Invoke-GuideDrift.ps1, which resolves the tenant and parses the guide first.
Opens Chromium headed at 1440x900 on https://portal.azure.com/#@<tenant id>, waits for the
person to sign in (multi-factor included; there is no unattended sign-in), saves the browser
session to --auth-state so the next run skips the password, then refuses to start unless the
Portal is in English and shows the expected tenant.

Everything a run leaves behind goes under --log-dir/<run id>/ and is gitignored:
results.jsonl (one record per check, appended as the run goes), Step-X.Y.N.png (full window,
for manual cropping and anonymisation), summary.md. Only the recording is written back into
the repository.

Usage (normally via Invoke-GuideDrift.ps1):
  python run.py --steps steps.json --recording recordings/lab-1.1.json --log-dir <dir>
                --run-id 20261007-100000 --tenant-id <guid> --tenant-domain contoso.onmicrosoft.com
                --state <path> --auth-state <path> [--from-step 1.1.6] [--resume]
"""
from __future__ import annotations

import argparse
import datetime as dt
import difflib
import json
import os
import re
import sys
import traceback
from pathlib import Path
from urllib.parse import urlsplit

from playwright.sync_api import Page, Frame, TimeoutError as PlaywrightTimeout, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
from decide import Candidate, Decision, HumanDecider, ReplayDecider, decide  # noqa: E402

PORTAL = "https://portal.azure.com"
SETTLE_MS = 1500
FIND_TIMEOUT_MS = 8000
CANDIDATE_ROLES = ("button", "link", "menuitem", "tab", "treeitem", "option", "textbox",
                   "combobox", "checkbox", "radio", "heading", "cell")
ENV_REF = re.compile(r"\$\{(?P<name>[A-Z0-9_]+)\}")


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def expand_env(value: str) -> str:
    def replace(m: re.Match) -> str:
        name = m.group("name")
        if name not in os.environ:
            raise SystemExit(f"environment variable {name} is not set; the recording needs it")
        return os.environ[name]
    return ENV_REF.sub(replace, value)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--steps", type=Path, required=True)
    p.add_argument("--recording", type=Path, required=True)
    p.add_argument("--log-dir", type=Path, required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--tenant-id", required=True)
    p.add_argument("--tenant-domain", required=True)
    p.add_argument("--state", type=Path, required=True)
    p.add_argument("--auth-state", type=Path, required=True)
    p.add_argument("--from-step")
    p.add_argument("--resume", action="store_true")
    return p.parse_args(argv)


def all_frames(page: Page) -> list[Frame]:
    """Main frame first, then every child frame: Entra ID blades render inside iframes."""
    return [page.main_frame] + [f for f in page.frames if f is not page.main_frame]


def aria_lines(page: Page) -> list[tuple[str, str, int]]:
    """(role, name, count) of every named element the accessibility tree exposes, across frames,
    in first-seen order. count is how many elements share that role and name: the Portal keeps
    earlier blades in the DOM, so 'Create' or 'Delete' often appears more than once, and a
    candidate that stands for several elements must never be clicked by name alone."""
    counts: dict[tuple[str, str], int] = {}
    for frame in all_frames(page):
        try:
            snapshot = frame.locator("body").aria_snapshot(timeout=2000)
        except PlaywrightTimeout:
            continue
        for line in snapshot.splitlines():
            m = re.match(r'\s*-\s+(?P<role>[a-z]+)\s+"(?P<name>[^"]+)"', line)
            if m and m.group("role") in CANDIDATE_ROLES:
                key = (m.group("role"), m.group("name"))
                counts[key] = counts.get(key, 0) + 1
    return [(role, name, count) for (role, name), count in counts.items()][:300]


def wait_for_sign_in(page: Page, say=print) -> None:
    """Signed in = back on portal.azure.com with a rendered header. No timeout: multi-factor
    authentication takes as long as it takes, and nobody is served by a run that gives up."""
    say("Sign in to the Portal in the browser window. Waiting (no timeout)...")
    while True:
        on_portal = page.url.startswith(PORTAL) and "login.microsoftonline.com" not in page.url
        if on_portal and page.get_by_role("search").count() + page.locator("header").count() > 0:
            return
        page.wait_for_timeout(2000)


def guard_language(page: Page) -> str | None:
    lang = page.evaluate("document.documentElement.lang || ''")
    if not lang.lower().startswith("en"):
        return f"Portal language is '{lang or 'unset'}', not English. Set the account's Portal language to English and re-run."
    return None


def guard_tenant(page: Page, tenant_domain: str, tenant_id: str) -> str | None:
    """The account menu lists the current directory with its domain; the URL fragment carries
    the tenant after '#@'. Either match is accepted."""
    if f"#@{tenant_domain}" in page.url or f"#@{tenant_id}" in page.url:
        return None
    menu = page.get_by_role("button", name=re.compile(r"account|profile|user menu", re.I)).first
    try:
        menu.click(timeout=FIND_TIMEOUT_MS)
        page.wait_for_timeout(SETTLE_MS)
        text = "\n".join(name for _, name, _ in aria_lines(page)) + page.locator("body").inner_text(timeout=2000)
        page.keyboard.press("Escape")
    except PlaywrightTimeout:
        return "Could not open the account menu to read the current directory."
    if tenant_domain.lower() in text.lower() or tenant_id.lower() in text.lower():
        return None
    return f"Portal is not signed in to {tenant_domain}. Switch directory and re-run."


def open_portal(pw, args: argparse.Namespace, recording: dict) -> tuple[object, Page]:
    width, height = recording.get("viewport", [1440, 900])
    browser = pw.chromium.launch(headless=False)
    context_kwargs = {"viewport": {"width": width, "height": height}, "device_scale_factor": 1,
                      "locale": "en-US"}
    if args.auth_state.is_file():
        context_kwargs["storage_state"] = str(args.auth_state)
    context = browser.new_context(**context_kwargs)
    page = context.new_page()
    page.goto(f"{PORTAL}/#@{args.tenant_id}", wait_until="domcontentloaded")
    wait_for_sign_in(page)
    page.wait_for_timeout(SETTLE_MS * 2)
    context.storage_state(path=str(args.auth_state))
    for guard in (guard_language(page), guard_tenant(page, args.tenant_domain, args.tenant_id)):
        if guard:
            browser.close()
            raise SystemExit(f"GUARD FAILED: {guard}")
    return browser, page
```

- [x] **Step 3: Smoke-test the sign-in and guards by hand**

Run from the worktree root, with the subscription's tenant values at hand (the entry point will
compute these in Task 10; for now paste them):

```powershell
python -c "import sys; sys.path.insert(0,'tools/guide-drift'); import run; print('imports ok')"
```

Expected: `imports ok`. If `aria_snapshot` is missing, Playwright is older than 1.49:
`python -m pip install -U playwright; python -m playwright install chromium`.

- [x] **Step 4: Commit**

```powershell
git add tools/guide-drift/requirements.txt tools/guide-drift/run.py
git commit -m "feat(guide-drift): open the Portal, wait for sign-in, guard language and tenant"
```

---

### Task 8: Runner: finding elements, performing steps, asking at the boundary

**Files:**

- Modify: `tools/guide-drift/run.py` (append)

- [x] **Step 1: Append element lookup and step execution**

Append to `tools/guide-drift/run.py`:

```python
# --- finding and acting --------------------------------------------------------------------

class Ambiguous(LookupError):
    """Several visible elements match. The runner never clicks one of them by guess: earlier
    Portal blades stay in the DOM, and the first match in DOM order is often the wrong one."""


def visible_in(locator) -> list:
    found = []
    for index in range(locator.count()):
        element = locator.nth(index)
        try:
            if element.is_visible():
                found.append(element)
        except PlaywrightTimeout:
            continue
    return found


def unique_visible(page: Page, make_locator):
    """The one visible element `make_locator(frame)` matches across all frames, or None when there
    is none; raises Ambiguous when there are several."""
    found = []
    for frame in all_frames(page):
        found += visible_in(make_locator(frame))
    if len(found) > 1:
        raise Ambiguous(f"{len(found)} visible elements match")
    return found[0] if found else None


def find_exact(page: Page, label: str, field: bool = False):
    """The visible element whose accessible name is exactly `label`: the field label first for a
    field, then the interactive roles, then plain text. An ambiguous role match raises Ambiguous;
    an ambiguous text match counts as not found, so the person picks a role-specific candidate."""
    strategies = []
    if field:
        strategies.append(lambda f: f.get_by_label(label, exact=True))
    for role in ("button", "link", "menuitem", "tab", "treeitem", "option", "checkbox", "radio"):
        strategies.append(lambda f, role=role: f.get_by_role(role, name=label, exact=True))
    for make_locator in strategies:
        element = unique_visible(page, make_locator)
        if element is not None:
            return element
    try:
        return unique_visible(page, lambda f: f.get_by_text(label, exact=True))
    except Ambiguous:
        return None


def find_by_name(page: Page, role: str | None, name: str):
    """The element a decision chose, by role and name. Raises Ambiguous rather than guess."""
    if role:
        return unique_visible(page, lambda f: f.get_by_role(role, name=name, exact=True))
    return unique_visible(page, lambda f: f.get_by_text(name, exact=True))


def candidates_on_screen(page: Page) -> list[Candidate]:
    return [Candidate(role=role, name=name, count=count) for role, name, count in aria_lines(page)]


GUID = re.compile(r"[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}")


class Redactor:
    """Keeps tenant data out of the committed recording, which lives in a public repository.
    The tenant's domain and id become tokens on the way into the recording and are restored on
    the way out, so a recorded name such as 'malfurion.stormrage@[tenantdomain]' still finds its
    element. tests/Guide-Drift-Recording.Tests.ps1 is the backstop: it fails on any literal
    e-mail address, *.onmicrosoft.com domain or GUID in a recording."""

    DOMAIN = "[tenantdomain]"
    TENANT = "[tenantid]"

    def __init__(self, domain: str, tenant_id: str, secrets: dict[str, str] | None = None) -> None:
        # The Portal shows domains in lower case; restore() must give back what is on screen.
        self.domain = domain.lower()
        self.tenant_id = tenant_id.lower()
        self._pairs: list[tuple[re.Pattern, str, str]] = []
        # Secret values first (the guest address, also in the '_' form a guest UPN uses:
        # 'me_example.com#EXT#@<tenant>'), then the tenant domain and id.
        for token, value in (secrets or {}).items():
            upn = value.replace("@", "_")
            self._pairs.append((re.compile(re.escape(value), re.IGNORECASE), token, value))
            # A distinct token for the UPN form, so restore() knows which form to give back.
            self._pairs.append((re.compile(re.escape(upn), re.IGNORECASE), token[:-1] + "|upn}", upn))
        self._pairs.append((re.compile(re.escape(self.domain), re.IGNORECASE), self.DOMAIN, self.domain))
        self._pairs.append((re.compile(re.escape(self.tenant_id), re.IGNORECASE), self.TENANT, self.tenant_id))

    def redact(self, text: str | None) -> str | None:
        if text is None:
            return None
        for pattern, token, _ in self._pairs:
            text = pattern.sub(token, text)
        return text

    def restore(self, text: str | None) -> str | None:
        if text is None:
            return None
        for _, token, value in reversed(self._pairs):
            text = text.replace(token, value)
        return text

    def view_url(self, url: str) -> str:
        """The Portal view without the tenant pin ('#@<tenant>/'), query strings (before or inside
        the fragment) or object ids: shown to the person on -Resume, never navigated to."""
        parts = urlsplit(url)
        fragment = re.sub(r"^@[^/]*/?", "", parts.fragment).split("?", 1)[0]
        return self.redact(GUID.sub("<id>", f"{parts.scheme}://{parts.netloc}{parts.path}#{fragment}"))


def env_secrets(recording: dict) -> dict[str, str]:
    """'${NAME}' -> value for every environment reference in the recording whose value is an
    address (contains '@'): the Redactor writes the token back wherever the value appears.
    Short non-address values such as the tenant prefix are covered by the domain itself and
    would otherwise clobber ordinary words."""
    secrets = {}
    for name in set(ENV_REF.findall(json.dumps(recording))):
        value = os.environ.get(name, "")
        if "@" in value:
            secrets[f"${{{name}}}"] = value
    return secrets


def rejected_candidates(candidates: list[Candidate], label: str, chosen: str | None) -> list[str]:
    """The 20 visible candidates most like the label, other than the chosen one, as 'role "name"':
    the reference set issue #190 needs, without committing the whole screen to the recording.
    Names with an '@' (user principal names, the signed-in account) or a GUID (object and
    subscription ids) are left out entirely."""
    others = [c for c in candidates if c.name != chosen and "@" not in c.name and not GUID.search(c.name)]
    others.sort(key=lambda c: difflib.SequenceMatcher(None, c.name.lower(), label.lower()).ratio(),
                reverse=True)
    return [str(c) for c in others[:20]]


def resolve_value(recording: dict, step: dict, label: str, value: str) -> str:
    override = recording["steps"].get(step["id"], {}).get("valueOverrides", {}).get(label)
    if override is not None:
        return expand_env(override)
    for placeholder, replacement in recording.get("placeholders", {}).items():
        if placeholder in value:
            value = value.replace(placeholder, expand_env(replacement))
    return value



BRACKET_TOKEN = re.compile(r"\[[^\]]+\]")


def value_action(value: str) -> str:
    """How to treat a field value once placeholders and overrides are applied: 'skip' when the
    whole value is a bracketed instruction ('[Leave blank]' in 1.1.10), 'unresolved' when a
    bracket token is left ('skycraft-auth-[uniqueID]'), otherwise 'type'."""
    if re.fullmatch(r"\[[^\]]+\]", value.strip()):
        return "skip"
    return "unresolved" if BRACKET_TOKEN.search(value) else "type"


def fill_field(page: Page, element, value: str) -> None:
    role = element.get_attribute("role") or ""
    tag = element.evaluate("e => e.tagName.toLowerCase()")
    if role in ("combobox", "button") or tag in ("button", "select"):
        element.click()
        page.wait_for_timeout(SETTLE_MS // 2)
        option = find_by_name(page, "option", value) or find_by_name(page, None, value)
        if option is None:
            raise LookupError(f"option '{value}' not found")
        option.click()
    else:
        element.fill(value)
    page.wait_for_timeout(SETTLE_MS // 2)


def fill_tag(page: Page, name: str, value: str) -> None:
    """The Portal's Tags grid ends with an empty row whose inputs are named 'Name' and 'Value';
    typing into it adds the next empty row. Fill the last of each. The exact roles are confirmed
    in the first supervised run (Task 12); until then a miss is reported as unknown, not guessed."""
    for frame in all_frames(page):
        names = frame.get_by_role("combobox", name="Name", exact=True)
        if names.count() == 0:
            names = frame.get_by_label("Name", exact=True)
        values = frame.get_by_role("combobox", name="Value", exact=True)
        if values.count() == 0:
            values = frame.get_by_label("Value", exact=True)
        if names.count() > 0 and values.count() > 0:
            names.last.fill(name)
            page.wait_for_timeout(SETTLE_MS // 2)
            values.last.fill(value)
            page.wait_for_timeout(SETTLE_MS // 2)
            return
    raise LookupError("Tags grid not found (no inputs named 'Name' and 'Value')")


class Runner:
    def __init__(self, page: Page, steps: dict, recording: dict, args: argparse.Namespace) -> None:
        self.page = page
        self.steps = steps
        self.recording = recording
        self.args = args
        self.run_dir = args.log_dir / args.run_id
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.results_path = self.run_dir / "results.jsonl"
        self.deciders = [ReplayDecider(recording), HumanDecider()]
        self.redactor = Redactor(args.tenant_domain, args.tenant_id, env_secrets(recording))
        self.records: list[dict] = []
        self.failed_steps: dict[str, str] = {}   # step id -> why (for skippedBecause)

    # -- recording -------------------------------------------------------------------------

    def step_entry(self, step: dict) -> dict:
        entry = self.recording["steps"].setdefault(step["id"], {})
        entry.setdefault("valueOverrides", {})
        entry.setdefault("viewUrl", None)
        entry.setdefault("result", None)
        entry.setdefault("labels", {})
        return entry

    def save_recording(self) -> None:
        self.args.recording.write_text(json.dumps(self.recording, indent=2, ensure_ascii=False) + "\n",
                                       encoding="utf-8")

    # -- one label -------------------------------------------------------------------------

    def act_on_label(self, step: dict, item: dict, label: str, value: str | None = None) -> dict:
        """Find the element the guide calls `label`, act on it, return the result record."""
        kind, line = item["kind"], item["line"]
        record = self.new_record(step, kind, label)
        try:
            element = find_exact(self.page, label, field=(kind == "field"))
        except Ambiguous as error:
            record.update(outcome="unknown", observed=f"ambiguous: {error} named '{label}'")
            return record
        decision = Decision(kind="use", name=label, decided_by="exact") if element is not None else None
        if decision is None:
            # Names are redacted before anyone sees them, so the person, the recording and replay
            # all work with '[tenantdomain]' and the element is found by the restored name.
            candidates = [Candidate(role=c.role, name=self.redactor.redact(c.name), count=c.count)
                          for c in candidates_on_screen(self.page)]
            decision = decide(step, item, label, candidates, self.deciders)
            if decision.name and decision.severity != "blocking":
                try:
                    element = find_by_name(self.page, decision.role, self.redactor.restore(decision.name))
                except Ambiguous as error:
                    # Not recorded: replay must never inherit a choice the runner refused to act on.
                    record.update(outcome="unknown", observed=f"ambiguous: {error} named '{decision.name}'")
                    return record
            entry = decision.to_recording(rejected_candidates(candidates, label, decision.name), now())
            if decision.decided_by == "human" and entry is not None:
                self.step_entry(step)["labels"][label] = entry
                self.save_recording()
        if decision.kind == "ignore":
            record.update(outcome="match", observed=None)
            return record
        if decision.kind == "unknown":
            record.update(outcome="unknown", observed=decision.reason)
            return record
        if decision.severity == "blocking":
            record.update(outcome="drift", severity="blocking", observed=None)
            return record
        if element is None:
            record.update(outcome="unknown", observed=f"'{decision.name}' chosen but not found on screen")
            return record
        try:
            if kind == "field":
                fill_field(self.page, element, value or "")
            else:
                element.click(timeout=FIND_TIMEOUT_MS)
                self.page.wait_for_timeout(SETTLE_MS)
        except (PlaywrightTimeout, LookupError) as error:
            record.update(outcome="unknown", observed=f"{type(error).__name__}: {error}")
            return record
        if decision.kind == "drift":      # misleading or cosmetic: acted on, under a different name
            record.update(outcome="drift", severity=decision.severity, observed=decision.name,
                          proposedEdit=self.proposed_edit(line, label, decision.name))
        else:
            record.update(outcome="match", observed=decision.name)
        return record

    def proposed_edit(self, line: int, old_label: str, new_label: str) -> dict | None:
        guide_lines = (Path(self.args.repo_root) / self.steps["guide"]).read_text(encoding="utf-8-sig").splitlines()
        if not (1 <= line <= len(guide_lines)):
            return None
        old = guide_lines[line - 1]
        return {"line": line, "old": old, "new": old.replace(f"**{old_label}**", f"**{new_label}**")}

    # -- one step --------------------------------------------------------------------------

    def run_step(self, step: dict) -> None:
        print(f"\n=== Step {step['id']}: {step['title']} ===")
        entry = self.step_entry(step)
        step_failed = False
        for item in step["items"]:
            if item["kind"] == "tag":
                record = self.new_record(step, "tag", item["name"])
                try:
                    fill_tag(self.page, item["name"], resolve_value(self.recording, step, item["name"], item["value"]))
                    record.update(outcome="match", observed=item["value"])
                except (PlaywrightTimeout, LookupError) as error:
                    record.update(outcome="unknown", observed=f"{type(error).__name__}: {error}")
                records = [record]
            elif item["kind"] == "field":
                value = resolve_value(self.recording, step, item["label"], item["value"])
                action = value_action(value)
                if action == "type":
                    record = self.act_on_label(step, item, item["label"], value)
                else:
                    record = self.new_record(step, "field", item["label"])
                    if action == "skip":
                        record.update(outcome="match", observed=f"left as is: {value}")
                    else:
                        record.update(outcome="unknown",
                                      observed=f"value '{value}' has an unresolved [token]; add a "
                                               "placeholder or a valueOverride to the recording")
                records = [record]
            else:
                records = []
                for label in item["labels"]:
                    records.append(self.act_on_label(step, item, label))
                    if records[-1]["outcome"] in ("unknown",) or records[-1].get("severity") == "blocking":
                        break
            for record in records:
                self.write(record)
                if record["outcome"] == "unknown" or record.get("severity") == "blocking":
                    step_failed = True
            if step_failed:
                break
        self.check_result(step, entry)
        entry["viewUrl"] = self.redactor.view_url(self.page.url)
        self.save_recording()
        self.write(self.screenshot(step))
        if step_failed:
            self.failed_steps[step["id"]] = step["id"]
```

- [x] **Step 2: Forbid the guest UPN form in recordings**

In `tests/Guide-Drift-Recording.Tests.ps1`, the privacy checks catch an e-mail address but not
a guest user principal name (`me_example.com#EXT#@[tenantdomain]` after redaction). Add one
`-ForEach $RecordingCases` It in the same boolean style as the others
(`($raw -match '#EXT#') | Should -BeFalse -Because ...`), prove it fails with a temporary
`#EXT#` in the seed, revert, and run the file.

- [x] **Step 3: Unit-test the Redactor without a browser**

`Redactor`, `env_secrets` and `rejected_candidates` are pure. Add
`tools/guide-drift/tests/test_redact.py` (stdlib unittest, run by the existing
`tests/Guide-Drift-Decide.Tests.ps1` discovery; import run.py's helpers without Playwright by
stubbing `playwright.sync_api` in `sys.modules` before the import if Playwright is not
installed). Cover: domain and tenant id round-trip, case-insensitive redaction with lower-case
restore; a guest UPN `me_example.com#EXT#@contoso.onmicrosoft.com` with the secret
`me@example.com` becomes `${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL|upn}#EXT#@[tenantdomain]` and restores, and
`me@example.com` itself becomes `${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}` and restores;
`view_url` on `https://portal.azure.com/?feature.x=1#@contoso.onmicrosoft.com/view/Blade/id/<a GUID>?q=1`
gives `https://portal.azure.com/#view/Blade/id/<id>`; `rejected_candidates` drops names with
`@` or a GUID and keeps at most 20, most similar first. Run the Pester wrapper.

- [x] **Step 4: Check it still imports**

Run: `python -c "import sys; sys.path.insert(0,'tools/guide-drift'); import run; print('ok')"`
Expected: `ok` (the methods `new_record`, `write`, `check_result`, `screenshot` come in Task 9;
Python resolves them at call time, so the import succeeds).

- [x] **Step 5: Commit**

```powershell
git add tools/guide-drift/run.py tools/guide-drift/tests/test_redact.py tests/Guide-Drift-Recording.Tests.ps1 PLAN.md
git commit -m "feat(guide-drift): find labelled elements, perform steps, ask at the boundary"
```

---

### Task 9: Runner: results, screenshots, resume, summary, exit code

**Files:**

- Modify: `tools/guide-drift/run.py` (append)

- [x] **Step 1: Append results, resume and main**

Append to `tools/guide-drift/run.py`:

```python
    # -- results ---------------------------------------------------------------------------

    def new_record(self, step: dict, kind: str, label: str | None) -> dict:
        return {"runId": self.args.run_id, "at": now(), "lab": self.steps["lab"], "step": step["id"],
                "kind": kind, "label": label, "outcome": None, "severity": None, "category": None,
                "skippedBecause": None, "observed": None, "proposedEdit": None,
                "screenshot": f"Step-{step['id']}.png"}

    def write(self, record: dict) -> None:
        self.records.append(record)
        with self.results_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")

    def check_result(self, step: dict, entry: dict) -> None:
        if not step.get("expected"):
            return
        if entry["result"] is None and "result" not in entry.get("asked", []):
            print(f'Expected Result: "{step["expected"]}"')
            answer = input("Text to look for on screen (Enter = not observable): ").strip()
            entry["result"] = {"text": self.redactor.redact(answer)} if answer else None
            entry.setdefault("asked", []).append("result")
            self.save_recording()
        if not entry["result"]:
            return
        record = self.new_record(step, "result", entry["result"]["text"])
        # Presence, not a unique element: a created group's name shows in the list and the
        # breadcrumb at once, and either proves the result.
        text = self.redactor.restore(entry["result"]["text"])
        found = any(visible_in(frame.get_by_text(text, exact=False)) for frame in all_frames(self.page))
        record.update(outcome="match" if found else "drift", severity=None if found else "misleading",
                      observed=None if found else "text not on screen")
        self.write(record)

    def screenshot(self, step: dict) -> dict:
        path = self.run_dir / f"Step-{step['id']}.png"
        self.page.screenshot(path=str(path), full_page=False)
        record = self.new_record(step, "screenshot", None)
        drifted = any(r["step"] == step["id"] and r["outcome"] == "drift" for r in self.records)
        if step["images"] and drifted:
            record.update(outcome="drift", category="stale", observed=", ".join(step["images"]))
        else:
            record.update(outcome="match")
        return record

    def skip_step(self, step: dict, because: str) -> None:
        record = self.new_record(step, "action", None)
        record.update(outcome="skipped", skippedBecause=because)
        self.write(record)

    def readability(self) -> None:
        for image in self.steps["images"]:
            if image["width"] > 1722:
                record = self.new_record({"id": "-"}, "readability", image["path"])
                record.update(outcome="drift", category="unreadable", observed=f"{image['width']} px wide",
                              screenshot=None)
                self.write(record)

    # -- state and resume -------------------------------------------------------------------

    def save_state(self, completed: list[str], in_flight: str | None) -> None:
        self.args.state.write_text(json.dumps({"runId": self.args.run_id, "lab": self.steps["lab"],
                                               "completed": completed, "inFlight": in_flight}, indent=2),
                                   encoding="utf-8")

    def load_state(self) -> dict:
        if not self.args.state.is_file():
            return {"completed": [], "inFlight": None}
        state = json.loads(self.args.state.read_text(encoding="utf-8"))
        if state.get("lab") != self.steps["lab"]:
            raise SystemExit(f"state at {self.args.state} belongs to lab {state.get('lab')}, not {self.steps['lab']}")
        return state

    # -- the run ---------------------------------------------------------------------------

    def run(self) -> int:
        completed: list[str] = []
        state = self.load_state() if self.args.resume else {"completed": [], "inFlight": None}
        completed = list(state["completed"])
        started = self.args.from_step is None and not self.args.resume
        self.readability()
        for step in self.steps["steps"]:
            if not step["portal"]:
                continue
            if step["id"] in completed:
                continue
            if not started:
                if step["id"] == self.args.from_step or step["id"] == state.get("inFlight"):
                    started = True
                    url = self.recording["steps"].get(step["id"], {}).get("viewUrl")
                    print(f"Resuming at step {step['id']}. Bring the Portal to this view, then press Enter:\n  {url or '(no view recorded yet)'}")
                    input()
                else:
                    continue
            prior = [self.failed_steps[i] for i in self.failed_steps]
            if prior:
                self.skip_step(step, prior[0])
                continue
            self.save_state(completed, step["id"])
            self.run_step(step)
            completed.append(step["id"])
            self.save_state(completed, None)
        return self.finish()

    def finish(self) -> int:
        by_severity: dict[str, list[dict]] = {"blocking": [], "misleading": [], "cosmetic": []}
        unknown, skipped, stale, unreadable, edits = [], [], [], [], []
        for r in self.records:
            if r["outcome"] == "drift" and r["severity"]:
                by_severity[r["severity"]].append(r)
            elif r["outcome"] == "drift" and r["category"] == "stale":
                stale.append(r)
            elif r["outcome"] == "drift" and r["category"] == "unreadable":
                unreadable.append(r)
            elif r["outcome"] == "unknown":
                unknown.append(r)
            elif r["outcome"] == "skipped":
                skipped.append(r)
            if r.get("proposedEdit"):
                edits.append(r)
        lines = [f"# Guide drift run {self.args.run_id} - lab {self.steps['lab']}", ""]
        for severity, items in by_severity.items():
            lines.append(f"## {severity} ({len(items)})")
            lines += [f"- step {r['step']} {r['kind']} **{r['label']}**: observed {r['observed']!r}" for r in items] or ["- none"]
            lines.append("")
        lines.append(f"## unknown ({len(unknown)})")
        lines += [f"- step {r['step']} {r['kind']} **{r['label']}**: {r['observed']}" for r in unknown] or ["- none"]
        lines.append("")
        lines.append(f"## skipped ({len(skipped)})")
        lines += [f"- step {r['step']} because step {r['skippedBecause']} failed" for r in skipped] or ["- none"]
        lines.append("")
        lines.append(f"## stale screenshots ({len(stale)})")
        lines += [f"- step {r['step']}: {r['observed']}" for r in stale] or ["- none"]
        lines.append("")
        lines.append(f"## unreadable screenshots, wider than 1722 px ({len(unreadable)})")
        lines += [f"- {r['label']}: {r['observed']}" for r in unreadable] or ["- none"]
        lines.append("")
        lines.append(f"## proposed edits ({len(edits)})")
        for r in edits:
            e = r["proposedEdit"]
            lines += [f"- {self.steps['guide']}:{e['line']}", f"  - old: `{e['old']}`", f"  - new: `{e['new']}`"]
        lines.append("")
        lines.append(f"Screenshots and results: {self.run_dir}")
        summary = "\n".join(lines)
        (self.run_dir / "summary.md").write_text(summary + "\n", encoding="utf-8")
        print("\n" + summary)
        return min(len(by_severity["blocking"]) + len(unknown), 250)


# Exit codes above the 250 cap of finish(), which Invoke-GuideDrift.ps1 reads as "not a count".
NOT_STARTED = 254   # a precondition or guard stopped the run before the first step
ABORTED = 255       # interrupted (Ctrl+C) or stopped mid-run; state kept for -Resume


def missing_env(recording: dict) -> list[str]:
    """Every ${NAME} the recording refers to that the environment does not set."""
    names = set(ENV_REF.findall(json.dumps(recording)))
    return sorted(name for name in names if name not in os.environ)


def main(argv: list[str] | None = None) -> int:
    # Accessible names and guide text reach the console; a redirected stdout on Windows would
    # otherwise use the ANSI code page and fail on the first arrow.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = parse_args(argv)
    args.repo_root = Path(__file__).resolve().parents[2]
    steps = json.loads(args.steps.read_text(encoding="utf-8"))
    recording = json.loads(args.recording.read_text(encoding="utf-8"))
    if recording.get("lab") != steps.get("lab"):
        print(f"Recording is for lab {recording.get('lab')}, steps are for lab {steps.get('lab')}.")
        return NOT_STARTED
    missing = missing_env(recording)
    if missing:
        print("Set these environment variables first: " + ", ".join(missing))
        return NOT_STARTED
    with sync_playwright() as pw:
        try:
            browser, page = open_portal(pw, args, recording)
        except (SystemExit, KeyboardInterrupt) as stop:   # a guard, or Ctrl+C while signing in
            print(stop or "Interrupted before the first step.")
            return NOT_STARTED
        runner = Runner(page, steps, recording, args)
        try:
            return runner.run()
        except BaseException as stop:       # noqa: BLE001 - every way out must keep -Resume possible
            # Ctrl+C, a closed browser window (Playwright Error 'Target closed'), EOF at a prompt
            # or a bug: exit 1 would read as 'one finding' and the entry point would clean up what
            # -Resume needs. Print what happened, keep the state, and say so.
            if not isinstance(stop, (KeyboardInterrupt, SystemExit)):
                traceback.print_exc()
            try:
                runner.finish()
            except Exception:               # noqa: BLE001 - the summary is best effort here
                traceback.print_exc()
            print(f"\nStopped ({type(stop).__name__}: {stop}). Progress is in {args.state}; "
                  "re-run with -Resume.")
            return ABORTED
        finally:
            try:
                browser.close()
            except Exception:               # noqa: BLE001 - the window may already be gone
                pass


if __name__ == "__main__":
    sys.exit(main())
```

- [x] **Step 2: Import check and a dry parse of lab 1.1**

```powershell
python -c "import sys; sys.path.insert(0,'tools/guide-drift'); import run; print('ok')"
python tools/guide-drift/parse.py module-1-identities-governance/1.1-entra-users-groups/lab-guide-1.1.md --out $env:TEMP/steps-1.1.json --repo-root .
```

Expected: `ok`, and a steps file with 14 steps. Every step after a failed one is recorded
`skipped` with that step's id: in a portal lab each step builds on the one before it.

- [x] **Step 3: Commit**

```powershell
git add tools/guide-drift/run.py
git commit -m "feat(guide-drift): write results, screenshots, state, summary and exit code"
```

---

### Task 10: Entry point `tools/Invoke-GuideDrift.ps1`

**Files:**

- Create: `tools/Invoke-GuideDrift.ps1`

`tests/Script-Standards.Tests.ps1` and `tests/Cbh-Coverage.Tests.ps1` pick up every `tools/*.ps1`
automatically; running them is the test for this task.

- [ ] **Step 1: Run the standards tests to see the file is not there yet**

Run: `Invoke-Pester -Path ./tests/Script-Standards.Tests.ps1, ./tests/Cbh-Coverage.Tests.ps1 -Output Normal`
Expected: green, with no `Invoke-GuideDrift.ps1` case listed.

- [ ] **Step 2: Write the entry point**

Create `tools/Invoke-GuideDrift.ps1`:

```powershell
<#
.SYNOPSIS
    Performs one lab guide's portal steps in a visible browser and reports what no longer matches
    the Azure Portal.

.DESCRIPTION
    The lab cycle (Invoke-LabCycle.ps1) proves the infrastructure-as-code path of 16 labs. Nothing
    proves that the portal instructions - the bold labels, the navigation chains, the form tables -
    still match the Portal, which changes without notice. This tool is for the moment a lab is
    being revised: run it, get a list of what drifted, with proposed edits and fresh screenshots.
    It never runs in CI (issue #189).

    WHAT A RUN DOES. Parses the guide with tools/guide-drift/parse.py (only '### Step' sections,
    outside code fences, Option 1 where Option headings exist; the fixed list of bold captions
    that are not UI elements lives in parse.py), opens Chromium through tools/guide-drift/run.py,
    waits for you to sign in, refuses to start unless the Portal is in English and shows the
    tenant of -SubscriptionId, then performs every portal step for real: later steps depend on
    what earlier ones created. Every check ends as match, drift (blocking, misleading or
    cosmetic), unknown or skipped, so 'could not check' is never reported as 'fine'.

    SUPERVISED FIRST, RECORDED ALWAYS. When a label is not on screen the run stops and asks you,
    listing what it can see. The answer goes to tools/guide-drift/recordings/lab-X.Y.json, which
    is committed; later runs replay it and stop only where the Portal no longer matches it. That
    recording is the only thing a run writes into the repository. A guide edit that changes a
    portal label must update the recording in the same PR (tests/Guide-Drift-Recording.Tests.ps1).

    WHAT A RUN LEAVES BEHIND, AND WHY IT IS GITIGNORED. -LogDirectory/<run id>/ holds
    results.jsonl (one record per check, appended as the run goes), a full-window screenshot of
    every step and summary.md. Screenshots show the tenant name, user principal names and the
    subscription id, so nothing is copied into a guide's images/ folder: crop and anonymise by
    hand. The saved browser session (tools/.guide-drift-auth.json) is a sign-in. All of it is
    gitignored and asserted by tests/Gitignore.Tests.ps1.

    VALUES THAT MUST NOT BE LITERAL. Step 1.1.5 invites a guest; the recording overrides that
    address with ${SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL}, and '[yourtenant]' with
    ${SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX}, which this script sets from the tenant's default domain.
    Set SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL to an address you control before running lab 1.1.

    CLEANUP IS THE LAB'S OWN. This script has no deletion logic. Unless -SkipCleanup, lab 1.1
    hands off to its scripts/Remove-LabResource.ps1 -Force (Microsoft Graph), every other lab to
    tools/Remove-LabCycle.ps1 with the same -SubscriptionId.

.PARAMETER SubscriptionId
    The subscription whose tenant the run is for. Mandatory and compared by id against the Az
    context through Test-LabCycleSubscription, for the reason Invoke-LabCycle.ps1 gives
    (2026-08-02). The tenant id and default domain are read from it.

.PARAMETER Lab
    The lab to run, as 'X.Y'. Resolves module-*/X.Y-*/lab-guide-X.Y.md.

.PARAMETER FromStep
    Start at this step id ('1.1.6'), assuming earlier steps were done by hand.

.PARAMETER Resume
    Continue the previous run from tools/.guide-drift-state.json.

.PARAMETER LogDirectory
    Where run folders are written. Defaults to tools/guide-drift-logs.

.PARAMETER SkipCleanup
    Leave what the run created in place.

.PARAMETER PythonPath
    The interpreter to use. Defaults to 'python' on Windows and 'python3' elsewhere.

.EXAMPLE
    .\tools\Invoke-GuideDrift.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Lab 1.1
    Performs lab 1.1 supervised, then removes its users and groups.

.EXAMPLE
    .\tools\Invoke-GuideDrift.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -Lab 1.1 -Resume -SkipCleanup
    Continues an interrupted run and leaves the resources for inspection.

.NOTES
    Project: SkyCraft
    Issue:   #189
    Exit code: blocking drifts + unknowns (0 = nothing to fix, capped at 250); 1 when a prerequisite
    is missing; 254 when run.py stopped before the first step; 255 when it was interrupted
    (state kept, nothing cleaned up: re-run with -Resume).
#>

#Requires -Version 7.0
#Requires -Modules Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+$')]
    [string]$Lab,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$FromStep,

    [Parameter(Mandatory = $false)]
    [switch]$Resume,

    [Parameter(Mandatory = $false)]
    [string]$LogDirectory = (Join-Path $PSScriptRoot 'guide-drift-logs'),

    [Parameter(Mandatory = $false)]
    [switch]$SkipCleanup,

    [Parameter(Mandatory = $false)]
    [string]$PythonPath = $(if ($IsWindows) { 'python' } else { 'python3' })
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabCycle.psm1') -Force

$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$toolDir   = Join-Path $PSScriptRoot 'guide-drift'
$statePath = Join-Path $PSScriptRoot '.guide-drift-state.json'
$authPath  = Join-Path $PSScriptRoot '.guide-drift-auth.json'
$runId     = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Host "=== Guide drift: lab $Lab ===" -ForegroundColor Cyan

# --- Guide --------------------------------------------------------------------------------
$labDir = Get-ChildItem -Path $repoRoot -Directory -Filter 'module-*' |
    Get-ChildItem -Directory |
    Where-Object { $_.Name -like "$Lab-*" } |
    Select-Object -First 1
$guide = if ($labDir) { Join-Path $labDir.FullName "lab-guide-$Lab.md" }
if (-not $guide -or -not (Test-Path -LiteralPath $guide)) {
    Write-Host "[ERROR] No lab guide found for lab $Lab (expected module-*/$Lab-*/lab-guide-$Lab.md)." -ForegroundColor Red
    exit 1
}
$recording = Join-Path $toolDir "recordings/lab-$Lab.json"
if (-not (Test-Path -LiteralPath $recording)) {
    Write-Host "[ERROR] No recording at $recording. Create one from the lab 1.1 seed shape before the first supervised run." -ForegroundColor Red
    exit 1
}

# --- Python and Playwright ----------------------------------------------------------------
if (-not (Get-Command $PythonPath -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] '$PythonPath' not found. Install Python 3.10+ or pass -PythonPath." -ForegroundColor Red
    exit 1
}
& $PythonPath -c 'import sys; assert sys.version_info >= (3, 10); import playwright.sync_api' 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Python 3.10+ with Playwright is required:" -ForegroundColor Red
    Write-Host "        $PythonPath -m pip install -r tools/guide-drift/requirements.txt" -ForegroundColor Yellow
    Write-Host "        $PythonPath -m playwright install chromium" -ForegroundColor Yellow
    exit 1
}

# --- Subscription and tenant ----------------------------------------------------------------
$check = Test-LabCycleSubscription -SubscriptionId $SubscriptionId
if (-not $check.Ok) {
    Write-Host "[ERROR] $($check.Detail)" -ForegroundColor Red
    exit 1
}
$context  = Get-AzContext
$tenantId = $context.Tenant.Id
$tenant   = Get-AzTenant -TenantId $tenantId
$domain   = if ($tenant.DefaultDomain) { $tenant.DefaultDomain } else { @($tenant.Domains)[0] }
if (-not $domain) {
    Write-Host "[ERROR] Could not read the default domain of tenant $tenantId." -ForegroundColor Red
    exit 1
}
$env:SKYCRAFT_GUIDE_DRIFT_TENANT_PREFIX = ($domain -split '\.')[0]
Write-Host "  Subscription: $($check.Detail)" -ForegroundColor Gray
Write-Host "  Tenant:       $tenantId ($domain)" -ForegroundColor Gray
Write-Host "  Run:          $runId -> $LogDirectory" -ForegroundColor Gray

# --- Parse, then run -------------------------------------------------------------------------
$runDir = Join-Path $LogDirectory $runId
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$stepsPath = Join-Path $runDir 'steps.json'
& $PythonPath (Join-Path $toolDir 'parse.py') $guide --out $stepsPath --repo-root $repoRoot
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] parse.py failed for $guide." -ForegroundColor Red
    exit 1
}

$runArgs = @(
    (Join-Path $toolDir 'run.py')
    '--steps', $stepsPath
    '--recording', $recording
    '--log-dir', $LogDirectory
    '--run-id', $runId
    '--tenant-id', $tenantId
    '--tenant-domain', $domain
    '--state', $statePath
    '--auth-state', $authPath
)
if ($FromStep) { $runArgs += @('--from-step', $FromStep) }
if ($Resume)   { $runArgs += '--resume' }

Write-Host 'Starting the browser...' -ForegroundColor Yellow
& $PythonPath @runArgs
$runExit = $LASTEXITCODE

# run.py reports a count of findings (0-250) or one of two codes that are not a count.
$notStarted = 254   # a precondition or guard stopped it before the first step
$aborted    = 255   # interrupted or stopped mid-run; the state file is kept for -Resume
if ($runExit -eq $notStarted) {
    Write-Host '[ERROR] The run did not start (see the message above). Nothing is cleaned up.' -ForegroundColor Red
    exit $runExit
}
if ($runExit -eq $aborted) {
    Write-Host "Run stopped before the end. Nothing is cleaned up, so it can continue: re-run with -Resume." -ForegroundColor Yellow
    exit $runExit
}

# --- Cleanup: the lab's own script -----------------------------------------------------------
if ($SkipCleanup) {
    Write-Host 'Skipping cleanup (-SkipCleanup).' -ForegroundColor Gray
} else {
    Write-Host '=== Cleanup ===' -ForegroundColor Cyan
    if ($Lab -eq '1.1') {
        & (Join-Path $labDir.FullName 'scripts/Remove-LabResource.ps1') -Force
    } else {
        & (Join-Path $PSScriptRoot 'Remove-LabCycle.ps1') -SubscriptionId $SubscriptionId -Confirm:$false
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARNING] Cleanup exited $LASTEXITCODE. The run's results above stand; remove what is left by hand." -ForegroundColor Yellow
    }
}

if ($runExit -eq 0) {
    Write-Host "Nothing to fix in lab $Lab." -ForegroundColor Green
} else {
    Write-Host "$runExit blocking drift(s) or unknown(s) in lab $Lab. See $runDir/summary.md." -ForegroundColor Yellow
}
exit $runExit
```

- [ ] **Step 3: Run the standards tests and the dry run**

```powershell
Invoke-Pester -Path ./tests/Script-Standards.Tests.ps1, ./tests/Cbh-Coverage.Tests.ps1 -Output Normal
./tools/Invoke-DryRun.ps1 -Check Parse,Analyzer
```

Expected: green; PSScriptAnalyzer reports 0 errors and 0 warnings for the new file. If it flags
`$runExit` as unused or `Write-Host`, the former means a typo, the latter is excluded by
`PSScriptAnalyzerSettings.psd1`.

- [ ] **Step 4: Run the whole suite**

Run: `Invoke-Pester -Path ./tests -Output Normal`
Expected: green. `Gitignore.Tests.ps1` now finds `tools/Invoke-GuideDrift.ps1` tracked after the
commit below; run it again after committing.

- [ ] **Step 5: Commit**

```powershell
git add tools/Invoke-GuideDrift.ps1
git commit -m "feat(guide-drift): entry point that parses, runs and hands off to the lab's cleanup"
```

---

### Task 11: CONTRIBUTING sentence

**Files:**

- Modify: `CONTRIBUTING.md` (section "🧪 Testing", the bullet list after "All new labs and scripts must include validation steps.")

- [ ] **Step 1: Add the sentence**

Append one bullet to the list in the Testing section:

```markdown
- **Portal steps**: when a lab is revised, `.\tools\Invoke-GuideDrift.ps1 -SubscriptionId <id> -Lab X.Y` performs its portal steps in a visible browser and reports what no longer matches the Portal. A guide edit that changes a portal label updates the lab's recording in `tools/guide-drift/recordings/` in the same PR (`tests/Guide-Drift-Recording.Tests.ps1` enforces it).
```

- [ ] **Step 2: Check links and lint**

Run: `Invoke-Pester -Path ./tests/Markdown-Links.Tests.ps1 -Output Normal`
Expected: green (the bullet has no links).

- [ ] **Step 3: Commit**

```powershell
git add CONTRIBUTING.md
git commit -m "docs(contributing): name the guide drift tool and the recording rule"
```

---

### Task 12: First supervised run of lab 1.1 (live verification)

This is the PR's live verification under ADR-0006. It needs: the dedicated run account signed
in to the Portal with its language set to English; `Connect-AzAccount` on the rehearsal
subscription; `SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL` set to an address the maintainer controls;
Microsoft Graph sign-in for the cleanup script. Lab 1.1 creates 3 users, 1 guest invitation and
3 groups, all removed by `Remove-LabResource.ps1 -Force` at the end.

- [ ] **Step 1: Run supervised**

```powershell
$env:SKYCRAFT_GUIDE_DRIFT_GUEST_EMAIL = '<address you control>'
./tools/Invoke-GuideDrift.ps1 -SubscriptionId <rehearsal subscription id> -Lab 1.1
```

Answer every prompt. For a label that is not a Portal element (`Azure Portal` in step 1.1.1 is a
URL, not a button), answer `i`. For a renamed label, pick the number. For an Expected Result
prompt, type the text to look for (`Malfurion Stormrage` in 1.1.2, `SkyCraft-Admins` in 1.1.6)
or press Enter when nothing on screen states it.

- [ ] **Step 2: Fix what the run shows, in the right place**

- A guard or selector that does not work on the live Portal (the account-menu button name in
  `guard_tenant`, the sign-in detection in `wait_for_sign_in`): fix in `run.py`, re-run with
  `-Resume`.
- A bold caption parsed as a label: add it to `NON_UI_BOLD` in `parse.py` and re-run the parser
  tests.
- Two places where the parser cannot read lab 1.1 as written, known before the run: the
  invitation message of 1.1.5 is a blockquote (not read; the invitation is sent without it),
  and the member to select in 1.1.7 (`- Malfurion Stormrage`) is not bold, so the run reaches
  **Select** with nobody selected. Do the selection by hand when the run stops there, record
  the step's outcome as it is, and list both as guide findings (bold the member name; keep the
  message as a field) for the separate guide PR.
- A real drift in the guide: do **not** fix the guide in this PR. Record it; it becomes the first
  finding the tool reports, and the guide fix is its own PR with its own fresh screenshot.

- [ ] **Step 3: Re-run to prove replay**

```powershell
./tools/Invoke-GuideDrift.ps1 -SubscriptionId <rehearsal subscription id> -Lab 1.1
```

Expected: the run asks nothing it was told in Step 1; the summary matches Step 1's; exit code
equals the number of blocking drifts plus unknowns from the summary.

- [ ] **Step 4: Verify the recording and the tree**

```powershell
Invoke-Pester -Path ./tests -Output Normal
git status --short
```

Expected: green; `git status` shows only `tools/guide-drift/recordings/lab-1.1.json` modified
(the logs, state and auth files are ignored). Open the recording and confirm no e-mail address,
no UPN and no GUID beyond what the Portal view URLs carry is in it; strip query strings from
`viewUrl` values if they contain tokens.

- [ ] **Step 5: Commit the recording and tick this plan**

```powershell
git add tools/guide-drift/recordings/lab-1.1.json PLAN.md
git commit -m "feat(guide-drift): record the first supervised run of lab 1.1"
```

---

### Task 13: Pull request

- [ ] **Step 1: Delete PLAN.md in the last commit**

```powershell
git rm PLAN.md
git commit -m "chore(guide-drift): remove the implementation plan before merge"
```

- [ ] **Step 2: Push and open the PR**

Only after the maintainer approves. Branch upstream is unset by design (ADR-0003):

```powershell
git push -u origin feature/guide-drift
gh pr create --repo mbiszczanik/skycraft --title "feat(guide-drift): check portal steps of lab guides against the live Azure Portal" --body-file <body.md>
```

PR body follows `.github/PULL_REQUEST_TEMPLATE.md`: `Closes #189`; `Live-verified: lab 1.1,
guide drift run <run id>, <date>` (the run from Task 12); type of change "CI / tooling / chore";
the summary.md of the run pasted as the findings list; no screenshots (they are not anonymised).
No "Generated with" footer, no Co-Authored-By.

The PR touches `tools/` files that are not on the gate's list in
`tools/Test-PrLiveVerification.ps1`, so the `Live Verification Declared` check will pass as "not
gated"; the `Live-verified` line is still written, because the run is the PR's evidence.

---

## Self-review against #189

| Spec requirement | Task |
|---|---|
| Entry point checks Python/Playwright, resolves tenant from mandatory `-SubscriptionId` compared by id | 10 |
| Headed Chromium 1440×900, waits for sign-in, saved session | 7 |
| Guards: English Portal, expected tenant | 7 |
| Accessible-name lookup, perform action, check expected result, screenshot, one record per check | 8, 9 |
| Performs the lab for real; cleanup is the lab's own script; no deletion logic | 8, 10 |
| Parser: Step sections only, fences skipped, Option 1 only, chains, tables, Expected Result, images, non-UI bold list, `portal: false` | 2, 3, 4 |
| Outcomes match/drift/unknown/skipped; severities blocking/misleading/cosmetic | 5, 8, 9 |
| Stale and unreadable (>1722 px) screenshots as separate categories | 9 (`screenshot`, `readability`) |
| Supervised first, recorded always; rejected candidates and who decided | 5, 8 |
| `decide(step_text, label, candidates)` with replay and human; extension point for #190 | 5 |
| Value overrides (1.1.5 guest address) set at the first run, never literal in the repo | 6, 12 |
| JSONL appended as the run goes; `-Resume` from the state file; terminal summary by severity; proposed edit for plain relabelling; raw screenshots | 9 |
| Gitignored logs, state, auth; only the recording is committed | 1, 12 |
| Exit code = blocking + unknown | 9, 10 |
| Parser test over 17 guides, Option 1 only, not enforcing §5 | 2, 4 |
| Recording test: steps and labels exist in the guide | 6 |
| Gitignore test | 1 |
| Reasoning in the tool's header, one sentence in CONTRIBUTING, no ADR | 10, 11 |
| First supervised run of 1.1 is the PR's live verification | 12, 13 |

Out of scope and untouched: CI runs, CLI/PowerShell steps, editing guides or `images/`, labs
other than 1.1, §5 enforcement, model-based deciders (#190).
