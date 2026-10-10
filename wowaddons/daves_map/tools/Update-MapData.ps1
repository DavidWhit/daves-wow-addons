<#
.SYNOPSIS
  Rebuilds daves_map's Data.lua from Map Genie's WoW Forever map, cross-referenced with pfQuest's quest database.

.DESCRIPTION
  1. Downloads the Map Genie page (-Url) and reads the map's id, groups and categories from its embedded
     `window.mapData` JSON, then the map's pins from the site's public map-data endpoint (/api/v1/maps/<id>/data).
  2. Downloads pfQuest's classic quest and NPC tables (MIT licence, github.com/shagu/pfQuest) unless -NoQuestDb.
  3. Writes Data.lua: groups, categories, tags and every pin (position, category, title, cleaned text, faction,
     level, classes) plus the links between pins: quest start -> turn-in NPC, transport -> destination, and
     quest -> prerequisite quests (pfQuest's "pre").

  Everything downloaded is DATA. It is saved into a new, empty folder of its own, parsed with a JSON parser and a
  small literal reader written here (no Lua or JavaScript from the web is ever run), and the folder is deleted at
  the end unless -KeepRaw.

  What is NOT copied from Map Genie: links (URLs in descriptions are dropped; links to other pins on the same map
  become pin-to-pin links), media, icons, and anything behind a login. Data.lua stays out of git (.gitignore):
  Map Genie's data is theirs, and the repo is public.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Update-MapData.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Update-MapData.ps1 -Url https://mapgenie.io/world-of-warcraft-forever/maps/azeroth -KeepRaw
#>
param(
	[string]$Url = 'https://mapgenie.io/world-of-warcraft-forever/maps/azeroth',
	[switch]$NoQuestDb,
	[string]$QuestDbRef = 'master',
	[switch]$KeepRaw
)
$ErrorActionPreference = 'Stop'
# The data goes into its own addon, daves_map_data, next to daves_map. daves_map lists it in ## OptionalDeps, so a
# copy without it (a fresh clone) loads with no error and says how to get it. The path is fixed on purpose: the repo
# root's .gitignore covers exactly wowaddons/daves_map_data/, and Map Genie's data must never land anywhere git sees.
$Out = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'daves_map_data\Data.lua'
# The data addon's TOC takes daves_map's Interface numbers. Read them before anything is downloaded or written: without
# them the data addon would show as out of date and never load, from a build that otherwise looked fine.
$mapToc = Join-Path (Split-Path $PSScriptRoot -Parent) 'daves_map.toc'
$iface = ([regex]::Match([IO.File]::ReadAllText($mapToc), '(?m)^## Interface:\s*(.+?)\s*$')).Groups[1].Value
if (-not $iface) { throw "No '## Interface:' line in $mapToc; the data addon needs it to load." }
Add-Type -AssemblyName System.Web.Extensions
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------------------------------------------------
# A reader for Lua table literals (pfQuest's db files are one `x = { ... }` literal each). Data only: tables, strings,
# numbers, true/false/nil. Anything else is an error, never evaluated.
# ---------------------------------------------------------------------------------------------------------------------
if (-not ('DavesMap.LuaLiteral' -as [type])) {
	Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
namespace DavesMap {
public static class LuaLiteral {
	// Parses the first table literal after the first '=' in the text.
	public static Dictionary<object, object> ParseAssignedTable(string text) {
		int eq = text.IndexOf('=');
		int pos = text.IndexOf('{', eq < 0 ? 0 : eq);
		if (pos < 0) throw new FormatException("no table literal");
		return (Dictionary<object, object>)Value(text, ref pos);
	}
	static void Skip(string s, ref int p) {
		while (p < s.Length) {
			char c = s[p];
			if (char.IsWhiteSpace(c)) { p++; continue; }
			if (c == '-' && p + 1 < s.Length && s[p + 1] == '-') {   // comment to end of line
				while (p < s.Length && s[p] != '\n') p++;
				continue;
			}
			break;
		}
	}
	static object Value(string s, ref int p) {
		Skip(s, ref p);
		char c = s[p];
		if (c == '{') return Table(s, ref p);
		if (c == '"' || c == '\'') return Str(s, ref p);
		if (c == '-' || c == '.' || char.IsDigit(c)) return Num(s, ref p);
		if (string.CompareOrdinal(s, p, "true", 0, 4) == 0) { p += 4; return true; }
		if (string.CompareOrdinal(s, p, "false", 0, 5) == 0) { p += 5; return false; }
		if (string.CompareOrdinal(s, p, "nil", 0, 3) == 0) { p += 3; return null; }
		throw new FormatException("unexpected '" + c + "' at " + p);
	}
	static Dictionary<object, object> Table(string s, ref int p) {
		var t = new Dictionary<object, object>();
		p++;   // {
		long n = 1;
		while (true) {
			Skip(s, ref p);
			if (s[p] == '}') { p++; return t; }
			object key = null;
			if (s[p] == '[') {
				p++; key = Value(s, ref p); Skip(s, ref p);
				if (s[p] != ']') throw new FormatException("']' expected at " + p);
				p++; Skip(s, ref p);
				if (s[p] != '=') throw new FormatException("'=' expected at " + p);
				p++;
			} else if (char.IsLetter(s[p]) || s[p] == '_') {
				int q = p; while (q < s.Length && (char.IsLetterOrDigit(s[q]) || s[q] == '_')) q++;
				int r = q; Skip(s, ref r);
				if (r < s.Length && s[r] == '=' && (r + 1 >= s.Length || s[r + 1] != '=')) {
					key = s.Substring(p, q - p); p = r + 1;
				}
			}
			object v = Value(s, ref p);
			if (key == null) key = n++;
			if (key is double && (double)key == Math.Floor((double)key)) key = (long)(double)key;
			if (v != null) t[key] = v;
			Skip(s, ref p);
			if (s[p] == ',' || s[p] == ';') p++;
		}
	}
	static object Num(string s, ref int p) {
		int q = p;
		if (s[q] == '-') q++;
		while (q < s.Length && (char.IsDigit(s[q]) || s[q] == '.' || s[q] == 'e' || s[q] == 'E' || ((s[q] == '-' || s[q] == '+') && (s[q - 1] == 'e' || s[q - 1] == 'E')))) q++;
		string tok = s.Substring(p, q - p); p = q;
		double d = double.Parse(tok, CultureInfo.InvariantCulture);
		if (d == Math.Floor(d) && Math.Abs(d) < 9e15) return (long)d;
		return d;
	}
	static string Str(string s, ref int p) {
		char quote = s[p++];
		var sb = new StringBuilder();
		while (true) {
			char c = s[p++];
			if (c == quote) return sb.ToString();
			if (c != '\\') { sb.Append(c); continue; }
			char e = s[p++];
			switch (e) {
				case 'n': sb.Append('\n'); break;
				case 't': sb.Append('\t'); break;
				case 'r': sb.Append('\r'); break;
				case '\\': sb.Append('\\'); break;
				case '"': sb.Append('"'); break;
				case '\'': sb.Append('\''); break;
				case '\n': sb.Append('\n'); break;
				default:
					if (char.IsDigit(e)) {
						int v = e - '0', k = 1;
						while (k < 3 && char.IsDigit(s[p])) { v = v * 10 + (s[p++] - '0'); k++; }
						sb.Append((char)v);
					} else sb.Append(e);
					break;
			}
		}
	}
}
}
'@
}

function Fetch([string]$u, [string]$path, [hashtable]$headers = @{}) {
	$h = @{ 'User-Agent' = $UA } + $headers
	Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $path -Headers $h -TimeoutSec 120 | Out-Null
	return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}
$json = New-Object Web.Script.Serialization.JavaScriptSerializer
$json.MaxJsonLength = [int]::MaxValue
$json.RecursionLimit = 256

# a fresh, empty folder for everything downloaded (data only)
$raw = Join-Path ([IO.Path]::GetTempPath()) ('daves_map_fetch_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $raw | Out-Null
Write-Host "Downloading into $raw"

# ---------------------------------------------------------------------------------------------------------------------
# 1. Map Genie: the page (map id, groups, categories) and the map's pins
# ---------------------------------------------------------------------------------------------------------------------
$html = Fetch $Url (Join-Path $raw 'page.html')
$i = $html.IndexOf('window.mapData')
if ($i -lt 0) { throw "window.mapData not found in $Url (the page layout changed?)" }
$i = $html.IndexOf('{', $i)
# cut the JSON literal out by brace matching (string-aware), then parse it as JSON
$depth = 0; $inStr = $false; $esc = $false; $j = $i
for (; $j -lt $html.Length; $j++) {
	$c = $html[$j]
	if ($inStr) { if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }; continue }
	if ($c -eq '"') { $inStr = $true } elseif ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { break } }
}
$page = $json.DeserializeObject($html.Substring($i, $j - $i + 1))
$mapId = [int]$page['map']['id']
$mapTitle = [string]$page['map']['title']
$origin = ([Uri]$Url).GetLeftPart([UriPartial]::Authority)
Write-Host "Map: $mapTitle (id $mapId)"
$dataText = Fetch "$origin/api/v1/maps/$mapId/data" (Join-Path $raw 'mapdata.json') @{ 'Accept' = 'application/json'; 'Referer' = $Url; 'X-Requested-With' = 'XMLHttpRequest' }
$data = $json.DeserializeObject($dataText)
$locations = @($data['locations'])
if ($locations.Count -eq 0) { throw "no locations in the map data (the endpoint changed?)" }
Write-Host "Pins: $($locations.Count)"

