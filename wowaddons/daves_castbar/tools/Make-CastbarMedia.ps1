<#
.SYNOPSIS
  Generates daves_castbar's art: tiling elemental bar layers, particles, spark and glow.

.DESCRIPTION
  Everything is procedural (periodic noise, Voronoi cells, simple shapes), so the layers tile
  seamlessly and the bar can scroll them forever. Writes 32-bit uncompressed TGA files into
  ..\Media. With -Preview <png> it also renders a still of every bar (70% filled) to check
  the art before restarting the game.

  The generator is C# (compiled once by Add-Type) because per-pixel PowerShell is far too slow.

.EXAMPLE
  & .\tools\Make-CastbarMedia.ps1 -Preview "$env:TEMP\castbar.png"
#>
param(
	[string]$Out = (Join-Path $PSScriptRoot '..\Media'),
	[string]$Preview
)
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;

public static class CastbarArt
{
	// ---------------------------------------------------------------- image buffer (top-down RGBA, 0..1)
	public class Img
	{
		public int W, H; public double[] R, G, B, A;
		public Img(int w, int h) { W = w; H = h; R = new double[w*h]; G = new double[w*h]; B = new double[w*h]; A = new double[w*h]; }
		public void Set(int x, int y, double r, double g, double b, double a)
		{ int i = y*W + x; R[i] = r; G[i] = g; B[i] = b; A[i] = a; }
	}

	public static void WriteTga(Img img, string path)
	{
		byte[] hdr = new byte[18];
		hdr[2] = 2; hdr[12] = (byte)(img.W & 255); hdr[13] = (byte)(img.W >> 8);
		hdr[14] = (byte)(img.H & 255); hdr[15] = (byte)(img.H >> 8); hdr[16] = 32; hdr[17] = 8; // bottom-left origin, 8 alpha bits
		byte[] px = new byte[img.W*img.H*4];
		for (int y = 0; y < img.H; y++)
		for (int x = 0; x < img.W; x++)
		{
			int s = y*img.W + x, d = ((img.H-1-y)*img.W + x)*4;
			px[d] = B8(img.B[s]); px[d+1] = B8(img.G[s]); px[d+2] = B8(img.R[s]); px[d+3] = B8(img.A[s]);
		}
		using (var f = File.Create(path)) { f.Write(hdr, 0, 18); f.Write(px, 0, px.Length); }
	}
	static byte B8(double v) { int i = (int)Math.Round(v*255); return (byte)(i < 0 ? 0 : i > 255 ? 255 : i); }

	// ---------------------------------------------------------------- math helpers
	static double Clamp(double v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
	static double Lerp(double a, double b, double t) { return a + (b-a)*t; }
	static double Smooth(double e0, double e1, double x) { double t = Clamp((x-e0)/(e1-e0)); return t*t*(3-2*t); }
	static double Fade(double t) { return t*t*t*(t*(t*6-15)+10); }
	static int Mod(int a, int m) { int r = a % m; return r < 0 ? r + m : r; }
	static double Frac(double v) { return v - Math.Floor(v); }

	static double Hash(int x, int y, int seed)
	{
		unchecked
		{
			uint h = (uint)(x*374761393 + y*668265263 + seed*1442695041);
			h = (h ^ (h >> 13)) * 1274126177u; h ^= h >> 16;
			return (h & 0xffffff) / 16777216.0;
		}
	}

	// Gradient noise on a lattice that wraps every px by py cells, so it tiles. Range about -1..1.
	static double Noise(double x, double y, int px, int py, int seed)
	{
		int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y);
		double fx = x - x0, fy = y - y0;
		int X0 = Mod(x0, px), X1 = Mod(x0+1, px), Y0 = Mod(y0, py), Y1 = Mod(y0+1, py);
		double u = Fade(fx), v = Fade(fy);
		double n00 = Grad(X0, Y0, fx, fy, seed), n10 = Grad(X1, Y0, fx-1, fy, seed);
		double n01 = Grad(X0, Y1, fx, fy-1, seed), n11 = Grad(X1, Y1, fx-1, fy-1, seed);
		return Lerp(Lerp(n00, n10, u), Lerp(n01, n11, u), v) * 1.5;
	}
	static double Grad(int ix, int iy, double dx, double dy, int seed)
	{ double a = Hash(ix, iy, seed) * Math.PI * 2; return Math.Cos(a)*dx + Math.Sin(a)*dy; }

	// Fractal noise over texture coordinates u,v in [0,1); bx,by = cells across at the base octave.
	static double Fbm(double u, double v, int bx, int by, int oct, int seed)
	{
		double s = 0, a = 0.5, norm = 0; int fx = bx, fy = by;
		for (int i = 0; i < oct; i++) { s += a*Noise(u*fx, v*fy, fx, fy, seed + i*31); norm += a; a *= 0.5; fx *= 2; fy *= 2; }
		return s / norm;
	}

	// Periodic Voronoi: distance (in cells) to the nearest and second-nearest feature point, plus the
	// nearest cell's id. Cells are gx by gy across the texture.
	static void Voronoi(double u, double v, int gx, int gy, int seed, out double f1, out double f2, out int cell)
	{
		double x = u*gx, y = v*gy; int cx = (int)Math.Floor(x), cy = (int)Math.Floor(y);
		f1 = 9; f2 = 9; cell = 0;
		for (int j = -1; j <= 1; j++)
		for (int i = -1; i <= 1; i++)
		{
			int nx = cx+i, ny = cy+j, wx = Mod(nx, gx), wy = Mod(ny, gy);
			double fx = nx + 0.15 + 0.7*Hash(wx, wy, seed), fy = ny + 0.15 + 0.7*Hash(wx, wy, seed+7);
			double d = Math.Sqrt((fx-x)*(fx-x) + (fy-y)*(fy-y));
			if (d < f1) { f2 = f1; f1 = d; cell = wy*gx + wx; } else if (d < f2) f2 = d;
		}
	}

