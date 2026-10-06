#!/usr/bin/env python3
"""Perform one lab guide's portal steps in a visible browser and report drift (issue #189).

Driven by tools/Invoke-GuideDrift.ps1, which resolves the tenant and parses the guide first.
Opens Chromium headed at 1440x900 on the Microsoft Entra ID overview of the tenant and waits,
without a timeout, until the overview shows its 'Tenant ID' field: the person signs in there
(multi-factor included; there is no unattended sign-in). The run then refuses to start unless
the Portal is in English and the overview shows the expected tenant id or domain. Only then is
the browser session saved to --auth-state, so the next run skips the password.

Everything a run leaves behind goes under --log-dir/<run id>/ and is gitignored:
results.jsonl (one record per check, appended as the run goes), Step-X.Y.N.png (full window,
for manual cropping and anonymisation), summary.md. Only the recording is written back into
the repository.

The runner acts only on an element it can see in the window, and only on one: several matches
are reported as unknown rather than guessed. It refuses to click or fill an element whose name
starts with Delete, Remove, Reset password, Revoke, Disable or Sign out unless the guide's own
label does too.

When a step does not go through, the person chooses: finish it by hand and continue, skip the
rest of the lab, or stop and keep the state. --state records the completed steps and the step a
-Resume starts at (the one in progress, or the one that failed); a resume first asks whether
that step finished. A run that ends normally marks the state finished, and it cannot be resumed.

Exit code: blocking drifts plus unknowns, capped at 250, when the run ends normally; 254 when a
precondition, a guard or the state stopped it before the first step; 255 when it stopped mid-run
(Ctrl+C, 'q', a closed window, a crash) with the state kept for -Resume, so nothing is cleaned up.

Usage (normally via Invoke-GuideDrift.ps1):
  python run.py --steps steps.json --recording recordings/lab-1.1.json --log-dir <dir>
                --run-id 20261007-100000 --tenant-id <guid> --tenant-domain contoso.onmicrosoft.com
                --state <path> --auth-state <path> [--from-step 1.1.6] [--resume]
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
from recording import (Redactor, env_secrets, missing_env, rejected_candidates,  # noqa: E402
                       resolve_value, value_action, write_json)

PORTAL = "https://portal.azure.com"
ENTRA_OVERVIEW = "/view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/Overview"
SETTLE_MS = 1500
FIND_TIMEOUT_MS = 8000
RESULT_TIMEOUT_S = 15
CANDIDATE_ROLES = ("button", "link", "menuitem", "tab", "treeitem", "option", "textbox",
                   "combobox", "checkbox", "radio", "heading", "cell")
FIELD_ROLES = ("textbox", "combobox", "checkbox", "radio")
# Never acted on unless the guide itself names such an element: a wrong replay or a mistyped
# number must not delete a user or sign the person out halfway through a lab.
DESTRUCTIVE = re.compile(r"^(Delete|Remove|Reset password|Revoke|Disable|Sign out)", re.IGNORECASE)
CHECKED = {"✅", "checked", "enabled", "yes", "on"}        # ✅ is the guides' check mark
UNCHECKED = {"☐", "unchecked", "disabled", "no", "off"}   # ☐ is the guides' empty box


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


def in_viewport(element: Locator, viewport: dict | None) -> bool:
    """Whether any part of the element is inside the window. A blade the Portal has slid out of
    view is still 'visible' to the DOM; it is not on screen, and acting on it is a guess."""
    box = element.bounding_box(timeout=1000)
    if box is None:
        return False
    if viewport is None:
        return True
    return (box["x"] < viewport["width"] and box["x"] + box["width"] > 0
            and box["y"] < viewport["height"] and box["y"] + box["height"] > 0)


def visible_in(locator: Locator, viewport: dict | None) -> list[Locator]:
    """The elements of `locator` that are visible and inside the window. is_visible() does not
    wait; a frame that goes away meanwhile raises PlaywrightError, which callers handle per frame."""
    found = []
    for index in range(locator.count()):
        element = locator.nth(index)
        if element.is_visible() and in_viewport(element, viewport):
            found.append(element)
    return found


def visible_across_frames(page: Page, make_locator: Callable[[Frame], Locator]) -> list[Locator]:
    found: list[Locator] = []
    for frame in all_frames(page):
        try:
            found += visible_in(make_locator(frame), page.viewport_size)
        except PlaywrightError:     # the frame detached or navigated: nothing to act on there
            continue
    return found


def unique_visible(page: Page, make_locator: Callable[[Frame], Locator]) -> Locator | None:
    """The one visible element `make_locator(frame)` matches across all frames, or None when there
    is none; raises Ambiguous when there are several."""
    found = visible_across_frames(page, make_locator)
    if len(found) > 1:
        raise Ambiguous(f"{len(found)} visible elements match")
    return found[0] if found else None


def text_on_screen(page: Page, text: str) -> bool:
    return bool(visible_across_frames(page, lambda f: f.get_by_text(text, exact=False)))


def find_exact(page: Page, label: str, field: bool = False) -> Locator | None:
    """The visible element whose accessible name is exactly `label`. For a field: the element the
    label belongs to, or a textbox, combobox, checkbox or radio of that name, and nothing else.
    Otherwise: the interactive roles, then plain text. An ambiguous role match raises Ambiguous;
    an ambiguous text match counts as not found, so the person picks a role-specific candidate."""
    strategies: list[Callable[[Frame], Locator]] = []
    if field:
        strategies.append(lambda f: f.get_by_label(label, exact=True))
        roles = FIELD_ROLES
    else:
        roles = ("button", "link", "menuitem", "tab", "treeitem", "option", "checkbox", "radio")
    for role in roles:
        strategies.append(lambda f, role=role: f.get_by_role(role, name=label, exact=True))
    for make_locator in strategies:
        element = unique_visible(page, make_locator)
        if element is not None:
            return element
    if field:
        return None
    try:
        return unique_visible(page, lambda f: f.get_by_text(label, exact=True))
    except Ambiguous:
        return None


def find_by_name(page: Page, role: str | None, name: str) -> Locator | None:
    """The element a decision chose, by role and name. Raises Ambiguous rather than guess."""
    if role:
        return unique_visible(page, lambda f: f.get_by_role(role, name=name, exact=True))
    return unique_visible(page, lambda f: f.get_by_text(name, exact=True))


def candidates_on_screen(page: Page) -> list[Candidate]:
    return [Candidate(role=role, name=name, count=count) for role, name, count in aria_lines(page)]


def current_text(element: Locator, tag: str) -> str:
    if tag in ("input", "textarea"):
        return element.input_value(timeout=FIND_TIMEOUT_MS)
    return element.inner_text(timeout=FIND_TIMEOUT_MS).strip()


def fill_field(page: Page, element: Locator, value: str) -> str | None:
    """Give the field `value`: tick or clear a checkbox or radio, pick an option, or type. Returns
    'already set' when the field held the value before, and does nothing then. Raises LookupError
    when the value cannot be applied (not a checkbox state, no such option)."""
    role = element.get_attribute("role", timeout=FIND_TIMEOUT_MS) or ""
    tag, input_type = element.evaluate("e => [e.tagName.toLowerCase(), (e.getAttribute('type') || '').toLowerCase()]")
    if role in ("checkbox", "radio", "switch") or (tag == "input" and input_type in ("checkbox", "radio")):
        wanted = value.strip().casefold()
        if wanted not in CHECKED | UNCHECKED:
            raise LookupError(f"'{value}' is not a checkbox state")
        checked = wanted in CHECKED
        if element.is_checked(timeout=FIND_TIMEOUT_MS) == checked:
            return "already set"
        element.set_checked(checked, timeout=FIND_TIMEOUT_MS)
    elif tag == "select":
        selected = element.evaluate("e => e.selectedIndex >= 0 ? e.options[e.selectedIndex].text.trim() : ''")
        if selected == value:
            return "already set"
        element.select_option(value, timeout=FIND_TIMEOUT_MS)   # an option whose value or label is `value`
    elif role in ("combobox", "button") or tag == "button":
        if current_text(element, tag) == value:
            return "already set"
        element.click(timeout=FIND_TIMEOUT_MS)
        page.wait_for_timeout(SETTLE_MS // 2)
        option = find_by_name(page, "option", value)
        if option is None:
            raise LookupError(f"option '{value}' not found")
        option.click(timeout=FIND_TIMEOUT_MS)
    else:
        if current_text(element, tag) == value:
            return "already set"
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
    last_goto = time.monotonic()
    while True:
        on_portal = page.url.startswith(PORTAL) and "#" in page.url
        if on_portal and visible_across_frames(page, lambda f: f.get_by_text("Tenant ID", exact=True)):
            return
        if on_portal and "ActiveDirectoryMenuBlade" not in page.url and time.monotonic() - last_goto > 10:
            page.goto(overview, wait_until="domcontentloaded")
            last_goto = time.monotonic()
        page.wait_for_timeout(2000)


def guard_language(page: Page) -> str | None:
    lang = page.evaluate("document.documentElement.lang || ''")
    if not lang.lower().startswith("en"):
        return f"Portal language is '{lang or 'unset'}', not English. Set the account's Portal language to English and re-run."
    return None


def guard_tenant(page: Page, tenant_domain: str, tenant_id: str) -> str | None:
    """The Entra overview open since sign-in shows the directory's tenant id and primary domain;
    one of them must be the expected tenant's. The id may sit in a read-only text box, which plain
    text search misses, so the accessibility tree of every frame is read as well."""
    deadline = time.monotonic() + 10
    while True:
        if text_on_screen(page, tenant_id) or text_on_screen(page, tenant_domain):
            return None
        tree = ""
        for frame in all_frames(page):
            try:
                tree += frame.locator("body").aria_snapshot(timeout=2000).lower()
            except PlaywrightError:
                continue
        if tenant_id.lower() in tree or tenant_domain.lower() in tree:
            return None
        if time.monotonic() >= deadline:
            return (f"The Microsoft Entra ID overview does not show tenant {tenant_id} ({tenant_domain}). "
                    "Switch directory and re-run.")
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
                 ask: Callable[[str], str] = input) -> None:
        self.page = page
        self.steps = steps
        self.recording = recording
        self.args = args
        self.ask = ask
        self.run_dir = args.log_dir / args.run_id
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.results_path = self.run_dir / "results.jsonl"
        self.deciders = [ReplayDecider(recording), HumanDecider(ask=lambda text: self.ask(text))]
        self.redactor = Redactor(args.tenant_domain, args.tenant_id, env_secrets(recording))
        self.records: list[dict] = []
        self.first_failure: str | None = None   # the step every later step is skipped because of
        self.begun = False                      # whether a step has been started in this run

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
        pending = None     # a person's use/drift decision, recorded only once the action succeeded
        if decision is None:
            # Names are redacted before anyone sees them, so the person, the recording and replay
            # all work with '[tenantdomain]' and the element is found by the restored name.
            candidates = [Candidate(role=c.role, name=self.redactor.redact(c.name), count=c.count)
                          for c in candidates_on_screen(self.page)]
            decision = decide(step, item, label, candidates, self.deciders)
            if decision.decided_by == "human":
                entry = decision.to_recording(rejected_candidates(candidates, label, decision.name), now())
                if decision.kind == "ignore" or decision.severity == "blocking":
                    self.remember(step, label, entry)     # nothing to act on: record at once
                else:
                    pending = entry
            if decision.name and decision.severity != "blocking":
                try:
                    element = find_by_name(self.page, decision.role, self.redactor.restore(decision.name))
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
        if DESTRUCTIVE.match(acted_on) and not DESTRUCTIVE.match(label):
            record.update(outcome="unknown", observed=f"refused: destructive element '{acted_on}'")
            return record
        note = None
        try:
            if element.is_disabled(timeout=FIND_TIMEOUT_MS):     # do not wait out a disabled control
                record.update(outcome="unknown", observed=f"disabled: '{acted_on}'")
                return record
            if kind == "field":
                note = fill_field(self.page, element, value or "")
            else:
                element.click(timeout=FIND_TIMEOUT_MS)
                self.page.wait_for_timeout(SETTLE_MS)
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
        entry = self.step_entry(step)
        step_failed = False
        for item in step["items"]:
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
        finished: the run ended normally, so there is nothing to resume."""
        write_json(self.args.state, {"runId": self.args.run_id, "lab": self.steps["lab"],
                                     "completed": completed, "inFlight": in_flight,
                                     "finished": finished})

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
            if self.run_step(step):
                completed.append(step["id"])
                self.save_state(completed, None)
                continue
            answer = self.ask_after_failure(step)
            if answer == "c":
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
        means nobody is there to finish the lab by hand: 's'."""
        print(f"\nStep {step['id']} did not go through (see above). What now?")
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
        runner = Runner(page, steps, recording, args)
        try:
            return runner.run(state)
        except BaseException as stop:       # noqa: BLE001 - every way out must keep -Resume possible
            # Ctrl+C, a closed browser window (Playwright Error 'Target closed') or a bug: exit 1
            # would read as 'one finding' and the entry point would clean up what -Resume needs.
            # Print what happened, keep the state, and say so.
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
