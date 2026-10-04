<#
.SYNOPSIS
  Self-test for the kit: proves the validator catches every planted problem in
  fixtures\BrokenAddon, and that a freshly scaffolded addon comes out clean.

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