	// Horizontal distance in pixels on a texture that wraps left-right.
	static double WrapDx(double x, double cx, int w) { double d = x - cx; d -= Math.Round(d / w) * w; return d; }

	static double[] Ramp(double t, double[][] stops)
	{
		t = Clamp(t);
		for (int i = 1; i < stops.Length; i++)
			if (t <= stops[i][0])
			{
				double k = (t - stops[i-1][0]) / Math.Max(1e-6, stops[i][0] - stops[i-1][0]);
				return new double[] { Lerp(stops[i-1][1], stops[i][1], k), Lerp(stops[i-1][2], stops[i][2], k), Lerp(stops[i-1][3], stops[i][3], k) };
			}
		var l = stops[stops.Length-1]; return new double[] { l[1], l[2], l[3] };
	}
	static double[] S(double t, double r, double g, double b) { return new double[] { t, r, g, b }; }

	// Bar layers are 512x64: 8 square cells across per cell down keeps noise round, not stretched.
	const int W = 512, H = 64;

	// ================================================================ FROST: diamond-cut ice, new every cast
	// The facets are built live from layers. frost_ice is the plain ice (deep blue, frost feathers, lit
	// top rim). Each frost_cutN pair holds one straight zigzag cut running edge to edge: a brighter tone on
	// one side, a deeper one on the other, and a bevelled line on the cut. Stacked, every facet's
	// tone is the sum of the sides it falls on, so neighbouring facets always differ. The addon gives
	// each layer a random offset, stretch, mirror and weight per cast (a new ice bar every time), drifts
	// the weights during the cast (the light moves), and traces two of the cuts.
	static readonly double[][] CUTS = {
		//          centre  amp    period(px) phase
		new double[]{ 0.50,  0.50,  512,      0.00 },
		new double[]{ 0.50,  0.50,  256,      0.25 },
		new double[]{ 0.50,  0.50,  512.0/3,  0.10 },
		new double[]{ 0.50, -0.50,  512,      0.37 },
		new double[]{ 0.50,  0.07,  256,      0.10 },   // a shallow girdle through the middle
	};
	static double Tri(double x, double p, double ph) { return 1 - 2*Math.Abs(Frac(x/p + ph)*2 - 1); }
	static double CutDist(int i, double x, double y)   // signed pixel distance, positive below the cut
	{
		var c = CUTS[i];
		double ly = (c[0] + c[1]*Tri(x, c[2], c[3])) * H;
		double slope = 4*Math.Abs(c[1])*H / c[2];
		return (y - ly) / Math.Sqrt(1 + slope*slope);
	}

	// Cut geometry for the addon (and the preview) to trace: [[x,y],...] per cut in texture pixels,
	// from the first corner at or after x = 0 to that corner + W.
	public static string FrostCutsJson()
	{
		var parts = new List<string>();
		foreach (var c in CUTS)
		{
			var xs = new List<double>();
			for (int m = -4; m < 4 * W / (int)c[2] + 8; m++)
			{
				double x = (m * 0.5 - c[3]) * c[2];
				if (x >= 0 && x < W) xs.Add(x);
			}
			xs.Sort(); xs.Add(xs[0] + W);
			var v = new List<string>();
			foreach (var x in xs)
				v.Add(string.Format(System.Globalization.CultureInfo.InvariantCulture, "[{0:0.##},{1:0.##}]", x, (c[0] + c[1]*Tri(x, c[2], c[3])) * H));
			parts.Add("[" + string.Join(",", v) + "]");
		}
		return "[" + string.Join(",", parts) + "]";
	}

