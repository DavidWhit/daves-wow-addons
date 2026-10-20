<#
.SYNOPSIS
  Reads the Lua errors, blocked actions and Lua warnings the game recorded, newest first. Start every in-game bug
  investigation here, then read the taint log (Get-WowTaintLog.ps1).

.DESCRIPTION
  The client shows Lua errors in a pop-up (/console scriptErrors 1) but keeps no record of them on disk. The kit's
  development addon !WowKitErrors (devaddons\!WowKitErrors) records them into its SavedVariables, which the game writes
  on /reload or logout:
    WTF\Account\<account>\SavedVariables\!WowKitErrors.lua
  This script reads that file (as data: its own Lua-literal reader, nothing is run) and prints, newest first:
    error      a Lua error: the message and the stack at the error (file:line of the addon code that failed)
    blocked    ADDON_ACTION_BLOCKED: an addon called a protected function from tainted code (see the taint log)
    forbidden  ADDON_ACTION_FORBIDDEN: an addon called a function addons may never call
    warning    LUA_WARNING: a warning the client raised (deprecated use, bad arguments, ...)
    probe      a taint probe run by hand in game (/wkprobe)
  Each entry carries its session (one per login or /reload) and how often it repeated in that session.
  The first blocked or forbidden entry of each kind per session (and every probe) also carries a taint probe: the
  values an addon had written, as issecurevariable reports them, on the frames under the mouse and their parents, on
  Blizzard's global tables and frames, and Blizzard globals an addon replaced. Read it before the taint log.

  It also scans the client's Logs\*.log for "Lua Error" lines, in case the client wrote any itself.

  If the recorder isn't installed in the client yet, it links it (Link-WowAddons.ps1 does the same with every link),
  then says what's left: restart the client fully, reproduce, /reload.

.EXAMPLE
  .\Get-WowScriptErrors.ps1                       # Forever client, the last 15 entries
  .\Get-WowScriptErrors.ps1 -Addon daves_map      # only entries whose message or stack names this addon
  .\Get-WowScriptErrors.ps1 -Session 0            # every session (default: the newest session that has entries)
  .\Get-WowScriptErrors.ps1 -Flavor retail -Last 40
#>
[CmdletBinding()]
param(
	[string]$Flavor = 'forever',
	[string]$Addon,
	[int]$Last = 15,
	[int]$Session = -1,      # -1: the newest session with entries; 0: all sessions; n: that session
	[string]$Root,
	[string]$File            # read this SavedVariables file instead of finding it (tests, other machines' copies)
)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
if (-not $Root) { $Root = Get-WowRoot }
if (-not $Root) { Write-Warning 'World of Warcraft was not found. Pass -Root "D:\Games\World of Warcraft".'; exit 1 }
$client = Get-WowInstall $Root | Where-Object Flavor -eq $Flavor | Select-Object -First 1
if (-not $client) { Write-Warning "No '$Flavor' client installed under $Root."; exit 1 }
$clientDir = Join-Path $Root $client.Folder
$devAddon = Join-Path (Split-Path $PSScriptRoot -Parent) 'devaddons\!WowKitErrors'

