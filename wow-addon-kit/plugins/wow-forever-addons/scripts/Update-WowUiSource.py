"""Keep a local copy of one branch of Blizzard's UI source.

The download hits GitHub. Pass -OutDir so a run does not replace data\\ui-source.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.request
import zipfile
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit

REPO = "Gethe/wow-ui-source"
BRANCHES = ("forever",)
FUNC_RX = re.compile(r"^\s*function\s+([A-Za-z_][\w.]*)([:.])?(\w+)?\s*\(")
XML_RX = re.compile(r'<(\w+)\s[^>]*?\bname="([^"$]+)"[^>]*>')


def _get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "wow-forever-addons-plugin"})
    with urllib.request.urlopen(request) as response:
        return response.read()


def index_zip(zip_path, dest):
    """Extract Interface lua/xml/toc files and return (file_count, index_rows)."""
    if os.path.isdir(dest):
        import shutil
        shutil.rmtree(dest)
    os.makedirs(dest, exist_ok=True)
    rows = []
    count = 0
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            full = info.filename.replace("\\", "/")
            marker = "/Interface/"
            at = full.find(marker)
            if at < 0 or full.endswith("/"):
                continue
            ext = os.path.splitext(full)[1].lower()
            if ext not in (".lua", ".xml", ".toc"):
                continue
            rel = full[at + 1:]
            target = os.path.join(dest, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with zf.open(info) as src, open(target, "wb") as dst:
                dst.write(src.read())
            count += 1
            if ext == ".toc":
                continue
            # ReadAllLines splits on newlines and drops the line ending.
            text = open(target, "r", encoding="utf-8-sig", newline="").read()
            lines = text.split("\n")
            if lines and lines[-1] == "" and text.endswith("\n"):
                lines = lines[:-1]
            # A trailing CR from CRLF stays on the line the way .NET ReadAllLines does not.
            lines = [line[:-1] if line.endswith("\r") else line for line in lines]
            for number, line in enumerate(lines, start=1):
                if ext == ".lua":
                    match = FUNC_RX.match(line)
                    if not match:
                        continue
                    if match.group(3):
                        name = match.group(1) + match.group(2) + match.group(3)
                        kind = "method"
                    elif "." in match.group(1):
                        name = match.group(1)
                        kind = "method"
                    else:
                        name = match.group(1)
                        kind = "function"
                    rows.append(f"{name}\t{kind}\t{rel}:{number}")
                else:
                    for match in XML_RX.finditer(line):
                        kind = "template" if re.search(r'\bvirtual="true"', match.group(0), re.I) else "frame"
                        rows.append(f"{match.group(2)}\t{kind}\t{rel}:{number}")
    rows.sort(key=str.lower)
    index_path = os.path.join(dest, "INDEX.tsv")
    with open(index_path, "w", encoding="utf-8", newline="") as handle:
        handle.write("name\tkind\tlocation\r\n")
        for row in rows:
            handle.write(row + "\r\n")
    return count, rows


def write_source_txt(dest, branch, sha, count, row_count):
    lines = [
        f"repo:     https://github.com/{REPO}",
        f"branch:   {branch}",
        f"commit:   {sha}",
        f"fetched:  {datetime.now().strftime('%Y-%m-%d')}",
        f"files:    {count} (.lua .xml .toc under Interface/)",
        f"index:    {row_count} definitions in INDEX.tsv",
    ]
    path = os.path.join(dest, "SOURCE.txt")
    # Set-Content -Encoding utf8 writes a BOM and CRLF.
    with open(path, "w", encoding="utf-8-sig", newline="") as handle:
        handle.write("\r\n".join(lines) + "\r\n")


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Branch", "value", "forever"),
        ("OutDir", "value", None),
    ])
    branch = args["Branch"]
    if branch not in BRANCHES:
        wowkit.die(f"Unknown branch '{branch}'. Use: {', '.join(BRANCHES)}")
    out_root = args["OutDir"] or str(wowkit.KIT_ROOT / "data" / "ui-source")
    wowkit.host(f"Resolving branch '{branch}' of {REPO}...")
    sha = json.loads(_get(f"https://api.github.com/repos/{REPO}/branches/{branch}"))["commit"]["sha"]
    zip_path = os.path.join(os.environ.get("TEMP") or ".", f"wow-ui-source-{sha[:12]}.zip")
    if not os.path.isfile(zip_path):
        wowkit.host(f"Downloading {branch} @ {sha[:10]} ...")
        data = _get(f"https://codeload.github.com/{REPO}/zip/{sha}")
        with open(zip_path, "wb") as handle:
            handle.write(data)
    dest = os.path.join(out_root, branch)
    count, rows = index_zip(zip_path, dest)
    write_source_txt(dest, branch, sha, count, len(rows))
    wowkit.host(f"Wrote {count} files and {len(rows)} index rows to {dest}")
    raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])