# image pixel space at zoom 16, relative to the tile set's bounds (Web Mercator, as Map Genie's tiles)
$ts = $page['mapConfig']['tile_sets'][0]
$Z = 16
$minTX = [double]$ts['bounds']["$Z"]['x']['min']; $minTY = [double]$ts['bounds']["$Z"]['y']['min']
$WORLD = [Math]::Pow(2, $Z) * 256
function ToPixel([double]$lat, [double]$lng) {
	$x = ($lng + 180.0) / 360.0 * $WORLD - $minTX * 256
	$phi = $lat * [Math]::PI / 180.0
	$y = (1.0 - [Math]::Log([Math]::Tan($phi) + 1.0 / [Math]::Cos($phi)) / [Math]::PI) / 2.0 * $WORLD - $minTY * 256
	return @([Math]::Round($x, 1), [Math]::Round($y, 1))
}

# ---------------------------------------------------------------------------------------------------------------------
# 2. Groups, categories, tags
# ---------------------------------------------------------------------------------------------------------------------
$groups = @($page['groups'] | Sort-Object { [int]$_['order'] })
$catById = @{}
foreach ($k in $page['categories'].Keys) { $catById[[int]$k] = $page['categories'][$k] }
$catIndex = @{}; $cats = New-Object System.Collections.ArrayList
$groupOut = New-Object System.Collections.ArrayList
foreach ($g in $groups) {
	$members = @($g['categories'] | Sort-Object { [int]$_['order'] })
	$idx = @()
	foreach ($m in $members) {
		$cid = [int]$m['id']; $c = $catById[$cid]; if (-not $c) { $c = $m }
		[void]$cats.Add([ordered]@{ id = $cid; title = [string]$c['title']; icon = [string]$c['icon']; color = [string]$(if ($c['icon_color']) { $c['icon_color'] } else { $c['color'] }); group = $groupOut.Count + 1; info = [string]$c['info'] })
		$catIndex[$cid] = $cats.Count
		$idx += $cats.Count
	}
	[void]$groupOut.Add([ordered]@{ id = [int]$g['id']; title = [string]$g['title']; color = [string]$g['color']; cats = $idx })
}
$TAG_FACTION = @{ 'alliance' = 1; 'horde' = 2; 'neutral' = 3 }
$CLASSES = @('warrior', 'paladin', 'hunter', 'rogue', 'priest', 'shaman', 'mage', 'warlock', 'druid')   # bit i-1
$tagById = @{}
foreach ($t in @($data['tags'])) { $tagById[[int]$t['id']] = [string]$t['title'] }