	public static Img FrostIce()
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double n = Fbm(u, v, 8, 1, 4, 221) * 0.10;
			double shade = 0.50 + n - (v - 0.5)*0.22;
			double fern = Math.Pow(Clamp(1 - Math.Abs(Fbm(u, v, 16, 2, 4, 204))), 10) * 0.13
				+ Math.Pow(Clamp(1 - Math.Abs(Fbm(u, v, 48, 6, 3, 205))), 16) * 0.08;   // a second, finer frost
			double grain = (Hash(x, y, 206) - 0.5) * 0.06 + (Hash(x, y, 207) > 0.993 ? 0.35 : 0);   // fine noise and glints
			double rim = Math.Exp(-y/1.6) * 0.45 + Math.Exp(-(H-1-y)/1.6) * 0.25 - Math.Exp(-(H-1-y)/4.0) * 0.12;
			double r = .05 + .30*shade, g = .20 + .44*shade, b = .42 + .50*shade, w = fern + rim + grain;
			img.Set(x, y, r + w*.80, g + w*.92, b + w, 0.94);
		}
		return img;
	}
	// Each cut comes as two layers so the ice keeps its colour:
	//   frost_cutN_hi (ADD): brightens the lit side, strongest along the bevel, plus the bright cut line
	//   frost_cutN_lo (BLEND): a deep navy wash over the shadow side, darkest along the bevel; clear elsewhere
	//   (alpha, not multiply, so the addon can fade it: WoW's MOD blend ignores alpha)
	public static Img FrostCut(int i, bool hi)
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double d = CutDist(i, x, y), ad = Math.Abs(d);
			bool lit = d < 0;                                                    // above the cut faces the light
			double bevel = Math.Exp(-ad/2.0), line = Math.Exp(-ad*ad/0.25);
			if (hi)
			{
				double k = lit ? 1 + 2.2*bevel : 0;
				img.Set(x, y, .09*k + line*.70, .15*k + line*.85, .21*k + line*1.0, 1);
			}
			else if (lit || line > 0.3) img.Set(x, y, 0, 0, 0, 0);
			else img.Set(x, y, .02, .07, .22, 0.40 + 0.25*bevel);
		}
		return img;
	}

	// ================================================================ FIRE
	public static Img FireBase()
	{
		var img = new Img(W, H);
		var ramp = new double[][] { S(0, .05,.01,0), S(.3, .42,.05,.01), S(.55, .85,.25,.02), S(.78, 1,.58,.10), S(1, 1,.92,.55) };
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double q = Fbm(u, v, 8, 1, 4, 31);
			double n = Fbm(u + 0.06*q, v + 0.4*q, 20, 2, 5, 32);
			double t = 0.42 + 0.5*n + (v - 0.45)*0.75;               // hotter toward the bottom
			var col = Ramp(t, ramp);
			img.Set(x, y, col[0], col[1], col[2], 1);
		}
		return img;
	}
	public static Img FireFlow()    // flame tongues; tiles both ways so it can scroll upward
	{
		var img = new Img(W, H);
		var ramp = new double[][] { S(0, 0,0,0), S(.35, .35,.06,0), S(.6, .95,.40,.04), S(.85, 1,.75,.25), S(1, 1,.97,.75) };
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double q = Fbm(u, v, 16, 2, 3, 41);
			double n = Fbm(u + 0.03*q, v + 0.25*q, 32, 2, 5, 42);
			double tongue = Math.Pow(Clamp(n*0.9 + 0.5), 2.6);
			var col = Ramp(tongue, ramp);
			img.Set(x, y, col[0], col[1], col[2], 1);
		}
		return img;
	}

	// ================================================================ NATURE
	public static Img NatureBase()  // dense foliage over moss; the vines are drawn live by the addon
	{
		var img = new Img(W, H);
		var greens = new double[][] { new double[]{.16,.34,.10}, new double[]{.26,.46,.13}, new double[]{.11,.26,.11}, new double[]{.34,.52,.16}, new double[]{.20,.40,.18}, new double[]{.40,.42,.12} };
		const int CELL = 12, GX = W / CELL, GY = H / CELL + 1;
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double m = Fbm(u, v, 32, 4, 4, 71);
			double r = .06 + .05*m, g = .14 + .08*m, b = .04 + .03*m;
			// leaves: three per cell, random size and angle; the highest-ranked leaf covering the pixel wins
			double best = -1; double lr = 0, lg = 0, lb = 0;
			int cx = x / CELL, cy = y / CELL;
			for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++)
			for (int k = 0; k < 3; k++)
			{
				int gx = Mod(cx+i, GX), gy = cy+j; if (gy < -1 || gy > GY) continue;
				int id = (gy+2)*1000 + gx*3 + k;
				double px = (cx+i + Hash(id,0,72))*CELL, py = (gy + Hash(id,1,72))*CELL;
				double len = 9 + 9*Hash(id,2,72), wid = len*(0.28 + 0.14*Hash(id,3,72)), ang = Hash(id,4,72)*Math.PI*2;
				double dx = x - px, dy = y - py;
				double ca = Math.Cos(ang), sa = Math.Sin(ang);
				double lx = (dx*ca + dy*sa)/len, ly = (-dx*sa + dy*ca)/len;   // along / across, leaf from lx 0..1
				if (lx < 0 || lx > 1) continue;
				double half = (wid/len) * Math.Sin(Math.PI*Math.Pow(lx, 0.8));
				if (Math.Abs(ly) > half) continue;
				double rank = Hash(id,5,72);
				if (rank <= best) continue;
				best = rank;
				var gc = greens[(int)(Hash(id,6,72)*greens.Length) % greens.Length];
				double side = ly > 0 ? 1.0 : 0.82;                                // one half catches more light
				double vein = 1 - 0.35*Math.Exp(-ly*ly*len*len/0.6);
				double tip = 0.75 + 0.35*lx;
				double edge = Smooth(half, half*0.75, Math.Abs(ly));
				double depth = 0.55 + 0.45*rank;                                   // leaves underneath are darker
				lr = Lerp(r, gc[0]*side*vein*tip*depth, edge); lg = Lerp(g, gc[1]*side*vein*tip*depth, edge); lb = Lerp(b, gc[2]*side*vein*tip*depth, edge);
			}
			if (best >= 0) { r = lr; g = lg; b = lb; }
			img.Set(x, y, r*0.85, g*0.85, b*0.85, 1);
		}
		return img;
	}
	public static Img NatureFlow()  // dappled sunlight through leaves
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double n = Fbm(u, v, 16, 2, 4, 81);
			double t = Smooth(0.15, 0.55, n) * 0.55;
			img.Set(x, y, t*.75, t*.95, t*.35, 1);
		}
		return img;
	}

	// ================================================================ ARCANE
	public static Img ArcaneBase()
	{
		var img = new Img(W, H);
		var ramp = new double[][] { S(0, .02,.02,.10), S(.45, .10,.08,.36), S(.7, .30,.18,.62), S(1, .55,.45,.95) };
		// constellation points, joined left to right
		var pts = new List<double[]>();
		for (int i = 0; i < 14; i++) pts.Add(new double[] { (i + Hash(i,0,95)) * W/14.0, 8 + 48*Hash(i,1,95) });
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double neb = Fbm(u, v, 12, 2, 5, 91);
			double streak = Math.Exp(-Math.Pow((v - 0.5 - 0.3*Fbm(u, 0.3, 4, 1, 3, 92)) * 4.5, 2));
			var col = Ramp(0.38 + 0.5*neb, ramp);
			double r = col[0] + streak*.05, g = col[1] + streak*.22, b = col[2] + streak*.45;
			double st = Hash(x, y, 93); if (st > 0.992) { double k = (st-0.992)/0.008; r += k; g += k; b += k; }
			double line = 0, dot = 0;
			for (int i = 0; i < pts.Count; i++)
			{
				var a = pts[i]; var p2 = pts[(i+1) % pts.Count];
				double bx = p2[0] + (i == pts.Count-1 ? W : 0), by = p2[1];
				double ax = a[0];
				double px = x; if (px < ax - W/2) px += W;
				double dx = bx-ax, dy = by-a[1], t = Clamp(((px-ax)*dx + (y-a[1])*dy) / (dx*dx + dy*dy));
				double ex = px - (ax + t*dx), ey = y - (a[1] + t*dy);
				line = Math.Max(line, Math.Exp(-(ex*ex + ey*ey)/0.5) * 0.45);
				double ddx = WrapDx(x, a[0], W), ddy = y - a[1];
				dot = Math.Max(dot, Math.Exp(-(ddx*ddx + ddy*ddy)/2.5));
			}
			r += line*.9 + dot; g += line*.75 + dot*.9; b += line*.45 + dot*.7;
			img.Set(x, y, r, g, b, 1);
		}
		return img;
	}
	// Rune glyphs: each is a few straight strokes on a 3x4 grid of nodes (a stave plus branches,
	// like Norse runes), sometimes with a small ring. Coordinates are 0..1 inside the glyph's box.
	static List<double[]>[] glyphSet;
	public const int GLYPH_COUNT = 16;
	static List<double[]>[] GetGlyphs()
	{
		if (glyphSet != null) return glyphSet;
		glyphSet = new List<double[]>[GLYPH_COUNT];
		double[] nx = { 0.18, 0.5, 0.82 }, ny = { 0.08, 0.36, 0.64, 0.92 };
		for (int g = 0; g < GLYPH_COUNT; g++)
		{
			var s = new List<double[]>();
			int stem = (int)(Hash(g, 0, 300)*3);
			if (Hash(g, 1, 300) < 0.85) s.Add(new double[] { nx[stem], ny[0], nx[stem], ny[3] });
			int n = 2 + (int)(Hash(g, 2, 300)*3);
			for (int i = 0, tries = 0; i < n && tries < 40; tries++)
			{
				int c1 = (int)(Hash(g, 10+tries, 301)*3), r1 = (int)(Hash(g, 10+tries, 302)*4);
				int c2 = (int)(Hash(g, 10+tries, 303)*3), r2 = (int)(Hash(g, 10+tries, 304)*4);
				if (c1 == c2 && Math.Abs(r1-r2) < 2) continue;
				if (c1 == c2 && c1 == stem) continue;
				s.Add(new double[] { nx[c1], ny[r1], nx[c2], ny[r2] }); i++;
			}
			if (Hash(g, 5, 300) > 0.7) s.Add(new double[] { -1, nx[(int)(Hash(g,6,300)*3)], ny[1 + (int)(Hash(g,7,300)*2)], 0.12 });
			glyphSet[g] = s;
		}
		return glyphSet;
	}
	static double GlyphDist(int g, double x, double y)   // distance to the glyph's strokes, in box units
	{
		double best = 9;
		foreach (var s in GetGlyphs()[g % GLYPH_COUNT])
		{
			double d;
			if (s[0] < 0) d = Math.Abs(Math.Sqrt((x-s[1])*(x-s[1]) + (y-s[2])*(y-s[2])) - s[3]);
			else
			{
				double dx = s[2]-s[0], dy = s[3]-s[1], t = Clamp(((x-s[0])*dx + (y-s[1])*dy) / (dx*dx + dy*dy));
				double ex = x - (s[0] + t*dx), ey = y - (s[1] + t*dy); d = Math.Sqrt(ex*ex + ey*ey);
			}
			if (d < best) best = d;
		}
		return best;
	}

	public static Img Glyphs()      // 8x2 atlas of 64px rune sprites, white with a glow
	{
		var img = new Img(512, 128);
		for (int y = 0; y < 128; y++) for (int x = 0; x < 512; x++)
		{
			int g = (y/64)*8 + x/64;
			double lx = ((x % 64) - 8) / 48.0, ly = ((y % 64) - 8) / 48.0;   // glyph box inset 8px
			double d = GlyphDist(g, lx, ly) * 48;                              // pixels
			double core = Smooth(2.6, 1.4, d), glow = Math.Exp(-d*d/40) * 0.55;
			img.Set(x, y, 1, 1, 1, Clamp(core + glow));
		}
		return img;
	}

	// ================================================================ SHADOW: black smoke, purple as the accent
	public static Img ShadowBase()
	{
		var img = new Img(W, H);
		var ramp = new double[][] { S(0, 0,0,0), S(.5, .03,.025,.04), S(.8, .085,.075,.105), S(1, .19,.17,.23) };
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double q1 = Fbm(u, v, 8, 1, 4, 51), q2 = Fbm(u, v, 8, 1, 4, 52);
			double n = Fbm(u + 0.05*q1, v + 0.5*q2, 16, 2, 5, 53);
			var col = Ramp(0.42 + 0.55*n, ramp);
			double edge = Math.Exp(-n*n*140) * Smooth(-0.3, 0.4, q1);             // thin purple seams in the smoke
			double ember = Smooth(0.25, 0.65, Fbm(u, v, 12, 2, 3, 54)) * 0.18;     // faint purple glow deep inside
			img.Set(x, y, col[0] + edge*.50 + ember*.45, col[1] + edge*.16 + ember*.12, col[2] + edge*.85 + ember*.80, 1);
		}
		return img;
	}
	public static Img ShadowFlow()
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double q = Fbm(u, v, 8, 1, 3, 61);
			double n = Fbm(u + 0.08*q, v + 0.6*q, 12, 2, 4, 62);
			double wisp = Math.Exp(-n*n*90) * Smooth(-0.3, 0.5, q) * 0.8;
			img.Set(x, y, wisp*.62, wisp*.20, wisp*1.0, 1);
		}
		return img;
	}

	// ================================================================ thorn (drawn live along the vines)
	public static Img Thorn()       // base along the bottom edge, curved point toward the top
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = (x - 31.5)/32.0, h = 1 - y/63.0;                      // h: 0 at the base, 1 at the tip
			double bend = 0.28*h*h;                                          // hooks to one side
			double half = 0.42*Math.Pow(1 - h, 1.6);
			double d = Math.Abs(u - bend);
			double a = Smooth(half + 0.05, half - 0.02, d) * Smooth(1.0, 0.95, h);
			double lit = 0.55 + 0.45*Clamp(1 - (u - bend + half)/(2*half + 1e-3));
			img.Set(x, y, .30*lit + .05*h, .16*lit, .08*lit, a);
		}
		return img;
	}

	// ================================================================ rune circles (drawn live by the addon, rotating)
	// 3 variants side by side in a 512x128 atlas (the fourth cell is empty; power-of-two size): outer double ring with ticks, a band of glyphs,
	// an inner ring and a different figure inside each.
	public static Img RuneCircles()
	{
		var img = new Img(512, 128);
		for (int y = 0; y < 128; y++) for (int x = 0; x < 384; x++)
		{
			int vi = x / 128;
			double dx = (x % 128) - 63.5, dy = y - 63.5, r = Math.Sqrt(dx*dx + dy*dy), R = 60;
			double ang = Math.Atan2(dy, dx), a01 = (ang + Math.PI) / (2*Math.PI);
			double t = 0;
			t += Math.Exp(-Math.Pow(r - R*0.98, 2)/0.9) + Math.Exp(-Math.Pow(r - R*0.90, 2)/0.7)*0.8;
			int ticks = vi == 1 ? 72 : 48;                                    // ticks between the outer rings
			if (r > R*0.90 && r < R*0.98 && Math.Abs(Frac(a01*ticks) - 0.5) < 0.09) t += 0.6;
			double rIn = R*0.62, rOut = R*0.86;
			t += Math.Exp(-Math.Pow(r - rIn, 2)/0.8)*0.8;
			if (r > rIn && r < rOut)
			{
				double bandH = rOut - rIn, mid = (rIn + rOut)/2;
				int cells = (int)Math.Round(2*Math.PI*mid / (bandH*0.78));
				int seg = (int)(a01*cells);
				double gx = (Frac(a01*cells) - 0.5) * (2*Math.PI*mid/cells) / bandH * 1.2 + 0.5;
				double gy = 1 - (r - rIn) / bandH;
				double d = GlyphDist((int)(Hash(seg, vi, 97)*GLYPH_COUNT), gx*1.15 - 0.075, gy*1.2 - 0.1) * bandH * 0.8;
				t += Smooth(1.4, 0.6, d) + Math.Exp(-d*d/3)*0.25;
			}
			if (r < rIn)
			{
				double rr = rIn*0.96, fig = 0;
				int pts = vi == 0 ? 6 : vi == 1 ? 8 : 3, step = vi == 0 ? 2 : vi == 1 ? 3 : 1;
				for (int k = 0; k < pts; k++)
				{
					double a1 = k*2*Math.PI/pts - Math.PI/2, a2 = (k+step)*2*Math.PI/pts - Math.PI/2;
					double x1 = Math.Cos(a1)*rr, y1 = Math.Sin(a1)*rr, x2 = Math.Cos(a2)*rr, y2 = Math.Sin(a2)*rr;
					double sx = x2-x1, sy = y2-y1, tt = Clamp(((dx-x1)*sx + (dy-y1)*sy) / (sx*sx + sy*sy));
					double ex = dx - (x1 + tt*sx), ey = dy - (y1 + tt*sy);
					fig = Math.Max(fig, Math.Exp(-(ex*ex + ey*ey)/0.7) * 0.75);
					if (vi == 2) { double cx = Math.Cos(a1)*rr, cy = Math.Sin(a1)*rr; fig = Math.Max(fig, Math.Exp(-Math.Pow(Math.Sqrt((dx-cx)*(dx-cx) + (dy-cy)*(dy-cy)) - 5, 2)/0.6)*0.8); }
				}
				t += fig + Math.Exp(-Math.Pow(r - R*0.16, 2)/0.6)*0.7 + Math.Exp(-r*r/5)*0.8;
			}
			t = Clamp(t);
			img.Set(x, y, 1, 1, 1, t);
		}
		return img;
	}

	public static Img ArcaneFlow()  // flowing ribbons of arcane energy with fine dust (the circles are live sprites)
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H, t = 0, pink = 0;
			for (int k = 0; k < 3; k++)
			{
				double cy = 0.5 + 0.32*Fbm(u, 0.2 + k*0.3, 4, 1, 3, 150 + k);
				double band = Math.Exp(-Math.Pow((v - cy)*H/(2.2 + 1.2*k), 2));
				double streak = 0.6 + 0.4*Noise(u*32, k*3.0, 32, 16, 160 + k);
				t += band*streak*(0.55 - 0.12*k); if (k == 1) pink += band*streak*0.4;
			}
			double dust = Hash(x, y, 170) > 0.985 ? 0.5 : 0;
			t = Clamp(t);
			img.Set(x, y, t*.45 + pink*.6 + dust, t*.55 + pink*.15 + dust, t*1.0 + pink*.5 + dust, 1);
		}
		return img;
	}

	// ================================================================ HOLY
	public static Img HolyBase()    // translucent gold radiance, fine glints, thin filigree near the edges
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double n = Fbm(u, v, 12, 2, 4, 101);
			double mid = Math.Exp(-Math.Pow((v - 0.5)*3.0, 2));
			double t = 0.30 + 0.45*mid + 0.2*n;
			double fil = 0;
			for (int k = -1; k <= 1; k += 2)
			{
				double cy = 0.5 + k*(0.36 + 0.035*Math.Sin(2*Math.PI*(u*6 + (k > 0 ? 0.5 : 0))));
				fil = Math.Max(fil, Math.Exp(-Math.Pow((v - cy)*H, 2)/0.5) * 0.6);
			}
			double gl = 0, hs = Hash(x/3, y/3, 102);
			if (hs > 0.985) { double cx = (x/3)*3 + 1, cy2 = (y/3)*3 + 1; double d = Math.Abs(x-cx) + Math.Abs(y-cy2); gl = Smooth(2.2, 0, d) * (hs-0.985)/0.015; }
			double r = .98*t + fil*.5 + gl, g = .80*t + fil*.42 + gl, b = .42*t + fil*.2 + gl*.8;
			img.Set(x, y, r, g, b, Clamp(0.40 + 0.40*mid + fil*0.5 + gl));
		}
		return img;
	}
	public static Img HolyFlow()    // soft light rays
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double rays = Fbm(u, v*0.08, 24, 1, 3, 111);
			double t = Smooth(-0.1, 0.6, rays) * 0.45 * (0.4 + 0.6*Math.Exp(-Math.Pow((v-0.5)*2.2, 2)));
			img.Set(x, y, t, t*.88, t*.55, 1);
		}
		return img;
	}

	// ================================================================ live-drawn pieces (vines, flowers, twinkles)
	public static Img Vine()        // bark strip, tiles along its length; the addon draws it as line segments
	{
		var img = new Img(128, 32);
		for (int y = 0; y < 32; y++) for (int x = 0; x < 128; x++)
		{
			double u = x/128.0, v = y/32.0, a = Math.Abs(v - 0.5)*2;
			double s = Math.Sqrt(Math.Max(0, 1 - a*a));
			double stri = 0.75 + 0.25*Noise(u*24, v*3, 24, 3, 131);
			double moss = Smooth(0.15, 0.45, Fbm(u, v, 4, 1, 3, 132));
			double r = Lerp(.40, .22, moss)*stri, g = Lerp(.27, .36, moss)*stri, b = Lerp(.13, .10, moss)*stri;
			double sh = 0.35 + 0.65*s + 0.25*Math.Exp(-Math.Pow((v-0.35)*8, 2));
			img.Set(x, y, r*sh, g*sh, b*sh, Smooth(1.0, 0.82, a));
		}
		return img;
	}
	public static Img Flower()      // five petals (white, tinted per flower) around a golden centre
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x-31.5)/32, dy = (y-31.5)/32, r = Math.Sqrt(dx*dx + dy*dy), a = Math.Atan2(dy, dx);
			double petalR = 0.62 + 0.30*Math.Pow(Math.Abs(Math.Cos(2.5*a)), 0.6);
			double petal = Smooth(petalR, petalR - 0.08, r);
			double shade = 0.7 + 0.3*(r/petalR) - 0.25*Math.Pow(Math.Abs(Math.Sin(2.5*a)), 8);
			double ctr = Smooth(0.24, 0.16, r);
			double cr = Lerp(shade, 1.0, ctr), cg = Lerp(shade, .78, ctr), cb = Lerp(shade, .18, ctr);
			img.Set(x, y, cr, cg, cb, Clamp(Math.Max(petal, ctr)));
		}
		return img;
	}
	public static Img Twinkle()     // four long thin rays, four short diagonal ones, bright core
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x-31.5)/32, dy = (y-31.5)/32, r = Math.Sqrt(dx*dx + dy*dy);
			double ray = Math.Exp(-dx*dx*900) * Smooth(1, 0, Math.Abs(dy)) + Math.Exp(-dy*dy*900) * Smooth(1, 0, Math.Abs(dx));
			double ex = (dx+dy)*0.7071, ey = (dy-dx)*0.7071;
			double diag = (Math.Exp(-ex*ex*1500) * Smooth(0.45, 0, Math.Abs(ey)) + Math.Exp(-ey*ey*1500) * Smooth(0.45, 0, Math.Abs(ex))) * 0.6;
			double core = Math.Exp(-r*r*120) + Math.Exp(-r*r*14)*0.35;
			img.Set(x, y, 1, 1, 1, Clamp(ray + diag + core));
		}
		return img;
	}

	// ================================================================ shared pieces
	public static Img Sweep()       // a soft vertical band of light; the addon leans it and sweeps it across frost
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 31.5)/32.0;
			img.Set(x, y, 1, 1, 1, Math.Exp(-dx*dx*9) * Smooth(1.0, 0.7, Math.Abs(dy)));
		}
		return img;
	}

	public static Img Veil()        // soft large-scale shimmer, greyscale, tinted per element
	{
		var img = new Img(256, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 256; x++)
		{
			double u = x/256.0, v = y/64.0;
			double n = Fbm(u, v, 4, 1, 4, 121);
			double t = Smooth(-0.2, 0.6, n) * 0.6;
			img.Set(x, y, t, t, t, 1);
		}
		return img;
	}
	public static Img Spark()       // leading edge: bright vertical core with a soft halo
	{
		var img = new Img(64, 128);
		for (int y = 0; y < 128; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 63.5)/64.0;
			double core = Math.Exp(-dx*dx*900) * Smooth(1.0, 0.55, Math.Abs(dy));
			double halo = Math.Exp(-(dx*dx*9 + dy*dy*5)) * 0.55;
			double t = Clamp(core + halo);
			img.Set(x, y, 1, 1, 1, t);
		}
		return img;
	}
	public static Img Glow()        // soft rounded-rectangle glow, used as left cap / stretched middle / right cap
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = Math.Abs(x - 31.5)/32.0, dy = Math.Abs(y - 31.5)/32.0;
			double ex = Math.Max(0, dx - 0.0), ey = Math.Max(0, dy - 0.5) / 0.5;   // flat middle band vertically
			double d = Math.Sqrt(ex*ex + ey*ey);
			double t = Math.Pow(Clamp(1 - d), 2.2);
			img.Set(x, y, 1, 1, 1, t);
		}
		return img;
	}
	// Edge masks for the borderless look. Masks multiply the bar's alpha.
	// edge_v: top and bottom fade with a ragged, noisy line; tiles left-right so it can drift.
	// edge_h: left-to-right fade over the texture's width; the addon uses it for both ends.
	public static Img EdgeV()
	{
		var img = new Img(256, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 256; x++)
		{
			double u = x/256.0, v = y/64.0, d = 0.5 - Math.Abs(v - 0.5);    // 0 at the edge, 0.5 in the middle
			double n = Fbm(u, v, 16, 1, 4, 141) * 0.09;
			img.Set(x, y, 1, 1, 1, Smooth(0.02, 0.20, d + n));
		}
		return img;
	}
	public static Img EdgeH()
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = x/64.0, v = y/64.0;
			double n = Noise(u*2, v*6, 2, 6, 142) * 0.12;
			img.Set(x, y, 1, 1, 1, Smooth(0.0, 0.9, u + n));
		}
		return img;
	}

	public static Img Particle(string kind)
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 31.5)/32.0, r = Math.Sqrt(dx*dx + dy*dy), a = Math.Atan2(dy, dx);
			double t = 0, shade = 1;
			if (kind == "soft") t = Math.Exp(-r*r*7);
			else if (kind == "star") t = Clamp(Math.Exp(-r*r*40) + Math.Pow(Math.Abs(Math.Cos(2*a)), 30) * Smooth(1, 0, r) * 0.9);
			else if (kind == "flake")
			{
				double arm = Math.Pow(Math.Abs(Math.Cos(3*a)), 50) * Smooth(0.95, 0.1, r);
				double br = Math.Pow(Math.Abs(Math.Cos(3*a + Math.PI/6)), 70) * Smooth(0.6, 0.25, r) * Smooth(0.15, 0.3, r);
				t = Clamp(arm + br*0.8 + Math.Exp(-r*r*60));
			}
			else if (kind == "ember") t = Math.Exp(-(dx*dx*30 + dy*dy*3.5));
			else if (kind == "leaf")
			{
				// pointed leaf along the diagonal with a central vein; shade carries the vein
				double lx = (dx + dy)*0.7071, ly = (dy - dx)*0.7071;
				double half = 0.42 * Math.Sqrt(Math.Max(0, 1 - lx*lx/0.85)) * (1 - 0.35*lx);
				t = Smooth(half + 0.04, half - 0.04, Math.Abs(ly));
				shade = 0.75 + 0.25*(1 - Math.Abs(ly)/Math.Max(0.01, half)) - 0.3*Math.Exp(-ly*ly*900);
			}
			img.Set(x, y, shade, shade, shade, Clamp(t));
		}
		return img;
	}

	// ================================================================ preview composite
	static void Add(double[] dst, double r, double g, double b) { dst[0] += r; dst[1] += g; dst[2] += b; }
	public static void Preview(string dir, string png)
	{
		string[] els = { "frost", "fire", "shadow", "nature", "arcane", "holy" };
		double[][] border = { new[]{.80,.92,1.0}, new[]{.85,.35,.08}, new[]{.30,.15,.45}, new[]{.30,.62,.15}, new[]{.35,.45,1.0}, new[]{1.0,.84,.45} };
		int BW = 768, BH = 48, GAP = 20, PW = BW + 40, PH = (BH + GAP) * els.Length + GAP;
		var bmp = new System.Drawing.Bitmap(PW, PH);
		var veil = Veil();
		for (int e = 0; e < els.Length; e++)
		{
			// frost is built live from layers; the still shows its plain ice
			string bp = Path.Combine(dir, els[e] + "_base.tga"), fp = Path.Combine(dir, els[e] + "_flow.tga");
			if (!File.Exists(bp)) { bp = Path.Combine(dir, els[e] + "_ice.tga"); fp = bp; }
			var bas = Load(bp);
			var flo = Load(fp);
			int ox = 20, oy = GAP + e*(BH + GAP);
			double fill = 0.7 * BW;
			for (int y = 0; y < BH; y++) for (int x = 0; x < BW; x++)
			{
				double tu = x * (64.0/BH) % bas.W, tv = y * (64.0/BH);
				int si = (int)tv*bas.W + (int)tu;
				double[] c = new double[3];
				double ba = bas.A[si];
				if (x < fill)
				{
					c[0] = bas.R[si]*ba; c[1] = bas.G[si]*ba; c[2] = bas.B[si]*ba;
					double fa = 0.8; Add(c, flo.R[si]*fa, flo.G[si]*fa, flo.B[si]*fa);
					int vi = (int)tv*256 + (int)(x*(64.0/BH)*0.5 % 256);
					Add(c, veil.R[vi]*border[e][0]*.5, veil.R[vi]*border[e][1]*.5, veil.R[vi]*border[e][2]*.5);
					double sd = (fill - x); if (sd < 14) { double k = Math.Exp(-sd*sd/40); Add(c, k, k, k); }
				}
				else { c[0] = .04 + bas.R[si]*.12; c[1] = .04 + bas.G[si]*.12; c[2] = .05 + bas.B[si]*.12; }
				if (y < 2 || y >= BH-2 || x < 2 || x >= BW-2) { c[0] = border[e][0]; c[1] = border[e][1]; c[2] = border[e][2]; }
				bmp.SetPixel(ox + x, oy + y, System.Drawing.Color.FromArgb(255, B8(c[0]), B8(c[1]), B8(c[2])));
			}
		}
		// fill the gaps dark grey
		for (int y = 0; y < PH; y++) for (int x = 0; x < PW; x++)
		{
			bool inBar = false;
			for (int e = 0; e < els.Length; e++) { int oy = GAP + e*(BH+GAP); if (x >= 20 && x < 20+BW && y >= oy && y < oy+BH) inBar = true; }
			if (!inBar) bmp.SetPixel(x, y, System.Drawing.Color.FromArgb(255, 28, 28, 32));
		}
		bmp.Save(png, System.Drawing.Imaging.ImageFormat.Png);
	}
	// For the browser preview: a TGA as a PNG data URI (straight alpha).
	public static string PngDataUri(string path)
	{
		var img = Load(path);
		var bmp = new System.Drawing.Bitmap(img.W, img.H, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
		for (int y = 0; y < img.H; y++) for (int x = 0; x < img.W; x++)
		{
			int i = y*img.W + x;
			bmp.SetPixel(x, y, System.Drawing.Color.FromArgb(B8(img.A[i]), B8(img.R[i]), B8(img.G[i]), B8(img.B[i])));
		}
		using (var ms = new MemoryStream()) { bmp.Save(ms, System.Drawing.Imaging.ImageFormat.Png); return "data:image/png;base64," + Convert.ToBase64String(ms.ToArray()); }
	}
	static Img Load(string path)
	{
		byte[] b = File.ReadAllBytes(path);
		int w = b[12] | (b[13] << 8), h = b[14] | (b[15] << 8);
		var img = new Img(w, h);
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
		{
			int s = 18 + ((h-1-y)*w + x)*4;
			img.Set(x, y, b[s+2]/255.0, b[s+1]/255.0, b[s]/255.0, b[s+3]/255.0);
		}
		return img;
	}
}
'@

