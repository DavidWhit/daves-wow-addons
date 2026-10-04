<#
.SYNOPSIS
  Self-test for the kit: proves the validator catches every planted problem in
  fixtures\BrokenAddon, that a freshly scaffolded addon comes out clean, and that
  Link-WowAddons.ps1 links, re-points, backs up and unlinks correctly in a fake install.

.EXAMPLE
  .\tests\Invoke-KitSelfTest.ps1
#>
[CmdletBinding()]
param([switch]$KeepTemp)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scripts = Join-Path $root 'scripts'
$failed = 0; $passed = 0

function Assert([bool]$cond, [string]$what) {
	if ($cond) { $script:passed++; Write-Host "  PASS  $what" -ForegroundColor Green }
	else { $script:failed++; Write-Host "  FAIL  $what" -ForegroundColor Red }
}
function Invoke-Check([string]$path, [string[]]$flavor = @('forever')) {
	$json = & (Join-Path $scripts 'Test-WowAddon.ps1') -Path $path -Flavor $flavor -Json | Out-String
	return [pscustomobject]@{ Exit = $LASTEXITCODE; Result = ($json | ConvertFrom-Json) }
}
function Has($res, [string]$rule, [string]$sev, [int]$line = 0) {
	@($res.Findings | Where-Object { $_.Rule -eq $rule -and $_.Severity -eq $sev -and ($line -eq 0 -or $_.Line -eq $line) }).Count -gt 0
}

Write-Host 'Broken fixture (forever):' -ForegroundColor Cyan
$b = Invoke-Check (Join-Path $PSScriptRoot 'fixtures\BrokenAddon')
$r = $b.Result
Assert ($b.Exit -eq 1) 'exit code 1 when errors exist'
Assert (Has $r 'toc-missing-file' 'error') 'missing TOC file'
Assert (Has $r 'toc-interface' 'warn') 'Interface missing 16001'
Assert (Has $r 'file-case' 'warn') 'file name case mismatch'
Assert (Has $r 'toc-directive' 'info') 'unknown TOC directive'
Assert (Has $r 'savedvariables-unused' 'warn') 'unused SavedVariables'
Assert (Has $r 'unloaded-file' 'warn') 'Lua file not in TOC'
Assert (Has $r 'cleu-removed' 'error' 6) 'COMBAT_LOG_EVENT_UNFILTERED on Forever'
Assert (Has $r 'unknown-event' 'error' 7) 'unknown event'
Assert (Has $r 'moved-api' 'warn' 10) 'GetSpellInfo -> C_Spell'
Assert (Has $r 'unknown-global' 'warn' 11) 'UnitAura does not exist on Forever'
Assert (Has $r 'deprecated-api' 'warn' 12) 'deprecation shim call'
Assert (Has $r 'unknown-namespace' 'error' 13) 'unknown C_ namespace'
Assert (Has $r 'unknown-function' 'warn' 14) 'unknown C_ function'
Assert (Has $r 'secret-value' 'warn' 17) 'secret compared'
Assert (Has $r 'secret-value' 'warn' 18) 'secret concatenated'
Assert (Has $r 'slash-handler' 'error') 'slash command without handler'
Assert (-not (Has $r 'moved-api' 'warn' 5)) 'no false positive on CreateFrame'
$hasLuacheck = $null -ne (Get-Command luacheck -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:LOCALAPPDATA 'wow-addon-kit\bin\luacheck.exe'))
if ($hasLuacheck) {
	Assert (Has $r 'luacheck-W111' 'warn') 'accidental global (luacheck)'
	Assert (Has $r 'luacheck-E011' 'error') 'syntax error (luacheck)'
} else { Write-Host '  SKIP  luacheck checks (run scripts\Install-WowDevTools.ps1)' -ForegroundColor DarkGray }