# ---------------------------------------------------------------------------------------------------------------------
# 3. Pins: position, text cleaned to plain game text (no links), structured fields
# ---------------------------------------------------------------------------------------------------------------------
$GOLD = '|cffffd200'
function CleanText([string]$s) {
	if (-not $s) { return '' }
	$s = $s -replace "`r", ''
	$s = [regex]::Replace($s, '\[([^\]]*)\]\([^)]*\)', '$1')            # markdown links -> their text (URL dropped)
	$s = [regex]::Replace($s, 'https?://\S+', '')                         # bare URLs dropped
	$s = [regex]::Replace($s, '\{\{[^}]*\}\}\s*', '')                     # Map Genie's inline icon markup
	$s = [regex]::Replace($s, '\*\*([^*]+?):\*\*', "$GOLD`$1:|r")         # **Label:** -> gold label
	$s = [regex]::Replace($s, '\*\*([^*]+?)\*\*', '$1')
	$s = $s -replace '\|(?!c[0-9a-fA-F]{8}|r)', '||'                       # a stray | would start an escape code in game
	$s = [regex]::Replace($s, "\n{2,}", "`n")
	return $s.Trim()
}
function Norm([string]$s) { return ([regex]::Replace(($s + '').ToLowerInvariant(), "[^a-z0-9]+", ' ')).Trim() }

