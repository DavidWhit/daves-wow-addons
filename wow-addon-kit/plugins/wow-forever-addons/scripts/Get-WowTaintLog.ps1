<#
.SYNOPSIS
  Reads the WoW client's taint log, the game's own record of which addon tainted
  what and which protected call was blocked. Start every taint or "action blocked"
  investigation here.

.DESCRIPTION
  The client writes Logs\taint.log (inside the client folder, e.g. _classic_beta_)
  once the player has run `/console taintLog 1` (1 = blocked actions, 2 = also
  global writes; it stays on). Each event is a header line plus a Blizzard stack:

    Execution tainted by <addon> while reading <what> - <C function>   <- where taint ENTERED
    An action was blocked because of taint from <addon> - <Function>() <- the symptom

  The "Execution tainted" line names the tainted value and the Blizzard code that
  read it. Open that file:line in the local UI source (data/ui-source/<branch>) and
  work backwards to the addon code that wrote the value.

.EXAMPLE
  .\Get-WowTaintLog.ps1                       # Forever client, last 10 events
  .\Get-WowTaintLog.ps1 -Addon daves_sack     # only events blaming this addon
  .\Get-WowTaintLog.ps1 -Flavor retail -Last 30
#>
[CmdletBinding()]
param(
	[string]$Flavor = 'forever',
	[string]$Addon,
	[int]$Last = 10,
	[string]$Root
)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
if (-not $Root) { $Root = Get-WowRoot }
if (-not $Root) { Write-Warning 'World of Warcraft was not found. Pass -Root "D:\Games\World of Warcraft".'; exit 1 }

$client = Get-WowInstall $Root | Where-Object Flavor -eq $Flavor | Select-Object -First 1
if (-not $client) { Write-Warning "No '$Flavor' client installed under $Root."; exit 1 }
$log = Join-Path (Join-Path $Root $client.Folder) 'Logs\taint.log'
if (-not (Test-Path $log)) {
	Write-Host "No taint log at $log" -ForegroundColor Yellow
	Write-Host 'In game: /console taintLog 1, reproduce the problem, then /reload (or log out) so the log is written.'
	exit 0
}

$item = Get-Item $log
Write-Host "Taint log: $log (written $($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"

# Split into events: a header line ("M/D HH:MM:SS.mmm  text") followed by indented stack lines.
$events = New-Object System.Collections.Generic.List[object]
$cur = $null
foreach ($line in [IO.File]::ReadAllLines($log)) {
	if ($line -match '^(\S+ \S+)  (\S.*)$') {
		$cur = [pscustomobject]@{ Time = $Matches[1]; Text = $Matches[2]; Stack = New-Object System.Collections.Generic.List[string] }
		$events.Add($cur)
	} elseif ($cur -and $line -match '^\S+ \S+\s{3,}(\S.*)$') {
		$cur.Stack.Add($Matches[1])
	}
}
if ($Addon) { $events = @($events | Where-Object { $_.Text -match [regex]::Escape($Addon) }) }
if (-not $events.Count) { Write-Host 'No matching events.'; exit 0 }

# Summary: which addon tainted which value, and which calls were blocked.
Write-Host "`n$($events.Count) event(s). Summary:" -ForegroundColor Cyan
$events | Group-Object { $_.Text -replace '\(<table: [0-9a-fA-F]+>\)', '(<table>)' } |
	Sort-Object Count -Descending |
	ForEach-Object { Write-Host ("  {0,3}x  {1}" -f $_.Count, $_.Name) }

Write-Host "`nLast $([Math]::Min($Last, $events.Count)) event(s), oldest first:" -ForegroundColor Cyan
foreach ($e in ($events | Select-Object -Last $Last)) {
	$color = if ($e.Text -like 'Execution tainted*') { 'Yellow' } elseif ($e.Text -like '*blocked*') { 'Red' } else { 'Gray' }
	Write-Host "`n$($e.Time)  $($e.Text)" -ForegroundColor $color
	foreach ($s in $e.Stack) { Write-Host "    $s" }
}
$branch = @{ forever = 'forever'; retail = 'live' }[$client.Flavor]
if (-not $branch) { $branch = '<branch>' }
Write-Host "`nNext: open each stack file:line in data/ui-source/$branch and find who wrote the value named after 'while reading'."
Write-Host "If Blizzard wrote it moments earlier in the same call, the taint came in before that: check what that call path read, and which of that state the addon touches."
