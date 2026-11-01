<#
.SYNOPSIS
  Keeps a local copy of Blizzard's UI source for one client branch, plus an
  index of where every function, mixin method and XML template is defined.

.DESCRIPTION
  Source: the Gethe/wow-ui-source git mirror (https://github.com/Gethe/wow-ui-source).
  The "forever" branch is WoW: Forever (game type "camelot", Interface 16001).

  Writes data/ui-source/<branch>/:
    Interface/...   every .lua, .xml and .toc file from the branch
    SOURCE.txt      branch, commit and download date
    INDEX.tsv       name <tab> kind <tab> path:line, one row per definition:
                      function  global function           (function ContainerFrameItemButton_OnClick)
                      method    mixin/table method        (function ItemLocationMixin:IsValid)
                      template  virtual XML template      (<ItemButton name="ContainerFrameItemButtonTemplate" virtual="true">)
                      frame     named XML frame           (<Frame name="MerchantFrame">)

  The copy is large and reproducible, so it is git-ignored. Re-run after each patch.

.EXAMPLE
  .\Update-WowUiSource.ps1                 # forever branch
  .\Update-WowUiSource.ps1 -Branch live    # retail (Midnight)
#>
[CmdletBinding()]
param(
	[ValidateSet('forever', 'live', 'ptr', 'classic', 'classic_era', 'classic_anniversary', 'classic_titan', 'beta')]
	[string]$Branch = 'forever',
	[string]$OutDir
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 leaves $PSScriptRoot empty inside param() defaults.
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'data\ui-source' }
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

$dest = Join-Path $OutDir $Branch
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force $dest | Out-Null

$funcRx = [regex]'^\s*function\s+([A-Za-z_][\w.]*)([:.])?(\w+)?\s*\('
$xmlRx = [regex]'<(\w+)\s[^>]*?\bname="([^"$]+)"[^>]*>'
$rows = New-Object System.Collections.Generic.List[string]
$count = 0

$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
	foreach ($entry in $zip.Entries) {
		$full = $entry.FullName
		$i = $full.IndexOf('/Interface/')
		if ($i -lt 0 -or $full.EndsWith('/')) { continue }
		$ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
		if ($ext -notin '.lua', '.xml', '.toc') { continue }
		$rel = $full.Substring($i + 1)                     # Interface/AddOns/...
		$target = Join-Path $dest ($rel -replace '/', '\')
		New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
		[IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
		$count++
		if ($ext -eq '.toc') { continue }

		$lines = [IO.File]::ReadAllLines($target)
		for ($n = 0; $n -lt $lines.Length; $n++) {
			$line = $lines[$n]
			if ($ext -eq '.lua') {
				$m = $funcRx.Match($line)
				if (-not $m.Success) { continue }
				if ($m.Groups[3].Success) { $name = $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value; $kind = 'method' }
				elseif ($m.Groups[1].Value.Contains('.')) { $name = $m.Groups[1].Value; $kind = 'method' }
				else { $name = $m.Groups[1].Value; $kind = 'function' }
				$rows.Add("$name`t$kind`t${rel}:$($n + 1)")
			} else {
				foreach ($m in $xmlRx.Matches($line)) {
					$kind = if ($m.Value -match '\bvirtual="true"') { 'template' } else { 'frame' }
					$rows.Add("$($m.Groups[2].Value)`t$kind`t${rel}:$($n + 1)")
				}
			}
		}
	}
} finally { $zip.Dispose() }

$rows.Sort([StringComparer]::OrdinalIgnoreCase)
[IO.File]::WriteAllLines((Join-Path $dest 'INDEX.tsv'), (@("name`tkind`tlocation") + $rows), (New-Object Text.UTF8Encoding($false)))
@(
	"repo:     https://github.com/$repo"
	"branch:   $Branch"
	"commit:   $sha"
	"fetched:  $((Get-Date).ToString('yyyy-MM-dd'))"
	"files:    $count (.lua .xml .toc under Interface/)"
	"index:    $($rows.Count) definitions in INDEX.tsv"
) | Set-Content -Encoding utf8 (Join-Path $dest 'SOURCE.txt')

Write-Host "Wrote $count files and $($rows.Count) index rows to $dest"
