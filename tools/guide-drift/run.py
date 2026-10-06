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
import json
import re
import sys
import traceback
from pathlib import Path

from playwright.sync_api import Page, Frame, TimeoutError as PlaywrightTimeout, sync_playwright

sys.path.insert(0, str(Path(__file__).parent))
from decide import Candidate, Decision, HumanDecider, ReplayDecider, decide  # noqa: E402
from recording import (Redactor, env_secrets, missing_env, rejected_candidates,  # noqa: E402
                       resolve_value, value_action)

PORTAL = "https://portal.azure.com"
SETTLE_MS = 1500
FIND_TIMEOUT_MS = 8000
CANDIDATE_ROLES = ("button", "link", "menuitem", "tab", "treeitem", "option", "textbox",
                   "combobox", "checkbox", "radio", "heading", "cell")


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
        if not started:
            # --from-step names no portal step, or -Resume found no step in flight: nothing ran,
            # and a finished run's exit code 0 would read as 'no drift'.
            print(f"No step to start from (--from-step {self.args.from_step}, in flight "
                  f"{state.get('inFlight')}); nothing was run.")
            return NOT_STARTED
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
            print(str(stop) or "Interrupted before the first step.")
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
