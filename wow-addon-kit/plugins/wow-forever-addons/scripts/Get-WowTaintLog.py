"""Read the WoW client's taint log."""

from __future__ import annotations

import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowkit


def main(argv):
    args = wowkit.parse_ps_args(argv, [
        ("Flavor", "value", "forever"),
        ("Addon", "value", None),
        ("Last", "value", "10"),
        ("Root", "value", None),
    ])
    root = args["Root"] or wowkit.wow_root()
    if not root:
        wowkit.warn('World of Warcraft was not found. Pass -Root "D:\\Games\\World of Warcraft".')
        raise SystemExit(1)
    clients = [c for c in wowkit.wow_install(root) if c.Flavor == args["Flavor"]]
    if not clients:
        wowkit.warn(f"No '{args['Flavor']}' client installed under {root}.")
        raise SystemExit(1)
    client = clients[0]
    log = os.path.join(root, client.Folder, "Logs", "taint.log")
    if not os.path.isfile(log):
        wowkit.host(f"No taint log at {log}")
        wowkit.host("In game: /console taintLog 1, reproduce the problem, then /reload (or log out) so the log is written.")
        raise SystemExit(0)
    # The game keeps taint.log open. Share the read the way the PowerShell script does.
    with open(log, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    events = []
    current = None
    for line in text.splitlines():
        header = re.match(r"^(\S+ \S+)  (\S.*)$", line)
        if header:
            current = {"Time": header.group(1), "Text": header.group(2), "Stack": []}
            events.append(current)
        elif current:
            stack = re.match(r"^\S+ \S+\s{3,}(\S.*)$", line)
            if stack:
                current["Stack"].append(stack.group(1))
    written = datetime_text(log)
    wowkit.host(f"Taint log: {log} (written {written})")
    # -match is case-insensitive.
    if args["Addon"]:
        events = [event for event in events if re.search(re.escape(args["Addon"]), event["Text"], re.I)]
    if not events:
        wowkit.host("No matching events.")
        raise SystemExit(0)
    wowkit.host(f"\n{len(events)} event(s). Summary:")
    counts = Counter(re.sub(r"\(<table: [0-9a-fA-F]+>\)", "(<table>)", event["Text"]) for event in events)
    for text, count in counts.most_common():
        wowkit.host(f"  {count:3}x  {text}")
    last = int(args["Last"])
    shown = events[-last:] if last else []
    wowkit.host(f"\nLast {min(last, len(events))} event(s), oldest first:")
    for event in shown:
        wowkit.host(f"\n{event['Time']}  {event['Text']}")
        for stack in event["Stack"]:
            wowkit.host(f"    {stack}")
    wowkit.host("\nNext: open each stack file:line in data/ui-source/forever and find who wrote the value named after 'while reading'.")
    wowkit.host("If Blizzard wrote it moments earlier in the same call, the taint came in before that: check what that call path read, and which of that state the addon touches.")
    raise SystemExit(0)


def datetime_text(path):
    import datetime
    stamp = os.path.getmtime(path)
    return datetime.datetime.fromtimestamp(stamp).strftime("%Y-%m-%d %H:%M")


if __name__ == "__main__":
    main(sys.argv[1:])
