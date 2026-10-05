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
	public static Img MineRails()
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H, f1, f2; int cell;
			Voronoi(u, v, 24, 3, 501, out f1, out f2, out cell);            // stones in the wall
			double stone = 0.55 + 0.25*Hash(cell, 1, 502) + 0.15*Fbm(u, v, 32, 4, 3, 503);
			double seam = Smooth(0.0, 0.12, f2 - f1);
			double r = .20*stone*seam, g = .17*stone*seam, b = .15*stone*seam;
			if (Hash(x/2, y/2, 504) > 0.996)                                   // ore glints in the wall
			{
				int k = (int)(Hash(x/2, y/2, 505)*4);
				double[][] gem = { new[]{.4,.7,1.0}, new[]{.75,.5,1.0}, new[]{.4,1.0,.6}, new[]{1.0,.8,.35} };
				r = gem[k][0]; g = gem[k][1]; b = gem[k][2];
			}
			// track bed: gravel, sleepers every 32 px, a far rail and the near rail
			double bed = Smooth(0.66, 0.70, v);
			double gravel = 0.12 + 0.08*Hash(x/2, y/2, 506);
			r = Lerp(r, gravel*1.1, bed); g = Lerp(g, gravel, bed); b = Lerp(b, gravel*0.9, bed);
			double sx = Mod(x, 32);
			if (v > 0.73 && v < 0.92 && sx > 4 && sx < 22)
			{
				double grain = 0.8 + 0.2*Noise(x/3.0, y*1.5, 512, 64, 507);
				double sh = 0.7 + 0.3*Clamp((0.92 - v)/0.19);
				r = .42*grain*sh; g = .27*grain*sh; b = .14*grain*sh;
			}
			double farRail = Smooth(0.03, 0.0, Math.Abs(v - 0.715)), nearRail = Smooth(0.045, 0.0, Math.Abs(v - 0.80));
			double rail = Math.Max(farRail*0.75, nearRail);
			double steel = 0.45 + 0.45*Clamp(1 - (v - 0.775)/0.05);
			r = Lerp(r, .55*steel, rail); g = Lerp(g, .50*steel, rail); b = Lerp(b, .48*steel, rail);
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
	public static Img Cart()           // 64x64: wooden cart with iron bands and a heap of ore; wheels are separate
	{
		var img = new Img(64, 64);
		double[][] gem = { new[]{.35,.65,1.0}, new[]{.70,.45,1.0}, new[]{.35,.95,.55}, new[]{1.0,.80,.30}, new[]{.62,.60,.58} };
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = x/63.0, v = y/63.0;
			double inset = (v - 0.38)*0.10;                                     // the box narrows toward the bottom
			bool box = v > 0.38 && v < 0.80 && u > 0.06 + inset && u < 0.94 - inset;
			double r = 0, g = 0, b = 0, a = 0;
			// ore heap: overlapping chunks above the rim
			for (int k = 0; k < 9; k++)
			{
				// crystals: tall diamonds leaning a little, lit on the left face
				double cx = 0.16 + 0.085*k, cy = 0.33 - 0.10*Hash(k, 0, 521), rad = 0.07 + 0.04*Hash(k, 1, 521);
				double lean = (Hash(k, 3, 521) - 0.5)*0.6;
				double qx = (u - cx) - lean*(v - cy), qy = v - cy;
				double dd = Math.Abs(qx)*1.6 + Math.Abs(qy);
				if (dd < rad*1.6)
				{
					var c = gem[(int)(Hash(k, 2, 521)*gem.Length)];
					double lit = (qx < 0 ? 1.1 : 0.7) + (dd < rad*0.4 ? 0.3 : 0);
					r = c[0]*lit; g = c[1]*lit; b = c[2]*lit; a = 1;
				}
			}
			if (box)
			{
				double plank = 0.85 + 0.15*Math.Sin(v*64*1.2) + 0.08*Noise(u*20, v*4, 64, 64, 522);
				r = .48*plank; g = .30*plank; b = .16*plank; a = 1;
				bool band = Math.Abs(v - 0.40) < 0.035 || Math.Abs(v - 0.78) < 0.03 || Math.Abs(u - 0.08 - inset) < 0.04 || Math.Abs(u - 0.92 + inset) < 0.04;
				if (band) { r = .30; g = .30; b = .32; }
				if (band && Hash(x/4, y/4, 523) > 0.8) { r = .55; g = .52; b = .48; }    // rivets
			}
			// lantern on the front face
			double ld = Math.Sqrt((u - 0.80)*(u - 0.80) + (v - 0.60)*(v - 0.60));
			if (ld < 0.07) { r = 1.0; g = .80; b = .40; a = 1; }
			img.Set(x, y, r, g, b, a);
		}
		return img;
	}
	public static Img Wheel()          // iron wheel with six spokes; the addon turns it as the cart rolls
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 31.5)/32.0, r = Math.Sqrt(dx*dx + dy*dy), an = Math.Atan2(dy, dx);
			double rim = Smooth(0.95, 0.88, r) * Smooth(0.66, 0.74, r);
			double spoke = Smooth(0.10, 0.06, Math.Abs(Math.Sin(an*3)) * r) * Smooth(0.75, 0.6, r);
			double hub = Smooth(0.22, 0.16, r);
			double t = Math.Max(rim, Math.Max(spoke, hub));
			double sh = 0.35 + 0.25*Clamp(-dy) + (hub > 0.5 ? 0.2 : 0);
			img.Set(x, y, sh, sh*.96, sh*.92, Clamp(t));
		}
		return img;
	}
	public static Img Pickaxe()        // handle straight down from the centre; the head across the top
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 31.5)/32.0;
			double handle = Smooth(0.07, 0.045, Math.Abs(dx)) * Smooth(0.95, 0.9, dy) * Smooth(-0.62, -0.55, dy);
			double hy = -0.62 + 0.30*dx*dx;                                     // the head curves down at both picks
			double headW = 0.09*(1 - Math.Abs(dx)/0.95);
			double head = Smooth(headW + 0.02, headW, Math.Abs(dy - hy)) * Smooth(0.95, 0.85, Math.Abs(dx));
			double r, g, b;
			if (head > 0.01) { double s = 0.55 + 0.4*Clamp(-(dy - hy)/0.1 + 0.5); r = .62*s; g = .64*s; b = .68*s; }
			else { double s = 0.8 + 0.2*Noise(dy*12, dx*4, 64, 64, 541); r = .50*s; g = .32*s; b = .17*s; }
			img.Set(x, y, r, g, b, Clamp(Math.Max(handle, head)));
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

	// ================================================================ SKINNING: a pasture of cows and pigs, a cleaver, bones
	public static Img SkinBase()       // dusk pasture: grass along the bottom, dark field behind
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double n = Fbm(u, v, 8, 1, 4, 601);
			double r = .10 + .04*n + .05*(1 - v), g = .13 + .05*n + .04*(1 - v), b = .12 + .04*n + .06*(1 - v);
			double ground = 0.80 + 0.03*Fbm(u, 0.5, 16, 1, 2, 602);
			double blade = Smooth(0.0, 1.0, (v - ground)*12 + 0.35*Math.Abs(Math.Sin(x*1.7 + 3*Hash(x, 0, 603))));
			double gr = Hash(x, y/2, 604);
			r = Lerp(r, .16 + .08*gr, blade); g = Lerp(g, .34 + .14*gr, blade); b = Lerp(b, .12 + .05*gr, blade);
			img.Set(x, y, r, g, b, 1);
		}
		return img;
	}
	public static Img SkinBlood()      // BLEND: blood stains soaking into the grass along the bottom
	{
		var img = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
		{
			double u = (double)x/W, v = (double)y/H;
			double stain = Smooth(-0.10, 0.25, Fbm(u, v, 12, 2, 4, 611)) * Smooth(0.55, 0.90, v);
			double drip = Hash(x/2, y/2, 612) > 0.992 && v > 0.55 ? 0.9 : 0;
			double a = Clamp(Math.Max(stain*0.85, drip));
			double dark = 0.6 + 0.4*Fbm(u, v, 24, 3, 2, 613);
			img.Set(x, y, .42*dark, .02, .03, a);
		}
		return img;
	}
	static double Ell(double x, double y, double cx, double cy, double a, double b) { double dx = (x - cx)/a, dy = (y - cy)/b; return Math.Sqrt(dx*dx + dy*dy); }
	static double Bar(double x, double y, double x0, double y0, double x1, double y1, double w)   // distance to a thick segment, 0 inside
	{
		double px = x - x0, py = y - y0, vx = x1 - x0, vy = y1 - y0;
		double t = Clamp((px*vx + py*vy) / (vx*vx + vy*vy));
		double dx = px - vx*t, dy = py - vy*t;
		return Math.Sqrt(dx*dx + dy*dy) - w;
	}
	public static Img Cow()            // a little cow facing right, feet on the bottom
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = x/63.0, v = y/63.0, r = 0, g = 0, b = 0, a = 0;
			bool legs = false;
			foreach (double lx in new[] { .26, .36, .56, .66 }) if (Bar(u, v, lx, .60, lx, .88, .035) < 0) legs = true;
			double body = Ell(u, v, .46, .52, .30, .16), head = Ell(u, v, .79, .44, .11, .10), snout = Ell(u, v, .87, .50, .06, .05);
			double horn = Math.Min(Bar(u, v, .74, .36, .70, .29, .015), Bar(u, v, .84, .36, .88, .29, .015));
			double tail = Bar(u, v, .17, .48, .11, .66, .012);
			if (legs || tail < 0) { r = g = b = .85; a = 1; if (v > .84 && legs) { r = g = b = .15; } }
			if (body < 1 || head < 1)
			{
				double patch = Fbm(u, v, 3, 3, 2, 621) > 0.12 && head > 1 ? 1 : 0;
				double sh = 0.75 + 0.25*Clamp(-(v - .45)*4);
				r = g = b = patch > 0 ? .12*sh : .92*sh; a = 1;
			}
			if (snout < 1) { r = .95; g = .65; b = .65; a = 1; }
			if (horn < 0) { r = .9; g = .85; b = .7; a = 1; }
			if (Ell(u, v, .81, .41, .018, .018) < 1) { r = g = b = .05; }   // eye
			img.Set(x, y, r, g, b, a);
		}
		return img;
	}
	public static Img Pig()            // a little pink pig facing right, curly tail
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = x/63.0, v = y/63.0, r = 0, g = 0, b = 0, a = 0;
			bool legs = false;
			foreach (double lx in new[] { .28, .38, .56, .66 }) if (Bar(u, v, lx, .66, lx, .88, .04) < 0) legs = true;
			double body = Ell(u, v, .46, .56, .30, .18), head = Ell(u, v, .77, .50, .12, .11), snout = Ell(u, v, .89, .53, .045, .055);
			double ear = Bar(u, v, .74, .40, .70, .32, .03);
			double tr = Math.Sqrt((u - .14)*(u - .14) + (v - .48)*(v - .48));
			double tail = Math.Abs(tr - .045) - .012;
			double sh = 0.75 + 0.25*Clamp(-(v - .5)*4);
			if (legs) { r = .90*sh; g = .58*sh; b = .62*sh; a = 1; if (v > .85) { r = .45; g = .25; b = .25; } }
			if (tail < 0 && u < .16) { r = .95; g = .62; b = .66; a = 1; }
			if (body < 1 || head < 1 || ear < 0) { r = .98*sh; g = .66*sh; b = .70*sh; a = 1; }
			if (snout < 1) { r = .90; g = .48; b = .55; a = 1; if (Ell(u, v, .885, .515, .01, .016) < 1 || Ell(u, v, .9, .55, .01, .016) < 1) { r = .4; g = .15; b = .2; } }
			if (Ell(u, v, .79, .46, .016, .016) < 1) { r = g = b = .05; }   // eye
			img.Set(x, y, r, g, b, a);
		}
		return img;
	}
	public static Img Bones()          // a skull and crossed bones on a blood stain
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double u = x/63.0, v = y/63.0, r = 0, g = 0, b = 0, a = 0;
			double pool = Ell(u, v, .50, .87, .40, .08) + 0.15*Noise(u*6, v*6, 64, 64, 631);
			if (pool < 1) { r = .45; g = .03; b = .04; a = .9; }
			double bone1 = Bar(u, v, .22, .82, .74, .64, .035), bone2 = Bar(u, v, .24, .62, .76, .80, .035);
			double knob = Math.Min(Math.Min(Ell(u, v, .21, .80, .05, .05), Ell(u, v, .75, .62, .05, .05)), Math.Min(Ell(u, v, .23, .60, .05, .05), Ell(u, v, .77, .82, .05, .05)));
			double skull = Ell(u, v, .50, .55, .16, .14), jaw = Ell(u, v, .50, .69, .09, .06);
			if (bone1 < 0 || bone2 < 0 || knob < 1) { r = .86; g = .82; b = .72; a = 1; }
			if (skull < 1 || jaw < 1)
			{
				double sh = 0.7 + 0.3*Clamp(-(v - .5)*5 - (u - .5)*2);
				r = .93*sh; g = .90*sh; b = .80*sh; a = 1;
				if (Ell(u, v, .44, .55, .04, .045) < 1 || Ell(u, v, .56, .55, .04, .045) < 1) { r = g = b = .1; }   // eye sockets
				if (Ell(u, v, .50, .63, .015, .02) < 1) { r = g = b = .15; }
			}
			img.Set(x, y, r, g, b, a);
		}
		return img;
	}
	public static Img Cleaver()        // handle straight down from the centre; the blade off the top, edge on its right
	{
		var img = new Img(64, 64);
		for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++)
		{
			double dx = (x - 31.5)/32.0, dy = (y - 31.5)/32.0;
			double handle = Smooth(0.07, 0.05, Math.Abs(dx)) * Smooth(0.95, 0.9, dy) * Smooth(-0.40, -0.36, dy);
			bool blade = dx > -0.07 && dx < 0.58 && dy > -0.95 && dy < -0.36;
			double r = 0, g = 0, bl = 0, a = 0;
			if (handle > 0.01) { double s = 0.8 + 0.2*Noise(dy*12, dx*4, 64, 64, 641); r = .30*s; g = .17*s; bl = .09*s; a = handle; }
			if (blade)
			{
				double s = 0.55 + 0.35*Clamp((dx + 0.07)/0.65) + 0.25*Math.Exp(-Math.Pow((dx - 0.55)*30, 2));   // bright cutting edge
				r = .70*s; g = .72*s; bl = .76*s; a = 1;
				if (Ell(dx, dy, .05, -.80, .05, .05) < 1) { r = .15; g = .15; bl = .17; }                       // the hanging hole
			}
			img.Set(x, y, r, g, bl, a);
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
	'frost_water' = { [CastbarArt]::FrostWater() };  'frost_water_hi' = { [CastbarArt]::FrostWaterHi() }
	'frost_front' = { [CastbarArt]::FrostFront() }
	'fish_water' = { [CastbarArt]::FishWater() };   'fish_caustic' = { [CastbarArt]::FishCaustic() }
	'mine_rails' = { [CastbarArt]::MineRails() };   'mine_flow'   = { [CastbarArt]::MineFlow() }
	'p_lily'     = { [CastbarArt]::LilyPad() };     'p_fish'      = { [CastbarArt]::Fish() }
	'p_bobber'   = { [CastbarArt]::Bobber() };      'p_ripple'    = { [CastbarArt]::Ripple() }
	'p_cart'     = { [CastbarArt]::Cart() };        'p_wheel'     = { [CastbarArt]::Wheel() }
	'p_pickaxe'  = { [CastbarArt]::Pickaxe() }
	'skin_base'  = { [CastbarArt]::SkinBase() };    'skin_blood'  = { [CastbarArt]::SkinBlood() }
	'p_cow'      = { [CastbarArt]::Cow() };         'p_pig'       = { [CastbarArt]::Pig() }
	'p_bones'    = { [CastbarArt]::Bones() };       'p_cleaver'   = { [CastbarArt]::Cleaver() }
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
	'edge_v'     = { [CastbarArt]::EdgeV() }
	'edge_h'     = { [CastbarArt]::EdgeH() }
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
