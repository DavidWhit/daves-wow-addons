param([string]$Out)
# Writes 32-bit uncompressed TGA files (bottom-left origin) for the orb art.
New-Item -ItemType Directory -Force $Out | Out-Null
$S = 256

function Write-Tga($path, [scriptblock]$pixel) {
	$hdr = [byte[]](0,0,2, 0,0,0,0,0, 0,0,0,0, ($S -band 255),($S -shr 8),($S -band 255),($S -shr 8), 32, 8)
	$px = New-Object byte[] ($S*$S*4)
	$c = ($S-1)/2.0
	for ($y=0; $y -lt $S; $y++) { for ($x=0; $x -lt $S; $x++) {
		$u = ($x-$c)/$c; $v = ($y-$c)/$c          # -1..1, v up
		$cr,$cg,$cb,$ca = & $pixel $u $v
		$i = ($y*$S+$x)*4
		$px[$i]  =[byte][math]::Max(0,[math]::Min(255,[int]($cb*255)))
		$px[$i+1]=[byte][math]::Max(0,[math]::Min(255,[int]($cg*255)))
		$px[$i+2]=[byte][math]::Max(0,[math]::Min(255,[int]($cr*255)))
		$px[$i+3]=[byte][math]::Max(0,[math]::Min(255,[int]($ca*255)))
	} }
	[IO.File]::WriteAllBytes($path, $hdr + $px)
}
function Clamp01($t){ [math]::Max(0.0,[math]::Min(1.0,$t)) }
function Smooth($e0,$e1,$t){ $k = Clamp01 (($t-$e0)/($e1-$e0)); $k*$k*(3-2*$k) }
function Ell($u,$v,$cx,$cy,$rx,$ry){ $a=($u-$cx)/$rx; $b=($v-$cy)/$ry; [math]::Sqrt($a*$a+$b*$b) }

$ORB_R = 0.80   # orb radius (not $R: PowerShell names ignore case and Write-Tga uses $r) as a fraction of half the texture

# Mask: solid circle, soft 1-2px edge.
Write-Tga "$Out\OrbMask.tga" { param($u,$v) $d=[math]::Sqrt($u*$u+$v*$v); 1,1,1,(1 - (Smooth ($ORB_R-0.01) ($ORB_R+0.01) $d)) }

# Background: dark smoky glass for the empty part.
Write-Tga "$Out\OrbBack.tga" { param($u,$v) $d=[math]::Sqrt($u*$u+$v*$v); 0.05,0.05,0.07,(0.85*(1 - (Smooth ($ORB_R-0.01) ($ORB_R+0.01) $d))) }

# Shade: darker toward the rim for depth. Fully covers the mask edge so no bare liquid shows there.
Write-Tga "$Out\OrbShade.tga" { param($u,$v)
	$d=[math]::Sqrt($u*$u+$v*$v)
	$inside = 1 - (Smooth ($ORB_R+0.012) ($ORB_R+0.025) $d)
	$bottom = Clamp01 ((-$v/$ORB_R + 0.2)/1.2)   # deeper toward the bottom
	0,0,0,((Clamp01 (0.02 + 0.22*(Smooth (0.6*$ORB_R) $ORB_R $d) + 0.15*$bottom))*$inside) }

# Glass: clear sphere. A faint soft rim (no hard border), curved window-like reflection
# streaks on the left, and soft light bouncing up from the bottom right.
Write-Tga "$Out\OrbGlass.tga" { param($u,$v)
	$d=[math]::Sqrt($u*$u+$v*$v)
	$inside = 1 - (Smooth ($ORB_R-0.005) ($ORB_R+0.005) $d)
	$rim = [math]::Pow((Smooth (0.82*$ORB_R) $ORB_R $d),2) * 0.22 * $inside
	$bounce = (1 - (Smooth 0.2 1.0 (Ell $u $v 0.18 -0.52 0.42 0.16))) * 0.22 * $inside
	# reflection streaks: thin arcs concentric with the glass, on the left between ~120 and ~215 degrees
	$ang = [math]::Atan2($v,$u) * 180 / [math]::PI; if ($ang -lt 0) { $ang += 360 }
	$along = (Smooth 118 140 $ang) * (1 - (Smooth 195 218 $ang))
	$arcs = 0
	foreach ($ar in @(@(0.93,0.010,0.55), @(0.88,0.006,0.35), @(0.84,0.004,0.25))) {
		$arcs += [math]::Exp(-[math]::Pow(($d/$ORB_R - $ar[0])/$ar[1],2)) * $ar[2]
	}
	$light = Clamp01 ($rim + $bounce + $arcs*$along*$inside)
	if ($light -le 0) { return 0,0,0,0 }
	0.92,0.96,1,$light }
