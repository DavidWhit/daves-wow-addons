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
