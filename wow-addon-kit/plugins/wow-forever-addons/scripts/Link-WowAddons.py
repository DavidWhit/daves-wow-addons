"""Link addon folders into a WoW client's AddOns directory."""

from __future__ import annotations

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit


def addon_tocs(directory):
    name = os.path.basename(directory)
    found = []
    try:
        entries = os.listdir(directory)
    except OSError:
        return found
    for entry in entries:
        full = os.path.join(directory, entry)
        if not os.path.isfile(full) or not entry.lower().endswith(".toc"):
            continue
        base = entry[:-4]
        if base.lower() == name.lower() or base.startswith(name + "_"):
            found.append(full)
    return found


def addon_info(directories):
    infos = []
    for directory in directories:
        tocs = addon_tocs(directory)
        if not tocs:
            continue
        flavors = []
        seen = set()
        for toc in tocs:
            with open(toc, "r", encoding="utf-8-sig", errors="replace") as handle:
                lines = handle.readlines()[:40]
            for line in lines:
                match = re.match(r"^\s*##\s*Interface(-\w+)?\s*:\s*(.+)$", line, re.I)
                if not match:
                    continue
                for number in match.group(2).split(","):
                    token = number.strip()
                    if re.match(r"^\d{5,6}$", token):
                        flavor = wowkit.flavor_for_interface(int(token))
                        if flavor and flavor not in seen:
                            seen.add(flavor)
                            flavors.append(flavor)
        infos.append({
            "Name": os.path.basename(directory),
            "Path": os.path.abspath(directory),
            "Flavors": flavors,
            "Dev": False,
        })
    return infos


def find_wowaddons(start):
    current = os.path.abspath(start)
    while True:
        candidate = os.path.join(current, "wowaddons")
        if os.path.isdir(candidate):
            return candidate
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent


