param([string]$Out)
# Paint guides for the five frame layers, on the shared template (see FRAME-STANDARD.md).
# Template is 1200 x 460 layout px; guides are drawn at 2x (2400 x 920), the size art is delivered at.
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Out | Out-Null
$K = 2
$W = 1200 * $K; $H = 460 * $K

$MAGENTA = [Drawing.Color]::FromArgb(255, 0, 255)
$GREY    = [Drawing.Color]::FromArgb(128, 128, 128)
$LGREY   = [Drawing.Color]::FromArgb(176, 176, 176)
$BLUE    = [Drawing.Color]::FromArgb(0, 0, 255)
$GREEN   = [Drawing.Color]::FromArgb(0, 255, 0)
$YELLOW  = [Drawing.Color]::FromArgb(255, 255, 0)
$CYAN    = [Drawing.Color]::FromArgb(0, 255, 255)
$ORANGE  = [Drawing.Color]::FromArgb(255, 140, 0)

# Template geometry (layout px).
$T = @{
	ringX = 600; ringY = 230; rIn = 105; rOut = 131
	plate = @(8, 153, 1192, 289, 14)            # L1 outer border: x1 y1 x2 y2 radius
	capL = @(0, 138, 64, 304); capR = @(1136, 138, 1200, 304)   # end-cap allowance
	inner = @(34, 175, 1166, 267, 10)           # L2 inner border outer edge
	win = @(50, 191, 1150, 251, 5)              # bar windows (transparent)
	keep = @(44, 185, 1156, 257)                # window keep-out for ornaments (window + 6)
	ornTop = @(300, 0, 900, 153)                # ornament zone above the plate
	ornBelow = @(430, 289, 770, 460)            # ornament zone below the plate (ring column only)
	badgeY = 354; badgeR = 40; badgeIn = 32         # L5 level badge: Blizzard's level circle size, on the ring's bottom (ringY + 124)
}
function S($v) { [float]($v * $K) }
function Brush($c) { New-Object Drawing.SolidBrush $c }
function RR($a) {
	$x1 = S $a[0]; $y1 = S $a[1]; $x2 = S $a[2]; $y2 = S $a[3]; $d = 2 * (S $a[4])
	$p = New-Object Drawing.Drawing2D.GraphicsPath
	if ($d -le 0) { $p.AddRectangle((New-Object Drawing.RectangleF $x1, $y1, ($x2 - $x1), ($y2 - $y1))); return $p }
	$p.AddArc($x1, $y1, $d, $d, 180, 90); $p.AddArc($x2 - $d, $y1, $d, $d, 270, 90)
	$p.AddArc($x2 - $d, $y2 - $d, $d, $d, 0, 90); $p.AddArc($x1, $y2 - $d, $d, $d, 90, 90); $p.CloseFigure(); $p
}
function Rect($g, $c, $a) { $g.FillRectangle((Brush $c), (S $a[0]), (S $a[1]), (S ($a[2] - $a[0])), (S ($a[3] - $a[1]))) }
function Circle($g, $c, $r) { $g.FillEllipse((Brush $c), (S ($T.ringX - $r)), (S ($T.ringY - $r)), (S (2 * $r)), (S (2 * $r))) }
function Canvas { $b = New-Object Drawing.Bitmap $W, $H; $g = [Drawing.Graphics]::FromImage($b); $g.SmoothingMode = 'AntiAlias'; $g.Clear($MAGENTA); return $b, $g }
function Save($b, $g, $name) { $g.Dispose(); $b.Save((Join-Path $Out $name), [Drawing.Imaging.ImageFormat]::Png); $b.Dispose() }
function Outline($g, $c, $path) { $pen = New-Object Drawing.Pen $c, 3; $pen.DashStyle = 'Dash'; $g.DrawPath($pen, $path) }
function OutlineCircle($g, $c, $r) { $pen = New-Object Drawing.Pen $c, 3; $pen.DashStyle = 'Dash'; $g.DrawEllipse($pen, (S ($T.ringX - $r)), (S ($T.ringY - $r)), (S (2 * $r)), (S (2 * $r))) }

# L1 outer border: GREY = paint the decorative border here; MAGENTA inside = leave empty (L2 sits there).
$b, $g = Canvas
$g.FillPath((Brush $GREY), (RR $T.plate))
Rect $g $GREY $T.capL; Rect $g $GREY $T.capR
$g.FillPath((Brush $MAGENTA), (RR $T.inner))
Save $b $g 'L1-outer-border-guide.png'

# L2 inner border: GREY = paint the container rim; BLUE window = stays perfectly flat blue (cut out later).
$b, $g = Canvas
$g.FillPath((Brush $GREY), (RR $T.inner))
$g.FillPath((Brush $BLUE), (RR $T.win))
Outline $g $CYAN (RR $T.plate)
Save $b $g 'L2-inner-border-guide.png'

# L3 portrait ring: LIGHT GREY = paint the ring; BLUE = portrait opening, flat blue.
$b, $g = Canvas
Circle $g $LGREY $T.rOut
Circle $g $BLUE $T.rIn
Outline $g $CYAN (RR $T.plate); Outline $g $CYAN (RR $T.win)
Save $b $g 'L3-ring-guide.png'

