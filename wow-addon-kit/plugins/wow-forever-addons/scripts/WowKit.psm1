# WowKit.psm1 - shared helpers for the wow-forever-addons plugin scripts.
# Windows PowerShell 5.1 compatible (no ?:, ??, &&). The install and link helpers also run
# under PowerShell 7 on macOS; everything else assumes Windows.

$script:KitRoot = Split-Path $PSScriptRoot -Parent
# $IsWindows only exists in PowerShell 6+; OSVersion.Platform works in 5.1 and 7.
$script:IsWindowsOS = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

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
	if (-not $script:IsWindowsOS) {
		# macOS: Battle.net installs to /Applications/World of Warcraft, with .build.info and the
		# _retail_ / _classic_beta_ / ... client folders directly under it, as on Windows.
		$candidates.Add('/Applications/World of Warcraft')
		$candidates.Add((Join-Path $HOME 'Applications/World of Warcraft'))
		foreach ($c in $candidates) {
			if (Test-Path (Join-Path $c '.build.info')) { return (Resolve-Path $c).Path }
		}
		return $null
	}
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

# Which game an Interface number belongs to, by major/minor (Forever is 1.60.x = 160xx, Classic Era
# 1.15.x = 115xx, ...); any 11.x or later number is Retail. $null when no known flavor matches.
function Get-WowFlavorForInterface([int]$Interface) {
	foreach ($k in $script:KnownFlavors.Keys) {
		$known = $script:KnownFlavors[$k].Interface
		if ([math]::Floor($known / 100) -eq [math]::Floor($Interface / 100) -or ($k -eq 'retail' -and $Interface -ge 110000)) { return $k }
	}
	return $null
}

# Every installed client folder (_retail_, _classic_beta_, ...) with its product, build and Interface number.
function Get-WowInstall([string]$Root = (Get-WowRoot)) {
	if (-not $Root) { return @() }
	$build = @(Read-BlizzardInfoFile (Join-Path $Root '.build.info'))
	$out = foreach ($dir in (Get-ChildItem $Root -Directory | Where-Object { $_.Name -match '^_.+_$' })) {
		$flavorInfo = @(Read-BlizzardInfoFile (Join-Path $dir.FullName '.flavor.info'))
		$product = if ($flavorInfo.Count) { $flavorInfo[0].'Product Flavor' } else { $null }
		if (-not $product) {
			# No .flavor.info: Battle.net names the folders after the product (_retail_ = "wow",
			# _classic_beta_ = "wow_classic_beta"), so use that when .build.info lists the product.
			$guess = if ($dir.Name -eq '_retail_') { 'wow' } else { 'wow' + $dir.Name.TrimEnd('_') }
			if ($build | Where-Object { $_.Product -eq $guess }) { $product = $guess }
		}
		$row = $build | Where-Object { $_.Product -eq $product } | Select-Object -First 1
		$version = if ($row) { $row.Version } else { $null }
		$iface = if ($version) { ConvertTo-WowInterface $version } else { $null }
		$flavor = if ($iface) { Get-WowFlavorForInterface $iface } else { $null }
		[pscustomobject]@{
			Folder    = $dir.Name
			Flavor    = $flavor
			Product   = $product
			Version   = $version
			Interface = $iface
			Path      = $dir.FullName
			# Two Join-Paths, so the separator is right on macOS too.
			AddOns    = Join-Path (Join-Path $dir.FullName 'Interface') 'AddOns'
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

# --- Links in Interface\AddOns: a directory junction on Windows, a symlink on macOS. ---
# Used by Deploy-WowAddon.ps1 and Link-WowAddons.ps1. None of these prompt; callers do ShouldProcess.

function Test-WowLink([string]$Path) {
	$i = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	return [bool]($i -and ($i.Attributes -band [IO.FileAttributes]::ReparsePoint))
}

# Where a link points, as a full path ($null if it is not a link). 5.1 returns Target as an array.
function Get-WowLinkTarget([string]$Path) {
	$i = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	if (-not $i) { return $null }
	$t = @($i.Target) | Select-Object -First 1
	if (-not $t) { return $null }
	$t = ([string]$t) -replace '^\\\\\?\\|^\\\?\?\\', ''
	if (-not [IO.Path]::IsPathRooted($t)) { $t = Join-Path (Split-Path $Path -Parent) $t }
	return [IO.Path]::GetFullPath($t)
}

function Test-WowSamePath([string]$A, [string]$B) {
	if (-not $A -or -not $B) { return $false }
	$sep = [char[]]'\/'
	$a1 = [IO.Path]::GetFullPath($A).TrimEnd($sep); $b1 = [IO.Path]::GetFullPath($B).TrimEnd($sep)
	# Case-insensitive: NTFS and macOS's default APFS both are.
	return [string]::Equals($a1, $b1, [StringComparison]::OrdinalIgnoreCase)
}

function New-WowLink([string]$Path, [string]$Target) {
	$type = if ($script:IsWindowsOS) { 'Junction' } else { 'SymbolicLink' }
	New-Item -ItemType $type -Path $Path -Target $Target | Out-Null
}

# Removes only the link, never the files it points to. Never use Remove-Item -Recurse on a
# junction in PowerShell 5.1: it deletes the target's files.
function Remove-WowLink([string]$Path) {
	if (-not (Test-WowLink $Path)) { throw "$Path is not a link; not removing it." }
	if ($script:IsWindowsOS) { [IO.Directory]::Delete($Path, $false) }   # non-recursive: just the junction
	else { [IO.File]::Delete($Path) }                                      # unlink() on the symlink itself
}

# Moves a real folder out of AddOns to Interface\AddOns.backup\<Name>-<timestamp>; returns the new path.
function Move-WowAddonToBackup([string]$Path) {
	$addOns = Split-Path $Path -Parent
	$backupRoot = Join-Path (Split-Path $addOns -Parent) 'AddOns.backup'
	New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
	$base = Join-Path $backupRoot ("{0}-{1:yyyyMMdd-HHmmss}" -f (Split-Path $Path -Leaf), (Get-Date))
	$backup = $base; $n = 1
	while (Test-Path -LiteralPath $backup) { $n++; $backup = "$base-$n" }
	Move-Item -LiteralPath $Path -Destination $backup
	return $backup
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
