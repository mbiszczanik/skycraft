"""Render an agent Portal pass from pass.json.

Usage: python render_report.py [--no-scan] <pass.json> <out-dir>

Writes:
  <out-dir>/report.html        - the full report page (templates/report.html with the data embedded),
                                 in pass.json's "lang".
  <out-dir>/panel-report.json  - the pass as a `lab-pass` report for the optional agents-config panel, in "lang":
                                 summary, per-lab sections and the decisions (panel_store.py write report).
  <out-dir>/comment-<lab>.md   - one GitHub comment per walked lab, always in English.

Text fields in pass.json are either a string or {"en": ..., "pl": ...}; comments use "en",
the page uses "lang" with "en" as fallback. After writing, the comments are scanned with the
publication guard named by PUBLIC_CONTENT_GUARD (path to guard-public-content.py); any
hit is printed and the exit code is 1, so nothing identifying is posted by accident. Without
a loadable guard the run writes nothing and exits 4, unless --no-scan is given (comments then
must not be posted unreviewed).

Before writing, pass.json is validated: unknown keys, step results outside OK/DRIFT/WRONG/
BLOCKED/NA, and Test-Lab passed/failed counts that are not numbers or disagree with testlab.log (the full saved
output, relative to pass.json) stop the run with exit code 3. With a log, the comment's counts
come from the log itself; a count the script never prints is shown as not counted.
"""
import importlib.util
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "..", "templates", "report.html")
HOOK = os.environ.get("PUBLIC_CONTENT_GUARD", "")
ORDER = ["OK", "DRIFT", "WRONG", "BLOCKED"]
BASE = [""]  # directory of pass.json; testlab.log paths are relative to it


def en(v):
    if isinstance(v, dict):
        return v.get("en", "")
    return "" if v is None else str(v)


def cell(v):
    return en(v).replace("|", "\\|").replace("\n", " ")


def counts(lab):
    c = {k: 0 for k in ORDER + ["NA"]}
    for s in lab.get("steps", []):
        c[s["result"]] = c.get(s["result"], 0) + 1
    return c


def comment(p, lab):
    c = counts(lab)
    out = [f"## Agent Portal pass, {p['date']}, guide at {p['guide_commit']}, {en(lab.get('account_role')) or en(p.get('account_role'))}", ""]
    out.append(f"**Lab {lab['id']}, Portal path.** This is an agent pass (automated browser), not a learner pass. "
               f"Guide read from `origin/main` at `{p['guide_commit']}`." + (" " + en(lab["context"]) if lab.get("context") else ""))
    out.append("")
    res = ", ".join(f"{c[k]} {k}" for k in ORDER)
    if c.get("NA"):
        res += f" ({c['NA']} without action)"
    out += [f"**Result: {res}.**", ""]
    bad = [s for s in lab.get("steps", []) if s["result"] in ("BLOCKED", "WRONG")]
    if bad:
        out += ["**BLOCKED / WRONG first:**"]
        out += [f"- **{s['step']} {s['result']}.** {en(s.get('detail')) or en(s.get('portal'))}" for s in bad]
        out.append("")
    out += ["| Step | Result | Guide says | Portal shows | Evidence |", "|---|---|---|---|---|"]
    for s in lab.get("steps", []):
        out.append(f"| {s['step']} | {s['result']} | {cell(s.get('guide'))} | {cell(s.get('portal'))} | {cell(s.get('evidence'))} |")
    out.append("")
    if lab.get("deviations"):
        out += ["**Deviations from the guide's text (pass constraints, not guide defects):**"] + [f"- {en(d)}" for d in lab["deviations"]] + [""]
    if lab.get("environment"):
        out += ["**Environment, not the guide:**"] + [f"- {en(d)}" for d in lab["environment"]] + [""]
    tl = lab.get("testlab")
    if tl:
        exit_txt = f"exit code {tl['exit']}" if tl.get("exit") is not None else "exit code not captured"
        got = log_counts(tl, BASE[0]) or {"passed": None, "failed": None}
        pa_ = got["passed"] if got["passed"] is not None else tl.get("passed")
        fa_ = got["failed"] if got["failed"] is not None else tl.get("failed")
        cnt = ", ".join(x for x in [f"Passed {pa_}" if pa_ is not None else "passed checks not counted by the script",
                                    f"Failed {fa_}" if fa_ is not None else "failures not counted by the script"])
        out += [f"**Test-Lab.ps1** (from `{p['guide_commit']}`, {en(tl.get('how'))}): **{exit_txt}**, {cnt}.", ""]
        if tl.get("output"):
            out += ["```", tl["output"].rstrip(), "```", ""]
        if tl.get("note"):
            out += [en(tl["note"]), ""]
    pa = lab.get("parity")
    if pa:
        ex = f"exit code {pa['whatif_exit']}" if pa.get("whatif_exit") is not None else "not run"
        out += [f"**Parity with the Bicep** (#362; {en(pa.get('how')) or 'Deploy-Bicep.ps1 -WhatIf against the Portal-built state'}): **{ex}**.", ""]
        diffs = [c for c in pa.get("changes", []) if c.get("verdict") == "difference"]
        noise = [c for c in pa.get("changes", []) if c.get("verdict") != "difference"]
        if diffs:
            out += ["| Resource | Change | Property | Portal path | Bicep | Issue |", "|---|---|---|---|---|---|"]
            out += [f"| {cell(c.get('resource'))} | {c.get('change','')} | {cell(c.get('property'))} | {cell(c.get('portal'))} | {cell(c.get('bicep'))} | {c.get('issue','')} |" for c in diffs]
            out += [""]
        elif pa.get("whatif_exit") is not None:
            out += ["No end-state differences reported." + (f" ({len(noise)} what-if noise entries ignored.)" if noise else ""), ""]
        if pa.get("steps_without_bicep"):
            out += ["Steps with no Bicep counterpart: " + "; ".join(en(x) for x in pa["steps_without_bicep"]) + "."]
        if pa.get("steps_without_script"):
            out += ["Steps with no PowerShell / CLI counterpart: " + "; ".join(en(x) for x in pa["steps_without_script"]) + "."]
        if pa.get("note"):
            out += [en(pa["note"])]
        out += [""]
    if lab.get("checklist_rows"):
        out += [f"**#{p.get('tracking_issue')} checklist rows for {lab['id']}:**"]
        out += [f"- {r['row']}: **{r['verdict']}**" + (f" ({en(r.get('note'))})" if r.get("note") else "") for r in lab["checklist_rows"]]
        out.append("")
    if lab.get("filed_line"):
        out += [en(lab["filed_line"]), ""]
    if lab.get("not_done"):
        out += ["Not done in this pass: " + "; ".join(en(x) for x in lab["not_done"]) + "."]
    return "\n".join(out).rstrip() + "\n"


