"""Build data/api-<branch>.json from Blizzard's UI source.

The download hits GitHub. Pass -OutDir to keep the live data\\api-forever.json untouched.
"""

from __future__ import annotations

import io
import json
import os
import re
import sys
import urllib.request
import zipfile
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit

REPO = "Gethe/wow-ui-source"
BRANCHES = ("forever", "live", "ptr", "classic", "classic_era", "classic_anniversary", "classic_titan", "beta")
KEYWORDS = {"if", "for", "while", "function", "return", "and", "or", "not", "local", "elseif", "until"}
CALL_RX = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(")
DEF_RX = re.compile(r"(?m)^\s*(?:function\s+([A-Za-z_]\w*)\s*\(|([A-Za-z_]\w*)\s*=)")
STRIP_RX = re.compile(r"--\[(=*)\[[\s\S]*?\]\1\]|--[^\n]*|\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'")
# -match / -like are case-insensitive. [regex]::Matches (calls, defs, strip) is not.
DEPRECATED_RX = re.compile(r"/Blizzard_Deprecated[^/]*/", re.I)
FUNC_LINE = re.compile(r"^\s*function\s+([A-Za-z_]\w*)\s*\(", re.I)
ASSIGN_LINE = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(function|C_\w+\.\w+)", re.I)


def _get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "wow-forever-addons-plugin"})
    with urllib.request.urlopen(request) as response:
        return response.read()


def _read_entry(zf, info):
    with zf.open(info) as handle:
        return io.TextIOWrapper(handle, encoding="utf-8-sig", errors="replace").read()


def _add_doc(text, functions, events, namespaces, methods):
    ns = None
    doc_name = None
    doc_type = None
    section = None
    entry = None

    def flush():
        nonlocal entry
        if entry is None:
            return
        sec = section.casefold() if section else ""
        if sec == "functions" and entry.get("Name"):
            if doc_type == "ScriptObject":
                mname = entry["Name"]
                slot = methods.setdefault(mname, {
                    "objects": set(),
                    "secret": set(),
                    "secretArgs": set(),
                    "protectedObjects": set(),
                    "restrictedObjects": set(),
                    "requires": set(),
                })
                obj = doc_name or "ScriptObject"
                slot["objects"].add(obj)
                slot["secret"].update(entry["Secret"])
                if entry.get("SecretArgs"):
                    slot["secretArgs"].add(entry["SecretArgs"])
                if entry.get("Protected"):
                    slot["protectedObjects"].add(obj)
                if entry.get("Restricted"):
                    slot["restrictedObjects"].add(obj)
                slot["requires"].update(entry["Requires"])
            else:
                key = f"{ns}.{entry['Name']}" if ns else entry["Name"]
                meta = {"secret": list(entry["Secret"])}
                if entry.get("SecretArgs"):
                    meta["secretArgs"] = entry["SecretArgs"]
                if entry.get("Protected"):
                    meta["protected"] = True
                if entry.get("Restricted"):
                    meta["restricted"] = True
                if entry.get("NoSecureHook"):
                    meta["noSecureHook"] = True
                if entry["Requires"]:
                    meta["requires"] = list(entry["Requires"])
                functions[key] = meta
        elif sec == "events" and entry.get("Literal"):
            has_secret = bool(entry.get("SecretPayloads") or entry["Secret"])
            emeta = {"secretPayloads": has_secret}
            if entry["Secret"]:
                emeta["secret"] = list(entry["Secret"])
            events[entry["Literal"]] = emeta
        entry = None

    for line in re.split(r"\r?\n", text):
        match = re.match(r'^\tName = "([^"]+)"', line, re.I)
        if match:
            doc_name = match.group(1)
            continue
        match = re.match(r'^\tType = "([^"]+)"', line, re.I)
        if match:
            doc_type = match.group(1)
            continue
        match = re.match(r'^\tNamespace = "([^"]+)"', line, re.I)
        if match:
            ns = match.group(1)
            namespaces.add(ns)
            continue
        match = re.match(r"^\t(Functions|Events|Tables|Predicates) =", line, re.I)
        if match:
            flush()
            section = match.group(1)
            continue
        match = re.match(r'^\t\t\tName = "([^"]+)"', line, re.I)
        if match:
            flush()
            entry = {"Name": match.group(1), "Secret": [], "Requires": []}
            continue
        if entry is None:
            continue
        match = re.match(r'^\t\t\tLiteralName = "([^"]+)"', line, re.I)
        if match:
            entry["Literal"] = match.group(1)
        elif re.match(r"^\t\t\tSecretPayloads = true", line, re.I):
            entry["SecretPayloads"] = True
        elif re.match(r"^\t\t\tIsProtectedFunction = true", line, re.I):
            entry["Protected"] = True
        elif re.match(r"^\t\t\tHasRestrictions = true", line, re.I):
            entry["Restricted"] = True
        elif re.match(r"^\t\t\tSecureHooksAllowed = false", line, re.I):
            entry["NoSecureHook"] = True
        elif re.match(r"^\t\t\tSecretReturnsForAspect\s*=", line, re.I):
            if "SecretReturnsForAspect" not in entry["Secret"]:
                entry["Secret"].append("SecretReturnsForAspect")
        else:
            match = re.match(r'^\t\t\tSecretArguments = "([^"]+)"', line, re.I)
            if match:
                entry["SecretArgs"] = match.group(1)
                continue
            match = re.match(r"^\t\t\t(SecretReturns|SecretWhen\w+|SecretIn\w+) = true", line, re.I)
            if match:
                entry["Secret"].append(match.group(1))
                continue
            match = re.match(r"^\t\t\t(Requires\w+) = true", line, re.I)
            if match:
                entry["Requires"].append(match.group(1))
    flush()


