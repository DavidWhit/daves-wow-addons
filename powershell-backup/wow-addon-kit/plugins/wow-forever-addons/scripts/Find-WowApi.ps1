<#
.SYNOPSIS
  Looks up functions and events in the local API index (Blizzard's own docs + UI source)
  so API questions are answered from the client's source, not from memory.

.EXAMPLE
  .\Find-WowApi.ps1 GetSpellInfo           # where did it go?
  .\Find-WowApi.ps1 'C_UnitAuras.*'        # wildcard over namespaced functions
  .\Find-WowApi.ps1 UNIT_AURA -Events      # events
  .\Find-WowApi.ps1 Unit* -SecretOnly      # what can return secret values
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory, Position = 0)][string]$Pattern,
	[ValidateSet('forever', 'live', 'ptr', 'classic', 'classic_era', 'classic_anniversary', 'classic_titan', 'beta')]
	[string]$Branch = 'forever',
	[switch]$Events,
	[switch]$SecretOnly,
	[int]$Max = 60
)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
$api = Get-WowApiIndex $Branch
if (-not $api) { Write-Warning "No index for '$Branch'. Run Update-WowApiIndex.ps1 -Branch $Branch first."; exit 1 }
Write-Host "API index: $Branch @ $($api.Commit.Substring(0,10))  ($($api.Source))" -ForegroundColor DarkGray

$wild = if ($Pattern -match '[*?]') { $Pattern } else { "*$Pattern*" }
if ($Events) {
	$hits = @($api.Events.Keys | Where-Object { $_ -like $wild } | Sort-Object)
	if ($SecretOnly) { $hits = @($hits | Where-Object { $api.Events[$_] }) }
	foreach ($h in ($hits | Select-Object -First $Max)) { "{0}{1}" -f $h, $(if ($api.Events[$h]) { '   [secret payloads]' } else { '' }) }
	Write-Host "$($hits.Count) event(s)" -ForegroundColor DarkGray
	exit 0
}

$hits = @($api.Functions.Keys | Where-Object { $_ -like $wild } | Sort-Object)
if ($SecretOnly) { $hits = @($hits | Where-Object { $api.Functions[$_].Count }) }
foreach ($h in ($hits | Select-Object -First $Max)) {
	$sec = $api.Functions[$h]
	"{0}{1}" -f $h, $(if ($sec.Count) { "   [secret: $($sec -join ', ')]" } else { '' })
}
Write-Host "$($hits.Count) documented function(s)" -ForegroundColor DarkGray

# For an exact bare name, say what the client knows about it as a global.
if ($Pattern -notmatch '[*?.]') {
	$g = $Pattern
	if ($api.Functions.ContainsKey($g)) { Write-Host "$g is a documented global function." -ForegroundColor Green }
	elseif ($api.Deprecated.ContainsKey($g)) { Write-Host "$g exists only through Blizzard's deprecation shim ($($api.Deprecated[$g])); it is scheduled for removal." -ForegroundColor Yellow }
	elseif ($api.Globals.Contains($g)) { Write-Host "$g is used or defined by Blizzard's own UI code on $Branch (FrameXML/engine global)." -ForegroundColor Green }
	else {
		Write-Host "$g is NOT a global on $Branch (not documented, not used by Blizzard's UI code)." -ForegroundColor Red
		if ($api.ByShort.ContainsKey($g)) { Write-Host "  Namespaced: $(@($api.ByShort[$g]) -join ', ')" -ForegroundColor Yellow }
	}
}
