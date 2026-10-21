using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

// Stacks a frame painted in layers (template\PAINT-LAYERS.md) into a preview, the way the addon layers it.
// Each layer is keyed (every guide colour becomes transparent), fitted onto the template whatever size the
// image tool painted it at, has its forbidden areas cleared (NOTES.md section 8), and is stacked with mock
// bars and a portrait. Writes a preview per ring fit and a fit sheet with the template drawn over each layer.

public class LImg {
	public int W, H;
	public float[] P;   // premultiplied RGBA
	public LImg(int w, int h) { W = w; H = h; P = new float[w * h * 4]; }
}

public class Keyed {
	public LImg Img;
	public byte[] Key;  // 1 + guide colour index where the pixel is that colour, else 0
	public int SrcW, SrcH;
}

public static class Layers {
	// Template at 2x (image px), the same numbers as template\Make-LayerGuides.ps1.
	const int W = 2400, H = 920;
	static readonly int[] PLATE = { 16, 306, 2384, 578, 28 };
	static readonly int[] INNER = { 68, 350, 2332, 534, 20 };
	static readonly int[] WIN = { 100, 382, 2300, 502, 10 };
	static readonly int[] KEEP = { 88, 370, 2312, 514 };
	const int L1T = 276, L1B = 608, CAP = 128;   // L1 with its end caps: full width, caps 128 wide
	const double CX = 1200, CY = 460, RIN = 210, ROUT = 262, OPEN = 208;
	const int BORDER2 = 32;                          // L2's rim: inner edge to window, every side

	// Guide colours: magenta, blue, green, yellow, orange, cyan.
	static readonly float[][] KEYS = {
		new float[] { 1, 0, 1 }, new float[] { 0, 0, 1 }, new float[] { 0, 1, 0 },
		new float[] { 1, 1, 0 }, new float[] { 1, 0.549f, 0 }, new float[] { 0, 1, 1 } };
	const int MAGENTA = 0, BLUE = 1, ORANGE = 4;

	static double Clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

	// ---- Load, key, save ----

	// How strongly a pixel leans to a guide colour, whatever its brightness (a darkened key is a painted shadow).
	static double Excess(int key, double r, double g, double b) {
		switch (key) {
			case 0: return Math.Min(r, b) - g;                   // magenta
			case 1: return b - Math.Max(r, g);                   // blue
			case 2: return g - Math.Max(r, b);                   // green
			case 3: return Math.Min(r, g) - b;                   // yellow
			case 4: return Math.Min(r - g, g - b) * 1.6;         // orange
			default: return Math.Min(g, b) - r;                  // cyan
		}
	}

	// keys: bit per guide colour the layer's guide uses (others are left alone, so rust never keys as orange).
	public static Keyed KeyFile(string path, int keys) {
		var k = new Keyed();
		using (var bmp = new Bitmap(path)) {
			int w = bmp.Width, h = bmp.Height;
			k.SrcW = w; k.SrcH = h;
			var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
			var px = new byte[w * h * 4];
			Marshal.Copy(data.Scan0, px, 0, px.Length);
			bmp.UnlockBits(data);
			k.Img = new LImg(w, h); k.Key = new byte[w * h];
			var P = k.Img.P;
			for (int i = 0; i < w * h; i++) {
				float b = px[i * 4] / 255f, g = px[i * 4 + 1] / 255f, r = px[i * 4 + 2] / 255f;
				double best = 9; int bi = 0;
				for (int c = 0; c < KEYS.Length; c++) {
					double dr = r - KEYS[c][0], dg = g - KEYS[c][1], db = b - KEYS[c][2];
					double d = Math.Sqrt(dr * dr + dg * dg + db * db);
					if (d < best) { best = d; bi = c; }
				}
				if (best < 0.3) k.Key[i] = (byte)(bi + 1);
				double e = 0; int ek = -1;
				for (int c = 0; c < KEYS.Length; c++) {
					if ((keys & (1 << c)) == 0) continue;
					double x = Excess(c, r, g, b);
					if (x > e) { e = x; ek = c; }
				}
				double a = 1 - Clamp01((e - 0.25) / 0.30);
				double cr = r, cg = g, cb = b;
				if (ek >= 0 && e > 0.04) {
					// Take the key's colour back out (despill): an edge or shadow keeps only its own shade.
					if (ek == 4) { double l = (r + g + b) / 3; cr = cg = cb = l * 0.6; }
					else {
						if (KEYS[ek][0] > 0.5) cr = Clamp01(r - e);
						if (KEYS[ek][1] > 0.5) cg = Clamp01(g - e);
						if (KEYS[ek][2] > 0.5) cb = Clamp01(b - e);
					}
				}
				P[i * 4] = (float)(cr * a); P[i * 4 + 1] = (float)(cg * a); P[i * 4 + 2] = (float)(cb * a); P[i * 4 + 3] = (float)a;
			}
		}
		return k;
	}

