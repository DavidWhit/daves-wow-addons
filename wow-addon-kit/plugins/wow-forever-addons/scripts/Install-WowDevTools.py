"""Install luacheck and refresh the Forever API index. Matches Install-WowDevTools.ps1."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import urllib.request
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit


def _download(url, dest):
    request = urllib.request.Request(url, headers={"User-Agent": "wow-forever-addons-plugin"})
    with urllib.request.urlopen(request) as response, open(dest, "wb") as handle:
        handle.write(response.read())


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("LuacheckVersion", "value", "v1.2.0"),
        ("SkipApiIndex", "switch", False),
        ("Force", "switch", False),
    ])
    version = args["LuacheckVersion"]
    bindir = wowkit.tool_dir()
    exe = bindir / "luacheck.exe"
    if exe.is_file() and not args["Force"]:
        wowkit.host(f"luacheck already installed: {exe}")
    else:
        bindir.mkdir(parents=True, exist_ok=True)
        api = f"https://api.github.com/repos/lunarmodules/luacheck/releases/tags/{version}"
        request = urllib.request.Request(api, headers={"User-Agent": "wow-forever-addons-plugin"})
        with urllib.request.urlopen(request) as response:
            import json
            release = json.load(response)
        asset = next((item for item in release.get("assets") or [] if item.get("name") == "luacheck.exe"), None)
        if not asset:
            wowkit.die(f"Release {version} has no luacheck.exe asset.")
        wowkit.host(f"Downloading {asset['browser_download_url']}")
        _download(asset["browser_download_url"], exe)
        if exe.stat().st_size != asset["size"]:
            exe.unlink()
            wowkit.die("Download size does not match the release asset; removed.")
        digest = hashlib.sha256(exe.read_bytes()).hexdigest().upper()
        wowkit.host(f"luacheck installed: {exe}  (SHA256 {digest})")
    subprocess.run([str(exe), "--version"])

    if not args["SkipApiIndex"]:
        index = wowkit.KIT_ROOT / "data" / "api-forever.json"
        fresh = False
        if index.is_file() and not args["Force"]:
            age = datetime.now() - datetime.fromtimestamp(index.stat().st_mtime)
            fresh = age.total_seconds() < 7 * 86400
        if fresh:
            wowkit.host(f"Forever API index is fresh: {index}")
        else:
            updater = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Update-WowApiIndex.py")
            subprocess.run([sys.executable, updater, "-Branch", "forever"], check=False)

    wowkit.host("")
    wowkit.host("Recommended editor setup (optional):")
    wowkit.host("  code --install-extension ketho.wow-api   # WoW API IntelliSense for VS Code (LuaLS)")
    raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
