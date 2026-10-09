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

	// ------------------------------------------------------------------ A2: A's pour, from B2's foundry ladle
	// The crane trolley runs along with the cast edge, so the hanging ladle rides it and trails a little on
	// its cables; it pours backward onto the metal behind the edge. B2's ladle faces right, so it is drawn
	// mirrored about its pivot (x -> 2*px - x) and its own lip and stream code still apply.
	CONCEPTS.push({
		group: 'Smelting', id: 'smelt-a2', letter: 'A2', name: 'Ladle pour, foundry',
		desc: 'A with B2\'s cast-iron foundry ladle: it hangs from a crane that rides the cast edge, swinging a little as it goes, and pours a thick stream; the metal cools to dark steel behind it',
		spell: 'Smelt Steel', dur: [3, 3.8], padTop: 2.5, padX: 1.6, flash: [255, 170, 70],
		init(s) {
			const H = s.H;
			s.tilt = wobble(2); s.ph = rand(0, 6.3); s.cool = rand(.16, .22); s.sparkAcc = 0; s.fumeAcc = 0;
			initFoundryLook(s);
			s.plates = [];
			for (let x = H * .2; x < s.W + H; x += H * rand(.3, .42)) for (const yy of [.32, .7]) s.plates.push({ x: x + rand(-.1, .1) * H, y: H * (yy + rand(-.06, .06)), pts: plateShape(H * rand(.2, .27)) });
		},
		draw(g, s) {
			const W = s.W, H = s.H, base = H * .12, cool = coolAfter(s), u = H * s.k;
			const land = Math.max(0, s.fill - H * .32);
			const temp = x => cool * Math.exp(-Math.max(0, land - x) / (W * s.cool + H * 1.2));
			const surf = x => base + Math.sin(x / H * 4 - s.t * 9 + s.ph) * H * .045 * Math.exp(-Math.abs(land - x) / (H * 1.2));
			g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
			drawMolten(g, s, 0, s.fill, base, surf, temp, s.plates, H * .45);
			g.restore();
			// the ladle: pours while casting, then rights itself and is lifted away
			const back = s.done ? easeOut(clamp(s.doneT / .5)) : 0;
			const tilt = lerp(.5 + .25 * s.p + .04 * s.tilt(s.t), .08, back);
			const [lx, ly] = rot(LIP[0] * u, LIP[1] * u, tilt);
			const px = land + H * .1 + lx, py = -H * .95 - back * H * .35;
			// trailing on its cables while the trolley moves; it settles once the cast stops
			s.sway = s.swayW(s.t) * H * .03 - H * .06 * (s.casting ? 1 : 1 - back);
			s.L = { px, py, u, tilt, full: 1 - s.p * .8, tip: [px - lx, py + ly], land, landY: surf(land) + H * .1, back };
			glow(g, land, base, H * 1.1, [255, 130, 40], .35 * (1 - back));
			if (s.casting && s.fill > 1) {
				s.sparkAcc += s.dt * 26;
				while (s.sparkAcc >= 1) { s.sparkAcc--; sparks(s, land, base, 1, .9); if (Math.random() < .15) blob(s, land, base); }
				s.fumeAcc += s.dt * 7;
				while (s.fumeAcc >= 1) {
					s.fumeAcc--;
					const [rx, ry] = rot(rand(-.6, .7) * u, FL.T * u, tilt);
					s.parts.emit({ x: px - rx, y: py + ry, vx: rand(-.3, .2) * H, vy: -H * rand(.7, 1.3), drag: .35, life: rand(1, 1.7),
						size: H * rand(.2, .35), grow: H * .7, color: [120, 112, 110], alpha: .2, kind: 'smoke' });
				}
			}
			s.parts.update(s.dt); s.parts.draw(g);
		},
		over(g, s) {
			if (!s.L || !(s.fill > .5 || s.casting)) return;
			const H = s.H, L = s.L;
			s.padTopPx = H * 2.5;
			g.save(); g.translate(2 * L.px, 0); g.scale(-1, 1);   // mirrored about the pivot: the lip faces back
			drawFoundryLadle(g, s, L.px, L.py, L.u, L.tilt, L.full);
			if (s.casting) drawHeavyStream(g, 2 * L.px - L.tip[0], L.tip[1], 2 * L.px - L.land, L.landY, H * (.14 - .04 * s.p), s.t, s.ph);
			g.restore();
		},
	});

	// ------------------------------------------------------------------ A3: A's pour, from B3's forged hand ladle
	const LADLE_A3 = .38;   // A3's ladle radius, in bar heights (B3's is .56)
	// A's metal and motion; the ladle is B3's painted forged-iron one (drawRealLadle, the same shape as A's,
	// so tip() still finds its spout), drawn in front of the frame line with its stream.
	CONCEPTS.push({
		group: 'Smelting', id: 'smelt-a3', letter: 'A3', name: 'Ladle pour, forged',
		desc: 'A with B3\'s forged-iron hand ladle, sooty and heat-tinted: it rides the cast edge pouring, and the metal cools to dark steel behind it',
		spell: 'Smelt Steel', dur: [3, 3.8], padTop: 1.6, padX: 1.6, flash: [255, 170, 70],
		init(s) {
			const H = s.H;
			s.tilt = wobble(2); s.ph = rand(0, 6.3); s.cool = rand(.16, .22); s.sparkAcc = 0;
			s.look = makeLadleLook();
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
			// the ladle: pours while casting, then tips back and lifts away (drawn in over())
			const back = s.done ? easeOut(clamp(s.doneT / .5)) : 0;
			const r = H * LADLE_A3, lx = land + H * .11, ly = -H * .3 - back * H * .3;   // about two-thirds of B3's ladle
			const tilt = lerp(.58 + .07 * s.tilt(s.t), .05, back);
			s.L = { lx, ly, r, tilt, land, landY: surf(land) + H * .1, full: 1 - s.p * .7 };
			if (s.fill > .5 || s.casting) glow(g, land, base, H * 1.1, [255, 130, 40], .35 * (1 - back));
			if (s.casting && s.fill > 1) {
				s.sparkAcc += s.dt * 26;
				while (s.sparkAcc >= 1) { s.sparkAcc--; sparks(s, land, base, 1, .9); if (Math.random() < .15) blob(s, land, base); }
			}
			s.parts.update(s.dt); s.parts.draw(g);
		},
		over(g, s) {
			if (!s.L || !(s.fill > .5 || s.casting)) return;
			const L = s.L, H = s.H;
			drawRealLadle(g, s.look, L.lx, L.ly, L.r, L.tilt, 1, L.full);
			if (s.casting) { const [tx, ty] = tip(L.lx, L.ly, L.r, L.tilt, 1); drawStream(g, tx, ty, L.land, L.landY, H * .11, s.t, -1, s.ph); }
		},
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

	// ------------------------------------------------------------------ B2: a foundry ladle hung from a crane pours the run
	// A big riveted bucket ladle hangs from its bail on the trunnion hub (pivot); the body turns on the hub to pour.
	// Local units: u = one bar height (times the cast's size); y down; the hub at (0,0).
	const FL = { T: -.55, B: 1.0, wt: .8, wb: .62 };
	function foundryBody(g, u) {
		const { T, B, wt, wb } = FL, c = .2;
		g.beginPath(); g.moveTo(-wt * u, T * u); g.lineTo(-wb * u, (B - c) * u); g.quadraticCurveTo(-wb * u, B * u, (-wb + c) * u, B * u);
		g.lineTo((wb - c) * u, B * u); g.quadraticCurveTo(wb * u, B * u, wb * u, (B - c) * u); g.lineTo(wt * u, T * u); g.closePath();
	}
	const halfW = y => lerp(FL.wt, FL.wb, (y - FL.T) / (FL.B - FL.T));
	// the pouring lip, in local units
	const LIP = [FL.wt + .27, FL.T - .13];
	const rot = (x, y, a) => [x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)];

	// The per-cast look of a foundry ladle (shared by B2 and A2): its size, the sway on its cables, slag and soot.
	function initFoundryLook(s) {
		s.k = rand(.6, .66); s.swayW = wobble(.8); s.sway = 0;
		s.slag = [];
		for (let i = 0; i < 5; i++) s.slag.push({ x: rand(-.6, .45), y: rand(-.06, .06), pts: plateShape(rand(.07, .12)) });
		s.soot = [];
		for (let i = 0; i < 7; i++) s.soot.push({ x: rand(-.75, .65), w: rand(.03, .09), l: rand(.25, .8), a: rand(.15, .35) });
	}

	// Drawn like cast iron rather than an outlined cartoon: shading only, no dark outlines.
	function drawFoundryLadle(g, s, px, py, u, tilt, full) {
		const { T, B, wt } = FL;
		const hookY = py - 1.25 * u, sway = s.sway;
		// two thin cables up to the crane, out of sight
		g.lineCap = 'round';
		for (const dx of [-.12, .12]) {
			g.strokeStyle = 'rgba(20,20,24,.9)'; g.lineWidth = Math.max(1, u * .04);
			g.beginPath(); g.moveTo(px + dx * u + sway, hookY - .25 * u); g.lineTo(px + dx * 1.4 * u + sway * 3, -s.padTopPx); g.stroke();
			g.strokeStyle = 'rgba(120,124,132,.35)'; g.lineWidth = Math.max(.5, u * .015); g.stroke();
		}
		// small hook block and the bail: a slim arched hanger down to the pivot on each side
		let gr = g.createLinearGradient(0, hookY - .3 * u, 0, hookY - .05 * u); gr.addColorStop(0, '#4a4c53'); gr.addColorStop(1, '#1d1e22');
		g.fillStyle = gr; roundRectPath(g, px - .15 * u + sway, hookY - .3 * u, .3 * u, .24 * u, .05 * u); g.fill();
		// seen from the side, the bail is a flat bar from the hook down to the pivot; the far one sits just behind
		const bail = (off, a) => {
			const x0 = px + sway + off * u, x1 = px + off * u;
			g.strokeStyle = `rgba(28,29,33,${a})`; g.lineWidth = u * .1;
			g.beginPath(); g.moveTo(x0, hookY - .08 * u); g.lineTo(x1, py); g.stroke();
			g.strokeStyle = 'rgba(150,154,162,.22)'; g.lineWidth = u * .022;
			g.beginPath(); g.moveTo(x0 - .03 * u, hookY - .06 * u); g.lineTo(x1 - .03 * u, py); g.stroke();
		};
		bail(.08, .7);

		// the body, turned on its pivot
		g.save(); g.translate(px, py); g.rotate(tilt);
		glow(g, 0, .3 * u, 1.3 * u, [255, 90, 20], .12 + .08 * full);
		foundryBody(g, u);
		gr = g.createLinearGradient(-wt * u, 0, wt * u, 0);
		gr.addColorStop(0, '#16171a'); gr.addColorStop(.28, '#3a3b40'); gr.addColorStop(.5, '#26272b'); gr.addColorStop(1, '#0f1012');
		g.fillStyle = gr; g.fill();
		g.save(); foundryBody(g, u); g.clip();
		// heat discolouration: dull red low down where the metal sits, a bronze-blue temper band above it
		glow(g, .1 * u, .8 * u, 1.0 * u, [210, 60, 14], .22 + .22 * full);
		gr = g.createLinearGradient(0, T * u, 0, B * u);
		gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(.35, 'rgba(90,80,110,.10)'); gr.addColorStop(.55, 'rgba(150,100,50,.12)'); gr.addColorStop(1, 'rgba(0,0,0,.35)');
		g.fillStyle = gr; g.fillRect(-u, T * u, 2 * u, (B - T) * u);
		// soot streaks running down from the rim
		for (const st of s.soot) { g.fillStyle = `rgba(5,5,6,${st.a})`; g.fillRect(st.x * u, T * u, st.w * u, st.l * u); }
		// two low banding hoops, small rivets
		for (const hy of [-.22, .72]) {
			const hw = halfW(hy) + .03;
			g.fillStyle = 'rgba(0,0,0,.35)'; g.fillRect(-hw * u, (hy - .05) * u, hw * 2 * u, .1 * u);
			g.fillStyle = 'rgba(160,165,175,.16)'; g.fillRect(-hw * u, (hy - .05) * u, hw * 2 * u, .018 * u);
			for (let rx = -hw + .12; rx < hw; rx += .24) {
				g.fillStyle = 'rgba(120,124,132,.55)'; g.beginPath(); g.arc(rx * u, hy * u, .018 * u, 0, PI2); g.fill();
			}
		}
		// a soft highlight down the near flank
		gr = g.createLinearGradient(-.6 * u, 0, -.3 * u, 0); gr.addColorStop(0, 'rgba(200,205,215,0)'); gr.addColorStop(.5, 'rgba(200,205,215,.12)'); gr.addColorStop(1, 'rgba(200,205,215,0)');
		g.fillStyle = gr; g.fillRect(-.6 * u, T * u, .3 * u, (B - T) * u);
		g.restore();
		// the pouring lip
		g.beginPath(); g.moveTo((wt - .12) * u, (T - .01) * u); g.lineTo(LIP[0] * u, LIP[1] * u); g.lineTo((LIP[0] - .05) * u, (LIP[1] + .07) * u); g.lineTo((wt - .02) * u, (T + .16) * u); g.closePath();
		g.fillStyle = '#232428'; g.fill();
		g.strokeStyle = rgba(heat(.85), .8 * full + .15); g.lineWidth = Math.max(1, u * .04); g.beginPath(); g.moveTo((wt - .08) * u, (T - .03) * u); g.lineTo(LIP[0] * u, LIP[1] * u); g.stroke();
		glow(g, LIP[0] * u, LIP[1] * u, .45 * u, [255, 150, 50], .35);
		// the open top: molten metal with a little slag, inside the rim
		const oy = T * u, orx = (wt + .01) * u, ory = .13 * u;
		g.save(); g.beginPath(); g.ellipse(0, oy, orx, ory, 0, 0, PI2); g.clip();
		gr = g.createRadialGradient(.3 * u, oy, 0, 0, oy, orx);
		gr.addColorStop(0, rgba(heat(.78 + .22 * full))); gr.addColorStop(1, rgba(heat(.45 + .2 * full)));
		g.fillStyle = gr; g.fillRect(-orx, oy - ory, orx * 2, ory * 2);
		for (const p of s.slag) {
			polyPath(g, p.x * u, oy + p.y * u, p.pts.map(([a, b]) => [a * u, b * u * .45]));
			g.fillStyle = 'rgba(52,44,40,.85)'; g.fill();
		}
		g.restore();
		// rim: a rolled iron lip, lit by the metal from inside
		g.beginPath(); g.ellipse(0, oy, orx, ory, 0, 0, PI2);
		g.strokeStyle = '#1e1f23'; g.lineWidth = u * .09; g.stroke();
		g.beginPath(); g.ellipse(0, oy + .01 * u, orx * .96, ory * .8, 0, Math.PI * .05, Math.PI * .95); g.strokeStyle = rgba(heat(.9), .45); g.lineWidth = u * .025; g.stroke();
		g.beginPath(); g.ellipse(0, oy - .02 * u, orx, ory, 0, Math.PI * 1.1, Math.PI * 1.9); g.strokeStyle = 'rgba(190,195,205,.22)'; g.lineWidth = u * .02; g.stroke();
		glow(g, .2 * u, oy - .08 * u, .9 * u, [255, 150, 50], .2 + .18 * full);
		// trunnion: a modest boss the body turns on
		gr = g.createRadialGradient(-.04 * u, -.04 * u, 0, 0, 0, .14 * u); gr.addColorStop(0, '#6d7078'); gr.addColorStop(1, '#1f2024');
		g.fillStyle = gr; g.beginPath(); g.arc(0, 0, .14 * u, 0, PI2); g.fill();
		g.restore();
		// near bail arm, over the pivot
		bail(0, 1);
		g.fillStyle = '#5a5d65'; g.beginPath(); g.arc(px, py, .06 * u, 0, PI2); g.fill();
	}

	// a thick, heavy pour: glow from a blur instead of a wide band, a rope-like twist down its length
	function drawHeavyStream(g, x0, y0, x1, y1, w, t, ph) {
		if (w <= .3) return;
		const pts = [], n = 18;
		for (let i = 0; i <= n; i++) {
			const v = i / n, e = 1 - (1 - v) * (1 - v);
			pts.push([lerp(x0, x1, e) + w * .5 * Math.sin(v * Math.PI) * (1 - v) + Math.sin(t * 17 + v * 7 + ph) * w * .08 * v, lerp(y0, y1, v)]);
		}
		const path = () => { g.beginPath(); pts.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y)); };
		g.lineCap = 'round'; g.lineJoin = 'round';
		g.save(); g.shadowColor = 'rgba(255,120,20,.9)'; g.shadowBlur = w * 1.6;
		path(); g.strokeStyle = rgba([220, 90, 18]); g.lineWidth = w; g.stroke(); g.restore();
		path(); g.strokeStyle = rgba(heat(.8)); g.lineWidth = w * .66; g.stroke();
		g.globalCompositeOperation = 'lighter';
		g.setLineDash([w * .7, w * .5]); g.lineDashOffset = -t * w * 14;
		path(); g.strokeStyle = 'rgba(255,235,170,.45)'; g.lineWidth = w * .3; g.stroke();
		g.setLineDash([]);
		g.globalCompositeOperation = 'source-over';
	}

	// ---- B2's molten run: a viscous height field, like lava. The metal heaps up where the stream lands,
	// slumps under its own weight and creeps along the bar with a blunt, rounded toe: the flow goes
	// with depth cubed times the slope, so a thin edge hardly moves and the toe stays fat. Heat is
	// carried with the metal and leaks away, so the run is brightest at the pour and crusts over
	// further on. Positions and depths are in bar heights, so it behaves the same at any size.
	function makeMelt(W, H) {
		const N = Math.max(30, Math.ceil(W / (H * .1)));
		return { N, dx: W / H / N, h: new Float32Array(N), T: new Float32Array(N), e: new Float32Array(N), q: new Float32Array(N + 1),
			hs: new Float32Array(N), vel: new Float32Array(N), tmp: new Float32Array(N) };
	}
	const MELT_K = .9;   // how freely it flows; lower is thicker
	function stepMelt(M, gate, dt, tilt) {
		const { N, dx, h, T, e, q } = M;
		let hmax = .2;
		for (let i = 0; i < N; i++) hmax = Math.max(hmax, h[i]);
		const STEP = Math.min(.01, dx * dx / (2.5 * MELT_K * hmax * hmax * hmax));
		for (let t = dt; t > 1e-6; t -= STEP) {
			const d = Math.min(t, STEP);
			for (let i = 1; i < N; i++) {
				const hm = (h[i - 1] + h[i]) / 2;
				q[i] = MELT_K * hm * hm * hm * (tilt - (h[i] - h[i - 1]) / dx) * clamp((gate - i * dx) / .35);   // the cast edge holds the toe back
			}
			q[0] = q[N] = 0;
			for (let i = 0; i < N; i++) {   // never drain a cell below empty
				const out = (Math.max(0, q[i + 1]) + Math.max(0, -q[i])) * d / dx;
				if (out > h[i] && out > 0) { const k = h[i] / out; if (q[i + 1] > 0) q[i + 1] *= k; if (q[i] < 0) q[i] *= k; }
			}
			// heat goes with the metal, taken from the cell it leaves
			for (let i = 0; i < N; i++) e[i] = T[i] * h[i];
			for (let i = 1; i < N; i++) {
				const f = q[i] * d / dx, src = f > 0 ? T[i - 1] : T[i];
				e[i - 1] -= f * src; e[i] += f * src;
			}
			for (let i = 0; i < N; i++) {
				h[i] = Math.max(0, h[i] + d * (q[i] - q[i + 1]) / dx);
				T[i] = h[i] > 1e-4 ? clamp(e[i] / h[i]) : 0;
			}
		}
		for (let i = 0; i < N; i++) M.vel[i] = h[i] > .04 ? (q[i] + q[i + 1]) / 2 / h[i] : 0;
		// what is drawn: smoothed, and a film too thin to see is no metal at all
		const { hs, tmp } = M;
		for (let i = 0; i < N; i++) tmp[i] = (h[Math.max(0, i - 1)] + 2 * h[i] + h[Math.min(N - 1, i + 1)]) / 4;
		for (let i = 0; i < N; i++) hs[i] = (tmp[Math.max(0, i - 1)] + 2 * tmp[i] + tmp[Math.min(N - 1, i + 1)]) / 4;
	}
	// pour `amount` (area, in bar heights squared) of fresh, fully hot metal around x
	function pourMelt(M, x, amount, sig) {
		const { N, dx, h, T } = M;
		let sum = 0;
		for (let i = 0; i < N; i++) sum += Math.exp(-((((i + .5) * dx - x) / sig) ** 2));
		if (sum <= 0) return;
		for (let i = 0; i < N; i++) {
			const a = amount * Math.exp(-((((i + .5) * dx - x) / sig) ** 2)) / sum / dx;
			if (a <= 0) continue;
			T[i] = (T[i] * h[i] + a) / (h[i] + a); h[i] += a;
		}
	}
	const meltAt = (M, a, x) => a[clamp(Math.floor(x / M.dx), 0, M.N - 1)];   // x in bar heights

	// The viscous run in the bar, shared by B2 and B3. pour is where the stream lands (px); back (0..1)
	// is how far the ladle has righted itself after the cast; fumeAt() gives a point on the ladle's
	// rim where fumes rise. Sets s.L.landY, the surface height where the stream lands.
	function initMelt(s) {
		s.melt = makeMelt(s.W, s.H); s.folds = []; s.foldT = 0; s.plates = []; s.plateT = 0; s.domes = []; s.domeT = rand(.3, .6);
		s.sparkAcc = 0; s.fumeAcc = 0;
	}
	function drawMeltRun(g, s, pour, back, fumeAt) {
		const W = s.W, H = s.H, M = s.melt, N = M.N, dxp = M.dx * H;
		// pour in what the cast has reached: a thick heap at first, the level rising to the brim at the end
		let vol = 0;
		for (let i = 0; i < N; i++) vol += M.h[i] * M.dx;
		const target = W / H * 1.04 * Math.pow(s.p, 1.7);
		if (s.casting && target > vol) pourMelt(M, pour / H, Math.min(target - vol, W / H * 1.6 * s.dt + .002), .32);
		const gate = s.done ? W / H + 1 : s.fill / H + .2;
		// while the toe trails the cast edge the run leans forward, so it creeps to keep up; once it has, it only slumps level
		const lean = s.done ? 0 : 40 * clamp(((s.fill - (s.xf || 0)) / H - .15) / .8);
		stepMelt(M, gate, s.dt, lean);
		// it cools as it goes: thin metal and the skin far from the pour fastest, and quickly once the pour stops
		const cr = s.done ? 1.6 : .75;
		for (let i = 0; i < N; i++) if (M.h[i] > 1e-4) M.T[i] = Math.max(.1, M.T[i] - s.dt * cr * (M.T[i] - .1) * (1 + .25 / Math.max(.15, M.h[i])));

		// the metal's outline: the smoothed depth, with a slow, heavy swell on the surface
		let xf = 0;
		for (let i = 0; i < N; i++) if (M.hs[i] > .03) xf = (i + 1) * dxp;
		s.xf = xf;
		const top = [];
		for (let i = 0; i < N; i++) {
			const x = (i + .5) * dxp, d = M.hs[i], calm = clamp(d / .3) * clamp((1.25 - d) / .3);
			const swell = Math.sin(x / (H * 1.4) - s.t * 1.1 + s.ph) * .028 + Math.sin(x / (H * 2.6) + s.t * .55) * .02;
			top.push([x, H - Math.min(d, 1.3) * H - calm * swell * H]);
		}
		const tempX = x => meltAt(M, M.T, x / H), topY = top.map(p => p[1]), surfAt = x => meltAt(M, topY, x / H);
		s.L.landY = surfAt(pour) + H * .02;
		g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
		if (xf > 1) {
			const iF = Math.min(N - 1, Math.ceil(xf / dxp));
			const body = () => {
				g.beginPath(); g.moveTo(0, H + 1); g.lineTo(0, top[0][1]);
				for (let i = 0; i <= iF; i++) g.lineTo(top[i][0], top[i][1]);
				g.quadraticCurveTo(xf + dxp * .6, top[iF][1] + (H - top[iF][1]) * .35, xf + dxp * .4, H + 1);
				g.closePath();
			};
			const grad = g.createLinearGradient(0, 0, xf + dxp, 0), n = 28;
			for (let k = 0; k <= n; k++) grad.addColorStop(k / n, rgba(heat(.9 * tempX(lerp(0, xf, k / n)))));
			body(); g.fillStyle = grad; g.fill();
			g.save(); body(); g.clip();
			// the skin on top is darker and cooler; underneath it stays hot, and deeper is darker again
			const gv = g.createLinearGradient(0, 0, 0, H);
			gv.addColorStop(0, 'rgba(25,8,4,.18)'); gv.addColorStop(.35, 'rgba(255,200,120,.06)'); gv.addColorStop(1, 'rgba(10,0,0,.4)');
			g.fillStyle = gv; g.fillRect(0, 0, xf + dxp, H + 2);
			// crust plates that form as it cools and ride along; their seams glow
			for (const p of s.plates) {
				const tp = tempX(p.x), a = p.a * smooth(.62, .3, tp);
				if (a <= .01) continue;
				polyPath(g, p.x, p.y, p.pts);
				g.strokeStyle = rgba(heat(Math.min(1, tp + .3)), a * .7); g.lineWidth = Math.max(1, H * .06); g.lineJoin = "round"; g.stroke();   // the glowing seam round it
				g.fillStyle = rgba(mix(heat(tp * .3), [34, 30, 32], .6), a * .92); g.fill();
				g.fillStyle = `rgba(200,205,215,${a * smooth(.3, 0, tp) * .14})`; polyPath(g, p.x - H * .02, p.y - H * .03, p.pts.map(([a1, b1]) => [a1 * .55, b1 * .45])); g.fill();
			}
			// ropy folds in the skin, bowed the way it flows, pushed up near the pour and carried off slowly
			g.lineCap = 'round';
			for (const f of s.folds) {
				const tf = tempX(f.x), y0 = surfAt(f.x);
				const a = clamp(f.age * 2) * clamp((f.life - f.age) / .6), depth = (H - y0) * f.dep, bow = f.bow * H;
				if (a <= 0 || depth < H * .08) continue;
				const path = dxs => { g.beginPath(); g.moveTo(f.x + dxs, y0 + H * .03); g.quadraticCurveTo(f.x + dxs + bow, y0 + depth * .5, f.x + dxs - bow * .2, y0 + depth); };
				path(-H * .04); g.strokeStyle = rgba(heat(Math.min(1, tf + .25)), .55 * a); g.lineWidth = Math.max(.7, H * .03); g.stroke();
				path(0); g.strokeStyle = rgba(mix(heat(tf * .5), [30, 20, 18], .4), .7 * a); g.lineWidth = Math.max(.9, H * .05); g.stroke();
			}
			g.restore();
			// the skin line along the top and round the toe: dull where crusted, bright where hot
			g.globalCompositeOperation = 'lighter'; g.lineJoin = 'round';
			g.beginPath(); for (let i = 0; i <= iF; i++) i ? g.lineTo(top[i][0], top[i][1]) : g.moveTo(top[i][0], top[i][1]);
			g.strokeStyle = grad; g.globalAlpha = .45; g.lineWidth = Math.max(1, H * .05); g.stroke();
			g.globalAlpha = 1; g.globalCompositeOperation = 'source-over';
			// the toe glows from inside its crust
			const tt = tempX(xf - H * .2);
			if (tt > .2) glow(g, xf - H * .15, (top[iF][1] + H) / 2, H * .7, heat(tt + .2), .35 * smooth(.2, .7, tt));
			// slow fat bubbles swelling up out of the hot metal and bursting
			for (const b of s.domes) {
				const v = b.age / b.life, yb = surfAt(b.x), r = b.r * Math.sin(Math.min(1, v * 1.15) * Math.PI / 2);
				g.beginPath(); g.arc(b.x, yb + H * .02, r, Math.PI, 0); g.closePath();
				g.fillStyle = rgba(heat(Math.min(1, tempX(b.x) + .12))); g.fill();
				g.strokeStyle = rgba(heat(.95), .6); g.lineWidth = Math.max(.6, H * .02); g.beginPath(); g.arc(b.x, yb + H * .02, r, Math.PI * 1.1, Math.PI * 1.9); g.stroke();
			}
		}
		g.restore();

		// spawn and move the skin features with the flow underneath them
		const velAt = x => meltAt(M, M.vel, x / H) * H;
		if (s.casting) {
			s.foldT -= s.dt;
			if (s.foldT <= 0 && xf > pour + H * .3) { s.foldT = rand(.14, .26); s.folds.push({ x: pour + H * rand(.15, .35), age: 0, life: rand(2.5, 4), dep: rand(.45, .85), bow: rand(.08, .16) }); }
			s.plateT -= s.dt;
			if (s.plateT <= 0 && xf > pour + H) { s.plateT = rand(.18, .3); s.plates.push({ x: pour + H * rand(.3, .6), y: H * rand(.45, .8), pts: plateShape(H * rand(.16, .26)), a: 0 }); }
			s.domeT -= s.dt;
			if (s.domeT <= 0 && xf > pour + H * .4) { s.domeT = rand(.35, .8); s.domes.push({ x: rand(Math.max(H * .3, pour - H * .5), Math.min(xf - H * .4, pour + H * 2.5)), age: 0, life: rand(.7, 1.3), r: H * rand(.07, .13) }); }
		}
		for (const f of s.folds) { f.age += s.dt; f.x = Math.min(f.x + velAt(f.x) * s.dt, xf - H * .15); }
		s.folds = s.folds.filter(f => f.age < f.life);
		for (const p of s.plates) { p.a = Math.min(1, p.a + s.dt); p.x = Math.min(p.x + velAt(p.x) * s.dt * .9, xf - H * .3); }
		if (s.plates.length > 40) s.plates.shift();
		s.domes = s.domes.filter(b => {
			b.age += s.dt;
			if (b.age < b.life) return true;
			const yb = surfAt(b.x);
			sparks(s, b.x, yb, 3, .5); blob(s, b.x, yb);
			return false;
		});

		// fumes off the ladle and heat haze over the run; sparks where the stream lands
		if (s.casting) {
			s.fumeAcc += s.dt * 9;
			while (s.fumeAcc >= 1) {
				s.fumeAcc--;
				const [fx, fy] = fumeAt();
				s.parts.emit({ x: fx, y: fy, vx: rand(-.2, .3) * H, vy: -H * rand(.7, 1.3), drag: .35, life: rand(1, 1.7),
					size: H * rand(.2, .35), grow: H * .7, color: [120, 112, 110], alpha: .22, kind: 'smoke' });
				if (Math.random() < .5 && xf > 0) s.parts.emit({ x: rand(0, xf), y: H * .2, vx: 0, vy: -H * rand(.6, 1.1), drag: .3, life: rand(1, 1.6),
					size: H * rand(.25, .4), grow: H * .4, color: [255, 160, 90], alpha: .09, kind: 'smoke' });
			}
			s.sparkAcc += s.dt * 14;
			while (s.sparkAcc >= 1) { s.sparkAcc--; sparks(s, pour, s.L.landY, 1, .8); if (Math.random() < .1) blob(s, pour, s.L.landY); }
		}
		glow(g, pour, s.L.landY, H * 1.3, [255, 130, 40], .4 * (1 - back));
		s.parts.update(s.dt); s.parts.draw(g);
	}

	CONCEPTS.push({
		group: 'Smelting', id: 'smelt-b2', letter: 'B2', name: 'Foundry ladle',
		desc: 'A cast-iron foundry ladle hangs from a crane and tips on its pivot; the thick molten steel heaps where it lands, slumps and creeps along the bar with a fat glowing toe, its skin wrinkling and crusting over as it cools, rising until it fills the bar',
		spell: 'Smelt Iron', dur: [3, 3.8], padTop: 2.5, padX: 1.6, flash: [255, 170, 70],
		init(s) {
			s.tilt = wobble(1.2); s.ph = rand(0, 6.3); s.sparkAcc = 0; s.fumeAcc = 0;
			initFoundryLook(s);
			initMelt(s);
		},
		draw(g, s) {
			const W = s.W, H = s.H, u = H * s.k;
			// the ladle's pose: tips further as it empties, then rights itself when the cast ends
			const back = s.done ? easeOut(clamp(s.doneT / .6)) : 0;
			s.L = { px: H * .02, py: -H * .95, u, tilt: lerp(.4 + s.p * .45 + .03 * s.tilt(s.t), .08, back), full: 1 - s.p * .85 };
			s.sway = s.swayW(s.t) * H * .03;
			const [lx, ly] = rot(LIP[0] * u, LIP[1] * u, s.L.tilt);
			s.L.tip = [s.L.px + lx, s.L.py + ly];
			const pour = clamp(s.L.tip[0] + H * .12, H * .3, W * .5);
			s.L.pour = pour; s.L.back = back;

			drawMeltRun(g, s, pour, back, () => {
				const [rx, ry] = rot(rand(-.6, .7) * u, FL.T * u, s.L.tilt);
				return [s.L.px + rx, s.L.py + ry];
			});
		},
		over(g, s) {
			if (!s.L) return;
			const H = s.H, L = s.L;
			s.padTopPx = H * 2.5;
			drawFoundryLadle(g, s, L.px, L.py, L.u, L.tilt, L.full);
			if (s.casting) drawHeavyStream(g, L.tip[0], L.tip[1], L.pour, L.landY, H * (.16 - .05 * s.p), s.t, s.ph);
		},
	});

	// ------------------------------------------------------------------ B3: a hand ladle pours the viscous run
	// The same ladle shape as drawLadle (so tip() still finds its spout), painted as forged iron rather
	// than outlined: soft shading, soot, heat colours near the rim, molten glow over the lip, slag inside,
	// and the run's orange light on its underside. The per-cast soot and slag come from s.ladle.
	function makeLadleLook() {
		const soot = [], slag = [];
		for (let i = 0; i < 6; i++) soot.push({ x: rand(.2, 1.8), w: rand(.04, .1), l: rand(.3, .9), a: rand(.12, .3) });
		for (let i = 0; i < 4; i++) slag.push({ x: rand(.35, 1.6), y: rand(-.05, .05), pts: plateShape(rand(.08, .14)) });
		return { soot, slag };
	}
	function drawRealLadle(g, look, lx, ly, r, tilt, dir, full) {
		g.save(); g.translate(lx, ly); g.scale(dir, 1); g.rotate(-tilt);
		g.lineCap = 'round';
		// handle: a forged iron rod, heat-tinted near the bowl, ending in a wooden grip with iron rings
		const hx0 = 1.8 * r, hy0 = .2 * r, ha = -.5, L = 2.5 * r, hx1 = hx0 + Math.cos(ha) * L, hy1 = hy0 + Math.sin(ha) * L;
		const at = v => [hx0 + Math.cos(ha) * L * v, hy0 + Math.sin(ha) * L * v];
		const [gx, gy] = at(.6);
		const line = (x0, y0, x1, y1, w, c) => { g.strokeStyle = c; g.lineWidth = w; g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke(); };
		line(hx0, hy0, gx, gy, r * .14, '#3a3c42');
		line(hx0, hy0 + r * .03, gx, gy + r * .03, r * .06, 'rgba(10,10,12,.45)');
		const tg = g.createLinearGradient(hx0, hy0, gx, gy);
		tg.addColorStop(0, 'rgba(165,115,60,.55)'); tg.addColorStop(.2, 'rgba(80,90,150,.4)'); tg.addColorStop(.45, 'rgba(80,90,150,0)');
		line(hx0, hy0, gx, gy, r * .14, tg);
		line(hx0, hy0 - r * .04, gx, gy - r * .04, r * .035, 'rgba(185,190,200,.45)');
		const wg = g.createLinearGradient(gx, gy - r * .1, gx, gy + r * .1);
		wg.addColorStop(0, '#6a4a30'); wg.addColorStop(.5, '#46301d'); wg.addColorStop(1, '#24170d');
		line(gx, gy, hx1, hy1, r * .2, wg);
		for (let k = 1; k < 4; k++) {   // grain along the grip
			const o = (k - 2) * r * .045;
			line(gx + r * .05, gy + o, hx1 - r * .05, hy1 + o, Math.max(.5, r * .012), 'rgba(25,14,6,.35)');
		}
		for (const v of [.62, .97]) {   // iron rings at each end of the grip
			const [rx, ry] = at(v), nx = -Math.sin(ha) * r * .12, ny = Math.cos(ha) * r * .12;
			line(rx - nx, ry - ny, rx + nx, ry + ny, r * .07, '#2a2b30');
			line(rx - nx * .8, ry - ny * .8, rx - nx * .1, ry - ny * .1, r * .02, 'rgba(180,185,195,.35)');
		}
		// bowl
		const bowl = () => {
			g.beginPath(); g.moveTo(-.24 * r, -.06 * r); g.lineTo(-.04 * r, .2 * r);
			g.bezierCurveTo(-.02 * r, .95 * r, .42 * r, 1.32 * r, r, 1.32 * r);
			g.bezierCurveTo(1.58 * r, 1.32 * r, 2.02 * r, .95 * r, 2 * r, 0);
			g.lineTo(0, 0); g.closePath();
		};
		const gb = g.createLinearGradient(.2 * r, 0, 1.4 * r, 1.35 * r);
		gb.addColorStop(0, '#4a4c53'); gb.addColorStop(.4, '#2c2d32'); gb.addColorStop(1, '#121315');
		bowl(); g.fillStyle = gb; g.fill();
		g.save(); bowl(); g.clip();
		glow(g, r, 1.25 * r, r * 1.1, [210, 60, 14], .22 + .16 * full);        // dull red where the metal sits
		glow(g, r, 1.6 * r, r * 1.2, [255, 130, 40], .22);                     // the run's light from below
		const band = g.createLinearGradient(0, 0, 0, .6 * r);                   // temper colours under the rim
		band.addColorStop(0, 'rgba(90,100,160,.2)'); band.addColorStop(.35, 'rgba(165,120,60,.18)'); band.addColorStop(1, 'rgba(0,0,0,0)');
		g.fillStyle = band; g.fillRect(-.3 * r, 0, 2.4 * r, .6 * r);
		for (const st of look.soot) { g.fillStyle = `rgba(6,6,7,${st.a})`; g.fillRect(st.x * r, 0, st.w * r, st.l * r); }
		const hl = g.createLinearGradient(1.45 * r, 0, 1.95 * r, 0);             // soft light down the far flank
		hl.addColorStop(0, 'rgba(200,205,215,0)'); hl.addColorStop(.6, 'rgba(200,205,215,.14)'); hl.addColorStop(1, 'rgba(200,205,215,0)');
		g.fillStyle = hl; g.fillRect(1.45 * r, 0, .5 * r, 1.3 * r);
		g.restore();
		bowl(); g.strokeStyle = 'rgba(0,0,0,.35)'; g.lineWidth = Math.max(.5, r * .025); g.stroke();
		// the metal inside, with a skin of slag
		g.save(); g.beginPath(); g.ellipse(r, -.02 * r, .92 * r, .2 * r, 0, 0, PI2); g.clip();
		const gi = g.createRadialGradient(r * .55, 0, 0, r, 0, r);
		gi.addColorStop(0, rgba(heat(.8 + .2 * full))); gi.addColorStop(1, rgba(heat(.45 + .25 * full)));
		g.fillStyle = gi; g.fillRect(0, -.25 * r, 2 * r, .5 * r);
		for (const p of look.slag) { polyPath(g, p.x * r, p.y * r, p.pts.map(([a, b]) => [a * r, b * r * .45])); g.fillStyle = 'rgba(50,42,38,.82)'; g.fill(); }
		g.restore();
		// rolled rim: iron, lit by the metal inside and the light above
		g.beginPath(); g.ellipse(r, -.02 * r, .95 * r, .22 * r, 0, 0, PI2); g.strokeStyle = '#2a2b30'; g.lineWidth = r * .13; g.stroke();
		g.beginPath(); g.ellipse(r, -.04 * r, .95 * r, .22 * r, 0, Math.PI * 1.1, Math.PI * 1.9); g.strokeStyle = 'rgba(195,200,210,.25)'; g.lineWidth = r * .03; g.stroke();
		g.beginPath(); g.ellipse(r, 0, .88 * r, .18 * r, 0, Math.PI * .08, Math.PI * .92); g.strokeStyle = rgba(heat(.9), .45); g.lineWidth = r * .035; g.stroke();
		// molten metal spilling over the spout
		g.strokeStyle = rgba(heat(.85), .95); g.lineWidth = r * .1;
		g.beginPath(); g.moveTo(.12 * r, -.02 * r); g.quadraticCurveTo(-.05 * r, -.07 * r, -.22 * r, -.05 * r); g.stroke();
		glow(g, -.1 * r, -.02 * r, r * .6, [255, 150, 40], .5);
		glow(g, r * .9, -.1 * r, r * .9, [255, 150, 50], .16 + .14 * full);
		g.restore();
	}

	CONCEPTS.push({
		group: 'Smelting', id: 'smelt-b3', letter: 'B3', name: 'Ladle pour, molten',
		desc: 'A forged-iron hand ladle, sooty and heat-tinted, tips at the left and pours a thick stream; the molten steel heaps, slumps and creeps along the bar, crusting as it cools, rising until it fills the bar',
		spell: 'Smelt Iron', dur: [3, 3.8], padTop: 2.4, padX: 2, flash: [255, 170, 70],
		init(s) {
			s.tilt = wobble(1.2); s.ph = rand(0, 6.3);
			s.look = makeLadleLook();
			initMelt(s);
		},
		draw(g, s) {
			const W = s.W, H = s.H, r = H * .56;
			// the ladle stays over the left end, tipping further as it empties, then rights itself
			const back = s.done ? easeOut(clamp(s.doneT / .6)) : 0;
			const lx = H * .28, ly = -H * .45 - back * H * .3;
			const tilt = lerp(.45 + s.p * .5 + .04 * s.tilt(s.t), .05, back);
			const tp = tip(lx, ly, r, tilt, -1);
			const pour = clamp(tp[0] + H * .12, H * .3, W * .5);
			s.L = { lx, ly, r, tilt, tip: tp, pour, full: 1 - s.p * .85 };
			drawMeltRun(g, s, pour, back, () => {
				const x = r * rand(.3, 1.7), y = -.05 * r, c = Math.cos(tilt), sn = Math.sin(tilt);
				return [lx - (x * c + y * sn), ly - x * sn + y * c];
			});
		},
		over(g, s) {
			if (!s.L) return;
			const L = s.L, H = s.H;
			drawRealLadle(g, s.look, L.lx, L.ly, L.r, L.tilt, -1, L.full);
			if (s.casting) drawHeavyStream(g, L.tip[0], L.tip[1], L.pour, L.landY, H * (.15 - .05 * s.p), s.t, s.ph);
		},
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
