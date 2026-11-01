"""Look up functions, widget methods, events, and UI source definitions in the local index.

Supports multiple patterns in one call, plus -Methods and -UiSource (INDEX.tsv filtered for the branch).
"""

from __future__ import annotations

import fnmatch
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit

BRANCHES = ("forever", "live", "ptr", "classic", "classic_era", "classic_anniversary", "classic_titan", "beta")


def like(name, pattern):
    return fnmatch.fnmatch(name.casefold(), pattern.casefold())


def format_fn_tags(meta):
    if not meta:
        return ""
    tags = []
    if meta.get("protected"):
        tags.append("PROTECTED")
    if meta.get("restricted"):
        tags.append("restricted")
    if meta.get("noSecureHook"):
        tags.append("no-hooksecurefunc")
    if meta.get("secret"):
        tags.append(f"secret: {', '.join(meta['secret'])}")
    if meta.get("secretArgs"):
        tags.append(f"secretArgs: {meta['secretArgs']}")
    if meta.get("requires"):
        tags.append(f"requires: {', '.join(meta['requires'])}")
    return ("   [" + "; ".join(tags) + "]") if tags else ""


def format_method_tags(meta):
    if not meta:
        return ""
    objs = meta.get("objects") or []
    obj_label = ", ".join(objs[:3]) + (f" +{len(objs) - 3}" if len(objs) > 3 else "")
    tags = []
    if obj_label:
        tags.append(obj_label)
    if meta.get("protected"):
        tags.append("PROTECTED")
    elif meta.get("protectedObjects"):
        tags.append(f"PROTECTED on {', '.join(meta['protectedObjects'])}")
    if meta.get("restricted"):
        tags.append("restricted")
    if meta.get("secret"):
        tags.append(f"secret: {', '.join(meta['secret'])}")
    if meta.get("secretArgs"):
        tags.append(f"secretArgs: {'|'.join(meta['secretArgs'])}")
    if meta.get("requires"):
        tags.append(f"requires: {', '.join(meta['requires'])}")
    return ("   [" + "; ".join(tags) + "]") if tags else ""


def search_ui_source(patterns, branch, limit, all_flavors):
    index_tsv = wowkit.KIT_ROOT / "data" / "ui-source" / branch / "INDEX.tsv"
    if not index_tsv.is_file():
        wowkit.warn(f"No UI source index at {index_tsv}. Run Update-WowUiSource.py -Branch {branch} first.")
        raise SystemExit(1)
    mainline = branch in ("forever", "live", "ptr", "beta")
    exclude_rx = None
    if not all_flavors:
        exclude_rx = re.compile(
            r"/(Classic|Vanilla|TBC|Wrath|Cata|Mists)/" if mainline else r"/(Mainline|Camelot|Standard)/",
            re.I,
        )
    rows = []
    with index_tsv.open("r", encoding="utf-8-sig", errors="replace") as handle:
        for idx, line in enumerate(handle):
            if idx == 0 and line.startswith("name\t"):
                continue
            parts = line.rstrip("\r\n").split("\t")
            if len(parts) < 3:
                continue
            if exclude_rx and exclude_rx.search(parts[2]):
                continue
            rows.append((parts[0], parts[1], parts[2]))
    wowkit.host(f"UI source INDEX.tsv ({branch}, {'all folders' if all_flavors else 'branch-loaded folders only'}):")
    for raw_pat in patterns:
        wild = raw_pat if any(ch in raw_pat for ch in "*?") else f"*{raw_pat}*"
        exact = [r for r in rows if r[0].casefold() == raw_pat.casefold()]
        hits = exact if (exact and not any(ch in raw_pat for ch in "*?")) else [r for r in rows if like(r[0], wild)]
        if len(patterns) > 1:
            wowkit.host(f"-- {raw_pat} --")
        for name, kind, loc in hits[:limit]:
            wowkit.host(f"  {name}\t{kind}\t{loc}")
        wowkit.host(f"{len(hits)} UI definition(s)" + (f" (showing first {limit})" if len(hits) > limit else ""))


