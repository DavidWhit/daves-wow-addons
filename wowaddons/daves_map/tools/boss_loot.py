"""Build Classic & WoW: Forever dungeon boss/rare loot tables for daves_map_data.

Combines:
  1. Hoizame/AtlasLootClassic (curated Classic Vanilla dungeon/raid boss & rare
     item lists + drop rates — parsed strictly as declarative data, never executed)
  2. Questie/QuestieDB Forever (WoW: Forever custom dungeon boss loot + new Forever
     custom items added to Classic bosses, plus fallback item names)
"""

from __future__ import annotations

import concurrent.futures
import os
import re
import ssl
import urllib.request

ATLASLOOT_BASE = "https://raw.githubusercontent.com/Hoizame/AtlasLootClassic/master/AtlasLootClassic_DungeonsAndRaids"
ATLASLOOT_FILES = (
    ("data.lua", "atlasloot/data.lua"),
    ("droprate.lua", "atlasloot/droprate.lua"),
    ("droprate_override.lua", "atlasloot/droprate_override.lua"),
)

# Encounters whose Places.lua name maps to one or more AtlasLootClassic boss names
ATLAS_ALIASES: dict[str, tuple[str, ...]] = {
    "sneed": ("Sneed", "Sneed's Shredder"),
    "the lost dwarves": ("Baelog", "Olaf", "Baelog's Chest"),
    "atal'ai defenders": ("Balcony Minibosses",),
    "jammal'an and ogom": ("Jammal'an the Prophet", "Ogom the Wretched"),
    "dreamscythe and weaver": ("Dreamscythe", "Weaver"),
    "morphaz and hazzas": ("Morphaz", "Hazzas"),
    "high inquisitor whitemane": ("High Inquisitor Whitemane", "Scarlet Commander Mograine"),
    "ring of law": (
        "Gorosh the Dervish", "Grizzle", "Eviscerator",
        "Ok'thor the Breaker", "Anub'shiah", "Hedrum the Creeper",
    ),
    "the vault": ("Dark Coffer", "Watchman Doomgrip"),
    "the seven": ("Chest of The Seven",),
    "warder stilgiss": ("Warder Stilgiss", "Verek"),
    "edge of madness": ("Gri'lek", "Hazza'rah", "Renataki", "Wushoolay"),
    "silithid royalty": ("Bug Trio",),
    "c'thun": ("C'Thun",),
    "ras frostwhisperer": ("Ras Frostwhisper",),
    "kirtonos": ("Kirtonos the Herald",),
}

# Boss name -> QuestieDB NPC / Object names for fallback & Forever custom bosses
QDB_ALIASES: dict[str, tuple[str, tuple[str, ...]]] = {
    "ras frostwhisperer": ("npc", ("ras frostwhisper",)),
    "kirtonos": ("npc", ("kirtonos the herald",)),
    "the lost dwarves": ("npc", ("baelog", 'eric "the swift"', "olaf")),
    "ring of law": ("npc", (
        "gorosh the dervish", "grizzle", "eviscerator",
        "ok'thor the breaker", "anub'shiah", "hedrum the creeper",
    )),
    "the seven": ("obj", ("chest of the seven",)),
    "the vault": ("both", ("watchman doomgrip", "dark coffer")),
    "atal'ai defenders": ("npc", ("zolo", "gasher", "loro", "hukku", "zul'lor", "mijan")),
    "edge of madness": ("npc", ("gri'lek", "hazza'rah", "renataki", "wushoolay")),
    "silithid royalty": ("npc", ("lord kri", "princess yauj", "vem")),
    "twin emperors": ("npc", ("emperor vek'nilash", "emperor vek'lor")),
    "majordomo executus": ("obj", ("cache of the firelord",)),
    "high inquisitor whitemane": ("npc", ("high inquisitor whitemane", "scarlet commander mograine")),
    "ezra grimm": ("npc", ("fras siabi", "ezra grimm")),
    "infurnus": ("npc", ("magmatus", "infurnus")),
    "ravasaur hunters": ("npc", ("ravasaur hunter",)),
    "deathless guardians": ("npc", ("deathless guardian", "deathless marrow")),
    "handler ashka": ("npc", ("war handler ashka", "handler ashka")),
}

