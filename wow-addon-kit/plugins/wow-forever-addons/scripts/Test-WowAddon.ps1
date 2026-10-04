<#
.SYNOPSIS
  Static checks for a WoW addon folder, tuned for WoW: Forever (and other flavors).

.DESCRIPTION
  Checks, each tied to a source:
    TOC     name matches folder, ## Interface present and current, files exist (with exact case),
            lines <= 1024 chars, known directives            [warcraft.wiki.gg/wiki/TOC_format]
    XML     well-formed, <Script file>/<Include file> targets exist
    API     every C_Namespace.Function call exists on the target branch; globals that Blizzard
            moved into a C_ namespace; calls to Blizzard deprecation shims
                                                              [Blizzard_APIDocumentationGenerated,
                                                               Gethe/wow-ui-source, via data/api-*.json]
    Events  RegisterEvent names exist; COMBAT_LOG_EVENT(_UNFILTERED) errors on 12.x / Forever
                                                              [warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes]
    Secrets comparisons/arithmetic/concatenation on values from functions Blizzard marks
            SecretReturns / SecretWhen*                       [same API docs + Patch 12.0.0 notes]
    Lua     luacheck (syntax, accidental globals, unused vars) when installed; slash command wiring;
            SavedVariables actually used
  Exit code 1 when any error is found, so it can gate packaging or CI.

.EXAMPLE
  .\Test-WowAddon.ps1 -Path ..\MyAddon
  .\Test-WowAddon.ps1 -Path ..\MyAddon -Flavor forever,retail -Json
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$Path,
	# forever, retail, mists, titan, anniversary, classic_era (comma-separated or array)
	[string[]]$Flavor = @('forever'),
	[switch]$NoLuacheck,
	[switch]$Json
)

Import-Module (Join-Path $PSScriptRoot 'WowKit.psm1') -Force
$ErrorActionPreference = 'Stop'
$Flavor = Resolve-WowFlavorList $Flavor

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Severity, [string]$Rule, [string]$File, [int]$Line, [string]$Message) {
	$findings.Add([pscustomobject]@{ Severity = $Severity; Rule = $Rule; File = $File; Line = $Line; Message = $Message })
}

