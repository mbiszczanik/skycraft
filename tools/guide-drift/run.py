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