def link_addons(path, flavor_args, root, remove, no_dev, what_if):
    if not path:
        for start in (os.getcwd(), os.path.dirname(os.path.abspath(__file__))):
            path = find_wowaddons(start)
            if path:
                break
        if not path:
            raise RuntimeError('No wowaddons folder found above the current folder or this script. Pass -Path "<folder with addon folders>".')
    path = os.path.abspath(path)
    if not os.path.isdir(path):
        raise RuntimeError(f"Not a folder: {path}")
    single = len(addon_tocs(path)) > 0
    candidates = [path] if single else [os.path.join(path, name) for name in os.listdir(path) if os.path.isdir(os.path.join(path, name))]
    addons = addon_info(candidates)
    if not addons:
        raise RuntimeError(f"No addon folders (<Folder>\\<Folder>.toc) in {path}.")
    dev_dir = os.path.join(wowkit.KIT_ROOT, "devaddons")
    if not no_dev and not (remove and single) and os.path.isdir(dev_dir):
        names = {item["Name"] for item in addons}
        for dev in addon_info([os.path.join(dev_dir, name) for name in os.listdir(dev_dir) if os.path.isdir(os.path.join(dev_dir, name))]):
            if dev["Name"] not in names:
                dev["Dev"] = True
                addons.append(dev)
    root = root or wowkit.wow_root()
    if not root:
        raise RuntimeError('World of Warcraft was not found. Pass -Root "<WoW install folder>" (the one holding .build.info).')
    clients = wowkit.wow_install(root)
    if not clients:
        raise RuntimeError(f"No client folders (_retail_, _forever_, ...) under {root}.")
    forced = None
    warnings = []
    if flavor_args:
        raw = []
        for item in flavor_args:
            raw.extend(part.lower() for part in re.split(r"[,\s]+", item) if part)
        if "all" in raw:
            forced = "all"
        else:
            forced = wowkit.resolve_flavors(raw)
            for flavor in forced:
                if not any(client.Flavor == flavor for client in clients):
                    warnings.append(f"No installed {flavor} client; skipping it.")
            clients = [client for client in clients if client.Flavor in forced]
            if not clients:
                raise RuntimeError(f"No installed client for flavor(s) {', '.join(forced)}. Run Find-WowInstall.py to see what is installed.")
    results = []
    for client in clients:
        for addon in addons:
            target = os.path.join(client.AddOns, addon["Name"])
            try:
                exists = os.path.lexists(target)
                is_link = exists and wowkit.is_link(target)
                current = wowkit.link_target(target) if is_link else None
                ours = is_link and wowkit.same_path(current, addon["Path"])
                detail = ""
                if remove:
                    if not exists:
                        status = "NotLinked"
                    elif not is_link:
                        status, detail = "Kept", "real folder, not a link; left alone"
                    elif not ours:
                        status, detail = "Kept", f"links to {current}; left alone"
                    elif what_if:
                        status = "WouldUnlink"
                    else:
                        wowkit.remove_link(target)
                        status = "Unlinked"
                elif forced is None and client.Flavor not in addon["Flavors"]:
                    why = f"TOC has no {client.Flavor} Interface" if client.Flavor else "unknown client flavor"
                    if ours:
                        why += "; existing link left alone"
                    status, detail = "Skipped", why
                elif ours:
                    status = "AlreadyLinked"
                elif is_link:
                    if what_if:
                        status, detail = "WouldRelink", f"now -> {current}"
                    else:
                        wowkit.remove_link(target)
                        wowkit.new_link(target, addon["Path"])
                        status, detail = "Relinked", f"was -> {current}"
                elif exists:
                    if what_if:
                        status, detail = "WouldLink", "real folder would move to AddOns.backup first"
                    else:
                        backup = wowkit.move_addon_to_backup(target)
                        wowkit.new_link(target, addon["Path"])
                        status, detail = "Linked", f"real folder moved to {backup}"
                else:
                    if what_if:
                        status = "WouldLink"
                    else:
                        os.makedirs(client.AddOns, exist_ok=True)
                        wowkit.new_link(target, addon["Path"])
                        status = "Linked"
                if addon["Dev"]:
                    detail = ("kit error recorder; " + detail).rstrip(" ;")
                results.append({
                    "Client": client.Folder,
                    "Flavor": client.Flavor,
                    "Addon": addon["Name"],
                    "Status": status,
                    "Detail": detail,
                })
            except Exception as exc:
                detail = str(exc)
                if addon["Dev"]:
                    detail = ("kit error recorder; " + detail).rstrip(" ;")
                results.append({
                    "Client": client.Folder,
                    "Flavor": client.Flavor,
                    "Addon": addon["Name"],
                    "Status": "Failed",
                    "Detail": detail,
                })
    return path, root, results, warnings


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Path", "value", None),
        ("Flavor", "list", []),
        ("Root", "value", None),
        ("Remove", "switch", False),
        ("NoDevAddons", "switch", False),
        ("PassThru", "switch", False),
        ("WhatIf", "switch", False),
    ])
    try:
        path, root, results, warnings = link_addons(
            args["Path"], args["Flavor"], args["Root"], args["Remove"], args["NoDevAddons"], args["WhatIf"],
        )
    except (RuntimeError, ValueError) as exc:
        wowkit.die(str(exc))
    for message in warnings:
        wowkit.warn(message)
    kind = "junctions" if os.name == "nt" else "symlinks"
    wowkit.host(f"Addons: {path}")
    wowkit.host(f"WoW:    {root} ({kind})")
    wowkit.host(f"{'Client':<16} {'Flavor':<10} {'Addon':<18} {'Status':<14} Detail")
    for row in results:
        wowkit.host(f"{row['Client']:<16} {row['Flavor'] or '':<10} {row['Addon']:<18} {row['Status']:<14} {row['Detail']}")
    counts = []
    seen = []
    for row in results:
        if row["Status"] not in seen:
            seen.append(row["Status"])
    for status in seen:
        counts.append(f"{sum(1 for row in results if row['Status'] == status)} {status}")
    wowkit.host(", ".join(counts))
    if any(row["Status"] in ("Linked", "Relinked") for row in results):
        wowkit.host("In game: fully restart the client once so it sees newly linked addons, then enable them in the AddOns list.")
    if args["PassThru"]:
        print(json.dumps(results))
    if any(row["Status"] == "Failed" for row in results):
        raise SystemExit(1)
    raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
