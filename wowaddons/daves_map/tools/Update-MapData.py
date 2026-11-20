"""Build the companion addon wowaddons/daves_map_data from QuestieDB's WoW: Forever database.

Replaces Map Genie and pfQuest completely with QuestieDB Forever (exact in-game
uiMapID + 0..1 normalized coordinates, real Forever quest IDs, starter/finisher
NPCs & objects, objective spawns, prerequisite chains, dungeons, flight masters,
townsfolk, rares, and treasures).

Downloads are read strictly as declarative Lua/JSON data over HTTPS from
raw.githubusercontent.com — nothing fetched is ever executed.
"""

from __future__ import annotations

import concurrent.futures
import copy
import math
import os
import re
import shutil
import ssl
import sys
import tempfile
import urllib.request
from datetime import datetime, timezone
from urllib.parse import urlparse

ALLOWED_HOSTS = ("raw.githubusercontent.com",)
MAX_BYTES = 64 * 1048576
UA = "daves-map-questiedb-builder/1.0"
GOLD = "|cffffd200"
REF_RX = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$")
BAD_NAME_RX = re.compile(
    r"<NYI>|<UNUSED>|<TXT>|\[DEPRECATED\]|\[PH\]|^TEST\b|\bUNAVAILABLE\b|DO NOT USE|UNUSED\b",
    re.I,
)

# QuestieDB Forever requiredRaces masks (expansions.lua):
# Classic Alliance (1+4+8+64=77) + Draenei(1024) + Worgen(2097152) + PandarenA(16777216) + SkyborneA(4294967296)
ALLIANCE_RACE_MASK = 1 | 4 | 8 | 64 | 1024 | 2097152 | 16777216 | 4294967296
# Classic Horde (2+16+32+128=178) + Goblin(256) + BloodElf(512) + PandarenH(33554432) + SkyborneH(8589934592)
HORDE_RACE_MASK = 2 | 16 | 32 | 128 | 256 | 512 | 33554432 | 8589934592

# Map QuestieDB classKeys -> daves_map 9-class bitmask (Layer.lua CLASS_BITS)
QDB_TO_DM_CLASS = (
    (1, 1),      # WARRIOR
    (2, 2),      # PALADIN
    (4, 4),      # HUNTER
    (8, 8),      # ROGUE
    (16, 16),    # PRIEST
    (64, 32),    # SHAMAN
    (128, 64),   # MAGE
    (256, 128),  # WARLOCK
    (1024, 256), # DRUID
)
ALL_DM_CLASSES = 511

REQUIRED_FILES = (
    "LICENSE.md",
    "src/meta/questMeta.lua",
    "src/meta/npcMeta.lua",
    "src/meta/objectMeta.lua",
    "src/meta/itemMeta.lua",
    "src/corrections/enum/expansions.lua",
    "src/corrections/enum/quests.lua",
    "src/corrections/enum/zones.lua",
    "src/corrections/enum/professions.lua",
    "src/corrections/enum/factions.lua",
    "src/corrections/enum/icons.lua",
    "src/corrections/enum/waypoints.lua",
    "src/corrections/enum/items.lua",
    "src/corrections/enum/phases.lua",
    "data/Forever/foreverQuestDB.lua",
    "data/Forever/foreverNpcDB.lua",
    "data/Forever/foreverObjectDB.lua",
    "data/Forever/foreverItemDB.lua",
    "src/corrections/Forever/legacy/classicQuestFixes.lua",
    "src/corrections/Forever/legacy/classicQuestReputationFixes.lua",
    "src/corrections/Forever/legacy/classicNPCFixes.lua",
    "src/corrections/Forever/legacy/classicObjectFixes.lua",
    "src/corrections/Forever/legacy/classicItemFixes.lua",
    "src/corrections/Forever/legacy/itemStartFixes.lua",
    "src/corrections/Forever/generated/foreverBaseQuest.lua",
    "src/corrections/Forever/generated/foreverBaseNpc.lua",
    "src/corrections/Forever/generated/foreverBaseObject.lua",
    "src/corrections/Forever/generated/foreverBaseItem.lua",
    "src/corrections/Forever/traces/foreverQuestTraces.lua",
    "src/corrections/Forever/traces/foreverNpcTraces.lua",
    "src/corrections/Forever/traces/foreverObjectTraces.lua",
    "src/corrections/Forever/traces/foreverItemTraces.lua",
    "src/corrections/Forever/traces/foreverQuestRelationTraces.lua",
    "src/corrections/Forever/foreverQuestFixes.lua",
    "src/corrections/Forever/foreverNPCFixes.lua",
    "src/corrections/Forever/foreverObjectFixes.lua",
    "src/corrections/Forever/foreverItemFixes.lua",
    "support/Forever/Zones/areaIdToUiMapId.lua",
    "support/Forever/Zones/dungeons.lua",
    "support/Forever/DropTables/classicItemDrops.lua",
)

GROUPS = (
    {"id": 1, "title": "Quests"},
    {"id": 2, "title": "Locations & Travel"},
    {"id": 3, "title": "Townsfolk & Services"},
    {"id": 4, "title": "World & Rare Spawns"},
)

CATEGORIES = (
    {"id": 101, "key": "quest", "title": "Quest", "icon": "quest", "color": "f5c242", "group": 1, "defaultOff": False},
    {"id": 102, "key": "repeatable", "title": "Repeatable", "icon": "repeatable", "color": "5cb3ff", "group": 1, "defaultOff": False},
    {"id": 103, "key": "turnin", "title": "Quest Turn-In", "icon": "turnin", "color": "ffd200", "group": 1, "defaultOff": True},
    {"id": 104, "key": "objective", "title": "Quest Objective", "icon": "quest_objective", "color": "ff8c33", "group": 1, "defaultOff": True},
    {"id": 105, "key": "instance", "title": "Instance", "icon": "instance", "color": "b366ff", "group": 2, "defaultOff": False},
    {"id": 106, "key": "flight", "title": "Flight Master", "icon": "flight_master", "color": "4ce680", "group": 2, "defaultOff": False},
    {"id": 107, "key": "graveyard", "title": "Graveyard", "icon": "graveyard", "color": "80d4ff", "group": 2, "defaultOff": False},
    {"id": 108, "key": "innkeeper", "title": "Innkeeper", "icon": "innkeeper", "color": "f0a848", "group": 3, "defaultOff": False},
    {"id": 109, "key": "mailbox", "title": "Mailbox", "icon": "mailbox", "color": "70b8ff", "group": 3, "defaultOff": False},
    {"id": 110, "key": "banker", "title": "Banker", "icon": "banker", "color": "e6c84c", "group": 3, "defaultOff": False},
    {"id": 111, "key": "auctioneer", "title": "Auctioneer", "icon": "auctioneer", "color": "ffd933", "group": 3, "defaultOff": False},
    {"id": 112, "key": "stable", "title": "Stable Master", "icon": "stable_master", "color": "c89b64", "group": 3, "defaultOff": False},
    {"id": 113, "key": "class_trainer", "title": "Class Trainer", "icon": "class_trainer", "color": "c480ff", "group": 3, "defaultOff": False},
    {"id": 114, "key": "prof_trainer", "title": "Profession Trainer", "icon": "profession_trainer", "color": "4cd9c0", "group": 3, "defaultOff": False},
    {"id": 115, "key": "repair", "title": "Repair", "icon": "repair_vendor", "color": "b8c4d0", "group": 3, "defaultOff": False},
    {"id": 116, "key": "vendor", "title": "Merchant", "icon": "merchant", "color": "9ec864", "group": 3, "defaultOff": True},
    {"id": 117, "key": "rare", "title": "Rare", "icon": "rare", "color": "ff4d5e", "group": 4, "defaultOff": False},
    {"id": 118, "key": "treasure", "title": "Treasure & Lore", "icon": "treasure", "color": "ffaa33", "group": 4, "defaultOff": False},
)

CAT_SLOT = {c["key"]: idx for idx, c in enumerate(CATEGORIES, start=1)}

QUEST_META_STRUCT = {
    2: "questgivers", 3: "questgivers", 8: "list", 9: "trigger", 10: "objectives",
    12: "list", 13: "list", 14: "list", 15: "list", 16: "list", 18: "pair",
    19: "pair", 20: "pair", 21: "list", 26: "list", 28: "list", 29: "list", 35: "list",
}
NPC_META_STRUCT = {7: "grouped", 8: "grouped", 10: "list", 11: "list"}
OBJ_META_STRUCT = {2: "list", 3: "list", 4: "grouped", 7: "grouped"}
ITEM_META_STRUCT = {2: "list", 3: "list", 4: "list", 6: "list", 14: "list", 15: "list"}

CLASS_SUBNAME_WORDS = (
    ("warrior", 1), ("paladin", 2), ("hunter", 4), ("rogue", 8), ("priest", 16),
    ("shaman", 32), ("mage", 64), ("warlock", 128), ("druid", 256),
)

TREASURE_OBJ_RX = re.compile(
    r"\b(chest|footlocker|strongbox|lockbox|coffer|cache|treasure|wanted:|wanted poster|plaque|tablet|tome|journal|diary|memorial|monument)\b",
    re.I,
)
SKIP_OBJ_RX = re.compile(
    r"\b(chair|bench|stool|brazier|torch|bonfire|campfire|anvil|forge|bed|cot|door|gate|lever|trap|portal|doodad|invisible|placeholder|test)\b",
    re.I,
)


def n0(value: float) -> str:
    return f"{int(round(value)):,}"


def lua_num(value: float | int) -> str:
    if isinstance(value, int):
        return str(value)
    if math.isnan(value) or math.isinf(value):
        raise RuntimeError(f"Non-finite number: {value}")
    return f"{value:.5f}".rstrip("0").rstrip(".") or "0"


def lua_str(value: str | None) -> str:
    text = (value or "").replace("\r", "")
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"\|(?!c[0-9a-fA-F]{8}|r)", "||", text, flags=re.I)
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", " ")
    text = re.sub(r"[\x00-\x1f\x7f]", "", text)
    return '"' + text.strip() + '"'


def num_list(values: list[int]) -> str:
    return "{" + ",".join(str(int(v)) for v in values) + "}"


# ---------------------------------------------------------------------------
# Pure-Python safe Lua table / expression reader (zero code execution)
# ---------------------------------------------------------------------------
TOKEN_RX = re.compile(
    r"""
    \s*(?:
        --\[\[[\s\S]*?\]\]
      | --[^\n]*
      | (\[\[[\s\S]*?\]\])
      | ("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')
      | (0x[0-9a-fA-F]+|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)
      | (\.\.\.|[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)
      | ([{}\[\]=,+|();:*~<>/-])
    )
    """,
    re.VERBOSE,
)
_ESC = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'"}


def _unquote(s: str) -> str:
    if s.startswith("[["):
        body = s[2:-2]
        return body[1:] if body.startswith("\n") else body
    inner = s[1:-1]
    out: list[str] = []
    i, n = 0, len(inner)
    while i < n:
        ch = inner[i]
        if ch == "\\" and i + 1 < n:
            nxt = inner[i + 1]
            if nxt in _ESC:
                out.append(_ESC[nxt])
                i += 2
            elif nxt.isdigit():
                j = i + 1
                while j < min(i + 4, n) and inner[j].isdigit():
                    j += 1
                out.append(chr(int(inner[i + 1:j])))
                i = j
            else:
                out.append(nxt)
                i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