def lookup_pattern(raw_pattern, api, branch, args, limit):
    pattern = raw_pattern.lstrip(":")
    method_only = args["Methods"] or raw_pattern.startswith(":")
    wild = pattern if any(ch in pattern for ch in "*?") else f"*{pattern}*"
    if args["Events"]:
        hits = sorted((name for name in api["Events"] if like(name, wild)), key=str.lower)
        if args["SecretOnly"]:
            hits = [name for name in hits if api["Events"][name]]
        for name in hits[:limit]:
            emeta = api.get("EventMeta", {}).get(name) or {}
            reasons = emeta.get("secret") or []
            if api["Events"][name]:
                detail = f": {', '.join(reasons)}" if reasons else ""
                mark = f"   [secret payloads{detail}]"
            else:
                mark = ""
            wowkit.host(f"{name}{mark}")
        wowkit.host(f"{len(hits)} event(s)")
        return

    fn_meta = api.get("FunctionMeta") or {}
    methods = api.get("Methods") or {}

    if not method_only:
        hits = sorted((name for name in api["Functions"] if like(name, wild)), key=str.lower)
        if args["SecretOnly"]:
            hits = [name for name in hits if api["Functions"][name]]
        for name in hits[:limit]:
            meta = fn_meta.get(name) or {"secret": api["Functions"][name]}
            wowkit.host(f"{name}{format_fn_tags(meta)}")
        wowkit.host(f"{len(hits)} documented function(s)")

    m_hits = sorted((name for name in methods if like(name, wild)), key=str.lower)
    if args["SecretOnly"]:
        m_hits = [name for name in m_hits if methods[name].get("secret") or methods[name].get("secretArgs")]
    if m_hits and (method_only or len(m_hits) <= limit):
        for name in m_hits[:limit]:
            wowkit.host(f":{name}{format_method_tags(methods[name])}")
        wowkit.host(f"{len(m_hits)} widget method(s)")
    elif m_hits:
        for name in m_hits[:min(15, limit)]:
            wowkit.host(f":{name}{format_method_tags(methods[name])}")
        wowkit.host(f"{len(m_hits)} widget method(s) (pass -Methods to list up to {limit})")

    if not method_only and not any(ch in pattern for ch in "*?."):
        if pattern in api["Functions"]:
            wowkit.host(f"{pattern} is a documented global function.")
        elif pattern in api["Deprecated"]:
            wowkit.host(f"{pattern} exists only through Blizzard's deprecation shim ({api['Deprecated'][pattern]}); it is scheduled for removal.")
        elif pattern in api["Globals"]:
            wowkit.host(f"{pattern} is used or defined by Blizzard's own UI code on {branch} (FrameXML/engine global).")
        elif pattern in methods:
            wowkit.host(f"{pattern} is a widget ScriptObject method (:{pattern}), not a global function.")
        else:
            wowkit.host(f"{pattern} is NOT a global on {branch} (not documented, not used by Blizzard's UI code).")
            if pattern in api["ByShort"]:
                wowkit.host("  Namespaced: " + ", ".join(api["ByShort"][pattern]))


def main(argv):
    positionals = []
    flags = []
    valued = {"branch", "max"}
    i = 0
    while i < len(argv):
        token = argv[i]
        if token.startswith("-"):
            flags.append(token)
            name = token[1:].lstrip("-").split(":", 1)[0].lower()
            if name in valued and ":" not in token[1:] and i + 1 < len(argv) and not argv[i + 1].startswith("-"):
                flags.append(argv[i + 1])
                i += 2
                continue
            i += 1
            continue
        positionals.append(token)
        i += 1
    args = wowkit.parse_ps_args(flags, [
        ("Branch", "value", "forever"),
        ("Events", "switch", False),
        ("Methods", "switch", False),
        ("SecretOnly", "switch", False),
        ("UiSource", "switch", False),
        ("AllFlavors", "switch", False),
        ("Max", "value", "60"),
    ])
    if not positionals:
        wowkit.die("Missing pattern(s). Example: Find-WowApi.py GetSpellInfo UnitHealth :SetTimerDuration")
    branch = args["Branch"]
    if branch not in BRANCHES:
        wowkit.die(f"Unknown branch '{branch}'.")
    limit = int(args["Max"])
    if args["UiSource"]:
        search_ui_source(positionals, branch, limit, args["AllFlavors"])
        raise SystemExit(0)
    api = wowkit.api_index(branch)
    if not api:
        wowkit.warn(f"No index for '{branch}'. Run Update-WowApiIndex.py -Branch {branch} first.")
        raise SystemExit(1)
    wowkit.host(f"API index: {branch} @ {api['Commit'][:10]}  ({api['Source']})")
    for idx, pattern in enumerate(positionals):
        if len(positionals) > 1:
            if idx > 0:
                wowkit.host("")
            wowkit.host(f"=== {pattern} ===")
        lookup_pattern(pattern, api, branch, args, limit)
    raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
