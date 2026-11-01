"""Static checks for a WoW addon folder. Behavior matches Test-WowAddon.ps1."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import json
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit

TOC_SUFFIXES = (
    "Standard", "Mainline", "Classic", "Vanilla", "TBC", "BCC", "Wrath", "WOTLK",
    "Cata", "Mists", "Camelot", "Plunderstorm", "WoWLabs", "WoWHack",
)
KNOWN_DIRECTIVES = {
    "interface", "title", "notes", "author", "version", "savedvariables", "savedvariablespercharacter",
    "loadsavedvariablesfirst", "category", "group", "icontexture", "iconatlas", "allowloadgametype",
    "excludeloadgametype", "loadondemand", "dependencies", "dependancies", "requireddeps", "dep",
    "optionaldeps", "loadwith", "loadmanagers", "defaultstate", "onlybetaandptr", "addoncompartmentfunc",
    "addoncompartmentfunconenter", "addoncompartmentfunconleave", "savedvariablesmachine",
    "allowaddontableaccess", "usesecureenvironment",
}
RENAMED = {
    "UnitAura": "C_UnitAuras.GetAuraDataByIndex(unit, index, filter)",
    "UnitBuff": "C_UnitAuras.GetBuffDataByIndex(unit, index, filter)",
    "UnitDebuff": "C_UnitAuras.GetDebuffDataByIndex(unit, index, filter)",
}
LIB_RX = re.compile(r"^(libs?|Libraries)\\|\\(libs?|Libraries)\\", re.I)
SKIP_DIR_RX = re.compile(r"(^|\\)(\.git|\.vscode|tests?|spec)\\", re.I)
SECRET_OPS = re.compile(r"((?:==|~=)(?!\s*nil\b)|<=|>=|(?<![-=])[<>](?!=)|(?<![-\w])[+*/%^](?!=)|\.\.)", re.I)
TAINT_UI_CALL_RX = re.compile(
    r"(?<![\w.:])("
    r"CloseAllBags|OpenAllBags|ToggleAllBags|ToggleBag|OpenBag|CloseBag|"
    r"ToggleBackpack|OpenBackpack|CloseBackpack|"
    r"ShowUIPanel|HideUIPanel|ToggleUIPanel|ToggleFrame|"
    r"ToggleCharacter|ToggleSpellBook|ToggleTalentFrame|ToggleFriendsFrame|"
    r"SetItemButtonCount|SetItemButtonTexture|SetItemButtonQuality|SetItemButtonDesaturated|SetItemButtonStock"
    r")\s*\("
)
TAINT_UNREG_RX = re.compile(
    r"\b(ContainerFrame\w*|BankFrame|BankPanel|ChatFrame\d+)\s*:\s*(UnregisterAllEvents|UnregisterEvent)\s*\("
)
BUILTIN_GUARDS = {"issecretvalue", "canaccessvalue", "issecrettable", "hasanysecretvalues", "scrubsecretvalues"}
LOCAL_WARN_THRESHOLD = 175
HAND_UI = re.compile(
    r"\bCreateFrame\s*\([^)]*?['\"](DefaultPanelTemplate|ButtonFrameTemplate|BasicFrameTemplate\w*|PortraitFrameTemplate\w*|DialogBorder\w*Template|MinimalSliderWithSteppersTemplate|OptionsSliderTemplate|UICheckButtonTemplate|InterfaceOptionsCheckButtonTemplate)['\"]\s*[,)]",
    re.I,
)


def ps_search(text, pattern):
    return re.search(pattern, text, re.I) if text else None


def rel_of(addon_dir, full):
    text = full[len(addon_dir):].lstrip("\\/")
    return text.replace("/", "\\")


def read_text(path):
    with open(path, "r", encoding="utf-8-sig", errors="replace") as handle:
        return handle.read()


def get_code_lines(text):
    parts = []
    i = 0
    length = len(text)
    while i < length:
        char = text[i]
        if char == "-" and i + 1 < length and text[i + 1] == "-":
            window = text[i + 2:i + 2 + min(64, length - i - 2)]
            match = re.match(r"\[(=*)\[", window)
            if match:
                close = "]" + match.group(1) + "]"
                end = text.find(close, i + 2 + match.end())
                if end < 0:
                    end = length - len(close)
                chunk = text[i:end + len(close)]
                parts.append(re.sub(r"[^\n]", " ", chunk))
                i = end + len(close)
                continue
            while i < length and text[i] != "\n":
                parts.append(" ")
                i += 1
            continue
        if char == "[":
            window = text[i:i + min(64, length - i)]
            match = re.match(r"\[(=*)\[", window)
            if match:
                close = "]" + match.group(1) + "]"
                end = text.find(close, i + match.end())
                if end < 0:
                    end = length - len(close)
                inner = text[i + match.end():end]
                parts.append('""')
                parts.append(re.sub(r"[^\n]", "", inner))
                i = end + len(close)
                continue
        if char in "\"'":
            quote = char
            parts.append(quote)
            i += 1
            while i < length and text[i] != quote and text[i] != "\n":
                if text[i] == "\\":
                    i += 1
                i += 1
            parts.append(quote)
            i += 1
            continue
        parts.append(char)
        i += 1
    return "".join(parts).split("\n")


def strip_comments(text):
    text = re.sub(r"(?s)--\[(=*)\[.*?\]\1\]", "", text)
    return re.sub(r"--[^\n]*", "", text)


def list_lua(addon_dir):
    found = []
    for dirpath, _dirs, filenames in os.walk(addon_dir):
        for name in filenames:
            if not name.lower().endswith(".lua"):
                continue
            full = os.path.abspath(os.path.join(dirpath, name))
            rel = rel_of(addon_dir, full)
            if SKIP_DIR_RX.search(rel):
                continue
            found.append((full, rel, name))
    return found


def exact_case(addon_dir, full, file, line_no, listed, add):
    rel = rel_of(addon_dir, full)
    cur = addon_dir
    for part in rel.split("\\"):
        if not part:
            continue
        try:
            names = os.listdir(cur)
        except OSError:
            return
        hit = next((item for item in names if item.lower() == part.lower()), None)
        if hit is None:
            return
        if hit != part:
            add("warn", "file-case", file, line_no, f"'{listed}' differs in case from '{hit}' on disk (breaks on macOS).")
            return
        cur = os.path.join(cur, hit)


def check(path, flavors, no_luacheck=False):
    flavors = wowkit.resolve_flavors(flavors)
    if not os.path.isdir(path):
        wowkit.die(f"Not a folder: {path}")
    addon_dir = os.path.abspath(path)
    folder = os.path.basename(addon_dir)
    findings = []

    def add(severity, rule, file, line, message):
        findings.append({
            "Severity": severity,
            "Rule": rule,
            "File": file or "",
            "Line": int(line or 0),
            "Message": message,
        })

    installs = wowkit.wow_install()
    known = wowkit.KNOWN_FLAVORS
    branches = []
    for flavor in flavors:
        branch = known[flavor]["ApiBranch"]
        if branch not in branches:
            branches.append(branch)
    api = None
    api_branch = None
    for branch in branches:
        api = wowkit.api_index(branch)
        if api:
            api_branch = branch
            break
    if not api:
        add("info", "api-index", "", 0, f"No API index for '{','.join(branches)}'. Run scripts\\Update-WowApiIndex.py -Branch {branches[0]} to enable API/event/secret checks.")
    modern = any(flavor in ("forever", "retail") for flavor in flavors)

    tocs = []
    for name in os.listdir(addon_dir):
        full = os.path.join(addon_dir, name)
        if os.path.isfile(full) and name.lower().endswith(".toc"):
            tocs.append(full)
    valid = []
    for toc in tocs:
        base = os.path.splitext(os.path.basename(toc))[0]
        if base.lower() == folder.lower() or any(base.lower() == f"{folder}_{suffix}".lower() or base.lower() == f"{folder}-{suffix}".lower() for suffix in TOC_SUFFIXES):
            valid.append(toc)
    if not valid:
        add("error", "toc-name", "", 0, f"No TOC named '{folder}.toc' (or '{folder}_<Suffix>.toc'). WoW only loads a TOC whose name matches the folder.")
    valid_set = {os.path.normcase(item) for item in valid}
    for toc in tocs:
        if os.path.normcase(toc) not in valid_set:
            add("warn", "toc-name", os.path.basename(toc), 0, f"TOC name doesn't match folder '{folder}'; WoW will ignore it.")

    loaded = set()
    saved_vars = {}
    compartment_funcs = set()
    covered = set()
    xml_queue = []

    def listed_path(base, entry):
        return os.path.abspath(os.path.join(base, entry.strip().replace("/", "\\")))

    for toc in valid:
        base_name = os.path.splitext(os.path.basename(toc))[0]
        suffix = None
        if base_name.lower() != folder.lower():
            suffix = base_name[len(folder) + 1:]
        raw_lines = read_text(toc).splitlines()
        interfaces = []
        has_title = False
        icon = None
        has_version = False
        toc_name = os.path.basename(toc)
        for index, line in enumerate(raw_lines):
            number = index + 1
            if len(line) > 1024:
                add("error", "toc-line-length", toc_name, number, "Line is longer than 1024 characters; WoW reads only the first 1024.")
            directive = re.match(r"^\s*##\s*([^:]+?)\s*:\s*(.*)$", line)
            if directive:
                key = directive.group(1)
                val = directive.group(2).strip()
                base_key = key.split("-", 1)[0]
                if ps_search(key, r"^X-"):
                    continue
                if base_key.lower() == "interface":
                    interfaces.extend([part.strip() for part in val.split(",") if part.strip()])
                elif base_key.lower() == "title":
                    has_title = True
                elif base_key.lower() == "version":
                    has_version = bool(val)
                elif base_key.lower() in ("icontexture", "iconatlas"):
                    icon = val
                elif base_key.lower().startswith("savedvariables"):
                    for var in val.split(","):
                        if var.strip():
                            saved_vars[var.strip()] = toc_name
                elif base_key.lower().startswith("addoncompartmentfunc"):
                    if val:
                        compartment_funcs.add(val)
                elif base_key.lower() not in KNOWN_DIRECTIVES:
                    add("info", "toc-directive", toc_name, number, f"Unknown directive '## {key}' (custom metadata should start with X-).")
                continue
            if re.match(r"^\s*#", line) or not line.strip():
                continue
            allow = None
            exclude = []
            allow_m = ps_search(line, r"\[AllowLoadGameType\s+([^\]]+)\]")
            if allow_m:
                allow = [part.lower() for part in re.split(r"[,\s]+", allow_m.group(1)) if part]
            exclude_m = ps_search(line, r"\[ExcludeLoadGameType\s+([^\]]+)\]")
            if exclude_m:
                exclude = [part.lower() for part in re.split(r"[,\s]+", exclude_m.group(1)) if part]
            entry = re.sub(r"\[(AllowLoad\w*|ExcludeLoad\w*|Bootstrap)[^\]]*\]", "", line, flags=re.I).strip()
            if not entry:
                continue
            if ps_search(entry, r"\[TextLocale\]"):
                add("info", "toc-variable", toc_name, number, f"Skipped existence check for '{entry}' ([TextLocale] varies per client language).")
                continue
            checked = set()
            for flavor in flavors:
                info = known[flavor]
                types = [info["GameType"], info["Family"].lower()]
                if allow and not any(item in types for item in allow):
                    continue
                if any(item in types for item in exclude):
                    continue
                game_dir = "Standard" if flavor == "retail" else ("Camelot" if flavor == "forever" else info["TocSuffix"])
                expanded = entry.replace("[Family]", info["Family"]).replace("[Game]", game_dir)
                if expanded in checked:
                    continue
                checked.add(expanded)
                full = listed_path(addon_dir, expanded)
                for_whom = f" (for {flavor})" if expanded != entry or allow or exclude else ""
                if not os.path.isfile(full):
                    add("error", "toc-missing-file", toc_name, number, f"Listed file '{expanded}' does not exist{for_whom}.")
                    continue
                exact_case(addon_dir, full, toc_name, number, expanded, add)
                loaded.add(os.path.normcase(full))
                ext = os.path.splitext(full)[1].lower()
                if ext == ".xml":
                    xml_queue.append(full)
                elif ext != ".lua":
                    add("warn", "toc-file-type", toc_name, number, f"'{expanded}' is not .lua or .xml; WoW only loads those from a TOC.")
        if not has_title:
            add("warn", "toc-title", toc_name, 0, "No ## Title; the AddOns list will show the folder name.")
        if not has_version:
            add("warn", "toc-version", toc_name, 0, "No ## Version; the addon cannot report its version on load.")
        if not icon:
            add("warn", "toc-icon", toc_name, 0, "No ## IconTexture; the AddOns list and minimap addon menu show a blank icon. Pick an icon that fits the addon.")
        elif ps_search(icon, r"INV_Misc_QuestionMark"):
            add("warn", "toc-icon", toc_name, 0, "## IconTexture is still the template's question mark; pick an icon that fits the addon.")
        if not interfaces:
            add("error", "toc-interface", toc_name, 0, "Missing ## Interface; the addon will be flagged out of date on every client.")
            continue
        for value in interfaces:
            if not re.match(r"^\d{5,6}$", value):
                add("error", "toc-interface", toc_name, 0, f"Interface value '{value}' is not a number like 16001.")
        for flavor in flavors:
            want = known[flavor]["TocSuffix"]
            specific = any(re.search(rf"[_-]{re.escape(want)}$", os.path.splitext(os.path.basename(item))[0], re.I) for item in valid)
            reads = (suffix.lower() == want.lower() or (flavor == "retail" and suffix.lower() == "standard")) if suffix else (not specific)
            if not reads:
                continue
            target = wowkit.interface_for(flavor, installs)
            if str(target) in interfaces:
                covered.add(flavor)
            else:
                older = []
                for value in interfaces:
                    try:
                        number = int(value)
                    except ValueError:
                        continue
                    if number // 100 == int(target) // 100:
                        older.append(value)
                if older:
                    msg = f"lists {','.join(older)} but the current {flavor} client is {target}"
                else:
                    msg = f"doesn't list {target} ({flavor})"
                add("warn", "toc-interface", toc_name, 0, f"## Interface {msg}; WoW will show the addon as out of date.")
                covered.add(flavor)
    for flavor in flavors:
        if valid and flavor not in covered:
            target = wowkit.interface_for(flavor, installs)
            suffix = known[flavor]["TocSuffix"]
            add("warn", "toc-flavor", "", 0, f"No TOC is read by the {flavor} client (add '## Interface: {target}' or a {folder}_{suffix}.toc).")

    seen_xml = set()
    while xml_queue:
        xml_path = xml_queue.pop(0)
        key = os.path.normcase(xml_path)
        if key in seen_xml:
            continue
        seen_xml.add(key)
        rel = rel_of(addon_dir, xml_path)
        try:
            tree = ET.parse(xml_path)
        except ET.ParseError as exc:
            add("error", "xml-parse", rel, 0, f"Not well-formed XML: {exc}")
            continue
        for node in tree.iter():
            local = node.tag.split("}")[-1]
            if local not in ("Script", "Include"):
                continue
            attr = next((value for name, value in node.attrib.items() if name.lower() == "file"), None)
            if attr is None:
                continue
            full = listed_path(os.path.dirname(xml_path), attr)
            if not os.path.isfile(full):
                add("error", "xml-missing-file", rel, 0, f'<{local} file="{attr}"> does not exist.')
                continue
            loaded.add(os.path.normcase(full))
            if full.lower().endswith(".xml"):
                xml_queue.append(full)

    lua_files = list_lua(addon_dir)
    for full, rel, _name in lua_files:
        if os.path.normcase(full) not in loaded and not LIB_RX.search(rel):
            add("warn", "unloaded-file", rel, 0, "Not listed in any TOC or XML, so WoW never loads it.")

    defined = set()
    guard_names = set(BUILTIN_GUARDS)
    define_rx = re.compile(r"\bfunction\s+([A-Za-z_]\w*)\s*\(|(?<![\w.:])([A-Za-z_]\w*)\s*=(?!=)")
    guard_fn_rx = re.compile(
        r"function\s+(?:[A-Za-z_]\w*[.:])?([A-Za-z_]\w*)\s*\([^)]*\)([\s\S]{1,400}?)\bend\b"
    )
    for full, _rel, _name in lua_files:
        txt = read_text(full)
        for match in define_rx.finditer(txt):
            defined.add((match.group(1) or "") + (match.group(2) or ""))
        stripped = strip_comments(txt)
        for match in guard_fn_rx.finditer(stripped):
            if ps_search(match.group(2), r"\b(issecretvalue|canaccessvalue|issecrettable|hasanysecretvalues)\b"):
                guard_names.add(match.group(1))
    guard_line_rx = re.compile(r"\b(" + "|".join(re.escape(g) for g in sorted(guard_names)) + r")\s*\(")
    has_deps = False
    for toc in valid:
        if ps_search(read_text(toc), r"(?m)^##\s*(Dependencies|RequiredDeps|OptionalDeps|Dep)\s*:"):
            has_deps = True
            break

    kit_dialog = "EditModeDialog.lua"
    kit_dialog_path = os.path.join(wowkit.KIT_ROOT, "templates", "editmode", kit_dialog)
    edit_file = None
    edit_click = False
    own_drag = None
    uses_snap = False
    for full, rel, name in lua_files:
        if name.lower() == kit_dialog.lower() or LIB_RX.search(rel):
            continue
        code = strip_comments(read_text(full))
        if edit_file is None and (ps_search(code, r"['\"]EditMode\.(Enter|Exit)['\"]") or ps_search(code, r"\bEditMode\.(Attach|CreateSelection|CreateDialog)\b")):
            edit_file = (full, rel, name)
        if ps_search(code, r"SetScript\s*\(\s*['\"]On(MouseUp|MouseDown|Click)['\"]"):
            edit_click = True
        if own_drag is None and ps_search(code, r"SetScript\s*\(\s*['\"]OnDragStart['\"]"):
            own_drag = (full, rel)
        if ps_search(code, r"\bEditMode\.(SnapRect|Attach)\b"):
            uses_snap = True

    all_text = []
    slash_defs = {}
    slash_handlers = set()
    uses_addon_msg = None
    uses_lockdown = False
    methods_meta = (api.get("Methods") or {}) if api else {}
    fn_meta = (api.get("FunctionMeta") or {}) if api else {}
    for full, rel, name in lua_files:
        if LIB_RX.search(rel):
            continue
        is_kit_copy = name.lower() == kit_dialog.lower()
        raw = read_text(full)
        all_text.append(raw)
        raw_lines = raw.split("\n")
        code_lines = get_code_lines(raw)
        file_text = "\n".join(code_lines)
        locals_ = set()
        for match in re.finditer(r"\blocal\s+(?:function\s+)?([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_][\w]*)*)", file_text):
            for item in re.split(r"\s*,\s*", match.group(1)):
                if item:
                    locals_.add(item)

        attached_frames = {}
        dialog_vars = {}
        onupdate_frames = {}
        dialog_setpoints = {}
        secret_locals = {}
        local_scopes = [[0]]
        warned_local_scopes = set()
        brace_depth = 0

        for index, code in enumerate(code_lines):
            raw_line = raw_lines[index] if index < len(raw_lines) else ""
            number = index + 1
            if not code.strip():
                continue
            brace_before = brace_depth
            brace_depth = max(0, brace_depth + code.count("{") - code.count("}"))

            # Track function/block scopes for 1-hop secret locals and Lua's 200-local limit.
            fn_opens = len(re.findall(r"\bfunction\b", code))
            block_opens = len(re.findall(r"\b(do|then|repeat)\b", code))
            closes = len(re.findall(r"\b(end|until)\b", code))
            if fn_opens:
                secret_locals.clear()
                for _ in range(fn_opens):
                    local_scopes.append([0])
            for _ in range(block_opens):
                local_scopes[-1].append(0)
            local_decl = re.match(r"^\s*local\s+(?:function\s+([A-Za-z_]\w*)|([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*))", code)
            if local_decl:
                added = 1 if local_decl.group(1) else len([x for x in re.split(r"\s*,\s*", local_decl.group(2)) if x])
                local_scopes[-1][-1] += added
                active_locals = sum(local_scopes[-1])
                scope_id = len(local_scopes)
                if active_locals >= LOCAL_WARN_THRESHOLD and scope_id not in warned_local_scopes and not is_kit_copy:
                    warned_local_scopes.add(scope_id)
                    where_scope = "file chunk" if scope_id == 1 else "function"
                    add("warn", "local-limit", rel, number, f"Active locals in {where_scope} reached {active_locals} (Lua's hard limit is 200 per function/chunk; move locals into a table or split files).")
            for _ in range(closes):
                if len(local_scopes[-1]) > 1:
                    local_scopes[-1].pop()
                elif len(local_scopes) > 1:
                    local_scopes.pop()
                    secret_locals.clear()

            line_has_guard = bool(guard_line_rx.search(code))
            secret_ok = bool(ps_search(raw_line, r"--\s*secret-value:\s*ok"))

            # Check existing 1-hop secret locals before clearing if guarded on this line.
            if secret_locals and modern and not is_kit_copy:
                for svar, (sfn, sflags) in list(secret_locals.items()):
                    if not re.search(r"\b" + re.escape(svar) + r"\b", code):
                        continue
                    g_match = re.search(
                        r"\b(?:" + "|".join(re.escape(g) for g in sorted(guard_names)) + r")\s*\([^)]*\b" + re.escape(svar) + r"\b",
                        code,
                    )
                    rhs_op = re.search(r"\b" + re.escape(svar) + r"\s*(?:(?:==|~=)(?!\s*nil\b)|<=|>=|(?<![-=])[<>](?!=)|\.\.|[+*/%^]|-(?![->=]))", code)
                    lhs_op = None
                    for cand_m in re.finditer(r"(==|~=|<=|>=|(?<![-=])[<>](?!=)|\.\.|[+*/%^])\s*" + re.escape(svar) + r"\b", code):
                        prefix = code[:cand_m.start()].rstrip()
                        if cand_m.group(1) in ("==", "~=") and re.search(r"\bnil$", prefix):
                            continue
                        lhs_op = cand_m
                        break
                    idx_op = re.search(r"[\w)\]]\s*\[\s*" + re.escape(svar) + r"\s*\]", code)
                    candidates = [m for m in (rhs_op, lhs_op, idx_op) if m]
                    op_match = min(candidates, key=lambda m: m.start()) if candidates else None
                    if g_match and (not op_match or g_match.start() < op_match.start()):
                        secret_locals.pop(svar, None)
                        continue
                    if op_match and not secret_ok:
                        add("warn", "secret-value", rel, number, f"Local '{svar}' holds {sfn}() ({', '.join(sflags)}), which can be a secret value; comparing, indexing, doing math or concatenating it before issecretvalue({svar}) errors in restricted contexts.")
                        secret_locals.pop(svar, None)
                        continue
                    if re.search(r"(?<![\w.])" + re.escape(svar) + r"\s*=(?!=)", code) and not re.match(r"^\s*local\s+" + re.escape(svar) + r"\s*=", code):
                        secret_locals.pop(svar, None)

            for match in re.finditer(r":Register(?:Unit)?Event\s*\(\s*['\"]([A-Z0-9_]+)['\"]", raw_line):
                event = match.group(1)
                if modern and ps_search(event, r"^COMBAT_LOG_EVENT(_UNFILTERED)?$"):
                    add("error", "cleu-removed", rel, number, f"{event} errors when registered on Midnight (12.x) and WoW: Forever. Combat-log parsing isn't available to addons there (Patch 12.0.0 API changes).")
                elif api and event not in api["Events"]:
                    add("error", "unknown-event", rel, number, f"Event '{event}' does not exist on {api_branch} (RegisterEvent will error).")
                elif api and api["Events"].get(event):
                    add("info", "secret-payload", rel, number, f"Event '{event}' can deliver secret values in its payload; don't compare or do math on them.")
            if api:
                for match in re.finditer(r"(?<![\w.:])(C_\w+)\.(\w+)", code):
                    ns, fn = match.group(1), match.group(1) + "." + match.group(2)
                    guarded = bool(
                        ps_search(code, r"\b" + re.escape(ns) + r"\s+and\s+" + re.escape(fn))
                        or ps_search(code, r"\b" + re.escape(fn) + r"\s+(and|or)\b")
                        or ps_search(code, r"\bor\s+" + re.escape(fn))
                    )
                    note = " (feature-detected, OK)" if guarded else ""
                    if ns not in api["Namespaces"]:
                        add("info" if guarded else "error", "unknown-namespace", rel, number, f"{ns} does not exist on {api_branch}{note}.")
                    elif fn not in api["Functions"]:
                        tail = " (feature-detected, OK)" if guarded else "; it will be nil if it does not exist"
                        add("info" if guarded else "warn", "unknown-function", rel, number, f"{fn} is not in Blizzard's API documentation for {api_branch}{tail}.")
                    else:
                        secret = api["Functions"][fn]
                        if secret and modern and not secret_ok:
                            after = code[match.start():]
                            close = after.find(")")
                            tail = after[close + 1:] if close >= 0 else after
                            before = code[:match.start()]
                            if re.search(r"^\s*" + SECRET_OPS.pattern, tail) or ps_search(before, r"(?:(?<!\bnil\s)(?<!\bnil)(?:==|~=)|<=|>=|[<>]|\.\.)\s*$"):
                                add("info" if line_has_guard else "warn", "secret-value", rel, number, f"{fn} can return secret values ({', '.join(secret)}); comparing, doing math or concatenating them errors in restricted contexts. Pass them straight to widget setters or check issecretvalue() first.")
                for match in re.finditer(r"(?<![\w.:])([A-Z][A-Za-z0-9_]+)\s*\(", code):
                    called = match.group(1)
                    if called in locals_ or ps_search(code, r"function\s+" + re.escape(called) + r"\s*\("):
                        continue
                    fallback = bool(
                        ps_search(code, r"\bor\s+" + re.escape(called) + r"\b")
                        or ps_search(code, r"\b" + re.escape(called) + r"\s+or\b")
                        or ps_search(file_text, r"\b(if|elseif|and|or|not)\s+" + re.escape(called) + r"\b(?!\s*\()")
                        or ps_search(file_text, r"\b" + re.escape(called) + r"\s+(and|then)\b")
                    )
                    if called in api["Deprecated"]:
                        add("warn", "deprecated-api", rel, number, f"{called} is only provided by Blizzard's deprecation shim ({api['Deprecated'][called]}) and is scheduled for removal.")
                    elif called not in api["Functions"] and called not in api["Globals"] and called in api["ByShort"]:
                        alts = " / ".join(f"{item}()" for item in api["ByShort"][called][:3])
                        extra = " (fallback present, OK)" if fallback else ""
                        add("info" if fallback else "warn", "moved-api", rel, number, f"Global {called}() doesn't exist on {api_branch}; use {alts}{extra}.")
                    elif called not in api["Functions"] and called not in api["Globals"] and called not in defined:
                        if called in RENAMED:
                            hint = f" Use {RENAMED[called]}."
                        elif has_deps:
                            hint = " (Unless a dependency provides it.)"
                        else:
                            hint = ""
                        extra = " Feature-detected, OK." if fallback else ""
                        add("info" if fallback else "warn", "unknown-global", rel, number, f"Global {called}() is not part of the {api_branch} client (not in Blizzard's API docs or UI code); it will be nil.{hint}{extra}")
                    elif modern and called in api["Functions"] and api["Functions"][called] and not secret_ok:
                        after = code[match.start():]
                        close = after.find(")")
                        tail = after[close + 1:] if close >= 0 else ""
                        before = code[:match.start()]
                        if re.search(r"^\s*" + SECRET_OPS.pattern, tail) or ps_search(before, r"(?:(?<!\bnil\s)(?<!\bnil)(?:==|~=)|<=|>=|[<>]|[+\-*/]|\.\.)\s*$"):
                            flags = ", ".join(api["Functions"][called])
                            add("info" if line_has_guard else "warn", "secret-value", rel, number, f"{called}() can return a secret value ({flags}); comparing, doing math or concatenating it errors in restricted contexts. Pass it straight to a widget setter (StatusBar:SetValue, FontString:SetText) or check issecretvalue() first.")

                # Record new 1-hop local assignments from secret-returning APIs.
                if modern and not is_kit_copy and not secret_ok and not line_has_guard:
                    assign_m = re.match(r"^\s*local\s+([A-Za-z_]\w*)\s*=\s*(C_\w+\.\w+|[A-Z][A-Za-z0-9_]+)\s*\([^)]*\)\s*$", code)
                    if assign_m:
                        lhs, rhs_fn = assign_m.group(1), assign_m.group(2)
                        if rhs_fn not in locals_ and rhs_fn in api["Functions"] and api["Functions"][rhs_fn]:
                            secret_locals[lhs] = (rhs_fn, api["Functions"][rhs_fn])

                # Check widget methods & API calls that reject tainted secret arguments (SecretArguments = AllowedWhenUntainted / NotAllowed).
                if modern and not is_kit_copy and not ps_search(raw_line, r"--\s*secret-args:\s*ok"):
                    for mm in re.finditer(r":([A-Za-z_]\w*)\s*\(([^)]*)\)", code):
                        mname, marg = mm.group(1), mm.group(2).strip()
                        if not marg:
                            continue
                        mmeta = methods_meta.get(mname)
                        if not mmeta:
                            continue
                        sargs = mmeta.get("secretArgs") or []
                        if sargs and "AllowedWhenTainted" not in sargs and ("AllowedWhenUntainted" in sargs or "NotAllowed" in sargs):
                            bad_src = None
                            for fm in re.finditer(r"(?<![\w.:])(C_\w+\.\w+|[A-Z][A-Za-z0-9_]+)\s*\(", marg):
                                cand = fm.group(1)
                                if cand not in locals_ and cand in api["Functions"] and api["Functions"][cand]:
                                    bad_src = f"{cand}()"
                                    break
                            if not bad_src and secret_locals:
                                for svar, (sfn, _sf) in secret_locals.items():
                                    if re.search(r"\b" + re.escape(svar) + r"\b", marg):
                                        bad_src = f"'{svar}' ({sfn}())"
                                        break
                            if bad_src:
                                add("warn", "secret-args", rel, number, f":{mname}() has SecretArguments = {'|'.join(sargs)} and rejects secret value {bad_src} when called from addon code.")
                    for cm in re.finditer(r"(?<![\w.:])(C_\w+\.\w+|[A-Z][A-Za-z0-9_]+)\s*\(([^)]*)\)", code):
                        cname, carg = cm.group(1), cm.group(2).strip()
                        if not carg or cname in locals_:
                            continue
                        cmeta = fn_meta.get(cname)
                        if not cmeta:
                            continue
                        csarg = cmeta.get("secretArgs")
                        if csarg in ("AllowedWhenUntainted", "NotAllowed"):
                            bad_src = None
                            for fm in re.finditer(r"(?<![\w.:])(C_\w+\.\w+|[A-Z][A-Za-z0-9_]+)\s*\(", carg):
                                cand = fm.group(1)
                                if cand not in locals_ and cand in api["Functions"] and api["Functions"][cand]:
                                    bad_src = f"{cand}()"
                                    break
                            if not bad_src and secret_locals:
                                for svar, (sfn, _sf) in secret_locals.items():
                                    if re.search(r"\b" + re.escape(svar) + r"\b", carg):
                                        bad_src = f"'{svar}' ({sfn}())"
                                        break
                            if bad_src:
                                add("warn", "secret-args", rel, number, f"{cname}() has SecretArguments = {csarg} and rejects secret value {bad_src} when called from addon code.")

                # Taint checks: overwriting Blizzard globals instead of hooksecurefunc.
                if brace_before == 0 and not is_kit_copy and not ps_search(raw_line, r"--\s*taint-hook:\s*ok"):
                    hook_m = re.match(r"^\s*(?:function\s+([A-Z][A-Za-z0-9_]*)\s*\(|([A-Z][A-Za-z0-9_]*)\s*=(?!=))", code)
                    if hook_m:
                        gname = (hook_m.group(1) or "") + (hook_m.group(2) or "")
                        if (
                            gname
                            and gname not in locals_
                            and gname not in saved_vars
                            and gname not in compartment_funcs
                            and not gname.startswith(("SLASH_", "BINDING_"))
                            and gname != "SlashCmdList"
                            and (gname in api["Functions"] or gname in api["Globals"])
                        ):
                            add("warn", "taint-hook", rel, number, f"Overwriting Blizzard global '{gname}' taints every secure caller that reads it; observe with hooksecurefunc(\"{gname}\", ...) instead.")

            if not is_kit_copy:
                if not ps_search(raw_line, r"--\s*taint-call:\s*ok"):
                    for tm in TAINT_UI_CALL_RX.finditer(code):
                        tcall = tm.group(1)
                        if tcall not in locals_:
                            add("warn", "taint-call", rel, number, f"Calling Blizzard UI function '{tcall}()' directly from addon code taints Blizzard frame state and can block protected actions later; use hooksecurefunc to observe or a SecureActionButtonTemplate outside combat (or mark '-- taint-call: ok' if intentional).")
                    if ps_search(code, r":SetCooldownFromDurationObject\s*\("):
                        add("warn", "taint-call", rel, number, "Cooldown:SetCooldownFromDurationObject is a protected function (AllowedWhenUntainted); use C_DurationUtil.CreateDurationTextBinding() instead.")
                if not ps_search(raw_line, r"--\s*taint-unregister:\s*ok"):
                    um = TAINT_UNREG_RX.search(code)
                    if um:
                        add("warn", "taint-unregister", rel, number, f"Calling :{um.group(2)}() on Blizzard frame '{um.group(1)}' taints Blizzard's event bookkeeping (e.g. bank/bag/chat state); park frames on a hidden parent and leave their events alone.")

            for match in re.finditer(r"\bSLASH_([A-Za-z0-9_]+?)\d+\s*=", code):
                slash_defs.setdefault(match.group(1), f"{rel}:{number}")
            for match in re.finditer(r"SlashCmdList\s*(?:\[\s*['\"]([A-Za-z0-9_]+)['\"]\s*\]|\.([A-Za-z0-9_]+))\s*=", raw_line):
                slash_handlers.add((match.group(1) or "") + (match.group(2) or ""))
            if edit_file and not is_kit_copy and ps_search(code, r"\bCreateFrame\s*\("):
                built = HAND_UI.search(raw_line)
                if built and not ps_search(raw_line, r"--\s*editmode-ui:\s*ok"):
                    add("error", "editmode-ui", rel, number, f"Hand-built {built.group(1)} in an addon that joins Edit Mode. Build its settings with ns.EditMode.CreateDialog (EditModeDialog.lua) so every addon's Edit Mode settings look and behave the same. For a window that isn't Edit Mode settings, end the line with '-- editmode-ui: ok'.")
            if edit_file and not is_kit_copy and ps_search(code, r"\bgridSpacing\b|:IsSnapEnabled\s*\(|\bEditModeMagnetismManager\b"):
                add("error", "editmode-snap", rel, number, "Hand-rolled Edit Mode snapping. Snap with ns.EditMode.SnapRect / SnapEdge (or ns.EditMode.Attach), so every frame snaps the way Blizzard's do: magnetic within 8 px to the grid, screen edges and centre, and nearby Edit Mode frames.")
            if not is_kit_copy:
                att_m = re.search(r"\bEditMode\.Attach\s*\(\s*([A-Za-z_][\w.]*)\s*,", code)
                if att_m:
                    attached_frames.setdefault(att_m.group(1), number)
                ou_m = re.search(r"\b([A-Za-z_][\w.]*)\s*:\s*SetScript\s*\(\s*['\"]OnUpdate['\"]", raw_line)
                if ou_m and not ps_search(raw_line, r"--\s*editmode-onupdate:\s*ok"):
                    onupdate_frames.setdefault(ou_m.group(1), number)
                dlg_m = re.search(r"\b([A-Za-z_][\w.]*)\s*=\s*[\w.]*EditMode\.CreateDialog\s*\(", code)
                if dlg_m:
                    dialog_vars.setdefault(dlg_m.group(1), number)
                sp_m = re.search(r"\b([A-Za-z_][\w.]*)\s*:\s*SetPoint\s*\(", code)
                if sp_m and not ps_search(raw_line, r"--\s*editmode-openfor:\s*ok"):
                    dialog_setpoints.setdefault(sp_m.group(1), number)
            if ps_search(code, r"\bSendAddonMessage(Logged)?\s*\(") and not uses_addon_msg:
                uses_addon_msg = f"{rel}:{number}"
            if ps_search(code, r"InChatMessagingLockdown"):
                uses_lockdown = True

        for fvar, ou_line in onupdate_frames.items():
            if fvar in attached_frames:
                add("warn", "editmode-onupdate", rel, ou_line, f"'{fvar}' has SetScript(\"OnUpdate\") and is also passed to EditMode.Attach (line {attached_frames[fvar]}), which overwrites OnUpdate while dragging. Run animations/watchers on a separate child frame.")
        for dvar, sp_line in dialog_setpoints.items():
            if dvar in dialog_vars:
                add("warn", "editmode-openfor", rel, sp_line, f"Edit Mode dialog '{dvar}' is anchored with :SetPoint(); open and position it via {dvar}:OpenFor(frame) so it stays clear of the frame and other dialogs.")

    for key, where in slash_defs.items():
        if key not in slash_handlers:
            file, line = re.split(r":(?=\d+$)", where)
            add("error", "slash-handler", file, int(line), f'SLASH_{key}1 is defined but SlashCmdList["{key}"] is never assigned; the command won\'t work.')
    if uses_addon_msg and modern and not uses_lockdown:
        file, line = re.split(r":(?=\d+$)", uses_addon_msg)
        add("info", "addon-comms", file, int(line), "Addon messages are restricted in instances on 12.x/Forever; check C_ChatInfo.InChatMessagingLockdown() before sending.")
    lua_all = "\n".join(all_text)
    if lua_all and not (ps_search(lua_all, r"GetAddOnMetadata") and ps_search(lua_all, r'"Version"')):
        add("warn", "load-version", "", 0, "The addon never reads its ## Version. Print it on PLAYER_LOGIN (see the template Core.lua) so every /reload shows which version is running.")
    if edit_file:
        copy = next((item for item in lua_files if item[2].lower() == kit_dialog.lower()), None)
        if copy is None:
            has_settings = edit_click or any(item["Rule"] == "editmode-ui" for item in findings)
            add("error" if has_settings else "warn", "editmode-dialog", edit_file[1], 0, f"Joins Edit Mode but has no {kit_dialog}. Copy the kit's templates\\editmode\\{kit_dialog} into the addon, list it in the TOC right after Core.lua, and build the frame's selection, snapping and settings with ns.EditMode (CreateSelection, SnapRect, CreateDialog).")
        if own_drag and not uses_snap:
            add("warn", "editmode-snap", own_drag[1], 0, "Drags a frame without the kit's snapping. Use ns.EditMode.Attach (or call ns.EditMode.SnapRect from the drag's OnUpdate), so it snaps like Blizzard's frames: magnetic within 8 px to the grid, screen edges and centre, and nearby Edit Mode frames.")
    copy = next((item for item in lua_files if item[2].lower() == kit_dialog.lower()), None)
    if copy and os.path.isfile(kit_dialog_path):
        left = read_text(copy[0]).replace("\r\n", "\n")
        right = read_text(kit_dialog_path).replace("\r\n", "\n")
        if left != right:
            add("warn", "editmode-dialog", copy[1], 0, f"Differs from the kit's templates\\editmode\\{kit_dialog}. Don't edit the copy: change the kit file and copy it into every addon, so all Edit Mode settings stay identical.")
    for var, toc_name in saved_vars.items():
        if not ps_search(lua_all, r"\b" + re.escape(var) + r"\b"):
            add("warn", "savedvariables-unused", toc_name, 0, f"SavedVariables '{var}' is declared but never referenced in Lua.")

    luacheck = None if no_luacheck else wowkit.find_luacheck()
    if luacheck:
        config = os.path.join(addon_dir, ".luacheckrc")
        if not os.path.isfile(config):
            config = os.path.join(wowkit.KIT_ROOT, "templates", "addon", ".luacheckrc")
        targets = [full for full, rel, _name in lua_files if not LIB_RX.search(rel)]
        if targets:
            args = [luacheck, "--formatter", "plain", "--codes", "--no-color", "--config", config] + targets
            if saved_vars:
                args += ["--globals"] + list(saved_vars)
            proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, errors="replace")
            for line in (proc.stdout or "").splitlines():
                match = re.match(r"^(.*?):(\d+):(\d+):\s*\((\w)(\d+)\)\s*(.*)$", line)
                if not match:
                    continue
                severity = "error" if match.group(4) == "E" else "warn"
                file = match.group(1)
                if os.path.normcase(file).startswith(os.path.normcase(addon_dir)):
                    file = rel_of(addon_dir, file)
                add(severity, f"luacheck-{match.group(4)}{match.group(5)}", file, int(match.group(2)), match.group(6))
    elif not no_luacheck:
        add("info", "luacheck", "", 0, "luacheck not found: syntax and accidental-global checks skipped. Run scripts\\Install-WowDevTools.py.")

    order = {"error": 0, "warn": 1, "info": 2}
    findings.sort(key=lambda item: (order[item["Severity"]], item["File"].casefold(), item["Line"]))
    errors = sum(1 for item in findings if item["Severity"] == "error")
    warns = sum(1 for item in findings if item["Severity"] == "warn")
    return {
        "Addon": folder,
        "Flavors": flavors,
        "ApiCommit": api["Commit"] if api else None,
        "Errors": errors,
        "Warnings": warns,
        "Findings": findings,
        "ApiBranch": api_branch,
    }


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Path", "value", None),
        ("Flavor", "list", []),
        ("NoLuacheck", "switch", False),
        ("NoInfo", "switch", False),
        ("Json", "switch", False),
    ])
    if not args["Path"]:
        wowkit.die("Missing value for -Path")
    try:
        result = check(args["Path"], args["Flavor"], args["NoLuacheck"])
    except ValueError as exc:
        wowkit.die(str(exc))
    shown_findings = [f for f in result["Findings"] if f["Severity"] != "info"] if args["NoInfo"] else result["Findings"]
    if args["Json"]:
        out = {k: result[k] for k in ("Addon", "Flavors", "ApiCommit", "Errors", "Warnings")}
        out["Findings"] = shown_findings
        print(json.dumps(out, indent=2))
    else:
        branch = ""
        if result["ApiCommit"]:
            branch = f" (API: {result['ApiBranch']} @ {result['ApiCommit'][:10]})"
        wowkit.host(f"Checking {result['Addon']} for {', '.join(result['Flavors'])}{branch}")
        for item in shown_findings:
            loc = item["File"] if item["File"] else result["Addon"]
            if item["File"] and item["Line"]:
                loc = f"{item['File']}:{item['Line']}"
            wowkit.host(f"  {item['Severity'].upper():<5} {loc}  [{item['Rule']}] {item['Message']}")
        notes = len(result["Findings"]) - result["Errors"] - result["Warnings"]
        wowkit.host(f"{result['Errors']} error(s), {result['Warnings']} warning(s), {notes} note(s)")
    raise SystemExit(1 if result["Errors"] else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