class LuaExprParser:
    def __init__(self, text: str, env: dict[str, object]):
        self.tokens: list[tuple[str, object]] = []
        text = text.rstrip()
        pos, n = 0, len(text)
        while pos < n:
            m = TOKEN_RX.match(text, pos)
            if not m or m.end() == pos:
                raise RuntimeError(f"Unexpected Lua syntax near: {text[pos:pos + 60]!r}")
            pos = m.end()
            g1, g2, g3, g4, g5 = m.groups()
            if g1 is not None:
                self.tokens.append(("STR", _unquote(g1)))
            elif g2 is not None:
                self.tokens.append(("STR", _unquote(g2)))
            elif g3 is not None:
                v = (
                    int(g3, 16)
                    if g3.startswith(("0x", "0X"))
                    else (float(g3) if ("." in g3 or "e" in g3.lower()) else int(g3))
                )
                self.tokens.append(("NUM", v))
            elif g4 is not None:
                self.tokens.append(("ID", g4))
            elif g5 is not None:
                self.tokens.append(("OP", g5))
        self.i = 0
        self.env = env

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else ("EOF", None)

    def next(self):
        tok = self.peek()
        self.i += 1
        return tok

    def expect(self, kind: str, val=None):
        t = self.next()
        if t[0] != kind or (val is not None and t[1] != val):
            raise RuntimeError(f"Expected {kind} {val}, got {t}")
        return t[1]

    def resolve_id(self, name: str):
        if name == "nil":
            return None
        if name == "true":
            return True
        if name == "false":
            return False
        if name in self.env:
            return self.env[name]
        parts = name.split(".")
        if parts[0] not in self.env:
            raise RuntimeError(f"Unknown identifier in data file: {name!r}")
        cur = self.env[parts[0]]
        for p in parts[1:]:
            if isinstance(cur, dict):
                cur = cur.get(p)
            else:
                return None
        return cur

    def parse_expr(self, depth: int = 0):
        if depth > 64:
            raise RuntimeError("Nesting depth > 64")
        val = self.parse_primary(depth)
        while self.peek()[0] == "OP" and self.peek()[1] in ("+", "-"):
            op = self.next()[1]
            rhs = self.parse_primary(depth)
            lhs_n = int(val or 0) if isinstance(val, (int, float)) else 0
            rhs_n = int(rhs or 0) if isinstance(rhs, (int, float)) else 0
            val = (lhs_n + rhs_n) if op == "+" else (lhs_n - rhs_n)
        return val

    def parse_primary(self, depth: int):
        kind, val = self.peek()
        if kind in ("STR", "NUM"):
            self.next()
            return val
        if kind == "OP" and val == "-":
            self.next()
            sub = self.parse_primary(depth + 1)
            return -sub if isinstance(sub, (int, float)) else 0
        if kind == "OP" and val == "(":
            self.next()
            v = self.parse_expr(depth + 1)
            self.expect("OP", ")")
            while self.peek() == ("OP", "["):
                self.next()
                idx = self.parse_expr(depth + 1)
                self.expect("OP", "]")
                v = v.get(idx) if isinstance(v, dict) else None
            return v
        if kind == "OP" and val == "{":
            return self.parse_table(depth + 1)
        if kind == "ID":
            self.next()
            if self.peek() == ("OP", "("):
                self.next()
                args = []
                while self.peek() != ("OP", ")"):
                    args.append(self.parse_expr(depth + 1))
                    if self.peek() == ("OP", ","):
                        self.next()
                self.expect("OP", ")")
                if val in ("bit.bor", "bit32.bor"):
                    res = 0
                    for a in args:
                        res |= int(a or 0)
                    return res
                if val == "l10n":
                    return str(args[0]) if args else ""
                raise RuntimeError(f"Unsupported function call in data: {val}")
            resolved = self.resolve_id(str(val))
            while self.peek() == ("OP", "["):
                self.next()
                idx = self.parse_expr(depth + 1)
                self.expect("OP", "]")
                resolved = resolved.get(idx) if isinstance(resolved, dict) else None
            return resolved
        raise RuntimeError(f"Unexpected token in expression: {(kind, val)}")

    def parse_table(self, depth: int = 0) -> dict:
        if depth > 64:
            raise RuntimeError("Table nesting depth > 64")
        self.expect("OP", "{")
        out: dict = {}
        idx = 1
        while self.peek() != ("OP", "}"):
            if self.peek() == ("OP", "["):
                self.next()
                k = self.parse_expr(depth + 1)
                self.expect("OP", "]")
                self.expect("OP", "=")
                v = self.parse_expr(depth + 1)
                if k is not None and v is not None:
                    out[k] = v
            elif self.peek()[0] == "ID" and self.i + 1 < len(self.tokens) and self.tokens[self.i + 1] == ("OP", "="):
                k = self.next()[1]
                self.expect("OP", "=")
                v = self.parse_expr(depth + 1)
                if v is not None:
                    out[k] = v
            else:
                v = self.parse_expr(depth + 1)
                if v is not None:
                    out[idx] = v
                idx += 1
            if self.peek() in (("OP", ","), ("OP", ";")):
                self.next()
        self.expect("OP", "}")
        return out


# ---------------------------------------------------------------------------
# Downloading / loading QuestieDB Forever files
# ---------------------------------------------------------------------------
def _check_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in ALLOWED_HOSTS:
        raise RuntimeError(f"Blocked URL: {url}")


def fetch_questiedb(ref: str, dest_root: str) -> None:
    if not REF_RX.match(ref):
        raise RuntimeError(f"Invalid git ref: {ref!r}")
    ctx = ssl.create_default_context()
    headers = {"User-Agent": UA}

    def dl(rel: str) -> int:
        url = f"https://raw.githubusercontent.com/Questie/QuestieDB/{ref}/{rel}"
        _check_url(url)
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=30, context=ctx) as resp:
            _check_url(resp.geturl())
            data = resp.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                raise RuntimeError(f"Download exceeded {MAX_BYTES} bytes: {rel}")
        out_path = os.path.join(dest_root, *rel.split("/"))
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "wb") as handle:
            handle.write(data)
        return len(data)

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        total = sum(pool.map(dl, REQUIRED_FILES))
    print(f"Fetched {len(REQUIRED_FILES)} QuestieDB Forever files ({total / 1048576:.2f} MB)", flush=True)


def dict_to_list(d) -> list:
    if not isinstance(d, dict) or not d:
        return []
    return [d[k] for k in sorted(k for k in d.keys() if isinstance(k, int) and k >= 1)]


def list_to_dict(lst: list) -> dict:
    return {i + 1: v for i, v in enumerate(lst)}


def apply_corrections(db: dict, corr: dict, struct_map: dict, no_new=False, no_overwrite=False) -> None:
    for eid, fields in corr.items():
        if not isinstance(eid, int):
            continue
        if fields is False:
            db.pop(eid, None)
            continue
        if not isinstance(fields, dict):
            continue
        if eid not in db:
            if no_new:
                continue
            db[eid] = {}
        row = db[eid]
        for fkey, val in fields.items():
            if not isinstance(fkey, int):
                continue
            if 0 < fkey < 1000:
                if no_overwrite and fkey in row and row[fkey] is not None:
                    continue
                row[fkey] = copy.deepcopy(val)
            else:
                is_add = fkey >= 1000
                base_f = fkey - 1000 if is_add else fkey + 1000
                if no_overwrite and base_f in row and row[base_f] is not None:
                    continue
                kind = struct_map.get(base_f, "list")
                cur = row.get(base_f)
                if not isinstance(cur, dict):
                    cur = {}
                if kind in ("questgivers", "objectives", "grouped"):
                    if isinstance(val, dict):
                        for gk, gitems in val.items():
                            cur_list = dict_to_list(cur.get(gk, {}))
                            op_list = dict_to_list(gitems) if isinstance(gitems, dict) else []
                            if is_add:
                                for x in op_list:
                                    if x not in cur_list:
                                        cur_list.append(copy.deepcopy(x))
                            else:
                                cur_list = [x for x in cur_list if x not in op_list]
                            if cur_list:
                                cur[gk] = list_to_dict(cur_list)
                            else:
                                cur.pop(gk, None)
                    row[base_f] = cur
                else:
                    cur_list = dict_to_list(cur)
                    op_list = dict_to_list(val) if isinstance(val, dict) else []
                    if is_add:
                        for x in op_list:
                            if x not in cur_list:
                                cur_list.append(copy.deepcopy(x))
                    else:
                        cur_list = [x for x in cur_list if x not in op_list]
                    row[base_f] = list_to_dict(cur_list)