# Inner shine: a subtle soft glint about a third of the radius across, a third of the radius
# in from the crescent (same direction, so it turns with the glare).
function Shine($u,$v){
	$cy = $ORB_R*0.975 - $ORB_R/3
	$e = Ell $u $v 0 $cy ($ORB_R/6) ($ORB_R/10)
	0.35*[math]::Exp(-2.2*$e*$e)
}

# Gloss: crescent highlight hugging the inside of the rim, centred straight up (90 degrees) so
# the game can rotate it toward the cursor (additive). Thickest in the middle, tapering to points.
Write-Tga "$Out\OrbGloss.tga" { param($u,$v)
	$d=[math]::Sqrt($u*$u+$v*$v)
	$phi = [math]::Atan2($u, $v) * 180 / [math]::PI      # 0 = straight up
	$span = 90                                  # half the perimeter
	if ([math]::Abs($phi) -ge $span) { return 1,1,1,(Shine $u $v) }
	$taper = [math]::Cos($phi/$span*[math]::PI/2)
	$outer = $ORB_R*0.975
	$thick = $ORB_R*0.04*$taper
	$mid = $outer - $thick/2
	# solid, fully opaque band with a hot centre line, plus a faint soft bloom around it
	$band = (Smooth ($outer-$thick-0.006) ($outer-$thick+0.003) $d) * (1 - (Smooth ($outer-0.004) ($outer+0.003) $d))
	$bloom = [math]::Exp(-[math]::Pow(($d-$mid)/0.035,2)) * 0.3
	1,1,1,(Clamp01 (($band + $bloom)*[math]::Pow($taper,0.35) + (Shine $u $v))) }
# Liquid noise: sums of sine waves with whole-number frequencies tile seamlessly; a second
# set of waves warps the first so the pattern looks organic rather than regular.
# $k (a whole number) scales the frequencies for finer octaves; tiling still holds.
# Used with REPEAT wrapping and scrolled by texture coordinates in game.
function Flow($u,$v,$seed,$k=1){
	$x = ($u+1)/2*2*[math]::PI*$k; $y = ($v+1)/2*2*[math]::PI*$k
	$wx = 0.9*[math]::Sin(2*$y + 1.7*$seed) + 0.5*[math]::Sin(3*$x - 5*$y + $seed)
	$wy = 0.9*[math]::Sin(2*$x + 0.6 + $seed) + 0.5*[math]::Sin(4*$x + 3*$y + 2*$seed)
	$px = $x + $wx; $py = $y + $wy
	$n  = 0.50*[math]::Sin(2*$px + 3*$py + $seed)
	$n += 0.35*[math]::Sin(-3*$px + 2*$py + 2.1*$seed)
	$n += 0.25*[math]::Sin(5*$px - 1*$py + 0.4)
	$n += 0.15*[math]::Sin(1*$px + 6*$py + 3.3*$seed)
	$n / 1.25
}
function Ridge($n,$width,$power){ [math]::Pow(1 - [math]::Min(1.0,[math]::Abs($n)/$width), $power) }

# Veins: branching electric filaments, sharp ridges at three scales (additive, tinted in game).
Write-Tga "$Out\OrbVeins.tga" { param($u,$v)
	$a1 = Ridge (Flow $u $v 1.0 1) 0.08 2           # long main filaments
	$a2 = Ridge (Flow $u $v 3.7 2) 0.05 2          # thinner side branches
	$hot = $a1*$a1                                  # whiter centre line on the main veins
	$a = Clamp01 ($a1*0.95 + $a2*0.35)
	$w = Clamp01 (0.55 + 0.45*$hot)
	$w,$w,$w,$a }

