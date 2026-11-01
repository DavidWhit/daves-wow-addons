"""Shared helpers for the wow-forever-addons scripts.

Behavior matches scripts/WowKit.psm1 (and the copy in powershell-backup). Windows
PowerShell 5.1 details that callers depend on are kept, including flavor order,
Interface encoding, and the backup-folder suffix that starts at -2.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
KIT_ROOT = SCRIPT_DIR.parent

# Family / Game are what TOC [Family] and [Game] expand to. Forever is game type
# "camelot" inside the "mainline" family. Installed clients override Interface.
KNOWN_FLAVORS = {
    "forever": {"Interface": 16001, "Version": "1.60.1", "GameType": "camelot", "Family": "Mainline", "TocSuffix": "Camelot", "ApiBranch": "forever"},
    "retail": {"Interface": 120100, "Version": "12.1.0", "GameType": "standard", "Family": "Mainline", "TocSuffix": "Mainline", "ApiBranch": "live"},
    "mists": {"Interface": 50504, "Version": "5.5.4", "GameType": "mists", "Family": "Classic", "TocSuffix": "Mists", "ApiBranch": "classic"},
    "titan": {"Interface": 38002, "Version": "3.80.2", "GameType": "wrath", "Family": "Classic", "TocSuffix": "Wrath", "ApiBranch": "classic_titan"},
    "anniversary": {"Interface": 20506, "Version": "2.5.6", "GameType": "tbc", "Family": "Classic", "TocSuffix": "TBC", "ApiBranch": "classic_anniversary"},
    "classic_era": {"Interface": 11509, "Version": "1.15.9", "GameType": "vanilla", "Family": "Classic", "TocSuffix": "Vanilla", "ApiBranch": "classic_era"},
}

_CANONICAL_NS = (
    "C_Item", "C_Spell", "C_Container", "C_AddOns", "C_ChatInfo",
    "C_CurrencyInfo", "C_UnitAuras", "C_SpellBook", "C_Map", "C_QuestLog",
)
_API_CACHE: dict = {}
_REPARSE = 0x400


class Client:
    def __init__(self, folder, flavor, product, version, interface, path, addons):
        self.Folder = folder
        self.Flavor = flavor
        self.Product = product
        self.Version = version
        self.Interface = interface
        self.Path = path
        self.AddOns = addons

    def as_dict(self):
        return {
            "Folder": self.Folder,
            "Flavor": self.Flavor,
            "Product": self.Product,
            "Version": self.Version,
            "Interface": self.Interface,
            "Path": self.Path,
            "AddOns": self.AddOns,
        }


def warn(message: str) -> None:
    print(f"WARNING: {message}", file=sys.stderr, flush=True)


def host(message: str = "") -> None:
    # Write-Host shows up immediately. A pipe would otherwise hold this until a child process finished.
    try:
        print(message, flush=True)
    except UnicodeEncodeError:
        enc = getattr(sys.stdout, "encoding", None) or "ascii"
        safe = message.encode(enc, errors="replace").decode(enc, errors="replace")
        print(safe, flush=True)


def die(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr, flush=True)
    raise SystemExit(code)


def parse_ps_args(argv, spec):
    """Parse PowerShell-style `-Name value` / `-Switch` arguments.

    spec items are (canonical_name, kind, default). kind is "switch", "value",
    or "list". Names are case-insensitive. A list collects every occurrence.
    """
    wanted = {}
    for name, kind, default in spec:
        wanted[name.lower()] = (name, kind, default)
    out = {name: ([] if kind == "list" else default) for name, kind, default in spec}
    i = 0
    args = list(argv)
    while i < len(args):
        token = args[i]
        if token in ("-?", "/?"):
            die("Unknown argument: " + token)
        if token.startswith("-"):
            raw = token[1:]
            if raw.startswith("-"):
                raw = raw[1:]
            # `-Name:value` is valid PowerShell.
            eq = ":" in raw
            key, inline = raw.split(":", 1) if eq else (raw, "")
            found = wanted.get(key.lower())
            if not found:
                die("Unknown argument: " + token)
            name, kind, _default = found
            if kind == "switch":
                if eq and inline:
                    out[name] = inline.strip().lower() not in ("false", "0", "$false")
                else:
                    out[name] = True
                i += 1
                continue
            if eq:
                value = inline
            else:
                if i + 1 >= len(args):
                    die(f"Missing value for -{name}")
                i += 1
                value = args[i]
            if kind == "list":
                out[name].append(value)
            else:
                out[name] = value
            i += 1
            continue
        die("Unknown argument: " + token)
    return out


def resolve_flavors(flavor) -> list:
    items = [] if flavor is None else ([flavor] if isinstance(flavor, str) else list(flavor))
    found = []
    seen = set()
    bad = []
    for item in items:
        for part in re.split(r"[,\s]+", str(item).strip()):
            name = part.lower()
            if not name or name in seen:
                continue
            seen.add(name)
            if name not in KNOWN_FLAVORS:
                bad.append(name)
            found.append(name)
    if bad:
        known = ", ".join(KNOWN_FLAVORS)
        raise ValueError(f"Unknown flavor(s): {', '.join(bad)}. Use: {known}")
    return found or ["forever"]


def interface_from_version(version):
    if not version:
        return None
    parts = str(version).split(".")
    if len(parts) < 3:
        return None
    try:
        return int(parts[0]) * 10000 + int(parts[1]) * 100 + int(parts[2])
    except ValueError:
        return None


def flavor_for_interface(interface: int):
    for name, info in KNOWN_FLAVORS.items():
        known = info["Interface"]
        if known // 100 == int(interface) // 100 or (name == "retail" and interface >= 110000):
            return name
    return None


def _has_build_info(path) -> bool:
    return bool(path) and os.path.isfile(os.path.join(path, ".build.info"))


def wow_root():
    if os.name != "nt":
        candidates = [
            "/Applications/World of Warcraft",
            os.path.join(os.path.expanduser("~"), "Applications/World of Warcraft"),
        ]
        for candidate in candidates:
            if _has_build_info(candidate):
                return os.path.abspath(candidate)
        return None

    candidates = []
    if os.name == "nt":
        import winreg
        for subkey in (
            r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
            r"SOFTWARE\Blizzard Entertainment\World of Warcraft",
        ):
            try:
                with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, subkey) as key:
                    install_path, _typ = winreg.QueryValueEx(key, "InstallPath")
            except OSError:
                continue
            if install_path:
                trimmed = install_path.rstrip("\\")
                candidates.append(os.path.dirname(trimmed))
                candidates.append(trimmed)
    program_files_x86 = os.environ.get("ProgramFiles(x86)")
    program_files = os.environ.get("ProgramFiles")
    if program_files_x86:
        candidates.append(os.path.join(program_files_x86, "World of Warcraft"))
    if program_files:
        candidates.append(os.path.join(program_files, "World of Warcraft"))
    if os.name == "nt":
        buf = __import__("ctypes").create_unicode_buffer(1024)
        length = __import__("ctypes").windll.kernel32.GetLogicalDriveStringsW(len(buf), buf)
        drives = [part for part in buf[:length].split("\0") if part]
        for drive in drives:
            candidates.append(os.path.join(drive, "World of Warcraft"))
            candidates.append(os.path.join(drive, "Games", "World of Warcraft"))
    for candidate in candidates:
        if _has_build_info(candidate):
            return os.path.abspath(candidate)
    return None


def _read_blizzard_info(path):
    if not os.path.isfile(path):
        return []
    # utf-8-sig covers the BOM PowerShell's Set-Content -Encoding UTF8 writes.
    with open(path, "r", encoding="utf-8-sig", errors="replace") as handle:
        lines = [line.rstrip("\r\n") for line in handle if line.strip() and not line.startswith("#")]
    if len(lines) < 2:
        return []
    columns = [col.split("!")[0] for col in lines[0].split("|")]
    rows = []
    for line in lines[1:]:
        values = line.split("|")
        rows.append({col: (values[i] if i < len(values) else "") for i, col in enumerate(columns)})
    return rows


def wow_install(root=None):
    if root is None:
        root = wow_root()
    if not root:
        return []
    build = _read_blizzard_info(os.path.join(root, ".build.info"))
    clients = []
    try:
        names = sorted(os.listdir(root))
    except OSError:
        return []
    # PowerShell Get-ChildItem order is filesystem order, not sorted. listdir is
    # arbitrary too; match the shell by using the raw directory order from os.listdir
    # on Windows (which is creation-unspecified). Keep insertion as listdir gives it.
    for name in names:
        full = os.path.join(root, name)
        if not os.path.isdir(full) or not re.match(r"^_.+_$", name):
            continue
        flavor_info = _read_blizzard_info(os.path.join(full, ".flavor.info"))
        product = flavor_info[0].get("Product Flavor") if flavor_info else None
        if not product:
            guess = "wow" if name == "_retail_" else "wow" + name.rstrip("_")
            if any(row.get("Product") == guess for row in build):
                product = guess
        row = next((item for item in build if item.get("Product") == product), None)
        version = row.get("Version") if row else None
        interface = interface_from_version(version) if version else None
        flavor = flavor_for_interface(interface) if interface else None
        clients.append(Client(
            name, flavor, product, version, interface, os.path.abspath(full),
            os.path.join(os.path.abspath(full), "Interface", "AddOns"),
        ))
    return clients


def interface_for(flavor, installs=None):
    if installs is None:
        installs = wow_install()
    hits = [c for c in installs if c.Flavor == flavor and c.Interface]
    if hits:
        return max(hits, key=lambda c: c.Interface).Interface
    info = KNOWN_FLAVORS.get(flavor)
    return info["Interface"] if info else None


def is_link(path) -> bool:
    try:
        st = os.lstat(path)
    except OSError:
        return False
    attrs = getattr(st, "st_file_attributes", 0)
    if attrs & _REPARSE:
        return True
    return os.path.islink(path)


def link_target(path):
    if not is_link(path):
        return None
    try:
        target = os.readlink(path)
    except OSError:
        return None
    target = re.sub(r"^\\\\\?\\|^\\\?\?\\", "", target)
    if not os.path.isabs(target):
        target = os.path.join(os.path.dirname(path), target)
    return os.path.abspath(target)


def same_path(a, b) -> bool:
    if not a or not b:
        return False
    def norm(path):
        return os.path.normpath(os.path.abspath(path)).rstrip("\\/").lower()
    return norm(a) == norm(b)


def new_link(path, target) -> None:
    if os.name == "nt":
        # A directory junction, same as New-Item -ItemType Junction. No admin needed.
        # cmd's mklink is a builtin; never delete through this path.
        result = subprocess.run(
            ["cmd", "/c", "mklink", "/J", path, target],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip()
            raise OSError(detail or f"mklink failed for {path}")
    else:
        os.symlink(target, path, target_is_directory=True)


def remove_link(path) -> None:
    if not is_link(path):
        raise OSError(f"{path} is not a link; not removing it.")
    # os.rmdir on a junction removes only the link. shutil.rmtree would follow it.
    if os.name == "nt":
        os.rmdir(path)
    else:
        os.unlink(path)


def move_addon_to_backup(path) -> str:
    addons = os.path.dirname(path)
    backup_root = os.path.join(os.path.dirname(addons), "AddOns.backup")
    os.makedirs(backup_root, exist_ok=True)
    base = os.path.join(
        backup_root,
        f"{os.path.basename(path)}-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
    )
    backup = base
    n = 1
    while os.path.exists(backup):
        n += 1
        backup = f"{base}-{n}"
    shutil.move(path, backup)
    return backup


def _as_list(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return list(value)


def api_index(branch="forever"):
    cached = _API_CACHE.get(branch)
    if cached is not None:
        return cached
    file = KIT_ROOT / "data" / f"api-{branch}.json"
    if not file.is_file():
        return None
    with file.open("r", encoding="utf-8-sig") as handle:
        raw = json.load(handle)
    index = {
        "Commit": raw.get("commit"),
        "Source": raw.get("source"),
        "Functions": {},
        "FunctionMeta": {},
        "Methods": {},
        "Events": {},
        "EventMeta": {},
        "Namespaces": {},
        "Deprecated": {},
        "ByShort": {},
        "Globals": set(),
    }
    for name in raw.get("globals") or []:
        index["Globals"].add(name)
    for name, value in (raw.get("functions") or {}).items():
        if isinstance(value, dict):
            secret = _as_list(value.get("secret"))
            index["FunctionMeta"][name] = {
                "secret": secret,
                "secretArgs": value.get("secretArgs"),
                "protected": bool(value.get("protected")),
                "restricted": bool(value.get("restricted")),
                "noSecureHook": bool(value.get("noSecureHook")),
                "requires": _as_list(value.get("requires")),
            }
        else:
            secret = []
            index["FunctionMeta"][name] = {
                "secret": [],
                "secretArgs": None,
                "protected": False,
                "restricted": False,
                "noSecureHook": False,
                "requires": [],
            }
        index["Functions"][name] = secret
        dot = name.find(".")
        if dot > 0:
            short = name[dot + 1:]
            bucket = index["ByShort"].setdefault(short, [])
            if name[:dot] in _CANONICAL_NS:
                bucket.insert(0, name)
            else:
                bucket.append(name)
    for name, value in (raw.get("methods") or {}).items():
        if isinstance(value, dict):
            index["Methods"][name] = {
                "objects": _as_list(value.get("objects")),
                "secret": _as_list(value.get("secret")),
                "secretArgs": _as_list(value.get("secretArgs")),
                "protected": bool(value.get("protected")),
                "protectedObjects": _as_list(value.get("protectedObjects")),
                "restricted": bool(value.get("restricted")),
                "requires": _as_list(value.get("requires")),
            }
    for name, value in (raw.get("events") or {}).items():
        if isinstance(value, dict):
            secret_list = _as_list(value.get("secret"))
            flag = bool(value.get("secretPayloads") or secret_list)
            index["EventMeta"][name] = {"secretPayloads": flag, "secret": secret_list}
        else:
            flag = False
            index["EventMeta"][name] = {"secretPayloads": False, "secret": []}
        index["Events"][name] = flag
    for name in raw.get("namespaces") or []:
        index["Namespaces"][name] = True
    for name, value in (raw.get("deprecated") or {}).items():
        index["Deprecated"][name] = value
    _API_CACHE[branch] = index
    return index


def tool_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    return Path(base) / "wow-addon-kit" / "bin"


def find_luacheck():
    found = shutil.which("luacheck")
    if found:
        return found
    local = tool_dir() / "luacheck.exe"
    if local.is_file():
        return str(local)
    return None
