using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

// Cuts the bar windows out of the art with smooth (anti-aliased) edges: a rounded window, minus the whole ring.
public static class Mask {
	public static void Cut(string src, string dst, float x0, float y0, float x1, float y1, float radius,
		float cx, float cy, float ringR) {
		var art = new Bitmap(src);
		int w = art.Width, h = art.Height;
		var mask = new Bitmap(w, h, PixelFormat.Format32bppArgb);
		using (var g = Graphics.FromImage(mask)) {
			g.SmoothingMode = SmoothingMode.AntiAlias;
			g.PixelOffsetMode = PixelOffsetMode.HighQuality;
			g.Clear(Color.White);
			var win = new GraphicsPath(); float d = radius * 2;
			win.AddArc(x0, y0, d, d, 180, 90); win.AddArc(x1 - d, y0, d, d, 270, 90);
			win.AddArc(x1 - d, y1 - d, d, d, 0, 90); win.AddArc(x0, y1 - d, d, d, 90, 90); win.CloseFigure();
			g.FillPath(Brushes.Black, win);
			g.FillEllipse(Brushes.White, cx - ringR, cy - ringR, ringR * 2, ringR * 2);
		}
		var ad = art.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
		var md = mask.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
		var a = new byte[w * h * 4]; var m = new byte[w * h * 4];
		Marshal.Copy(ad.Scan0, a, 0, a.Length); Marshal.Copy(md.Scan0, m, 0, m.Length);
		art.UnlockBits(ad); mask.UnlockBits(md); mask.Dispose();
		for (int i = 0; i < w * h; i++) a[i * 4 + 3] = (byte)(a[i * 4 + 3] * m[i * 4 + 2] / 255);
		var res = new Bitmap(w, h, PixelFormat.Format32bppArgb);
		var rd = res.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
		Marshal.Copy(a, 0, rd.Scan0, a.Length); res.UnlockBits(rd);
		art.Dispose();
		res.Save(dst, ImageFormat.Png); res.Dispose();
	}
}
