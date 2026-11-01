"""Rebuild wowaddons/daves_map_data from Map Genie and pfQuest.

Matches Update-MapData.ps1. Downloads are data: JSON and Lua literals only,
https on mapgenie.io and raw.githubusercontent.com, 64 MB cap. Nothing fetched
is executed. Do not commit daves_map_data or its zip.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import shutil
import ssl
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from datetime import datetime, timezone
from decimal import ROUND_HALF_EVEN, Decimal
from urllib.parse import urlparse

ALLOWED_HOSTS = ("mapgenie.io", "raw.githubusercontent.com")
MAX_BYTES = 64 * 1048576
UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
)
GOLD = "|cffffd200"
CLASSES = ("warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid")
TAG_FACTION = {"alliance": 1, "horde": 2, "neutral": 3}
ALLIANCE_RACES = 1 + 4 + 8 + 64
HORDE_RACES = 2 + 16 + 32 + 128
IFACE_RX = re.compile(r"(?m)^## Interface:\s*(.+?)\s*$")
REF_RX = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$")


def n0(value):
    """PowerShell {0:N0} on en-US: half away from zero, thousands commas."""
    number = int(value + 0.5) if value >= 0 else int(value - 0.5)
    return f"{number:,}"


def ps_round(value, digits):
    """[Math]::Round(x, digits) on .NET Framework: half to even, one decimal in practice.

    Rounding the shortest decimal of the double matches Framework where binary
    round() does not (1.05 to one place is 1, because 0 is even).
    """
    quant = Decimal(1).scaleb(-digits)
    rounded = Decimal(str(float(value))).quantize(quant, rounding=ROUND_HALF_EVEN)
    return float(rounded)


def ps_int(value):
    """PowerShell [int] on a number: halves round to even."""
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return round(value)
    return round(float(value))


def ps_string(value):
    if value is None:
        return ""
    return str(value)


def lua_num(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        raise RuntimeError(f"Not a number for Data.lua: '{value}'") from None
    if math.isnan(number) or math.isinf(number):
        raise RuntimeError(f"Not a number for Data.lua: '{value}'")
    # Double.ToString(invariant) is general format G15, with an uppercase exponent.
    return format(number, ".15g").replace("e", "E")


def lua_str(value):
    text = ps_string(value)
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", " ")
    text = re.sub(r"[\x00-\x1f\x7f]", "", text)
    return '"' + text + '"'


def num_list(values):
    return "{" + ",".join(lua_num(item) for item in values) + "}"


def clean_text(value):
    if not value:
        return ""
    text = str(value).replace("\r", "")
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"\{\{[^}]*\}\}\s*", "", text)
    text = re.sub(r"\*\*([^*]+?):\*\*", GOLD + r"\1:|r", text)
    text = re.sub(r"\*\*([^*]+?)\*\*", r"\1", text)
    text = re.sub(r"\|(?!c[0-9a-fA-F]{8}|r)", "||", text, flags=re.I)
    text = re.sub(r"\n{2,}", "\n", text)
    return text.strip()


def norm(value):
    return re.sub(r"[^a-z0-9]+", " ", (value or "").lower()).strip()


def to_pixel(lat, lng, world, min_tx, min_ty):
    x = (lng + 180.0) / 360.0 * world - min_tx * 256.0
    phi = lat * math.pi / 180.0
    y = (1.0 - math.log(math.tan(phi) + 1.0 / math.cos(phi)) / math.pi) / 2.0 * world - min_ty * 256.0
    return (ps_round(x, 1), ps_round(y, 1))


class LuaLiteral:
    """pfQuest's `name = { ... }` files. Tables, strings, numbers, true, false, nil."""

    MAX_DEPTH = 64

    def parse_assigned(self, text):
        eq = text.find("=")
        start = text.find("{", 0 if eq < 0 else eq)
        if start < 0:
            raise ValueError("no table literal")
        self.depth = 0
        self.text = text
        self.pos = start
        return self._value()

    def _skip(self):
        s = self.text
        p = self.pos
        while p < len(s):
            c = s[p]
            if c.isspace():
                p += 1
                continue
            if c == "-" and p + 1 < len(s) and s[p + 1] == "-":
                while p < len(s) and s[p] != "\n":
                    p += 1
                continue
            break
        self.pos = p

    def _value(self):
        self._skip()
        s = self.text
        if self.pos >= len(s):
            raise ValueError("unexpected end")
        c = s[self.pos]
        if c == "{":
            return self._table()
        if c in "\"'":
            return self._str()
        if c == "-" or c == "." or c.isdigit():
            return self._num()
        if s.startswith("true", self.pos):
            self.pos += 4
            return True
        if s.startswith("false", self.pos):
            self.pos += 5
            return False
        if s.startswith("nil", self.pos):
            self.pos += 3
            return None
        raise ValueError(f"unexpected '{c}' at {self.pos}")

    def _table(self):
        table = {}
        self.pos += 1
        self.depth += 1
        if self.depth > self.MAX_DEPTH:
            raise ValueError(f"tables nested deeper than {self.MAX_DEPTH} at {self.pos}")
        n = 1
        s = self.text
        while True:
            self._skip()
            if self.pos >= len(s):
                raise ValueError("unexpected end")
            if s[self.pos] == "}":
                self.pos += 1
                self.depth -= 1
                return table
            key = None
            if s[self.pos] == "[":
                self.pos += 1
                key = self._value()
                self._skip()
                if self.pos >= len(s) or s[self.pos] != "]":
                    raise ValueError(f"']' expected at {self.pos}")
                self.pos += 1
                self._skip()
                if self.pos >= len(s) or s[self.pos] != "=":
                    raise ValueError(f"'=' expected at {self.pos}")
                self.pos += 1
            elif s[self.pos].isalpha() or s[self.pos] == "_":
                q = self.pos
                while q < len(s) and (s[q].isalnum() or s[q] == "_"):
                    q += 1
                saved = self.pos
                self.pos = q
                self._skip()
                r = self.pos
                if r < len(s) and s[r] == "=" and (r + 1 >= len(s) or s[r + 1] != "="):
                    key = s[saved:q]
                    self.pos = r + 1
                else:
                    self.pos = saved
            value = self._value()
            if key is None:
                key = n
                n += 1
            if isinstance(key, float) and key == math.floor(key) and abs(key) < 9e15:
                key = int(key)
            if value is not None:
                table[key] = value
            self._skip()
            if self.pos < len(s) and s[self.pos] in ",;":
                self.pos += 1

    def _num(self):
        s = self.text
        q = self.pos
        if s[q] == "-":
            q += 1
        while q < len(s) and (
            s[q].isdigit() or s[q] == "." or s[q] in "eE"
            or (s[q] in "-+" and s[q - 1] in "eE")
        ):
            q += 1
        token = s[self.pos:q]
        self.pos = q
        number = float(token)
        if number == math.floor(number) and abs(number) < 9e15:
            return int(number)
        return number

    def _str(self):
        s = self.text
        quote = s[self.pos]
        self.pos += 1
        out = []
        while True:
            if self.pos >= len(s):
                raise ValueError("unterminated string")
            c = s[self.pos]
            self.pos += 1
            if c == quote:
                return "".join(out)
            if c != "\\":
                out.append(c)
                continue
            if self.pos >= len(s):
                raise ValueError("unterminated string")
            esc = s[self.pos]
            self.pos += 1
            mapping = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}
            if esc in mapping:
                out.append(mapping[esc])
            elif esc.isdigit():
                value = ord(esc) - 48
                k = 1
                while k < 3 and self.pos < len(s) and s[self.pos].isdigit():
                    value = value * 10 + (ord(s[self.pos]) - 48)
                    self.pos += 1
                    k += 1
                out.append(chr(value))
            else:
                out.append(esc)


