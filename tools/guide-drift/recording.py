"""The guide drift runner's pure helpers: everything that touches the recording but not the
browser (issue #189).

run.py drives Chromium through Playwright and imports these; keeping them here lets the unit
tests (tools/guide-drift/tests/test_redact.py) run on the CI runner, which has no Playwright.

  Redactor             keeps the tenant domain, tenant id and guest addresses out of the
                       committed recording, and restores them when a recorded name is looked up
  expand_env           expands '${NAME}' references from the environment at the moment of use
  env_secrets          the '${NAME}' references whose values are addresses (for the Redactor)
  missing_env          the '${NAME}' references the environment does not set
  resolve_value        a field value with the recording's placeholders and overrides applied
  resource_name        a resource name of a navigation chain with the placeholders filled, or
                       None when a placeholder is left (#199)
  value_action         type it, leave it ('[Leave blank]'), or report an unresolved [token]
  field_action         what to do with a field item and the value to do it with: as above, or
                       report a value parse.py marked '"literal": false' that the recording
                       does not resolve (#202)
  checkbox_state       the check box state a field value names, if any
  rejected_candidates  the reference set of candidates not chosen, without tenant data
  skip_reason          why the recording skips a step ('"skip": "<reason>"', #200), or None
  write_json           writes the recording or the state file atomically
"""
from __future__ import annotations

import difflib
import json
import os
import re
import time
from pathlib import Path
from urllib.parse import unquote, urlsplit

from decide import Candidate
from parse import BRACKET_TOKEN, value_is_literal

# '${NAME}', or '${NAME|upn}' for the guest user principal name form of an address (the
# Redactor writes that form; see Redactor.__init__).
ENV_REF = re.compile(r"\$\{(?P<name>[A-Z0-9_]+)(?P<upn>\|upn)?\}")


def env_names(recording: dict) -> set[str]:
    """The NAME of every '${NAME}' or '${NAME|upn}' the recording refers to."""
    return {m.group("name") for m in ENV_REF.finditer(json.dumps(recording))}


def expand_env(value: str) -> str:
    def replace(m: re.Match) -> str:
        name = m.group("name")
        if name not in os.environ:
            raise SystemExit(f"environment variable {name} is not set; the recording needs it")
        return os.environ[name].replace("@", "_") if m.group("upn") else os.environ[name]
    return ENV_REF.sub(replace, value)


def missing_env(recording: dict) -> list[str]:
    """Every ${NAME} the recording refers to that the environment does not set."""
    return sorted(name for name in env_names(recording) if name not in os.environ)


REPLACE_ATTEMPTS = 20
REPLACE_PAUSE_S = 0.05


def write_json(path: Path, data: dict) -> None:
    """Write `data` as indented UTF-8 JSON through a temporary file and os.replace, so Ctrl+C or
    a closed window mid-write never leaves a truncated recording or state file behind.

    On Windows, replacing a file that was replaced a moment ago can fail with PermissionError
    (WinError 5) while an antivirus scanner or the search indexer still holds it open. The
    replace is retried for about a second before the error is raised."""
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for attempt in range(1, REPLACE_ATTEMPTS + 1):
        try:
            os.replace(temp, path)
            return
        except PermissionError:
            if attempt == REPLACE_ATTEMPTS:
                raise
            time.sleep(REPLACE_PAUSE_S)


GUID = re.compile(r"[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}")
# A GUID written without hyphens: 32 hex digits that are not part of a longer run, also right
# after a percent-encoded character ('%2F' and the id).
HEX_ID = re.compile(r"(?:(?<=%[0-9a-fA-F]{2})|(?<![0-9a-fA-F]))[0-9a-fA-F]{32}(?![0-9a-fA-F])")


