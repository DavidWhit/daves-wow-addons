param([string]$Media, [string]$Out, [double[]]$Color = @(0.10,0.25,0.95), [double]$Level = 0.65, [double]$TiltDeg = 0)
# Rough software composite of the orb layers (same order and tints as Orbs.lua), to eyeball
# the art outside the game. Additive layers are approximated by adding tinted colour.
Add-Type -AssemblyName System.Drawing
$S = 256
$L = @{}
foreach ($n in 'OrbBack','OrbMask','OrbShade','OrbGloss','OrbGlass','OrbWave','OrbCloud','OrbVeins','OrbSparks','OrbCore','OrbHalo') {
	$L[$n] = [IO.File]::ReadAllBytes("$Media\$n.tga")
}
function Px($n, $x, $y) {  # texture pixel (wrapping), bottom-left origin -> r,g,b,a in 0..1
	$b = $L[$n]; $x = (([int]$x % $S) + $S) % $S; $y = (([int]$y % $S) + $S) % $S
	$i = 18 + ($y*$S + $x)*4
	($b[$i+2]/255.0), ($b[$i+1]/255.0), ($b[$i]/255.0), ($b[$i+3]/255.0)
}
# Same colour derivation as Orbs.lua
$deep = @(($Color[0]*0.35), ($Color[1]*0.35), ($Color[2]*0.35))   # parens: "," binds tighter than "*"
$glow = @(($Color[0] + (1-$Color[0])*0.35), ($Color[1] + (1-$Color[1])*0.35), ($Color[2] + (1-$Color[2])*0.35))
$gold = @(1.0, 0.72, 0.30)

$bmp = New-Object Drawing.Bitmap $S, $S
$levelY = [int]((0.1 + 0.8*$Level) * $S)
for ($y=0; $y -lt $S; $y++) { for ($x=0; $x -lt $S; $x++) {
	$r=0.12;$g=0.12;$bl=0.12
	function Over($c,$a){ $script:r=$script:r*(1-$a)+$c[0]*$a; $script:g=$script:g*(1-$a)+$c[1]*$a; $script:bl=$script:bl*(1-$a)+$c[2]*$a }
	function Add($c,$a){ $script:r+=$c[0]*$a; $script:g+=$c[1]*$a; $script:bl+=$c[2]*$a }
	$p = Px 'OrbHalo' $x $y; Add $glow $p[3]
	$p = Px 'OrbBack' $x $y; Over $p $p[3]
	$m = (Px 'OrbMask' $x $y)[3]
	$surf = $levelY + [math]::Tan($TiltDeg*[math]::PI/180)*($x-128)
	if ($y -lt $surf -and $m -gt 0) {
		Over $deep $m
		$c = Px 'OrbCloud' ($x*0.8+40) ($y*0.8+70); Add $glow ($c[3]*0.45*$m)
		$c = Px 'OrbVeins' ($x*0.55) ($y*0.55); Add $glow ($c[3]*0.9*$m)
		$c = Px 'OrbVeins' ($x*0.45+100) ($y*0.45+30); Add $gold ($c[3]*0.7*$m)
		$c = Px 'OrbSparks' $x $y; Add @(1,1,1) ($c[3]*0.8*$m)
		$c = Px 'OrbCore' $x $y; Add $gold ($c[3]*0.8*$m)
	}
	$dy = $y - $surf
	if ([math]::Abs($dy) -lt 18) { $w = Px 'OrbWave' ($x*0.75 + 30) (128 + $dy*256/36); Add $glow ($w[3]*0.6*$m) }
	$p = Px 'OrbShade' $x $y; Over $p $p[3]
	$p = Px 'OrbGloss' $x $y; Add $p ($p[3]*0.8)
	$p = Px 'OrbGlass' $x $y; Add $p $p[3]
	$f = { param($v) [int][math]::Round([math]::Max(0.0,[math]::Min(1.0,$v))*255.0) }
	$bmp.SetPixel($x, $S-1-$y, [Drawing.Color]::FromArgb((& $f $r),(& $f $g),(& $f $bl)))
} }
$bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png)