def load_questiedb(qdb_root: str):
    enums: dict[str, object] = {}
    env: dict[str, object] = {"constants": enums, "LibQuestieDB": {"Enum": enums}}

    for fn in (
        "expansions.lua", "quests.lua", "zones.lua", "professions.lua",
        "factions.lua", "icons.lua", "waypoints.lua", "items.lua", "phases.lua",
    ):
        p = os.path.join(qdb_root, "src", "corrections", "enum", fn)
        txt = open(p, encoding="utf-8").read()
        parser = LuaExprParser(txt, env)
        while parser.peek()[0] != "EOF":
            t = parser.next()
            if t[0] == "ID" and str(t[1]).startswith("constants.") and parser.peek() == ("OP", "="):
                parser.next()
                key = str(t[1]).split(".", 1)[1]
                enums[key] = parser.parse_expr()
                env[str(t[1])] = enums[key]
            elif t == ("ID", "local") and parser.peek()[0] == "ID":
                vname = str(parser.next()[1])
                if parser.peek() == ("OP", "="):
                    parser.next()
                    env[vname] = parser.parse_expr()

    def make_keys(meta_name: str) -> dict[str, int]:
        txt = open(os.path.join(qdb_root, "src", "meta", meta_name), encoding="utf-8").read()
        m = re.search(r"keys\s*=\s*(\{[\s\S]*?\n  \})", txt)
        if not m:
            raise RuntimeError(f"Missing keys table in {meta_name}")
        raw = LuaExprParser(m.group(1), {}).parse_table()
        full = dict(raw)
        for k, v in raw.items():
            full[f"{k}_add"] = v + 1000
            full[f"{k}_remove"] = v - 1000
        return full

    quest_keys = make_keys("questMeta.lua")
    npc_keys = make_keys("npcMeta.lua")
    obj_keys = make_keys("objectMeta.lua")
    item_keys = make_keys("itemMeta.lua")

    corr_env = {
        "questKeys": quest_keys,
        "npcKeys": npc_keys,
        "objectKeys": obj_keys,
        "itemKeys": item_keys,
        "zoneIDs": enums["zoneIDs"],
        "raceIDs": enums["byExpansion"]["Forever"]["raceKeys"],
        "classIDs": enums["byExpansion"]["Classic"]["classKeys"],
        "npcFlags": enums["byExpansion"]["Forever"]["npcFlags"],
        "sortKeys": enums["sortKeys"],
        "questFlags": enums["questFlags"],
        "specialFlags": enums["specialFlags"],
        "profKeys": enums["professionKeys"],
        "specKeys": enums["specializationKeys"],
        "rankKeys": enums["rankNames"],
        "factionIDs": enums["factionIDs"],
        "iconTypes": enums["iconTypes"],
        "iconKeys": enums["iconTypes"],
        "Questie": enums["iconTypes"],
        "phases": enums["phases"],
        "Phasing": {"phases": enums["phases"]},
        "itemClasses": enums["itemClasses"],
        "dropCorrectionKeys": enums["dropCorrectionKeys"],
        "waypointPresets": enums["waypointPresets"],
        "QuestieDB": {
            "questKeys": quest_keys, "npcKeys": npc_keys, "objectKeys": obj_keys, "itemKeys": item_keys,
            "raceKeys": enums["byExpansion"]["Forever"]["raceKeys"],
            "classKeys": enums["byExpansion"]["Classic"]["classKeys"],
            "npcFlags": enums["byExpansion"]["Forever"]["npcFlags"],
            "sortKeys": enums["sortKeys"], "questFlags": enums["questFlags"],
            "specialFlags": enums["specialFlags"], "factionIDs": enums["factionIDs"],
            "itemClasses": enums["itemClasses"], "phases": enums["phases"],
            "waypointPresets": enums["waypointPresets"],
        },
        "ZoneDB": {"zoneIDs": enums["zoneIDs"]},
        "QuestieProfessions": {
            "professionKeys": enums["professionKeys"],
            "specializationKeys": enums["specializationKeys"],
            "rankNames": enums["rankNames"],
        },
    }

    def parse_raw(rel: str) -> dict:
        txt = open(os.path.join(qdb_root, *rel.split("/")), encoding="utf-8").read()
        m = re.search(r"\[\[return\s*(\{[\s\S]*\})\]\]", txt)
        if not m:
            raise RuntimeError(f"Missing [[return {{...}}]] block in {rel}")
        return LuaExprParser(m.group(1), {}).parse_table()

    quests = parse_raw("data/Forever/foreverQuestDB.lua")
    npcs = parse_raw("data/Forever/foreverNpcDB.lua")
    objs = parse_raw("data/Forever/foreverObjectDB.lua")
    items = parse_raw("data/Forever/foreverItemDB.lua")
    item_drops = parse_raw("support/Forever/DropTables/classicItemDrops.lua")

    def parse_corr(rel: str, fn_name: str = "Load") -> dict:
        txt = open(os.path.join(qdb_root, "src", "corrections", "Forever", *rel.split("/")), encoding="utf-8").read()
        m = re.search(rf"function\s+[A-Za-z0-9_]+:{fn_name}\(\)([\s\S]*?)^\s*end\b", txt, re.M)
        if not m:
            return {}
        body = m.group(1)
        rm = re.search(r"\breturn\s*\{", body)
        if not rm:
            return {}
        local_env = dict(corr_env)
        for lm in re.finditer(r"local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^\n-]+)", body[:rm.start()]):
            try:
                local_env[lm.group(1)] = LuaExprParser(lm.group(2).strip(), local_env).parse_expr()
            except Exception:
                pass
        return LuaExprParser(body[rm.end() - 1:], local_env).parse_table()

    layers = (
        ("legacy/classicQuestFixes.lua", "Load", quests, QUEST_META_STRUCT, False, False),
        ("legacy/classicQuestReputationFixes.lua", "Load", quests, QUEST_META_STRUCT, False, False),
        ("legacy/classicNPCFixes.lua", "Load", npcs, NPC_META_STRUCT, False, False),
        ("legacy/classicObjectFixes.lua", "Load", objs, OBJ_META_STRUCT, False, False),
        ("legacy/classicItemFixes.lua", "Load", items, ITEM_META_STRUCT, False, False),
        ("legacy/itemStartFixes.lua", "LoadAutomaticQuestStarts", items, ITEM_META_STRUCT, True, True),
        ("generated/foreverBaseQuest.lua", "Load", quests, QUEST_META_STRUCT, False, False),
        ("generated/foreverBaseNpc.lua", "Load", npcs, NPC_META_STRUCT, False, False),
        ("generated/foreverBaseObject.lua", "Load", objs, OBJ_META_STRUCT, False, False),
        ("generated/foreverBaseItem.lua", "Load", items, ITEM_META_STRUCT, False, False),
        ("traces/foreverQuestTraces.lua", "Load", quests, QUEST_META_STRUCT, False, False),
        ("traces/foreverNpcTraces.lua", "Load", npcs, NPC_META_STRUCT, False, False),
        ("traces/foreverObjectTraces.lua", "Load", objs, OBJ_META_STRUCT, False, False),
        ("traces/foreverItemTraces.lua", "Load", items, ITEM_META_STRUCT, False, False),
        ("traces/foreverQuestRelationTraces.lua", "Load", quests, QUEST_META_STRUCT, False, False),
        ("foreverQuestFixes.lua", "Load", quests, QUEST_META_STRUCT, False, False),
        ("foreverNPCFixes.lua", "Load", npcs, NPC_META_STRUCT, False, False),
        ("foreverObjectFixes.lua", "Load", objs, OBJ_META_STRUCT, False, False),
        ("foreverItemFixes.lua", "Load", items, ITEM_META_STRUCT, False, False),
    )
    for rel, fn, target_db, smap, no_new, no_ov in layers:
        apply_corrections(target_db, parse_corr(rel, fn), smap, no_new=no_new, no_overwrite=no_ov)

    area_txt = open(os.path.join(qdb_root, "support", "Forever", "Zones", "areaIdToUiMapId.lua"), encoding="utf-8").read()
    blocks = re.findall(r"\[\[return\s*(\{[\s\S]*?\})\]\]", area_txt)
    area_to_uimap = LuaExprParser(blocks[1], {}).parse_table()

    dung_txt = open(os.path.join(qdb_root, "support", "Forever", "Zones", "dungeons.lua"), encoding="utf-8").read()
    dung_head = dung_txt.split("if Expansions.Current")[0]
    dung_head = re.sub(r"\(isHorde\s+and\s+(\{[^}]+\})\)\s+or\s+(\{[^}]+\})", r"\1, \2", dung_head)
    dm = re.search(r"local\s+dungeons\s*=\s*(\{[\s\S]*\})", dung_head)
    dungeons = LuaExprParser(dm.group(1), {}).parse_table() if dm else {}

    return quests, npcs, objs, items, item_drops, area_to_uimap, dungeons


# ---------------------------------------------------------------------------
# Building daves_map pin model from merged QuestieDB Forever tables
# ---------------------------------------------------------------------------
def convert_class_mask(qdb_cls: int | None) -> int:
    if not isinstance(qdb_cls, int) or qdb_cls <= 0:
        return 0
    out = 0
    for qbit, dmbit in QDB_TO_DM_CLASS:
        if qdb_cls & qbit:
            out |= dmbit
    return 0 if out == ALL_DM_CLASSES else out


def friendly_to_fac(friendly: str | None) -> int:
    if friendly == "A":
        return 1
    if friendly == "H":
        return 2
    return 3


def quest_faction(required_races: int | None, starter_fac: int) -> int:
    if isinstance(required_races, int) and required_races > 0:
        has_a = (required_races & ALLIANCE_RACE_MASK) != 0
        has_h = (required_races & HORDE_RACE_MASK) != 0
        if has_a and not has_h:
            return 1
        if has_h and not has_a:
            return 2
    return starter_fac


SEASONAL_SORT_KEYS = {-404, -402, -378, -376, -375, -374, -370, -369, -366, -364, -41, -22, -21}

