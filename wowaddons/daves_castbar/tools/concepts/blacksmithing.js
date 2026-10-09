// Blacksmithing concepts: the bar is hot metal, a forge hammer strikes it, steam comes off.
(() => {
	// iron heat colours: cold iron -> dull red -> orange -> yellow -> white
	const HEAT = [[0, [42, 34, 32]], [.22, [104, 20, 10]], [.45, [190, 46, 12]], [.66, [245, 118, 28]], [.85, [255, 196, 84]], [1.05, [255, 246, 214]], [1.3, [255, 255, 250]]];
	function heatCol(v) {
		if (v <= HEAT[0][0]) return HEAT[0][1];
		for (let i = 1; i < HEAT.length; i++) if (v <= HEAT[i][0]) {
			const [a, ca] = HEAT[i - 1], [b, cb] = HEAT[i];
			return mix(ca, cb, (v - a) / (b - a));
		}
		return HEAT[HEAT.length - 1][1];
	}
	const STEAM = [226, 226, 232];
	const SPARKS = [[255, 226, 130], [255, 172, 60], [255, 250, 210], [255, 130, 40]];

	// ---- the forge hammer. (px, py) is the grip end; the head sits L along the handle.
	// rot 0 = handle level, striking face down; rot < 0 lifts the head.
	const hammerLen = H => 1.45 * H;
	const hammerFace = H => .58 * .9 * H;           // grip-line to striking face
	function drawHammer(g, px, py, rot, H, glow = 0, alpha = 1, dir = 1) {
		const L = hammerLen(H), hw = .54 * H, hh = .9 * H, th = .15 * H, lw = Math.max(1, H * .035);
		g.save(); g.globalAlpha = alpha; g.translate(px, py); g.scale(dir, 1); g.rotate(rot);
		// handle: ash wood, a little fatter at the grip
		let gr = g.createLinearGradient(0, -th, 0, th);
		gr.addColorStop(0, '#b98549'); gr.addColorStop(.45, '#85562a'); gr.addColorStop(1, '#4b2e14');
		g.fillStyle = gr; g.beginPath();
		g.moveTo(-.2 * H, -th * .62); g.lineTo(L, -th * .42); g.lineTo(L, th * .42); g.lineTo(-.2 * H, th * .62);
		g.quadraticCurveTo(-.3 * H, 0, -.2 * H, -th * .62); g.closePath(); g.fill();
		g.strokeStyle = 'rgba(22,12,4,.85)'; g.lineWidth = lw; g.stroke();
		// leather grip wrap
		g.save(); g.clip();
		for (let i = 0; i < 6; i++) {
			const x = -.3 * H + i * .11 * H;
			g.fillStyle = i % 2 ? '#2e1b0e' : '#4a2c17'; g.beginPath();
			g.moveTo(x, -th); g.lineTo(x + .11 * H, -th); g.lineTo(x + .08 * H, th); g.lineTo(x - .03 * H, th); g.fill();
		}
		g.restore();
		// head: peen on top, flared striking face below
		const x0 = L - hw / 2, y0 = -.42 * hh, y1 = .58 * hh;
		const pts = [[.1, 0], [.9, 0], [1, .07], [1, .84], [1.07, .92], [1.07, 1], [-.07, 1], [-.07, .92], [0, .84], [0, .07]];
		g.beginPath();
		pts.forEach(([u, v], i) => { const x = x0 + u * hw, y = y0 + v * (y1 - y0); i ? g.lineTo(x, y) : g.moveTo(x, y); });
		g.closePath();
		gr = g.createLinearGradient(x0, 0, x0 + hw, 0);
		gr.addColorStop(0, '#2f3238'); gr.addColorStop(.35, '#7d838d'); gr.addColorStop(.55, '#9aa0aa'); gr.addColorStop(1, '#3a3d44');
		g.fillStyle = gr; g.fill();
		g.save(); g.clip();
		// polished face band, and the orange glow reflected from the hot metal below
		g.fillStyle = 'rgba(200,206,216,.55)'; g.fillRect(x0 - hw * .1, y1 - (y1 - y0) * .08, hw * 1.2, (y1 - y0) * .08);
		if (glow > 0) {
			gr = g.createLinearGradient(0, y1, 0, y0);
			gr.addColorStop(0, `rgba(255,140,40,${.75 * glow})`); gr.addColorStop(.5, `rgba(255,90,20,${.15 * glow})`); gr.addColorStop(1, 'rgba(255,90,20,0)');
			g.fillStyle = gr; g.fillRect(x0 - hw * .1, y0, hw * 1.2, y1 - y0);
		}
		// the eye the handle passes through, and a lit left edge
		g.fillStyle = 'rgba(0,0,0,.28)'; g.fillRect(x0 - hw * .1, -th * .75, hw * 1.2, th * 1.5);
		g.fillStyle = 'rgba(220,226,236,.35)'; g.fillRect(x0, y0, Math.max(1, hw * .07), y1 - y0);
		// wedge where the handle comes through the top
		g.fillStyle = 'rgba(30,20,10,.7)'; g.fillRect(L - th * .45, y0, th * .9, (y1 - y0) * .1);
		g.restore();
		g.strokeStyle = 'rgba(10,10,14,.9)'; g.lineWidth = lw; g.stroke();
		g.restore();
	}

	// Hammer rhythm. u is the phase in a strike cycle (0 = impact): bounce, rest, slow raise, fast drop.
	const MAXLIFT = .95;
	function lift(u) {
		if (u < .12) return -.13 * Math.sin(Math.PI * u / .12);          // small bounce back up
		if (u < .26) return 0;
		if (u < .8) return -MAXLIFT * easeOut((u - .26) / .54);
		return -MAXLIFT * (1 - easeIn((u - .8) / .2));
	}
	// advance a hammer's clock; returns true on the frame it lands
	function stepHammer(h, dt, period) {
		h.u += dt / period;
		if (h.u >= 1) { h.u -= 1; return true; }
		return false;
	}
	function placeHammer(g, s, x, h, glow, alpha) {
		const H = s.H;
		drawHammer(g, x - hammerLen(H), -hammerFace(H), lift(h.u), H, glow, alpha);
	}

	function strikeFX(s, x, heat, big = 1) {
		const H = s.H, k = H / 30;
		const n = Math.round((10 + 10 * heat) * big);
		for (let i = 0; i < n; i++) s.parts.emit({
			x: x + rand(-.2, .2) * H, y: rand(-.05, .1) * H, vx: rand(-6, 6) * H, vy: rand(-8, -1.5) * H, ay: 16 * H, drag: .6,
			size: rand(.7, 1.5) * k, life: rand(.25, .65), kind: 'spark', color: pick(SPARKS) });
		for (let i = 0; i < 5 * big; i++) s.parts.emit({
			x: x + rand(-.45, .45) * H, y: rand(-.15, .25) * H, vx: rand(-1, 1) * H, vy: rand(-1.8, -.7) * H, drag: 1.6,
			size: rand(.18, .3) * H, grow: rand(.7, 1.1) * H, life: rand(.8, 1.4), kind: 'smoke', color: STEAM, alpha: .55 });
		s.flashes.push({ x, age: 0 });
	}
	function steamWisps(s, x0, x1, rate, alpha) {
		const H = s.H;
		s.steamAcc = (s.steamAcc || 0) + rate * s.dt;
		while (s.steamAcc >= 1 && x1 > x0 + 2) {
			s.steamAcc -= 1;
			s.parts.emit({ x: rand(x0, x1), y: rand(-.05, .15) * H, vx: rand(-.25, .25) * H + s.wind * H, vy: rand(-1.3, -.6) * H, drag: .4,
				size: rand(.1, .18) * H, grow: rand(.45, .75) * H, life: rand(1, 1.9), kind: 'smoke', color: STEAM, alpha });
		}
	}
	function drawFlashes(g, s) {
		const H = s.H;
		g.globalCompositeOperation = 'lighter';
		for (const f of s.flashes) {
			f.age += s.dt;
			const a = clamp(1 - f.age / .18), r = H * (.5 + 1.1 * easeOut(f.age / .18));
			if (a <= 0) continue;
			const gr = g.createRadialGradient(f.x, 0, 0, f.x, 0, r);
			gr.addColorStop(0, `rgba(255,250,220,${.95 * a})`); gr.addColorStop(.35, `rgba(255,190,90,${.5 * a})`); gr.addColorStop(1, 'rgba(255,120,30,0)');
			g.fillStyle = gr; g.beginPath(); g.ellipse(f.x, 0, r * 1.3, r * .8, 0, 0, 6.283); g.fill();
		}
		g.globalCompositeOperation = 'source-over';
		s.flashes = s.flashes.filter(f => f.age < .2);
	}

	// Hot metal: strips coloured by heatAt(x); rounded shading so it reads as a bar of iron, scale flecks on the cooler parts.
	function drawMetal(g, s, x0, x1, heatAt, flecks) {
		const H = s.H, step = 2;
		for (let x = x0; x < x1; x += step) {
			g.fillStyle = rgba(heatCol(heatAt(x + 1)));
			g.fillRect(x, 0, Math.min(step + .5, x1 - x), H);
		}
		if (flecks) for (const f of flecks) {
			if (f.x < x0 || f.x > x1) continue;
			const h = heatAt(f.x), a = f.a * clamp(1.15 - h);
			if (a <= .02) continue;
			g.fillStyle = `rgba(28,10,6,${a})`; g.beginPath(); g.ellipse(f.x, f.y * H, f.r * H, f.r * H * .6, f.rot, 0, 6.283); g.fill();
		}
		const gr = g.createLinearGradient(0, 0, 0, H);
		gr.addColorStop(0, 'rgba(255,255,255,.16)'); gr.addColorStop(.18, 'rgba(255,255,255,0)');
		gr.addColorStop(.7, 'rgba(0,0,0,.08)'); gr.addColorStop(1, 'rgba(0,0,0,.5)');
		g.fillStyle = gr; g.fillRect(x0, 0, x1 - x0, H);
	}
	// soft glow around the hot part, spilling past the bar
	function bloom(g, s, x0, x1, heat) {
		if (x1 - x0 < 8 || heat < .2) return;
		const c = heatCol(Math.min(heat, .8));
		g.save(); g.shadowColor = rgba(c, clamp((heat - .2) * .9)); g.shadowBlur = s.H * (.5 + .7 * heat);
		g.fillStyle = rgba(c, .5); roundRectPath(g, x0 + 2, 2, x1 - x0 - 4, s.H - 4, s.H * .18); g.fill(); g.restore();
	}
	const clipBar = (g, s) => { roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip(); };
	function makeFlecks(s, n) {
		return Array.from({ length: n }, () => ({ x: rand(0, s.W), y: rand(.1, .9), r: rand(.03, .09), a: rand(.25, .6), rot: rand(0, 3) }));
	}
	function coldIron(g, s, x0) {
		// what is still to be heated: dull cold iron
		if (x0 >= s.W) return;
		g.fillStyle = 'rgba(58,56,60,.75)'; g.fillRect(x0, 0, s.W - x0, s.H);
		const gr = g.createLinearGradient(0, 0, 0, s.H);
		gr.addColorStop(0, 'rgba(170,175,185,.18)'); gr.addColorStop(.25, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,.45)');
		g.fillStyle = gr; g.fillRect(x0, 0, s.W - x0, s.H);
	}

	// ------------------------------------------------------------------ quench ending (shared by A and C)
	// On completion: a rolling cloud of steam bursts off the bar and the metal drops to tempered steel.
	function quenchStart(s, heat) {
		if (!s.done || s.quenched) return;
		s.quenched = true; s.lastHeat = heat;
		for (let i = 0; i < Math.round(s.W / s.H * 5); i++) s.parts.emit({
			x: rand(0, s.W), y: rand(-.1, .8) * s.H, vx: rand(-.6, .6) * s.H + s.wind * s.H, vy: rand(-2.2, -.6) * s.H, drag: 1.4,
			size: rand(.25, .45) * s.H, grow: rand(.9, 1.5) * s.H, life: rand(1, 1.6), kind: 'smoke', color: STEAM, alpha: .7 });
	}
	const quenchAmount = s => s.done ? easeOut(clamp(s.doneT / .35)) : 0;
	function temperedSteel(g, s, F, q) {
		if (q <= 0) return;
		g.globalAlpha = q;
		const gr = g.createLinearGradient(0, 0, s.W, 0);
		gr.addColorStop(0, '#6c7480'); gr.addColorStop(.35, '#8a8577'); gr.addColorStop(.55, '#9a7d4f'); gr.addColorStop(.75, '#5d5a86'); gr.addColorStop(1, '#4b6a92');
		g.fillStyle = gr; g.fillRect(0, 0, F, s.H);
		const sh = g.createLinearGradient(0, 0, 0, s.H);
		sh.addColorStop(0, 'rgba(255,255,255,.35)'); sh.addColorStop(.25, 'rgba(255,255,255,0)'); sh.addColorStop(1, 'rgba(0,0,0,.5)');
		g.fillStyle = sh; g.fillRect(0, 0, F, s.H);
		g.globalAlpha = 1;
	}

	// ------------------------------------------------------------------ A: red-hot billet
	CONCEPTS.push({
		group: 'Blacksmithing', id: 'smith-a', letter: 'A', name: 'Red-hot billet',
		desc: 'Iron glows hottest at the cast edge; the hammer strikes there in rhythm, sparks and a burst of steam each blow; it quenches in a cloud of steam',
		spell: 'Copper Chain Belt', padTop: 2.4, padX: 1.5, padBottom: .6, flash: [200, 225, 255],
		init(s) {
			s.hammer = { u: rand(.3, .6) }; s.period = rand(.62, .78); s.flashes = []; s.impacts = []; s.quenched = false;
			s.n = noise1(); s.wind = rand(-.3, .3); s.flecks = makeFlecks(s, Math.round(s.W / s.H * 9));
		},
		draw(g, s) {
			const H = s.H, F = s.fill, base = .2 + .4 * s.p;
			quenchStart(s, base + .2);
			const q = quenchAmount(s);
			for (const m of s.impacts) m.age += s.dt;
			s.impacts = s.impacts.filter(m => m.age < 2);
			const heatAt = x => {
				let h = base + .07 * s.n(x / (1.4 * H) + s.t * .25) + .4 * Math.exp(-Math.max(0, F - x) / (1.1 * H));
				for (const m of s.impacts) h += .45 * Math.exp(-m.age * 2.2) * Math.exp(-(((x - m.x) / (.7 * H)) ** 2));
				return h;
			};
			bloom(g, s, 0, F, s.done ? s.lastHeat * (1 - q) : base + .2);
			g.save(); clipBar(g, s);
			coldIron(g, s, F);
			if (q < 1) drawMetal(g, s, 0, F, heatAt, s.flecks);
			temperedSteel(g, s, F, q);
			g.restore();
			// hammer
			const hx = Math.max(.3 * H, F - .3 * H);
			if (s.casting && stepHammer(s.hammer, s.dt, s.period) && F > .2 * H) {
				s.impacts.push({ x: hx, age: 0 }); strikeFX(s, hx, base + .4);
			}
			if (!s.done) steamWisps(s, 0, F, (2 + 12 * s.p) * F / 300, .14 + .2 * s.p);
			s.parts.update(s.dt);
			s.parts.draw(g, q => q.kind === 'smoke');
			const ha = s.done ? clamp(1 - s.doneT * 3) : 1;
			if (ha > 0) placeHammer(g, s, hx, s.hammer, clamp(base + .3) * (1 - clamp(-lift(s.hammer.u) / MAXLIFT)), ha);
			s.parts.draw(g, q => q.kind !== 'smoke');
			drawFlashes(g, s);
		},
	});

	// ------------------------------------------------------------------ B: on the anvil
	function drawAnvil(g, s) {
		const H = s.H, cx = s.W * .56, fw = Math.min(s.W * .62, 4.4 * H), top = H, lw = Math.max(1, H * .035);
		const L = cx - fw / 2, R = cx + fw / 2;
		g.beginPath();
		g.moveTo(L - 1.5 * H, top);                                         // horn tip
		g.lineTo(R + .15 * H, top);                                         // face
		g.lineTo(R + .15 * H, top + .3 * H);                                // heel
		g.lineTo(R - .15 * fw, top + .38 * H);
		g.quadraticCurveTo(cx + .12 * fw, top + .5 * H, cx + .12 * fw, top + .78 * H);   // waist
		g.lineTo(cx + .3 * fw, top + 1.05 * H); g.lineTo(cx + .3 * fw, top + 1.18 * H);  // foot
		g.lineTo(cx - .3 * fw, top + 1.18 * H); g.lineTo(cx - .3 * fw, top + 1.05 * H);
		g.lineTo(cx - .12 * fw, top + .78 * H);
		g.quadraticCurveTo(cx - .12 * fw, top + .5 * H, L + .1 * fw, top + .38 * H);
		g.quadraticCurveTo(L - .4 * H, top + .36 * H, L - 1.5 * H, top);  // under the horn
		g.closePath();
		const gr = g.createLinearGradient(0, top, 0, top + 1.2 * H);
		gr.addColorStop(0, '#5d6068'); gr.addColorStop(.12, '#3a3c42'); gr.addColorStop(1, '#17181b');
		g.fillStyle = gr; g.fill();
		g.strokeStyle = 'rgba(0,0,0,.85)'; g.lineWidth = lw; g.stroke();
		// warm light from the hot bar on the anvil's face
		const hg = g.createLinearGradient(0, top, 0, top + .25 * H);
		hg.addColorStop(0, `rgba(255,120,40,${.12 + .25 * s.p})`); hg.addColorStop(1, 'rgba(255,120,40,0)');
		g.save(); g.clip(); g.fillStyle = hg; g.fillRect(L - 1.6 * H, top, fw + 2 * H, .5 * H); g.restore();
		// face edge highlight
		g.strokeStyle = 'rgba(190,195,205,.5)'; g.lineWidth = lw; g.beginPath(); g.moveTo(L - 1.3 * H, top + lw); g.lineTo(R + .1 * H, top + lw); g.stroke();
	}
	CONCEPTS.push({
		group: 'Blacksmithing', id: 'smith-b', letter: 'B', name: 'On the anvil',
		desc: 'The bar lies on an anvil; the hammer works along it, each blow leaves a glowing dent that cools; steam vents more as it heats',
		spell: 'Rough Bronze Leggings', padTop: 2.4, padX: 1.5, padBottom: 1.35, flash: [255, 210, 140],
		init(s) {
			s.hammer = { u: rand(.3, .6) }; s.period = rand(.72, .9); s.flashes = []; s.dents = []; s.vents = [];
			s.n = noise1(); s.wind = rand(-.2, .2); s.flecks = makeFlecks(s, Math.round(s.W / s.H * 7));
			s.hx = s.H * .5; s.from = s.hx; s.to = s.hx; s.ventNext = rand(.6, 1.6) * s.H;
		},
		draw(g, s) {
			const H = s.H, F = s.fill, base = .25 + .48 * s.p;
			drawAnvil(g, s);
			for (const d of s.dents) d.age += s.dt;
			const heatAt = x => {
				let h = base + .08 * s.n(x / (1.2 * H) + s.t * .2) + .2 * Math.exp(-Math.max(0, F - x) / (1.5 * H));
				for (const d of s.dents) h += .5 * Math.exp(-d.age * 1.1) * Math.exp(-(((x - d.x) / (.65 * H)) ** 2));
				return h;
			};
			bloom(g, s, 0, F, base + .1);
			g.save(); clipBar(g, s);
			coldIron(g, s, F);
			drawMetal(g, s, 0, F, heatAt, s.flecks);
			// dents: a bright core that cools, leaving a dark hollow with a lit rim
			for (const d of s.dents) {
				const glow = Math.exp(-d.age * 1.4), rx = .32 * H, ry = .26 * H;
				g.fillStyle = 'rgba(30,8,4,.38)'; g.beginPath(); g.ellipse(d.x, d.y, rx, ry, 0, Math.PI * 1.05, Math.PI * 1.95); g.ellipse(d.x, d.y + ry * .25, rx * .9, ry * .7, 0, Math.PI * 1.95, Math.PI * 1.05, true); g.fill();
				g.strokeStyle = 'rgba(255,230,180,.22)'; g.lineWidth = Math.max(1, H * .03); g.beginPath(); g.ellipse(d.x, d.y, rx, ry, 0, Math.PI * .1, Math.PI * .9); g.stroke();
				if (glow > .02) {
					g.globalCompositeOperation = 'lighter';
					const gr = g.createRadialGradient(d.x, d.y, 0, d.x, d.y, rx * 1.6);
					gr.addColorStop(0, rgba(heatCol(.75 + .5 * glow), .9 * glow)); gr.addColorStop(1, 'rgba(255,90,20,0)');
					g.fillStyle = gr; g.beginPath(); g.ellipse(d.x, d.y, rx * 1.6, ry * 1.5, 0, 0, 6.283); g.fill();
					g.globalCompositeOperation = 'source-over';
				}
			}
			g.restore();
			// hammer travels to a new spot while it is raised
			if (s.casting && stepHammer(s.hammer, s.dt, s.period)) {
				if (F > .3 * H) {
					s.dents.push({ x: s.hx, y: rand(.35, .65) * H, age: 0 }); strikeFX(s, s.hx, base + .3);
					if (s.dents.length > 14) s.dents.shift();
				}
				s.from = s.hx; s.to = F < 1.2 * H ? Math.max(.4 * H, F * .6) : rand(.5 * H, F - .3 * H);
			}
			const mv = clamp((s.hammer.u - .26) / .5);
			s.hx = lerp(s.from, s.to, mv * mv * (3 - 2 * mv));
			// steam vents open along the top of the hot part
			while (s.casting && F > s.ventNext) { s.vents.push({ x: s.ventNext, ph: rand(0, 6.283), f: rand(1.2, 2.4) }); s.ventNext += rand(.9, 2.2) * H; }
			for (const v of s.vents) {
				const on = Math.sin(s.t * v.f + v.ph) > .55 - .9 * s.p;
				if (on && Math.random() < s.dt * (8 + 18 * s.p)) s.parts.emit({
					x: v.x + rand(-.08, .08) * H, y: 0, vx: rand(-.15, .15) * H + s.wind * H, vy: rand(-2.4, -1.5) * H, drag: 1.1,
					size: .08 * H, grow: rand(.5, .8) * H, life: rand(.7, 1.3), kind: 'smoke', color: STEAM, alpha: .3 + .25 * s.p });
			}
			steamWisps(s, 0, F, (1 + 4 * s.p) * F / 300, .12 + .12 * s.p);
			s.parts.update(s.dt);
			s.parts.draw(g, q => q.kind === 'smoke');
			const ha = s.done ? clamp(1 - s.doneT * 3) : 1;
			if (ha > 0) placeHammer(g, s, s.hx, s.hammer, clamp(base + .3) * (1 - clamp(-lift(s.hammer.u) / MAXLIFT)), ha);
			s.parts.draw(g, q => q.kind !== 'smoke');
			drawFlashes(g, s);
		},
	});

	// ------------------------------------------------------------------ C: heat build-up and quench
	CONCEPTS.push({
		group: 'Blacksmithing', id: 'smith-c', letter: 'C', name: 'Heat and quench',
		desc: 'The whole bar builds from dull red to white-hot under heat haze; blows quicken and send bright ripples along it; it quenches in a cloud of steam',
		spell: 'Thorium Greatsword', padTop: 2.4, padX: 1.5, padBottom: .6, flash: [200, 225, 255],
		init(s) {
			s.hammer = { u: rand(.3, .6) }; s.flashes = []; s.waves = []; s.quenched = false;
			s.n = noise1(); s.n2 = noise1(); s.wind = rand(-.25, .25); s.flecks = makeFlecks(s, Math.round(s.W / s.H * 6));
			s.hx = s.H * .6; s.from = s.hx; s.to = s.hx; s.lastHeat = .3;
		},
		draw(g, s) {
			const H = s.H, F = s.fill;
			const base = .26 + .82 * Math.pow(s.p, 1.25);
			for (const w of s.waves) w.age += s.dt;
			s.waves = s.waves.filter(w => w.age < 1.6);
			const heatAt = x => {
				let h = base + .09 * s.n(x / (1.6 * H) + s.t * .35) + .05 * s.n2(x / (.5 * H) - s.t * .8);
				for (const w of s.waves) {
					const d = Math.abs(x - w.x), front = w.age * 7 * H;
					h += Math.exp(-w.age * 2.2) * (.35 * Math.exp(-(((d - front) / (.6 * H)) ** 2)) + .4 * Math.exp(-((d / (.6 * H)) ** 2)));
				}
				return h;
			};
			// quench: on completion the colour drops to tempered steel under a rolling cloud of steam
			if (s.done && !s.quenched) {
				s.quenched = true; s.lastHeat = base;
				for (let i = 0; i < Math.round(s.W / H * 5); i++) s.parts.emit({
					x: rand(0, s.W), y: rand(-.1, .8) * H, vx: rand(-.6, .6) * H + s.wind * H, vy: rand(-2.2, -.6) * H, drag: 1.4,
					size: rand(.25, .45) * H, grow: rand(.9, 1.5) * H, life: rand(1, 1.6), kind: 'smoke', color: STEAM, alpha: .7 });
			}
			const q = s.done ? easeOut(clamp(s.doneT / .35)) : 0;
			if (!s.done) bloom(g, s, 0, F, base);
			else bloom(g, s, 0, F, s.lastHeat * (1 - q));
			g.save(); clipBar(g, s);
			coldIron(g, s, F);
			if (q < 1) { g.globalAlpha = 1; drawMetal(g, s, 0, F, heatAt, s.flecks); }
			if (q > 0) {
				// tempered steel: grey with straw-to-blue temper colours
				g.globalAlpha = q;
				const gr = g.createLinearGradient(0, 0, s.W, 0);
				gr.addColorStop(0, '#6c7480'); gr.addColorStop(.35, '#8a8577'); gr.addColorStop(.55, '#9a7d4f'); gr.addColorStop(.75, '#5d5a86'); gr.addColorStop(1, '#4b6a92');
				g.fillStyle = gr; g.fillRect(0, 0, F, H);
				const sh = g.createLinearGradient(0, 0, 0, H);
				sh.addColorStop(0, 'rgba(255,255,255,.35)'); sh.addColorStop(.25, 'rgba(255,255,255,0)'); sh.addColorStop(1, 'rgba(0,0,0,.5)');
				g.fillStyle = sh; g.fillRect(0, 0, F, H);
				g.globalAlpha = 1;
			}
			g.restore();
			// heat haze: faint shimmering bands rising off the bar, stronger as it heats
			if (!s.done && F > 4) {
				g.globalCompositeOperation = 'lighter';
				for (let k = 0; k < 4; k++) {
					const y0 = -(.12 + k * .22) * H, a = .3 * clamp(base - .25) * (1 - k / 4.5);
					g.strokeStyle = rgba(heatCol(.7), a); g.lineWidth = Math.max(1, H * (.1 - k * .015));
					g.beginPath();
					for (let x = 0; x <= F; x += 4) {
						const y = y0 + Math.sin(x / (.55 * H) + s.t * (3 + k) + k * 1.7) * .06 * H + s.n2(x / H + s.t * 1.5 + k * 9) * .07 * H;
						x ? g.lineTo(x, y) : g.moveTo(x, y);
					}
					g.stroke();
				}
				g.globalCompositeOperation = 'source-over';
			}
			// blows quicken as the cast goes on; the hammer works its way along the hot part
			const period = lerp(.85, .4, s.p);
			if (s.casting && stepHammer(s.hammer, s.dt, period)) {
				if (F > .3 * H) { s.waves.push({ x: s.hx, age: 0 }); strikeFX(s, s.hx, base, .8); }
				let nx = s.hx + rand(.7, 1.3) * H;
				if (nx > F - .3 * H) nx = Math.min(F - .3 * H, rand(.4, 1) * H);
				s.from = s.hx; s.to = Math.max(.4 * H, nx);
			}
			const mv = clamp((s.hammer.u - .26) / .5);
			s.hx = lerp(s.from, s.to, mv * mv * (3 - 2 * mv));
			if (!s.done) steamWisps(s, 0, F, (1 + 8 * s.p) * F / 300, .1 + .15 * s.p);
			s.parts.update(s.dt);
			s.parts.draw(g, p => p.kind === 'smoke');
			const ha = s.done ? clamp(1 - s.doneT * 4) : 1;
			if (ha > 0) placeHammer(g, s, s.hx, s.hammer, clamp(base + .2) * (1 - clamp(-lift(s.hammer.u) / MAXLIFT)), ha);
			s.parts.draw(g, p => p.kind !== 'smoke');
			drawFlashes(g, s);
		},
	});
})();
