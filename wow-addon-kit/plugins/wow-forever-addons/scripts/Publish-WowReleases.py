"""Build clean <addon>.zip packages for all tracked addons and update the orphan 'releases' branch."""

from __future__ import annotations

import fnmatch
import os
import re
import subprocess
import sys
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit

REPO_ROOT = os.path.abspath(os.path.join(wowkit.KIT_ROOT, "..", "..", ".."))
ADDONS_ROOT = os.path.join(REPO_ROOT, "wowaddons")

EXCLUDE_DIRS = {".git", ".vscode", "tests", "tools", "__pycache__", ".release", "guides"}
EXCLUDE_FILES = [".luacheckrc", ".pkgmeta", ".gitignore", "README.md", "NOTES.md", "*.zip", "*.bak"]
SKIP_ADDONS = {"ForeverLoot", "daves_map_data", "daves_map_textures"}
ZIP_TIMESTAMP = (2026, 1, 1, 0, 0, 0)


def _excluded_dir(name: str) -> bool:
    return name.casefold() in EXCLUDE_DIRS


def _excluded_file(name: str) -> bool:
    return any(fnmatch.fnmatch(name, pat) for pat in EXCLUDE_FILES)


def read_toc_meta(toc_path: str) -> dict[str, str]:
    meta: dict[str, str] = {}
    with open(toc_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"^##\s*([A-Za-z0-9_-]+)\s*:\s*(.+?)\s*$", line)
            if m:
                val = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", m.group(2)).strip()
                meta[m.group(1)] = val
    return meta


def discover_addons(addons_root: str) -> list[tuple[str, str, dict[str, str]]]:
    found: list[tuple[str, str, dict[str, str]]] = []
    if not os.path.isdir(addons_root):
        return found
    for name in sorted(os.listdir(addons_root)):
        if name in SKIP_ADDONS or name.startswith("."):
            continue
        addon_dir = os.path.join(addons_root, name)
        toc_path = os.path.join(addon_dir, f"{name}.toc")
        if os.path.isdir(addon_dir) and os.path.isfile(toc_path):
            found.append((name, addon_dir, read_toc_meta(toc_path)))
    return found