# ---------------------------------------------------------------------------------------------------------------------
# A reader for the Lua table literal the game writes (data only: tables, strings, numbers, booleans)
# ---------------------------------------------------------------------------------------------------------------------
if (-not ('WowKit.LuaData' -as [type])) {
	Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
namespace WowKit {
public static class LuaData {
	public static object ParseAssigned(string text, string name) {
		int at = text.IndexOf(name + " =", StringComparison.Ordinal);
		if (at < 0) return null;
		int p = text.IndexOf('=', at) + 1;
		return Value(text, ref p);
	}
	static void Skip(string s, ref int p) {
		while (p < s.Length) {
			if (char.IsWhiteSpace(s[p])) { p++; continue; }
			if (s[p] == '-' && p + 1 < s.Length && s[p + 1] == '-') { while (p < s.Length && s[p] != '\n') p++; continue; }
			break;
		}
	}
	static object Value(string s, ref int p) {
		Skip(s, ref p);
		char c = s[p];
		if (c == '{') return Table(s, ref p);
		if (c == '"' || c == '\'') return Str(s, ref p);
		if (c == '-' || c == '.' || char.IsDigit(c)) {
			int q = p; if (s[q] == '-') q++;
			while (q < s.Length && (char.IsDigit(s[q]) || s[q] == '.' || s[q] == 'e' || s[q] == 'E' || ((s[q] == '-' || s[q] == '+') && (s[q - 1] == 'e' || s[q - 1] == 'E')))) q++;
			double d = double.Parse(s.Substring(p, q - p), CultureInfo.InvariantCulture); p = q;
			if (d == Math.Floor(d) && Math.Abs(d) < 9e15) return (long)d;
			return d;
		}
		if (string.CompareOrdinal(s, p, "true", 0, 4) == 0) { p += 4; return true; }
		if (string.CompareOrdinal(s, p, "false", 0, 5) == 0) { p += 5; return false; }
		if (string.CompareOrdinal(s, p, "nil", 0, 3) == 0) { p += 3; return null; }
		throw new FormatException("unexpected '" + c + "' at " + p);
	}
	static Dictionary<object, object> Table(string s, ref int p) {
		var t = new Dictionary<object, object>(); p++; long n = 1;
		while (true) {
			Skip(s, ref p);
			if (s[p] == '}') { p++; return t; }
			object key = null;
			if (s[p] == '[') {
				p++; key = Value(s, ref p); Skip(s, ref p); p++; Skip(s, ref p); p++;   // ] =
			} else if (char.IsLetter(s[p]) || s[p] == '_') {
				int q = p; while (q < s.Length && (char.IsLetterOrDigit(s[q]) || s[q] == '_')) q++;
				int r = q; Skip(s, ref r);
				if (r < s.Length && s[r] == '=' && (r + 1 >= s.Length || s[r + 1] != '=')) { key = s.Substring(p, q - p); p = r + 1; }
			}
			object v = Value(s, ref p);
			if (key == null) key = n++;
			if (v != null) t[key] = v;
			Skip(s, ref p);
			if (s[p] == ',' || s[p] == ';') p++;
		}
	}
	static string Str(string s, ref int p) {
		char quote = s[p++]; var sb = new StringBuilder();
		while (true) {
			char c = s[p++];
			if (c == quote) return sb.ToString();
			if (c != '\\') { sb.Append(c); continue; }
			char e = s[p++];
			switch (e) {
				case 'n': sb.Append('\n'); break;
				case 't': sb.Append('\t'); break;
				case 'r': break;
				case '\n': sb.Append('\n'); break;
				default:
					if (char.IsDigit(e)) { int v = e - '0', k = 1; while (k < 3 && char.IsDigit(s[p])) { v = v * 10 + (s[p++] - '0'); k++; } sb.Append((char)v); }
					else sb.Append(e);
					break;
			}
		}
	}
}
}
'@
}

