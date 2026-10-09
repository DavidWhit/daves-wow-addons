<#
.SYNOPSIS
  Generates daves_castbar's art: tiling elemental and profession bar layers, sprites, particles, spark and glow.

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

	// ================================================================ FROST: a liquid that freezes as the cast moves across
	// Ahead of the cast (drawn on the track) a level band of water flows: frost_water, with bright
	// streaks in frost_water_hi. Behind the fill edge it is frozen into a slab: frost_ice. The freeze
	// front (frost_front) sits at the fill edge: feathery white rime, strongest at the edge itself.
	// A level band of water, the same shape as the ice slab, with only a slight ripple on its surface.
	static double RibbonCover(double u, double v, out double depth)
	{
		double top = 0.07 + 0.012*Math.Sin(2*Math.PI*(u*16)) + 0.01*Fbm(u, 0.5, 24, 1, 2, 301);
		double bot = 0.95;
		depth = Clamp((v - top) / (bot - top));
		double spray = 0.03*Fbm(u, v, 48, 6, 2, 303);
		return Smooth(top - 0.02 + spray, top + 0.03 + spray, v) * Smooth(bot + 0.03, bot - 0.02, v);
	}
	public static Img FrostWater()
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H, d;
			double cover = RibbonCover(u, v, out d);
			double flow = Fbm(u, v, 6, 3, 4, 304);
			double r = Lerp(.42, .06, d) + .10*flow, g = Lerp(.68, .28, d) + .12*flow, b = Lerp(.92, .58, d) + .10*flow;
			double rim = Math.Exp(-d*d*120) * 0.45;                       // light along the top of the ribbon
			img.Set(x, y, r + rim, g + rim, b + rim, cover * (0.72 + 0.18*(1 - d)));
		}
		return img;
	}
	public static Img FrostWaterHi()   // ADD: bright flowing streaks and a few bubbles inside the ribbon
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H, d;
			double cover = RibbonCover(u, v, out d);
			// long thin streaks along the flow: noise stretched sideways, few cells across, many down
			double streak = Math.Pow(Clamp(1 - Math.Abs(Fbm(u, v, 4, 6, 4, 305))), 18) * 0.55;
			int bx = x / 6, by = y / 6;
			double bdx = (x % 6) - 2.5, bdy = (y % 6) - 2.5;
			double bubble = Hash(bx, by, 306) > 0.97 ? Math.Exp(-(bdx*bdx + bdy*bdy)/1.2) * 0.6 : 0;
			double t = (streak + bubble) * cover;
			img.Set(x, y, t*.80, t*.92, t, 1);
		}
		return img;
	}
	public static Img FrostIce()       // the frozen slab: pale, cloudy, cracked, frosted along the rims
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double cloud = Fbm(u, v, 8, 1, 5, 311);
			// a few long fractures (sharp ridges of stretched noise), not a cell network
			double fracture = Math.Pow(Clamp(1 - Math.Abs(Fbm(u, v, 6, 2, 3, 312))), 30) * 0.45
				+ Math.Pow(Clamp(1 - Math.Abs(Fbm(u, v, 12, 3, 3, 313))), 40) * 0.25;
			double crack = fracture;
			double streak = Math.Pow(Clamp(1 - Math.Abs(Fbm(u, v*0.3, 12, 1, 3, 314))), 10) * 0.18
				+ Smooth(0.1, 0.7, Fbm(u, v, 16, 4, 4, 318)) * 0.22;                 // milky frozen-in cloud
			double rimN = 0.06*Fbm(u, v, 32, 2, 3, 315);
			double rim = Smooth(0.16 + rimN, 0.0, v)*0.55 + Smooth(0.84 - rimN, 1.0, v)*0.40;   // frosted top and bottom
			double grain = (Hash(x, y, 316) - 0.5)*0.05 + (Hash(x, y, 317) > 0.994 ? 0.3 : 0);
			double t = 0.52 + 0.16*cloud - (v - 0.5)*0.10;
			double w = crack + streak + rim + grain;
			img.Set(x, y, .40*t + .55*w + .22, .56*t + .58*w + .26, .70*t + .60*w + .28, 0.95);
		}
		return img;
	}
	public static Img FrostFront()     // 64x64: rime feathering in from the right edge (the freeze front)
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = x/63.0, v = y/63.0;
			double fern = Math.Pow(Clamp(1 - Math.Abs(Fbm(u, v, 4, 4, 4, 321))), 6);
			double reach = Smooth(0.0, 1.0, u + 0.25*Fbm(u, v, 2, 6, 3, 322));
			img.Set(x, y, .86, .95, 1, Clamp(reach*reach*(0.35 + 0.65*fern)));
		}
		return img;
	}

	// ================================================================ FISHING: a pond with lily pads, fish and a bobber
	public static Img FishWater()      // the pond: bright surface line near the top, deeper teal below
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double surf = 0.13 + 0.015*Math.Sin(2*Math.PI*(u*8)) + 0.01*Fbm(u, 0.5, 16, 1, 2, 401);
			double n = Fbm(u, v, 8, 1, 4, 402);
			double depth = Clamp((v - surf) / (1 - surf));
			double r = Lerp(.20, .04, depth) + .04*n, g = Lerp(.55, .22, depth) + .05*n, b = Lerp(.60, .30, depth) + .05*n;
			double line = Math.Exp(-Math.Pow((v - surf)*H/1.3, 2)) * 0.55;    // the surface catching the light
			double above = Smooth(surf + 0.01, surf - 0.03, v);                 // a sliver of sky reflection over it
			r = Lerp(r, .55, above*0.6) + line; g = Lerp(g, .75, above*0.6) + line; b = Lerp(b, .78, above*0.6) + line;
			double weed = Smooth(0.72, 1.0, v) * Smooth(0.2, 0.6, Fbm(u, v, 24, 2, 3, 403)) * 0.35;   // weed in the deep
			img.Set(x, y, r - weed*.10, g - weed*.02, b - weed*.12, 0.92);
		}
		return img;
	}
	public static Img FishCaustic()    // ADD: sunlight network on the water, fading with depth
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H, f1, f2; int cell;
			Voronoi(u + 0.02*Fbm(u, v, 8, 1, 2, 411), v, 32, 4, 412, out f1, out f2, out cell);
			double t = Math.Exp(-Math.Pow((f2 - f1)*9, 2)) * 0.28 * (1 - 0.75*v) * Smooth(0.1, 0.18, v);
			img.Set(x, y, t*.65, t*.95, t*.90, 1);
		}
		return img;
	}
	public static Img LilyPad()        // a pad seen from just above the water: flat ellipse with a notch and veins
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/30.0, dy = (y - 31.5)/12.0, r = Math.Sqrt(dx*dx + dy*dy), a = Math.Atan2(dy, dx);
			double notch = Smooth(0.18, 0.08, Math.Abs(Math.Atan2(Math.Sin(a - 0.6), Math.Cos(a - 0.6)))) * Smooth(0.15, 0.3, r);
			double pad = Smooth(1.0, 0.92, r) * (1 - notch);
			double vein = Math.Pow(Math.Abs(Math.Cos(a*7)), 40) * 0.25 * Smooth(0.15, 0.4, r);
			double shade = 0.75 + 0.25*(-dy*0.35 + 0.6) - vein - Smooth(0.75, 1.0, r)*0.25;
			double n = 0.08*Noise(dx*3, dy*3, 64, 64, 421);
			img.Set(x, y, (.22 + n)*shade, (.50 + n)*shade, (.18 + n)*shade, Clamp(pad));
		}
		return img;
	}
	public static Img Fish()           // a small fish facing right, white (tinted per fish), dark eye
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 31.5)/32.0;
			double bx = (dx - 0.08)/0.52, by = dy/(0.20*(1 - 0.35*Math.Max(0, -bx)));   // body narrows toward the tail
			double body = Smooth(1.0, 0.85, Math.Sqrt(bx*bx + by*by));
			double tx = (-dx - 0.42)/0.30;                                                   // forked tail
			double tail = (tx > 0 && tx < 1) ? Smooth(0.08, 0.0, Math.Abs(Math.Abs(dy) - tx*0.26) - 0.06*(1 - tx)) : 0;
			double fin = Smooth(0.03, 0.0, Math.Abs(dy + 0.20 + 0.35*(dx - 0.05)) - 0.02) * Smooth(-0.15, -0.05, dx) * Smooth(0.25, 0.1, dx);
			double a = Clamp(Math.Max(body, Math.Max(tail*0.9, fin*0.8)));
			double shade = 0.65 + 0.35*Clamp(-dy*2.2 + 0.4);                               // lit from above
			double eye = Math.Exp(-((dx - 0.42)*(dx - 0.42) + (dy + 0.03)*(dy + 0.03))*1800);
			shade = Lerp(shade, 0.08, eye);
			img.Set(x, y, shade, shade, shade, a);
		}
		return img;
	}
	public static Img Bobber()         // red cap, white base, a little stick on top; the line hangs from it
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 35.5)/32.0, r = Math.Sqrt(dx*dx + dy*dy);
			double ball = Smooth(0.36, 0.32, r);
			double stick = Smooth(0.05, 0.03, Math.Abs(dx)) * Smooth(-0.75, -0.7, dy) * Smooth(-0.25, -0.32, dy);
			bool top = dy < 0.02;
			double band = Math.Exp(-Math.Pow((dy - 0.02)*40, 2));
			double lit = 0.75 + 0.25*Clamp(-(dx + dy)*1.6) + 0.5*Math.Exp(-((dx + 0.12)*(dx + 0.12) + (dy + 0.14)*(dy + 0.14))*90);
			double cr = top ? .85 : .95, cg = top ? .10 : .93, cb = top ? .10 : .90;
			cr = Lerp(cr, .15, band); cg = Lerp(cg, .10, band); cb = Lerp(cb, .10, band);
			if (stick > ball) { cr = .25; cg = .18; cb = .12; lit = 1; }
			img.Set(x, y, cr*lit, cg*lit, cb*lit, Clamp(Math.Max(ball, stick)));
		}
		return img;
	}
	public static Img Ripple()         // a thin ring; the addon squashes it flat and grows it
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 31.5)/32.0, r = Math.Sqrt(dx*dx + dy*dy);
			img.Set(x, y, 1, 1, 1, Math.Exp(-Math.Pow((r - 0.85)/0.06, 2)));
		}
		return img;
	}

	// ================================================================ MINING: rails along a rock wall, a cart, a pickaxe
	// Mining art, painted rather than outlined (as the skinning knife and the forge hammer): soft shading, brushed
	// metal, wood grain, one soft shadow. The rails run along the very bottom of the bar, with no ground strip under
	// them, so the cart fits inside the bar's height.
	static void OverP(double[] p, double r, double g, double b, double a) { p[0] = Lerp(p[0], r, a); p[1] = Lerp(p[1], g, a); p[2] = Lerp(p[2], b, a); p[3] = p[3] + a*(1 - p[3]); }
	public static Img MineRails()
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H, f1, f2; int cell;
			Voronoi(u, v, 24, 3, 501, out f1, out f2, out cell);            // stones in the wall
			double stone = 0.55 + 0.25*Hash(cell, 1, 502) + 0.15*Fbm(u, v, 32, 4, 3, 503);
			double seam = Smooth(0.0, 0.12, f2 - f1);
			double dim = 1 - 0.35*Smooth(0.55, 1.0, v);                     // the wall darkens toward the track
			double r = .20*stone*seam*dim, g = .17*stone*seam*dim, b = .15*stone*seam*dim;
			if (Hash(x/2, y/2, 504) > 0.997 && v < 0.8)                        // a few ore glints in the wall
			{
				int k = (int)(Hash(x/2, y/2, 505)*4);
				double[][] gem = { new[]{.4,.7,1.0}, new[]{.75,.5,1.0}, new[]{.4,1.0,.6}, new[]{1.0,.8,.35} };
				r = gem[k][0]*.8; g = gem[k][1]*.8; b = gem[k][2]*.8;
			}
			// sleepers: dark, weathered wood ties between and under the rails, every 32 px
			double sx = Mod(x, 32);
			double tie = Smooth(3, 5, sx)*Smooth(23, 21, sx)*Smooth(0.86, 0.88, v);
			if (tie > 0)
			{
				double grain = 0.75 + 0.25*Noise(x/2.5, y*1.2, 512, 64, 507);
				double sh = 0.55 + 0.45*Clamp((v - 0.86)/0.14);
				r = Lerp(r, .30*grain*sh, tie); g = Lerp(g, .20*grain*sh, tie); b = Lerp(b, .12*grain*sh, tie);
			}
			// a soft shadow just above each rail, then the rails: lit top edge, brushed steel, dark underside
			double shadow = 0.35*Smooth(0.04, 0, Math.Abs(v - 0.86)) + 0.45*Smooth(0.05, 0, Math.Abs(v - 0.925));
			r *= 1 - shadow; g *= 1 - shadow; b *= 1 - shadow;
			foreach (var rail in new[] { new[] { 0.885, 0.028, 0.7 }, new[] { 0.955, 0.04, 1.0 } })   // far rail, near rail: centre, half height, brightness
			{
				double d = Math.Abs(v - rail[0]);
				double cover = Smooth(rail[1] + 1.0/H, rail[1], d);
				if (cover <= 0) continue;
				double t = (v - (rail[0] - rail[1]))/(2*rail[1]);               // 0 top .. 1 bottom
				double brush = 0.93 + 0.07*Noise(x/1.5, 0, 512, 1, 508);
				double steel = (0.62 - 0.38*t + 0.3*Smooth(0.25, 0, t))*brush*rail[2];
				r = Lerp(r, steel*.92, cover); g = Lerp(g, steel*.9, cover); b = Lerp(b, steel*.9, cover);
			}
			img.Set(x, y, r, g, b, 1);
		}
		return img;
	}
	public static Img MineFlow()       // ADD: warm, flickering lantern light on the wall
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double t = Smooth(-0.1, 0.6, Fbm(u, v, 8, 1, 3, 511)) * 0.35 * (1 - 0.5*v);
			img.Set(x, y, t, t*.62, t*.25, 1);
		}
		return img;
	}
	// 128x128: a wooden ore cart with iron bands and a heap of ore and gems; wheels are separate sprites. The box
	// spans v .40-.80, the ore heaps above the rim, the brass lantern hangs on the front (u .80, v .60).
	public static Img Cart()
	{
		const int S = 128; double aa = 1.5/S;
		var img = new Img(S, S);
		double[][] gem = { new[]{.35,.65,1.0}, new[]{.70,.45,1.0}, new[]{.35,.95,.55}, new[]{1.0,.80,.30} };
		var rnd = new Random(530);
		var rocks = new List<double[]>();   // x, y, rx, ry, tone, gem index (-1 rock)
		for (int k = 0; k < 14; k++)
		{
			double cx = 0.14 + 0.72*k/13.0 + Rnd(rnd, -.03, .03), top = 0.42 - 0.16*Math.Sin(Math.PI*(cx - 0.1)/0.8);
			rocks.Add(new[] { cx, top + Rnd(rnd, 0, .06), Rnd(rnd, .05, .09), Rnd(rnd, .04, .065), Rnd(rnd, .7, 1.1), rnd.NextDouble() < .3 ? rnd.Next(4) : -1 });
		}
		for (int y = 0; y < S; y++) for (int x = 0; x < S; x++)
		{
			double u = (x + .5)/S, v = (y + .5)/S;
			var P = new double[4];   // r, g, b, a, painted back to front with OverP
			// one soft shadow under the box, on the track
			double sh = Math.Exp(-Math.Pow((u - .5)/.42, 2) - Math.Pow((v - .83)/.025, 2));
			OverP(P, 0, 0, 0, .45*sh);
			// the ore heap: rough rocks lit from the upper left, a few gems among them
			foreach (var k in rocks)
			{
				double dx = (u - k[0])/k[2], dy = (v - k[1])/k[3];
				double e = Math.Sqrt(dx*dx + dy*dy) + 0.12*Noise(u*24 + k[0]*7, v*24, 64, 64, 531);
				double cov = Smooth(1 + aa/k[3], 1, e);
				if (cov <= 0) continue;
				double lit = Clamp(0.55 - 0.45*dy - 0.25*dx);
				if (k[5] >= 0)
				{
					var c = gem[(int)k[5]];
					double facet = Math.Abs(dx) < .15 ? 1.15 : 0.85;
					double spec = Math.Exp(-((dx + .35)*(dx + .35) + (dy + .45)*(dy + .45))/.03);
					OverP(P, Clamp(c[0]*(0.45 + 0.6*lit)*facet + spec), Clamp(c[1]*(0.45 + 0.6*lit)*facet + spec), Clamp(c[2]*(0.45 + 0.6*lit)*facet + spec), cov);
				}
				else
				{
					double t = (0.16 + 0.22*lit)*k[4];
					OverP(P, t*1.05, t*.98, t*.92, cov);
				}
			}
			// the box: a trapezoid of three planks
			double inset = (v - 0.40)*0.10;
			double l = 0.07 + inset, rr = 0.93 - inset;
			double bx = Smooth(l - aa, l, u)*Smooth(rr + aa, rr, u)*Smooth(0.40 - aa, 0.40, v)*Smooth(0.80 + aa, 0.80, v);
			if (bx > 0)
			{
				double pv = (v - 0.40)/0.40, plankV = pv*3, seamD = Math.Abs(plankV - Math.Round(plankV));
				double grain = 0.82 + 0.12*Noise(u*6, v*60, 32, 128, 532) + 0.06*Noise(u*40, v*8, 128, 32, 533);
				double shade = (0.95 - 0.35*pv)*(0.85 + 0.25*Clamp(1 - (u - l)/(rr - l)));
				double seamDark = 1 - 0.45*Smooth(0.08, 0.0, seamD)*(pv > 0.02 && pv < 0.98 ? 1 : 0);
				double t = grain*shade*seamDark;
				OverP(P, .46*t, .29*t, .16*t, bx);
				// iron: a band along the rim and the foot, two straps; brushed, with small rivets
				double band = Math.Max(Smooth(0.045, 0.035, Math.Abs(v - 0.425)), Smooth(0.035, 0.025, Math.Abs(v - 0.775)));
				double strap = Math.Max(Smooth(0.035, 0.025, Math.Abs(u - (l + 0.09))), Smooth(0.035, 0.025, Math.Abs(u - (rr - 0.09))));
				double iron = Math.Max(band, strap)*bx;
				if (iron > 0)
				{
					double brush = 0.9 + 0.1*Noise(u*90, v*6, 128, 32, 534);
					double s = (0.42 + 0.18*Clamp(1 - pv*1.6) + 0.1*Clamp(1 - (u - l)/(rr - l)))*brush;
					OverP(P, s*.92, s*.92, s*.95, iron);
					foreach (double ru in new[] { l + 0.09, rr - 0.09, 0.5 })
						foreach (double rv in new[] { 0.425, 0.775, 0.6 })
						{
							if (ru == 0.5 && rv == 0.6) continue;
							double d = Math.Sqrt((u - ru)*(u - ru) + (v - rv)*(v - rv));
							double rc = Smooth(0.016 + aa, 0.016, d);
							if (rc > 0) { double hl = 0.5 + 0.4*Clamp(-(u - ru + v - rv)/0.02); OverP(P, hl, hl*.97, hl*.92, rc*iron); }
						}
				}
			}
			// the lantern on the front: a small brass cage with a warm glass
			{
				double lu = 0.80, lv = 0.60;
				double frame = Smooth(0.052, 0.045, Math.Abs(u - lu))*Smooth(0.075, 0.068, Math.Abs(v - lv));
				if (frame > 0)
				{
					double glass = Smooth(0.034, 0.028, Math.Abs(u - lu))*Smooth(0.058, 0.05, Math.Abs(v - lv));
					double brass = 0.55 + 0.3*Clamp(-(u - lu)/0.05);
					OverP(P, .75*brass, .58*brass, .30*brass, frame);
					double glow = Math.Exp(-((u - lu)*(u - lu) + (v - lv)*(v - lv))/0.0015);
					OverP(P, 1, Clamp(.72 + .2*glow), Clamp(.35 + .3*glow), glass);
				}
				double cap = Smooth(0.03, 0.02, Math.Abs(u - lu))*Smooth(0.014, 0.008, Math.Abs(v - (lv - 0.085)));
				OverP(P, .55, .42, .22, cap);
			}
			img.Set(x, y, P[0], P[1], P[2], Clamp(P[3]));
		}
		return img;
	}
	// 128x128: a spoked iron wheel with a flanged tyre; the addon turns it as the cart rolls
	public static Img Wheel()
	{
		const int S = 128; double aa = 1.5/S;
		var img = new Img(S, S);
		for (int y = 0; y < S; y++) for (int x = 0; x < S; x++)
		{
			double dx = (x + .5 - S/2.0)/(S/2.0), dy = (y + .5 - S/2.0)/(S/2.0), rr = Math.Sqrt(dx*dx + dy*dy), an = Math.Atan2(dy, dx);
			double tyre = Smooth(0.96 + aa, 0.96, rr)*Smooth(0.74 - aa, 0.74, rr);
			double spoke = Smooth(0.075 + aa, 0.075, Math.Abs(Math.Sin(an*3))*rr)*Smooth(0.78, 0.74, rr);
			double hub = Smooth(0.24 + aa, 0.24, rr);
			double cov = Math.Max(tyre, Math.Max(spoke, hub));
			double light = Clamp(0.5 - 0.35*dy - 0.2*dx);
			double brush = 0.92 + 0.08*Noise(an*20, rr*8, 64, 16, 541);
			double s;
			if (tyre > 0.5) s = (0.32 + 0.3*light + 0.15*Smooth(0.88, 0.95, rr)*Clamp(-dy))*brush;    // the tyre, its outer flange catching light
			else if (hub > 0.5) s = (0.35 + 0.35*light + 0.25*Smooth(0.09, 0.0, rr))*brush;           // the hub and its bolt
			else s = (0.28 + 0.3*light)*brush;
			double rust = 0.06*Noise(dx*10, dy*10, 32, 32, 542);
			img.Set(x, y, Clamp(s*.95 + rust), Clamp(s*.92), Clamp(s*.9 - rust*.5), Clamp(cov));
		}
		return img;
	}
	// 128x128: handle straight down from the centre, the steel head across the top, curving down to both points
	public static Img Pickaxe()
	{
		const int S = 128; double aa = 1.5/(S/2.0);
		var img = new Img(S, S);
		for (int y = 0; y < S; y++) for (int x = 0; x < S; x++)
		{
			double dx = (x + .5 - S/2.0)/(S/2.0), dy = (y + .5 - S/2.0)/(S/2.0);
			var P = new double[4];   // r, g, b, a, painted back to front with OverP
			// the haft: wood with grain along it, a dark leather wrap near the end
			double hw = 0.055 + 0.012*Clamp((dy + 0.55)/1.5);
			double haft = Smooth(hw + aa, hw, Math.Abs(dx))*Smooth(0.95 + aa, 0.95, dy)*Smooth(-0.6 - aa, -0.6, dy);
			if (haft > 0)
			{
				double round = Math.Sqrt(Clamp(1 - (dx/hw)*(dx/hw)));
				double grain = 0.85 + 0.15*Noise(dx*30, dy*3, 64, 16, 551);
				double s = (0.55 + 0.45*round - 0.2*Clamp(dx/hw))*grain;
				if (dy > 0.5 && dy < 0.88)
				{
					double turn = Mod((int)Math.Floor((dy - dx*0.6)*22), 2) == 0 ? 1 : 0.85;
					OverP(P, .30*s*turn, .19*s*turn, .12*s*turn, haft);
				}
				else OverP(P, .52*s, .34*s, .19*s, haft);
			}
			// the head: steel, thickest at the eye, tapering to points, a bright ground edge along its top
			double hy = -0.62 + 0.30*dx*dx;
			double headW = 0.095*(1 - Math.Abs(dx)/0.97) + 0.012;
			double head = Smooth(headW + aa, headW, Math.Abs(dy - hy))*Smooth(0.97 + aa, 0.97, Math.Abs(dx));
			if (head > 0)
			{
				double t = Clamp((dy - (hy - headW))/(2*headW));                   // 0 top .. 1 bottom
				double brush = 0.93 + 0.07*Noise(dx*60, dy*4, 128, 16, 552);
				double s = (0.78 - 0.45*t + 0.25*Smooth(0.2, 0, t))*brush;
				double glint = 0.35*Math.Exp(-Math.Pow((dx + 0.35)/0.12, 2))*Smooth(0.5, 0.1, t);
				OverP(P, Clamp(s*.9 + glint), Clamp(s*.92 + glint), Clamp(s*.96 + glint), head);
			}
			// the eye's iron collar where head meets haft
			double collar = Smooth(0.085 + aa, 0.085, Math.Abs(dx))*Smooth(0.07 + aa, 0.07, Math.Abs(dy + 0.5));
			if (collar > 0) { double s = 0.42 + 0.25*Clamp(-dx/0.08) + 0.1*Clamp(-(dy + 0.5)/0.07); OverP(P, s*.9, s*.88, s*.86, collar); }
			img.Set(x, y, P[0], P[1], P[2], Clamp(P[3]));
		}
		return img;
	}
	public static Img Chip()           // an angular rock chip, white (tinted)
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 31.5)/32.0, an = Math.Atan2(dy, dx);
			double r = Math.Abs(dx)*0.9 + Math.Abs(dy)*1.2 + 0.15*Math.Sin(an*5 + 1);
			double lit = 0.6 + 0.4*Clamp(-dy - dx*0.5 + 0.3);
			img.Set(x, y, lit, lit, lit, Smooth(0.75, 0.68, r));
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

	// ================================================================ SKINNING: the pelt rolls back over marbled meat
	// Ahead of the cast lies the fur: skin_fur (the coat) with the guard hairs' light tips in skin_fur_hi, added
	// on top. Both are neutral; the addon tints them to a different pelt every cast. At the cast edge the hide
	// rolls up on itself (p_roll_*: the fur side, its shape, its shading and the hide's flesh side, the spiral
	// end), behind it lies the meat it leaves (skin_meat, a marbled ribeye), a pool of blood grows behind the
	// knife from soft blots (p_pool), and the knife saws under the roll (p_knife_wood, p_knife_antler).

	// distance from (x, y) to the segment (x0, y0)-(x1, y1)
	static double SegDist(double x, double y, double x0, double y0, double x1, double y1)
	{
		double vx = x1 - x0, vy = y1 - y0, l2 = vx*vx + vy*vy;
		double t = l2 > 0 ? Clamp(((x - x0)*vx + (y - y0)*vy) / l2) : 0;
		double dx = x - x0 - vx*t, dy = y - y0 - vy*t;
		return Math.Sqrt(dx*dx + dy*dy);
	}
	// A hair: a stroke along the polyline (xs, ys), w pixels wide with round ends and 1px antialiasing, painted
	// over img at brightness lum and opacity a. The image wraps left-right (and top-bottom with wrapY).
	static void Stroke(Img img, double[] xs, double[] ys, double w, double lum, double a, bool wrapY)
	{
		double minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
		for (int i = 0; i < xs.Length; i++) { minX = Math.Min(minX, xs[i]); maxX = Math.Max(maxX, xs[i]); minY = Math.Min(minY, ys[i]); maxY = Math.Max(maxY, ys[i]); }
		double pad = w/2 + 1.5, rr = Math.Max(w/2, 0.5), k = Math.Min(1, w);
		int x0 = (int)Math.Floor(minX - pad), x1 = (int)Math.Ceiling(maxX + pad), y0 = (int)Math.Floor(minY - pad), y1 = (int)Math.Ceiling(maxY + pad);
		for (int y = y0; y <= y1; y++)
		{
			int yy = wrapY ? Mod(y, img.H) : y;
			if (yy < 0 || yy >= img.H) continue;
			for (int x = x0; x <= x1; x++)
			{
				double d = 1e9;
				for (int i = 0; i + 1 < xs.Length; i++) d = Math.Min(d, SegDist(x + 0.5, y + 0.5, xs[i], ys[i], xs[i+1], ys[i+1]));
				double cov = Clamp(rr + 0.5 - d) * k * a;
				if (cov <= 0) continue;
				int j = yy*img.W + Mod(x, img.W);
				img.R[j] = Lerp(img.R[j], lum, cov); img.G[j] = Lerp(img.G[j], lum, cov); img.B[j] = Lerp(img.B[j], lum, cov);
				img.A[j] = img.A[j] + cov*(1 - img.A[j]);
			}
		}
	}
	// Points along a slightly bent hair from (x, y), between fractions t0 and t1 of its length.
	static void HairPts(double x, double y, double ang, double len, double bend, double t0, double t1, out double[] xs, out double[] ys)
	{
		double ex = x + Math.Cos(ang)*len, ey = y + Math.Sin(ang)*len;
		double cx = (x + ex)/2 - Math.Sin(ang)*bend, cy = (y + ey)/2 + Math.Cos(ang)*bend;
		xs = new double[4]; ys = new double[4];
		for (int i = 0; i < 4; i++)
		{
			double t = Lerp(t0, t1, i/3.0), it = 1 - t;
			xs[i] = it*it*x + 2*it*t*cx + t*t*ex; ys[i] = it*it*y + 2*it*t*cy + t*t*ey;
		}
	}
	static double Rnd(Random r, double a, double b) { return a + r.NextDouble()*(b - a); }

	// Fur, in brightness relative to the coat colour (1 = the coat colour the addon tints it to): dark roots,
	// the coat, and long guard hairs whose dark roots go in `coat` and whose light tips go in `tips` (white on
	// clear, added on top and tinted to the tips' colour). hp is pixels per bar height; ang gives the hairs'
	// direction at a pixel. Three coats: dense short undercoat, the main coat, the guard hairs.
	static void PaintFur(Img coat, Img tips, double hp, Func<double, double, double> ang, Random rnd, bool wrapY)
	{
		double area = coat.W * coat.H / (hp*hp);
		// soft mottling, so the coat isn't one flat tone
		for (int n = 0; n < (int)(area*6); n++)
		{
			double cx = Rnd(rnd, 0, coat.W), cy = Rnd(rnd, 0, coat.H), r = hp*Rnd(rnd, 0.15, 0.45), c = rnd.NextDouble() < 0.5 ? 0.35 : 1.0;
			for (int y = (int)(cy - r); y <= (int)(cy + r); y++)
			{
				int yy = wrapY ? Mod(y, coat.H) : y;
				if (yy < 0 || yy >= coat.H) continue;
				for (int x = (int)(cx - r); x <= (int)(cx + r); x++)
				{
					double d = Math.Sqrt((x - cx)*(x - cx) + (y - cy)*(y - cy)), t = 0.28*Clamp(1 - d/r);
					int j = yy*coat.W + Mod(x, coat.W);
					coat.R[j] = Lerp(coat.R[j], c, t); coat.G[j] = coat.R[j]; coat.B[j] = coat.R[j];
				}
			}
		}
		double[] xs, ys;
		// undercoat: short dense hairs at the roots' colour
		for (int n = 0; n < (int)(area*1100); n++)
		{
			double x = Rnd(rnd, 0, coat.W), y = Rnd(rnd, -0.05*hp, coat.H + 0.05*hp), a = ang(x, y) + Rnd(rnd, -0.12, 0.12);
			HairPts(x, y, a, hp*Rnd(rnd, 0.05, 0.09), hp*Rnd(rnd, -0.025, 0.025), 0, 1, out xs, out ys);
			Stroke(coat, xs, ys, Math.Max(0.45, hp*0.02), rnd.NextDouble() < 0.5 ? 0.35 : 0.52, 0.75, wrapY);
		}
		// the main coat
		for (int n = 0; n < (int)(area*800); n++)
		{
			double x = Rnd(rnd, 0, coat.W), y = Rnd(rnd, -0.05*hp, coat.H + 0.05*hp), a = ang(x, y) + Rnd(rnd, -0.12, 0.12);
			HairPts(x, y, a, hp*Rnd(rnd, 0.08, 0.14), hp*Rnd(rnd, -0.025, 0.025), 0, 1, out xs, out ys);
			double pick = rnd.NextDouble();
			Stroke(coat, xs, ys, Math.Max(0.45, hp*0.016), pick < 0.34 ? 0.68 : 1.0, 0.7, wrapY);
		}
		// guard hairs: dark root half in the coat, light tip half (and a brighter tip end) in the tips
		for (int n = 0; n < (int)(area*380); n++)
		{
			double x = Rnd(rnd, 0, coat.W), y = Rnd(rnd, -0.05*hp, coat.H + 0.05*hp), a = ang(x, y) + Rnd(rnd, -0.12, 0.12);
			double len = hp*Rnd(rnd, 0.12, 0.22), bend = hp*Rnd(rnd, -0.025, 0.025), w = Math.Max(0.4, hp*0.012);
			HairPts(x, y, a, len, bend, 0, 0.5, out xs, out ys); Stroke(coat, xs, ys, w, 0.35, 0.75, wrapY);
			HairPts(x, y, a, len, bend, 0.5, 1, out xs, out ys); Stroke(tips, xs, ys, w, 1, 0.7, wrapY);
			HairPts(x, y, a, len, bend, 0.82, 1, out xs, out ys); Stroke(tips, xs, ys, w*0.8, 1, 0.55, wrapY);
		}
	}
	static Img furTips;
	public static Img SkinFur()        // the coat ahead of the cast: hairs flow toward the tail (left) and fan out top and bottom
	{
		var coat = new Img(W, H); furTips = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double v = (y + 0.5)/H, l = v < 0.5 ? Lerp(0.76, 0.68, v*2) : Lerp(0.68, 0.52, (v - 0.5)*2);
			coat.Set(x, y, l, l, l, 1); furTips.Set(x, y, 1, 1, 1, 0);
		}
		PaintFur(coat, furTips, H, (x, y) => Math.PI - (y/H - 0.5)*1.0 + 0.4*Fbm(x/W, y/H, 27, 3, 1, 703), new Random(701), false);
		// a soft sheen where the light catches the coat, and the body rounding off top and bottom
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double v = (y + 0.5)/H, band = 0.22*Math.Exp(-Math.Pow((v - 0.3)/0.12, 2));
			double shade = v < 0.25 ? 0.32*(1 - v/0.25) : v > 0.75 ? 0.4*(v - 0.75)/0.25 : 0;
			int j = y*W + x;
			double k = (1 + band)*(1 - shade);
			coat.R[j] = Clamp(coat.R[j]*k); coat.G[j] = coat.R[j]; coat.B[j] = coat.R[j];
			furTips.A[j] = Clamp(furTips.A[j]*k);
		}
		return coat;
	}
	public static Img SkinFurHi() { if (furTips == null) SkinFur(); return furTips; }   // ADD: the guard hairs' light tips

	// The roll: its side is fur wrapped round (p_roll_fur, tiling top to bottom so the addon can turn it as it
	// rolls), cut to shape by p_roll_mask (a rectangle with a rounded bottom) and shaded by p_roll_shade (the
	// hide's pale flesh side along the left, cylinder light and shade). The top end (p_roll_end) shows the hide
	// rolled on itself; p_roll_spiral is the fur between its layers, tinted with the pelt.
	public static Img RollFur()        // 64x128: hairs running down the roll
	{
		var img = new Img(64, 128); var tips = new Img(64, 128);
		for (int i = 0; i < img.R.Length; i++) { img.R[i] = img.G[i] = img.B[i] = 0.7; img.A[i] = 1; tips.R[i] = tips.G[i] = tips.B[i] = 1; }
		PaintFur(img, tips, 110, (x, y) => Math.PI/2 + 0.25 + 0.35*Fbm(x/64.0, y/128.0, 2, 5, 1, 711), new Random(712), true);
		for (int i = 0; i < img.R.Length; i++)   // the tips are part of this one texture
		{
			double l = Lerp(img.R[i], 1, tips.A[i]*0.6);
			img.R[i] = img.G[i] = img.B[i] = l;
		}
		return img;
	}
	const double ROLL_CAP = 0.07;      // the rounded bottom's share of the roll's height
	static double RollShape(double u, double v)
	{
		double ax = Math.Abs(u - 0.5)/0.5;
		if (v <= 1 - ROLL_CAP) return Smooth(1.0, 0.94, ax);
		double dy = (v - (1 - ROLL_CAP))/ROLL_CAP;
		return Smooth(1.0, 0.94, Math.Sqrt(ax*ax + dy*dy));
	}
	public static Img RollMask()
	{
		var img = new Img(64, 128);
		for (int y = 0; y < 128; y++) for (int x = 0; x < 64; x++) img.Set(x, y, 1, 1, 1, RollShape((x + 0.5)/64, (y + 0.5)/128));
		return img;
	}
	static readonly double[] HIDE = { 216/255.0, 178/255.0, 150/255.0 }, HIDE_D = { 168/255.0, 120/255.0, 96/255.0 };
	// a premultiplied "over"
	static void Over(ref double r, ref double g, ref double b, ref double a, double cr, double cg, double cb, double ca)
	{ r = cr*ca + r*(1 - ca); g = cg*ca + g*(1 - ca); b = cb*ca + b*(1 - ca); a = ca + a*(1 - ca); }
	public static Img RollShade()
	{
		var img = new Img(64, 128);
		// cylinder light: dark on the left edge, a warm highlight, clear, then deep shade on the far side
		double[] su = { 0, 0.28, 0.45, 0.8, 1 }, sa = { 0.35, 0.12, 0, 0.35, 0.6 };
		for (int y = 0; y < 128; y++) for (int x = 0; x < 64; x++)
		{
			double u = (x + 0.5)/64, v = (y + 0.5)/128, r = 0, g = 0, b = 0, a = 0;
			// the hide's flesh side showing on the curl, along the side that faces the meat
			double t = u/0.3;
			if (t < 1)
			{
				double k = Clamp(t/0.45);
				double hr = Lerp(HIDE_D[0], HIDE[0], k), hg = Lerp(HIDE_D[1], HIDE[1], k), hb = Lerp(HIDE_D[2], HIDE[2], k);
				double ha = t < 0.45 ? Lerp(0.95, 0.85, t/0.45) : Lerp(0.85, 0, (t - 0.45)/0.55);
				Over(ref r, ref g, ref b, ref a, hr, hg, hb, ha);
			}
			int s = 1; while (s < su.Length - 1 && u > su[s]) s++;
			double ca = Lerp(sa[s-1], sa[s], Clamp((u - su[s-1])/(su[s] - su[s-1])));
			bool warm = u > 0.12 && u < 0.45;
			Over(ref r, ref g, ref b, ref a, warm ? 1 : 0, warm ? 0.94 : 0, warm ? 0.84 : 0, ca);
			if (v > 0.7) Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.4*(v - 0.7)/0.3);
			double shape = RollShape(u, v);
			if (a > 0) img.Set(x, y, r/a, g/a, b/a, a*shape);
		}
		return img;
	}
	// The end is drawn squashed to an ellipse a third as tall as it is wide; distances for its strokes are
	// measured on screen (y times 0.3), the way they look there.
	public static Img RollEnd()
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double ux = (x + 0.5 - 32)/32, uy = (y + 0.5 - 32)/32, d = Math.Sqrt(ux*ux + uy*uy);
			double t = Clamp(Math.Sqrt((ux + 0.2)*(ux + 0.2) + (uy + 0.3)*(uy + 0.3))/1.15);
			double r, g, b;
			if (t < 0.75) { double k = t/0.75; r = Lerp(Lerp(HIDE[0], 1, 0.2), HIDE[0], k); g = Lerp(Lerp(HIDE[1], 0.94, 0.2), HIDE[1], k); b = Lerp(Lerp(HIDE[2], 0.88, 0.2), HIDE[2], k); }
			else { double k = (t - 0.75)/0.25; r = Lerp(HIDE[0], HIDE_D[0], k); g = Lerp(HIDE[1], HIDE_D[1], k); b = Lerp(HIDE[2], HIDE_D[2], k); }
			double core = 0.7*Clamp(1 - d/0.3);
			r = Lerp(r, 20/255.0, core); g = Lerp(g, 10/255.0, core); b = Lerp(b, 6/255.0, core);
			double ring = 0.3*Clamp(1 - Math.Abs(d - 0.97)*32/1.5);
			r *= 1 - ring; g *= 1 - ring; b *= 1 - ring;
			img.Set(x, y, r, g, b, Smooth(1.0, 0.96, d));
		}
		return img;
	}
	public static Img RollSpiral()     // white (tinted to the pelt): the fur showing between the rolled hide's layers
	{
		var img = new Img(64, 64);
		var px = new List<double>(); var py = new List<double>();
		double turns = 2.6, ang0 = 0.7;
		for (double a = 0; a <= Math.PI*2*turns; a += 0.06)
		{
			double rr = 1 - a/(Math.PI*2*(turns + 0.35));
			px.Add(Math.Cos(a + ang0)*rr); py.Add(Math.Sin(a + ang0)*rr*0.3);
		}
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double ux = (x + 0.5 - 32)/32, uy = (y + 0.5 - 32)/32, sx = ux, sy = uy*0.3, d = 1e9;
			for (int i = 0; i + 1 < px.Count; i++) d = Math.Min(d, SegDist(sx, sy, px[i], py[i], px[i+1], py[i+1]));
			double px1 = 1/32.0*0.3;                                   // one texture pixel, measured on screen
			double outer = 0.85*Clamp((0.065 - d)/px1 + 0.5), inner = 0.7*Clamp((0.025 - d)/px1 + 0.5);
			double r = 0, g = 0, b = 0, a = 0;
			Over(ref r, ref g, ref b, ref a, 1, 1, 1, outer);
			Over(ref r, ref g, ref b, ref a, 0.35, 0.35, 0.35, inner);
			a *= Smooth(1.0, 0.96, Math.Sqrt(ux*ux + uy*uy));
			if (a > 0) img.Set(x, y, r/Math.Max(a, 1e-6), g/Math.Max(a, 1e-6), b/Math.Max(a, 1e-6), a);
		}
		return img;
	}

	// The meat behind the roll, like a marbled ribeye: deep wine-red muscle laced with fine creamy fat, larger
	// swirling fat seams that split it into regions, and a waxy, pink-tinged fat cap along the top and bottom.
	public static Img SkinMeat()
	{
		var img = new Img(W, H);
		double[] MD = { 78, 6, 18 }, M = { 142, 18, 32 }, ML = { 186, 44, 52 }, FC = { 246, 232, 222 }, FP = { 232, 196, 186 };
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (x + 0.5)/W, v = (y + 0.5)/H;
			// swirl: warp the coordinates so seams and lace curl around like a ribeye's eye
			double wu = u + 0.45/8*Fbm(u, v, 6, 1, 3, 801)*1.4, wv = v + 0.3*Fbm(u + 0.37, v, 6, 1, 3, 802)*1.4;
			// fat cap along the top and bottom, with a wavy inner edge
			double top = 0.135 + 0.06*Fbm(u, 0.1, 13, 1, 1, 803) + 0.03*Fbm(u, 0.3, 40, 1, 1, 804);
			double bot = 0.865 - 0.06*Fbm(u, 0.6, 13, 1, 1, 805) - 0.03*Fbm(u, 0.8, 40, 1, 1, 806);
			double cap = Math.Max(1 - Smooth(top - 0.04, top + 0.03, v), Smooth(bot - 0.03, bot + 0.04, v));
			// large seams of fat between muscle regions, soft and uneven in width
			double seamW = 0.045 + 0.035*Fbm(wu, wv, 16, 2, 1, 807);
			double seam = 1 - Smooth(seamW*0.35, seamW, Math.Abs(Fbm(wu, wv, 9, 2, 3, 808)*1.4));
			// fine marbling, denser in some regions: fat patches, a dense spray of specks, a broken web of threads
			double dens = Clamp(0.5 + 0.6*Fbm(u, v, 6, 2, 2, 809)*1.4);
			double patch = Smooth(0.3 - 0.12*dens, 0.45 - 0.12*dens, Fbm(wu, wv, 24, 4, 3, 810)*1.4);
			double speck = Smooth(0.18 - 0.2*dens, 0.32 - 0.2*dens, Fbm(wu, wv, 64, 8, 2, 811)*1.4);
			double web = (1 - Smooth(0.01, 0.045, Math.Abs(Fbm(wu + 0.2, wv, 40, 5, 2, 812)*1.4))) * Smooth(0.05, 0.3, Fbm(wu, wv, 56, 7, 2, 813)*1.4);
			double fine = Math.Max(patch*0.95, Math.Max(speck*0.9, web*0.75)) * (0.35 + 0.65*dens);
			// muscle: wine-red, darker in the deep middle of each region, lighter toward the fat
			double tone = Clamp(0.5 + 0.55*Fbm(wu, wv, 18, 3, 3, 814)*1.4 + 0.25*seam);
			double[] m = new double[3];
			for (int c = 0; c < 3; c++) m[c] = tone < 0.5 ? Lerp(MD[c], M[c], tone*2) : Lerp(M[c], ML[c], (tone - 0.5)*2);
			// fat: creamy white with a pink blush; thin fat is translucent and the red shows through it
			double wax = 0.5 + 0.5*Fbm(u, v, 32, 4, 1, 815);
			double thin = Math.Max(fine*0.3, seam*0.12), fatW = Math.Max(cap, Math.Max(seam*0.95, fine*0.88)), blush = (1 - cap)*thin;
			double band = Smooth(0, 0.5, cap)*(1 - Smooth(0.5, 1, cap));   // the cap meets the meat in a pink band
			double sh = (1 - 0.18*Math.Pow(Math.Abs(v - 0.5)*2, 3)) * (0.92 + 0.08*Fbm(u + 0.5, v, 9, 1, 1, 816));
			double[] o = new double[3]; double[] pinkBand = { 214, 132, 132 };
			for (int c = 0; c < 3; c++)
			{
				double f = Lerp(FC[c], FP[c], wax*0.7);
				f = Lerp(f, m[c] + (c == 0 ? 70 : 60), blush);
				double col = Lerp(m[c], f, fatW);
				col = Lerp(col, pinkBand[c], band*0.5);
				o[c] = Clamp(col*sh/255);
			}
			img.Set(x, y, o[0], o[1], o[2], 1);
		}
		return img;
	}

	// Pool blots, 4 cells of 64x64 (white, tinted): a round lobe with a few rounded bulges. The addon lays them
	// down behind the knife in three passes (a dark seep, a brighter rim, the darker body a little smaller), so
	// overlapping blots merge into one puddle.
	public static Img PoolBlots()
	{
		var img = new Img(256, 64);
		var rnd = new Random(851);
		for (int c = 0; c < 4; c++)
		{
			int n = 3 + rnd.Next(3);
			var cx = new List<double> { 0 }; var cy = new List<double> { 0 }; var cr = new List<double> { 0.3 };
			for (int i = 0; i < n; i++) { cx.Add(Rnd(rnd, -0.85, 0.85)*0.3); cy.Add(Rnd(rnd, -0.7, 0.7)*0.3); cr.Add(Rnd(rnd, 0.4, 0.6)*0.3); }
			for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
			{
				double ux = (x + 0.5)/64 - 0.5, uy = (y + 0.5)/64 - 0.5, a = 0;
				for (int i = 0; i < cx.Count; i++)
				{
					double d = Math.Sqrt((ux - cx[i])*(ux - cx[i]) + (uy - cy[i])*(uy - cy[i]));
					a = Math.Max(a, Clamp((cr[i] - d)*64/1.3 + 0.5));
				}
				img.Set(c*64 + x, y, 1, 1, 1, a);
			}
		}
		return img;
	}

	// ---------------------------------------------------------------- the skinning knife
	// Painted upright, as it stands against the pelt roll: the tip at the bottom, the blade running straight up
	// with its curved edge facing right (against the roll), then the bolster and the handle above. 128x256 at
	// 120 px per bar height; the tip sits 0.35 bar heights from the left and 2.0 from the top. A soft shadow falls
	// down and to the right.
	public const double KNIFE_PX = 120, KNIFE_TIPX = 0.35, KNIFE_TIPY = 2.0, KNIFE_ANG = Math.PI/2;
	static List<double[]> Bez(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3, int n)
	{
		var p = new List<double[]>();
		for (int i = 0; i <= n; i++)
		{
			double t = (double)i/n, it = 1 - t;
			p.Add(new[] { it*it*it*x0 + 3*it*it*t*x1 + 3*it*t*t*x2 + t*t*t*x3, it*it*it*y0 + 3*it*it*t*y1 + 3*it*t*t*y2 + t*t*t*y3 });
		}
		return p;
	}
	static List<double[]> Quad(double x0, double y0, double x1, double y1, double x2, double y2, int n)
	{ return Bez(x0, y0, x0 + (x1 - x0)*2/3, y0 + (y1 - y0)*2/3, x2 + (x1 - x2)*2/3, y2 + (y1 - y2)*2/3, x2, y2, n); }
	static bool InPoly(List<double[]> p, double x, double y)
	{
		bool c = false;
		for (int i = 0, j = p.Count - 1; i < p.Count; j = i++)
			if (((p[i][1] > y) != (p[j][1] > y)) && (x < (p[j][0] - p[i][0])*(y - p[i][1])/(p[j][1] - p[i][1]) + p[i][0])) c = !c;
		return c;
	}
	static double LineDist(List<double[]> p, double x, double y, bool closed)
	{
		double d = 1e9;
		for (int i = 0; i + 1 < p.Count; i++) d = Math.Min(d, SegDist(x, y, p[i][0], p[i][1], p[i+1][0], p[i+1][1]));
		if (closed) d = Math.Min(d, SegDist(x, y, p[p.Count-1][0], p[p.Count-1][1], p[0][0], p[0][1]));
		return d;
	}
	static List<double[]> RoundRect(double x, double y, double w, double h, double r)
	{
		var p = new List<double[]>();
		double[][] c = { new[]{ x + w - r, y + r, -Math.PI/2 }, new[]{ x + w - r, y + h - r, 0 }, new[]{ x + r, y + h - r, Math.PI/2 }, new[]{ x + r, y + r, Math.PI } };
		foreach (var k in c) for (int i = 0; i <= 6; i++) { double a = k[2] + Math.PI/2*i/6; p.Add(new[] { k[0] + Math.Cos(a)*r, k[1] + Math.Sin(a)*r }); }
		return p;
	}
	static double[] Stops(double t, double[] at, double[][] cols)
	{
		t = Clamp(t);
		for (int i = 1; i < at.Length; i++)
			if (t <= at[i]) { double k = (t - at[i-1])/(at[i] - at[i-1]); return new[] { Lerp(cols[i-1][0], cols[i][0], k), Lerp(cols[i-1][1], cols[i][1], k), Lerp(cols[i-1][2], cols[i][2], k) }; }
		return cols[cols.Length - 1];
	}
	static double[] Hex(int rgb) { return new[] { ((rgb >> 16) & 255)/255.0, ((rgb >> 8) & 255)/255.0, (rgb & 255)/255.0 }; }
	static double Ink(double d, double w) { return Clamp((w/2 - d)*KNIFE_PX + 0.5); }   // coverage of a line w wide at distance d
	public static Img Knife(bool antler)
	{
		const int SW = 128, SH = 256; const double PX = KNIFE_PX;
		double L = 1.05, bw = 0.27, hc = bw*0.16, gw = bw*0.3, hl = 0.76, hh = bw*0.44, hx0 = L + gw, hx1 = L + gw + hl;
		var blade = Bez(0, 0, L*0.05, bw*0.55, L*0.45, bw*0.98, L, bw*0.62, 28);
		blade.Add(new[] { L, -bw*0.3 });
		blade.AddRange(Quad(L, -bw*0.3, L*0.45, bw*0.1, 0, 0, 18));
		var belly = Bez(0, 0, L*0.05, bw*0.55, L*0.45, bw*0.98, L, bw*0.62, 40);
		var spine = Quad(L, -bw*0.28, L*0.45, bw*0.1, L*0.04, bw*0.01, 18);
		var handle = Bez(hx0, hc - hh, hx0 + hl*0.4, hc - hh*1.08, hx1 - hl*0.2, hc - hh*1.15, hx1 - hh*0.5, hc - hh*1.05, 20);
		handle.AddRange(Quad(hx1 - hh*0.5, hc - hh*1.05, hx1 + hh*0.35, hc, hx1 - hh*0.5, hc + hh, 10));
		handle.AddRange(Bez(hx1 - hh*0.5, hc + hh, hx1 - hl*0.25, hc + hh*1.05, hx0 + hl*0.35, hc + hh*0.95, hx0, hc + hh, 20));
		var bolster = RoundRect(L - gw*0.05, hc - hh*1.18, gw*1.1, hh*2.36, gw*0.35);

		var rnd = new Random(antler ? 871 : 861);
		var smears = new List<double[]>();      // u, v, rx, ry, a: blood toward the tip
		for (int i = 0; i < 6; i++) smears.Add(new[] { Rnd(rnd, 0.02, 0.42), Rnd(rnd, -0.1, 0.55), Rnd(rnd, 0.05, 0.14), Rnd(rnd, 0.08, 0.22), Rnd(rnd, 0.35, 0.7) });
		var grain = new List<double[]>();       // v, amp, f, ph
		for (int i = 0; i < 7; i++) grain.Add(new[] { Rnd(rnd, -0.8, 0.8), Rnd(rnd, 0.03, 0.1), Rnd(rnd, 5, 11), Rnd(rnd, 0, 6.283) });
		var knobs = new List<double[]>();       // u, v, r
		for (int i = 0; i < 9; i++) knobs.Add(new[] { Rnd(rnd, 0.05, 0.95), Rnd(rnd, -0.6, 0.6), Rnd(rnd, 0.04, 0.09) });

		double ca = Math.Cos(KNIFE_ANG), sa = Math.Sin(KNIFE_ANG);
		var img = new Img(SW, SH);
		double[] hAt = { 0, 0.4, 1 }; double[][] hCol = antler ? new[] { Hex(0xe6dac4), Hex(0xb7a385), Hex(0x5d4c38) } : new[] { Hex(0x9a6a40), Hex(0x6a4322), Hex(0x2a160a) };
		double[] bAt = { 0, 0.35, 0.7, 1 };
		double[][] bCol = antler ? new[] { Hex(0xf2f5f8), Hex(0xa9b2bb), Hex(0x5c646d), Hex(0x2a2f35) } : new[] { Hex(0xfbe6a8), Hex(0xc79a44), Hex(0x7a5418), Hex(0x3e2a0a) };
		double[][] pin = antler ? new[] { Hex(0xffffff), Hex(0xa8b0b8), Hex(0x4a5058) } : new[] { Hex(0xfff0b8), Hex(0xb88a36), Hex(0x5a3e12) };
		double[] sAt = { 0, 0.3, 0.55, 1 }; double[][] sCol = { Hex(0xe4e9ee), Hex(0xa7b0b9), Hex(0x7b858f), Hex(0x5d6670) };
		for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++)
		{
			int hH = 0, hB = 0, hK = 0;
			for (int sy = 0; sy < 4; sy++) for (int sx = 0; sx < 4; sx++)
			{
				double wx = (x + (sx + 0.5)/4)/PX - KNIFE_TIPX, wy = (y + (sy + 0.5)/4)/PX - KNIFE_TIPY;
				double qx = ca*wx - sa*wy, qy = sa*wx + ca*wy;
				if (qx > hx0 - 0.02 && InPoly(handle, qx, qy)) hH++;
				if (qx > L - 0.1 && qx < L + gw*1.2 && InPoly(bolster, qx, qy)) hB++;
				if (qx < L + 0.02 && InPoly(blade, qx, qy)) hK++;
			}
			double cx = (x + 0.5)/PX - KNIFE_TIPX, cy = (y + 0.5)/PX - KNIFE_TIPY;
			double lx = ca*cx - sa*cy, ly = sa*cx + ca*cy;
			double r = 0, g = 0, b = 0, a = 0;
			if (lx > hx0 - 0.1 && lx < hx1 + 0.1 && Math.Abs(ly - hc) < hh*1.5)
			{
				// handle: wood with grain, or pitted, ridged antler; a highlight along the top, two pins
				if (hH > 0)
				{
					var c = Stops((ly - (hc - hh))/(2*hh), hAt, hCol);
					double uu = (lx - hx0)/hl;
					if (antler)
						foreach (var k in knobs)
						{
							double kx = Lerp(hx0, hx1, k[0]), ky = hc + k[1]*hh, kr = k[2], d = Math.Sqrt((lx - kx + kr*0.3)*(lx - kx + kr*0.3) + (ly - ky + kr*0.3)*(ly - ky + kr*0.3))/kr;
							if (d < 1) { double t = d < 0.6 ? 0.35*(1 - d/0.6) : 0; double dk = d >= 0.6 ? 0.25*(1 - (d - 0.6)/0.4) : 0; for (int q = 0; q < 3; q++) c[q] = Lerp(Lerp(c[q], 1.0, t), 0.35, dk); }
						}
					foreach (var gr in grain)
					{
						double gy = hc + gr[0]*hh*(antler ? 0.8 : 1) + Math.Sin(uu*gr[2] + gr[3])*gr[1]*hh;
						double k = Ink(Math.Abs(ly - gy), 0.01) * (antler ? 0.35 : 0.25 + gr[1]*2);
						double[] gc = antler ? new[] { 70/255.0, 52/255.0, 34/255.0 } : new[] { 30/255.0, 14/255.0, 4/255.0 };
						for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], gc[q], k);
					}
					if (!antler)
					{
						double wx0 = Lerp(hx0, hx1, 0.55), wy0 = hc - hh*0.3, wd = Math.Sqrt((lx - wx0)*(lx - wx0) + (ly - wy0)*(ly - wy0))/(hl*0.35);
						double k = 0.12*Clamp(1 - wd); c[0] = Lerp(c[0], 1, k); c[1] = Lerp(c[1], 0.88, k); c[2] = Lerp(c[2], 0.75, k);
					}
					double top = 0.28*Clamp(1 - (ly - (hc - hh))/(hh*0.6));
					c[0] = Lerp(c[0], 1, top); c[1] = Lerp(c[1], 0.96, top); c[2] = Lerp(c[2], 0.88, top);
					Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], hH/16.0);
				}
				foreach (double pu in new[] { 0.28, 0.72 })
				{
					double px0 = Lerp(hx0, hx1, pu), pr = bw*0.075, d = Math.Sqrt((lx - px0)*(lx - px0) + (ly - hc)*(ly - hc));
					if (d < pr + 0.01)
					{
						double dl = Math.Sqrt((lx - px0 + pr*0.35)*(lx - px0 + pr*0.35) + (ly - hc + pr*0.35)*(ly - hc + pr*0.35))/pr;
						var pc = Stops(dl, new[] { 0, 0.55, 1 }, pin);
						Over(ref r, ref g, ref b, ref a, pc[0], pc[1], pc[2], Clamp((pr - d)*PX + 0.5));
					}
				}
				Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.3*Ink(LineDist(handle, lx, ly, true), 0.012));
			}
			// bolster: brass or steel
			if (hB > 0)
			{
				var c = Stops((ly - (hc - hh*1.18))/(hh*2.36), bAt, bCol);
				Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], hB/16.0);
			}
			if (lx > L - 0.1 && lx < L + gw*1.2) Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.3*Ink(LineDist(bolster, lx, ly, true), 0.012));
			// blade: brushed steel, a brighter ground bevel along the edge, blood toward the tip
			if (lx < L + 0.05)
			{
				double dBelly = LineDist(belly, lx, ly, false);
				if (hK > 0)
				{
					var c = Stops((ly + bw*0.35)/(bw*1.25), sAt, sCol);
					double brush = 1 + 0.035*Noise(lx*30, ly*400, 64, 512, 881);   // fine lengthwise brushing
					for (int q = 0; q < 3; q++) c[q] *= brush;
					double bev = 0.55*Clamp((bw*0.25 - dBelly)*PX + 0.5);
					c[0] = Lerp(c[0], 214/255.0, bev); c[1] = Lerp(c[1], 224/255.0, bev); c[2] = Lerp(c[2], 232/255.0, bev);
					double line = 0.35*Ink(LineDist(belly, lx, ly + bw*0.22, false), 0.012);
					c[0] = Lerp(c[0], 70/255.0, line); c[1] = Lerp(c[1], 78/255.0, line); c[2] = Lerp(c[2], 88/255.0, line);
					foreach (var sm in smears)
					{
						double al = sm[4]*(1 - sm[0]*1.6);
						if (al <= 0) continue;
						double ex = (lx - L*sm[0])/(L*sm[2]), ey = (ly - bw*sm[1])/(bw*sm[3]*2), t = Math.Sqrt(ex*ex + ey*ey);
						if (t >= 1) continue;
						double k = t < 0.7 ? Lerp(al, al*0.6, t/0.7) : Lerp(al*0.6, 0, (t - 0.7)/0.3);
						c[0] = Lerp(c[0], t < 0.7 ? 118/255.0 : 96/255.0, k); c[1] = Lerp(c[1], 8/255.0, k); c[2] = Lerp(c[2], 12/255.0, k);
					}
					Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], hK/16.0);
				}
				Over(ref r, ref g, ref b, ref a, 1, 1, 1, 0.85*Ink(dBelly, 0.01));                              // the sharp edge
				Over(ref r, ref g, ref b, ref a, 1, 1, 1, 0.4*Ink(LineDist(spine, lx, ly, false), 0.012));     // spine highlight
				Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.28*Ink(LineDist(blade, lx, ly, true), 0.012));     // outline
			}
			if (a > 0) img.Set(x, y, r/a, g/a, b/a, a);
		}
		// one soft shadow under the whole knife, down and to the right
		var sh = new double[SW*SH];
		for (int i = 0; i < sh.Length; i++) sh[i] = img.A[i];
		for (int pass = 0; pass < 3; pass++) sh = BoxBlur(sh, SW, SH, 8);
		int ox = (int)Math.Round(0.05*PX), oy = (int)Math.Round(0.08*PX);
		for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++)
		{
			int sx = x - ox, sy = y - oy;
			double s = (sx >= 0 && sy >= 0) ? 0.45*sh[sy*SW + sx] : 0;
			int i = y*SW + x;
			double ka = img.A[i], oa = ka + s*(1 - ka);
			if (oa <= 0) continue;
			img.R[i] = img.R[i]*ka/oa; img.G[i] = img.G[i]*ka/oa; img.B[i] = img.B[i]*ka/oa; img.A[i] = oa;
		}
		return img;
	}
	// ================================================================ BLACKSMITHING and SMELTING: hot metal, the hammer, the ladle
	// Iron heat colours (blacksmithing): cold iron -> dull red -> orange -> yellow -> white.
	static readonly double[][] IRON_HEAT = { S(0, 42, 34, 32), S(0.22, 104, 20, 10), S(0.45, 190, 46, 12), S(0.66, 245, 118, 28), S(0.85, 255, 196, 84), S(1.05, 255, 246, 214) };
	// Molten steel (smelting): cooled crust -> dull red -> orange -> pale yellow; the hottest stays short of white so text reads.
	static readonly double[][] MELT_HEAT = { S(0, 52, 50, 56), S(0.16, 84, 38, 26), S(0.34, 165, 42, 14), S(0.52, 228, 92, 18), S(0.72, 255, 160, 44), S(0.88, 255, 208, 104), S(1, 255, 228, 150) };
	static double[] HeatCol(double[][] ramp, double t)
	{
		double lo = ramp[0][0], hi = ramp[ramp.Length-1][0];
		var c = Ramp((t - lo)/(hi - lo), Rescale(ramp, lo, hi));
		return new[] { c[0]/255, c[1]/255, c[2]/255 };
	}
	static double[][] Rescale(double[][] ramp, double lo, double hi)
	{
		var o = new double[ramp.Length][];
		for (int i = 0; i < ramp.Length; i++) o[i] = new[] { (ramp[i][0] - lo)/(hi - lo), ramp[i][1], ramp[i][2], ramp[i][3] };
		return o;
	}

	// A bar of iron at a heat, as the concept (blacksmithing.js drawMetal): a few dark scale flecks (about nine per
	// bar height square, fading as it gets hotter), lit along the top, darker underneath.
	static Img IronBar(double heat, int seed)
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (x + 0.5)/W, v = (y + 0.5)/H;
			double h = heat + 0.07*Fbm(u, v, 12, 1, 3, seed);
			double[] c = HeatCol(IRON_HEAT, h);
			double f1, f2; int cell;
			Voronoi(u, v, 24, 3, seed + 2, out f1, out f2, out cell);   // cells about a third of a bar height
			double r = 0.12 + 0.2*Hash(cell, 4, seed);
			double fleck = Smooth(r, r*0.6, f1) * (0.25 + 0.35*Hash(cell, 5, seed));
			double fa = fleck * Clamp(1.15 - h);
			for (int k = 0; k < 3; k++) c[k] = Lerp(c[k], new[] { 28/255.0, 10/255.0, 6/255.0 }[k], fa);
			double top = 0.16*Clamp(1 - v/0.18), dark = v > 0.7 ? 0.08 + 0.42*(v - 0.7)/0.3 : 0.08*Smooth(0.18, 0.7, v);
			for (int k = 0; k < 3; k++) c[k] = Clamp(Lerp(c[k], 1, top)*(1 - dark));
			img.Set(x, y, c[0], c[1], c[2], 1);
		}
		return img;
	}
	// The concept's heat runs .2 at the start of a cast to .6 at its end (base = .2 + .4p): the fill is the iron at .2,
	// with the iron at .6 laid over it, more opaque as the cast goes on. The cast edge's extra heat is smith_edge.
	public static Img SmithIron() { return IronBar(0.2, 901); }
	public static Img SmithHot()  { return IronBar(0.6, 901); }
	// Ahead of the cast: plain cold iron (58,56,60 at .75 over the dark track), lit along the top, shaded below; no flecks.
	public static Img SmithCold()
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (x + 0.5)/W, v = (y + 0.5)/H;
			double n = 1 + 0.04*Fbm(u, v, 16, 2, 2, 905);
			double[] c = { 58/255.0*n, 56/255.0*n, 60/255.0*n };
			double top = 0.18*Smooth(0.25, 0, v), dark = 0.45*Smooth(0.25, 1, v);
			double[] hl = { 170/255.0, 175/255.0, 185/255.0 };
			for (int k = 0; k < 3; k++) c[k] = Clamp(Lerp(c[k], hl[k], top)*(1 - dark));
			img.Set(x, y, c[0], c[1], c[2], 1);
		}
		return img;
	}
	// The cast edge's extra heat (+.4, falling off over 1.1 bar heights): white, the addon tints it to the heat at the
	// edge. It spans 4.4 bar heights (256 px = 4 e-folds); its alpha is the falloff, strongest at the right.
	public static Img SmithEdge()
	{
		var img = new Img(256, 32);
		for (int y = 0; y < 32; y++) for (int x = 0; x < 256; x++)
		{
			double u = (x + 0.5)/256, v = (y + 0.5)/32;
			double dark = v > 0.7 ? 0.08 + 0.42*(v - 0.7)/0.3 : 0.08*Smooth(0.18, 0.7, v);   // the iron's shading, as IronBar
			img.Set(x, y, 1 - dark, 1 - dark, 1 - dark, Math.Exp(-(1 - u)*4));
		}
		return img;
	}

	// Tempered steel after the quench, stretched across the whole bar: cool grey steel, with only a faint, narrow
	// temper sheen (straw, bronze, a hint of blue) toward the right, where the iron was hottest.
	public static Img SmithTemper()
	{
		var img = new Img(256, 64);
		double[] at = { 0, 0.62, 0.72, 0.8, 0.88, 1 };
		double[][] cols = { Hex(0x70767e), Hex(0x72777e), Hex(0x86837a), Hex(0x86796a), Hex(0x6c7385), Hex(0x6e757f) };
		for (int y = 0; y < 64; y++) for (int x = 0; x < 256; x++)
		{
			double u = (x + 0.5)/256, v = (y + 0.5)/64;
			var c = Stops(u + 0.02*Fbm(u, v, 8, 2, 2, 911), at, cols);
			double brush = 1 + 0.05*Noise(u*16, v*90, 16, 90, 912);
			double top = 0.35*Clamp(1 - v/0.25), dark = 0.5*Smooth(0.25, 1, v);
			for (int k = 0; k < 3; k++) c[k] = Clamp(Lerp(c[k]*brush, 1, top)*(1 - dark));
			img.Set(x, y, c[0], c[1], c[2], 1);
		}
		return img;
	}

	// ---------------------------------------------------------------- shared: paint a shape-built sprite once, then turn it
	// Sprites that swing (the hammer) or tip (the ladle) are painted once in their own frame, then sampled at a
	// set of angles into an atlas, so the addon only ever switches cells and moves them: nothing turns in game.
	class Src { public double X0, Y0, PX; public Img Img; }   // premultiplied colour; local point (X0, Y0) at pixel 0,0
	static double InkP(double d, double w, double px) { return Clamp((w/2 - d)*px + 0.5); }
	static double Cover(List<double[]> poly, double lx, double ly, double px)   // 3x3 supersampled coverage of a polygon
	{
		int n = 0;
		for (int sy = 0; sy < 3; sy++) for (int sx = 0; sx < 3; sx++)
			if (InPoly(poly, lx + (sx - 1)/(3*px), ly + (sy - 1)/(3*px))) n++;
		return n/9.0;
	}
	static double[] Bbox(List<double[]> p)
	{
		double a = 1e9, b = 1e9, c = -1e9, d = -1e9;
		foreach (var q in p) { a = Math.Min(a, q[0]); b = Math.Min(b, q[1]); c = Math.Max(c, q[0]); d = Math.Max(d, q[1]); }
		return new[] { a, b, c, d };
	}
	static bool Near(double[] bb, double x, double y, double m) { return x > bb[0] - m && x < bb[2] + m && y > bb[1] - m && y < bb[3] + m; }
	static void Bilinear(Src s, double lx, double ly, double[] o)   // o: premultiplied r, g, b, a
	{
		double fx = (lx - s.X0)*s.PX - 0.5, fy = (ly - s.Y0)*s.PX - 0.5;
		int x0 = (int)Math.Floor(fx), y0 = (int)Math.Floor(fy); double tx = fx - x0, ty = fy - y0;
		o[0] = o[1] = o[2] = o[3] = 0;
		for (int j = 0; j < 2; j++) for (int i = 0; i < 2; i++)
		{
			int xx = x0 + i, yy = y0 + j;
			if (xx < 0 || yy < 0 || xx >= s.Img.W || yy >= s.Img.H) continue;
			double w = (i == 0 ? 1 - tx : tx)*(j == 0 ? 1 - ty : ty); int k = yy*s.Img.W + xx;
			o[0] += s.Img.R[k]*w; o[1] += s.Img.G[k]*w; o[2] += s.Img.B[k]*w; o[3] += s.Img.A[k]*w;
		}
	}
	// One atlas of poses: cell c shows the source turned by ang[c] (canvas sense: y down, positive turns clockwise)
	// about the local origin, which sits at (ox, oy) bar heights from the cell's top-left; cell is span bar heights
	// square. A soft shadow falls down and to the right, as under the skinning knife.
	static Img Poses(Src s, double[] ang, int cols, int cell, double span, double ox, double oy)
	{
		int rows = (ang.Length + cols - 1)/cols;
		var img = new Img(cols*cell, rows*cell);
		double cpx = cell/span; var o = new double[4];
		for (int c = 0; c < ang.Length; c++)
		{
			double ca = Math.Cos(ang[c]), sa = Math.Sin(ang[c]);
			int bx = (c % cols)*cell, by = (c/cols)*cell;
			var pr = new double[cell*cell]; var pg = new double[cell*cell]; var pb = new double[cell*cell]; var pa = new double[cell*cell];
			for (int y = 0; y < cell; y++) for (int x = 0; x < cell; x++)
			{
				double r = 0, g = 0, b = 0, a = 0;
				for (int sy = 0; sy < 2; sy++) for (int sx = 0; sx < 2; sx++)
				{
					double dx = (x + 0.25 + sx*0.5)/cpx - ox, dy = (y + 0.25 + sy*0.5)/cpx - oy;
					Bilinear(s, dx*ca + dy*sa, -dx*sa + dy*ca, o);
					r += o[0]; g += o[1]; b += o[2]; a += o[3];
				}
				int i = y*cell + x; pr[i] = r/4; pg[i] = g/4; pb[i] = b/4; pa[i] = a/4;
			}
			var sh = (double[])pa.Clone();
			int rad = Math.Max(1, (int)Math.Round(0.05*cpx));
			for (int pass = 0; pass < 3; pass++) sh = BoxBlur(sh, cell, cell, rad);
			int offx = (int)Math.Round(0.05*cpx), offy = (int)Math.Round(0.08*cpx);
			for (int y = 0; y < cell; y++) for (int x = 0; x < cell; x++)
			{
				int i = y*cell + x, sx2 = x - offx, sy2 = y - offy;
				double shA = (sx2 >= 0 && sy2 >= 0) ? 0.45*sh[sy2*cell + sx2] : 0;
				double ka = pa[i], oa = ka + shA*(1 - ka);
				if (oa <= 0) continue;
				img.Set(bx + x, by + y, Clamp(pr[i]/oa), Clamp(pg[i]/oa), Clamp(pb[i]/oa), Clamp(oa));   // shadow is black: colour scales by ka/oa
			}
		}
		return img;
	}
	static void Put(Src s, int x, int y, double r, double g, double b, double a)   // store premultiplied
	{ int k = y*s.Img.W + x; s.Img.R[k] = r*a; s.Img.G[k] = g*a; s.Img.B[k] = b*a; s.Img.A[k] = a; }

	// ---------------------------------------------------------------- the forge hammer
	// The Warcraft hammer of the blacksmithing concept (smith-a), painted like the skinning knife: brushed steel
	// with a bright ground striking face and a glint, a brass or steel bolster, bands and pommel, a wood or antler
	// haft with grain and two pins, faint edges, no outline. Its own frame, in bar heights: the grip end at the
	// origin, the haft along +x, the head at x = 1.45 with the striking face 0.522 below the haft (y down).
	// The atlas holds HAM_POSES cells from level (cell 0) to lifted HAM_MAX rad (the last), the grip end at
	// (HAM_OX, HAM_OY) in each HAM_SPAN-square cell; the addon draws it at 0.78 of the bar height.
	public const int HAM_POSES = 16, HAM_CELL = 128;
	public const double HAM_MAX = 0.95, HAM_SPAN = 3.0, HAM_OX = 0.45, HAM_OY = 2.1, HAM_L = 1.45, HAM_FACE = 0.522;
	static Src HammerSource(bool antler)
	{
		const double PX = 96, X0 = -0.42, Y0 = -1.0;
		var s = new Src { X0 = X0, Y0 = Y0, PX = PX, Img = new Img((int)(2.45*PX), (int)(1.65*PX)) };
		double L = HAM_L, th = 0.16, hx0 = -0.1, hx1 = L - 0.06, hw = 0.78, cx = L, x0 = cx - hw/2, x1 = cx + hw/2;
		double yFace = HAM_FACE, yTop = -0.5, hh = yFace - yTop, bev = 0.07, glow = 0.55;
		var haft = Bez(hx0, -th*0.9, hx0 + (hx1 - hx0)*0.4, -th, hx1 - 0.1, -th*0.8, hx1, -th*0.7, 16);
		haft.AddRange(Bez(hx1, th*0.7, hx1 - 0.1, th*0.8, hx0 + (hx1 - hx0)*0.4, th, hx0, th*0.9, 16));
		haft.AddRange(Quad(hx0, th*0.9, hx0 - th*0.5, 0, hx0, -th*0.9, 8));
		double pr = th*1.05;
		var pommel = RoundRect(hx0 - pr*1.1, -pr, pr*1.2, pr*2, pr*0.45);
		var bolster = RoundRect(L - hw*0.5 - 0.1, -th*1.15, 0.12, th*2.3, th*0.35);
		var head = new List<double[]> { new[]{ x0 + bev, yTop }, new[]{ x1 - bev, yTop }, new[]{ x1, yTop + bev }, new[]{ x1, yFace - bev },
			new[]{ x1 - bev, yFace }, new[]{ x0 + bev, yFace }, new[]{ x0, yFace - bev }, new[]{ x0, yTop + bev } };
		var back = new List<double[]>();
		if (!antler)   // a spike (wood and brass), or a double claw (antler and steel)
		{
			back.AddRange(Quad(cx - hw*0.24, yTop + 0.01, cx - hw*0.12, yTop - 0.2, cx - hw*0.02, yTop - 0.42, 10));
			back.AddRange(Quad(cx + hw*0.02, yTop - 0.42, cx + hw*0.12, yTop - 0.2, cx + hw*0.24, yTop + 0.01, 10));
		}
		else
		{
			back.AddRange(Quad(cx - hw*0.42, yTop + 0.01, cx - hw*0.58, yTop - 0.28, cx - hw*0.32, yTop - 0.36, 10));
			back.Add(new[]{ cx - hw*0.13, yTop + 0.01 }); back.Add(new[]{ cx + hw*0.13, yTop + 0.01 });
			back.Add(new[]{ cx + hw*0.32, yTop - 0.36 });
			back.AddRange(Quad(cx + hw*0.32, yTop - 0.36, cx + hw*0.58, yTop - 0.28, cx + hw*0.42, yTop + 0.01, 10));
		}
		double bh = 0.085;
		double[] bandY = { yTop + hh*0.24, yTop + hh*0.7 };
		var bands = new List<List<double[]>>();
		foreach (var yc in bandY) bands.Add(RoundRect(x0 - 0.02, yc - bh/2, hw + 0.04, bh, bh*0.3));

		var rnd = new Random(antler ? 931 : 921);
		var grain = new List<double[]>(); for (int i = 0; i < 7; i++) grain.Add(new[] { Rnd(rnd, -0.8, 0.8), Rnd(rnd, 0.03, 0.1), Rnd(rnd, 5, 11), Rnd(rnd, 0, 6.283) });
		var knobs = new List<double[]>(); for (int i = 0; i < 9; i++) knobs.Add(new[] { Rnd(rnd, 0.05, 0.95), Rnd(rnd, -0.6, 0.6), Rnd(rnd, 0.04, 0.09) });
		bool brass = !antler;
		double[] hAt = { 0, 0.4, 1 }; double[][] hCol = antler ? new[] { Hex(0xe6dac4), Hex(0xb7a385), Hex(0x5d4c38) } : new[] { Hex(0x9a6a40), Hex(0x6a4322), Hex(0x2a160a) };
		double[] mAt = { 0, 0.35, 0.7, 1 };
		double[][] mCol = brass ? new[] { Hex(0xfbe6a8), Hex(0xc79a44), Hex(0x7a5418), Hex(0x3e2a0a) } : new[] { Hex(0xf2f5f8), Hex(0xa9b2bb), Hex(0x5c646d), Hex(0x2a2f35) };
		double[][] pin = brass ? new[] { Hex(0xfff0b8), Hex(0xb88a36), Hex(0x5a3e12) } : new[] { Hex(0xffffff), Hex(0xa8b0b8), Hex(0x4a5058) };
		double[] sAt = { 0, 0.3, 0.55, 1 }; double[][] sCol = { Hex(0xe4e9ee), Hex(0xa7b0b9), Hex(0x7b858f), Hex(0x5d6670) };
		double[] orange = { 1, 130/255.0, 50/255.0 };
		var bbHaft = Bbox(haft); var bbPom = Bbox(pommel); var bbBol = Bbox(bolster); var bbHead = Bbox(head); var bbBack = Bbox(back);
		double m = 0.03;
		for (int y = 0; y < s.Img.H; y++) for (int x = 0; x < s.Img.W; x++)
		{
			double lx = X0 + (x + 0.5)/PX, ly = Y0 + (y + 0.5)/PX, r = 0, g = 0, b = 0, a = 0;
			// haft: wood or antler, as the knife's handle; forge light along its underside
			if (Near(bbHaft, lx, ly, m))
			{
				double cov = Cover(haft, lx, ly, PX);
				if (cov > 0)
				{
					var c = Stops((ly + th)/(2*th), hAt, hCol);
					double uu = (lx - hx0)/(hx1 - hx0);
					if (antler)
						foreach (var k in knobs)
						{
							double kx = Lerp(hx0, hx1, k[0]), ky = k[1]*th, kr = k[2], d = Math.Sqrt((lx - kx + kr*0.3)*(lx - kx + kr*0.3) + (ly - ky + kr*0.3)*(ly - ky + kr*0.3))/kr;
							if (d < 1) { double t = d < 0.6 ? 0.35*(1 - d/0.6) : 0, dk = d >= 0.6 ? 0.25*(1 - (d - 0.6)/0.4) : 0; for (int q = 0; q < 3; q++) c[q] = Lerp(Lerp(c[q], 1.0, t), 0.35, dk); }
						}
					foreach (var gr in grain)
					{
						double gy = gr[0]*th*0.9 + Math.Sin(uu*gr[2] + gr[3])*gr[1]*th;
						double k = InkP(Math.Abs(ly - gy), 0.01, PX)*(antler ? 0.35 : 0.25 + gr[1]*2);
						double[] gc = antler ? new[] { 70/255.0, 52/255.0, 34/255.0 } : new[] { 30/255.0, 14/255.0, 4/255.0 };
						for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], gc[q], k);
					}
					double top = 0.28*Clamp(1 - (ly + th)/(th*0.6));
					c[0] = Lerp(c[0], 1, top); c[1] = Lerp(c[1], 0.96, top); c[2] = Lerp(c[2], 0.88, top);
					double fl = (0.12 + 0.25*glow)*Clamp((ly + th)/(2*th));
					for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], orange[q], fl);
					Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], cov);
					foreach (double pu in new[] { 0.22, 0.55 })
					{
						double px0 = Lerp(hx0, hx1, pu), prr = th*0.3, d = Math.Sqrt((lx - px0)*(lx - px0) + ly*ly);
						if (d < prr + 0.02)
						{
							double dl = Math.Sqrt((lx - px0 + prr*0.35)*(lx - px0 + prr*0.35) + (ly + prr*0.35)*(ly + prr*0.35))/prr;
							var pc = Stops(dl, new[] { 0, 0.55, 1 }, pin);
							Over(ref r, ref g, ref b, ref a, pc[0], pc[1], pc[2], Clamp((prr - d)*PX + 0.5));
						}
					}
				}
				Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.3*InkP(LineDist(haft, lx, ly, true), 0.012, PX));
			}
			// pommel cap and bolster in the trim metal
			foreach (var part in new[] { pommel, bolster })
			{
				var bb = part == pommel ? bbPom : bbBol;
				if (!Near(bb, lx, ly, m)) continue;
				double cov = Cover(part, lx, ly, PX);
				if (cov > 0) { var c = Stops((ly - bb[1])/(bb[3] - bb[1]), mAt, mCol); Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], cov); }
				Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.3*InkP(LineDist(part, lx, ly, true), 0.012, PX));
			}
			// steel: the back (spike or claw) and the head, brushed, lit from above, a glint across the middle
			foreach (var part in new[] { back, head })
			{
				var bb = part == back ? bbBack : bbHead;
				if (!Near(bb, lx, ly, m)) continue;
				double cov = Cover(part, lx, ly, PX);
				if (cov > 0)
				{
					double y0 = part == back ? yTop - 0.42 : yTop, y1 = part == back ? yTop : yFace;
					var c = Stops((ly - y0)/(y1 - y0), sAt, sCol);
					double brush = 1 + 0.04*Noise(lx*8, ly*120, 64, 512, 941);
					for (int q = 0; q < 3; q++) c[q] = Clamp(c[q]*brush);
					double gx = Lerp(x0, x1, 0.5), gy = Lerp(y0, y1, 0.3), gd = Math.Sqrt((lx - gx)*(lx - gx) + (ly - gy)*(ly - gy))/(hw*0.35);
					double gl = 0.5*Math.Max(0, 1 - gd)*Math.Max(0, 1 - gd);
					for (int q = 0; q < 3; q++) c[q] = Clamp(c[q] + gl);
					if (part == head)
					{
						double tb = 0.35*Clamp(1 - (ly - yTop)/(bev*1.6));                          // top bevel catches the light
						for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], 1, tb);
						double rs = 0.4*Clamp(1 - (x1 - lx)/(bev*2));                               // right side in shadow
						for (int q = 0; q < 3; q++) c[q] *= 1 - rs;
						if (ly > yFace - 0.09) { c[0] = Lerp(c[0], 214/255.0, 0.55); c[1] = Lerp(c[1], 224/255.0, 0.55); c[2] = Lerp(c[2], 232/255.0, 0.55); }   // ground striking face
						double bl = 0.35*InkP(Math.Abs(ly - (yFace - 0.095)), 0.012, PX);
						c[0] = Lerp(c[0], 70/255.0, bl); c[1] = Lerp(c[1], 78/255.0, bl); c[2] = Lerp(c[2], 88/255.0, bl);
						double fg = (ly - yTop)/hh, fa = fg > 0.5 ? Lerp(0.05 + 0.12*glow, 0.2 + 0.6*glow, (fg - 0.5)/0.5) : Lerp(0, 0.05 + 0.12*glow, fg/0.5);
						for (int q = 0; q < 3; q++) c[q] = Clamp(c[q] + orange[q]*fa);                // the forge's light on the face toward the bar
					}
					Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], cov);
				}
				Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.3*InkP(LineDist(part, lx, ly, true), 0.012, PX));
			}
			// bands across the head in the trim metal, with two small pins each
			for (int bi = 0; bi < 2; bi++)
			{
				var band = bands[bi]; double yc = bandY[bi];
				if (Math.Abs(ly - yc) > bh || lx < x0 - 0.05 || lx > x1 + 0.05) continue;
				double cov = Cover(band, lx, ly, PX);
				if (cov > 0) { var c = Stops((ly - (yc - bh/2))/bh, mAt, mCol); Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], cov); }
				Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.3*InkP(LineDist(band, lx, ly, true), 0.012, PX));
				foreach (double fx in new[] { 0.18, 0.82 })
				{
					double px0 = x0 + hw*fx, prr = bh*0.22, d = Math.Sqrt((lx - px0)*(lx - px0) + (ly - yc)*(ly - yc));
					if (d < prr + 0.02)
					{
						double dl = Math.Sqrt((lx - px0 + prr*0.35)*(lx - px0 + prr*0.35) + (ly - yc + prr*0.35)*(ly - yc + prr*0.35))/prr;
						var pc = Stops(dl, new[] { 0, 0.55, 1 }, pin);
						Over(ref r, ref g, ref b, ref a, pc[0], pc[1], pc[2], Clamp((prr - d)*PX + 0.5));
					}
				}
			}
			if (a > 0) Put(s, x, y, r/a, g/a, b/a, a);
		}
		return s;
	}
	public static Img Hammer(bool antler)
	{
		var ang = new double[HAM_POSES];
		for (int i = 0; i < HAM_POSES; i++) ang[i] = -HAM_MAX*i/(HAM_POSES - 1);   // canvas sense: negative lifts the head
		return Poses(HammerSource(antler), ang, 4, HAM_CELL, HAM_SPAN, HAM_OX, HAM_OY);
	}

	// ---------------------------------------------------------------- the forged pouring ladle (smelting)
	// The hand ladle of the smelting concepts (smelt-a3, drawn as in B3): a deep forged-iron bowl, sooty and
	// heat-tinted under the rim, slag on the metal inside, molten metal spilling over the spout; no handle (it
	// was dropped 2026-10-09, so only the bowl rides the cast edge). Its own frame, in bar heights (y down): the
	// spout lip at the origin, the bowl to the right. The atlas holds LADLE_TILT.Length cells, the lip at
	// (LADLE_OX, LADLE_OY) in each LADLE_SPAN-square cell, tipped by each tilt (the first pours, the last has righted itself).
	public static readonly double[] LADLE_TILT = { 0.58, 0.40, 0.22, 0.05 };
	public const int LADLE_CELL = 256; public const double LADLE_SPAN = 2.6, LADLE_OX = 0.3, LADLE_OY = 1.8, LADLE_R = 0.56;
	static double EllD(double x, double y, double cx, double cy, double a, double b)   // about the distance to an ellipse's outline
	{ double dx = (x - cx)/a, dy = (y - cy)/b, k = Math.Sqrt(dx*dx + dy*dy); return Math.Abs(k - 1)*Math.Min(a, b); }
	static Src LadleSource()
	{
		const double PX = 96, X0 = -0.3, Y0 = -0.75;
		var s = new Src { X0 = X0, Y0 = Y0, PX = PX, Img = new Img((int)(2.7*PX), (int)(1.6*PX)) };
		double R = LADLE_R, full = 0.7;
		var bowl = new List<double[]> { new[]{ -0.24*R, -0.06*R }, new[]{ -0.04*R, 0.2*R } };
		bowl.AddRange(Bez(-0.04*R, 0.2*R, -0.02*R, 0.95*R, 0.42*R, 1.32*R, R, 1.32*R, 16));
		bowl.AddRange(Bez(R, 1.32*R, 1.58*R, 1.32*R, 2.02*R, 0.95*R, 2*R, 0, 16));
		bowl.Add(new[]{ 0.0, 0.0 });
		var rnd = new Random(951);
		var soot = new List<double[]>(); for (int i = 0; i < 6; i++) soot.Add(new[] { Rnd(rnd, 0.2, 1.8), Rnd(rnd, 0.04, 0.1), Rnd(rnd, 0.3, 0.9), Rnd(rnd, 0.12, 0.3) });
		var slag = new List<double[]>(); for (int i = 0; i < 4; i++) slag.Add(new[] { Rnd(rnd, 0.35, 1.6), Rnd(rnd, -0.05, 0.05), Rnd(rnd, 0.08, 0.14) });
		var bbBowl = Bbox(bowl);
		double[] bAt = { 0, 0.4, 1 }; double[][] bCol = { Hex(0x4a4c53), Hex(0x2c2d32), Hex(0x121315) };
		for (int y = 0; y < s.Img.H; y++) for (int x = 0; x < s.Img.W; x++)
		{
			double lx = X0 + (x + 0.5)/PX, ly = Y0 + (y + 0.5)/PX, r = 0, g = 0, b = 0, a = 0;
			// bowl: dark forged iron, dull red where the metal sits, temper colours under the rim, soot, a soft flank light
			if (Near(bbBowl, lx, ly, 0.03))
			{
				double cov = Cover(bowl, lx, ly, PX);
				if (cov > 0)
				{
					double gt = ((lx - 0.2*R)*1.2*R + ly*1.35*R)/(1.2*R*1.2*R + 1.35*R*1.35*R);
					var c = Stops(gt, bAt, bCol);
					double d1 = Math.Sqrt((lx - R)*(lx - R) + (ly - 1.25*R)*(ly - 1.25*R))/(1.1*R), red = (0.22 + 0.16*full)*Math.Max(0, 1 - d1);
					c[0] = Clamp(c[0] + 210/255.0*red); c[1] = Clamp(c[1] + 60/255.0*red); c[2] = Clamp(c[2] + 14/255.0*red);
					double d2 = Math.Sqrt((lx - R)*(lx - R) + (ly - 1.6*R)*(ly - 1.6*R))/(1.2*R), lit = 0.22*Math.Max(0, 1 - d2);
					c[0] = Clamp(c[0] + lit); c[1] = Clamp(c[1] + 130/255.0*lit); c[2] = Clamp(c[2] + 40/255.0*lit);
					double bv = ly/(0.6*R);
					if (bv > 0 && bv < 1)
					{
						double[] tc = bv < 0.35 ? new[] { 90/255.0, 100/255.0, 160/255.0 } : new[] { 165/255.0, 120/255.0, 60/255.0 };
						double ta = bv < 0.35 ? Lerp(0.2, 0.18, bv/0.35) : Lerp(0.18, 0, (bv - 0.35)/0.65);
						for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], tc[q], ta);
					}
					foreach (var st in soot)
						if (lx > st[0]*R && lx < (st[0] + st[1])*R && ly > 0 && ly < st[2]*R) for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], 0.025, st[3]);
					if (lx > 1.45*R && lx < 1.95*R) { double f = (lx - 1.45*R)/(0.5*R), k = 0.14*(f < 0.6 ? f/0.6 : (1 - f)/0.4); for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], 0.8, k); }
					Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], cov);
				}
				Over(ref r, ref g, ref b, ref a, 0, 0, 0, 0.35*InkP(LineDist(bowl, lx, ly, true), Math.Max(0.008, R*0.025), PX));
			}
			// the metal inside, with a skin of slag
			{
				double ex = (lx - R)/(0.92*R), ey = (ly + 0.02*R)/(0.2*R), k = Math.Sqrt(ex*ex + ey*ey);
				if (k < 1.05)
				{
					double cov = Clamp((1 - k)*0.2*R*PX + 0.5);
					double gi = Math.Sqrt((lx - 0.55*R)*(lx - 0.55*R) + ly*ly)/R;
					var c0 = HeatCol(MELT_HEAT, 0.8 + 0.2*full); var c1 = HeatCol(MELT_HEAT, 0.45 + 0.25*full);
					double[] c = { Lerp(c0[0], c1[0], Clamp(gi)), Lerp(c0[1], c1[1], Clamp(gi)), Lerp(c0[2], c1[2], Clamp(gi)) };
					foreach (var sl in slag)
					{
						double sx = (lx - sl[0]*R)/(sl[2]*R), sy = (ly - sl[1]*R)/(sl[2]*R*0.45), sd = Math.Sqrt(sx*sx + sy*sy);
						double sa = 0.82*Clamp((1 - sd)*sl[2]*R*0.45*PX + 0.5);
						for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], new[] { 50/255.0, 42/255.0, 38/255.0 }[q], sa);
					}
					Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], cov);
				}
			}
			// rolled rim: iron, a cool light along its far edge, the metal's glow along its near edge
			Over(ref r, ref g, ref b, ref a, 42/255.0, 43/255.0, 48/255.0, InkP(EllD(lx, ly, R, -0.02*R, 0.95*R, 0.22*R), 0.13*R, PX));
			if (ly < -0.04*R) Over(ref r, ref g, ref b, ref a, 195/255.0, 200/255.0, 210/255.0, 0.25*InkP(EllD(lx, ly, R, -0.04*R, 0.95*R, 0.22*R), 0.03*R, PX));
			if (ly > 0.02*R) { var hc = HeatCol(MELT_HEAT, 0.9); Over(ref r, ref g, ref b, ref a, hc[0], hc[1], hc[2], 0.45*InkP(EllD(lx, ly, R, 0, 0.88*R, 0.18*R), 0.035*R, PX)); }
			// molten metal spilling over the spout
			{
				var spill = Quad(0.12*R, -0.02*R, -0.05*R, -0.07*R, -0.22*R, -0.05*R, 10);
				double d = LineDist(spill, lx, ly, false);
				if (d < 0.1*R) { var hc = HeatCol(MELT_HEAT, 0.85); Over(ref r, ref g, ref b, ref a, hc[0], hc[1], hc[2], 0.95*InkP(d, 0.1*R, PX)); }
			}
			if (a > 0) Put(s, x, y, r/a, g/a, b/a, a);
		}
		return s;
	}
	public static Img Ladle()
	{
		var ang = new double[LADLE_TILT.Length];
		for (int i = 0; i < ang.Length; i++) ang[i] = -LADLE_TILT[i];   // canvas sense: the concept's rotate(-tilt)
		return Poses(LadleSource(), ang, 2, LADLE_CELL, LADLE_SPAN, LADLE_OX, LADLE_OY);
	}

	// The falling stream of molten metal, tiling downward (the addon scrolls it): a hot pale core, orange edges,
	// brighter knots running down it.
	public static Img SmeltStream()
	{
		var img = new Img(32, 128);
		for (int y = 0; y < 128; y++) for (int x = 0; x < 32; x++)
		{
			double u = (x + 0.5)/32 - 0.5, v = (y + 0.5)/128;
			double wob = 0.05*Noise(v*4, 0.5, 4, 1, 961), d = Math.Abs(u - wob)/0.32;
			double knot = 0.5 + 0.5*Noise(u*2, v*8, 2, 8, 962);
			double core = Smooth(0.6, 0.15, d), body = Smooth(1.0, 0.75, d), haze = 0.25*Smooth(1.55, 0.9, d);
			var hot = HeatCol(MELT_HEAT, 0.8 + 0.2*knot); double[] edge = { 235/255.0, 105/255.0, 22/255.0 };
			double r = Lerp(edge[0], Lerp(hot[0], 1, 0.4*knot), core), g = Lerp(edge[1], Lerp(hot[1], 0.94, 0.4*knot), core), b = Lerp(edge[2], Lerp(hot[2], 0.75, 0.4*knot), core);
			img.Set(x, y, r, g, b, Math.Max(body, haze));
		}
		return img;
	}

	// The smelting bar, as the concept (smelting.js smelt-a, drawMolten). The molten body lies under a thin dark strip
	// at the top of the bar (its surface SMELT_BASE bar heights down, a bright skin along it) and its colour is the heat
	// along the bar; crust plates float on it: angular polygons a bit under half a bar height across in two rows,
	// overlapping into crazy paving, darker than the metal round them, each edged with a brighter line of the heat.
	//   smelt_crust  the cold steel (the fill layer): the dark metal with the plates, their cold sheen, no glow
	//   smelt_seam   the heat map laid over it, white: the addon colours it with a gradient of the heat along the bar;
	//                its alpha is the metal between the plates (.7), the plates (.4) and their edges (1), so the
	//                plates stay darker than the metal and their edges brighter, as the concept paints them
	//   smelt_hot    the fresh pour behind the landing point, opaque where the metal is molten (the plates are gone)
	//   smelt_nose   the pour's rounded front: a mask over the fill's last half bar height (a soft D-shaped nose)
	//   smelt_dark   the track: the bar's dark interior ahead of the pour
	const double SMELT_BASE = 0.09, SMELT_SKIN = 0.135;
	static readonly double[] SMELT_DARK = { 16/255.0, 15/255.0, 20/255.0 };
	class Plate { public double X, Y; public List<double[]> Pts, Hi; public double Var; }
	static List<Plate> plates;
	static List<Plate> SmeltPlates()
	{
		if (plates != null) return plates;
		plates = new List<Plate>();
		var rnd = new Random(991);
		foreach (double row in new[] { .32, .7 })
			for (double x = H*.2; x < W + H; x += H*Rnd(rnd, .3, .4))
			{
				var p = new Plate { X = x + Rnd(rnd, -.1, .1)*H, Y = H*(row + Rnd(rnd, -.06, .06)), Var = 0.85 + 0.3*rnd.NextDouble() };
				double r = H*Rnd(rnd, .24, .32); int n = 5 + rnd.Next(3);
				p.Pts = new List<double[]>(); p.Hi = new List<double[]>();
				for (int i = 0; i < n; i++)
				{
					double a = (i + Rnd(rnd, -.3, .3))/n*2*Math.PI, d = r*Rnd(rnd, .7, 1.1);
					double px = Math.Cos(a)*d, py = Math.Sin(a)*d*.75;
					p.Pts.Add(new[] { p.X + px, p.Y + py });
					p.Hi.Add(new[] { p.X - .02*H + px*.6, p.Y - .03*H + py*.5 });   // the concept's smaller, lighter polygon up and left
				}
				plates.Add(p);
			}
		return plates;
	}
	// the topmost plate under (px, py) on the tiling bar, how far inside its edge, and whether in its highlight
	static Plate PlateAt(double px, double py, out double edge, out bool hi)
	{
		var ps = SmeltPlates(); edge = 0; hi = false;
		for (int i = ps.Count - 1; i >= 0; i--)
		{
			var p = ps[i];
			foreach (double o in new[] { 0.0, -W, W })
			{
				if (Math.Abs(px + o - p.X) > H*.4) continue;
				if (InPoly(p.Pts, px + o, py)) { edge = LineDist(p.Pts, px + o, py, true); hi = InPoly(p.Hi, px + o, py); return p; }
			}
		}
		return null;
	}
	// the bar's vertical make-up: the dark strip above the metal, the bright skin along its surface, shade toward the bottom
	static void SmeltDepth(double[] c, double v)
	{
		if (v < SMELT_BASE) { c[0] = SMELT_DARK[0]; c[1] = SMELT_DARK[1]; c[2] = SMELT_DARK[2]; return; }
		double skin = 0.4*Smooth(SMELT_SKIN + 0.02, SMELT_BASE + 0.01, v), dark = 0.42*Smooth(0.3, 1, v);
		for (int k = 0; k < 3; k++) c[k] = Clamp(Lerp(c[k], new[] { 1, 240/255.0, 190/255.0 }[k], skin)*(1 - dark));
	}
	public static Img SmeltCrust()
	{
		var img = new Img(W, H);
		double[] sheen = { 200/255.0, 205/255.0, 215/255.0 }, rimc = { 78/255.0, 72/255.0, 80/255.0 };
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double px = x + 0.5, py = y + 0.5, u = px/W, v = py/H;
			double edge; bool hi;
			var p = PlateAt(px, py, out edge, out hi);
			double[] c;
			if (p == null)
			{
				double n = 1 + 0.08*Fbm(u, v, 16, 2, 2, 971);
				c = new[] { 52/255.0*n, 50/255.0*n, 56/255.0*n };
			}
			else
			{
				c = new[] { 40/255.0*p.Var, 38/255.0*p.Var, 42/255.0*p.Var };
				if (hi) for (int k = 0; k < 3; k++) c[k] = Lerp(c[k], sheen[k], 0.16);           // the cold plates' dull sheen
				double rim = Smooth(2.4, 0.9, edge);
				for (int k = 0; k < 3; k++) c[k] = Lerp(c[k], rimc[k], 0.6*rim);                 // a faint lighter edge
			}
			SmeltDepth(c, v);
			img.Set(x, y, c[0], c[1], c[2], 1);
		}
		return img;
	}
	public static Img SmeltSeam()
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double px = x + 0.5, py = y + 0.5, v = py/H;
			double edge; bool hi;
			var p = PlateAt(px, py, out edge, out hi);
			double a = p == null ? 0.7 : Lerp(0.4, 1, Smooth(2.4, 0.9, edge));   // the plates' edges brighter than the metal between them
			if (v < SMELT_BASE) a = 0; else if (v < SMELT_SKIN) a = 1;
			double dark = 0.42*Smooth(0.3, 1, v);
			img.Set(x, y, 1 - dark, 1 - dark, 1 - dark, a);
		}
		return img;
	}
	// The fresh pour, stretched behind the landing point: clear at the left, where the crust has formed, growing opaque
	// through red and orange to pale yellow at the right edge (the landing point; the addon clamps past it).
	public static Img SmeltHot()
	{
		var img = new Img(256, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 256; x++)
		{
			double u = (x + 0.5)/256, v = (y + 0.5)/64;
			double temp = Math.Exp(-(1 - u)*3.2) * (1 + 0.06*Fbm(u, v, 12, 2, 2, 981));
			var c = HeatCol(MELT_HEAT, Clamp(temp));
			double streak = 0.08*Smooth(0.2, 0.7, Fbm(u*1, v, 24, 4, 2, 982))*Clamp(temp*1.5);
			for (int k = 0; k < 3; k++) c[k] = Clamp(c[k] + streak);
			SmeltDepth(c, v);
			img.Set(x, y, c[0], c[1], c[2], Smooth(0.38, 0.78, temp));   // the plates fade out where the metal is molten
		}
		return img;
	}
	// The pour's rounded front, as the concept's nose: a mask (white = kept) Effects_Forge.lua anchors to the fill's
	// edge, half a bar height wide and a bar high, on everything in the smelting fill. Its left column is solid, so
	// CLAMP keeps all of the fill left of it; its right side is a soft D: the fill's end rounds in most at the top,
	// bulges out at just over half height and comes in a little at the bottom, the edge fading over .14 of its width.
	// No painted dark cap and no straight clip line: the hot pool simply rounds off into the dark track.
	public static Img SmeltNose()
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = (x + 0.5)/64, v = (y + 0.5)/64;
			double q = (v - 0.58)/0.58, edge = 0.22 + 0.78*Math.Sqrt(Math.Max(0, 1 - q*q));
			img.Set(x, y, 1, 1, 1, 1 - Smooth(edge - 0.07, edge + 0.07, u));
		}
		return img;
	}
	public static Img SmeltDark()
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double n = 1 + 0.1*Fbm((x + 0.5)/64, (y + 0.5)/64, 4, 4, 2, 983);
			img.Set(x, y, Clamp(SMELT_DARK[0]*n), Clamp(SMELT_DARK[1]*n), Clamp(SMELT_DARK[2]*n), 1);
		}
		return img;
	}

	// ================================================================ TAILORING: the loom (tail-a2), and LEATHERWORKING: laced, tooled panels (lw-b)
	// Painting on a transparent image, in bar heights at px pixels per bar height: a straight-alpha "over" on a pixel,
	// strokes and fills of polylines (wrapping left-right for tiles), and the embossed strokes the leather tooling uses.
	static void OverPx(Img img, int x, int y, double cr, double cg, double cb, double ca)
	{
		if (x < 0 || y < 0 || x >= img.W || y >= img.H || ca <= 0) return;
		int i = y*img.W + x;
		double a0 = img.A[i], r = img.R[i]*a0, g = img.G[i]*a0, b = img.B[i]*a0, a = a0;
		Over(ref r, ref g, ref b, ref a, cr, cg, cb, ca);
		if (a > 0) { img.R[i] = r/a; img.G[i] = g/a; img.B[i] = b/a; }
		img.A[i] = a;
	}
	static void StrokeH(Img img, List<double[]> pts, double w, double px, double[] c, double alpha, bool closed, bool wrapX)
	{
		var bb = Bbox(pts); double pad = w/2 + 1.5/px;
		int x0 = (int)Math.Floor((bb[0] - pad)*px), x1 = (int)Math.Ceiling((bb[2] + pad)*px), y0 = (int)Math.Floor((bb[1] - pad)*px), y1 = (int)Math.Ceiling((bb[3] + pad)*px);
		for (int y = Math.Max(0, y0); y <= Math.Min(img.H - 1, y1); y++) for (int x = x0; x <= x1; x++)
		{
			int xx = wrapX ? Mod(x, img.W) : x;
			if (xx < 0 || xx >= img.W) continue;
			double d = LineDist(pts, (x + 0.5)/px, (y + 0.5)/px, closed);
			OverPx(img, xx, y, c[0], c[1], c[2], alpha*InkP(d, w, px));
		}
	}
	static void FillH(Img img, List<double[]> pts, double px, double[] c, double alpha, bool wrapX)
	{
		var bb = Bbox(pts); double pad = 1.5/px;
		int x0 = (int)Math.Floor((bb[0] - pad)*px), x1 = (int)Math.Ceiling((bb[2] + pad)*px), y0 = (int)Math.Floor((bb[1] - pad)*px), y1 = (int)Math.Ceiling((bb[3] + pad)*px);
		for (int y = Math.Max(0, y0); y <= Math.Min(img.H - 1, y1); y++) for (int x = x0; x <= x1; x++)
		{
			int xx = wrapX ? Mod(x, img.W) : x;
			if (xx < 0 || xx >= img.W) continue;
			OverPx(img, xx, y, c[0], c[1], c[2], alpha*Cover(pts, (x + 0.5)/px, (y + 0.5)/px, px));
		}
	}
	static List<double[]> Shift(List<double[]> pts, double dx, double dy)
	{
		var o = new List<double[]>(); foreach (var p in pts) o.Add(new[] { p[0] + dx, p[1] + dy }); return o;
	}
	static List<double[]> Seg(double x0, double y0, double x1, double y1) { return new List<double[]> { new[] { x0, y0 }, new[] { x1, y1 } }; }
	static List<double[]> Circle(double cx, double cy, double r)
	{
		var p = new List<double[]>(); for (int i = 0; i < 20; i++) { double a = 2*Math.PI*i/20; p.Add(new[] { cx + Math.Cos(a)*r, cy + Math.Sin(a)*r }); } return p;
	}
	// A rounded rectangle's signed distance (negative inside), for the cloth's strands.
	static double RRDist(double x, double y, double cx, double cy, double hw, double hh, double r)
	{
		double qx = Math.Abs(x - cx) - (hw - r), qy = Math.Abs(y - cy) - (hh - r);
		double ox = Math.Max(qx, 0), oy = Math.Max(qy, 0);
		return Math.Sqrt(ox*ox + oy*oy) + Math.Min(Math.Max(qx, qy), 0) - r;
	}
	// a soft shadow of the image's own alpha, down and to the right (as under the knife)
	static void DropShadow(Img img, int ox, int oy, int rad, double k)
	{
		var sh = new double[img.W*img.H];
		for (int i = 0; i < sh.Length; i++) sh[i] = img.A[i];
		for (int pass = 0; pass < 3; pass++) sh = BoxBlur(sh, img.W, img.H, rad);
		for (int y = 0; y < img.H; y++) for (int x = 0; x < img.W; x++)
		{
			int sx = x - ox, sy = y - oy;
			double s = (sx >= 0 && sy >= 0) ? k*sh[sy*img.W + sx] : 0;
			int i = y*img.W + x;
			double ka = img.A[i], oa = ka + s*(1 - ka);
			if (oa <= 0) continue;
			img.R[i] = img.R[i]*ka/oa; img.G[i] = img.G[i]*ka/oa; img.B[i] = img.B[i]*ka/oa; img.A[i] = oa;
		}
	}

	// ---------------------------------------------------------------- the woven cloth (the tailoring fill) and the warp ahead of it
	// Plain weave, as the concept's weaveTile: cells WEAVE_C px square (twelve per bar height), the warp running along the
	// bar in the cells where (column + row) is even, the weft across it in the others, each thread a rounded strand lit
	// across its width. Painted in brightness (1 = the cloth's colour; the addon tints it per cast), the weft a shade
	// lighter than the warp, the dark between them at .42. Slubs, soft mottling and the cloth curving away top and bottom.
	public const double WEAVE_C = 64.0/12;
	static double StrandLum(double t)   // across a strand: shaded edge, the lit crown, the body, the far edge in shade
	{
		return t < 0.42 ? Lerp(0.6, 1.0, t/0.42) : t < 0.6 ? Lerp(1.0, 0.9, (t - 0.42)/0.18) : Lerp(0.9, 0.55, (t - 0.6)/0.4);
	}
	public static Img TailCloth()
	{
		var img = new Img(W, H); double c = WEAVE_C, th = c*0.8;
		var rnd = new Random(1021);
		var slub = new double[W/(int)Math.Round(c) + 2]; for (int i = 0; i < slub.Length; i++) { double r = rnd.NextDouble(); slub[i] = r < 0.1 ? 0.07 : r < 0.2 ? -0.1 : 0; }
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double sx = x + 0.5, sy = y + 0.5; int ci = (int)Math.Floor(sx/c), cj = (int)Math.Floor(sy/c);
			double lum = 0.42; bool hit = false;
			for (int pass = 0; pass < 2 && !hit; pass++)   // the weft (vertical strands) lies over the warp
			{
				bool vert = pass == 0;
				for (int k = -1; k <= 1 && !hit; k++)
				{
					int i = vert ? ci : ci + k, j = vert ? cj + k : cj;
					if (Mod(i + j, 2) != (vert ? 1 : 0)) continue;
					double cx = (i + 0.5)*c, cy = (j + 0.5)*c, d = vert ? RRDist(sx, sy, cx, cy, th/2, c*0.6, th/2) : RRDist(sx, sy, cx, cy, c*0.6, th/2, th/2);
					double cov = Clamp(0.5 - d);
					if (cov <= 0) continue;
					double t = vert ? (sx - (cx - th/2))/th : (sy - (cy - th/2))/th;
					double l = StrandLum(Clamp(t))*(vert ? 1.0 : 0.93);
					lum = Lerp(lum, l, cov); hit = cov >= 0.999;
				}
			}
			int su = Math.Min(slub.Length - 1, (int)Math.Floor(sx/c));
			if (slub[su] > 0) lum = Lerp(lum, 1, slub[su]); else lum *= 1 + slub[su];
			double v = sy/H, curve = v < 0.2 ? 0.3*(1 - v/0.2) : v > 0.75 ? 0.38*(v - 0.75)/0.25 : 0;
			lum *= 1 - curve;
			img.Set(x, y, lum, lum, lum, 1);
		}
		for (int n = 0; n < 64; n++)   // soft mottling
		{
			double cx = Rnd(rnd, 0, W), cy = Rnd(rnd, 0, H), r = H*Rnd(rnd, 0.3, 0.9); bool dark = rnd.NextDouble() < 0.55;
			for (int y = (int)(cy - r); y <= (int)(cy + r); y++) { if (y < 0 || y >= H) continue; for (int x = (int)(cx - r); x <= (int)(cx + r); x++)
			{
				double d = Math.Sqrt((x - cx)*(x - cx) + (y - cy)*(y - cy)), t = (dark ? 0.12 : 0.06)*Clamp(1 - d/r); int j = y*W + Mod(x, W);
				img.R[j] = Lerp(img.R[j], dark ? 0 : 1, t); img.G[j] = img.R[j]; img.B[j] = img.R[j];
			} }
		}
		return img;
	}
	// The warp ahead of the fell: taut threads along the bar, one per weave unit (six per bar height), on a dark ground.
	// Brightness .55 of the cloth's colour (the addon tints it); tail_warp_hi is the light along their tops, added.
	static Img warpHi;
	public static Img TailWarp()
	{
		var img = new Img(W, H); warpHi = new Img(W, H);
		double lw = Math.Max(0.8, WEAVE_C*0.5);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double sy = y + 0.5, a = 0, hi = 0;
			for (int j = 0; j < 6; j++)
			{
				double cy = (j + 0.5)*2*WEAVE_C + 0.15*Math.Sin(x/37.0 + j);
				a = Math.Max(a, Clamp(lw/2 - Math.Abs(sy - cy) + 0.5));
				hi = Math.Max(hi, Clamp(lw*0.35/2 - Math.Abs(sy - cy + lw*0.2) + 0.5));
			}
			double l = Lerp(0.03, 0.55, a*0.9);
			img.Set(x, y, l, l, l, 1);
			warpHi.Set(x, y, 1, 1, 1, 0.55*hi*a);
		}
		return img;
	}
	public static Img TailWarpHi() { if (warpHi == null) TailWarp(); return warpHi; }
	// The shed: one bar height square laid on the track just past the fell, where alternate threads part by .45 of a cell
	// over the first .7, then run on and close again while the square fades out, so it meets the taut warp behind it.
	// Flipped top to bottom (texcoords) for the other shed.
	public static Img TailShed()
	{
		var img = new Img(64, 64); double px = 64, lw = Math.Max(0.8, WEAVE_C*0.5)/64, cell = 1.0/12;
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = (x + 0.5)/px, v = (y + 0.5)/px, a = 0, hi = 0;
			double part = u < 0.7 ? u/0.7 : u < 0.85 ? 1 : 1 - (u - 0.85)/0.15;
			for (int j = 0; j < 6; j++)
			{
				double cy = (j + 0.5)*2*cell + (j % 2 == 1 ? 1 : -1)*0.45*cell*part;
				a = Math.Max(a, Clamp((lw/2 - Math.Abs(v - cy))*px + 0.5));
				hi = Math.Max(hi, Clamp((lw*0.35/2 - Math.Abs(v - cy + lw*0.2))*px + 0.5));
			}
			double l = Lerp(0.03, Lerp(0.55, 0.9, hi), a*0.9), alpha = u < 0.8 ? 1 : 1 - (u - 0.8)/0.2;
			img.Set(x, y, l, l, l, alpha);
		}
		return img;
	}
	// ---------------------------------------------------------------- the loom's tools (tail-a2): small boat shuttle, pirn, reed, loose weft ends
	// All at 160 px per bar height, painted as the concept's drawShuttleSmall / drawReedSmall: worn, muted wood, no brass, soft shadows.
	public const double SHUTTLE_L = 0.6, SHUTTLE_W = 0.14;
	public static Img Shuttle()   // 64x128 (.4 x .8 bar heights), standing upright, centred; its cavity is empty (p_pirn fills it)
	{
		var img = new Img(64, 128); double px = 160, cx = 0.2, cy = 0.4, L = SHUTTLE_L, w = SHUTTLE_W;
		var body = Bez(cx, cy - L/2, cx + w*0.62, cy - L*0.28, cx + w*0.62, cy + L*0.28, cx, cy + L/2, 24);
		body.AddRange(Bez(cx, cy + L/2, cx - w*0.62, cy + L*0.28, cx - w*0.62, cy - L*0.28, cx, cy - L/2, 24));
		double[] at = { 0, 0.4, 0.6, 1 }; double[][] wood = { Hex(0x2e1c10), Hex(0x6b4a2c), Hex(0x7c5a38), Hex(0x2a1a0e) };
		var bb = Bbox(body);
		for (int y = 0; y < img.H; y++) for (int x = 0; x < img.W; x++)
		{
			double lx = (x + 0.5)/px, ly = (y + 0.5)/px;
			if (!Near(bb, lx, ly, 0.02)) continue;
			double cov = Cover(body, lx, ly, px);
			if (cov <= 0) continue;
			var c = Stops((lx - (cx - w/2))/w, at, wood);
			for (int i = -1; i <= 1; i++)   // grain
			{
				var gr = Bez(cx + i*w*0.15, cy - L/2, cx + i*w*0.25, cy - L*0.15, cx + i*w*0.05, cy + L*0.15, cx + i*w*0.18, cy + L/2, 12);
				double k = 0.3*InkP(LineDist(gr, lx, ly, false), 0.008, px);
				for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], new[] { 30/255.0, 16/255.0, 6/255.0 }[q], k);
			}
			OverPx(img, x, y, c[0], c[1], c[2], cov);
		}
		FillH(img, RoundRect(cx - w*0.2, cy - L*0.21, w*0.4, L*0.42, w*0.2), px, new[] { 16/255.0, 8/255.0, 2/255.0 }, 0.85, false);
		StrokeH(img, Bez(cx - w*0.22, cy - L*0.32, cx - w*0.34, cy - L*0.1, cx - w*0.34, cy + L*0.1, cx - w*0.22, cy + L*0.32, 12), 0.012, px, new[] { 1, 236/255.0, 210/255.0 }, 0.22, false, false);
		DropShadow(img, 4, 5, 4, 0.4);
		return img;
	}
	public static Img Pirn()      // 32x128 (.2 x .8): the pirn of thread in the shuttle's cavity, white (tinted to the cloth's thread)
	{
		var img = new Img(32, 128); double px = 160, cx = 0.1, cy = 0.4, bw = SHUTTLE_W*0.4*0.78, bl = SHUTTLE_L*0.42*0.8;
		var body = RoundRect(cx - bw/2, cy - bl/2, bw, bl, bw*0.3);
		for (int y = 0; y < img.H; y++) for (int x = 0; x < img.W; x++)
		{
			double lx = (x + 0.5)/px, ly = (y + 0.5)/px, cov = Cover(body, lx, ly, px);
			if (cov <= 0) continue;
			double t = (lx - (cx - bw/2))/bw, l = t < 0.45 ? Lerp(0.45, 1, t/0.45) : Lerp(1, 0.45, (t - 0.45)/0.55);
			double wind = 0.45*InkP(Math.Abs(Frac((ly - lx*0.15)/0.025) - 0.5)*0.025, 0.004, px);   // the wound thread, slightly slanted
			l = Lerp(l, 0.45, wind);
			OverPx(img, x, y, l, l, l, cov);
		}
		return img;
	}
	public static Img Reed()      // 32x256 (.2 x 1.6): the slim steel reed in dark wood caps, from .1 above the bar to .1 below it; the bar's top is .3 down the sprite
	{
		var img = new Img(32, 256); double px = 160, cx = 0.1, top = 0.3 - 0.1, bot = 0.3 + 1.1, w = 0.075, cap = 0.06, cw = 0.12;
		double[] sAt = { 0, 0.5, 1 }; double[][] steel = { Hex(0x4a4e55), Hex(0xa2a8b0), Hex(0x55595f) };
		double[][] wood = { Hex(0x2e1c10), Hex(0x6b4a2c), Hex(0x2a1a0e) };
		var plate = RoundRect(cx - w/2, top + cap, w, bot - top - 2*cap, 0.004);
		var caps = new[] { RoundRect(cx - cw/2, top, cw, cap, cap*0.3), RoundRect(cx - cw/2, bot - cap, cw, cap, cap*0.3) };
		for (int y = 0; y < img.H; y++) for (int x = 0; x < img.W; x++)
		{
			double lx = (x + 0.5)/px, ly = (y + 0.5)/px, cov = Cover(plate, lx, ly, px);
			if (cov > 0)
			{
				var c = Stops((lx - (cx - w/2))/w, sAt, steel);
				double dent = ly > top + cap + 0.02 && ly < bot - cap ? 0.5*InkP(Math.Abs(Frac((ly - top - cap - 0.02)/0.06) - 0.5)*0.06, 0.007, px) : 0;
				for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], new[] { 30/255.0, 32/255.0, 36/255.0 }[q], dent);
				OverPx(img, x, y, c[0], c[1], c[2], cov);
			}
			foreach (var k in caps)
			{
				double cc = Cover(k, lx, ly, px);
				if (cc > 0) { var c = Stops((lx - (cx - cw/2))/cw, sAt, wood); OverPx(img, x, y, c[0], c[1], c[2], cc); }
			}
		}
		DropShadow(img, 4, 2, 3, 0.4);
		return img;
	}
	public static Img WeftTail()  // 32x32 (.2 x .2): a loose weft end poking out of the top selvedge: up from the bottom middle, curling right. White (tinted); flipped for the bottom edge and the other curl
	{
		var img = new Img(32, 32); double px = 160, x = 0.1, y0 = 0.16, len = 0.15;
		var pts = Bez(x, 0.2, x + 0.05, y0 - len*0.5, x + 0.14, y0 - len*0.7, x + 0.08, y0 - len, 16);
		StrokeH(img, pts, 0.033, px, new[] { 1.0, 1.0, 1.0 }, 0.9, false, false);
		return img;
	}

	// ---------------------------------------------------------------- tanned leather (the leatherworking panels), tooled patterns, holes, lace, stitches, the needle
	// Leather in brightness (.88 = the tone's colour the addon tints it to, highlights up to 1): a soft top light and
	// darker lower half, mottling, fine crinkled grain mostly along the hide, pores, light flecks and a few pale scuffs.
	public const double LEATHER_NOM = 0.88;
	public static Img Leather()
	{
		var img = new Img(W, H); double nom = LEATHER_NOM, hp = H;
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double v = (y + 0.5)/H, l = v < 0.55 ? Lerp(nom*1.06, nom, v/0.55) : Lerp(nom, nom*0.72, (v - 0.55)/0.45);
			img.Set(x, y, l, l, l, 1);
		}
		var rnd = new Random(1031); double area = W*H/(hp*hp);
		for (int n = 0; n < (int)(area*5); n++)   // mottling
		{
			double cx = Rnd(rnd, 0, W), cy = Rnd(rnd, 0, H), r = hp*Rnd(rnd, 0.2, 0.7); bool dark = rnd.NextDouble() < 0.6;
			for (int y = (int)(cy - r); y <= (int)(cy + r); y++) { if (y < 0 || y >= H) continue; for (int x = (int)(cx - r); x <= (int)(cx + r); x++)
			{
				double d = Math.Sqrt((x - cx)*(x - cx) + (y - cy)*(y - cy)), t = (dark ? 0.22 : 0.1)*Clamp(1 - d/r); int j = y*W + Mod(x, W);
				img.R[j] = Lerp(img.R[j], dark ? nom*0.72 : 1, t); img.G[j] = img.R[j]; img.B[j] = img.R[j];
			} }
		}
		double[] xs, ys;
		for (int n = 0; n < (int)(area*150); n++)   // grain: short crinkles, mostly along the hide
		{
			double x = Rnd(rnd, 0, W), y = Rnd(rnd, 0, H), a = Rnd(rnd, -0.6, 0.6) + (rnd.NextDouble() < 0.25 ? 1.57 : 0), l = hp*Rnd(rnd, 0.025, 0.07);
			HairPts(x, y, a, l, 0, 0, 1, out xs, out ys);
			Stroke(img, xs, ys, Math.Max(0.4, hp*0.01), nom*0.72, Rnd(rnd, 0.12, 0.26), false);
		}
		for (int n = 0; n < (int)(area*90); n++)    // pores
		{
			double x = Rnd(rnd, 0, W), y = Rnd(rnd, 0, H);
			xs = new[] { x, x }; ys = new[] { y, y };
			Stroke(img, xs, ys, Math.Max(0.6, hp*Rnd(rnd, 0.01, 0.026)), nom*0.5, Rnd(rnd, 0.2, 0.4), false);
		}
		for (int n = 0; n < (int)(area*40); n++)    // light flecks
		{
			double x = Rnd(rnd, 0, W), y = Rnd(rnd, 0, H);
			xs = new[] { x, x }; ys = new[] { y, y };
			Stroke(img, xs, ys, Math.Max(0.6, hp*Rnd(rnd, 0.012, 0.03)), 1, Rnd(rnd, 0.05, 0.12), false);
		}
		for (int n = 0; n < (int)Math.Max(2, W/hp*0.6); n++)   // scuffs
		{
			double x = Rnd(rnd, 0, W), y = Rnd(rnd, 0, H), l = hp*Rnd(rnd, 0.3, 0.8), a = Rnd(rnd, -0.4, 0.4);
			HairPts(x, y, a, l, hp*Rnd(rnd, -0.08, 0.08), 0, 1, out xs, out ys);
			Stroke(img, xs, ys, hp*Rnd(rnd, 0.01, 0.025), 1, Rnd(rnd, 0.08, 0.16), false);
		}
		return img;
	}
	// A tooled pattern, 256x128 at TOOL_PX px per bar height: two bar heights long (tiling along the bar) and one tall,
	// the pattern in the band .15 to .85 that the addon lays over a panel's middle. Pressed into the leather: a dark
	// impression with a faintly lit lip below and to the right of it (the concept's emboss), on a clear ground.
	public const double TOOL_PX = 128;
	static readonly double[] EMB_LIGHT = { 1, 228/255.0, 192/255.0 }, EMB_DARK = { 26/255.0, 11/255.0, 4/255.0 };
	static void EmbossStroke(Img img, List<double[]> pts, double w, double px, double depth, bool closed)
	{
		StrokeH(img, Shift(pts, 0.014, 0.02), w, px, EMB_LIGHT, 0.28*depth, closed, true);
		StrokeH(img, Shift(pts, -0.006, -0.008), w, px, EMB_DARK, 0.55*depth, closed, true);
	}
	static void EmbossFill(Img img, List<double[]> pts, double px, double depth)
	{
		FillH(img, Shift(pts, 0.014, 0.02), px, EMB_LIGHT, 0.3*depth, true);
		FillH(img, pts, px, EMB_DARK, 0.6*depth, true);
	}
	public static Img Tooling(int kind)
	{
		var img = new Img(256, 128); double px = TOOL_PX, y0 = 0.15, y1 = 0.85, mid = 0.5, hgt = y1 - y0;
		if (kind == 0)   // basket-weave: cells of three bars, turned in turn
		{
			double cw = 0.24; int cols = 8, rows = 2; double ox = (2 - cols*cw)/2, oy = y0 + (hgt - rows*cw)/2;
			for (int c = 0; c < cols; c++) for (int r = 0; r < rows; r++)
			{
				double cx = ox + c*cw, cy = oy + r*cw; bool vert = (c + r) % 2 == 1;
				for (int b = 0; b < 3; b++)
				{
					double along = cw*0.78, thick = cw*0.16, o = (b - 1)*cw*0.27;
					double x = vert ? cx + cw/2 + o - thick/2 : cx + cw*0.11, y = vert ? cy + cw*0.11 : cy + cw/2 + o - thick/2;
					EmbossFill(img, RoundRect(x, y, vert ? thick : along, vert ? along : thick, thick*0.45), px, 0.9);
				}
			}
		}
		else if (kind == 1)   // scrolling vine: a winding stem, curls and leaves off it in turn
		{
			double amp = hgt*0.22;
			var stem = new List<double[]>(); for (int i = 0; i <= 200; i++) { double x = 2.0*i/200; stem.Add(new[] { x, mid + amp*Math.Sin(x*2*Math.PI) }); }
			EmbossStroke(img, stem, 0.04, px, 1, false);
			bool up = true;
			for (int k = 0; k < 3; k++)
			{
				double x = 0.12 + k*(2.0/3), y = mid + amp*Math.Sin(x*2*Math.PI), sg = up ? -1 : 1;
				var curl = Bez(x, y, x + 0.12, y + sg*0.18, x + 0.3, y + sg*0.2, x + 0.26, y + sg*0.06, 14);
				curl.AddRange(Bez(x + 0.26, y + sg*0.06, x + 0.22, y - sg*0.02, x + 0.16, y + sg*0.04, x + 0.19, y + sg*0.1, 10));
				EmbossStroke(img, curl, 0.03, px, 0.85, false);
				double lx = x + 0.36, ly = mid + amp*Math.Sin(lx*2*Math.PI);
				var leaf = Quad(lx, ly, lx + 0.06, ly - sg*0.22, lx + 0.2, ly - sg*0.26, 10);
				leaf.AddRange(Quad(lx + 0.2, ly - sg*0.26, lx + 0.14, ly - sg*0.08, lx, ly, 10));
				EmbossStroke(img, leaf, 0.03, px, 0.85, true);
				EmbossStroke(img, Seg(lx + 0.03, ly - sg*0.04, lx + 0.16, ly - sg*0.2), 0.03, px, 0.85, false);
				up = !up;
			}
		}
		else if (kind == 2)   // diamond lattice: crossed grooves, a dot in each diamond
		{
			double sp = 2.0/7;
			for (int k = -3; k < 10; k++)
			{
				EmbossStroke(img, Seg(k*sp, y0, k*sp + hgt, y1), 0.028, px, 0.8, false);
				EmbossStroke(img, Seg(k*sp + hgt, y0, k*sp, y1), 0.028, px, 0.8, false);
			}
			for (int i = 0; i < 7; i++) for (int m = -2; m <= 3; m++)
			{
				foreach (var d in new[] { new[] { (i + 0.5)*sp, y0 + m*sp }, new[] { i*sp, y0 + (m + 0.5)*sp } })
					if (d[1] > y0 + 0.04 && d[1] < y1 - 0.04) EmbossFill(img, Circle(d[0], d[1], 0.028), px, 0.9);
			}
		}
		else if (kind == 3)   // bordered shells: bevelled border grooves and a row of fan stamps, up and down in turn
		{
			EmbossStroke(img, Seg(0, y0 + 0.05, 2, y0 + 0.05), 0.03, px, 1, false);
			EmbossStroke(img, Seg(0, y1 - 0.05, 2, y1 - 0.05), 0.03, px, 1, false);
			double sp = 2.0/6, R = 0.15;
			for (int i = 0; i < 6; i++)
			{
				double cx = (i + 0.5)*sp; bool up = i % 2 == 0; double bs = mid + (up ? R*0.5 : -R*0.5), sg = up ? -1 : 1;
				var fan = new List<double[]>();
				for (int k = 0; k <= 16; k++) { double a = Math.PI*k/16; fan.Add(new[] { cx + Math.Cos(a)*R, bs + sg*Math.Sin(a)*R }); }
				EmbossStroke(img, fan, 0.025, px, 0.9, true);
				for (int k = 1; k < 4; k++) { double a = Math.PI*k/4; EmbossStroke(img, Seg(cx, bs, cx + Math.Cos(a)*R*0.85, bs + sg*Math.Sin(a)*R*0.85), 0.025, px, 0.9, false); }
			}
		}
		else   // knotwork band: two strands crossing back and forth
		{
			double A = hgt*0.3, k = 1.0/(2*Math.PI);
			foreach (int sg in new[] { 1, -1 })
			{
				var pts = new List<double[]>(); for (int i = 0; i <= 200; i++) { double x = 2.0*i/200; pts.Add(new[] { x, mid + sg*A*Math.Sin(x/k) }); }
				EmbossStroke(img, pts, 0.05, px, 1, false);
			}
			for (int m = 0; m < 4; m++) EmbossStroke(img, Seg(m*Math.PI*k, mid - A*0.18, m*Math.PI*k, mid + A*0.18), 0.02, px, 0.6, false);
		}
		return img;
	}
	public static Img Hole()      // 32x32 at 320 px per bar height: a punched lacing hole .03 bar heights across, a faint lit lip below it
	{
		var img = new Img(32, 32); double px = 320, cx = 0.05, cy = 0.05, r = 0.03;
		for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++)
		{
			double lx = (x + 0.5)/px, ly = (y + 0.5)/px;
			double ex = (lx - cx)/r, ey = (ly - cy)/(r*0.9), k = Math.Sqrt(ex*ex + ey*ey);
			OverPx(img, x, y, 22/255.0, 10/255.0, 4/255.0, 0.85*Clamp((1 - k)*r*0.9*px + 0.5));
			double dx = lx - cx, dy = ly - (cy + r*0.15), ang = Math.Atan2(dy, dx), dist = Math.Sqrt(dx*dx + dy*dy);
			if (ang > 0.3 && ang < 2.84) OverPx(img, x, y, 1, 226/255.0, 190/255.0, 0.22*InkP(Math.Abs(dist - r*1.05), r*0.45, px));
		}
		return img;
	}
	public static Img Lace()      // 64x8, along a lacing Line: the thong lit along its top, in shade along its bottom (white, tinted to the thong)
	{
		var img = new Img(64, 8);
		for (int y = 0; y < 8; y++) for (int x = 0; x < 64; x++)
		{
			double t = (y + 0.5)/8, l = t < 0.3 ? Lerp(1.0, 0.92, t/0.3) : t < 0.7 ? Lerp(0.92, 0.8, (t - 0.3)/0.4) : Lerp(0.8, 0.5, (t - 0.7)/0.3);
			img.Set(x, y, l, l, l, y == 0 || y == 7 ? 0.6 : 1);
		}
		return img;
	}
	public static Img Stitch()    // 64x32 at 320 px per bar height (.2 x .1), tiling along the bar: one running stitch, its shadow under it (white, tinted to the thread)
	{
		var img = new Img(64, 32); double px = 320, sp = 0.2, w = 0.035;
		var seg = Seg(sp*0.1, 0.05, sp*0.1 + sp*0.55, 0.05);
		StrokeH(img, Shift(seg, 0, w*0.45), w*1.35, px, new[] { 0.0, 0.0, 0.0 }, 0.42, false, true);
		StrokeH(img, seg, w, px, new[] { 0.88, 0.88, 0.88 }, 1, false, true);
		StrokeH(img, Shift(seg, -w*0.12, -w*0.22), w*0.32, px, new[] { 1.0, 1.0, 1.0 }, 0.55, false, true);
		return img;
	}
	// The lacing needle: steel, from its eye at the origin to its tip NEEDLE_L along +x, w .055 across. The atlas holds
	// NEEDLE_POSES cells at NEEDLE_ANG rad (tip pointing down-right, more steeply each cell), the eye at (NEEDLE_OX,
	// NEEDLE_OY) in each NEEDLE_SPAN-square cell; the addon flips cells left-right for the other lacing diagonal.
	public const int NEEDLE_POSES = 4, NEEDLE_CELL = 128;
	public const double NEEDLE_SPAN = 1.0, NEEDLE_OX = 0.25, NEEDLE_OY = 0.3, NEEDLE_L = 0.5;
	public static readonly double[] NEEDLE_ANG = { 0.44, 0.56, 0.70, 0.82 };
	static Src NeedleSource()
	{
		const double PX = 160, X0 = -0.1, Y0 = -0.1;
		var s = new Src { X0 = X0, Y0 = Y0, PX = PX, Img = new Img((int)(0.75*PX), (int)(0.2*PX)) };
		double L = NEEDLE_L, w = 0.055;
		var body = new List<double[]> { new[] { 0, -w/2 }, new[] { L*0.82, -w*0.36 }, new[] { L, 0 }, new[] { L*0.82, w*0.36 }, new[] { 0, w/2 } };
		for (int i = 1; i < 8; i++) { double a = Math.PI/2 + Math.PI*i/8; body.Add(new[] { Math.Cos(a)*w/2, Math.Sin(a)*w/2 }); }
		double[] sAt = { 0, 0.45, 1 }; double[][] steel = { Hex(0xeef0f4), Hex(0xa4a8b0), Hex(0x4c4f57) };
		var hl = Seg(L*0.25, -w*0.28, L*0.62, -w*0.2);
		for (int y = 0; y < s.Img.H; y++) for (int x = 0; x < s.Img.W; x++)
		{
			double lx = X0 + (x + 0.5)/PX, ly = Y0 + (y + 0.5)/PX, r = 0, g = 0, b = 0, a = 0;
			double cov = Cover(body, lx, ly, PX);
			if (cov > 0)
			{
				var c = Stops((ly + w/2)/w, sAt, steel);
				double ex = (lx - w*1.5)/(w*0.95), ey = ly/(w*0.2), eye = 0.9*Clamp((1 - Math.Sqrt(ex*ex + ey*ey))*w*0.2*PX + 0.5);
				for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], new[] { 20/255.0, 20/255.0, 24/255.0 }[q], eye);
				double h = 0.7*InkP(LineDist(hl, lx, ly, false), w*0.18, PX);
				for (int q = 0; q < 3; q++) c[q] = Lerp(c[q], 1, h);
				Over(ref r, ref g, ref b, ref a, c[0], c[1], c[2], cov);
			}
			if (a > 0) Put(s, x, y, r/a, g/a, b/a, a);
		}
		return s;
	}
	public static Img Needle() { return Poses(NeedleSource(), NEEDLE_ANG, 2, NEEDLE_CELL, NEEDLE_SPAN, NEEDLE_OX, NEEDLE_OY); }

	static double[] BoxBlur(double[] src, int w, int h, int rad)
	{
		var tmp = new double[w*h]; var dst = new double[w*h];
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
		{ double s = 0; int n = 0; for (int k = -rad; k <= rad; k++) { int xx = x + k; if (xx < 0 || xx >= w) continue; s += src[y*w + xx]; n++; } tmp[y*w + x] = s/(2*rad + 1); }
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
		{ double s = 0; for (int k = -rad; k <= rad; k++) { int yy = y + k; if (yy < 0 || yy >= h) continue; s += tmp[yy*w + x]; } dst[y*w + x] = s/(2*rad + 1); }
		return dst;
	}

	// ================================================================ live-drawn pieces (vines, flowers, twinkles)
	// ================================================================ LIGHTNING: painted clouds over a dark sky, forked bolts striking inside
	// storm_sky (the layer) is the dark sky behind the clouds. storm_cloud is the one cloud (StormCloud below), placed
	// as sprites by Effects_Storm.lua. p_bolts holds 4x2 forked bolts, each cell 2.5 by 1.25 bar heights (BOLT_PX per bar
	// height), the bolt running from 0.05 above the bar to 0.05 below it, the cell's top 0.075 above the bar.
	public static Img StormSky()
	{
		var img = new Img(W, H);
		var ramp = new[] { S(0, 22, 26, 60), S(0.6, 14, 16, 49), S(1, 7, 8, 26) };
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = x/(double)W, v = y/(double)H;
			var c = Ramp(v, ramp);
			double n = 1 + Fbm(u, v, 16, 2, 4, 611)*0.12;
			img.Set(x, y, Clamp(c[0]/255*n), Clamp(c[1]/255*n), Clamp(c[2]/255*n), 1);
		}
		return img;
	}

	// ---------------------------------------------------------------- the cloud: the user's reference painting, cut out
	// storm_cloud (512x256): the painted cloud of tools/ref_cloud.jpg (the user's indigo cloud painting, 2026-10-09, a JPEG
	// over a checkerboard, scaled to 1000 px wide), keyed as the concept
	// does (tools/concepts/lightning_sprites.js): alpha from how much bluer than red a pixel is (the checker is neutral),
	// the matte choked by a pixel, the edge pixels darkened toward the underside blue-grey so no light rim is left, the
	// alpha softened by a small blur (the colours stay sharp), then scaled to fill the texture's width; the cloud is
	// CLOUD_FILL of the texture's height. The game draws the whole texture at (2 / CLOUD_FILL) by (1 / CLOUD_FILL) of
	// the cloud height it wants (Effects_Storm.lua CLOUD_W/CLOUD_H).
	public const double CLOUD_FILL = 0.968;
	public static Img StormCloud(string path)
	{
		int sw, sh; double[] r, g, b;
		using (var bmp = new System.Drawing.Bitmap(path))
		{
			sw = bmp.Width; sh = bmp.Height; r = new double[sw*sh]; g = new double[sw*sh]; b = new double[sw*sh];
			for (int y = 0; y < sh; y++) for (int x = 0; x < sw; x++)
			{ var c = bmp.GetPixel(x, y); int i = y*sw + x; r[i] = c.R; g[i] = c.G; b[i] = c.B; }
		}
		int n = sw*sh;
		var A = new double[n];
		for (int i = 0; i < n; i++) A[i] = Clamp((b[i] - r[i] - 3)/9);
		var E = new double[n];   // the matte choked by a pixel
		for (int y = 0; y < sh; y++) for (int x = 0; x < sw; x++)
		{
			double m = 1;
			for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++)
			{
				int yy = Math.Min(sh-1, Math.Max(0, y+dy)), xx = Math.Min(sw-1, Math.Max(0, x+dx));
				m = Math.Min(m, A[yy*sw + xx]);
			}
			E[y*sw + x] = m;
		}
		for (int i = 0; i < n; i++)   // edge pixels darken toward the underside's dark indigo instead of carrying the checker's light grey
		{
			double k = (1 - E[i])*.6;
			r[i] = r[i]*(1-k) + 30*k; g[i] = g[i]*(1-k) + 26*k; b[i] = b[i]*(1-k) + 52*k;
		}
		// soften: a gaussian (sigma 1.2 px) over the choked alpha, squared against it, as the concept's blurred double pass
		double[] kern = { .086, .243, .343, .243, .086 };
		var T = new double[n]; var S = new double[n];
		for (int y = 0; y < sh; y++) for (int x = 0; x < sw; x++)
		{ double v = 0; for (int k = -2; k <= 2; k++) { int xx = Math.Min(sw-1, Math.Max(0, x+k)); v += E[y*sw + xx]*kern[k+2]; } T[y*sw + x] = v; }
		for (int y = 0; y < sh; y++) for (int x = 0; x < sw; x++)
		{ double v = 0; for (int k = -2; k <= 2; k++) { int yy = Math.Min(sh-1, Math.Max(0, y+k)); v += T[yy*sw + x]*kern[k+2]; } S[y*sw + x] = v; }
		for (int i = 0; i < n; i++) A[i] = S[i]*S[i]*E[i];
		// scale into the texture (bilinear, alpha-weighted so no dark fringe), the cloud filling the width, centred in the height
		const int TW = 512, TH = 256;
		double scale = TW/(double)sw, oy = (TH - sh*scale)/2;
		var img = new Img(TW, TH);
		for (int y = 0; y < TH; y++) for (int x = 0; x < TW; x++)
		{
			double sx = (x + .5)/scale - .5, sy = (y - oy + .5)/scale - .5;
			int x0 = (int)Math.Floor(sx), y0 = (int)Math.Floor(sy);
			double fx = sx - x0, fy = sy - y0;
			double ar = 0, ag = 0, ab = 0, aa = 0;
			for (int j = 0; j <= 1; j++) for (int i = 0; i <= 1; i++)
			{
				int xx = x0 + i, yy = y0 + j;
				if (xx < 0 || yy < 0 || xx >= sw || yy >= sh) continue;
				double wgt = (i == 0 ? 1 - fx : fx)*(j == 0 ? 1 - fy : fy), al = A[yy*sw + xx]*wgt;
				ar += r[yy*sw + xx]*al; ag += g[yy*sw + xx]*al; ab += b[yy*sw + xx]*al; aa += al;
			}
			if (aa <= 0.0005) { img.Set(x, y, 48/255.0, 54/255.0, 68/255.0, 0); continue; }
			img.Set(x, y, Clamp(ar/aa/255), Clamp(ag/aa/255), Clamp(ab/aa/255), Clamp(aa));
		}
		return img;
	}

	public const double BOLT_PX = 102.4;
	static List<double[]> StormJag(Random rnd, double x1, double y1, double x2, double y2, double disp, int levels)
	{
		var pts = new List<double[]> { new[] { x1, y1 }, new[] { x2, y2 } };
		double d = disp;
		for (int l = 0; l < levels; l++)
		{
			var next = new List<double[]> { pts[0] };
			for (int i = 1; i < pts.Count; i++)
			{
				double[] a = pts[i - 1], b = pts[i];
				double dx = b[0] - a[0], dy = b[1] - a[1], len = Math.Max(1e-6, Math.Sqrt(dx*dx + dy*dy)), o = Rnd(rnd, -d, d);
				next.Add(new[] { (a[0] + b[0])/2 - dy/len*o, (a[1] + b[1])/2 + dx/len*o }); next.Add(b);
			}
			pts = next; d *= .55;
		}
		return pts;
	}
	// Electricity, additive: a wide faint halo, a blue body and a white-hot core along a jagged bolt with forks.
	public static Img Bolts()
	{
		const int CW = 256, CH = 128; double P = BOLT_PX;
		var img = new Img(CW*4, CH*2);
		double[] dxs = { .4, .7, 1.0, 1.25, .55, .85, 1.1, 1.35 };
		double[] col = { 130/255.0, 170/255.0, 1 }, core = { Lerp(col[0], 1, .75), Lerp(col[1], 1, .75), 1 };
		var rnd = new Random(733);
		for (int c = 0; c < 8; c++)
		{
			int ox = (c % 4)*CW, oy = (c / 4)*CH;
			double x1 = CW/2.0 - dxs[c]*P/2, x2 = CW/2.0 + dxs[c]*P/2, y1 = .025*P, y2 = 1.125*P;
			if (c % 2 == 1) { double t = x1; x1 = x2; x2 = t; }
			var main = StormJag(rnd, x1, y1, x2, y2, .3*P, 5);
			var forks = new List<List<double[]>>();
			double len = Math.Sqrt((x2 - x1)*(x2 - x1) + (y2 - y1)*(y2 - y1)), ang0 = Math.Atan2(y2 - y1, x2 - x1);
			int nf = 1 + rnd.Next(3);
			for (int f = 0; f < nf; f++)
			{
				var a = main[(int)(Rnd(rnd, .2, .8)*main.Count)];
				double ang = ang0 + Rnd(rnd, .4, 1.0)*(rnd.NextDouble() < .5 ? -1 : 1), fl = len*Rnd(rnd, .18, .35);
				forks.Add(StormJag(rnd, a[0], a[1], a[0] + Math.Cos(ang)*fl, a[1] + Math.Sin(ang)*fl, .15*P, 4));
			}
			double w = .045*P;
			for (int y = 0; y < CH; y++) for (int x = 0; x < CW; x++)
			{
				double px = x + .5, py = y + .5, sum = 0, cr = 0, cg = 0, cb = 0;
				for (int s = 0; s <= forks.Count; s++)
				{
					var pts = s == 0 ? main : forks[s - 1];
					double ww = s == 0 ? w : w*.55, d = LineDist(pts, px, py, false);
					if (d > ww*8) continue;
					double halo = .10*Math.Exp(-(d/(3*ww))*(d/(3*ww))) + .22*Math.Exp(-(d/(1.6*ww))*(d/(1.6*ww)));
					double bodyA = .7*Smooth(.8*ww + 1, .8*ww - 1, d), coreA = .95*Smooth(Math.Max(.6, .3*ww) + .7, Math.Max(.6, .3*ww) - .7, d);
					sum += halo + bodyA + coreA;
					cr += (halo + bodyA)*col[0] + coreA*core[0]; cg += (halo + bodyA)*col[1] + coreA*core[1]; cb += (halo + bodyA)*col[2] + coreA*core[2];
				}
				if (sum <= 0) continue;
				img.Set(ox + x, oy + y, Clamp(cr/sum), Clamp(cg/sum), Clamp(cb/sum), Clamp(sum));
			}
		}
		return img;
	}

	// ================================================================ ALCHEMY: a bench of glassware on the bar, a trough of potion in it
	// alch_glass and alch_liquid are 4x2 atlases of 128x256 cells, one per station kind (boil, retort, cyl, erlen,
	// funnel, jacket, coil, rack), painted at ALCH_PX per station size S: the station's centre at the cell's middle
	// column, the bar's top edge at the cell's bottom. alch_glass is the glassware, burners, rods and racks;
	// alch_liquid is white where liquid can be (the addon crops it to the level and tints it). Station zones and
	// tube ends (Effects.lua ALCH_KINDS) are in station units: x from the centre, y up from the bar's top.
	public const double ALCH_PX = 96;
	static void AComp(Img img, int x, int y, double r, double g, double b, double a)   // straight-alpha "over"
	{
		if (a <= 0 || x < 0 || y < 0 || x >= img.W || y >= img.H) return;
		int i = y*img.W + x; double da = img.A[i], oa = a + da*(1 - a);
		if (oa <= 0) return;
		img.R[i] = (r*a + img.R[i]*da*(1 - a))/oa; img.G[i] = (g*a + img.G[i]*da*(1 - a))/oa; img.B[i] = (b*a + img.B[i]*da*(1 - a))/oa;
		img.A[i] = oa;
	}
	class ACell { public Img img; public double ox, oy; public double ylo = -9, yhi = 9; }   // station origin in pixels; paint only ylo..yhi
	static List<double[]> APix(ACell c, List<double[]> pts)
	{
		var o = new List<double[]>();
		foreach (var p in pts) o.Add(new[] { c.ox + p[0]*ALCH_PX, c.oy - p[1]*ALCH_PX });
		return o;
	}
	static bool AInY(ACell c, double py) { double Y = (c.oy - py)/ALCH_PX; return Y >= c.ylo && Y <= c.yhi; }
	static void AFill(ACell c, List<double[]> pts, double[] col, double a)
	{
		var p = APix(c, pts); var bb = Bbox(p);
		for (int y = (int)Math.Floor(bb[1]) - 1; y <= (int)Math.Ceiling(bb[3]) + 1; y++)
		for (int x = (int)Math.Floor(bb[0]) - 1; x <= (int)Math.Ceiling(bb[2]) + 1; x++)
		{
			if (!AInY(c, y + .5)) continue;
			double cov = Cover(p, x + .5, y + .5, 1);
			if (cov > 0) AComp(c.img, x, y, col[0], col[1], col[2], a*cov);
		}
	}
	static void AStroke(ACell c, List<double[]> pts, bool closed, double w, double[] col, double a)
	{
		var p = APix(c, pts); var bb = Bbox(p); double hw = w*ALCH_PX/2;
		for (int y = (int)Math.Floor(bb[1] - hw) - 1; y <= (int)Math.Ceiling(bb[3] + hw) + 1; y++)
		for (int x = (int)Math.Floor(bb[0] - hw) - 1; x <= (int)Math.Ceiling(bb[2] + hw) + 1; x++)
		{
			if (!AInY(c, y + .5)) continue;
			double cov = Clamp(hw - LineDist(p, x + .5, y + .5, closed) + .5);
			if (cov > 0) AComp(c.img, x, y, col[0], col[1], col[2], a*cov);
		}
	}
	static List<double[]> AArc(double cx, double cy, double rx, double ry, double a0, double a1, int n)
	{
		var p = new List<double[]>();
		for (int i = 0; i <= n; i++) { double a = a0 + (a1 - a0)*i/n; p.Add(new[] { cx + Math.Cos(a)*rx, cy + Math.Sin(a)*ry }); }
		return p;
	}
	static List<double[]> ARect(double x0, double y0, double x1, double y1)
	{ return new List<double[]> { new[] { x0, y0 }, new[] { x1, y0 }, new[] { x1, y1 }, new[] { x0, y1 } }; }
	static List<double[]> ABez(double[] a, double[] b, double[] c, double[] d, int n)
	{ return Bez(a[0], a[1], b[0], b[1], c[0], c[1], d[0], d[1], n); }
	static readonly double[] GLASS_IN = { 160/255.0, 205/255.0, 240/255.0 }, GLASS_LINE = { 215/255.0, 240/255.0, 1 }, WHITE = { 1, 1, 1 };
	static readonly double[] TUBE_OUT = { 205/255.0, 235/255.0, 1 }, TUBE_DARK = { 8/255.0, 12/255.0, 20/255.0 }, HOSE = { 120/255.0, 52/255.0, 24/255.0 };
	static void AGlass(ACell c, List<double[]> body, List<double[]> shine, bool liquid)
	{
		if (liquid) { AFill(c, body, WHITE, 1); return; }
		AFill(c, body, GLASS_IN, .12);
		AStroke(c, body, true, .04, GLASS_LINE, .8);
		if (shine != null) AStroke(c, shine, false, .035, WHITE, .6);
	}
	static void ACork(ACell c, double nw, double yt)
	{
		double cw = nw*1.2, ch = .08;
		AFill(c, ARect(-cw/2, yt - .4*ch, cw/2, yt + .6*ch), Hex(0x8a5a32), 1);
		AFill(c, ARect(-cw/2, yt + .3*ch, cw/2, yt + .6*ch), new[] { 1, 220/255.0, 170/255.0 }, .3);
	}
	static void ABurner(ACell c, double bx)
	{
		const double legH = .34, r = .3;
		AStroke(c, new List<double[]> { new[] { bx - r, 0.0 }, new[] { bx - r*.75, legH } }, false, .045, Hex(0x6e6964), 1);
		AStroke(c, new List<double[]> { new[] { bx + r, 0.0 }, new[] { bx + r*.75, legH } }, false, .045, Hex(0x6e6964), 1);
		var baseE = AArc(bx, .03, r*.5, .05, 0, 2*Math.PI, 24);
		AFill(c, baseE, Hex(0x3d3024), 1); AStroke(c, baseE, true, .012, Hex(0xa07a45), 1);
		AFill(c, ARect(bx - r*.12, .007, bx + r*.12, .119), Hex(0x5a4a3a), 1);
		AStroke(c, new List<double[]> { new[] { bx - .26, legH }, new[] { bx + .26, legH } }, false, .045, Hex(0xa09b96), 1);
	}
	static void ARod(ACell c, double x, double y1)
	{
		AStroke(c, new List<double[]> { new[] { x, 0.0 }, new[] { x, y1 } }, false, .045, Hex(0x787673), 1);
		AStroke(c, new List<double[]> { new[] { x - .01, 0.0 }, new[] { x - .01, y1 } }, false, .015, Hex(0xe6e6e1), .35);
		AFill(c, ARect(x - .12, 0, x + .12, .05), Hex(0x2e2a26), 1);
	}
	static void AClamp(ACell c, double x0, double x1, double y)
	{
		AStroke(c, new List<double[]> { new[] { x0, y }, new[] { x1, y } }, false, .035, Hex(0x8c6a3c), 1);
		AFill(c, AArc(x0, y, .035, .035, 0, 2*Math.PI, 12), Hex(0xb08a4e), 1);
	}
	static void ATube(ACell c, List<double[]> pts, double tw, bool liquid)
	{
		if (liquid) { AStroke(c, pts, false, tw*.56, WHITE, 1); return; }
		AStroke(c, pts, false, tw, TUBE_OUT, .6);
		AStroke(c, pts, false, tw*.62, TUBE_DARK, .65);
		var sh = new List<double[]>(); foreach (var p in pts) sh.Add(new[] { p[0] - tw*.1, p[1] + tw*.24 });
		AStroke(c, sh, false, Math.Max(.006, tw*.14), WHITE, .4);
	}
	// vial: a rounded tube w wide, h tall, standing at x
	static List<double[]> AVial(double x, double w, double h)
	{
		var p = new List<double[]>(); double r = w*.4;
		p.AddRange(AArc(x + w/2 - r, r, r, r, -Math.PI/2, 0, 6)); p.AddRange(AArc(x + w/2 - r, h - r, r, r, 0, Math.PI/2, 6));
		p.AddRange(AArc(x - w/2 + r, h - r, r, r, Math.PI/2, Math.PI, 6)); p.AddRange(AArc(x - w/2 + r, r, r, r, Math.PI, Math.PI*1.5, 6));
		return p;
	}
	static void AStation(ACell c, int kind, bool liquid)
	{
		const double tw = .075;
		if (kind == 0 || kind == 1)   // boil: a round flask over a burner; retort: a bulb with a long neck, over a burner
		{
			double r = .285, yb = .235, bx = kind == 0 ? 0 : -.12, cy = yb + r;
			if (!liquid) ABurner(c, bx);
			if (kind == 0)
			{
				double nw = .1235, a = Math.Asin(nw/2/r), yt = yb + 2*r + .304;
				var body = new List<double[]> { new[] { -nw/2, yt } };
				body.AddRange(AArc(0, cy, r, r, Math.PI/2 + a, Math.PI*2.5 - a, 40));
				body.Add(new[] { nw/2, yt });
				if (liquid) c.ylo = .235; if (liquid) c.yhi = .748;
				AGlass(c, body, AArc(0, cy, r*.7, r*.7, .6*Math.PI, .92*Math.PI, 10), liquid);
				if (!liquid) ACork(c, nw, yt);
			}
			else
			{
				double ta = .75, dl = Math.Asin(.057/r), L = .5225, h = .057;
				double[] d = { Math.Cos(ta), Math.Sin(ta) }, n = { -Math.Sin(ta), Math.Cos(ta) };
				double[] tip = { bx + d[0]*(r + L), cy + d[1]*(r + L) };
				var body = new List<double[]> { new[] { tip[0] + n[0]*h, tip[1] + n[1]*h } };
				body.AddRange(AArc(bx, cy, r, r, ta + dl, ta - dl + 2*Math.PI, 44));
				body.Add(new[] { tip[0] - n[0]*h, tip[1] - n[1]*h });
				if (liquid) { c.ylo = .235; c.yhi = .805; }
				AGlass(c, body, AArc(bx, cy, r*.7, r*.7, .65*Math.PI, Math.PI, 10), liquid);
			}
			if (!liquid) AStroke(c, new List<double[]> { new[] { bx - .26, .34 }, new[] { bx + .26, .34 } }, false, .045, Hex(0xa09b96), 1);
		}
		else if (kind == 2)   // a tall graduated cylinder on a foot
		{
			double w = .22, yb = .07, yt = 1.22, h = yt - yb;
			if (!liquid) AFill(c, AArc(0, .035, .2, .04, 0, 2*Math.PI, 24), Hex(0x4a4f57), 1);
			var body = new List<double[]> { new[] { -w/2, yt }, new[] { -w/2, yb }, new[] { w/2, yb }, new[] { w/2, yt - .03 }, new[] { w/2 + .04, yt + .015 } };
			if (liquid) { c.ylo = .07; c.yhi = 1.105; }
			AGlass(c, body, new List<double[]> { new[] { -w*.25, yt - h*.1 }, new[] { -w*.25, yb + h*.08 } }, liquid);
			if (!liquid) for (int k = 1; k < 8; k++)
			{
				double y = yb + h*k/8, L = k % 2 == 1 ? .04 : .07;
				AStroke(c, new List<double[]> { new[] { w/2, y }, new[] { w/2 - L, y } }, false, .012, new[] { 230/255.0, 245/255.0, 1 }, .55);
			}
		}
		else if (kind == 3)   // an erlenmeyer
		{
			double bw = .62, nw = .15, ys = .58, yt = .88, k = .05;
			var body = new List<double[]> { new[] { -nw/2, yt }, new[] { -nw/2, ys }, new[] { -bw/2, k } };
			body.AddRange(Quad(-bw/2, k, -bw/2, 0, -bw/2 + k, 0, 4)); body.Add(new[] { bw/2 - k, 0.0 });
			body.AddRange(Quad(bw/2 - k, 0, bw/2, 0, bw/2, k, 4)); body.Add(new[] { nw/2, ys }); body.Add(new[] { nw/2, yt });
			if (liquid) { c.ylo = 0; c.yhi = .52; }
			AGlass(c, body, new List<double[]> { new[] { -nw*.3, ys - .06 }, new[] { -bw*.3, .1 } }, liquid);
			if (!liquid) ACork(c, nw, yt);
		}
		else if (kind == 4)   // a separatory funnel on a rod, dripping into a beaker
		{
			double w = .437, hb = .399, ybf = .699, bw = .418, nw = .114, ytf = 1.5065;
			var beaker = new List<double[]> { new[] { -w/2 - .0285, hb }, new[] { -w/2, hb - .0285 }, new[] { -w/2, 0.0 }, new[] { w/2, 0.0 }, new[] { w/2, hb } };
			var funnel = new List<double[]> { new[] { -nw/2, ytf }, new[] { -nw/2, ytf - .0665 } };
			funnel.AddRange(ABez(new[] { -nw/2, ytf - .0665 }, new[] { -bw*.75, ytf - .152 }, new[] { -bw*.55, ytf - .494 }, new[] { -.024, ybf }, 16));
			funnel.Add(new[] { .024, ybf });
			funnel.AddRange(ABez(new[] { .024, ybf }, new[] { bw*.55, ytf - .494 }, new[] { bw*.75, ytf - .152 }, new[] { nw/2, ytf - .0665 }, 16));
			funnel.Add(new[] { nw/2, ytf });
			if (liquid)
			{
				c.ylo = .699; c.yhi = 1.288; AFill(c, funnel, WHITE, 1);
				c.ylo = 0; c.yhi = .319; AFill(c, beaker, WHITE, 1);
				return;
			}
			ARod(c, -.42, ytf + .1);
			AClamp(c, -.42, -.115, ytf - .2);
			AStroke(c, AArc(0, ytf - .2, .199, .04, 0, 2*Math.PI, 24), true, .03, Hex(0x969696), .9);
			AGlass(c, funnel, ABez(new[] { -bw*.28, ytf - .19 }, new[] { -bw*.3, ytf - .35 }, new[] { -bw*.2, ytf - .55 }, new[] { -bw*.08, ybf + .114 }, 10), false);
			AStroke(c, new List<double[]> { new[] { 0.0, ybf }, new[] { 0.0, .319 } }, false, .045, TUBE_OUT, .75);
			AFill(c, ARect(-.05, ybf - .09, .05, ybf - .04), Hex(0xe9e4d8), 1);
			AStroke(c, new List<double[]> { new[] { -.064, ybf - .1 }, new[] { .064, ybf - .03 } }, false, .035, Hex(0x3a6fb0), 1);
			AGlass(c, beaker, new List<double[]> { new[] { -w*.32, hb - hb*.2 }, new[] { -w*.32, hb*.15 } }, false);
		}
		else if (kind == 5)   // a jacketed condenser on a rod: coolant round an inner tube
		{
			double y0 = .22, y1 = 1.27, jw = .26;
			var inner = new List<double[]> { new[] { 0.0, y1 + .12 }, new[] { 0.0, y0 - .1 } };
			if (liquid) { c.ylo = .12; c.yhi = 1.39; ATube(c, inner, tw*.9, true); return; }
			ARod(c, -.38, y1 + .05);
			AClamp(c, -.38, -jw/2, (y0 + y1)/2);
			var jacket = RoundRect(-jw/2, y0, jw, y1 - y0, jw*.35);
			AFill(c, jacket, new[] { 90/255.0, 170/255.0, 1 }, .22);
			AStroke(c, jacket, true, .035, GLASS_LINE, .8);
			AStroke(c, Quad(jw/2, y1 - .12, jw, y1 - .1, jw*1.05, y1 - .3, 8), false, tw, HOSE, .95);
			AStroke(c, Quad(-jw/2, y0 + .12, -jw, y0 + .1, -jw*.95, y0 - .05, 8), false, tw, HOSE, .95);
			for (int k = 0; k < 5; k++) AFill(c, AArc((k % 2 == 1 ? 1 : -1)*jw*.28, y0 + (y1 - y0)*(k + .5)/5, .018, .018, 0, 2*Math.PI, 8), new[] { 220/255.0, 240/255.0, 1 }, .55);
			ATube(c, inner, tw*.9, false);
		}
		else if (kind == 6)   // a glass coil on a rod
		{
			double yT = 1.15, yB = .2, turns = 3.5, R = .2;
			var coil = new List<double[]> { new[] { 0.0, yT + .12 } };
			double u = 0;
			for (; u <= 2*Math.PI*turns; u += .15) coil.Add(new[] { R*Math.Sin(u), yT - (yT - yB)*u/(2*Math.PI*turns) - R*.32*Math.Cos(u) });
			coil.Add(new[] { coil[coil.Count - 1][0], yB - .08 });
			if (liquid) { c.ylo = .12; c.yhi = 1.27; ATube(c, coil, tw, true); return; }
			ARod(c, -.36, yT + .12);
			AClamp(c, -.36, -.2, yT - .08);
			ATube(c, coil, tw, false);
		}
		else   // a rack of three vials joined by little glass arches
		{
			double[] xs = { -.3, 0, .3 }, ks = { .62, .7, .58 };
			var tops = new double[3];
			for (int k = 0; k < 3; k++) tops[k] = ks[k]*.95;
			if (liquid) { c.ylo = 0; c.yhi = .565; }
			for (int k = 0; k < 3; k++)
			{
				double w = ks[k]*.26, h = tops[k];
				AGlass(c, AVial(xs[k], w, h), new List<double[]> { new[] { xs[k] - w*.2, h*.82 }, new[] { xs[k] - w*.2, h*.2 } }, liquid);
				if (!liquid) ACork(c, w/1.2*1.0, h);
			}
			if (liquid) return;
			for (int k = 0; k < 2; k++)
			{
				double top = Math.Max(tops[k], tops[k + 1]) + .12;
				ATube(c, ABez(new[] { xs[k], tops[k] }, new[] { xs[k], top }, new[] { xs[k + 1], top }, new[] { xs[k + 1], tops[k + 1] }, 16), tw*.8, false);
			}
			AFill(c, ARect(-.5, .16, .5, .24), Hex(0x6b4529), 1);
			AFill(c, ARect(-.5, .215, .5, .24), new[] { 1, 210/255.0, 160/255.0 }, .25);
			AFill(c, ARect(-.5, 0, -.45, .24), Hex(0x4a2f18), 1); AFill(c, ARect(.45, 0, .5, .24), Hex(0x4a2f18), 1);
		}
	}
	public static Img AlchAtlas(bool liquid)
	{
		var img = new Img(512, 512);
		for (int k = 0; k < 8; k++)
		{
			var c = new ACell { img = img, ox = (k % 4)*128 + 64, oy = (k / 4)*256 + 256 };
			AStation(c, k, liquid);
		}
		return img;
	}
	// a bunsen flame, additive: blue at the root, warm toward the tip; the addon sizes it with the heat
	public static Img AlchFlame()
	{
		var img = new Img(32, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 32; x++)
		{
			double v = 1 - (y + .5)/64, u = (x + .5)/32 - .5;   // v: 0 at the root, 1 at the tip
			double hw = .46*Math.Pow(Math.Sin(Math.PI*Math.Min(1, (v + .08)/1.08)), .8)*(1 - .55*v);
			double cov = Smooth(hw + .04, hw - .04, Math.Abs(u)), inner = Smooth(hw*.55 + .04, hw*.55 - .04, Math.Abs(u))*Smooth(.75, .2, v);
			double r = Lerp(60, 255, Smooth(.2, .9, v))/255, g = Lerp(110, 130, v)/255, b = Lerp(255, 40, Smooth(.2, .9, v))/255;
			r = Lerp(r, 150/255.0, inner); g = Lerp(g, 200/255.0, inner); b = Lerp(b, 1, inner);
			img.Set(x, y, r, g, b, Clamp(cov*(1 - v*v*.85) + inner*.4));
		}
		return img;
	}
	// a brass valve: closed (handle across the tube) in the left cell, open (handle along it) in the right
	public static Img AlchValve()
	{
		var img = new Img(64, 32);
		for (int cell = 0; cell < 2; cell++)
		for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++)
		{
			double dx = x + .5 - 16, dy = y + .5 - 16, r = Math.Sqrt(dx*dx + dy*dy);
			double disc = Smooth(9, 8, r), rim = Smooth(1.2, 0, Math.Abs(r - 8.5));
			double hx = cell == 0 ? dy : dx, hy = cell == 0 ? dx : dy;
			double handle = Smooth(2.6, 1.6, Math.Abs(hy))*Smooth(14.5, 13.5, Math.Abs(hx));
			double rr = Lerp(201, 232, handle)/255, gg = Lerp(162, 211, handle)/255, bb = Lerp(90, 160, handle)/255;
			rr = Lerp(rr, 40/255.0, rim*.8*(1 - handle)); gg = Lerp(gg, 25/255.0, rim*.8*(1 - handle)); bb = Lerp(bb, 5/255.0, rim*.8*(1 - handle));
			img.Set(cell*32 + x, y, rr, gg, bb, Math.Max(disc, handle));
		}
		return img;
	}
	// the bench trough (the alchemy layer): dark glass, a faint highlight near the top
	public static Img AlchTrough()
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = x/(double)W, v = (y + .5)/H, n = Fbm(u, v, 16, 2, 3, 671)*.04;
			double r = Lerp(32, 8, v)/255 + n, g = Lerp(40, 10, v)/255 + n, b = Lerp(54, 16, v)/255 + n;
			double hl = Smooth(.06, .08, v)*Smooth(.13, .11, v)*.12;
			img.Set(x, y, Clamp(Lerp(r, 1, hl)), Clamp(Lerp(g, 1, hl)), Clamp(Lerp(b, 1, hl)), .95);
		}
		return img;
	}
	// one column of the potion, from its surface (top) down to the trough's floor: a light band under the surface,
	// darker with depth. White: the addon tints each column with the potion's colour where it stands.
	public static Img AlchColumn()
	{
		// The liquid's body, shaded by height in the BAR (v 0 = the bar's top, 1 = its bottom), not by the column:
		// every column samples the same rows at the same height, so neighbours match and no vertical lines show.
		// The surface's highlight is drawn separately as one continuous line (Effects.lua UpdateTrough).
		// Opaque: the columns overlap by a pixel, and a translucent overlap shows as stripes.
		var img = new Img(8, 128);
		for (int y = 0; y < 128; y++) for (int x = 0; x < 8; x++)
		{
			double v = (y + .5)/128;
			double L = Lerp(1, .6, Smooth(0, 1, v));   // as the concept: full colour near the top, half as deep as the bar
			img.Set(x, y, Clamp(L*.9), Clamp(L*.9), Clamp(L*.9), 1);
		}
		return img;
	}
	// the light caught just under the potion's surface: a soft white band, brightest along its middle and fading
	// to both edges. Drawn as Lines along the surface (Effects.lua UpdateTrough), so it follows the surface at any
	// level, which the columns (shaded by height in the bar) cannot.
	public static Img AlchBand()
	{
		var img = new Img(8, 32);
		for (int y = 0; y < 32; y++) for (int x = 0; x < 8; x++)
		{
			double v = (y + .5)/32, a = Math.Pow(Math.Sin(Math.PI*v), 1.4);
			img.Set(x, y, 1, 1, 1, a);
		}
		return img;
	}

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
	// edge_h: a left-to-right fade over the texture's width, used as a soft gradient (skinning's shade ahead
	// of the roll, blacksmithing's hot edge, lightning's leading glow). No ragged edge masks: bars are framed.
	// ---------------------------------------------------------------- corners and depth (Bar.lua)
	// Signed distance to a rectangle rounded at its left corners only (it runs on to the right): negative inside.
	static double RoundLeft(double x, double y, double x0, double y0, double y1, double R)
	{
		double cy = (y0 + y1)/2, hh = (y1 - y0)/2;
		double qx = (x0 + R) - x, qy = Math.Abs(y - cy) - (hh - R);
		double ox = Math.Max(qx, 0), oy = Math.Max(qy, 0);
		return Math.Sqrt(ox*ox + oy*oy) + Math.Min(Math.Max(qx, qy), 0) - R;
	}
	static double Cov(double d) { return Clamp(0.5 - d); }
	// The corner mask: the bar's left end square (64 px = one bar height) with its left corners rounded by r bar
	// heights, white. Bar.lua anchors it to the bar's left end, and mirrored to its right end, on every texture that
	// reaches the bar's edges. r = 0 is the all-white square mask.
	public static Img CornerMask(double r)
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
			img.Set(x, y, 1, 1, 1, r <= 0 ? 1 : Cov(RoundLeft(x + 0.5, y + 0.5, 0, 0, 64, r*64)));
		return img;
	}
	// The frame line's end cap for rounded corners (Bar.lua LayoutBorder): the square reaching e outside the bar on
	// every side, S = 1 + 2e bar heights across, where the dark line is td = .1 bar heights thick with e = 2/3 of it
	// outside the bar, and the lit line inside it is td/2 thick ending at the bar's edge. Painted white; Bar.lua tints
	// the dark one black and the lit one in the look's colour. Mirrored for the right end.
	public static Img CapRing(double r, bool lit)
	{
		const double td = 0.1, e = td*2/3, tl = td/2, S = 1 + 2*e;
		double s = 64/S, Ro = (r + e)*s;   // texture px per bar height; the dark line's outer corner radius
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double px = x + 0.5, py = y + 0.5, a;
			if (!lit)
			{
				double i = td*s;
				a = Cov(RoundLeft(px, py, 0, 0, 64, Ro)) - Cov(RoundLeft(px, py, i, i, 64 - i, Math.Max(0, Ro - i)));
			}
			else
			{
				double o = (e - tl)*s, i = e*s;
				a = Cov(RoundLeft(px, py, o, o, 64 - o, Math.Max(0, Ro - o))) - Cov(RoundLeft(px, py, i, i, 64 - i, Math.Max(0, Ro - i)));
			}
			img.Set(x, y, 1, 1, 1, Clamp(a));
		}
		return img;
	}
	// The frame's middle piece (Bar.lua): an 8x64 strip holding the top and bottom lines, taken from the cap's own
	// straight part (its last column), so the lines between the caps have exactly the caps' thickness and
	// anti-aliasing at every height. Stretched between the two caps; uniform along x.
	public static Img StripRing(double r, bool lit)
	{
		var cap = CapRing(r, lit);
		var img = new Img(8, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 8; x++) img.Set(x, y, 1, 1, 1, cap.A[y*64 + 63]);
		return img;
	}
	public static Img BevelV()   // 8x64, white: alpha 1 along the top fading to 0 at the bottom (the bevel's light, shade and inner shadow)
	{
		var img = new Img(8, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 8; x++) { double v = (y + 0.5)/64; img.Set(x, y, 1, 1, 1, 1 - v); }
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

	// ================================================================ ENCHANTING: the velvet, the flow of settled magic, the vortex, dust, essence
	// The velvet the magic settles on (concept makeVelvet), neutral: the addon tints it to the cast's palette (its deep colour,
	// the top a little toward the main one; ench_velvet_hi is added over it in the palette's main/accent for the mottling
	// and the pale specks). Brightness: a vertical gradient, soft mottling, fine grain; at most .78 so the mottles can rise above it.
	public static Img EnchVelvet()
	{
		var img = new Img(W, H);
		var rnd = new Random(8101);
		int n = 60; var bx = new double[n]; var by = new double[n]; var br = new double[n];
		for (int i = 0; i < n; i++) { bx[i] = rnd.NextDouble()*W; by[i] = rnd.NextDouble()*H; br[i] = H*(0.3 + 0.6*rnd.NextDouble()); }
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double v = (y + 0.5)/H;
			double lum = v < 0.55 ? Lerp(1.0, 0.85, v/0.55) : Lerp(0.85, 0.5, (v - 0.55)/0.45);
			double m = 0;
			for (int i = 0; i < n; i++) { double dx = WrapDx(x, bx[i], W), dy = y - by[i]; double d = Math.Sqrt(dx*dx + dy*dy)/br[i]; if (d < 1) m += (1 - d)*(1 - d)*0.16; }
			double g = 0.78*lum*(1 + m) + Fbm(x/(double)W, v, 32, 4, 3, 8102)*0.03;
			img.Set(x, y, Clamp(g), Clamp(g), Clamp(g), 1);
		}
		return img;
	}
	// ADD over the velvet: the coloured mottling (main and accent in the concept; one tint here) and a scatter of tiny pale specks.
	public static Img EnchVelvetHi()
	{
		var img = new Img(W, H);
		var rnd = new Random(8111);
		int n = 70; var bx = new double[n]; var by = new double[n]; var br = new double[n];
		for (int i = 0; i < n; i++) { bx[i] = rnd.NextDouble()*W; by[i] = rnd.NextDouble()*H; br[i] = H*(0.3 + 0.6*rnd.NextDouble()); }
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double m = 0;
			for (int i = 0; i < n; i++) { double dx = WrapDx(x, bx[i], W), dy = y - by[i]; double d = Math.Sqrt(dx*dx + dy*dy)/br[i]; if (d < 1) m += (1 - d)*(1 - d); }
			double g = Clamp(m*0.45);
			img.Set(x, y, g, g, g, 1);
		}
		for (int i = 0; i < 240; i++)
		{
			int sx = rnd.Next(W), sy = rnd.Next(H); double a = 0.25 + 0.75*rnd.NextDouble();
			double g = Clamp(img.R[sy*W + sx] + a);
			img.Set(sx, sy, g, g, g, 1);
		}
		return img;
	}
	// The settled power's flow (concept drawFlow, one texture per band): the region under a sine wave, lit by a vertical
	// gradient that peaks at mid-height, so a band of light waxes and wanes along the bar. White, ADD, tinted to the palette
	// (band 0 main, band 1 accent). Band k runs 2 + k whole waves across the texture, so it tiles: in bar heights the
	// texture is 11.4 (k = 0) or 12.6 (k = 1) wide at the concept's wavelengths (Effects.lua ENCH_FLOW).
	public static Img EnchFlow(int k)
	{
		var img = new Img(W, H);
		int periods = 2 + k; double ph = k == 0 ? 0.6 : 2.9;
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (x + 0.5)/W, v = (y + 0.5)/H;
			double wave = 0.45 + k*0.1 + Math.Sin(u*2*Math.PI*periods + ph)*0.25;
			double grad = v < 0.5 ? v/0.5 : (1 - v)/0.5;
			double a = Smooth(wave - 0.025, wave + 0.025, v)*grad;
			img.Set(x, y, 1, 1, 1, Clamp(a));
		}
		return img;
	}
	// The vortex (concept drawVortex): six tilted rings of light at the cast edge, each an open arc (two thirds of the ring)
	// that spins at its own rate, tighter toward the throat. Nothing turns in game: this atlas holds every ring at
	// VORTEX_COLS spin phases, and the addon shows the cell for the time; mirrored cells spin the other way (disenchant).
	// 1024x512: a cell is 64 px = 1.4 bar heights square, the vortex's centre at its middle; columns are the phases, rows the rings.
	public const int VORTEX_COLS = 16, VORTEX_ROWS = 6, VORTEX_PX = 64;
	public static Img Vortex()
	{
		var img = new Img(VORTEX_COLS*VORTEX_PX, 512);
		double hpx = VORTEX_PX/1.4;   // px per bar height
		int N = 160;
		var xs = new double[N + 1]; var ys = new double[N + 1];
		for (int row = 0; row < VORTEX_ROWS; row++)
		{
			double k = row/5.0, rx = hpx*Lerp(0.36, 0.1, k), ry = hpx*Lerp(0.62, 0.2, k), cx0 = hpx*0.05*k, lw = Math.Max(1.2, hpx*0.035);
			for (int col = 0; col < VORTEX_COLS; col++)
			{
				double sp = col*2*Math.PI/VORTEX_COLS;
				for (int i = 0; i <= N; i++)
				{
					double th = sp + 4.2*i/N, px = rx*Math.Cos(th), py = ry*Math.Sin(th);
					xs[i] = cx0 + px*Math.Cos(0.25) - py*Math.Sin(0.25);
					ys[i] = px*Math.Sin(0.25) + py*Math.Cos(0.25);
				}
				int ox = col*VORTEX_PX, oy = row*VORTEX_PX;
				for (int y = 0; y < VORTEX_PX; y++) for (int x = 0; x < VORTEX_PX; x++)
				{
					double qx = x + 0.5 - VORTEX_PX/2.0, qy = y + 0.5 - VORTEX_PX/2.0, d = 1e9;
					for (int i = 0; i < N; i++) d = Math.Min(d, SegDist(qx, qy, xs[i], ys[i], xs[i + 1], ys[i + 1]));
					// the arc fades in at its tail and is brightest at its head, as a spinning streak
					double core = Clamp((lw/2 - d) + 0.5), halo = Math.Exp(-d*d/(2*lw*lw))*0.45;
					double a = Clamp(core + halo);
					img.Set(ox + x, oy + y, 1, 1, 1, a);
				}
			}
		}
		return img;
	}
	// A hard little disc with a soft edge (the dust grains' centres), white.
	public static Img Dot()
	{
		var img = new Img(32, 32);
		for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++)
		{
			double dx = (x - 15.5)/16.0, dy = (y - 15.5)/16.0, r = Math.Sqrt(dx*dx + dy*dy);
			img.Set(x, y, 1, 1, 1, Smooth(0.75, 0.55, r));
		}
		return img;
	}
	// An essence mote (concept drawEssence): a bright core in a soft glow with a thin flat ring of light round it. White,
	// tinted to the palette's accent; the addon adds a wider glow in the main colour under it. 64 px = 4 mote radii.
	public static Img Essence()
	{
		var img = new Img(64, 64);
		double r = 16;
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/r, dy = (y - 31.5)/r, d = Math.Sqrt(dx*dx + dy*dy);
			double mid = 0.55*Math.Exp(-d*d/(1.4*1.4)*1.6), core = 0.9*Math.Exp(-d*d/(0.6*0.6)*1.4);
			double e = Math.Sqrt(dx*dx/(1.9*1.9) + dy*dy/(0.55*0.55));
			double ring = 0.45*Smooth(0.22, 0.08, Math.Abs(e - 1));
			double a = 1 - (1 - mid)*(1 - core)*(1 - ring);
			img.Set(x, y, 1, 1, 1, Clamp(a));
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
	'frost_water' = { [CastbarArt]::FrostWater() };  'frost_water_hi' = { [CastbarArt]::FrostWaterHi() }
	'frost_front' = { [CastbarArt]::FrostFront() }
	'fish_water' = { [CastbarArt]::FishWater() };   'fish_caustic' = { [CastbarArt]::FishCaustic() }
	'mine_rails' = { [CastbarArt]::MineRails() };   'mine_flow'   = { [CastbarArt]::MineFlow() }
	'p_lily'     = { [CastbarArt]::LilyPad() };     'p_fish'      = { [CastbarArt]::Fish() }
	'p_bobber'   = { [CastbarArt]::Bobber() };      'p_ripple'    = { [CastbarArt]::Ripple() }
	'p_cart'     = { [CastbarArt]::Cart() };        'p_wheel'     = { [CastbarArt]::Wheel() }
	'p_pickaxe'  = { [CastbarArt]::Pickaxe() }
	'skin_fur'   = { [CastbarArt]::SkinFur() };     'skin_fur_hi' = { [CastbarArt]::SkinFurHi() }
	'skin_meat'  = { [CastbarArt]::SkinMeat() };    'p_pool'      = { [CastbarArt]::PoolBlots() }
	'p_roll_fur' = { [CastbarArt]::RollFur() };     'p_roll_mask' = { [CastbarArt]::RollMask() }
	'p_roll_shade' = { [CastbarArt]::RollShade() }; 'p_roll_end'  = { [CastbarArt]::RollEnd() }
	'p_roll_spiral' = { [CastbarArt]::RollSpiral() }
	'p_knife_wood' = { [CastbarArt]::Knife($false) }; 'p_knife_antler' = { [CastbarArt]::Knife($true) }
	'smith_iron' = { [CastbarArt]::SmithIron() };   'smith_hot'   = { [CastbarArt]::SmithHot() }
	'smith_edge' = { [CastbarArt]::SmithEdge() };   'smelt_seam'  = { [CastbarArt]::SmeltSeam() }
	'smith_cold' = { [CastbarArt]::SmithCold() };   'smith_temper' = { [CastbarArt]::SmithTemper() }
	'p_hammer_wood' = { [CastbarArt]::Hammer($false) }; 'p_hammer_antler' = { [CastbarArt]::Hammer($true) }
	'smelt_crust' = { [CastbarArt]::SmeltCrust() }; 'smelt_hot'   = { [CastbarArt]::SmeltHot() }
	'smelt_stream' = { [CastbarArt]::SmeltStream() }; 'p_ladle'   = { [CastbarArt]::Ladle() }
	'smelt_nose' = { [CastbarArt]::SmeltNose() }; 'smelt_dark'  = { [CastbarArt]::SmeltDark() }
	'storm_sky'  = { [CastbarArt]::StormSky() };     'p_bolts'     = { [CastbarArt]::Bolts() }
	'storm_cloud' = { [CastbarArt]::StormCloud((Join-Path $PSScriptRoot 'ref_cloud.jpg')) }
	'alch_glass' = { [CastbarArt]::AlchAtlas($false) }; 'alch_liquid' = { [CastbarArt]::AlchAtlas($true) }
	'alch_trough' = { [CastbarArt]::AlchTrough() }; 'alch_column' = { [CastbarArt]::AlchColumn() }
	'alch_band'  = { [CastbarArt]::AlchBand() }
	'tail_cloth' = { [CastbarArt]::TailCloth() };   'tail_warp'   = { [CastbarArt]::TailWarp() }
	'tail_warp_hi' = { [CastbarArt]::TailWarpHi() }; 'tail_shed'  = { [CastbarArt]::TailShed() }
	'p_shuttle'  = { [CastbarArt]::Shuttle() };     'p_pirn'      = { [CastbarArt]::Pirn() }
	'p_reed'     = { [CastbarArt]::Reed() };        'p_tail'      = { [CastbarArt]::WeftTail() }
	'lw_leather' = { [CastbarArt]::Leather() };     'p_hole'      = { [CastbarArt]::Hole() }
	'lw_tool1'   = { [CastbarArt]::Tooling(0) };    'lw_tool2'    = { [CastbarArt]::Tooling(1) }
	'lw_tool3'   = { [CastbarArt]::Tooling(2) };    'lw_tool4'    = { [CastbarArt]::Tooling(3) }
	'lw_tool5'   = { [CastbarArt]::Tooling(4) }
	'lw_lace'    = { [CastbarArt]::Lace() };        'lw_stitch'   = { [CastbarArt]::Stitch() }
	'p_needle'   = { [CastbarArt]::Needle() }
	'ench_velvet' = { [CastbarArt]::EnchVelvet() }; 'ench_velvet_hi' = { [CastbarArt]::EnchVelvetHi() }
	'ench_flow1' = { [CastbarArt]::EnchFlow(0) };   'ench_flow2'  = { [CastbarArt]::EnchFlow(1) }
	'p_vortex'   = { [CastbarArt]::Vortex() };      'p_dot'       = { [CastbarArt]::Dot() }
	'p_essence'  = { [CastbarArt]::Essence() }
	'p_flame'    = { [CastbarArt]::AlchFlame() };   'p_valve'     = { [CastbarArt]::AlchValve() }
	'p_chip'     = { [CastbarArt]::Chip() };        'p_flower'    = { [CastbarArt]::Flower() }
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
	'edge_h'     = { [CastbarArt]::EdgeH() }
	'corner_square' = { [CastbarArt]::CornerMask(0) }; 'corner_soft' = { [CastbarArt]::CornerMask(0.18) }; 'corner_rounded' = { [CastbarArt]::CornerMask(0.36) }
	'cap_dark_square' = { [CastbarArt]::CapRing(0, $false) }; 'cap_lit_square' = { [CastbarArt]::CapRing(0, $true) }
	'cap_dark_soft' = { [CastbarArt]::CapRing(0.18, $false) }; 'cap_lit_soft' = { [CastbarArt]::CapRing(0.18, $true) }
	'cap_dark_rounded' = { [CastbarArt]::CapRing(0.36, $false) }; 'cap_lit_rounded' = { [CastbarArt]::CapRing(0.36, $true) }
	'strip_dark_square' = { [CastbarArt]::StripRing(0, $false) }; 'strip_lit_square' = { [CastbarArt]::StripRing(0, $true) }
	'strip_dark_soft' = { [CastbarArt]::StripRing(0.18, $false) }; 'strip_lit_soft' = { [CastbarArt]::StripRing(0.18, $true) }
	'strip_dark_rounded' = { [CastbarArt]::StripRing(0.36, $false) }; 'strip_lit_rounded' = { [CastbarArt]::StripRing(0.36, $true) }
	'bevel_v'    = { [CastbarArt]::BevelV() }
	'p_thorn'    = { [CastbarArt]::Thorn() }
	'p_runecircles' = { [CastbarArt]::RuneCircles() }
}
foreach ($name in $jobs.Keys) {
	[CastbarArt]::WriteTga((& $jobs[$name]), (Join-Path $Out "$name.tga"))
}
Write-Host "Wrote $($jobs.Count) textures to $Out"

if ($Preview) {
	[CastbarArt]::Preview($Out, $Preview)
	Write-Host "Preview: $Preview"
}