$pins = New-Object System.Collections.ArrayList
$pinByMgId = @{}
foreach ($l in $locations) {
	$cid = [int]$l['category_id']
	if (-not $catIndex.ContainsKey($cid)) { continue }
	$xy = ToPixel ([double]$l['latitude']) ([double]$l['longitude'])
	$desc = [string]$l['description']
	$fac = 0; $cls = 0
	foreach ($tid in @($l['tags'])) {
		$tn = $tagById[[int]$tid]
		if ($TAG_FACTION.ContainsKey($tn)) { $fac = $TAG_FACTION[$tn] }
		elseif ($tn -like 'class-*') { $k = [array]::IndexOf($CLASSES, $tn.Substring(6)); if ($k -ge 0) { $cls = $cls -bor (1 -shl $k) } }
	}
	if ($fac -eq 0) {
		if ($desc -match '\*\*(?:Faction|Side):\*\*\s*(Alliance|Horde|Neutral)') { $fac = $TAG_FACTION[$Matches[1].ToLowerInvariant()] }
		elseif ($desc -match '\((Alliance|Horde)\)') { $fac = $TAG_FACTION[$Matches[1].ToLowerInvariant()] }
	}
	if ($cls -eq 0 -and $desc -match '\*\*Required Class:\*\*([^\n]*)') {
		foreach ($k in 0..($CLASSES.Count - 1)) { if ($Matches[1] -match "\b$($CLASSES[$k])\b") { $cls = $cls -bor (1 -shl $k) } }
	}
	$lvl = 0; if ($desc -match '\*\*Required Level:\*\*\s*(\d+)') { $lvl = [int]$Matches[1] }
	$qs = ''; if ($desc -match 'Start:\s*([^\n]+)') { $qs = $Matches[1].Trim() }
	$qe = ''; if ($desc -match 'End:\s*([^\n]+)') { $qe = $Matches[1].Trim() }
	$npc = ''; if ($desc -match '^\*\*[^*]+:\*\*\s*([^\n(]+?)\s*(\((Alliance|Horde|Neutral)\))?\s*$' -and $desc -notmatch 'Faction:|Side:|Destination:') { $npc = $Matches[1].Trim() }
	$dest = 0; if ($desc -match 'locationIds=(\d+)') { $dest = [int]$Matches[1] }   # a link to another pin: kept as a pin link
	$p = [ordered]@{
		mg = [int]$l['id']; cat = $catIndex[$cid]; x = $xy[0]; y = $xy[1]; title = ([string]$l['title']).Trim(); text = (CleanText $desc)
		fac = $fac; lvl = $lvl; cls = $cls; qs = $qs; qe = $qe; npc = $npc; destMg = $dest; dest = 0; endp = 0; qid = 0; pre = @()
	}
	[void]$pins.Add($p)
	$pinByMgId[$p.mg] = $pins.Count
}
Write-Host "Kept pins: $($pins.Count) in $($cats.Count) categories"

# ---------------------------------------------------------------------------------------------------------------------
# 4. Links between pins
# ---------------------------------------------------------------------------------------------------------------------
function Dist2($a, $b) { $dx = $a.x - $b.x; $dy = $a.y - $b.y; return $dx * $dx + $dy * $dy }
function Nearest($fromPin, $candidates) {
	$best = 0; $bd = [double]::MaxValue
	foreach ($ci in $candidates) { $d = Dist2 $fromPin $pins[$ci - 1]; if ($d -lt $bd) { $bd = $d; $best = $ci } }
	return $best
}
# where each NPC stands: pins of quests they start, and service pins naming them
$npcAt = @{}
for ($n = 1; $n -le $pins.Count; $n++) {
	$p = $pins[$n - 1]
	foreach ($name in @($p.qs, $p.npc)) { if ($name) { $k = Norm $name; if (-not $npcAt[$k]) { $npcAt[$k] = New-Object System.Collections.ArrayList }; [void]$npcAt[$k].Add($n) } }
}
$links = @{ dest = 0; endp = 0; pre = 0 }
for ($n = 1; $n -le $pins.Count; $n++) {
	$p = $pins[$n - 1]
	if ($p.destMg -and $pinByMgId[$p.destMg]) { $p.dest = $pinByMgId[$p.destMg]; $links.dest++ }
}

