"""Screenshot concepts/index.html in headless Chrome and print JS errors.

Usage: shot.py -Only skin -Hold 60 -Sim 2 -H 40 -Out skin60.png
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import uuid

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"


def _args(argv):
    out = {"Only": "", "Hold": "60", "Sim": "2", "H": "40", "W": "420", "Out": "shot.png", "Extra": ""}
    i = 0
    while i < len(argv):
        token = argv[i]
        if not token.startswith("-"):
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        raw = token[1:]
        if ":" in raw:
            key, value = raw.split(":", 1)
        else:
            key = raw
            if i + 1 >= len(argv):
                print(f"Missing value for -{key}", file=sys.stderr, flush=True)
                raise SystemExit(1)
            i += 1
            value = argv[i]
        found = next((name for name in out if name.lower() == key.lower()), None)
        if not found:
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        out[found] = value
        i += 1
    return out


def main(argv):
    args = _args(argv)
    directory = os.path.dirname(os.path.abspath(__file__))
    query = f"only={args['Only']}&hold={args['Hold']}&sim={args['Sim']}&h={args['H']}&w={args['W']}"
    if args["Extra"]:
        query += "&" + args["Extra"]
    url = "file:///" + directory.replace("\\", "/") + "/index.html?" + query
    out_path = args["Out"] if os.path.isabs(args["Out"]) else os.path.join(directory, args["Out"])
    tag = uuid.uuid4().hex[:8]
    profile = os.path.join(directory, f".chrome-{tag}")
    dom_file = os.path.join(directory, f".dom-{tag}.txt")
    err_file = dom_file + ".err"
    common = [
        "--headless=new", "--disable-gpu", "--hide-scrollbars",
        f"--user-data-dir={profile}", "--virtual-time-budget=1500",
    ]
    with open(err_file, "w", encoding="utf-8") as err_out:
        subprocess.run(
            [CHROME, *common, "--window-size=1000,1100", f"--screenshot={out_path}", url],
            stderr=err_out,
            check=False,
        )
    with open(dom_file, "w", encoding="utf-8") as dom_out, open(err_file, "w", encoding="utf-8") as err_out:
        subprocess.run([CHROME, *common, "--dump-dom", url], stdout=dom_out, stderr=err_out, check=False)
    dom = ""
    if os.path.isfile(dom_file):
        with open(dom_file, "r", encoding="utf-8", errors="replace") as handle:
            dom = handle.read()
    shutil.rmtree(profile, ignore_errors=True)
    for path in (dom_file, err_file):
        if os.path.isfile(path):
            try:
                os.remove(path)
            except OSError:
                pass
    match = re.search(r'<div id="errors">([^<]*)</div>', dom)
    if match:
        text = match.group(1).strip()
        print(f"JS ERRORS: {text}" if text else "no JS errors", flush=True)
    else:
        print("could not read the page", flush=True)
    print(f"Screenshot: {out_path}", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