New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$jobs = [ordered]@{
	'frost_ice'  = { [CastbarArt]::FrostIce() }
	'frost_cut0_hi' = { [CastbarArt]::FrostCut(0, $true) };  'frost_cut0_lo' = { [CastbarArt]::FrostCut(0, $false) }
	'frost_cut1_hi' = { [CastbarArt]::FrostCut(1, $true) };  'frost_cut1_lo' = { [CastbarArt]::FrostCut(1, $false) }
	'frost_cut2_hi' = { [CastbarArt]::FrostCut(2, $true) };  'frost_cut2_lo' = { [CastbarArt]::FrostCut(2, $false) }
	'frost_cut3_hi' = { [CastbarArt]::FrostCut(3, $true) };  'frost_cut3_lo' = { [CastbarArt]::FrostCut(3, $false) }
	'frost_cut4_hi' = { [CastbarArt]::FrostCut(4, $true) };  'frost_cut4_lo' = { [CastbarArt]::FrostCut(4, $false) }
	'fire_base'  = { [CastbarArt]::FireBase() };    'fire_flow'   = { [CastbarArt]::FireFlow() }
	'shadow_base'= { [CastbarArt]::ShadowBase() };  'shadow_flow' = { [CastbarArt]::ShadowFlow() }
	'nature_base'= { [CastbarArt]::NatureBase() };  'nature_flow' = { [CastbarArt]::NatureFlow() }
	'arcane_base'= { [CastbarArt]::ArcaneBase() };  'arcane_flow' = { [CastbarArt]::ArcaneFlow() }
	'holy_base'  = { [CastbarArt]::HolyBase() };    'holy_flow'   = { [CastbarArt]::HolyFlow() }
	'veil'       = { [CastbarArt]::Veil() }
	'sweep'      = { [CastbarArt]::Sweep() }
	'spark'      = { [CastbarArt]::Spark() }
	'glow'       = { [CastbarArt]::Glow() }
	'p_soft'     = { [CastbarArt]::Particle('soft') }
	'p_star'     = { [CastbarArt]::Particle('star') }
	'p_flake'    = { [CastbarArt]::Particle('flake') }
	'p_ember'    = { [CastbarArt]::Particle('ember') }
	'p_leaf'     = { [CastbarArt]::Particle('leaf') }
	'p_glyphs'   = { [CastbarArt]::Glyphs() }
	'p_twinkle'  = { [CastbarArt]::Twinkle() }
	'vine'       = { [CastbarArt]::Vine() }
	'edge_v'     = { [CastbarArt]::EdgeV() }
	'edge_h'     = { [CastbarArt]::EdgeH() }
	'p_thorn'    = { [CastbarArt]::Thorn() }
	'p_runecircles' = { [CastbarArt]::RuneCircles() }
}
foreach ($name in $jobs.Keys) {
	[CastbarArt]::WriteTga((& $jobs[$name]), (Join-Path $Out "$name.tga"))
}
Write-Host "Wrote $($jobs.Count) textures to $Out"

# The frost cut geometry, so the addon traces exactly the lines baked into the frost_cut textures.
$lua = @(
	'-- daves_castbar / FrostCuts.lua',
	'-- GENERATED by tools/Make-CastbarMedia.ps1 - do not edit. The frost cut lines baked into',
	'-- Media/frost_cutN_*.tga, as { {x, y}, ... } per cut in texture pixels (512 x 64, y down),',
	'-- from the first corner at or after x = 0 to that corner + 512.',
	'',
	'local _, ns = ...',
	('ns.FROST_CUTS = ' + ([CastbarArt]::FrostCutsJson() -replace '\[', '{' -replace '\]', '}'))
) -join "`n"
[IO.File]::WriteAllText((Join-Path (Split-Path $Out) 'FrostCuts.lua'), $lua + "`n", (New-Object Text.UTF8Encoding $false))
if ($Preview) {
	[CastbarArt]::Preview($Out, $Preview)
	Write-Host "Preview: $Preview"
}
