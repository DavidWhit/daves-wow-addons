"""Read Lua errors recorded by !WowKitErrors. Matches Get-WowScriptErrors.ps1."""

from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit


class LuaData:
    """The same Lua-literal reader as WowKit.LuaData. Nothing is executed."""

    @staticmethod
    def parse_assigned(text, name):
        at = text.find(name + " =")
        if at < 0:
            return None
        pos = text.find("=", at) + 1
        value, _pos = LuaData._value(text, pos)
        return value

    @staticmethod
    def _skip(text, pos):
        length = len(text)
        while pos < length:
            char = text[pos]
            if char.isspace():
                pos += 1
                continue
            if char == "-" and pos + 1 < length and text[pos + 1] == "-":
                while pos < length and text[pos] != "\n":
                    pos += 1
                continue
            break
        return pos

    @staticmethod
    def _value(text, pos):
        pos = LuaData._skip(text, pos)
        char = text[pos]
        if char == "{":
            return LuaData._table(text, pos)
        if char in "\"'":
            return LuaData._str(text, pos)
        if char == "-" or char == "." or char.isdigit():
            end = pos
            if text[end] == "-":
                end += 1
            while end < len(text) and (
                text[end].isdigit()
                or text[end] == "."
                or text[end] in "eE"
                or (text[end] in "-+" and text[end - 1] in "eE")
            ):
                end += 1
            number = float(text[pos:end])
            if number == int(number) and abs(number) < 9e15:
                return int(number), end
            return number, end
        if text.startswith("true", pos):
            return True, pos + 4
        if text.startswith("false", pos):
            return False, pos + 5
        if text.startswith("nil", pos):
            return None, pos + 3
        raise ValueError(f"unexpected '{char}' at {pos}")

    @staticmethod
    def _table(text, pos):
        table = {}
        pos += 1
        index = 1
        while True:
            pos = LuaData._skip(text, pos)
            if text[pos] == "}":
                return table, pos + 1
            key = None
            if text[pos] == "[":
                pos += 1
                key, pos = LuaData._value(text, pos)
                pos = LuaData._skip(text, pos)
                pos += 1
                pos = LuaData._skip(text, pos)
                pos += 1
            elif text[pos].isalpha() or text[pos] == "_":
                end = pos
                while end < len(text) and (text[end].isalnum() or text[end] == "_"):
                    end += 1
                look = LuaData._skip(text, end)
                if look < len(text) and text[look] == "=" and (look + 1 >= len(text) or text[look + 1] != "="):
                    key = text[pos:end]
                    pos = look + 1
            value, pos = LuaData._value(text, pos)
            if key is None:
                key = index
                index += 1
            if value is not None:
                table[key] = value
            pos = LuaData._skip(text, pos)
            if pos < len(text) and text[pos] in ",;":
                pos += 1

    @staticmethod
    def _str(text, pos):
        quote = text[pos]
        pos += 1
        chars = []
        while True:
            char = text[pos]
            pos += 1
            if char == quote:
                return "".join(chars), pos
            if char != "\\":
                chars.append(char)
                continue
            escaped = text[pos]
            pos += 1
            if escaped == "n":
                chars.append("\n")
            elif escaped == "t":
                chars.append("\t")
            elif escaped == "r":
                pass
            elif escaped == "\n":
                chars.append("\n")
            elif escaped.isdigit():
                value = ord(escaped) - ord("0")
                count = 1
                while count < 3 and pos < len(text) and text[pos].isdigit():
                    value = value * 10 + (ord(text[pos]) - ord("0"))
                    pos += 1
                    count += 1
                chars.append(chr(value))
            else:
                chars.append(escaped)


def _text(value):
    return "" if value is None else str(value)


def _whole(value):
    if isinstance(value, bool) or value is None:
        return 0
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value == int(value):
        return int(value)
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _sort_key(key):
    if isinstance(key, bool):
        return (1, str(key))
    if isinstance(key, int):
        return (0, key)
    if isinstance(key, float):
        return (0, key)
    return (1, str(key))


