<#
.SYNOPSIS
  Creates a new WoW addon from the kit's template, ready for WoW: Forever.

.DESCRIPTION
  Writes <OutDir>\<Name>\ with a TOC (Interface numbers for every chosen flavor, taken
  from the installed clients when present), Core.lua (events, SavedVariables, slash
  command, Forever detection), Options.lua (Blizzard Settings panel), .luacheckrc,
  .pkgmeta, VS Code settings and a README. Then runs Test-WowAddon.ps1 on it.

.EXAMPLE
  .\New-WowAddon.ps1 -Name CampTracker -OutDir C:\dev\addons
  .\New-WowAddon.ps1 -Name CampTracker -Flavor forever,retail -Slash camp -Deploy
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]{1,48}$')][string]$Name,
	[string]$OutDir = (Get-Location).Path,
	# forever, retail, mists, titan, anniversary, classic_era (comma-separated or array)
	[string[]]$Flavor = @('forever'),
	[string]$Title,
	[string]$Notes = 'A WoW: Forever addon.',
	[string]$Author = $env:USERNAME,
	[string]$Version = '0.1.0',
	[ValidatePattern('^[a-z][a-z0-9]{1,15}$')][string]$Slash,
	[switch]$Deploy,
	[switch]$Force
)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
$ErrorActionPreference = 'Stop'
$Flavor = Resolve-WowFlavorList $Flavor

$dest = Join-Path $OutDir $Name
if ((Test-Path $dest) -and (Get-ChildItem $dest -Force | Select-Object -First 1) -and -not $Force) {
	throw "$dest already exists and is not empty. Pick another name or pass -Force to overwrite template files."
}

if (-not $Title) { $Title = ($Name -creplace '(?<=[a-z0-9])([A-Z])', ' $1') }
if (-not $Slash) { $Slash = ($Name.ToLower() -replace '[^a-z0-9]', ''); if ($Slash.Length -gt 12) { $Slash = $Slash.Substring(0, 12) } }

$installs = Get-WowInstall
$interfaces = @($Flavor | ForEach-Object { Get-WowInterfaceFor $_ $installs } | Where-Object { $_ } | Select-Object -Unique)
$db = "${Name}DB"

$tokens = [ordered]@{
	'{{NAME}}'        = $Name
	'{{TITLE}}'       = $Title
	'{{TITLEPLAIN}}'  = $Title
	'{{NOTES}}'       = $Notes
	'{{AUTHOR}}'      = $Author
	'{{VERSION}}'     = $Version
	'{{DB}}'          = $db
	'{{SLASH}}'       = $Slash
	'{{SLASHUPPER}}'  = $Name.ToUpper()
	'{{INTERFACES}}'  = ($interfaces -join ', ')
	'{{FLAVORS}}'     = ($Flavor -join ', ')
	'{{FLAVORLIST}}'  = ($Flavor -join ',')
	'--@globals@'     = "`"$db`",`n`t`"${Name}_OnAddonCompartmentClick`","
}

$template = Join-Path (Get-WowKitRoot) 'templates\addon'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false   # WoW reads UTF-8; no BOM keeps the TOC's first line clean
foreach ($src in (Get-ChildItem $template -Recurse -File -Force)) {
	$rel = $src.FullName.Substring($template.Length).TrimStart('\').Replace('__NAME__', $Name)
	$target = Join-Path $dest $rel
	New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
	$text = [IO.File]::ReadAllText($src.FullName)
	foreach ($k in $tokens.Keys) { $text = $text.Replace($k, $tokens[$k]) }
	[IO.File]::WriteAllText($target, $text, $utf8)
}

Write-Host "Created $dest" -ForegroundColor Green
Write-Host "  ## Interface: $($interfaces -join ', ')   SavedVariables: $db   Slash: /$Slash"
Write-Host ''
& (Join-Path $PSScriptRoot 'Test-WowAddon.ps1') -Path $dest -Flavor $Flavor
$ok = $LASTEXITCODE -eq 0

if ($Deploy) {
	foreach ($fl in $Flavor) { & (Join-Path $PSScriptRoot 'Deploy-WowAddon.ps1') -Path $dest -Flavor $fl }
}
if (-not $ok) { exit 1 }