SKIP_ATLAS_SECTIONS = {
    "trash mobs", "trash", "shared boss loot", "quests", "books", "class books",
    "tribute", "dungeon set 1", "dungeon set 2", "tier 1", "tier 2", "tier 2.5",
    "tier 3", "enchants", "patterns", "plans", "all bosses", "high priest shared loot",
    "atiesh", "coren direbrew", "theldren", "balzaphon", "sothos and jarien's heirlooms",
}


def fetch_atlasloot(dest_root: str, check_url_fn, ua: str, max_bytes: int) -> None:
    ctx = ssl.create_default_context()
    headers = {"User-Agent": ua}

    def dl(pair: tuple[str, str]) -> int:
        src_name, rel_dest = pair
        url = f"{ATLASLOOT_BASE}/{src_name}"
        check_url_fn(url)
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=30, context=ctx) as resp:
            check_url_fn(resp.geturl())
            data = resp.read(max_bytes + 1)
            if len(data) > max_bytes:
                raise RuntimeError(f"Download exceeded {max_bytes} bytes: {src_name}")
        out_path = os.path.join(dest_root, *rel_dest.split("/"))
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "wb") as handle:
            handle.write(data)
        return len(data)

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        total = sum(pool.map(dl, ATLASLOOT_FILES))
    print(f"Fetched {len(ATLASLOOT_FILES)} AtlasLootClassic files ({total / 1024:.1f} KB)", flush=True)


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def _extract_brace_block(s: str, start_idx: int) -> tuple[str, int]:
    depth = 0
    in_str = None
    i = start_idx
    n = len(s)
    while i < n:
        ch = s[i]
        if in_str:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == in_str:
                in_str = None
        else:
            if ch in ('"', "'"):
                in_str = ch
            elif ch == "-" and i + 1 < n and s[i + 1] == "-":
                nl = s.find("\n", i)
                i = n if nl < 0 else nl + 1
                continue
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return s[start_idx:i + 1], i + 1
        i += 1
    return s[start_idx:], n


def _parse_atlas_droprates(txt: str) -> dict[int, dict[int, float]]:
    out: dict[int, dict[int, float]] = {}
    cur_npc = None
    for line in txt.splitlines():
        m = re.match(r"\s*\[(\d+)\]\s*=\s*\{", line)
        if m:
            cur_npc = int(m.group(1))
            out.setdefault(cur_npc, {})
            for im in re.finditer(r"\[(\d+)\]\s*=\s*([\d.]+)", line[m.end():]):
                out[cur_npc][int(im.group(1))] = float(im.group(2))
        elif cur_npc is not None:
            if "}" in line and not re.search(r"\[(\d+)\]\s*=", line):
                cur_npc = None
                continue
            for im in re.finditer(r"\[(\d+)\]\s*=\s*([\d.]+)", line):
                out[cur_npc][int(im.group(1))] = float(im.group(2))
            if line.strip().endswith("},") or line.strip() == "}":
                cur_npc = None
    return out