# ---------------------------------------------------------------------------------------------------------------------
# 1. !WowKitErrors's SavedVariables (the newest across accounts)
# ---------------------------------------------------------------------------------------------------------------------
$devToc = Join-Path $clientDir 'Interface\AddOns\!WowKitErrors\!WowKitErrors.toc'
if (-not $File -and -not (Test-Path -LiteralPath $devToc)) {
	# Not in this client yet: put it in now, so the next session is recorded.
	Write-Host 'The kit''s error recorder (!WowKitErrors) was not installed in this client. Linking it now:'
	try { & (Join-Path $PSScriptRoot 'Link-WowAddons.ps1') -Path $devAddon -Flavor $Flavor -Root $Root 6>$null | Out-Null } catch { Write-Host "  $($_.Exception.Message)" }
	if (Test-Path -LiteralPath $devToc) {
		Write-Host "  linked into $($client.Folder)\Interface\AddOns\!WowKitErrors" -ForegroundColor Green
		Write-Host '  Fully restart the client (a new addon), reproduce the problem, then /reload so it is written.'
	} else {
		Write-Host '  the link failed. Run it by hand to see why:' -ForegroundColor Red
		Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Link-WowAddons.ps1`" -Path `"$devAddon`" -Flavor $Flavor"
	}
}
$files = if ($File) { @(Get-Item -LiteralPath $File) } else {
	@(Get-ChildItem -LiteralPath (Join-Path $clientDir 'WTF\Account') -Recurse -Filter '!WowKitErrors.lua' -ErrorAction SilentlyContinue |
		Where-Object { $_.DirectoryName -like '*SavedVariables' } | Sort-Object LastWriteTime -Descending)
}
$entries = @()
if ($files.Count -eq 0) {
	Write-Host 'No recorded script errors yet.' -ForegroundColor Yellow
	Write-Host 'In game: make sure WowKit Error Log is enabled in the AddOns list, reproduce the problem, then /reload (or log out) so its file is written.'
} else {
	$svFile = $files[0]
	Write-Host ("Script errors: {0} (written {1})" -f $svFile.FullName, $svFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
	$db = [WowKit.LuaData]::ParseAssigned([IO.File]::ReadAllText($svFile.FullName), 'WowKitErrorsDB')
	if ($db -and $db.ContainsKey('entries')) {
		$entries = @($db['entries'].Keys | Sort-Object | ForEach-Object {
			$e = $db['entries'][$_]
			[pscustomobject]@{
				Kind = [string]$e['kind']; Message = [string]$e['message']; Stack = [string]$e['stack']
				Count = [int]$e['count']; Time = [string]$e['time']; Last = [string]$e['last']; Session = [int]$e['session']
				Taint = [string]$e['taint']
			}
		})
	}
	if ($Addon) {
		$pat = '(AddOns[\\/]' + [regex]::Escape($Addon) + '[\\/])|(^|\W)' + [regex]::Escape($Addon) + '\W'
		$entries = @($entries | Where-Object { $_.Message -match $pat -or $_.Stack -match $pat -or $_.Taint -match $pat })
	}
	$sessions = @($entries | ForEach-Object Session | Sort-Object -Unique)
	if ($Session -eq -1 -and $sessions.Count) { $Session = $sessions[-1] }
	$shown = if ($Session -gt 0) { @($entries | Where-Object Session -eq $Session) } else { $entries }
	$latest = if ($db -and $db.ContainsKey('session')) { [int]$db['session'] } else { 0 }
	if (-not $shown.Count) {
		Write-Host ('No matching entries' + $(if ($Addon) { " for $Addon" } else { '' }) + '.')
	} else {
		$info = if ($db['sessions'] -and $db['sessions'].ContainsKey([long]$Session)) { $db['sessions'][[long]$Session] } else { $null }
		$when = if ($info) { " started $($info['start']), build $($info['build'])" } else { '' }
		$scope = if ($Session -gt 0) { "session $Session of $latest$when" } else { 'all sessions' }
		Write-Host ''
		Write-Host ("{0} entr{1} in {2}. Summary:" -f $shown.Count, $(if ($shown.Count -eq 1) { 'y' } else { 'ies' }), $scope)
		$shown | Group-Object Kind | ForEach-Object { Write-Host ("  {0,-9} {1} distinct, {2} total" -f $_.Name, $_.Count, ($_.Group | Measure-Object Count -Sum).Sum) }
		Write-Host ''
		foreach ($e in @($shown | Select-Object -Last $Last)[-1..-([Math]::Min($Last, $shown.Count))]) {
			$rep = if ($e.Count -gt 1) { " x$($e.Count) (last $($e.Last))" } else { '' }
			Write-Host ("[{0}] {1}{2}  (session {3})" -f $e.Kind, $e.Time, $rep, $e.Session) -ForegroundColor $(if ($e.Kind -eq 'error') { 'Red' } elseif ($e.Kind -eq 'warning') { 'Yellow' } else { 'Magenta' })
			Write-Host ("    {0}" -f ($e.Message -replace "`n", "`n    "))
			$lines = @($e.Stack -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 8)
			foreach ($l in $lines) { Write-Host "      $l" -ForegroundColor DarkGray }
			if ($e.Taint) {
				Write-Host '    Taint probe (values an addon wrote where the action read):' -ForegroundColor Cyan
				foreach ($l in @($e.Taint -split "`n" | Where-Object { $_.Trim() })) { Write-Host "      $l" -ForegroundColor Cyan }
			}
			Write-Host ''
		}
		if ($sessions.Count -gt 1 -and $Session -gt 0) { Write-Host "Older sessions with entries: $(($sessions | Where-Object { $_ -ne $Session }) -join ', ') (use -Session <n> or -Session 0)." }
	}
}

# ---------------------------------------------------------------------------------------------------------------------
# 2. Anything the client logged itself
# ---------------------------------------------------------------------------------------------------------------------
$logHits = @(Get-ChildItem -LiteralPath (Join-Path $clientDir 'Logs') -Filter '*.log' -ErrorAction SilentlyContinue |
	Select-String -Pattern 'Lua Error' -SimpleMatch -ErrorAction SilentlyContinue)
if ($Addon) { $logHits = @($logHits | Where-Object { $_.Line -match [regex]::Escape($Addon) }) }
if ($logHits.Count) {
	Write-Host "Client logs with 'Lua Error' lines:"
	$logHits | Select-Object -Last 10 | ForEach-Object { Write-Host ("  {0}:{1}  {2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim()) }
}
Write-Host ''
Write-Host 'Next: for "blocked" or "forbidden" entries, start from the taint probe lines; if they name nothing, read the taint log (Get-WowTaintLog.ps1 -Addon <name>). For errors, open the first stack line that is in the addon.'