FOREVER_DUNGEONS = (
    {"name": "Ragefire Chasm", "lo": 13, "hi": 18, "raid": False, "zones": ((1454, 52.6, 49.0),), "zos": (2437,), "phrases": ("ragefire chasm",)},
    {"name": "The Hall of Thanes", "lo": 13, "hi": 20, "raid": False, "zones": ((1455, 27.7, 47.9),), "zos": (16919,), "phrases": ("hall of thanes",)},
    {"name": "Ruins of Lordaeron", "lo": 15, "hi": 22, "raid": False, "zones": ((1458, 72.5, 11.4), (1420, 61.8, 65.0)), "zos": (16611,), "phrases": ("ruins of lordaeron",)},
    {"name": "Wailing Caverns", "lo": 15, "hi": 24, "raid": False, "zones": ((1413, 46.0, 36.5),), "zos": (718,), "phrases": ("wailing caverns",)},
    {"name": "The Deadmines", "lo": 17, "hi": 26, "raid": False, "zones": ((1436, 42.5, 71.7),), "zos": (1581, 10029), "phrases": ("deadmines",)},
    {"name": "Shadowfang Keep", "lo": 20, "hi": 30, "raid": False, "zones": ((1421, 44.8, 67.8),), "zos": (209, 10014, 10015, 10016, 10017, 10018, 10019), "phrases": ("shadowfang keep",)},
    {"name": "Blackfathom Deeps", "lo": 24, "hi": 32, "raid": False, "zones": ((1440, 14.5, 14.2),), "zos": (719, 10020, 10021), "phrases": ("blackfathom deeps",)},
    {"name": "Stormwind Stockade", "lo": 24, "hi": 32, "raid": False, "zones": ((1453, 52.4, 70.0),), "zos": (717,), "phrases": ("the stockade", "stormwind stockade")},
    {"name": "Excavation Site: Wetlands", "lo": 26, "hi": 33, "raid": False, "zones": ((1437, 47.8, 56.2),), "zos": (16732,), "phrases": ("excavation site: wetlands", "wetlands excavation site")},
    {"name": "City of Dalaran", "lo": 28, "hi": 35, "raid": False, "zones": ((1416, 8.5, 59.3),), "zos": (16544,), "phrases": ("inside the city of dalaran", "from the city of dalaran", "in the city of dalaran")},
    {"name": "Gnomeregan", "lo": 29, "hi": 38, "raid": False, "zones": ((1426, 24.3, 39.8),), "zos": (721, 133, 10030, 10031, 10032), "phrases": ("gnomeregan",)},
    {"name": "Razorfen Kraul", "lo": 29, "hi": 38, "raid": False, "zones": ((1413, 42.9, 90.2),), "zos": (491, 1717), "phrases": ("razorfen kraul",)},
    {"name": "Scarlet Monastery", "lo": 30, "hi": 46, "raid": False, "zones": ((1420, 82.6, 33.8),), "zos": (796, 6109, 6386, 10008, 10009, 10010), "phrases": ("scarlet monastery",)},
    {"name": "The Drowned City", "lo": 35, "hi": 42, "raid": False, "zones": ((1434, 21.3, 27.8),), "zos": (), "phrases": ("drowned city",)},
    {"name": "Razorfen Downs", "lo": 37, "hi": 46, "raid": False, "zones": ((1413, 49.0, 93.9),), "zos": (722, 1316), "phrases": ("razorfen downs",)},
    {"name": "Krol'dok Stronghold", "lo": 40, "hi": 47, "raid": False, "zones": ((2548, 37.5, 37.3),), "zos": (), "phrases": ("krol'dok stronghold", "krol'dok no more")},
    {"name": "Uldaman", "lo": 41, "hi": 51, "raid": False, "zones": ((1418, 44.6, 12.1),), "zos": (1337, 1517, 10033), "phrases": ("uldaman",)},
    {"name": "Zul'Farrak", "lo": 44, "hi": 54, "raid": False, "zones": ((1446, 38.7, 20.1),), "zos": (1176, 978), "phrases": ("zul'farrak",)},
    {"name": "Maraudon", "lo": 46, "hi": 55, "raid": False, "zones": ((1443, 29.1, 62.5),), "zos": (2100, 10000), "phrases": ("maraudon",)},
    {"name": "Alcaz Prison", "lo": 48, "hi": 55, "raid": False, "zones": ((1445, 75.3, 14.1),), "zos": (), "phrases": ("alcaz prison",)},
    {"name": "Sunken Temple", "lo": 50, "hi": 60, "raid": False, "zones": ((1435, 69.9, 53.5),), "zos": (1477, 1417), "phrases": ("temple of atal'hakkar", "sunken temple")},
    {"name": "Blackrock Depths", "lo": 52, "hi": 60, "raid": False, "zones": ((1427, 34.8, 85.3), (1428, 29.4, 38.3)), "zos": (1584, 1585), "phrases": ("blackrock depths",)},
    {"name": "Dire Maul", "lo": 54, "hi": 60, "raid": False, "zones": ((1444, 59.2, 45.1),), "zos": (2557, 10022, 10023, 10024, 10025, 10026, 10027), "phrases": ("dire maul",)},
    {"name": "Blackmaw Hold", "lo": 55, "hi": 60, "raid": False, "zones": ((1447, 38.6, 33.2),), "zos": (), "phrases": ("blackmaw hold", "varrox bleakhoof")},
    {"name": "Blackrock Spire", "lo": 55, "hi": 60, "raid": False, "zones": ((1427, 34.8, 85.3), (1428, 29.4, 38.3)), "zos": (1583, 10003, 10004, 10005, 10006, 10007), "phrases": ("blackrock spire",)},
    {"name": "Scholomance", "lo": 58, "hi": 60, "raid": False, "zones": ((1422, 69.7, 73.2),), "zos": (2057, 10011, 10012, 10013), "phrases": ("scholomance",)},
    {"name": "Shaper's Terrace", "lo": 58, "hi": 60, "raid": False, "zones": ((1449, 48.1, 6.1),), "zos": (16985,), "phrases": ("shaper's terrace",)},
    {"name": "Stratholme", "lo": 58, "hi": 60, "raid": False, "zones": ((1423, 26.5, 10.4),), "zos": (2017, 10001), "phrases": ("stratholme",)},
    {"name": "Molten Core", "lo": 60, "hi": 60, "raid": True, "zones": ((1427, 34.8, 85.3), (1428, 29.4, 38.3)), "zos": (2717,), "phrases": ("molten core",)},
    {"name": "Onyxia's Lair", "lo": 60, "hi": 60, "raid": True, "zones": ((1445, 52.6, 76.8),), "zos": (2159,), "phrases": ("onyxia's lair",)},
    {"name": "Blackwing Lair", "lo": 60, "hi": 60, "raid": True, "zones": ((1427, 34.8, 85.3), (1428, 29.4, 38.3)), "zos": (2677,), "phrases": ("blackwing lair",)},
    {"name": "Zul'Gurub", "lo": 60, "hi": 60, "raid": True, "zones": ((1434, 53.9, 17.6),), "zos": (1977,), "phrases": ("zul'gurub",)},
    {"name": "Ruins of Ahn'Qiraj", "lo": 60, "hi": 60, "raid": True, "zones": ((1451, 28.6, 92.3),), "zos": (3429,), "phrases": ("ruins of ahn'qiraj",)},
    {"name": "Temple of Ahn'Qiraj", "lo": 60, "hi": 60, "raid": True, "zones": ((1451, 28.6, 92.3),), "zos": (3428, 10040, 10041), "phrases": ("temple of ahn'qiraj",)},
    {"name": "Naxxramas", "lo": 60, "hi": 60, "raid": True, "zones": ((1423, 34.3, 19.5),), "zos": (3456, 10062, 10063, 10064, 10065, 10066), "phrases": ("naxxramas",)},
)


