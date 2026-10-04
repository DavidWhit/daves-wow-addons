<#
.SYNOPSIS
  Links every addon in a folder (default: the repo's wowaddons\) into every installed WoW client.
  Run it after cloning or pulling.

.DESCRIPTION
  An addon folder is one that holds <Folder>.toc or <Folder>_<Flavor>.toc. Each one becomes
  Interface\AddOns\<Folder> in the client: a directory junction on Windows, a symlink on macOS
  (PowerShell 7). Edits in the repo are then live after /reload. No admin rights needed.

  Which clients: by default, every installed client whose game one of the addon's TOCs lists
  in "## Interface:" (16001 -> Forever, 120100 -> Retail, 11509 -> Classic Era, ...), so a
  Forever-only addon is not linked into Retail, where it would show as out of date.
  -Flavor forever,retail links into those clients regardless of the TOC; -Flavor all into every client.

  What is already there:
  - a link to this addon's folder is left alone;
  - a link pointing anywhere else is re-pointed;
  - a real folder (e.g. an installed release copy) is moved to
    Interface\AddOns.backup\<Name>-<timestamp> first, like Deploy-WowAddon.ps1 -Force.
  -Remove deletes only links that point at these addons; real folders and source files are never touched.

  -Path defaults to the nearest "wowaddons" folder found walking up from the current
  directory, then from this script's folder. It may also be one addon folder, to link just that addon.

.EXAMPLE
  .\Link-WowAddons.ps1 -WhatIf                          # show what would change
  .\Link-WowAddons.ps1                                  # link everything in the repo's wowaddons\
  .\Link-WowAddons.ps1 -Path D:\dev\addons -Flavor forever
  .\Link-WowAddons.ps1 -Path D:\dev\addons\CampTracker            # just one addon
  .\Link-WowAddons.ps1 -Remove                          # unlink them all again
  pwsh ./Link-WowAddons.ps1                             # macOS with PowerShell 7 (symlinks)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
	[string]$Path,
	[string[]]$Flavor,
	[string]$Root,
	[switch]$Remove,
	[switch]$PassThru
)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
$ErrorActionPreference = 'Stop'

# --- The addons to link ---
if (-not $Path) {
	foreach ($start in @((Get-Location).ProviderPath, $PSScriptRoot)) {
		$d = $start
		while ($d -and -not $Path) {
			$c = Join-Path $d 'wowaddons'
			if (Test-Path -LiteralPath $c -PathType Container) { $Path = $c }
			$d = Split-Path $d -Parent
		}
		if ($Path) { break }
	}
	if (-not $Path) { throw 'No wowaddons folder found above the current folder or this script. Pass -Path "<folder with addon folders>".' }
}
$Path = (Resolve-Path -LiteralPath $Path).Path

function Get-AddonToc($dir) {
	@(Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.toc' | Where-Object {
		$_.BaseName -eq $dir.Name -or $_.BaseName.StartsWith($dir.Name + '_')
	})
}
# -Path may also be a single addon folder: then link just that one.
$candidates = if ((Get-AddonToc (Get-Item -LiteralPath $Path)).Count) { @(Get-Item -LiteralPath $Path) } else { @(Get-ChildItem -LiteralPath $Path -Directory) }
$addons = foreach ($dir in $candidates) {
	$tocs = Get-AddonToc $dir
	if (-not $tocs.Count) { continue }
	# Flavors the TOCs target, from "## Interface: 16001, 120100" (and "## Interface-Xyz:" lines).
	$targets = @(foreach ($t in $tocs) {
		foreach ($line in (Get-Content -LiteralPath $t.FullName -TotalCount 40)) {
			if ($line -match '^\s*##\s*Interface(-\w+)?\s*:\s*(.+)$') {
				foreach ($n in ($Matches[2] -split ',')) {
					if ($n.Trim() -match '^\d{5,6}$') { Get-WowFlavorForInterface ([int]$n.Trim()) }
				}
			}
		}
	}) | Where-Object { $_ } | Select-Object -Unique
	[pscustomobject]@{ Name = $dir.Name; Path = $dir.FullName; Flavors = @($targets) }
}
$addons = @($addons)
if (-not $addons.Count) { throw "No addon folders (<Folder>\<Folder>.toc) in $Path." }

# --- The clients to link into ---
if (-not $Root) { $Root = Get-WowRoot }
if (-not $Root) { throw 'World of Warcraft was not found. Pass -Root "<WoW install folder>" (the one holding .build.info).' }
$clients = @(Get-WowInstall $Root)
if (-not $clients.Count) { throw "No client folders (_retail_, _classic_beta_, ...) under $Root." }

