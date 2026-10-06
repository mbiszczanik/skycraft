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
for manual cropping and anonymisation), summary.md. Only the recording is written back into
the repository.

The runner acts only on a visible element within the window's width (the Portal parks earlier
blades off to the left; below the fold is fine, it scrolls there first), and only on one:
several matches are reported as unknown rather than guessed. It refuses to click or fill an
element whose name contains the word delete, remove, reset, revoke, disable, block, purge or
sign out, unless the guide's own label does too. A guide's 'Search for **X**' is typed into the
Portal's global search, and the result named exactly X in its dropdown is opened (the Services
entry, never Marketplace or Documentation); when that fails, the dropdown's accessibility tree
is kept as search-<step>.aria.txt in the run folder. Plain text counts only when it
is, or sits inside, a link, button or other interactive element; before a label is reported as
not found, the blade menu's collapsed groups are opened once ('Expand all headers').

When a step does not go through, the person chooses: finish it by hand and continue, skip the
rest of the lab, or stop and keep the state. --state records the completed steps and the step a
-Resume starts at (the one in progress, or the one that failed); a resume first asks whether
that step finished. A run that ends normally marks the state finished, and it cannot be resumed.
A resumed run is the same run: it keeps the state's run id (ignoring --run-id), writes into the
same --log-dir/<run id>/ folder, and its summary and exit code cover every step of both parts.

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
from typing import Callable

from playwright.sync_api import Browser, Error as PlaywrightError, Frame, Locator, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
from decide import Candidate, Decision, HumanDecider, ReplayDecider, decide  # noqa: E402
from recording import (Redactor, checkbox_state, env_secrets, missing_env,  # noqa: E402
                       rejected_candidates, resolve_value, value_action, write_json)

PORTAL = "https://portal.azure.com"
ENTRA_OVERVIEW = "/view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview"
SETTLE_MS = 1500
FIND_TIMEOUT_MS = 8000
RESULT_TIMEOUT_S = 15
CANDIDATE_ROLES = ("button", "link", "menuitem", "tab", "treeitem", "option", "textbox",
                   "combobox", "checkbox", "radio", "heading", "cell")
