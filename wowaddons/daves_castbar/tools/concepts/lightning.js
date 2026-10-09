// Lightning concepts: storm cloud with forked strikes, a riding arc with a plasma ball, a charged conduit.
(() => {
	// Jagged bolt by midpoint displacement: points from (x1,y1) to (x2,y2), each level halving the offset.
	function jag(x1, y1, x2, y2, disp, levels = 5) {
		let pts = [[x1, y1], [x2, y2]];
		let d = disp;
		for (let l = 0; l < levels; l++) {
			const next = [pts[0]];
			for (let i = 1; i < pts.length; i++) {
				const a = pts[i - 1], b = pts[i];
				const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy) || 1;
				const o = rand(-d, d);
				next.push([(a[0] + b[0]) / 2 - dy / len * o, (a[1] + b[1]) / 2 + dx / len * o], b);
			}
			pts = next; d *= .55;
		}
		return pts;
	}
	// A bolt with a few forks hanging off it.
	function forked(x1, y1, x2, y2, disp, forks, levels) {
		const main = jag(x1, y1, x2, y2, disp, levels), out = [{ pts: main, w: 1 }];
		for (let f = 0; f < forks; f++) {
			const i = Math.floor(rand(.2, .8) * main.length), a = main[i];
			const ang = Math.atan2(y2 - y1, x2 - x1) + rand(.4, 1.1) * (Math.random() < .5 ? -1 : 1);
			const len = Math.hypot(x2 - x1, y2 - y1) * rand(.2, .45);
			out.push({ pts: jag(a[0], a[1], a[0] + Math.cos(ang) * len, a[1] + Math.sin(ang) * len, disp * .5, Math.max(2, levels - 1)), w: .55 });
		}
		return out;
	}
	function path(g, pts) {
		g.beginPath(); g.moveTo(pts[0][0], pts[0][1]);
		for (let i = 1; i < pts.length; i++) g.lineTo(pts[i][0], pts[i][1]);
	}
	// Electricity: a wide faint halo, a coloured body and a white-hot core, all additive.
	function drawBolt(g, pts, w, col, a = 1) {
		g.save(); g.globalCompositeOperation = 'lighter'; g.lineJoin = 'round'; g.lineCap = 'round';
		path(g, pts);
		g.strokeStyle = rgba(col, .07 * a); g.lineWidth = w * 7; g.stroke();
		g.strokeStyle = rgba(col, .18 * a); g.lineWidth = w * 3.5; g.stroke();
		g.strokeStyle = rgba(col, .65 * a); g.lineWidth = w * 1.6; g.stroke();
		g.strokeStyle = rgba(mix(col, [255, 255, 255], .75), .95 * a); g.lineWidth = Math.max(.6, w * .6); g.stroke();
		g.restore();
	}
	function glow(g, x, y, r, col, a) {
		if (r <= 0 || a <= 0) return;
		const gr = g.createRadialGradient(x, y, 0, x, y, r);
		gr.addColorStop(0, rgba(col, a)); gr.addColorStop(.4, rgba(col, a * .35)); gr.addColorStop(1, rgba(col, 0));
		g.save(); g.globalCompositeOperation = 'lighter'; g.fillStyle = gr; g.beginPath(); g.arc(x, y, r, 0, 6.283); g.fill(); g.restore();
	}
	const clipBar = (g, s, w = s.W) => { roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip(); g.beginPath(); g.rect(0, -s.H, Math.max(0, w), s.H * 3); g.clip(); };
	function sparks(s, x, y, n, col, speed) {
		for (let i = 0; i < n; i++) {
			const a = rand(0, 6.283), v = s.H * rand(2, 6) * speed;
			s.parts.emit({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, ay: s.H * 6, drag: 3, life: rand(.15, .4), size: Math.max(.7, s.H * .04), color: col, kind: 'spark' });
		}
	}

	// ------------------------------------------------------------------ A: storm cloud
	CONCEPTS.push({
		group: 'Lightning', id: 'light-a', letter: 'A', name: 'Thunderhead',
		desc: 'Churning storm cloud; forked bolts strike inside it and light it up', spell: 'Lightning Bolt',
		padTop: .9, padBottom: .6, flash: [190, 215, 255],
		init(s) {
			const H = s.H;
			s.puffs = [];
			// two layers of billows: big dark ones low down, smaller lit ones on top
			for (let x = -H; x < s.W + H; x += H * rand(.5, .8))
				s.puffs.push({ x, y: H * rand(.7, 1.1), r: H * rand(.8, 1.2), sh: rand(.5, .75), v: rand(.12, .25) * H, ph: rand(0, 6.283) });
			for (let x = -H; x < s.W + H; x += H * rand(.4, .7))
				s.puffs.push({ x, y: H * rand(.1, .5), r: H * rand(.4, .75), sh: rand(.85, 1.25), v: rand(.25, .45) * H, ph: rand(0, 6.283) });
			s.bolts = []; s.nextBolt = .15; s.flash = 0; s.flashX = 0;
			s.roll = wobble(2);
		},
		draw(g, s) {
			const { W, H, fill, dt } = s;
			g.save(); clipBar(g, s, fill);
			// cloud body
			const bg = g.createLinearGradient(0, 0, 0, H);
			bg.addColorStop(0, '#1b2147'); bg.addColorStop(.6, '#11143a'); bg.addColorStop(1, '#090a1f');
			g.fillStyle = bg; g.fillRect(0, 0, fill, H);
			for (const q of s.puffs) {
				const x = ((q.x + s.t * q.v) % (W + H * 2)) - H, y = q.y + Math.sin(s.t * .8 + q.ph) * H * .06;
				const lit = s.flash * clamp(1 - Math.abs(x - s.flashX) / (H * 4));
				// sheet lightning flickers inside single puffs between the strikes
				const sheet = Math.max(0, Math.sin(s.t * 23 + q.ph * 7) * Math.sin(s.t * 3.1 + q.ph) - .85) * 5;
				const c = mix([52, 60, 120].map(v => v * q.sh), [130, 155, 240], clamp(lit * .5 + sheet * .35));
				const gr = g.createRadialGradient(x, y - q.r * .3, 0, x, y, q.r);
				gr.addColorStop(0, rgba(mix(c, [140, 150, 220], .35), .9)); gr.addColorStop(.55, rgba(c, .55)); gr.addColorStop(1, rgba(c, 0));
				g.fillStyle = gr; g.beginPath(); g.arc(x, y, q.r, 0, 6.283); g.fill();
			}
			// a whole-cloud flash behind the strike
			if (s.flash > 0) {
				g.globalCompositeOperation = 'lighter';
				const fg = g.createRadialGradient(s.flashX, H / 2, 0, s.flashX, H / 2, H * 2.5);
				fg.addColorStop(0, rgba([110, 140, 255], .28 * s.flash)); fg.addColorStop(1, rgba([110, 140, 255], 0));
				g.fillStyle = fg; g.fillRect(0, 0, fill, H); g.globalCompositeOperation = 'source-over';
			}
			s.flash = Math.max(0, s.flash - dt * 5);
			// strikes
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
			// the cloud's leading edge glows faintly, with a static flicker now and then
			if (s.casting && fill > 2) {
				g.save(); clipBar(g, s, fill);
				const e = fill, eg = g.createLinearGradient(e - H * 1.2, 0, e, 0), f = .25 + .2 * (s.roll(s.t * 6) + 1) / 2 + (Math.random() < .08 ? .3 : 0);
				eg.addColorStop(0, 'rgba(120,150,255,0)'); eg.addColorStop(1, rgba([150, 180, 255], f));
				g.globalCompositeOperation = 'lighter'; g.fillStyle = eg; g.fillRect(e - H * 1.2, 0, H * 1.2, H);
				g.restore();
			}
		},
	});

	// ------------------------------------------------------------------ A3: A's storm, with wide layered cloud banks
	// The same bolts, flashes and blues as A, but the cloud is four wide horizontal banks at different
	// depths. Each bank is painted once per cast to its own canvas from many very wide, blurred lobes:
	// broad low swells along its top (lit periwinkle), a flatter, darker underside, faint streaks inside.
	// The banks overlap at different heights and drift at different speeds; dark sky shows only between them.
	function cnv(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }
	const BANKS = [   // y values in bar heights from the bar's top; far banks first; cloud = cloud length range
		{ top: [84, 88, 160], mid: [52, 56, 116], under: [30, 32, 78], a: .75, y: .06, base: .36, thick: .7, v: .05, cloud: [2.8, 6.3], gap: [1.6, 3.2] },
		{ top: [96, 106, 184], mid: [50, 57, 122], under: [24, 26, 64], a: .95, y: .32, base: .62, thick: .8, v: .1, cloud: [2.5, 5.6], gap: [1.8, 3.6] },
		{ top: [110, 126, 206], mid: [46, 53, 116], under: [14, 15, 40], a: 1, y: .58, base: .9, thick: .85, v: .17, cloud: [2.1, 4.9], gap: [2, 4] },
		{ top: [74, 84, 162], mid: [30, 34, 82], under: [8, 8, 24], a: 1, y: .9, base: 1.3, thick: .9, v: .26, cloud: [2.1, 4.9], gap: [2.4, 4.6] },
	];
	// Per-cast weather (2026-10-09): which banks there are, how the clouds are cut, their tint and how they
	// move. One is picked each cast in turn (?weather=0..4 starts from one), so no two storms look alike.
	//   cloud/gap/thick/v scale the banks' ranges; tower = how often billows stack up into towers;
	//   ragged = torn edges and wisps; stray = chance of faint stray rows drifting between the banks;
	//   back = chance a bank drifts the other way.
	const WEATHERS = [
		{ name: 'layered', banks: [0, 1, 2, 3], tint: [1, 1, 1], cloud: 1, gap: 1, thick: 1, v: 1, tower: .45, ragged: 0, stray: .5, back: .2 },
		{ name: 'towering', banks: [0, 1, 2, 3], tint: [.96, .96, 1.05], cloud: 1.3, gap: .8, thick: 1.25, v: .8, tower: .95, ragged: .1, stray: .3, back: .1 },
		{ name: 'scattered', banks: [1, 2, 3], tint: [1.06, 1.06, 1], cloud: .6, gap: 1.8, thick: .85, v: 1.3, tower: .3, ragged: .25, stray: .8, back: .35 },
		{ name: 'overcast', banks: [0, 1, 2, 3], tint: [.86, .88, .96], cloud: 2, gap: .35, thick: .75, v: .6, tower: .15, ragged: 0, stray: .2, back: 0 },
		{ name: 'ragged squall', banks: [0, 2, 3], tint: [.92, 1, 1.06], cloud: .9, gap: 1.1, thick: .9, v: 1.8, tower: .5, ragged: .85, stray: 1, back: .5 },
	];
	let weatherTurn = Math.floor(Math.random() * WEATHERS.length);
	{ const q = new URLSearchParams(location.search); if (q.has('weather')) weatherTurn = +q.get('weather'); }
	const tintCol = (c, t) => [c[0] * t[0], c[1] * t[1], c[2] * t[2]];
	// a bank's ranges under this weather
	function weatherBank(B, Wt) {
		const sc = (r, f) => [r[0] * f, r[1] * f];
		return Object.assign({}, B, { top: tintCol(B.top, Wt.tint), mid: tintCol(B.mid, Wt.tint), under: tintCol(B.under, Wt.tint),
			cloud: sc(B.cloud, Wt.cloud), gap: sc(B.gap, Wt.gap), thick: B.thick * Wt.thick, v: B.v * Wt.v * rand(.7, 1.3) * (Math.random() < Wt.back ? -1 : 1),
			tower: Wt.tower, ragged: Wt.ragged });
	}
	const BANK_TOP = .9;   // room above a bank's billows in its canvas, in bar heights
	// One bank, BW wide (it tiles), painted at k device pixels per bar pixel. A bank is a row of clouds with
	// sky between them. Each cloud is a run of rounded billows of mixed sizes along its top (overlapping into
	// a scalloped silhouette, tallest in the middle, rounded at both ends) over a belly of lower lobes, so the
	// underside bulges gently instead of lying ruler-flat.
	function paintBank(B, BW, H, k) {
		const BH = (BANK_TOP + B.base - B.y + .6) * H;
		const y0 = BANK_TOP * H, depth = (B.base - B.y) * H;
		const lobes = [], bellies = [];
		for (let cx = rand(0, H * 2); cx < BW - H;) {
			const len = Math.min(H * rand(...B.cloud), BW - cx);
			// billows: round, mixed sizes, packed so they overlap; the dome peaks in the middle of the cloud
			for (let px = cx + H * .35; px < cx + len - H * .3; px += H * rand(.55, .95)) {
				const u = (px - cx) / len, dome = Math.sin(Math.PI * clamp(u));        // 0 at the ends, 1 mid-cloud
				const r = H * rand(.32, .6) * B.thick * (.55 + .45 * dome);
				lobes.push({ x: px, y: y0 + depth * .25 - dome * H * rand(.12, .28) - r * .35, rx: r * rand(1.4, 1.9), ry: r });
				// now and then a smaller billow riding on top, for the cauliflower scallops; under a towering
				// weather they stack two or three high into towers
				const tower = B.tower ?? .45;
				let last = lobes[lobes.length - 1], stack = 0;
				while (Math.random() < tower * dome && stack < (tower > .7 ? 3 : 1)) {
					last = { x: last.x + rand(-.2, .2) * H, y: last.y - last.ry * .55, rx: last.rx * .75, ry: last.ry * .6 };
					lobes.push(last); stack++;
				}
			}
			// rounded ends: a round billow capping each end
			for (const ex of [cx + H * .35, cx + len - H * .35]) lobes.push({ x: ex, y: y0 + depth * .3, rx: H * .38 * B.thick, ry: H * .32 * B.thick });
			// the belly: lower lobes that bulge the underside a little, deepest mid-cloud
			for (let px = cx + H * .4; px < cx + len - H * .4; px += H * rand(.6, 1)) {
				const dome = Math.sin(Math.PI * clamp((px - cx) / len));
				bellies.push({ x: px, y: y0 + depth * (.45 + .15 * dome), rx: H * rand(.6, .95), ry: depth * (.35 + .2 * dome) });
			}
			// ragged weather: torn tufts around the cloud's ends and small wisps hanging under it
			const ragged = B.ragged || 0;
			for (let i = 0; i < ragged * len / H * 2; i++) {
				const nearEnd = Math.random() < .5, px = nearEnd ? (Math.random() < .5 ? cx + rand(-.3, .4) * H : cx + len + rand(-.4, .3) * H) : cx + rand(.2, .8) * len;
				const r = H * rand(.1, .25) * B.thick;
				if (nearEnd) lobes.push({ x: px, y: y0 + depth * rand(.1, .5), rx: r * rand(1.2, 2), ry: r });
				else bellies.push({ x: px, y: y0 + depth * rand(.6, .9), rx: r * rand(1.5, 2.5), ry: r * .6 });
			}
			cx += len + H * rand(...B.gap);
		}
		lobes.sort((a, b) => a.y - b.y);   // upper billows first; lower ones overlap their shaded undersides
		const tile = (list, f) => { for (const l of list) for (const o of [-BW, 0, BW]) f(l, l.x + o); };
		const body = cnv(BW * k, BH * k), b = body.getContext('2d');
		b.scale(k, k);
		// body: billows and belly lobes in the mid tone, softly blurred so the scallops stay round but soft
		b.filter = `blur(${H * .09 * k}px)`;
		b.fillStyle = rgba(B.mid);
		tile(bellies, (l, lx) => { b.beginPath(); b.ellipse(lx, l.y, l.rx, l.ry, 0, 0, 6.283); b.fill(); });
		tile(lobes, (l, lx) => { b.beginPath(); b.ellipse(lx, l.y, l.rx, l.ry, 0, 0, 6.283); b.fill(); });
		b.filter = 'none';
		// each billow lit on its upper side and shaded under its lower curve (kept inside the body), so every
		// swell reads as its own rounded form; the curved shading lines follow the billows
		b.globalCompositeOperation = 'source-atop';
		b.filter = `blur(${H * .1 * k}px)`;
		tile(lobes, (l, lx) => {
			const gr = b.createLinearGradient(0, l.y - l.ry, 0, l.y + l.ry * .3);
			gr.addColorStop(0, rgba(B.top)); gr.addColorStop(1, rgba(B.top, 0));
			b.fillStyle = gr; b.beginPath(); b.ellipse(lx - l.rx * .08, l.y - l.ry * .3, l.rx * .85, l.ry * .75, 0, 0, 6.283); b.fill();
			b.strokeStyle = rgba(B.under, .22); b.lineWidth = Math.max(1, l.ry * .3);
			b.beginPath(); b.ellipse(lx, l.y + l.ry * .05, l.rx * .92, l.ry * .9, 0, Math.PI * .12, Math.PI * .88); b.stroke();
		});
		b.filter = 'none';
		// darker toward the underside
		const sh = b.createLinearGradient(0, y0 - H * .1, 0, y0 + (B.base - B.y) * H);
		sh.addColorStop(0, rgba(B.under, 0)); sh.addColorStop(1, rgba(B.under, .95));
		b.fillStyle = sh; b.fillRect(0, 0, BW, BH);
		// faint long streaks inside the bank
		b.filter = `blur(${H * .05 * k}px)`;
		for (let i = 0; i < BW / H * 1.2; i++) {
			const sx = rand(0, BW), sy = y0 + rand(-.15, .45) * H, light = Math.random() < .5;
			b.fillStyle = rgba(light ? B.top : B.under, rand(.12, .25));
			const rx = H * rand(1, 2.4), ry = H * rand(.03, .07);
			for (const o of [-BW, 0, BW]) { b.beginPath(); b.ellipse(sx + o, sy, rx, ry, 0, 0, 6.283); b.fill(); }
		}
		b.filter = 'none';
		// a lit copy of the same shape, for strikes lighting the bank from within
		const lit = cnv(BW * k, BH * k), lx = lit.getContext('2d');
		lx.drawImage(body, 0, 0); lx.globalCompositeOperation = 'source-in';
		const lg = lx.createLinearGradient(0, 0, 0, BH * k);
		lg.addColorStop(0, 'rgb(190,210,255)'); lg.addColorStop(.55, 'rgb(120,140,240)'); lg.addColorStop(1, 'rgb(40,50,120)');
		lx.fillStyle = lg; lx.fillRect(0, 0, BW * k, BH * k);
		return { c: body, lit, BW, BH, oy: (B.y - BANK_TOP) * H };
	}
	CONCEPTS.push({
		group: 'Lightning', id: 'light-a3', letter: 'A3', name: 'Thunderhead, layered',
		desc: 'A\'s bolts, flashes and blues, over layered cloud banks at up to four depths: scalloped rounded billows, gently bulging dark undersides, each drifting and slowly swelling at its own pace. The weather changes every cast: layered, towering, scattered, overcast, ragged squall (banks, cloud sizes, gaps, tint, drift, towers, torn edges and stray rows all differ)',
		spell: 'Lightning Bolt', padTop: .9, padBottom: .6, flash: [190, 215, 255],
		init(s) {
			const H = s.H, k = Math.min(2, window.devicePixelRatio || 1);
			const BW = Math.max(s.W, H * 8) + H * 4;
			const Wt = s.weather = WEATHERS[weatherTurn++ % WEATHERS.length];
			s.banks = Wt.banks.map(i => { const B = weatherBank(BANKS[i], Wt); return Object.assign(paintBank(B, BW, H, k), { B, u: rand(0, BW), ph: rand(0, 6.283), breath: rand(.03, .08), a: B.a }); });
			// stray rows: a faint copy of a bank drifting between the others at its own height and pace
			s.loose = [];
			for (let i = 0; i < 2; i++) if (Math.random() < Wt.stray) {
				const K = pick(s.banks);
				s.loose.push({ K, y: rand(-.3, .7) * H, a: rand(.25, .45), u: rand(0, BW), v: K.B.v * rand(.6, 1.6) * (Math.random() < .4 ? -1 : 1), ph: rand(0, 6.283) });
			}
			s.bolts = []; s.nextBolt = .15; s.flash = 0; s.flashX = 0; s.sheet = 0; s.sheetX = 0;
			s.roll = wobble(2);
		},
		draw(g, s) {
			const { H, fill, dt } = s, tint = s.weather.tint;
			g.save(); clipBar(g, s, fill);
			const bg = g.createLinearGradient(0, 0, 0, H);
			bg.addColorStop(0, rgba(tintCol([22, 26, 60], tint))); bg.addColorStop(.6, rgba(tintCol([14, 16, 49], tint))); bg.addColorStop(1, rgba(tintCol([7, 8, 26], tint)));
			g.fillStyle = bg; g.fillRect(0, 0, fill, H);
			// occasional dim sheet lightning somewhere in the banks
			if (Math.random() < dt * .8) { s.sheet = rand(.35, .6); s.sheetX = rand(0, fill); }
			s.sheet = Math.max(0, s.sheet - dt * 3);
			// the stray rows lie behind the banks they were copied from
			for (const L of s.loose) {
				L.u = ((L.u + L.v * H * dt) % L.K.BW + L.K.BW) % L.K.BW;
				g.globalAlpha = L.a;
				for (let x = -L.u; x < fill; x += L.K.BW) g.drawImage(L.K.c, x, L.y + Math.sin(s.t * .25 + L.ph) * H * .04, L.K.BW, L.K.BH);
				g.globalAlpha = 1;
			}
			for (const K of s.banks) {
				K.u = ((K.u + K.B.v * H * dt) % K.BW + K.BW) % K.BW;
				// slow rise and fall, and the billows slowly swelling (the bank breathes taller and shorter, pinned at its base)
				const sw = 1 + K.breath * Math.sin(s.t * .45 + K.ph * 1.7), bh = K.BH * sw;
				const y = K.oy + Math.sin(s.t * .3 + K.ph) * H * .03 - (bh - K.BH) * .6;
				const tiles = [];
				for (let x = -K.u; x < fill; x += K.BW) tiles.push(x);
				g.globalAlpha = K.B.a;
				for (const x of tiles) g.drawImage(K.c, x, y, K.BW, bh);
				// strikes and sheet lightning light the bank from within, fading with distance
				for (const [I, cx, reach] of [[s.flash * .5, s.flashX, H * 2.6], [s.sheet * .35, s.sheetX, H * 2]]) {
					if (I < .02) continue;
					// the lit copy of the bank, masked to a soft round glow around the strike
					const T = s.glowCnv || (s.glowCnv = cnv(1, 1)), k = Math.min(2, window.devicePixelRatio || 1);
					const tw = reach * 2, th = H * 3, ox = cx - reach, oy = -H;
					if (T.width !== Math.ceil(tw * k) || T.height !== Math.ceil(th * k)) { T.width = Math.ceil(tw * k); T.height = Math.ceil(th * k); }
					const t = T.getContext('2d');
					t.setTransform(k, 0, 0, k, 0, 0); t.globalCompositeOperation = 'source-over'; t.clearRect(0, 0, tw, th);
					for (const x of tiles) t.drawImage(K.lit, x - ox, y - oy, K.BW, bh);
					t.globalCompositeOperation = 'destination-in';
					const mg = t.createRadialGradient(reach, H * 1.5, 0, reach, H * 1.5, reach);
					mg.addColorStop(0, 'rgba(0,0,0,1)'); mg.addColorStop(.5, 'rgba(0,0,0,.45)'); mg.addColorStop(1, 'rgba(0,0,0,0)');
					t.fillStyle = mg; t.fillRect(0, 0, tw, th);
					g.globalCompositeOperation = 'lighter'; g.globalAlpha = I * K.B.a;
					g.drawImage(T, ox, oy, tw, th);
					g.globalCompositeOperation = 'source-over';
				}
				g.globalAlpha = 1;
			}
			// a whole-cloud flash behind the strike
			if (s.flash > 0) {
				g.globalCompositeOperation = 'lighter';
				const fg = g.createRadialGradient(s.flashX, H / 2, 0, s.flashX, H / 2, H * 2.5);
				fg.addColorStop(0, rgba([110, 140, 255], .2 * s.flash)); fg.addColorStop(1, rgba([110, 140, 255], 0));
				g.fillStyle = fg; g.fillRect(0, 0, fill, H); g.globalCompositeOperation = 'source-over';
			}
			s.flash = Math.max(0, s.flash - dt * 5);
			// strikes, as in A
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
			// the cloud's leading edge glows faintly, with a static flicker now and then
			if (s.casting && fill > 2) {
				g.save(); clipBar(g, s, fill);
				const e = fill, eg = g.createLinearGradient(e - H * 1.2, 0, e, 0), f = .25 + .2 * (s.roll(s.t * 6) + 1) / 2 + (Math.random() < .08 ? .3 : 0);
				eg.addColorStop(0, 'rgba(120,150,255,0)'); eg.addColorStop(1, rgba([150, 180, 255], f));
				g.globalCompositeOperation = 'lighter'; g.fillStyle = eg; g.fillRect(e - H * 1.2, 0, H * 1.2, H);
				g.restore();
				// the leading-edge spark every spell look has (the addon's spark texture), in the bolts' blue-white
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

	// ------------------------------------------------------------------ A2: grey cumulonimbus, lit from inside
	// The cloud is a heap of many small rounded puffs (pre-rendered sprites): each puff is lighter on
	// top and shadowed underneath, and lower puffs overlap the ones above, so the mass reads as the
	// cauliflower billows of a storm cloud. No bolts are drawn; lightning only lights the cloud from
	// within, brightest on the back puffs so the front ones stand dark against it.
	const PUFF = 96;
	function canvas(n) { const c = document.createElement('canvas'); c.width = c.height = n; return c; }
	// A cauliflower puff: a small heap of rounded bumps, each lit on top and shadowed underneath.
	// Lower bumps are drawn over the upper ones, so their lit tops sit against the dark undersides
	// above them, the crevices of a real cumulus.
	function puffSprite(top, mid, under) {
		const S = PUFF, raw = canvas(S), x = raw.getContext('2d'), bumps = [];
		const n = Math.floor(rand(5, 8));
		for (let i = 0; i < n; i++) {
			const a = rand(0, 6.283), d = S * rand(0, .17);
			bumps.push({ x: S / 2 + Math.cos(a) * d * 1.2, y: S / 2 + Math.sin(a) * d * .8, r: S * rand(.14, .24) });
		}
		bumps.push({ x: S / 2, y: S * .55, r: S * .26 });   // a broad core so the puff holds together
		bumps.sort((a, b) => a.y - b.y);
		for (const b of bumps) {
			const vg = x.createLinearGradient(0, b.y - b.r, 0, b.y + b.r);
			vg.addColorStop(0, rgba(top)); vg.addColorStop(.5, rgba(mid)); vg.addColorStop(1, rgba(under));
			x.fillStyle = vg; x.beginPath(); x.arc(b.x, b.y, b.r, 0, 6.283); x.fill();
			// a soft light catching the upper left of the bump
			const hg = x.createRadialGradient(b.x - b.r * .3, b.y - b.r * .45, 0, b.x - b.r * .3, b.y - b.r * .45, b.r * .75);
			hg.addColorStop(0, rgba(mix(top, [215, 215, 222], .28), .32)); hg.addColorStop(1, rgba(top, 0));
			x.fillStyle = hg; x.beginPath(); x.arc(b.x, b.y, b.r, 0, 6.283); x.fill();
		}
		// soften the outline a touch, the way cloud edges blur
		const cv = canvas(S), y = cv.getContext('2d');
		y.filter = 'blur(2px)'; y.drawImage(raw, 0, 0);
		return cv;
	}
	// a ragged wisp: a loose cluster of faint blobs, for the torn edges at the cloud's front
	function wispSprite(col) {
		const S = PUFF, cv = canvas(S), x = cv.getContext('2d');
		for (let i = 0; i < 12; i++) {
			const px = S * (.5 + rand(-.36, .36)), py = S * (.5 + rand(-.22, .22)), r = S * rand(.09, .2);
			const gr = x.createRadialGradient(px, py, 0, px, py, r);
			gr.addColorStop(0, rgba(col, .35)); gr.addColorStop(1, rgba(col, 0));
			x.fillStyle = gr; x.fillRect(px - r, py - r, r * 2, r * 2);
		}
		return cv;
	}
	function glowSprite(col) {
		const S = PUFF, cv = canvas(S), x = cv.getContext('2d');
		const gr = x.createRadialGradient(S / 2, S * .45, 0, S / 2, S / 2, S / 2);
		gr.addColorStop(0, rgba(col, 1)); gr.addColorStop(.5, rgba(col, .45)); gr.addColorStop(1, rgba(col, 0));
		x.fillStyle = gr; x.fillRect(0, 0, S, S);
		return cv;
	}
	let SPR = null;
	const sprites = () => SPR || (SPR = {
		// back puffs are lighter grey, front ones charcoal: depth reads from tone, as in a real thunderhead
		back: [0, 1, 2].map(() => puffSprite([118, 118, 127], [80, 80, 89], [44, 44, 52])),
		mid: [0, 1, 2].map(() => puffSprite([96, 96, 105], [62, 62, 71], [30, 30, 37])),
		front: [0, 1, 2].map(() => puffSprite([64, 64, 72], [36, 36, 43], [12, 12, 16])),
		wisp: wispSprite([110, 110, 118]),
		glow: glowSprite([205, 208, 255]),
	});
	// One depth layer of puffs spread along the whole bar. Each puff appears as the fill reaches it.
	function puffLayer(s, o) {
		const H = s.H, puffs = [];
		const n = Math.round((s.W + H * 2) / H * o.density);
		for (let i = 0; i < n; i++) {
			const x = rand(-H * .5, s.W + H * .5);
			// a lumpy upper outline: tops rise and fall along the bar, puffs fill in below it
			const y = H * (o.y[0] + (o.y[1] - o.y[0]) * Math.random());
			puffs.push({ x, y, r: H * rand(...o.r), tone: Math.floor(Math.random() * 3), ph: rand(0, 6.283), m: rand(.15, .45), born: -1 });
		}
		puffs.sort((a, b) => a.y - b.y);   // upper puffs first; lower ones overlap their shadowed undersides
		return { puffs, spr: o.spr, lit: o.lit, a: o.a ?? 1 };
	}
	function drawPuffs(g, s, L, lightAt) {
		const H = s.H, spr = sprites(), list = spr[L.spr];
		for (const q of L.puffs) {
			if (q.x - q.r * .3 > s.fill) continue;
			if (q.born < 0) q.born = s.t;
			const grow = easeOut(clamp((s.t - q.born) / .5));
			// slow churn: each puff swells and drifts a little on its own cycle
			const r = q.r * (.55 + .45 * grow) * (1 + .06 * Math.sin(s.t * q.m + q.ph));
			const x = q.x + Math.sin(s.t * q.m * .7 + q.ph) * H * .04, y = q.y - Math.sin(s.t * q.m * .5 + q.ph * 2) * H * .03;
			g.globalCompositeOperation = 'source-over'; g.globalAlpha = L.a * grow;
			g.drawImage(list[q.tone], x - r, y - r, r * 2, r * 2);
			const I = lightAt(x, y);
			if (I > .02 && L.lit > 0) {
				g.globalCompositeOperation = 'lighter'; g.globalAlpha = Math.min(1, I * L.lit) * grow;
				g.drawImage(spr.glow, x - r, y - r, r * 2, r * 2);
			}
		}
		g.globalAlpha = 1; g.globalCompositeOperation = 'source-over';
	}
	// A flash: 2-4 quick pulses that each decay fast, so it flickers like real lightning in a cloud.
	function flashLevel(l) {
		let k = 0;
		for (const p of l.pulses) if (l.age >= p.t) k += p.k * Math.exp(-(l.age - p.t) / .055);
		return Math.min(1.2, k);
	}
	CONCEPTS.push({
		group: 'Lightning', id: 'light-a2', letter: 'A2', name: 'Thunderhead, dark',
		desc: 'A grey storm cloud of countless billowing puffs; lightning only shows as flashes lighting the cloud from inside', spell: 'Lightning Bolt',
		padTop: .9, padBottom: .6, flash: [200, 205, 235],
		init(s) {
			s.layers = [
				puffLayer(s, { density: 3.2, y: [.1, .55], r: [.42, .7], spr: 'back', lit: .8 }),
				puffLayer(s, { density: 3.6, y: [.35, .85], r: [.36, .6], spr: 'mid', lit: .55 }),
				puffLayer(s, { density: 3, y: [.7, 1.1], r: [.32, .55], spr: 'front', lit: .18 }),
			];
			s.wisps = [];
			for (let x = 0; x < s.W + s.H; x += s.H * rand(.25, .5)) s.wisps.push({ x, y: rand(.1, .9) * s.H, r: s.H * rand(.3, .55), ph: rand(0, 6.283) });
			s.lights = []; s.nextStrike = rand(.3, .6); s.nextSheet = rand(.4, 1);
		},
		draw(g, s) {
			const { H, fill, dt } = s;
			g.save(); roundRectPath(g, 0, 0, s.W, H, H * .18); g.clip();
			// the darkness inside the storm, behind the puffs
			if (fill > 0) {
				const bg = g.createLinearGradient(0, 0, 0, H);
				bg.addColorStop(0, '#2a2a30'); bg.addColorStop(1, '#101014');
				g.fillStyle = bg; g.fillRect(0, 0, Math.max(0, fill - H * 1.2), H);
				// fade it out toward the front, so the cloud's edge is its puffs, not a straight line
				const x0 = Math.max(0, fill - H * 1.2), fg = g.createLinearGradient(x0, 0, fill, 0);
				fg.addColorStop(0, 'rgba(30,30,36,1)'); fg.addColorStop(1, 'rgba(30,30,36,0)');
				g.fillStyle = fg; g.fillRect(x0, 0, fill - x0, H);
			}
			for (const l of s.lights) l.age += dt;
			s.lights = s.lights.filter(l => l.age < l.life);
			const lightAt = (x, y) => {
				let I = 0;
				for (const l of s.lights) I += flashLevel(l) * Math.exp(-((x - l.x) ** 2) / (2 * (l.rx * H) ** 2) - ((y - l.y) ** 2) / (2 * (.9 * H) ** 2));
				return I;
			};
			// strikes: a bright flickering flash somewhere inside the cloud
			s.nextStrike -= dt;
			if (s.casting && s.nextStrike <= 0 && fill > H * 1.2) {
				s.nextStrike = rand(.35, .9);
				const n = Math.floor(rand(2, 5)), pulses = [];
				let t = 0;
				for (let i = 0; i < n; i++) { pulses.push({ t, k: i ? rand(.45, .9) : 1 }); t += rand(.05, .11); }
				s.lights.push({ x: rand(H * .4, fill - H * .4), y: rand(.15, .5) * H, age: 0, life: t + .35, rx: rand(.9, 1.6), pulses });
			}
			// sheet lightning: a dim, wide flicker deep in the cloud
			s.nextSheet -= dt;
			if (s.casting && s.nextSheet <= 0 && fill > H) {
				s.nextSheet = rand(.5, 1.4);
				s.lights.push({ x: rand(0, fill), y: rand(.2, .6) * H, age: 0, life: .4, rx: rand(2, 3.5), pulses: [{ t: 0, k: rand(.2, .35) }, { t: rand(.06, .12), k: rand(.15, .3) }] });
			}
			// a soft glow behind the puffs where a flash is, so gaps between them light up too
			g.globalCompositeOperation = 'lighter';
			for (const l of s.lights) {
				const k = flashLevel(l), r = H * l.rx * 1.6;
				if (k < .02) continue;
				const fg = g.createRadialGradient(l.x, l.y, 0, l.x, l.y, r);
				fg.addColorStop(0, rgba([170, 175, 235], .35 * k)); fg.addColorStop(1, rgba([170, 175, 235], 0));
				g.fillStyle = fg; g.fillRect(l.x - r, 0, r * 2, H);
			}
			g.globalCompositeOperation = 'source-over';
			for (const L of s.layers) drawPuffs(g, s, L, lightAt);
			// torn wisps trailing off the cloud's front
			if (s.casting && fill > 2) {
				const spr = sprites();
				for (const w of s.wisps) {
					const d = w.x - fill;
					if (d < -H * .6 || d > H * .5) continue;
					g.globalAlpha = .55 * clamp(1 - Math.abs(d + H * .1) / (H * .6));
					const x = w.x + Math.sin(s.t * .8 + w.ph) * H * .06;
					g.drawImage(spr.wisp, x - w.r, w.y - w.r * .6, w.r * 2, w.r * 1.2);
				}
				g.globalAlpha = 1;
			}
			g.restore();
		},
	});

	// ------------------------------------------------------------------ B: riding arc and plasma ball
	CONCEPTS.push({
		group: 'Lightning', id: 'light-b', letter: 'B', name: 'Riding arc',
		desc: 'One arc from the bar\'s start to a crackling plasma ball at the cast edge', spell: 'Chain Lightning',
		padTop: 1.0, padBottom: .9, flash: [170, 225, 255],
		init(s) {
			s.jagT = 0; s.main = null; s.side = []; s.crackle = []; s.yW = wobble(3); s.pulse = wobble(6);
		},
		draw(g, s) {
			const { W, H, fill, dt } = s;
			const cy = H / 2 + s.yW(s.t) * H * .08;
			// charged channel behind the arc
			g.save(); clipBar(g, s, fill);
			const bg = g.createLinearGradient(0, 0, fill, 0);
			bg.addColorStop(0, '#060c22'); bg.addColorStop(1, '#0d2150');
			g.fillStyle = bg; g.fillRect(0, 0, fill, H);
			const vg = g.createLinearGradient(0, 0, 0, H);
			vg.addColorStop(0, 'rgba(60,120,255,0)'); vg.addColorStop(.5, 'rgba(60,140,255,.22)'); vg.addColorStop(1, 'rgba(60,120,255,0)');
			g.globalCompositeOperation = 'lighter'; g.fillStyle = vg; g.fillRect(0, 0, fill, H); g.globalCompositeOperation = 'source-over';
			// re-jag the arcs every few frames
			s.jagT -= dt;
			if (s.jagT <= 0 && fill > H * .4) {
				s.jagT = rand(.04, .08);
				const x0 = H * .15, lv = Math.min(7, 3 + Math.floor(Math.log2(Math.max(2, fill / H))));
				s.main = jag(x0, H / 2 + rand(-.15, .15) * H, fill, cy, H * .3, lv);
				s.side = [];
				for (let i = 0; i < 2; i++) s.side.push(jag(x0, rand(.2, .8) * H, fill, cy + rand(-.1, .1) * H, H * .45, lv));
			}
			if (s.main && fill > H * .4) {
				for (const p of s.side) drawBolt(g, p, Math.max(.7, H * .025), [90, 150, 255], .45);
				drawBolt(g, s.main, Math.max(1, H * .05), [110, 190, 255], 1);
			}
			g.restore();
			if (!s.casting || fill < 2) return;
			// the plasma ball, free to spill past the bar
			const pr = H * (.55 + .08 * s.pulse(s.t));
			glow(g, fill, cy, Math.min(pr * 2.4, H * .68 + W - fill, H * .95), [70, 140, 255], .35);   // stays inside the canvas
			glow(g, fill, cy, pr, [150, 210, 255], .8);
			glow(g, fill, cy, pr * .35, [255, 255, 255], .95);
			// tendrils crackling out of the ball
			if (Math.random() < dt * 30) {
				const a = rand(0, 6.283), r = H * rand(.6, 1.2);
				s.crackle.push({ pts: jag(fill, cy, fill + Math.cos(a) * r, cy + Math.sin(a) * r, H * .18, 3), age: 0, life: rand(.05, .12) });
			}
			for (const c of s.crackle) { c.age += dt; drawBolt(g, c.pts, Math.max(.6, H * .03), [140, 200, 255], 1 - c.age / c.life); }
			s.crackle = s.crackle.filter(c => c.age < c.life);
			if (Math.random() < dt * 14) sparks(s, fill, cy, Math.ceil(rand(1, 4)), [170, 220, 255], 1);
			s.parts.update(dt); s.parts.draw(g);
		},
	});

	// ------------------------------------------------------------------ C: charged conduit
	CONCEPTS.push({
		group: 'Lightning', id: 'light-c', letter: 'C', name: 'Charged conduit',
		desc: 'Writhing plasma filaments in a glass tube; arcs leap out as it charges, a bolt strikes at the end', spell: 'Thunderstorm',
		padTop: 2.2, padBottom: .9, flash: [210, 190, 255],
		init(s) {
			s.fil = [];
			for (let i = 0; i < 4; i++) s.fil.push({ n: noise1(), n2: noise1(), sp: rand(.8, 1.6), col: pick([[170, 120, 255], [110, 190, 255], [200, 150, 255], [120, 220, 255]]) });
			s.leaps = []; s.leapT = .4; s.strike = null;
		},
		draw(g, s) {
			const { W, H, fill, dt, p } = s;
			// glass tube: dark everywhere, so the empty part reads as unpowered glass
			g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
			const tg = g.createLinearGradient(0, 0, 0, H);
			tg.addColorStop(0, 'rgba(90,100,140,.35)'); tg.addColorStop(.18, 'rgba(20,22,40,.2)'); tg.addColorStop(.85, 'rgba(10,10,25,.2)'); tg.addColorStop(1, 'rgba(70,80,120,.3)');
			g.fillStyle = tg; g.fillRect(0, 0, W, H);
			// powered part
			g.beginPath(); g.rect(0, 0, fill, H); g.clip();
			const charge = .5 + .5 * p;
			const bg = g.createLinearGradient(0, 0, 0, H);
			bg.addColorStop(0, '#120a2e'); bg.addColorStop(.5, rgba(mix([30, 16, 70], [60, 40, 140], charge))); bg.addColorStop(1, '#0c0722');
			g.fillStyle = bg; g.fillRect(0, 0, fill, H);
			// filaments: each a noise curve along the tube, pinned to the centre at both ends
			for (const f of s.fil) {
				const pts = [], step = Math.max(3, H * .12);
				for (let x = 0; x <= fill + step; x += step) {
					const xx = Math.min(x, fill), pin = clamp(xx / (H * .8)) * clamp((fill - xx) / (H * .5));
					const y = H / 2 + (f.n(xx / (H * 1.4) - s.t * f.sp) * .7 + f.n2(xx / (H * .45) + s.t * 2.3) * .3) * H * .38 * pin;
					pts.push([xx, y]);
				}
				drawBolt(g, pts, Math.max(.6, H * .028), f.col, .55 + .35 * charge);
			}
			// bright core where the filaments meet the cast edge
			glow(g, fill, H / 2, H * .8, [180, 150, 255], .5 * charge);
			g.restore();
			// glass highlight over the whole tube
			g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
			const hl = g.createLinearGradient(0, 0, 0, H * .45);
			hl.addColorStop(0, 'rgba(255,255,255,.22)'); hl.addColorStop(1, 'rgba(255,255,255,0)');
			g.fillStyle = hl; g.fillRect(H * .1, H * .08, W - H * .2, H * .3); g.restore();
			// arcs leap out of the tube, more often as it charges
			s.leapT -= dt;
			if (s.casting && s.leapT <= 0 && fill > H) {
				s.leapT = lerp(.55, .1, p) * rand(.6, 1.3);
				const x = rand(H * .4, fill - H * .2), up = Math.random() < .65, len = H * rand(.6, 1.1 + p * .8);
				const ex = x + rand(-.6, .6) * H;
				s.leaps.push({ segs: forked(x, up ? 0 : H, ex, up ? -len : H + len * .6, H * .25, Math.random() < .4 ? 1 : 0, 4), age: 0, life: rand(.08, .16), x, up });
			}
			for (const l of s.leaps) {
				l.age += dt;
				for (const sg of l.segs) drawBolt(g, sg.pts, Math.max(.7, H * .035) * sg.w, [170, 150, 255], 1 - l.age / l.life);
				glow(g, l.x, l.up ? 0 : H, H * .5, [190, 170, 255], .5 * (1 - l.age / l.life));
			}
			s.leaps = s.leaps.filter(l => l.age < l.life);
			// on completion a bolt drops from above onto the bar
			if (s.done) {
				if (!s.strike) {
					const x = rand(.35, .75) * W;
					s.strike = { x, segs: forked(x + rand(-1, 1) * H, -H * 2.1, x, H * .5, H * .5, 3, 6), regen: 0 };
					sparks(s, x, H * .2, 14, [210, 200, 255], 1.4);
				}
				const k = s.strike, a = clamp(1 - s.doneT / .6);
				k.regen -= dt;
				if (k.regen <= 0 && a > 0) { k.regen = .05; k.segs = forked(k.x + rand(-1, 1) * H * .5, -H * 2.1, k.x, H * .5, H * .5, 3, 6); }
				if (a > 0) {
					for (const sg of k.segs) drawBolt(g, sg.pts, Math.max(1.2, H * .07) * sg.w, [190, 170, 255], a);
					glow(g, k.x, H * .5, H * 2, [170, 150, 255], .6 * a);
				}
			}
			s.parts.update(dt); s.parts.draw(g);
		},
	});
})();