def _finalize_methods(raw_methods):
    out = {}
    for mname in sorted(raw_methods):
        slot = raw_methods[mname]
        objs = sorted(slot["objects"])
        meta = {"objects": objs}
        if slot["secret"]:
            meta["secret"] = sorted(slot["secret"])
        if slot["secretArgs"]:
            meta["secretArgs"] = sorted(slot["secretArgs"])
        if slot["protectedObjects"]:
            if len(slot["protectedObjects"]) == len(objs):
                meta["protected"] = True
            else:
                meta["protectedObjects"] = sorted(slot["protectedObjects"])
        if slot["restrictedObjects"] and len(slot["restrictedObjects"]) == len(objs):
            meta["restricted"] = True
        if slot["requires"]:
            meta["requires"] = sorted(slot["requires"])
        out[mname] = meta
    return out


def _scan_lua_entries(entries, branch):
    mainline = branch in ("forever", "live", "ptr", "beta")
    other = re.compile(r"/(Classic|Vanilla|TBC|Wrath|Cata|Mists)/" if mainline else r"/(Mainline|Camelot|Standard)/", re.I)
    functions = {}
    events = {}
    namespaces = set()
    methods = {}
    deprecated = {}
    globals_ = set()
    doc_count = 0
    lua_count = 0
    for path, read_fn in entries:
        norm = path.replace("\\", "/")
        folded = norm.casefold()
        if not folded.endswith(".lua"):
            continue
        if "/blizzard_apidocumentationgenerated/" in folded:
            _add_doc(read_fn(), functions, events, namespaces, methods)
            doc_count += 1
            continue
        if other.search(norm) or "transitionguide" in folded:
            continue
        text = read_fn()
        lua_count += 1
        code = STRIP_RX.sub(" ", text)
        for match in CALL_RX.finditer(code):
            globals_.add(match.group(1))
        for match in DEF_RX.finditer(code):
            name = (match.group(1) or "") + (match.group(2) or "")
            if name:
                globals_.add(name)
        if DEPRECATED_RX.search(norm):
            file_name = norm.rsplit("/", 1)[-1]
            for line in re.split(r"\r?\n", text):
                match = FUNC_LINE.match(line) or ASSIGN_LINE.match(line)
                if match and match.group(1) not in deprecated:
                    deprecated[match.group(1)] = file_name
    globals_ -= KEYWORDS
    return {
        "functions": functions,
        "methods": _finalize_methods(methods),
        "events": events,
        "namespaces": namespaces,
        "deprecated": deprecated,
        "globals": globals_,
        "doc_count": doc_count,
        "lua_count": lua_count,
    }