def check_url(url):
    if re.search(r'[\s"]', url or ""):
        raise RuntimeError(f"Refusing -Url '{url}': it must be an https://mapgenie.io/... address.")
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != "mapgenie.io" or not parsed.netloc:
        raise RuntimeError(f"Refusing -Url '{url}': it must be an https://mapgenie.io/... address.")


def check_ref(ref):
    if not ref or not REF_RX.match(ref) or ".." in ref:
        raise RuntimeError(
            f"Refusing -QuestDbRef '{ref}': a branch, tag or commit name only (letters, digits, '.', '_', '-')."
        )


def _allowed(url):
    parsed = urlparse(url)
    return parsed.scheme == "https" and parsed.hostname in ALLOWED_HOSTS


def fetch(url, path, headers, security):
    if not _allowed(url):
        raise RuntimeError(f"Refusing to download {url} (not https on {' / '.join(ALLOWED_HOSTS)}).")
    request_headers = {"User-Agent": UA}
    request_headers.update(headers or {})
    request = urllib.request.Request(url, headers=request_headers)
    redirects = {"n": 0}

    class Handler(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, hdrs, newurl):
            redirects["n"] += 1
            if redirects["n"] > 3:
                raise RuntimeError(f"Download of {url} redirected more than 3 times.")
            return super().redirect_request(req, fp, code, msg, hdrs, newurl)

    context = ssl.create_default_context()
    opener = urllib.request.build_opener(Handler, urllib.request.HTTPSHandler(context=context))
    try:
        with opener.open(request, timeout=120) as response:
            final = response.geturl()
            if not _allowed(final):
                raise RuntimeError(
                    f"Download of {url} was redirected to {final} (not https on an allowed host); stopped before reading it."
                )
            blob = response.read(MAX_BYTES + 1)
    except urllib.error.URLError as exc:
        if os.path.isfile(path):
            os.remove(path)
        raise RuntimeError(f"Download of {url} failed: {exc.reason}") from None
    except RuntimeError:
        if os.path.isfile(path):
            os.remove(path)
        raise
    if len(blob) > MAX_BYTES:
        raise RuntimeError(
            f"Download of {url} is {n0(len(blob) / 1048576)} MB, over the {n0(MAX_BYTES / 1048576)} MB limit; stopped before reading it."
        )
    with open(path, "wb") as handle:
        handle.write(blob)
    if len(blob) == 0:
        raise RuntimeError(f"Download of {url} is empty.")
    digest = hashlib.sha256(blob).hexdigest()
    security.append(f"download: {url} ({n0(len(blob) / 1024)} KB, sha256 {digest})")
    return blob.decode("utf-8-sig")


