<#
.SYNOPSIS
  Builds the drop-in addon daves_map_textures: OpenMap's stitched-map textures and data tables, for daves_map's
  seamless world map (daves_map\Stitch\).

.DESCRIPTION
  daves_map's seamless map is OpenMap's (MIT licence, github / CurseForge "OpenMap"), copied into daves_map\Stitch\.
  Its art and data tables are a separate addon, built here from an OpenMap release for WoW Forever:
    wowaddons\daves_map_textures\
      daves_map_textures.toc   (daves_map's Interface numbers)
      Data\*.lua               OpenMap's generated data tables the map uses (plain tables, no code)
      Export.lua               hands those tables to daves_map (the global DAVES_MAP_TEXTURES)
      Media\Textures\...       OpenMap's textures, cut from Blizzard's map art
      NOTICE-OpenMap.md, LICENSE-OpenMap.txt

  Left out on purpose:
  - Santiago Reyes' paintings. He lets OpenMap use them, which is not daves_map: the sea chart (MapChart), the
    hand-painted gaps between zones (MapGapFill, and the baked zone tiles MapZones, which have them painted in) and
    Forever's own dungeon maps (MapDungeonDrawn). Without them the gaps show plain map paper and the zones are drawn
    live, as OpenMap does with its "Filled gaps" option off.
  - What daves_map doesn't draw: dungeon maps, flight routes, fishing, zone levels, the changelog.

  Like daves_map_data, the result is never committed (.gitignore): it's Blizzard's art and 200 MB. Nothing here is
  downloaded; the source is an OpenMap folder or zip you downloaded yourself. Only files are copied; nothing from
  the source is run.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Update-MapTextures.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Update-MapTextures.ps1 -Source "$HOME\Downloads\OpenMap-v0.7.2-beta.zip" -Zip
#>
param(
	# an OpenMap release for WoW Forever: its folder (the one holding OpenMap.toc) or its zip. Default: OpenMap\ at the repo root
	[string]$Source,
	# also write daves_map_textures.zip next to the folder, to send a tester (large)
	[switch]$Zip
)
$ErrorActionPreference = 'Stop'
$addonDir = Split-Path $PSScriptRoot -Parent
$repo = Split-Path (Split-Path $addonDir -Parent) -Parent
if (-not $Source) { $Source = Join-Path $repo 'OpenMap' }
if (-not (Test-Path -LiteralPath $Source)) { throw "No OpenMap release at '$Source'. Pass -Source <folder or zip>." }

# the drop-in's TOC takes daves_map's Interface numbers (else it shows as out of date and never loads)
$mapToc = Join-Path $addonDir 'daves_map.toc'
$iface = ([regex]::Match([IO.File]::ReadAllText($mapToc), '(?m)^## Interface:\s*(.+?)\s*$')).Groups[1].Value
if (-not $iface) { throw "No '## Interface:' line in $mapToc." }

# a zip: unpacked into a new, empty folder of its own, read as files only, deleted at the end
$temp = $null
$src = (Resolve-Path -LiteralPath $Source).Path
if ((Get-Item -LiteralPath $src) -is [IO.FileInfo]) {
	if ($src -notmatch '\.zip$') { throw "-Source must be an OpenMap folder or a .zip." }
	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$temp = Join-Path ([IO.Path]::GetTempPath()) ('openmap-' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $temp | Out-Null
	[IO.Compression.ZipFile]::ExtractToDirectory($src, $temp)
	$toc = Get-ChildItem -LiteralPath $temp -Recurse -Filter 'OpenMap.toc' | Select-Object -First 1
	if (-not $toc) { throw "No OpenMap.toc in $Source." }
	$src = $toc.DirectoryName
}
try {
	# the Forever build only: its own OpenMap.toc at Forever's Interface (the Retail one has OpenMap_Mainline.toc and
	# Data\Retail, whose map IDs are Retail's)
	$omToc = Join-Path $src 'OpenMap.toc'
	if (-not (Test-Path -LiteralPath $omToc)) { throw "No OpenMap.toc in ${src}: that's not OpenMap's WoW Forever build (the Retail one is OpenMap_Mainline.toc)." }
	$tocText = [IO.File]::ReadAllText($omToc)
	$omIface = ([regex]::Match($tocText, '(?m)^## Interface:\s*(.+?)\s*$')).Groups[1].Value
	$omVersion = ([regex]::Match($tocText, '(?m)^## Version:\s*(.+?)\s*$')).Groups[1].Value
	$want = ($iface -split ',')[0].Trim()
	if (($omIface -split ',' | ForEach-Object { $_.Trim() }) -notcontains $want) {
		throw "OpenMap at $src is for Interface $omIface, not WoW Forever's $want."
	}

	# the data tables Stitch.lua, WorldMap.lua and Close.lua read (Data\GapFills, ZoneArt, Chart, DungeonDrawn: Santiago
	# Reyes' art; DungeonMaps, FlightData, Fishing, Levels, Changelog: OpenMap features daves_map leaves out)
	$DATA = 'ArtEdits', 'Banners', 'Caves', 'CaveMinimap', 'Gaps', 'GapPlaces', 'Grade', 'Labels', 'Minimap', 'MinimapLOD', 'Places', 'Reveal', 'Tones'
	$EXCLUDE = 'MapChart', 'MapGapFill', 'MapZones', 'MapDungeonDrawn'
	foreach ($d in $DATA) {
		$f = Join-Path $src "Data\$d.lua"
		if (-not (Test-Path -LiteralPath $f)) { throw "OpenMap $omVersion has no Data\$d.lua: daves_map\Stitch needs updating to this release." }
		# plain tables only: the drop-in runs these in game, so a release that put code in them would be a surprise
		if ([IO.File]::ReadAllText($f) -match '\bfunction\b|\bloadstring\b|\bsetfenv\b|_G\b') { throw "Data\$d.lua in OpenMap $omVersion holds code, not just tables: check it before using it." }
	}

	$out = Join-Path $repo 'wowaddons\daves_map_textures'
	if (Test-Path -LiteralPath $out) {
		# only ever clear our own build (its TOC says so)
		$own = Join-Path $out 'daves_map_textures.toc'
		if (-not (Test-Path -LiteralPath $own)) { throw "$out exists and isn't a daves_map_textures build; move it away first." }
		Remove-Item -LiteralPath $out -Recurse -Force
	}
	New-Item -ItemType Directory -Path (Join-Path $out 'Data') | Out-Null
	New-Item -ItemType Directory -Path (Join-Path $out 'Media\Textures') | Out-Null

	foreach ($d in $DATA) { Copy-Item -LiteralPath (Join-Path $src "Data\$d.lua") -Destination (Join-Path $out 'Data') }
	$texSrc = Join-Path $src 'Media\Textures'
	$copied, $bytes = 0, 0L
	foreach ($item in Get-ChildItem -LiteralPath $texSrc) {
		if ($EXCLUDE -contains $item.Name -or $item.Name -eq 'NOTICE.md') { continue }
		Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $out 'Media\Textures') -Recurse
	}
	foreach ($f in Get-ChildItem -LiteralPath (Join-Path $out 'Media') -Recurse -File) { $copied++; $bytes += $f.Length }
	Copy-Item -LiteralPath (Join-Path $texSrc 'NOTICE.md') -Destination (Join-Path $out 'NOTICE-OpenMap.md')
	Copy-Item -LiteralPath (Join-Path $src 'LICENSE.txt') -Destination (Join-Path $out 'LICENSE-OpenMap.txt')

	$utf8 = New-Object Text.UTF8Encoding $false
	$stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
	$toc = @"
## Interface: $iface
## Title: |cffd4a94eDave's|r Map (textures)
## Notes: OpenMap's stitched world map art and tables for Dave's Map (OpenMap $omVersion), built on this machine by daves_map\tools\Update-MapTextures.ps1 ($stamp). Not in git.
## Author: generated (OpenMap contributors; map art is Blizzard's)
## Version: $omVersion
## X-License: MIT (OpenMap's tables, LICENSE-OpenMap.txt); map art is Blizzard's (NOTICE-OpenMap.md)
## IconTexture: Interface\Icons\INV_Misc_Map_01

$(($DATA | ForEach-Object { "Data\$_.lua" }) -join "`r`n")
Export.lua
"@
	[IO.File]::WriteAllText((Join-Path $out 'daves_map_textures.toc'), $toc, $utf8)
	$export = @"
-- daves_map_textures / Export.lua -- GENERATED by daves_map\tools\Update-MapTextures.ps1. Do not edit; do not commit.
-- The data files above filled this addon's namespace (ns.MapReveal, ns.MapPlaces ...). daves_map (## OptionalDeps)
-- takes it as its stitched map's namespace (daves_map\Stitch\Base.lua). Its textures are under Media\.
local ADDON, ns = ...
ns.texturesAddon = ADDON
ns.openMapVersion = "$omVersion"
ns.built = "$stamp"
DAVES_MAP_TEXTURES = ns
"@
	[IO.File]::WriteAllText((Join-Path $out 'Export.lua'), $export, $utf8)
	Write-Host ("Built {0}: OpenMap {1}, {2} data tables, {3:N0} textures ({4:N0} MB). Left out: {5}." -f $out, $omVersion, $DATA.Count, $copied, ($bytes / 1MB), ($EXCLUDE -join ', '))

	if ($Zip) {
		$zipPath = Join-Path (Split-Path $out -Parent) 'daves_map_textures.zip'
		if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
		# entry by entry, with "/" in the names (Compress-Archive writes "\", which other unzip tools mangle)
		Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
		$archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
		try {
			foreach ($f in Get-ChildItem -LiteralPath $out -Recurse -File) {
				$rel = 'daves_map_textures/' + $f.FullName.Substring($out.Length + 1).Replace('\', '/')
				[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal)
			}
		} finally { $archive.Dispose() }
		Write-Host ("Shareable copy: {0} ({1:N0} MB). Unzip into World of Warcraft\_classic_beta_\Interface\AddOns, restart the client." -f $zipPath, ((Get-Item -LiteralPath $zipPath).Length / 1MB))
	}
	Write-Host "First time on this machine: link it into the game, then restart the client fully:"
	Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File <kit>\scripts\Link-WowAddons.ps1 -Path `"$out`""
} finally {
	if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