def build_addon_zip(name: str, addon_dir: str, dest_zip: str) -> tuple[int, int]:
    file_count = 0
    with zipfile.ZipFile(dest_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for dirpath, dirnames, filenames in os.walk(addon_dir):
            dirnames[:] = sorted(d for d in dirnames if not _excluded_dir(d))
            for fname in sorted(filenames):
                if _excluded_file(fname):
                    continue
                full_path = os.path.join(dirpath, fname)
                rel_path = os.path.relpath(full_path, addon_dir).replace("\\", "/")
                arcname = f"{name}/{rel_path}"
                info = zipfile.ZipInfo(arcname, date_time=ZIP_TIMESTAMP)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                with open(full_path, "rb") as src_file:
                    zf.writestr(info, src_file.read(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=6)
                file_count += 1
    return file_count, os.path.getsize(dest_zip)


def format_size(num_bytes: int) -> str:
    if num_bytes >= 1024 * 1024:
        return f"{num_bytes / (1024 * 1024):.2f} MB"
    return f"{num_bytes / 1024:.1f} KB"


def build_releases_readme(entries: list[dict[str, str]], main_sha: str) -> str:
    lines = [
        "# Dave's WoW: Forever Addons — Releases",
        "",
        f"Ready-to-install `.zip` packages built from `main` (`{main_sha}`) for **WoW: Forever** (`Interface 16001`).",
        "",
        "## Install",
        "",
        "1. Click any `.zip` below and download it.",
        "2. Extract it into `World of Warcraft\\_forever_\\Interface\\AddOns\\` so the folder sits at `Interface\\AddOns\\<addon_name>\\`.",
        "3. Fully restart the WoW: Forever client (or `/reload` when updating Lua-only changes).",
        "",
        "## Addons",
        "",
        "| Addon | Version | Download | Size | Description |",
        "| --- | --- | --- | --- | --- |",
    ]
    for e in entries:
        lines.append(
            f"| **{e['title']}** (`{e['name']}`) | `v{e['version']}` | [`{e['zip_name']}`]({e['zip_name']}) | {e['size']} | {e['notes']} |"
        )
    lines.extend([
        "",
        "> **Note for `daves_map`:** Map Genie pin data (`daves_map_data.zip`) and seamless map art (`daves_map_textures.zip`) are distributed separately.",
        "",
    ])
    return "\n".join(lines)


def run_git(args: list[str], input_text: str | None = None) -> str:
    proc = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        input=input_text.encode("utf-8") if input_text is not None else None,
        capture_output=True,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout).decode("utf-8", errors="replace").strip()
        wowkit.die(f"git {' '.join(args)} failed: {err}")
    return proc.stdout.decode("utf-8", errors="replace").strip()


def main(argv: list[str]) -> None:
    args = wowkit.parse_ps_args(argv, [
        ("Branch", "value", "releases"),
        ("Remote", "value", "origin"),
        ("OutputDir", "value", None),
        ("Push", "switch", False),
        ("WhatIf", "switch", False),
    ])
    branch = args["Branch"]
    remote = args["Remote"]
    out_dir = os.path.abspath(args["OutputDir"]) if args["OutputDir"] else None

    addons = discover_addons(ADDONS_ROOT)
    if not addons:
        wowkit.die(f"No addons found in {ADDONS_ROOT}")

    main_sha = run_git(["rev-parse", "--short", "HEAD"])

    if args["WhatIf"]:
        for name, _, meta in addons:
            ver = meta.get("Version", "dev")
            wowkit.host(f"[WhatIf] Would package {name}.zip (v{ver})")
        wowkit.host(f"[WhatIf] Would update orphan branch '{branch}' from HEAD {main_sha}" + (f" and push to {remote}" if args["Push"] else ""))
        return

    with tempfile.TemporaryDirectory(prefix="wow-releases-") as tmp_dir:
        work_dir = out_dir or tmp_dir
        os.makedirs(work_dir, exist_ok=True)

        entries: list[dict[str, str]] = []
        summary_parts: list[str] = []
        built_files: list[tuple[str, str]] = []

        for name, addon_dir, meta in addons:
            zip_name = f"{name}.zip"
            zip_path = os.path.join(work_dir, zip_name)
            count, size_bytes = build_addon_zip(name, addon_dir, zip_path)
            ver = meta.get("Version", "dev")
            size_str = format_size(size_bytes)
            wowkit.host(f"Packed {zip_name} (v{ver}, {count} files, {size_str})")
            entries.append({
                "name": name,
                "title": meta.get("Title", name),
                "version": ver,
                "zip_name": zip_name,
                "size": size_str,
                "notes": meta.get("Notes", ""),
            })
            summary_parts.append(f"{name} v{ver}")
            built_files.append((zip_name, zip_path))

        readme_path = os.path.join(work_dir, "README.md")
        with open(readme_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(build_releases_readme(entries, main_sha))
        built_files.append(("README.md", readme_path))

        if out_dir:
            wowkit.host(f"Wrote {len(entries)} addon zip(s) and README.md to {out_dir}")
            return

        tree_lines: list[str] = []
        for fname, fpath in sorted(built_files, key=lambda x: x[0]):
            blob_sha = run_git(["hash-object", "-w", "--no-filters", fpath])
            tree_lines.append(f"100644 blob {blob_sha}\t{fname}")

        tree_sha = run_git(["mktree"], input_text="\n".join(tree_lines) + "\n")
        commit_msg = f"Releases ({main_sha}): " + ", ".join(summary_parts)
        commit_sha = run_git(["commit-tree", tree_sha, "-m", commit_msg])
        run_git(["update-ref", f"refs/heads/{branch}", commit_sha])
        wowkit.host(f"Updated orphan branch '{branch}' -> {commit_sha[:7]} ({commit_msg})")

        if args["Push"]:
            run_git(["push", "--force", remote, f"refs/heads/{branch}:refs/heads/{branch}"])
            wowkit.host(f"Pushed '{branch}' to {remote}/{branch}")


if __name__ == "__main__":
    main(sys.argv[1:])