class Redactor:
    """Keeps tenant data out of the committed recording, which lives in a public repository.
    The tenant's domain and id become tokens on the way into the recording and are restored on
    the way out, so a recorded name such as 'malfurion.stormrage@[tenantdomain]' still finds its
    element. The tenant prefix (the domain's first label, as in a directory named 'contoso')
    becomes '[yourtenant]', the guides' own placeholder, when it is at least 4 characters long;
    a shorter one would clobber ordinary words. The tenant's display name ('Contoso Ltd', shown
    in the directory switcher and on the Entra overview) becomes '[tenantname]' under the same
    rule. tests/Guide-Drift-Recording.Tests.ps1 is the backstop: it fails on any literal e-mail
    address, *.onmicrosoft.com domain, guest user principal name or GUID in a recording.

    Restored values are lower case, as the Portal shows domains and ids (the display name comes
    back as given); a display name that spells the prefix in another case ('Contoso') comes back
    as 'contoso'. matcher() therefore matches a restored name regardless of case."""

    DOMAIN = "[tenantdomain]"
    TENANT = "[tenantid]"
    NAME = "[tenantname]"
    PREFIX = "[yourtenant]"
    PREFIX_MIN = 4

    def __init__(self, domain: str, tenant_id: str, secrets: dict[str, str] | None = None,
                 tenant_name: str = "") -> None:
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
        # The display name and the prefix are bounded by anything but a letter, digit, '_' or '-':
        # 'contoso Ltd' is redacted, 'contoso-admins' and 'contosoville' are not. The display name
        # goes first, as it often contains the prefix ('Contoso Ltd' in contoso.onmicrosoft.com).
        name = tenant_name.strip()
        if len(name) >= self.PREFIX_MIN:
            self._pairs.append((re.compile(rf"(?<![\w-]){re.escape(name)}(?![\w-])", re.IGNORECASE),
                                self.NAME, name))
        # Last, so the full domain is already a token.
        prefix = self.domain.split(".", 1)[0]
        if len(prefix) >= self.PREFIX_MIN:
            self._pairs.append((re.compile(rf"(?<![\w-]){re.escape(prefix)}(?![\w-])", re.IGNORECASE),
                                self.PREFIX, prefix))

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

    def matcher(self, name: str) -> str | re.Pattern[str]:
        """What to look a recorded name up by on screen. A name without tokens is returned as it
        is, for an exact, case-sensitive match. A name restore() changed becomes a whole-string,
        case-insensitive pattern, because the restored value is lower case and the screen may
        not be: '[yourtenant] Ltd' must find 'Contoso Ltd'."""
        restored = self.restore(name)
        if restored == name:
            return name
        return re.compile("^" + re.escape(restored) + "$", re.IGNORECASE)

    def view_url(self, url: str) -> str | None:
        """The Portal view without the tenant pin ('#@<tenant>/'), query strings (before or inside
        the fragment), object ids (GUIDs, with or without hyphens: '<id>') or tenant data, for the
        recording; a resume opens it again (run.py, Runner.view_address). None when the view
        cannot be kept without tenant or personal data: once percent-decoded ('%40' is '@'), it
        still holds an address or a user principal name ('@', '#EXT#'), a query, an id, or text
        the Redactor would replace (an encoded tenant name, 'Contoso%20Ltd')."""
        parts = urlsplit(url)
        fragment = re.sub(r"^@[^/]*/?", "", parts.fragment).split("?", 1)[0]
        view = f"{parts.scheme}://{parts.netloc}{parts.path}#{fragment}"
        view = self.redact(HEX_ID.sub("<id>", GUID.sub("<id>", view)))
        decoded = unquote(view)
        if ("@" in decoded or "?" in decoded or "#ext#" in decoded.casefold() or GUID.search(decoded)
                or HEX_ID.search(decoded) or self.redact(decoded) != decoded):
            return None
        return view


def env_secrets(recording: dict) -> dict[str, str]:
    """'${NAME}' -> value for every environment reference in the recording whose value is an
    address (contains '@'): the Redactor writes the token back wherever the value appears.
    Short non-address values such as the tenant prefix are covered by the domain itself and
    would otherwise clobber ordinary words."""
    secrets = {}
    for name in env_names(recording):
        value = os.environ.get(name, "")
        if "@" in value:
            secrets[f"${{{name}}}"] = value
    return secrets


def rejected_candidates(candidates: list[Candidate], label: str, chosen: str | None) -> list[str]:
    """The 20 visible candidates most like the label, other than the chosen one, as 'role "name"':
    the reference set issue #190 needs, without committing the whole screen to the recording.
    Left out entirely: table cells (user data: display names, user principal names), names with
    an '@' (user principal names, the signed-in account) and names with a GUID (object and
    subscription ids)."""
    others = [c for c in candidates if c.name != chosen and c.role != "cell"
              and "@" not in c.name and not GUID.search(c.name)]
    others.sort(key=lambda c: difflib.SequenceMatcher(None, c.name.lower(), label.lower()).ratio(),
                reverse=True)
    return [str(c) for c in others[:20]]


