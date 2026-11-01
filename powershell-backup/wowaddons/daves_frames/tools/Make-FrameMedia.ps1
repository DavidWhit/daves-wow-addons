<#
.SYNOPSIS
  Builds daves_frames' textures in Media\ from a frame painting (uncompressed 32-bit TGA, power of two).

.DESCRIPTION
  For a painting on the magenta/blue key (see NOTES.md and tools\template\PAINT-LAYERS.md):
    1. Key.cs cuts out the magenta background and the blue portrait opening, at full size (2x layout).
    2. Mask.cs cuts the bar windows out with smooth edges and a 5 px rounded end, keeping the whole ring.
    3. FrameMedia.cs packs the art (scaled to 2048 wide) and the board strip into frame-<variant>.tga
       (2048 x 1024), and writes chain-<variant>.tga and stripes.tga.
  It prints the atlas numbers that Layout.lua needs for the variant.

  Run it in a fresh PowerShell process after changing any .cs file (Add-Type types stay loaded).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Make-FrameMedia.ps1 -Source "$HOME\Downloads\TargetFrameGuides\render\gold-elite.jpg" -Variant gold
#>
param(
	[Parameter(Mandatory)][string]$Source,
	[string]$Variant = 'gold'
)
$ErrorActionPreference = 'Stop'
$TOOLS = $PSScriptRoot
$MEDIA = Join-Path (Split-Path $TOOLS -Parent) 'Media'
$WORK = Join-Path ([IO.Path]::GetTempPath()) 'daves_frames_media'
New-Item -ItemType Directory -Force $MEDIA, $WORK | Out-Null
Add-Type -AssemblyName System.Drawing
foreach ($cs in 'Key.cs', 'Mask.cs', 'FrameMedia.cs') { Add-Type -Path (Join-Path $TOOLS $cs) -ReferencedAssemblies System.Drawing }

# Geometry per variant, in layout px (1x), as measured from the painting. Must match Layout.lua.
# New paintings made on the template (tools\template) use the template numbers instead.
$GEO = @{
	gold = @{ cx = 595.8; cy = 227.8; rOut = 131; cutL = 49; cutR = 1146; cutT = 189; cutB = 249; bandT = 140; bandB = 300
	          metal = @(@(246, 220, 148), @(168, 122, 44), @(74, 50, 12)) }
}
$g = $GEO[$Variant]
if (-not $g) { throw "No geometry for variant '$Variant'. Add it to `$GEO (and to Layout.lua)." }
$K = 2; $RADIUS = 5

$full = Join-Path $WORK "$Variant-full@2x.png"
$art = Join-Path $WORK "$Variant-art@2x.png"
$geoJson = [Key]::Run($Source, $full, 1.0)
Write-Host "Keyed: $geoJson"
[Mask]::Cut($full, $art, $g.cutL * $K, $g.cutT * $K, $g.cutR * $K, $g.cutB * $K, $RADIUS * $K, $g.cx * $K, $g.cy * $K, ($g.rOut + 1) * $K)

$atlas = [FrameMedia]::Atlas($art, $full, (Join-Path $MEDIA "frame-$Variant.tga"), $g.bandT * $K, $g.bandB * $K)
$m = $g.metal
[FrameMedia]::Chain((Join-Path $MEDIA "chain-$Variant.tga"), $m[0][0], $m[0][1], $m[0][2], $m[1][0], $m[1][1], $m[1][2], $m[2][0], $m[2][1], $m[2][2])
[FrameMedia]::Stripes((Join-Path $MEDIA 'stripes.tga'))

$artH, $stripY, $stripW, $stripH = $atlas -split ' '
Write-Host ""
Write-Host "Atlas for Layout.lua (variant '$Variant', texture 2048 x 1024):"
Write-Host ("  art:   0..2048 x 0..{0}   -> texcoords 0, 1, 0, {1:0.######}" -f $artH, ($artH / 1024))
Write-Host ("  strip: 0..{0} x {1}..{2} -> texcoords 0, {3:0.######}, {4:0.######}, {5:0.######}" -f $stripW, $stripY, ([int]$stripY + [int]$stripH), ($stripW / 2048), ($stripY / 1024), (([int]$stripY + [int]$stripH) / 1024))
Get-ChildItem $MEDIA | Select-Object Name, Length | Format-Table -AutoSize
