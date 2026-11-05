"""Build a compact, pre-annotated review packet for a WoW addon in one shot.

Replaces redundant validator re-runs, full-addon reads of untouched/kit files,
and one-by-one Find-WowApi.py calls during post-edit code reviews.
"""

from __future__ import annotations

import importlib.util
import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
import wowkit

HIGH_RISK_RX = re.compile(
    r"\b("
    r"Secure\w*|hooksecurefunc|HookScript|SetScript|SetParent|SetAttribute|"
    r"InCombatLockdown|PLAYER_REGEN_\w+|"
    r"ContainerFrame\w*|ChatFrame\w*|BankFrame\w*|BankPanel\w*|PlayerFrame\w*|TargetFrame\w*|"
    r"EditMode\b|issecretvalue|canaccessvalue|issecrettable|hasanysecretvalues|"
    r"ShowUIPanel|HideUIPanel|ToggleUIPanel|ToggleCharacter|CloseAllBags|OpenAllBags|ToggleAllBags|"
    r"SendAddonMessage\w*"
    r")\b"
)
NOTES_HEADING_RX = re.compile(
    r"(hard rule|do not|architecture|verified|open|tradeoff|known limit|lesson|advisor review|deferred|skipped|taint|secret)",
    re.I,
)
CODE_EXTS = (".lua", ".toc", ".xml")


