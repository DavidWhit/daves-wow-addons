"""Build wowaddons/daves_map_textures from a local OpenMap folder or zip.

Matches Update-MapTextures.ps1. Nothing is downloaded. The default output is the
gitignored daves_map_textures addon next to daves_map. Pass a source you already have.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import tempfile
import zipfile
from datetime import datetime, timezone

DATA = (
    "ArtEdits", "Banners", "Caves", "CaveMinimap", "Gaps", "GapPlaces", "Grade",
    "Labels", "Minimap", "MinimapLOD", "Places", "Reveal", "Tones",
)
EXCLUDE = ("MapChart", "MapGapFill", "MapZones", "MapDungeonDrawn")
CODE_RX = re.compile(r"\bfunction\b|\bloadstring\b|\bsetfenv\b|_G\b", re.I)
IFACE_RX = re.compile(r"(?m)^## Interface:\s*(.+?)\s*$")
VERSION_RX = re.compile(r"(?m)^## Version:\s*(.+?)\s*$")


def n0(value):
    """PowerShell {0:N0} on en-US: half away from zero, with thousands commas."""
    if value >= 0:
        number = int(value + 0.5)
    else:
        number = int(value - 0.5)
    return f"{number:,}"


def _read(path):
    with open(path, "r", encoding="utf-8-sig", newline="") as handle:
        return handle.read()


def _same_name(left, right):
    return left.casefold() == right.casefold()


def paths_from_script(script_file):
    tools = os.path.dirname(os.path.abspath(script_file))
    addon_dir = os.path.dirname(tools)
    repo = os.path.dirname(os.path.dirname(addon_dir))
    return addon_dir, repo


def build(source, addon_dir, repo, make_zip):
    if not source:
        source = os.path.join(repo, "OpenMap")
    if not os.path.exists(source):
        raise RuntimeError(f"No OpenMap release at '{source}'. Pass -Source <folder or zip>.")

    map_toc = os.path.join(addon_dir, "daves_map.toc")
    iface_match = IFACE_RX.search(_read(map_toc))
    iface = iface_match.group(1) if iface_match else ""
    if not iface:
        raise RuntimeError(f"No '## Interface:' line in {map_toc}.")

    temp = None
    src = os.path.abspath(source)
    try:
        if os.path.isfile(src):
            if not src.lower().endswith(".zip"):
                raise RuntimeError("-Source must be an OpenMap folder or a .zip.")
            temp = os.path.join(tempfile.gettempdir(), "openmap-" + os.urandom(16).hex())
            os.makedirs(temp)
            with zipfile.ZipFile(src) as archive:
                archive.extractall(temp)
            toc_hit = None
            for dirpath, _dirs, files in os.walk(temp):
                for name in files:
                    if name.lower() == "openmap.toc":
                        toc_hit = os.path.join(dirpath, name)
                        break
                if toc_hit:
                    break
            if not toc_hit:
                raise RuntimeError(f"No OpenMap.toc in {source}.")
            src = os.path.dirname(toc_hit)

        om_toc = os.path.join(src, "OpenMap.toc")
        if not os.path.isfile(om_toc):
            raise RuntimeError(
                f"No OpenMap.toc in {src}: that's not OpenMap's WoW Forever build "
                "(the Retail one is OpenMap_Mainline.toc)."
            )
        toc_text = _read(om_toc)
        om_iface_match = IFACE_RX.search(toc_text)
        om_version_match = VERSION_RX.search(toc_text)
        om_iface = om_iface_match.group(1) if om_iface_match else ""
        om_version = om_version_match.group(1) if om_version_match else ""
        want = iface.split(",")[0].strip()
        have = [part.strip() for part in om_iface.split(",")]
        if want.casefold() not in {part.casefold() for part in have}:
            raise RuntimeError(f"OpenMap at {src} is for Interface {om_iface}, not WoW Forever's {want}.")

        for name in DATA:
            path = os.path.join(src, "Data", name + ".lua")
            if not os.path.isfile(path):
                raise RuntimeError(
                    f"OpenMap {om_version} has no Data\\{name}.lua: "
                    "daves_map\\Stitch needs updating to this release."
                )
            if CODE_RX.search(_read(path)):
                raise RuntimeError(
                    f"Data\\{name}.lua in OpenMap {om_version} holds code, not just tables: "
                    "check it before using it."
                )

        out = os.path.join(repo, "wowaddons", "daves_map_textures")
        if os.path.exists(out):
            own = os.path.join(out, "daves_map_textures.toc")
            if not os.path.isfile(own):
                raise RuntimeError(f"{out} exists and isn't a daves_map_textures build; move it away first.")
            shutil.rmtree(out)
        os.makedirs(os.path.join(out, "Data"))
        os.makedirs(os.path.join(out, "Media", "Textures"))

        for name in DATA:
            shutil.copy2(os.path.join(src, "Data", name + ".lua"), os.path.join(out, "Data"))
        tex_src = os.path.join(src, "Media", "Textures")
        excluded = {name.casefold() for name in EXCLUDE}
        for item in os.listdir(tex_src):
            if item.casefold() in excluded or _same_name(item, "NOTICE.md"):
                continue
            src_item = os.path.join(tex_src, item)
            dest_item = os.path.join(out, "Media", "Textures", item)
            if os.path.isdir(src_item):
                shutil.copytree(src_item, dest_item)
            else:
                shutil.copy2(src_item, dest_item)
        copied = 0
        total = 0
        media = os.path.join(out, "Media")
        for dirpath, _dirs, files in os.walk(media):
            for name in files:
                copied += 1
                total += os.path.getsize(os.path.join(dirpath, name))
        shutil.copy2(os.path.join(tex_src, "NOTICE.md"), os.path.join(out, "NOTICE-OpenMap.md"))
        shutil.copy2(os.path.join(src, "LICENSE.txt"), os.path.join(out, "LICENSE-OpenMap.txt"))

        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M") + " UTC"
        # Here-strings in this script are LF, and the newline before the closing
        # "@ is not part of the string. Data file names are joined with CRLF.
        data_lines = "\r\n".join(f"Data\\{name}.lua" for name in DATA)
        toc = (
            f"## Interface: {iface}\n"
            "## Title: |cffd4a94eDave's|r Map (textures)\n"
            f"## Notes: OpenMap's stitched world map art and tables for Dave's Map (OpenMap {om_version}), "
            f"built on this machine by daves_map\\tools\\Update-MapTextures.py ({stamp}). Not in git.\n"
            "## Author: generated (OpenMap contributors; map art is Blizzard's)\n"
            f"## Version: {om_version}\n"
            "## X-License: MIT (OpenMap's tables, LICENSE-OpenMap.txt); map art is Blizzard's (NOTICE-OpenMap.md)\n"
            "## IconTexture: Interface\\Icons\\INV_Misc_Map_01\n"
            "\n"
            f"{data_lines}\n"
            "Export.lua"
        )
        export = (
            "-- daves_map_textures / Export.lua -- GENERATED by daves_map\\tools\\Update-MapTextures.py. Do not edit; do not commit.\n"
            "-- The data files above filled this addon's namespace (ns.MapReveal, ns.MapPlaces ...). daves_map (## OptionalDeps)\n"
            "-- takes it as its stitched map's namespace (daves_map\\Stitch\\Base.lua). Its textures are under Media\\.\n"
            "local ADDON, ns = ...\n"
            "ns.texturesAddon = ADDON\n"
            f'ns.openMapVersion = "{om_version}"\n'
            f'ns.built = "{stamp}"\n'
            "DAVES_MAP_TEXTURES = ns"
        )
        with open(os.path.join(out, "daves_map_textures.toc"), "w", encoding="utf-8", newline="") as handle:
            handle.write(toc)
        with open(os.path.join(out, "Export.lua"), "w", encoding="utf-8", newline="") as handle:
            handle.write(export)
        left = ", ".join(EXCLUDE)
        print(
            f"Built {out}: OpenMap {om_version}, {len(DATA)} data tables, {n0(copied)} textures "
            f"({n0(total / 1048576)} MB). Left out: {left}.",
            flush=True,
        )

        if make_zip:
            zip_path = os.path.join(os.path.dirname(out), "daves_map_textures.zip")
            if os.path.exists(zip_path):
                os.remove(zip_path)
            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for dirpath, _dirs, files in os.walk(out):
                    for name in files:
                        full = os.path.join(dirpath, name)
                        rel = "daves_map_textures/" + os.path.relpath(full, out).replace("\\", "/")
                        archive.write(full, rel)
            print(
                f"Shareable copy: {zip_path} ({n0(os.path.getsize(zip_path) / 1048576)} MB). "
                "Unzip into World of Warcraft\\_classic_beta_\\Interface\\AddOns, restart the client.",
                flush=True,
            )
        print("First time on this machine: link it into the game, then restart the client fully:", flush=True)
        print(
            f'  py -3 <kit>\\scripts\\Link-WowAddons.py -Path "{out}"',
            flush=True,
        )
    finally:
        if temp and os.path.isdir(temp):
            shutil.rmtree(temp)


def main(argv):
    source = None
    make_zip = False
    i = 0
    while i < len(argv):
        token = argv[i]
        key = token[1:].lower() if token.startswith("-") else ""
        if key == "zip":
            make_zip = True
        elif key == "source":
            if i + 1 >= len(argv):
                print("Missing value for -Source", file=sys.stderr, flush=True)
                raise SystemExit(1)
            i += 1
            source = argv[i]
        elif key.startswith("source:"):
            source = token.split(":", 1)[1]
        elif token.startswith("-"):
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        else:
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        i += 1
    addon_dir, repo = paths_from_script(__file__)
    try:
        build(source, addon_dir, repo, make_zip)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