FIELD_ROLES = ("textbox", "combobox", "checkbox", "radio")
ACTION_ROLES = ("button", "link", "menuitem", "tab", "treeitem", "option", "checkbox", "radio")
RESULT_ROLES = ("option", "link", "button", "menuitem")    # entries of the global search's results
# The Portal's global search box, named "Search resources, services, and docs (G+/)".
SEARCH_BOX = re.compile(r"^Search resources")
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
# Whether a labelled element can be a form field at all: nothing in a table or grid header (a
# column's sort button is named after the column, 'User principal name' on the Users list), and
# a plain button only when it opens a list (aria-haspopup listbox, menu or true, or aria-expanded).
FIELD_CANDIDATE_JS = r"""e => {
  if (e.closest('th, thead, [role=columnheader], [role=rowheader]')) return false;
  const role = e.getAttribute('role') || '';
  const plainButton = role === 'button' || (!role && e.tagName.toLowerCase() === 'button');
  if (!plainButton) return true;
  const popup = (e.getAttribute('aria-haspopup') || '').toLowerCase();
  return ['listbox', 'menu', 'true'].includes(popup) || e.hasAttribute('aria-expanded');
}"""
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
    box = element.bounding_box(timeout=1000)
    if box is None:
        return False
    return box["x"] + box["width"] > 0 and box["x"] < viewport["width"]


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
    name is never taken for the field, so the field is not found and the person decides. An
    ambiguous match raises Ambiguous."""
    def fields(make_locator: Callable[[Frame], Locator]) -> list[Locator]:
        return [element for element in visible_across_frames(page, make_locator) if can_be_field(element)]

    labelled = fields(lambda f: f.get_by_label(label, exact=True))
    if labelled:
        controls = [element for element in labelled if is_control(element)]
        containers = [element for element in labelled if not any(element is c for c in controls)]
        composite = [element for element in containers if parts_of(element, "combobox")]
        if composite or controls:
            return only_one(composite or controls)
        textbox = only_one(fields(lambda f: f.get_by_role("textbox", name=label, exact=True)))
        return textbox or only_one(containers)
    for role in FIELD_ROLES:
        element = only_one(fields(lambda f, role=role: f.get_by_role(role, name=label, exact=True)))
        if element is not None:
            return element
    return None


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
    found = search_box(page)
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
        element.set_checked(checked, timeout=FIND_TIMEOUT_MS)
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
    FAILURE_PROMPT = (
        "  c  I did it by hand: mark the step done and continue\n"
        "  s  skip the rest of the lab and finish (the entry point then cleans up)\n"
        "  q  stop here and keep the state for -Resume (no clean-up)\n> "
    )
    RESUME_PROMPT = (
        "  y  it finished: mark it done and continue (leave the Portal where the step ended)\n"
        "  n  it did not: bring the Portal back to the view above, then redo it from its first item\n"
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
        self.begun = bool(self.records)         # whether a step was started (and images checked)
        self.expanded = False                   # whether the current item opened the menu groups

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

    def find_after_expanding(self, label: str) -> Locator | None:
        """The element named `label` after opening every collapsed group of the blade's menu, or
        None. Entra ID blades fold menu entries into groups ('Manage', 'Monitoring'), so a link
        such as 'Users' is not on screen until its group opens. The blade's 'Expand all headers'
        button opens them all; it is clicked at most once per item (run_step resets the flag),
        and only when exactly one is visible. Raises Ambiguous as find_exact does."""
        if self.expanded:
            return None
        try:
            button = unique_visible(self.page, lambda f: f.get_by_role("button", name=EXPAND_ALL, exact=True))
        except Ambiguous:
            return None
        if button is None:
            return None
        self.expanded = True
        try:
            button.click(timeout=FIND_TIMEOUT_MS)
        except PlaywrightError:
            return None
        self.page.wait_for_timeout(SETTLE_MS)
        print(f"Opened the menu groups ('{EXPAND_ALL}') to look for '{label}' again.")
        return find_exact(self.page, label)

    def save_search_tree(self, step: dict, tree: str) -> None:
        """Keep the search dropdown's accessibility tree, redacted, as search-<step>.aria.txt in
        the run folder: a search that found no single result shows there what the Portal
        offered, so the lookup can be fixed without another live run."""
        path = self.run_dir / f"search-{step['id']}.aria.txt"
        path.write_text(self.redactor.redact(tree) + "\n", encoding="utf-8")
        print(f"The search results' structure is in {path}")

    def act_on_label(self, step: dict, item: dict, label: str, value: str | None = None) -> dict:
        """Find the element the guide calls `label`, act on it, return the result record."""
        kind, line = item["kind"], item["line"]
        record = self.new_record(step, kind, label)
        try:
            if kind == "search":
                element = search_portal(self.page, label, diagnose=lambda tree: self.save_search_tree(step, tree))
            else:
                element = find_exact(self.page, label, field=(kind == "field"))
                if element is None and kind in ("navigation", "action"):
                    element = self.find_after_expanding(label)
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

    def run_step(self, step: dict) -> bool:
        """Perform one step; True when every item went through. A failed step keeps the view
        URL of its last good run and is not checked for its expected result."""
        print(f"\n=== Step {step['id']}: {step['title']} ===")
        if self.page.is_closed():
            raise PageClosed("the browser window was closed")
        entry = self.step_entry(step)
        step_failed = False
        for item in step["items"]:
            self.expanded = False
            if item["kind"] == "tag":
                record = self.new_record(step, "tag", item["name"])
                try:
                    fill_tag(self.page, item["name"], resolve_value(self.recording, step, item["name"], item["value"]))
                    record.update(outcome="match", observed=item["value"])
                except (PlaywrightError, LookupError) as error:
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
                    if records[-1]["outcome"] == "unknown" or records[-1].get("severity") == "blocking":
                        break
            for record in records:
                self.write(record)
                if record["outcome"] == "unknown" or record.get("severity") == "blocking":
                    step_failed = True
            if step_failed:
                break
        if not step_failed:
            self.check_result(step, entry)
            entry["viewUrl"] = self.redactor.view_url(self.page.url)
            self.save_recording()
        self.write(self.screenshot(step))
        return not step_failed

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

    def save_state(self, completed: list[str], in_flight: str | None, finished: bool = False) -> None:
        """completed: steps done (or deliberately skipped) that a resume passes over. in_flight:
        the step a resume starts at: the step being performed, or the step that failed.
        finished: the run ended normally, so there is nothing to resume. logDir: the absolute
        --log-dir, so that Invoke-GuideDrift.ps1 -Resume finds this run's folder again whatever
        -LogDirectory it is given."""
        write_json(self.args.state, {"runId": self.args.run_id, "lab": self.steps["lab"],
                                     "completed": completed, "inFlight": in_flight,
                                     "finished": finished, "logDir": str(Path(self.args.log_dir).resolve())})

    def view_before(self, portal: list[dict], index: int) -> str:
        if index == 0:
            return "(the lab's first step: start from the Portal home page)"
        previous = portal[index - 1]["id"]
        url = self.recording["steps"].get(previous, {}).get("viewUrl")
        return url or f"(no view recorded for step {previous})"

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
        if in_flight:
            print(f"\nStep {first['id']} ({first['title']}) was in progress when the last run stopped.\n"
                  f"The step before it ended on this view:\n  {self.view_before(portal, start)}\n"
                  f"Did step {first['id']} finish?")
            answer = None
            while answer not in ("y", "n", "s"):
                answer = self.prompt(self.RESUME_PROMPT)
                if answer is None:
                    print("No answer (input closed); nothing was run.")
                    return NOT_STARTED
            if answer in ("y", "s"):
                completed.append(first["id"])
                if answer == "s":
                    self.skip_step(first, first["id"])
                self.save_state(completed, None)
        elif start > 0 or self.args.resume:
            print(f"\nStarting at step {first['id']} ({first['title']}). Bring the Portal to the view "
                  f"the step before it ended on, then press Enter:\n  {self.view_before(portal, start)}")
            if self.prompt("> ") is None:
                print("No answer (input closed); nothing was run.")
                return NOT_STARTED
        for step in portal[start:]:
            if step["id"] in completed:
                continue
            if self.first_failure:
                self.skip_step(step, self.first_failure)
                continue
            if not self.begun:
                self.begun = True
                self.readability()
            self.save_state(completed, step["id"])
            # A step redone after -Resume replaces what its stopped attempt found (its screenshot
            # is overwritten too); results.jsonl keeps both attempts.
            self.records = [r for r in self.records if r["step"] != step["id"]]
            if self.run_step(step):
                completed.append(step["id"])
                self.save_state(completed, None)
                continue
            answer = self.ask_after_failure(step)
            if answer == "c":
                record = self.new_record(step, "action", None)
                record.update(outcome="match", observed="done by hand")
                self.write(record)
                completed.append(step["id"])
                self.save_state(completed, None)
            elif answer == "s":
                self.first_failure = step["id"]     # the state keeps it in flight
            else:
                self.finish()
                print(f"\nStopped at step {step['id']}. Progress is in {self.args.state}; re-run with -Resume.")
                return ABORTED
        self.save_state(completed, self.first_failure, finished=True)
        return self.finish()

    def ask_after_failure(self, step: dict) -> str:
        """'c' (done by hand), 's' (skip the rest) or 'q' (stop, keep the state). Closed input
        means nobody is there to finish the lab by hand: 's'. The reasons are printed first, one
        line per record of the step that is not a match, redacted: results.jsonl is not where
        the person looks."""
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
                return "s"
            if answer in ("c", "s", "q"):
                return answer
            print("Answer c, s or q.")

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
            lines += [f"- step {r['step']} {r['kind']} **{r['label']}**: "
                      + ("gone from the Portal" if severity == "blocking" else f"observed {r['observed']!r}")
                      for r in items] or ["- none"]
            lines.append("")
        lines.append(f"## unknown ({len(unknown)})")
        lines += [f"- step {r['step']} {r['kind']} **{r['label']}**: {r['observed']}" for r in unknown] or ["- none"]
        lines.append("")
        lines.append(f"## skipped ({len(skipped)})")
        lines += [f"- step {r['step']} skipped on resume" if r["skippedBecause"] == r["step"]
                  else f"- step {r['step']} because step {r['skippedBecause']} failed" for r in skipped] or ["- none"]
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
        lines.append(f"## unreadable screenshots, wider than 1722 px ({len(unreadable)})")
        lines += [f"- {r['label']}: {r['observed']}" for r in unreadable] or ["- none"]
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