def build_model(quests, npcs, objs, items, item_drops, area_to_uimap, dungeons):
    dungeon_entrance: dict[int, tuple[int, float, float, str]] = {}
    dungeon_rows: list[tuple[int, str, int, float, float, int, int, bool]] = []
    seen_dungeon_spots: set[tuple[str, int]] = set()
    dung_by_name: dict[str, dict] = {}
    zos_to_dung: dict[int, dict] = {}

    def norm_dname(s: str) -> str:
        s2 = s.strip().lower()
        if s2 == "the stockade":
            return "stormwind stockade"
        if s2 == "the temple of atal'hakkar":
            return "sunken temple"
        return s2

    for spec in FOREVER_DUNGEONS:
        drec = {
            "name": spec["name"],
            "lo": spec["lo"],
            "hi": spec["hi"],
            "raid": spec["raid"],
            "zones": list(spec["zones"]),
            "phrases": spec["phrases"],
            "pin_by_zone": {},
            "quests": [],
        }
        dung_by_name[norm_dname(spec["name"])] = drec
        u0, x0, y0 = spec["zones"][0]
        info0 = (u0, float(x0), float(y0), spec["name"])
        for z in spec["zos"]:
            zos_to_dung[z] = drec
            dungeon_entrance[z] = info0
        for uimap, ex, ey in spec["zones"]:
            spot_key = (norm_dname(spec["name"]), uimap)
            if spot_key not in seen_dungeon_spots:
                seen_dungeon_spots.add(spot_key)
                dungeon_rows.append((0, spec["name"], uimap, float(ex), float(ey), spec["lo"], spec["hi"], spec["raid"]))

    for d_area, entry in sorted(dungeons.items()):
        dname = entry.get(1)
        if not isinstance(dname, str) or not dname:
            continue
        alts = dict_to_list(entry.get(2, {}))
        locs = dict_to_list(entry.get(4, {}))
        mapped_locs = []
        for loc in locs:
            if not isinstance(loc, dict):
                continue
            ent_area, ex, ey = loc.get(1), loc.get(2), loc.get(3)
            uimap = area_to_uimap.get(ent_area, 0) if isinstance(ent_area, int) else 0
            if uimap and uimap > 0 and uimap not in (947, 1414, 1415) and isinstance(ex, (int, float)) and isinstance(ey, (int, float)):
                mapped_locs.append((uimap, float(ex), float(ey)))
        if not mapped_locs:
            continue
        uimap0, ex0, ey0 = mapped_locs[0]
        info = (uimap0, ex0, ey0, dname)
        if d_area not in dungeon_entrance:
            dungeon_entrance[d_area] = info
        for a in alts:
            if isinstance(a, int) and a not in dungeon_entrance:
                dungeon_entrance[a] = info
        spot_key = (norm_dname(dname), uimap0)
        if spot_key not in seen_dungeon_spots:
            seen_dungeon_spots.add(spot_key)
            dungeon_rows.append((d_area, dname, uimap0, ex0, ey0, 0, 0, False))

    def spawns_by_uimap(spawns_tbl) -> list[tuple[int, float, float, int, str | None]]:
        """Return [(uiMapID, med_x_pct, med_y_pct, count, dungeonName), ...] sorted by count desc."""
        if not isinstance(spawns_tbl, dict):
            return []
        grouped: dict[int, list[tuple[float, float]]] = {}
        dung_hits: list[tuple[int, float, float, int, str]] = []
        for area_id, coords_tbl in spawns_tbl.items():
            if not isinstance(area_id, int) or not isinstance(coords_tbl, dict):
                continue
            pts = [
                (float(pt[1]), float(pt[2]))
                for pt in dict_to_list(coords_tbl)
                if isinstance(pt, dict)
                and isinstance(pt.get(1), (int, float))
                and isinstance(pt.get(2), (int, float))
                and 0 <= pt.get(1) <= 100
                and 0 <= pt.get(2) <= 100
            ]
            if not pts:
                if area_id in dungeon_entrance:
                    du, dx, dy, dn = dungeon_entrance[area_id]
                    dung_hits.append((du, dx, dy, 1, dn))
                continue
            uimap = area_to_uimap.get(area_id, 0)
            if uimap and uimap > 0 and uimap not in (947, 1414, 1415):
                grouped.setdefault(uimap, []).extend(pts)
            elif area_id in dungeon_entrance:
                du, dx, dy, dn = dungeon_entrance[area_id]
                dung_hits.append((du, dx, dy, len(pts), dn))

        res: list[tuple[int, float, float, int, str | None]] = []
        for uimap, pts in grouped.items():
            mx = sum(p[0] for p in pts) / len(pts)
            my = sum(p[1] for p in pts) / len(pts)
            med = min(pts, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)
            res.append((uimap, med[0], med[1], len(pts), None))
        res.sort(key=lambda r: (-r[3], r[0]))
        if res:
            return res
        return dung_hits[:1]

    def best_spawn(spawns_tbl, prefer_uimap: int | None = None):
        all_sp = spawns_by_uimap(spawns_tbl)
        if not all_sp:
            return None
        if prefer_uimap:
            for sp in all_sp:
                if sp[0] == prefer_uimap:
                    return sp
        return all_sp[0]

    # Reverse quest starts/ends from NPCs, Objects, Items + Rare signature drops
    npc_starts: dict[int, list[int]] = {}
    npc_ends: dict[int, list[int]] = {}
    rare_nids: set[int] = set()
    for nid, row in npcs.items():
        if row.get(6) in (2, 4):
            rare_nids.add(nid)
        for q in dict_to_list(row.get(10, {})):
            if isinstance(q, int):
                npc_starts.setdefault(q, []).append(nid)
        for q in dict_to_list(row.get(11, {})):
            if isinstance(q, int):
                npc_ends.setdefault(q, []).append(nid)

    rare_cand_items: dict[int, set[int]] = {}
    item_dropper_count: dict[int, int] = {}
    for iid, row in items.items():
        droppers = [n for n in dict_to_list(row.get(2, {})) if isinstance(n, int)]
        dr_tbl = item_drops.get(iid)
        if isinstance(dr_tbl, dict):
            all_d = set(droppers) | {k for k in dr_tbl.keys() if isinstance(k, int)}
        else:
            all_d = set(droppers)
        if not all_d:
            continue
        item_dropper_count[iid] = len(all_d)
        for nid in all_d:
            if nid in rare_nids:
                rare_cand_items.setdefault(nid, set()).add(iid)

    def rare_notable_drops(nid: int) -> list[tuple[int, str, float]]:
        cands = rare_cand_items.get(nid)
        if not cands:
            return []
        primary: list[tuple[float, int, str, float]] = []
        fallback: list[tuple[float, int, str, float]] = []
        for iid in cands:
            irow = items.get(iid)
            if not irow:
                continue
            iname = irow.get(1)
            if not isinstance(iname, str) or not iname.strip() or BAD_NAME_RX.search(iname):
                continue
            dcnt = item_dropper_count.get(iid, 999)
            icls = irow.get(12) if isinstance(irow.get(12), int) else -1
            ilvl = irow.get(9) if isinstance(irow.get(9), int) else 0
            start_q = irow.get(5) if isinstance(irow.get(5), int) else 0
            teaches = irow.get(16) if isinstance(irow.get(16), int) else 0
            dr_tbl = item_drops.get(iid)
            rate = float(dr_tbl.get(nid, 0.0)) if isinstance(dr_tbl, dict) and isinstance(dr_tbl.get(nid), (int, float)) else 0.0
            is_gear_or_special = icls in (1, 2, 4, 9) or start_q > 0 or teaches > 0
            score = (
                (200.0 if dcnt <= 2 else (100.0 if dcnt <= 6 else (40.0 if dcnt <= 18 else 0.0)))
                + (80.0 if icls in (2, 4) else (70.0 if icls in (1, 9) or start_q > 0 or teaches > 0 else 0.0))
                + min(rate, 100.0) * 0.6
                + ilvl * 0.4
            )
            entry = (score, iid, iname.strip(), rate)
            if (dcnt <= 18 or start_q > 0 or icls == 9 or teaches > 0) and (is_gear_or_special or dcnt <= 3):
                primary.append(entry)
            elif (is_gear_or_special and dcnt <= 60) or (rate >= 5.0 and dcnt <= 40):
                fallback.append(entry)
        primary.sort(key=lambda x: (-x[0], -x[3], x[2]))
        fallback.sort(key=lambda x: (-x[0], -x[3], x[2]))
        out: list[tuple[int, str, float]] = []
        seen_names: set[str] = set()
        for _sc, iid, nm, rate in primary:
            if nm not in seen_names:
                seen_names.add(nm)
                out.append((iid, nm, rate))
                if len(out) >= 8:
                    return out
        if len(out) < 4:
            for _sc, iid, nm, rate in fallback:
                if nm not in seen_names:
                    seen_names.add(nm)
                    out.append((iid, nm, rate))
                    if len(out) >= 6:
                        break
        return out

    obj_starts: dict[int, list[int]] = {}
    obj_ends: dict[int, list[int]] = {}
    for oid, row in objs.items():
        for q in dict_to_list(row.get(2, {})):
            if isinstance(q, int):
                obj_starts.setdefault(q, []).append(oid)
        for q in dict_to_list(row.get(3, {})):
            if isinstance(q, int):
                obj_ends.setdefault(q, []).append(oid)

    item_starts: dict[int, list[int]] = {}
    cand_rewards: dict[int, list[tuple[int, int, str, int]]] = {}
    for iid, row in sorted(items.items()):
        sq = row.get(5)
        if isinstance(sq, int) and sq > 0:
            item_starts.setdefault(sq, []).append(iid)
        q_rews = [q for q in dict_to_list(row.get(6, {})) if isinstance(q, int) and q > 0]
        if q_rews:
            iname = row.get(1)
            if isinstance(iname, str) and iname.strip() and not BAD_NAME_RX.search(iname):
                icls = row.get(12) if isinstance(row.get(12), int) else -1
                ilvl = row.get(9) if isinstance(row.get(9), int) else 0
                teaches = row.get(16) if isinstance(row.get(16), int) else 0
                tier = 3 if icls in (2, 4) else (2 if (icls in (1, 9, 13) or teaches > 0) else (1 if icls != 12 else 0))
                entry = (-tier, -ilvl, iname.strip(), iid)
                for q in q_rews:
                    cand_rewards.setdefault(q, []).append(entry)

    quest_rewards_by_qid: dict[int, list[int]] = {}
    reward_item_names: dict[int, str] = {}
    for qid_k, cands in cand_rewards.items():
        cands.sort()
        picked: list[int] = []
        for _ntier, _nilvl, nm, iid in cands:
            if iid not in picked:
                picked.append(iid)
                reward_item_names[iid] = nm
                if len(picked) >= 6:
                    break
        if picked:
            quest_rewards_by_qid[qid_k] = picked

    pins: list[dict] = []
    npc_pin_by_map: dict[tuple[int, int], int] = {}   # (npc_id, uimap) -> 1-based pin index
    obj_pin_by_map: dict[tuple[int, int], int] = {}   # (obj_id, uimap) -> 1-based pin index
    objv_pin_by_key: dict[tuple[str, int, int], int] = {}  # (kind, id, uimap) -> 1-based pin index

    def add_pin(uimap: int, x_pct: float, y_pct: float, cat_key: str, title: str, text: str = "",
                fac: int = 3, lvl: int = 0, cls: int = 0, qid: int = 0) -> int:
        x01 = max(0.0, min(1.0, round(x_pct / 100.0, 5)))
        y01 = max(0.0, min(1.0, round(y_pct / 100.0, 5)))
        pins.append({
            "map": int(uimap),
            "x": x01,
            "y": y01,
            "cat": CAT_SLOT[cat_key],
            "fac": int(fac),
            "lvl": max(0, int(lvl or 0)),
            "cls": int(cls),
            "qid": int(qid),
            "endp": 0,
            "dest": 0,
            "title": title.strip(),
            "text": text.strip(),
            "pre": [],
            "nxt": 0,
            "obj": [],
            "rew": [],
            "drops": [],
        })
        return len(pins)

    # 1. Dungeon & Raid Entrances
    for _d_area, dname, uimap, ex, ey, lo, hi, is_raid in dungeon_rows:
        kind_lbl = "Raid" if is_raid else "Instance"
        lvl_line = f"\n{GOLD}Level:|r {lo}" if (lo > 0 and lo == hi) else (f"\n{GOLD}Level:|r {lo}-{hi}" if lo > 0 else "")
        pidx = add_pin(uimap, ex, ey, "instance", dname, f"{GOLD}{kind_lbl}:|r {dname}{lvl_line}", lvl=lo)
        drec = dung_by_name.get(norm_dname(dname))
        if drec and uimap not in drec["pin_by_zone"]:
            drec["pin_by_zone"][uimap] = pidx

    # 2. Townsfolk, Flight Masters, Spirit Healers & Rare Mobs (from foreverNpcDB)
    for nid, row in sorted(npcs.items()):
        name = row.get(1)
        if not isinstance(name, str) or not name.strip() or BAD_NAME_RX.search(name):
            continue
        flags = row.get(15) if isinstance(row.get(15), int) else 0
        rank = row.get(6) if isinstance(row.get(6), int) else 0
        sub = row.get(14) if isinstance(row.get(14), str) else ""
        min_lvl = row.get(4) if isinstance(row.get(4), int) else 0
        max_lvl = row.get(5) if isinstance(row.get(5), int) else min_lvl
        fac = friendly_to_fac(row.get(13) if isinstance(row.get(13), str) else None)

        cat_key = None
        cls_mask = 0
        if flags & 8:
            cat_key = "flight"
        elif flags & 32 or nid == 6491:
            cat_key = "graveyard"
            fac = 3
        elif flags & 4096:
            cat_key = "auctioneer"
        elif flags & 256:
            cat_key = "banker"
        elif flags & 128:
            cat_key = "innkeeper"
        elif flags & 8192:
            cat_key = "stable"
        elif flags & 16:
            sub_l = sub.lower()
            for word, cbit in CLASS_SUBNAME_WORDS:
                if word in sub_l and "pet" not in sub_l:
                    cls_mask = cbit
                    break
            cat_key = "class_trainer" if cls_mask else "prof_trainer"
        elif flags & 16384:
            cat_key = "repair"
        elif rank in (2, 4):
            cat_key = "rare"
            fac = 3
        elif flags & 4:
            cat_key = "vendor"

        if not cat_key:
            continue
        sp_list = spawns_by_uimap(row.get(7))
        if not sp_list:
            continue
        # Place once per zone (primary medoid per zone)
        info_lines = []
        if sub:
            info_lines.append(f"{GOLD}Role:|r {sub}")
        if min_lvl > 0:
            lvl_txt = f"{min_lvl}-{max_lvl}" if max_lvl > min_lvl else str(min_lvl)
            if rank == 2:
                lvl_txt += " (Rare Elite)"
            elif rank == 4:
                lvl_txt += " (Rare)"
            info_lines.append(f"{GOLD}Level:|r {lvl_txt}")
        rare_drop_pairs: list[int] = []
        if cat_key == "rare":
            drops = rare_notable_drops(nid)
            if drops:
                info_lines.append(f"{GOLD}Drops:|r " + ", ".join(nm for _iid, nm, _r in drops[:4]))
                for diid, dnm, drate in drops:
                    rare_drop_pairs.append(int(diid))
                    rare_drop_pairs.append(max(0, min(1000, int(round(drate * 10.0)))))
                    if diid not in reward_item_names:
                        reward_item_names[diid] = dnm
        desc = "\n".join(info_lines)
        for uimap, sx, sy, _cnt, dname in sp_list:
            if dname:
                continue  # skip inside-instance vendors/rares on world layer
            pidx = add_pin(uimap, sx, sy, cat_key, name, desc, fac=fac, lvl=min_lvl, cls=cls_mask)
            if rare_drop_pairs:
                pins[pidx - 1]["drops"] = list(rare_drop_pairs)
            npc_pin_by_map[(nid, uimap)] = pidx

    # 3. Mailboxes & World Chests / Lore Objects (from foreverObjectDB)
    seen_mailboxes: set[tuple[int, int, int]] = set()
    seen_treasures: set[tuple[str, int, int, int]] = set()
    for oid, row in sorted(objs.items()):
        name = row.get(1)
        if not isinstance(name, str) or not name.strip() or BAD_NAME_RX.search(name):
            continue
        nl = name.strip().lower()
        is_mail = nl == "mailbox"
        is_treas = not is_mail and bool(TREASURE_OBJ_RX.search(name)) and not SKIP_OBJ_RX.search(name)
        if not (is_mail or is_treas):
            continue
        sp_list = spawns_by_uimap(row.get(4))
        for uimap, sx, sy, _cnt, dname in sp_list:
            if dname:
                continue
            gx, gy = int(round(sx * 2)), int(round(sy * 2))
            if is_mail:
                mk = (uimap, gx, gy)
                if mk in seen_mailboxes:
                    continue
                seen_mailboxes.add(mk)
                pidx = add_pin(uimap, sx, sy, "mailbox", "Mailbox", "")
                obj_pin_by_map[(oid, uimap)] = pidx
            else:
                tk = (nl, uimap, gx, gy)
                if tk in seen_treasures:
                    continue
                seen_treasures.add(tk)
                pidx = add_pin(uimap, sx, sy, "treasure", name, "")
                obj_pin_by_map[(oid, uimap)] = pidx

    # Helper to get or create a Turn-In pin for an NPC or Object
    def ensure_finisher_pin(kind: str, eid: int, prefer_uimap: int | None) -> tuple[int, str]:
        if kind == "npc":
            nr = npcs.get(eid)
            if not nr:
                return 0, ""
            ename = nr.get(1) if isinstance(nr.get(1), str) else f"NPC #{eid}"
            sp = best_spawn(nr.get(7), prefer_uimap)
            if not sp:
                return 0, ename
            uimap, sx, sy, _cnt, dname = sp
            existing = npc_pin_by_map.get((eid, uimap))
            if existing:
                return existing, ename
            sub = nr.get(14) if isinstance(nr.get(14), str) else ""
            fac = friendly_to_fac(nr.get(13) if isinstance(nr.get(13), str) else None)
            note = f"{GOLD}In:|r {dname}" if dname else (f"{GOLD}Role:|r {sub}" if sub else "Quest turn-in")
            pidx = add_pin(uimap, sx, sy, "turnin", ename, note, fac=fac)
            npc_pin_by_map[(eid, uimap)] = pidx
            return pidx, ename
        else:
            orow = objs.get(eid)
            if not orow:
                return 0, ""
            ename = orow.get(1) if isinstance(orow.get(1), str) else f"Object #{eid}"
            sp = best_spawn(orow.get(4), prefer_uimap)
            if not sp:
                return 0, ename
            uimap, sx, sy, _cnt, dname = sp
            existing = obj_pin_by_map.get((eid, uimap))
            if existing:
                return existing, ename
            note = f"{GOLD}In:|r {dname}" if dname else "Quest turn-in object"
            pidx = add_pin(uimap, sx, sy, "turnin", ename, note, fac=3)
            obj_pin_by_map[(eid, uimap)] = pidx
            return pidx, ename

    # Helper to get or create a Quest Objective pin
    def ensure_objective_pin(kind: str, eid: int, label_override: str | None, prefer_uimap: int) -> int:
        if kind == "npc":
            nr = npcs.get(eid)
            if not nr:
                return 0
            sp = best_spawn(nr.get(7), prefer_uimap)
            if not sp:
                return 0
            uimap, sx, sy, cnt, dname = sp
            key = ("npc", eid, uimap)
            if key in objv_pin_by_key:
                return objv_pin_by_key[key]
            ename = label_override or (nr.get(1) if isinstance(nr.get(1), str) else f"Target #{eid}")
            min_l = nr.get(4) if isinstance(nr.get(4), int) else 0
            max_l = nr.get(5) if isinstance(nr.get(5), int) else min_l
            lines = []
            if dname:
                lines.append(f"{GOLD}Instance:|r {dname}")
            if min_l > 0:
                lines.append(f"{GOLD}Level:|r {min_l}-{max_l}" if max_l > min_l else f"{GOLD}Level:|r {min_l}")
            if cnt > 1:
                lines.append(f"{GOLD}Spawns in area:|r {cnt}")
            pidx = add_pin(uimap, sx, sy, "objective", ename, "\n".join(lines), fac=3, lvl=min_l)
            objv_pin_by_key[key] = pidx
            return pidx
        elif kind == "obj":
            orow = objs.get(eid)
            if not orow:
                return 0
            sp = best_spawn(orow.get(4), prefer_uimap)
            if not sp:
                return 0
            uimap, sx, sy, cnt, dname = sp
            key = ("obj", eid, uimap)
            if key in objv_pin_by_key:
                return objv_pin_by_key[key]
            ename = label_override or (orow.get(1) if isinstance(orow.get(1), str) else f"Object #{eid}")
            note = f"{GOLD}Instance:|r {dname}" if dname else (f"{GOLD}Locations:|r {cnt}" if cnt > 1 else "Quest objective")
            pidx = add_pin(uimap, sx, sy, "objective", ename, note, fac=3)
            objv_pin_by_key[key] = pidx
            return pidx
        return 0

    def best_item_drop_source(item_id: int, prefer_uimap: int) -> tuple[str, int, str] | None:
        irow = items.get(item_id)
        if not irow:
            return None
        iname = irow.get(1) if isinstance(irow.get(1), str) else f"Item #{item_id}"
        drops_rate = item_drops.get(item_id) if isinstance(item_drops.get(item_id), dict) else {}
        cand_npcs = dict_to_list(irow.get(2, {}))
        if drops_rate:
            cand_npcs = sorted(
                set(cand_npcs) | {k for k in drops_rate.keys() if isinstance(k, int)},
                key=lambda nid: -(float(drops_rate.get(nid, 0.0)) if isinstance(drops_rate.get(nid), (int, float)) else 0.0),
            )
        # First pass: NPC in the quest's own zone!
        for nid in cand_npcs[:60]:
            nr = npcs.get(nid)
            if nr:
                sp = best_spawn(nr.get(7), prefer_uimap)
                if sp and sp[0] == prefer_uimap:
                    nname = nr.get(1) if isinstance(nr.get(1), str) else f"NPC #{nid}"
                    return ("npc", nid, f"{iname} ({nname})")
        # Object drops in the quest's zone or anywhere
        for oid in dict_to_list(irow.get(3, {}))[:20]:
            orow = objs.get(oid)
            if orow and best_spawn(orow.get(4), prefer_uimap):
                oname = orow.get(1) if isinstance(orow.get(1), str) else f"Object #{oid}"
                return ("obj", oid, f"{iname} ({oname})")
        # Second pass: highest drop-rate NPC anywhere
        for nid in cand_npcs[:30]:
            nr = npcs.get(nid)
            if nr and best_spawn(nr.get(7), prefer_uimap):
                nname = nr.get(1) if isinstance(nr.get(1), str) else f"NPC #{nid}"
                return ("npc", nid, f"{iname} ({nname})")
        return None

    # 4. Quests (from foreverQuestDB + all Forever delta/trace/authored layers)
    quest_pin_by_qid: dict[int, int] = {}
    quest_raw_links: list[tuple[int, int]] = []  # (pin_idx, qid)

    for qid, q in sorted(quests.items()):
        title = q.get(1)
        if not isinstance(title, str) or not title.strip() or BAD_NAME_RX.search(title):
            continue
        sb = q.get(2) if isinstance(q.get(2), dict) else {}
        c_starts = dict_to_list(sb.get(1, {})) or npc_starts.get(qid, [])
        o_starts = dict_to_list(sb.get(2, {})) or obj_starts.get(qid, [])
        i_starts = dict_to_list(sb.get(3, {})) or item_starts.get(qid, [])

        loc = None
        starter_label = ""
        starter_fac = 3

        for nid in c_starts:
            nr = npcs.get(nid)
            if nr:
                sp = best_spawn(nr.get(7))
                if sp:
                    loc = sp
                    starter_label = nr.get(1) if isinstance(nr.get(1), str) else ""
                    starter_fac = friendly_to_fac(nr.get(13) if isinstance(nr.get(13), str) else None)
                    break
        if not loc:
            for oid in o_starts:
                orow = objs.get(oid)
                if orow:
                    sp = best_spawn(orow.get(4))
                    if sp:
                        loc = sp
                        starter_label = orow.get(1) if isinstance(orow.get(1), str) else ""
                        break
        if not loc:
            for iid in i_starts:
                irow = items.get(iid)
                if irow:
                    iname = irow.get(1) if isinstance(irow.get(1), str) else f"Item #{iid}"
                    src = best_item_drop_source(iid, 0)
                    if src:
                        skind, sid, _ = src
                        sp = best_spawn((npcs[sid].get(7) if skind == "npc" else objs[sid].get(4)))
                        if sp:
                            loc = sp
                            starter_label = f"{iname} (item)"
                            break
                    for vid in dict_to_list(irow.get(14, {})):
                        nr = npcs.get(vid)
                        if nr:
                            sp = best_spawn(nr.get(7))
                            if sp:
                                loc = sp
                                starter_label = f"{iname} (vendor)"
                                break
                if loc:
                    break
        zos = q.get(17)
        is_seasonal = isinstance(zos, int) and zos in SEASONAL_SORT_KEYS
        obj_texts = [s.strip() for s in dict_to_list(q.get(8, {})) if isinstance(s, str) and s.strip()]
        matched_dung = zos_to_dung.get(zos) if isinstance(zos, int) else None
        if not matched_dung and not is_seasonal and loc and loc[4]:
            matched_dung = dung_by_name.get(norm_dname(loc[4]))
        if not matched_dung and not is_seasonal:
            blob = (title + " " + " ".join(obj_texts)).lower()
            for spec_rec in dung_by_name.values():
                if any(ph in blob for ph in spec_rec["phrases"]):
                    matched_dung = spec_rec
                    break

        if not loc:
            if matched_dung:
                du, dx, dy = matched_dung["zones"][0]
                loc = (du, float(dx), float(dy), 1, matched_dung["name"])
            elif isinstance(zos, int) and zos > 0 and zos in dungeon_entrance:
                du, dx, dy, dn = dungeon_entrance[zos]
                loc = (du, dx, dy, 1, dn)

        if not loc:
            continue

        uimap, sx, sy, _cnt, start_dname = loc
        inst_name = matched_dung["name"] if matched_dung else start_dname
        req_lvl = q.get(4) if isinstance(q.get(4), int) else 0
        q_lvl = q.get(5) if isinstance(q.get(5), int) else req_lvl
        if q_lvl < 0:
            q_lvl = req_lvl
        fac = quest_faction(q.get(6) if isinstance(q.get(6), int) else 0, starter_fac)
        cls_mask = convert_class_mask(q.get(7) if isinstance(q.get(7), int) else 0)
        q_flags = q.get(23) if isinstance(q.get(23), int) else 0
        sp_flags = q.get(24) if isinstance(q.get(24), int) else 0
        is_rep = (sp_flags & 1) != 0 or (q_flags & (4096 | 32768 | 65536)) != 0
        cat_key = "repeatable" if is_rep else "quest"

        # Build clean, informative tooltip text
        desc_lines: list[str] = []
        if q_lvl > 0 or req_lvl > 0:
            if q_lvl > 0 and req_lvl > 0 and req_lvl != q_lvl:
                desc_lines.append(f"{GOLD}Level:|r {q_lvl} (requires {req_lvl})")
            else:
                desc_lines.append(f"{GOLD}Level:|r {q_lvl or req_lvl}")
        if inst_name:
            desc_lines.append(f"{GOLD}Instance:|r {inst_name}")
        if starter_label:
            desc_lines.append(f"{GOLD}Start:|r {starter_label}")
        if obj_texts:
            joined = " ".join(obj_texts)
            if len(joined) > 260:
                joined = joined[:257].rstrip() + "..."
            desc_lines.append(joined)

        pidx = add_pin(uimap, sx, sy, cat_key, title, "\n".join(desc_lines), fac=fac, lvl=q_lvl, cls=cls_mask, qid=qid)
        q_rew_ids = quest_rewards_by_qid.get(qid)
        if q_rew_ids:
            pins[pidx - 1]["rew"] = q_rew_ids
        if matched_dung:
            matched_dung["quests"].append(pidx)
        quest_pin_by_qid[qid] = pidx
        quest_raw_links.append((pidx, qid))

        # Resolve finisher (endp)
        fb = q.get(3) if isinstance(q.get(3), dict) else {}
        c_ends = dict_to_list(fb.get(1, {})) or npc_ends.get(qid, [])
        o_ends = dict_to_list(fb.get(2, {})) or obj_ends.get(qid, [])
        end_pidx = 0
        for nid in c_ends:
            end_pidx, _ = ensure_finisher_pin("npc", nid, uimap)
            if end_pidx:
                break
        if not end_pidx:
            for oid in o_ends:
                end_pidx, _ = ensure_finisher_pin("obj", oid, uimap)
                if end_pidx:
                    break
        if not end_pidx and isinstance(q.get(9), dict):
            trig = q.get(9)
            tlabel = trig.get(1) if isinstance(trig.get(1), str) and trig.get(1) else f"{title} (Complete)"
            tsp = best_spawn(trig.get(2), uimap)
            if tsp:
                end_pidx = add_pin(tsp[0], tsp[1], tsp[2], "turnin", tlabel, "Quest completion spot", fac=fac)
        if end_pidx and end_pidx != pidx:
            pins[pidx - 1]["endp"] = end_pidx

        # Resolve quest objective spawn clusters (up to 4 per quest)
        obj_tbl = q.get(10) if isinstance(q.get(10), dict) else {}
        obj_pins: list[int] = []

        # 1: creatureObjective {{npcId, text?}, ...}
        for entry in dict_to_list(obj_tbl.get(1, {}))[:4]:
            if isinstance(entry, dict) and isinstance(entry.get(1), int):
                op = ensure_objective_pin("npc", entry[1], entry.get(2) if isinstance(entry.get(2), str) else None, uimap)
                if op and op not in obj_pins:
                    obj_pins.append(op)
        # 2: objectObjective {{objId, text?}, ...}
        for entry in dict_to_list(obj_tbl.get(2, {}))[:4]:
            if isinstance(entry, dict) and isinstance(entry.get(1), int):
                op = ensure_objective_pin("obj", entry[1], entry.get(2) if isinstance(entry.get(2), str) else None, uimap)
                if op and op not in obj_pins:
                    obj_pins.append(op)
        # 3: itemObjective {{itemId, text?}, ...}
        for entry in dict_to_list(obj_tbl.get(3, {}))[:4]:
            if len(obj_pins) >= 4:
                break
            if isinstance(entry, dict) and isinstance(entry.get(1), int):
                src = best_item_drop_source(entry[1], uimap)
                if src:
                    op = ensure_objective_pin(src[0], src[1], src[2], uimap)
                    if op and op not in obj_pins:
                        obj_pins.append(op)
        # 5: killCreditObjective {{{npcIds...}, rootNpcId, text?}, ...}
        for entry in dict_to_list(obj_tbl.get(5, {}))[:3]:
            if len(obj_pins) >= 4:
                break
            if isinstance(entry, dict):
                root_id = entry.get(2) if isinstance(entry.get(2), int) else None
                id_list = dict_to_list(entry.get(1, {}))
                cand_id = root_id if (root_id and root_id in npcs) else (id_list[0] if id_list else None)
                if isinstance(cand_id, int):
                    op = ensure_objective_pin("npc", cand_id, entry.get(3) if isinstance(entry.get(3), str) else None, uimap)
                    if op and op not in obj_pins:
                        obj_pins.append(op)
        # triggerEnd scout spot if not already used as endp
        if len(obj_pins) < 4 and isinstance(q.get(9), dict):
            trig = q.get(9)
            tsp = best_spawn(trig.get(2), uimap)
            if tsp:
                tlabel = trig.get(1) if isinstance(trig.get(1), str) and trig.get(1) else f"{title} (Objective)"
                key = ("trig", qid, tsp[0])
                if key not in objv_pin_by_key:
                    objv_pin_by_key[key] = add_pin(tsp[0], tsp[1], tsp[2], "objective", tlabel, "Quest objective", fac=fac, lvl=q_lvl)
                op = objv_pin_by_key[key]
                if op != pins[pidx - 1]["endp"] and op not in obj_pins:
                    obj_pins.append(op)

        if obj_pins:
            pins[pidx - 1]["obj"] = obj_pins[:4]

    # 5. Wire prerequisite chains (preQuestGroup, small preQuestSingle, parentQuest, and nextQuestInChain)
    pre_qids_of: dict[int, list[int]] = {}
    for pidx, qid in quest_raw_links:
        q = quests[qid]
        pres: list[int] = []
        grp = [pq for pq in dict_to_list(q.get(12, {})) if isinstance(pq, int) and pq > 0 and pq != qid]
        if len(grp) <= 4:
            for pq in grp:
                if pq not in pres:
                    pres.append(pq)
        sgl = [pq for pq in dict_to_list(q.get(13, {})) if isinstance(pq, int) and pq > 0 and pq != qid]
        if len(sgl) <= 2:
            for pq in sgl:
                if pq not in pres:
                    pres.append(pq)
        parent_q = q.get(25)
        if isinstance(parent_q, int) and parent_q > 0 and parent_q != qid and parent_q not in pres:
            pres.append(parent_q)
        if pres:
            pre_qids_of[qid] = pres
        nxt = q.get(22)
        if isinstance(nxt, int) and nxt > 0 and nxt != qid:
            if nxt in quest_pin_by_qid:
                pins[pidx - 1]["nxt"] = quest_pin_by_qid[nxt]
            nxt_pres = pre_qids_of.setdefault(nxt, [])
            if qid not in nxt_pres:
                nxt_pres.append(qid)

    def has_path(src_q: int, dst_q: int) -> bool:
        seen = set()
        stack = [src_q]
        while stack:
            cur = stack.pop()
            if cur == dst_q:
                return True
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(pre_qids_of.get(cur, ()))
        return False

    pre_links = 0
    for pidx, qid in quest_raw_links:
        pin_pres: list[int] = []
        for pq in pre_qids_of.get(qid, ()):
            # Guard against mutual/cyclic preQuest links in trace data
            if pq in quest_pin_by_qid and not has_path(pq, qid):
                target_pin = quest_pin_by_qid[pq]
                if target_pin != pidx and target_pin not in pin_pres:
                    pin_pres.append(target_pin)
                    pre_links += 1
        pins[pidx - 1]["pre"] = pin_pres

    # Propagate faction across same-zone duplicate-title twin chains (e.g. Zephras Isle Alliance vs Horde campaign twins)
    twins_by_zone_title: dict[tuple[int, str], list[int]] = {}
    for pidx, _qid in quest_raw_links:
        p = pins[pidx - 1]
        twins_by_zone_title.setdefault((p["map"], p["title"].lower()), []).append(pidx)
    rev_next: dict[int, list[int]] = {}
    for pidx, _qid in quest_raw_links:
        for pr in pins[pidx - 1]["pre"]:
            rev_next.setdefault(pr, []).append(pidx)
    for _pass in range(4):
        for (_z, _tl), tlist in twins_by_zone_title.items():
            if len(tlist) != 2:
                continue
            for ti in tlist:
                p = pins[ti - 1]
                if p["fac"] != 3:
                    continue
                linked_facs = {
                    pins[nb - 1]["fac"]
                    for nb in (list(p["pre"]) + rev_next.get(ti, []))
                    if pins[nb - 1]["fac"] in (1, 2)
                }
                if len(linked_facs) == 1:
                    p["fac"] = next(iter(linked_facs))

    # 6. Gently fan out co-located quest pins on the exact same NPC spot so every quest is hoverable
    spot_quests: dict[tuple[int, int, int], list[int]] = {}
    quest_slots = {CAT_SLOT["quest"], CAT_SLOT["repeatable"]}
    for idx, pin in enumerate(pins):
        if pin["cat"] in quest_slots:
            sk = (pin["map"], int(round(pin["x"] * 2000)), int(round(pin["y"] * 2000)))
            spot_quests.setdefault(sk, []).append(idx)
    for sk, idxs in spot_quests.items():
        if len(idxs) <= 1:
            continue
        cx = sum(pins[i]["x"] for i in idxs) / len(idxs)
        cy = sum(pins[i]["y"] for i in idxs) / len(idxs)
        radius = min(0.0045, 0.0014 + 0.00035 * len(idxs))
        for k, i in enumerate(idxs):
            angle = (2.0 * math.pi * k) / len(idxs)
            pins[i]["x"] = max(0.001, min(0.999, round(cx + radius * math.cos(angle), 5)))
            pins[i]["y"] = max(0.001, min(0.999, round(cy + radius * math.sin(angle), 5)))

    # 7. Compute clean zone level brackets [uiMapID] = (min_lvl, max_lvl)
    q_lvls_by_map: dict[int, list[int]] = {}
    m_lvls_by_map: dict[int, list[int]] = {}
    for p in pins:
        lv = p["lvl"]
        if 1 <= lv <= 60:
            if p["cat"] in quest_slots:
                q_lvls_by_map.setdefault(p["map"], []).append(lv)
            elif p["cat"] in (CAT_SLOT["rare"], CAT_SLOT["objective"]):
                m_lvls_by_map.setdefault(p["map"], []).append(lv)
    zone_levels: dict[int, tuple[int, int]] = {}
    for uimap in sorted(set(q_lvls_by_map.keys()) | set(m_lvls_by_map.keys())):
        arr = sorted(q_lvls_by_map.get(uimap) or m_lvls_by_map.get(uimap) or [])
        if not arr:
            continue
        if len(arr) >= 8:
            lo = arr[max(0, int(len(arr) * 0.08))]
            hi = arr[min(len(arr) - 1, int(len(arr) * 0.92))]
        else:
            lo, hi = arr[0], arr[-1]
        zone_levels[uimap] = (lo, max(lo, hi))

    # 8. Build per-zone dungeon & dungeon-quest index [uiMapID] = { { name, pin, lo, hi, raid, quests = {...} }, ... }
    zone_dungeons: dict[int, list[dict]] = {}
    for drec in dung_by_name.values():
        q_sorted = sorted(
            drec["quests"],
            key=lambda pi: (pins[pi - 1]["lvl"] or 999, pins[pi - 1]["title"], pi),
        )
        for uimap, _ex, _ey in drec["zones"]:
            epin = drec["pin_by_zone"].get(uimap, 0)
            zone_dungeons.setdefault(uimap, []).append({
                "name": drec["name"],
                "pin": epin,
                "lo": drec["lo"],
                "hi": drec["hi"],
                "raid": drec["raid"],
                "quests": q_sorted,
            })
    for uimap, dlist in zone_dungeons.items():
        dlist.sort(key=lambda d: (1 if d["raid"] else 0, d["lo"], d["hi"], d["name"]))

    stats = {
        "pins": len(pins),
        "quests": len(quest_pin_by_qid),
        "endp": sum(1 for p in pins if p["endp"] != 0),
        "pre": pre_links,
        "obj": sum(len(p["obj"]) for p in pins),
        "rew_quests": sum(1 for p in pins if p["rew"]),
        "rew_items": len(reward_item_names),
        "rare_with_drops": sum(1 for p in pins if p["cat"] == CAT_SLOT["rare"] and "Drops:|r" in p["text"]),
        "dungeons": len(dung_by_name),
        "dungeon_quests": sum(len(d["quests"]) for d in dung_by_name.values()),
    }
    return pins, zone_levels, zone_dungeons, reward_item_names, stats