def map_json(html, page_url):
    i = html.find("window.mapData")
    if i < 0:
        raise RuntimeError(f"window.mapData not found in {page_url} (the page layout changed?)")
    i = html.find("{", i)
    depth = 0
    in_str = False
    esc = False
    j = i
    while j < len(html):
        c = html[j]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            j += 1
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return json.loads(html[i:j + 1])


def _dist2(a, b):
    return (a["x"] - b["x"]) ** 2 + (a["y"] - b["y"]) ** 2


def _nearest(origin, candidates, pins):
    best = 0
    best_d = float("inf")
    for index in candidates:
        dist = _dist2(origin, pins[index - 1])
        if dist < best_d:
            best_d = dist
            best = index
    return best


def _unit_names(side, units):
    names = []
    if isinstance(side, dict) and isinstance(side.get("U"), dict):
        for unit_id in side["U"].values():
            name = units.get(ps_int(unit_id))
            if name:
                names.append(ps_string(name))
    return names


def build_pins(page, data, url):
    tile = page["mapConfig"]["tile_sets"][0]
    world = (2 ** 16) * 256
    bounds = tile["bounds"]["16"]
    min_tx = float(bounds["x"]["min"])
    min_ty = float(bounds["y"]["min"])
    groups = sorted(page["groups"], key=lambda item: ps_int(item["order"]))
    cat_by_id = {ps_int(key): value for key, value in page["categories"].items()}
    cats = []
    cat_index = {}
    group_out = []
    for group in groups:
        members = sorted(group["categories"], key=lambda item: ps_int(item["order"]))
        indexes = []
        for member in members:
            cid = ps_int(member["id"])
            category = cat_by_id.get(cid) or member
            color = category.get("icon_color") or category.get("color")
            cats.append({
                "id": cid,
                "title": ps_string(category.get("title")),
                "icon": ps_string(category.get("icon")),
                "color": ps_string(color),
                "group": len(group_out) + 1,
                "info": ps_string(category.get("info")),
            })
            cat_index[cid] = len(cats)
            indexes.append(len(cats))
        group_out.append({
            "id": ps_int(group["id"]),
            "title": ps_string(group["title"]),
            "color": ps_string(group.get("color")),
            "cats": indexes,
        })
    tag_by_id = {ps_int(tag["id"]): ps_string(tag.get("title")) for tag in (data.get("tags") or [])}
    locations = data.get("locations") or []
    if len(locations) == 0:
        raise RuntimeError("no locations in the map data (the endpoint changed?)")
    pins = []
    pin_by_mg = {}
    for location in locations:
        cid = ps_int(location["category_id"])
        if cid not in cat_index:
            continue
        x, y = to_pixel(float(location["latitude"]), float(location["longitude"]), world, min_tx, min_ty)
        desc = ps_string(location.get("description"))
        fac = 0
        cls = 0
        for tid in location.get("tags") or []:
            title = tag_by_id.get(ps_int(tid))
            folded = title.lower() if title else ""
            if folded in TAG_FACTION:
                fac = TAG_FACTION[folded]
            elif title and title.lower().startswith("class-"):
                # -like is case-insensitive; IndexOf on the original suffix is not.
                name = title[6:]
                k = CLASSES.index(name) if name in CLASSES else -1
                if k >= 0:
                    cls |= 1 << k
        if fac == 0:
            match = re.search(r"\*\*(?:Faction|Side):\*\*\s*(Alliance|Horde|Neutral)", desc, re.I)
            if match:
                fac = TAG_FACTION[match.group(1).lower()]
            else:
                match = re.search(r"\((Alliance|Horde)\)", desc, re.I)
                if match:
                    fac = TAG_FACTION[match.group(1).lower()]
        if cls == 0:
            match = re.search(r"\*\*Required Class:\*\*([^\n]*)", desc, re.I)
            if match:
                for k, name in enumerate(CLASSES):
                    if re.search(rf"\b{name}\b", match.group(1), re.I):
                        cls |= 1 << k
        lvl = 0
        match = re.search(r"\*\*Required Level:\*\*\s*(\d+)", desc, re.I)
        if match:
            lvl = int(match.group(1))
        qs = ""
        match = re.search(r"Start:\s*([^\n]+)", desc, re.I)
        if match:
            qs = match.group(1).strip()
        qe = ""
        match = re.search(r"End:\s*([^\n]+)", desc, re.I)
        if match:
            qe = match.group(1).strip()
        npc = ""
        npc_match = re.search(
            r"^\*\*[^*]+:\*\*\s*([^\n(]+?)\s*(\((?:Alliance|Horde|Neutral)\))?\s*$", desc, re.I
        )
        if npc_match and not re.search(r"Faction:|Side:|Destination:", desc, re.I):
            npc = npc_match.group(1).strip()
        dest = 0
        match = re.search(r"locationIds=(\d+)", desc, re.I)
        if match:
            dest = int(match.group(1))
        pin = {
            "mg": ps_int(location["id"]),
            "cat": cat_index[cid],
            "x": x,
            "y": y,
            "title": ps_string(location.get("title")).strip(),
            "text": clean_text(desc),
            "fac": fac,
            "lvl": lvl,
            "cls": cls,
            "qs": qs,
            "qe": qe,
            "npc": npc,
            "destMg": dest,
            "dest": 0,
            "endp": 0,
            "qid": 0,
            "pre": [],
        }
        pins.append(pin)
        pin_by_mg[pin["mg"]] = len(pins)
    return {
        "url": url,
        "map_title": ps_string(page["map"]["title"]),
        "map_id": ps_int(page["map"]["id"]),
        "groups": group_out,
        "cats": cats,
        "cat_index": cat_index,
        "pins": pins,
        "pin_by_mg": pin_by_mg,
        "tag_by_id": tag_by_id,
    }


