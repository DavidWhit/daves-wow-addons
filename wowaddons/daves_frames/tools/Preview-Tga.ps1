<#
.SYNOPSIS
  Converts a daves_frames TGA (uncompressed 32-bit) to a PNG over a dark background, for checking art
  without starting the game. -Zoom enlarges small textures (chain, stripes) with crisp pixels.
#>
param([Parameter(Mandatory)][string]$Tga, [Parameter(Mandatory)][string]$Png, [int]$Zoom = 1)
Add-Type -AssemblyName System.Drawing
$b = [IO.File]::ReadAllBytes($Tga)
$w = $b[12] + 256 * $b[13]; $h = $b[14] + 256 * $b[15]
$topDown = ($b[17] -band 0x20) -ne 0
$bmp = New-Object Drawing.Bitmap $w, $h, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$d = $bmp.LockBits((New-Object Drawing.Rectangle 0, 0, $w, $h), 'WriteOnly', $bmp.PixelFormat)
for ($y = 0; $y -lt $h; $y++) {
	$row = if ($topDown) { $y } else { $h - 1 - $y }
	[Runtime.InteropServices.Marshal]::Copy($b, 18 + $row * $w * 4, [IntPtr]($d.Scan0.ToInt64() + $y * $d.Stride), $w * 4)
}
$bmp.UnlockBits($d)
$out = New-Object Drawing.Bitmap ($w * $Zoom), ($h * $Zoom)
$g = [Drawing.Graphics]::FromImage($out)
$g.Clear([Drawing.Color]::FromArgb(36, 48, 56))
$g.InterpolationMode = 'NearestNeighbor'; $g.PixelOffsetMode = 'Half'
$g.DrawImage($bmp, 0, 0, $w * $Zoom, $h * $Zoom)
$g.Dispose(); $out.Save($Png, [Drawing.Imaging.ImageFormat]::Png); $out.Dispose(); $bmp.Dispose()
"$Tga -> $Png ($w x $h)"