def _parse_atlas_data(al_dir: str, item_drops: dict) -> tuple[dict[int, list], dict[int, str]]:
    data_path = os.path.join(al_dir, "data.lua")
    if not os.path.isfile(data_path):
        return {}, {}
    atlas_rates: dict[int, dict[int, float]] = {}
    for fn in ("droprate.lua", "droprate_override.lua"):
        p = os.path.join(al_dir, fn)
        if os.path.isfile(p):
            parsed = _parse_atlas_droprates(open(p, encoding="utf-8", errors="ignore").read())
            for nid, tbl in parsed.items():
                atlas_rates.setdefault(nid, {}).update(tbl)

    al_txt = open(data_path, encoding="utf-8", errors="ignore").read()
    by_inst: dict[int, list[tuple[str, list[int], list[tuple[int, float]]]]] = {}
    item_names: dict[int, str] = {}

    for m in re.finditer(r'data\["([^"]+)"\]\s*=\s*\{', al_txt):
        if m.group(1) == "WorldBosses":
            continue
        block, _ = _extract_brace_block(al_txt, m.end() - 1)
        im = re.search(r"\bInstanceID\s*=\s*(\d+)", block)
        if not im:
            continue
        inst_id = int(im.group(1))
        it_m = re.search(r"\bitems\s*=\s*\{", block)
        if not it_m:
            continue
        items_block, _ = _extract_brace_block(block, it_m.end() - 1)
        pos, n = 1, len(items_block) - 1
        while pos < n:
            ch = items_block[pos]
            if ch == "-" and pos + 1 < n and items_block[pos + 1] == "-":
                nl = items_block.find("\n", pos)
                pos = n if nl < 0 else nl + 1
                continue
            if ch == "{":
                b_blk, pos = _extract_brace_block(items_block, pos)
                nm_m = re.search(
                    r'\bname\s*=\s*(?:AL(?:IL)?\["([^"]+)"\]|"([^"]+)"|format\([^,]+,\s*AL\["([^"]+)"\])',
                    b_blk,
                )
                bname = (nm_m.group(1) or nm_m.group(2) or nm_m.group(3)).strip() if nm_m else ""
                if not bname or bname.lower() in SKIP_ATLAS_SECTIONS:
                    continue
                nid_m = re.search(r"\bnpcID\s*=\s*(\{[^}]+\}|\d+)", b_blk)
                nids = [int(x) for x in re.findall(r"\d+", nid_m.group(1))] if nid_m else []
                boss_items: list[tuple[int, float]] = []
                seen_iids: set[int] = set()
                for diff_m in re.finditer(
                    r"\[(NORMAL_DIFF|RAID20_DIFF|RAID40_DIFF|ALLIANCE_DIFF|HORDE_DIFF)\]\s*=\s*\{",
                    b_blk,
                ):
                    d_blk, _ = _extract_brace_block(b_blk, diff_m.end() - 1)
                    for line in d_blk.splitlines():
                        rm = re.match(r"\s*\{\s*\d+\s*,\s*(\d+)\b", line)
                        if not rm:
                            continue
                        iid = int(rm.group(1))
                        if iid in seen_iids or iid < 100:
                            continue
                        seen_iids.add(iid)
                        cm = re.search(r"--\s*(.+)$", line)
                        if cm:
                            cname = cm.group(1).strip()
                            if cname and iid not in item_names:
                                item_names[iid] = cname
                        pct = 0.0
                        for nid in nids:
                            if nid in atlas_rates and iid in atlas_rates[nid]:
                                pct = max(pct, atlas_rates[nid][iid])
                        if pct == 0.0:
                            dr_tbl = item_drops.get(iid)
                            if isinstance(dr_tbl, dict):
                                for nid in nids:
                                    v = dr_tbl.get(nid)
                                    if isinstance(v, (int, float)):
                                        pct = max(pct, float(v))
                        boss_items.append((iid, pct))
                if boss_items:
                    by_inst.setdefault(inst_id, []).append((bname, nids, boss_items))
            else:
                pos += 1
    return by_inst, item_names


def _read_canonical_bosses(wowaddons_dir: str) -> dict[int, list[str]]:
    by_inst: dict[int, list[str]] = {}
    places_path = os.path.join(wowaddons_dir, "daves_map_textures", "Data", "Places.lua")
    if os.path.isfile(places_path):
        txt = open(places_path, encoding="utf-8").read()
        m = re.search(r"bosses\s*=\s*\{([\s\S]*?)\n\t\},", txt)
        if m:
            for line in m.group(1).splitlines():
                im = re.match(r"\s*\[(\d+)\]\s*=\s*\{(.*)\}", line)
                if im:
                    by_inst[int(im.group(1))] = re.findall(r'"([^"]+)"', im.group(2))
    dboss_path = os.path.join(wowaddons_dir, "daves_map_textures", "Data", "DungeonBosses.lua")
    if os.path.isfile(dboss_path):
        txt = open(dboss_path, encoding="utf-8").read()
        cur = None
        for line in txt.splitlines():
            im = re.match(r"\s*\[(\d+)\]\s*=", line)
            if im:
                cur = int(im.group(1))
                by_inst.setdefault(cur, [])
            elif cur is not None:
                bm = re.match(r'\s*\["([^"]+)"\]\s*=', line)
                if bm and bm.group(1) not in by_inst[cur]:
                    by_inst[cur].append(bm.group(1))
    return by_inst