def link_pins(model, pf_q=None, pf_t=None, pf_u=None):
    pins = model["pins"]
    npc_at = {}
    for n, pin in enumerate(pins, start=1):
        for name in (pin["qs"], pin["npc"]):
            if not name:
                continue
            key = norm(name)
            npc_at.setdefault(key, []).append(n)
    links = {"dest": 0, "endp": 0, "pre": 0}
    for pin in pins:
        if pin["destMg"] and model["pin_by_mg"].get(pin["destMg"]):
            pin["dest"] = model["pin_by_mg"][pin["destMg"]]
            links["dest"] += 1
    matched = None
    quest_pins = None
    if pf_q is not None:
        by_title = {}
        for qid, quest in pf_q.items():
            title = pf_t.get(qid) if pf_t else None
            if not isinstance(title, dict) or "T" not in title:
                continue
            by_title.setdefault(norm(ps_string(title["T"])), []).append(ps_int(qid))
        pins_by_qid = {}
        matched = 0
        cats = model["cats"]
        for n, pin in enumerate(pins, start=1):
            if not re.search(r"Quest|Repeatable", cats[pin["cat"] - 1]["title"], re.I):
                continue
            candidates = by_title.get(norm(pin["title"]))
            if not candidates:
                continue
            best = None
            best_score = -1
            for qid in candidates:
                quest = pf_q.get(qid) or {}
                score = 0
                starts = _unit_names(quest.get("start"), pf_u)
                if pin["qs"] and any(norm(name) == norm(pin["qs"]) for name in starts):
                    score += 4
                ends = _unit_names(quest.get("end"), pf_u)
                if pin["qe"] and any(norm(name) == norm(pin["qe"]) for name in ends):
                    score += 2
                race = ps_int(quest["race"]) if "race" in quest else 0
                if race and pin["fac"] == 1 and (race & ALLIANCE_RACES):
                    score += 1
                if race and pin["fac"] == 2 and (race & HORDE_RACES):
                    score += 1
                if "min" in quest and pin["lvl"] and ps_int(quest["min"]) == pin["lvl"]:
                    score += 1
                if score > best_score:
                    best_score = score
                    best = qid
            if best is not None and (len(candidates) == 1 or best_score >= 2):
                pin["qid"] = ps_int(best)
                matched += 1
                pins_by_qid.setdefault(pin["qid"], []).append(n)
                if not pin["qe"]:
                    ends = _unit_names((pf_q.get(best) or {}).get("end"), pf_u)
                    if ends:
                        pin["qe"] = ends[0]
        for n, pin in enumerate(pins, start=1):
            if not pin["qid"]:
                continue
            quest = pf_q.get(ps_int(pin["qid"])) or {}
            pre = quest.get("pre")
            if not isinstance(pre, dict):
                continue
            for item in pre.values():
                hits = pins_by_qid.get(ps_int(item))
                if hits:
                    target = _nearest(pin, hits, pins)
                    if target and target != n:
                        pin["pre"].append(target)
                        links["pre"] += 1
        quest_pins = sum(
            1 for pin in pins if re.search(r"Quest|Repeatable", cats[pin["cat"] - 1]["title"], re.I)
        )
    for n, pin in enumerate(pins, start=1):
        if not pin["qe"]:
            continue
        if norm(pin["qe"]) == norm(pin["qs"]):
            continue
        at = npc_at.get(norm(pin["qe"]))
        if at:
            target = _nearest(pin, at, pins)
            if target and target != n:
                pin["endp"] = target
                links["endp"] += 1
    return links, matched, quest_pins


