"""Create a WoW addon from the kit template. Matches New-WowAddon.ps1."""

from __future__ import annotations

import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Name", "value", None),
        ("OutDir", "value", os.getcwd()),
        ("Flavor", "list", []),
        ("Title", "value", None),
        ("Notes", "value", "A WoW: Forever addon."),
        ("Author", "value", os.environ.get("USERNAME") or ""),
        ("Version", "value", "0.1.0"),
        ("Icon", "value", r"Interface\Icons\INV_Misc_QuestionMark"),
        ("Slash", "value", None),
        ("EditMode", "switch", False),
        ("Deploy", "switch", False),
        ("Force", "switch", False),
    ])
    name = args["Name"]
    if not name:
        wowkit.die("Missing value for -Name")
    if not re.match(r"^[A-Za-z][A-Za-z0-9_]{1,48}$", name):
        wowkit.die(f"Name '{name}' must match ^[A-Za-z][A-Za-z0-9_]{{1,48}}$.")
    try:
        flavors = wowkit.resolve_flavors(args["Flavor"])
    except ValueError as exc:
        wowkit.die(str(exc))
    dest = os.path.join(args["OutDir"], name)
    if os.path.isdir(dest) and os.listdir(dest) and not args["Force"]:
        wowkit.die(f"{dest} already exists and is not empty. Pick another name or pass -Force to overwrite template files.")
    title = args["Title"] or re.sub(r"(?<=[a-z0-9])([A-Z])", r" \1", name)
    slash = args["Slash"]
    if slash:
        if not re.match(r"^[a-z][a-z0-9]{1,15}$", slash):
            wowkit.die("Slash must match ^[a-z][a-z0-9]{1,15}$.")
    else:
        slash = re.sub(r"[^a-z0-9]", "", name.lower())[:12]
    installs = wowkit.wow_install()
    interfaces = []
    for flavor in flavors:
        number = wowkit.interface_for(flavor, installs)
        if number and number not in interfaces:
            interfaces.append(number)
    icon = args["Icon"]
    if not re.search(r"[\\/]", icon):
        icon = "Interface\\Icons\\" + icon
    db = name + "DB"
    tokens = {
        "{{NAME}}": name,
        "{{TITLE}}": title,
        "{{TITLEPLAIN}}": title,
        "{{NOTES}}": args["Notes"],
        "{{AUTHOR}}": args["Author"],
        "{{VERSION}}": args["Version"],
        "{{ICON}}": icon,
        "{{DB}}": db,
        "{{SLASH}}": slash,
        "{{SLASHUPPER}}": name.upper(),
        "{{INTERFACES}}": ", ".join(str(item) for item in interfaces),
        "{{FLAVORS}}": ", ".join(flavors),
        "{{FLAVORLIST}}": ",".join(flavors),
        "--@globals@": f'"{db}",\n\t"{name}_OnAddonCompartmentClick",',
    }
    template = os.path.join(wowkit.KIT_ROOT, "templates", "addon")
    os.makedirs(dest, exist_ok=True)
    for dirpath, _dirs, filenames in os.walk(template):
        for filename in filenames:
            src = os.path.join(dirpath, filename)
            rel = os.path.relpath(src, template).replace("__NAME__", name)
            target = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            # ReadAllText/WriteAllText keep the template's own newlines and write UTF-8 with no BOM.
            text = open(src, "r", encoding="utf-8-sig", newline="").read()
            for key, value in tokens.items():
                text = text.replace(key, value)
            with open(target, "w", encoding="utf-8", newline="") as handle:
                handle.write(text)
    if args["EditMode"]:
        dialog = os.path.join(wowkit.KIT_ROOT, "templates", "editmode", "EditModeDialog.lua")
        with open(dialog, "rb") as src, open(os.path.join(dest, "EditModeDialog.lua"), "wb") as dst:
            dst.write(src.read())
        text = open(os.path.join(wowkit.KIT_ROOT, "templates", "editmode", "EditMode.lua"), "r", encoding="utf-8-sig", newline="").read()
        for key, value in tokens.items():
            text = text.replace(key, value)
        with open(os.path.join(dest, "EditMode.lua"), "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        toc_path = os.path.join(dest, name + ".toc")
        toc = open(toc_path, "r", encoding="utf-8-sig", newline="").read()
        toc = re.sub(r"(?m)^Core\.lua(\r?)$", r"Core.lua\1\nEditModeDialog.lua\1\nEditMode.lua\1", toc)
        with open(toc_path, "w", encoding="utf-8", newline="") as handle:
            handle.write(toc)
    wowkit.host(f"Created {dest}")
    wowkit.host(f"  ## Interface: {', '.join(str(item) for item in interfaces)}   SavedVariables: {db}   Slash: /{slash}")
    wowkit.host("")
    checker = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Test-WowAddon.py")
    proc = subprocess.run([sys.executable, checker, "-Path", dest, "-Flavor", ",".join(flavors)])
    ok = proc.returncode == 0
    if args["Deploy"]:
        deploy = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Deploy-WowAddon.py")
        for flavor in flavors:
            subprocess.run([sys.executable, deploy, "-Path", dest, "-Flavor", flavor])
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main(sys.argv[1:])
