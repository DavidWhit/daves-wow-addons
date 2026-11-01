"""Put one addon into a client's AddOns folder."""

from __future__ import annotations

import fnmatch
import os
import shutil
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit

# robocopy /XD and /XF are case-insensitive on Windows.
EXCLUDE_DIRS = {".git", ".vscode", "tests", "tools", "__pycache__", ".release"}
EXCLUDE_FILES = [".luacheckrc", ".pkgmeta", ".gitignore", "README.md", "NOTES.md", "*.zip"]


def _excluded_dir(name):
    return name.casefold() in EXCLUDE_DIRS


def _backup_path(path):
    """The path Move-WowAddonToBackup would return. Used when -WhatIf skips the move."""
    addons = os.path.dirname(path)
    backup_root = os.path.join(os.path.dirname(addons), "AddOns.backup")
    base = os.path.join(backup_root, f"{os.path.basename(path)}-{datetime.now().strftime('%Y%m%d-%H%M%S')}")
    backup = base
    n = 1
    while os.path.exists(backup):
        n += 1
        backup = f"{base}-{n}"
    return backup


def copy_tree(src, dest):
    os.makedirs(dest, exist_ok=True)
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [name for name in dirnames if not _excluded_dir(name)]
        rel = os.path.relpath(dirpath, src)
        target_dir = dest if rel == "." else os.path.join(dest, rel)
        os.makedirs(target_dir, exist_ok=True)
        for name in filenames:
            if any(fnmatch.fnmatch(name, pattern) for pattern in EXCLUDE_FILES):
                continue
            shutil.copy2(os.path.join(dirpath, name), os.path.join(target_dir, name))


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Path", "value", None),
        ("Flavor", "value", "forever"),
        ("Mode", "value", "Link"),
        ("AddOnsPath", "value", None),
        ("Remove", "switch", False),
        ("Force", "switch", False),
        ("WhatIf", "switch", False),
    ])
    if not args["Path"]:
        wowkit.die("Missing value for -Path")
    flavor = args["Flavor"]
    if flavor not in wowkit.KNOWN_FLAVORS:
        wowkit.die(f"Unknown flavor '{flavor}'. Use: {', '.join(wowkit.KNOWN_FLAVORS)}")
    if args["Mode"] not in ("Link", "Copy"):
        wowkit.die("Mode must be Link or Copy.")
    src = os.path.abspath(args["Path"])
    if not os.path.isdir(src):
        wowkit.die(f"Not a folder: {src}")
    name = os.path.basename(src)
    client = None
    addons_path = args["AddOnsPath"]
    if not addons_path:
        matches = [item for item in wowkit.wow_install() if item.Flavor == flavor]
        if not matches:
            wowkit.die(f"No installed {flavor} client found. Run Find-WowInstall.py, or pass -AddOnsPath.")
        client = matches[0]
        addons_path = client.AddOns
    if not args["WhatIf"]:
        os.makedirs(addons_path, exist_ok=True)
    target = os.path.join(addons_path, name)

    def record():
        if not client or args["WhatIf"]:
            return
        link = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Link-WowAddons.py")
        dev = os.path.join(wowkit.KIT_ROOT, "devaddons", "!WowKitErrors")
        proc = subprocess.run([sys.executable, link, "-Path", dev, "-Flavor", flavor], capture_output=True, text=True)
        if proc.returncode == 0:
            wowkit.host(f"Kit error recorder (!WowKitErrors) linked in {client.Folder} too: it records Lua errors for Get-WowScriptErrors.py.")
        else:
            wowkit.warn(f"Could not link the kit's error recorder (!WowKitErrors): {(proc.stderr or proc.stdout).strip()}")

    if os.path.lexists(target):
        if wowkit.is_link(target):
            current = wowkit.link_target(target)
            if args["Remove"] or args["Mode"] == "Copy" or (current and not wowkit.same_path(current, src)):
                if not args["WhatIf"]:
                    wowkit.remove_link(target)
                    wowkit.host(f"Unlinked {target}")
            elif args["Mode"] == "Link":
                wowkit.host(f"Already linked: {target} -> {src}")
                record()
                raise SystemExit(0)
        elif args["Remove"]:
            wowkit.die(f"{target} is a real folder, not a link made by this script; not removing it.")
        elif os.path.isfile(os.path.join(target, ".deployed-by-wow-addon-kit")):
            # Remove-Item honors -WhatIf. robocopy does not, so a skipped delete leaves the old copy in place.
            if not args["WhatIf"]:
                shutil.rmtree(target)
        elif args["Force"]:
            if args["WhatIf"]:
                backup = _backup_path(target)
                wowkit.host(f"Moved the existing folder to {backup}")
            else:
                backup = wowkit.move_addon_to_backup(target)
                wowkit.host(f"Moved the existing folder to {backup}")
        else:
            wowkit.die(f"{target} already exists as a real folder (maybe an installed copy of this addon). Re-run with -Force to move it to AddOns.backup first.")
    if args["Remove"]:
        raise SystemExit(0)
    if args["Mode"] == "Link":
        if not args["WhatIf"]:
            wowkit.new_link(target, src)
            wowkit.host(f"Linked {target} -> {src}")
    else:
        # robocopy ignores -WhatIf. Set-Content does not, so the marker is only written for real.
        copy_tree(src, target)
        if not args["WhatIf"]:
            with open(os.path.join(target, ".deployed-by-wow-addon-kit"), "w", encoding="ascii", newline="") as handle:
                handle.write(datetime.now().strftime("%Y-%m-%dT%H:%M:%S") + "\r\n")
        wowkit.host(f"Copied {src} -> {target}")
    record()
    wowkit.host("In game: /reload picks up Lua/XML edits. New files, TOC changes and new textures need a full client restart.")
    raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
