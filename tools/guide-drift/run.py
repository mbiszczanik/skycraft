#!/usr/bin/env python3
"""Perform one lab guide's portal steps in a visible browser and report drift (issue #189).

Driven by tools/Invoke-GuideDrift.ps1, which resolves the tenant and parses the guide first.
Opens Chromium headed at 1440x900 on the Microsoft Entra ID overview of the tenant and waits,
without a timeout, until the overview shows its 'Tenant ID' field: the person signs in there
(multi-factor included; there is no unattended sign-in). The run then refuses to start unless
the Portal is in English and the overview shows the expected tenant ID (the domain is no proof:
the account's own address in the header carries it in any directory). Only then is the browser
session saved to --auth-state, so the next run skips the password.

Everything a run leaves behind goes under --log-dir/<run id>/ and is gitignored:
results.jsonl (one record per check, appended as the run goes), Step-X.Y.N.png (full window,
for manual cropping and anonymisation), summary.md, and blade-<step>-<line>.aria.txt for a label that
was not found (the outline the loading check read, redacted). Only the recording is written back
into the repository.

The runner acts only on a visible element within the window's width (the Portal parks earlier
blades off to the left; below the fold is fine, it scrolls there first), and only on one:
several matches are reported as unknown rather than guessed. It refuses to click or fill an
element whose name contains the word delete, remove, reset, revoke, disable, block, purge or
sign out, unless the guide's own label does too. A guide's 'Search for **X**' is typed into the
Portal's global search, and the result named exactly X in its dropdown is opened (the Services
entry, never Marketplace or Documentation); when that fails, the dropdown's accessibility tree
is kept as search-<step>.aria.txt in the run folder. A search inside a blade ('Search for
**"Owner"**' in a role assignment, scope 'blade') is typed into that blade's own search box, the
only one on screen besides the top one, and the result is checked for, not clicked: the guide's
next item clicks it. Plain text counts only when it
is, or sits inside, a link, button or other interactive element. A label is looked for until
FIND_TIMEOUT_MS has passed, as a blade renders its controls after its heading; when SETTLE_MS of
that finds nothing, the blade menu's collapsed groups are opened once ('Expand all headers') and
the looking goes on to the same deadline. When the deadline passes while a blade is still
loading (blade_still_loading: a close button reads "Close content 'undefined'", or the newest
blade's title heading has no content after it), the console says so once and the label is looked
for up to BLADE_LOAD_TIMEOUT_MS more (BLADE_EMPTY_TIMEOUT_MS for a titled blade); once the blade
has rendered, it is looked for FIND_TIMEOUT_MS again. Only then is the person asked.

A resource a navigation chain names in a code span ('**Load balancers** -> `dev-skycraft-swc-lb`
-> **Backend pools**', parse.py's "resources") is opened as the one visible link, grid cell or row
of that exact name, once the recording's placeholders are filled; a name with a placeholder left
is unknown. It is looked for as long as a label. When it opens the chain and is not on screen
(such a chain may start from anywhere: 'Navigate to `prodskycraftswcsa` -> ...'), the name is
typed into the Portal's global search and the result named exactly so is opened, as for a
'Search for **X**' item; a search that finds nothing is closed again. Later in a chain it is
looked for on screen only: the label before it opened the list or picker it is in (an endpoint
picker in a wizard, a vault's backup items), and a search would leave that. The person is never
asked about it: when it is not found, the step fails with blocking drift in category
'missing-resource' and no proposed edit, as an earlier step, another lab or the view the run is
on is at fault, not the guide's name (issue #199). Its screenshot is not marked stale for it.

When a step does not go through, the person chooses: c, finish it by hand and continue; s, skip
this step and continue with the next one, giving the reason, which the summary lists under
'skipped' (the step's own findings stay counted, and a later step that needed it may fail too
and is asked about the same way); e, end the lab: skip the rest and finish; or q, stop and keep
the state. Closed input ends the lab. A step finished by hand (c) records the view the Portal
shows when the person answers, as a step that went through does (issue #206). --state records
the completed steps (a skipped step among them, so a resume passes over it) and the step a
-Resume starts at (the one in progress, or the one that failed); a resume first asks whether
that step finished (y), must be redone (n) or is skipped (s, as above but without a reason). A
run that ends normally, whatever was skipped, marks the state finished, and it cannot be resumed.
A resumed run is the same run: it keeps the state's run id (ignoring --run-id), writes into the
same --log-dir/<run id>/ folder, and its summary and exit code cover every step of both parts.

A resumed run, and one started with --from-step, has a new browser on the Microsoft Entra ID
overview, not where the stopped run left the Portal (issue #206). So before the first step that
runs, the Portal is brought to the view that step starts from (Runner.start_view): the view the
recording keeps for the last step performed before it, passing over steps the recording skips.
After y that is the view the step in flight ended on; after n, the view the step before it ended
on, so that it is redone from there; after s, the skipped step's own view when it has one (from
an earlier run), or else the view it started from, as a failed step records none. The run opens
that view itself, pinned to the tenant, when it can: not when the view names an object by id
('<id>': the recording leaves ids out), keeps a '[token]' or '${NAME}' this run cannot fill in
(an environment variable that is not set), or is no Portal view. Otherwise it prints the view
and why it cannot open it, or says that no view is recorded for that step. Either way it waits
for Enter, as the recording keeps no query string and a view opened on its own has none of the
blades the guide opened before it: the person checks the Portal and corrects it. The answer to
the resume question is saved only then, so closed input there leaves the state as it was.

A view is recorded only from a Portal page, and only without tenant or personal data
(Redactor.view_url): the tenant pin, query strings and object ids (with or without hyphens) are
left out, and a view that still holds an address, a guest user principal name, an id or tenant
data once percent-decoded is recorded as none.

Each step starts on a blade, and the run checks it is the right one (issue #207). The recording
keeps, as the step's "startBlade", the blade part of the view the step began on (view_blade:
'Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Members', without the blade's inputs except a Browse
blade's resourceType, cut from the redacted view, so a view recorded as none gives none). It is
recorded only when none is, once the step's first item has gone through, with or without the
person's help (a step whose first item fails may have started on the wrong blade), from the
address read before that item once two readings SETTLE_MS apart agree (the Portal changes it a
moment after a Create or Save), and the console says "Recorded: step X starts on <blade>" so that
the person notices a wrong one. Before the first item of a step with a recorded blade, the open
blade is compared with it (same_blade: regardless of case and of a trailing overview) for up to
FIND_TIMEOUT_MS; when it never matches, the run reports misleading drift in category
'wrong-blade', "the step starts on X, the Portal is on Y; the guide does not say how to get
there", asks the person to bring the Portal to X and press Enter (closed input goes on as well),
and performs the step. The first step after a resume or --from-step (its browser is new; the
resume message names the blade) and the first step after a step the recording skips (its blade
depends on the skip, which is also why none is recorded for it) are asked about the same way,
with the reason and without a record: the guide is not at fault there. A step whose first item
is a global search, or a chain that opens with a resource name (looked up there), may start
anywhere and is neither checked nor recorded, and neither is a step begun on a view the run
cannot name. A recorded blade that is wrong is deleted from the recording by hand; the next
supervised run records it again. The first field acted on after anything but a field starts a
form (the rows of a form table, or '**Label**: value' items in a row), and is looked for only as
a field that can be filled in (editable, as fill_field would act on it: a text field that is
not read-only or already shows the value, any other control, or a labelled container holding a
control that takes a value), so the lookup never lands on a list's column or a read-only
summary. When there is none, the run reports the same drift ("no form with a field 'X' is open;
..."), unless the step's start was already reported or excused (one cause, one record), asks
the person to open the form and press Enter, then looks the field up as usual; when this happens
at the step's first item, the form's blade is the one recorded. A first field the recording
holds a decision for is not checked: replay finds it. Neither drift makes the guide's
screenshots stale or counts in the exit code.

A step whose recording entry carries '"skip": "<reason>"' (an optional or conceptual step that
would create resources, or the other option of a lettered pair; issue #200) is never performed:
the Portal is not touched for it, no screenshot is taken, and the summary lists it under
'skipped' with that reason. It counts as completed, so a resume passes over it, and later steps
run as usual. The step after it therefore starts on the view the step before the skip ended on,
without the blade the skipped step would have opened or the resources it would have created, and
fails if it needed them: skip only a step whose blade and resources no later step needs, or skip
those later steps too. The skip wins over everything else the entry records: its decisions, value
overrides and result are kept, for the day the skip is removed, but not read. The reason must
be a non-empty string (recording.skip_reason); the run refuses to start otherwise. A step that
was in flight when a run stopped and is skipped in the recording since (it failed, the person
answered q and added the skip) is not asked about on -Resume: its stopped attempt's findings are
dropped, as a redone step's are, and it is skipped like any other.

Exit code: blocking drifts plus unknowns, capped at 250, when the run ends normally; 254 when a
precondition, a guard or the state stopped it before the first step; 255 when it stopped mid-run
(Ctrl+C, 'q', a closed window, a crash) with the state kept for -Resume, so nothing is cleaned up.

Usage (normally via Invoke-GuideDrift.ps1):
  python run.py --steps steps.json --recording recordings/lab-1.1.json --log-dir <dir>
                --run-id 20261007-100000 --tenant-id <guid> --tenant-domain contoso.onmicrosoft.com
                --state <path> --auth-state <path> [--tenant-name "Contoso Ltd"]
                [--from-step 1.1.6] [--resume]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import time
import traceback
from pathlib import Path
from typing import Callable, TypeVar
from urllib.parse import urlsplit

from playwright.sync_api import Browser, Error as PlaywrightError, Frame, Locator, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
from decide import Candidate, Decision, HumanDecider, ReplayDecider, decide  # noqa: E402
from recording import (Redactor, checkbox_state, env_secrets, missing_env,  # noqa: E402
                       field_action, rejected_candidates, resolve_value, resource_name, skip_reason,
                       same_blade, start_blade, view_blade, write_json)

Found = TypeVar("Found")     # what in_time() looks for

PORTAL = "https://portal.azure.com"
ENTRA_OVERVIEW = "/view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview"
# A token left in a recorded view once the Redactor restored it: '[token]' or '${NAME}', which this
# run cannot fill in, so the view is not opened on resume (#206).
UNFILLED_TOKEN = re.compile(r"\[[^\]]*\]|\$\{[^}]*\}?")
SETTLE_MS = 1500
FIND_TIMEOUT_MS = 8000
CHECK_TIMEOUT_MS = 2000     # set_checked() before the label is tried, and the wait for its effect
LATE_CLICK_MS = 750         # how long an intercepted set_checked() may take to show, before the label
RESULT_TIMEOUT_S = 15
# How much longer a label is looked for while the newest blade is still loading (issue #233): on a
# slow Portal a blade's frame opens well before its form or list does.
BLADE_LOAD_TIMEOUT_MS = 60000
# The same for a blade whose title is there but whose content is not: a blade that has nothing
# but its title and buttons for good (a read-only summary) costs this much, not a minute.
BLADE_EMPTY_TIMEOUT_MS = 20000
# A blade's or pane's close button, named after its title: "Close content 'New Group'". The title
# reads 'undefined' while the blade's content is still loading.
BLADE_CLOSE = re.compile(r"^Close content '(?P<title>.*)'$")
UNTITLED_BLADE = "undefined"
# What blade_still_loading() answers: a close button titled 'undefined', or a titled blade with no
# content after its heading.
BLADE_UNTITLED, BLADE_EMPTY = "untitled", "empty"
# What a rendered blade shows after its title: form controls, list rows, tabs, tables, prose.
# Buttons, links and bare text do not count, as the blade's header has them (Maximize, Close)
# before anything else renders.
BLADE_CONTENT_ROLES = ("textbox", "searchbox", "combobox", "checkbox", "radio", "switch", "spinbutton",
                       "slider", "listbox", "row", "tab", "tabpanel", "table", "grid", "paragraph",
                       "term", "definition")
CANDIDATE_ROLES = ("button", "link", "menuitem", "tab", "treeitem", "option", "textbox",
                   "combobox", "checkbox", "radio", "heading", "cell")
FIELD_ROLES = ("textbox", "combobox", "checkbox", "radio")
ACTION_ROLES = ("button", "link", "menuitem", "tab", "treeitem", "option", "checkbox", "radio")
RESULT_ROLES = ("option", "link", "button", "menuitem")    # entries of the global search's results
# A resource in a Portal list: the link in its name cell, the cell, or the whole row (#199).
RESOURCE_ROLES = ("link", "gridcell", "row")
MISSING_RESOURCE = "missing-resource"    # the category of a resource that is not on screen
RECORDED_SKIP = "recorded-skip"          # the category of a step the recording skips (#200)
# The category of a step that starts on another blade than the recorded one, or of a form whose
# first field cannot be filled in on the open blade: the guide leaves out how to get there (#207).
WRONG_BLADE = "wrong-blade"
# The Portal's global search box, named "Search resources, services, and docs (G+/)".
SEARCH_BOX = re.compile(r"^Search resources")
# A blade's own search box (search scope 'blade'): a search box, or a text box whose accessible
# name or placeholder says search or filter.
BLADE_SEARCH_NAME = re.compile(r"search|filter", re.IGNORECASE)
IN_TOP_BAR_JS = "e => e.closest('[role=banner]') !== null"     # the Portal's top bar, not a blade
# The role and accessible name on the first line of an element's aria_snapshot().
ARIA_FIRST_LINE = re.compile(r'^\s*-\s+(?P<role>[a-z]+)(?:\s+"(?P<name>(?:[^"\\]|\\.)*)")?')
LEADING_PLUS = re.compile(r"^\s*\+\s*")   # '+ New user': the Portal names the item 'New user'
# What plain text must be, or sit inside, to count as the element a guide label names.
INTERACTIVE = ("a, button, [role=link], [role=button], [role=menuitem], [role=treeitem], [role=tab], "
               "[role=option], [role=checkbox], [role=radio]")
# A blade menu's button that opens all its collapsed groups ('Manage', 'Monitoring', 'Help').
EXPAND_ALL = "Expand all headers"
# The global search's dropdown when the box names none in aria-controls or aria-owns: a popup of
# these roles that was not visible before typing (MARK_POPUPS_JS records the visible ones first,
# NEW_POPUP_JS asks, UNMARK_POPUPS_JS forgets them after the search). Only when that record could
# not be made does a popup that starts within POPUP_GAP_PX of the box's bottom edge count instead.
POPUP_ROLES = "[role=listbox], [role=dialog], [role=menu], [role=tree], [role=grid]"
POPUP_GAP_PX = 8
MARK_POPUPS_JS = ("selector => { window.__guideDriftPopups = new Set([...document.querySelectorAll(selector)]"
                  ".filter(e => e.getClientRects().length > 0)); }")
NEW_POPUP_JS = "e => window.__guideDriftPopups ? !window.__guideDriftPopups.has(e) : null"
UNMARK_POPUPS_JS = "() => { delete window.__guideDriftPopups; }"
# A text field the person cannot type into: fill() would wait out its whole timeout.
READ_ONLY_JS = ("e => e.readOnly === true || e.hasAttribute('readonly') "
                "|| e.getAttribute('aria-readonly') === 'true'")
# Sections of the global search's dropdown: the service itself, an offer to buy, articles.
SEARCH_PREFERRED = re.compile(r"^Services\b", re.IGNORECASE)
SEARCH_EXCLUDED = re.compile(r"^(?:Marketplace|Documentation)\b", re.IGNORECASE)
SEARCH_SECTION = re.compile(r"^(?:Services|Marketplace|Documentation)\b", re.IGNORECASE)
# For one search result inside the dropdown `root`: [its group's name, the nearest heading before
# it, the text of the whole result it is or sits in], each with whitespace normalised. A group or
# heading outside the dropdown (the page's own title) is no section: ''.
RESULT_SECTION_JS = r"""(e, {interactive, root}) => {
  const clean = t => (t || '').replace(/\s+/g, ' ').trim();
  const inside = n => !!n && root.contains(n);
  const group = e.closest('[role=group]');
  let name = inside(group) ? group.getAttribute('aria-label') : '';
  if (!name && inside(group) && group.getAttribute('aria-labelledby')) {
    name = group.getAttribute('aria-labelledby').split(/\s+/)
      .map(id => (document.getElementById(id) || {}).textContent).join(' ');
  }
  const heading = document.evaluate(
    "preceding::*[self::h1 or self::h2 or self::h3 or self::h4 or self::h5 or self::h6 or @role='heading'][1]",
    e, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
  return [clean(name), clean(inside(heading) ? heading.textContent : ''),
          clean((e.closest(interactive) || e).textContent)];
}"""
# An element that takes a value itself; a labelled element that is none of these is a container
# (find_field, fill_parts). CONTROL_JS reads [tag, role attribute, contenteditable].
CONTROL_TAGS = ("input", "textarea", "select", "button")
CONTROL_ROLES = ("textbox", "searchbox", "combobox", "spinbutton", "slider", "checkbox", "radio",
                 "switch", "button", "listbox")
CONTROL_JS = "e => [e.tagName.toLowerCase(), e.getAttribute('role') || '', e.isContentEditable]"
# What a field candidate is (field_kind): [tag, role attribute, type attribute, aria-haspopup,
# contenteditable].
FIELD_KIND_JS = ("e => [e.tagName.toLowerCase(), e.getAttribute('role') || '', "
                 "(e.getAttribute('type') || '').toLowerCase(), (e.getAttribute('aria-haspopup') || '').toLowerCase(), "
                 "e.isContentEditable]")
VALUE_ROLES = ("textbox", "searchbox", "combobox", "checkbox", "radio", "switch", "listbox", "spinbutton",
               "slider")
NOT_VALUE_INPUTS = ("button", "submit", "reset", "image", "hidden")
# Whether a labelled element can be a form field at all: nothing in a table or grid header (a
# column's sort button is named after the column, 'User principal name' on the Users list), and
# a plain button only when it opens a list: aria-haspopup listbox, menu or true, or aria-expanded
# together with aria-controls or aria-owns naming a listbox or menu (aria-expanded alone is what
# an info icon's callout button has too).
FIELD_CANDIDATE_JS = r"""e => {
  if (e.closest('th, thead, [role=columnheader], [role=rowheader]')) return false;
  const role = e.getAttribute('role') || '';
  const plainButton = role === 'button' || (!role && e.tagName.toLowerCase() === 'button');
  if (!plainButton) return true;
  const popup = (e.getAttribute('aria-haspopup') || '').toLowerCase();
  if (['listbox', 'menu', 'true'].includes(popup)) return true;
  if (!e.hasAttribute('aria-expanded')) return false;
  const ids = ((e.getAttribute('aria-controls') || '') + ' ' + (e.getAttribute('aria-owns') || ''))
    .split(/\s+/).filter(Boolean);
  return ids.some(id => {
    const target = document.getElementById(id);
    return !!target && ['listbox', 'menu'].includes(target.getAttribute('role'));
  });
}"""
# For a check box's label (label_of): [whether it belongs to the input, whether it holds a link].
LABEL_CHECK_JS = "(label, input) => [label.control === input, label.querySelector('a') !== null]"
# Never acted on unless the guide itself names such an element: a wrong replay or a mistyped
# number must not delete a user or sign the person out halfway through a lab.
DESTRUCTIVE = re.compile(r"\b(delete|remove|reset|revoke|disable|block|purge|sign out)\b", re.IGNORECASE)


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--steps", type=Path, required=True)
    p.add_argument("--recording", type=Path, required=True)
    p.add_argument("--log-dir", type=Path, required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--tenant-id", required=True)
    p.add_argument("--tenant-domain", required=True)
    p.add_argument("--tenant-name", default="",
                   help="the tenant's display name, kept out of the recording as [tenantname]")
    p.add_argument("--state", type=Path, required=True)
    p.add_argument("--auth-state", type=Path, required=True)
    p.add_argument("--from-step")
    p.add_argument("--resume", action="store_true")
    return p.parse_args(argv)


def all_frames(page: Page) -> list[Frame]:
    """Main frame first, then every child frame: Entra ID blades render inside iframes."""
    return [page.main_frame] + [f for f in page.frames if f is not page.main_frame]


def aria_outline(page: Page) -> list[tuple[str, str]]:
    """(role, name) of every element line of the accessibility tree, across frames (main frame
    first), in tree order; the name is '' when the element has none. What blade_still_loading()
    reads. A child frame whose iframe lies outside the window's columns is left out: Entra ID
    blades render in iframes and the Portal parks earlier ones off to the left, where their rows
    would follow the new blade's heading and pass for its content. So is a frame that cannot be
    read."""
    outline: list[tuple[str, str]] = []
    frames = all_frames(page)
    for frame in frames:
        if frame is not frames[0] and not frame_in_window(frame, page.viewport_size):
            continue
        try:
            snapshot = frame.locator("body").aria_snapshot(timeout=2000)
        except PlaywrightError:     # timed out, or the frame went away while the Portal navigated
            continue
        for line in snapshot.splitlines():
            m = ARIA_FIRST_LINE.match(line)
            if m:
                outline.append((m.group("role"), m.group("name") or ""))
    return outline


def blade_still_loading(outline: list[tuple[str, str]]) -> str | None:
    """Whether a blade's frame is open while its content has not rendered yet (issue #233), from
    aria_outline(): BLADE_UNTITLED when any close button reads "Close content 'undefined'";
    BLADE_EMPTY when the newest blade (the one whose "Close content '<title>'" button comes last)
    has a heading named after its title but no content (BLADE_CONTENT_ROLES) after the later of
    the two; None otherwise. The top bar's search box and an older blade's fields come before
    them, so they do not count. Without a close button, or without the title heading, nothing is
    said to be loading and the lookup keeps its normal time."""
    closes = [(index, m.group("title")) for index, (role, name) in enumerate(outline)
              if role == "button" and (m := BLADE_CLOSE.match(name))]
    if not closes:
        return None
    if any(title == UNTITLED_BLADE for _, title in closes):
        return BLADE_UNTITLED
    close_at, title = closes[-1]
    headings = [index for index, (role, name) in enumerate(outline) if role == "heading" and name == title]
    if not headings:
        return None
    start = max(close_at, headings[-1])
    return None if any(role in BLADE_CONTENT_ROLES for role, _ in outline[start + 1:]) else BLADE_EMPTY


def aria_lines(page: Page) -> list[tuple[str, str, int]]:
    """(role, name, count) of every named element the accessibility tree exposes, across frames,
    in first-seen order. count is how many elements share that role and name: the Portal keeps
    earlier blades in the DOM, so 'Create' or 'Delete' often appears more than once, and a
    candidate that stands for several elements must never be clicked by name alone."""
    counts: dict[tuple[str, str], int] = {}
    for frame in all_frames(page):
        try:
            snapshot = frame.locator("body").aria_snapshot(timeout=2000)
        except PlaywrightError:     # timed out, or the frame went away while the Portal navigated
            continue
        for line in snapshot.splitlines():
            m = re.match(r'\s*-\s+(?P<role>[a-z]+)\s+"(?P<name>[^"]+)"', line)
            if m and m.group("role") in CANDIDATE_ROLES:
                key = (m.group("role"), m.group("name"))
                counts[key] = counts.get(key, 0) + 1
    return [(role, name, count) for (role, name), count in counts.items()][:300]


# --- finding and acting --------------------------------------------------------------------

class Ambiguous(LookupError):
    """Several visible elements match. The runner never clicks one of them by guess: earlier
    Portal blades stay in the DOM, and the first match in DOM order is often the wrong one."""


class PageClosed(Exception):
    """The browser window is gone. The run stops at once (ABORTED, state kept) rather than ask
    the person to choose among the candidates of an empty screen."""


class ReadOnly(LookupError):
    """The text field to type into is read-only (readonly, aria-readonly): reported at once
    rather than after fill() has waited out its timeout."""


def in_window_columns(element: Locator, viewport: dict | None) -> bool:
    """Whether the element overlaps the window horizontally. The Portal parks earlier blades off
    to the side (far left), where the DOM still calls them visible; acting on one is a guess.
    Vertical position does not count: long forms and lists scroll, and the runner scrolls an
    element into view before acting on it."""
    if viewport is None:
        return True
    return overlaps_columns(element.bounding_box(timeout=1000), viewport)


def overlaps_columns(box: dict | None, viewport: dict) -> bool:
    """Whether a bounding box (None: not rendered) overlaps the window's columns."""
    if box is None:
        return False
    return box["x"] + box["width"] > 0 and box["x"] < viewport["width"]


def frame_in_window(frame: Frame, viewport: dict | None) -> bool:
    """Whether a child frame's iframe overlaps the window's columns, as in_window_columns() asks
    of an element; the iframe is an ElementHandle, whose bounding_box() takes no timeout. A frame
    whose iframe cannot be read (it went away) does not count."""
    if viewport is None:
        return True
    try:
        iframe = frame.frame_element()
        try:
            return overlaps_columns(iframe.bounding_box(), viewport)
        finally:
            iframe.dispose()
    except PlaywrightError:
        return False


def visible_in(locator: Locator, viewport: dict | None) -> list[Locator]:
    """The elements of `locator` that are visible and, when `viewport` is given, overlap the
    window horizontally. is_visible() does not wait. An element that cannot be inspected (it
    went away mid-check) still counts: dropping it could turn two matches into one, and the
    runner would act on a guess. A frame that goes away raises PlaywrightError from count(),
    which callers handle per frame."""
    found = []
    for index in range(locator.count()):
        element = locator.nth(index)
        try:
            counts = element.is_visible() and in_window_columns(element, viewport)
        except PlaywrightError:
            counts = True
        if counts:
            found.append(element)
    return found


def visible_across_frames(page: Page, make_locator: Callable[[Frame], Locator],
                          anywhere: bool = False) -> list[Locator]:
    """Visible matches in every frame; outside the window's columns too when `anywhere`."""
    found: list[Locator] = []
    for frame in all_frames(page):
        try:
            found += visible_in(make_locator(frame), None if anywhere else page.viewport_size)
        except PlaywrightError:     # the frame detached or navigated: nothing to act on there
            continue
    return found


def only_one(found: list[Locator], by_text: bool = False) -> Locator | None:
    """The one element of `found`, or None when it is empty; raises Ambiguous when there are
    several. The default choice of find_in_roles, whose signature `by_text` belongs to."""
    if len(found) > 1:
        raise Ambiguous(f"{len(found)} visible elements match")
    return found[0] if found else None


def unique_visible(page: Page, make_locator: Callable[[Frame], Locator]) -> Locator | None:
    """The one visible element `make_locator(frame)` matches across all frames, or None when there
    is none; raises Ambiguous when there are several."""
    return only_one(visible_across_frames(page, make_locator))


def text_on_screen(page: Page, text: str) -> bool:
    """Whether the text is visible anywhere on the page: presence, not position, so a created
    group listed below the fold still counts."""
    return bool(visible_across_frames(page, lambda f: f.get_by_text(text, exact=False), anywhere=True))


def interactive_text(scope: Frame | Locator, label: str) -> Locator:
    """Text whose whole text is `label` (get_by_text, exact: whitespace normalised, child elements
    included, so '<a>Users<span> (preview)</span></a>' is not 'Users') and that is, or sits
    inside, an interactive element (INTERACTIVE); clicking the text clicks that element. The
    constraint is part of the locator rather than a check after it, so a re-render between
    count() and nth(k) cannot move a match onto a static caption."""
    return scope.get_by_text(label, exact=True).and_(scope.locator(f":is({INTERACTIVE}), :is({INTERACTIVE}) *"))


# find_in_roles' choice among the visible matches of one role (by_text False) or of the text.
Choose = Callable[[list[Locator], bool], "Locator | None"]


def find_in_roles(page: Page, label: str, roles: tuple[str, ...], root: Locator | None = None,
                  choose: Choose = only_one) -> Locator | None:
    """The visible element of the first of `roles` whose accessible name is exactly `label`, then
    plain text that is, or sits inside, an interactive element (interactive_text). Static text is
    never a match: the Entra overview's 'Basic information' table has a 'Users' caption, and
    clicking it navigates nowhere. Every frame is searched, or only inside `root` when it is
    given (the global search's results). `choose` picks among the matches of one role, or of the
    text: by default there must be at most one, and several raise Ambiguous. An ambiguous text
    match counts as not found, so the person picks a role-specific candidate."""
    def matches(make_locator: Callable[[Frame | Locator], Locator]) -> list[Locator]:
        if root is None:
            return visible_across_frames(page, make_locator)
        try:
            return visible_in(make_locator(root), page.viewport_size)
        except PlaywrightError:     # the results went away while the Portal reloaded them
            return []

    for role in roles:
        element = choose(matches(lambda s, role=role: s.get_by_role(role, name=label, exact=True)), False)
        if element is not None:
            return element
    try:
        return choose(matches(lambda s: interactive_text(s, label)), True)
    except Ambiguous:
        return None


def is_control(element: Locator) -> bool:
    """Whether the element takes a value itself (CONTROL_TAGS, CONTROL_ROLES, contenteditable)
    rather than being a container labelled for one. An element that cannot be inspected counts
    as a control: it is acted on as before, and the error that follows is reported."""
    try:
        tag, role, editable = element.evaluate(CONTROL_JS, timeout=1000)
    except PlaywrightError:
        return True
    return tag in CONTROL_TAGS or role in CONTROL_ROLES or bool(editable)


def field_kind(element: Locator) -> tuple[str, str | None]:
    """(what the element is, for a message: its role, or its tag; and its tier for one_field):
    'value' for an element that takes a value itself (a text box or text area, a select, a combo
    box, check box, radio, switch, list box, spin button or slider, or contenteditable), 'dropdown'
    for a button that opens a list (aria-haspopup listbox, menu or true), None for anything else,
    such as the info icon next to a label. An element that cannot be inspected is '?', with no
    tier."""
    try:
        tag, role, input_type, popup, editable = element.evaluate(FIELD_KIND_JS, timeout=1000)
    except PlaywrightError:
        return "?", None
    what = role or (f"{tag}[type={input_type}]" if tag == "input" and input_type else tag)
    if editable or role in VALUE_ROLES or (not role and (tag in ("textarea", "select")
                                                         or (tag == "input" and input_type not in NOT_VALUE_INPUTS))):
        return what, "value"
    if (role == "button" or (not role and tag == "button")) and popup in ("listbox", "menu", "true"):
        return what, "dropdown"
    return what, None


def one_field(found: list[Locator]) -> Locator | None:
    """The field among the elements a label matches: the only one, or else the only one that
    takes a value, or else the only button that opens a list (field_kind). Fluent UI forms put
    more than the field under a label ('Group description' and its info icon). Raises Ambiguous
    naming what matched ('textarea, button'), so a live run shows what collided, and whenever
    one of them could not be inspected: it may be the field, and dropping it would be a guess."""
    if len(found) <= 1:
        return found[0] if found else None
    kinds = [field_kind(element) for element in found]
    inspected = all(what != "?" for what, _ in kinds)
    for tier in ("value", "dropdown") if inspected else ():
        picked = [element for element, (_, kind) in zip(found, kinds) if kind == tier]
        if len(picked) == 1:
            return picked[0]
        if picked:
            break
    raise Ambiguous(f"{len(found)} visible elements match ({', '.join(what for what, _ in kinds)})")


def can_be_field(element: Locator) -> bool:
    """Whether the element can be a form field (FIELD_CANDIDATE_JS). One that cannot be inspected
    still counts: dropping it could turn two matches into one, and the runner would act on a
    guess."""
    try:
        return bool(element.evaluate(FIELD_CANDIDATE_JS, timeout=1000))
    except PlaywrightError:
        return True


def is_read_only(element: Locator) -> bool:
    """Whether the text field is read-only (READ_ONLY_JS). One that cannot be inspected is not:
    fill() then reports what went wrong."""
    try:
        return bool(element.evaluate(READ_ONLY_JS, timeout=1000))
    except PlaywrightError:
        return False


def parts_of(container: Locator, role: str) -> list[Locator]:
    """The visible elements of `role` inside `container`."""
    try:
        return visible_in(container.get_by_role(role), None)
    except PlaywrightError:     # the container went away
        return []


def find_field(page: Page, label: str) -> Locator | None:
    """The element the label belongs to, or a textbox, combobox, checkbox or radio of that name,
    and nothing else. A labelled container that is not a control itself gives way to a control
    of the label (another labelled element, or a text box of that name), unless it holds a combo
    box: the Portal's 'User principal name' is a <div aria-label> around a text box, an '@' and
    a domain combo box, and fill_field splits the value over those parts. Only elements that can
    be a field count (can_be_field): a list's column header or a plain button of the label's
    name is never taken for the field, so the field is not found and the person decides. Of
    several matches, the one that takes a value wins (one_field). An ambiguous match raises
    Ambiguous."""
    def fields(make_locator: Callable[[Frame], Locator]) -> list[Locator]:
        return [element for element in visible_across_frames(page, make_locator) if can_be_field(element)]

    labelled = fields(lambda f: f.get_by_label(label, exact=True))
    if labelled:
        controls = [element for element in labelled if is_control(element)]
        containers = [element for element in labelled if not any(element is c for c in controls)]
        composite = [element for element in containers if parts_of(element, "combobox")]
        if composite or controls:
            return one_field(composite or controls)
        textbox = one_field(fields(lambda f: f.get_by_role("textbox", name=label, exact=True)))
        return textbox or one_field(containers)
    for role in FIELD_ROLES:
        element = one_field(fields(lambda f, role=role: f.get_by_role(role, name=label, exact=True)))
        if element is not None:
            return element
    return None


def editable(element: Locator, value: str = "") -> bool:
    """Whether a field find_field found can be filled in with `value`, so a form is open (#207),
    judged as fill_field acts on it. A check box, radio, switch, select, combo box or button is
    picked or ticked, not typed into, so it counts whatever its aria-readonly says. A text field
    counts unless it is read-only (a user's Overview shows 'User principal name' as a read-only
    text box), or when it already shows `value`, which fill_field leaves as it is. A labelled
    container counts when it holds any control that takes a value (VALUE_ROLES: the Portal's
    'User principal name' on the New user form, a group of radios). One that cannot be inspected
    counts, as for is_control."""
    if not is_control(element):
        return any(parts_of(element, role) for role in VALUE_ROLES)
    try:
        tag, role, input_type, _, _ = element.evaluate(FIELD_KIND_JS, timeout=1000)
    except PlaywrightError:
        return True
    if (role in ("checkbox", "radio", "switch", "combobox", "button") or tag in ("select", "button")
            or (tag == "input" and input_type in ("checkbox", "radio"))):
        return True
    if not is_read_only(element):
        return True
    try:
        return current_text(element, tag) == value
    except PlaywrightError:
        return False


def starts_anywhere(item: dict) -> bool:
    """Whether a step whose first item is `item` may start on any blade (#207): a search in the
    Portal's global search (a 'search' item without scope 'blade'), or a chain that opens with a
    resource name, which is looked up there when it is not on screen (#199)."""
    if item["kind"] == "search":
        return item.get("scope") != "blade"
    return 0 in item.get("resources", ())


def find_exact(page: Page, label: str, field: bool = False) -> Locator | None:
    """The visible element whose accessible name is exactly `label`: for a field, find_field;
    otherwise the interactive roles, then plain text (find_in_roles). When nothing has the name
    and the label starts with '+' ('+ New user'), it is looked up again without the '+': the
    Portal draws the '+' as an icon, so the toolbar item is named 'New user'. That is still the
    element the guide names, not drift."""
    element = find_field(page, label) if field else find_in_roles(page, label, ACTION_ROLES)
    bare = LEADING_PLUS.sub("", label, count=1)
    if element is None and bare and bare != label:
        return find_exact(page, bare, field)
    return element


def find_resource(page: Page, name: str) -> Locator | None:
    """The visible link, grid cell or row (RESOURCE_ROLES) whose accessible name is exactly
    `name`, then plain text of that name that is, or sits inside, an interactive element
    (find_in_roles): a resource a navigation chain names (#199). No '+' is dropped and no menu
    group is opened: a resource is listed, it is not a toolbar or menu entry."""
    return find_in_roles(page, name, RESOURCE_ROLES)


def in_time(page: Page, look: Callable[[], Found | None], ms: int = FIND_TIMEOUT_MS) -> Found | None:
    """What `look()` finds, asked every 250 ms until it finds something or `ms` (FIND_TIMEOUT_MS)
    has passed; None then. A blade renders its controls a moment after its heading (step 1.1.9:
    the New Group form showed only its title when 'Group type' was looked up), so one look before
    the person is asked is not enough. An Ambiguous look is retried too, and raised only when it
    lasts to the deadline. Raises PageClosed when the window is gone."""
    deadline = time.monotonic() + ms / 1000
    while True:
        ambiguous: Ambiguous | None = None
        try:
            found = look()
        except Ambiguous as error:
            found, ambiguous = None, error
        if found is not None:
            return found
        if time.monotonic() >= deadline:
            if ambiguous is not None:
                raise ambiguous
            return None
        if page.is_closed():
            raise PageClosed("the browser window was closed")
        page.wait_for_timeout(250)


def by_id(element_id: str) -> str:
    """A CSS selector for the element with this id, whatever characters the id holds."""
    return '[id="' + element_id.replace("\\", "\\\\").replace('"', '\\"') + '"]'


def owned_ids(element: Locator) -> list[str]:
    """The ids the element names in aria-controls, or else in aria-owns."""
    owned = (element.get_attribute("aria-controls", timeout=1000)
             or element.get_attribute("aria-owns", timeout=1000) or "")
    return owned.split()


def search_box(page: Page) -> tuple[Frame, Locator] | None:
    """The Portal's global search box and the frame it is in; None when it is not on screen.
    Raises Ambiguous when there are several."""
    found: list[tuple[Frame, Locator]] = []
    for frame in all_frames(page):
        try:
            found += [(frame, box) for box in visible_in(frame.get_by_role("combobox", name=SEARCH_BOX),
                                                         page.viewport_size)]
        except PlaywrightError:     # the frame detached or navigated
            continue
    if len(found) > 1:
        raise Ambiguous(f"{len(found)} visible search boxes")
    return found[0] if found else None


def search_dropdown(page: Page, frame: Frame, box: Locator) -> Locator | None:
    """The list of results under the search box; None while there is none (the results are
    still loading). When the box names it in aria-controls or aria-owns, that element and nothing
    else. Otherwise the nearest visible popup (POPUP_ROLES) below the box and overlapping it
    horizontally that was not visible before typing (search_portal records the visible popups
    before it types), so a list or grid already on the page is never taken for the results; only
    when that record could not be made, one that starts within POPUP_GAP_PX of the box's bottom
    edge."""
    try:
        owned = owned_ids(box)
        if owned:
            for owned_id in owned:
                found = visible_in(frame.locator(by_id(owned_id)), None)
                if len(found) == 1:
                    return found[0]
            return None
        under = box.bounding_box(timeout=1000)
        if under is None:
            return None
        nearest: tuple[float, Locator] | None = None
        for popup in visible_in(frame.locator(POPUP_ROLES), page.viewport_size):
            rect = popup.bounding_box(timeout=1000)
            if (rect is None or rect["y"] < under["y"] or rect["x"] >= under["x"] + under["width"]
                    or rect["x"] + rect["width"] <= under["x"]):
                continue
            distance = rect["y"] - (under["y"] + under["height"])
            new = popup.evaluate(NEW_POPUP_JS, timeout=1000)     # None: there is no record
            if new is False or (new is None and abs(distance) > POPUP_GAP_PX):
                continue
            if nearest is None or distance < nearest[0]:     # a tie keeps the outer popup
                nearest = (distance, popup)
        return nearest[1] if nearest else None
    except PlaywrightError:     # the box or the popup went away mid-check
        return None


def search_result(label: str, root: object) -> Choose:
    """find_in_roles' choice among exact results in the search dropdown `root` (an element
    handle). The Portal lists a service under 'Services' and again under 'Marketplace' (an offer
    to buy) and in 'Documentation' links; the section is the result's group name, or the nearest
    heading before it, either only when it is inside the dropdown. Results in Marketplace or
    Documentation never count. One result in Services wins; several there are Ambiguous. A
    result with no identifiable section never counts when another result has one (it cannot be
    told apart from a Marketplace entry), and otherwise only when it is the only one left;
    several are Ambiguous. Plain text counts only when the whole result it sits in reads `label`,
    not when it is the highlighted part of a longer result ('Microsoft Entra ID Protection'). A
    result that changes while it is read raises Ambiguous, so the caller looks again."""
    def choose(found: list[Locator], by_text: bool) -> Locator | None:
        read: list[tuple[Locator, str, str]] = []
        for element in found:
            try:
                group, heading, whole = element.evaluate(
                    RESULT_SECTION_JS, {"interactive": INTERACTIVE, "root": root}, timeout=1000)
            except PlaywrightError as error:
                raise Ambiguous(f"a result changed while it was read ({type(error).__name__})") from error
            read.append((element, group if SEARCH_SECTION.match(group) else heading, whole))
        sectioned = any(section for _, section, _ in read)
        services: list[Locator] = []
        others: list[Locator] = []
        for element, section, whole in read:
            if (SEARCH_EXCLUDED.match(section) or (by_text and whole != label)
                    or (sectioned and not section)):
                continue
            (services if SEARCH_PREFERRED.match(section) else others).append(element)
        if len(services) > 1:
            raise Ambiguous(f"{len(services)} visible results in Services match")
        if services:
            return services[0]
        if len(others) > 1:
            raise Ambiguous(f"{len(others)} visible results match, none of them under Services")
        return others[0] if others else None
    return choose


def tree_of(dropdown: Locator | None, frame: Frame) -> str:
    """The accessibility tree of the search results, or of the whole frame when no results list
    was identified: what the next run's fix needs to see."""
    target, what = ((dropdown, "the search results") if dropdown is not None
                    else (frame.locator("body"), "no results list identified; the whole frame"))
    try:
        return f"# {what}\n{target.aria_snapshot(timeout=2000)}"
    except PlaywrightError as error:
        return f"# {what}: no snapshot ({type(error).__name__}: {error})"


def search_portal(page: Page, label: str, diagnose: Callable[[str], None] | None = None) -> Locator | None:
    """Type `label` into the Portal's global search and return the result named exactly `label`
    in its dropdown (search_dropdown, search_result): an option, link, button or menu item, then
    plain text. Nothing outside the dropdown counts, so a same-named link already on the page (a
    favourite in the portal menu, a tile on Home) is never clicked. The results load as the
    Portal answers, so they are looked for until FIND_TIMEOUT_MS has passed; an ambiguous look
    is retried too. When there is no exact result, or the last look was ambiguous, `diagnose` is
    given the dropdown's accessibility tree; then None is returned (the person picks from the
    list still open on screen) or the last Ambiguous raised. Raises LookupError when the search
    box is not on screen, PageClosed when the window is gone."""
    found = in_time(page, lambda: search_box(page))
    if found is None:
        if page.is_closed():
            raise PageClosed("the browser window was closed")
        raise LookupError("the Portal's search box is not on screen")
    frame, box = found
    try:
        frame.evaluate(MARK_POPUPS_JS, POPUP_ROLES)
    except PlaywrightError:         # then only a popup right under the box counts
        pass
    try:
        return search_results(page, frame, box, label, diagnose)
    finally:
        try:
            frame.evaluate(UNMARK_POPUPS_JS)
        except PlaywrightError:     # the page navigated or closed: the record went with it
            pass


def search_results(page: Page, frame: Frame, box: Locator, label: str,
                   diagnose: Callable[[str], None] | None) -> Locator | None:
    """search_portal once the popups on the page are recorded: type, then look for the result."""
    try:
        box.fill(label, timeout=FIND_TIMEOUT_MS)
    except PlaywrightError:
        if page.is_closed():
            raise PageClosed("the browser window was closed") from None
        raise
    page.wait_for_timeout(SETTLE_MS)
    deadline = time.monotonic() + FIND_TIMEOUT_MS / 1000
    while True:
        dropdown = search_dropdown(page, frame, box)
        ambiguous: Ambiguous | None = None
        if dropdown is not None:
            result = None
            try:
                root = dropdown.element_handle(timeout=1000)
                try:
                    result = find_in_roles(page, label, RESULT_ROLES, root=dropdown,
                                           choose=search_result(label, root))
                finally:
                    root.dispose()
            except Ambiguous as error:
                ambiguous = error
            except PlaywrightError:     # the dropdown went away while the Portal reloaded it
                pass
            if result is not None:
                return result
        if time.monotonic() >= deadline:
            break
        page.wait_for_timeout(500)
    if diagnose is not None:
        diagnose(tree_of(dropdown, frame))
    if ambiguous is not None:
        raise ambiguous
    return None


def close_search(page: Page) -> None:
    """Empty the Portal's global search box and press Escape, so a lookup that found nothing
    leaves no dropdown open over the next step. Nothing happens when the box is gone, there are
    several, or it cannot be typed in: the step has failed already."""
    try:
        found = search_box(page)
        if found is not None:
            found[1].fill("", timeout=FIND_TIMEOUT_MS)
            found[1].press("Escape", timeout=FIND_TIMEOUT_MS)
    except (PlaywrightError, Ambiguous):
        pass


def choose_search_box(boxes: list[dict]) -> tuple[int | None, str | None]:
    """Which of `boxes` is the open blade's or pane's own search box. Each box is a descriptor:
    'role' ('searchbox' or 'textbox'), 'name' (accessible name), 'placeholder' and 'global' (it
    sits in the Portal's top bar, [role=banner]). A search box counts, and a text box whose name
    or placeholder says search or filter; the Portal's top search box never does, whatever its
    role: it is in the top bar, or named like it (SEARCH_BOX).
    Returns (index, None), or (None, why): 'no search box on the open blade', or 'ambiguous: N
    search boxes (names)'. The Portal offers no marker the runner could rely on for the blade or
    pane opened last, so several boxes are never narrowed down by guess; blades parked off to
    the left are already left out (visible_in)."""
    candidates = [index for index, box in enumerate(boxes)
                  if not box["global"] and not SEARCH_BOX.match(box["name"]) and (box["role"] == "searchbox" or (
                      box["role"] == "textbox"
                      and BLADE_SEARCH_NAME.search(f"{box['name']} {box['placeholder']}")))]
    if not candidates:
        return None, "no search box on the open blade"
    if len(candidates) > 1:
        names = ", ".join(f"'{boxes[i]['name'] or boxes[i]['placeholder'] or '(no name)'}'" for i in candidates)
        return None, f"ambiguous: {len(candidates)} search boxes ({names})"
    return candidates[0], None


def accessible_name(element: Locator) -> str:
    """The element's accessible name, as the first line of its aria_snapshot() gives it."""
    m = ARIA_FIRST_LINE.match(element.aria_snapshot(timeout=1000))
    return (m.group("name") or "") if m else ""


def blade_search_boxes(page: Page) -> list[tuple[Locator, dict]]:
    """Every visible search box and text box in the window's columns, in every frame, with its
    descriptor for choose_search_box; 'global' marks one in the Portal's top bar ([role=banner]).
    An element that cannot be read raises Ambiguous, so in_time looks again rather than choose
    among the rest."""
    found: list[tuple[Locator, dict]] = []
    for frame in all_frames(page):
        try:
            for role in ("searchbox", "textbox"):
                for element in visible_in(frame.get_by_role(role), page.viewport_size):
                    found.append((element, {
                        "role": role, "name": accessible_name(element),
                        "placeholder": element.get_attribute("placeholder", timeout=1000) or "",
                        "global": bool(element.evaluate(IN_TOP_BAR_JS, timeout=1000))}))
        except PlaywrightError as error:
            raise Ambiguous(f"a search box changed while it was read ({type(error).__name__})") from error
    return found


def results_of(page: Page, box: Locator) -> Locator | None:
    """The visible element the search box names in aria-controls or aria-owns (its results
    list), or None when it names none or that element is not on screen."""
    try:
        owned = owned_ids(box)
    except PlaywrightError:
        return None
    for owned_id in owned:
        try:
            area = unique_visible(page, lambda f, owned_id=owned_id: f.locator(by_id(owned_id)))
        except Ambiguous:
            continue
        if area is not None:
            return area
    return None


def listed(page: Page, box: Locator, label: str) -> bool:
    """Whether a visible element's text is exactly `label`: inside the box's results list when it
    names one (results_of), else anywhere in the window. The box's own value is not a text node,
    so typing `label` does not list it."""
    area = results_of(page, box)
    if area is None:
        return bool(visible_across_frames(page, lambda f: f.get_by_text(label, exact=True)))
    try:
        return bool(visible_in(area.get_by_text(label, exact=True), page.viewport_size))
    except PlaywrightError:     # the list went away while the blade reloaded it
        return False


# The end of a blade search's observation when the label was listed before it too; finish()
# lists such matches under "unconfirmed searches".
UNCONFIRMED = "the search's effect is not confirmed"


def search_outcome(label: str, before: bool, after: bool) -> tuple[str, str]:
    """(outcome, observed) of a blade search from whether `label` was listed before and after
    it. Listed only after: match. Listed before too: match, but the observation says the
    search's effect is not confirmed, since an unfiltered list, a breadcrumb or a title already
    showed it. Not listed after: unknown."""
    if not after:
        return "unknown", f"no result for '{label}' after the search"
    if before:
        return "match", f"'{label}' was listed before the search too; {UNCONFIRMED}"
    return "match", label


def stays_disabled(page: Page, element: Locator) -> bool:
    """Whether the element is still disabled after FIND_TIMEOUT_MS. The Portal greys controls out
    for a moment while a blade loads ('Create new user' under '+ New user'), so one look is not
    enough; is_disabled() itself returns at once, so it is asked again every 250 ms."""
    deadline = time.monotonic() + FIND_TIMEOUT_MS / 1000
    while element.is_disabled(timeout=FIND_TIMEOUT_MS):
        if time.monotonic() >= deadline:
            return True
        page.wait_for_timeout(250)
    return False


def find_by_name(page: Page, role: str | None, name: str | re.Pattern[str]) -> Locator | None:
    """The element a decision chose, by role and name: a string matches exactly and case-
    sensitively, a pattern (Redactor.matcher) as written. Raises Ambiguous rather than guess."""
    if role:
        return unique_visible(page, lambda f: f.get_by_role(role, name=name, exact=True))
    return unique_visible(page, lambda f: f.get_by_text(name, exact=True))


def candidates_on_screen(page: Page) -> list[Candidate]:
    return [Candidate(role=role, name=name, count=count) for role, name, count in aria_lines(page)]


def current_text(element: Locator, tag: str) -> str:
    if tag in ("input", "textarea"):
        return element.input_value(timeout=FIND_TIMEOUT_MS)
    return element.inner_text(timeout=FIND_TIMEOUT_MS).strip()


def find_option(page: Page, element: Locator, name: str | re.Pattern[str]) -> Locator | None:
    """The option called `name` of the open combo box `element`: inside the listbox it names in
    aria-controls or aria-owns, when that is on screen; otherwise anywhere on screen. Raises
    Ambiguous when several options have the name."""
    try:
        owned = owned_ids(element)
    except PlaywrightError:
        owned = []
    for owned_id in owned:
        try:
            listbox = unique_visible(page, lambda f, owned_id=owned_id: f.locator(by_id(owned_id)))
        except Ambiguous:
            continue
        if listbox is not None:
            try:
                return only_one(visible_in(listbox.get_by_role("option", name=name, exact=True),
                                           page.viewport_size))
            except PlaywrightError:     # the list closed or reloaded: look again
                return None
    return find_by_name(page, "option", name)


def pick_option(page: Page, element: Locator, tag: str, value: str, ignore_case: bool = False) -> str | None:
    """Open the combo box or drop-down button `element` and pick the option named `value`;
    'already set' when it shows `value` already. With `ignore_case`, names are compared regardless
    of case (a domain). The options load as the Portal answers, so they are looked for until
    FIND_TIMEOUT_MS has passed (find_option), and so is the field's text after the click, which
    the Portal may update late. Raises LookupError when no option has the name, or when the
    element does not show `value` by then; Ambiguous when several options have the name."""
    def shows(text: str) -> bool:
        return text == value or (ignore_case and text.casefold() == value.casefold())

    if shows(current_text(element, tag)):
        return "already set"
    element.click(timeout=FIND_TIMEOUT_MS)
    page.wait_for_timeout(SETTLE_MS // 2)
    name = re.compile("^" + re.escape(value) + "$", re.IGNORECASE) if ignore_case else value
    deadline = time.monotonic() + FIND_TIMEOUT_MS / 1000
    option = find_option(page, element, name)
    while option is None and time.monotonic() < deadline:
        page.wait_for_timeout(250)
        option = find_option(page, element, name)
    if option is None:
        raise LookupError(f"option '{value}' not found")
    option.click(timeout=FIND_TIMEOUT_MS)
    deadline = time.monotonic() + FIND_TIMEOUT_MS / 1000
    shown = current_text(element, tag)
    while not shows(shown) and time.monotonic() < deadline:
        page.wait_for_timeout(250)
        shown = current_text(element, tag)
    if not shows(shown):
        raise LookupError(f"option '{value}' was clicked, but the field shows '{shown}'")
    return None


def fill_parts(page: Page, container: Locator, value: str) -> str | None:
    """Give `value` to a labelled container that is not a control itself (find_field). With one
    text box and nothing else, the text box gets the value. With one text box and one combo box
    and an '@' in the value (the Portal's user principal name: name, '@', domain), the combo box
    must show the part after the last '@', compared regardless of case (when it does not, the
    domain is picked from its options), and then the text box gets the part before it.
    'already set' when every part held its value before. Raises LookupError for any other
    container, or when the domain cannot be picked; Ambiguous when several options carry it."""
    textboxes, comboboxes = parts_of(container, "textbox"), parts_of(container, "combobox")
    if len(textboxes) == 1 and not comboboxes:
        return fill_field(page, textboxes[0], value)
    if len(textboxes) == 1 and len(comboboxes) == 1 and "@" in value:
        local, domain = value.rsplit("@", 1)
        try:
            tag = comboboxes[0].evaluate(CONTROL_JS, timeout=FIND_TIMEOUT_MS)[0]
            picked = pick_option(page, comboboxes[0], tag, domain, ignore_case=True)
        except Ambiguous:
            raise
        except LookupError as error:
            raise LookupError(f"the domain combo box: {error}") from error
        typed = fill_field(page, textboxes[0], local)
        return "already set" if typed and picked else None
    raise LookupError(f"the labelled element is not a field: it holds {len(textboxes)} text box(es) "
                      f"and {len(comboboxes)} combo box(es)")


def label_of(element: Locator) -> Locator:
    """The one label to click for a check box or radio: the closest <label> around it, or the
    <label for=its id> anywhere in its document. It must be the only one on screen, belong to
    this input (label.control) and hold no link, which a click could follow. Raises LookupError
    saying which of these failed."""
    paths = ["ancestor::label[1]"]
    element_id = element.get_attribute("id", timeout=1000) or ""
    if element_id and "'" not in element_id:
        paths.append(f"ancestor::*[last()]//label[@for='{element_id}']")
    labels = visible_in(element.locator("xpath=" + " | ".join(paths)), None)
    if not labels:
        raise LookupError("it has no label to click")
    if len(labels) > 1:
        raise LookupError(f"it has {len(labels)} labels on screen, not one")
    handle = element.element_handle(timeout=1000)
    try:
        belongs, has_link = labels[0].evaluate(LABEL_CHECK_JS, handle, timeout=1000)
    finally:
        handle.dispose()
    if not belongs:
        raise LookupError("its label belongs to another control")
    if has_link:
        raise LookupError("its label holds a link, which a click could follow")
    return labels[0]


def set_check_state(page: Page, element: Locator, checked: bool) -> None:
    """Tick or clear the check box, radio or switch `element`. Fluent UI draws the tick mark
    over the input ('ms-Checkbox-checkmark' inside its label), so set_checked() can time out on
    an intercepted click. Then the state is read for LATE_CLICK_MS, in case the click went
    through late, and only if it is still wrong is the input's label (label_of) clicked once,
    which toggles it as a person's click does; the state is then read until CHECK_TIMEOUT_MS has
    passed. The label is never clicked twice: a second click would toggle it back. Raises
    LookupError when the state cannot be set, PlaywrightError for any other failure."""
    wanted = "checked" if checked else "unchecked"
    try:
        element.set_checked(checked, timeout=CHECK_TIMEOUT_MS)
        return
    except PlaywrightError as error:
        reason = str(error)
        if "intercepts pointer events" not in reason and "timeout" not in reason.lower():
            raise
    if state_within(page, element, checked, LATE_CLICK_MS):     # the click went through late
        return
    try:
        label = label_of(element)
    except LookupError as error:
        raise LookupError(f"the click to make it {wanted} was intercepted ({reason.splitlines()[0]}), "
                          f"and {error}") from None
    label.click(timeout=FIND_TIMEOUT_MS)
    if not state_within(page, element, checked, CHECK_TIMEOUT_MS):
        raise LookupError(f"its label was clicked to make it {wanted}, but it is still "
                          f"{'unchecked' if checked else 'checked'}")


def state_within(page: Page, element: Locator, checked: bool, ms: int) -> bool:
    """Whether the check box shows `checked` within `ms`, read every 250 ms."""
    deadline = time.monotonic() + ms / 1000
    while element.is_checked(timeout=FIND_TIMEOUT_MS) != checked:
        if time.monotonic() >= deadline:
            return False
        page.wait_for_timeout(250)
    return True


def fill_field(page: Page, element: Locator, value: str) -> str | None:
    """Give the field `value`: tick or clear a checkbox or radio, pick an option, or type; a
    labelled container that is not a control itself is filled through its parts (fill_parts).
    Returns 'already set' when the field held the value before, and does nothing then. Raises
    LookupError when the value cannot be applied (not a checkbox state, no such option)."""
    if not is_control(element):
        return fill_parts(page, element, value)
    role = element.get_attribute("role", timeout=FIND_TIMEOUT_MS) or ""
    tag, input_type = element.evaluate("e => [e.tagName.toLowerCase(), (e.getAttribute('type') || '').toLowerCase()]")
    if role in ("checkbox", "radio", "switch") or (tag == "input" and input_type in ("checkbox", "radio")):
        checked = checkbox_state(value)
        if checked is None:
            raise LookupError(f"'{value}' is not a checkbox state")
        if element.is_checked(timeout=FIND_TIMEOUT_MS) == checked:
            return "already set"
        set_check_state(page, element, checked)
    elif tag == "select":
        selected = element.evaluate("e => e.selectedIndex >= 0 ? e.options[e.selectedIndex].text.trim() : ''")
        if selected == value:
            return "already set"
        element.select_option(value, timeout=FIND_TIMEOUT_MS)   # an option whose value or label is `value`
    elif role in ("combobox", "button") or tag == "button":
        if pick_option(page, element, tag, value):
            return "already set"
    else:
        if current_text(element, tag) == value:
            return "already set"
        if is_read_only(element):
            raise ReadOnly("the field is read-only")
        element.fill(value, timeout=FIND_TIMEOUT_MS)
    page.wait_for_timeout(SETTLE_MS // 2)
    return None


def fill_tag(page: Page, name: str, value: str) -> None:
    """The Portal's Tags grid ends with an empty row whose inputs are named 'Name' and 'Value';
    typing into it adds the next empty row. Fill the last of each. The exact roles are confirmed
    in the first supervised run (Task 12); until then a miss is reported as unknown, not guessed."""
    for frame in all_frames(page):
        try:
            names = frame.get_by_role("combobox", name="Name", exact=True)
            if names.count() == 0:
                names = frame.get_by_label("Name", exact=True)
            values = frame.get_by_role("combobox", name="Value", exact=True)
            if values.count() == 0:
                values = frame.get_by_label("Value", exact=True)
            grid = names.count() > 0 and values.count() > 0
        except PlaywrightError:     # the frame went away: look in the others
            continue
        if grid:
            names.last.fill(name, timeout=FIND_TIMEOUT_MS)
            page.wait_for_timeout(SETTLE_MS // 2)
            values.last.fill(value, timeout=FIND_TIMEOUT_MS)
            page.wait_for_timeout(SETTLE_MS // 2)
            return
    raise LookupError("Tags grid not found (no inputs named 'Name' and 'Value')")


# --- signing in and the guards -------------------------------------------------------------

def wait_for_sign_in(page: Page, tenant_id: str, say: Callable[[str], None] = print) -> None:
    """Signed in = the Microsoft Entra ID overview shows its 'Tenant ID' field. No timeout:
    multi-factor authentication takes as long as it takes, and nobody is served by a run that
    gives up. If the Portal lands elsewhere after sign-in (the home page), it is sent back to the
    overview, at most every 10 seconds so a sign-in in progress is not interrupted."""
    say("Sign in to the Portal in the browser window. Waiting (no timeout) for the "
        "Microsoft Entra ID overview to show the Tenant ID...")
    overview = f"{PORTAL}/#@{tenant_id}{ENTRA_OVERVIEW}"
    last_goto = last_note = time.monotonic()
    while True:
        on_portal = page.url.startswith(PORTAL) and "#" in page.url
        if on_portal and visible_across_frames(page, lambda f: f.get_by_text("Tenant ID", exact=True)):
            return
        if on_portal and "ActiveDirectoryMenuBlade" not in page.url and time.monotonic() - last_goto > 10:
            page.goto(overview, wait_until="domcontentloaded")
            last_goto = time.monotonic()
        if time.monotonic() - last_note >= 60:
            say("Still waiting for sign-in; press Ctrl+C if the browser shows an error.")
            last_note = time.monotonic()
        page.wait_for_timeout(2000)


def guard_language(page: Page) -> str | None:
    lang = page.evaluate("document.documentElement.lang || ''")
    if not lang.lower().startswith("en"):
        return f"Portal language is '{lang or 'unset'}', not English. Set the account's Portal language to English and re-run."
    return None


TREE_VALUE = re.compile(r'^\s*-\s+(?:text|textbox(?:\s+"[^"]*")?(?:\s+\[[^\]]*\])*):\s*(?P<value>.+)$')


def tree_text(snapshot: str) -> str:
    """The text and text box values of an accessibility snapshot, in lower case, one per line.
    Nothing else: a link's '/url' line can carry the '#@<tenant>' pin of any tenant, and a
    name is not what the page says the tenant is."""
    values = []
    for line in snapshot.splitlines():
        m = TREE_VALUE.match(line)
        if m:
            values.append(m.group("value").strip().strip('"'))
    return "\n".join(values).lower()


def guard_tenant(page: Page, tenant_domain: str, tenant_id: str) -> str | None:
    """The Entra overview open since sign-in shows the directory's tenant id; it must be the
    expected one. Only the id counts: the domain is no proof, because the signed-in account's
    address in the Portal header carries its home domain while another directory is shown.
    `tenant_domain` only names the tenant in the message. The id may sit in a read-only text box,
    which plain text search misses, so the text and text box values of every frame's
    accessibility tree are read as well."""
    deadline = time.monotonic() + 10
    while True:
        if text_on_screen(page, tenant_id):
            return None
        tree = ""
        for frame in all_frames(page):
            try:
                tree += tree_text(frame.locator("body").aria_snapshot(timeout=2000)) + "\n"
            except PlaywrightError:
                continue
        if tenant_id.lower() in tree:
            return None
        if time.monotonic() >= deadline:
            return (f"The Microsoft Entra ID overview does not show tenant ID {tenant_id} "
                    f"(expected directory {tenant_domain}). Switch directory and re-run.")
        page.wait_for_timeout(1000)


def open_portal(pw, args: argparse.Namespace, recording: dict) -> tuple[Browser, Page]:
    width, height = recording.get("viewport", [1440, 900])
    browser = pw.chromium.launch(headless=False)
    try:
        context_kwargs = {"viewport": {"width": width, "height": height}, "device_scale_factor": 1,
                          "locale": "en-US"}
        if args.auth_state.is_file():
            context_kwargs["storage_state"] = str(args.auth_state)
        context = browser.new_context(**context_kwargs)
        page = context.new_page()
        page.goto(f"{PORTAL}/#@{args.tenant_id}{ENTRA_OVERVIEW}", wait_until="domcontentloaded")
        wait_for_sign_in(page, args.tenant_id)
        for guard in (lambda: guard_language(page),
                      lambda: guard_tenant(page, args.tenant_domain, args.tenant_id)):
            failure = guard()
            if failure:
                raise SystemExit(f"GUARD FAILED: {failure}")
        # Saved only now: a session in the wrong tenant or language must not be reused next time.
        context.storage_state(path=str(args.auth_state))
    except BaseException:
        try:
            browser.close()
        except PlaywrightError:
            pass
        raise
    return browser, page


# Exit codes above the 250 cap of finish(), which Invoke-GuideDrift.ps1 reads as "not a count".
NOT_STARTED = 254   # a precondition, a guard or the state stopped the run before the first step
ABORTED = 255       # interrupted (Ctrl+C), stopped at the person's request ('q') or crashed mid-run;
                    # the state is kept for -Resume, so the entry point must not clean up


class StateError(Exception):
    """The state file cannot be resumed from. main() reports it before the browser opens."""


def load_state(path: Path, lab: str) -> dict:
    """The state of an earlier, unfinished run of `lab`, for -Resume."""
    if not path.is_file():
        raise StateError(f"There is no state to resume from at {path}")
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise StateError(f"The state at {path} cannot be read ({error})") from error
    if not isinstance(state, dict) or not isinstance(state.get("completed"), list):
        raise StateError(f"The state at {path} is not a guide drift state")
    if state.get("lab") != lab:
        raise StateError(f"The state at {path} belongs to lab {state.get('lab')}, not {lab}")
    if state.get("finished"):
        raise StateError(f"The run in {path} finished; there is nothing to resume")
    return state


def start_point(portal_ids: list[str], state: dict, from_step: str | None, resume: bool) -> tuple[int, bool]:
    """(index into portal_ids where the run starts, whether that step was in flight when the last
    run stopped). Raises ValueError when there is nowhere to start."""
    if from_step is not None:
        if from_step not in portal_ids:
            raise ValueError(f"--from-step {from_step} is not a portal step of this lab "
                             f"({', '.join(portal_ids)})")
        return portal_ids.index(from_step), False
    if not resume:
        return 0, False
    in_flight = state.get("inFlight")
    if in_flight is not None:
        if in_flight not in portal_ids:
            raise ValueError(f"The step in flight, {in_flight}, is not a portal step of this lab")
        return portal_ids.index(in_flight), True
    for index, step_id in enumerate(portal_ids):
        if step_id not in state["completed"]:
            return index, False
    raise ValueError("Every step in the state is completed; there is nothing to resume")


class Runner:
    # A letter means the same in both prompts: 's' skips one step and the run goes on.
    FAILURE_PROMPT = (
        "  c  I did it by hand: mark the step done and continue\n"
        "  s  skip this step and continue with the next step (you give the reason)\n"
        "  e  end the lab: skip the rest of the lab and finish (the entry point then cleans up)\n"
        "  q  stop here and keep the state for -Resume (no clean-up)\n> "
    )
    REASON_PROMPT = "Why is the step skipped? (goes into the summary)\n> "
    # The browser of a resumed run is new, on the Microsoft Entra ID overview: whatever the answer,
    # the Portal is brought to the view the next step starts from before it runs (#206).
    RESUME_PROMPT = (
        "  y  it finished: mark it done, then bring the Portal to the view it ended on\n"
        "  n  it did not: bring the Portal to the view the step before it ended on, then redo it\n"
        "  s  skip it and continue with the next step\n> "
    )

    def __init__(self, page: Page, steps: dict, recording: dict, args: argparse.Namespace,
                 ask: Callable[[str], str] = input, state: dict | None = None) -> None:
        self.page = page
        self.steps = steps
        self.recording = recording
        self.args = args
        self.ask = ask
        if args.resume and state and state.get("runId"):
            # A resumed run is the same run: its folder, its results and one summary for both parts.
            args.run_id = state["runId"]
        self.run_dir = args.log_dir / args.run_id
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.results_path = self.run_dir / "results.jsonl"
        self.deciders = [ReplayDecider(recording), HumanDecider(ask=lambda text: self.ask(text))]
        self.redactor = Redactor(args.tenant_domain, args.tenant_id, env_secrets(recording),
                                 getattr(args, "tenant_name", ""))
        self.records: list[dict] = self.earlier_results() if args.resume else []
        self.first_failure: str | None = None   # the step every later step is skipped because of
        self.expanded = False                   # whether the current item opened the menu groups
        # The blade the current step started on, to record once its first item went through; None
        # when there is none to record (one is recorded already, or the view has none), and after
        # the first item (#207).
        self.start_seen: str | None = None
        self.first_item = False         # the current item is the step's first (find_form)
        self.start_accounted = False    # check_start reported or excused the step's start
        # Steps whose start is not the guide's doing, with the reason (check_start): the first
        # step after a resume, the first after a step the recording skips. The latter are in
        # `unrecorded` too: their blade is not recorded either.
        self.excused: dict[str, str] = {}
        self.unrecorded: set[str] = set()

    def earlier_results(self) -> list[dict]:
        """The records the stopped part of this run wrote. A last line cut short by a crash is
        skipped."""
        if not self.results_path.is_file():
            return []
        records = []
        for line in self.results_path.read_text(encoding="utf-8").splitlines():
            try:
                records.append(json.loads(line))
            except ValueError:
                continue
        return records

    def prompt(self, text: str) -> str | None:
        """One line from the person, stripped; None when input is closed."""
        try:
            return self.ask(text).strip()
        except EOFError:
            return None

    # -- recording -------------------------------------------------------------------------

    def step_entry(self, step: dict) -> dict:
        entry = self.recording["steps"].setdefault(step["id"], {})
        entry.setdefault("valueOverrides", {})
        entry.setdefault("viewUrl", None)
        entry.setdefault("result", None)
        entry.setdefault("labels", {})
        return entry

    def save_recording(self) -> None:
        write_json(self.args.recording, self.recording)

    def remember(self, step: dict, label: str, entry: dict | None) -> None:
        if entry is not None:
            self.step_entry(step)["labels"][label] = entry
            self.save_recording()

    # -- one label -------------------------------------------------------------------------

    def same_after_restore(self, candidates: list[Candidate], label: str) -> Candidate | None:
        """The one candidate that is the label once tokens are restored, ignoring case: the
        guide's '[yourtenant]' and the screen's 'Contoso' are the same thing, and the deciders,
        which compare redacted names, would report it as drift. Only names with a token count;
        a plain difference in case is still for the deciders to judge."""
        wanted = self.redactor.restore(label)
        matches = [c for c in candidates
                   if (self.redactor.restore(c.name) != c.name or wanted != label)
                   and self.redactor.restore(c.name).casefold() == wanted.casefold()]
        return matches[0] if len(matches) == 1 and matches[0].count == 1 else None

    def looking_for(self, label: str, kind: str) -> Callable[[], Locator | None]:
        """One look for `label` (find_exact), for in_time to repeat. For a navigation or action
        item, once looks have found nothing for SETTLE_MS, the blade menu's collapsed groups are
        opened (expand_menu_groups) and the looks go on to the same deadline, so a label that
        only an open group shows costs a moment, not the whole FIND_TIMEOUT_MS."""
        started = time.monotonic()

        def look() -> Locator | None:
            element = find_exact(self.page, label, field=(kind == "field"))
            if (element is None and kind in ("navigation", "action")
                    and time.monotonic() - started >= SETTLE_MS / 1000):
                self.expand_menu_groups(label)
            return element
        return look

    def wait_for_blade(self, step: dict, item: dict, label: str,
                       look: Callable[[], Locator | None]) -> Locator | None:
        """After `look` found nothing for FIND_TIMEOUT_MS: when a blade is still loading
        (blade_still_loading), say so once and go on looking until it has rendered or its limit
        has passed (BLADE_LOAD_TIMEOUT_MS while a title reads 'undefined', BLADE_EMPTY_TIMEOUT_MS
        for a titled blade without content); once it has rendered, look for FIND_TIMEOUT_MS again,
        as its controls come a moment after it. None at once when no blade is loading, so a label
        missing from a rendered blade is asked about after the normal time (issue #233). Whenever
        the label is still not found, the outline is kept (save_blade_outline)."""
        outline = aria_outline(self.page)
        loading = blade_still_loading(outline)
        if loading is None:
            self.save_blade_outline(step, item, label, outline)
            return None
        limit = BLADE_LOAD_TIMEOUT_MS if loading == BLADE_UNTITLED else BLADE_EMPTY_TIMEOUT_MS
        print(f"The blade is still loading: waiting up to {limit // 1000} s for it "
              f"before asking about '{label}'.")
        rendered = object()     # what the look below returns once the blade has rendered

        def look_while_loading() -> Locator | object | None:
            try:
                element = look()
            except Ambiguous:
                # Several matches on a rendered blade are the normal lookup's to report, after
                # FIND_TIMEOUT_MS, not after the whole limit.
                if blade_still_loading(aria_outline(self.page)) is not None:
                    raise
                return rendered
            if element is not None:
                return element
            return None if blade_still_loading(aria_outline(self.page)) is not None else rendered

        found = in_time(self.page, look_while_loading, ms=limit)
        if found is rendered:
            found = in_time(self.page, look)
        if found is None:
            self.save_blade_outline(step, item, label)
        return found

    def save_blade_outline(self, step: dict, item: dict, label: str,
                           outline: list[tuple[str, str]] | None = None) -> None:
        """Keep what blade_still_loading() read (`outline`, or a fresh aria_outline()), redacted,
        as blade-<step>-<guide line>.aria.txt in the run folder, one '<role> "<name>"' per line: a
        label that was not found shows there whether the blade was taken for loaded, so the check
        can be tuned without another live run. Not for a label the recording already holds a
        decision for: replay settles it, and the person is not asked."""
        if self.page.is_closed() or label in self.recording["steps"].get(step["id"], {}).get("labels", {}):
            return
        if outline is None:
            outline = aria_outline(self.page)
        lines = [f'{role} "{name}"' if name else role for role, name in outline]
        path = self.run_dir / f"blade-{step['id']}-{item.get('line')}.aria.txt"
        path.write_text(self.redactor.redact("\n".join(lines)) + "\n", encoding="utf-8")
        print(f"The blade's outline is in {path}")

    def expand_menu_groups(self, label: str) -> None:
        """Open every collapsed group of the blade's menu with its 'Expand all headers' button.
        Entra ID blades fold menu entries into groups ('Manage', 'Monitoring'), so a link such as
        'Users' is not on screen until its group opens. The button is clicked at most once per
        item (run_step resets the flag), and only when exactly one is visible."""
        if self.expanded:
            return
        try:
            button = unique_visible(self.page, lambda f: f.get_by_role("button", name=EXPAND_ALL, exact=True))
        except Ambiguous:
            return
        if button is None:
            return
        self.expanded = True
        try:
            button.click(timeout=FIND_TIMEOUT_MS)
        except PlaywrightError:
            return
        print(f"Opened the menu groups ('{EXPAND_ALL}') to look for '{label}' again.")

    def save_search_tree(self, step: dict, tree: str) -> None:
        """Keep the search dropdown's accessibility tree, redacted, as search-<step>.aria.txt in
        the run folder: a search that found no single result shows there what the Portal
        offered, so the lookup can be fixed without another live run."""
        path = self.run_dir / f"search-{step['id']}.aria.txt"
        path.write_text(self.redactor.redact(tree) + "\n", encoding="utf-8")
        print(f"The search results' structure is in {path}")

    def search_in_blade(self, label: str, record: dict) -> dict:
        """A search item of scope 'blade' ('Search for **"Owner"**' in a role assignment): type
        `label` into the open blade's or pane's own search box (choose_search_box) and wait up to
        RESULT_TIMEOUT_S for a visible element whose text is `label` (listed). Whether it was
        listed before the search is read first, so a search that changed nothing is not taken
        for a result (search_outcome). The result is not clicked: the guide's next item does
        that. Returns `record` with outcome match, or unknown with the reason (no search box,
        several, no result)."""
        def look() -> Locator | None:
            boxes = blade_search_boxes(self.page)
            index, why = choose_search_box([descriptor for _, descriptor in boxes])
            if why and why.startswith("ambiguous"):
                raise Ambiguous(why)
            return boxes[index][0] if index is not None else None

        try:
            box = in_time(self.page, look)
            if box is None:
                record.update(outcome="unknown", observed="no search box on the open blade")
                return record
            self.page.wait_for_timeout(SETTLE_MS)       # a list still rendering is not 'not listed'
            before = listed(self.page, box, label)
            box.fill(label, timeout=FIND_TIMEOUT_MS)
            after = bool(in_time(self.page, lambda: listed(self.page, box, label) or None,
                                 ms=RESULT_TIMEOUT_S * 1000))
        except Ambiguous as error:
            record.update(outcome="unknown", observed=str(error))
            return record
        except (PlaywrightError, LookupError) as error:
            record.update(outcome="unknown", observed=f"{type(error).__name__}: {error}")
            return record
        outcome, observed = search_outcome(label, before, after)
        record.update(outcome=outcome, observed=observed)
        return record

    def find_form(self, step: dict, item: dict, label: str, value: str,
                  look: Callable[[], Locator | None]) -> Locator | None:
        """The first field of a form (#207), found by `look` only once it can be filled in with
        `value` (editable), as long as any label is looked for (in_time, then wait_for_blade).
        When it cannot, no form is open: a list or a read-only summary is, and a lookup there
        would land on a column or a caption (step 1.1.4's 'User principal name' on the Users
        list). That is misleading drift in category WRONG_BLADE (the guide does not say how to get
        to the form), written at once, except at the step's first item when check_start has
        already accounted for the step's start (start_accounted): one cause, one record. The
        person is asked to open the form and press Enter, and the field is then looked up as any
        other, the person being asked about it as usual when it is still not there. Closed input
        at that prompt goes on the same way."""
        def form_field() -> Locator | None:
            element = look()
            return element if element is not None and editable(element, value) else None

        element = in_time(self.page, form_field)
        if element is None:
            element = self.wait_for_blade(step, item, label, form_field)
        if element is not None:
            return element
        where = (f"no form with a field '{label}' is open; the Portal is on "
                 f"{self.open_blade() or 'a view the run does not name'}")
        if self.first_item and self.start_accounted:
            print(f"\nStep {step['id']}: {where}.\nOpen the form, then press Enter.")
        else:
            message = f"{where}; the guide does not say how to get there"
            record = self.new_record(step, "field", label)
            record.update(outcome="drift", severity="misleading", category=WRONG_BLADE, observed=message)
            self.write(record)
            print(f"\nStep {step['id']}: {message}.\nOpen the form, then press Enter.")
        self.prompt("> ")
        if self.start_seen is not None:     # set during the step's first item only: it starts on the form
            self.start_seen = self.open_blade()
        element = in_time(self.page, look)
        if element is None:
            element = self.wait_for_blade(step, item, label, look)
        return element

    def act_on_label(self, step: dict, item: dict, label: str, value: str | None = None,
                     form_start: bool = False) -> dict:
        """Find the element the guide calls `label`, act on it, return the result record.
        `form_start`: the label is the first field of a form, which must be open (find_form)
        unless the recording holds a decision for the label (replay finds the field)."""
        kind, line = item["kind"], item["line"]
        record = self.new_record(step, kind, label)
        if kind == "search" and item.get("scope") == "blade":
            return self.search_in_blade(label, record)
        try:
            if kind == "search":
                element = search_portal(self.page, label, diagnose=lambda tree: self.save_search_tree(step, tree))
            else:
                look = self.looking_for(label, kind)
                if form_start and label not in self.recording["steps"].get(step["id"], {}).get("labels", {}):
                    element = self.find_form(step, item, label, value or "", look)
                else:
                    element = in_time(self.page, look)
                    if element is None:
                        element = self.wait_for_blade(step, item, label, look)
        except Ambiguous as error:
            record.update(outcome="unknown", observed=f"ambiguous: {error} named '{label}'")
            return record
        except (PlaywrightError, LookupError) as error:     # the search box is missing or cannot be typed in
            record.update(outcome="unknown", observed=f"{type(error).__name__}: {error}")
            return record
        decision = Decision(kind="use", name=label, decided_by="exact") if element is not None else None
        pending = None     # a person's use/drift decision, recorded only once the action succeeded
        if decision is None:
            # Names are redacted before anyone sees them, so the person, the recording and replay
            # all work with '[tenantdomain]' and the element is found by the restored name.
            if self.page.is_closed():
                raise PageClosed("the browser window was closed")
            candidates = [Candidate(role=c.role, name=self.redactor.redact(c.name), count=c.count)
                          for c in candidates_on_screen(self.page)]
            same = self.same_after_restore(candidates, label)
            if same is not None:
                decision = Decision(kind="use", name=same.name, role=same.role, decided_by="exact")
            else:
                decision = decide(step, item, label, candidates, self.deciders)
            if decision.decided_by == "human":
                entry = decision.to_recording(rejected_candidates(candidates, label, decision.name), now())
                if decision.kind == "ignore" or decision.severity == "blocking":
                    self.remember(step, label, entry)     # nothing to act on: record at once
                else:
                    pending = entry
            if decision.name and decision.severity != "blocking":
                try:
                    element = find_by_name(self.page, decision.role, self.redactor.matcher(decision.name))
                except Ambiguous as error:
                    record.update(outcome="unknown", observed=f"ambiguous: {error} named '{decision.name}'")
                    return record
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
        acted_on = decision.name or label
        if DESTRUCTIVE.search(acted_on) and not DESTRUCTIVE.search(label):
            record.update(outcome="unknown", observed=f"refused: destructive element '{acted_on}'")
            return record
        note = None
        try:
            # Found anywhere in the window's columns, maybe below the fold: bring it into view first.
            element.scroll_into_view_if_needed(timeout=FIND_TIMEOUT_MS)
            if stays_disabled(self.page, element):     # never click() into a 30 s Playwright wait
                record.update(outcome="unknown", observed=f"disabled: '{acted_on}'")
                return record
            if kind == "field":
                note = fill_field(self.page, element, value or "")
            else:
                element.click(timeout=FIND_TIMEOUT_MS)
                self.page.wait_for_timeout(SETTLE_MS)
        except ReadOnly:
            record.update(outcome="unknown", observed=f"read-only: '{acted_on}'")
            return record
        except (PlaywrightError, LookupError) as error:
            record.update(outcome="unknown", observed=f"{type(error).__name__}: {error}")
            return record
        # Replay must never inherit a choice the runner could not act on.
        self.remember(step, label, pending)
        if decision.kind == "drift":      # misleading or cosmetic: acted on, under a different name
            record.update(outcome="drift", severity=decision.severity, observed=decision.name,
                          proposedEdit=self.proposed_edit(line, label, decision.name))
        else:
            record.update(outcome="match", observed=note or decision.name)
        return record

    def open_resource(self, step: dict, item: dict, name: str, at_start: bool = False) -> dict:
        """Open the resource `name` that a navigation chain names in a code span (#199): fill the
        recording's placeholders (resource_name), look for it as long as for a label (in_time,
        then wait_for_blade) with find_resource, and click it.

        `at_start`: the name opens the chain, before any label of the item. Such a chain may
        start from anywhere ('Navigate to `prodskycraftswcsa` -> ...'), so when the name is not on
        screen it is typed into the Portal's global search and the result named exactly `name` is
        opened (search_portal, as for a search item of scope 'global'); a search without one is
        closed again (close_search). Later in a chain the label before the name set where it is
        listed (an endpoint picker in a Connection Monitor wizard, 5.3.6; a vault's backup items,
        5.2.3), and a search would leave that view or open a same-named resource elsewhere, so it
        is looked for on screen only.

        Returns the result record: match; unknown for a placeholder left in the name, several
        matches on screen or in the search, no search box or a failed click; or, when it is not
        found, blocking drift in category MISSING_RESOURCE with no proposed edit. The deciders
        are never asked and nothing is recorded: another element is no stand-in for a resource,
        and an earlier step or lab that did not create it is no fault of the guide."""
        record = self.new_record(step, item["kind"], name)
        wanted = resource_name(self.recording, name)
        if wanted is None:
            record.update(outcome="unknown", observed=f"resource name '{name}' has an unresolved placeholder; "
                                                      "add a placeholder to the recording")
            return record

        def look() -> Locator | None:
            return find_resource(self.page, wanted)

        try:
            element = in_time(self.page, look)
            if element is None:
                element = self.wait_for_blade(step, item, name, look)
            searched = element is None and at_start
            if searched:
                print(f"'{name}' is not on screen: looking it up in the Portal's search.")
                try:
                    element = search_portal(self.page, wanted,
                                            diagnose=lambda tree: self.save_search_tree(step, tree))
                except Ambiguous:
                    close_search(self.page)
                    raise
                if element is None:
                    close_search(self.page)
            if element is None:
                where = ", and no result of that name in the Portal's search" if searched else ""
                record.update(outcome="drift", severity="blocking", category=MISSING_RESOURCE,
                              observed=f"no link, cell or row named '{name}' on screen{where}")
                return record
            element.scroll_into_view_if_needed(timeout=FIND_TIMEOUT_MS)
            if stays_disabled(self.page, element):
                record.update(outcome="unknown", observed=f"disabled: '{name}'")
                return record
            element.click(timeout=FIND_TIMEOUT_MS)
            self.page.wait_for_timeout(SETTLE_MS)
        except Ambiguous as error:
            record.update(outcome="unknown", observed=f"ambiguous: {error} named '{name}'")
            return record
        except (PlaywrightError, LookupError) as error:
            record.update(outcome="unknown", observed=f"{type(error).__name__}: {error}")
            return record
        record.update(outcome="match", observed="opened from the Portal's search" if searched else None)
        return record

    def proposed_edit(self, line: int, old_label: str, new_label: str) -> dict | None:
        """The guide line with the bold label replaced; None when the line is out of range or does
        not carry the label in bold, so there is nothing to change."""
        guide_lines = (Path(self.args.repo_root) / self.steps["guide"]).read_text(encoding="utf-8-sig").splitlines()
        if not (1 <= line <= len(guide_lines)):
            return None
        old = guide_lines[line - 1]
        new = old.replace(f"**{old_label}**", f"**{new_label}**")
        return None if new == old else {"line": line, "old": old, "new": new}

    # -- one step --------------------------------------------------------------------------

    def open_blade(self) -> str | None:
        """The blade the Portal shows (view_blade of the redacted view, Redactor.view_url); None
        for a closed window, a page off the Portal, and a view that cannot be kept without tenant
        or personal data."""
        if self.page.is_closed():
            return None
        address = urlsplit(self.page.url)
        if f"{address.scheme}://{address.netloc}" != PORTAL:
            return None
        return view_blade(self.redactor.view_url(self.page.url))

    def settled_blade(self) -> str | None:
        """The blade the Portal shows once two readings SETTLE_MS apart agree: after a Create or
        Save the address changes a moment after the click (#207). None when it does not settle
        within FIND_TIMEOUT_MS, or the view cannot be named."""
        blade = self.open_blade()
        for _ in range(FIND_TIMEOUT_MS // SETTLE_MS):
            self.page.wait_for_timeout(SETTLE_MS)
            again = self.open_blade()
            if again == blade:
                return blade
            blade = again
        return None

    def check_start(self, step: dict) -> str | None:
        """Before the step's first item (#207): compare the blade the Portal shows (open_blade)
        with the one the recording says the step starts on (start_blade, same_blade), for up to
        FIND_TIMEOUT_MS, as the address changes a moment after the previous step's last click.
        When it never matches, write misleading drift in category WRONG_BLADE ('the step starts
        on X, the Portal is on Y; the guide does not say how to get there') and ask the person to
        bring the Portal to X and press Enter; the recorded blade stays. A step in `excused` (the
        first one after a resume, or after a step the recording skips) is asked about the same
        way, with the reason and without a record: the guide is not at fault there.

        Sets start_accounted when the step's start is accounted for (a record, or an excuse), so
        that find_form does not report the same cause again at the first item. Returns the blade
        to record once the first item has gone through: the settled one (settled_blade) when the
        recording has none yet; None when it has one, the open blade cannot be named, the step
        follows a step the recording skips (`unrecorded`: the blade would depend on the skip), or
        the step starts anywhere (starts_anywhere), in which case nothing is compared either."""
        excuse = self.excused.get(step["id"])
        self.start_accounted = excuse is not None
        if not step["items"] or starts_anywhere(step["items"][0]):
            return None
        recorded = start_blade(self.recording, step["id"])
        if recorded is None:
            return None if step["id"] in self.unrecorded else self.settled_blade()
        current: str | None = None

        def on_recorded() -> bool | None:
            nonlocal current
            current = self.open_blade()
            return True if current is not None and same_blade(current, recorded) else None

        if in_time(self.page, on_recorded) or current is None:
            return None
        if excuse is None:
            message = (f"the step starts on {recorded}, the Portal is on {current}; "
                       "the guide does not say how to get there")
            record = self.new_record(step, "blade", recorded)
            record.update(outcome="drift", severity="misleading", category=WRONG_BLADE, observed=message)
            self.write(record)
            self.start_accounted = True
            print(f"\nStep {step['id']}: {message}.\nBring the Portal to {recorded}, then press Enter.")
        else:
            print(f"\nStep {step['id']} starts on {recorded}, the Portal is on {current} ({excuse}).\n"
                  f"Bring the Portal to {recorded}, then press Enter.")
        self.prompt("> ")
        return None

    def run_step(self, step: dict) -> bool:
        """Perform one step; True when every item went through. A failed step keeps the view
        URL of its last good run and is not checked for its expected result. Before the first
        item the open blade is checked (check_start); once that item has gone through, with or
        without the person's help, the blade it started on is recorded when none is (#207). The
        first field acted on after anything but a field starts a form (form table rows or
        '**Label**: value' items in a row), which must be open (act_on_label's form_start)."""
        print(f"\n=== Step {step['id']}: {step['title']} ===")
        if self.page.is_closed():
            raise PageClosed("the browser window was closed")
        entry = self.step_entry(step)
        self.start_seen = self.check_start(step)
        step_failed = False
        in_form = False     # a field of the item before was acted on: the form is open
        for position, item in enumerate(step["items"]):
            self.expanded = False
            self.first_item = position == 0
            if item["kind"] == "tag":
                record = self.new_record(step, "tag", item["name"])
                try:
                    fill_tag(self.page, item["name"], resolve_value(self.recording, step, item["name"], item["value"]))
                    record.update(outcome="match", observed=item["value"])
                except (PlaywrightError, LookupError) as error:
                    record.update(outcome="unknown", observed=f"{type(error).__name__}: {error}")
                records = [record]
            elif item["kind"] == "field":
                action, value = field_action(self.recording, step, item)
                if action == "type":
                    record = self.act_on_label(step, item, item["label"], value, form_start=not in_form)
                    in_form = True
                else:
                    record = self.new_record(step, "field", item["label"])
                    if action == "skip":
                        record.update(outcome="match", observed=f"left as is: {value}")
                    elif action == "instruction":     # the guide's own text: no tenant data
                        record.update(outcome="unknown",
                                      observed=f"value '{item['value']}' is an instruction, not text to "
                                               "type; add a valueOverride for this field to the recording")
                    else:
                        record.update(outcome="unknown",
                                      observed=f"value '{value}' has an unresolved [token]; add a "
                                               "placeholder or a valueOverride to the recording")
                records = [record]
            else:
                records = []
                resources = set(item.get("resources", ()))     # indices of resource names (#199)
                for index, label in enumerate(item["labels"]):
                    records.append(self.open_resource(step, item, label, at_start=(index == 0))
                                   if index in resources
                                   else self.act_on_label(step, item, label))
                    if records[-1]["outcome"] == "unknown" or records[-1].get("severity") == "blocking":
                        break
            if item["kind"] != "field":
                in_form = False
            for record in records:
                self.write(record)
                if record["outcome"] == "unknown" or record.get("severity") == "blocking":
                    step_failed = True
            if position == 0:
                if not step_failed and self.start_seen is not None:
                    # It went through on the blade the step started on: later runs compare with it.
                    self.step_entry(step)["startBlade"] = self.start_seen
                    self.save_recording()
                    print(f"Recorded: step {step['id']} starts on {self.start_seen}")
                self.start_seen = None      # a later item's find_form must not change it
            if step_failed:
                break
        self.first_item = False
        if not step_failed:
            self.check_result(step, entry)
            self.record_view(step)
        self.write(self.screenshot(step))
        return not step_failed

    # -- results ---------------------------------------------------------------------------

    def record_view(self, step: dict) -> None:
        """Keep the view `step` ended on in the recording (redacted: Redactor.view_url), where a
        resume finds it for the step after it. Called when the step went through, and when the
        person finished it by hand ('c'), so that a step done by hand leaves a view too (#206).
        The recording is left as it is for a closed window (its address is the last one it
        showed) and for a page off the Portal (a sign-in page). A Portal view that cannot be kept
        without tenant or personal data (view_url gives None) is recorded as None, so that a
        resume does not open the view an older run ended on."""
        if self.page.is_closed():
            return
        address = urlsplit(self.page.url)
        if f"{address.scheme}://{address.netloc}" != PORTAL:
            return
        self.step_entry(step)["viewUrl"] = self.redactor.view_url(self.page.url)
        self.save_recording()

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
            answer = self.prompt("Text to look for on screen (Enter = not observable): ")
            if answer is None:          # input closed: ask again next time
                return
            entry["result"] = {"text": self.redactor.redact(answer)} if answer else None
            entry.setdefault("asked", []).append("result")
            self.save_recording()
        if not entry["result"]:
            return
        record = self.new_record(step, "result", entry["result"]["text"])
        # Presence, not a unique element: a created group's name shows in the list and the
        # breadcrumb at once, and either proves the result. The Portal often shows the result a
        # few seconds after the last click (a notification, a refreshed list), so keep looking.
        text = self.redactor.restore(entry["result"]["text"])
        deadline = time.monotonic() + RESULT_TIMEOUT_S
        try:
            found = text_on_screen(self.page, text)
            while not found and time.monotonic() < deadline:
                self.page.wait_for_timeout(500)
                found = text_on_screen(self.page, text)
        except PlaywrightError as error:
            record.update(outcome="unknown", observed=f"{type(error).__name__}: {error}")
            self.write(record)
            return
        record.update(outcome="match" if found else "drift", severity=None if found else "misleading",
                      observed=None if found else f"text not on screen within {RESULT_TIMEOUT_S} s")
        self.write(record)

    def screenshot(self, step: dict) -> dict:
        path = self.run_dir / f"Step-{step['id']}.png"
        self.page.screenshot(path=str(path), full_page=False)
        record = self.new_record(step, "screenshot", None)
        # A missing resource is no drift of the guide, and a wrong blade is a navigation the guide
        # leaves out, not a blade it shows: neither makes the guide's images stale.
        drifted = any(r["step"] == step["id"] and r["outcome"] == "drift"
                      and r.get("category") not in (MISSING_RESOURCE, WRONG_BLADE) for r in self.records)
        if step["images"] and drifted:
            record.update(outcome="drift", category="stale", observed=", ".join(step["images"]))
        else:
            record.update(outcome="match")
        return record

    def skip_step(self, step: dict, because: str, reason: str | None = None,
                  category: str | None = None) -> None:
        """A 'skipped' record. because: the step whose failure caused the skip, or the step
        itself when the person skipped it (on resume, or after it failed) or the recording does
        (category RECORDED_SKIP). reason: why the person or the recording skipped the step, kept
        as observed; on resume there is none."""
        record = self.new_record(step, "action", None)
        record.update(outcome="skipped", skippedBecause=because, observed=reason, category=category)
        self.write(record)

    # -- state and resume -------------------------------------------------------------------

    def save_state(self, completed: list[str], in_flight: str | None, finished: bool = False) -> None:
        """completed: steps done (or deliberately skipped) that a resume passes over. in_flight:
        the step a resume starts at: the step being performed, or the step that failed.
        finished: the run ended normally, so there is nothing to resume. logDir: the absolute
        --log-dir, so that Invoke-GuideDrift.ps1 -Resume finds this run's folder again whatever
        -LogDirectory it is given."""
        write_json(self.args.state, {"runId": self.args.run_id, "lab": self.steps["lab"],
                                     "completed": completed, "inFlight": in_flight,
                                     "finished": finished, "logDir": str(Path(self.args.log_dir).resolve())})

    def start_view(self, portal: list[dict], index: int, skipped: tuple[str, ...] = ()) -> tuple[str | None, str | None]:
        """The view portal[index] starts from: (the id of the last step performed before it, the
        view the recording keeps for that step or None). (None, None) when no step comes before
        it. A step the recording skips never moved the Portal, so the step before it is taken
        instead (#200). So is a step in `skipped` (skipped with 's' at the resume prompt) that has
        no view of its own: it failed, so it never recorded one, and the guide's next step most
        likely starts where it started."""
        while index > 0:
            before = portal[index - 1]["id"]
            if skip_reason(self.recording, before) is None and (
                    before not in skipped or self.recording["steps"].get(before, {}).get("viewUrl")):
                break
            index -= 1
        if index == 0:
            return None, None
        previous = portal[index - 1]["id"]
        return previous, self.recording["steps"].get(previous, {}).get("viewUrl")

    def view_problem(self, view: str) -> str | None:
        """Why a recorded view cannot be opened as an address in this run, for the person; None
        when it can. A recording is data, and the run only ever goes to the Portal."""
        restored = self.redactor.restore(view)
        parts = urlsplit(restored)
        if "<id>" in view:
            return "it names an object by id, which the recording leaves out"
        token = UNFILLED_TOKEN.search(parts.fragment)
        if token:
            return (f"it keeps {token.group(0)}, which this run cannot fill in "
                    f"(is the environment variable set?)")
        if (f"{parts.scheme}://{parts.netloc}" != PORTAL or parts.path not in ("", "/") or parts.query
                or not parts.fragment or parts.fragment.startswith("@")):
            return "it is no Portal view the run can open"
        return None

    def view_address(self, view: str) -> str | None:
        """The address that opens a recorded view in this run's tenant: the view with the tenant
        data restored and the tenant pinned, as open_portal() pins it. None when view_problem()
        names a reason it cannot be opened."""
        if self.view_problem(view) is not None:
            return None
        return f"{PORTAL}/#@{self.args.tenant_id}/{urlsplit(self.redactor.restore(view)).fragment}"

    def bring_to_view(self, portal: list[dict], index: int, passed: str = "",
                      skipped: tuple[str, ...] = ()) -> bool:
        """Before portal[index], the first step a resumed run (or one started with --from-step)
        performs: its browser is new and shows the Microsoft Entra ID overview, not the view the
        step starts from (#206; start_view, with the steps skipped at the resume prompt). Opens
        that view when the recording keeps one that can be opened (view_address); otherwise says
        what to bring the Portal to and why the run cannot. Then waits for Enter either way: the
        recording keeps no query string, and a view opened on its own has none of the blades the
        guide opened before it. False when input is closed.

        When the recording keeps the blade the step starts on (#207), the message names it too,
        and the step is excused (check_start): a blade that differs after this prompt is asked
        about again, but is no drift of the guide."""
        step = portal[index]
        previous, view = self.start_view(portal, index, skipped)
        head = f"\nStarting at step {step['id']} ({step['title']}){passed}."
        blade = start_blade(self.recording, step["id"])
        if blade is not None:
            head += f" It starts on {blade}."
        self.excused[step["id"]] = ("the browser of this run is new: the blades the guide opened before "
                                    "the step are not open")
        if previous is None:
            print(f"{head} No step of the lab comes before it, so it starts where a new run does, on "
                  f"the view the browser opened: check the Portal shows it, then press Enter.")
        elif view is None:
            print(f"{head} No view is recorded for step {previous}, the step before it, so the run cannot "
                  f"open it: bring the Portal to where step {previous} ends in the guide, then press Enter.")
        else:
            why = self.view_problem(view)
            if why is None:
                try:
                    self.page.goto(self.view_address(view), wait_until="domcontentloaded")
                except PlaywrightError as error:
                    why = f"opening it failed: {(str(error).strip().splitlines() or [type(error).__name__])[0]}"
                else:
                    print(f"{head} Opened the view step {previous} ended on:\n  {view}\n"
                          f"Check the Portal shows it, then press Enter. The recording keeps no query "
                          f"string, and the blades the guide opened before it are not open: if the step "
                          f"needs them, bring the Portal there by hand first.")
                    return self.prompt("> ") is not None
            print(f"{head} Bring the Portal to the view step {previous} ended on, then press Enter "
                  f"(the run cannot open it: {self.redactor.redact(why)}):\n  {view}")
        return self.prompt("> ") is not None

    # -- the run ---------------------------------------------------------------------------

    def run(self, state: dict | None = None) -> int:
        state = state or {"completed": [], "inFlight": None}
        completed = list(state.get("completed", []))
        portal = [step for step in self.steps["steps"] if step["portal"]]
        try:
            start, in_flight = start_point([s["id"] for s in portal], state, self.args.from_step, self.args.resume)
        except ValueError as error:
            print(error)
            return NOT_STARTED
        print(f"Run folder: {self.run_dir}")
        first = portal[start]
        if in_flight and skip_reason(self.recording, first["id"]) is not None:
            # Skipped in the recording since the run stopped (#200): whether it finished does not
            # matter any more. Its stopped attempt is dropped, as a redo's is (results.jsonl keeps
            # it), and the loop below writes the recorded skip; the person is asked for the view
            # the first step that runs needs, as on any other resume.
            print(f"\nStep {first['id']} ({first['title']}) was in progress when the last run stopped; "
                  f"the recording now skips it.")
            self.records = [r for r in self.records if r["step"] != first["id"]]
            in_flight = False
        answer = None
        if in_flight:
            print(f"\nStep {first['id']} ({first['title']}) was in progress when the last run stopped.\n"
                  f"Did step {first['id']} finish?")
            while answer not in ("y", "n", "s"):
                answer = self.prompt(self.RESUME_PROMPT)
                if answer is None:
                    print("No answer (input closed); nothing was run.")
                    return NOT_STARTED
            if answer in ("y", "s"):
                completed.append(first["id"])   # saved below, once the Portal is on the next view
        if start > 0 or self.args.resume:
            # The browser is new: the first step that runs needs the Portal brought to the view it
            # starts from (#206). Steps the recording skips are passed over (#200), and when every
            # step left is skipped or completed there is no view to bring the Portal to.
            runs = next((i for i in range(start, len(portal)) if portal[i]["id"] not in completed
                         and skip_reason(self.recording, portal[i]["id"]) is None), None)
            if runs is not None:
                skipped = [s["id"] for s in portal[start:runs] if skip_reason(self.recording, s["id"]) is not None]
                passed = ("" if not skipped else f" (the recording skips step {skipped[0]})" if len(skipped) == 1
                          else f" (the recording skips steps {', '.join(skipped)})")
                if not self.bring_to_view(portal, runs, passed, (first["id"],) if answer == "s" else ()):
                    print("No answer (input closed); nothing was run.")
                    return NOT_STARTED
        if answer in ("y", "s"):
            if answer == "s":
                self.skip_step(first, first["id"])
            self.save_state(completed, None)
        for step in portal[start:]:
            if step["id"] in completed:
                continue
            reason = skip_reason(self.recording, step["id"])
            if reason is not None:
                # Never performed (#200), so it comes before an ended lab's 'because step X
                # failed': the recording's reason is why the step is not checked either way.
                self.skip_step(step, step["id"], reason, category=RECORDED_SKIP)
                completed.append(step["id"])
                self.save_state(completed, self.first_failure)     # an ended lab keeps its step in flight
                continue
            if self.first_failure:
                self.skip_step(step, self.first_failure)
                continue
            before = portal.index(step) - 1
            if before >= 0 and skip_reason(self.recording, portal[before]["id"]) is not None:
                # Its blade depends on whether the step before it runs: neither compared as the
                # guide's fault nor recorded (#207).
                self.excused.setdefault(step["id"], f"the recording skips step {portal[before]['id']}, "
                                                    "the step before it")
                self.unrecorded.add(step["id"])
            self.save_state(completed, step["id"])
            # A step redone after -Resume replaces what its stopped attempt found (its screenshot
            # is overwritten too); results.jsonl keeps both attempts.
            self.records = [r for r in self.records if r["step"] != step["id"]]
            if self.run_step(step):
                completed.append(step["id"])
                self.save_state(completed, None)
                continue
            answer = self.ask_after_failure(step)
            reason = self.ask_skip_reason() if answer == "s" else None
            if answer == "s" and reason is None:    # input closed: nobody is there to go on
                answer = "e"
            if answer == "c":
                self.record_view(step)          # where the person finished it, for a resume (#206)
                record = self.new_record(step, "action", None)
                record.update(outcome="match", observed="done by hand")
                self.write(record)
                completed.append(step["id"])
                self.save_state(completed, None)
            elif answer == "s":
                # Its findings stay counted; a resume passes over it, as over a step skipped there.
                self.skip_step(step, step["id"], self.redactor.redact(reason))
                completed.append(step["id"])
                self.save_state(completed, None)
            elif answer == "e":
                self.first_failure = step["id"]     # the state keeps it in flight
            else:
                self.finish()
                print(f"\nStopped at step {step['id']}. Progress is in {self.args.state}; re-run with -Resume.")
                return ABORTED
        self.save_state(completed, self.first_failure, finished=True)
        return self.finish()

    def ask_after_failure(self, step: dict) -> str:
        """'c' (done by hand), 's' (skip this step), 'e' (end the lab: skip the rest) or 'q'
        (stop, keep the state). Closed input means nobody is there to finish the lab by hand:
        'e'. The reasons are printed first, one line per record of the step that is not a
        match, redacted: results.jsonl is not where the person looks."""
        print(f"\nStep {step['id']} did not go through:")
        for r in self.records:
            if r["step"] == step["id"] and r["outcome"] != "match":
                outcome = f"{r['outcome']} ({r['severity']})" if r.get("severity") else r["outcome"]
                observed = (str(r["observed"]).strip().splitlines() or [""])[0] if r.get("observed") else "-"
                what = f"{r['kind']} '{r['label']}'" if r.get("label") else r["kind"]
                print(self.redactor.redact(f"  {what}: {outcome}: {observed}"))
        print("What now?")
        while True:
            answer = self.prompt(self.FAILURE_PROMPT)
            if answer is None:
                return "e"
            if answer in ("c", "s", "e", "q"):
                return answer
            print("Answer c, s, e or q.")

    def ask_skip_reason(self) -> str | None:
        """Why the person skips a step that failed ('no spare licences in this tenant'), for the
        summary; asked again while empty. None when input is closed."""
        while True:
            reason = self.prompt(self.REASON_PROMPT)
            if reason is None or reason:
                return reason
            print("A reason is needed: the summary says why the step was not checked.")

    def finish(self) -> int:
        by_severity: dict[str, list[dict]] = {"blocking": [], "misleading": [], "cosmetic": []}
        unknown, skipped, stale, edits = [], [], [], []
        for r in self.records:
            if r["outcome"] == "drift" and r["severity"]:
                by_severity[r["severity"]].append(r)
            elif r["outcome"] == "drift" and r["category"] == "stale":
                stale.append(r)
            elif r["outcome"] == "unknown":
                unknown.append(r)
            elif r["outcome"] == "skipped":
                skipped.append(r)
            if r.get("proposedEdit"):
                edits.append(r)
        lines = [f"# Guide drift run {self.args.run_id} - lab {self.steps['lab']}", ""]
        for severity, items in by_severity.items():
            lines.append(f"## {severity} ({len(items)})")
            lines += [self.drift_line(r) for r in items] or ["- none"]
            lines.append("")
        lines.append(f"## unknown ({len(unknown)})")
        lines += [f"- step {r['step']} {r['kind']} **{r['label']}**: {r['observed']}" for r in unknown] or ["- none"]
        lines.append("")
        # Matches, so not counted in the exit code, but a reviewer must see them: the label was
        # on screen before the blade search too (search_outcome).
        unconfirmed = [r for r in self.records if r["outcome"] == "match" and UNCONFIRMED in (r["observed"] or "")]
        lines.append(f"## unconfirmed searches ({len(unconfirmed)})")
        lines += [f"- step {r['step']} **{r['label']}**: {r['observed']}" for r in unconfirmed] or ["- none"]
        lines.append("")
        lines.append(f"## skipped ({len(skipped)})")
        lines += [self.skipped_line(r) for r in skipped] or ["- none"]
        lines.append("")
        by_hand = [r for r in self.records if r["outcome"] == "match" and r["observed"] == "done by hand"]
        lines.append(f"## done by hand ({len(by_hand)})")
        lines += [f"- step {r['step']}" for r in by_hand] or ["- none"]
        lines.append("")
        no_portal = [s for s in self.steps["steps"] if not s["portal"]]
        lines.append(f"## no portal part ({len(no_portal)})")
        lines += [f"- step {s['id']}: {s['title']} (not checked: no UI element in the step)" for s in no_portal] or ["- none"]
        lines.append("")
        lines.append(f"## stale screenshots ({len(stale)})")
        lines += [f"- step {r['step']}: {r['observed']}" for r in stale] or ["- none"]
        lines.append("")
        lines.append(f"## proposed edits ({len(edits)})")
        for r in edits:
            e = r["proposedEdit"]
            lines += [f"- {self.steps['guide']}:{e['line']}", f"  - old: `{e['old']}`", f"  - new: `{e['new']}`"]
        if not edits:
            lines.append("- none")
        lines.append("")
        lines.append(f"Screenshots and results: {self.run_dir}")
        summary = "\n".join(lines)
        (self.run_dir / "summary.md").write_text(summary + "\n", encoding="utf-8")
        print("\n" + summary)
        return min(len(by_severity["blocking"]) + len(unknown), 250)

    @staticmethod
    def drift_line(record: dict) -> str:
        """A drift record in the summary: what was observed instead of the label, or that the
        label is gone from the Portal, or for a missing resource (#199) where it was looked for,
        which is no fault of the guide, or for a wrong blade (#207) the message that names it."""
        what = f"- step {record['step']} {record['kind']}"
        if record.get("category") == WRONG_BLADE:
            return f"- step {record['step']}: {record['observed']}"
        if record.get("category") == MISSING_RESOURCE:
            return f"{what} `{record['label']}`: {record['observed']} (an earlier step or lab, or the view, not the guide)"
        if record["severity"] == "blocking":
            return f"{what} **{record['label']}**: gone from the Portal"
        return f"{what} **{record['label']}**: observed {record['observed']!r}"

    @staticmethod
    def skipped_line(record: dict) -> str:
        """A 'skipped' record in the summary (skip_step): skipped by the recording, with its
        reason; skipped by the person after it failed, with theirs; skipped on resume; or skipped
        because an earlier step failed and the person ended the lab there."""
        if record.get("category") == RECORDED_SKIP:
            return f"- step {record['step']} skipped by the recording: {record['observed']}"
        if record["skippedBecause"] != record["step"]:
            return f"- step {record['step']} because step {record['skippedBecause']} failed"
        if record.get("observed"):
            return f"- step {record['step']} skipped after it failed: {record['observed']}"
        return f"- step {record['step']} skipped on resume"


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
    # A malformed skip must not read as 'perform the step', nor a malformed startBlade as a blade
    # no Portal view has (#207).
    try:
        for step_id in recording.get("steps", {}):
            skip_reason(recording, step_id)
            start_blade(recording, step_id)
    except ValueError as error:
        print(f"The recording cannot be used: {error}.")
        return NOT_STARTED
    # Everything that can refuse the run is checked before the browser opens and the person signs in.
    state = {"completed": [], "inFlight": None}
    if args.resume:
        try:
            state = load_state(args.state, steps["lab"])
        except StateError as error:
            print(f"{error}. Delete {args.state} or run without -Resume.")
            return NOT_STARTED
    try:
        start_point([s["id"] for s in steps["steps"] if s["portal"]], state, args.from_step, args.resume)
    except ValueError as error:
        print(error)
        return NOT_STARTED
    with sync_playwright() as pw:
        try:
            browser, page = open_portal(pw, args, recording)
        except (SystemExit, KeyboardInterrupt) as stop:   # a guard, or Ctrl+C while signing in
            print(str(stop) or "Interrupted before the first step.")
            return NOT_STARTED
        except PlaywrightError as error:    # Chromium missing, or the window closed while signing in
            print(f"The browser stopped before the first step: {error}")
            return NOT_STARTED
        except Exception as error:          # noqa: BLE001 - e.g. OSError saving --auth-state
            print(f"Could not open the Portal: {type(error).__name__}: {error}")
            return NOT_STARTED
        runner = Runner(page, steps, recording, args, state=state)
        try:
            return runner.run(state)
        except BaseException as stop:       # noqa: BLE001 - every way out must keep -Resume possible
            # Ctrl+C, a closed browser window (Playwright Error 'Target closed') or a bug: exit 1
            # would read as 'one finding' and the entry point would clean up what -Resume needs.
            # Print what happened, keep the state, and say so.
            if not isinstance(stop, (KeyboardInterrupt, SystemExit, PageClosed)):
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