# Keys the renderer and templates/report.html read. Anything else is a typo (e.g. "commented"
# for "updated") that would silently drop content, so render_report refuses it.
SCHEMA = {
    "": {"lang", "page_title", "title", "title_id", "date", "guide_commit", "repo", "tracking_issue", "intro",
         "meta", "header_note", "account_role", "labs", "findings", "issues", "state", "state_note", "decisions"},
    "labs[]": {"id", "name", "walked", "account_role", "summary", "context", "steps", "deviations", "environment",
               "testlab", "parity", "checklist_rows", "filed_line", "not_done", "ledger_note"},
    "labs[].steps[]": {"step", "result", "guide", "portal", "evidence", "detail", "summary"},
    "labs[].testlab": {"exit", "passed", "failed", "how", "output", "log", "note"},
    "labs[].parity": {"whatif_exit", "how", "changes", "steps_without_bicep", "steps_without_script", "note"},
    "labs[].parity.changes[]": {"resource", "change", "property", "portal", "bicep", "verdict", "issue", "note"},
    "labs[].checklist_rows[]": {"row", "verdict", "note"},
    "findings[]": {"severity", "title", "text"},
    "issues": {"filed", "updated"},
    "issues.filed[]": {"n", "title", "text"},
    "issues.updated[]": {"n", "title", "text"},
    "state[]": {"title", "items"},
    "state[].items[]": {"live", "text"},
    "decisions[]": {"id", "q", "why", "options"},
    "decisions[].options[]": {"value", "label", "desc", "rec"},
}
RESULTS = set(ORDER) | {"NA"}


