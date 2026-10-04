<#
.SYNOPSIS
  Builds the animated browser preview of the cast bars from the current Media textures and opens it.

.DESCRIPTION
  Regenerates the textures (Make-CastbarMedia.ps1), embeds them as PNG data URIs into
  preview.html and writes the result to -Out. The page animates the bars the way the addon does
  (scrolling layers, particles, vines, glyphs, twinkles), so art can be judged without a client restart.
#>
param(
	[string]$Out = (Join-Path $env:TEMP 'daves_castbar_preview.html'),
	[switch]$NoOpen
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Make-CastbarMedia.ps1') | Out-Null
$media = Resolve-Path (Join-Path $PSScriptRoot '..\Media')
$pairs = foreach ($f in Get-ChildItem -LiteralPath $media -Filter *.tga | Sort-Object Name) {
	'"{0}":"{1}"' -f $f.BaseName, [CastbarArt]::PngDataUri($f.FullName)
}
$html = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'preview.html') -Raw -Encoding UTF8).Replace('/*TEXTURES*/{}', '{' + ($pairs -join ',') + '}').Replace('/*FROSTCUTS*/[]', [CastbarArt]::FrostCutsJson())
[IO.File]::WriteAllText($Out, $html, (New-Object Text.UTF8Encoding $false))
Write-Host "Preview: $Out"
if (-not $NoOpen) { Start-Process $Out }