if (-not (Test-Path $Path -PathType Container)) { throw "Not a folder: $Path" }
$addonDir = (Resolve-Path $Path).Path
$folder = Split-Path $addonDir -Leaf
function Rel([string]$full) { $full.Substring($addonDir.Length).TrimStart('\') }

$installs = Get-WowInstall
$flavors = Get-WowKnownFlavors
$apiBranches = @($Flavor | ForEach-Object { $flavors[$_].ApiBranch } | Select-Object -Unique)
$api = $null
foreach ($b in $apiBranches) { $api = Get-WowApiIndex $b; if ($api) { $apiBranch = $b; break } }
if (-not $api) {
	Add-Finding info 'api-index' '' 0 "No API index for '$($apiBranches -join ',')'. Run scripts\Update-WowApiIndex.ps1 -Branch $($apiBranches[0]) to enable API/event/secret checks."
}
$modern = @($Flavor | Where-Object { $_ -in 'forever', 'retail' }).Count -gt 0

#---------------------------------------------------------------------------
# TOC files
#---------------------------------------------------------------------------
# Client-specific suffixes from warcraft.wiki.gg/wiki/TOC_format.
$tocSuffixes = 'Standard', 'Mainline', 'Classic', 'Vanilla', 'TBC', 'BCC', 'Wrath', 'WOTLK', 'Cata', 'Mists', 'Camelot', 'Plunderstorm', 'WoWLabs', 'WoWHack'
$knownDirectives = 'Interface', 'Title', 'Notes', 'Author', 'Version', 'SavedVariables', 'SavedVariablesPerCharacter',
	'LoadSavedVariablesFirst', 'Category', 'Group', 'IconTexture', 'IconAtlas', 'AllowLoadGameType', 'ExcludeLoadGameType',
	'LoadOnDemand', 'Dependencies', 'Dependancies', 'RequiredDeps', 'Dep', 'OptionalDeps', 'LoadWith', 'LoadManagers', 'DefaultState',
	'OnlyBetaAndPTR', 'AddonCompartmentFunc', 'AddonCompartmentFuncOnEnter', 'AddonCompartmentFuncOnLeave', 'SavedVariablesMachine',
	'AllowAddOnTableAccess', 'UseSecureEnvironment'

$tocs = @(Get-ChildItem $addonDir -Filter *.toc -File)
$validTocs = @($tocs | Where-Object {
	$b = $_.BaseName
	$b -eq $folder -or ($tocSuffixes | Where-Object { $b -eq "${folder}_$_" -or $b -eq "${folder}-$_" })
})
if ($validTocs.Count -eq 0) {
	Add-Finding error 'toc-name' '' 0 "No TOC named '$folder.toc' (or '${folder}_<Suffix>.toc'). WoW only loads a TOC whose name matches the folder."
}
foreach ($t in ($tocs | Where-Object { $validTocs -notcontains $_ })) {
	Add-Finding warn 'toc-name' $t.Name 0 "TOC name doesn't match folder '$folder'; WoW will ignore it."
}

$loaded = @{}          # full path (lower) -> $true for every file the TOCs / XML pull in
$savedVars = @{}
$tocFlavorCover = @{}  # flavor -> $true when some TOC that flavor reads lists its Interface

function Resolve-Listed([string]$baseDir, [string]$entry) {
	$p = $entry.Trim().Replace('/', '\')
	Join-Path $baseDir $p
}

function Test-ExactCase([string]$full, [string]$file, [int]$lineNo, [string]$listed) {
	# Windows is case-insensitive but macOS clients are not; catch mismatches here.
	$rel = Rel $full
	$cur = $addonDir
	foreach ($part in $rel.Split('\')) {
		$hit = Get-ChildItem -LiteralPath $cur -Force | Where-Object { $_.Name -ieq $part } | Select-Object -First 1
		if (-not $hit) { return }
		if ($hit.Name -cne $part) { Add-Finding warn 'file-case' $file $lineNo "'$listed' differs in case from '$($hit.Name)' on disk (breaks on macOS)."; return }
		$cur = $hit.FullName
	}
}

$xmlQueue = New-Object System.Collections.Generic.Queue[string]

foreach ($t in $validTocs) {
	$suffix = $null
	if ($t.BaseName -ne $folder) { $suffix = $t.BaseName.Substring($folder.Length + 1) }
	$lines = [IO.File]::ReadAllLines($t.FullName)
	$interfaces = @(); $hasTitle = $false; $icon = $null; $hasVersion = $false
	for ($i = 0; $i -lt $lines.Count; $i++) {
		$line = $lines[$i]; $n = $i + 1
		if ($line.Length -gt 1024) { Add-Finding error 'toc-line-length' $t.Name $n 'Line is longer than 1024 characters; WoW reads only the first 1024.' }
		if ($line -match '^\s*##\s*([^:]+?)\s*:\s*(.*)$') {
			$key = $Matches[1]; $val = $Matches[2].Trim()
			$baseKey = ($key -split '-')[0]
			if ($key -match '^X-') { continue }
			if ($baseKey -eq 'Interface') { $interfaces += @($val -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
			elseif ($baseKey -eq 'Title') { $hasTitle = $true }
			elseif ($baseKey -eq 'Version') { $hasVersion = [bool]$val }
			elseif ($baseKey -in 'IconTexture', 'IconAtlas') { $icon = $val }
			elseif ($baseKey -match '^SavedVariables') { foreach ($v in ($val -split ',')) { if ($v.Trim()) { $savedVars[$v.Trim()] = $t.Name } } }
			elseif ($knownDirectives -notcontains $baseKey) { Add-Finding info 'toc-directive' $t.Name $n "Unknown directive '## $key' (custom metadata should start with X-)." }
			continue
		}
		if ($line -match '^\s*#' -or -not $line.Trim()) { continue }
		# Per-line conditions: [AllowLoadGameType a, b] / [ExcludeLoadGameType c] match a game type
		# (camelot, standard, vanilla...) or a family (mainline, classic).
		$allow = $null; $exclude = @()
		if ($line -match '\[AllowLoadGameType\s+([^\]]+)\]') { $allow = @($Matches[1] -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $_.ToLower() }) }
		if ($line -match '\[ExcludeLoadGameType\s+([^\]]+)\]') { $exclude = @($Matches[1] -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $_.ToLower() }) }
		$entry = ($line -replace '\[(AllowLoad\w*|ExcludeLoad\w*|Bootstrap)[^\]]*\]', '').Trim()
		if (-not $entry) { continue }
		if ($entry -match '\[TextLocale\]') { Add-Finding info 'toc-variable' $t.Name $n "Skipped existence check for '$entry' ([TextLocale] varies per client language)."; continue }

		# Check the entry once per target flavor that actually loads it, expanding [Family]/[Game].
		$checked = @{}
		foreach ($fl in $Flavor) {
			$fi = $flavors[$fl]
			$types = @($fi.GameType, $fi.Family.ToLower())
			if ($allow -and -not ($allow | Where-Object { $types -contains $_ })) { continue }
			if ($exclude | Where-Object { $types -contains $_ }) { continue }
			$gameDir = if ($fl -eq 'retail') { 'Standard' } elseif ($fl -eq 'forever') { 'Camelot' } else { $fi.TocSuffix }
			$expanded = $entry.Replace('[Family]', $fi.Family).Replace('[Game]', $gameDir)
			if ($checked.ContainsKey($expanded)) { continue }
			$checked[$expanded] = $true
			$full = Resolve-Listed $addonDir $expanded
			$forWhom = if ($expanded -ne $entry -or $allow -or $exclude) { " (for $fl)" } else { '' }
			if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { Add-Finding error 'toc-missing-file' $t.Name $n "Listed file '$expanded' does not exist$forWhom."; continue }
			Test-ExactCase $full $t.Name $n $expanded
			$loaded[$full.ToLower()] = $true
			$ext = [IO.Path]::GetExtension($full).ToLower()
			if ($ext -eq '.xml') { $xmlQueue.Enqueue($full) }
			elseif ($ext -ne '.lua') { Add-Finding warn 'toc-file-type' $t.Name $n "'$expanded' is not .lua or .xml; WoW only loads those from a TOC." }
		}
	}

	if (-not $hasTitle) { Add-Finding warn 'toc-title' $t.Name 0 'No ## Title; the AddOns list will show the folder name.' }
	if (-not $hasVersion) { Add-Finding warn 'toc-version' $t.Name 0 'No ## Version; the addon cannot report its version on load.' }
	if (-not $icon) { Add-Finding warn 'toc-icon' $t.Name 0 'No ## IconTexture; the AddOns list and minimap addon menu show a blank icon. Pick an icon that fits the addon.' }
	elseif ($icon -match 'INV_Misc_QuestionMark') { Add-Finding warn 'toc-icon' $t.Name 0 "## IconTexture is still the template's question mark; pick an icon that fits the addon." }
	if ($interfaces.Count -eq 0) { Add-Finding error 'toc-interface' $t.Name 0 'Missing ## Interface; the addon will be flagged out of date on every client.'; continue }
	foreach ($iv in $interfaces) { if ($iv -notmatch '^\d{5,6}$') { Add-Finding error 'toc-interface' $t.Name 0 "Interface value '$iv' is not a number like 16001." } }

	# Which flavors read this TOC: a client-specific suffix wins; the plain TOC is the fallback for all.
	foreach ($fl in $Flavor) {
		$want = $flavors[$fl].TocSuffix
		$specific = $validTocs | Where-Object { $_.BaseName -match "[_-]$want$" }
		$reads = if ($suffix) { $suffix -eq $want -or ($fl -eq 'retail' -and $suffix -eq 'Standard') } else { -not $specific }
		if (-not $reads) { continue }
		$target = Get-WowInterfaceFor $fl $installs
		if ($interfaces -contains "$target") { $tocFlavorCover[$fl] = $true }
		else {
			$older = @($interfaces | Where-Object { [math]::Floor([int]$_ / 100) -eq [math]::Floor($target / 100) })
			$msg = if ($older.Count) { "lists $($older -join ',') but the current $fl client is $target" } else { "doesn't list $target ($fl)" }
			Add-Finding warn 'toc-interface' $t.Name 0 "## Interface $msg; WoW will show the addon as out of date."
			$tocFlavorCover[$fl] = $true
		}
	}
}
foreach ($fl in $Flavor) {
	if ($validTocs.Count -and -not $tocFlavorCover.ContainsKey($fl)) {
		Add-Finding warn 'toc-flavor' '' 0 "No TOC is read by the $fl client (add '## Interface: $(Get-WowInterfaceFor $fl $installs)' or a ${folder}_$($flavors[$fl].TocSuffix).toc)."
	}
}

#---------------------------------------------------------------------------
# XML
#---------------------------------------------------------------------------
$seenXml = @{}
while ($xmlQueue.Count) {
	$x = $xmlQueue.Dequeue()
	if ($seenXml.ContainsKey($x.ToLower())) { continue }
	$seenXml[$x.ToLower()] = $true
	$rel = Rel $x
	try { [xml]$doc = Get-Content -LiteralPath $x -Raw } catch { Add-Finding error 'xml-parse' $rel 0 "Not well-formed XML: $($_.Exception.InnerException.Message)"; continue }
	foreach ($node in $doc.SelectNodes("//*[local-name()='Script' or local-name()='Include'][@file]")) {
		$full = Resolve-Listed (Split-Path $x -Parent) $node.file
		if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { Add-Finding error 'xml-missing-file' $rel 0 "<$($node.LocalName) file=`"$($node.file)`"> does not exist."; continue }
		$loaded[$full.ToLower()] = $true
		if ($full -like '*.xml') { $xmlQueue.Enqueue($full) }
	}
}

#---------------------------------------------------------------------------
# Lua
#---------------------------------------------------------------------------
# Folder filters apply to the path inside the addon, so an addon that itself lives under a "tests" folder still works.
$libRx = '^(libs?|Libraries)\\|\\(libs?|Libraries)\\'
$luaFiles = @(Get-ChildItem $addonDir -Recurse -File -Filter *.lua | Where-Object { (Rel $_.FullName) -notmatch '(^|\\)(\.git|\.vscode|tests?|spec)\\' })
foreach ($f in $luaFiles) {
	$isLib = (Rel $f.FullName) -match $libRx
	if (-not $loaded.ContainsKey($f.FullName.ToLower()) -and -not $isLib) { Add-Finding warn 'unloaded-file' (Rel $f.FullName) 0 'Not listed in any TOC or XML, so WoW never loads it.' }
}

# Blanks out comments and string contents so operators/identifiers are matched only in code.
# Returns per-line code text; long brackets ([[...]], --[==[...]==]) are handled across lines.
function Get-CodeLines([string]$text) {
	$sb = New-Object System.Text.StringBuilder $text.Length
	$i = 0; $len = $text.Length
	while ($i -lt $len) {
		$c = $text[$i]
		if ($c -eq '-' -and $i + 1 -lt $len -and $text[$i + 1] -eq '-') {
			$m = [regex]::Match($text.Substring($i + 2, [math]::Min(64, $len - $i - 2)), '^\[(=*)\[')
			if ($m.Success) {
				$close = ']' + $m.Groups[1].Value + ']'
				$end = $text.IndexOf($close, $i + 2 + $m.Length); if ($end -lt 0) { $end = $len - $close.Length }
				$chunk = $text.Substring($i, $end + $close.Length - $i)
				[void]$sb.Append(($chunk -replace '[^\n]', ' ')); $i = $end + $close.Length; continue
			}
			while ($i -lt $len -and $text[$i] -ne "`n") { [void]$sb.Append(' '); $i++ }
			continue
		}
		if ($c -eq '[') {
			$m = [regex]::Match($text.Substring($i, [math]::Min(64, $len - $i)), '^\[(=*)\[')
			if ($m.Success) {
				$close = ']' + $m.Groups[1].Value + ']'
				$end = $text.IndexOf($close, $i + $m.Length); if ($end -lt 0) { $end = $len - $close.Length }
				$inner = $text.Substring($i + $m.Length, $end - $i - $m.Length)
				[void]$sb.Append('""'); [void]$sb.Append(($inner -replace '[^\n]', ''))
				$i = $end + $close.Length; continue
			}
		}
		if ($c -eq '"' -or $c -eq "'") {
			$q = $c; [void]$sb.Append($q); $i++
			while ($i -lt $len -and $text[$i] -ne $q -and $text[$i] -ne "`n") { if ($text[$i] -eq '\') { $i++ }; $i++ }
			[void]$sb.Append($q); $i++; continue
		}
		[void]$sb.Append($c); $i++
	}
	return $sb.ToString() -split "`n"
}

# Names the addon (or its embedded libraries) defines itself, so calls to them aren't "unknown".
$addonDefined = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($f in $luaFiles) {
	$t = [IO.File]::ReadAllText($f.FullName)
	foreach ($m in [regex]::Matches($t, '\bfunction\s+([A-Za-z_]\w*)\s*\(|(?<![\w.:])([A-Za-z_]\w*)\s*=(?!=)')) { [void]$addonDefined.Add($m.Groups[1].Value + $m.Groups[2].Value) }
}
# Replacements whose names differ from the removed global (each verified in the forever API index).
$renamedApi = @{
	UnitAura   = 'C_UnitAuras.GetAuraDataByIndex(unit, index, filter)'
	UnitBuff   = 'C_UnitAuras.GetBuffDataByIndex(unit, index, filter)'
	UnitDebuff = 'C_UnitAuras.GetDebuffDataByIndex(unit, index, filter)'
}
$hasDeps = @($validTocs | Where-Object { (Get-Content $_.FullName -Raw) -match '(?m)^##\s*(Dependencies|RequiredDeps|OptionalDeps|Dep)\s*:' }).Count -gt 0

$allLuaText = New-Object System.Text.StringBuilder
$slashDefs = @{}; $slashHandlers = @{}
$usesAddonMsg = $null; $usesLockdownCheck = $false
$secretOps = '(==|~=|<=|>=|(?<![-=])[<>](?!=)|(?<![-\w])[+*/%^](?!=)|\.\.)'

foreach ($f in $luaFiles) {
	$rel = Rel $f.FullName
	if ($rel -match $libRx) { continue }   # don't lint embedded libraries
	$raw = [IO.File]::ReadAllText($f.FullName)
	[void]$allLuaText.AppendLine($raw)
	$rawLines = $raw -split "`n"
	$code = Get-CodeLines $raw
	$fileText = ($code -join "`n")
	$guardsSecrets = $raw -match '\b(issecretvalue|canaccessvalue|issecrettable|hasanysecretvalues)\b'
	$localNames = @{}
	foreach ($m in [regex]::Matches($fileText, '\blocal\s+(?:function\s+)?([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_][\w]*)*)')) {
		foreach ($nm in ($m.Groups[1].Value -split '\s*,\s*')) { $localNames[$nm] = $true }
	}

	for ($i = 0; $i -lt $code.Count; $i++) {
		$c = $code[$i]; $r = $rawLines[$i]; $n = $i + 1
		if (-not $c.Trim()) { continue }

		# Events (the name lives in a string literal, so read the raw line)
		foreach ($m in [regex]::Matches($r, ':Register(?:Unit)?Event\s*\(\s*["'']([A-Z0-9_]+)["'']')) {
			$ev = $m.Groups[1].Value
			if ($modern -and $ev -match '^COMBAT_LOG_EVENT(_UNFILTERED)?$') {
				Add-Finding error 'cleu-removed' $rel $n "$ev errors when registered on Midnight (12.x) and WoW: Forever. Combat-log parsing isn't available to addons there (Patch 12.0.0 API changes)."
			} elseif ($api -and -not $api.Events.ContainsKey($ev)) {
				Add-Finding error 'unknown-event' $rel $n "Event '$ev' does not exist on $apiBranch (RegisterEvent will error)."
			} elseif ($api -and $api.Events[$ev]) {
				Add-Finding info 'secret-payload' $rel $n "Event '$ev' can deliver secret values in its payload; don't compare or do math on them."
			}
		}

		if ($api) {
			# C_Namespace.Function calls
			foreach ($m in [regex]::Matches($c, '(?<![\w.:])(C_\w+)\.(\w+)')) {
				$ns = $m.Groups[1].Value; $fn = "$ns.$($m.Groups[2].Value)"
				$guarded = $c -match ("\b$ns\s+and\s+$([regex]::Escape($fn))") -or $c -match ("\b$([regex]::Escape($fn))\s+(and|or)\b") -or $c -match ("\bor\s+$([regex]::Escape($fn))")
				if (-not $api.Namespaces.ContainsKey($ns)) {
					$sev = 'error'; if ($guarded) { $sev = 'info' }
					Add-Finding $sev 'unknown-namespace' $rel $n "$ns does not exist on $apiBranch$(if ($guarded) { ' (feature-detected, OK)' })."
				} elseif (-not $api.Functions.ContainsKey($fn)) {
					$sev = 'warn'; if ($guarded) { $sev = 'info' }
					Add-Finding $sev 'unknown-function' $rel $n "$fn is not in Blizzard's API documentation for $apiBranch$(if ($guarded) { ' (feature-detected, OK)' } else { '; it will be nil if it does not exist' })."
				} else {
					$sec = $api.Functions[$fn]
					if ($sec.Count -and $modern) {
						$after = $c.Substring($m.Index)
						if ($after -match $secretOps -or $c.Substring(0, $m.Index) -match '(==|~=|<=|>=|[<>]|\.\.)\s*$') {
							$sev = 'warn'; if ($guardsSecrets) { $sev = 'info' }
							Add-Finding $sev 'secret-value' $rel $n "$fn can return secret values ($($sec -join ', ')); comparing, doing math or concatenating them errors in restricted contexts. Pass them straight to widget setters or check issecretvalue() first."
						}
					}
				}
			}

			# Global calls: moved into C_ namespaces, deprecation shims, secret returns
			foreach ($m in [regex]::Matches($c, '(?<![\w.:])([A-Z][A-Za-z0-9_]+)\s*\(')) {
				$g = $m.Groups[1].Value
				if ($localNames.ContainsKey($g)) { continue }
				if ($c -match "function\s+$g\s*\(") { continue }
				# Feature detection anywhere in the file (if Foo then / elseif Foo / X or Foo) makes the call safe.
				$fallback = $c -match "\bor\s+$g\b" -or $c -match "\b$g\s+or\b" -or
					$fileText -match "\b(if|elseif|and|or|not)\s+$g\b(?!\s*\()" -or $fileText -match "\b$g\s+(and|then)\b"
				if ($api.Deprecated.ContainsKey($g)) {
					Add-Finding warn 'deprecated-api' $rel $n "$g is only provided by Blizzard's deprecation shim ($($api.Deprecated[$g])) and is scheduled for removal."
				} elseif (-not $api.Functions.ContainsKey($g) -and -not $api.Globals.Contains($g) -and $api.ByShort.ContainsKey($g)) {
					# Two pieces of evidence: not a documented global, and Blizzard's own code never calls or defines it.
					$sev = 'warn'; if ($fallback) { $sev = 'info' }
					$alts = @($api.ByShort[$g] | Select-Object -First 3 | ForEach-Object { "$_()" }) -join ' / '
					Add-Finding $sev 'moved-api' $rel $n "Global $g() doesn't exist on $apiBranch; use $alts$(if ($fallback) { ' (fallback present, OK)' })."
				} elseif (-not $api.Functions.ContainsKey($g) -and -not $api.Globals.Contains($g) -and -not $addonDefined.Contains($g)) {
					# Not documented, never called or defined by Blizzard's code on this branch, not defined by the addon.
					$sev = 'warn'; if ($fallback) { $sev = 'info' }
					$hint = if ($renamedApi.ContainsKey($g)) { " Use $($renamedApi[$g])." } elseif ($hasDeps) { ' (Unless a dependency provides it.)' } else { '' }
					Add-Finding $sev 'unknown-global' $rel $n "Global $g() is not part of the $apiBranch client (not in Blizzard's API docs or UI code); it will be nil.$hint$(if ($fallback) { ' Feature-detected, OK.' })"
				} elseif ($modern -and $api.Functions.ContainsKey($g) -and $api.Functions[$g].Count) {
					$after = $c.Substring($m.Index)
					$close = $after.IndexOf(')')
					$tail = if ($close -ge 0) { $after.Substring($close + 1) } else { '' }
					if ($tail -match "^\s*$secretOps" -or $c.Substring(0, $m.Index) -match '(==|~=|<=|>=|[<>]|[+\-*/]|\.\.)\s*$') {
						$sev = 'warn'; if ($guardsSecrets) { $sev = 'info' }
						Add-Finding $sev 'secret-value' $rel $n "$g() can return a secret value ($($api.Functions[$g] -join ', ')); comparing, doing math or concatenating it errors in restricted contexts. Pass it straight to a widget setter (StatusBar:SetValue, FontString:SetText) or check issecretvalue() first."
					}
				}
			}
		}

		# Slash commands
		foreach ($m in [regex]::Matches($c, '\bSLASH_([A-Za-z0-9_]+?)\d+\s*=')) { if (-not $slashDefs.ContainsKey($m.Groups[1].Value)) { $slashDefs[$m.Groups[1].Value] = "$rel`:$n" } }
		foreach ($m in [regex]::Matches($r, 'SlashCmdList\s*(?:\[\s*["'']([A-Za-z0-9_]+)["'']\s*\]|\.([A-Za-z0-9_]+))\s*=')) { $slashHandlers[($m.Groups[1].Value + $m.Groups[2].Value)] = $true }

		if ($c -match '\bSendAddonMessage(Logged)?\s*\(' -and -not $usesAddonMsg) { $usesAddonMsg = "$rel`:$n" }
		if ($c -match 'InChatMessagingLockdown') { $usesLockdownCheck = $true }
	}
}

foreach ($k in $slashDefs.Keys) {
	if (-not $slashHandlers.ContainsKey($k)) {
		$file, $line = $slashDefs[$k] -split ':(?=\d+$)'
		Add-Finding error 'slash-handler' $file ([int]$line) "SLASH_$k`1 is defined but SlashCmdList[`"$k`"] is never assigned; the command won't work."
	}
}
if ($usesAddonMsg -and $modern -and -not $usesLockdownCheck) {
	$file, $line = $usesAddonMsg -split ':(?=\d+$)'
	Add-Finding info 'addon-comms' $file ([int]$line) 'Addon messages are restricted in instances on 12.x/Forever; check C_ChatInfo.InChatMessagingLockdown() before sending.'
}
$luaAll = $allLuaText.ToString()
# Every addon announces its version on load (PLAYER_LOGIN also fires on /reload).
if ($luaAll.Length -and -not ($luaAll -match 'GetAddOnMetadata' -and $luaAll -match '"Version"')) {
	Add-Finding warn 'load-version' '' 0 'The addon never reads its ## Version. Print it on PLAYER_LOGIN (see the template Core.lua) so every /reload shows which version is running.'
}
foreach ($sv in $savedVars.Keys) {
	if ($luaAll -notmatch "\b$([regex]::Escape($sv))\b") { Add-Finding warn 'savedvariables-unused' $savedVars[$sv] 0 "SavedVariables '$sv' is declared but never referenced in Lua." }
}

#---------------------------------------------------------------------------
# luacheck (syntax errors, accidental globals, unused/shadowed locals)
#---------------------------------------------------------------------------
$luacheck = $null
if (-not $NoLuacheck) { $luacheck = Find-Luacheck }
if ($luacheck) {
	$cfg = Join-Path $addonDir '.luacheckrc'
	if (-not (Test-Path $cfg)) { $cfg = Join-Path (Get-WowKitRoot) 'templates\addon\.luacheckrc' }
	$targets = @($luaFiles | Where-Object { (Rel $_.FullName) -notmatch $libRx } | ForEach-Object FullName)
	if ($targets.Count) {
		# SavedVariables declared in the TOC are intentional globals.
		$lcArgs = @('--formatter', 'plain', '--codes', '--no-color', '--config', $cfg) + $targets
		if ($savedVars.Count) { $lcArgs += @('--globals') + @($savedVars.Keys) }
		$out = & $luacheck @lcArgs 2>$null
		foreach ($l in $out) {
			if ($l -match '^(.*?):(\d+):(\d+):\s*\((\w)(\d+)\)\s*(.*)$') {
				$sev = if ($Matches[4] -eq 'E') { 'error' } else { 'warn' }
				Add-Finding $sev "luacheck-$($Matches[4])$($Matches[5])" (Rel $Matches[1]) ([int]$Matches[2]) $Matches[6]
			}
		}
	}
} elseif (-not $NoLuacheck) {
	Add-Finding info 'luacheck' '' 0 'luacheck not found: syntax and accidental-global checks skipped. Run scripts\Install-WowDevTools.ps1.'
}

#---------------------------------------------------------------------------
# Report
#---------------------------------------------------------------------------
$order = @{ error = 0; warn = 1; info = 2 }
$sorted = @($findings | Sort-Object { $order[$_.Severity] }, File, Line)
$errors = @($sorted | Where-Object Severity -eq 'error').Count
$warns = @($sorted | Where-Object Severity -eq 'warn').Count

if ($Json) {
	[pscustomobject]@{ Addon = $folder; Flavors = $Flavor; ApiCommit = $(if ($api) { $api.Commit } else { $null }); Errors = $errors; Warnings = $warns; Findings = $sorted } | ConvertTo-Json -Depth 4
} else {
	Write-Host "Checking $folder for $($Flavor -join ', ')$(if ($api) { " (API: $apiBranch @ $($api.Commit.Substring(0,10)))" })"
	$colors = @{ error = 'Red'; warn = 'Yellow'; info = 'DarkGray' }
	foreach ($f in $sorted) {
		$loc = if ($f.File) { if ($f.Line) { "$($f.File):$($f.Line)" } else { $f.File } } else { $folder }
		Write-Host ("  {0,-5} {1}  [{2}] {3}" -f $f.Severity.ToUpper(), $loc, $f.Rule, $f.Message) -ForegroundColor $colors[$f.Severity]
	}
	$color = if ($errors) { 'Red' } elseif ($warns) { 'Yellow' } else { 'Green' }
	Write-Host "$errors error(s), $warns warning(s), $(@($sorted).Count - $errors - $warns) note(s)" -ForegroundColor $color
}
if ($errors) { exit 1 } else { exit 0 }