def validate(p, base):
    errors = []

    def walk(obj, path):
        allowed = SCHEMA.get(path)
        if isinstance(obj, dict) and allowed is not None:
            for k, v in obj.items():
                if k not in allowed:
                    errors.append(f"unknown key '{k}' at {path or '<top>'} (known: {', '.join(sorted(allowed))})")
                else:
                    walk(v, f"{path}.{k}" if path else k)
        elif isinstance(obj, list):
            for x in obj:
                walk(x, path + "[]")

    walk(p, "")
    for lab in p.get("labs", []):
        for st in lab.get("steps", []):
            if st.get("result") not in RESULTS:
                errors.append(f"lab {lab.get('id')} step {st.get('step')}: result '{st.get('result')}' is not one of {sorted(RESULTS)}")
        tl = lab.get("testlab")
        if not tl:
            continue
        got = log_counts(tl, base)
        for k in ("passed", "failed"):
            given = tl.get(k)
            if given is not None and not isinstance(given, int):
                errors.append(f"lab {lab.get('id')} testlab.{k} must be a number or absent, not {given!r}")
            elif got is not None and isinstance(given, int) and got[k] is not None and given != got[k]:
                errors.append(f"lab {lab.get('id')} testlab.{k} is {given} but {tl['log']} says {got[k]}")
            elif got is not None and isinstance(given, int) and got[k] is None:
                errors.append(f"lab {lab.get('id')} testlab.{k} is {given} but {tl['log']} prints no such count; leave it out")
        if got is not None and tl.get("exit") == 0 and (got["failed"] or 0) > 0:
            errors.append(f"lab {lab.get('id')} exit code 0 but {tl['log']} reports {got['failed']} failures")
    return errors


def log_counts(tl, base):
    """Counts from testlab.log (the full saved output, path relative to pass.json); None without a log."""
    if not tl.get("log"):
        return None
    path = os.path.join(base, tl["log"])
    if not os.path.exists(path):
        return {"passed": None, "failed": None, "missing": path}
    with io.open(path, encoding="utf-8", errors="replace") as f:
        return counts_from_output(f.read())


def counts_from_output(text):
    """Passed/failed counts as the script printed them; None where it printed none.

    Test-Lab scripts differ: 'Tests Passed: 39' / 'Tests Failed: 0', 'Passed: 21' / 'Failed: 1', 'Tests Passed: 10 / 11',
    'Failures: 1', or only [PASS] / [FAIL] tags.
    """
    import re
    t = re.sub(r"\x1b\[[0-9;]*m", "", text)
    passed = failed = None
    m = re.findall(r"(?:Tests? )?Passed:\s*(\d+)(?:\s*/\s*(\d+))?", t, re.I)
    if m:
        passed = int(m[-1][0])
        if m[-1][1]:
            failed = int(m[-1][1]) - passed
    m = re.findall(r"(?:(?:Tests? )?Failed|Failures):\s*(\d+)", t, re.I)
    if m:
        failed = int(m[-1])
    if passed is None and failed is None:
        tags_p, tags_f = len(re.findall(r"\[PASS\]", t)), len(re.findall(r"\[FAIL\]", t))
        if tags_p or tags_f:
            passed, failed = tags_p, tags_f
    return {"passed": passed, "failed": failed}


def panel_report(p, now=None):
    """The pass as a `lab-pass` report for the local panel (panel_store.py write report)."""
    import re
    from datetime import datetime
    lang = p.get("lang", "en")

    def tr(v):
        text = (v.get(lang) or v.get("en", "")) if isinstance(v, dict) else ("" if v is None else str(v))
        # The panel shows plain text and refuses an em dash.
        return text.replace("**", "").replace("`", "").replace(" \u2014 ", ": ").replace("\u2014", ",").strip()

    def section(heading, items):
        items = [i for i in items if i]
        return [{"heading": heading, "items": items}] if heading and items else []

    labs = p.get("labs", [])
    modules = sorted({str(lab["id"]).split(".")[0] for lab in labs})
    rid = f"module-{modules[0]}" if len(modules) == 1 else "labs-" + "-".join(str(lab["id"]) for lab in labs)
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9])?", rid) or ".." in rid:
        rid = f"portal-pass-{p.get('date', 'undated')}"
    total = {k: 0 for k in ORDER}
    sections = []
    for lab in labs:
        for k in ORDER:
            total[k] += counts(lab)[k]
        steps = [f"{s['step']} {s['result']}: {tr(s.get('summary')) or tr(s.get('detail')) or tr(s.get('portal'))}"
                 for s in lab.get("steps", []) if s["result"] in ("DRIFT", "WRONG", "BLOCKED")]
        sections += section(f"Lab {lab['id']}: {tr(lab.get('name'))}".rstrip(": "), [tr(lab.get("summary"))] + steps)
    sections += section("Ustalenia" if lang == "pl" else "Findings",
                        [f"{f.get('severity', '')}: {tr(f.get('title'))}. {tr(f.get('text'))}".lstrip(": ")
                         for f in p.get("findings", [])])
    issues = p.get("issues") or {}
    sections += section("Issues", [" ".join(x for x in [f"#{i['n']}" if i.get("n") else "", tr(i.get("title")), tr(i.get("text"))] if x)
                                   for i in issues.get("filed", []) + issues.get("updated", [])])
    for group in p.get("state", []):
        sections += section(tr(group.get("title")), [("(live) " if i.get("live") else "") + tr(i.get("text"))
                                                     for i in group.get("items", []) if tr(i.get("text"))])
    decisions = []
    for d in p.get("decisions", []):
        options = d.get("options", [])
        item = {"id": str(d["id"]), "q": tr(d["q"]), "options": [tr(o.get("label")) for o in options],
                "blocks": False, "who": "Ty" if lang == "pl" else "You"}
        if tr(d.get("why")):
            item["why"] = tr(d["why"])
        facts = [f"{tr(o.get('label'))}: {tr(o.get('desc'))}" for o in options if tr(o.get("desc"))]
        if facts:
            item["facts"] = facts
        rec = next((tr(o.get("label")) for o in options if o.get("rec")), "")
        if rec:
            item["rec"] = rec
        decisions.append(item)
    result = ", ".join(f"{total[k]} {k}" for k in ORDER)
    report = {
        "id": rid, "kind": "lab-pass", "title": tr(p.get("title")) or p.get("page_title") or "Portal pass",
        "at": (now or datetime.now().astimezone()).isoformat(timespec="minutes"),
        "summary": " ".join(x for x in [tr(p.get("intro")), f"{result}. Guide at {p.get('guide_commit', '?')}, {p.get('date', '?')}."] if x),
    }
    if sections:
        report["sections"] = sections
    if decisions:
        report["decisions"] = decisions
    return report


