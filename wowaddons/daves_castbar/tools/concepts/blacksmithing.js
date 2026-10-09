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

	// ------------------------------------------------------------------ A: red-hot billet (final)
	CONCEPTS.push({
		group: 'Blacksmithing', id: 'smith-a', letter: 'A', name: 'Red-hot billet',
		desc: 'Iron glows hottest at the cast edge; a Warcraft hammer painted like the skinning knife (brushed steel, brass or steel bands, wood or antler haft), lit by the forge, strikes there in rhythm, sparks and a burst of steam each blow; it quenches in a cloud of steam',
		spell: 'Copper Chain Belt', padTop: 2.4, padX: 1.5, padBottom: .6, flash: [200, 225, 255],
		init(s) {
			s.hammer = { u: rand(.3, .6) }; s.period = rand(.62, .78); s.flashes = []; s.impacts = []; s.quenched = false;
			s.n = noise1(); s.wind = rand(-.3, .3); s.flecks = makeFlecks(s, Math.round(s.W / s.H * 9));
			s.look = makeHammerLook();
			s.hx = s.H * .3;
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
			s.hx = Math.max(.3 * H, F - .3 * H);
			if (s.casting && stepHammer(s.hammer, s.dt, s.period) && F > .2 * H) {
				s.impacts.push({ x: s.hx, age: 0 }); strikeFX(s, s.hx, base + .4);
			}
			if (!s.done) steamWisps(s, 0, F, (2 + 12 * s.p) * F / 300, .14 + .2 * s.p);
			s.parts.update(s.dt);
			s.parts.draw(g, q => q.kind === 'smoke');
			s.base = base;
		},
		over(g, s) {
			const ha = s.done ? clamp(1 - s.doneT * 3) : 1;
			s.look.glint = .5 + .5 * Math.sin(s.t * 2.3);   // the glint slides across the head as it swings
			if (ha > 0) placeWowHammer(g, s, s.hx, s.look, clamp(s.base + .3) * (1 - clamp(-lift(s.hammer.u) / MAXLIFT)), ha, .78, drawKnifeHammer);
			s.parts.draw(g, q => q.kind !== 'smoke');
			drawFlashes(g, s);
		},
	});

	// ------------------------------------------------------------------ A2: red-hot billet, forged
	// A deeper heat ramp: near-black maroon -> blood red -> crimson -> orange -> yellow-white.
	const DEEP = [[0, [22, 5, 6]], [.18, [58, 6, 8]], [.34, [112, 8, 14]], [.5, [170, 18, 20]], [.64, [222, 58, 18]],
		[.76, [250, 120, 26]], [.88, [255, 184, 64]], [1, [255, 228, 140]], [1.2, [255, 250, 226]]];
	function deepCol(v) {
		if (v <= DEEP[0][0]) return DEEP[0][1];
		for (let i = 1; i < DEEP.length; i++) if (v <= DEEP[i][0]) {
			const [a, ca] = DEEP[i - 1], [b, cb] = DEEP[i];
			return mix(ca, cb, (v - a) / (b - a));
		}
		return DEEP[DEEP.length - 1][1];
	}

	// A stylised Warcraft forge hammer: oversized bevelled block head, metal trim bands with rivets,
	// a spiked or flared back, thick leather-wrapped haft and a trimmed pommel. Same grip/face geometry
	// as drawHammer, so placeHammer's anchor still puts the face on the bar.
	const TRIMS = [
		{ hi: [255, 226, 120], mid: [214, 156, 46], lo: [118, 70, 16] },     // gold
		{ hi: [244, 190, 128], mid: [182, 108, 52], lo: [92, 46, 18] },      // bronze
		{ hi: [214, 236, 255], mid: [128, 160, 196], lo: [52, 66, 92] },     // thorium blue-steel
	];
	const GEMS = [[90, 220, 255], [255, 70, 60], [120, 255, 120], [200, 110, 255]];
	function drawWowHammer(g, px, py, rot, H, look, glow = 0, alpha = 1) {
		const L = hammerLen(H), lw = Math.max(1.2, H * .05), ol = 'rgba(14,8,6,.95)';
		const T = look.trim, tc = (c, a = 1) => rgba(c, a);
		g.save(); g.globalAlpha = alpha; g.translate(px, py); g.rotate(rot);
		g.lineJoin = 'round';

		// haft: dark stained wood, thick, slightly tapered toward the head
		const th = .2 * H;
		let gr = g.createLinearGradient(0, -th, 0, th);
		gr.addColorStop(0, '#9a5e2c'); gr.addColorStop(.4, '#6a3818'); gr.addColorStop(1, '#2c1408');
		g.fillStyle = gr; g.beginPath();
		g.moveTo(-.12 * H, -th * .6); g.lineTo(L, -th * .45); g.lineTo(L, th * .45); g.lineTo(-.12 * H, th * .6); g.closePath();
		g.fill(); g.strokeStyle = ol; g.lineWidth = lw; g.stroke();
		// leather wrap: crossing bands with a painted highlight
		g.save(); g.beginPath(); g.rect(-.12 * H, -th, .62 * H, th * 2); g.clip();
		for (let i = 0; i < 7; i++) {
			const x = -.16 * H + i * .095 * H;
			g.fillStyle = i % 2 ? '#3b2112' : '#5a3419'; g.beginPath();
			g.moveTo(x, -th); g.lineTo(x + .095 * H, -th); g.lineTo(x + .05 * H, th); g.lineTo(x - .045 * H, th); g.closePath(); g.fill();
			g.strokeStyle = 'rgba(255,214,160,.18)'; g.lineWidth = Math.max(.8, H * .015);
			g.beginPath(); g.moveTo(x + .02 * H, -th * .55); g.lineTo(x + .07 * H, -th * .55); g.stroke();
		}
		g.restore();
		// trim collar where the wrap ends
		const collar = (x, w) => {
			gr = g.createLinearGradient(0, -th * .8, 0, th * .8);
			gr.addColorStop(0, tc(T.hi)); gr.addColorStop(.45, tc(T.mid)); gr.addColorStop(1, tc(T.lo));
			g.fillStyle = gr; g.beginPath(); roundRectPath(g, x, -th * .78, w, th * 1.56, th * .25); g.fill();
			g.strokeStyle = ol; g.lineWidth = lw * .8; g.stroke();
		};
		collar(.48 * H, .1 * H);
		// pommel: a trimmed knob with a gem
		const pr = .17 * H;
		gr = g.createRadialGradient(-.2 * H - pr * .3, -pr * .4, pr * .1, -.2 * H, 0, pr);
		gr.addColorStop(0, tc(T.hi)); gr.addColorStop(.55, tc(T.mid)); gr.addColorStop(1, tc(T.lo));
		g.fillStyle = gr; g.beginPath();
		for (let i = 0; i < 6; i++) { const a = i / 6 * 6.283 + .26, r = i % 2 ? pr : pr * .86; g.lineTo(-.2 * H + Math.cos(a) * r, Math.sin(a) * r); }
		g.closePath(); g.fill(); g.strokeStyle = ol; g.lineWidth = lw * .8; g.stroke();
		g.fillStyle = tc(look.gem); g.beginPath(); g.arc(-.2 * H, 0, pr * .42, 0, 6.283); g.fill();
		g.fillStyle = 'rgba(255,255,255,.75)'; g.beginPath(); g.arc(-.2 * H - pr * .14, -pr * .15, pr * .14, 0, 6.283); g.fill();
		g.strokeStyle = ol; g.lineWidth = lw * .6; g.beginPath(); g.arc(-.2 * H, 0, pr * .42, 0, 6.283); g.stroke();

		// head: a big block, face at hammerFace(H) below the haft line, back rising above it
		const hw = .78 * H, cx = L, x0 = cx - hw / 2, x1 = cx + hw / 2;
		const yFace = hammerFace(H), yTop = -.5 * H, bev = .1 * H;
		// back: a spike (or a flared double claw) above the block
		g.fillStyle = '#4a4e58'; g.beginPath();
		if (look.spike) {
			g.moveTo(cx - hw * .26, yTop + 2); g.lineTo(cx - hw * .06, yTop - .42 * H); g.lineTo(cx + hw * .06, yTop - .42 * H); g.lineTo(cx + hw * .26, yTop + 2);
		} else {
			g.moveTo(cx - hw * .42, yTop + 2); g.quadraticCurveTo(cx - hw * .6, yTop - .3 * H, cx - hw * .34, yTop - .38 * H);
			g.lineTo(cx - hw * .14, yTop + 2); g.lineTo(cx + hw * .14, yTop + 2); g.lineTo(cx + hw * .34, yTop - .38 * H);
			g.quadraticCurveTo(cx + hw * .6, yTop - .3 * H, cx + hw * .42, yTop + 2);
		}
		g.closePath();
		gr = g.createLinearGradient(x0, 0, x1, 0);
		gr.addColorStop(0, '#2c2f37'); gr.addColorStop(.4, '#8a909c'); gr.addColorStop(1, '#30333b');
		g.fillStyle = gr; g.fill(); g.strokeStyle = ol; g.lineWidth = lw; g.stroke();
		// block body with painted bevels: lit top-left facets, shadowed bottom-right, cool-to-warm shift
		const body = () => {
			g.beginPath();
			g.moveTo(x0 + bev, yTop); g.lineTo(x1 - bev, yTop); g.lineTo(x1, yTop + bev); g.lineTo(x1, yFace - bev);
			g.lineTo(x1 - bev, yFace); g.lineTo(x0 + bev, yFace); g.lineTo(x0, yFace - bev); g.lineTo(x0, yTop + bev); g.closePath();
		};
		body();
		gr = g.createLinearGradient(x0, yTop, x1, yFace);
		gr.addColorStop(0, '#a8b2c4'); gr.addColorStop(.35, '#6d7484'); gr.addColorStop(.7, '#474b56'); gr.addColorStop(1, '#2a2b31');
		g.fillStyle = gr; g.fill();
		g.save(); body(); g.clip();
		// inner panel, a step in from the bevel
		g.fillStyle = 'rgba(20,22,28,.28)'; g.fillRect(x0 + bev * 1.2, yTop + bev * 1.2, hw - bev * 2.4, yFace - yTop - bev * 2.4);
		g.fillStyle = 'rgba(210,222,240,.5)'; g.fillRect(x0, yTop, hw, Math.max(1, H * .05));                 // lit top facet
		g.fillStyle = 'rgba(200,214,236,.35)'; g.fillRect(x0, yTop, Math.max(1, H * .06), yFace - yTop);      // lit left facet
		g.fillStyle = 'rgba(0,0,0,.35)'; g.fillRect(x1 - H * .07, yTop, H * .07, yFace - yTop);               // dark right facet
		// striking face: a polished band at the bottom, lit orange by the hot metal
		g.fillStyle = 'rgba(214,222,236,.6)'; g.fillRect(x0, yFace - H * .07, hw, H * .07);
		if (glow > 0) {
			gr = g.createLinearGradient(0, yFace, 0, yTop);
			gr.addColorStop(0, `rgba(255,120,40,${.85 * glow})`); gr.addColorStop(.45, `rgba(255,70,20,${.2 * glow})`); gr.addColorStop(1, 'rgba(255,70,20,0)');
			g.fillStyle = gr; g.fillRect(x0, yTop, hw, yFace - yTop);
		}
		g.restore();
		body(); g.strokeStyle = ol; g.lineWidth = lw; g.stroke();
		// trim bands across the head, top and bottom, with rivets
		for (const [yc, hgt] of [[yTop + (yFace - yTop) * .2, .13 * H], [yTop + (yFace - yTop) * .72, .13 * H]]) {
			gr = g.createLinearGradient(0, yc - hgt / 2, 0, yc + hgt / 2);
			gr.addColorStop(0, tc(T.hi)); gr.addColorStop(.5, tc(T.mid)); gr.addColorStop(1, tc(T.lo));
			g.fillStyle = gr; g.fillRect(x0 - H * .03, yc - hgt / 2, hw + H * .06, hgt);
			g.strokeStyle = ol; g.lineWidth = lw * .8; g.strokeRect(x0 - H * .03, yc - hgt / 2, hw + H * .06, hgt);
			for (let i = 0; i < 3; i++) {
				const rx = x0 + hw * (.2 + .3 * i), rr = hgt * .24;
				g.fillStyle = tc(T.lo); g.beginPath(); g.arc(rx, yc, rr, 0, 6.283); g.fill();
				g.fillStyle = tc(T.hi, .9); g.beginPath(); g.arc(rx - rr * .3, yc - rr * .3, rr * .45, 0, 6.283); g.fill();
			}
		}
		// rune plate on the side of the head
		g.fillStyle = tc(T.mid, .9); g.beginPath();
		const ry = (yTop + yFace) / 2 - .02 * H, rs = .14 * H;
		g.moveTo(cx, ry - rs); g.lineTo(cx + rs * .8, ry); g.lineTo(cx, ry + rs); g.lineTo(cx - rs * .8, ry); g.closePath(); g.fill();
		g.strokeStyle = ol; g.lineWidth = lw * .7; g.stroke();
		g.fillStyle = tc(look.gem, .9); g.beginPath(); g.arc(cx, ry, rs * .35, 0, 6.283); g.fill();
		g.restore();
	}
	// The Warcraft hammer at a scale, its striking face landing on the bar's top edge at x.
	function placeWowHammer(g, s, x, look, glow, alpha, scale = 1, draw = drawWowHammer) {
		const H = s.H;
		g.save(); g.translate(x, 0); g.scale(scale, scale);
		draw(g, -hammerLen(H), -hammerFace(H), lift(s.hammer.u), H, look, glow, alpha);
		g.restore();
	}

	// The same Warcraft hammer painted like in-game item art rather than a cartoon: no heavy outline,
	// forged steel with soft shading, a worn and scratched face, aged iron bands with a few small
	// rivets, a dark worn leather wrap over grained wood, and a plain iron pommel. The face side (toward
	// the bar, +y) catches the forge's orange light; the back gets a cool rim light.
	function drawRealHammer(g, px, py, rot, H, look, glow = 0, alpha = 1) {
		const L = hammerLen(H), edge = 'rgba(10,8,8,.45)', ew = Math.max(.6, H * .018);
		const warm = a => `rgba(255,130,50,${a})`, cool = a => `rgba(170,200,235,${a})`;
		const sd = look.seed;
		g.save(); g.globalAlpha = alpha; g.translate(px, py); g.rotate(rot);
		g.lineJoin = 'round'; g.lineCap = 'round';

		// haft: grained dark wood, tapering a little toward the head
		const th = .17 * H;
		const haft = () => { g.beginPath(); g.moveTo(-.12 * H, -th * .62); g.lineTo(L, -th * .46); g.lineTo(L, th * .46); g.lineTo(-.12 * H, th * .62); g.closePath(); };
		haft();
		let gr = g.createLinearGradient(0, -th, 0, th);
		gr.addColorStop(0, '#6e4a2c'); gr.addColorStop(.35, '#4e321c'); gr.addColorStop(.8, '#2a1a0e'); gr.addColorStop(1, '#1a0f08');
		g.fillStyle = gr; g.fill();
		g.save(); haft(); g.clip();
		g.strokeStyle = 'rgba(20,10,4,.45)'; g.lineWidth = Math.max(.5, H * .01);
		for (let i = 0; i < 5; i++) {   // wood grain
			const y = -th * .5 + i * th * .25;
			g.beginPath(); g.moveTo(.4 * H, y);
			for (let x = .4 * H; x <= L; x += .1 * H) g.lineTo(x, y + Math.sin(x / (.3 * H) + sd[i % sd.length] * 6) * th * .06);
			g.stroke();
		}
		gr = g.createLinearGradient(0, -th, 0, th);   // forge light along the underside
		gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, warm(.25 + .35 * glow));
		g.fillStyle = gr; g.fillRect(-.2 * H, -th, L + .4 * H, th * 2);
		g.restore();
		haft(); g.strokeStyle = edge; g.lineWidth = ew; g.stroke();

		// leather wrap: dark, worn, slightly uneven turns with stitch hints
		g.save(); g.beginPath(); g.rect(-.12 * H, -th, .6 * H, th * 2); g.clip();
		for (let i = 0; i < 8; i++) {
			const x = -.16 * H + i * .085 * H, v = .85 + .3 * sd[i % sd.length];
			gr = g.createLinearGradient(0, -th, 0, th);
			gr.addColorStop(0, rgba([88 * v, 60 * v, 40 * v])); gr.addColorStop(.45, rgba([52 * v, 34 * v, 22 * v])); gr.addColorStop(1, rgba([22, 14, 9]));
			g.fillStyle = gr; g.beginPath();
			g.moveTo(x, -th); g.lineTo(x + .085 * H, -th); g.lineTo(x + .045 * H, th); g.lineTo(x - .04 * H, th); g.closePath(); g.fill();
			g.strokeStyle = 'rgba(0,0,0,.4)'; g.lineWidth = Math.max(.5, H * .01); g.beginPath(); g.moveTo(x, -th); g.lineTo(x - .04 * H, th); g.stroke();
			g.strokeStyle = 'rgba(200,170,130,.16)'; g.setLineDash([Math.max(1, H * .02), Math.max(1, H * .025)]);   // stitching
			g.beginPath(); g.moveTo(x + .03 * H, -th * .7); g.lineTo(x + .005 * H, th * .7); g.stroke(); g.setLineDash([]);
		}
		g.restore();
		// iron ferrule where the wrap ends
		const ferrule = (x, w) => {
			gr = g.createLinearGradient(0, -th * .75, 0, th * .75);
			gr.addColorStop(0, '#8a8c90'); gr.addColorStop(.3, '#55575c'); gr.addColorStop(1, '#202226');
			g.fillStyle = gr; g.beginPath(); roundRectPath(g, x, -th * .72, w, th * 1.44, th * .2); g.fill();
			g.fillStyle = warm(.3 * glow + .1); g.fillRect(x, th * .3, w, th * .4);
			g.strokeStyle = edge; g.lineWidth = ew; g.stroke();
		};
		ferrule(.46 * H, .07 * H);
		// pommel: a plain forged iron cap, no gem
		const pr = .14 * H, pcx = -.19 * H;
		gr = g.createRadialGradient(pcx - pr * .35, -pr * .45, pr * .1, pcx, 0, pr * 1.05);
		gr.addColorStop(0, '#9a9ca2'); gr.addColorStop(.45, '#56585e'); gr.addColorStop(1, '#1c1d21');
		g.fillStyle = gr; g.beginPath();
		for (let i = 0; i < 8; i++) { const a = i / 8 * 6.283 + .2, r = i % 2 ? pr : pr * .9; g.lineTo(pcx + Math.cos(a) * r, Math.sin(a) * r); }
		g.closePath(); g.fill(); g.strokeStyle = edge; g.lineWidth = ew; g.stroke();
		g.fillStyle = 'rgba(30,26,22,.8)'; g.beginPath(); g.arc(pcx, 0, pr * .3, 0, 6.283); g.fill();   // a dull dark stud where the gem was

		// head: same silhouette as the cartoon hammer
		const hw = .78 * H, cx = L, x0 = cx - hw / 2, x1 = cx + hw / 2;
		const yFace = hammerFace(H), yTop = -.5 * H, bev = .08 * H, hh = yFace - yTop;
		// back: spike or double claw, forged and darkened
		const back = () => {
			g.beginPath();
			if (look.spike) {
				g.moveTo(cx - hw * .24, yTop + 1); g.quadraticCurveTo(cx - hw * .12, yTop - .2 * H, cx - hw * .03, yTop - .4 * H);
				g.lineTo(cx + hw * .03, yTop - .4 * H); g.quadraticCurveTo(cx + hw * .12, yTop - .2 * H, cx + hw * .24, yTop + 1);
			} else {
				g.moveTo(cx - hw * .42, yTop + 1); g.quadraticCurveTo(cx - hw * .58, yTop - .28 * H, cx - hw * .32, yTop - .36 * H);
				g.lineTo(cx - hw * .13, yTop + 1); g.lineTo(cx + hw * .13, yTop + 1); g.lineTo(cx + hw * .32, yTop - .36 * H);
				g.quadraticCurveTo(cx + hw * .58, yTop - .28 * H, cx + hw * .42, yTop + 1);
			}
			g.closePath();
		};
		back();
		gr = g.createLinearGradient(x0, yTop - .4 * H, x1, yTop);
		gr.addColorStop(0, '#24262c'); gr.addColorStop(.45, '#6a6e78'); gr.addColorStop(.6, '#3e4148'); gr.addColorStop(1, '#1c1d22');
		g.fillStyle = gr; g.fill();
		g.save(); back(); g.clip();
		g.strokeStyle = cool(.45); g.lineWidth = Math.max(.8, H * .02);   // cool rim light on the upper edge
		back(); g.stroke(); g.restore();
		back(); g.strokeStyle = edge; g.lineWidth = ew; g.stroke();

		// block body: forged steel, soft gradients, slight hammered unevenness
		const body = () => {
			g.beginPath();
			g.moveTo(x0 + bev, yTop); g.lineTo(x1 - bev, yTop); g.lineTo(x1, yTop + bev); g.lineTo(x1, yFace - bev);
			g.lineTo(x1 - bev, yFace); g.lineTo(x0 + bev, yFace); g.lineTo(x0, yFace - bev); g.lineTo(x0, yTop + bev); g.closePath();
		};
		body();
		gr = g.createLinearGradient(x0, yTop, x1, yFace);
		gr.addColorStop(0, '#7c818b'); gr.addColorStop(.3, '#555a63'); gr.addColorStop(.65, '#363940'); gr.addColorStop(1, '#1d1e22');
		g.fillStyle = gr; g.fill();
		g.save(); body(); g.clip();
		// hammered surface: faint soft dents
		for (let i = 0; i < 9; i++) {
			const dx = x0 + hw * (.1 + .8 * sd[i % sd.length]), dy = yTop + hh * (.15 + .7 * sd[(i + 3) % sd.length]), r = H * (.05 + .04 * sd[(i + 5) % sd.length]);
			const dg = g.createRadialGradient(dx - r * .3, dy - r * .3, 0, dx, dy, r);
			dg.addColorStop(0, 'rgba(255,255,255,.07)'); dg.addColorStop(.6, 'rgba(0,0,0,.08)'); dg.addColorStop(1, 'rgba(0,0,0,0)');
			g.fillStyle = dg; g.beginPath(); g.arc(dx, dy, r, 0, 6.283); g.fill();
		}
		// bevel facets: soft cool light top-left, deep shadow right
		gr = g.createLinearGradient(0, yTop, 0, yTop + bev * 1.6); gr.addColorStop(0, cool(.45)); gr.addColorStop(1, cool(0));
		g.fillStyle = gr; g.fillRect(x0, yTop, hw, bev * 1.6);
		gr = g.createLinearGradient(x0, 0, x0 + bev * 1.6, 0); gr.addColorStop(0, cool(.25)); gr.addColorStop(1, cool(0));
		g.fillStyle = gr; g.fillRect(x0, yTop, bev * 1.6, hh);
		gr = g.createLinearGradient(x1, 0, x1 - bev * 2, 0); gr.addColorStop(0, 'rgba(0,0,0,.45)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
		g.fillStyle = gr; g.fillRect(x1 - bev * 2, yTop, bev * 2, hh);
		// fine scratches
		g.strokeStyle = 'rgba(210,215,225,.12)'; g.lineWidth = Math.max(.4, H * .007);
		for (let i = 0; i < 6; i++) {
			const sx = x0 + hw * sd[(i + 1) % sd.length], sy = yTop + hh * sd[(i + 4) % sd.length], len = H * (.08 + .1 * sd[(i + 2) % sd.length]);
			g.beginPath(); g.moveTo(sx, sy); g.lineTo(sx + len, sy + len * (sd[i % sd.length] - .5) * .6); g.stroke();
		}
		// striking face: worn bright steel along the bottom, darker bevel, lit orange by the hot metal below
		gr = g.createLinearGradient(0, yFace - H * .1, 0, yFace);
		gr.addColorStop(0, 'rgba(0,0,0,.35)'); gr.addColorStop(.35, 'rgba(150,155,165,.5)'); gr.addColorStop(1, 'rgba(205,210,218,.65)');
		g.fillStyle = gr; g.fillRect(x0, yFace - H * .1, hw, H * .1);
		gr = g.createLinearGradient(0, yFace, 0, yTop);
		gr.addColorStop(0, warm(.25 + .6 * glow)); gr.addColorStop(.5, warm(.06 + .14 * glow)); gr.addColorStop(1, warm(0));
		g.globalCompositeOperation = 'lighter'; g.fillStyle = gr; g.fillRect(x0, yTop, hw, hh); g.globalCompositeOperation = 'source-over';
		g.restore();
		body(); g.strokeStyle = edge; g.lineWidth = ew; g.stroke();

		// aged iron bands with a couple of small rivets
		for (const yc of [yTop + hh * .22, yTop + hh * .74]) {
			const hgt = .09 * H;
			gr = g.createLinearGradient(0, yc - hgt / 2, 0, yc + hgt / 2);
			gr.addColorStop(0, '#6e6458'); gr.addColorStop(.4, '#4a4036'); gr.addColorStop(1, '#221c16');
			g.fillStyle = gr; g.fillRect(x0 - H * .02, yc - hgt / 2, hw + H * .04, hgt);
			g.fillStyle = 'rgba(120,70,30,.18)'; g.fillRect(x0 - H * .02, yc - hgt / 2, hw + H * .04, hgt);   // rust bloom
			g.fillStyle = cool(.25); g.fillRect(x0 - H * .02, yc - hgt / 2, hw + H * .04, Math.max(.6, hgt * .18));
			g.strokeStyle = edge; g.lineWidth = ew; g.strokeRect(x0 - H * .02, yc - hgt / 2, hw + H * .04, hgt);
			for (const fx of [.18, .82]) {
				const rx = x0 + hw * fx, rr = hgt * .2;
				gr = g.createRadialGradient(rx - rr * .4, yc - rr * .4, 0, rx, yc, rr);
				gr.addColorStop(0, '#a49a8c'); gr.addColorStop(1, '#2a241e');
				g.fillStyle = gr; g.beginPath(); g.arc(rx, yc, rr, 0, 6.283); g.fill();
			}
		}
		g.restore();
	}

	// The Warcraft hammer painted the way Skinning C2's knife is (skinning.js drawRealKnife): one soft drop
	// shadow and no outlines; brushed steel with a bright ground bevel along the striking face and a glint
	// that slides across the head; a brass or steel bolster and bands; a wood or antler haft with grain and
	// two pins. The face toward the bar still takes the forge's orange light.
	function makeHammerLook() {
		const grain = [], knobs = [];
		for (let i = 0; i < 7; i++) grain.push({ v: rand(-.8, .8), amp: rand(.03, .1), f: rand(5, 11), ph: rand(0, 6.283) });
		for (let i = 0; i < 9; i++) knobs.push({ u: rand(.05, .95), v: rand(-.6, .6), r: rand(.04, .09) });
		return { antler: Math.random() < .4, brass: Math.random() < .5, spike: Math.random() < .5, grain, knobs, glint: .5 };
	}
	function drawKnifeHammer(g, px, py, rot, H, look, glow = 0, alpha = 1) {
		const L = hammerLen(H), th = .16 * H, hx0 = -.1 * H, hx1 = L - .06 * H;
		const hw = .78 * H, cx = L, x0 = cx - hw / 2, x1 = cx + hw / 2, yFace = hammerFace(H), yTop = -.5 * H, hh = yFace - yTop, bev = .07 * H;
		const faint = 'rgba(0,0,0,.3)', fw = Math.max(.5, H * .012);
		const metal = (y0, y1) => {
			const m = g.createLinearGradient(0, y0, 0, y1);
			if (look.brass) { m.addColorStop(0, '#fbe6a8'); m.addColorStop(.35, '#c79a44'); m.addColorStop(.7, '#7a5418'); m.addColorStop(1, '#3e2a0a'); }
			else { m.addColorStop(0, '#f2f5f8'); m.addColorStop(.35, '#a9b2bb'); m.addColorStop(.7, '#5c646d'); m.addColorStop(1, '#2a2f35'); }
			return m;
		};
		g.save(); g.globalAlpha *= alpha; g.translate(px, py); g.rotate(rot);

		const haft = new Path2D();
		haft.moveTo(hx0, -th * .9);
		haft.bezierCurveTo(hx0 + (hx1 - hx0) * .4, -th, hx1 - H * .1, -th * .8, hx1, -th * .7);
		haft.lineTo(hx1, th * .7);
		haft.bezierCurveTo(hx1 - H * .1, th * .8, hx0 + (hx1 - hx0) * .4, th, hx0, th * .9);
		haft.quadraticCurveTo(hx0 - th * .5, 0, hx0, -th * .9);
		haft.closePath();
		const pr = th * 1.05, pommel = new Path2D(); roundRectPathTo(pommel, hx0 - pr * 1.1, -pr, pr * 1.2, pr * 2, pr * .45);
		const bolster = new Path2D(); roundRectPathTo(bolster, L - hw * .5 - H * .1, -th * 1.15, H * .12, th * 2.3, th * .35);
		const head = new Path2D();
		head.moveTo(x0 + bev, yTop); head.lineTo(x1 - bev, yTop); head.lineTo(x1, yTop + bev); head.lineTo(x1, yFace - bev);
		head.lineTo(x1 - bev, yFace); head.lineTo(x0 + bev, yFace); head.lineTo(x0, yFace - bev); head.lineTo(x0, yTop + bev); head.closePath();
		const back = new Path2D();
		if (look.spike) {
			back.moveTo(cx - hw * .24, yTop + 1); back.quadraticCurveTo(cx - hw * .12, yTop - .2 * H, cx - hw * .02, yTop - .42 * H);
			back.lineTo(cx + hw * .02, yTop - .42 * H); back.quadraticCurveTo(cx + hw * .12, yTop - .2 * H, cx + hw * .24, yTop + 1);
		} else {
			back.moveTo(cx - hw * .42, yTop + 1); back.quadraticCurveTo(cx - hw * .58, yTop - .28 * H, cx - hw * .32, yTop - .36 * H);
			back.lineTo(cx - hw * .13, yTop + 1); back.lineTo(cx + hw * .13, yTop + 1); back.lineTo(cx + hw * .32, yTop - .36 * H);
			back.quadraticCurveTo(cx + hw * .58, yTop - .28 * H, cx + hw * .42, yTop + 1);
		}
		back.closePath();

		// one soft shadow under the whole hammer
		g.save(); g.shadowColor = 'rgba(0,0,0,.45)'; g.shadowBlur = H * .14 * dpr; g.shadowOffsetX = H * .05 * dpr; g.shadowOffsetY = H * .08 * dpr;
		g.fillStyle = '#555'; for (const p of [haft, pommel, bolster, back, head]) g.fill(p); g.restore();

		// haft: wood or antler, exactly as the knife's handle
		g.save(); g.clip(haft);
		let gr = g.createLinearGradient(0, -th, 0, th);
		if (look.antler) { gr.addColorStop(0, '#e6dac4'); gr.addColorStop(.45, '#b7a385'); gr.addColorStop(1, '#5d4c38'); }
		else { gr.addColorStop(0, '#9a6a40'); gr.addColorStop(.4, '#6a4322'); gr.addColorStop(1, '#2a160a'); }
		g.fillStyle = gr; g.fillRect(hx0 - th, -th * 1.3, hx1 - hx0 + th * 2, th * 2.6);
		if (look.antler) {
			for (const kn of look.knobs) {
				const kx = lerp(hx0, hx1, kn.u), ky = kn.v * th, kr = H * kn.r;
				const kg = g.createRadialGradient(kx - kr * .3, ky - kr * .3, 0, kx, ky, kr);
				kg.addColorStop(0, 'rgba(255,248,232,.35)'); kg.addColorStop(.6, 'rgba(120,96,70,.25)'); kg.addColorStop(1, 'rgba(60,44,30,0)');
				g.fillStyle = kg; g.beginPath(); g.arc(kx, ky, kr, 0, 6.283); g.fill();
			}
		}
		g.lineWidth = Math.max(.4, H * .01);
		for (const gn of look.grain) {
			g.strokeStyle = look.antler ? 'rgba(70,52,34,.35)' : `rgba(30,14,4,${.25 + gn.amp * 2})`;
			g.beginPath();
			for (let u = 0; u <= 1; u += .04) { const x = lerp(hx0, hx1, u), y = gn.v * th * .9 + Math.sin(u * gn.f + gn.ph) * gn.amp * th; u ? g.lineTo(x, y) : g.moveTo(x, y); }
			g.stroke();
		}
		if (!look.antler) {
			const wg = g.createRadialGradient(lerp(hx0, hx1, .3), -th * .3, 0, lerp(hx0, hx1, .3), -th * .3, (hx1 - hx0) * .3);   // worn, handled spot
			wg.addColorStop(0, 'rgba(255,225,190,.12)'); wg.addColorStop(1, 'rgba(255,225,190,0)');
			g.fillStyle = wg; g.fillRect(hx0 - th, -th * 1.3, hx1 - hx0 + th * 2, th * 2.6);
		}
		gr = g.createLinearGradient(0, -th, 0, -th * .4);   // highlight along the top
		gr.addColorStop(0, 'rgba(255,245,225,.28)'); gr.addColorStop(1, 'rgba(255,245,225,0)');
		g.fillStyle = gr; g.fillRect(hx0 - th, -th * 1.3, hx1 - hx0 + th * 2, th);
		gr = g.createLinearGradient(0, -th, 0, th);   // the forge's light on the underside
		gr.addColorStop(0, 'rgba(255,130,50,0)'); gr.addColorStop(1, `rgba(255,130,50,${.12 + .25 * glow})`);
		g.fillStyle = gr; g.fillRect(hx0 - th, -th * 1.3, hx1 - hx0 + th * 2, th * 2.6);
		g.restore();
		const pin = look.brass ? ['#fff0b8', '#b88a36', '#5a3e12'] : ['#ffffff', '#a8b0b8', '#4a5058'];
		const drawPin = (x, y, r) => {
			const pg = g.createRadialGradient(x - r * .35, y - r * .35, 0, x, y, r);
			pg.addColorStop(0, pin[0]); pg.addColorStop(.55, pin[1]); pg.addColorStop(1, pin[2]);
			g.fillStyle = pg; g.beginPath(); g.arc(x, y, r, 0, 6.283); g.fill();
		};
		for (const u of [.22, .55]) drawPin(lerp(hx0, hx1, u), 0, th * .3);
		g.strokeStyle = faint; g.lineWidth = fw; g.stroke(haft);
		// pommel cap and bolster, like the knife's bolster
		g.fillStyle = metal(-pr, pr); g.fill(pommel); g.strokeStyle = faint; g.stroke(pommel);
		g.fillStyle = metal(-th * 1.15, th * 1.15); g.fill(bolster); g.stroke(bolster);

		// steel: brushed gradient lit from above, a ground bevel bright along the face, a sliding glint
		const steel = (path, y0, y1) => {
			g.save(); g.clip(path);
			const sg = g.createLinearGradient(0, y0, 0, y1);
			sg.addColorStop(0, '#e4e9ee'); sg.addColorStop(.3, '#a7b0b9'); sg.addColorStop(.55, '#7b858f'); sg.addColorStop(1, '#5d6670');
			g.fillStyle = sg; g.fillRect(x0 - H, y0 - H, hw + 2 * H, y1 - y0 + 2 * H);
			g.strokeStyle = 'rgba(255,255,255,.07)'; g.lineWidth = Math.max(.3, H * .006);
			for (let i = 0; i < 12; i++) { const yy = lerp(y0, y1, i / 11); g.beginPath(); g.moveTo(x0 - H * .2, yy); g.lineTo(x1 + H * .2, yy + H * .01); g.stroke(); }
			const gx = lerp(x0, x1, look.glint), gl = g.createRadialGradient(gx, lerp(y0, y1, .3), 0, gx, lerp(y0, y1, .3), hw * .35);
			gl.addColorStop(0, 'rgba(255,255,255,.5)'); gl.addColorStop(1, 'rgba(255,255,255,0)');
			g.globalCompositeOperation = 'lighter'; g.fillStyle = gl; g.fillRect(x0 - H, y0 - H, hw + 2 * H, y1 - y0 + 2 * H); g.globalCompositeOperation = 'source-over';
			g.restore();
			g.strokeStyle = faint; g.lineWidth = fw; g.stroke(path);
		};
		steel(back, yTop - .42 * H, yTop);
		steel(head, yTop, yFace);
		g.save(); g.clip(head);
		// bevels: light on the top and left, shadow on the right
		gr = g.createLinearGradient(0, yTop, 0, yTop + bev * 1.6); gr.addColorStop(0, 'rgba(255,255,255,.35)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
		g.fillStyle = gr; g.fillRect(x0, yTop, hw, bev * 1.6);
		gr = g.createLinearGradient(x1, 0, x1 - bev * 2, 0); gr.addColorStop(0, 'rgba(0,0,0,.4)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
		g.fillStyle = gr; g.fillRect(x1 - bev * 2, yTop, bev * 2, hh);
		// the ground striking face: a bright band with a bevel line above it
		g.fillStyle = 'rgba(214,224,232,.55)'; g.fillRect(x0, yFace - H * .09, hw, H * .09);
		g.strokeStyle = 'rgba(70,78,88,.35)'; g.lineWidth = Math.max(.4, H * .012);
		g.beginPath(); g.moveTo(x0, yFace - H * .095); g.lineTo(x1, yFace - H * .095); g.stroke();
		// the forge's orange light on the face toward the hot bar
		gr = g.createLinearGradient(0, yFace, 0, yTop);
		gr.addColorStop(0, `rgba(255,130,50,${.2 + .6 * glow})`); gr.addColorStop(.5, `rgba(255,130,50,${.05 + .12 * glow})`); gr.addColorStop(1, 'rgba(255,130,50,0)');
		g.globalCompositeOperation = 'lighter'; g.fillStyle = gr; g.fillRect(x0, yTop, hw, hh); g.globalCompositeOperation = 'source-over';
		g.restore();
		// bands across the head in the bolster's metal, with two small pins each
		for (const yc of [yTop + hh * .24, yTop + hh * .7]) {
			const bh = .085 * H, band = new Path2D(); roundRectPathTo(band, x0 - H * .02, yc - bh / 2, hw + H * .04, bh, bh * .3);
			g.fillStyle = metal(yc - bh / 2, yc + bh / 2); g.fill(band); g.strokeStyle = faint; g.lineWidth = fw; g.stroke(band);
			for (const fx of [.18, .82]) drawPin(x0 + hw * fx, yc, bh * .22);
		}
		g.restore();
	}
	// a Path2D rounded rectangle (roundRectPath draws straight into a context)
	function roundRectPathTo(p, x, y, w, h, r) {
		r = Math.min(r, h / 2, w / 2);
		p.moveTo(x + r, y); p.arcTo(x + w, y, x + w, y + h, r); p.arcTo(x + w, y + h, x, y + h, r);
		p.arcTo(x, y + h, x, y, r); p.arcTo(x, y, x + w, y, r); p.closePath();
	}

	CONCEPTS.push({
		group: 'Blacksmithing', id: 'smith-a2', letter: 'A2', name: 'Red-hot billet, forged',
		desc: 'Deeper heat: each blow drives the iron from blood red toward white and it lingers; cooler parts sink to maroon with glowing veins. A Warcraft-style forge hammer. Quenches in steam',
		spell: 'Copper Chain Belt', padTop: 2.6, padX: 1.6, padBottom: .6, flash: [200, 225, 255],
		init(s) {
			s.hammer = { u: rand(.3, .6) }; s.period = rand(.62, .78); s.flashes = []; s.quenched = false;
			s.n = noise1(); s.wind = rand(-.3, .3); s.flecks = makeFlecks(s, Math.round(s.W / s.H * 7));
			s.look = { trim: pick(TRIMS), gem: pick(GEMS), spike: Math.random() < .5 };
			// heat each blow has driven into the iron, in cells a quarter of the bar high; it cools slowly
			s.cell = s.H * .25; s.heat = new Float32Array(Math.ceil(s.W / s.cell) + 2);
			// glowing veins through the cooler iron
			s.veins = Array.from({ length: 3 + Math.floor(Math.random() * 2) }, () => {
				const pts = [], n = noise1(); let y = rand(.2, .8);
				for (let x = 0; x <= s.W + 4; x += s.H * .2) { y = clamp(y + n(x / s.H * .7) * .09, .12, .88); pts.push([x, y * s.H]); }
				return { pts, w: rand(.035, .07), ph: rand(0, 6.283) };
			});
		},
		draw(g, s) {
			const H = s.H, F = s.fill, floor = .14 + .12 * s.p;
			quenchStart(s, .9);
			const q = quenchAmount(s);
			// driven heat relaxes toward the floor; the newest metal at the cast edge is always fresh from the fire
			const k = Math.exp(-s.dt / 2.6);
			for (let i = 0; i < s.heat.length; i++) s.heat[i] *= k;
			const driven = x => {
				const f = x / s.cell, i = Math.floor(f), t = f - i;
				return lerp(s.heat[clamp(i, 0, s.heat.length - 1)], s.heat[clamp(i + 1, 0, s.heat.length - 1)], t);
			};
			const heatAt = x => floor + .06 * s.n(x / (1.3 * H) + s.t * .25) + driven(x) + .38 * Math.exp(-Math.max(0, F - x) / (1.2 * H));
			bloom(g, s, 0, F, s.done ? .7 * (1 - q) : .45 + .25 * s.p);
			g.save(); clipBar(g, s);
			coldIron(g, s, F);
			if (q < 1) {
				const step = 2;
				for (let x = 0; x < F; x += step) { g.fillStyle = rgba(deepCol(heatAt(x + 1))); g.fillRect(x, 0, Math.min(step + .5, F - x), H); }
				// glowing veins: brightest where the iron has cooled most, so the dark parts still read as hot inside
				g.globalCompositeOperation = 'lighter';
				for (const v of s.veins) {
					g.lineWidth = Math.max(1, v.w * H); g.lineCap = 'round';
					for (let i = 1; i < v.pts.length; i++) {
						const [ax, ay] = v.pts[i - 1], [bx, by] = v.pts[i];
						if (ax > F) break;
						const h = heatAt(ax), a = clamp((.62 - h) * 1.6) * (.55 + .25 * Math.sin(s.t * 2.2 + v.ph + ax / H));
						if (a <= .02) continue;
						g.strokeStyle = rgba([255, 92, 24], a);
						g.beginPath(); g.moveTo(ax, ay); g.lineTo(Math.min(bx, F), by); g.stroke();
					}
				}
				g.globalCompositeOperation = 'source-over';
				for (const f of s.flecks) {
					if (f.x > F) continue;
					const a = f.a * clamp(.9 - heatAt(f.x));
					if (a <= .02) continue;
					g.fillStyle = `rgba(12,2,2,${a})`; g.beginPath(); g.ellipse(f.x, f.y * H, f.r * H, f.r * H * .6, f.rot, 0, 6.283); g.fill();
				}
				// rounded shading, a touch stronger for more contrast
				const gr = g.createLinearGradient(0, 0, 0, H);
				gr.addColorStop(0, 'rgba(255,240,220,.22)'); gr.addColorStop(.2, 'rgba(255,255,255,0)'); gr.addColorStop(.65, 'rgba(0,0,0,.1)'); gr.addColorStop(1, 'rgba(0,0,0,.6)');
				g.fillStyle = gr; g.fillRect(0, 0, F, H);
			}
			temperedSteel(g, s, F, q);
			g.restore();
			// the blow: drive heat in around the strike
			s.hx = Math.max(.35 * H, F - .35 * H);
			if (s.casting && stepHammer(s.hammer, s.dt, s.period) && F > .2 * H) {
				const c = s.hx / s.cell;
				for (let i = 0; i < s.heat.length; i++) s.heat[i] = Math.min(.95, s.heat[i] + .5 * Math.exp(-(((i - c) / 3.2) ** 2)));
				strikeFX(s, s.hx, .9);
			}
			if (!s.done) steamWisps(s, 0, F, (2 + 12 * s.p) * F / 300, .14 + .2 * s.p);
			s.parts.update(s.dt);
			s.parts.draw(g, p => p.kind === 'smoke');
		},
		over(g, s) {
			const H = s.H, ha = s.done ? clamp(1 - s.doneT * 3) : 1;
			if (ha > 0) {
				const glow = clamp(.9 * (1 - clamp(-lift(s.hammer.u) / MAXLIFT)));
				drawWowHammer(g, s.hx - hammerLen(H), -hammerFace(H), lift(s.hammer.u), H, s.look, glow, ha);
			}
			s.parts.draw(g, p => p.kind !== 'smoke');
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