def _load_validator():
    spec = importlib.util.spec_from_file_location("test_wow_addon", os.path.join(SCRIPT_DIR, "Test-WowAddon.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def infer_flavors(addon_dir):
    folder = os.path.basename(addon_dir)
    found = []
    suffix_to_flavor = {info["TocSuffix"].lower(): name for name, info in wowkit.KNOWN_FLAVORS.items()}
    for name in sorted(os.listdir(addon_dir)):
        if not name.lower().endswith(".toc"):
            continue
        base = os.path.splitext(name)[0]
        if base.lower() != folder.lower() and base.lower().startswith(folder.lower() + "_"):
            suf = base[len(folder) + 1:].lower()
            if suf in suffix_to_flavor and suffix_to_flavor[suf] not in found:
                found.append(suffix_to_flavor[suf])
        text = open(os.path.join(addon_dir, name), "r", encoding="utf-8-sig", errors="replace").read()
        for match in re.finditer(r"(?m)^\s*##\s*Interface[^:]*:\s*(.+)$", text):
            for part in match.group(1).split(","):
                part = part.strip()
                if part.isdigit():
                    flav = wowkit.flavor_for_interface(int(part))
                    if flav and flav not in found:
                        found.append(flav)
    return found or ["forever"]


def _run_git(args, cwd):
    try:
        proc = subprocess.run(
            ["git", *args],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        return proc.returncode, proc.stdout or ""
    except OSError:
        return 1, ""


def _annotate_diff_with_lines(diff_text):
    out = []
    new_line = 0
    for line in diff_text.splitlines():
        hunk = re.match(r"^@@\s*-\d+(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s*@@(.*)$", line)
        if hunk:
            new_line = int(hunk.group(1))
            out.append(line)
            continue
        if line.startswith(("diff --git ", "index ", "--- ", "+++ ")):
            out.append(line)
            continue
        if line.startswith("+"):
            out.append(f"{new_line:>5} + {line[1:]}")
            new_line += 1
        elif line.startswith("-"):
            out.append(f"    - - {line[1:]}")
        elif line.startswith(" "):
            out.append(f"{new_line:>5}   {line[1:]}")
            new_line += 1
        else:
            out.append(line)
    return "\n".join(out)


def collect_git_changes(addon_dir, kit_dialog_same):
    rc, top = _run_git(["rev-parse", "--show-toplevel"], addon_dir)
    if rc != 0 or not top.strip():
        return {"tracked": False, "source": "untracked", "files": [], "skipped": [], "added": 0, "deleted": 0, "diff": "", "changed_code": ""}
    repo_root = os.path.abspath(top.strip())
    rel_addon = os.path.relpath(addon_dir, repo_root).replace("\\", "/")

    _rc, tracked_out = _run_git(["ls-files", "--", rel_addon], repo_root)
    is_tracked = bool(tracked_out.strip())
    if not is_tracked:
        return {"tracked": False, "source": "untracked-addon", "files": [], "skipped": [], "added": 0, "deleted": 0, "diff": "", "changed_code": ""}

    _rc, status_out = _run_git(["status", "--porcelain", "--", rel_addon], repo_root)
    source = "working-tree"
    diff_base = ["HEAD"]
    untracked_files = []
    for sline in status_out.splitlines():
        if sline.startswith("?? "):
            u_rel = sline[3:].strip().strip('"')
            u_full = os.path.abspath(os.path.join(repo_root, u_rel))
            if os.path.isdir(u_full):
                for dp, _ds, fns in os.walk(u_full):
                    for fn in fns:
                        untracked_files.append(os.path.join(dp, fn))
            elif os.path.isfile(u_full):
                untracked_files.append(u_full)

    if not status_out.strip():
        # Working tree clean for this addon: inspect the latest commit touching this addon.
        rc_last, last_sha = _run_git(["log", "-n", "1", "--pretty=format:%H", "--", rel_addon], repo_root)
        sha = last_sha.strip()
        if rc_last == 0 and sha:
            source = f"last-commit ({sha[:8]})"
            diff_base = [f"{sha}~1", sha]
        else:
            return {"tracked": True, "source": "clean", "files": [], "skipped": [], "added": 0, "deleted": 0, "diff": "", "changed_code": ""}

    if len(diff_base) == 1:
        _rc, raw_diff = _run_git(["diff", "-U4", "HEAD", "--", rel_addon], repo_root)
    else:
        _rc, raw_diff = _run_git(["diff", "-U4", diff_base[0], diff_base[1], "--", rel_addon], repo_root)

    # Split diff per file, filter to code files, and skip unmodified EditModeDialog.lua.
    chunks = re.split(r"(?m)(?=^diff --git )", raw_diff)
    kept_chunks = []
    changed_files = []
    skipped = []
    added = 0
    deleted = 0
    changed_code_lines = []

    for chunk in chunks:
        if not chunk.strip():
            continue
        m = re.match(r"^diff --git a/(.*?) b/(.*?)$", chunk.splitlines()[0])
        b_path = m.group(2) if m else ""
        full_b = os.path.abspath(os.path.join(repo_root, b_path))
        rel_in_addon = os.path.relpath(full_b, addon_dir).replace("/", "\\")
        base_name = os.path.basename(rel_in_addon)
        ext = os.path.splitext(base_name)[1].lower()
        if base_name.lower() == "editmodedialog.lua" and kit_dialog_same:
            skipped.append(f"{rel_in_addon} (unmodified kit copy)")
            continue
        if ext not in CODE_EXTS:
            skipped.append(f"{rel_in_addon} (non-code)")
            continue
        changed_files.append(rel_in_addon)
        for dline in chunk.splitlines():
            if dline.startswith("+") and not dline.startswith("+++"):
                added += 1
                changed_code_lines.append(dline[1:])
            elif dline.startswith("-") and not dline.startswith("---"):
                deleted += 1
                changed_code_lines.append(dline[1:])
        kept_chunks.append(_annotate_diff_with_lines(chunk))

    for u_full in sorted(untracked_files):
        rel_in_addon = os.path.relpath(u_full, addon_dir).replace("/", "\\")
        base_name = os.path.basename(rel_in_addon)
        ext = os.path.splitext(base_name)[1].lower()
        if base_name.lower() == "editmodedialog.lua" and kit_dialog_same:
            skipped.append(f"{rel_in_addon} (unmodified kit copy)")
            continue
        if ext not in CODE_EXTS:
            skipped.append(f"{rel_in_addon} (non-code)")
            continue
        changed_files.append(rel_in_addon)
        lines = open(u_full, "r", encoding="utf-8-sig", errors="replace").read().splitlines()
        added += len(lines)
        changed_code_lines.extend(lines)
        numbered = "\n".join(f"{idx:>5} + {txt}" for idx, txt in enumerate(lines, 1))
        kept_chunks.append(f"--- /dev/null\n+++ {rel_in_addon} (untracked)\n{numbered}")

    return {
        "tracked": True,
        "source": source,
        "files": changed_files,
        "skipped": skipped,
        "added": added,
        "deleted": deleted,
        "diff": "\n\n".join(kept_chunks),
        "changed_code": "\n".join(changed_code_lines),
    }


def extract_notes_summary(addon_dir, max_lines=60):
    notes_path = os.path.join(addon_dir, "NOTES.md")
    if not os.path.isfile(notes_path):
        return []
    lines = open(notes_path, "r", encoding="utf-8-sig", errors="replace").read().splitlines()
    captured = []
    keep_section = False
    skip_section = False
    for line in lines:
        heading = re.match(r"^(#{2,3})\s+(.+)$", line)
        if heading:
            title = heading.group(2)
            skip_section = bool(re.search(r"\b(version history|files|file map|how to install|checklist|testing)\b", title, re.I))
            keep_section = (not skip_section) and bool(NOTES_HEADING_RX.search(title))
            if keep_section:
                captured.append(line)
            continue
        if skip_section:
            continue
        if keep_section:
            if line.strip():
                captured.append(line if len(line) <= 320 else line[:317] + "...")
        elif re.search(r"\b(skipped|not applied|waiting on|declined|do not|never )\b", line, re.I):
            captured.append(line if len(line) <= 320 else line[:317] + "...")
        if len(captured) >= max_lines:
            captured.append(f"... (truncated at {max_lines} lines; see NOTES.md for full text)")
            break
    return captured


def extract_api_annotations(code_text, api):
    if not api or not code_text.strip():
        return []
    stripped = re.sub(r"--[^\n]*", "", code_text)
    fn_meta = api.get("FunctionMeta") or {}
    methods_meta = api.get("Methods") or {}
    event_meta = api.get("EventMeta") or {}
    notes = []
    seen = set()

    for m in re.finditer(r"(?<![\w.:])(C_\w+\.\w+|[A-Z][A-Za-z0-9_]+)\s*\(", stripped):
        fn = m.group(1)
        if fn in seen:
            continue
        seen.add(fn)
        if fn in api["Deprecated"]:
            notes.append(f"  {fn:<36} [DEPRECATED: {api['Deprecated'][fn]}]")
            continue
        meta = fn_meta.get(fn)
        if not meta:
            continue
        tags = []
        if meta.get("protected"):
            tags.append("PROTECTED")
        if meta.get("restricted"):
            tags.append("restricted")
        if meta.get("noSecureHook"):
            tags.append("no-hooksecurefunc")
        if meta.get("secret"):
            tags.append("secret: " + ", ".join(meta["secret"]))
        if meta.get("secretArgs") in ("AllowedWhenUntainted", "NotAllowed"):
            tags.append(f"secretArgs: {meta['secretArgs']}")
        if meta.get("requires"):
            tags.append("requires: " + ", ".join(meta["requires"]))
        if tags:
            notes.append(f"  {fn:<36} [{'; '.join(tags)}]")

    for m in re.finditer(r":([A-Za-z_]\w*)\s*\(", stripped):
        mn = m.group(1)
        key = ":" + mn
        if key in seen:
            continue
        seen.add(key)
        mmeta = methods_meta.get(mn)
        if not mmeta:
            continue
        tags = []
        sargs = mmeta.get("secretArgs") or []
        has_secret_ret = bool(mmeta.get("secret"))
        rejects_tainted_secret = bool(sargs and "AllowedWhenTainted" not in sargs and ("AllowedWhenUntainted" in sargs or "NotAllowed" in sargs))
        if not (has_secret_ret or (rejects_tainted_secret and mn in ("SetTimerDuration", "SetCooldownFromDurationObject", "SetAttribute", "SetID"))):
            if "AllowedWhenTainted" in sargs and mn in ("SetValue", "SetMinMaxValues", "SetText", "SetFormattedText", "SetVertexColorFromBoolean", "SetAlphaFromBoolean", "SetTexture"):
                notes.append(f"  {key:<36} [secretArgs: AllowedWhenTainted (safe sink)]")
            continue
        if mmeta.get("protected"):
            tags.append("PROTECTED")
        if has_secret_ret:
            tags.append("secret: " + ", ".join(mmeta["secret"]))
        if sargs:
            tags.append("secretArgs: " + "|".join(sargs))
        if tags:
            notes.append(f"  {key:<36} [{'; '.join(tags)}]")

    for m in re.finditer(r"['\"]([A-Z][A-Z0-9_]{3,})['\"]|\bfunction\s+\w+[:.]([A-Z][A-Z0-9_]{3,})\s*\(", stripped):
        ev = m.group(1) or m.group(2)
        if not ev or ev in seen or ev not in api["Events"]:
            continue
        seen.add(ev)
        if api["Events"].get(ev):
            em = event_meta.get(ev) or {}
            detail = ": " + ", ".join(em.get("secret") or []) if em.get("secret") else ""
            notes.append(f"  event {ev:<30} [secret payloads{detail}]")

    return sorted(notes, key=str.lower)


def build_packet(path, flavors, full=False, threshold=40, no_luacheck=False):
    if not os.path.isdir(path):
        wowkit.die(f"Not a folder: {path}")
    addon_dir = os.path.abspath(path)
    resolved_flavors = wowkit.resolve_flavors(flavors) if flavors else infer_flavors(addon_dir)

    validator = _load_validator()
    val = validator.check(addon_dir, resolved_flavors, no_luacheck=no_luacheck)
    issues = [f for f in val["Findings"] if f["Severity"] != "info"]
    info_count = len(val["Findings"]) - len(issues)

    kit_dialog_path = os.path.join(wowkit.KIT_ROOT, "templates", "editmode", "EditModeDialog.lua")
    addon_dialog_path = os.path.join(addon_dir, "EditModeDialog.lua")
    kit_same = False
    if os.path.isfile(addon_dialog_path) and os.path.isfile(kit_dialog_path):
        kit_same = (
            validator.read_text(addon_dialog_path).replace("\r\n", "\n")
            == validator.read_text(kit_dialog_path).replace("\r\n", "\n")
        )

    git_info = collect_git_changes(addon_dir, kit_same)
    use_full = full or not git_info["tracked"]

    api = wowkit.api_index(val["ApiBranch"] or "forever")
    if use_full:
        all_lua = []
        file_list = []
        for full_f, rel_f, name_f in validator.list_lua(addon_dir):
            if name_f.lower() == "editmodedialog.lua" and kit_same:
                continue
            if validator.LIB_RX.search(rel_f):
                continue
            file_list.append(rel_f)
            all_lua.append(validator.read_text(full_f))
        scan_text = "\n".join(all_lua)
        api_notes = extract_api_annotations(scan_text, api)
    else:
        file_list = git_info["files"]
        scan_text = git_info["changed_code"]
        api_notes = extract_api_annotations(scan_text, api)

    risk_hits = sorted(set(m.group(1) for m in HIGH_RISK_RX.finditer(scan_text))) if scan_text else []
    has_secret_api_in_diff = any("[secret:" in n or "[secret payloads" in n or "AllowedWhenUntainted" in n or "NotAllowed" in n or "PROTECTED" in n for n in api_notes)

    if use_full:
        mode = "subagent-full"
        reason = "-Full requested" if full else f"addon not yet tracked in git ({git_info['source']})"
    elif not git_info["files"] and val["Errors"] == 0 and val["Warnings"] == 0:
        mode = "inline"
        reason = "no changed code files and 0 validator errors/warnings"
    elif (
        val["Errors"] == 0
        and val["Warnings"] == 0
        and len(git_info["files"]) <= 2
        and (git_info["added"] + git_info["deleted"]) <= threshold
        and not risk_hits
        and not has_secret_api_in_diff
    ):
        mode = "inline"
        reason = f"small low-risk diff ({git_info['added'] + git_info['deleted']} changed lines <= {threshold}, <= 2 files, no taint/secure/secret triggers, 0 validator issues)"
    else:
        mode = "subagent-diff"
        reasons = []
        if val["Errors"] or val["Warnings"]:
            reasons.append(f"{val['Errors']}E/{val['Warnings']}W from validator")
        if len(git_info["files"]) > 2 or (git_info["added"] + git_info["deleted"]) > threshold:
            reasons.append(f"{len(git_info['files'])} file(s), +{git_info['added']}/-{git_info['deleted']} lines")
        if risk_hits:
            reasons.append("touches " + ", ".join(risk_hits[:6]))
        if has_secret_api_in_diff:
            reasons.append("touches secret/protected APIs or events")
        reason = "; ".join(reasons) or "diff review"

    notes_summary = extract_notes_summary(addon_dir)

    return {
        "Addon": val["Addon"],
        "Flavors": resolved_flavors,
        "ApiBranch": val["ApiBranch"],
        "ApiCommit": val["ApiCommit"],
        "Errors": val["Errors"],
        "Warnings": val["Warnings"],
        "InfoNotes": info_count,
        "Findings": issues,
        "RecommendedMode": mode,
        "ModeReason": reason,
        "DiffSource": "full" if use_full else git_info["source"],
        "FilesInScope": file_list,
        "SkippedFiles": (["EditModeDialog.lua (unmodified kit copy)"] if (use_full and kit_same) else git_info["skipped"]),
        "AddedLines": git_info["added"],
        "DeletedLines": git_info["deleted"],
        "RiskTriggers": risk_hits,
        "ApiAnnotations": api_notes,
        "NotesSummary": notes_summary,
        "Diff": "" if use_full else git_info["diff"],
    }


def print_packet(pkt):
    commit = (pkt["ApiCommit"] or "none")[:10]
    wowkit.host(f"=== Review Packet: {pkt['Addon']} ({', '.join(pkt['Flavors'])} | API: {pkt['ApiBranch']} @ {commit}) ===")
    wowkit.host(f"Validator: {pkt['Errors']} error(s), {pkt['Warnings']} warning(s) ({pkt['InfoNotes']} info note(s) omitted)")
    wowkit.host(f"RecommendedMode: {pkt['RecommendedMode']}  ({pkt['ModeReason']})")
    wowkit.host(f"Scope ({pkt['DiffSource']}): {', '.join(pkt['FilesInScope']) if pkt['FilesInScope'] else '(none)'}")
    if pkt["SkippedFiles"]:
        wowkit.host(f"Skipped (do NOT read): {', '.join(pkt['SkippedFiles'])}")

    if pkt["Findings"]:
        wowkit.host("\n--- Validator Errors & Warnings ---")
        for item in pkt["Findings"]:
            loc = f"{item['File']}:{item['Line']}" if (item["File"] and item["Line"]) else (item["File"] or pkt["Addon"])
            wowkit.host(f"  {item['Severity'].upper():<5} {loc}  [{item['Rule']}] {item['Message']}")

    if pkt["NotesSummary"]:
        wowkit.host("\n--- NOTES.md Rules & Settled/Deferred Items (do NOT re-flag skipped items) ---")
        for nline in pkt["NotesSummary"]:
            wowkit.host("  " + nline)

    if pkt["ApiAnnotations"]:
        wowkit.host("\n--- Forever API / Widget / Event Metadata in Scope (pre-checked; skip Find-WowApi.py for these) ---")
        for aline in pkt["ApiAnnotations"]:
            wowkit.host(aline)

    if pkt["Diff"]:
        wowkit.host("\n--- Line-Numbered Diff ---")
        wowkit.host(pkt["Diff"])


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Path", "value", None),
        ("Flavor", "list", []),
        ("Full", "switch", False),
        ("Threshold", "value", "40"),
        ("NoLuacheck", "switch", False),
        ("Json", "switch", False),
    ])
    if not args["Path"]:
        wowkit.die("Missing value for -Path")
    pkt = build_packet(
        args["Path"],
        args["Flavor"],
        full=args["Full"],
        threshold=int(args["Threshold"]),
        no_luacheck=args["NoLuacheck"],
    )
    if args["Json"]:
        print(json.dumps(pkt, indent=2))
    else:
        print_packet(pkt)
    raise SystemExit(1 if pkt["Errors"] else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