def render(model, stamp, quest_db, out_lua):
    pins = model["pins"]
    lines = [
        "-- daves_map_data / Data.lua -- GENERATED by daves_map/tools/Update-MapData.py. Do not edit; do not commit (Map Genie's data).",
        f"-- Source: {model['url']}  ({stamp})",
        "-- One global, read once by daves_map at its ADDON_LOADED (this addon is its ## OptionalDeps, so it loads first).",
        "DAVES_MAP_DATA = {",
        "source = { url = %s, map = %s, mapId = %s, fetched = %s, questDb = %s }," % (
            lua_str(model["url"]),
            lua_str(model["map_title"]),
            lua_num(model["map_id"]),
            lua_str(stamp),
            lua_str("pfQuest@" + quest_db) if quest_db else "false",
        ),
        "groups = {",
    ]
    for group in model["groups"]:
        lines.append(
            "  { id = %s, title = %s, cats = %s }," % (lua_num(group["id"]), lua_str(group["title"]), num_list(group["cats"]))
        )
    lines.append("},")
    lines.append("cats = {")
    for category in model["cats"]:
        lines.append(
            "  { id = %s, title = %s, icon = %s, color = %s, group = %s, info = %s }," % (
                lua_num(category["id"]),
                lua_str(category["title"]),
                lua_str(category["icon"]),
                lua_str(category["color"]),
                lua_num(category["group"]),
                lua_str(clean_text(category["info"])),
            )
        )
    lines.append("},")

    def column(name, values):
        lines.append(name + " = {" + ",".join(lua_num(item) for item in values) + "},")

    column("x", [pin["x"] for pin in pins])
    column("y", [pin["y"] for pin in pins])
    column("cat", [pin["cat"] for pin in pins])
    column("fac", [pin["fac"] for pin in pins])
    column("lvl", [pin["lvl"] for pin in pins])
    column("cls", [pin["cls"] for pin in pins])
    column("qid", [pin["qid"] for pin in pins])
    column("endp", [pin["endp"] for pin in pins])
    column("dest", [pin["dest"] for pin in pins])
    lines.append("title = {")
    for pin in pins:
        lines.append(lua_str(pin["title"]) + ",")
    lines.append("},")
    lines.append("text = {")
    for pin in pins:
        lines.append(lua_str(pin["text"]) + ",")
    lines.append("},")
    lines.append("pre = {")
    for n, pin in enumerate(pins, start=1):
        if pin["pre"]:
            unique = list(dict.fromkeys(pin["pre"]))
            lines.append(f"  [{n}] = {num_list(unique)},")
    lines.append("},")
    lines.append("}")
    os.makedirs(os.path.dirname(out_lua), exist_ok=True)
    with open(out_lua, "w", encoding="utf-8", newline="") as handle:
        handle.write("\r\n".join(lines) + "\r\n")


