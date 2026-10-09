// Smelting D: an intricate foundry line. A whole smelting works stands along the bar - a stone furnace,
// a bellows hearth, an ore hopper over a crucible, a crucible on a swivel, a sluice gate, stepped ingot
// moulds, a launder cooled over a quench trough, a hanging ladle - joined by clay launders and pipes.
// The molten metal works its way from station to station with the cast, each one waking as it
// arrives, and spills off the head of the run into the bar, where it is thick and slow.
(() => {
	const PI = Math.PI, PI2 = PI * 2;

	// temperature (0 cold .. 1 fresh) -> colour; the hottest stop stays short of white so text reads
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
	const shadeC = (c, k) => [c[0] * k, c[1] * k, c[2] * k];
	// a small seeded random, so painted detail (bricks, soot, grain) holds still from frame to frame
	function rng(seed) {
		let a = (seed * 1e6) | 0;
		return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
	}
	function glow(g, x, y, r, c, a) {
		if (a <= .005 || r <= .5) return;
		const gr = g.createRadialGradient(x, y, 0, x, y, r);
		gr.addColorStop(0, rgba(c, a)); gr.addColorStop(1, rgba(c, 0));
		g.globalCompositeOperation = 'lighter'; g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
		g.globalCompositeOperation = 'source-over';
	}
	function sparks(s, x, y, n, spread = 1, up = 1) {
		const H = s.H;
		for (let i = 0; i < n; i++) {
			const a = -PI / 2 + rand(-1.1, 1.1) * spread, v = H * rand(1.8, 4.5) * up;
			s.parts.emit({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, ay: H * 12, drag: .6, life: rand(.3, .7),
				size: Math.max(.7, H * rand(.025, .05)), color: pick([[255, 210, 110], [255, 160, 50], [255, 240, 170]]), kind: 'spark', layer: 'top' });
		}
	}
	function smokePuff(s, x, y, warm, alpha, size = 1) {
		const H = s.H;
		s.parts.emit({ x: x + rand(-.08, .08) * H, y, vx: rand(-.1, .25) * H, vy: -H * rand(.5, .9), drag: .35, life: rand(1.2, 2),
			size: H * rand(.1, .18) * size, grow: H * .45 * size, color: mix([96, 92, 94], [255, 150, 80], warm), alpha, kind: 'smoke', layer: 'top' });
	}
	function steamPuff(s, x, y, alpha) {
		const H = s.H;
		s.parts.emit({ x: x + rand(-.15, .15) * H, y, vx: rand(-.2, .2) * H, vy: -H * rand(.7, 1.3), drag: .8, life: rand(.7, 1.2),
			size: H * rand(.08, .14), grow: H * .55, color: [228, 230, 236], alpha, kind: 'smoke', layer: 'top' });
	}
	function plateShape(r) {
		const n = 5 + Math.floor(rand(0, 3)), pts = [];
		for (let i = 0; i < n; i++) { const a = (i + rand(-.3, .3)) / n * PI2, d = r * rand(.7, 1.1); pts.push([Math.cos(a) * d, Math.sin(a) * d * .75]); }
		return pts;
	}
	function polyPath(g, x, y, pts) {
		g.beginPath(); pts.forEach(([px, py], i) => i ? g.lineTo(x + px, y + py) : g.moveTo(x + px, y + py)); g.closePath();
	}
	function rot(x, y, a) { const c = Math.cos(a), sn = Math.sin(a); return [x * c - y * sn, x * sn + y * c]; }

	// ---- painterly surfaces: soft gradients, a faint dark edge rather than an outline
	const IRON = { hi: [126, 124, 130], mid: [70, 69, 75], lo: [30, 29, 33] };
	const STONE = { hi: [142, 132, 120], mid: [98, 90, 82], lo: [52, 47, 43] };
	const CLAY = { hi: [168, 108, 72], mid: [120, 72, 46], lo: [62, 36, 24] };
	const WOOD = { hi: [140, 98, 60], mid: [96, 64, 38], lo: [48, 32, 20] };
	const LEATHER = { hi: [120, 80, 52], mid: [80, 50, 32], lo: [38, 24, 16] };
	function paint(g, path, x0, y0, x1, y1, m, edgeW) {
		const gr = g.createLinearGradient(x0, y0, x1, y1);
		gr.addColorStop(0, rgba(m.hi)); gr.addColorStop(.45, rgba(m.mid)); gr.addColorStop(1, rgba(m.lo));
		path(); g.fillStyle = gr; g.fill();
		if (edgeW) { path(); g.strokeStyle = 'rgba(14,10,8,.45)'; g.lineWidth = edgeW; g.stroke(); }
	}
	// warm light from the molten metal falling on a surface
	function warmLight(g, path, x, y, r, a) {
		if (a <= .01) return;
		g.save(); path(); g.clip();
		const gr = g.createRadialGradient(x, y, 0, x, y, r);
		gr.addColorStop(0, `rgba(255,140,50,${a})`); gr.addColorStop(1, 'rgba(255,120,40,0)');
		g.globalCompositeOperation = 'lighter'; g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
		g.restore();
	}
	// stone courses: staggered blocks of slightly different shades over dark mortar (path must be clipped)
	function masonry(g, x, y, w, h, bh, seed, m) {
		const R = rng(seed);
		g.fillStyle = rgba(shadeC(m.lo, .8)); g.fillRect(x, y, w, h);
		const gap = Math.max(.6, bh * .1);
		for (let r = 0, yy = y; yy < y + h; r++, yy += bh) {
			const bw = bh * (1.7 + R() * .5);
			for (let xx = x - (r % 2 ? bw * .5 : R() * bw * .3); xx < x + w; xx += bw) {
				const k = .82 + R() * .3;
				const gr = g.createLinearGradient(0, yy, 0, yy + bh);
				gr.addColorStop(0, rgba(shadeC(m.hi, k))); gr.addColorStop(1, rgba(shadeC(m.mid, k)));
				g.fillStyle = gr; g.fillRect(xx + gap / 2, yy + gap / 2, bw - gap, bh - gap);
			}
		}
		// shade the sides so the mass reads as round/solid
		const sg = g.createLinearGradient(x, 0, x + w, 0);
		sg.addColorStop(0, 'rgba(0,0,0,.35)'); sg.addColorStop(.35, 'rgba(0,0,0,0)'); sg.addColorStop(1, 'rgba(0,0,0,.45)');
		g.fillStyle = sg; g.fillRect(x, y, w, h);
	}
	function soot(g, x, y, w, h, a) {
		const gr = g.createLinearGradient(0, y, 0, y + h);
		gr.addColorStop(0, `rgba(12,10,10,${a})`); gr.addColorStop(1, 'rgba(12,10,10,0)');
		g.fillStyle = gr; g.fillRect(x, y, w, h);
	}

	// a small open crucible (clay-graphite), centre-top at (x, y), width w; heat 0..1 lights the metal inside
	function crucible(g, x, y, w, hot, full) {
		const h = w * .95, ew = Math.max(.6, w * .04);
		const body = () => { g.beginPath(); g.moveTo(x - w / 2, y); g.quadraticCurveTo(x - w * .52, y + h * .8, x - w * .3, y + h); g.lineTo(x + w * .3, y + h); g.quadraticCurveTo(x + w * .52, y + h * .8, x + w / 2, y); g.closePath(); };
		paint(g, body, x - w / 2, y, x + w / 2, y + h, { hi: [92, 84, 82], mid: [58, 52, 52], lo: [24, 22, 24] }, ew);
		warmLight(g, body, x, y, w * 1.1, .35 * hot);
		// the rim and the metal inside
		g.fillStyle = 'rgba(20,16,16,.95)'; g.beginPath(); g.ellipse(x, y, w / 2, w * .13, 0, 0, PI2); g.fill();
		if (full > .02) {
			g.fillStyle = rgba(heat(.45 + .5 * hot)); g.beginPath(); g.ellipse(x, y + w * .02, w * .43 * Math.sqrt(full), w * .1 * Math.sqrt(full), 0, 0, PI2); g.fill();
			glow(g, x, y, w * .9, heat(.8), .45 * hot * full);
		}
		g.strokeStyle = 'rgba(150,140,135,.5)'; g.lineWidth = ew; g.beginPath(); g.ellipse(x, y, w / 2, w * .13, 0, PI * 1.05, PI * 1.95); g.stroke();
	}

	// ---------------------------------------------------------------- stations
	// Each station sits on the bar's top edge (y = 0; up is negative), built in units of S.
	// build sets in/out (where the metal enters and leaves); draw(g, s, st, act) paints it, act 0..1 since the metal arrived.
	const K = {};
	K.furnace = {   // a tapering stone bloomery: glowing mouth, a stack that smokes, a tap hole low on the right
		build(st, S) { st.out = [st.x + S * .44, -S * .2]; st.in = st.out; st.top = -S * 1.95; },
		draw(g, s, st, act) {
			const S = st.S, x = st.x, R = rng(st.seed), fl = .75 + .25 * Math.sin(s.t * 9 + st.seed) * Math.sin(s.t * 3.7);
			const body = () => { g.beginPath(); g.moveTo(x - S * .48, 0); g.lineTo(x - S * .3, -S * 1.42); g.lineTo(x + S * .3, -S * 1.42); g.lineTo(x + S * .48, 0); g.closePath(); };
			g.save(); body(); g.clip();
			masonry(g, x - S * .5, -S * 1.45, S, S * 1.45, S * .17, st.seed, STONE);
			soot(g, x - S * .5, -S * 1.45, S, S * .7, .55);
			g.restore();
			body(); g.strokeStyle = 'rgba(14,10,8,.4)'; g.lineWidth = Math.max(.6, S * .03); g.stroke();
			// the stack
			const stack = () => { g.beginPath(); g.rect(x - S * .13, -S * 1.95, S * .26, S * .55); };
			g.save(); stack(); g.clip(); masonry(g, x - S * .13, -S * 1.95, S * .26, S * .55, S * .12, st.seed + 1, STONE); soot(g, x - S * .13, -S * 1.95, S * .26, S * .5, .7); g.restore();
			g.fillStyle = 'rgba(20,16,14,.9)'; g.fillRect(x - S * .16, -S * 1.98, S * .32, S * .06);
			// the mouth: an arch that glows from the fire inside, brighter as the metal is tapped
			const my = -S * .5, mr = S * .17;
			const mouth = () => { g.beginPath(); g.moveTo(x - mr, my + mr * .9); g.lineTo(x - mr, my); g.arc(x, my, mr, PI, 0); g.lineTo(x + mr, my + mr * .9); g.closePath(); };
			const fire = .55 + .45 * act;
			mouth(); const mg = g.createLinearGradient(0, my - mr, 0, my + mr);
			mg.addColorStop(0, rgba(heat(.62 * fire * fl))); mg.addColorStop(1, rgba(heat(.95 * fire)));
			g.fillStyle = mg; g.fill();
			g.strokeStyle = 'rgba(60,40,30,.8)'; g.lineWidth = Math.max(.8, S * .05); mouth(); g.stroke();
			glow(g, x, my + mr * .3, S * .75, [255, 140, 50], .32 * fire * fl);
			// tap hole with a little spout; once tapped, the metal shows in it
			const [tx, ty] = st.out;
			g.fillStyle = rgba(CLAY.mid); g.beginPath(); g.moveTo(tx - S * .1, ty - S * .05); g.lineTo(tx + S * .05, ty - S * .02); g.lineTo(tx + S * .05, ty + S * .05); g.lineTo(tx - S * .1, ty + S * .07); g.closePath(); g.fill();
			if (act > 0) { g.fillStyle = rgba(heat(.9)); g.beginPath(); g.ellipse(tx - S * .02, ty, S * .05, S * .025, 0, 0, PI2); g.fill(); glow(g, tx, ty, S * .35, [255, 150, 60], .4 * act); }
			// smoke from the stack the whole time, heavier once it is tapped
			st.acc = (st.acc || 0) + s.dt * (3 + 4 * act);
			while (st.acc >= 1) { st.acc--; smokePuff(s, x, -S * 2, .12 + .1 * act, .26, S / s.H); }
			if (Math.random() < s.dt * 6 * fire) s.parts.emit({ x: x + rand(-.05, .05) * S, y: -S * 1.98, vx: rand(-.2, .2) * S, vy: -S * rand(1.5, 2.6), drag: .5, life: rand(.4, .8), size: Math.max(.6, S * .025), color: [255, 170, 70], kind: 'spark', layer: 'top' });
		},
	};
	K.hearth = {   // a stone hearth of coals with a crucible in it; leather bellows pump and the coals flare
		build(st, S) { st.in = [st.x, -S * .78]; st.out = [st.x + S * .36, -S * .32]; st.top = -S * .85; },
		draw(g, s, st, act) {
			const S = st.S, x = st.x, ew = Math.max(.6, S * .03);
			const pump = Math.max(0, Math.sin(s.t * 4.2 + st.seed)), flare = (.35 + .65 * act) * (.6 + .4 * pump);
			// bellows: two boards hinged at the nozzle, leather pleats between them
			const bx = x - S * .42, by = -S * .3, open = S * (.06 + .1 * (1 - pump));
			const leather = () => { g.beginPath(); g.moveTo(bx, by); g.lineTo(bx - S * .38, by - open - S * .05); g.lineTo(bx - S * .4, by + S * .02 + open * .3); g.closePath(); };
			paint(g, leather, bx - S * .4, by - open, bx, by + open, LEATHER, ew);
			g.strokeStyle = 'rgba(30,18,12,.5)'; g.lineWidth = ew;
			for (let k = 1; k < 4; k++) { const u = k / 4; g.beginPath(); g.moveTo(bx - S * .38 * u, by - (open + S * .05) * u); g.lineTo(bx - S * .4 * u, by + (S * .02 + open * .3) * u); g.stroke(); }
			g.strokeStyle = rgba(WOOD.mid); g.lineWidth = Math.max(1, S * .05); g.lineCap = 'round';
			g.beginPath(); g.moveTo(bx, by - S * .01); g.lineTo(bx - S * .44, by - open - S * .08); g.stroke();
			g.strokeStyle = rgba(IRON.mid); g.lineWidth = Math.max(1, S * .04); g.beginPath(); g.moveTo(bx, by); g.lineTo(bx + S * .1, by + S * .02); g.stroke();
			// the hearth box
			const box = () => { g.beginPath(); g.rect(x - S * .36, -S * .42, S * .76, S * .42); };
			g.save(); box(); g.clip(); masonry(g, x - S * .36, -S * .42, S * .76, S * .42, S * .14, st.seed, STONE); g.restore();
			box(); g.strokeStyle = 'rgba(14,10,8,.4)'; g.lineWidth = ew; g.stroke();
			// coals heaped on top, glowing with each pump
			const R = rng(st.seed + 3);
			for (let k = 0; k < 9; k++) {
				const cx = x - S * .3 + R() * S * .62, cy = -S * .43 - R() * S * .06, r = S * (.045 + R() * .035);
				g.fillStyle = rgba(mix([30, 24, 22], heat(.55 + .4 * flare), clamp(flare * (.5 + R() * .6)))); g.beginPath(); g.arc(cx, cy, r, 0, PI2); g.fill();
			}
			glow(g, x, -S * .45, S * .6, [255, 120, 40], .35 * flare);
			crucible(g, x, -S * .78, S * .36, act * (.7 + .3 * flare), act);
			// a clay spout out of the hearth's side for the metal to leave by
			const [ox, oy] = st.out;
			g.fillStyle = rgba(CLAY.mid); g.fillRect(ox - S * .06, oy - S * .03, S * .08, S * .07);
			if (act > .5) glow(g, ox, oy, S * .3, [255, 150, 60], .35);
			if (pump > .95 && Math.random() < .5) sparks(s, x + rand(-.2, .2) * S, -S * .5, 2, .6, S / s.H * .7);
		},
	};
	K.hopper = {   // an ore hopper on legs drops ore down a chute into a crucible, where it melts into the run
		build(st, S) { st.in = [st.x + S * .02, -S * .5]; st.out = [st.x + S * .3, -S * .44]; st.top = -S * 1.8; },
		draw(g, s, st, act) {
			const S = st.S, x = st.x - S * .12, ew = Math.max(.6, S * .03);
			// legs
			g.strokeStyle = rgba(WOOD.lo); g.lineWidth = Math.max(1, S * .055); g.lineCap = 'butt';
			for (const lx of [-.26, .26]) { g.beginPath(); g.moveTo(x + lx * S, -S * 1.3); g.lineTo(x + lx * S * 1.15, 0); g.stroke(); }
			g.lineWidth = Math.max(.8, S * .035); g.beginPath(); g.moveTo(x - S * .28, -S * .5); g.lineTo(x + S * .28, -S * .8); g.stroke();
			// the bin: planks with iron bands
			const bin = () => { g.beginPath(); g.moveTo(x - S * .36, -S * 1.78); g.lineTo(x + S * .36, -S * 1.78); g.lineTo(x + S * .1, -S * 1.25); g.lineTo(x - S * .1, -S * 1.25); g.closePath(); };
			paint(g, bin, x - S * .36, -S * 1.78, x + S * .36, -S * 1.25, WOOD, ew);
			g.save(); bin(); g.clip();
			g.strokeStyle = 'rgba(30,20,12,.45)'; g.lineWidth = ew;
			for (let k = 1; k < 4; k++) { const yy = -S * 1.78 + k * S * .13; g.beginPath(); g.moveTo(x - S * .4, yy); g.lineTo(x + S * .4, yy); g.stroke(); }
			g.fillStyle = rgba(IRON.mid); g.fillRect(x - S * .4, -S * 1.6, S * .8, S * .045);
			g.restore();
			// ore heaped in the top
			const R = rng(st.seed);
			for (let k = 0; k < 7; k++) { g.fillStyle = rgba(mix([70, 62, 58], [130, 90, 70], R())); g.beginPath(); g.arc(x - S * .28 + R() * S * .56, -S * 1.79 - R() * S * .05, S * (.04 + R() * .03), 0, PI2); g.fill(); }
			// the chute down to the crucible
			const chute = () => { g.beginPath(); g.moveTo(x - S * .08, -S * 1.25); g.lineTo(x + S * .08, -S * 1.25); g.lineTo(x + S * .2, -S * .82); g.lineTo(x + S * .08, -S * .8); g.closePath(); };
			paint(g, chute, x - S * .08, -S * 1.25, x + S * .2, -S * .8, IRON, ew);
			// ore chunks tumble down the chute while the metal is there to melt them
			st.ore = st.ore || [];
			st.oreT = (st.oreT || 0) - s.dt;
			if (act > 0 && act < 1.5 && s.casting && st.oreT <= 0) { st.oreT = rand(.12, .25); st.ore.push({ t: 0, r: S * rand(.03, .05), c: mix([80, 70, 66], [140, 96, 70], Math.random()) }); }
			st.ore = st.ore.filter(o => {
				o.t += s.dt * 2.4;
				const u = Math.min(1, o.t), ox = lerp(x, st.in[0], u), oy = lerp(-S * 1.2, st.in[1] - S * .05, u * u);
				g.fillStyle = rgba(o.c); g.beginPath(); g.arc(ox, oy, o.r, 0, PI2); g.fill();
				if (o.t >= 1) { sparks(s, st.in[0], st.in[1], 1, .5, S / s.H * .6); return false; }
				return true;
			});
			crucible(g, st.in[0], st.in[1], S * .38, act, act);
		},
	};
	K.swivel = {   // a crucible slung between two posts on trunnions; it tips to pour once full
		build(st, S) { st.in = [st.x - S * .05, -S * 1.12]; st.out = [st.x + S * .3, -S * .72]; st.top = -S * 1.15; },
		draw(g, s, st, act) {
			const S = st.S, x = st.x, ew = Math.max(.6, S * .03);
			for (const px of [-.3, .3]) paint(g, () => { g.beginPath(); g.rect(x + px * S - S * .035, -S * .98, S * .07, S * .98); }, x + px * S - S * .04, 0, x + px * S + S * .04, 0, IRON, ew);
			paint(g, () => { g.beginPath(); g.rect(x - S * .4, -S * .03, S * .8, S * .05); }, 0, -S * .03, 0, S * .02, IRON, 0);
			const tip = .95 * smooth(.35, 1, act), py = -S * .9;
			g.save(); g.translate(x, py); g.rotate(tip);
			crucible(g, 0, -S * .14, S * .42, act, 1 - .7 * smooth(.5, 1, act));
			g.restore();
			// trunnion
			g.fillStyle = rgba(IRON.hi); g.beginPath(); g.arc(x, py, S * .05, 0, PI2); g.fill();
			g.strokeStyle = rgba(IRON.mid); g.lineWidth = Math.max(1, S * .04); g.beginPath(); g.moveTo(x - S * .3, py); g.lineTo(x + S * .3, py); g.stroke();
			// its lip, where the pour leaves
			const [lx, ly] = rot(S * .21, -S * .14, tip);
			st.out = [x + lx, py + ly];
		},
	};
	K.sluice = {   // a stone channel on a pillar; an iron gate lifts to let the metal through
		build(st, S) { st.in = [st.x - S * .44, -S * .78]; st.out = [st.x + S * .44, -S * .78]; st.top = -S * 1.1; },
		draw(g, s, st, act) {
			const S = st.S, x = st.x, ew = Math.max(.6, S * .03);
			const pil = () => { g.beginPath(); g.rect(x - S * .16, -S * .7, S * .32, S * .7); };
			g.save(); pil(); g.clip(); masonry(g, x - S * .16, -S * .7, S * .32, S * .7, S * .14, st.seed, STONE); g.restore();
			pil(); g.strokeStyle = 'rgba(14,10,8,.4)'; g.lineWidth = ew; g.stroke();
			// the channel: a U of stone, the metal along it up to the gate, past it once open
			const ch = () => { g.beginPath(); g.rect(x - S * .46, -S * .86, S * .92, S * .16); };
			paint(g, ch, 0, -S * .86, 0, -S * .7, STONE, ew);
			const gateOpen = smooth(.3, .7, act), fillTo = lerp(x - S * .46, x + S * .02, smooth(0, .35, act)) + (x + S * .46 - (x + S * .02)) * smooth(.55, 1, act);
			if (act > 0) {
				g.fillStyle = rgba(heat(.85)); g.fillRect(x - S * .44, -S * .83, Math.max(0, fillTo - (x - S * .44)), S * .07);
				glow(g, (x - S * .44 + fillTo) / 2, -S * .8, S * .5, [255, 140, 50], .3);
			}
			g.fillStyle = 'rgba(180,170,160,.35)'; g.fillRect(x - S * .46, -S * .86, S * .92, Math.max(.6, S * .02));
			// gate frame and the gate, lifting
			g.strokeStyle = rgba(IRON.mid); g.lineWidth = Math.max(1, S * .04);
			g.beginPath(); g.moveTo(x - S * .02, -S * .7); g.lineTo(x - S * .02, -S * 1.12); g.moveTo(x + S * .1, -S * .7); g.lineTo(x + S * .1, -S * 1.12); g.moveTo(x - S * .05, -S * 1.12); g.lineTo(x + S * .13, -S * 1.12); g.stroke();
			const gy = -S * .88 - gateOpen * S * .2;
			paint(g, () => { g.beginPath(); g.rect(x, gy, S * .08, S * .2); }, x, gy, x + S * .08, gy + S * .2, IRON, ew);
			g.fillStyle = 'rgba(200,195,190,.4)'; g.fillRect(x + S * .01, gy + S * .02, S * .015, S * .16);
			// the chain that lifted it
			g.strokeStyle = 'rgba(150,145,140,.6)'; g.lineWidth = Math.max(.6, S * .015); g.beginPath(); g.moveTo(x + S * .04, gy); g.lineTo(x + S * .04, -S * 1.12); g.stroke();
		},
	};
	K.moulds = {   // three ingot moulds stepped down an iron rack; each fills, glows and spills into the next
		build(st, S) {
			st.m = [[-.3, -.9], [0, -.62], [.3, -.34]].map(([dx, y]) => [st.x + dx * S, y * S]);
			st.in = [st.m[0][0] - S * .14, st.m[0][1] - S * .06]; st.out = [st.m[2][0] + S * .2, st.m[2][1] - S * .02]; st.top = -S * 1.05;
		},
		draw(g, s, st, act) {
			const S = st.S, ew = Math.max(.6, S * .03);
			// a stepped iron stand: each step a solid block the mould sits on
			st.m.forEach(([mx, my], i) => {
				const blk = () => { g.beginPath(); g.rect(mx - S * .17, my + S * .07, S * .34, -my - S * .07); };
				paint(g, blk, mx - S * .17, 0, mx + S * .17, 0, { hi: [84, 80, 84], mid: [52, 50, 54], lo: [26, 25, 28] }, ew);
				g.fillStyle = 'rgba(170,165,160,.3)'; g.fillRect(mx - S * .17, my + S * .07, S * .34, Math.max(.6, S * .02));
				// a short lip from each mould down to the next, so the overflow runs on
				if (i < 2) {
					const [nx, ny] = st.m[i + 1], on = clamp(act * 3 - i - .85) > 0;
					g.strokeStyle = on ? rgba(heat(.8)) : rgba(IRON.mid); g.lineWidth = Math.max(1, S * .045); g.lineCap = 'round';
					g.beginPath(); g.moveTo(mx + S * .16, my - S * .03); g.quadraticCurveTo(mx + S * .24, my, nx - S * .1, ny - S * .06); g.stroke();
				}
			});
			st.m.forEach(([mx, my], i) => {
				const w = S * .36, h = S * .15, f = smooth(i / 3, (i + 1) / 3, act), age = clamp(act * 3 - i - 1);
				const mould = () => { g.beginPath(); g.moveTo(mx - w / 2, my - h / 2); g.lineTo(mx + w / 2, my - h / 2); g.lineTo(mx + w * .38, my + h / 2); g.lineTo(mx - w * .38, my + h / 2); g.closePath(); };
				paint(g, mould, mx - w / 2, my - h / 2, mx + w / 2, my + h / 2, IRON, ew);
				if (f > 0) {
					g.save(); mould(); g.clip();
					const t = .95 - .45 * age;
					g.fillStyle = rgba(heat(t)); g.fillRect(mx - w / 2, my + h / 2 - h * .85 * f, w, h);
					g.restore();
					glow(g, mx, my, S * .35, heat(t), .35 * f * (1 - age * .5));
					if (age > .3 && Math.random() < s.dt * 3) smokePuff(s, mx, my - h / 2, .15, .14, S / s.H * .6);
				}
				g.fillStyle = 'rgba(190,185,180,.35)'; g.fillRect(mx - w / 2, my - h / 2, w, Math.max(.6, S * .02));
			});
		},
	};
	K.quench = {   // a launder runs over a water trough; the water hisses steam as the hot metal passes
		build(st, S) { st.in = [st.x - S * .44, -S * .62]; st.out = [st.x + S * .44, -S * .55]; st.top = -S * .7; },
		draw(g, s, st, act) {
			const S = st.S, x = st.x, ew = Math.max(.6, S * .03);
			const trough = () => { g.beginPath(); g.moveTo(x - S * .44, -S * .34); g.lineTo(x + S * .44, -S * .34); g.lineTo(x + S * .38, 0); g.lineTo(x - S * .38, 0); g.closePath(); };
			paint(g, trough, x - S * .44, -S * .34, x + S * .44, 0, WOOD, ew);
			g.save(); trough(); g.clip();
			g.strokeStyle = 'rgba(30,20,12,.4)'; g.lineWidth = ew;
			for (let k = 1; k < 3; k++) { g.beginPath(); g.moveTo(x - S * .5, -S * .34 + k * S * .11); g.lineTo(x + S * .5, -S * .34 + k * S * .11); g.stroke(); }
			g.fillStyle = rgba(IRON.mid); g.fillRect(x - S * .5, -S * .2, S, S * .035);
			g.restore();
			// the water
			const wy = -S * .3;
			const wg = g.createLinearGradient(0, wy, 0, wy + S * .06);
			wg.addColorStop(0, 'rgba(120,150,170,.9)'); wg.addColorStop(1, 'rgba(40,60,75,.9)');
			g.fillStyle = wg; g.beginPath(); g.ellipse(x, wy, S * .42, S * .04, 0, 0, PI2); g.fill();
			if (act > 0) glow(g, x, wy, S * .5, [255, 130, 50], .18 * act);
			// the launder over it on two iron hangers
			g.strokeStyle = rgba(IRON.mid); g.lineWidth = Math.max(.8, S * .03);
			for (const hx of [-.3, .3]) { g.beginPath(); g.moveTo(x + hx * S, -S * .34); g.lineTo(x + hx * S, -S * .56); g.stroke(); }
			const ln = () => { g.beginPath(); g.moveTo(st.in[0], st.in[1] - S * .04); g.lineTo(st.out[0], st.out[1] - S * .04); g.lineTo(st.out[0], st.out[1] + S * .05); g.lineTo(st.in[0], st.in[1] + S * .05); g.closePath(); };
			paint(g, ln, 0, -S * .66, 0, -S * .5, CLAY, ew);
			if (act > 0) {
				const fx = lerp(st.in[0], st.out[0], smooth(0, .8, act));
				g.strokeStyle = rgba(heat(.85)); g.lineWidth = Math.max(1, S * .05); g.lineCap = 'round';
				g.beginPath(); g.moveTo(st.in[0], st.in[1]); g.lineTo(fx, lerp(st.in[1], st.out[1], (fx - st.in[0]) / (st.out[0] - st.in[0]))); g.stroke();
				st.acc = (st.acc || 0) + s.dt * 7 * act;
				while (st.acc >= 1) { st.acc--; steamPuff(s, x + rand(-.35, .35) * S, wy - S * .05, .3, S / s.H); }
			}
		},
	};
	K.ladle = {   // a hand ladle hangs from a post's arm on a chain; it tips to pour once it fills
		build(st, S) { st.in = [st.x - S * .02, -S * .82]; st.out = [st.x + S * .2, -S * .7]; st.top = -S * 1.4; },
		draw(g, s, st, act) {
			const S = st.S, x = st.x, ew = Math.max(.6, S * .03);
			paint(g, () => { g.beginPath(); g.rect(x - S * .36, -S * 1.38, S * .07, S * 1.38); }, x - S * .37, 0, x - S * .28, 0, WOOD, ew);
			paint(g, () => { g.beginPath(); g.rect(x - S * .36, -S * 1.38, S * .5, S * .06); }, 0, -S * 1.38, 0, -S * 1.32, WOOD, ew);
			g.strokeStyle = rgba(WOOD.lo); g.lineWidth = Math.max(.8, S * .03); g.beginPath(); g.moveTo(x - S * .3, -S * 1.05); g.lineTo(x - S * .05, -S * 1.32); g.stroke();
			// chain to the bowl
			const tip = .8 * smooth(.4, 1, act), bx = x, by = -S * .8;
			g.strokeStyle = 'rgba(150,145,140,.7)'; g.lineWidth = Math.max(.6, S * .018);
			g.setLineDash([S * .04, S * .025]); g.beginPath(); g.moveTo(x + S * .02, -S * 1.32); g.lineTo(bx, by - S * .12); g.stroke(); g.setLineDash([]);
			g.save(); g.translate(bx, by); g.rotate(tip);
			// the bowl: hammered iron with a pouring lip and a long handle
			const bowl = () => { g.beginPath(); g.moveTo(-S * .17, -S * .02); g.quadraticCurveTo(-S * .16, S * .2, 0, S * .2); g.quadraticCurveTo(S * .16, S * .2, S * .2, -S * .04); g.lineTo(S * .24, -S * .06); g.lineTo(S * .17, -S * .02); g.closePath(); };
			paint(g, bowl, -S * .17, -S * .04, S * .2, S * .2, IRON, ew);
			warmLight(g, bowl, 0, 0, S * .35, .4 * act);
			g.strokeStyle = rgba(IRON.mid); g.lineWidth = Math.max(1, S * .035); g.lineCap = 'round';
			g.beginPath(); g.moveTo(-S * .17, -S * .01); g.lineTo(-S * .48, -S * .2); g.stroke();
			g.fillStyle = 'rgba(18,14,14,.95)'; g.beginPath(); g.ellipse(0, -S * .02, S * .17, S * .04, 0, 0, PI2); g.fill();
			const full = act * (1 - .6 * smooth(.5, 1, act));
			if (full > .02) { g.fillStyle = rgba(heat(.88)); g.beginPath(); g.ellipse(0, -S * .015, S * .15 * Math.sqrt(full), S * .033 * Math.sqrt(full), 0, 0, PI2); g.fill(); }
			g.restore();
			glow(g, bx, by, S * .55, [255, 140, 50], .3 * act);
			const [lx, ly] = rot(S * .24, -S * .06, tip);
			st.out = [bx + lx, by + ly];
		},
	};
	const POOL = ['hearth', 'hopper', 'swivel', 'sluice', 'moulds', 'quench', 'ladle'];

	// ---- the runs between stations: open clay launders on posts going down, closed pipes when they climb
	function bez(A, B, C, D, n = 24) {
		const pts = [];
		for (let i = 0; i <= n; i++) {
			const t = i / n, u = 1 - t;
			pts.push([u * u * u * A[0] + 3 * u * u * t * B[0] + 3 * u * t * t * C[0] + t * t * t * D[0], u * u * u * A[1] + 3 * u * u * t * B[1] + 3 * u * t * t * C[1] + t * t * t * D[1]]);
		}
		return pts;
	}
	function lengths(pts) { const L = [0]; for (let i = 1; i < pts.length; i++) L.push(L[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])); return L; }
	function along(pts, L, f) {
		const want = L[L.length - 1] * clamp(f);
		for (let i = 1; i < pts.length; i++) if (L[i] >= want) { const u = (want - L[i - 1]) / Math.max(1e-6, L[i] - L[i - 1]); return [lerp(pts[i - 1][0], pts[i][0], u), lerp(pts[i - 1][1], pts[i][1], u), i]; }
		const p = pts[pts.length - 1]; return [p[0], p[1], pts.length - 1];
	}
	function strokePts(g, pts, upto) { g.beginPath(); for (let i = 0; i < upto; i++) i ? g.lineTo(pts[i][0], pts[i][1]) : g.moveTo(pts[i][0], pts[i][1]); }
	function drawLink(g, s, ln, f, S) {
		const pts = ln.pts, w = Math.max(1.6, S * .1), ew = Math.max(.6, S * .03);
		g.lineCap = 'round'; g.lineJoin = 'round';
		if (ln.type === 'launder') {
			// posts down to the bar
			g.strokeStyle = rgba(WOOD.lo); g.lineWidth = Math.max(.8, S * .04);
			for (const u of [.3, .75]) { const [px, py] = along(pts, ln.L, u); g.beginPath(); g.moveTo(px, py + w * .5); g.lineTo(px, 0); g.stroke(); }
			strokePts(g, pts, pts.length); g.strokeStyle = 'rgba(20,12,8,.5)'; g.lineWidth = w + ew * 2; g.stroke();
			strokePts(g, pts, pts.length); g.strokeStyle = rgba(CLAY.mid); g.lineWidth = w; g.stroke();
			g.save(); g.translate(0, w * .18); strokePts(g, pts, pts.length); g.strokeStyle = rgba(CLAY.lo); g.lineWidth = w * .5; g.stroke(); g.restore();
			if (f > 0) {
				const [hx, hy, k] = along(pts, ln.L, f), seg = pts.slice(0, k).concat([[hx, hy]]);
				g.beginPath(); seg.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y));
				g.strokeStyle = rgba(heat(.85)); g.lineWidth = w * .5; g.stroke();
				g.beginPath(); seg.forEach(([x, y], i) => i ? g.lineTo(x, y - w * .08) : g.moveTo(x, y - w * .08));
				g.globalCompositeOperation = 'lighter'; g.strokeStyle = 'rgba(255,230,160,.35)'; g.lineWidth = w * .18; g.stroke(); g.globalCompositeOperation = 'source-over';
			}
			g.save(); g.translate(0, -w * .32); strokePts(g, pts, pts.length); g.strokeStyle = 'rgba(210,160,120,.35)'; g.lineWidth = Math.max(.6, w * .14); g.stroke(); g.restore();
		} else {
			// a closed pipe (clay or iron), joints banded; the metal glows through the joints as it passes
			const m = ln.type === 'iron' ? IRON : CLAY;
			strokePts(g, pts, pts.length); g.strokeStyle = 'rgba(16,10,8,.5)'; g.lineWidth = w + ew * 2; g.stroke();
			strokePts(g, pts, pts.length); g.strokeStyle = rgba(m.mid); g.lineWidth = w; g.stroke();
			g.save(); g.translate(-w * .12, -w * .2); strokePts(g, pts, pts.length); g.strokeStyle = rgba(m.hi, .55); g.lineWidth = w * .3; g.stroke(); g.restore();
			const joints = Math.max(2, Math.round(ln.L[ln.L.length - 1] / (S * .32)));
			for (let j = 1; j < joints; j++) {
				const u = j / joints, [jx, jy, k] = along(pts, ln.L, u), [ax, ay] = pts[Math.max(0, k - 1)], [bx, by] = pts[Math.min(pts.length - 1, k)];
				const a = Math.atan2(by - ay, bx - ax) + PI / 2, hw = w * .62;
				const hot = f > u ? 1 : 0;
				g.strokeStyle = hot ? rgba(mix(IRON.lo, heat(.6), .55)) : rgba(IRON.lo); g.lineWidth = Math.max(.8, S * .035);
				g.beginPath(); g.moveTo(jx - Math.cos(a) * hw, jy - Math.sin(a) * hw); g.lineTo(jx + Math.cos(a) * hw, jy + Math.sin(a) * hw); g.stroke();
				if (hot) glow(g, jx, jy, S * .18, [255, 120, 40], .18);
			}
			// the head of the metal inside shows as a hot spot moving along
			if (f > 0 && f < 1) { const [hx, hy] = along(pts, ln.L, f); glow(g, hx, hy, S * .35, [255, 150, 50], .45); }
			if (f > 0) { g.save(); strokePts(g, pts, pts.length); g.globalCompositeOperation = 'lighter'; g.strokeStyle = `rgba(255,110,30,${.1 * Math.min(1, f * 3)})`; g.lineWidth = w * .9; g.stroke(); g.restore(); }
		}
	}

	// ---- the bar's molten run: a viscous height field (as in Smelting B2). It heaps where the metal
	// spills in, slumps under its weight and creeps with a blunt toe; heat goes with the metal and leaks away.
	function makeMelt(W, H) {
		const N = Math.max(30, Math.ceil(W / (H * .1)));
		return { N, dx: W / H / N, h: new Float32Array(N), T: new Float32Array(N), e: new Float32Array(N), q: new Float32Array(N + 1),
			hs: new Float32Array(N), vel: new Float32Array(N), tmp: new Float32Array(N) };
	}
	const MELT_K = .9;
	function stepMelt(M, gate, dt, tilt) {
		const { N, dx, h, T, e, q } = M;
		let hmax = .2;
		for (let i = 0; i < N; i++) hmax = Math.max(hmax, h[i]);
		const STEP = Math.min(.01, dx * dx / (2.5 * MELT_K * hmax * hmax * hmax));
		for (let t = dt; t > 1e-6; t -= STEP) {
			const d = Math.min(t, STEP);
			for (let i = 1; i < N; i++) {
				const hm = (h[i - 1] + h[i]) / 2;
				q[i] = MELT_K * hm * hm * hm * (tilt - (h[i] - h[i - 1]) / dx) * clamp((gate - i * dx) / .35);
			}
			q[0] = q[N] = 0;
			for (let i = 0; i < N; i++) {
				const out = (Math.max(0, q[i + 1]) + Math.max(0, -q[i])) * d / dx;
				if (out > h[i] && out > 0) { const k = h[i] / out; if (q[i + 1] > 0) q[i + 1] *= k; if (q[i] < 0) q[i] *= k; }
			}
			for (let i = 0; i < N; i++) e[i] = T[i] * h[i];
			for (let i = 1; i < N; i++) { const f = q[i] * d / dx, src = f > 0 ? T[i - 1] : T[i]; e[i - 1] -= f * src; e[i] += f * src; }
			for (let i = 0; i < N; i++) { h[i] = Math.max(0, h[i] + d * (q[i] - q[i + 1]) / dx); T[i] = h[i] > 1e-4 ? clamp(e[i] / h[i]) : 0; }
		}
		for (let i = 0; i < N; i++) M.vel[i] = h[i] > .04 ? (q[i] + q[i + 1]) / 2 / h[i] : 0;
		const { hs, tmp } = M;
		for (let i = 0; i < N; i++) tmp[i] = (h[Math.max(0, i - 1)] + 2 * h[i] + h[Math.min(N - 1, i + 1)]) / 4;
		for (let i = 0; i < N; i++) hs[i] = (tmp[Math.max(0, i - 1)] + 2 * tmp[i] + tmp[Math.min(N - 1, i + 1)]) / 4;
	}
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
	const meltAt = (M, a, x) => a[clamp(Math.floor(x / M.dx), 0, M.N - 1)];

	function drawMelt(g, s) {
		const W = s.W, H = s.H, M = s.melt, N = M.N, dxp = M.dx * H;
		let xf = 0;
		for (let i = 0; i < N; i++) if (M.hs[i] > .03) xf = (i + 1) * dxp;
		s.xf = xf;
		const top = [];
		for (let i = 0; i < N; i++) {
			const x = (i + .5) * dxp, d = M.hs[i], calm = clamp(d / .3) * clamp((1.25 - d) / .3);
			const swell = Math.sin(x / (H * 1.4) - s.t * 1.1 + s.ph) * .028 + Math.sin(x / (H * 2.6) + s.t * .55) * .02;
			top.push([x, H - Math.min(d, 1.3) * H - calm * swell * H]);
		}
		const tempX = x => meltAt(M, M.T, x / H), topY = top.map(p => p[1]);
		s.surfAt = x => meltAt(M, topY, x / H);
		g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
		// the empty clay runner of the bar, faintly lit by the works above
		const bg = g.createLinearGradient(0, 0, 0, H);
		bg.addColorStop(0, 'rgba(46,34,28,.95)'); bg.addColorStop(1, 'rgba(16,11,9,.95)');
		g.fillStyle = bg; g.fillRect(0, 0, W, H);
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
			const gv = g.createLinearGradient(0, 0, 0, H);
			gv.addColorStop(0, 'rgba(25,8,4,.2)'); gv.addColorStop(.35, 'rgba(255,200,120,.05)'); gv.addColorStop(1, 'rgba(10,0,0,.42)');
			g.fillStyle = gv; g.fillRect(0, 0, xf + dxp, H + 2);
			for (const p of s.plates) {
				const tp = tempX(p.x), a = p.a * smooth(.62, .3, tp);
				if (a <= .01) continue;
				polyPath(g, p.x, p.y, p.pts);
				g.strokeStyle = rgba(heat(Math.min(1, tp + .3)), a * .7); g.lineWidth = Math.max(1, H * .06); g.lineJoin = 'round'; g.stroke();
				g.fillStyle = rgba(mix(heat(tp * .3), [34, 30, 32], .6), a * .92); g.fill();
			}
			g.lineCap = 'round';
			for (const f of s.folds) {
				const tf = tempX(f.x), y0 = s.surfAt(f.x);
				const a = clamp(f.age * 2) * clamp((f.life - f.age) / .6), depth = (H - y0) * f.dep, bow = f.bow * H;
				if (a <= 0 || depth < H * .08) continue;
				const path = dxs => { g.beginPath(); g.moveTo(f.x + dxs, y0 + H * .03); g.quadraticCurveTo(f.x + dxs + bow, y0 + depth * .5, f.x + dxs - bow * .2, y0 + depth); };
				path(-H * .04); g.strokeStyle = rgba(heat(Math.min(1, tf + .25)), .55 * a); g.lineWidth = Math.max(.7, H * .03); g.stroke();
				path(0); g.strokeStyle = rgba(mix(heat(tf * .5), [30, 20, 18], .4), .7 * a); g.lineWidth = Math.max(.9, H * .05); g.stroke();
			}
			g.restore();
			g.globalCompositeOperation = 'lighter'; g.lineJoin = 'round';
			g.beginPath(); for (let i = 0; i <= iF; i++) i ? g.lineTo(top[i][0], top[i][1]) : g.moveTo(top[i][0], top[i][1]);
			g.strokeStyle = grad; g.globalAlpha = .45; g.lineWidth = Math.max(1, H * .05); g.stroke();
			g.globalAlpha = 1; g.globalCompositeOperation = 'source-over';
			const tt = tempX(xf - H * .2);
			if (tt > .2) glow(g, xf - H * .15, (top[iF][1] + H) / 2, H * .7, heat(tt + .2), .35 * smooth(.2, .7, tt));
		}
		g.restore();
		// skin features ride along with the flow
		const velAt = x => meltAt(M, M.vel, x / H) * H, pour = s.pourX;
		if (s.casting && pour != null) {
			s.foldT -= s.dt;
			if (s.foldT <= 0 && xf > pour + H * .3) { s.foldT = rand(.16, .28); s.folds.push({ x: pour + H * rand(.15, .35), age: 0, life: rand(2.5, 4), dep: rand(.45, .85), bow: rand(.08, .16) }); }
			s.plateT -= s.dt;
			if (s.plateT <= 0 && xf > H) { s.plateT = rand(.18, .3); s.plates.push({ x: rand(H * .3, Math.max(H * .4, pour - H * .2)), y: H * rand(.45, .8), pts: plateShape(H * rand(.16, .26)), a: 0 }); }
		}
		for (const f of s.folds) { f.age += s.dt; f.x = Math.min(f.x + velAt(f.x) * s.dt, xf - H * .15); }
		s.folds = s.folds.filter(f => f.age < f.life);
		for (const p of s.plates) { p.a = Math.min(1, p.a + s.dt); p.x = Math.min(p.x + velAt(p.x) * s.dt * .9, xf - H * .3); }
		if (s.plates.length > 40) s.plates.shift();
	}

	// a thick, short pour from the head of the run down into the bar
	function drawSpill(g, x0, y0, x1, y1, w, t) {
		if (w <= .3 || y1 - y0 < 1) return;
		const pts = [];
		for (let i = 0; i <= 12; i++) { const v = i / 12; pts.push([lerp(x0, x1, v * v) + Math.sin(t * 15 + v * 6) * w * .08 * v, lerp(y0, y1, v)]); }
		const path = () => { g.beginPath(); pts.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y)); };
		g.lineCap = 'round';
		g.save(); g.shadowColor = 'rgba(255,120,20,.85)'; g.shadowBlur = w * 1.5;
		path(); g.strokeStyle = rgba([220, 90, 18]); g.lineWidth = w; g.stroke(); g.restore();
		path(); g.strokeStyle = rgba(heat(.82)); g.lineWidth = w * .62; g.stroke();
		g.globalCompositeOperation = 'lighter'; g.setLineDash([w * .7, w * .5]); g.lineDashOffset = -t * w * 12;
		path(); g.strokeStyle = 'rgba(255,235,170,.4)'; g.lineWidth = w * .26; g.stroke();
		g.setLineDash([]); g.globalCompositeOperation = 'source-over';
	}

	CONCEPTS.push({
		group: 'Smelting', id: 'smelt-d', letter: 'D', name: 'Foundry line',
		desc: 'A whole smelting works: furnace, bellows hearth, ore hopper, swivel crucible, sluice gate, stepped moulds, a launder over a quench trough and a hanging ladle, joined by launders and pipes; the metal works its way through and spills into the bar, thick and slow, rising until it fills it',
		spell: 'Smelt Thorium', dur: [3.4, 4.2], padTop: 2.9, padX: .9, padBottom: .5, flash: [255, 170, 70],
		init(s) {
			const H = s.H, W = s.W, m = H * .62;
			const n = clamp(Math.floor((W - 2 * m) / (H * 1.15)) + 1, 6, 9), Z = (W - 2 * m) / (n - 1), S = Math.min(H * 1.12, Z * .9);
			const pool = POOL.slice().sort(() => Math.random() - .5), kinds = ['furnace'];
			for (let i = 1; i < n; i++) kinds.push(pool[(i - 1) % pool.length]);
			s.st = kinds.map((kind, i) => {
				const st = { kind, S, x: m + Z * i + (i && i < n - 1 ? rand(-.05, .05) * Z : 0), seed: rand(0, 99) };
				K[kind].build(st, S);
				return st;
			});
			s.Z = Z; s.S = S;
			s.links = [];
			for (let i = 0; i < n - 1; i++) {
				const A = s.st[i].out, B = s.st[i + 1].in, climb = A[1] - B[1];
				let ln;
				if (climb < S * .08) {   // level or going down: an open launder, sagging a touch
					const mid = (A[1] + B[1]) / 2 + S * .06;
					ln = { type: 'launder', raw: [A, [lerp(A[0], B[0], .35), mid], [lerp(A[0], B[0], .65), mid], B] };
				} else {   // climbing: a closed pipe arching over
					const top = Math.min(A[1], B[1]) - S * rand(.15, .3);
					ln = { type: Math.random() < .5 ? 'iron' : 'clay', raw: [A, [A[0] + Z * .2, A[1] + S * .1], [B[0] - Z * .25, top], B] };
				}
				s.links.push(ln);
			}
			s.melt = makeMelt(W, H); s.folds = []; s.foldT = 0; s.plates = []; s.plateT = 0; s.ph = rand(0, 6.3);
			s.sparkAcc = 0;
		},
		draw(g, s) {
			const W = s.W, H = s.H, M = s.melt, N = M.N, n = s.st.length, Z = s.Z;
			// how far the metal has got: station i wakes as the cast reaches it, the run to the next fills after
			const X = s.done ? W * 2 : s.fill;
			s.act = s.st.map((st, i) => i === 0 ? clamp((X + Z * .5) / (Z * .5)) : clamp((X - st.x + Z * .15) / (Z * .45)));
			s.linkF = s.links.map((ln, i) => clamp((X - s.st[i].x - Z * .3) / (Z * .55)));
			// the head of the run, where the metal spills into the bar
			let head = s.st[0].out;
			for (let i = 0; i < n; i++) {
				if (s.act[i] > 0) head = s.st[i].out;
				if (i < n - 1 && s.linkF[i] > 0 && s.links[i].pts) head = along(s.links[i].pts, s.links[i].L, s.linkF[i]);
			}
			s.head = head;
			const pour = clamp(head[0], H * .25, W - H * .25);
			s.pourX = pour;
			let vol = 0;
			for (let i = 0; i < N; i++) vol += M.h[i] * M.dx;
			const target = W / H * 1.04 * Math.pow(s.p, 1.6);
			if (s.casting && target > vol) pourMelt(M, pour / H, Math.min(target - vol, W / H * 1.6 * s.dt + .002), .3);
			const gate = s.done ? W / H + 1 : s.fill / H + .25;
			const lean = s.done ? 0 : 40 * clamp(((s.fill - (s.xf || 0)) / H - .15) / .8);
			stepMelt(M, gate, s.dt, lean);
			const cr = s.done ? 1.6 : .75;
			for (let i = 0; i < N; i++) if (M.h[i] > 1e-4) M.T[i] = Math.max(.1, M.T[i] - s.dt * cr * (M.T[i] - .1) * (1 + .25 / Math.max(.15, M.h[i])));
			drawMelt(g, s);
		},
		over(g, s) {
			if (!s.act) return;
			const H = s.H, S = s.S, n = s.st.length;
			// the links (their points follow the stations, some of which tip)
			for (let i = 0; i < n - 1; i++) {
				const ln = s.links[i], A = s.st[i].out, B = s.st[i + 1].in, r = ln.raw;
				ln.pts = bez(A, [r[1][0] + (A[0] - r[0][0]), r[1][1] + (A[1] - r[0][1])], r[2], B); ln.L = lengths(ln.pts);
			}
			// the stations, back to front (each paints its own parts), then the runs over them
			for (let i = 0; i < n; i++) K[s.st[i].kind].draw(g, s, s.st[i], s.act[i]);
			for (let i = 0; i < n - 1; i++) drawLink(g, s, s.links[i], s.linkF[i], S);
			// the spill into the bar from the head of the run, sparks where it lands
			if (s.casting && s.head && s.surfAt) {
				const [hx, hy] = s.head, x1 = s.pourX, y1 = s.surfAt(x1) + H * .02;
				drawSpill(g, hx, hy + S * .03, x1, y1, Math.max(1.2, S * .085), s.t);
				glow(g, x1, y1, H * 1.1, [255, 130, 40], .38);
				s.sparkAcc += s.dt * 10;
				while (s.sparkAcc >= 1) { s.sparkAcc--; sparks(s, x1, y1, 1, .8, .8); }
			}
			s.parts.update(s.dt); s.parts.draw(g);
		},
	});
})();
