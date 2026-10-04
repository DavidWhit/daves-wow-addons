# WowKit.psm1 - shared helpers for the wow-forever-addons plugin scripts.
# Windows PowerShell 5.1 compatible (no ?:, ??, &&).

$script:KitRoot = Split-Path $PSScriptRoot -Parent

# Interface numbers per flavor, from Warcraft Wiki "Public client builds"
# (https://warcraft.wiki.gg/wiki/Public_client_builds, checked 2026-10-03).
# Installed clients override these at runtime (see Get-WowInstall), so a patch
# that bumps the number is picked up without editing this table.
#
# Family / Game are what the TOC path variables [Family] and [Game] expand to, and the
# game-type names AllowLoadGameType / ExcludeLoadGameType match. Taken from Blizzard's own
# TOCs on the forever branch, e.g. Blizzard_UnitFrame.toc:
#   [Family]\UnitFramePvPIndicatorStyle.lua  [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]
#   [Game]\UnitFramePvPIndicatorStyle.lua    [AllowLoadGameType camelot]
# i.e. Forever is game type "camelot" inside the "mainline" family.
$script:KnownFlavors = [ordered]@{
	forever     = @{ Interface = 16001;  Version = '1.60.1'; GameType = 'camelot';  Family = 'Mainline'; TocSuffix = 'Camelot'; ApiBranch = 'forever' }
	retail      = @{ Interface = 120100; Version = '12.1.0'; GameType = 'standard'; Family = 'Mainline'; TocSuffix = 'Mainline'; ApiBranch = 'live' }
	mists       = @{ Interface = 50504;  Version = '5.5.4';  GameType = 'mists';    Family = 'Classic';  TocSuffix = 'Mists'; ApiBranch = 'classic' }
	titan       = @{ Interface = 38002;  Version = '3.80.2'; GameType = 'wrath';    Family = 'Classic';  TocSuffix = 'Wrath'; ApiBranch = 'classic_titan' }
	anniversary = @{ Interface = 20506;  Version = '2.5.6';  GameType = 'tbc';      Family = 'Classic';  TocSuffix = 'TBC'; ApiBranch = 'classic_anniversary' }
	classic_era = @{ Interface = 11509;  Version = '1.15.9'; GameType = 'vanilla';  Family = 'Classic';  TocSuffix = 'Vanilla'; ApiBranch = 'classic_era' }
}

# "-Flavor forever,retail" arrives as one string under "powershell -File", as an array in-process; accept both.
function Resolve-WowFlavorList([string[]]$Flavor) {
	$list = @($Flavor | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLower() } | Select-Object -Unique)
	$bad = @($list | Where-Object { -not $script:KnownFlavors.Contains($_) })
	if ($bad.Count) { throw "Unknown flavor(s): $($bad -join ', '). Use: $($script:KnownFlavors.Keys -join ', ')" }
	if (-not $list.Count) { $list = @('forever') }
	return $list
}

function Get-WowKitRoot { $script:KitRoot }
function Get-WowKnownFlavors { $script:KnownFlavors }

# "1.60.1" -> 16001, "12.1.0" -> 120100 (the TOC Interface encoding: major*10000 + minor*100 + patch).
function ConvertTo-WowInterface([string]$Version) {
	$p = $Version.Split('.')
	if ($p.Count -lt 3) { return $null }
	return [int]$p[0] * 10000 + [int]$p[1] * 100 + [int]$p[2]
}

