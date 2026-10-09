// Enchanting concepts: a power siphon. Disenchanting draws the magic out of an item into dust, essences
// and shards; enchanting channels it from a rod into the bar. No leading-edge marker: the flow of
// power itself shows the progress (profession looks never get the spark).
(() => {
	const PALETTES = [
		{ main: [158, 96, 255], deep: [34, 12, 62], acc: [86, 228, 222], hi: [232, 208, 255], gold: [255, 206, 120] },
		{ main: [96, 205, 235], deep: [10, 34, 56], acc: [190, 120, 255], hi: [214, 252, 255], gold: [255, 214, 140] },
		{ main: [206, 112, 255], deep: [46, 14, 58], acc: [255, 196, 104], hi: [255, 226, 255], gold: [255, 220, 150] },
		{ main: [124, 132, 255], deep: [18, 18, 64], acc: [120, 255, 200], hi: [222, 228, 255], gold: [255, 200, 110] },
	];
	const ROD_METALS = [   // copper, silver, golden, arcanite
		{ lo: [96, 46, 22], mid: [184, 104, 58], hi: [246, 188, 140] },
		{ lo: [88, 92, 104], mid: [176, 182, 196], hi: [246, 248, 255] },
		{ lo: [110, 74, 18], mid: [214, 164, 62], hi: [255, 234, 160] },
		{ lo: [40, 70, 110], mid: [92, 156, 214], hi: [200, 236, 255] },
	];
	const barClip = (g, s) => { roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip(); };
	const light = (c, k) => mix(c, [255, 255, 255], k);
	const dark = (c, k) => mix(c, [0, 0, 0], k);
	const grey = (c, k) => { const l = c[0] * .3 + c[1] * .59 + c[2] * .11; return mix(c, [l, l, l], k); };
	function mkCanvas(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }
	function glow(g, x, y, r, col, a) {
		if (a <= .002 || r <= .5) return;
		const gr = g.createRadialGradient(x, y, 0, x, y, r);
		gr.addColorStop(0, rgba(col, a)); gr.addColorStop(.4, rgba(col, a * .45)); gr.addColorStop(1, rgba(col, 0));
		g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
	}

	// A dark, softly mottled velvet the magic settles on, painted once per cast (keeps the text readable).
	function makeVelvet(W, H, pal) {
		const k = typeof dpr === 'number' ? dpr : 1, cv = mkCanvas(W * k, H * k), g = cv.getContext('2d');
		g.scale(k, k);
		const bg = g.createLinearGradient(0, 0, 0, H);
		bg.addColorStop(0, rgba(mix(pal.deep, pal.main, .18))); bg.addColorStop(.55, rgba(pal.deep)); bg.addColorStop(1, rgba(dark(pal.deep, .5)));
		g.fillStyle = bg; g.fillRect(0, 0, W, H);
		for (let i = 0; i < W / H * 7; i++) {
			const x = rand(0, W), y = rand(0, H), r = H * rand(.3, .9), c = Math.random() < .5 ? pal.main : pal.acc;
			const gr = g.createRadialGradient(x, y, 0, x, y, r);
			gr.addColorStop(0, rgba(c, .1)); gr.addColorStop(1, rgba(c, 0));
			g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
		}
		for (let i = 0; i < W / H * 30; i++) { g.fillStyle = rgba(pal.hi, rand(.05, .22)); g.fillRect(rand(0, W), rand(0, H), .8, .8); }
		return cv;
	}

	// A rune: a few strokes on a 3x3 grid, drawn as soft light.
	function makeRune() {
		const pts = [];
		for (let i = 0; i < 9; i++) pts.push([(i % 3) / 2 - .5, Math.floor(i / 3) / 2 - .5]);
		const strokes = [], n = Math.floor(rand(3, 6));
		let a = Math.floor(rand(0, 9));
		for (let i = 0; i < n; i++) { let b = Math.floor(rand(0, 9)); if (b === a) b = (b + 4) % 9; strokes.push([pts[a], pts[b]]); a = Math.random() < .6 ? b : Math.floor(rand(0, 9)); }
		return strokes;
	}
	function drawRune(g, x, y, size, strokes, col, a) {
		if (a <= .01) return;
		g.save(); g.globalCompositeOperation = 'lighter'; g.lineCap = 'round';
		for (const [w, al] of [[.2, .22], [.08, 1]]) {
			g.strokeStyle = rgba(col, a * al); g.lineWidth = Math.max(.8, size * w);
			g.beginPath();
			for (const [p, q] of strokes) { g.moveTo(x + p[0] * size, y + p[1] * size); g.lineTo(x + q[0] * size, y + q[1] * size); }
			g.stroke();
		}
		g.restore();
	}

	// Disenchant products: a crystal shard, a glowing essence, a heap of glittering dust.
	function drawShard(g, x, y, h, ang, pal, a) {
		g.save(); g.translate(x, y); g.rotate(ang); g.globalAlpha *= a;
		const w = h * .34;
		const p = new Path2D(); p.moveTo(0, -h); p.lineTo(w, -h * .32); p.lineTo(w * .6, 0); p.lineTo(-w * .6, 0); p.lineTo(-w, -h * .4); p.closePath();
		glow(g, 0, -h * .45, h * 1.1, pal.main, .35);
		const gr = g.createLinearGradient(-w, 0, w, -h);
		gr.addColorStop(0, rgba(dark(pal.main, .45))); gr.addColorStop(.5, rgba(pal.main)); gr.addColorStop(1, rgba(light(pal.main, .6)));
		g.fillStyle = gr; g.fill(p);
		g.strokeStyle = rgba(light(pal.hi, .3), .75); g.lineWidth = Math.max(.6, h * .05);
		g.beginPath(); g.moveTo(0, -h); g.lineTo(-w * .15, -h * .05); g.stroke();   // the bright facet edge
		g.fillStyle = rgba([255, 255, 255], .5); g.beginPath(); g.ellipse(w * .25, -h * .62, w * .14, h * .12, -.4, 0, 6.283); g.fill();
		g.restore();
	}
	function drawEssence(g, x, y, r, pal, t, ph, a) {
		g.save(); g.globalAlpha *= a; g.globalCompositeOperation = 'lighter';
		glow(g, x, y, r * 3.2, pal.main, .35 + .1 * Math.sin(t * 3 + ph));
		glow(g, x, y, r * 1.4, pal.acc, .55);
		glow(g, x, y, r * .6, [255, 255, 255], .9);
		g.strokeStyle = rgba(pal.hi, .45); g.lineWidth = Math.max(.6, r * .14);
		g.beginPath(); g.ellipse(x, y, r * 1.9, r * .55, Math.sin(t * 1.3 + ph) * .5, 0, 6.283); g.stroke();
		g.restore();
	}
	function drawDust(g, x, y, r, grains, pal, t, a) {
		g.save(); g.globalAlpha *= a;
		const gr = g.createRadialGradient(x, y, 0, x, y, r * 1.3);
		gr.addColorStop(0, rgba(light(pal.main, .25), .55)); gr.addColorStop(1, rgba(pal.main, 0));
		g.fillStyle = gr; g.beginPath(); g.ellipse(x, y, r * 1.3, r * .55, 0, 0, 6.283); g.fill();
		g.globalCompositeOperation = 'lighter';
		for (const q of grains) {
			const tw = .45 + .55 * Math.max(0, Math.sin(t * q.f + q.ph));
			g.fillStyle = rgba(q.c ? pal.acc : pal.hi, tw * .9);
			g.beginPath(); g.arc(x + q.dx * r, y + q.dy * r * .45, Math.max(.5, r * q.s), 0, 6.283); g.fill();
		}
		g.restore();
	}
	const grainsFor = () => { const a = []; for (let i = 0; i < 14; i++) a.push({ dx: rand(-1, 1), dy: rand(-1, .6), s: rand(.03, .08), f: rand(2, 7), ph: rand(0, 6.283), c: Math.random() < .3 }); return a; };

	// A painted sword, the item being disenchanted: steel blade with a fuller, gold guard, wrapped grip,
	// a gem pommel. `drain` 0..1 greys it and dims its aura.
	function drawSword(g, x, y, L, ang, pal, drain, t) {
		g.save(); g.translate(x, y); g.rotate(ang);
		const bw = L * .085, hl = L * .26, bl = L - hl;
		// shadow
		g.save(); g.shadowColor = 'rgba(0,0,0,.55)'; g.shadowBlur = L * .06; g.shadowOffsetY = L * .02;
		g.fillStyle = 'rgba(0,0,0,.01)'; g.fillRect(-bl, -bw, L, bw * 2); g.restore();
		// the aura: the magic still in it
		const aura = 1 - drain;
		if (aura > .02) {
			g.save(); g.globalCompositeOperation = 'lighter';
			for (let i = 0; i < 3; i++) glow(g, -bl * (.2 + i * .3), 0, L * .32, pal.main, .28 * aura * (.85 + .15 * Math.sin(t * 4 + i)));
			g.restore();
		}
		const steel = c => grey(c, drain * .85);
		// blade
		const blade = new Path2D();
		blade.moveTo(0, -bw); blade.lineTo(-bl * .82, -bw * .9); blade.lineTo(-bl, 0); blade.lineTo(-bl * .82, bw * .9); blade.lineTo(0, bw); blade.closePath();
		const bg = g.createLinearGradient(0, -bw, 0, bw);
		bg.addColorStop(0, rgba(steel([232, 236, 246]))); bg.addColorStop(.45, rgba(steel([150, 158, 176]))); bg.addColorStop(.55, rgba(steel([96, 102, 120]))); bg.addColorStop(1, rgba(steel([176, 182, 198])));
		g.fillStyle = bg; g.fill(blade);
		g.strokeStyle = rgba(steel([60, 64, 78]), .6); g.lineWidth = Math.max(.6, bw * .14); g.beginPath(); g.moveTo(-bw, 0); g.lineTo(-bl * .78, 0); g.stroke();   // fuller
		// runes along the blade, glowing while it still holds magic
		if (aura > .02) for (let i = 0; i < 4; i++) {
			const rx = -bl * (.18 + i * .16);
			glow(g, rx, 0, bw * 1.2, pal.acc, .55 * aura * (.6 + .4 * Math.sin(t * 5 + i * 1.7)));
		}
		// a moving glint
		const gx = -bl * (.5 + .45 * Math.sin(t * .9));
		const gl = g.createLinearGradient(gx - bw * 3, 0, gx + bw * 3, 0);
		gl.addColorStop(0, 'rgba(255,255,255,0)'); gl.addColorStop(.5, `rgba(255,255,255,${.35 * (1 - drain * .6)})`); gl.addColorStop(1, 'rgba(255,255,255,0)');
		g.save(); g.clip(blade); g.fillStyle = gl; g.fillRect(gx - bw * 3, -bw, bw * 6, bw * 2); g.restore();
		// guard
		const gold = c => grey(c, drain * .7);
		const gg = g.createLinearGradient(0, -bw * 3.4, 0, bw * 3.4);
		gg.addColorStop(0, rgba(gold([255, 226, 150]))); gg.addColorStop(.5, rgba(gold([196, 140, 52]))); gg.addColorStop(1, rgba(gold([120, 78, 24])));
		g.fillStyle = gg;
		g.beginPath(); g.moveTo(bw * .3, -bw * 3.4); g.quadraticCurveTo(-bw * 1.1, -bw * 1.6, -bw * .5, 0); g.quadraticCurveTo(-bw * 1.1, bw * 1.6, bw * .3, bw * 3.4);
		g.lineTo(bw * 1.1, bw * 3.0); g.quadraticCurveTo(bw * .6, 0, bw * 1.1, -bw * 3.0); g.closePath(); g.fill();
		// grip, wrapped
		const grip = g.createLinearGradient(0, -bw * .8, 0, bw * .8);
		grip.addColorStop(0, rgba(grey([120, 72, 44], drain * .6))); grip.addColorStop(1, rgba(grey([46, 24, 14], drain * .6)));
		g.fillStyle = grip; g.fillRect(bw * 1, -bw * .75, hl - bw * 2.2, bw * 1.5);
		g.strokeStyle = 'rgba(20,10,6,.45)'; g.lineWidth = Math.max(.5, bw * .12);
		for (let u = bw * 1.4; u < hl - bw * 1.4; u += bw * .7) { g.beginPath(); g.moveTo(u, -bw * .75); g.lineTo(u + bw * .45, bw * .75); g.stroke(); }
		// pommel gem
		const px = hl - bw * .6;
		g.fillStyle = gg; g.beginPath(); g.arc(px, 0, bw * 1.15, 0, 6.283); g.fill();
		const gemC = grey(pal.main, drain);
		const gm = g.createRadialGradient(px - bw * .25, -bw * .25, 0, px, 0, bw * .75);
		gm.addColorStop(0, rgba(light(gemC, .6))); gm.addColorStop(1, rgba(dark(gemC, .35)));
		g.fillStyle = gm; g.beginPath(); g.arc(px, 0, bw * .72, 0, 6.283); g.fill();
		if (aura > .02) { g.globalCompositeOperation = 'lighter'; glow(g, px, 0, bw * 2.4, pal.main, .5 * aura); g.globalCompositeOperation = 'source-over'; }
		g.restore();
	}

	// ------------------------------------------------------------------ A: disenchant siphon
	CONCEPTS.push({
		group: 'Enchanting', id: 'ench-a', letter: 'A', name: 'Disenchant siphon',
		desc: 'The item at the bar\'s end is drained: ribbons and motes of magic are pulled out of it and condense into dust, essences and shards behind the flow; the item greys as it empties',
		spell: 'Disenchant', dur: [2.8, 3.4], padX: 1.3, padTop: 1, padBottom: .8, flash: [220, 180, 255],
		init(s) {
			const { W, H } = s;
			s.pal = pick(PALETTES); s.bg = makeVelvet(W, H, s.pal);
			s.items = []; s.nextDrop = H * rand(.5, .8); s.motes = []; s.moteAcc = 0;
			s.ribbons = [0, 1, 2].map(i => ({ ph: rand(0, 6.283), f: rand(1.1, 1.9), sp: rand(2.4, 3.6) * (i % 2 ? 1 : -1), amp: rand(.14, .26), w: rand(.04, .08) }));
			s.sword = { x: W + H * .55, y: -H * .02, L: H * 1.6, ang: -Math.PI / 2 + rand(-.12, .12) };   // standing tip-down at the bar's end
		},
		draw(g, s) {
			const { W, H, t, dt } = s, f = s.fill, pal = s.pal, drain = easeIn(s.p);
			// what is already siphoned: velvet with the products resting on it
			g.save(); barClip(g, s);
			g.beginPath(); g.rect(0, 0, f, H); g.clip();
			g.drawImage(s.bg, 0, 0, W, H);
			g.globalCompositeOperation = 'lighter';
			const sheen = g.createLinearGradient(0, 0, f, 0);
			sheen.addColorStop(0, rgba(pal.main, 0)); sheen.addColorStop(1, rgba(pal.main, .22));
			g.fillStyle = sheen; g.fillRect(0, 0, f, H);
			g.globalCompositeOperation = 'source-over';
			// products drop out of the flow as it condenses
			while (s.casting && f > s.nextDrop) {
				const r = Math.random(), kind = r < .55 ? 'dust' : r < .8 ? 'essence' : 'shard';
				s.items.push({ kind, x: s.nextDrop - rand(0, .25) * H, y: kind === 'dust' ? H * rand(.72, .84) : kind === 'shard' ? H * rand(.86, .94) : H * rand(.3, .6),
					age: 0, size: H * (kind === 'shard' ? rand(.38, .52) : kind === 'essence' ? rand(.09, .13) : rand(.18, .3)), ang: rand(-.35, .35), ph: rand(0, 6.283), grains: grainsFor() });
				s.nextDrop += H * rand(.3, .55);
			}
			for (const q of s.items) {
				q.age += dt;
				const k = Math.max(.01, easeOutBack(clamp(q.age / .45))), a = clamp(q.age / .2);
				const yy = lerp(H * .5, q.y, easeOut(clamp(q.age / .45)));
				if (q.kind === 'dust') drawDust(g, q.x, yy, q.size * k, q.grains, pal, t, a);
				else if (q.kind === 'shard') drawShard(g, q.x, yy, q.size * k, q.ang, pal, a);
				else drawEssence(g, q.x, yy + Math.sin(t * 1.6 + q.ph) * H * .04, q.size * k, pal, t, q.ph, a);
			}
			// where the flow condenses: a soft swirl of light, not a line
			if (s.casting && f > 2) {
				g.globalCompositeOperation = 'lighter';
				glow(g, f, H * .5, H * .7, pal.main, .35 + .1 * Math.sin(t * 9));
				g.globalCompositeOperation = 'source-over';
			}
			g.restore();
			// the flow: ribbons of magic pulled from the item along the unfilled part
			const x0 = f, x1 = s.sword.x - H * .15;
			if (s.casting && x1 - x0 > H * .2) {
				g.save(); g.globalCompositeOperation = 'lighter'; g.lineCap = 'round';
				for (const rb of s.ribbons) {
					for (const [wm, am, col] of [[3.2, .12, pal.main], [1, .45, pal.acc], [.35, .55, pal.hi]]) {
						g.strokeStyle = rgba(col, am * (1 - drain * .6)); g.lineWidth = Math.max(.7, H * rb.w * wm);
						g.beginPath();
						for (let x = x0; x <= x1; x += 3) {
							const u = (x - x0) / (x1 - x0), env = Math.sin(Math.PI * Math.min(1, u * 1.1)) ** .7 * (1 - .65 * clamp((x - (W - H * 1.6)) / (H * .8)));   // calmer behind the timer
							const y = H * .5 + Math.sin(x / H * rb.f + t * rb.sp + rb.ph) * H * rb.amp * env;
							x === x0 ? g.moveTo(x, y) : g.lineTo(x, y);
						}
						g.stroke();
					}
				}
				g.restore();
			}
			// motes pulled out of the item, racing to the flow's head
			if (s.casting) {
				s.moteAcc += dt * 34 * (1 - drain * .5);
				while (s.moteAcc >= 1) {
					s.moteAcc--;
					const u = rand(.1, .9);
					s.motes.push({ x: s.sword.x + rand(-.12, .12) * H, y: s.sword.y + s.sword.L * .74 * u, vx: -H * rand(2.6, 4.4), ph: rand(0, 6.283), r: H * rand(.03, .07), c: Math.random() < .3 ? pal.acc : pal.hi, by: H * rand(.3, .7) });
				}
			}
			g.save(); g.globalCompositeOperation = 'lighter';
			for (const m of s.motes) {
				m.x += m.vx * dt; m.y = lerp(m.y, m.by + Math.sin(m.x / H * 3 + m.ph) * H * .12, clamp(dt * 3));
				glow(g, m.x, m.y, m.r * 3, pal.main, .4); glow(g, m.x, m.y, m.r, m.c, .95);
			}
			g.restore();
			s.motes = s.motes.filter(m => m.x > f - H * .2);
			s.parts.update(dt); s.parts.draw(g);
		},
		over(g, s) {
			const sw = s.sword, drain = s.done ? 1 : easeIn(s.p);
			drawSword(g, sw.x, sw.y, sw.L, sw.ang, s.pal, drain, s.t);
			// the last of it: a puff of dust as the item gives up its magic
			if (s.done && !s.puffed) {
				s.puffed = true;
				for (let i = 0; i < 18; i++) s.parts.emit({ x: sw.x + rand(-.2, .2) * s.H, y: sw.y + sw.L * rand(.1, .7), vx: rand(-.6, .6) * s.H, vy: rand(-1.2, -.2) * s.H, drag: 2, life: rand(.5, 1), size: s.H * rand(.03, .06), kind: 'glow', color: s.pal.hi });
			}
		},
	});

	// ------------------------------------------------------------------ B: enchant infuse
	// A runed rod at the left channels a beam along the bar; the power spirals into the filled part as
	// swirling light and runes that pulse; a glyph seal flashes when it takes hold.
	function drawRod(g, x, y, L, ang, metal, pal, t, lit) {
		g.save(); g.translate(x, y); g.rotate(ang);
		const r = L * .045;
		g.save(); g.shadowColor = 'rgba(0,0,0,.55)'; g.shadowBlur = L * .05; g.shadowOffsetY = L * .015;
		const sg = g.createLinearGradient(0, -r, 0, r);
		sg.addColorStop(0, rgba(metal.hi)); sg.addColorStop(.4, rgba(metal.mid)); sg.addColorStop(1, rgba(metal.lo));
		g.fillStyle = sg; roundRectPath(g, 0, -r, L * .86, r * 2, r); g.fill(); g.restore();
		// bands
		for (const u of [.08, .5, .78]) {
			const bg = g.createLinearGradient(0, -r * 1.4, 0, r * 1.4);
			bg.addColorStop(0, rgba(light(metal.mid, .5))); bg.addColorStop(1, rgba(dark(metal.lo, .3)));
			g.fillStyle = bg; roundRectPath(g, L * u, -r * 1.4, r * 1.6, r * 2.8, r * .5); g.fill();
		}
		// etched runes glowing along the shaft
		for (let i = 0; i < 4; i++) {
			const rx = L * (.18 + i * .14);
			g.save(); g.globalCompositeOperation = 'lighter';
			glow(g, rx, 0, r * 2.2, pal.acc, (.35 + .3 * Math.sin(t * 6 - i)) * lit);
			g.restore();
		}
		// the crystal at the tip
		const cx = L * .93, ch = r * 4.2;
		g.save(); g.globalCompositeOperation = 'lighter'; glow(g, cx, 0, ch * 2.6, pal.main, .55 * lit); g.restore();
		const cg = g.createLinearGradient(cx - ch, -ch, cx + ch, ch);
		cg.addColorStop(0, rgba(light(pal.main, .65))); cg.addColorStop(.5, rgba(pal.main)); cg.addColorStop(1, rgba(dark(pal.main, .4)));
		g.fillStyle = cg;
		g.beginPath(); g.moveTo(cx + ch, 0); g.lineTo(cx + ch * .15, -ch * .55); g.lineTo(cx - ch * .6, 0); g.lineTo(cx + ch * .15, ch * .55); g.closePath(); g.fill();
		g.fillStyle = 'rgba(255,255,255,.6)'; g.beginPath(); g.ellipse(cx + ch * .2, -ch * .2, ch * .18, ch * .08, -.4, 0, 6.283); g.fill();
		g.restore();
		return [x + Math.cos(ang) * L * 1.0, y + Math.sin(ang) * L * 1.0];
	}
	CONCEPTS.push({
		group: 'Enchanting', id: 'ench-b', letter: 'B', name: 'Enchanting rod',
		desc: 'A runed enchanting rod at the left channels a beam along the bar; the power spirals into the filled part as swirling light and runes that pulse; a glyph seal flashes as the enchantment takes hold',
		spell: 'Enchant Weapon - Crusader', dur: [2.8, 3.4], padX: 1.9, padTop: 1.1, padBottom: .9, flash: [255, 220, 150],
		init(s) {
			const { W, H } = s;
			s.pal = pick(PALETTES); s.metal = pick(ROD_METALS); s.bg = makeVelvet(W, H, s.pal);
			s.helix = []; s.hAcc = 0; s.runes = []; s.runeNext = H * rand(.5, .9);
			s.bands = [0, 1, 2].map(() => ({ f: rand(.9, 1.6), sp: rand(1.2, 2.2), ph: rand(0, 6.283), y: rand(.3, .7) }));
			s.seal = makeRune(); s.sealRunes = Array.from({ length: 8 }, makeRune);
			s.rod = { x: -H * 1.65, y: H * 1.05, L: H * 1.7, ang: -.32 };
		},
		draw(g, s) {
			const { W, H, t, dt } = s, f = s.fill, pal = s.pal, pulse = .82 + .18 * Math.sin(t * 4.2);
			g.save(); barClip(g, s);
			g.beginPath(); g.rect(0, 0, f, H); g.clip();
			g.drawImage(s.bg, 0, 0, W, H);
			// the enchantment: slow swirling bands of light
			g.globalCompositeOperation = 'lighter';
			for (const b of s.bands) {
				for (const [wm, am, col] of [[.5, .12, pal.main], [.18, .26, pal.acc]]) {
					g.strokeStyle = rgba(col, am * pulse); g.lineWidth = H * wm * .4; g.lineCap = 'round';
					g.beginPath();
					for (let x = 0; x <= f; x += 4) {
						const y = H * b.y + Math.sin(x / H * b.f - t * b.sp + b.ph) * H * .2;
						x ? g.lineTo(x, y) : g.moveTo(x, y);
					}
					g.stroke();
				}
			}
			// runes fade in where the power lands and pulse
			while (s.casting && f > s.runeNext) { s.runes.push({ x: s.runeNext, y: H * rand(.28, .72), size: H * rand(.3, .46), st: makeRune(), born: t, ph: rand(0, 6.283) }); s.runeNext += H * rand(.55, .9); }
			for (const r of s.runes) drawRune(g, r.x, r.y, r.size, r.st, pal.hi, clamp((t - r.born) / .3) * (.35 + .3 * Math.sin(t * 3 + r.ph)) * pulse);
			g.globalCompositeOperation = 'source-over';
			g.restore();
			// the beam from the rod's crystal to where the power is landing
			const tip = s.tip || [0, H * .5];
			if (s.casting && f > 1) {
				g.save(); g.globalCompositeOperation = 'lighter'; g.lineCap = 'round';
				for (const [w, a, col] of [[.42, .12, pal.main], [.16, .34, pal.acc], [.05, .6, pal.hi]]) {
					g.strokeStyle = rgba(col, a * pulse); g.lineWidth = H * w;
					g.beginPath(); g.moveTo(tip[0], tip[1]);
					g.quadraticCurveTo(Math.min(f, H * .9), H * .5, f, H * .5);
					g.stroke();
				}
				g.restore();
				// a helix of motes riding the beam into the bar
				s.hAcc += dt * 40;
				while (s.hAcc >= 1) { s.hAcc--; s.helix.push({ x: Math.max(0, tip[0]), ph: rand(0, 6.283), sp: H * rand(3, 4.5), c: Math.random() < .4 ? pal.acc : pal.hi }); }
			}
			g.save(); g.globalCompositeOperation = 'lighter';
			for (const m of s.helix) {
				m.x += m.sp * dt; m.ph += dt * 9;
				const depth = .5 + .5 * Math.cos(m.ph), y = H * .5 + Math.sin(m.ph) * H * .3;
				glow(g, m.x, y, H * (.05 + .06 * depth), m.c, .4 + .5 * depth);
			}
			g.restore();
			s.helix = s.helix.filter(m => m.x < f);
			s.parts.update(dt); s.parts.draw(g);
		},
		over(g, s) {
			const H = s.H, rd = s.rod, lit = s.done ? clamp(1 - s.doneT * 2) : 1;
			s.tip = drawRod(g, rd.x, rd.y, rd.L, rd.ang, s.metal, s.pal, s.t, lit);
			// the glyph seal: a ring of runes that flares over the bar as the enchantment takes hold
			if (s.done) {
				const k = Math.max(.01, easeOutBack(clamp(s.doneT * 3))), a = clamp(1 - s.doneT * 1.4), cx = s.W * .5, cy = H * .5, R = H * .9 * k;
				g.save(); g.globalCompositeOperation = 'lighter';
				glow(g, cx, cy, R * 1.6, s.pal.main, .5 * a);
				g.strokeStyle = rgba(s.pal.gold, .8 * a); g.lineWidth = Math.max(1, H * .05);
				g.beginPath(); g.arc(cx, cy, R, 0, 6.283); g.stroke();
				g.lineWidth = Math.max(.8, H * .025); g.beginPath(); g.arc(cx, cy, R * .78, 0, 6.283); g.stroke();
				s.sealRunes.forEach((st, i) => { const an = i / 8 * 6.283 + s.doneT * .8; drawRune(g, cx + Math.cos(an) * R * .89, cy + Math.sin(an) * R * .89, R * .16, st, s.pal.gold, a); });
				drawRune(g, cx, cy, R * .7, s.seal, s.pal.hi, a);
				g.restore();
			}
		},
	});

	// ------------------------------------------------------------------ C: vortex siphon
	// A swirling funnel of power at the cast edge pulls glittering dust out of the unfilled part and
	// spins it into the filled part, where it settles as shimmering, slowly flowing magic.
	const vortexC = {
		group: 'Enchanting', id: 'ench-c', letter: 'C', name: 'Vortex siphon',
		desc: 'A swirling vortex at the cast edge pulls glittering dust out of the unfilled part and spins it into the filled part, where it settles as shimmering, flowing magic',
		spell: 'Enchant Chest - Major Health', dur: [2.8, 3.4], padTop: .8, padBottom: .8, flash: [200, 170, 255],
		init(s) {
			const { W, H } = s;
			s.pal = pick(PALETTES); s.bg = makeVelvet(W, H, s.pal);
			s.dust = []; for (let i = 0; i < W / H * 16; i++) s.dust.push(newDust(s, rand(0, W)));
			s.glitter = []; for (let i = 0; i < W / H * 10; i++) s.glitter.push({ x: rand(0, W), y: rand(.1, .9) * H, f: rand(2, 6), ph: rand(0, 6.283), r: rand(.02, .045) });
			s.flowPh = rand(0, 6.283);
		},
		draw(g, s) {
			const { W, H, t, dt } = s, f = s.fill, pal = s.pal;
			// settled power
			g.save(); barClip(g, s);
			g.beginPath(); g.rect(0, 0, f, H); g.clip();
			g.drawImage(s.bg, 0, 0, W, H);
			g.globalCompositeOperation = 'lighter';
			for (let k = 0; k < 2; k++) {
				const gr = g.createLinearGradient(0, 0, 0, H);
				gr.addColorStop(0, rgba(pal.main, 0)); gr.addColorStop(.5, rgba(k ? pal.acc : pal.main, .2)); gr.addColorStop(1, rgba(pal.main, 0));
				g.fillStyle = gr;
				g.beginPath(); g.moveTo(0, H);
				for (let x = 0; x <= f; x += 4) g.lineTo(x, H * (.45 + k * .1) + Math.sin(x / H * (1.1 + k * .4) - t * (1.4 + k * .5) + s.flowPh) * H * .25);
				g.lineTo(f, H); g.closePath(); g.fill();
			}
			for (const q of s.glitter) {
				if (q.x > f) continue;
				const a = Math.max(0, Math.sin(t * q.f + q.ph)) ** 3;
				glow(g, q.x, q.y, H * q.r * 3, pal.hi, a * .8);
			}
			g.globalCompositeOperation = 'source-over';
			g.restore();
			// dust in the unfilled part, drawn toward the vortex and spun into it
			const vx = f, vy = H * .5;
			g.save(); barClip(g, s); g.globalCompositeOperation = 'lighter';
			for (const d of s.dust) {
				const dx = d.x - vx, dist = Math.max(H * .2, Math.abs(dx));
				const pull = s.casting ? H * 2.8 / (dist / H + .4) : 0;
				d.x -= pull * dt * (dx > 0 ? 1 : 0);
				d.ang += dt * (2 + 9 / (dist / H + .3));
				const near = clamp(1 - dist / (H * 1.6));
				const y = lerp(d.y, vy + Math.sin(d.ang) * H * .38 * (1 - near * .4), near);
				const a = .25 + .55 * near * (.5 + .5 * Math.sin(t * d.f + d.ph));
				glow(g, d.x, y, H * d.r * 2.6, near > .3 ? pal.acc : pal.main, a * .6);
				g.fillStyle = rgba(pal.hi, a); g.beginPath(); g.arc(d.x, y, Math.max(.5, H * d.r * .6), 0, 6.283); g.fill();
			}
			g.restore();
			for (let i = 0; i < s.dust.length; i++) if (s.dust[i].x < vx - H * .05) s.dust[i] = newDust(s, rand(Math.max(vx + H * .5, 0), W + H * .5));
			s.parts.update(dt); s.parts.draw(g);
		},
		over(g, s) { if (s.casting && s.fill >= 2) drawVortex(g, s, 1); },
	};
	CONCEPTS.push(vortexC);

	function newDust(s, x) { return { x, y: s.H * rand(.1, .9), ang: rand(0, 6.283), r: rand(.025, .05), f: rand(2, 6), ph: rand(0, 6.283) }; }

	// The vortex: tilted rings of light spinning at the cast edge, tighter toward its throat. dir 1 draws
	// power in (enchanting), -1 turns the other way and leans the other way (disenchanting throws it out).
	function drawVortex(g, s, dir, x = s.fill) {
		const { H, t } = s, y = H * .5, pal = s.pal;
		g.save(); g.globalCompositeOperation = 'lighter';
		glow(g, x, y, H * .9, pal.main, .35);
		for (let i = 0; i < 6; i++) {
			const k = i / 5, rx = H * lerp(.36, .1, k), ry = H * lerp(.62, .2, k), sp = (dir * t * (3 + i * 1.6)) % 6.283;
			g.strokeStyle = rgba(i % 2 ? pal.acc : pal.hi, .2 + .5 * k); g.lineWidth = Math.max(.7, H * .035);
			g.beginPath(); g.ellipse(x + dir * H * .05 * k, y, rx, ry, .25 * dir, sp, sp + 4.2); g.stroke();
		}
		glow(g, x, y, H * .18, [255, 255, 255], .85);
		g.restore();
	}

	// The settled-power flow of C, drawn between x0 and x1 with alpha a(x) (C2 fades it out behind the vortex).
	function drawFlow(g, s, x0, x1, alphaAt) {
		const { H, t } = s, pal = s.pal, step = Math.max(2, H * .2);
		g.save(); g.globalCompositeOperation = 'lighter';
		for (let sx = Math.max(0, x0); sx < x1; sx += step) {
			const a = alphaAt(sx + step / 2);
			if (a <= .01) continue;
			g.save(); g.beginPath(); g.rect(sx, 0, Math.min(step, x1 - sx) + .5, H); g.clip(); g.globalAlpha = a;
			for (let k = 0; k < 2; k++) {
				const gr = g.createLinearGradient(0, 0, 0, H);
				gr.addColorStop(0, rgba(pal.main, 0)); gr.addColorStop(.5, rgba(k ? pal.acc : pal.main, .2)); gr.addColorStop(1, rgba(pal.main, 0));
				g.fillStyle = gr; g.beginPath(); g.moveTo(sx, H);
				for (let x = sx; x <= sx + step + 4; x += 4) g.lineTo(x, H * (.45 + k * .1) + Math.sin(x / H * (1.1 + k * .4) - t * (1.4 + k * .5) * s.flowDir + s.flowPh) * H * .25);
				g.lineTo(sx + step + 4, H); g.closePath(); g.fill();
			}
			g.restore();
		}
		g.restore();
	}

	// ------------------------------------------------------------------ C2: vortex siphon, disenchant
	// C flipped: the vortex turns the other way and pulls the magic OUT of the filled part, throwing it
	// ahead as glittering dust and essence motes that drift and settle on the unfilled part. Behind it the
	// bar is left dull and spent; only the stretch just behind the vortex still holds magic being drawn off.
	CONCEPTS.push({
		group: 'Enchanting', id: 'ench-c2', letter: 'C2', name: 'Vortex siphon, disenchant',
		desc: 'C flipped for Disenchant: the vortex turns the other way, draws the magic out of the filled part and throws it ahead as glittering dust that settles on the unfilled part; behind it the bar is left dull and spent',
		spell: 'Disenchant', dur: [2.8, 3.4], padTop: .8, padBottom: .8, flash: [170, 150, 210],
		init(s) {
			const { W, H } = s;
			s.pal = pick(PALETTES); s.bg = makeVelvet(W, H, s.pal);
			// the spent velvet: the same cloth with the colour drained out
			const k = typeof dpr === 'number' ? dpr : 1;
			s.spent = mkCanvas(W * k, H * k);
			const sg = s.spent.getContext('2d'); sg.filter = 'grayscale(.85) brightness(.55)'; sg.drawImage(s.bg, 0, 0);
			s.flowPh = rand(0, 6.283); s.flowDir = -1;
			s.pull = []; s.thrown = []; s.pullAcc = 0;
			s.ash = []; for (let i = 0; i < W / H * 8; i++) s.ash.push({ x: rand(0, W), y: rand(.1, .9) * H, f: rand(1, 3), ph: rand(0, 6.283), r: rand(.015, .03) });
		},
		draw(g, s) {
			const { W, H, t, dt } = s, f = s.fill, pal = s.pal, DRAIN = H * 2.6;
			// behind the vortex: spent cloth, with the magic still being drawn off just behind it
			g.save(); barClip(g, s);
			g.beginPath(); g.rect(0, 0, f, H); g.clip();
			g.drawImage(s.spent, 0, 0, W, H);
			const fresh = x => clamp(1 - (f - x) / DRAIN) ** 1.4;
			// the cloth is still coloured where the drain hasn't finished, fading smoothly into the spent part
			const kp = s.bg.width / W, strip = Math.max(2, H * .12);
			for (let sx = Math.max(0, f - DRAIN); sx < f; sx += strip) {
				const w = Math.min(strip, f - sx);
				g.globalAlpha = .9 * fresh(sx + w / 2);
				g.drawImage(s.bg, sx * kp, 0, w * kp, s.bg.height, sx, 0, w, H);
			}
			g.globalAlpha = 1;
			drawFlow(g, s, f - DRAIN, f, x => fresh(x));
			g.globalCompositeOperation = 'lighter';
			for (const q of s.ash) {   // a last few dull glints in the spent part
				if (q.x > f - DRAIN * .5) continue;
				const a = Math.max(0, Math.sin(t * q.f + q.ph)) ** 4 * .25;
				glow(g, q.x, q.y, H * q.r * 3, [190, 190, 200], a);
			}
			g.restore();
			// motes drawn out of the drain stretch, spiralling right into the vortex
			const vx = f, vy = H * .5;
			if (s.casting && f > H * .3) {
				s.pullAcc += dt * 26;
				while (s.pullAcc >= 1) {
					s.pullAcc--;
					s.pull.push({ x: rand(Math.max(0, f - DRAIN), f - H * .15), y: H * rand(.12, .88), ang: rand(0, 6.283), r: rand(.025, .05), f: rand(2, 6), ph: rand(0, 6.283) });
				}
			}
			g.save(); g.globalCompositeOperation = 'lighter';
			for (let i = s.pull.length - 1; i >= 0; i--) {
				const d = s.pull[i], dx = vx - d.x, dist = Math.max(H * .15, Math.abs(dx));
				d.x += H * 2.6 / (dist / H + .35) * dt;
				d.ang -= dt * (2 + 9 / (dist / H + .3));
				const near = clamp(1 - dist / (H * 1.6));
				const y = lerp(d.y, vy + Math.sin(d.ang) * H * .38 * (1 - near * .4), near);
				const a = .35 + .55 * near;
				glow(g, d.x, y, H * d.r * 2.6, near > .3 ? pal.acc : pal.main, a * .6);
				g.fillStyle = rgba(pal.hi, a); g.beginPath(); g.arc(d.x, y, Math.max(.5, H * d.r * .6), 0, 6.283); g.fill();
				if (d.x >= vx - H * .05 || !s.casting) {
					s.pull.splice(i, 1);
					// out of the throat and flung ahead: some dust, now and then an essence mote
					if (s.casting) s.thrown.push({ x: vx + H * .1, y: vy + rand(-.15, .15) * H, vx: H * rand(1.4, 3.6), vy: H * rand(-1.2, 1.2), rest: H * rand(.15, .85),
						r: rand(.02, .045), f: rand(2, 6), ph: rand(0, 6.283), ess: Math.random() < .07, c: Math.random() < .5, age: 0 });
				}
			}
			// thrown dust drifts ahead, slows and settles on the unfilled part, where it collects and glitters
			for (const q of s.thrown) {
				q.age += dt;
				const drag = Math.exp(-dt * 2.4);
				q.vx *= drag; q.vy = q.vy * drag + (q.rest - q.y) * dt * 3;
				q.x += q.vx * dt; q.y += q.vy * dt;
				// the vortex's wind keeps the dust ahead of it: it is never left behind on the spent part
				if (s.casting) q.x = Math.max(q.x, vx + H * (.3 + .2 * Math.sin(q.ph)));
				if (q.x > W + H) continue;
				const tw = .45 + .55 * Math.max(0, Math.sin(t * q.f + q.ph));
				if (q.ess) drawEssence(g, q.x, q.y, H * .07, pal, t, q.ph, .8);
				else {
					glow(g, q.x, q.y, H * q.r * 2.4, pal.main, .35 * tw);
					g.fillStyle = rgba(q.c ? pal.hi : pal.acc, .85 * tw); g.beginPath(); g.arc(q.x, q.y, Math.max(.5, H * q.r * .55), 0, 6.283); g.fill();
				}
			}
			if (s.thrown.length > 400) s.thrown.splice(0, s.thrown.length - 400);
			g.restore();
			s.parts.update(dt); s.parts.draw(g);
		},
		over(g, s) { if (s.casting && s.fill >= 2) drawVortex(g, s, -1); },
	});

	// ------------------------------------------------------------------ C3: vortex siphon, disenchant, right to left
	// The bar starts as solid enchanted velvet. The vortex comes in at the right end and travels left,
	// drawing the magic out as it goes: ahead of it (left) the magic is still solid, fading as it is drawn
	// off over the drain stretch; behind it (right) the cloth is left spent, with the extracted dust and
	// essence motes flung out and settling there, glittering. C2's spent cloth, motes and dust.
	CONCEPTS.push({
		group: 'Enchanting', id: 'ench-c3', letter: 'C3', name: 'Vortex siphon, disenchant',
		desc: 'Disenchant: the bar starts solid with magic; the vortex comes in from the right end and moves left, drawing the magic out of the solid part ahead of it and throwing it out behind as glittering dust that settles on the spent cloth',
		spell: 'Disenchant', dur: [2.8, 3.4], padTop: .8, padBottom: .8, flash: [170, 150, 210],
		init(s) {
			const { W, H } = s;
			s.pal = pick(PALETTES); s.bg = makeVelvet(W, H, s.pal);
			const k = typeof dpr === 'number' ? dpr : 1;
			s.spent = mkCanvas(W * k, H * k);
			const sg = s.spent.getContext('2d'); sg.filter = 'grayscale(.85) brightness(.55)'; sg.drawImage(s.bg, 0, 0);
			s.flowPh = rand(0, 6.283); s.flowDir = 1;
			s.pull = []; s.thrown = []; s.pullAcc = 0;
			s.glitter = []; for (let i = 0; i < W / H * 10; i++) s.glitter.push({ x: rand(0, W), y: rand(.1, .9) * H, f: rand(2, 6), ph: rand(0, 6.283), r: rand(.02, .045) });
			s.ash = []; for (let i = 0; i < W / H * 8; i++) s.ash.push({ x: rand(0, W), y: rand(.1, .9) * H, f: rand(1, 3), ph: rand(0, 6.283), r: rand(.015, .03) });
		},
		draw(g, s) {
			const { W, H, t, dt } = s, pal = s.pal, DRAIN = H * 2.6, vx = W - s.fill, vy = H * .5;
			const fresh = x => clamp((vx - x) / DRAIN) ** 1.4;   // 1 well ahead of the vortex, 0 at it
			g.save(); barClip(g, s);
			g.drawImage(s.spent, 0, 0, W, H);
			// ahead (left): the solid magic, fading into the spent cloth over the drain stretch before the vortex
			const kp = s.bg.width / W, strip = Math.max(2, H * .12), solid = Math.max(0, vx - DRAIN);
			if (solid > 0) g.drawImage(s.bg, 0, 0, solid * kp, s.bg.height, 0, 0, solid, H);
			for (let sx = solid; sx < vx; sx += strip) {
				const w = Math.min(strip, vx - sx);
				g.globalAlpha = .9 * fresh(sx + w / 2);
				g.drawImage(s.bg, sx * kp, 0, w * kp, s.bg.height, sx, 0, w, H);
			}
			g.globalAlpha = 1;
			drawFlow(g, s, 0, vx, x => fresh(x));
			g.globalCompositeOperation = 'lighter';
			for (const q of s.glitter) {   // the solid part shimmers
				if (q.x > vx - DRAIN * .3) continue;
				const a = Math.max(0, Math.sin(t * q.f + q.ph)) ** 3;
				glow(g, q.x, q.y, H * q.r * 3, pal.hi, a * .8);
			}
			for (const q of s.ash) {   // a last few dull glints in the spent part behind
				if (q.x < vx + DRAIN * .5) continue;
				const a = Math.max(0, Math.sin(t * q.f + q.ph)) ** 4 * .25;
				glow(g, q.x, q.y, H * q.r * 3, [190, 190, 200], a);
			}
			g.restore();
			// motes drawn out of the drain stretch ahead, spiralling right into the vortex
			if (s.casting && vx > H * .3) {
				s.pullAcc += dt * 26;
				while (s.pullAcc >= 1) {
					s.pullAcc--;
					s.pull.push({ x: rand(Math.max(0, vx - DRAIN), vx - H * .15), y: H * rand(.12, .88), ang: rand(0, 6.283), r: rand(.025, .05), f: rand(2, 6), ph: rand(0, 6.283) });
				}
			}
			g.save(); barClip(g, s); g.globalCompositeOperation = 'lighter';   // the dust stays inside the bar
			for (let i = s.pull.length - 1; i >= 0; i--) {
				const d = s.pull[i], dx = vx - d.x, dist = Math.max(H * .15, Math.abs(dx));
				d.x += H * 2.6 / (dist / H + .35) * dt;
				d.ang -= dt * (2 + 9 / (dist / H + .3));
				const near = clamp(1 - dist / (H * 1.6));
				const y = lerp(d.y, vy + Math.sin(d.ang) * H * .38 * (1 - near * .4), near);
				const a = .35 + .55 * near;
				glow(g, d.x, y, H * d.r * 2.6, near > .3 ? pal.acc : pal.main, a * .6);
				g.fillStyle = rgba(pal.hi, a); g.beginPath(); g.arc(d.x, y, Math.max(.5, H * d.r * .6), 0, 6.283); g.fill();
				if (d.x >= vx - H * .05 || !s.casting) {
					s.pull.splice(i, 1);
					// out of the throat and flung behind (right): dust, now and then an essence mote
					if (s.casting) s.thrown.push({ x: vx + H * .1, y: vy + rand(-.15, .15) * H, vx: H * rand(1.4, 3.6), vy: H * rand(-1.2, 1.2), rest: H * rand(.15, .85),
						r: rand(.02, .045), f: rand(2, 6), ph: rand(0, 6.283), ess: Math.random() < .07, c: Math.random() < .5, age: 0 });
				}
			}
			// the thrown dust drifts behind, slows and settles on the spent cloth, where it collects and glitters
			for (const q of s.thrown) {
				q.age += dt;
				const drag = Math.exp(-dt * 2.4);
				q.vx *= drag; q.vy = q.vy * drag + (q.rest - q.y) * dt * 3;
				q.x += q.vx * dt; q.y += q.vy * dt;
				if (s.casting) q.x = Math.max(q.x, vx + H * (.3 + .2 * Math.sin(q.ph)));   // never left on the solid part
				if (q.x > W + H) continue;
				const tw = .45 + .55 * Math.max(0, Math.sin(t * q.f + q.ph));
				if (q.ess) drawEssence(g, q.x, q.y, H * .07, pal, t, q.ph, .8);
				else {
					glow(g, q.x, q.y, H * q.r * 2.4, pal.main, .35 * tw);
					g.fillStyle = rgba(q.c ? pal.hi : pal.acc, .85 * tw); g.beginPath(); g.arc(q.x, q.y, Math.max(.5, H * q.r * .55), 0, 6.283); g.fill();
				}
			}
			if (s.thrown.length > 400) s.thrown.splice(0, s.thrown.length - 400);
			g.restore();
			s.parts.update(dt); s.parts.draw(g);
		},
		over(g, s) { if (s.casting && s.fill >= 2) drawVortex(g, s, -1, s.W - s.fill); },
	});
})();
