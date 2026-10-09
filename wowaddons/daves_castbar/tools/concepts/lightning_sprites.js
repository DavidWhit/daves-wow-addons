// Lightning, reference cloud sprites (2026-10-09): the user's own cloud painting is the cloud. Its
// checkerboard backing is keyed out (the painting is blue-grey, the checker neutral), the cut-out is
// softened at its edge, and copies of it, some mirrored, at mixed sizes, are placed about the bar and
// drift slowly. The sky stays a mid storm grey-blue rather than near-black. A's bolts, flashes and the
// leading-edge spark; strikes light the clouds they hit.
(() => {
	function cnv(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }
	// ---- the cut-out, made once when the embedded image has loaded
	const REF = { cv: null, lit: null, w: 0, h: 0 };
	const img = new Image();
	img.onload = () => {
		const w = img.width, h = img.height, cv = cnv(w, h), g = cv.getContext('2d');
		g.drawImage(img, 0, 0);
		const d = g.getImageData(0, 0, w, h), p = d.data;
		const A = new Float32Array(w * h);
		for (let i = 0, j = 0; i < p.length; i += 4, j++) A[j] = clamp((p[i + 2] - p[i] - 3) / 9);   // the cloud is bluer than it is red; the checker is neutral
		// choke the matte by a pixel (the edge pixels still carry the checker's light grey, which read as a
		// white rim), then colour the remaining edge toward the cloud's own dark tone
		const E = new Float32Array(w * h);
		for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
			let m = 1;
			for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
				const yy = Math.min(h - 1, Math.max(0, y + dy)), xx = Math.min(w - 1, Math.max(0, x + dx));
				m = Math.min(m, A[yy * w + xx]);
			}
			E[y * w + x] = m;
		}
		for (let i = 0, j = 0; i < p.length; i += 4, j++) {
			const a = E[j];
			if (a <= 0) { p[i + 3] = 0; continue; }
			const k = 1 - a;   // edge pixels darken toward the underside's dark indigo instead of lightening
			p[i] = p[i] * (1 - k * .6) + 30 * k * .6; p[i + 1] = p[i + 1] * (1 - k * .6) + 26 * k * .6; p[i + 2] = p[i + 2] * (1 - k * .6) + 52 * k * .6;
			p[i + 3] = a * 255;
		}
		g.putImageData(d, 0, 0);
		// soften: a slightly blurred copy of the alpha, so the cut edge is smooth, not pixel-stepped
		const soft = cnv(w, h), sg = soft.getContext('2d');
		sg.filter = 'blur(1.2px)'; sg.drawImage(cv, 0, 0); sg.filter = 'none';
		sg.globalCompositeOperation = 'source-in'; sg.drawImage(cv, 0, 0);   // the colours stay sharp, only the edge alpha softens
		sg.globalCompositeOperation = 'destination-in'; sg.drawImage(soft, 0, 0);
		REF.cv = soft; REF.w = w; REF.h = h;
		// a lit copy for strikes lighting a cloud from within
		const lit = cnv(w, h), lx = lit.getContext('2d');
		lx.drawImage(soft, 0, 0); lx.globalCompositeOperation = 'source-in';
		const lg = lx.createLinearGradient(0, 0, 0, h);
		lg.addColorStop(0, 'rgb(205,220,255)'); lg.addColorStop(.6, 'rgb(130,150,235)'); lg.addColorStop(1, 'rgb(50,60,130)');
		lx.fillStyle = lg; lx.fillRect(0, 0, w, h);
		REF.lit = lit;
	};
	img.src = REF_CLOUD_B64;

	// ---- bolts, as A
	function jag(x1, y1, x2, y2, disp, levels = 5) {
		let pts = [[x1, y1], [x2, y2]];
		for (let l = 0; l < levels; l++) {
			const out = [pts[0]];
			for (let i = 1; i < pts.length; i++) {
				const a = pts[i - 1], b = pts[i], mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
				const nx = -(b[1] - a[1]), ny = b[0] - a[0], n = Math.hypot(nx, ny) || 1, o = rand(-disp, disp);
				out.push([mx + nx / n * o, my + ny / n * o], b);
			}
			pts = out; disp *= .5;
		}
		return pts;
	}
	function forked(x1, y1, x2, y2, disp, forks, levels) {
		const main = jag(x1, y1, x2, y2, disp, levels), segs = [{ pts: main, w: 1 }];
		for (let f = 0; f < forks; f++) {
			const i = Math.floor(rand(.2, .8) * main.length), a = main[i];
			const ang = Math.atan2(y2 - y1, x2 - x1) + rand(.4, 1.1) * (Math.random() < .5 ? -1 : 1);
			const len = Math.hypot(x2 - x1, y2 - y1) * rand(.2, .45);
			segs.push({ pts: jag(a[0], a[1], a[0] + Math.cos(ang) * len, a[1] + Math.sin(ang) * len, disp * .5, 3), w: .5 });
		}
		return segs;
	}
	function drawBolt(g, pts, w, col, a) {
		g.save(); g.globalCompositeOperation = 'lighter'; g.lineCap = 'round'; g.lineJoin = 'round';
		for (const [lw, c, al] of [[w * 5, col, .12 * a], [w * 2.2, col, .35 * a], [w, [255, 255, 255], a]]) {
			g.strokeStyle = rgba(c, al); g.lineWidth = lw; g.beginPath();
			pts.forEach((p, i) => i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1])); g.stroke();
		}
		g.restore();
	}
	function clipBar(g, s, w) { roundRectPath(g, 0, 0, w, s.H, s.H * .18); g.clip(); }

	// ---- the look. o.sky = [top, mid, bottom] colours; o.clouds(s) → list of { x, y (centre, bar px), h (height, bar px), flip, v, ph, a }
	function sprites(o) {
		CONCEPTS.push({
			group: 'Lightning', id: o.id, letter: o.letter, name: o.name, desc: o.desc,
			spell: 'Lightning Bolt', padTop: .9, padBottom: .6, flash: [190, 215, 255],
			init(s) {
				s.clouds = o.clouds(s);
				s.bolts = []; s.nextBolt = .15; s.flash = 0; s.flashX = 0; s.sheet = 0; s.sheetX = 0; s.roll = wobble(2);
			},
			draw(g, s) {
				const { H, fill, dt, W } = s;
				g.save(); clipBar(g, s, fill);
				const bg = g.createLinearGradient(0, 0, 0, H);
				bg.addColorStop(0, rgba(o.sky[0])); bg.addColorStop(.55, rgba(o.sky[1])); bg.addColorStop(1, rgba(o.sky[2]));
				g.fillStyle = bg; g.fillRect(0, 0, fill, H);
				if (Math.random() < dt * .8) { s.sheet = rand(.35, .6); s.sheetX = rand(0, fill); }
				s.sheet = Math.max(0, s.sheet - dt * 3);
				if (REF.cv) {
					for (const c of s.clouds) {
						c.x += c.v * H * dt;
						const span = W + c.h * 2.4;
						if (c.x > W + c.h * 1.2) c.x -= span; else if (c.x < -c.h * 1.2) c.x += span;
						const w = c.h * REF.w / REF.h, y = c.y + Math.sin(s.t * .35 + c.ph) * H * .03;
						g.save(); g.globalAlpha = c.a; g.translate(c.x, y); if (c.flip) g.scale(-1, 1);
						g.drawImage(REF.cv, -w / 2, -c.h / 2, w, c.h);
						// strikes and sheet lightning light the cloud from within, fading with distance
						for (const [I, cx, reach] of [[s.flash * .6, s.flashX, H * 2.4], [s.sheet * .35, s.sheetX, H * 2]]) {
							const d = Math.abs(cx - c.x) / reach, k = I * Math.max(0, 1 - d * d);
							if (k > .02) { g.globalCompositeOperation = 'lighter'; g.globalAlpha = c.a * k; g.drawImage(REF.lit, -w / 2, -c.h / 2, w, c.h); g.globalCompositeOperation = 'source-over'; }
						}
						g.restore();
					}
				}
				if (s.flash > 0) {
					g.globalCompositeOperation = 'lighter';
					const fg = g.createRadialGradient(s.flashX, H / 2, 0, s.flashX, H / 2, H * 2.5);
					fg.addColorStop(0, rgba([110, 140, 255], .2 * s.flash)); fg.addColorStop(1, rgba([110, 140, 255], 0));
					g.fillStyle = fg; g.fillRect(0, 0, fill, H); g.globalCompositeOperation = 'source-over';
				}
				s.flash = Math.max(0, s.flash - dt * 5);
				s.nextBolt -= dt;
				if (s.casting && s.nextBolt <= 0 && fill > H * 1.2) {
					s.nextBolt = rand(.08, .3);
					const x1 = rand(H * .3, fill - H * .3), dx = rand(H * .6, H * 2.4) * (Math.random() < .5 ? -1 : 1);
					const x2 = clamp(x1 + dx, H * .2, fill - H * .2);
					s.bolts.push({ segs: forked(x1, -H * .05, x2, H * 1.05, H * .35, Math.floor(rand(1, 4)), 5), age: 0, life: rand(.18, .32), x: (x1 + x2) / 2, ph: rand(0, 6.283) });
					s.flash = 1; s.flashX = (x1 + x2) / 2;
				}
				for (const b of s.bolts) {
					b.age += dt;
					const t = b.age / b.life, a = (1 - t) * (.7 + .3 * Math.sin(b.age * 90 + b.ph));
					for (const sg of b.segs) drawBolt(g, sg.pts, Math.max(1, H * .045) * sg.w, [130, 170, 255], a);
				}
				s.bolts = s.bolts.filter(b => b.age < b.life);
				g.restore();
				// the leading edge: a faint glow and the spark, as A
				if (s.casting && fill > 2) {
					g.save(); clipBar(g, s, fill);
					const e = fill, eg = g.createLinearGradient(e - H * 1.2, 0, e, 0), f = .25 + .2 * (s.roll(s.t * 6) + 1) / 2 + (Math.random() < .08 ? .3 : 0);
					eg.addColorStop(0, 'rgba(120,150,255,0)'); eg.addColorStop(1, rgba([150, 180, 255], f));
					g.globalCompositeOperation = 'lighter'; g.fillStyle = eg; g.fillRect(e - H * 1.2, 0, H * 1.2, H);
					g.restore();
					const sa = .75 + .25 * s.roll(s.t * 9), sw = H * .45, sh = H * .85;
					g.save(); g.globalCompositeOperation = 'lighter'; g.translate(e, H / 2); g.scale(1, sh / sw);
					const sg = g.createRadialGradient(0, 0, 0, 0, 0, sw);
					sg.addColorStop(0, rgba([235, 245, 255], sa)); sg.addColorStop(.25, rgba([200, 225, 255], .7 * sa)); sg.addColorStop(1, rgba([130, 170, 255], 0));
					g.fillStyle = sg; g.beginPath(); g.arc(0, 0, sw, 0, 6.283); g.fill();
					g.fillStyle = rgba([255, 255, 255], .85 * sa); g.fillRect(-Math.max(.6, H * .025), -sw * .8, Math.max(1.2, H * .05), sw * 1.6);
					g.restore();
				}
			},
		});
	}

	const SKY_MID = [[72, 82, 104], [52, 60, 80], [34, 40, 56]];      // a mid storm grey-blue
	const SKY_LIGHT = [[98, 108, 130], [70, 78, 100], [46, 52, 70]];
	const SKY_DARK = [[22, 26, 60], [14, 16, 49], [7, 8, 26]];        // A3's dark blue sky (C2 uses it: picked 2026-10-09)
	sprites({
		id: 'light-c1', letter: 'C1', name: 'Reference clouds, scattered',
		desc: 'Your cloud painting, cut out and placed about the bar at mixed sizes (some mirrored), drifting slowly on a mid grey-blue sky; A\'s bolts and flashes light the clouds they strike',
		sky: SKY_MID,
		clouds(s) {
			const { W, H } = s, list = [];
			for (let x = -H; x < W + H; x += H * rand(1.1, 2)) {
				const far = Math.random() < .4, h = H * (far ? rand(.5, .8) : rand(.9, 1.4));
				list.push({ x, y: far ? H * rand(.15, .45) : H * rand(.45, .75), h, flip: Math.random() < .5, v: (far ? rand(.03, .07) : rand(.08, .16)) * (Math.random() < .25 ? -1 : 1), ph: rand(0, 6.283), a: far ? .7 : 1 });
			}
			return list.sort((a, b) => a.h - b.h);   // small (far) ones behind
		},
	});
	sprites({
		id: 'light-c2', letter: 'C2', name: 'Reference clouds, bank',
		desc: 'The same cut-out, larger and overlapping into one continuous bank along the bar with its bases low; a few small far ones above; A3\'s dark blue sky. Picked for the game (2026-10-09)',
		sky: SKY_DARK,
		clouds(s) {
			const { W, H } = s, list = [];
			for (let x = -H; x < W + H; x += H * rand(1.4, 2.2)) list.push({ x, y: H * rand(.1, .35), h: H * rand(.45, .7), flip: Math.random() < .5, v: rand(.03, .06), ph: rand(0, 6.283), a: .65 });
			for (let x = -H; x < W + H; x += H * rand(1.3, 1.8)) list.push({ x, y: H * rand(.6, .8), h: H * rand(1.3, 1.7), flip: Math.random() < .5, v: rand(.07, .13), ph: rand(0, 6.283), a: 1 });
			return list;
		},
	});
	sprites({
		id: 'light-c3', letter: 'C3', name: 'Reference clouds, light sky',
		desc: 'C1 on a lighter storm-grey sky, so the bar is no darker than the other looks; the strikes and flashes read against the clouds',
		sky: SKY_LIGHT,
		clouds(s) {
			const { W, H } = s, list = [];
			for (let x = -H; x < W + H; x += H * rand(1.1, 2)) {
				const far = Math.random() < .4, h = H * (far ? rand(.5, .8) : rand(.9, 1.4));
				list.push({ x, y: far ? H * rand(.15, .45) : H * rand(.45, .75), h, flip: Math.random() < .5, v: (far ? rand(.03, .07) : rand(.08, .16)) * (Math.random() < .25 ? -1 : 1), ph: rand(0, 6.283), a: far ? .7 : 1 });
			}
			return list.sort((a, b) => a.h - b.h);
		},
	});
})();