function Get-WowRoot {
	$candidates = New-Object System.Collections.Generic.List[string]
	foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
		try {
			$ip = (Get-ItemProperty $key -ErrorAction Stop).InstallPath
			if ($ip) { $candidates.Add((Split-Path ($ip.TrimEnd('\')) -Parent)); $candidates.Add($ip.TrimEnd('\')) }
		} catch {}
	}
	$candidates.Add("${env:ProgramFiles(x86)}\World of Warcraft")
	$candidates.Add("$env:ProgramFiles\World of Warcraft")
	foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
		$candidates.Add((Join-Path $d.Root 'World of Warcraft'))
		$candidates.Add((Join-Path $d.Root 'Games\World of Warcraft'))
	}
	foreach ($c in $candidates) {
		if ($c -and (Test-Path (Join-Path $c '.build.info'))) { return (Resolve-Path $c).Path }
	}
	return $null
}

# Reads Blizzard's pipe-delimited .build.info / .flavor.info ("Name!TYPE:n|..." header row).
function Read-BlizzardInfoFile([string]$Path) {
	if (-not (Test-Path $Path)) { return @() }
	$lines = @(Get-Content $Path | Where-Object { $_ -and -not $_.StartsWith('#') })
	if ($lines.Count -lt 2) { return @() }
	$cols = @($lines[0].Split('|') | ForEach-Object { $_.Split('!')[0] })
	$rows = foreach ($l in $lines[1..($lines.Count - 1)]) {
		$v = $l.Split('|'); $o = [ordered]@{}
		for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = if ($i -lt $v.Count) { $v[$i] } else { '' } }
		[pscustomobject]$o
	}
	return @($rows)
}

# Every installed client folder (_retail_, _classic_beta_, ...) with its product, build and Interface number.
function Get-WowInstall([string]$Root = (Get-WowRoot)) {
	if (-not $Root) { return @() }
	$build = @(Read-BlizzardInfoFile (Join-Path $Root '.build.info'))
	$out = foreach ($dir in (Get-ChildItem $Root -Directory | Where-Object { $_.Name -match '^_.+_$' })) {
		$flavorInfo = @(Read-BlizzardInfoFile (Join-Path $dir.FullName '.flavor.info'))
		$product = if ($flavorInfo.Count) { $flavorInfo[0].'Product Flavor' } else { $null }
		$row = $build | Where-Object { $_.Product -eq $product } | Select-Object -First 1
		$version = if ($row) { $row.Version } else { $null }
		$iface = if ($version) { ConvertTo-WowInterface $version } else { $null }
		# Identify the game by its Interface major/minor (Forever is 1.60.x, Classic Era 1.15.x, ...).
		$flavor = $null
		if ($iface) {
			foreach ($k in $script:KnownFlavors.Keys) {
				$known = $script:KnownFlavors[$k].Interface
				if ([math]::Floor($known / 100) -eq [math]::Floor($iface / 100) -or ($k -eq 'retail' -and $iface -ge 110000)) { $flavor = $k; break }
			}
		}
		[pscustomobject]@{
			Folder    = $dir.Name
			Flavor    = $flavor
			Product   = $product
			Version   = $version
			Interface = $iface
			Path      = $dir.FullName
			AddOns    = Join-Path $dir.FullName 'Interface\AddOns'
		}
	}
	return @($out)
}

# The Interface number to target for a flavor: the installed client's if present, else the known table.
function Get-WowInterfaceFor([string]$Flavor, $Installs = $null) {
	if ($null -eq $Installs) { $Installs = Get-WowInstall }
	$hit = $Installs | Where-Object { $_.Flavor -eq $Flavor -and $_.Interface } | Sort-Object Interface -Descending | Select-Object -First 1
	if ($hit) { return $hit.Interface }
	if ($script:KnownFlavors.Contains($Flavor)) { return $script:KnownFlavors[$Flavor].Interface }
	return $null
}

$script:ApiCache = @{}
function Get-WowApiIndex([string]$Branch = 'forever') {
	if ($script:ApiCache.ContainsKey($Branch)) { return $script:ApiCache[$Branch] }
	$file = Join-Path $script:KitRoot "data\api-$Branch.json"
	if (-not (Test-Path $file)) { return $null }
	$raw = Get-Content $file -Raw | ConvertFrom-Json
	$idx = @{
		Commit     = $raw.commit
		Source     = $raw.source
		Functions  = @{}
		Events     = @{}
		Namespaces = @{}
		Deprecated = @{}
		ByShort    = @{}   # "GetSpellInfo" -> "C_Spell.GetSpellInfo" (namespaced replacements)
		Globals    = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
	}
	# Globals Blizzard's own Lua on this branch calls or defines (CreateFrame, PlaySound, ...).
	foreach ($g in $raw.globals) { [void]$idx.Globals.Add($g) }
	# Namespaces Blizzard moved the classic globals into; listed first when a name exists in several.
	$canonical = 'C_Item', 'C_Spell', 'C_Container', 'C_AddOns', 'C_ChatInfo', 'C_CurrencyInfo', 'C_UnitAuras', 'C_SpellBook', 'C_Map', 'C_QuestLog'
	foreach ($p in $raw.functions.PSObject.Properties) {
		$idx.Functions[$p.Name] = @($p.Value.secret)
		$dot = $p.Name.IndexOf('.')
		if ($dot -gt 0) {
			$short = $p.Name.Substring($dot + 1)
			if (-not $idx.ByShort.ContainsKey($short)) { $idx.ByShort[$short] = New-Object System.Collections.Generic.List[string] }
			if ($canonical -contains $p.Name.Substring(0, $dot)) { $idx.ByShort[$short].Insert(0, $p.Name) } else { $idx.ByShort[$short].Add($p.Name) }
		}
	}
	foreach ($p in $raw.events.PSObject.Properties) { $idx.Events[$p.Name] = [bool]$p.Value.secretPayloads }
	foreach ($n in $raw.namespaces) { $idx.Namespaces[$n] = $true }
	foreach ($p in $raw.deprecated.PSObject.Properties) { $idx.Deprecated[$p.Name] = $p.Value }
	$script:ApiCache[$Branch] = $idx
	return $idx
}

# luacheck: PATH first, then the kit's tool folder (Install-WowDevTools.ps1 puts it there).
function Get-WowKitToolDir { Join-Path $env:LOCALAPPDATA 'wow-addon-kit\bin' }
function Find-Luacheck {
	$cmd = Get-Command luacheck -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	$local = Join-Path (Get-WowKitToolDir) 'luacheck.exe'
	if (Test-Path $local) { return $local }
	return $null
}

Export-ModuleMember -Function *
