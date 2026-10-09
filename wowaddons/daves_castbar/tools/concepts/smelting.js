// Smelting concepts: a forge ladle pours molten steel into the bar.
(() => {
	const PI2 = Math.PI * 2;

	// temperature (0 cold .. 1 fresh pour) -> colour; the hottest stop stays short of white so text reads
	const RAMP = [[0, [52, 50, 56]], [.16, [84, 38, 26]], [.34, [165, 42, 14]], [.52, [228, 92, 18]], [.72, [255, 160, 44]], [.88, [255, 208, 104]], [1, [255, 228, 150]]];
	function heat(t) {
		t = clamp(t);
		for (let i = 1; i < RAMP.length; i++) if (t <= RAMP[i][0]) {
			const [a, ca] = RAMP[i - 1], [b, cb] = RAMP[i];
			return mix(ca, cb, (t - a) / (b - a));
		}
		return RAMP[RAMP.length - 1][1];
	}
	const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };

	function plateShape(r) {
		const n = 5 + Math.floor(rand(0, 3)), pts = [];
		for (let i = 0; i < n; i++) { const a = (i + rand(-.3, .3)) / n * PI2, d = r * rand(.7, 1.1); pts.push([Math.cos(a) * d, Math.sin(a) * d * .75]); }
		return pts;
	}
	function polyPath(g, x, y, pts) {
		g.beginPath(); pts.forEach(([px, py], i) => i ? g.lineTo(x + px, y + py) : g.moveTo(x + px, y + py)); g.closePath();
	}
	function glow(g, x, y, r, c, a) {
		const gr = g.createRadialGradient(x, y, 0, x, y, r);
		gr.addColorStop(0, rgba(c, a)); gr.addColorStop(1, rgba(c, 0));
		g.globalCompositeOperation = 'lighter'; g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
		g.globalCompositeOperation = 'source-over';
	}

	// A forge ladle. (lx, ly) is the spout lip; dir +1 puts the bowl to the right of the lip (pouring left),
	// -1 to the left (pouring right). tilt lowers the lip; full (0..1) dims the metal inside as it empties.
	function drawLadle(g, lx, ly, r, tilt, dir, full = 1) {
		g.save(); g.translate(lx, ly); g.scale(dir, 1); g.rotate(-tilt);
		const lw = Math.max(1, r * .07);
		// handle, behind the bowl: iron rod with a wooden grip
		const hx0 = 1.8 * r, hy0 = .2 * r, ha = -.5, L = 2.5 * r, hx1 = hx0 + Math.cos(ha) * L, hy1 = hy0 + Math.sin(ha) * L;
		const gx = hx0 + Math.cos(ha) * L * .62, gy = hy0 + Math.sin(ha) * L * .62;
		g.lineCap = 'round';
		g.strokeStyle = '#0c0c0e'; g.lineWidth = r * .2; g.beginPath(); g.moveTo(hx0, hy0); g.lineTo(gx, gy); g.stroke();
		g.strokeStyle = '#4b4e57'; g.lineWidth = r * .11; g.stroke();
		g.strokeStyle = 'rgba(190,195,205,.55)'; g.lineWidth = r * .035; g.beginPath(); g.moveTo(hx0, hy0 - r * .03); g.lineTo(gx, gy - r * .03); g.stroke();
		g.strokeStyle = '#140c07'; g.lineWidth = r * .3; g.beginPath(); g.moveTo(gx, gy); g.lineTo(hx1, hy1); g.stroke();
		g.strokeStyle = '#6b4427'; g.lineWidth = r * .21; g.stroke();
		g.strokeStyle = 'rgba(200,150,100,.4)'; g.lineWidth = r * .05; g.beginPath(); g.moveTo(gx, gy - r * .05); g.lineTo(hx1, hy1 - r * .05); g.stroke();
		// bowl
		const bowl = () => {
			g.beginPath(); g.moveTo(-.24 * r, -.06 * r); g.lineTo(-.04 * r, .2 * r);
			g.bezierCurveTo(-.02 * r, .95 * r, .42 * r, 1.32 * r, r, 1.32 * r);
			g.bezierCurveTo(1.58 * r, 1.32 * r, 2.02 * r, .95 * r, 2 * r, 0);
			g.lineTo(0, 0); g.closePath();
		};
		const gb = g.createLinearGradient(0, -.1 * r, r * .4, 1.35 * r);
		gb.addColorStop(0, '#60636d'); gb.addColorStop(.45, '#30323a'); gb.addColorStop(1, '#141418');
		bowl(); g.fillStyle = gb; g.fill();
		g.save(); bowl(); g.clip();
		glow(g, r, 1.2 * r, r * 1.1, [255, 80, 20], .32);                    // the iron glows dull red from the heat inside
		g.strokeStyle = 'rgba(210,215,225,.35)'; g.lineWidth = r * .07;          // a soft highlight down one flank
		g.beginPath(); g.moveTo(1.75 * r, .15 * r); g.bezierCurveTo(1.8 * r, .7 * r, 1.5 * r, 1.05 * r, 1.15 * r, 1.18 * r); g.stroke();
		g.restore();
		bowl(); g.strokeStyle = '#08080a'; g.lineWidth = lw; g.stroke();
		// the metal inside, seen over the rim
		const hot = heat(.55 + .45 * full), gi = g.createRadialGradient(r * .7, 0, 0, r, 0, r);
		gi.addColorStop(0, rgba(heat(.8 + .2 * full))); gi.addColorStop(1, rgba(mix(hot, [120, 30, 10], .3)));
		g.beginPath(); g.ellipse(r, -.02 * r, .92 * r, .2 * r, 0, 0, PI2); g.fillStyle = gi; g.fill();
		// rim, with the light along its top edge
		g.beginPath(); g.ellipse(r, -.02 * r, .95 * r, .22 * r, 0, 0, PI2);
		g.strokeStyle = '#0a0a0c'; g.lineWidth = r * .17; g.stroke();
		g.strokeStyle = '#646873'; g.lineWidth = r * .1; g.stroke();
		g.beginPath(); g.ellipse(r, -.04 * r, .95 * r, .22 * r, 0, Math.PI * 1.08, Math.PI * 1.92);
		g.strokeStyle = 'rgba(215,220,230,.7)'; g.lineWidth = r * .035; g.stroke();
		// glowing spout lip
		g.strokeStyle = rgba(heat(.9), .9); g.lineWidth = r * .07;
		g.beginPath(); g.moveTo(.08 * r, -.02 * r); g.lineTo(-.2 * r, -.04 * r); g.stroke();
		glow(g, -.1 * r, 0, r * .55, [255, 150, 40], .45);
		g.restore();
	}

	// where the spout tip of drawLadle ends up
	const tip = (lx, ly, r, tilt, dir) => { const c = Math.cos(tilt), sn = Math.sin(tilt), x = -.22 * r, y = -.05 * r; return [lx + dir * (x * c + y * sn), ly - x * sn + y * c]; };

	// a falling stream of molten metal from the lip (x0,y0) to (x1,y1); dirX is the way the lip faces
	function drawStream(g, x0, y0, x1, y1, w, t, dirX, ph) {
		if (w <= .2) return;
		const pts = [], n = 14;
		for (let i = 0; i <= n; i++) {
			const u = i / n, e = 1 - (1 - u) * (1 - u);
			const x = lerp(x0, x1, e) + dirX * w * .45 * Math.sin(u * Math.PI) * (1 - u) + Math.sin(t * 23 + u * 9 + ph) * w * .12 * u;
			pts.push([x, lerp(y0, y1, u)]);
		}
		const path = () => { g.beginPath(); pts.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y)); };
		g.lineCap = 'round'; g.lineJoin = 'round';
		g.globalCompositeOperation = 'lighter';
		path(); g.strokeStyle = 'rgba(255,110,20,.22)'; g.lineWidth = w * 3.2; g.stroke();
		g.globalCompositeOperation = 'source-over';
		path(); g.strokeStyle = rgba([235, 105, 22]); g.lineWidth = w; g.stroke();
		path(); g.strokeStyle = rgba(heat(.85)); g.lineWidth = w * .55; g.stroke();
		g.globalCompositeOperation = 'lighter';
		path(); g.strokeStyle = 'rgba(255,240,190,.55)'; g.lineWidth = w * .2; g.stroke();
		g.globalCompositeOperation = 'source-over';
	}

	// The molten body from x0 to x1 inside the bar, its top at surf(x) and a rounded front ending at x1.
	// temp(x) colours it; plates [{x, y, pts, a}] are crust floating on it.
	function drawMolten(g, s, x0, x1, base, surf, temp, plates, frontR) {
		const H = s.H;
		if (x1 - x0 < 1) return;
		const fr = Math.min(frontR, x1 - x0), step = Math.max(2, H / 12), pts = [];
		for (let x = x0; ; x += step) {
			const xx = Math.min(x, x1);
			let y = surf(xx);
			if (xx > x1 - fr) { const u = (xx - (x1 - fr)) / fr; y = lerp(y, H + 1, 1 - Math.sqrt(Math.max(0, 1 - u * u))); }
			pts.push([xx, y]);
			if (xx >= x1) break;
		}
		const body = () => { g.beginPath(); g.moveTo(x0, H + 1); pts.forEach(([x, y]) => g.lineTo(x, y)); g.lineTo(x1, H + 1); g.closePath(); };
		const grad = g.createLinearGradient(x0, 0, x1, 0), n = 24;
		for (let i = 0; i <= n; i++) grad.addColorStop(i / n, rgba(heat(temp(lerp(x0, x1, i / n)))));
		body(); g.fillStyle = grad; g.fill();
		g.save(); body(); g.clip();
		// depth: a lit skin at the top, darker underneath
		const gv = g.createLinearGradient(0, base, 0, H);
		gv.addColorStop(0, 'rgba(255,235,180,.22)'); gv.addColorStop(.25, 'rgba(0,0,0,0)'); gv.addColorStop(1, 'rgba(10,0,0,.42)');
		g.fillStyle = gv; g.fillRect(x0, 0, x1 - x0, H + 2);
		// crust plates: darker than the metal around them, so the seams between them glow
		for (const p of plates) {
			if (p.x < x0 - H || p.x > x1 + H) continue;
			const tp = temp(p.x), a = (p.a == null ? 1 : p.a) * smooth(.78, .38, tp);
			if (a <= .01) continue;
			polyPath(g, p.x, p.y, p.pts);
			g.fillStyle = rgba(mix(heat(tp * .5), [40, 38, 42], .35), a); g.fill();
			g.strokeStyle = rgba(heat(Math.min(1, tp + .3)), a * smooth(.05, .3, tp) * .9); g.lineWidth = Math.max(.8, H * .045); g.stroke();
			g.fillStyle = `rgba(200,205,215,${a * smooth(.3, 0, tp) * .18})`; polyPath(g, p.x - H * .02, p.y - H * .03, p.pts.map(([a1, b1]) => [a1 * .6, b1 * .5])); g.fill();
		}
		g.restore();
		// bright skin line along the surface and around the front
		g.globalCompositeOperation = 'lighter'; g.lineJoin = 'round';
		g.beginPath(); pts.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y));
		g.strokeStyle = grad; g.globalAlpha = .55; g.lineWidth = Math.max(1, H * .06); g.stroke();
		g.globalAlpha = 1; g.globalCompositeOperation = 'source-over';
		const tf = temp(x1);
		if (tf > .3) glow(g, x1 - fr * .4, (base + H) / 2, H * .8, heat(tf), .4 * smooth(.3, .8, tf));
	}

	function sparks(s, x, y, n, spread = 1) {
		const H = s.H;
		for (let i = 0; i < n; i++) {
			const a = -Math.PI / 2 + rand(-1.1, 1.1) * spread, v = H * rand(2.5, 6);
			s.parts.emit({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, ay: H * 14, drag: .6, life: rand(.35, .8),
				size: Math.max(.8, H * rand(.03, .06)), color: pick([[255, 210, 110], [255, 160, 50], [255, 240, 170]]), kind: 'spark' });
		}
	}
	function blob(s, x, y) {
		const H = s.H, a = -Math.PI / 2 + rand(-.9, .9), v = H * rand(1.5, 3);
		s.parts.emit({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, ay: H * 12, life: rand(.25, .45), size: H * rand(.04, .07), color: [255, 150, 40], kind: 'drop' });
	}
	function smoke(s, x, y, n, warm = .3) {
		const H = s.H;
		for (let i = 0; i < n; i++) s.parts.emit({ x: x + rand(-.3, .3) * H, y, vx: rand(-.2, .2) * H, vy: -H * rand(.6, 1.2), drag: .4, life: rand(.9, 1.6),
			size: H * rand(.15, .3), grow: H * .5, color: mix([150, 145, 150], [255, 150, 70], warm), alpha: rand(.18, .3), kind: 'smoke' });
	}
	const coolAfter = s => s.done ? Math.exp(-s.doneT * 1.4) : 1;

	// ------------------------------------------------------------------ A: the ladle follows the cast
	CONCEPTS.push({
		group: 'Smelting', id: 'smelt-a', letter: 'A', name: 'Ladle pour',
		desc: 'The ladle rides the cast edge, pouring; the metal cools to dark steel behind it',
		spell: 'Smelt Steel', dur: [3, 3.8], padTop: 1.9, padX: 1.5, flash: [255, 170, 70],
		init(s) {
			const H = s.H;
			s.tilt = wobble(2); s.ph = rand(0, 6.3); s.cool = rand(.16, .22); s.sparkAcc = 0;
			s.plates = [];
			for (let x = H * .2; x < s.W + H; x += H * rand(.3, .42)) for (const yy of [.32, .7]) s.plates.push({ x: x + rand(-.1, .1) * H, y: H * (yy + rand(-.06, .06)), pts: plateShape(H * rand(.2, .27)) });
		},
		draw(g, s) {
			const W = s.W, H = s.H, base = H * .12, cool = coolAfter(s);
			const land = Math.max(0, s.fill - H * .32);
			const temp = x => cool * Math.exp(-Math.max(0, land - x) / (W * s.cool + H * 1.2));
			const surf = x => base + Math.sin(x / H * 4 - s.t * 9 + s.ph) * H * .045 * Math.exp(-Math.abs(land - x) / (H * 1.2));
			g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
			drawMolten(g, s, 0, s.fill, base, surf, temp, s.plates, H * .45);
			g.restore();
			// the ladle: pours while casting, then tips back and lifts away
			const back = s.done ? easeOut(clamp(s.doneT / .5)) : 0;
			const lx = land + H * .16, ly = -H * .38 - back * H * .3;
			const tilt = lerp(.58 + .07 * s.tilt(s.t), .05, back), r = H * .5;
			if (s.fill > .5 || s.casting) {
				glow(g, land, base, H * 1.1, [255, 130, 40], .35 * (1 - back));
				drawLadle(g, lx, ly, r, tilt, 1, 1 - s.p * .7);
				if (s.casting) { const [tx, ty] = tip(lx, ly, r, tilt, 1); drawStream(g, tx, ty, land, surf(land) + H * .1, H * .16, s.t, -1, s.ph); }
			}
			if (s.casting && s.fill > 1) {
				s.sparkAcc += s.dt * 26;
				while (s.sparkAcc >= 1) { s.sparkAcc--; sparks(s, land, base, 1, .9); if (Math.random() < .15) blob(s, land, base); }
			}
			s.parts.update(s.dt); s.parts.draw(g);
		}
	});

	// ------------------------------------------------------------------ B: one pour from the left, the metal runs along
	CONCEPTS.push({
		group: 'Smelting', id: 'smelt-b', letter: 'B', name: 'Running channel',
		desc: 'The ladle pours at the left; the metal runs along the bar, crust drifting on it',
		spell: 'Smelt Iron', dur: [3, 3.8], padTop: 1.9, padX: 1.6, flash: [255, 170, 70],
		init(s) {
			s.tilt = wobble(1.5); s.ph = rand(0, 6.3); s.plates = []; s.plateT = 0; s.sparkAcc = 0; s.bubbles = [];
		},
		draw(g, s) {
			const W = s.W, H = s.H, base = H * .14, cool = coolAfter(s);
			const pour = H * .55, front = Math.max(s.fill, Math.min(W, pour + H * .3) * Math.min(1, s.t * 3));
			const temp = x => cool * (.93 - .42 * clamp((x - pour) / Math.max(H, front - pour)) * Math.min(1, front / (W * .5)));
			const surf = x => base + Math.sin(x / H * 3 - s.t * 6 + s.ph) * H * .025 + Math.sin(x / H * 7.3 - s.t * 11) * H * .012;
			// crust drifts from the pour toward the front and piles up behind the lip
			if (s.casting) {
				s.plateT -= s.dt;
				if (s.plateT <= 0 && front > pour + H) { s.plateT = rand(.12, .22); s.plates.push({ x: pour + H * .4, y: H * rand(.35, .72), pts: plateShape(H * rand(.18, .3)), a: 0 }); }
				let limit = front - H * .6;
				const sorted = s.plates.slice().sort((a, b) => b.x - a.x);
				for (const p of sorted) {
					p.a = Math.min(1, p.a + s.dt * 1.5);
					p.x = Math.min(p.x + s.dt * (H * 2.2 + W * .25), limit);
					limit = Math.max(pour, p.x - H * rand(.2, .35));
				}
			}
			g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
			drawMolten(g, s, 0, front, base, surf, temp, s.plates, H * .55);
			// bubbles rising through the hot part and popping
			if (s.casting && Math.random() < s.dt * 7 && front > pour) s.bubbles.push({ x: rand(pour * .5, front - H * .5), age: 0, life: rand(.4, .8), r: H * rand(.04, .08) });
			s.bubbles = s.bubbles.filter(b => (b.age += s.dt) < b.life);
			for (const b of s.bubbles) {
				const u = b.age / b.life;
				g.strokeStyle = rgba(heat(1), .6 * (1 - u)); g.lineWidth = Math.max(.7, H * .025);
				g.beginPath(); g.arc(b.x, surf(b.x) + H * .05, b.r * (.5 + u), Math.PI, 0); g.stroke();
				if (u > .85 && !b.popped) { b.popped = 1; sparks(s, b.x, surf(b.x), 2, .6); }
			}
			g.restore();
			// heat haze over the hot run
			if (s.casting && Math.random() < s.dt * 10) s.parts.emit({ x: rand(0, front), y: base, vx: 0, vy: -H * rand(.8, 1.4), drag: .3, life: rand(.8, 1.3),
				size: H * rand(.2, .35), grow: H * .4, color: [255, 160, 90], alpha: .12, kind: 'smoke' });
			// the ladle stays over the left end, tipping further as it empties
			const back = s.done ? easeOut(clamp(s.doneT / .5)) : 0, r = H * .5;
			const lx = pour - H * .14, ly = -H * .4 - back * H * .3;
			const tilt = lerp(.45 + s.p * .55 + .05 * s.tilt(s.t), .05, back);
			glow(g, pour, base, H * 1.1, [255, 130, 40], .35 * (1 - back));
			drawLadle(g, lx, ly, r, tilt, -1, 1 - s.p);
			if (s.casting) { const [tx, ty] = tip(lx, ly, r, tilt, -1); drawStream(g, tx, ty, pour, base + H * .1, H * (.17 - .06 * s.p), s.t, 1, s.ph); }
			if (s.casting) {
				s.sparkAcc += s.dt * 18;
				while (s.sparkAcc >= 1) { s.sparkAcc--; sparks(s, pour, base, 1, .9); if (Math.random() < .25) sparks(s, front - H * .3, base + H * .1, 1, .5); }
			}
			s.parts.update(s.dt); s.parts.draw(g);
		}
	});

	// ------------------------------------------------------------------ C: ingot moulds, filled one by one
	CONCEPTS.push({
		group: 'Smelting', id: 'smelt-c', letter: 'C', name: 'Ingot moulds',
		desc: 'The ladle fills a row of ingot moulds in turn; each cools to a steel ingot with a puff of steam',
		spell: 'Smelt Steel', dur: [3.4, 4.2], padTop: 1.9, padX: 1.5, flash: [210, 220, 235],
		init(s) {
			const n = clamp(Math.round(s.W / (s.H * rand(1.6, 2.1))), 4, 11);
			s.cells = [];
			for (let i = 0; i < n; i++) s.cells.push({ level: 0, doneAt: null, puffed: false, ph: rand(0, 6.3) });
			s.tilt = wobble(2); s.sparkAcc = 0;
		},
		draw(g, s) {
			const W = s.W, H = s.H, n = s.cells.length, cw = W / n, inset = Math.max(1.5, H * .1);
			const pn = s.p * n, cur = Math.min(n - 1, Math.floor(pn)), u = pn - cur;
			const POUR0 = .14, POUR1 = .9;
			// cell levels
			s.cells.forEach((c, i) => {
				const lv = i < cur ? 1 : i > cur ? 0 : clamp((u - POUR0) / (POUR1 - POUR0));
				c.level = s.p >= 1 ? 1 : lv;
				if (c.level >= 1 && c.doneAt == null) c.doneAt = s.t;
			});
			// the mould: one dark iron casting with a well per ingot
			g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
			const gm = g.createLinearGradient(0, 0, 0, H);
			gm.addColorStop(0, '#3d3f46'); gm.addColorStop(1, '#1b1c20');
			g.fillStyle = gm; g.fillRect(0, 0, W, H);
			const well = (i, top) => {
				const x0 = i * cw + inset, x1 = (i + 1) * cw - inset, y1 = H - inset * .8, k = (x1 - x0) * .1;
				g.beginPath(); g.moveTo(x0, top); g.lineTo(x1, top); g.lineTo(x1 - k, y1); g.lineTo(x0 + k, y1); g.closePath();
				return [x0, x1, y1, k];
			};
			s.cells.forEach((c, i) => {
				const top = inset * .8;
				const [x0, x1, y1, k] = well(i, top);
				g.fillStyle = '#0d0d10'; g.fill();
				g.strokeStyle = 'rgba(160,165,175,.35)'; g.lineWidth = Math.max(.8, H * .03);        // lit lower lip of the well
				g.beginPath(); g.moveTo(x0 + k, y1); g.lineTo(x1 - k, y1); g.stroke();
				if (c.level <= 0) return;
				const tc = c.doneAt == null ? 1 : Math.exp(-(s.t - c.doneAt) / 1.3);
				const ly = lerp(y1, top + H * .06, c.level), lyw = ly + Math.sin(s.t * 12 + c.ph) * H * .02 * (c.level < 1 ? 1 : tc);
				g.save(); well(i, top); g.clip();
				const kk = (x1 - x0) * .1 * (1 - (lyw - top) / (y1 - top));
				g.beginPath(); g.moveTo(x0 + kk - 1, lyw); g.lineTo(x1 - kk + 1, lyw); g.lineTo(x1, y1 + 1); g.lineTo(x0, y1 + 1); g.closePath();
				const cool = heat(tc), steel = [128, 134, 146];
				const col = mix(steel, cool, smooth(0, .25, tc));
				const gi = g.createLinearGradient(0, lyw, 0, y1);
				gi.addColorStop(0, rgba(mix(col, [255, 255, 255], tc < .2 ? .35 : .15)));
				gi.addColorStop(.3, rgba(col)); gi.addColorStop(1, rgba(mix(col, [0, 0, 0], .45)));
				g.fillStyle = gi; g.fill();
				if (tc < .25) {      // a cold ingot: a bevel highlight and a stamp
					const a = smooth(.25, .05, tc);
					g.strokeStyle = `rgba(235,240,250,${.5 * a})`; g.lineWidth = Math.max(.8, H * .035);
					g.beginPath(); g.moveTo(x0 + kk + H * .05, lyw + H * .05); g.lineTo(x1 - kk - H * .05, lyw + H * .05); g.stroke();
					g.strokeStyle = `rgba(40,42,48,${.5 * a})`; g.lineWidth = Math.max(.7, H * .025);
					const cx = (x0 + x1) / 2, cy = (lyw + y1) / 2 + H * .04, rr = Math.min(cw * .12, H * .16);
					g.beginPath(); g.moveTo(cx - rr, cy); g.lineTo(cx, cy - rr * .7); g.lineTo(cx + rr, cy); g.lineTo(cx, cy + rr * .7); g.closePath(); g.stroke();
				}
				g.restore();
				if (tc > .3) glow(g, (x0 + x1) / 2, lyw, cw * .7, heat(tc), .3 * tc);
				if (c.doneAt != null && !c.puffed && tc < .45) { c.puffed = true; smoke(s, (x0 + x1) / 2, top, 6, .15); }
			});
			// cast iron rim between the wells
			g.strokeStyle = 'rgba(120,125,135,.45)'; g.lineWidth = Math.max(.8, H * .035);
			g.beginPath(); g.moveTo(0, inset * .8); g.lineTo(W, inset * .8); g.stroke();
			g.restore();
			// the ladle: slides to the next mould, then tips and pours
			const center = i => (i + .5) * cw;
			const back = s.done ? easeOut(clamp(s.doneT / .5)) : 0, r = H * .5;
			const mv = smooth(0, POUR0, u), xPour = s.p >= 1 ? center(n - 1) : lerp(cur > 0 ? center(cur - 1) : -cw * .3, center(cur), mv);
			const pouring = s.casting && u > POUR0 * .8 && u < POUR1;
			const tiltTarget = pouring ? .6 + .06 * s.tilt(s.t) : .08;
			s.tiltNow = s.tiltNow == null ? .08 : lerp(s.tiltNow, s.done ? .05 : tiltTarget, Math.min(1, s.dt * 10));
			const lx = xPour + H * .14, ly = -H * .4 - back * H * .3;
			const c = s.cells[cur], lyTop = lerp(H - inset * .8, inset * .8 + H * .06, c.level);
			if (pouring) glow(g, xPour, lyTop, H, [255, 130, 40], .35);
			drawLadle(g, lx, ly, r, s.tiltNow, 1, 1 - s.p * .8);
			if (pouring && s.tiltNow > .4) {
				const [tx, ty] = tip(lx, ly, r, s.tiltNow, 1); drawStream(g, tx, ty, xPour, lyTop, H * .14, s.t, -1, c.ph);
				s.sparkAcc += s.dt * 20;
				while (s.sparkAcc >= 1) { s.sparkAcc--; sparks(s, xPour, lyTop, 1, .8); }
			}
			s.parts.update(s.dt); s.parts.draw(g);
		}
	});
})();
