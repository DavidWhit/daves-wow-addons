<#
.SYNOPSIS
  Stacks a frame painted in layers into a preview of the frame as the addon would layer it.

.DESCRIPTION
  Finds <variant>-L1, -L2, -L3, -L4 (or -L4-back) and -L4-front (png or jpg, any case) in -Folder.
  With <variant>-L4-front-mask (white = in front, on L4 back's canvas), L4 front is cut out of L4 back instead,
  so the two match pixel for pixel where they meet.
  Layers.cs keys out every guide colour, fits each layer onto the template whatever size it was painted at
  (L1: 3-slice by its end caps, L2: 9-slice by its rim, L3: by its opening, L4: by the guide's orange ring),
  clears what NOTES.md section 8 forbids and reports it, then writes to -Out:
    preview-ring-scale.png  the frame, ring scaled so its opening is 105 (its outside lands where it lands)
    preview-ring-remap.png  the frame, ring band squeezed onto the template's 105..131
    seams-ring-*.png        the preview with every see-through pixel in the frame's body in red (none = stitched)
    fit-sheet.png           every fitted layer with the template drawn over it
    fitted-*.png            each fitted layer, 2400 x 920 with alpha (the layer files of NOTES.md section 8)
  L5 is not stacked yet.

  Run it in a fresh PowerShell process after changing Layers.cs (Add-Type types stay loaded).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Preview-Layers.ps1 -Folder "$HOME\Downloads" -Variant boss
#>
param(
	[Parameter(Mandatory)][string]$Folder,
	[string]$Variant = 'boss',
	[string]$Out = (Join-Path ([IO.Path]::GetTempPath()) 'daves_frames_layers')
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'Layers.cs') -ReferencedAssemblies System.Drawing

$files = Get-ChildItem $Folder -File | Where-Object { $_.Extension -match '^\.(png|jpe?g)$' }
function Layer([string[]]$names) {
	foreach ($n in $names) {
		$f = $files | Where-Object { $_.BaseName -ieq "$Variant-$n" } | Select-Object -First 1
		if ($f) { return $f.FullName }
	}
	return ''
}
$report = [Layers]::Run((Layer 'L1'), (Layer 'L2'), (Layer 'L3'), (Layer 'L4-back', 'L4'), (Layer 'L4-front'), (Layer 'L4-front-mask'), (Resolve-Path $Out).Path)
Write-Host $report
Write-Host "Written to $Out"