# pfQuest: quest ids, prerequisites, start/end NPC names
$pfUsed = $null
if (-not $NoQuestDb) {
	$base = "https://raw.githubusercontent.com/shagu/pfQuest/$QuestDbRef"
	Write-Host "Reading pfQuest ($QuestDbRef)"
	$pfQ = [DavesMap.LuaLiteral]::ParseAssignedTable((Fetch "$base/db/quests.lua" (Join-Path $raw 'pf_quests.txt')))
	$pfT = [DavesMap.LuaLiteral]::ParseAssignedTable((Fetch "$base/db/enUS/quests.lua" (Join-Path $raw 'pf_quests_enUS.txt')))
	$pfU = [DavesMap.LuaLiteral]::ParseAssignedTable((Fetch "$base/db/enUS/units.lua" (Join-Path $raw 'pf_units_enUS.txt')))
	$ALLIANCE_RACES = 1 + 4 + 8 + 64; $HORDE_RACES = 2 + 16 + 32 + 128
	function UnitNames($side) {
		$names = @()
		if ($side -and $side.ContainsKey('U')) { foreach ($u in $side['U'].Values) { $nm = $pfU[[long]$u]; if ($nm) { $names += [string]$nm } } }
		return $names
	}
	# index pfQuest quests by normalized title
	$byTitle = @{}
	foreach ($qid in $pfQ.Keys) {
		$t = $pfT[$qid]; if (-not $t -or -not $t.ContainsKey('T')) { continue }
		$k = Norm $t['T']
		if (-not $byTitle[$k]) { $byTitle[$k] = New-Object System.Collections.ArrayList }
		[void]$byTitle[$k].Add([long]$qid)
	}
	$pinsByQid = @{}
	$matched = 0
	for ($n = 1; $n -le $pins.Count; $n++) {
		$p = $pins[$n - 1]
		if (-not ($cats[$p.cat - 1].title -match 'Quest|Repeatable')) { continue }
		$cands = $byTitle[(Norm $p.title)]; if (-not $cands) { continue }
		$best = $null; $bestScore = -1
		foreach ($qid in $cands) {
			$q = $pfQ[$qid]; $score = 0
			$starts = UnitNames $q['start']
			if ($p.qs -and ($starts | ? { (Norm $_) -eq (Norm $p.qs) })) { $score += 4 }
			$ends = UnitNames $q['end']
			if ($p.qe -and ($ends | ? { (Norm $_) -eq (Norm $p.qe) })) { $score += 2 }
			$race = if ($q.ContainsKey('race')) { [long]$q['race'] } else { 0 }
			if ($race -ne 0 -and $p.fac -eq 1 -and ($race -band $ALLIANCE_RACES)) { $score += 1 }
			if ($race -ne 0 -and $p.fac -eq 2 -and ($race -band $HORDE_RACES)) { $score += 1 }
			if ($q.ContainsKey('min') -and $p.lvl -and [long]$q['min'] -eq $p.lvl) { $score += 1 }
			if ($score -gt $bestScore) { $bestScore = $score; $best = $qid }
		}
		# accept a title match when it is the only candidate or something else agrees too
		if ($best -and ($cands.Count -eq 1 -or $bestScore -ge 2)) {
			$p.qid = [long]$best; $matched++
			if (-not $pinsByQid[$p.qid]) { $pinsByQid[$p.qid] = New-Object System.Collections.ArrayList }
			[void]$pinsByQid[$p.qid].Add($n)
			if (-not $p.qe) { $e = @(UnitNames $pfQ[$best]['end']); if ($e.Count) { $p.qe = $e[0] } }
		}
	}
	# prerequisites -> the nearest pin of each prerequisite quest
	for ($n = 1; $n -le $pins.Count; $n++) {
		$p = $pins[$n - 1]
		if (-not $p.qid) { continue }
		$q = $pfQ[[long]$p.qid]
		if (-not $q.ContainsKey('pre')) { continue }
		foreach ($pre in $q['pre'].Values) {
			$pp = $pinsByQid[[long]$pre]
			if ($pp) { $t = Nearest $p $pp; if ($t -and $t -ne $n) { $p.pre += $t; $links.pre++ } }
		}
	}
	$pfUsed = $QuestDbRef
	Write-Host "pfQuest: matched $matched of $(@($pins | ? { $cats[$_.cat - 1].title -match 'Quest|Repeatable' }).Count) quest pins"
}
# quest -> where its turn-in NPC stands (nearest pin naming that NPC)
for ($n = 1; $n -le $pins.Count; $n++) {
	$p = $pins[$n - 1]
	if (-not $p.qe) { continue }
	if ((Norm $p.qe) -eq (Norm $p.qs)) { continue }   # turned in where it started: no line to draw
	$at = $npcAt[(Norm $p.qe)]
	if ($at) { $t = Nearest $p $at; if ($t -and $t -ne $n) { $p.endp = $t; $links.endp++ } }
}
Write-Host "Links: $($links.endp) quest turn-ins, $($links.pre) prerequisites, $($links.dest) transport routes"

