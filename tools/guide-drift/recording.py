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
  value_action         type it, leave it ('[Leave blank]'), or report an unresolved [token]
  rejected_candidates  the reference set of candidates not chosen, without tenant data
  write_json           writes the recording or the state file atomically
"""
from __future__ import annotations

import difflib
import json
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

from decide import Candidate

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


def write_json(path: Path, data: dict) -> None:
    """Write `data` as indented UTF-8 JSON through a temporary file and os.replace, so Ctrl+C or
    a closed window mid-write never leaves a truncated recording or state file behind."""
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temp, path)


GUID = re.compile(r"[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}")


class Redactor:
    """Keeps tenant data out of the committed recording, which lives in a public repository.
    The tenant's domain and id become tokens on the way into the recording and are restored on
    the way out, so a recorded name such as 'malfurion.stormrage@[tenantdomain]' still finds its
    element. The tenant prefix (the domain's first label, as in a directory named 'contoso')
    becomes '[yourtenant]', the guides' own placeholder, when it is at least 4 characters long;
    a shorter one would clobber ordinary words. tests/Guide-Drift-Recording.Tests.ps1 is the
    backstop: it fails on any literal e-mail address, *.onmicrosoft.com domain, guest user
    principal name or GUID in a recording.

    Restored values are lower case, as the Portal shows domains and ids; a display name that
    spells the prefix in another case ('Contoso') comes back as 'contoso'."""

    DOMAIN = "[tenantdomain]"
    TENANT = "[tenantid]"
    PREFIX = "[yourtenant]"
    PREFIX_MIN = 4

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
        # Last, so the full domain is already a token. Bounded by anything but a letter, digit,
        # '_' or '-': 'contoso Ltd' is redacted, 'contoso-admins' and 'contosoville' are not.
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
    for name in env_names(recording):
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