Write-Host 'Invoked the way the skills do (powershell -File, comma-separated flavors):' -ForegroundColor Cyan
$json = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'Test-WowAddon.ps1') -Path (Join-Path $PSScriptRoot 'fixtures\BrokenAddon') -Flavor forever,retail -Json | Out-String
$fileExit = $LASTEXITCODE
$viaFile = $null; try { $viaFile = $json | ConvertFrom-Json } catch {}
Assert ($null -ne $viaFile -and $fileExit -eq 1) 'runs under -File and returns exit 1 for errors'
Assert ($null -ne $viaFile -and @($viaFile.Flavors).Count -eq 2) 'comma-separated -Flavor parsed into two flavors'

Write-Host 'Scaffold (forever, retail, classic_era):' -ForegroundColor Cyan
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("wowkit-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
	& (Join-Path $scripts 'New-WowAddon.ps1') -Name KitProbe -OutDir $tmp -Flavor forever, retail, classic_era -Author selftest -Icon INV_Misc_Gear_01 | Out-Null
	$probe = Join-Path $tmp 'KitProbe'
	Assert (Test-Path (Join-Path $probe 'KitProbe.toc')) 'TOC named after the folder'
	$toc = Get-Content (Join-Path $probe 'KitProbe.toc') -Raw
	Assert ($toc -match '## Interface: 16001\b') 'Forever Interface 16001 first'
	Assert ($toc -notmatch '\{\{') 'no unreplaced template tokens'
	$bytes = [IO.File]::ReadAllBytes((Join-Path $probe 'KitProbe.toc'))
	Assert (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'TOC written without BOM'
	$c = Invoke-Check $probe @('forever', 'retail', 'classic_era')
	Assert ($c.Exit -eq 0 -and $c.Result.Errors -eq 0 -and $c.Result.Warnings -eq 0) "scaffold is clean ($($c.Result.Errors) errors, $($c.Result.Warnings) warnings)"
} finally {
	if (-not $KeepTemp) { Remove-Item -LiteralPath $tmp -Recurse -Force } else { Write-Host "  kept $tmp" }
}

Write-Host 'Link-WowAddons (fake WoW install in a temp folder):' -ForegroundColor Cyan
Import-Module (Join-Path $scripts 'WowKit.psm1') -Force
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("wowkit-linktest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$wow = Join-Path $tmp 'World of Warcraft'; $src = Join-Path $tmp 'wowaddons'; $elsewhere = Join-Path $tmp 'elsewhere'
$fAdd = Join-Path $wow '_classic_beta_\Interface\AddOns'; $rAdd = Join-Path $wow '_retail_\Interface\AddOns'
try {
	foreach ($d in $fAdd, $rAdd, $elsewhere, "$src\ForeverOnly", "$src\Both", "$src\RetailOnly", "$src\NotAnAddon", "$fAdd\Both") { New-Item -ItemType Directory -Force -Path $d | Out-Null }
	Set-Content (Join-Path $wow '.build.info') "Branch!STRING:0|Active!DEC:1|Version!STRING:0|Product!STRING:0`nus|1|1.60.1.70205|wow_classic_beta`nus|1|12.1.0.65000|wow"
	Set-Content (Join-Path $wow '_classic_beta_\.flavor.info') "Product Flavor!STRING:0`nwow_classic_beta"   # _retail_ has none: name fallback
	Set-Content "$src\ForeverOnly\ForeverOnly.toc" '## Interface: 16001'
	Set-Content "$src\Both\Both.toc" '## Interface: 16001, 120100'
	Set-Content "$src\RetailOnly\RetailOnly_Mainline.toc" '## Interface: 120100'
	Set-Content "$src\NotAnAddon\README.md" 'no toc here'
	Set-Content "$fAdd\Both\marker.txt" 'installed copy'                       # real folder: must be backed up
	New-WowLink (Join-Path $rAdd 'RetailOnly') $elsewhere                     # stale link: must be re-pointed

	$inst = @(Get-WowInstall $wow)
	Assert (@($inst | Where-Object { $_.Folder -eq '_retail_' -and $_.Flavor -eq 'retail' }).Count -eq 1) 'client without .flavor.info identified by folder name'

	$link = Join-Path $scripts 'Link-WowAddons.ps1'
	& $link -Path $src -Root $wow -WhatIf 6>$null | Out-Null
	Assert ((Test-Path "$fAdd\Both\marker.txt") -and -not (Test-Path "$fAdd\ForeverOnly")) '-WhatIf changes nothing'

	$res = @(& $link -Path $src -Root $wow -PassThru 6>$null)
	function St($client, $addon) { ($res | Where-Object { $_.Client -eq $client -and $_.Addon -eq $addon }).Status }
	Assert (@($res | Where-Object Addon -eq 'NotAnAddon').Count -eq 0) 'folder without a TOC ignored'
	Assert ((St '_classic_beta_' 'ForeverOnly') -eq 'Linked' -and (Test-WowSamePath (Get-WowLinkTarget "$fAdd\ForeverOnly") "$src\ForeverOnly")) 'new addon linked'
	Assert ((St '_retail_' 'ForeverOnly') -eq 'Skipped' -and -not (Test-Path "$rAdd\ForeverOnly")) 'Forever-only addon not linked into Retail'
	Assert ((St '_classic_beta_' 'RetailOnly') -eq 'Skipped') 'flavor TOC (_Mainline) read: Retail-only addon not linked into Forever'
	Assert ((St '_retail_' 'RetailOnly') -eq 'Relinked' -and (Test-WowSamePath (Get-WowLinkTarget "$rAdd\RetailOnly") "$src\RetailOnly") -and (Test-Path $elsewhere)) 'stale link re-pointed, old target kept'
	$bak = @(Get-ChildItem (Join-Path $wow '_classic_beta_\Interface\AddOns.backup') -Directory -Filter 'Both-*' -ErrorAction SilentlyContinue)
	Assert ((Test-WowLink "$fAdd\Both") -and $bak.Count -eq 1 -and (Test-Path (Join-Path $bak[0].FullName 'marker.txt'))) 'real folder moved to AddOns.backup, then linked'

	$res = @(& $link -Path $src -Root $wow -PassThru 6>$null)
	Assert (@($res | Where-Object Status -eq 'AlreadyLinked').Count -eq 4 -and @($res | Where-Object Status -eq 'Skipped').Count -eq 2) 'second run leaves correct links alone'

	$res = @(& $link -Path "$src\Both" -Root $wow -Remove -PassThru 6>$null)
	Assert ($res.Count -eq 2 -and @($res | Where-Object Status -eq 'Unlinked').Count -eq 2 -and (Test-Path "$fAdd\ForeverOnly")) '-Path <one addon> touches only that addon'

	$res = @(& $link -Path $src -Root $wow -Remove -PassThru 6>$null)
	Assert (@($res | Where-Object Status -eq 'Unlinked').Count -eq 2 -and -not (Test-Path "$fAdd\ForeverOnly") -and -not (Test-Path "$fAdd\Both") -and (Test-Path "$src\Both\Both.toc")) '-Remove unlinks, sources intact'
} finally {
	# Unlink before deleting: Remove-Item -Recurse in 5.1 would follow a junction into its target.
	foreach ($a in $fAdd, $rAdd) { Get-ChildItem -LiteralPath $a -Force -ErrorAction SilentlyContinue | Where-Object { Test-WowLink $_.FullName } | ForEach-Object { Remove-WowLink $_.FullName } }
	if (-not $KeepTemp) { Remove-Item -LiteralPath $tmp -Recurse -Force } else { Write-Host "  kept $tmp" }
}

$example = Join-Path (Split-Path (Split-Path $root -Parent) -Parent) 'examples\HelloForever'
if (Test-Path $example) {
	Write-Host 'Example HelloForever:' -ForegroundColor Cyan
	$e = Invoke-Check $example @('forever', 'retail', 'classic_era')
	Assert ($e.Exit -eq 0 -and $e.Result.Errors -eq 0 -and $e.Result.Warnings -eq 0) "example is clean ($($e.Result.Errors) errors, $($e.Result.Warnings) warnings)"
}

Write-Host ''
$color = if ($failed) { 'Red' } else { 'Green' }
Write-Host "$passed passed, $failed failed" -ForegroundColor $color
if ($failed) { exit 1 } else { exit 0 }
