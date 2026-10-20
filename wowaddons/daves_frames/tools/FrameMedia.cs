using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

// Game textures for daves_frames: uncompressed 32-bit TGA (top-left origin), power-of-two sizes.
public static class FrameMedia {
	// Writes a bitmap as an uncompressed 32-bit TGA, 8 alpha bits, top-left origin.
	public static void WriteTga(Bitmap bmp, string path) {
		int w = bmp.Width, h = bmp.Height;
		var d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
		var px = new byte[w * h * 4];
		for (int y = 0; y < h; y++) Marshal.Copy(d.Scan0 + y * d.Stride, px, y * w * 4, w * 4);
		bmp.UnlockBits(d);
		var head = new byte[18];
		head[2] = 2;
		head[12] = (byte)(w & 255); head[13] = (byte)(w >> 8);
		head[14] = (byte)(h & 255); head[15] = (byte)(h >> 8);
		head[16] = 32; head[17] = 0x28;
		using (var f = File.Create(path)) { f.Write(head, 0, 18); f.Write(px, 0, px.Length); }
	}

	static Bitmap Canvas(int w, int h) {
		var b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
		using (var g = Graphics.FromImage(b)) g.Clear(Color.Transparent);
		return b;
	}

	static void Draw(Graphics g, Image src, Rectangle to, Rectangle from) {
		g.InterpolationMode = InterpolationMode.HighQualityBicubic;
		g.PixelOffsetMode = PixelOffsetMode.HighQuality;
		g.CompositingMode = CompositingMode.SourceCopy;
		using (var ia = new ImageAttributes()) {
			ia.SetWrapMode(WrapMode.TileFlipXY);   // no dark fringe at the source edges
			g.DrawImage(src, to, from.X, from.Y, from.Width, from.Height, GraphicsUnit.Pixel, ia);
		}
	}

	// The frame atlas (2048 x 1024): the cut frame art across the top, scaled to 2048 wide, and the board
	// strip (the plate's two ends side by side) in the rows below it. Returns "artH stripY stripW stripH".
	public static string Atlas(string artPng, string fullPng, string outTga, int bandTop2x, int bandBottom2x) {
		using (var art = new Bitmap(artPng)) using (var full = new Bitmap(fullPng)) {
			int W = 2048, H = 1024;
			double s = (double)W / art.Width;
			int artH = (int)Math.Round(art.Height * s);
			var atlas = Canvas(W, H);
			using (var g = Graphics.FromImage(atlas)) {
				Draw(g, art, new Rectangle(0, 0, W, artH), new Rectangle(0, 0, art.Width, art.Height));
				// Board strip: 600 x band at 1x = 1200 x (band*2) at 2x, the left and right 600 px of the plate.
				int bh = bandBottom2x - bandTop2x, sw = 1024, sh = (int)Math.Round(bh * 1024.0 / 1200.0);
				int sy = artH + 8;
				using (var strip = new Bitmap(1200, bh, PixelFormat.Format32bppArgb)) {
					using (var sg = Graphics.FromImage(strip)) {
						sg.Clear(Color.Transparent); sg.CompositingMode = CompositingMode.SourceCopy;
						sg.DrawImage(full, new Rectangle(0, 0, 600, bh), new Rectangle(0, bandTop2x, 600, bh), GraphicsUnit.Pixel);
						sg.DrawImage(full, new Rectangle(600, 0, 600, bh), new Rectangle(full.Width - 600, bandTop2x, 600, bh), GraphicsUnit.Pixel);
					}
					Draw(g, strip, new Rectangle(0, sy, sw, sh), new Rectangle(0, 0, 1200, bh));
				}
				WriteTga(atlas, outTga);
				atlas.Dispose();
				return artH + " " + sy + " " + sw + " " + sh;
			}
		}
	}

	static Color Mix(Color a, Color b, double t) {
		t = Math.Max(0, Math.Min(1, t));
		return Color.FromArgb((int)(a.A + (b.A - a.A) * t), (int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
	}

	// One repeat of a chain, 32 x 64, tiling vertically: a face-on ring, then an edge-on link that runs
	// through the bottom of this ring and on into the top of the next repeat's ring.
	public static void Chain(string outTga, int r1, int g1, int b1, int r2, int g2, int b2, int r3, int g3, int b3) {
		Color hi = Color.FromArgb(r1, g1, b1), mid = Color.FromArgb(r2, g2, b2), dark = Color.FromArgb(r3, g3, b3);
		var bmp = Canvas(32, 64);
		using (var g = Graphics.FromImage(bmp)) {
			g.SmoothingMode = SmoothingMode.AntiAlias;
			using (var pd = new Pen(dark, 6.5f)) using (var pm = new Pen(mid, 4f)) using (var ph = new Pen(hi, 1.6f))
			using (var bd = new SolidBrush(dark)) using (var bm = new SolidBrush(mid)) {
				// Edge-on link from y 28 to the tile's bottom, and its end again at the top (the wrap).
				foreach (var seg in new[] { new[] { 28f, 36f }, new[] { 0f, 8f } }) {
					g.FillRectangle(bd, 12.5f, seg[0], 7, seg[1]);
					g.FillRectangle(bm, 14, seg[0], 4, seg[1]);
				}
				g.DrawLine(ph, 15, 32, 15, 60);
				// Face-on ring over the link ends.
				g.DrawEllipse(pd, 7, 6, 18, 26); g.DrawEllipse(pm, 7, 6, 18, 26);
				g.DrawArc(ph, 9, 8, 14, 22, 200, 70);
			}
		}
		WriteTga(bmp, outTga); bmp.Dispose();
	}

	// Shield stripes, 32 x 32, tiling: white diagonal bands over a faint blue.
	public static void Stripes(string outTga) {
		var bmp = new Bitmap(32, 32, PixelFormat.Format32bppArgb);
		for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++) {
			// 45 degree bands, period 16 px: 8 px white, 8 px faint blue, with a half-step pixel at each edge.
			int k = (x + y) % 16;
			double t = k < 7 ? 0 : k == 7 || k == 15 ? 0.5 : 1;
			bmp.SetPixel(x, y, Mix(Color.FromArgb(230, 255, 255, 255), Color.FromArgb(90, 160, 200, 255), t));
		}
		WriteTga(bmp, outTga); bmp.Dispose();
	}
}