# L4 ornament, back and front. GREEN = ornament may be painted; YELLOW = never (bars and their margin);
# ORANGE = the ring (L3 always covers the ornament here, so anything painted is hidden); MAGENTA = empty.
foreach ($side in 'back', 'front') {
	$b, $g = Canvas
	Rect $g $GREEN $T.ornTop
	Rect $g $GREEN $T.ornBelow
	if ($side -eq 'back') { $g.FillPath((Brush $GREEN), (RR $T.plate)) }   # behind the plate: may run under the whole plate
	else { $g.FillPath((Brush $GREEN), (RR @(300, 153, 900, 289, 0))) }      # over the plate: only around the ring
	Rect $g $YELLOW $T.keep
	Circle $g $ORANGE $T.rOut
	Circle $g $BLUE $T.rIn
	Outline $g $CYAN (RR $T.plate)
	Save $b $g "L4-ornament-$side-guide.png"
}

# L5 level badge: LIGHT GREY = paint the badge; BLUE = where the level number sits, flat blue.
# It sits on the bottom of the ring, in front of the ring and everything else (only the text is over it).
$b, $g = Canvas
$g.FillEllipse((Brush $LGREY), (S ($T.ringX - $T.badgeR)), (S ($T.badgeY - $T.badgeR)), (S (2 * $T.badgeR)), (S (2 * $T.badgeR)))
$g.FillEllipse((Brush $BLUE), (S ($T.ringX - $T.badgeIn)), (S ($T.badgeY - $T.badgeIn)), (S (2 * $T.badgeIn)), (S (2 * $T.badgeIn)))
OutlineCircle $g $CYAN $T.rOut; OutlineCircle $g $CYAN $T.rIn; Outline $g $CYAN (RR $T.plate)
Save $b $g 'L5-level-badge-guide.png'

# Stack preview: every layer in its own colour, drawn in game order, for checking fit.
$b, $g = Canvas
$g.Clear([Drawing.Color]::FromArgb(30, 40, 46))
$g.FillPath((Brush ([Drawing.Color]::FromArgb(150, 60, 160, 90))), (RR @(300, 0, 900, 289, 0)))          # L4 back
$g.FillPath((Brush ([Drawing.Color]::FromArgb(255, 120, 96, 60))), (RR $T.plate))                       # L1
Rect $g ([Drawing.Color]::FromArgb(255, 120, 96, 60)) $T.capL; Rect $g ([Drawing.Color]::FromArgb(255, 120, 96, 60)) $T.capR
$g.FillPath((Brush ([Drawing.Color]::FromArgb(255, 190, 150, 80))), (RR $T.inner))                      # L2
$g.FillPath((Brush ([Drawing.Color]::FromArgb(255, 200, 40, 30))), (RR @(50, 191, 600, 251, 5)))         # health
$g.FillPath((Brush ([Drawing.Color]::FromArgb(255, 40, 100, 220))), (RR @(600, 191, 1150, 251, 5)))      # resource
Rect $g ([Drawing.Color]::FromArgb(150, 60, 160, 90)) @(430, 289, 770, 420)                              # L4 front (tail)
Circle $g ([Drawing.Color]::FromArgb(255, 60, 70, 80)) $T.rIn                                             # portrait
$pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 240, 200, 110)), (S 26)
$g.DrawEllipse($pen, (S ($T.ringX - 118)), (S ($T.ringY - 118)), (S 236), (S 236))                        # L3
$g.FillEllipse((Brush ([Drawing.Color]::FromArgb(255, 250, 215, 120))), (S ($T.ringX - $T.badgeR)), (S ($T.badgeY - $T.badgeR)), (S (2 * $T.badgeR)), (S (2 * $T.badgeR)))   # L5
$g.FillEllipse((Brush ([Drawing.Color]::FromArgb(255, 20, 16, 10))), (S ($T.ringX - $T.badgeIn)), (S ($T.badgeY - $T.badgeIn)), (S (2 * $T.badgeIn)), (S (2 * $T.badgeIn)))
$font = New-Object Drawing.Font 'Segoe UI', 26, ([Drawing.FontStyle]::Bold)
$w = Brush ([Drawing.Color]::White)
$g.DrawString('L4 back (behind everything)', $font, $w, (S 320), (S 20))
$g.DrawString('L1 outer border', $font, $w, (S 20), (S 310))
$g.DrawString('L2 inner border (rim around both bars)', $font, $w, (S 820), (S 296))
$g.DrawString('health bar', $font, $w, (S 200), (S 210))
$g.DrawString('resource bar', $font, $w, (S 880), (S 210))
$g.DrawString('L3 ring', $font, (Brush ([Drawing.Color]::Black)), (S 560), (S 104))
$g.DrawString('L4 front (over L1/L2, under L3)', $font, $w, (S 440), (S 425))
$g.DrawString('L5 level badge', $font, $w, (S 640), (S 372))
Save $b $g 'L0-stack-preview.png'

Get-ChildItem $Out *.png | Select-Object Name, Length | Format-Table -AutoSize