def _stamp(path):
    import datetime
    return datetime.datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d %H:%M")


def _saved_files(client_dir, explicit):
    if explicit:
        if not os.path.isfile(explicit):
            wowkit.die(f"Cannot find path '{explicit}' because it does not exist.")
        return [os.path.abspath(explicit)]
    account = os.path.join(client_dir, "WTF", "Account")
    found = []
    if os.path.isdir(account):
        for dirpath, _dirs, filenames in os.walk(account):
            if not dirpath.lower().endswith("savedvariables"):
                continue
            for name in filenames:
                if name.lower() == "!wowkiterrors.lua":
                    found.append(os.path.join(dirpath, name))
    found.sort(key=lambda path: os.path.getmtime(path), reverse=True)
    return found


def _log_hits(client_dir, addon):
    logs = os.path.join(client_dir, "Logs")
    hits = []
    if not os.path.isdir(logs):
        return hits
    try:
        names = os.listdir(logs)
    except OSError:
        return hits
    for name in names:
        if not name.lower().endswith(".log"):
            continue
        path = os.path.join(logs, name)
        try:
            lines = open(path, "r", encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            continue
        for number, line in enumerate(lines, start=1):
            if "lua error" in line.casefold():
                if addon and not re.search(re.escape(addon), line, re.I):
                    continue
                hits.append((name, number, line.strip()))
    return hits


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Flavor", "value", "forever"),
        ("Addon", "value", None),
        ("Last", "value", "15"),
        ("Session", "value", "-1"),
        ("Root", "value", None),
        ("File", "value", None),
    ])
    root = args["Root"] or wowkit.wow_root()
    if not root:
        wowkit.warn('World of Warcraft was not found. Pass -Root "D:\\Games\\World of Warcraft".')
        raise SystemExit(1)
    clients = [item for item in wowkit.wow_install(root) if item.Flavor == args["Flavor"]]
    if not clients:
        wowkit.warn(f"No '{args['Flavor']}' client installed under {root}.")
        raise SystemExit(1)
    client = clients[0]
    client_dir = os.path.join(root, client.Folder)
    dev_addon = os.path.join(wowkit.KIT_ROOT, "devaddons", "!WowKitErrors")
    dev_toc = os.path.join(client_dir, "Interface", "AddOns", "!WowKitErrors", "!WowKitErrors.toc")
    if not args["File"] and not os.path.isfile(dev_toc):
        wowkit.host("The kit's error recorder (!WowKitErrors) was not installed in this client. Linking it now:")
        link = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Link-WowAddons.py")
        proc = __import__("subprocess").run(
            [sys.executable, link, "-Path", dev_addon, "-Flavor", args["Flavor"], "-Root", root],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            wowkit.host("  " + ((proc.stderr or proc.stdout or "").strip()))
        if os.path.isfile(dev_toc):
            wowkit.host(f"  linked into {client.Folder}\\Interface\\AddOns\\!WowKitErrors")
            wowkit.host("  Fully restart the client (a new addon), reproduce the problem, then /reload so it is written.")
        else:
            wowkit.host("  the link failed. Run it by hand to see why:")
            script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Link-WowAddons.py")
            wowkit.host(f'  py -3 "{script}" -Path "{dev_addon}" -Flavor {args["Flavor"]}')

    files = _saved_files(client_dir, args["File"])
    if not files:
        wowkit.host("No recorded script errors yet.")
        wowkit.host("In game: make sure WowKit Error Log is enabled in the AddOns list, reproduce the problem, then /reload (or log out) so its file is written.")
    else:
        sv_file = files[0]
        wowkit.host(f"Script errors: {sv_file} (written {_stamp(sv_file)})")
        db = LuaData.parse_assigned(open(sv_file, "r", encoding="utf-8-sig", errors="replace").read(), "WowKitErrorsDB")
        entries = []
        if isinstance(db, dict) and "entries" in db and isinstance(db["entries"], dict):
            for key in sorted(db["entries"], key=_sort_key):
                item = db["entries"][key]
                if not isinstance(item, dict):
                    continue
                entries.append({
                    "Kind": _text(item.get("kind")),
                    "Message": _text(item.get("message")),
                    "Stack": _text(item.get("stack")),
                    "Count": _whole(item.get("count")),
                    "Time": _text(item.get("time")),
                    "Last": _text(item.get("last")),
                    "Session": _whole(item.get("session")),
                    "Taint": _text(item.get("taint")),
                })
        addon = args["Addon"]
        if addon:
            pattern = r"(AddOns[\\/]" + re.escape(addon) + r"[\\/])|(^|\W)" + re.escape(addon) + r"\W"
            entries = [
                entry for entry in entries
                if re.search(pattern, entry["Message"], re.I)
                or re.search(pattern, entry["Stack"], re.I)
                or re.search(pattern, entry["Taint"], re.I)
            ]
        sessions = sorted({entry["Session"] for entry in entries})
        session = int(args["Session"])
        if session == -1 and sessions:
            session = sessions[-1]
        shown = [entry for entry in entries if entry["Session"] == session] if session > 0 else list(entries)
        latest = _whole(db.get("session")) if isinstance(db, dict) else 0
        # One pscustomobject unwraps, so its .Count is the entry's count field, not 1.
        header_count = shown[0]["Count"] if len(shown) == 1 else len(shown)
        if not header_count:
            suffix = f" for {addon}" if addon else ""
            wowkit.host(f"No matching entries{suffix}.")
        else:
            info = None
            sessions_table = db.get("sessions") if isinstance(db, dict) else None
            if isinstance(sessions_table, dict) and session in sessions_table:
                info = sessions_table[session]
            when = f" started {info.get('start')}, build {info.get('build')}" if isinstance(info, dict) else ""
            scope = f"session {session} of {latest}{when}" if session > 0 else "all sessions"
            wowkit.host("")
            noun = "y" if header_count == 1 else "ies"
            wowkit.host(f"{header_count} entr{noun} in {scope}. Summary:")
            groups = []
            grouped = {}
            for entry in shown:
                key = entry["Kind"].casefold()
                if key not in grouped:
                    grouped[key] = {"name": entry["Kind"], "items": []}
                    groups.append(grouped[key])
                grouped[key]["items"].append(entry)
            for group in groups:
                total = sum(item["Count"] for item in group["items"])
                wowkit.host(f"  {group['name']:<9} {len(group['items'])} distinct, {total} total")
            wowkit.host("")
            last = int(args["Last"])
            count = min(last, header_count) if last > 0 else 0
            for entry in reversed(shown[-count:]):
                repeat = f" x{entry['Count']} (last {entry['Last']})" if entry["Count"] > 1 else ""
                wowkit.host(f"[{entry['Kind']}] {entry['Time']}{repeat}  (session {entry['Session']})")
                wowkit.host("    " + entry["Message"].replace("\n", "\n    "))
                lines = [line for line in entry["Stack"].split("\n") if line.strip()][:8]
                for line in lines:
                    wowkit.host(f"      {line}")
                if entry["Taint"]:
                    wowkit.host("    Taint probe (values an addon wrote where the action read):")
                    for line in entry["Taint"].split("\n"):
                        if line.strip():
                            wowkit.host(f"      {line}")
                wowkit.host("")
            if len(sessions) > 1 and session > 0:
                older = ", ".join(str(item) for item in sessions if item != session)
                wowkit.host(f"Older sessions with entries: {older} (use -Session <n> or -Session 0).")

    hits = _log_hits(client_dir, args["Addon"])
    if hits:
        wowkit.host("Client logs with 'Lua Error' lines:")
        for name, number, line in hits[-10:]:
            wowkit.host(f"  {name}:{number}  {line}")
    wowkit.host("")
    wowkit.host('Next: for "blocked" or "forbidden" entries, start from the taint probe lines; if they name nothing, read the taint log (Get-WowTaintLog.py -Addon <name>). For errors, open the first stack line that is in the addon.')
    raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
