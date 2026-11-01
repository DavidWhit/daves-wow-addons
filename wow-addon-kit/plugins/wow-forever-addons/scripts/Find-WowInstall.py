"""Find the WoW install and list clients. Matches Find-WowInstall.ps1."""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Root", "value", None),
        ("Json", "switch", False),
    ])
    root = args["Root"] or wowkit.wow_root()
    if not root:
        wowkit.warn('World of Warcraft was not found (checked the registry, Program Files and drive roots). Pass -Root "D:\\Games\\World of Warcraft".')
        raise SystemExit(1)
    installs = wowkit.wow_install(root)
    if args["Json"]:
        print(json.dumps({"Root": root, "Clients": [c.as_dict() for c in installs]}, indent=2))
        raise SystemExit(0)
    wowkit.host(f"WoW root: {root}")
    wowkit.host(f"{'Folder':<16} {'Flavor':<12} {'Product':<10} {'Version':<16} {'Interface':<10} AddOns")
    for client in installs:
        wowkit.host(f"{client.Folder:<16} {client.Flavor or '':<12} {client.Product or '':<10} {client.Version or '':<16} {client.Interface or '':<10} {client.AddOns}")
    forever = next((client for client in installs if client.Flavor == "forever"), None)
    if forever:
        wowkit.host(f"WoW: Forever client: {forever.Folder} -> ## Interface: {forever.Interface}")
    else:
        wowkit.host("No WoW: Forever client found among the installed folders.")
    raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
