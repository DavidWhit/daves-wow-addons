// Alchemy concepts: glassware, tubing and a potion that travels through it.
(() => {
	const PALETTES = [
		[[90, 255, 130], [50, 225, 235], [175, 100, 255], [255, 205, 70]],
		[[255, 90, 110], [255, 150, 60], [255, 225, 90], [255, 250, 210]],
		[[90, 150, 255], [110, 255, 225], [225, 120, 255], [255, 130, 200]],
		[[160, 255, 80], [255, 235, 70], [255, 130, 50], [255, 70, 120]],
	];
	const palAt = (pal, f) => { f = clamp(f) * (pal.length - 1); const i = Math.min(pal.length - 2, Math.floor(f)); return mix(pal[i], pal[i + 1], f - i); };
	const light = (c, k) => mix(c, [255, 255, 255], k);
	const dark = (c, k) => mix(c, [0, 0, 0], k);
	const barClip = (g, s) => { roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip(); };

	// ---- tubes: sampled cubic beziers
	function bez(a, b, c, d, n = 32) {
		const pts = [];
		for (let i = 0; i <= n; i++) {
			const t = i / n, u = 1 - t;
			pts.push([u * u * u * a[0] + 3 * u * u * t * b[0] + 3 * u * t * t * c[0] + t * t * t * d[0],
				u * u * u * a[1] + 3 * u * u * t * b[1] + 3 * u * t * t * c[1] + t * t * t * d[1]]);
		}
		return pts;
	}
	function pointAt(pts, f) {
		f = clamp(f) * (pts.length - 1); const k = Math.min(pts.length - 2, Math.floor(f)), r = f - k;
		return [lerp(pts[k][0], pts[k + 1][0], r), lerp(pts[k][1], pts[k + 1][1], r)];
	}
	function polyTo(g, pts, from = 0, to = 1) {
		const n = pts.length - 1, a = clamp(from) * n, b = clamp(to) * n;
		const p0 = pointAt(pts, from); g.beginPath(); g.moveTo(p0[0], p0[1]);
		for (let i = Math.floor(a) + 1; i < b; i++) g.lineTo(pts[i][0], pts[i][1]);
		const p1 = pointAt(pts, to); g.lineTo(p1[0], p1[1]);
		return p1;
	}
	function tubeGlass(g, pts, tw) {
		g.lineCap = 'round'; g.lineJoin = 'round';
		polyTo(g, pts); g.strokeStyle = 'rgba(205,235,255,.6)'; g.lineWidth = tw; g.stroke();
		g.strokeStyle = 'rgba(8,12,20,.65)'; g.lineWidth = tw * .62; g.stroke();
	}
	function tubeShine(g, pts, tw) {
		g.save(); g.translate(-tw * .1, -tw * .24); polyTo(g, pts);
		g.strokeStyle = 'rgba(255,255,255,.4)'; g.lineWidth = Math.max(.6, tw * .14); g.lineCap = 'round'; g.stroke(); g.restore();
	}
	function tubeLiquid(g, pts, from, to, tw, c1, c2) {
		if (to <= from) return null;
		const a = pts[0], b = pts[pts.length - 1], gr = g.createLinearGradient(a[0], a[1], b[0] + .01, b[1]);
		gr.addColorStop(0, rgba(c1)); gr.addColorStop(1, rgba(c2));
		const h = polyTo(g, pts, from, to); g.strokeStyle = gr; g.lineWidth = tw * .56; g.lineCap = 'round'; g.stroke();
		return h;
	}
	function glow(g, x, y, r, c, a) {
		if (r <= 0 || a <= 0) return;
		g.save(); g.globalCompositeOperation = 'lighter';
		const gr = g.createRadialGradient(x, y, 0, x, y, r);
		gr.addColorStop(0, rgba(c, a)); gr.addColorStop(1, rgba(c, 0));
		g.fillStyle = gr; g.beginPath(); g.arc(x, y, r, 0, 6.283); g.fill(); g.restore();
	}
	// a bunsen flame: blue at the root, warm at the tip
	function drawFlame(g, x, yb, h, w, t, seed) {
		if (h <= .5) return;
		const sway = Math.sin(t * 9 + seed) * w * .2 + Math.sin(t * 23 + seed * 3) * w * .08;
		const hh = h * (.86 + .14 * Math.sin(t * 31 + seed * 7));
		g.save(); g.globalCompositeOperation = 'lighter';
		const layer = (hk, wk, c0, c1) => {
			const H2 = hh * hk, W2 = w * wk, gr = g.createLinearGradient(0, yb, 0, yb - H2);
			gr.addColorStop(0, c0); gr.addColorStop(1, c1); g.fillStyle = gr;
			g.beginPath(); g.moveTo(x - W2 / 2, yb);
			g.bezierCurveTo(x - W2 * .7, yb - H2 * .45, x + sway * .5 - W2 * .15, yb - H2 * .7, x + sway * hk, yb - H2);
			g.bezierCurveTo(x + sway * .5 + W2 * .15, yb - H2 * .7, x + W2 * .7, yb - H2 * .45, x + W2 / 2, yb);
			g.closePath(); g.fill();
		};
		layer(1, 1, 'rgba(60,110,255,.9)', 'rgba(255,130,40,0)');
		layer(.6, .55, 'rgba(150,200,255,.95)', 'rgba(255,230,160,.3)');
		g.restore();
		glow(g, x, yb - hh * .3, w * 1.4, [80, 140, 255], .35);
	}

	// ---- glass vessels. yb is the bottom; yt the top of the neck (where the cork and tube go)
	function makeVessel(type, x, yb, S) {
		const v = { type, x, yb, S, seed: Math.random() };
		if (type === 'round') {
			const r = S * .3, cy = yb - r, nw = S * .13, a = Math.asin(nw / 2 / r);
			Object.assign(v, { yt: yb - 2 * r - S * .32, w: r, liqH: 2 * r * .9, nw, r, cy });
			v.path = g => { g.beginPath(); g.moveTo(x - nw / 2, v.yt); g.lineTo(x - nw / 2, cy - r * Math.cos(a)); g.arc(x, cy, r, -Math.PI / 2 - a, -Math.PI / 2 + a, true); g.lineTo(x + nw / 2, v.yt); g.closePath(); };
			v.shine = g => { g.beginPath(); g.arc(x, cy, r * .7, Math.PI * 1.08, Math.PI * 1.4); g.stroke(); };
		} else if (type === 'erlen') {
			const bw = S * .62, nw = S * .15, ys = yb - S * .58, k = S * .05;
			Object.assign(v, { yt: yb - S * .88, w: bw / 2, liqH: S * .52, nw });
			v.path = g => {
				g.beginPath(); g.moveTo(x - nw / 2, v.yt); g.lineTo(x - nw / 2, ys); g.lineTo(x - bw / 2, yb - k);
				g.quadraticCurveTo(x - bw / 2, yb, x - bw / 2 + k, yb); g.lineTo(x + bw / 2 - k, yb); g.quadraticCurveTo(x + bw / 2, yb, x + bw / 2, yb - k);
				g.lineTo(x + nw / 2, ys); g.lineTo(x + nw / 2, v.yt); g.closePath();
			};
			v.shine = g => { g.beginPath(); g.moveTo(x - nw * .3, ys + S * .06); g.lineTo(x - bw * .3, yb - S * .1); g.stroke(); };
		} else if (type === 'vial') {
			const w = S * .26, h = S * .95;
			Object.assign(v, { yt: yb - h, w: w / 2, liqH: h * .85, nw: w });
			v.path = g => roundRectPath(g, x - w / 2, yb - h, w, h, w * .4);
			v.shine = g => { g.beginPath(); g.moveTo(x - w * .2, yb - h * .82); g.lineTo(x - w * .2, yb - h * .2); g.stroke(); };
		} else {
			const bw = S * .5, bh = S * .46, nw = S * .16, ys = yb - S * .64, k = S * .07;
			Object.assign(v, { yt: yb - S * .84, w: bw / 2, liqH: bh, nw });
			v.path = g => {
				g.beginPath(); g.moveTo(x - nw / 2, v.yt); g.lineTo(x - nw / 2, ys); g.quadraticCurveTo(x - bw / 2, ys, x - bw / 2, yb - bh);
				g.lineTo(x - bw / 2, yb - k); g.quadraticCurveTo(x - bw / 2, yb, x - bw / 2 + k, yb); g.lineTo(x + bw / 2 - k, yb);
				g.quadraticCurveTo(x + bw / 2, yb, x + bw / 2, yb - k); g.lineTo(x + bw / 2, yb - bh); g.quadraticCurveTo(x + bw / 2, ys, x + nw / 2, ys);
				g.lineTo(x + nw / 2, v.yt); g.closePath();
			};
			v.shine = g => { g.beginPath(); g.moveTo(x - bw * .3, yb - bh * .85); g.lineTo(x - bw * .3, yb - bh * .2); g.stroke(); };
		}
		return v;
	}
	function drawVessel(g, v, level, col, t, boil, cork = true) {
		const { x, yb, S } = v;
		v.path(g); g.fillStyle = 'rgba(160,205,240,.12)'; g.fill();
		if (level > .01) {
			g.save(); v.path(g); g.clip();
			const sy = yb - level * v.liqH, ww = v.w * 1.3;
			const gr = g.createLinearGradient(0, sy, 0, yb);
			gr.addColorStop(0, rgba(light(col, .3), .95)); gr.addColorStop(1, rgba(dark(col, .4), .95));
			g.fillStyle = gr; g.beginPath(); g.moveTo(x - ww, yb + 2);
			const wave = i => sy + Math.sin(t * (4 + boil * 7) + i * 1.4 + v.seed * 9) * S * (.01 + boil * .018);
			for (let i = 0; i <= 8; i++) g.lineTo(x - ww + i * ww * 2 / 8, wave(i));
			g.lineTo(x + ww, yb + 2); g.closePath(); g.fill();
			g.beginPath(); for (let i = 0; i <= 8; i++) g.lineTo(x - ww + i * ww * 2 / 8, wave(i));
			g.strokeStyle = rgba(light(col, .75), .9); g.lineWidth = Math.max(.7, S * .025); g.stroke();
			glow(g, x, yb - level * v.liqH * .4, v.w * 1.4, col, .3 + .3 * boil);
			const N = 2 + Math.round(boil * 5);
			g.fillStyle = 'rgba(255,255,255,.7)';
			for (let k = 0; k < N; k++) {
				const ph = (t * (.5 + boil * 1.5) + k / N + v.seed) % 1;
				const by = yb - ph * level * v.liqH, bx = x + Math.sin(k * 2.3 + t * 2 + v.seed * 9) * v.w * .45;
				g.beginPath(); g.arc(bx, by, Math.max(.5, S * (.016 + .02 * ph) * (.7 + boil * .6)), 0, 6.283); g.fill();
			}
			g.restore();
		}
		v.path(g); g.lineWidth = Math.max(1, S * .04); g.strokeStyle = 'rgba(215,240,255,.8)'; g.lineJoin = 'round'; g.stroke();
		g.strokeStyle = 'rgba(255,255,255,.6)'; g.lineWidth = Math.max(.8, S * .035); g.lineCap = 'round'; v.shine(g);
		if (cork) {
			const cw = v.nw * 1.2, ch = Math.max(2, S * .08);
			g.fillStyle = '#8a5a32'; g.fillRect(x - cw / 2, v.yt - ch * .6, cw, ch);
			g.fillStyle = 'rgba(255,220,170,.3)'; g.fillRect(x - cw / 2, v.yt - ch * .6, cw, ch * .3);
		}
	}
	const rising = (s, x, y, col, H, a = .6) => s.parts.emit({ x, y, vx: rand(-.15, .15) * H, vy: -rand(.35, .7) * H, kind: 'glow', size: H * rand(.04, .07), grow: H * .02, life: rand(.7, 1.2), color: light(col, .5), alpha: a });
	const burst = (s, x, y, col, H, n = 10) => { for (let i = 0; i < n; i++) s.parts.emit({ x, y, vx: rand(-.9, .9) * H, vy: -rand(.3, 1.4) * H, ay: H * 2.5, drag: 1.5, kind: 'glow', size: H * rand(.04, .08), life: rand(.4, .8), color: light(col, .4) }); };

	// ------------------------------------------------------------------ A: the alchemist's table
	CONCEPTS.push({
		group: 'Alchemy', id: 'alch-a', letter: 'A', name: "Alchemist's table",
		desc: 'Glassware on a wooden table; the potion runs flask to flask through tubing, changing colour, and lights the table.',
		spell: 'Major Healing Potion', padTop: 1.7, flash: [230, 255, 235],
		init(s) {
			const H = s.H, W = s.W, n = clamp(Math.floor(W / (H * 1.7)), 3, 9), m = H * .75;
			s.pal = pick(PALETTES); s.vs = []; s.tw = Math.max(2, H * .085);
			for (let i = 0; i < n; i++) {
				const type = i === 0 ? pick(['round', 'erlen']) : pick(['round', 'erlen', 'vial', 'bottle']);
				const x = m + (W - 2 * m) * (i / (n - 1)) + rand(-.12, .12) * H;
				const v = makeVessel(type, x, 0, H * rand(.85, 1.12));
				v.col = palAt(s.pal, i / (n - 1)); s.vs.push(v);
			}
			s.tubes = [];
			for (let i = 0; i < n - 1; i++) {
				const a = s.vs[i], b = s.vs[i + 1], top = Math.min(a.yt, b.yt) - H * rand(.16, .28);
				s.tubes.push(bez([a.x, a.yt - H * .02], [a.x + H * .05, top], [b.x - H * .05, top], [b.x, b.yt + H * .06]));
			}
			s.wood = noise1();
			s.grain = Array.from({ length: 8 }, (_, k) => ({ y: (k + .5) / 8 + rand(-.03, .03), c: k % 2 ? 'rgba(150,100,60,.2)' : 'rgba(30,14,4,.5)', f: rand(2, 5), ph: rand(0, 6) }));
		},
		draw(g, s) {
			const W = s.W, H = s.H, X = s.fill, vs = s.vs, n = vs.length;
			const gap = i => (i < n - 1 ? vs[i + 1].x : W + H * .3) - vs[i].x;
			// the table
			g.save(); barClip(g, s);
			const wg = g.createLinearGradient(0, 0, 0, H);
			wg.addColorStop(0, '#6b4529'); wg.addColorStop(.5, '#523318'); wg.addColorStop(1, '#36200f');
			g.fillStyle = wg; g.fillRect(0, 0, W, H);
			g.lineWidth = 1;
			s.grain.forEach((L, k) => {
				g.strokeStyle = L.c; g.beginPath();
				for (let x = 0; x <= W + 4; x += 4) { const y = L.y * H + s.wood(x / (H * 1.3) + k * 7.7) * H * .07 + Math.sin(x / (H * L.f) + L.ph) * H * .02; x ? g.lineTo(x, y) : g.moveTo(x, y); }
				g.stroke();
			});
			// potion light spilling over the table behind the flow
			if (X > 0) {
				const lg = g.createLinearGradient(0, 0, W, 0);
				for (let i = 0; i < 4; i++) lg.addColorStop(i / 3, rgba(s.pal[i], .32));
				g.globalCompositeOperation = 'lighter'; g.fillStyle = lg; g.fillRect(0, 0, X, H);
				const eg = g.createLinearGradient(X - H * .8, 0, X, 0), ec = palAt(s.pal, X / W);
				eg.addColorStop(0, rgba(ec, 0)); eg.addColorStop(1, rgba(ec, .55));
				g.fillStyle = eg; g.fillRect(X - H * .8, 0, H * .8, H);
				g.globalCompositeOperation = 'source-over';
			}
			vs.forEach((v, i) => {
				g.fillStyle = 'rgba(0,0,0,.35)'; g.beginPath(); g.ellipse(v.x, 1, v.w * 1.1, H * .07, 0, 0, 6.283); g.fill();
				const lit = i === 0 ? 1 : clamp((X - v.x) / (H * .4));
				if (lit > 0) glow(g, v.x, 0, v.w * 2.6, v.col, .45 * lit);
			});
			g.fillStyle = 'rgba(255,210,160,.22)'; g.fillRect(0, 0, W, Math.max(1, H * .06));
			g.restore();

			// vessels: the first holds the potion and drains, the rest fill as it arrives
			vs.forEach((v, i) => {
				let level, boil;
				if (i === 0) { level = .78 - .4 * s.p; boil = 1; }
				else { level = (i === n - 1 ? .78 : .72) * clamp((X - v.x) / (gap(i) * .4)); boil = clamp((X - v.x) / (H * .5)); }
				if (i > 0 && !v.lit && X > v.x) { v.lit = true; burst(s, v.x, v.yt - H * .05, v.col, H); }
				drawVessel(g, v, level, v.col, s.t, boil);
				if (s.casting && boil > .5 && Math.random() < s.dt * 2.5) rising(s, v.x + rand(-.5, .5) * v.nw, v.yt - H * .08, v.col, H, .5);
			});
			// tubing, and the potion travelling through it
			const tw = s.tw;
			s.tubes.forEach(pts => tubeGlass(g, pts, tw));
			s.tubes.forEach((pts, i) => {
				const a = vs[i], b = vs[i + 1], d = gap(i) * .35, f = clamp((X - a.x - d) / (b.x - a.x - d));
				if (f <= 0) return;
				const h = tubeLiquid(g, pts, 0, f, tw, a.col, b.col);
				if (f < 1) { const hc = mix(a.col, b.col, f); glow(g, h[0], h[1], tw * 2.4, hc, .9); glow(g, h[0], h[1], tw * .6, [255, 255, 255], .8); }
				else if (b.yt + H * .06 < b.yb - .78 * b.liqH && s.casting && X - b.x < gap(i + 1) * .45) {
					// a thin stream pours from the tube end into the next vessel while it fills
					const lv = .72 * clamp((X - b.x) / (gap(i + 1) * .4)), sy = b.yb - lv * b.liqH;
					g.strokeStyle = rgba(light(b.col, .3), .85); g.lineWidth = Math.max(.8, tw * .3);
					g.beginPath(); g.moveTo(b.x, b.yt + H * .06); g.lineTo(b.x + Math.sin(s.t * 20) * .4, sy); g.stroke();
				}
			});
			s.tubes.forEach(pts => tubeShine(g, pts, tw));
			s.parts.update(s.dt); s.parts.draw(g);
		},
	});

	// ------------------------------------------------------------------ B: one long coil
	CONCEPTS.push({
		group: 'Alchemy', id: 'alch-b', letter: 'B', name: 'Coiled condenser',
		desc: 'A glass coil the length of the bar; the potion snakes through it from a heated flask to the receiving one.',
		spell: 'Elixir of the Mongoose', padTop: 1.3, padX: 1.0, padBottom: .8, flash: [235, 245, 255],
		init(s) {
			const H = s.H, W = s.W;
			s.pal = pick(PALETTES); s.P = H * rand(.75, .95); s.ph0 = rand(0, 6.283); s.seed = rand(0, 99);
			const r = H * .46;
			s.left = makeVessel('round', -H * .12, H / 2 + r, r / .3);
			s.right = makeVessel('round', W + H * .12, H / 2 + r, r / .3);
			s.puffT = 0;
		},
		draw(g, s) {
			const W = s.W, H = s.H, cy = H / 2, A = H * .3, c = s.P * .42, tw = Math.max(2, H * .15);
			const u0 = H * .1, u1 = W - H * .1, uF = lerp(u0, u1, s.fill / W);
			const at = u => { const th = s.ph0 + 6.283 * (u - u0) / s.P; return [u + c * Math.cos(th), cy + A * Math.sin(th), Math.cos(th) < 0]; };
			const build = (max, front) => {
				const P = new Path2D(); let on = false;
				for (let u = u0; u <= max + .01; u += 2) {
					const q = at(Math.min(u, max));
					if (q[2] === front) { on ? P.lineTo(q[0], q[1]) : P.moveTo(q[0], q[1]); on = true; } else on = false;
				}
				return P;
			};
			const lg = g.createLinearGradient(u0, 0, u1, 0);
			for (let i = 0; i < 4; i++) lg.addColorStop(i / 3, rgba(s.pal[i]));

			// glass case
			g.save(); barClip(g, s);
			const bg = g.createLinearGradient(0, 0, 0, H);
			bg.addColorStop(0, 'rgba(34,46,62,.95)'); bg.addColorStop(1, 'rgba(10,14,22,.95)');
			g.fillStyle = bg; g.fillRect(0, 0, W, H);
			if (s.fill > 0) { g.globalCompositeOperation = 'lighter'; g.globalAlpha = .2; g.fillStyle = lg; g.fillRect(0, 0, s.fill, H); g.globalAlpha = 1; g.globalCompositeOperation = 'source-over'; }
			g.lineCap = 'round'; g.lineJoin = 'round';
			g.strokeStyle = 'rgba(170,210,245,.42)'; g.lineWidth = tw * .9; g.stroke(build(u1, false)); g.strokeStyle = 'rgba(6,10,18,.5)'; g.lineWidth = tw * .55; g.stroke(build(u1, false));
			if (uF > u0) { g.globalAlpha = .6; g.strokeStyle = lg; g.lineWidth = tw * .5; g.stroke(build(uF, false)); g.globalAlpha = 1; }
			const fp = build(u1, true);
			g.strokeStyle = 'rgba(205,235,255,.6)'; g.lineWidth = tw; g.stroke(fp);
			g.strokeStyle = 'rgba(6,10,18,.6)'; g.lineWidth = tw * .62; g.stroke(fp);
			if (uF > u0) {
				g.strokeStyle = lg; g.lineWidth = tw * .55; g.stroke(build(uF, true));
				// bubbles riding along behind the head
				const L = uF - u0, sp = H * .55;
				g.fillStyle = 'rgba(255,255,255,.8)';
				for (let k = 0; k < Math.floor(L / sp); k++) {
					const q = at(uF - ((s.t * H * 1.3 + k * sp) % L));
					g.globalAlpha = q[2] ? .85 : .3; g.beginPath(); g.arc(q[0], q[1], Math.max(.6, tw * .14), 0, 6.283); g.fill();
				}
				g.globalAlpha = 1;
			}
			g.save(); g.translate(0, -tw * .24); g.strokeStyle = 'rgba(255,255,255,.4)'; g.lineWidth = Math.max(.6, tw * .13); g.stroke(fp); g.restore();
			g.fillStyle = 'rgba(255,255,255,.1)'; g.fillRect(0, H * .08, W, Math.max(1, H * .05));
			g.restore();
			if (uF > u0 && s.casting) {
				const h = at(uF), hc = palAt(s.pal, (uF - u0) / (u1 - u0));
				glow(g, h[0], h[1], tw * 2.6, hc, .95); glow(g, h[0], h[1], tw * .7, [255, 255, 255], .85);
				if (Math.random() < s.dt * 8) s.parts.emit({ x: h[0], y: h[1], vx: rand(-.4, .4) * H, vy: -rand(.3, .8) * H, kind: 'glow', size: H * .05, life: .5, color: light(hc, .4) });
			}
			// the flasks at either end: a heated one draining, a receiving one filling
			drawFlame(g, s.left.x, s.left.yb + H * .42, H * .4, H * .28, s.t, s.seed);
			drawVessel(g, s.left, .85 - .7 * s.p, s.pal[0], s.t, 1);
			drawVessel(g, s.right, .06 + .8 * s.p, s.pal[3], s.t, .35 + .4 * s.p);
			s.puffT -= s.dt;
			if (s.casting && s.puffT <= 0 && s.p > .08) {
				s.puffT = rand(.25, .5);
				s.parts.emit({ x: s.right.x + rand(-.05, .05) * H, y: s.right.yt - H * .08, vx: rand(-.1, .25) * H, vy: -rand(.5, .8) * H, kind: 'smoke', size: H * .12, grow: H * .35, life: rand(1, 1.5), color: light(s.pal[3], .55), alpha: .4 });
			}
			if (s.casting && Math.random() < s.dt * 3) rising(s, s.left.x, s.left.yt - H * .06, s.pal[0], H, .45);
			s.parts.update(s.dt); s.parts.draw(g);
		},
	});

	// ------------------------------------------------------------------ C: distillation chain
	CONCEPTS.push({
		group: 'Alchemy', id: 'alch-c', letter: 'C', name: 'Distillation chain',
		desc: 'Flasks boil over burners in turn; the vapour condenses in arching tubes and drips into a trough that fills.',
		spell: 'Flask of Distilled Wisdom', padTop: 1.75, flash: [255, 245, 220],
		init(s) {
			const H = s.H, W = s.W, n = clamp(Math.round(W / (H * 2.8)), 2, 5), Z = W / n;
			s.pal = pick(PALETTES); s.Z = Z; s.legH = H * .36; s.tw = Math.max(2, H * .08);
			s.st = Array.from({ length: n }, (_, i) => {
				const x = Z * (i + .35) + rand(-.04, .04) * Z, dripX = Z * (i + .86), r = H * .3;
				const v = makeVessel('round', x, -s.legH + r * .35, H);
				const tube = bez([x, v.yt - H * .02], [x + Z * .12, v.yt - H * .38], [dripX, v.yt - H * .25], [dripX, -H * .1]);
				return { x, dripX, v, tube, r, col: palAt(s.pal, n === 1 ? 0 : i / (n - 1)), dripT: 0, seed: rand(0, 99) };
			});
			s.drops = []; s.ripples = []; s.surf = H * .34;
		},
		draw(g, s) {
			const W = s.W, H = s.H, X = s.fill, Z = s.Z, sy = s.surf;
			const waveY = x => sy + Math.sin(x / (H * .45) - s.t * 3) * H * .025 + Math.sin(x / (H * .23) + s.t * 5) * H * .012;
			// the receiving trough
			g.save(); barClip(g, s);
			const bg = g.createLinearGradient(0, 0, 0, H);
			bg.addColorStop(0, 'rgba(30,38,52,.95)'); bg.addColorStop(1, 'rgba(8,10,16,.95)');
			g.fillStyle = bg; g.fillRect(0, 0, W, H);
			if (X > 1) {
				const lg = g.createLinearGradient(0, 0, W, 0);
				s.st.forEach(st => lg.addColorStop(clamp(st.dripX / W), rgba(st.col, .85)));
				const path = () => {
					g.beginPath(); g.moveTo(0, H + 1);
					for (let x = 0; x < X - H * .15; x += 3) g.lineTo(x, waveY(x));
					const ex = Math.max(0, X - H * .15);
					g.lineTo(ex, waveY(ex)); g.quadraticCurveTo(X + H * .1, waveY(ex), X, H * .75); g.lineTo(X, H + 1); g.closePath();
				};
				path(); g.fillStyle = lg; g.fill();
				const dg = g.createLinearGradient(0, sy, 0, H); dg.addColorStop(0, 'rgba(255,255,255,.15)'); dg.addColorStop(.3, 'rgba(0,0,0,0)'); dg.addColorStop(1, 'rgba(0,0,0,.4)');
				path(); g.fillStyle = dg; g.fill();
				g.beginPath(); for (let x = 0; x < X - H * .15; x += 3) g.lineTo(x, waveY(x));
				g.strokeStyle = 'rgba(255,255,255,.55)'; g.lineWidth = Math.max(.7, H * .035); g.stroke();
				const fc = palAt(s.pal, X / W); glow(g, X, H * .6, H * .7, fc, .55);
			}
			s.ripples = s.ripples.filter(r => (r.age += s.dt) < .5);
			for (const r of s.ripples) {
				const t = clamp(r.age / .5); g.strokeStyle = `rgba(255,255,255,${.7 * (1 - t)})`; g.lineWidth = 1;
				g.beginPath(); g.ellipse(r.x, r.y, H * (.05 + .3 * t), H * (.02 + .08 * t), 0, 0, 6.283); g.stroke();
			}
			g.fillStyle = 'rgba(255,255,255,.12)'; g.fillRect(0, H * .07, W, Math.max(1, H * .04));
			g.restore();

			// stations: burner, tripod, boiling flask, condenser tube
			const tw = s.tw;
			s.st.forEach((st, i) => {
				const start = Z * i, lp = clamp((X - start) / Z), heat = clamp((X - (start - Z * .15)) / (Z * .2)), r = st.r, v = st.v;
				g.fillStyle = '#3d3024'; g.strokeStyle = '#a07a45'; g.lineWidth = 1;
				g.beginPath(); g.ellipse(st.x, -H * .03, r * .5, H * .05, 0, 0, 6.283); g.fill(); g.stroke();
				drawFlame(g, st.x, -H * .06, s.legH * .85 * heat, r * .55, s.t, st.seed);
				glow(g, st.x, -s.legH, r * 1.3, [255, 140, 50], .35 * heat);
				g.strokeStyle = 'rgba(110,105,100,1)'; g.lineWidth = Math.max(1, H * .05); g.lineCap = 'round';
				g.beginPath(); g.moveTo(st.x - r, 0); g.lineTo(st.x - r * .75, -s.legH); g.moveTo(st.x + r, 0); g.lineTo(st.x + r * .75, -s.legH); g.stroke();
				drawVessel(g, v, .75 - .45 * lp, st.col, s.t, heat * (lp < 1 ? 1 : .4));
				g.strokeStyle = 'rgba(160,155,150,1)'; g.beginPath(); g.moveTo(st.x - r * .85, -s.legH); g.lineTo(st.x + r * .85, -s.legH); g.stroke();
				tubeGlass(g, st.tube, tw);
				// vapour travelling through the tube, condensing to liquid on the way down
				if (heat > .3 && lp < 1) {
					for (let k = 0; k < 5; k++) {
						const f = (s.t * .8 + k / 5 + st.seed) % 1, q = pointAt(st.tube, f);
						glow(g, q[0], q[1], tw * (f < .6 ? 1.1 : .8), f < .6 ? light(st.col, .6) : st.col, .8);
					}
					if (lp > .1) tubeLiquid(g, st.tube, .78, 1, tw, st.col, st.col);
					st.dripT -= s.dt;
					if (s.casting && st.dripT <= 0) { st.dripT = rand(.14, .3); s.drops.push({ x: st.dripX, y: -H * .1, vy: H * .4, col: st.col }); }
				}
				if (!st.done && lp >= 1) { st.done = true; burst(s, st.dripX, sy, st.col, H, 8); }
				tubeShine(g, st.tube, tw);
			});
			// drops fall into the trough and splash
			s.drops = s.drops.filter(d => {
				d.vy += H * 14 * s.dt; d.y += d.vy * s.dt;
				const floor = X > d.x ? waveY(d.x) : H * .85;
				if (d.y < floor) return true;
				s.ripples.push({ x: d.x, y: floor, age: 0 });
				for (let k = 0; k < 4; k++) s.parts.emit({ x: d.x, y: floor, vx: rand(-.8, .8) * H, vy: -rand(.5, 1.3) * H, ay: H * 9, size: H * .025, life: .35, color: light(d.col, .4) });
				return false;
			});
			for (const d of s.drops) {
				const r = Math.max(1, H * .04);
				g.fillStyle = rgba(light(d.col, .2), .95);
				g.beginPath(); g.arc(d.x, d.y, r, 0, Math.PI); g.lineTo(d.x, d.y - r * 2.6); g.closePath(); g.fill();
				glow(g, d.x, d.y, r * 3, d.col, .5);
			}
			s.parts.update(s.dt); s.parts.draw(g);
		},
	});

	// ------------------------------------------------------------------ B2: a full apparatus
	// Even spacing along a path, so liquid moves through every tube at a steady speed.
	function resample(pts, step) {
		const out = [pts[0]];
		let carry = 0;
		for (let i = 1; i < pts.length; i++) {
			const a = pts[i - 1], b = pts[i], L = Math.hypot(b[0] - a[0], b[1] - a[1]);
			let d = step - carry;
			while (d <= L) { const t = d / L; out.push([lerp(a[0], b[0], t), lerp(a[1], b[1], t)]); d += step; }
			carry = L - (d - step);
		}
		const last = pts[pts.length - 1], tail = out[out.length - 1];
		if (Math.hypot(last[0] - tail[0], last[1] - tail[1]) > step * .2) out.push(last); else out[out.length - 1] = last;
		return out;
	}
	// a polyline with its corners rounded off (glass bent at right angles)
	function elbowPath(pts, r) {
		const out = [pts[0]];
		for (let i = 1; i < pts.length - 1; i++) {
			const A = pts[i - 1], P = pts[i], B = pts[i + 1];
			const la = Math.hypot(P[0] - A[0], P[1] - A[1]), lb = Math.hypot(B[0] - P[0], B[1] - P[1]), rr = Math.min(r, la / 2, lb / 2);
			const p0 = [P[0] + (A[0] - P[0]) / la * rr, P[1] + (A[1] - P[1]) / la * rr], p1 = [P[0] + (B[0] - P[0]) / lb * rr, P[1] + (B[1] - P[1]) / lb * rr];
			out.push(p0);
			for (let k = 1; k <= 6; k++) { const t = k / 6, u = 1 - t; out.push([u * u * p0[0] + 2 * u * t * P[0] + t * t * p1[0], u * u * p0[1] + 2 * u * t * P[1] + t * t * p1[1]]); }
		}
		out.push(pts[pts.length - 1]);
		return out;
	}
	// a retort: a bulb with a long neck reaching up and to the right
	function makeRetort(x, yb, S) {
		const r = S * .3, C = [x, yb - r], a = -.75, L = S * .55, h = S * .06, dl = Math.asin(h / r);
		const d = [Math.cos(a), Math.sin(a)], n1 = [-Math.sin(a), Math.cos(a)];
		const tip = [C[0] + d[0] * (r + L), C[1] + d[1] * (r + L)];
		const Tu = [tip[0] - n1[0] * h, tip[1] - n1[1] * h], Tl = [tip[0] + n1[0] * h, tip[1] + n1[1] * h];
		const Au = [C[0] + r * Math.cos(a - dl), C[1] + r * Math.sin(a - dl)];
		const v = { type: 'retort', x, yb, S, seed: Math.random(), yt: tip[1], w: r * 1.6, liqH: 2 * r, nw: 2 * h, tip, dir: d };
		v.path = g => { g.beginPath(); g.moveTo(Tu[0], Tu[1]); g.lineTo(Au[0], Au[1]); g.arc(C[0], C[1], r, a - dl, a + dl, true); g.lineTo(Tl[0], Tl[1]); g.closePath(); };
		v.shine = g => { g.beginPath(); g.arc(C[0], C[1], r * .7, Math.PI * 1.0, Math.PI * 1.35); g.stroke(); };
		return v;
	}
	// a tall graduated cylinder on a foot; its glass starts above the foot
	function makeCylinder(x, S, h) {
		const w = S * .22, foot = S * .07, yb = -foot, yt = yb - h;
		const v = { type: 'cyl', x, yb, S, seed: Math.random(), yt, w: w / 2, liqH: h * .9, nw: w, foot, h };
		v.path = g => { g.beginPath(); g.moveTo(x - w / 2, yt); g.lineTo(x - w / 2, yb); g.lineTo(x + w / 2, yb); g.lineTo(x + w / 2, yt + S * .03); g.lineTo(x + w / 2 + S * .04, yt - S * .015); g.closePath(); };
		v.shine = g => { g.beginPath(); g.moveTo(x - w * .25, yt + h * .1); g.lineTo(x - w * .25, yb - h * .08); g.stroke(); };
		return v;
	}
	function makeBeaker(x, S) {
		const w = S * .46, h = S * .42, yb = 0, yt = -h;
		const v = { type: 'beaker', x, yb, S, seed: Math.random(), yt, w: w / 2, liqH: h * .8, nw: w };
		v.path = g => { g.beginPath(); g.moveTo(x - w / 2 - S * .03, yt); g.lineTo(x - w / 2, yt + S * .03); g.lineTo(x - w / 2, yb); g.lineTo(x + w / 2, yb); g.lineTo(x + w / 2, yt); g.closePath(); };
		v.shine = g => { g.beginPath(); g.moveTo(x - w * .32, yt + h * .2); g.lineTo(x - w * .32, yb - h * .15); g.stroke(); };
		return v;
	}
	// a separatory funnel: pear-shaped, narrowing to a stopcock at the bottom (yb)
	function makeFunnel(x, yb, S) {
		const bw = S * .44, nw = S * .12, yt = yb - S * .85;
		const v = { type: 'funnel', x, yb, S, seed: Math.random(), yt, w: bw / 2, liqH: S * .62, nw };
		v.path = g => {
			g.beginPath(); g.moveTo(x - nw / 2, yt); g.lineTo(x - nw / 2, yt + S * .07);
			g.bezierCurveTo(x - bw * .75, yt + S * .16, x - bw * .55, yt + S * .52, x - S * .025, yb);
			g.lineTo(x + S * .025, yb);
			g.bezierCurveTo(x + bw * .55, yt + S * .52, x + bw * .75, yt + S * .16, x + nw / 2, yt + S * .07);
			g.lineTo(x + nw / 2, yt); g.closePath();
		};
		v.shine = g => { g.beginPath(); g.moveTo(x - bw * .28, yt + S * .2); g.quadraticCurveTo(x - bw * .3, yt + S * .45, x - bw * .08, yb - S * .12); g.stroke(); };
		return v;
	}
	function drawRod(g, x, y0, y1, H) {
		g.strokeStyle = 'rgba(120,118,115,1)'; g.lineWidth = Math.max(1, H * .045); g.lineCap = 'round';
		g.beginPath(); g.moveTo(x, y0); g.lineTo(x, y1); g.stroke();
		g.strokeStyle = 'rgba(230,230,225,.35)'; g.lineWidth = Math.max(.5, H * .015);
		g.beginPath(); g.moveTo(x - H * .01, y0); g.lineTo(x - H * .01, y1); g.stroke();
		g.fillStyle = '#2e2a26'; g.fillRect(x - H * .12, y0 - H * .04, H * .24, H * .05);
	}
	function drawClamp(g, x0, x1, y, H) {
		g.strokeStyle = '#8c6a3c'; g.lineWidth = Math.max(1, H * .035); g.lineCap = 'round';
		g.beginPath(); g.moveTo(x0, y); g.lineTo(x1, y); g.stroke();
		g.fillStyle = '#b08a4e'; g.beginPath(); g.arc(x0, y, Math.max(1.2, H * .035), 0, 6.283); g.fill();
	}
	function drawValve(g, pts, f, tw) {
		const p = pointAt(pts, .5), q = pointAt(pts, .53), ang = Math.atan2(q[1] - p[1], q[0] - p[0]);
		const open = clamp((f - .38) / .12), rot = ang + (1 - open) * Math.PI / 2;
		g.fillStyle = '#c9a25a'; g.strokeStyle = 'rgba(40,25,5,.8)'; g.lineWidth = 1;
		g.beginPath(); g.arc(p[0], p[1], tw * .85, 0, 6.283); g.fill(); g.stroke();
		g.strokeStyle = '#e8d3a0'; g.lineWidth = Math.max(1, tw * .45); g.lineCap = 'round';
		g.beginPath(); g.moveTo(p[0] - Math.cos(rot) * tw * 1.4, p[1] - Math.sin(rot) * tw * 1.4); g.lineTo(p[0] + Math.cos(rot) * tw * 1.4, p[1] + Math.sin(rot) * tw * 1.4); g.stroke();
	}
	function drawHose(g, pts, tw) {
		g.lineCap = 'round'; g.lineJoin = 'round';
		polyTo(g, pts); g.strokeStyle = 'rgba(120,52,24,.95)'; g.lineWidth = tw * 1.3; g.stroke();
		g.strokeStyle = 'rgba(200,110,60,.35)'; g.lineWidth = tw * .9; g.stroke();
	}
	function hoseShine(g, pts, tw) {
		g.save(); g.translate(0, -tw * .3); polyTo(g, pts);
		g.strokeStyle = 'rgba(255,200,160,.35)'; g.lineWidth = Math.max(.6, tw * .18); g.lineCap = 'round'; g.stroke(); g.restore();
		for (const e of [pts[0], pts[pts.length - 1]]) { g.fillStyle = '#c9a25a'; g.beginPath(); g.arc(e[0], e[1], tw * .75, 0, 6.283); g.fill(); }
	}
	const KINDS = ['retort', 'jacket', 'cyl', 'rack', 'funnel', 'coil', 'erlen', 'boil'];

	// ---- the bench trough's potion: a shallow-water height field (one column per few pixels). The
	// potion pours in at the flow's head, spreads sideways under its own weight with a rounded front,
	// sloshes back off the glass at either end and settles; the volume poured follows the cast, so the
	// level rises with it and brims at the top edge at the end.
	function makePool(W, H) {
		const N = Math.max(40, Math.ceil(W / 3));
		return { N, dx: W / N, h: new Float32Array(N), q: new Float32Array(N + 1), hs: new Float32Array(N), drops: [], rings: [], bubbles: [], dripT: 0, bubT: 0 };
	}
	function stepPool(P, s, dt) {
		const { N, dx, h, q } = P, H = s.H, G = 120 * Math.max(H, 40), damp = 1.2, STEP = 1 / 480;   // short bars still spread as fast
		const tmp = P.tmp || (P.tmp = new Float32Array(N));
		for (let t = dt; t > 1e-6; t -= STEP) {
			const d = Math.min(t, STEP);
			for (let i = 1; i < N; i++) {
				// flux follows depth x slope (shallow water), so a thin film creeps and the front stays rounded
				const depth = (h[i - 1] + h[i]) / 2;
				q[i] = (q[i] + d * G * depth * (h[i - 1] - h[i]) / dx) * (1 - damp * d);
			}
			q[0] = q[N] = 0;   // the glass at either end
			// a little viscosity: neighbouring fluxes pull together, so no saw-tooth builds up
			for (let i = 1; i < N; i++) tmp[i] = q[i] + .25 * (q[i - 1] - 2 * q[i] + q[i + 1]);
			for (let i = 1; i < N; i++) q[i] = tmp[i];
			for (let i = 0; i < N; i++) {   // never drain a column below empty
				const out = (Math.max(0, q[i + 1]) + Math.max(0, -q[i])) * d / dx;
				if (out > h[i] && out > 0) { const k = h[i] / out; if (q[i + 1] > 0) q[i + 1] *= k; if (q[i] < 0) q[i] *= k; }
			}
			for (let i = 0; i < N; i++) h[i] = Math.max(0, h[i] + d * (q[i] - q[i + 1]) / dx);
		}
		// what is drawn: smoothed, with a meniscus climbing the glass at each end
		const hs = P.hs;
		for (let i = 0; i < N; i++) tmp[i] = (h[Math.max(0, i - 1)] + 2 * h[i] + h[Math.min(N - 1, i + 1)]) / 4;
		for (let i = 0; i < N; i++) hs[i] = (tmp[Math.max(0, i - 1)] + 2 * tmp[i] + tmp[Math.min(N - 1, i + 1)]) / 4;
		for (let i = 0; i < N; i++) {
			if (hs[i] < H * .04) continue;
			const x = (i + .5) * dx;
			hs[i] += H * .06 * (Math.exp(-x / (H * .08)) + Math.exp(-(s.W - x) / (H * .08)));
		}
	}
	// add `amount` (area) spread as a bell of width sig around x; a negative bell minus a wider positive one moves liquid outward
	function bell(P, x, amount, sig) {
		const { N, dx, h } = P;
		let sum = 0;
		const w = new Float32Array(N);
		for (let i = 0; i < N; i++) { w[i] = Math.exp(-((((i + .5) * dx - x) / sig) ** 2)); sum += w[i]; }
		if (sum > 0) for (let i = 0; i < N; i++) h[i] = Math.max(0, h[i] + amount * w[i] / sum / dx);
	}
	const pour = (P, xs, amount, H) => bell(P, xs, amount, H * .45);
	function splash(P, x, H) {   // a drop pushes the surface down where it lands and heaps it round about; that spreads as rings
		const i = clamp(Math.floor(x / P.dx), 0, P.N - 1), k = Math.min(P.h[i] * .3, H * .03) * H * .3;
		bell(P, x, -k, H * .1); bell(P, x, k, H * .3);
	}
	const surfY = (P, s, x) => s.H - P.hs[clamp(Math.floor(x / P.dx), 0, P.N - 1)];

	CONCEPTS.push({
		group: 'Alchemy', id: 'alch-b2', letter: 'B2', name: "Alchemist's apparatus",
		desc: 'A whole bench of glassware: burners, a retort, condensers, a coil, a dripping funnel and a vial rack, joined by glass, hoses and valves; the potion works its way through and pours into the bar, spreading, sloshing and rising until it brims.',
		spell: 'Flask of the Titans', padTop: 2.15, padX: .9, padBottom: .5, flash: [235, 250, 255],
		init(s) {
			const H = s.H, W = s.W, m = H * .7;
			s.pool = makePool(W, H);
			const n = clamp(Math.floor((W - 2 * m) / (H * 1.05)) + 1, 6, 10), Z = (W - 2 * m) / (n - 1), S = Math.min(H, Z * .92);
			s.pal = pick(PALETTES); s.Z = Z; s.S = S; s.tw = Math.max(1.8, S * .075); s.legH = S * .34; s.surf = H * .36;
			const pool = KINDS.slice().sort(() => Math.random() - .5);
			const kinds = ['boil'];
			for (let i = 1; i < n; i++) kinds.push(pool[(i - 1) % pool.length]);
			s.st = kinds.map((kind, i) => {
				const x = m + Z * i + (i && i < n - 1 ? rand(-.06, .06) * Z : 0), st = { kind, x, col: palAt(s.pal, i / (n - 1)), seed: rand(0, 99), lit: i === 0 };
				if (kind === 'boil') {
					st.v = makeVessel('round', x, -s.legH + S * .3 * .35, S * rand(.9, 1)); st.burner = true;
					st.in = st.out = [x, st.v.yt];
				} else if (kind === 'retort') {
					st.v = makeRetort(x - S * .12, -s.legH + S * .3 * .35, S * .95); st.burner = true; st.fx = x - S * .12;
					st.in = [st.v.x - S * .02, st.v.yb - st.v.liqH * .95]; st.out = st.v.tip;
				} else if (kind === 'cyl') {
					st.v = makeCylinder(x, S, S * rand(1.05, 1.25)); st.in = st.out = [x, st.v.yt];
				} else if (kind === 'erlen') {
					st.v = makeVessel('erlen', x, 0, S * rand(.95, 1.1)); st.in = st.out = [x, st.v.yt];
				} else if (kind === 'funnel') {
					st.b = makeBeaker(x, S * .95);
					st.v = makeFunnel(x, st.b.yt - S * .3, S * .95);
					st.in = [x, st.v.yt]; st.out = [x + st.b.w * .7, st.b.yt]; st.drips = []; st.dripT = 0;
				} else if (kind === 'jacket') {
					st.y0 = -H * .22; st.y1 = st.y0 - S * 1.05; st.jw = S * .26;
					st.in = [x, st.y1 - S * .12]; st.out = [x, st.y0 + S * .1];
					st.inner = resample([st.in, st.out], 2); st.bub = Array.from({ length: 5 }, () => rand(0, 1));
				} else if (kind === 'coil') {
					const yT = -S * 1.15, yB = -H * .2, k = 3.5, R = S * .2, pts = [];
					for (let u = 0; u <= 6.283 * k; u += .15) pts.push([x + R * Math.sin(u), yT + (yB - yT) * u / (6.283 * k) + R * .32 * Math.cos(u)]);
					st.coil = resample([[x, yT - S * .12], ...pts, [pts[pts.length - 1][0], yB + S * .08]], 1.5);
					st.in = st.coil[0]; st.out = st.coil[st.coil.length - 1];
				} else {   // rack of three vials joined by little arches
					st.vials = [-1, 0, 1].map(k => makeVessel('vial', x + k * S * .3, 0, S * rand(.55, .72)));
					st.minis = [0, 1].map(k => { const a = st.vials[k], b = st.vials[k + 1], top = Math.min(a.yt, b.yt) - S * .12; return resample(bez([a.x, a.yt], [a.x, top], [b.x, top], [b.x, b.yt]), 1.5); });
					st.in = [st.vials[0].x, st.vials[0].yt]; st.out = [st.vials[2].x, st.vials[2].yt];
				}
				return st;
			});
			// connections between stations: glass arches, bent glass, rubber hoses; some with a valve
			s.links = [];
			for (let i = 0; i < n - 1; i++) {
				const A = s.st[i].out, B = s.st[i + 1].in, top = Math.min(A[1], B[1]) - H * rand(.14, .28);
				let type = A[1] > B[1] + S * .3 ? pick(['hose', 'elbow']) : pick(['glass', 'glass', 'elbow', 'hose']), raw;
				if (s.st[i].kind === 'retort') { type = 'glass'; const d = s.st[i].v.dir; raw = bez(A, [A[0] + d[0] * S * .35, A[1] + d[1] * S * .35], [B[0], top], B); }
				else if (type === 'glass') raw = bez(A, [A[0] + Z * .1, top], [B[0] - Z * .1, top], B);
				else if (type === 'elbow') raw = elbowPath([A, [A[0], top], [B[0], top], B], S * .15);
				else raw = bez(A, [A[0] + Z * .25, A[1] + (A[1] > -S * .5 ? -S * .1 : S * .45)], [B[0] - Z * .3, top - S * .1], B);
				s.links.push({ type, pts: resample(raw, 1.5), valve: type !== 'hose' && Math.random() < .45 });
			}
		},
		draw(g, s) {
			// the bench trough: the finished potion pours in at the flow's head and fills it like a liquid;
			// by the end of the cast it brims at the bar's top edge
			const W = s.W, H = s.H, X = s.fill, P = s.pool, N = P.N, dx = P.dx;
			const xs = clamp(X - H * .12, H * .15, W - H * .15);   // where the potion falls in
			let vol = 0;
			for (let i = 0; i < N; i++) vol += P.h[i] * dx;
			const target = W * H * 1.04 * s.p * s.p;   // spread over the poured length, the level rises with the cast
			if (target > vol) pour(P, xs, Math.min(target - vol, W * H * 2.5 * s.dt + 1), H);
			stepPool(P, s, s.dt);
			// drops falling into it from above, each leaving rings
			P.dripT -= s.dt;
			if (s.casting && X > H * .2 && P.dripT <= 0) { P.dripT = rand(.06, .14); P.drops.push({ x: xs + rand(-.08, .08) * H, y: 0, vy: H * rand(.4, 1) }); }
			P.drops = P.drops.filter(dp => {
				dp.vy += H * 14 * s.dt; dp.y += dp.vy * s.dt;
				const sy = surfY(P, s, dp.x);
				if (dp.y < sy) return true;
				splash(P, dp.x, H); P.rings.push({ x: dp.x, age: 0 });
				for (let k = 0; k < 3; k++) s.parts.emit({ x: dp.x, y: sy, vx: rand(-.6, .6) * H, vy: -rand(.4, 1) * H, ay: H * 10, size: Math.max(.6, H * .02), life: .35, color: light(palAt(s.pal, dp.x / W), .5), add: true });
				return false;
			});
			P.rings = P.rings.filter(r => (r.age += s.dt) < .6);
			// bubbles rise from the bottom and pop at the surface
			P.bubT -= s.dt;
			if (P.bubT <= 0) {
				P.bubT = rand(.03, .09) * 300 / W;
				const i = Math.floor(rand(0, N));
				if (P.hs[i] > H * .25) P.bubbles.push({ x: (i + .5) * dx, y: H - rand(0, .1) * H, r: H * rand(.015, .035), ph: rand(0, 6.283) });
			}
			P.bubbles = P.bubbles.filter(b => {
				b.y -= H * .7 * s.dt; b.x += Math.sin(s.t * 6 + b.ph) * H * .08 * s.dt;
				if (b.y > surfY(P, s, b.x) + b.r) return true;
				s.parts.emit({ x: b.x, y: surfY(P, s, b.x), vx: 0, vy: -H * .2, size: b.r * 1.5, grow: H * .1, life: .25, kind: 'glow', color: [255, 255, 255], alpha: .5 });
				return false;
			});

			g.save(); barClip(g, s);
			const bg = g.createLinearGradient(0, 0, 0, H);
			bg.addColorStop(0, 'rgba(32,40,54,.95)'); bg.addColorStop(1, 'rgba(8,10,16,.95)');
			g.fillStyle = bg; g.fillRect(0, 0, W, H);
			// the surface: the simulated level, plus small travelling ripples where it is neither thin nor brimming
			const top = [];
			let minY = H;
			for (let i = 0; i < N; i++) {
				const x = (i + .5) * dx, d = P.hs[i];
				const calm = clamp(d / (H * .12)) * clamp((H - d) / (H * .15));
				const y = H - d - calm * (Math.sin(x / (H * .5) - s.t * 2.6) * H * .02 + Math.sin(x / (H * .21) + s.t * 4.3) * H * .01 + Math.sin(x / (H * .9) + s.t * 1.3) * H * .015);
				top.push([x, y]); if (d > H * .02) minY = Math.min(minY, y);
			}
			const path = () => { g.beginPath(); g.moveTo(0, H + 1); g.lineTo(0, top[0][1]); for (const [x, y] of top) g.lineTo(x, y); g.lineTo(W, top[N - 1][1]); g.lineTo(W, H + 1); g.closePath(); };
			if (vol > 1) {
				const lg = g.createLinearGradient(0, 0, W, 0);
				for (let i = 0; i < 4; i++) lg.addColorStop(i / 3, rgba(s.pal[i], .88));
				path(); g.fillStyle = lg; g.fill();
				// deeper is darker; just under the surface the light catches it in a band
				const dg = g.createLinearGradient(0, minY, 0, H);
				dg.addColorStop(0, 'rgba(255,255,255,.14)'); dg.addColorStop(.25, 'rgba(0,0,0,0)'); dg.addColorStop(1, 'rgba(0,0,0,.5)');
				path(); g.fillStyle = dg; g.fill();
				path(); g.fillStyle = 'rgba(0,0,0,.12)'; g.fill();   // a touch deeper, so the text stays readable over a full bar
				g.save(); path(); g.clip();
				g.globalCompositeOperation = 'lighter';
				g.strokeStyle = 'rgba(255,255,255,.13)'; g.lineWidth = Math.max(1, H * .07);
				g.beginPath();
				for (let i = 0; i < N; i++) { const [x, y] = top[i], yy = y + H * .1 + Math.sin(x / (H * .35) + s.t * 2) * H * .02; i ? g.lineTo(x, yy) : g.moveTo(x, yy); }
				g.stroke();
				// bubbles
				for (const b of P.bubbles) {
					g.strokeStyle = 'rgba(255,255,255,.5)'; g.lineWidth = Math.max(.5, b.r * .4);
					g.beginPath(); g.arc(b.x, b.y, b.r, 0, 6.283); g.stroke();
				}
				g.globalCompositeOperation = 'source-over';
				g.restore();
				// the surface line, only where there is liquid
				g.strokeStyle = 'rgba(255,255,255,.5)'; g.lineWidth = Math.max(.7, H * .03);
				g.beginPath();
				let on = false;
				for (let i = 0; i < N; i++) {
					const [x, y] = top[i];
					if (P.hs[i] > H * .03) { on ? g.lineTo(x, y) : g.moveTo(x, y); on = true; } else on = false;
				}
				g.stroke();
				// rings where drops landed
				for (const r of P.rings) {
					const k = r.age / .6, rx = H * (.08 + .5 * k);
					g.strokeStyle = `rgba(255,255,255,${.45 * (1 - k)})`; g.lineWidth = 1;
					g.beginPath(); g.ellipse(r.x, surfY(P, s, r.x) + 1, rx, rx * .22, 0, 0, 6.283); g.stroke();
				}
			}
			// the falling potion: a thin stream with drops
			if (s.casting && X > H * .2) {
				const sy = surfY(P, s, xs), c = palAt(s.pal, xs / W);
				if (sy > H * .05) {
					g.strokeStyle = rgba(light(c, .3), .45); g.lineWidth = Math.max(.8, H * .025);
					g.beginPath(); g.moveTo(xs, 0); g.lineTo(xs + Math.sin(s.t * 20) * H * .01, sy); g.stroke();
				}
				for (const dp of P.drops) { g.fillStyle = rgba(light(palAt(s.pal, dp.x / W), .35), .95); g.beginPath(); g.ellipse(dp.x, dp.y, Math.max(.7, H * .025), Math.max(1, H * .04), 0, 0, 6.283); g.fill(); }
				glow(g, xs, sy, H * .5, c, .35);
			}
			g.fillStyle = 'rgba(255,255,255,.12)'; g.fillRect(0, H * .07, W, Math.max(1, H * .04));
			g.restore();
		},
		over(g, s) {
			const H = s.H, X = s.fill, S = s.S, Z = s.Z, tw = s.tw, st = s.st, n = st.length, d = Z * .38;
			// how far the potion has got at each station (0..1 while it fills there)
			const fillAt = i => i === 0 ? 1 : clamp((X - st[i].x) / d);
			const linkF = i => clamp((X - st[i].x - d) / (st[i + 1].x - st[i].x - d));
			st.forEach((p, i) => {
				const f = fillAt(i), on = i === 0 || X > p.x;
				if (on && !p.lit) { p.lit = true; burst(s, p.in[0], p.in[1], p.col, H, 7); }
				const heat = i === 0 ? 1 : clamp((X - p.x) / (H * .35));
				if (p.burner) {
					const bx = p.fx || p.x, r = S * .3;
					g.fillStyle = '#3d3024'; g.strokeStyle = '#a07a45'; g.lineWidth = 1;
					g.beginPath(); g.ellipse(bx, -H * .03, r * .5, H * .05, 0, 0, 6.283); g.fill(); g.stroke();
					g.fillStyle = '#5a4a3a'; g.fillRect(bx - r * .12, -s.legH * .35, r * .24, s.legH * .33);
					drawFlame(g, bx, -s.legH * .36, s.legH * .62 * heat, r * .5, s.t, p.seed);
					glow(g, bx, -s.legH, r * 1.3, [255, 140, 50], .35 * heat);
					g.strokeStyle = 'rgba(110,105,100,1)'; g.lineWidth = Math.max(1, H * .045); g.lineCap = 'round';
					g.beginPath(); g.moveTo(bx - r, 0); g.lineTo(bx - r * .75, -s.legH); g.moveTo(bx + r, 0); g.lineTo(bx + r * .75, -s.legH); g.stroke();
				}
				const boil = p.burner ? heat : .25 * heat;
				if (p.kind === 'boil' || p.kind === 'retort') {
					const level = i === 0 ? .8 - .4 * s.p : .72 * f;
					drawVessel(g, p.v, level, p.col, s.t, boil, p.kind === 'boil');
					g.strokeStyle = 'rgba(160,155,150,1)'; g.lineWidth = Math.max(1, H * .045);
					g.beginPath(); g.moveTo((p.fx || p.x) - S * .26, -s.legH); g.lineTo((p.fx || p.x) + S * .26, -s.legH); g.stroke();
					if (s.casting && heat > .5 && Math.random() < s.dt * 3) rising(s, p.in[0], p.in[1] - H * .05, p.col, H, .45);
				} else if (p.kind === 'cyl') {
					g.fillStyle = '#4a4f57'; g.beginPath(); g.ellipse(p.x, -p.v.foot / 2, S * .2, p.v.foot / 2 + .5, 0, 0, 6.283); g.fill();
					drawVessel(g, p.v, .85 * f, p.col, s.t, boil, false);
					g.strokeStyle = 'rgba(230,245,255,.55)'; g.lineWidth = 1;
					for (let k = 1; k < 8; k++) { const y = p.v.yb - p.v.h * k / 8, L = k % 2 ? S * .04 : S * .07; g.beginPath(); g.moveTo(p.x + p.v.w, y); g.lineTo(p.x + p.v.w - L, y); g.stroke(); }
				} else if (p.kind === 'erlen') {
					drawVessel(g, p.v, .7 * f, p.col, s.t, .3 * heat);
				} else if (p.kind === 'funnel') {
					const v = p.v, b = p.b, rodX = p.x - S * .42;
					drawRod(g, rodX, 0, v.yt - S * .1, H);
					drawClamp(g, rodX, p.x - v.w * .55, v.yt + S * .2, H);
					g.strokeStyle = 'rgba(150,150,150,.9)'; g.lineWidth = Math.max(1, H * .03);
					g.beginPath(); g.ellipse(p.x, v.yt + S * .2, v.w * .95, S * .04, 0, 0, 6.283); g.stroke();
					// the funnel fills first, then drains drop by drop into the beaker
					const ff = clamp(f * 1.6), drain = clamp(f * 1.6 - .6) * .6;
					drawVessel(g, v, Math.max(0, .85 * ff - drain), p.col, s.t, .2);
					const stemTop = v.yb, stemBot = b.yt + S * .08;
					g.strokeStyle = 'rgba(205,235,255,.75)'; g.lineWidth = Math.max(1, S * .045);
					g.beginPath(); g.moveTo(p.x, stemTop); g.lineTo(p.x, stemBot); g.stroke();
					const open = clamp((f - .35) / .1), cy = stemTop + S * .07, rot = (1 - open) * Math.PI / 2;
					g.fillStyle = '#e9e4d8'; g.fillRect(p.x - S * .05, cy - S * .025, S * .1, S * .05);
					g.strokeStyle = '#3a6fb0'; g.lineWidth = Math.max(1, S * .035); g.lineCap = 'round';
					g.beginPath(); g.moveTo(p.x - Math.cos(rot) * S * .09, cy - Math.sin(rot) * S * .09); g.lineTo(p.x + Math.cos(rot) * S * .09, cy + Math.sin(rot) * S * .09); g.stroke();
					p.dripT -= s.dt;
					if (s.casting && open > .5 && f < 1 && p.dripT <= 0) { p.dripT = rand(.12, .22); p.drips.push({ y: stemBot, vy: H * .3 }); }
					const surf = b.yb - b.liqH * .82 * clamp((f - .35) / .65);
					p.drips = p.drips.filter(dp => { dp.vy += H * 12 * s.dt; dp.y += dp.vy * s.dt; if (dp.y < surf) return true; s.parts.emit({ x: p.x, y: surf, vx: rand(-.5, .5) * H, vy: -rand(.3, .8) * H, ay: H * 8, size: H * .02, life: .3, color: light(p.col, .4) }); return false; });
					for (const dp of p.drips) { g.fillStyle = rgba(light(p.col, .2), .95); g.beginPath(); g.arc(p.x, dp.y, Math.max(.8, S * .025), 0, 6.283); g.fill(); }
					drawVessel(g, b, .82 * clamp((f - .35) / .65), p.col, s.t, .15, false);
				} else if (p.kind === 'jacket') {
					const rodX = p.x - S * .38, jw = p.jw;
					drawRod(g, rodX, 0, p.y1 - S * .05, H);
					drawClamp(g, rodX, p.x - jw / 2, (p.y0 + p.y1) / 2, H);
					// coolant water in the jacket, with small bubbles rising
					roundRectPath(g, p.x - jw / 2, p.y1, jw, p.y0 - p.y1, jw * .35);
					g.fillStyle = 'rgba(90,170,255,.22)'; g.fill();
					g.strokeStyle = 'rgba(215,240,255,.8)'; g.lineWidth = Math.max(1, S * .035); g.stroke();
					g.fillStyle = 'rgba(220,240,255,.55)';
					p.bub.forEach((b0, k) => { const ph = (b0 + s.t * .35) % 1; g.beginPath(); g.arc(p.x + (k % 2 ? 1 : -1) * jw * .28, p.y0 - ph * (p.y0 - p.y1), Math.max(.5, S * .018), 0, 6.283); g.fill(); });
					// rubber coolant ports on the sides
					g.strokeStyle = 'rgba(120,52,24,.95)'; g.lineWidth = tw;
					g.beginPath(); g.moveTo(p.x + jw / 2, p.y1 + S * .12); g.quadraticCurveTo(p.x + jw, p.y1 + S * .1, p.x + jw * 1.05, p.y1 + S * .3); g.stroke();
					g.beginPath(); g.moveTo(p.x - jw / 2, p.y0 - S * .12); g.quadraticCurveTo(p.x - jw, p.y0 - S * .1, p.x - jw * .95, p.y0 + S * .05); g.stroke();
					tubeGlass(g, p.inner, tw * .9);
					if (f > 0) { const h = tubeLiquid(g, p.inner, 0, f, tw * .9, p.col, light(p.col, .2)); if (f < 1) glow(g, h[0], h[1], tw * 2, p.col, .8); }
					tubeShine(g, p.inner, tw * .9);
				} else if (p.kind === 'coil') {
					const rodX = p.x - S * .36;
					drawRod(g, rodX, 0, p.in[1], H);
					drawClamp(g, rodX, p.x - S * .2, p.in[1] + S * .2, H);
					tubeGlass(g, p.coil, tw);
					if (f > 0) {
						const h = tubeLiquid(g, p.coil, 0, f, tw, p.col, light(p.col, .3));
						if (f < 1) { glow(g, h[0], h[1], tw * 2.4, p.col, .9); glow(g, h[0], h[1], tw * .6, [255, 255, 255], .8); }
					}
					tubeShine(g, p.coil, tw);
				} else {   // vial rack
					p.vials.forEach((v, k) => drawVessel(g, v, .8 * clamp(f * 3 - k), p.col, s.t, .2));
					p.minis.forEach((pts, k) => {
						tubeGlass(g, pts, tw * .8);
						const mf = clamp((f * 3 - k - .8) / .25);
						if (mf > 0) tubeLiquid(g, pts, 0, mf, tw * .8, p.col, p.col);
						tubeShine(g, pts, tw * .8);
					});
					const rw = S * 1.0, ry = -S * .24;
					g.fillStyle = '#6b4529'; g.fillRect(p.x - rw / 2, ry, rw, S * .08);
					g.fillStyle = 'rgba(255,210,160,.25)'; g.fillRect(p.x - rw / 2, ry, rw, S * .025);
					g.fillStyle = '#4a2f18'; g.fillRect(p.x - rw / 2, ry, S * .05, -ry); g.fillRect(p.x + rw / 2 - S * .05, ry, S * .05, -ry);
				}
			});
			// the links, and the potion travelling through them
			s.links.forEach((L, i) => {
				const a = st[i], b = st[i + 1], f = linkF(i);
				if (L.type === 'hose') drawHose(g, L.pts, tw); else tubeGlass(g, L.pts, tw);
				if (f > 0) {
					g.globalAlpha = L.type === 'hose' ? .6 : 1;
					const h = tubeLiquid(g, L.pts, 0, f, tw, a.col, b.col);
					g.globalAlpha = 1;
					if (f < 1) { const hc = mix(a.col, b.col, f); glow(g, h[0], h[1], tw * 2.4, hc, .9); glow(g, h[0], h[1], tw * .6, [255, 255, 255], .8); }
				}
				if (L.type === 'hose') hoseShine(g, L.pts, tw); else tubeShine(g, L.pts, tw);
				if (L.valve) drawValve(g, L.pts, f, tw);
			});
			s.parts.update(s.dt); s.parts.draw(g);
		},
	});
})();