# Nebula: soft bright wisps (additive, tinted in game).
Write-Tga "$Out\OrbCloud.tga" { param($u,$v)
	$n = Flow $u $v 2.3
	$m = Flow $u $v 4.1 2
	1,1,1,(Clamp01 ((Smooth -0.1 0.9 $n)*0.55 + (Smooth 0.2 1.0 $m)*0.25)) }

# Core: soft radial glow for the bright heart of the orb (additive, pulsed in game).
Write-Tga "$Out\OrbCore.tga" { param($u,$v)
	$d=[math]::Sqrt($u*$u+$v*$v)
	$ang = [math]::Atan2($v,$u)
	$rays = [math]::Pow([math]::Abs([math]::Sin(3.5*$ang + 0.4)), 12) + 0.6*[math]::Pow([math]::Abs([math]::Sin(5*$ang + 1.3)), 16)
	1,1,1,(Clamp01 ([math]::Exp(-[math]::Pow($d/0.10,2)) + 0.5*[math]::Exp(-[math]::Pow($d/0.40,2)) + 0.45*$rays*[math]::Exp(-$d/0.28))) }

# Halo: soft glow just outside the glass (additive, tinted in game).
Write-Tga "$Out\OrbHalo.tga" { param($u,$v)
	$d=[math]::Sqrt($u*$u+$v*$v)
	$out = Smooth ($ORB_R-0.02) ($ORB_R+0.01) $d
	1,1,1,($out*[math]::Exp(-[math]::Pow(($d-$ORB_R)/0.07,2))*0.6) }

# Sparks: tiny scattered points of light that tile (additive). Drawn dot by dot.
& {
	$rng = New-Object System.Random 7
	$img = New-Object 'double[]' ($S*$S)
	for ($i = 0; $i -lt 160; $i++) {
		$cx = $rng.NextDouble()*$S; $cy = $rng.NextDouble()*$S
		$rad = 0.6 + 1.4*[math]::Pow($rng.NextDouble(), 3)
		$bright = 0.4 + 0.6*$rng.NextDouble()
		$reach = [int][math]::Ceiling($rad*2.5)
		$fx = [math]::Floor($cx); $fy = [math]::Floor($cy)
		for ($dy = -$reach; $dy -le $reach; $dy++) { for ($dx = -$reach; $dx -le $reach; $dx++) {
			$px = (([int]$fx + $dx) % $S + $S) % $S
			$py = (([int]$fy + $dy) % $S + $S) % $S
			$ex = $fx + $dx + 0.5 - $cx; $ey = $fy + $dy + 0.5 - $cy
			$val = $bright*[math]::Exp(-($ex*$ex + $ey*$ey)/($rad*$rad))
			$j = $py*$S + $px
			if ($val -gt $img[$j]) { $img[$j] = $val }
		} }
	}
	$hdr = [byte[]](0,0,2, 0,0,0,0,0, 0,0,0,0, ($S -band 255),($S -shr 8),($S -band 255),($S -shr 8), 32, 8)
	$bytes = New-Object byte[] ($S*$S*4)
	for ($j = 0; $j -lt $S*$S; $j++) { $bytes[$j*4]=255; $bytes[$j*4+1]=255; $bytes[$j*4+2]=255; $bytes[$j*4+3]=[byte][math]::Min(255.0, $img[$j]*255) }
	[IO.File]::WriteAllBytes("$Out\OrbSparks.tga", $hdr + $bytes)
}
# Wave: foam line on the liquid surface. Two sine periods across the width and periodic
# at the edges, so it tiles horizontally (scrolled by texture coordinates in game).
Write-Tga "$Out\OrbWave.tga" { param($u,$v)
	$x = ($u+1)/2
	$edge = 0.15*[math]::Sin($x*4*[math]::PI) + 0.04*[math]::Sin($x*8*[math]::PI + 0.7)
	$dy = $v - $edge
	$foam = [math]::Exp(-[math]::Pow($dy/0.05,2))
	1,1,1,($foam*0.9) }

# Liquid level: a half-plane mask (opaque below the middle, clear above, soft 2px edge).
# Anchored at the liquid level and rotated in game so the whole liquid body tilts.
Write-Tga "$Out\OrbLevel.tga" { param($u,$v) 1,1,1,(1 - (Smooth -0.008 0.008 $v)) }











