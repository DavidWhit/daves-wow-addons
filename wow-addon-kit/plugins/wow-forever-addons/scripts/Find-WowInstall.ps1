<#
.SYNOPSIS
  Finds World of Warcraft and lists every installed client (Forever, Retail, Classic...),
  its build, the TOC Interface number to use, and its AddOns folder.

.DESCRIPTION
  Reads Blizzard's own .build.info (install root) and .flavor.info (per client folder),
  so the Interface number comes from the build actually installed, not a hard-coded guess.

.EXAMPLE
  .\Find-WowInstall.ps1
  .\Find-WowInstall.ps1 -Json
#>
[CmdletBinding()]
param([string]$Root, [switch]$Json)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
if (-not $Root) { $Root = Get-WowRoot }
if (-not $Root) {
	Write-Warning 'World of Warcraft was not found (checked the registry, Program Files and drive roots). Pass -Root "D:\Games\World of Warcraft".'
	exit 1
}

$installs = Get-WowInstall $Root
if ($Json) { [pscustomobject]@{ Root = $Root; Clients = $installs } | ConvertTo-Json -Depth 4; exit 0 }

Write-Host "WoW root: $Root"
$installs | Format-Table Folder, Flavor, Product, Version, Interface, AddOns -AutoSize | Out-String -Width 250 | Write-Host
$forever = $installs | Where-Object Flavor -eq 'forever'
if ($forever) {
	Write-Host "WoW: Forever client: $($forever.Folder) -> ## Interface: $($forever.Interface)" -ForegroundColor Cyan
} else {
	Write-Host 'No WoW: Forever client found among the installed folders.' -ForegroundColor Yellow
}