$forced = $null   # $null = follow the TOCs
if ($Flavor) {
	$list = @($Flavor | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLower() })
	if ($list -contains 'all') { $forced = 'all' } else {
		$forced = @(Resolve-WowFlavorList $list)
		foreach ($f in $forced) { if (-not ($clients | Where-Object Flavor -eq $f)) { Write-Warning "No installed $f client; skipping it." } }
		$clients = @($clients | Where-Object { $forced -contains $_.Flavor })
		if (-not $clients.Count) { throw "No installed client for flavor(s) $($forced -join ', '). Run Find-WowInstall.ps1 to see what is installed." }
	}
}

# --- Link (or unlink) each addon in each client ---
$results = New-Object System.Collections.Generic.List[object]
function Add-Result($client, $addon, [string]$status, [string]$detail = '') {
	$results.Add([pscustomobject]@{ Client = $client.Folder; Flavor = $client.Flavor; Addon = $addon.Name; Status = $status; Detail = $detail })
}

foreach ($client in $clients) {
	foreach ($addon in $addons) {
		$target = Join-Path $client.AddOns $addon.Name
		try {
			$exists = $null -ne (Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue)   # Test-Path is false for a broken link
			$isLink = $exists -and (Test-WowLink $target)
			$current = if ($isLink) { Get-WowLinkTarget $target } else { $null }
			$ours = $isLink -and (Test-WowSamePath $current $addon.Path)

			if ($Remove) {
				if (-not $exists) { Add-Result $client $addon 'NotLinked' }
				elseif (-not $isLink) { Add-Result $client $addon 'Kept' 'real folder, not a link; left alone' }
				elseif (-not $ours) { Add-Result $client $addon 'Kept' "links to $current; left alone" }
				elseif ($PSCmdlet.ShouldProcess($target, 'Remove link')) { Remove-WowLink $target; Add-Result $client $addon 'Unlinked' }
				else { Add-Result $client $addon 'WouldUnlink' }
				continue
			}

			if ($null -eq $forced -and $addon.Flavors -notcontains $client.Flavor) {
				$why = if ($client.Flavor) { "TOC has no $($client.Flavor) Interface" } else { 'unknown client flavor' }
				if ($ours) { $why += '; existing link left alone' }
				Add-Result $client $addon 'Skipped' $why
				continue
			}

			if ($ours) { Add-Result $client $addon 'AlreadyLinked' }
			elseif ($isLink) {
				if ($PSCmdlet.ShouldProcess($target, "Re-point link from $current to $($addon.Path)")) {
					Remove-WowLink $target; New-WowLink $target $addon.Path
					Add-Result $client $addon 'Relinked' "was -> $current"
				} else { Add-Result $client $addon 'WouldRelink' "now -> $current" }
			} elseif ($exists) {
				if ($PSCmdlet.ShouldProcess($target, "Move real folder to AddOns.backup, then link to $($addon.Path)")) {
					$backup = Move-WowAddonToBackup $target
					New-WowLink $target $addon.Path
					Add-Result $client $addon 'Linked' "real folder moved to $backup"
				} else { Add-Result $client $addon 'WouldLink' 'real folder would move to AddOns.backup first' }
			} else {
				if ($PSCmdlet.ShouldProcess($target, "Link to $($addon.Path)")) {
					New-Item -ItemType Directory -Force -Path $client.AddOns | Out-Null
					New-WowLink $target $addon.Path
					Add-Result $client $addon 'Linked'
				} else { Add-Result $client $addon 'WouldLink' }
			}
		} catch {
			Add-Result $client $addon 'Failed' $_.Exception.Message
		}
	}
}

# --- Summary ---
$kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'junctions' } else { 'symlinks' }
Write-Host "Addons: $Path"
Write-Host "WoW:    $Root ($kind)"
$results | Format-Table Client, Flavor, Addon, Status, Detail -AutoSize | Out-String -Width 250 | Write-Host
$counts = $results | Group-Object Status | ForEach-Object { "$($_.Count) $($_.Name)" }
$failed = @($results | Where-Object Status -eq 'Failed').Count
$color = if ($failed) { 'Red' } else { 'Green' }
Write-Host ($counts -join ', ') -ForegroundColor $color
if (@($results | Where-Object { $_.Status -in 'Linked', 'Relinked' }).Count) {
	Write-Host 'In game: fully restart the client once so it sees newly linked addons, then enable them in the AddOns list.'
}
if ($PassThru) { $results }
if ($failed) { exit 1 } else { exit 0 }