def render_data_lua(
    pins: list[dict],
    zone_levels: dict[int, tuple[int, int]],
    zone_dungeons: dict[int, list[dict]],
    reward_item_names: dict[int, str],
    stamp: str,
    ref: str,
    out_lua: str,
) -> None:
    lines = [
        "-- daves_map_data / Data.lua -- GENERATED by daves_map/tools/Update-MapData.py from Questie/QuestieDB (Forever).",
        f"-- Built: {stamp} (QuestieDB@{ref}). See NOTICE-QuestieDB.md.",
        "local ADDON, ns = ...",
        'ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"',
        "DAVES_MAP_DATA = {",
        'source = { url = "https://github.com/Questie/QuestieDB", map = "QuestieDB Forever", mapId = 947, fetched = %s, questDb = %s },'
        % (lua_str(stamp), lua_str(f"QuestieDB@{ref}")),
        "groups = {",
    ]
    for g in GROUPS:
        gcats = [idx for idx, c in enumerate(CATEGORIES, start=1) if c["group"] == g["id"]]
        lines.append(f"  {{ id = {g['id']}, title = {lua_str(g['title'])}, cats = {num_list(gcats)} }},")
    lines.append("},")
    lines.append("cats = {")
    for c in CATEGORIES:
        doff = ", defaultOff = true" if c["defaultOff"] else ""
        lines.append(
            f'  {{ id = {c["id"]}, title = {lua_str(c["title"])}, icon = {lua_str(c["icon"])}, '
            f'color = {lua_str(c["color"])}, group = {c["group"]}, info = ""{doff} }},'
        )
    lines.append("},")

    def col_num(name: str, key: str) -> None:
        lines.append(name + " = {" + ",".join(lua_num(p[key]) for p in pins) + "},")

    col_num("map", "map")
    col_num("x", "x")
    col_num("y", "y")
    col_num("cat", "cat")
    col_num("fac", "fac")
    col_num("lvl", "lvl")
    col_num("cls", "cls")
    col_num("qid", "qid")
    col_num("endp", "endp")
    col_num("dest", "dest")

    lines.append("title = {")
    for p in pins:
        lines.append(lua_str(p["title"]) + ",")
    lines.append("},")

    lines.append("text = {")
    for p in pins:
        lines.append(lua_str(p["text"]) + ",")
    lines.append("},")

    lines.append("pre = {")
    for idx, p in enumerate(pins, start=1):
        if p["pre"]:
            lines.append(f"  [{idx}] = {num_list(p['pre'])},")
    lines.append("},")

    lines.append("nxt = {")
    for idx, p in enumerate(pins, start=1):
        if p["nxt"]:
            lines.append(f"  [{idx}] = {p['nxt']},")
    lines.append("},")

    lines.append("obj = {")
    for idx, p in enumerate(pins, start=1):
        if p["obj"]:
            lines.append(f"  [{idx}] = {num_list(p['obj'])},")
    lines.append("},")

    lines.append("rew = {")
    for idx, p in enumerate(pins, start=1):
        if p["rew"]:
            lines.append(f"  [{idx}] = {num_list(p['rew'])},")
    lines.append("},")

    lines.append("drops = {")
    for idx, p in enumerate(pins, start=1):
        if p["drops"]:
            lines.append(f"  [{idx}] = {num_list(p['drops'])},")
    lines.append("},")

    lines.append("iname = {")
    used_iids = sorted(
        {iid for p in pins for iid in p["rew"] if iid in reward_item_names}
        | {p["drops"][k] for p in pins for k in range(0, len(p["drops"]), 2) if p["drops"][k] in reward_item_names}
    )
    for iid in used_iids:
        lines.append(f"  [{iid}] = {lua_str(reward_item_names[iid])},")
    lines.append("},")

    lines.append("zones = {")
    for uimap, (lo, hi) in sorted(zone_levels.items()):
        lines.append(f"  [{uimap}] = {{{lo},{hi}}},")
    lines.append("},")

    lines.append("dungeons = {")
    for uimap, dlist in sorted(zone_dungeons.items()):
        lines.append(f"  [{uimap}] = {{")
        for d in dlist:
            rflag = ", raid = true" if d["raid"] else ""
            lines.append(
                f"    {{ name = {lua_str(d['name'])}, pin = {d['pin']}, lo = {d['lo']}, hi = {d['hi']}{rflag}, quests = {num_list(d['quests'])} }},"
            )
        lines.append("  },")
    lines.append("},")

    lines.append("}")
    os.makedirs(os.path.dirname(out_lua), exist_ok=True)
    with open(out_lua, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def write_companion_meta(qdb_root: str, addon_dir: str, out_dir: str, ver_date: str) -> None:
    map_toc = os.path.join(addon_dir, "daves_map.toc")
    toc_text = open(map_toc, encoding="utf-8-sig").read()
    m = re.search(r"(?m)^## Interface:\s*(.+?)\s*$", toc_text)
    if not m:
        raise RuntimeError(f"No '## Interface:' line in {map_toc}")
    iface = m.group(1)

    toc_out = (
        f"## Interface: {iface}\n"
        "## Title: |cffd4a94eDave's|r Map (data)\n"
        "## Notes: QuestieDB Forever quests, objectives, turn-ins, chains, townsfolk and rares for Dave's Map.\n"
        "## Author: davidwhit5 (data: Questie/QuestieDB contributors, NOTICE-QuestieDB.md)\n"
        f"## Version: {ver_date}\n"
        "## IconTexture: Interface\\Icons\\INV_Misc_Map_01\n"
        "\n"
        "Data.lua\n"
    )
    with open(os.path.join(out_dir, "daves_map_data.toc"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(toc_out)

    luacheck_rc = (
        'std = "lua51"\n'
        "max_line_length = false\n"
        "codes = true\n"
        'exclude_files = { "Data.lua" }\n'
        'ignore = { "113", "143", "212", "542" }\n'
        'globals = { "DAVES_MAP_DATA" }\n'
    )
    with open(os.path.join(out_dir, ".luacheckrc"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(luacheck_rc)

    lic_path = os.path.join(qdb_root, "LICENSE.md")
    lic_body = open(lic_path, encoding="utf-8").read().strip() if os.path.isfile(lic_path) else ""
    notice = (
        "# QuestieDB Data Attribution (`daves_map_data`)\n\n"
        "`daves_map_data/Data.lua` is compiled by `daves_map/tools/Update-MapData.py` from the open-source "
        "[Questie/QuestieDB](https://github.com/Questie/QuestieDB) WoW: Forever dataset "
        "(including `data/Forever/`, `src/corrections/Forever/`, and `support/Forever/`). "
        "`daves_map` is an independent addon and is not affiliated with or endorsed by the Questie team.\n\n"
        "---\n\n"
        + lic_body
        + "\n"
    )
    with open(os.path.join(out_dir, "NOTICE-QuestieDB.md"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(notice)


def _parse_args(argv: list[str]) -> dict:
    out = {"Ref": "master", "LocalDir": "", "KeepRaw": False}
    i = 0
    while i < len(argv):
        tok = argv[i]
        if not tok.startswith("-"):
            raise RuntimeError(f"Unknown argument: {tok}")
        raw = tok[1:]
        if ":" in raw:
            k, v = raw.split(":", 1)
            take = False
        else:
            k, v, take = raw, None, True
        found = next((name for name in out if name.lower() == k.lower()), None)
        if not found:
            raise RuntimeError(f"Unknown argument: {tok}")
        if isinstance(out[found], bool):
            out[found] = True if v is None else v.strip().lower() not in ("false", "0", "$false")
        else:
            if take:
                if i + 1 >= len(argv):
                    raise RuntimeError(f"Missing value for -{found}")
                i += 1
                v = argv[i]
            out[found] = v or ""
        i += 1
    return out


def main(argv: list[str]) -> None:
    try:
        args = _parse_args(argv)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)

    tools_dir = os.path.dirname(os.path.abspath(__file__))
    addon_dir = os.path.dirname(tools_dir)
    wowaddons_dir = os.path.dirname(addon_dir)
    out_dir = os.path.join(wowaddons_dir, "daves_map_data")
    out_lua = os.path.join(out_dir, "Data.lua")

    temp_dir = None
    try:
        if args["LocalDir"]:
            qdb_root = os.path.abspath(args["LocalDir"])
            if not os.path.isdir(qdb_root):
                raise RuntimeError(f"-LocalDir not found: {qdb_root}")
            print(f"Reading QuestieDB Forever from local folder: {qdb_root}", flush=True)
        else:
            temp_dir = os.path.join(tempfile.gettempdir(), "daves_map_qdb_" + os.urandom(4).hex())
            os.makedirs(temp_dir, exist_ok=True)
            print(f"Downloading QuestieDB Forever ({args['Ref']}) into {temp_dir}", flush=True)
            fetch_questiedb(args["Ref"], temp_dir)
            qdb_root = temp_dir

        quests, npcs, objs, items, item_drops, area_to_uimap, dungeons = load_questiedb(qdb_root)
        print(
            f"Merged QuestieDB Forever: {n0(len(quests))} quests, {n0(len(npcs))} NPCs, "
            f"{n0(len(objs))} objects, {n0(len(items))} items",
            flush=True,
        )
        pins, zone_levels, zone_dungeons, reward_item_names, stats = build_model(
            quests, npcs, objs, items, item_drops, area_to_uimap, dungeons
        )
        now = datetime.now(timezone.utc)
        stamp = now.strftime("%Y-%m-%d %H:%M UTC")
        ver_date = now.strftime("%Y.%m.%d")
        os.makedirs(out_dir, exist_ok=True)
        render_data_lua(pins, zone_levels, zone_dungeons, reward_item_names, stamp, args["Ref"], out_lua)
        write_companion_meta(qdb_root, addon_dir, out_dir, ver_date)

        # Clean up any temporary bundled Data.lua / NOTICE-QuestieDB.md or loose zip
        for stale in (
            os.path.join(addon_dir, "Data.lua"),
            os.path.join(addon_dir, "NOTICE-QuestieDB.md"),
            os.path.join(wowaddons_dir, "daves_map_data.zip"),
        ):
            if os.path.isfile(stale):
                os.remove(stale)

        print(
            f"Wrote {out_dir} ({n0(os.path.getsize(out_lua) / 1024)} KB): "
            f"{n0(stats['pins'])} total pins ({n0(stats['quests'])} quests, "
            f"{n0(stats['rew_quests'])} quests with {n0(stats['rew_items'])} item rewards, "
            f"{n0(stats['endp'])} turn-ins, {n0(stats['pre'])} prereq links, "
            f"{n0(stats['obj'])} objective links, {n0(stats['rare_with_drops'])} rares with notable loot, "
            f"{n0(stats['dungeons'])} dungeons/raids with {n0(stats['dungeon_quests'])} dungeon quests).",
            flush=True,
        )
        for idx, c in enumerate(CATEGORIES, start=1):
            cnt = sum(1 for p in pins if p["cat"] == idx)
            off_note = " (default off)" if c["defaultOff"] else ""
            print(f"  {c['title']}: {n0(cnt)}{off_note}", flush=True)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
    finally:
        if temp_dir and not args["KeepRaw"] and os.path.isdir(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    main(sys.argv[1:])
