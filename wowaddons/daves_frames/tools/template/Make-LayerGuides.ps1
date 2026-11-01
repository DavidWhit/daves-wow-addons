<#
.SYNOPSIS
  Stop. The paint mask is tools\Build-FrameTemplate.py.

.DESCRIPTION
  This used to draw the old layer crops. It now refuses. Redraw the mask with
  tools\Build-FrameTemplate.py.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\template\Make-LayerGuides.ps1
#>
param([string]$Out)
$ErrorActionPreference = 'Stop'
Write-Host "The paint mask is tools\template\guides\frame-template.png."
Write-Host "Redraw it with: py -3 tools\Build-FrameTemplate.py"
Write-Host "This script drew the old layer crops. It does not run."
exit 1
