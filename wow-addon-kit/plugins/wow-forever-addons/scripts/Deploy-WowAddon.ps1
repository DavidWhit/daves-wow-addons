<#
.SYNOPSIS
  Puts an addon into a WoW client's Interface\AddOns folder.

.DESCRIPTION
  -Mode Link (default): creates a directory junction AddOns\<Name> -> your source folder,
    so edits are live after /reload. Junctions need no admin rights.
  -Mode Copy: copies the files (minus dev-only files) for a release-like test.

  Safety: an existing *real* folder is never deleted. With -Force it is moved to
  Interface\AddOns.backup\<Name>-<timestamp>. An existing junction is unlinked without
  touching the files it points to.

.EXAMPLE
  .\Deploy-WowAddon.ps1 -Path C:\dev\CampTracker                 # Forever client, junction
  .\Deploy-WowAddon.ps1 -Path C:\dev\CampTracker -Mode Copy
  .\Deploy-WowAddon.ps1 -Path C:\dev\CampTracker -Remove          # unlink again
#>
[CmdletBinding(SupportsShouldProcess)]
param(
	[Parameter(Mandatory)][string]$Path,
	[ValidateSet('forever', 'retail', 'mists', 'titan', 'anniversary', 'classic_era')]
	[string]$Flavor = 'forever',
	[ValidateSet('Link', 'Copy')][string]$Mode = 'Link',
	[string]$AddOnsPath,
	[switch]$Remove,
	[switch]$Force
)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
$ErrorActionPreference = 'Stop'

$src = (Resolve-Path $Path).Path
$name = Split-Path $src -Leaf
if (-not $AddOnsPath) {
	$client = Get-WowInstall | Where-Object Flavor -eq $Flavor | Select-Object -First 1
	if (-not $client) { throw "No installed $Flavor client found. Run Find-WowInstall.ps1, or pass -AddOnsPath." }
	$AddOnsPath = $client.AddOns
}
New-Item -ItemType Directory -Force -Path $AddOnsPath | Out-Null
$target = Join-Path $AddOnsPath $name

if (Test-Path -LiteralPath $target) {
	if (Test-WowLink $target) {
		$current = Get-WowLinkTarget $target
		if ($Remove -or $Mode -eq 'Copy' -or ($current -and -not (Test-WowSamePath $current $src))) {
			if ($PSCmdlet.ShouldProcess($target, 'Unlink junction')) { Remove-WowLink $target; Write-Host "Unlinked $target" }
		} elseif ($Mode -eq 'Link') {
			Write-Host "Already linked: $target -> $src" -ForegroundColor Green; exit 0
		}
	} elseif ($Remove) {
		throw "$target is a real folder, not a link made by this script; not removing it."
	} elseif (Test-Path (Join-Path $target '.deployed-by-wow-addon-kit')) {
		# Our own earlier copy: safe to refresh.
		Remove-Item -LiteralPath $target -Recurse -Force
	} elseif ($Force) {
		$backup = Move-WowAddonToBackup $target
		Write-Host "Moved the existing folder to $backup" -ForegroundColor Yellow
	} else {
		throw "$target already exists as a real folder (maybe an installed copy of this addon). Re-run with -Force to move it to AddOns.backup first."
	}
}
if ($Remove) { exit 0 }

if ($Mode -eq 'Link') {
	if ($PSCmdlet.ShouldProcess($target, "Junction to $src")) {
		New-WowLink $target $src   # junction on Windows, symlink on macOS
		Write-Host "Linked $target -> $src" -ForegroundColor Green
	}
} else {
	$exclude = '.git', '.vscode', 'tests', '.release'
	$excludeFiles = '.luacheckrc', '.pkgmeta', '.gitignore', 'README.md', '*.zip'
	& robocopy $src $target /E /NFL /NDL /NJH /NJS /NP /XD @exclude /XF @excludeFiles | Out-Null
	if ($LASTEXITCODE -ge 8) { throw "robocopy failed with code $LASTEXITCODE" }
	Set-Content -Path (Join-Path $target '.deployed-by-wow-addon-kit') -Value (Get-Date -Format s)
	Write-Host "Copied $src -> $target" -ForegroundColor Green
}
Write-Host 'In game: /reload picks up Lua/XML edits. New files, TOC changes and new textures need a full client restart.'
exit 0   # robocopy's 1-7 "success" codes would otherwise leak out as failures
