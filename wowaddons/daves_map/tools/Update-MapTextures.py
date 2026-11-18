"""Build the companion addon wowaddons/daves_map_textures from a local OpenMap release.

Nothing is downloaded. Reads a local OpenMap WoW Forever release folder or .zip
(defaulting to <repo>/OpenMap) and writes wowaddons/daves_map_textures:
  - daves_map_textures.toc, Init.lua, Export.lua, .luacheckrc
  - Data/*.lua (OpenMap's declarative data tables)
  - Media/Textures/* (excluding MapChart, MapGapFill, MapZones)
  - NOTICE-OpenMap.md & LICENSE-OpenMap.txt
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
    "ArtEdits", "Banners", "Caves", "CaveMinimap",
    "DungeonMaps", "DungeonDrawn", "DungeonMinimap", "DungeonBosses",
    "Gaps", "GapPlaces", "Grade",
    "Labels", "Minimap", "MinimapLOD", "Places", "Reveal", "Tones",
)
EXCLUDE = ("MapChart", "MapGapFill", "MapZones")
CODE_RX = re.compile(r"\bfunction\b|\bloadstring\b|\bsetfenv\b|_G\b", re.I)
DANGEROUS_RX = re.compile(r"\bloadstring\b|\bsetfenv\b|_G\b", re.I)
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
    out = os.path.join(os.path.dirname(addon_dir), "daves_map_textures")
    return addon_dir, repo, out


def build(source, addon_dir, repo, out_dir):
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

        data_src = os.path.join(src, "Data", "Forever")
        if not os.path.isdir(data_src):
            data_src = os.path.join(src, "Data")
        tex_src = os.path.join(src, "Media", "Textures", "Forever")
        if not os.path.isdir(tex_src):
            tex_src = os.path.join(src, "Media", "Textures")

        data_names = list(DATA)
        tiles_src = os.path.join(data_src, "Tiles.lua")
        if os.path.isfile(tiles_src):
            data_names.append("Tiles")

        for name in DATA:
            path = os.path.join(data_src, name + ".lua")
            if not os.path.isfile(path):
                rel_path = os.path.relpath(path, src)
                raise RuntimeError(
                    f"OpenMap {om_version} has no {rel_path}: "
                    "daves_map\\Stitch needs updating to this release."
                )
            if CODE_RX.search(_read(path)):
                rel_path = os.path.relpath(path, src)
                raise RuntimeError(
                    f"{rel_path} in OpenMap {om_version} holds code, not just tables: "
                    "check it before using it."
                )
        if os.path.isfile(tiles_src) and DANGEROUS_RX.search(_read(tiles_src)):
            raise RuntimeError(f"Data\\Tiles.lua in OpenMap {om_version} holds unsafe globals.")

        if os.path.isdir(out_dir):
            shutil.rmtree(out_dir)
        data_out = os.path.join(out_dir, "Data")
        tex_out = os.path.join(out_dir, "Media", "Textures")
        os.makedirs(data_out, exist_ok=True)
        os.makedirs(tex_out, exist_ok=True)

        for name in data_names:
            shutil.copy2(
                os.path.join(data_src, name + ".lua"),
                os.path.join(data_out, name + ".lua"),
            )

        excluded = {name.casefold() for name in EXCLUDE}
        for item in os.listdir(tex_src):
            if item.casefold() in excluded or _same_name(item, "NOTICE.md"):
                continue
            src_item = os.path.join(tex_src, item)
            dest_item = os.path.join(tex_out, item)
            if os.path.isdir(src_item):
                shutil.copytree(src_item, dest_item)
            else:
                shutil.copy2(src_item, dest_item)

        copied = 0
        total = 0
        for dirpath, _dirs, files in os.walk(tex_out):
            for name in files:
                copied += 1
                total += os.path.getsize(os.path.join(dirpath, name))

        shutil.copy2(os.path.join(tex_src, "NOTICE.md"), os.path.join(out_dir, "NOTICE-OpenMap.md"))
        shutil.copy2(os.path.join(src, "LICENSE.txt"), os.path.join(out_dir, "LICENSE-OpenMap.txt"))
        shutil.copy2(os.path.join(src, "LICENSE.txt"), os.path.join(addon_dir, "Stitch", "LICENSE-OpenMap.txt"))

        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M") + " UTC"
        toc_data_lines = "\n".join(f"Data\\{name}.lua" for name in data_names)
        toc_ver = om_version.lstrip("vV") or om_version
        toc_content = (
            f"## Interface: {iface}\n"
            "## Title: |cffd4a94eDave's|r Map (textures)\n"
            "## Notes: OpenMap's seamless world map and dungeon map art and tables for Dave's Map.\n"
            "## Author: davidwhit5 (OpenMap: MIT, LICENSE-OpenMap.txt; map art: Blizzard, NOTICE-OpenMap.md)\n"
            f"## Version: {toc_ver}\n"
            "## IconTexture: Interface\\Icons\\INV_Misc_Map_01\n"
            "\n"
            "Init.lua\n"
            f"{toc_data_lines}\n"
            "Export.lua\n"
        )
        with open(os.path.join(out_dir, "daves_map_textures.toc"), "w", encoding="utf-8", newline="\n") as handle:
            handle.write(toc_content)

        init_lua = (
            "-- daves_map_textures / Init.lua -- GENERATED by daves_map\\tools\\Update-MapTextures.py.\n"
            "local ADDON, ns = ...\n"
            'ns.Client = "Forever"\n'
            'ns.Media = { path = "Interface\\\\AddOns\\\\" .. ADDON .. "\\\\Media\\\\" }\n'
            'ns.Media.tex = ns.Media.path .. "Textures\\\\"\n'
        )
        with open(os.path.join(out_dir, "Init.lua"), "w", encoding="utf-8", newline="\n") as handle:
            handle.write(init_lua)

        export_lua = (
            "-- daves_map_textures / Export.lua -- GENERATED by daves_map\\tools\\Update-MapTextures.py.\n"
            "local ADDON, ns = ...\n"
            'ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"\n'
            "ns.texturesAddon = ADDON\n"
            f'ns.openMapVersion = "{om_version}"\n'
            f'ns.built = "{stamp}"\n'
            "DAVES_MAP_TEXTURES = ns\n"
        )
        with open(os.path.join(out_dir, "Export.lua"), "w", encoding="utf-8", newline="\n") as handle:
            handle.write(export_lua)

        luacheck_rc = (
            'std = "lua51"\n'
            "max_line_length = false\n"
            "codes = true\n"
            'exclude_files = { "Data/" }\n'
            'ignore = { "113", "143", "212", "542" }\n'
            'globals = { "DAVES_MAP_TEXTURES" }\n'
        )
        with open(os.path.join(out_dir, ".luacheckrc"), "w", encoding="utf-8", newline="\n") as handle:
            handle.write(luacheck_rc)

        # Clean up any temporary bundled Stitch/Data or Media/Textures inside daves_map
        for stale_dir in (
            os.path.join(addon_dir, "Stitch", "Data"),
            os.path.join(addon_dir, "Media", "Textures"),
        ):
            if os.path.isdir(stale_dir):
                shutil.rmtree(stale_dir)
        stale_notice = os.path.join(addon_dir, "Stitch", "NOTICE-OpenMap.md")
        if os.path.isfile(stale_notice):
            os.remove(stale_notice)

        left = ", ".join(EXCLUDE)
        print(
            f"Wrote {out_dir}: OpenMap {om_version}, {len(data_names)} data tables, "
            f"{n0(copied)} textures ({n0(total / 1048576)} MB). Left out: {left}.",
            flush=True,
        )
    finally:
        if temp and os.path.isdir(temp):
            shutil.rmtree(temp)


def main(argv):
    source = None
    i = 0
    while i < len(argv):
        token = argv[i]
        key = token[1:].lower() if token.startswith("-") else ""
        if key == "source":
            if i + 1 >= len(argv):
                print("Missing value for -Source", file=sys.stderr, flush=True)
                raise SystemExit(1)
            i += 1
            source = argv[i]
        elif key.startswith("source:"):
            source = token.split(":", 1)[1]
        else:
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        i += 1
    addon_dir, repo, out_dir = paths_from_script(__file__)
    try:
        build(source, addon_dir, repo, out_dir)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
