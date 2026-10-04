<#
.SYNOPSIS
  Builds a local index of the real WoW API for one client branch from Blizzard's
  own UI source.

.DESCRIPTION
  Source: the Gethe/wow-ui-source git mirror (https://github.com/Gethe/wow-ui-source),
  which tracks the UI source shipped in each client. The "forever" branch is
  WoW: Forever (internal game type "camelot", build 1.60.x, Interface 16001).

  Downloads the branch as one zip and writes data/api-<branch>.json with:
    functions   from Blizzard_APIDocumentationGenerated: "C_Spell.GetSpellInfo" /
                "UnitHealth" -> secret flags (SecretReturns, SecretWhen*)
    events      "UNIT_HEALTH" -> secret payload flag
    namespaces  every documented C_ namespace
    deprecated  globals defined by Blizzard_Deprecated* shims (scheduled for removal)
    globals     every global identifier Blizzard's own Lua calls or defines. Engine and
                FrameXML globals (CreateFrame, PlaySound...) aren't in the generated docs,
                so this is the evidence that a global still exists on the branch.

.EXAMPLE
  .\Update-WowApiIndex.ps1                 # forever branch
  .\Update-WowApiIndex.ps1 -Branch live    # retail (Midnight)
#>
[CmdletBinding()]
param(
	[ValidateSet('forever', 'live', 'ptr', 'classic', 'classic_era', 'classic_anniversary', 'classic_titan', 'beta')]
	[string]$Branch = 'forever',
	[string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$repo = 'Gethe/wow-ui-source'
$headers = @{ 'User-Agent' = 'wow-forever-addons-plugin' }

Write-Host "Resolving branch '$Branch' of $repo..."
$sha = (Invoke-RestMethod "https://api.github.com/repos/$repo/branches/$Branch" -Headers $headers).commit.sha
$zipPath = Join-Path ([IO.Path]::GetTempPath()) "wow-ui-source-$($sha.Substring(0,12)).zip"
if (-not (Test-Path $zipPath)) {
	Write-Host "Downloading $Branch @ $($sha.Substring(0,10)) ..."
	Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri "https://codeload.github.com/$repo/zip/$sha" -OutFile $zipPath
}

$functions = [ordered]@{}
$events = [ordered]@{}
$namespaces = New-Object System.Collections.Generic.SortedSet[string]
$deprecated = [ordered]@{}
$globals = New-Object System.Collections.Generic.HashSet[string]
$docCount = 0; $luaCount = 0

function Read-Entry($entry) {
	$sr = New-Object IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8)
	try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
}

# The generated docs are machine-written with strict tab indentation:
#   1 tab  = system fields (Namespace = "C_X") and section headers (Functions = / Events =)
#   3 tabs = fields of one function/event entry (Name, LiteralName, Secret* flags)
function Add-DocFile([string]$text) {
	$ns = $null; $section = $null; $e = $null
	$flush = {
		if ($null -eq $e) { return }
		if ($section -eq 'Functions' -and $e.Name) {
			$key = if ($ns) { "$ns.$($e.Name)" } else { $e.Name }
			$functions[$key] = @{ secret = @($e.Secret) }
		} elseif ($section -eq 'Events' -and $e.Literal) {
			$events[$e.Literal] = @{ secretPayloads = [bool]$e.SecretPayloads }
		}
	}
	foreach ($line in ($text -split "`r?`n")) {
		if ($line -match '^\tNamespace = "([^"]+)"') { $ns = $Matches[1]; [void]$namespaces.Add($ns); continue }
		if ($line -match '^\t(Functions|Events|Tables|Predicates) =') { & $flush; $e = $null; $section = $Matches[1]; continue }
		if ($line -match '^\t\t\tName = "([^"]+)"') { & $flush; $e = @{ Name = $Matches[1]; Secret = @() }; continue }
		if ($null -eq $e) { continue }
		if ($line -match '^\t\t\tLiteralName = "([^"]+)"') { $e.Literal = $Matches[1] }
		elseif ($line -match '^\t\t\tSecretPayloads = true') { $e.SecretPayloads = $true }
		elseif ($line -match '^\t\t\t(SecretReturns|SecretWhen\w+|SecretInChatMessagingLockdown) = true') { $e.Secret += $Matches[1] }
	}
	& $flush
}

# Global identifiers used as calls (Foo( not preceded by . or :) or defined (function Foo( / Foo = function).
$callRx = [regex]'(?<![\w.:])([A-Za-z_]\w*)\s*\('
$defRx = [regex]'(?m)^\s*(?:function\s+([A-Za-z_]\w*)\s*\(|([A-Za-z_]\w*)\s*=)'
$stripRx = [regex]'--\[(=*)\[[\s\S]*?\]\1\]|--[^\n]*|"(?:\\.|[^"\\\n])*"|''(?:\\.|[^''\\\n])*'''

# Each branch also carries code for the other client family, loaded through [Family]/[Game]
# TOC variables (Forever: [Family] = Mainline, [Game] = Camelot). Code in the other family's
# folders never runs on this branch, so it is not evidence that a global exists here.
$mainlineFamily = $Branch -in 'forever', 'live', 'ptr', 'beta'
$otherFamilyRx = if ($mainlineFamily) { '/(Classic|Vanilla|TBC|Wrath|Cata|Mists)/' } else { '/(Mainline|Camelot|Standard)/' }

$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
	foreach ($entry in $zip.Entries) {
		$p = $entry.FullName
		if ($p -notlike '*.lua') { continue }
		if ($p -like '*/Blizzard_APIDocumentationGenerated/*') { Add-DocFile (Read-Entry $entry); $docCount++; continue }
		if ($p -match $otherFamilyRx -or $p -like '*TransitionGuide*') { continue }
		$text = Read-Entry $entry
		$luaCount++
		$code = $stripRx.Replace($text, ' ')
		foreach ($m in $callRx.Matches($code)) { [void]$globals.Add($m.Groups[1].Value) }
		foreach ($m in $defRx.Matches($code)) {
			$name = $m.Groups[1].Value + $m.Groups[2].Value
			if ($name) { [void]$globals.Add($name) }
		}
		if ($p -match '/Blizzard_Deprecated[^/]*/') {
			$file = Split-Path $p -Leaf
			foreach ($line in ($text -split "`r?`n")) {
				if ($line -match '^\s*function\s+([A-Za-z_]\w*)\s*\(' -or $line -match '^\s*([A-Za-z_]\w*)\s*=\s*(function|C_\w+\.\w+)') {
					if (-not $deprecated.Contains($Matches[1])) { $deprecated[$Matches[1]] = $file }
				}
			}
		}
	}
} finally { $zip.Dispose() }

# Lua keywords and the shims' own definitions don't count as live usage evidence.
foreach ($k in 'if', 'for', 'while', 'function', 'return', 'and', 'or', 'not', 'local', 'elseif', 'until') { [void]$globals.Remove($k) }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$out = Join-Path $OutDir "api-$Branch.json"
$sortedGlobals = New-Object System.Collections.Generic.List[string] (, [string[]]@($globals))
$sortedGlobals.Sort([StringComparer]::Ordinal)
[ordered]@{
	source     = "https://github.com/$repo/tree/$sha"
	branch     = $Branch
	commit     = $sha
	generated  = (Get-Date).ToString('s')
	namespaces = @($namespaces)
	functions  = $functions
	events     = $events
	deprecated = $deprecated
	globals    = $sortedGlobals
} | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $out -Encoding UTF8

$secretCount = @($functions.Values | Where-Object { $_.secret.Count -gt 0 }).Count
Write-Host "Wrote $out  ($docCount doc files, $luaCount Lua files scanned)"
Write-Host ("  {0} functions ({1} can return secret values), {2} events, {3} namespaces, {4} deprecated globals, {5} globals used by Blizzard code" -f `
	$functions.Count, $secretCount, $events.Count, $namespaces.Count, $deprecated.Count, $globals.Count)
