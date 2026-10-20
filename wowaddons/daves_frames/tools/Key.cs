using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// Cuts the magenta background and the blue portrait opening out of a frame painting.
// Darkened magenta (a painted drop shadow) becomes a soft black shadow. Prints the geometry it finds.
public static class Key {
	static float Clamp(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

	public static string Run(string src, string dst, float scale) {
		var bmp = new Bitmap(src);
		int w = bmp.Width, h = bmp.Height;
		var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
		var px = new byte[w * h * 4];
		Marshal.Copy(data.Scan0, px, 0, px.Length);
		bmp.UnlockBits(data); bmp.Dispose();

		var outp = new byte[px.Length];
		var isBlue = new bool[w * h];
		var solid = new bool[w * h];
		for (int i = 0; i < w * h; i++) {
			int o = i * 4;
			float b = px[o] / 255f, g = px[o + 1] / 255f, r = px[o + 2] / 255f;
			float mag = Math.Min(r, b) - g;          // magenta-ness
			float blu = b - Math.Max(r, g);          // blue-ness
			float a, cr = r, cg = g, cb = b;
			if (blu > 0.45f) { a = 0; isBlue[i] = true; }
			else if (blu > 0.25f) {
				a = 1 - Clamp((blu - 0.25f) / 0.2f);
				float k = 1 - a; cb = Clamp((b - k) / Math.Max(a, 0.05f)); // remove the blue the edge mixed in
				cb = Math.Min(cb, Math.Max(r, g) * 1.1f);
			} else {
				a = 1 - Clamp((mag - 0.30f) / 0.30f);
				if (a < 1) {
					// Remove magenta spill at the edge: pull r and b toward g.
					float spill = Math.Max(0, Math.Min(r, b) - g) * (1 - a);
					cr = Clamp(r - spill); cb = Clamp(b - spill);
				}
			}
			if (a <= 0.001f && !isBlue[i]) {
				// Background. Darker magenta than the plain backdrop is a painted shadow.
				float bg = Math.Min(r, b);
				float sh = Clamp((0.82f - bg) / 0.4f) * 0.7f;
				outp[o] = 0; outp[o + 1] = 0; outp[o + 2] = 0; outp[o + 3] = (byte)(sh * 255);
				continue;
			}
			{ float sp = Math.Max(0, Math.Min(cr, cb) - cg); cr -= sp * 0.85f; cb -= sp * 0.85f; }
			solid[i] = a > 0.5f;
			outp[o] = (byte)(cb * 255); outp[o + 1] = (byte)(cg * 255); outp[o + 2] = (byte)(cr * 255); outp[o + 3] = (byte)(a * 255);
		}

		// Geometry, in source pixels.
		int bx0 = w, bx1 = 0, by0 = h, by1 = 0;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (isBlue[y * w + x]) {
			if (x < bx0) bx0 = x; if (x > bx1) bx1 = x; if (y < by0) by0 = y; if (y > by1) by1 = y;
		}
		float cx = (bx0 + bx1) / 2f, cy = (by0 + by1) / 2f, rIn = (bx1 - bx0 + by1 - by0) / 4f;
		// Ring outer edge: straight down from the opening until the background.
		int ry = by1 + 6; while (ry < h - 1 && solid[ry * w + (int)cx]) ry++;
		float rOut = ry - cy;
		// Plate and window along the centre row.
		int row = (int)cy;
		Func<int, int, float> L = (x, y) => { int o = (y * w + x) * 4; return (px[o] + px[o + 1] + px[o + 2]) / 3f; };
		int pl = 0; while (pl < w && !solid[row * w + pl]) pl++;
		int pr = w - 1; while (pr > 0 && !solid[row * w + pr]) pr--;
		int wl = pl; while (wl < cx && L(wl, row) > 40) wl++;
		int wr = pr; while (wr > cx && L(wr, row) > 40) wr--;
		int probe = wl + 80;
		int wt = row; while (wt > 0 && L(probe, wt) < 55) wt--;
		int wb = row; while (wb < h - 1 && L(probe, wb) < 55) wb++;
		int probeR = wr - 80;
		int wtR = row; while (wtR > 0 && L(probeR, wtR) < 55) wtR--;
		int wbR = row; while (wbR < h - 1 && L(probeR, wbR) < 55) wbR++;
		int pt = row; while (pt > 0 && solid[pt * w + probe]) pt--;
		int pb = row; while (pb < h - 1 && solid[pb * w + probe]) pb++;

		// Crop to everything that isn't plain background, then scale.
		int x0 = w, x1 = 0, y0 = h, y1 = 0;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) if (outp[(y * w + x) * 4 + 3] > 8) {
			if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
		}
		x0 = Math.Max(0, x0 - 4); y0 = Math.Max(0, y0 - 4); x1 = Math.Min(w - 1, x1 + 4); y1 = Math.Min(h - 1, y1 + 4);
		int cw = x1 - x0 + 1, ch = y1 - y0 + 1;
		var full = new Bitmap(cw, ch, PixelFormat.Format32bppArgb);
		var fd = full.LockBits(new Rectangle(0, 0, cw, ch), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
		for (int y = 0; y < ch; y++) Marshal.Copy(outp, ((y + y0) * w + x0) * 4, fd.Scan0 + y * fd.Stride, cw * 4);
		full.UnlockBits(fd);
		int ow = (int)Math.Round(cw * scale), oh = (int)Math.Round(ch * scale);
		var small = new Bitmap(ow, oh, PixelFormat.Format32bppPArgb);
		using (var g = Graphics.FromImage(small)) {
			g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
			g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
			g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
			g.DrawImage(full, new Rectangle(0, 0, ow, oh));
		}
		small.Save(dst, ImageFormat.Png); small.Dispose(); full.Dispose();

		Func<float, float, string> X = (v, off) => ((v - off) * scale).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture);
		return "{\"w\":" + ow + ",\"h\":" + oh
			+ ",\"cx\":" + X(cx, x0) + ",\"cy\":" + X(cy, y0) + ",\"rIn\":" + X(rIn, 0) + ",\"rOut\":" + X(rOut, 0)
			+ ",\"plateL\":" + X(pl, x0) + ",\"plateR\":" + X(pr, x0) + ",\"plateT\":" + X(pt, y0) + ",\"plateB\":" + X(pb, y0)
			+ ",\"winL\":" + X(wl, x0) + ",\"winR\":" + X(wr, x0)
			+ ",\"winTL\":" + X(wt, y0) + ",\"winBL\":" + X(wb, y0) + ",\"winTR\":" + X(wtR, y0) + ",\"winBR\":" + X(wbR, y0) + "}";
	}
}