def build_boss_drops(
    qdb_root: str,
    wowaddons_dir: str,
    npcs: dict,
    objs: dict,
    items: dict,
    item_drops: dict,
    dict_to_list,
    bad_name_rx,
) -> tuple[dict[int, dict[str, list[int]]], dict[int, str], dict[str, int]]:
    bosses_by_inst = _read_canonical_bosses(wowaddons_dir)
    atlas_by_inst, atlas_names = _parse_atlas_data(os.path.join(qdb_root, "atlasloot"), item_drops)

    # Index QuestieDB NPCs, Objects, and item drops
    npc_by_name: dict[str, list[int]] = {}
    for nid, row in npcs.items():
        nm = row.get(1)
        if isinstance(nm, str) and nm.strip():
            npc_by_name.setdefault(nm.strip().lower(), []).append(nid)

    obj_by_name: dict[str, list[int]] = {}
    for oid, row in objs.items():
        nm = row.get(1)
        if isinstance(nm, str) and nm.strip():
            obj_by_name.setdefault(nm.strip().lower(), []).append(oid)

    npc_items: dict[int, list[int]] = {}
    obj_items: dict[int, list[int]] = {}
    item_dcnt: dict[int, int] = {}
    for iid, row in items.items():
        ndrops = [n for n in dict_to_list(row.get(2, {})) if isinstance(n, int)]
        odrops = [o for o in dict_to_list(row.get(3, {})) if isinstance(o, int)]
        dr_tbl = item_drops.get(iid)
        all_n = set(ndrops) | ({k for k in dr_tbl.keys() if isinstance(k, int)} if isinstance(dr_tbl, dict) else set())
        item_dcnt[iid] = len(all_n) + len(odrops)
        for nid in all_n:
            npc_items.setdefault(nid, []).append(iid)
        for oid in odrops:
            obj_items.setdefault(oid, []).append(iid)

    def qdb_drops_for(boss_name: str, extra_nids: list[int], forever_only: bool, max_dcnt: int) -> list[tuple[int, float]]:
        low = boss_name.lower()
        nids = list(extra_nids)
        oids: list[int] = []
        if low in QDB_ALIASES:
            kind, names_lst = QDB_ALIASES[low]
            for nm in names_lst:
                if kind in ("npc", "both"):
                    nids.extend(npc_by_name.get(nm, []))
                if kind in ("obj", "both"):
                    oids.extend(obj_by_name.get(nm, []))
        else:
            nids.extend(npc_by_name.get(low, []))
        nids = list(dict.fromkeys(nids))
        cands: set[int] = set()
        for nid in nids:
            cands.update(npc_items.get(nid, []))
        for oid in oids:
            cands.update(obj_items.get(oid, []))
        scored = []
        for iid in cands:
            if forever_only and iid < 200000:
                continue
            row = items.get(iid)
            if not row:
                continue
            iname = row.get(1)
            if not isinstance(iname, str) or not iname.strip() or bad_name_rx.search(iname):
                continue
            icls = row.get(12) if isinstance(row.get(12), int) else -1
            ilvl = row.get(9) if isinstance(row.get(9), int) else 0
            start_q = row.get(5) if isinstance(row.get(5), int) else 0
            teaches = row.get(16) if isinstance(row.get(16), int) else 0
            dcnt = item_dcnt.get(iid, 999)
            if forever_only:
                # Only append Forever-exclusive gear/weapons/bags/unique boss items (skip shared recipes)
                if not ((icls in (1, 2, 4) and dcnt <= 4) or (icls == 15 and dcnt <= 2)):
                    continue
            else:
                if not (
                    (icls in (1, 2, 4) and dcnt <= max_dcnt)
                    or ((icls == 9 or start_q > 0 or teaches > 0) and dcnt <= min(max_dcnt, 10))
                    or (icls == 15 and dcnt <= 4)
                ):
                    continue
            pct = 0.0
            dr_tbl = item_drops.get(iid)
            if isinstance(dr_tbl, dict):
                for nid in nids:
                    v = dr_tbl.get(nid)
                    if isinstance(v, (int, float)):
                        pct = max(pct, float(v))
            scored.append((0 if icls in (2, 4) else (1 if icls == 1 else 2), -ilvl, iname.strip(), iid, pct))
        scored.sort()
        out: list[tuple[int, float]] = []
        seen_names: set[str] = set()
        for _, _, nm, iid, pct in scored:
            nk = nm.lower()
            if nk in seen_names:
                continue
            seen_names.add(nk)
            out.append((iid, pct))
        return out

    boss_drops: dict[int, dict[str, list[int]]] = {}
    boss_item_names: dict[int, str] = {}
    total_bosses = 0
    matched_bosses = 0
    total_items = 0

    for inst_id, names in sorted(bosses_by_inst.items()):
        al_list = atlas_by_inst.get(inst_id, [])
        al_by_norm = {_norm(b): (b, nids, its) for b, nids, its in al_list}
        inst_out: dict[str, list[int]] = {}
        for boss_name in names:
            total_bosses += 1
            low = boss_name.lower()
            merged: list[tuple[int, float]] = []
            seen_iids: set[int] = set()
            matched_nids: list[int] = []

            if inst_id < 2000 and al_list:
                targets = ATLAS_ALIASES.get(low)
                if targets:
                    for tname in targets:
                        hit = al_by_norm.get(_norm(tname))
                        if hit:
                            matched_nids.extend(hit[1])
                            for iid, pct in hit[2]:
                                if iid not in seen_iids:
                                    seen_iids.add(iid)
                                    merged.append((iid, pct))
                else:
                    nk = _norm(boss_name)
                    hit = al_by_norm.get(nk)
                    if not hit:
                        for b, nids, its in al_list:
                            nb = _norm(b)
                            if nk and nb and (nk == nb or nk in nb or nb in nk):
                                hit = (b, nids, its)
                                break
                    if hit:
                        matched_nids.extend(hit[1])
                        for iid, pct in hit[2]:
                            if iid not in seen_iids:
                                seen_iids.add(iid)
                                merged.append((iid, pct))

                if merged:
                    # Append any Forever-exclusive custom gear added to this Classic boss
                    for iid, pct in qdb_drops_for(boss_name, matched_nids, forever_only=True, max_dcnt=4):
                        if iid not in seen_iids:
                            seen_iids.add(iid)
                            merged.append((iid, pct))
                else:
                    # Fallback to QuestieDB Forever (e.g., Stockade/RFC/BRD Guzzler/Roogug/Lorgus Jett)
                    for iid, pct in qdb_drops_for(boss_name, [], forever_only=False, max_dcnt=12):
                        if iid not in seen_iids:
                            seen_iids.add(iid)
                            merged.append((iid, pct))
            else:
                # WoW: Forever custom dungeons
                for iid, pct in qdb_drops_for(boss_name, [], forever_only=False, max_dcnt=18):
                    if iid not in seen_iids:
                        seen_iids.add(iid)
                        merged.append((iid, pct))

            if merged:
                flat: list[int] = []
                for iid, pct in merged[:28]:
                    flat.append(iid)
                    flat.append(int(round(pct * 10)) if pct > 0 else 0)
                    if iid not in boss_item_names:
                        qrow = items.get(iid)
                        qname = qrow.get(1) if isinstance(qrow, dict) else None
                        if isinstance(qname, str) and qname.strip():
                            boss_item_names[iid] = qname.strip()
                        elif iid in atlas_names:
                            boss_item_names[iid] = atlas_names[iid]
                inst_out[boss_name] = flat
                matched_bosses += 1
                total_items += len(flat) // 2

        if inst_out:
            boss_drops[inst_id] = inst_out

    stats = {
        "boss_loot_insts": len(boss_drops),
        "boss_loot_bosses": matched_bosses,
        "boss_loot_total": total_bosses,
        "boss_loot_items": total_items,
    }
    return boss_drops, boss_item_names, stats