def index_zip(zip_path, branch):
    with zipfile.ZipFile(zip_path) as zf:
        entries = [
            (info.filename, (lambda inf=info: _read_entry(zf, inf)))
            for info in zf.infolist()
            if info.filename.casefold().endswith(".lua")
        ]
        return _scan_lua_entries(entries, branch)


def index_local_dir(source_dir, branch):
    entries = []
    for dirpath, _dirs, filenames in os.walk(source_dir):
        for name in filenames:
            if not name.lower().endswith(".lua"):
                continue
            full = os.path.join(dirpath, name)
            rel = "/" + os.path.relpath(full, source_dir).replace("\\", "/")
            entries.append((rel, (lambda p=full: open(p, "r", encoding="utf-8-sig", errors="replace").read())))
    return _scan_lua_entries(entries, branch)


def write_index(result, out_dir, branch, sha):
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"api-{branch}.json")
    payload = {
        "source": f"https://github.com/{REPO}/tree/{sha}",
        "branch": branch,
        "commit": sha,
        "generated": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        "namespaces": sorted(result["namespaces"]),
        "functions": result["functions"],
        "methods": result.get("methods") or {},
        "events": result["events"],
        "deprecated": result["deprecated"],
        "globals": sorted(result["globals"]),
    }
    text = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    with open(out, "w", encoding="utf-8-sig", newline="") as handle:
        handle.write(text)
    return out


def _read_local_sha(source_dir):
    source_txt = os.path.join(source_dir, "SOURCE.txt")
    if os.path.isfile(source_txt):
        text = open(source_txt, "r", encoding="utf-8-sig", errors="replace").read()
        match = re.search(r"(?m)^commit:\s*([0-9a-f]{7,40})\b", text)
        if match:
            return match.group(1)
    return "local"


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Branch", "value", "forever"),
        ("OutDir", "value", None),
        ("FromLocal", "switch", False),
        ("SourceDir", "value", None),
    ])
    branch = args["Branch"]
    if branch not in BRANCHES:
        wowkit.die(f"Unknown branch '{branch}'. Use: {', '.join(BRANCHES)}")
    out_dir = args["OutDir"] or str(wowkit.KIT_ROOT / "data")
    if args["FromLocal"] or args["SourceDir"]:
        local_dir = args["SourceDir"] or str(wowkit.KIT_ROOT / "data" / "ui-source" / branch)
        if not os.path.isdir(local_dir):
            wowkit.die(f"Local UI source not found: {local_dir}. Run Update-WowUiSource.py -Branch {branch} first.")
        sha = _read_local_sha(local_dir)
        wowkit.host(f"Indexing local UI source '{branch}' @ {sha[:10]} ({local_dir})...")
        result = index_local_dir(local_dir, branch)
    else:
        wowkit.host(f"Resolving branch '{branch}' of {REPO}...")
        sha = json.loads(_get(f"https://api.github.com/repos/{REPO}/branches/{branch}"))["commit"]["sha"]
        zip_path = os.path.join(os.environ.get("TEMP") or ".", f"wow-ui-source-{sha[:12]}.zip")
        if not os.path.isfile(zip_path):
            wowkit.host(f"Downloading {branch} @ {sha[:10]} ...")
            data = _get(f"https://codeload.github.com/{REPO}/zip/{sha}")
            with open(zip_path, "wb") as handle:
                handle.write(data)
        result = index_zip(zip_path, branch)
    out = write_index(result, out_dir, branch, sha)
    secret_count = sum(1 for value in result["functions"].values() if value["secret"])
    method_count = len(result.get("methods") or {})
    wowkit.host(f"Wrote {out}  ({result['doc_count']} doc files, {result['lua_count']} Lua files scanned)")
    wowkit.host(
        f"  {len(result['functions'])} functions ({secret_count} can return secret values), "
        f"{method_count} widget methods, "
        f"{len(result['events'])} events, {len(result['namespaces'])} namespaces, "
        f"{len(result['deprecated'])} deprecated globals, {len(result['globals'])} globals used by Blizzard code"
    )
    raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
