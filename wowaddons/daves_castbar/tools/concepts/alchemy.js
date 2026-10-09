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
})();