	static Bitmap ToBitmap(LImg im) {
		var bmp = new Bitmap(im.W, im.H, PixelFormat.Format32bppArgb);
		var px = new byte[im.W * im.H * 4];
		for (int i = 0; i < im.W * im.H; i++) {
			float a = im.P[i * 4 + 3];
			float inv = a > 0.0001f ? 1 / a : 0;
			px[i * 4] = (byte)(Clamp01(im.P[i * 4 + 2] * inv) * 255 + 0.5);
			px[i * 4 + 1] = (byte)(Clamp01(im.P[i * 4 + 1] * inv) * 255 + 0.5);
			px[i * 4 + 2] = (byte)(Clamp01(im.P[i * 4] * inv) * 255 + 0.5);
			px[i * 4 + 3] = (byte)(Clamp01(a) * 255 + 0.5);
		}
		var data = bmp.LockBits(new Rectangle(0, 0, im.W, im.H), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
		Marshal.Copy(px, 0, data.Scan0, px.Length);
		bmp.UnlockBits(data);
		return bmp;
	}

	static void SavePng(Bitmap bmp, string path, double scale) {
		if (scale == 1) { bmp.Save(path, ImageFormat.Png); return; }
		int w = (int)Math.Round(bmp.Width * scale), h = (int)Math.Round(bmp.Height * scale);
		using (var s = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
			using (var g = Graphics.FromImage(s)) {
				g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
				g.DrawImage(bmp, 0, 0, w, h);
			}
			s.Save(path, ImageFormat.Png);
		}
	}

	// ---- Measuring ----

	// Bounding box {x0, y0, x1, y1} (x1, y1 exclusive) of opaque pixels (key < 0) or of one guide colour.
	static int[] Box(Keyed k, int key) {
		int w = k.Img.W, h = k.Img.H, x0 = w, y0 = h, x1 = -1, y1 = -1;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
			int i = y * w + x;
			bool hit = key < 0 ? k.Img.P[i * 4 + 3] > 0.5f : k.Key[i] == key + 1;
			if (!hit) continue;
			if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
		}
		return x1 < 0 ? null : new[] { x0, y0, x1 + 1, y1 + 1 };
	}

	static string BoxStr(int[] b) { return b == null ? "none" : string.Format("{0},{1} to {2},{3} ({4} x {5})", b[0], b[1], b[2], b[3], b[2] - b[0], b[3] - b[1]); }

	// ---- Resampling ----