def skip_reason(recording: dict, step_id: str) -> str | None:
    """The reason the recording gives for skipping step `step_id` ('"skip": "Optional: creates a
    CNAME record"', #200), stripped; None when the step entry has no 'skip' key. The step is then
    not performed at all, whatever else its entry records: its decisions, overrides and result
    are kept for the day the skip is removed, and not read while it stays. A 'skip' that is not
    a string with text in it raises ValueError rather than reading as 'not skipped', which would
    perform the very step the recording meant to leave out; run.py checks every entry before the
    browser opens, and tests/Guide-Drift-Recording.Tests.ps1 rejects such an entry in CI."""
    entry = recording["steps"].get(step_id, {})
    if "skip" not in entry:
        return None
    reason = entry["skip"]
    if not isinstance(reason, str) or not reason.strip():
        raise ValueError(f"step {step_id}: 'skip' must be the reason the step is skipped, "
                         f"a non-empty string, not {json.dumps(reason)}")
    return reason.strip()


def value_override(recording: dict, step: dict, label: str) -> str | None:
    """The recording's valueOverrides entry for `label` in `step`, as written; None when none."""
    return recording["steps"].get(step["id"], {}).get("valueOverrides", {}).get(label)


def resolve_value(recording: dict, step: dict, label: str, value: str) -> str:
    override = value_override(recording, step, label)
    if override is not None:
        return expand_env(override)
    return fill_placeholders(recording, value)


def fill_placeholders(recording: dict, text: str) -> str:
    """`text` with each of the recording's placeholders ('[yourtenant]') replaced."""
    for placeholder, replacement in recording.get("placeholders", {}).items():
        if placeholder in text:
            text = text.replace(placeholder, expand_env(replacement))
    return text


# What is left of a placeholder in a resource name: '[yourtenant]', '<your name>'.
NAME_TOKEN = re.compile(r"\[[^\]]+\]|<[^<>]+>")


def resource_name(recording: dict, name: str) -> str | None:
    """The resource name a navigation chain gives in a code span (#199) with the recording's
    placeholders filled; None when a bracket or angle-bracket token is left, so the runner
    reports the step rather than looking for the token."""
    name = fill_placeholders(recording, name)
    return None if NAME_TOKEN.search(name) else name


# Checkbox and toggle states as the guides write them: '✅ Checked', '❌ Unchecked', '☐',
# 'Enabled', `Uncheck`, 'leave unchecked'. Matched per word, not as the whole value.
CHECKED_WORDS = {"✅", "✔", "checked", "check", "enabled", "yes", "on", "true"}
UNCHECKED_WORDS = {"☐", "❌", "✗", "unchecked", "uncheck", "disabled", "no", "off", "false"}


# A remark after a state: '✅ Checked (or uncheck if already have Defender)' (3.2.5).
REMARK = re.compile(r"\([^()]*\)")


def checkbox_state(value: str) -> bool | None:
    """True or False for a checkbox or toggle value, None when it states neither or both
    ('Leave default', 'Checked or unchecked'), so the runner reports it instead of guessing. A
    remark in parentheses is not read."""
    words = set(re.findall(r"[✅✔☐❌✗]|[a-z]+", REMARK.sub(" ", value).casefold()))
    on, off = bool(words & CHECKED_WORDS), bool(words & UNCHECKED_WORDS)
    return on if on != off else None


def value_action(value: str) -> str:
    """How to treat a field value once placeholders and overrides are applied: 'skip' when the
    whole value is a bracketed instruction (an override '[Leave blank]' leaves the field as it
    is), 'unresolved' when a bracket token is left ('skycraft-auth-[uniqueID]'), otherwise
    'type'."""
    if re.fullmatch(r"\[[^\]]+\]", value.strip()):
        return "skip"
    return "unresolved" if BRACKET_TOKEN.search(value) else "type"


def field_action(recording: dict, step: dict, item: dict) -> tuple[str, str]:
    """What the runner does with a field item, and the value it does it with (#202).

    The value is the recording's valueOverrides entry for the field, or else the guide's value
    with the recording's placeholders applied (resolve_value). An override, and a value parse.py
    did not mark '"literal": false', go to value_action. A value it did mark is typed only when
    the placeholders made it a literal ('[yourtenant]' in an address); otherwise the action is
    'unresolved' when a bracket token is left and 'instruction' when it is still prose ('Click
    the "..." button', 'Select:'), and the runner reports the field instead of typing it."""
    value = resolve_value(recording, step, item["label"], item["value"])
    if (item.get("literal", True) is False and value_override(recording, step, item["label"]) is None
            and not value_is_literal(value)):
        return ("unresolved" if BRACKET_TOKEN.search(value) else "instruction"), value
    return value_action(value), value
