<#
.SYNOPSIS
  Paints daves_map's own textures into Media\ (uncompressed 32-bit TGA, 64x64):
    dot.tga   a white disc inside a dark ring: tinted per category, the ring stays dark (the fallback pin)
    ring.tga  a white ring with a soft outer glow: the highlight round hovered and linked pins
#>
$ErrorActionPreference = 'Stop'
$MEDIA_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) 'Media'
New-Item -ItemType Directory -Force -Path $MEDIA_DIR | Out-Null
$SIZE = 64

function Smoothstep([double]$e0, [double]$e1, [double]$v) {
	$t = [Math]::Min(1.0, [Math]::Max(0.0, ($v - $e0) / ($e1 - $e0)))
	return $t * $t * (3.0 - 2.0 * $t)
}
function Write-Tga([string]$path, [scriptblock]$pixel) {
	$bytes = New-Object byte[] (18 + $SIZE * $SIZE * 4)
	$bytes[2] = 2                                         # uncompressed true-colour
	$bytes[12] = $SIZE; $bytes[14] = $SIZE; $bytes[16] = 32; $bytes[17] = 0x28   # 8 alpha bits, top-left origin
	$o = 18
	for ($py = 0; $py -lt $SIZE; $py++) {
		for ($px = 0; $px -lt $SIZE; $px++) {
			$dx = ($px + 0.5) / $SIZE * 2.0 - 1.0; $dy = ($py + 0.5) / $SIZE * 2.0 - 1.0
			$rgba = & $pixel ([Math]::Sqrt($dx * $dx + $dy * $dy))   # distance from the centre, 1 = the edge
			$bytes[$o] = [byte][int]($rgba[2] * 255.0); $bytes[$o + 1] = [byte][int]($rgba[1] * 255.0)
			$bytes[$o + 2] = [byte][int]($rgba[0] * 255.0); $bytes[$o + 3] = [byte][int]($rgba[3] * 255.0)
			$o += 4
		}
	}
	[IO.File]::WriteAllBytes($path, $bytes)
}

# dot: white disc to .70, a dark ring to .92, a clean anti-aliased edge
Write-Tga (Join-Path $MEDIA_DIR 'dot.tga') {
	param($dist)
	$inner = 1.0 - (Smoothstep 0.66 0.72 $dist)
	$edgeA = 1.0 - (Smoothstep 0.88 0.94 $dist)
	$lum = $inner
	@($lum, $lum, $lum, [Math]::Max($inner, 0.9 * $edgeA))
}
# ring: a crisp white band at .74-.86 with a faint glow either side
Write-Tga (Join-Path $MEDIA_DIR 'ring.tga') {
	param($dist)
	$band = (Smoothstep 0.70 0.75 $dist) * (1.0 - (Smoothstep 0.85 0.90 $dist))
	$glow = 0.35 * [Math]::Exp(-[Math]::Pow(($dist - 0.8) / 0.12, 2))
	@(1.0, 1.0, 1.0, [Math]::Min(1.0, $band + $glow))
}
Write-Host "Wrote dot.tga and ring.tga to $MEDIA_DIR"