# ---------------------------------------------------------------------------------------------------------------------
# 5. Data.lua
# ---------------------------------------------------------------------------------------------------------------------
function LuaStr([string]$s) {
	$s = $s -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`t", ' '
	return '"' + $s + '"'
}
function NumList($list) { return '{' + (($list | % { [string]$_ }) -join ',') + '}' }
$inv = [Globalization.CultureInfo]::InvariantCulture
$sb = New-Object Text.StringBuilder
$stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm', $inv) + ' UTC'
[void]$sb.AppendLine('-- daves_map_data / Data.lua -- GENERATED by daves_map/tools/Update-MapData.ps1. Do not edit; do not commit (Map Genie''s data).')
[void]$sb.AppendLine("-- Source: $Url  ($stamp)")
[void]$sb.AppendLine('-- One global, read once by daves_map at its ADDON_LOADED (this addon is its ## OptionalDeps, so it loads first).')
[void]$sb.AppendLine('DAVES_MAP_DATA = {')
[void]$sb.AppendLine("source = { url = $(LuaStr $Url), map = $(LuaStr $mapTitle), mapId = $mapId, fetched = $(LuaStr $stamp), questDb = $(if ($pfUsed) { LuaStr ('pfQuest@' + $pfUsed) } else { 'false' }) },")
[void]$sb.AppendLine('groups = {')
foreach ($g in $groupOut) { [void]$sb.AppendLine("  { id = $($g.id), title = $(LuaStr $g.title), cats = $(NumList $g.cats) },") }
[void]$sb.AppendLine('},')
[void]$sb.AppendLine('cats = {')
foreach ($c in $cats) { [void]$sb.AppendLine("  { id = $($c.id), title = $(LuaStr $c.title), icon = $(LuaStr $c.icon), color = $(LuaStr $c.color), group = $($c.group), info = $(LuaStr (CleanText $c.info)) },") }
[void]$sb.AppendLine('},')
# columnar pin arrays: one Lua constant list each keeps the file small and quick to load
function Column([string]$name, $values) { [void]$sb.Append("$name = {"); [void]$sb.Append(($values -join ',')); [void]$sb.AppendLine('},') }
Column 'x' ($pins | % { $_.x.ToString($inv) })
Column 'y' ($pins | % { $_.y.ToString($inv) })
Column 'cat' ($pins | % { $_.cat })
Column 'fac' ($pins | % { $_.fac })
Column 'lvl' ($pins | % { $_.lvl })
Column 'cls' ($pins | % { $_.cls })
Column 'qid' ($pins | % { $_.qid })
Column 'endp' ($pins | % { $_.endp })
Column 'dest' ($pins | % { $_.dest })
[void]$sb.AppendLine('title = {'); foreach ($p in $pins) { [void]$sb.AppendLine((LuaStr $p.title) + ',') }; [void]$sb.AppendLine('},')
[void]$sb.AppendLine('text = {'); foreach ($p in $pins) { [void]$sb.AppendLine((LuaStr $p.text) + ',') }; [void]$sb.AppendLine('},')
[void]$sb.AppendLine('pre = {')
for ($n = 1; $n -le $pins.Count; $n++) { if ($pins[$n - 1].pre.Count) { [void]$sb.AppendLine("  [$n] = $(NumList ($pins[$n - 1].pre | Select-Object -Unique)),") } }
[void]$sb.AppendLine('},')
[void]$sb.AppendLine('}')
$outDir = Split-Path $Out -Parent
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
# an older build wrote Data.lua inside daves_map itself: use it for the change report, then remove it
$oldInAddon = Join-Path (Split-Path $PSScriptRoot -Parent) 'Data.lua'
$prevPath = if (Test-Path -LiteralPath $Out) { $Out } elseif (Test-Path -LiteralPath $oldInAddon) { $oldInAddon } else { $null }
$prev = if ($prevPath) { [IO.File]::ReadAllText($prevPath) } else { $null }
[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
Write-Host ("Wrote {0} ({1:N0} KB)" -f $Out, ((Get-Item -LiteralPath $Out).Length / 1KB))
# the companion addon's TOC, with daves_map's own Interface numbers (read and checked at the start)
$tocText = @"
## Interface: $iface
## Title: |cffd4a94eDave's|r Map (data)
## Notes: Map Genie's map data for Dave's Map, built on this machine by daves_map\tools\Update-MapData.ps1 ($stamp). Not in git.
## Author: generated
## Version: $((Get-Date).ToUniversalTime().ToString('yyyy.MM.dd', $inv))
## IconTexture: Interface\Icons\INV_Misc_Map_01

Data.lua
"@
[IO.File]::WriteAllText((Join-Path $outDir 'daves_map_data.toc'), $tocText, (New-Object Text.UTF8Encoding $false))
if (Test-Path -LiteralPath $oldInAddon) { Remove-Item -LiteralPath $oldInAddon; Write-Host "Removed the old $oldInAddon (the data now lives in daves_map_data)" }
# a zip to share privately (e.g. with a tester): unzipped into Interface\AddOns it is the daves_map_data addon, no
# scripts needed on their side. Next to the folder; *.zip is gitignored at the repo root.
$zip = Join-Path (Split-Path $outDir -Parent) 'daves_map_data.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
# built entry by entry: Windows PowerShell's Compress-Archive stores "\" in entry names, which other unzip tools
# turn into odd file names; the zip format wants "/"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
	foreach ($f in Get-ChildItem -LiteralPath $outDir -File) {
		[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, 'daves_map_data/' + $f.Name, [IO.Compression.CompressionLevel]::Optimal)
	}
} finally { $archive.Dispose() }
Write-Host ("Shareable copy: {0} ({1:N0} KB). Unzip into World of Warcraft\_classic_beta_\Interface\AddOns, restart the client." -f $zip, ((Get-Item -LiteralPath $zip).Length / 1KB))
Write-Host "First time on this machine: link it into the game, then restart the client fully:"
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File <kit>\scripts\Link-WowAddons.ps1 -Path `"$outDir`""

# what changed since the last build, per category
if ($prev -and $prev -match '(?m)^cat = \{([^}]*)\}') {
	$old = @{}; foreach ($v in $Matches[1].Split(',')) { if ($v) { $old[[int]$v]++ } }
	$oldTitles = @{}; $ci = 0
	# category lines only (group lines have no icon)
	foreach ($m in [regex]::Matches($prev, '(?m)^  \{ id = (\d+), title = "([^"]*)", icon')) { $ci++; $oldTitles[[int]$m.Groups[1].Value] = $ci }
	$changes = foreach ($c in $cats) {
		$nNew = @($pins | ? { $_.cat -eq $catIndex[$c.id] }).Count
		$nOld = if ($oldTitles[$c.id]) { [int]$old[$oldTitles[$c.id]] } else { 0 }
		if ($nNew -ne $nOld) { "  {0}: {1} -> {2}" -f $c.title, $nOld, $nNew }
	}
	if ($changes) { Write-Host 'Changed since the last build:'; $changes | % { Write-Host $_ } } else { Write-Host 'No change in pin counts since the last build.' }
}
if ($KeepRaw) { Write-Host "Raw downloads kept in $raw" } else { Remove-Item -LiteralPath $raw -Recurse -Force }