	static void Bilinear(LImg s, double x, double y, double[] acc) {
		x -= 0.5; y -= 0.5;
		int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y);
		double fx = x - x0, fy = y - y0;
		for (int j = 0; j < 2; j++) for (int i = 0; i < 2; i++) {
			int px = x0 + i, py = y0 + j;
			if (px < 0 || py < 0 || px >= s.W || py >= s.H) continue;
			double wgt = (i == 0 ? 1 - fx : fx) * (j == 0 ? 1 - fy : fy);
			int o = (py * s.W + px) * 4;
			acc[0] += wgt * s.P[o]; acc[1] += wgt * s.P[o + 1]; acc[2] += wgt * s.P[o + 2]; acc[3] += wgt * s.P[o + 3];
		}
	}

	// dst[x0..x1, y0..y1] <- src, mapped axis by axis: srcX = ax + dstX * bx (continuous coordinates).
	static void Affine(LImg src, LImg dst, double dx0, double dy0, double dx1, double dy1, double sx0, double sy0, double sx1, double sy1) {
		if (dx1 <= dx0 || dy1 <= dy0) return;
		double bx = (sx1 - sx0) / (dx1 - dx0), by = (sy1 - sy0) / (dy1 - dy0);
		int ss = (int)Math.Min(8, Math.Max(2, Math.Ceiling(Math.Max(Math.Abs(bx), Math.Abs(by)))));
		var acc = new double[4];
		for (int y = (int)Math.Floor(dy0); y < (int)Math.Ceiling(dy1); y++) for (int x = (int)Math.Floor(dx0); x < (int)Math.Ceiling(dx1); x++) {
			if (x < 0 || y < 0 || x >= dst.W || y >= dst.H) continue;
			acc[0] = acc[1] = acc[2] = acc[3] = 0;
			for (int j = 0; j < ss; j++) for (int i = 0; i < ss; i++) {
				double tx = x + (i + 0.5) / ss, ty = y + (j + 0.5) / ss;
				if (tx < dx0 || tx >= dx1 || ty < dy0 || ty >= dy1) continue;
				Bilinear(src, sx0 + (tx - dx0) * bx, sy0 + (ty - dy0) * by, acc);
			}
			int o = (y * dst.W + x) * 4; double n = ss * ss;
			for (int c = 0; c < 4; c++) dst.P[o + c] += (float)(acc[c] / n);
		}
	}

	// Nine-slice: src rect so with insets si (l, t, r, b) onto dst rect d with insets di. Corners keep their
	// look, edges stretch along their length only.
	static void Nine(LImg src, int[] so, int[] si, LImg dst, int[] d, int[] di) {
		double[] sx = { so[0], so[0] + si[0], so[2] - si[2], so[2] }, sy = { so[1], so[1] + si[1], so[3] - si[3], so[3] };
		double[] dx = { d[0], d[0] + di[0], d[2] - di[2], d[2] }, dy = { d[1], d[1] + di[1], d[3] - di[3], d[3] };
		for (int j = 0; j < 3; j++) for (int i = 0; i < 3; i++)
			Affine(src, dst, dx[i], dy[j], dx[i + 1], dy[j + 1], sx[i], sy[j], sx[i + 1], sy[j + 1]);
	}

	// Ring onto the template centre. Radii in source px. remap: the band [rIn, rOut] is squeezed radially onto
	// the template's 105..131 band; otherwise a plain scale that puts the opening at 105.
	static void Ring(LImg src, LImg dst, double scx, double scy, double rIn, double rOut, bool remap) {
		double s = RIN / rIn;
		const int ss = 4;
		var acc = new double[4];
		for (int y = 0; y < dst.H; y++) for (int x = 0; x < dst.W; x++) {
			acc[0] = acc[1] = acc[2] = acc[3] = 0;
			for (int j = 0; j < ss; j++) for (int i = 0; i < ss; i++) {
				double tx = x + (i + 0.5) / ss - CX, ty = y + (j + 0.5) / ss - CY;
				double r = Math.Sqrt(tx * tx + ty * ty), sr;
				if (!remap) sr = r / s;
				else if (r <= RIN) sr = r * rIn / RIN;
				else if (r <= ROUT) sr = rIn + (r - RIN) * (rOut - rIn) / (ROUT - RIN);
				else sr = rOut + (r - ROUT) * rOut / ROUT;
				double f = r > 0 ? sr / r : 0;
				Bilinear(src, scx + tx * f, scy + ty * f, acc);
			}
			int o = (y * dst.W + x) * 4;
			for (int c = 0; c < 4; c++) dst.P[o + c] = (float)(acc[c] / (ss * ss));
		}
	}

	// ---- Shapes ----

	static double SdRoundRect(double px, double py, int[] r) {
		double rad = r.Length > 4 ? r[4] : 0;
		double cx = (r[0] + r[2]) / 2.0, cy = (r[1] + r[3]) / 2.0, hx = (r[2] - r[0]) / 2.0 - rad, hy = (r[3] - r[1]) / 2.0 - rad;
		double qx = Math.Abs(px - cx) - hx, qy = Math.Abs(py - cy) - hy;
		double ox = Math.Max(qx, 0), oy = Math.Max(qy, 0);
		return Math.Sqrt(ox * ox + oy * oy) + Math.Min(Math.Max(qx, qy), 0) - rad;
	}

	static double SdCircle(double px, double py, double r) { return Math.Sqrt((px - CX) * (px - CX) + (py - CY) * (py - CY)) - r; }

	// Clears a shape (1 px soft edge). Returns how many visible pixels were inside it: the rule check.
	static int ClearRect(LImg im, int[] r) { return Clear(im, true, r, 0); }
	// The keep-out where a bar shows: outside the ring (inside it the ring and the portrait cover the bars).
	static int ClearRectOutsideRing(LImg im, int[] r) { return Clear(im, true, r, ROUT); }
	static int ClearCircle(LImg im, double rad) { return Clear(im, false, null, rad); }
	static int Clear(LImg im, bool rect, int[] r, double rad) {
		int n = 0;
		for (int y = 0; y < im.H; y++) for (int x = 0; x < im.W; x++) {
			double d = rect ? SdRoundRect(x + 0.5, y + 0.5, r) : SdCircle(x + 0.5, y + 0.5, rad);
			double cov = Clamp01(0.5 - d);
			if (rect && rad > 0) cov *= Clamp01(0.5 + SdCircle(x + 0.5, y + 0.5, rad));   // spare the ring disc
			if (cov <= 0) continue;
			int o = (y * im.W + x) * 4;
			if (cov > 0.5 && im.P[o + 3] > 0.1f) n++;
			float m = (float)(1 - cov);
			for (int c = 0; c < 4; c++) im.P[o + c] *= m;
		}
		return n;
	}

	// Clears everything outside the zones, 3 px in from their edges (where the guide's zone lines are).
	// Returns how many visible pixels were clearly outside: the rule check.
	static int ClearOutside(LImg im, int[][] zones) {
		int n = 0;
		for (int y = 0; y < im.H; y++) for (int x = 0; x < im.W; x++) {
			double d = double.MaxValue;
			foreach (var z in zones) d = Math.Min(d, SdRoundRect(x + 0.5, y + 0.5, z));
			double keep = Clamp01(0.5 - (d + 3));
			if (keep >= 1) continue;
			int o = (y * im.W + x) * 4;
			if (d > 4 && im.P[o + 3] > 0.1f) n++;
			for (int c = 0; c < 4; c++) im.P[o + c] *= (float)keep;
		}
		return n;
	}

	static void Over(LImg dst, LImg src) {
		if (src == null) return;
		for (int i = 0; i < dst.W * dst.H; i++) {
			int o = i * 4; float m = 1 - src.P[o + 3];
			for (int c = 0; c < 4; c++) dst.P[o + c] = src.P[o + c] + dst.P[o + c] * m;
		}
	}

	delegate void Shade(double x, double y, double[] rgb);

	static void Fill(LImg dst, int[] rect, double circleR, Shade shade) {
		var rgb = new double[3];
		for (int y = 0; y < dst.H; y++) for (int x = 0; x < dst.W; x++) {
			double d = rect != null ? SdRoundRect(x + 0.5, y + 0.5, rect) : SdCircle(x + 0.5, y + 0.5, circleR);
			double cov = Clamp01(0.5 - d);
			if (cov <= 0) continue;
			shade(x + 0.5, y + 0.5, rgb);
			int o = (y * dst.W + x) * 4; float m = (float)(1 - cov);
			for (int c = 0; c < 3; c++) dst.P[o + c] = (float)(rgb[c] * cov) + dst.P[o + c] * m;
			dst.P[o + 3] = (float)cov + dst.P[o + 3] * m;
		}
	}

	static double Lerp(double a, double b, double t) { return a + (b - a) * t; }

	// ---- The layers ----

	static LImg FitL1(Keyed k, StringBuilder rep) {
		var ob = Box(k, -1);
		rep.AppendLine("  painted: " + BoxStr(ob));
		// End caps: the full-height blocks at each end. Walk out from the middle until a column reaches the top.
		int w = k.Img.W, tol = Math.Max(4, (ob[3] - ob[1]) / 60);
		Func<int, int> top = x => { for (int y = ob[1]; y < ob[3]; y++) if (k.Img.P[(y * w + x) * 4 + 3] > 0.5f) return y; return int.MaxValue; };
		int mid = (ob[0] + ob[2]) / 2, capL = 0, capR = 0;
		for (int x = mid; x > ob[0]; x--) if (top(x) <= ob[1] + tol) { capL = x + 1 - ob[0]; break; }
		for (int x = mid; x < ob[2]; x++) if (top(x) <= ob[1] + tol) { capR = ob[2] - x; break; }
		var dst = new LImg(W, H);
		double sy = (double)(L1B - L1T) / (ob[3] - ob[1]);
		if (capL > 0 && capR > 0 && capL + capR < (ob[2] - ob[0]) * 0.8) {
			Nine(k.Img, ob, new[] { capL, 0, capR, 0 }, dst, new[] { 0, L1T, W, L1B }, new[] { CAP, 0, CAP, 0 });
			double midS = (double)(W - 2 * CAP) / (ob[2] - ob[0] - capL - capR);
			rep.AppendLine(string.Format("  fit: 3-slice. Height x{0:0.###}. Caps {1}/{2} px -> {3} (squeezed to x{4:0.##} of their shape). Middle stretched x{5:0.##} wider than tall",
				sy, capL, capR, CAP, CAP / (capL * sy), midS / sy));
		} else {
			Affine(k.Img, dst, 0, L1T, W, L1B, ob[0], ob[1], ob[2], ob[3]);
			rep.AppendLine("  fit: no end caps found; stretched to the plate box");
		}
		Cut(rep, "windows", ClearRect(dst, WIN));
		Cut(rep, "portrait opening", ClearCircle(dst, OPEN));
		return dst;
	}

	static LImg FitL2(Keyed k, StringBuilder rep) {
		var ob = Box(k, -1); var wb = Box(k, BLUE);
		rep.AppendLine("  painted: " + BoxStr(ob) + ", window " + BoxStr(wb));
		var dst = new LImg(W, H);
		var si = new[] { wb[0] - ob[0], wb[1] - ob[1], ob[2] - wb[2], ob[3] - wb[3] };
		Nine(k.Img, ob, si, dst, INNER, new[] { BORDER2, BORDER2, BORDER2, BORDER2 });
		rep.AppendLine(string.Format("  fit: 9-slice. Rim {0}/{1}/{2}/{3} px -> {4} (x{5:0.###}); painted outer aspect {6:0.0}:1, template {7:0.0}:1",
			si[0], si[1], si[2], si[3], BORDER2, (double)BORDER2 / si[1], (double)(ob[2] - ob[0]) / (ob[3] - ob[1]), (double)(INNER[2] - INNER[0]) / (INNER[3] - INNER[1])));
		Cut(rep, "windows", ClearRect(dst, WIN));
		Cut(rep, "portrait opening", ClearCircle(dst, OPEN));
		return dst;
	}

	static LImg FitL3(Keyed k, bool remap, StringBuilder rep) {
		var ob = Box(k, -1); var bb = Box(k, BLUE);
		double cx = (bb[0] + bb[2]) / 2.0, cy = (bb[1] + bb[3]) / 2.0;
		double rIn = (bb[2] - bb[0] + bb[3] - bb[1]) / 4.0, rOut = (ob[2] - ob[0] + ob[3] - ob[1]) / 4.0;
		if (rep != null) {
			rep.AppendLine("  painted: ring " + BoxStr(ob) + ", opening " + BoxStr(bb));
			rep.AppendLine(string.Format("  painted opening/outer = {0:0.00} (template 105/131 = {1:0.00}); centre {2:0},{3:0} = {4:0.###},{5:0.###} of the image (template 0.5, 0.5)",
				rIn / rOut, RIN / ROUT, cx, cy, cx / k.SrcW, cy / k.SrcH));
		}
		var dst = new LImg(W, H);
		Ring(k.Img, dst, cx, cy, rIn, rOut, remap);
		if (rep != null) {
			rep.AppendLine(string.Format("  fit 'scale': opening to 105, so the ring's outside lands at {0:0} (template 131)", rOut * RIN / rIn / 2));
			rep.AppendLine(string.Format("  fit 'remap': band squeezed x{0:0.##} radially onto 105..131", (ROUT - RIN) / (rOut - rIn)));
		}
		int n = ClearCircle(dst, OPEN);
		if (rep != null) Check(rep, "portrait opening", n);
		return dst;
	}

	// Where the L4 painting lands on the template: dst rect {x0, y0, x1, y1} for the whole source image.
	static double[] L4Rect(Keyed k, StringBuilder rep) {
		var ob = Box(k, ORANGE);
		if (ob == null) {
			double s = (double)W / k.SrcW;
			rep.AppendLine("  fit: no orange ring found; scaled to the width");
			return new[] { 0, (H - k.SrcH * s) / 2, W, (H + k.SrcH * s) / 2 };
		}
		double r = (ob[2] - ob[0]) / 2.0, cx = (ob[0] + ob[2]) / 2.0, cy = ob[3] - r, sc = ROUT / r;
		rep.AppendLine(string.Format("  fit: by the guide's orange ring (r {0:0} px). Scale x{1:0.####} (plain resize x{2:0.####}); ring centre at {3:0.###},{4:0.###} of the image (template 0.5, 0.5)",
			r, sc, (double)W / k.SrcW, cx / k.SrcW, cy / k.SrcH));
		return new[] { CX - cx * sc, CY - cy * sc, CX + (k.SrcW - cx) * sc, CY + (k.SrcH - cy) * sc };
	}

	static LImg Place(LImg src, double[] r) {
		var dst = new LImg(W, H);
		Affine(src, dst, r[0], r[1], r[2], r[3], 0, 0, src.W, src.H);
		return dst;
	}

	// A front mask: white where the ornament lies in front, black behind, on the same canvas as L4 back.
	static LImg LoadMask(string path) {
		using (var bmp = new Bitmap(path)) {
			var m = new LImg(bmp.Width, bmp.Height);
			var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
			var px = new byte[bmp.Width * bmp.Height * 4];
			Marshal.Copy(data.Scan0, px, 0, px.Length);
			bmp.UnlockBits(data);
			for (int i = 0; i < bmp.Width * bmp.Height; i++) {
				float l = (px[i * 4] + px[i * 4 + 1] + px[i * 4 + 2]) / 765f;
				m.P[i * 4] = m.P[i * 4 + 1] = m.P[i * 4 + 2] = m.P[i * 4 + 3] = l;
			}
			return m;
		}
	}

	static LImg FitL4(Keyed k, bool front, StringBuilder rep) {
		return L4Rules(Place(k.Img, L4Rect(k, rep)), front, rep);
	}

	static LImg L4Rules(LImg dst, bool front, StringBuilder rep) {
		// Zones as in Make-LayerGuides.ps1: above the plate, below it round the ring, and on the plate
		// (all of it behind, only round the ring in front).
		var zones = new[] { new[] { 600, 0, 1800, 306, 0 }, new[] { 860, 578, 1540, 920, 0 },
			front ? new[] { 600, 306, 1800, 578, 0 } : PLATE };
		Check(rep, "outside the ornament zones", ClearOutside(dst, zones));
		// Front may cover the ring and the portrait (NOTES.md section 2), never a bar.
		if (front) Check(rep, "bar keep-out outside the ring (zero alpha)", ClearRectOutsideRing(dst, KEEP));
		else {
			Check(rep, "bar keep-out (zero alpha)", ClearRect(dst, KEEP));
			Check(rep, "portrait opening", ClearCircle(dst, OPEN));
		}
		return dst;
	}

	static void Check(StringBuilder rep, string what, int n) {
		rep.AppendLine(n == 0 ? "  ok   " + what : string.Format("  FIX  {0}: {1} painted px inside (cleared for the preview)", what, n));
	}

	// For a layer whose painted shape was stretched onto the template: the cut is the fitter's, not a paint fault.
	static void Cut(StringBuilder rep, string what, int n) {
		rep.AppendLine(string.Format("  cut  {0}: {1} px", what, n));
	}

	// ---- Preview ----

	// Bars as the addon lays them: they run under the rim 5 layout px at each end and 2 at top and bottom
	// (Layout.lua ns.STD sideX, sideY), so no seam shows where the rim meets them.
	static readonly int[] BARS = { WIN[0] - 10, WIN[1] - 4, WIN[2] + 10, WIN[3] + 4, WIN[4] };

	static LImg Compose(LImg l1, LImg l2, LImg l3, LImg back, LImg front, bool background) {
		var c = new LImg(W, H);
		if (background) Fill(c, new[] { 0, 0, W, H }, 0, (x, y, o) => { double t = y / H; o[0] = Lerp(0.16, 0.07, t); o[1] = Lerp(0.17, 0.08, t); o[2] = Lerp(0.20, 0.10, t); });
		Over(c, back);
		// Bars as the addon draws them (NOTES.md 3): health left, resource right, empty toward the portrait.
		Fill(c, BARS, 0, (x, y, o) => {
			double v = (y - WIN[1]) / (double)(WIN[3] - WIN[1]), shade = 1.15 - 0.5 * v;
			bool left = x < CX, full = left ? x < 820 : x > 1640;
			double[] col = left ? (full ? new[] { 0.82, 0.19, 0.12 } : new[] { 0.20, 0.03, 0.02 })
			                    : (full ? new[] { 0.18, 0.44, 0.88 } : new[] { 0.02, 0.08, 0.22 });
			for (int i = 0; i < 3; i++) o[i] = Clamp01(col[i] * shade);
		});
		Over(c, l1); Over(c, l2);
		Fill(c, null, RIN + 8, (x, y, o) => {
			double t = Clamp01(Math.Sqrt((x - CX) * (x - CX) + (y - CY + 40) * (y - CY + 40)) / (RIN + 40));
			o[0] = Lerp(0.55, 0.14, t); o[1] = Lerp(0.42, 0.10, t); o[2] = Lerp(0.36, 0.12, t);
		});
		Over(c, l3); Over(c, front);
		return c;
	}

	// Stitching: stacked with no background, the frame's body (the plate and the ring disc, 3 px in from their
	// outlines, where an edge may be soft) must be solid everywhere. A see-through pixel there is a seam between
	// two layers. Marks them red on the preview and returns how many there are.
	static int Seams(LImg bare, LImg shown) {
		int n = 0;
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
			double px = x + 0.5, py = y + 0.5;
			if (SdRoundRect(px, py, PLATE) > -3 && SdCircle(px, py, ROUT) > -3) continue;
			int o = (y * W + x) * 4;
			if (bare.P[o + 3] >= 0.98f) continue;
			n++;
			shown.P[o] = 1; shown.P[o + 1] = 0; shown.P[o + 2] = 0; shown.P[o + 3] = 1;
		}
		return n;
	}

	static LImg Checker(LImg layer) {
		var c = new LImg(W, H);
		Fill(c, new[] { 0, 0, W, H }, 0, (x, y, o) => { double v = (((int)x / 24 + (int)y / 24) & 1) == 0 ? 0.30 : 0.22; o[0] = o[1] = o[2] = v; });
		Over(c, layer);
		return c;
	}

	static GraphicsPath RR(int[] a) {
		var p = new GraphicsPath(); int d = 2 * a[4];
		p.AddArc(a[0], a[1], d, d, 180, 90); p.AddArc(a[2] - d, a[1], d, d, 270, 90);
		p.AddArc(a[2] - d, a[3] - d, d, d, 0, 90); p.AddArc(a[0], a[3] - d, d, d, 90, 90); p.CloseFigure();
		return p;
	}

	// The fit sheet: each fitted layer on a checkerboard, with the template drawn over it.
	static void Sheet(string path, string[] labels, LImg[] layers) {
		int pw = W / 2, ph = H / 2, n = 0;
		foreach (var l in layers) if (l != null) n++;
		using (var sheet = new Bitmap(pw, ph * n, PixelFormat.Format32bppArgb))
		using (var g = Graphics.FromImage(sheet)) {
			g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.SmoothingMode = SmoothingMode.AntiAlias;
			int row = 0;
			for (int i = 0; i < layers.Length; i++) {
				if (layers[i] == null) continue;
				using (var bmp = ToBitmap(Checker(layers[i])))
				using (var bg = Graphics.FromImage(bmp)) {
					bg.SmoothingMode = SmoothingMode.AntiAlias;
					using (var cyan = new Pen(Color.Cyan, 3) { DashStyle = DashStyle.Dash })
					using (var yellow = new Pen(Color.Yellow, 3) { DashStyle = DashStyle.Dot }) {
						bg.DrawPath(cyan, RR(PLATE)); bg.DrawPath(cyan, RR(INNER)); bg.DrawPath(cyan, RR(WIN));
						bg.DrawRectangle(cyan, 0, L1T, CAP, L1B - L1T); bg.DrawRectangle(cyan, W - CAP, L1T, CAP, L1B - L1T);
						bg.DrawEllipse(cyan, (float)(CX - RIN), (float)(CY - RIN), (float)(2 * RIN), (float)(2 * RIN));
						bg.DrawEllipse(cyan, (float)(CX - ROUT), (float)(CY - ROUT), (float)(2 * ROUT), (float)(2 * ROUT));
						bg.DrawRectangle(yellow, KEEP[0], KEEP[1], KEEP[2] - KEEP[0], KEEP[3] - KEEP[1]);
					}
					using (var font = new Font("Segoe UI", 36, FontStyle.Bold)) {
						var sz = bg.MeasureString(labels[i], font);
						bg.FillRectangle(new SolidBrush(Color.FromArgb(200, 0, 0, 0)), 10, 10, sz.Width + 16, sz.Height + 8);
						bg.DrawString(labels[i], font, Brushes.White, 18, 14);
					}
					g.DrawImage(bmp, 0, row * ph, pw, ph);
				}
				row++;
			}
			sheet.Save(path, ImageFormat.Png);
		}
	}

	// Any path may be empty (layer not painted). Returns the report.
	public static string Run(string l1, string l2, string l3, string l4back, string l4front, string l4frontMask, string outDir) {
		var rep = new StringBuilder();
		LImg f1 = null, f2 = null, f3s = null, f3r = null, fb = null, ff = null;
		Func<string, string, int, Keyed> load = (name, p, keys) => {
			if (string.IsNullOrEmpty(p)) { rep.AppendLine(name + ": not painted"); return null; }
			var k = KeyFile(p, keys);
			rep.AppendLine(string.Format("{0}: {1} ({2} x {3}, aspect {4:0.000}; template 2400 x 920, {5:0.000})",
				name, System.IO.Path.GetFileName(p), k.SrcW, k.SrcH, (double)k.SrcW / k.SrcH, (double)W / H));
			return k;
		};
		// Key bits: magenta 1, blue 2, green 4, yellow 8, orange 16, cyan 32 (green, yellow and orange are only in L4's guides).
		var k1 = load("L1 outer border", l1, 35); if (k1 != null) f1 = FitL1(k1, rep);
		var k2 = load("L2 inner border", l2, 35); if (k2 != null) f2 = FitL2(k2, rep);
		var k3 = load("L3 ring", l3, 35); if (k3 != null) { f3s = FitL3(k3, false, rep); f3r = FitL3(k3, true, null); }
		var kb = load("L4 back", l4back, 63);
		if (kb != null) {
			var rect = L4Rect(kb, rep);
			var raw = Place(kb.Img, rect);
			if (!string.IsNullOrEmpty(l4frontMask)) {
				// L4 front cut out of the same painting, so it matches L4 back pixel for pixel where they meet.
				rep.AppendLine("L4 front: cut from L4 back by " + System.IO.Path.GetFileName(l4frontMask));
				var mask = Place(LoadMask(l4frontMask), rect);
				ff = new LImg(W, H);
				for (int i = 0; i < W * H; i++) for (int c = 0; c < 4; c++) ff.P[i * 4 + c] = raw.P[i * 4 + c] * mask.P[i * 4 + 3];
				ff = L4Rules(ff, true, rep);
			}
			rep.AppendLine("L4 back rules:");
			fb = L4Rules(raw, false, rep);
		}
		if (ff == null) {
			var kf = load("L4 front", l4front, 63);
			if (kf != null) {
				ff = FitL4(kf, true, rep);
				rep.AppendLine("  note: a separately painted front never matches the back pixel for pixel; a <variant>-L4-front-mask stitches exactly");
			}
		}

		foreach (var mode in new[] { "scale", "remap" }) {
			var ring = mode == "scale" ? f3s : f3r;
			var c = Compose(f1, f2, ring, fb, ff, true);
			using (var bmp = ToBitmap(c)) {
				SavePng(bmp, System.IO.Path.Combine(outDir, "preview-ring-" + mode + ".png"), 1);
				SavePng(bmp, System.IO.Path.Combine(outDir, "preview-ring-" + mode + "-half.png"), 0.5);
			}
			int seams = Seams(Compose(f1, f2, ring, fb, ff, false), c);
			rep.AppendLine(seams == 0 ? "Seams (ring " + mode + "): ok, the stacked frame is solid"
				: string.Format("Seams (ring {0}): FIX  {1} see-through px in the frame's body, red in seams-ring-{0}.png", mode, seams));
			using (var bmp = ToBitmap(c)) bmp.Save(System.IO.Path.Combine(outDir, "seams-ring-" + mode + ".png"), ImageFormat.Png);
			if (f3s == null) break;
		}
		Sheet(System.IO.Path.Combine(outDir, "fit-sheet.png"),
			new[] { "L1 outer border", "L2 inner border", "L3 ring (scale)", "L3 ring (remap)", "L4 back", "L4 front" },
			new[] { f1, f2, f3s, f3r, fb, ff });
		var names = new[] { "L1", "L2", "L3-scale", "L3-remap", "L4-back", "L4-front" };
		var fitted = new[] { f1, f2, f3s, f3r, fb, ff };
		for (int i = 0; i < names.Length; i++) if (fitted[i] != null)
			using (var bmp = ToBitmap(fitted[i])) bmp.Save(System.IO.Path.Combine(outDir, "fitted-" + names[i] + ".png"), ImageFormat.Png);
		return rep.ToString();
	}
}
