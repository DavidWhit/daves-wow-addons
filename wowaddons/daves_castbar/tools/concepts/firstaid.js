// First Aid concepts: a bleeding wound bound up in bandage as the cast goes on.
// Same painterly style as the approved looks: soft shading, no hard outlines, no leading-edge marker (the
// wrapping shows the progress). Kept cheap per frame, the way the add-on would draw it: the gauze, the wound
// and the blood blots are painted once per cast, and each frame only places them (one image per bandage
// turn, one scrolling wound, a handful of blots, beads and drops). A turn is laid at a fixed lean and never
// turns while it shows, so the add-on can paint the turns as a few lean poses.
// Page keys: &wrap=spiral|figure8|reverse|spica|circular, &cloth=0..4 (linen, wool, silk, mageweave, runecloth).
(() => {
	const CRIM = [150, 8, 24], CRIM_D = [74, 2, 10], CRIM_L = [214, 30, 44], DRIED = [92, 18, 16], DRIED_D = [52, 10, 8];
	const CLOTHS = [
		{ spell: 'Heavy Linen Bandage', base: [238, 230, 214], shade: [170, 156, 132], weave: .55 },
		{ spell: 'Heavy Wool Bandage', base: [228, 214, 186], shade: [150, 130, 98], weave: .85 },
		{ spell: 'Heavy Silk Bandage', base: [246, 242, 238], shade: [186, 178, 174], weave: .3, sheen: 1 },
		{ spell: 'Heavy Mageweave Bandage', base: [230, 220, 238], shade: [152, 136, 172], weave: .5, sheen: .6 },
		{ spell: 'Heavy Runecloth Bandage', base: [216, 224, 234], shade: [134, 146, 168], weave: .6 },
	];
	const STYLES = ['spiral', 'figure8', 'reverse', 'spica', 'circular'];
	const STYLE_NAMES = { spiral: 'spiral', figure8: 'figure-eight', reverse: 'reverse spiral', spica: 'spica', circular: 'circular' };
	const Q = new URLSearchParams(location.search);
	let clothN = Math.floor(Math.random() * CLOTHS.length), styleN = Math.floor(Math.random() * STYLES.length);
	const K = () => (typeof dpr === 'number' ? dpr : 1);
	function mkCanvas(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }
	// lub-dub: two soft bumps per beat
	function heartbeat(t, rate) { const ph = (t * rate) % 1; return Math.exp(-(((ph - .05) / .05) ** 2)) + .6 * Math.exp(-(((ph - .25) / .055) ** 2)); }

	// One bandage strip, painted once per cast: x across its width, y along its length. Open gauze weave,
	// a few slubs, clean hemmed edges (no fraying), a hint of roundness across the band.
	function makeBand(cl, bw, len, H) {
		const k = K(), cv = mkCanvas(bw * k, len * k), g = cv.getContext('2d');
		g.scale(k, k);
		const gr = g.createLinearGradient(0, 0, bw, 0);
		gr.addColorStop(0, rgba(mix(cl.base, cl.shade, .5))); gr.addColorStop(.2, rgba(cl.base));
		gr.addColorStop(.55, rgba(mix(cl.base, [255, 255, 255], .3 + (cl.sheen || 0) * .2))); gr.addColorStop(1, rgba(mix(cl.base, cl.shade, .6)));
		g.fillStyle = gr; g.fillRect(0, 0, bw, len);
		for (let i = 0; i < len / H * 4; i++) {   // soft mottling
			const x = rand(0, bw), y = rand(0, len), r = H * rand(.1, .3), m = g.createRadialGradient(x, y, 0, x, y, r);
			m.addColorStop(0, rgba(cl.shade, .14)); m.addColorStop(1, rgba(cl.shade, 0));
			g.fillStyle = m; g.fillRect(x - r, y - r, r * 2, r * 2);
		}
		const sp = Math.max(1.6, H * .055);
		g.lineWidth = Math.max(.45, sp * .3);
		for (let x = sp * .5; x < bw; x += sp) { g.strokeStyle = rgba(cl.shade, cl.weave * rand(.3, .5)); g.beginPath(); g.moveTo(x, 0); g.lineTo(x, len); g.stroke(); }
		for (let y = sp * .5; y < len; y += sp) { g.strokeStyle = rgba(cl.shade, cl.weave * rand(.25, .45)); g.beginPath(); g.moveTo(0, y); g.lineTo(bw, y); g.stroke(); }
		g.lineCap = 'round';
		for (let i = 0; i < len / H * 7; i++) {   // slubs: thicker bits of thread
			const x = rand(0, bw), y = rand(0, len), light = Math.random() < .5;
			g.strokeStyle = light ? `rgba(255,255,255,${rand(.25, .45)})` : rgba(cl.shade, rand(.25, .4)); g.lineWidth = Math.max(.6, sp * .42);
			g.beginPath(); g.moveTo(x, y); g.lineTo(x + rand(-.4, .4), y + H * rand(.06, .16)); g.stroke();
		}
		const hem = Math.max(1, bw * .06);   // hems: a crisp folded edge each side
		g.fillStyle = rgba(cl.shade, .6); g.fillRect(0, 0, hem, len); g.fillRect(bw - hem, 0, hem, len);
		g.fillStyle = 'rgba(255,255,255,.4)'; g.fillRect(hem, 0, Math.max(.6, bw * .025), len);
		return cv;
	}

	// The open wound: crimson that runs downward, twice the bar's height and repeating every bar height, so
	// it can scroll (one texture with a moving texcoord in the add-on).
	function makeWound(W, H) {
		const k = K(), cv = mkCanvas(W * k, 2 * H * k), g = cv.getContext('2d');
		g.scale(k, k);
		g.fillStyle = rgba(mix(CRIM, CRIM_D, .4)); g.fillRect(0, 0, W, 2 * H);
		const rep = (y, fn) => { for (const oy of [-H, 0, H, 2 * H]) fn(y + oy); };
		for (let i = 0; i < W / H * 10; i++) {   // streaks of blood running down
			const x = rand(0, W), y0 = rand(0, H), r = H * rand(.1, .45), c = pick([CRIM_D, CRIM, CRIM_L, [112, 4, 16]]), a = rand(.25, .6);
			rep(y0, y => {
				const gr = g.createRadialGradient(x, y, 0, x, y, r);
				gr.addColorStop(0, rgba(c, a)); gr.addColorStop(1, rgba(c, 0));
				g.save(); g.translate(x, y); g.scale(.55, 1.7); g.translate(-x, -y); g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2); g.restore();
			});
		}
		g.lineCap = 'round';
		for (let i = 0; i < W / H * 4; i++) {   // bright rivulets
			const x = rand(0, W), y0 = rand(0, H), l = H * rand(.3, .9), w = H * rand(.02, .05), cx = rand(-.1, .1) * H, ex = rand(-.08, .08) * H, a = rand(.2, .45);
			rep(y0, y => { g.strokeStyle = rgba(CRIM_L, a); g.lineWidth = w; g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + cx, y + l * .5, x + ex, y + l); g.stroke(); });
		}
		for (let i = 0; i < W / H * 5; i++) {   // dark clots
			const x = rand(0, W), y0 = rand(0, H), r = H * rand(.03, .08);
			rep(y0, y => { g.fillStyle = rgba([40, 0, 4], .55); g.beginPath(); g.ellipse(x, y, r, r * 1.4, 0, 0, 6.283); g.fill(); });
		}
		return cv;
	}
	// Wet shine on the wound, which stays put while the blood runs under it.
	function makeGloss(W, H) {
		const k = K(), cv = mkCanvas(W * k, H * k), g = cv.getContext('2d');
		g.scale(k, k);
		for (let i = 0; i < W / H * 2.5; i++) {
			const x = rand(0, W), y = H * rand(.18, .4), rx = H * rand(.25, .8), ry = H * rand(.03, .07);
			const gr = g.createRadialGradient(x, y, 0, x, y, rx);
			gr.addColorStop(0, 'rgba(255,215,220,.35)'); gr.addColorStop(1, 'rgba(255,215,220,0)');
			g.save(); g.translate(x, y); g.scale(1, ry / rx); g.translate(-x, -y); g.fillStyle = gr; g.fillRect(x - rx, y - rx, rx * 2, rx * 2); g.restore();
		}
		for (let i = 0; i < W / H * 6; i++) { g.fillStyle = `rgba(255,235,235,${rand(.25, .6)})`; g.beginPath(); g.arc(rand(0, W), H * rand(.12, .6), H * rand(.012, .025), 0, 6.283); g.fill(); }
		return cv;
	}

	// A blot of blood soaked into gauze: a darker tide line at its rim, the weave showing through. Four
	// shapes, fresh and dried, painted once per bar height and reused (flipped) for every blot.
	function makeBlot(sz, col, rim) {
		const k = K(), cv = mkCanvas(sz * k, sz * k), g = cv.getContext('2d');
		g.scale(k, k);
		const c = sz / 2, blobs = [];
		for (let i = 0; i < 9; i++) { const a = rand(0, 6.283), d = i ? sz * rand(.05, .22) : 0; blobs.push([c + Math.cos(a) * d, c + Math.sin(a) * d, sz * (i ? rand(.1, .2) : .26)]); }
		const shape = sc => { g.beginPath(); for (const [x, y, r] of blobs) { const px = c + (x - c) * sc, py = c + (y - c) * sc; g.moveTo(px + r * sc, py); g.arc(px, py, r * sc, 0, 6.283); } };
		g.filter = `blur(${Math.max(.8, sz * .05)}px)`;
		g.fillStyle = rgba(rim, .75); shape(.95); g.fill();
		g.filter = `blur(${Math.max(.8, sz * .07)}px)`;
		g.fillStyle = rgba(col, .8); shape(.72); g.fill();
		g.filter = 'none';
		g.globalCompositeOperation = 'source-atop';
		const gr = g.createRadialGradient(c, c, 0, c, c, sz * .35);
		gr.addColorStop(0, rgba(mix(col, [255, 90, 100], .22), .5)); gr.addColorStop(1, rgba(col, 0));
		g.fillStyle = gr; g.fillRect(0, 0, sz, sz);
		const sp = Math.max(1.4, sz * .09);
		g.strokeStyle = 'rgba(255,220,220,.12)'; g.lineWidth = Math.max(.4, sp * .3);
		for (let x = sp * .5; x < sz; x += sp) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x, sz); g.stroke(); }
		for (let y = sp * .5; y < sz; y += sp) { g.beginPath(); g.moveTo(0, y); g.lineTo(sz, y); g.stroke(); }
		return cv;
	}
	const blotCache = {};
	function getBlots(H) {
		const key = H + ':' + K();
		if (!blotCache[key]) {
			const sz = Math.max(12, H * .7), fresh = [], dried = [];
			for (let i = 0; i < 4; i++) { fresh.push(makeBlot(sz, CRIM, CRIM_D)); dried.push(makeBlot(sz, DRIED, DRIED_D)); }
			blotCache[key] = { fresh, dried };
		}
		return blotCache[key];
	}

	// ------------------------------------------------------------------ shared
	// Lays out the turns for this cast. Each turn: centre cx, lean a, where along the cast it starts (ws)
	// and ends (we) coming round, and the blots that soak through it once it's laid.
	function faInit(s, o) {
		const { W, H } = s;
		s.cl = Q.has('cloth') ? CLOTHS[+Q.get('cloth') % CLOTHS.length] : CLOTHS[0];   // one bandage (linen); &cloth= still shows the others
		s.style = (STYLES.includes(Q.get('wrap')) && Q.get('wrap')) || STYLES[styleN++ % STYLES.length];
		s.lean = pick([-1, 1]); s.up = Math.random() < .5;
		const A = s.style === 'circular' ? .05 : rand(.32, .46), bw = s.bw = Math.max(H * 1.4, Math.min(H * 5, W / 7)) * rand(.93, 1.07);   // a seventh of the bar's length wide (1.4 to 5 bar heights)
		s.L = H / Math.cos(A + .08) + bw * Math.tan(A + .08) + 4;
		s.band = makeBand(s.cl, bw, s.L * 3, H);
		s.wound = makeWound(W, H); s.gloss = makeGloss(W, H); s.blots = getBlots(H);
		s.sh = H * .09; s.beads = []; s.sheenPh = rand(0, 1); s.grads = null;
		const T = []; let x = -bw * .55, i = 0;
		const add = (cx, a, fold) => T.push({
			cx, a: a + rand(-.05, .05), fold, wx: rand(.93, 1.06), off: rand(0, s.L * 2), laid: -1,
			creases: Array.from({ length: Math.random() < .5 ? 1 : 2 }, () => ({ x: rand(-.32, .32) * bw, y: rand(-.4, .2) * H, l: H * rand(.2, .5) })),
		});
		while (x < W + bw) {
			const alt = i % 2 ? -1 : 1;
			switch (s.style) {
				case 'figure8': add(x, A * s.lean * alt); x += bw * (i % 2 ? .75 : .5); break;   // crossing pairs: an X, then the next X, each turn as unhurried as a spiral's
				case 'spica': add(x, A * s.lean * alt); x += bw * .62; break;                    // alternating leans: a herringbone of Vs
				case 'reverse': add(x, A * s.lean, true); x += bw * rand(.8, .88); break;        // each turn folded back on itself
				case 'circular': add(x, 0); x += bw * rand(.84, .9); break;                       // straight round, overlapping
				default: add(x, A * s.lean); x += bw * rand(.82, .88);                           // spiral
			}
			i++;
		}
		let prev = -Infinity;
		for (const t of T) { t.ws = Math.max(t.cx - bw * .45, prev); t.we = Math.max(t.cx + bw * .15, t.ws + bw * .3); prev = t.we; }
		for (const t of T) {   // blood soaks through each laid turn, after a moment
			t.blots = [];
			const n = o.soak > 1 ? (Math.random() < .5 ? 1 : 2) : (Math.random() < .65 ? 1 : 0);
			for (let j = 0; j < n; j++) {
				const xl = rand(-.06, .06) * bw, room = (bw * .5 - Math.abs(xl)) / (o.soak > 1 ? 1.35 : 1);
				const rx = Math.min(room * 1.15, H * (o.soak > 1 ? rand(.28, .36) : rand(.2, .3)));   // the blot's soft fringe may reach the hem
				t.blots.push({ xl, yl: rand(-.18, .18) * H, rx, ry: rx * (o.soak > 1 ? rand(1.6, 2.2) : rand(1.3, 1.9)), i: Math.floor(rand(0, 4)),
					fx: pick([-1, 1]), fy: pick([-1, 1]), a: rand(.75, .95), delay: rand(.15, .9), dur: rand(1.4, 2.6) });
			}
		}
		s.turns = T;
	}

	function drawBlot(g, s, t, b, o) {
		const age = s.t - t.laid - b.delay;
		if (age <= 0) return;
		let gr = easeOut(clamp(age / b.dur));
		if (o.soak > 1) gr *= 1 + .35 * clamp((age - b.dur) / 5);   // soaked: it keeps creeping
		const rx = b.rx * gr, ry = b.ry * gr;
		g.save(); g.translate(b.xl, b.yl); g.scale(b.fx, b.fy);
		g.globalAlpha = clamp(age / .4) * b.a;
		g.drawImage(s.blots.fresh[b.i], -rx, -ry, rx * 2, ry * 2);
		if (o.dry) {   // and darkens as it dries
			g.globalAlpha *= clamp((age - b.dur * .5) / 6) * .85;
			g.drawImage(s.blots.dried[b.i], -rx, -ry, rx * 2, ry * 2);
		}
		g.restore();
	}

	function drawTurn(g, s, t, r, o) {
		const { H, bw, L } = s, k = K(), hl = L / 2, len = r * L, y0 = s.up ? hl - len : -hl;
		g.save(); g.translate(t.cx, H / 2); g.rotate(t.a); g.scale(t.wx, 1);
		g.fillStyle = s.grads.edge; g.fillRect(-bw / 2 - s.sh, y0, s.sh, len);   // its shadow on the turn before
		g.drawImage(s.band, 0, (t.off + y0 + hl) * k, bw * k, len * k, -bw / 2, y0, bw, len);
		g.save();
		if (r < 1) { g.beginPath(); g.rect(-bw / 2, y0, bw, len); g.clip(); }
		if (t.fold) {   // reverse spiral: the band folded back over itself
			const yf = (s.up ? 1 : -1) * H * .1, d = bw * .32;
			g.fillStyle = rgba(s.cl.shade, .35);
			g.beginPath(); g.moveTo(-bw / 2, yf - d); g.lineTo(bw / 2, yf + d); g.lineTo(-bw / 2, yf + d); g.closePath(); g.fill();
			g.lineWidth = Math.max(.7, H * .025);
			g.strokeStyle = rgba(mix(s.cl.shade, [0, 0, 0], .3), .6); g.beginPath(); g.moveTo(-bw / 2, yf - d); g.lineTo(bw / 2, yf + d); g.stroke();
			g.strokeStyle = 'rgba(255,255,255,.55)'; g.beginPath(); g.moveTo(-bw / 2, yf - d - H * .03); g.lineTo(bw / 2, yf + d - H * .03); g.stroke();
		}
		if (r >= 1) {
			g.lineWidth = Math.max(.5, H * .015);
			for (const c of t.creases) {   // tension creases
				g.strokeStyle = rgba(s.cl.shade, .45); g.beginPath(); g.moveTo(c.x, c.y); g.lineTo(c.x + c.l * .08, c.y + c.l); g.stroke();
				g.strokeStyle = 'rgba(255,255,255,.35)'; g.beginPath(); g.moveTo(c.x + .8, c.y); g.lineTo(c.x + .8 + c.l * .08, c.y + c.l); g.stroke();
			}
			for (const b of t.blots) drawBlot(g, s, t, b, o);
		}
		g.restore();
		if (r < 1) {   // the band's end as it comes round: a lit lip, its shadow on the wound ahead
			const ty = s.up ? y0 : y0 + len, sd = H * .07;
			const sg = g.createLinearGradient(0, ty, 0, ty + (s.up ? -sd : sd));
			sg.addColorStop(0, 'rgba(20,0,2,.55)'); sg.addColorStop(1, 'rgba(20,0,2,0)');
			g.fillStyle = sg; g.fillRect(-bw / 2, s.up ? ty - sd : ty, bw, sd);
			g.fillStyle = rgba(mix(s.cl.base, [255, 255, 255], .5), .75); g.fillRect(-bw / 2, s.up ? ty : ty - H * .03, bw, H * .03);
		}
		g.restore();
	}

	function rollState(s) {   // the turn being wound now, and how far round it is
		let lead = null, lr = 0;
		for (const t of s.turns) { const r = clamp((s.f - t.ws) / (t.we - t.ws)); if (r > 0) { lead = t; lr = r; } }
		return { lead, r: lr };
	}

	function faDraw(g, s, o) {
		const { W, H } = s, k = K();
		// the cast covers the bar plus the last turns past its end, so the wound is bound shut at 100 %
		const f = s.f = (o.channel ? W - s.fill : s.fill) * (W + s.bw * .9) / W;
		s.calm = o.calm ? 1 - s.p * .8 : 1;   // binding it slows the bleeding
		s.beat = heartbeat(s.t, o.calm ? 1.2 - s.p * .45 : 1.2) * s.calm;
		if (!s.grads) {
			const edge = g.createLinearGradient(-s.bw / 2 - s.sh, 0, -s.bw / 2, 0);
			edge.addColorStop(0, 'rgba(30,10,6,0)'); edge.addColorStop(1, 'rgba(30,10,6,.4)');
			const round = g.createLinearGradient(0, 0, 0, H);   // the limb's roundness: lit near the top, shade at both edges
			round.addColorStop(0, 'rgba(10,0,0,.16)'); round.addColorStop(.28, 'rgba(255,240,235,.06)'); round.addColorStop(.5, 'rgba(0,0,0,0)'); round.addColorStop(1, 'rgba(10,0,0,.2)');
			s.grads = { edge, round };
		}
		if (o.channel) { g.translate(W, 0); g.scale(-1, 1); }
		g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
		const x0 = Math.max(0, Math.floor(f - s.bw * 1.6));
		if (x0 < W) {   // the wound, only where it can still show
			const off = (s.t * H * .22) % H, w = W - x0;
			g.drawImage(s.wound, x0 * k, (H - off) * k, w * k, H * k, x0, 0, w, H);
			g.drawImage(s.gloss, x0 * k, 0, w * k, H * k, x0, 0, w, H);
			g.globalCompositeOperation = 'lighter'; g.fillStyle = rgba(CRIM_L, .24 * s.beat * (o.bleed || 1)); g.fillRect(x0, 0, w, H);
			g.globalCompositeOperation = 'source-over';
		}
		for (const t of s.turns) {
			const r = clamp((f - t.ws) / (t.we - t.ws));
			if (r <= 0) continue;
			if (r >= 1 && t.laid < 0) t.laid = s.t;
			drawTurn(g, s, t, r, o);
		}
		if (s.cl.sheen) {   // silk and mageweave catch a slow sheen
			const sx = ((s.t * .12 + s.sheenPh) % 1.4 - .2) * W, sg = g.createLinearGradient(sx - H, 0, sx + H, 0);
			sg.addColorStop(0, 'rgba(255,255,255,0)'); sg.addColorStop(.5, `rgba(255,255,255,${.12 * s.cl.sheen})`); sg.addColorStop(1, 'rgba(255,255,255,0)');
			g.fillStyle = sg; g.fillRect(0, 0, Math.min(W, f - s.bw * .5), H);
		}
		g.fillStyle = s.grads.round; g.fillRect(0, 0, W, H);
		g.restore();
		stepBeads(s, f, (o.bleed || 1) * s.calm * (.6 + s.beat * .6));
		const open = W - f;   // drops off the bottom of the open wound
		if (s.casting && open > 0 && Math.random() < s.dt * (open / H) * .5 * (o.bleed || 1) * s.calm * (.4 + s.beat))
			s.parts.emit({ x: rand(Math.max(0, f), W), y: H, vx: 0, vy: H * rand(.2, .5), ay: H * 9, life: rand(.45, .8), size: H * rand(.025, .045), kind: 'drop', color: pick([CRIM, CRIM_D]) });
		if (o.soak > 1 && Math.random() < s.dt * .8) {   // the soaked turns drip too
			const laid = s.turns.filter(t => t.laid >= 0 && s.t - t.laid > 1.5 && t.cx > 0 && t.cx < W);
			if (laid.length) { const t = pick(laid); s.parts.emit({ x: t.cx + rand(-.2, .2) * s.bw, y: H, vx: 0, vy: H * .3, ay: H * 9, life: .6, size: H * .03, kind: 'drop', color: CRIM_D }); }
		}
	}

	// Beads of blood swell on the wound's lower edge and fall.
	function stepBeads(s, f, rate) {
		const { W, H } = s;
		s.beads = s.beads.filter(b => b.x > f + s.bw * .2);
		if (s.casting && s.beads.length < 4 && W - f > H * .6 && Math.random() < s.dt * rate * 1.2)
			s.beads.push({ x: rand(f + s.bw * .4, W - H * .25), age: 0, life: rand(.7, 1.5), r: H * rand(.045, .07) });
		for (const b of s.beads) {
			b.age += s.dt;
			if (b.age >= b.life) {
				s.parts.emit({ x: b.x, y: H + b.r * 1.6, vx: 0, vy: H * .5, ay: H * 9, life: rand(.4, .7), size: b.r * .8, kind: 'drop', color: CRIM });
				b.age = 0; b.life = rand(.7, 1.5) / Math.max(.25, rate);
			}
		}
	}
	function drawBeads(g, s) {
		const H = s.H;
		for (const b of s.beads) {
			const t = clamp(b.age / b.life), r = b.r * (.35 + .65 * t), hang = r * (.4 + 1.3 * t * t);
			g.fillStyle = rgba(mix(CRIM, CRIM_D, .2));
			g.beginPath(); g.moveTo(b.x - r * .8, H - 1);
			g.quadraticCurveTo(b.x - r, H + hang * .5, b.x - r, H + hang); g.arc(b.x, H + hang, r, Math.PI, 0, true);
			g.quadraticCurveTo(b.x + r, H + hang * .5, b.x + r * .8, H - 1); g.closePath(); g.fill();
			g.fillStyle = 'rgba(255,200,205,.6)'; g.beginPath(); g.arc(b.x - r * .35, H + hang - r * .25, r * .22, 0, 6.283); g.fill();
		}
	}

	// B and D: the bandage roll at the end of the band as it comes round. It shrinks as the cast uses it up,
	// and squashes and fades at the bar's edges as it passes behind the limb.
	function drawRoll(g, s) {
		const { H, bw, L } = s, { lead, r } = rollState(s);
		if (!lead) return;
		const tip = s.up ? L / 2 - r * L : -L / 2 + r * L;
		const x = lead.cx - tip * Math.sin(lead.a), y = H / 2 + tip * Math.cos(lead.a);
		const v = clamp((H * .55 - Math.abs(y - H / 2)) / (H * .25)) * (s.done ? clamp(1 - s.doneT / .3) : 1);
		if (v <= 0) return;
		const d = H * (.44 - .2 * s.p) * (.7 + .3 * v), w = bw * 1.04;
		g.save(); g.translate(x, y); g.rotate(lead.a); g.globalAlpha = v;
		g.fillStyle = 'rgba(0,0,0,.35)'; g.beginPath(); g.ellipse(H * .04, d * .2, w * .55, d * .55, 0, 0, 6.283); g.fill();
		const gr = g.createLinearGradient(0, -d / 2, 0, d / 2);
		gr.addColorStop(0, rgba(mix(s.cl.base, s.cl.shade, .7))); gr.addColorStop(.3, rgba(mix(s.cl.base, [255, 255, 255], .35)));
		gr.addColorStop(.6, rgba(s.cl.base)); gr.addColorStop(1, rgba(mix(s.cl.shade, [0, 0, 0], .25)));
		roundRectPath(g, -w / 2, -d / 2, w, d, d * .12); g.fillStyle = gr; g.fill();
		g.strokeStyle = rgba(s.cl.shade, .45); g.lineWidth = Math.max(.5, H * .012);   // the wound layers, seen at each end
		for (const ex of [-w / 2, w / 2]) {
			for (let j = 1; j <= 3; j++) { g.beginPath(); g.ellipse(ex, 0, d * .1 * j / 3, d * .5 * j / 3.2, 0, 0, 6.283); g.stroke(); }
		}
		g.strokeStyle = 'rgba(255,255,255,.4)'; g.beginPath(); g.moveTo(-w * .4, -d * .22); g.lineTo(w * .4, -d * .22); g.stroke();
		g.restore();
	}

	function faOver(g, s, o) {
		if (o.channel) { g.translate(s.W, 0); g.scale(-1, 1); }
		drawBeads(g, s);
		s.parts.update(s.dt); s.parts.draw(g);
		if (o.roll) {   // the roll is clipped to the bar, like the loom: no bandage shows past the bar's lines
			g.save(); roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip();
			drawRoll(g, s);
			g.restore();
		}
	}

	const VARIANTS = [
		{ id: 'fa-a', letter: 'A', name: 'Wrapped turns', soak: 1,
			desc: 'An open crimson wound, its blood running and pulsing with a heartbeat, beads swelling and dripping off the bottom; bandage turns wrap round it at the cast edge and blood seeps through each one after it is laid. Every cast changes the wrap (spiral, figure-eight, reverse spiral with folds, spica herringbone, circular), the lean, which way the turns come round, and the cloth' },
		{ id: 'fa-b', letter: 'B', name: 'Bandage roll', soak: 1, roll: true,
			desc: 'A with the bandage roll riding the end of the band as it comes round, passing behind the limb at the edges and back again for the next turn; the roll shrinks as the cast uses it up and is clipped to the bar, so no bandage shows past its lines' },
		{ id: 'fa-c', letter: 'C', name: 'Soaked through', soak: 2, dry: true, calm: true, bleed: 1.4, roll: true,
			desc: 'B bleeding harder: bigger blots that keep creeping through the gauze and dry darker, soaked turns that drip; the heartbeat slows and the bleeding eases as more of the wound is bound' },
		{ id: 'fa-d', letter: 'D', name: 'Applying a bandage (channel)', soak: 1, calm: true, roll: true, channel: true, dur: [5.5, 6.5],
			desc: 'Using a bandage is a channel, so the wrapping comes in from the right as the channel drains (like frost\'s channels); the bleeding slows and stops as it binds' },
	];
	for (const o of VARIANTS) {
		const c = {
			group: 'First Aid', id: o.id, letter: o.letter, name: o.name, desc: o.desc, spell: 'Heavy Linen Bandage',
			channel: o.channel, dur: o.dur, padTop: .8, padBottom: 1.5, padX: .9, flash: [255, 214, 214], flashAlpha: .3, frame: [178, 28, 40],
			init(s) { faInit(s, o); c.spell = (o.channel ? 'First Aid' : s.cl.spell.replace('Heavy ', '')) + ' · ' + STYLE_NAMES[s.style]; },
			draw(g, s) { faDraw(g, s, o); },
			over(g, s) { faOver(g, s, o); },
		};
		CONCEPTS.push(c);
	}
})();
