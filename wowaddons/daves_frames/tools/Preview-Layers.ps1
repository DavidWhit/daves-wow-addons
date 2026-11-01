<#
.SYNOPSIS
  Stop. The paint mask is tools\template\guides\frame-template.png.

.DESCRIPTION
  This used to stack the old layer guides. It now refuses. Paint onto
  guides\frame-template.png. See tools\template\PAINT-LAYERS.md.
#>
$ErrorActionPreference = 'Stop'
Write-Host "The paint mask is tools\template\guides\frame-template.png."
Write-Host "Redraw it with: py -3 tools\Build-FrameTemplate.py"
Write-Host "This script stacked the old layer guides. It does not run."
exit 1