def scanner():
    if not HOOK:
        print("error: PUBLIC_CONTENT_GUARD is not set; set it to the path of guard-public-content.py "
              "or pass --no-scan for a run whose comments will not be posted", file=sys.stderr)
        return None
    try:
        spec = importlib.util.spec_from_file_location("guard", HOOK)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        cfg = mod.load_config()
        return lambda text: mod.findings(text, cfg)
    except Exception as exc:
        print(f"error: PUBLIC_CONTENT_GUARD={HOOK} not loadable ({type(exc).__name__}: {exc})", file=sys.stderr)
        return None


def main():
    no_scan = "--no-scan" in sys.argv[1:]
    args = [a for a in sys.argv[1:] if a != "--no-scan"]
    if len(args) != 2:
        print(__doc__)
        return 2
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    src, out_dir = args
    if no_scan:
        scan = None
        print("warning: --no-scan: comments are NOT scanned for identifying data; do not post them unreviewed",
              file=sys.stderr)
    else:
        scan = scanner()
        if scan is None:
            print("nothing written", file=sys.stderr)
            return 4
    with io.open(src, encoding="utf-8") as f:
        p = json.load(f)
    BASE[0] = os.path.dirname(os.path.abspath(src))
    errors = validate(p, BASE[0])
    for lab in p.get("labs", []):
        got = log_counts(lab.get("testlab") or {}, os.path.dirname(os.path.abspath(src)))
        if got and got.get("missing"):
            errors.append(f"lab {lab.get('id')} testlab.log not found: {got['missing']}")
    if errors:
        for e in errors:
            print("pass.json: " + e, file=sys.stderr)
        print("nothing written; fix pass.json and run again", file=sys.stderr)
        return 3
    os.makedirs(out_dir, exist_ok=True)
    with io.open(TEMPLATE, encoding="utf-8") as f:
        html = f.read()
    title = p["title"].get(p.get("lang", "en"), en(p["title"])) if isinstance(p["title"], dict) else p["title"]
    p.setdefault("title_id", p.get("guide_commit", "") + "-" + p.get("date", ""))
    data = json.dumps(p, ensure_ascii=False).replace("</", "<\\/")
    html = html.replace("__TITLE__", (p.get("page_title") or "Portal Pass")).replace("/*PASS_JSON*/null", data)
    with io.open(os.path.join(out_dir, "report.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write(html)
    with io.open(os.path.join(out_dir, "panel-report.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(panel_report(p), ensure_ascii=False, indent=1) + "\n")
    problems = 0
    for lab in p["labs"]:
        if not lab.get("walked"):
            continue
        text = comment(p, lab)
        path = os.path.join(out_dir, f"comment-{lab['id']}.md")
        with io.open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        hits = scan(text) if scan else []
        for kind, value in hits:
            print(f"IDENTIFYING DATA in {os.path.basename(path)}: {kind} `{value}`")
        problems += len(hits)
        print(f"wrote {path}")
    print(f"wrote {os.path.join(out_dir, 'report.html')}  (title: {title})")
    print(f"wrote {os.path.join(out_dir, 'panel-report.json')}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