def change_report(prev, model):
    if not prev:
        return []
    match = re.search(r"(?m)^cat = \{([^}]*)\}", prev)
    if not match:
        return []
    old = {}
    for part in match.group(1).split(","):
        if part.strip():
            key = int(part)
            old[key] = old.get(key, 0) + 1
    old_titles = {}
    ci = 0
    for found in re.finditer(r'(?m)^  \{ id = (\d+), title = "([^"]*)", icon', prev):
        ci += 1
        old_titles[int(found.group(1))] = ci
    changes = []
    for category in model["cats"]:
        n_new = sum(1 for pin in model["pins"] if pin["cat"] == model["cat_index"][category["id"]])
        slot = old_titles.get(category["id"])
        n_old = old.get(slot, 0) if slot else 0
        if n_new != n_old:
            changes.append(f"  {category['title']}: {n_old} -> {n_new}")
    return changes


def write_toc_and_zip(out_dir, iface, stamp, version):
    toc = (
        f"## Interface: {iface}\n"
        "## Title: |cffd4a94eDave's|r Map (data)\n"
        f"## Notes: Map Genie's map data for Dave's Map, built on this machine by daves_map\\tools\\Update-MapData.py ({stamp}). Not in git.\n"
        "## Author: generated\n"
        f"## Version: {version}\n"
        "## IconTexture: Interface\\Icons\\INV_Misc_Map_01\n"
        "\n"
        "Data.lua"
    )
    toc_path = os.path.join(out_dir, "daves_map_data.toc")
    with open(toc_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(toc)
    zip_path = os.path.join(os.path.dirname(out_dir), "daves_map_data.zip")
    if os.path.isfile(zip_path):
        os.remove(zip_path)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in os.listdir(out_dir):
            full = os.path.join(out_dir, name)
            if os.path.isfile(full):
                archive.write(full, "daves_map_data/" + name)
    return zip_path


def paths_from_script(script_file):
    tools = os.path.dirname(os.path.abspath(script_file))
    addon = os.path.dirname(tools)
    wowaddons = os.path.dirname(addon)
    return addon, os.path.join(wowaddons, "daves_map_data", "Data.lua")


def _args(argv):
    out = {
        "Url": "https://mapgenie.io/world-of-warcraft-forever/maps/azeroth",
        "NoQuestDb": False,
        "QuestDbRef": "master",
        "KeepRaw": False,
    }
    i = 0
    while i < len(argv):
        token = argv[i]
        if not token.startswith("-"):
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        raw = token[1:]
        if ":" in raw:
            key, value = raw.split(":", 1)
            take = False
        else:
            key = raw
            value = None
            take = True
        found = next((name for name in out if name.lower() == key.lower()), None)
        if not found:
            print("Unknown argument: " + token, file=sys.stderr, flush=True)
            raise SystemExit(1)
        if isinstance(out[found], bool):
            out[found] = True if value is None else value.strip().lower() not in ("false", "0", "$false")
        else:
            if take:
                if i + 1 >= len(argv):
                    print(f"Missing value for -{found}", file=sys.stderr, flush=True)
                    raise SystemExit(1)
                i += 1
                value = argv[i]
            out[found] = value
        i += 1
    return out


def main(argv):
    args = _args(argv)
    try:
        check_url(args["Url"])
        check_ref(args["QuestDbRef"])
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
    security = [f"sources: {args['Url']} (https, mapgenie.io); pfQuest ref '{args['QuestDbRef']}'"]
    addon, out_lua = paths_from_script(__file__)
    map_toc = os.path.join(addon, "daves_map.toc")
    iface_match = IFACE_RX.search(open(map_toc, "r", encoding="utf-8-sig", newline="").read())
    iface = iface_match.group(1) if iface_match else ""
    if not iface:
        print(f"No '## Interface:' line in {map_toc}; the data addon needs it to load.", file=sys.stderr, flush=True)
        raise SystemExit(1)
    raw = os.path.join(tempfile.gettempdir(), "daves_map_fetch_" + os.urandom(4).hex())
    os.makedirs(raw)
    print(f"Downloading into {raw}", flush=True)
    try:
        html = fetch(args["Url"], os.path.join(raw, "page.html"), {}, security)
        page = map_json(html, args["Url"])
        map_id = ps_int(page["map"]["id"])
        map_title = ps_string(page["map"]["title"])
        print(f"Map: {map_title} (id {map_id})", flush=True)
        origin = "https://" + urlparse(args["Url"]).hostname
        data_text = fetch(
            f"{origin}/api/v1/maps/{map_id}/data",
            os.path.join(raw, "mapdata.json"),
            {"Accept": "application/json", "Referer": args["Url"], "X-Requested-With": "XMLHttpRequest"},
            security,
        )
        data = json.loads(data_text)
        print(f"Pins: {len(data.get('locations') or [])}", flush=True)
        model = build_pins(page, data, args["Url"])
        print(f"Kept pins: {len(model['pins'])} in {len(model['cats'])} categories", flush=True)
        pf_used = None
        if not args["NoQuestDb"]:
            base = f"https://raw.githubusercontent.com/shagu/pfQuest/{args['QuestDbRef']}"
            print(f"Reading pfQuest ({args['QuestDbRef']})", flush=True)
            parser = LuaLiteral()
            pf_q = parser.parse_assigned(fetch(f"{base}/db/quests.lua", os.path.join(raw, "pf_quests.txt"), {}, security))
            pf_t = parser.parse_assigned(fetch(f"{base}/db/enUS/quests.lua", os.path.join(raw, "pf_quests_enUS.txt"), {}, security))
            pf_u = parser.parse_assigned(fetch(f"{base}/db/enUS/units.lua", os.path.join(raw, "pf_units_enUS.txt"), {}, security))
            links, matched, quest_pins = link_pins(model, pf_q, pf_t, pf_u)
            pf_used = args["QuestDbRef"]
            print(f"pfQuest: matched {matched} of {quest_pins} quest pins", flush=True)
        else:
            links, _matched, _quest_pins = link_pins(model)
        print(
            f"Links: {links['endp']} quest turn-ins, {links['pre']} prerequisites, {links['dest']} transport routes",
            flush=True,
        )
        now = datetime.now(timezone.utc)
        stamp = now.strftime("%Y-%m-%d %H:%M") + " UTC"
        version = now.strftime("%Y.%m.%d")
        out_dir = os.path.dirname(out_lua)
        old_in_addon = os.path.join(addon, "Data.lua")
        prev_path = out_lua if os.path.isfile(out_lua) else (old_in_addon if os.path.isfile(old_in_addon) else None)
        prev = open(prev_path, "r", encoding="utf-8-sig", newline="").read() if prev_path else None
        render(model, stamp, pf_used, out_lua)
        print(f"Wrote {out_lua} ({n0(os.path.getsize(out_lua) / 1024)} KB)", flush=True)
        zip_path = write_toc_and_zip(out_dir, iface, stamp, version)
        if os.path.isfile(old_in_addon):
            os.remove(old_in_addon)
            print(f"Removed the old {old_in_addon} (the data now lives in daves_map_data)", flush=True)
        print(
            f"Shareable copy: {zip_path} ({n0(os.path.getsize(zip_path) / 1024)} KB). "
            "Unzip into World of Warcraft\\_classic_beta_\\Interface\\AddOns, restart the client.",
            flush=True,
        )
        print("First time on this machine: link it into the game, then restart the client fully:", flush=True)
        print(f'  py -3 <kit>\\scripts\\Link-WowAddons.py -Path "{out_dir}"', flush=True)
        changes = change_report(prev, model)
        if prev and re.search(r"(?m)^cat = \{", prev):
            if changes:
                print("Changed since the last build:", flush=True)
                for line in changes:
                    print(line, flush=True)
            else:
                print("No change in pin counts since the last build.", flush=True)
        if args["KeepRaw"]:
            print(f"Raw downloads kept in {raw}", flush=True)
        print("", flush=True)
        print("Security checks passed:", flush=True)
        for line in security:
            print(f"  {line}", flush=True)
        print(
            "  each download: https on "
            + " / ".join(ALLOWED_HOSTS)
            + f" after redirects, under {n0(MAX_BYTES / 1048576)} MB, read as data only (JSON / Lua literals, nesting <= 64)",
            flush=True,
        )
        print("  Data.lua: downloaded text written only as escaped Lua strings, numbers checked as numbers", flush=True)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
    finally:
        if not args["KeepRaw"] and os.path.isdir(raw):
            shutil.rmtree(raw, ignore_errors=True)


if __name__ == "__main__":
    main(sys.argv[1:])
