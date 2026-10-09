// Leatherworking concepts: leather stitched together as the cast goes on.
// Same painterly style as the approved looks (skinning C2, blacksmithing A): no hard outlines, soft
// shading and glints, tools in front of the bar drawn in over(), and no leading-edge marker — the
// stitching itself shows the progress.
(() => {
	const TONES = [
		{ base: [198, 150, 98], dark: [150, 104, 62] },    // light leather
		{ base: [158, 104, 62], dark: [112, 70, 38] },     // medium
		{ base: [118, 74, 42], dark: [78, 46, 24] },       // heavy
		{ base: [96, 60, 36], dark: [60, 36, 20] },        // thick
		{ base: [132, 96, 60], dark: [88, 62, 36] },       // rugged
	];
	const THREADS = [[236, 224, 188], [48, 38, 30], [156, 46, 34], [214, 168, 92], [226, 226, 222]];
	const smooth01 = t => { t = clamp(t); return t * t * (3 - 2 * t); };
	const K = () => (typeof dpr === 'number' ? dpr : 1);
	function mkCanvas(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }

	// Tanned hide painted once per cast: soft mottling, fine crinkled grain, pores, a few pale scuffs.
	function makeLeather(w, h, H, tone) {
		const k = K(), cv = mkCanvas(w * k, h * k), g = cv.getContext('2d');
		g.scale(k, k);
		const bg = g.createLinearGradient(0, 0, 0, h);
		bg.addColorStop(0, rgba(mix(tone.base, [255, 236, 210], .1))); bg.addColorStop(.55, rgba(tone.base)); bg.addColorStop(1, rgba(mix(tone.base, tone.dark, .6)));
		g.fillStyle = bg; g.fillRect(0, 0, w, h);
		const area = w * h / (H * H);
		for (let i = 0; i < area * 5; i++) {
			const x = rand(0, w), y = rand(0, h), r = H * rand(.2, .7), dark = Math.random() < .6;
			const gr = g.createRadialGradient(x, y, 0, x, y, r);
			gr.addColorStop(0, dark ? rgba(tone.dark, .22) : 'rgba(255,236,210,.1)'); gr.addColorStop(1, dark ? rgba(tone.dark, 0) : 'rgba(255,236,210,0)');
			g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
		}
		g.lineCap = 'round';
		for (let i = 0; i < area * 150; i++) {   // grain: short crinkles, mostly along the hide
			const x = rand(0, w), y = rand(0, h), a = rand(-.6, .6) + (Math.random() < .25 ? 1.57 : 0), l = H * rand(.025, .07);
			g.strokeStyle = rgba(tone.dark, rand(.12, .26)); g.lineWidth = Math.max(.4, H * .01);
			g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
		}
		for (let i = 0; i < area * 90; i++) {   // pores
			g.fillStyle = rgba(mix(tone.dark, [20, 10, 4], .4), rand(.2, .4));
			g.beginPath(); g.arc(rand(0, w), rand(0, h), H * rand(.005, .013), 0, 6.283); g.fill();
		}
		for (let i = 0; i < area * 40; i++) {   // light flecks
			g.fillStyle = `rgba(255,238,214,${rand(.05, .12)})`;
			g.beginPath(); g.arc(rand(0, w), rand(0, h), H * rand(.006, .015), 0, 6.283); g.fill();
		}
		for (let i = 0; i < Math.max(2, w / H * .6); i++) {   // scuffs
			const x = rand(0, w), y = rand(0, h), l = H * rand(.3, .8), a = rand(-.4, .4);
			g.strokeStyle = `rgba(255,232,200,${rand(.08, .16)})`; g.lineWidth = H * rand(.01, .025);
			g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + Math.cos(a) * l * .5, y + rand(-.08, .08) * H, x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
		}
		return cv;
	}

	// A waxed thread or thong: soft shadow, body, highlight along its top.
	function strokeThread(g, build, col, w) {
		g.lineCap = 'round'; g.lineJoin = 'round';
		g.save(); g.translate(0, w * .45); g.strokeStyle = 'rgba(0,0,0,.42)'; g.lineWidth = w * 1.35; build(); g.stroke(); g.restore();
		g.strokeStyle = rgba(col); g.lineWidth = w; build(); g.stroke();
		g.save(); g.translate(-w * .12, -w * .22); g.strokeStyle = rgba(mix(col, [255, 255, 255], .5), .55); g.lineWidth = w * .32; build(); g.stroke(); g.restore();
	}
	// A punched hole: dark centre, a faint lit lip on its lower side.
	function hole(g, x, y, r) {
		g.fillStyle = 'rgba(22,10,4,.85)'; g.beginPath(); g.ellipse(x, y, r, r * .9, 0, 0, 6.283); g.fill();
		g.strokeStyle = 'rgba(255,226,190,.22)'; g.lineWidth = Math.max(.5, r * .45);
		g.beginPath(); g.arc(x, y + r * .15, r * 1.05, .3, 2.84); g.stroke();
	}
	// A steel needle from its eye (ex, ey) to its tip (tx, ty).
	function drawNeedle(g, ex, ey, tx, ty, H, alpha = 1) {
		const L = Math.hypot(tx - ex, ty - ey), a = Math.atan2(ty - ey, tx - ex), w = Math.max(1.3, H * .055);
		g.save(); g.globalAlpha *= alpha; g.translate(ex, ey); g.rotate(a);
		const body = new Path2D();
		body.moveTo(0, -w / 2); body.lineTo(L * .82, -w * .36); body.lineTo(L, 0); body.lineTo(L * .82, w * .36); body.lineTo(0, w / 2);
		body.arc(0, 0, w / 2, Math.PI / 2, -Math.PI / 2); body.closePath();
		g.save(); g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = H * .1; g.shadowOffsetY = H * .04; g.fillStyle = '#777'; g.fill(body); g.restore();
		const gr = g.createLinearGradient(0, -w / 2, 0, w / 2);
		gr.addColorStop(0, '#eef0f4'); gr.addColorStop(.45, '#a4a8b0'); gr.addColorStop(1, '#4c4f57');
		g.fillStyle = gr; g.fill(body);
		g.fillStyle = 'rgba(20,20,24,.9)'; g.beginPath(); g.ellipse(w * 1.5, 0, w * .95, w * .2, 0, 0, 6.283); g.fill();   // the eye
		g.strokeStyle = 'rgba(255,255,255,.7)'; g.lineWidth = Math.max(.5, w * .18);
		g.beginPath(); g.moveTo(L * .25, -w * .28); g.lineTo(L * .62, -w * .2); g.stroke();
		g.restore();
	}
	// An awl: pear-shaped wooden handle on top, a steel spike down to its tip at (x, y).
	function drawAwl(g, x, y, H, alpha = 1) {
		const sl = H * .5, hl = H * .42, hw = H * .2;
		g.save(); g.globalAlpha *= alpha;
		g.save(); g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = H * .1; g.shadowOffsetX = H * .04;
		const sg = g.createLinearGradient(x - H * .03, 0, x + H * .03, 0);
		sg.addColorStop(0, '#f0f2f6'); sg.addColorStop(.5, '#9ea2aa'); sg.addColorStop(1, '#55585f');
		g.fillStyle = sg; g.beginPath(); g.moveTo(x, y); g.lineTo(x - H * .028, y - sl); g.lineTo(x + H * .028, y - sl); g.closePath(); g.fill();
		g.restore();
		const fy = y - sl;   // brass ferrule
		const fg = g.createLinearGradient(x - hw * .3, 0, x + hw * .3, 0);
		fg.addColorStop(0, '#f6dc94'); fg.addColorStop(.5, '#b88a36'); fg.addColorStop(1, '#6e4e1a');
		g.fillStyle = fg; g.fillRect(x - hw * .3, fy - H * .07, hw * .6, H * .07);
		const hy = fy - H * .07;   // handle
		const hg = g.createLinearGradient(x - hw / 2, 0, x + hw / 2, 0);
		hg.addColorStop(0, '#c48a52'); hg.addColorStop(.45, '#8e5a2c'); hg.addColorStop(1, '#4a2c12');
		g.fillStyle = hg;
		g.beginPath(); g.moveTo(x - hw * .3, hy);
		g.bezierCurveTo(x - hw * .7, hy - hl * .3, x - hw * .55, hy - hl, x, hy - hl);
		g.bezierCurveTo(x + hw * .55, hy - hl, x + hw * .7, hy - hl * .3, x + hw * .3, hy); g.closePath(); g.fill();
		g.strokeStyle = 'rgba(255,230,190,.35)'; g.lineWidth = Math.max(.6, H * .02);
		g.beginPath(); g.moveTo(x - hw * .3, hy - hl * .25); g.quadraticCurveTo(x - hw * .45, hy - hl * .7, x - hw * .1, hy - hl * .9); g.stroke();
		g.restore();
	}
	function clipBar(g, s) { roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip(); }

	// ------------------------------------------------------------------ A: saddle-stitched seam
	CONCEPTS.push({
		group: 'Leatherworking', id: 'lw-a', letter: 'A', name: 'Saddle-stitched seam',
		desc: 'Two halves of tanned leather are drawn together and saddle-stitched shut behind a needle and waxed thread; holes stay punched along the open seam ahead',
		spell: 'Light Leather', padTop: 1.3, padBottom: .7, padX: .9, flash: [255, 220, 170],
		init(s) {
			const { W, H } = s;
			s.tone = pick(TONES); s.thread = pick(THREADS); s.lea = makeLeather(W, H, H, s.tone);
			s.sp = H * rand(.19, .23); s.ph = rand(0, 6.283);
		},
		draw(g, s) {
			const { W, H, fill } = s, k = K(), gapMax = H * .15, sp = s.sp;
			const gap = x => gapMax * smooth01((x - (fill - H * .35)) / (H * .9));
			s.gap = gap;
			g.save(); clipBar(g, s);
			g.fillStyle = 'rgba(12,7,4,.96)'; g.fillRect(0, H * .3, W, H * .4);   // the open seam
			const st = 2;
			for (let x = 0; x < W; x += st) {
				const sw = Math.min(st, W - x), gy = gap(x + sw / 2) / 2;
				g.drawImage(s.lea, x * k, 0, sw * k, (H / 2) * k, x, -gy, sw + .6, H / 2);
				g.drawImage(s.lea, x * k, (H / 2) * k, sw * k, (H / 2) * k, x, H / 2 + gy, sw + .6, H / 2);
			}
			// burnished cut edges along the seam, darker where they meet
			for (const side of [-1, 1]) {
				g.beginPath();
				for (let x = 0; x <= W; x += 3) { const y = H / 2 + side * (gap(x) / 2 + H * .018); x ? g.lineTo(x, y) : g.moveTo(x, y); }
				g.strokeStyle = 'rgba(40,20,8,.6)'; g.lineWidth = H * .04; g.stroke();
				g.beginPath();
				for (let x = 0; x <= W; x += 3) { const y = H / 2 + side * (gap(x) / 2 + H * .05); x ? g.lineTo(x, y) : g.moveTo(x, y); }
				g.strokeStyle = 'rgba(255,230,196,.12)'; g.lineWidth = Math.max(.6, H * .015); g.stroke();
			}
			// soft top light over the whole hide
			const sh = g.createLinearGradient(0, 0, 0, H);
			sh.addColorStop(0, 'rgba(255,240,220,.1)'); sh.addColorStop(.3, 'rgba(255,240,220,0)'); sh.addColorStop(1, 'rgba(0,0,0,.18)');
			g.fillStyle = sh; g.fillRect(0, 0, W, H);
			// holes on both edges; stitches run diagonally from a top hole to the next bottom hole
			const top = x => H / 2 - gap(x) / 2 - H * .11, bot = x => H / 2 + gap(x) / 2 + H * .11, r = Math.max(.8, H * .028);
			const front = fill - H * .3;
			s.next = null;
			for (let i = 0; ; i++) {
				const x = sp * (i + .5);
				if (x > W) break;
				hole(g, x, top(x), r); hole(g, x, bot(x), r);
			}
			for (let i = 0; ; i++) {
				const x0 = sp * (i + .5), x1 = x0 + sp;
				if (x1 > W) break;
				if (x1 < front) {
					strokeThread(g, () => { g.beginPath(); g.moveTo(x0, top(x0)); g.lineTo(x1, bot(x1)); }, s.thread, Math.max(1, H * .045));
				} else { if (!s.next) s.next = { x0, x1 }; }
			}
			if (!s.next) { const x0 = sp * (Math.floor(W / sp) - .5); s.next = { x0, x1: x0 + sp }; }
			s.top = top; s.bot = bot;
			g.restore();
		},
		over(g, s) {
			if (!s.next || !s.top) return;
			const { H, t } = s, lift = s.done ? easeIn(clamp(s.doneT / .4)) : 0;
			const n = s.next, tx0 = n.x0, ty0 = s.top(tx0), tx1 = n.x1, ty1 = s.bot(tx1);
			const dx = tx1 - tx0, dy = ty1 - ty0, d = Math.hypot(dx, dy), ux = dx / d, uy = dy / d;
			const u = s.casting ? .5 + .5 * Math.sin(t * 7 + s.ph) : 0;
			const tipX = tx0 + ux * lerp(-.3, .7, u) * d, tipY = ty0 + uy * lerp(-.3, .7, u) * d - lift * H;
			const len = H * 1.0, ex = tipX - ux * len, ey = tipY - uy * len;
			// the thread from the last stitch, slack while the needle goes in, taut as it pulls out
			const sx = tx0, sy = s.bot(tx0);
			const cx = (sx + ex) / 2, cy = Math.max(sy, ey) + H * .35 * u;
			g.save(); g.globalAlpha = 1 - lift;
			strokeThread(g, () => { g.beginPath(); g.moveTo(sx, sy); g.quadraticCurveTo(cx, cy, ex + ux * H * .08, ey + uy * H * .08); }, s.thread, Math.max(1, H * .045));
			strokeThread(g, () => { g.beginPath(); g.moveTo(ex + ux * H * .08, ey + uy * H * .08); g.quadraticCurveTo(ex - H * .15, ey - H * .05, ex - H * .25, ey + H * .12); }, s.thread, Math.max(1, H * .04));
			g.restore();
			drawNeedle(g, ex, ey, tipX, tipY, H, 1 - lift);
		},
	});

	// ------------------------------------------------------------------ tooled patterns for B's panels
	// Pressed into the leather, not drawn on it: a dark impression with a faintly lit lip below and to
	// the right of it. One pattern per cast, in turn. Each takes the panel's inset rect (x0..x1, y0..y1).
	function emboss(g, build, H, depth = 1) {
		g.lineCap = 'round'; g.lineJoin = 'round';
		g.save(); g.translate(H * .014, H * .02); g.strokeStyle = `rgba(255,228,192,${.28 * depth})`; build(); g.stroke(); g.restore();
		g.save(); g.translate(-H * .006, -H * .008); g.strokeStyle = `rgba(26,11,4,${.55 * depth})`; build(); g.stroke(); g.restore();
	}
	function embossFill(g, build, H, depth = 1) {
		g.save(); g.translate(H * .014, H * .02); g.fillStyle = `rgba(255,228,192,${.3 * depth})`; build(); g.fill(); g.restore();
		g.fillStyle = `rgba(26,11,4,${.6 * depth})`; build(); g.fill();
	}
	const TOOLING = [
		{ name: 'basket-weave', draw(g, x0, x1, y0, y1, H) {   // cells of three bars, turned in turn
			const cw = H * .24, cols = Math.floor((x1 - x0) / cw), rows = Math.floor((y1 - y0) / cw);
			if (cols < 1 || rows < 1) return;
			const ox = x0 + ((x1 - x0) - cols * cw) / 2, oy = y0 + ((y1 - y0) - rows * cw) / 2;
			for (let c = 0; c < cols; c++) for (let r = 0; r < rows; r++) {
				const cx = ox + c * cw, cy = oy + r * cw, vert = (c + r) % 2 === 1;
				for (let b = 0; b < 3; b++) {
					const along = cw * .78, thick = cw * .16, o = (b - 1) * cw * .27;
					const x = vert ? cx + cw / 2 + o - thick / 2 : cx + cw * .11, y = vert ? cy + cw * .11 : cy + cw / 2 + o - thick / 2;
					embossFill(g, () => roundRectPath(g, x, y, vert ? thick : along, vert ? along : thick, thick * .45), H, .9);
				}
			}
		} },
		{ name: 'scrolling vine', draw(g, x0, x1, y0, y1, H) {   // a winding stem with curls and leaves
			const mid = (y0 + y1) / 2, amp = (y1 - y0) * .22, wl = H * .9, w = x1 - x0;
			g.lineWidth = Math.max(1, H * .04);
			emboss(g, () => {
				g.beginPath();
				for (let x = x0; x <= x1; x += 2) { const y = mid + amp * Math.sin((x - x0) / wl * 6.283); x === x0 ? g.moveTo(x, y) : g.lineTo(x, y); }
			}, H);
			let up = true;
			for (let x = x0 + H * .35; x < x1 - H * .3; x += H * .72) {
				const y = mid + amp * Math.sin((x - x0) / wl * 6.283), sg = up ? -1 : 1;
				g.lineWidth = Math.max(.8, H * .03);
				emboss(g, () => {   // a curl off the stem
					g.beginPath(); g.moveTo(x, y);
					g.bezierCurveTo(x + H * .12, y + sg * H * .18, x + H * .3, y + sg * H * .2, x + H * .26, y + sg * H * .06);
					g.bezierCurveTo(x + H * .22, y + sg * H * -.02, x + H * .16, y + sg * H * .04, x + H * .19, y + sg * H * .1);
				}, H, .85);
				const lx = x + H * .36, ly = mid + amp * Math.sin((lx - x0) / wl * 6.283);   // a leaf the other way
				emboss(g, () => {
					g.beginPath(); g.moveTo(lx, ly);
					g.quadraticCurveTo(lx + H * .06, ly - sg * H * .22, lx + H * .2, ly - sg * H * .26);
					g.quadraticCurveTo(lx + H * .14, ly - sg * H * .08, lx, ly); g.closePath();
					g.moveTo(lx + H * .03, ly - sg * H * .04); g.lineTo(lx + H * .16, ly - sg * H * .2);
				}, H, .85);
				up = !up;
			}
		} },
		{ name: 'diamond lattice', draw(g, x0, x1, y0, y1, H) {   // crossed grooves, a dot in each diamond
			const sp = H * .3, h = y1 - y0, w = x1 - x0;
			g.lineWidth = Math.max(.8, H * .028);
			emboss(g, () => {
				g.beginPath();
				for (let x = x0 - h; x < x1 + h; x += sp) { g.moveTo(x, y0); g.lineTo(x + h, y1); g.moveTo(x + h, y0); g.lineTo(x, y1); }
			}, H, .8);
			const ox = x0 + ((w % sp) / 2);
			for (let x = ox + sp / 2; x < x1; x += sp) for (let y = y0 + h / 2 - sp * Math.floor(h / (2 * sp)); y <= y1; y += sp) {
				if (y <= y0 || y >= y1) continue;
				embossFill(g, () => { g.beginPath(); g.arc(x, y, H * .028, 0, 6.283); }, H, .9);
			}
		} },
		{ name: 'bordered shells', draw(g, x0, x1, y0, y1, H) {   // beveled border grooves and a row of fan stamps
			g.lineWidth = Math.max(.8, H * .03);
			emboss(g, () => { g.beginPath(); g.moveTo(x0, y0 + H * .05); g.lineTo(x1, y0 + H * .05); g.moveTo(x0, y1 - H * .05); g.lineTo(x1, y1 - H * .05); }, H);
			const sp = H * .34, R = H * .15, cy = (y0 + y1) / 2, n = Math.floor((x1 - x0 - H * .1) / sp), ox = x0 + ((x1 - x0) - n * sp) / 2;
			for (let i = 0; i < n; i++) {
				const cx = ox + (i + .5) * sp, up = i % 2 === 0, base = cy + (up ? R * .5 : -R * .5), sg = up ? -1 : 1;
				g.lineWidth = Math.max(.7, H * .025);
				emboss(g, () => {
					g.beginPath(); g.arc(cx, base, R, up ? Math.PI : 0, up ? 0 : Math.PI); g.closePath();
					for (let k = 1; k < 4; k++) { const a = Math.PI * (k / 4); g.moveTo(cx, base); g.lineTo(cx + Math.cos(a) * R * .85, base + sg * Math.sin(a) * R * .85); }
				}, H, .9);
			}
		} },
		{ name: 'knotwork band', draw(g, x0, x1, y0, y1, H) {   // two strands crossing back and forth
			const mid = (y0 + y1) / 2, A = (y1 - y0) * .3, k = H * .3;
			g.lineWidth = Math.max(1.2, H * .05);
			for (const sg of [1, -1]) emboss(g, () => {
				g.beginPath();
				for (let x = x0; x <= x1; x += 2) { const y = mid + sg * A * Math.sin((x - x0) / k); x === x0 ? g.moveTo(x, y) : g.lineTo(x, y); }
			}, H);
			g.lineWidth = Math.max(.6, H * .02);   // the over-strand's edges where they cross
			emboss(g, () => {
				g.beginPath();
				for (let x = x0; x <= x1; x += Math.PI * k) { g.moveTo(x, mid - A * .18); g.lineTo(x, mid + A * .18); }
			}, H, .6);
		} },
	];
	let toolingTurn = Math.floor(Math.random() * TOOLING.length);
	{ const q = new URLSearchParams(location.search); if (q.has('tooling')) toolingTurn = +q.get('tooling'); }   // ?tooling=0..4 to start from one
	const nextTooling = () => TOOLING[toolingTurn++ % TOOLING.length];

	// ------------------------------------------------------------------ B: panels laced edge to edge
	CONCEPTS.push({
		group: 'Leatherworking', id: 'lw-b', letter: 'B', name: 'Laced panels',
		desc: 'Separate tooled leather panels lie apart with their lacing holes already punched; at each joint a needle cross-laces them shut with a thong; edge stitching runs along behind. The tooling changes each cast: basket-weave, scrolling vine, diamond lattice, bordered shells, knotwork band',
		spell: 'Heavy Leather Ball', padTop: 1.3, padBottom: .7, padX: .9, flash: [255, 215, 160],
		init(s) {
			const { W, H } = s;
			s.tone = pick(TONES); s.lea = makeLeather(W, H, H, s.tone);
			s.thong = pick([[60, 36, 20], [30, 24, 20], [176, 120, 70]]); s.thread = pick(THREADS);
			s.joints = [];
			for (let x = H * rand(1.3, 2); x < W - H * .9; x += H * rand(1.8, 3)) s.joints.push(x);
			s.tints = [];
			for (let i = 0; i <= s.joints.length; i++) s.tints.push(rand(-.14, .12));
			s.rows = H >= 34 ? 5 : 4;
			s.tooling = nextTooling();
		},
		draw(g, s) {
			const { W, H, fill } = s, k = K(), J = s.joints, rows = s.rows;
			const ys = []; for (let r = 0; r < rows; r++) ys.push(H * (.18 + .64 * r / (rows - 1)));
			const lp = j => clamp((fill - J[j]) / (H * .9)), pp = j => clamp((fill - (J[j] - H * .75)) / (H * .65));
			const openG = j => H * .14 * (1 - easeOut(lp(j)));
			g.save(); clipBar(g, s);
			g.fillStyle = 'rgba(12,7,4,.96)'; g.fillRect(0, 0, W, H);
			// panels, each shifted right by the gaps still open before it
			let off = 0;
			const offs = [];
			for (let p = 0; p <= J.length; p++) {
				const a = p ? J[p - 1] : 0, b = p < J.length ? J[p] : W;
				offs.push(off);
				g.drawImage(s.lea, a * k, 0, (b - a) * k, H * k, a + off, 0, b - a, H);
				const v = s.tints[p];
				g.fillStyle = v > 0 ? `rgba(255,238,214,${v})` : `rgba(30,14,4,${-v})`; g.fillRect(a + off, 0, b - a, H);
				// the panel's tooling, kept clear of the lacing holes at its ends and the edge stitching
				const ix0 = a + off + (p ? H * .24 : H * .18), ix1 = b + off - (p < J.length ? H * .24 : H * .18);
				if (ix1 - ix0 > H * .4) {
					g.save(); g.beginPath(); g.rect(ix0, H * .15, ix1 - ix0, H * .7); g.clip();
					s.tooling.draw(g, ix0, ix1, H * .15, H * .85, H);
					g.restore();
				}
				for (const [ex, dir] of [[a + off, 1], [b + off, -1]]) {   // burnished panel edges
					if ((dir === 1 && p === 0) || (dir === -1 && p === J.length)) continue;
					const eg = g.createLinearGradient(ex, 0, ex + dir * H * .08, 0);
					eg.addColorStop(0, 'rgba(36,18,6,.7)'); eg.addColorStop(1, 'rgba(36,18,6,0)');
					g.fillStyle = eg; g.fillRect(Math.min(ex, ex + dir * H * .08), 0, H * .08, H);
				}
				if (p < J.length) off += openG(p);
			}
			const sh = g.createLinearGradient(0, 0, 0, H);
			sh.addColorStop(0, 'rgba(255,240,220,.1)'); sh.addColorStop(.3, 'rgba(255,240,220,0)'); sh.addColorStop(1, 'rgba(0,0,0,.18)');
			g.fillStyle = sh; g.fillRect(0, 0, W, H);
			// running stitches along both long edges, behind the work
			let done = fill - H * .2;
			for (let j = 0; j < J.length; j++) if (lp(j) < 1) { done = Math.min(done, J[j] + offs[j]); break; }
			const sp = H * .2, r = Math.max(.7, H * .022);
			for (const y of [H * .07, H * .93]) {
				for (let x = sp * .5; x + sp * .55 < done; x += sp) strokeThread(g, () => { g.beginPath(); g.moveTo(x, y); g.lineTo(x + sp * .55, y); }, s.thread, Math.max(.8, H * .035));
			}
			// joints: the holes are already punched; the needle cross-laces them shut as the cast reaches each
			s.tool = null;
			for (let j = 0; j < J.length; j++) {
				const L = J[j] + offs[j], R = L + openG(j), xl = L - H * .1, xr = R + H * .1;
				for (let h = 0; h < rows * 2; h++) hole(g, h % 2 ? xr : xl, ys[Math.floor(h / 2)], Math.max(.9, H * .03));
				const segs = [];
				for (let rr = 0; rr < rows - 1; rr++) { segs.push([xl, ys[rr], xr, ys[rr + 1]]); segs.push([xr, ys[rr], xl, ys[rr + 1]]); }
				const n = lp(j) * segs.length, w = Math.max(1.4, H * .06);
				for (let q = 0; q < Math.min(segs.length, Math.ceil(n)); q++) {
					const [x1, y1, x2, y2] = segs[q], f = Math.min(1, n - q);
					strokeThread(g, () => { g.beginPath(); g.moveTo(x1, y1); g.lineTo(lerp(x1, x2, f), lerp(y1, y2, f)); }, s.thong, w);
					if (f < 1) s.tool = { kind: 'needle', x: lerp(x1, x2, f), y: lerp(y1, y2, f), dx: x2 - x1, dy: y2 - y1 };
				}
			}
			g.restore();
		},
		over(g, s) {
			const T = s.tool, H = s.H;
			if (!T || s.done) return;
			const d = Math.hypot(T.dx, T.dy) || 1, ux = T.dx / d, uy = T.dy / d, len = H * .5;
			drawNeedle(g, T.x - ux * H * .08, T.y - uy * H * .08, T.x - ux * H * .08 + ux * len, T.y - uy * H * .08 + uy * len, H);
		},
	});

	// ------------------------------------------------------------------ C: tooled and stitched strap
	CONCEPTS.push({
		group: 'Leatherworking', id: 'lw-c', letter: 'C', name: 'Tooled strap',
		desc: 'A strap of veg-tan leather: a mallet drives a stamp along it, leaving an antiqued basket-weave behind, and the stitching groove fills with stitches',
		spell: 'Rugged Leather Pants', padTop: 1.9, padBottom: .7, padX: .9, flash: [255, 220, 170],
		init(s) {
			const { W, H } = s;
			s.tone = pick([TONES[0], TONES[1], TONES[4]]); s.lea = makeLeather(W, H, H, s.tone);
			s.thread = pick(THREADS); s.cw = H * .38; s.y0 = H * .12; s.ph = rand(0, 1);
			s.stampAge = {};
		},
		draw(g, s) {
			const { W, H, fill, cw } = s, k = K();
			g.save(); clipBar(g, s);
			g.drawImage(s.lea, 0, 0, W * k, H * k, 0, 0, W, H);
			// antique finish behind the work: the dye darkens the stamped part
			if (fill > 0) {
				const ag = g.createLinearGradient(Math.max(0, fill - H * .6), 0, fill, 0);
				ag.addColorStop(0, 'rgba(60,30,10,.22)'); ag.addColorStop(1, 'rgba(60,30,10,0)');
				g.fillStyle = 'rgba(60,30,10,.22)'; g.fillRect(0, 0, Math.max(0, fill - H * .6), H);
				g.fillStyle = ag; g.fillRect(Math.max(0, fill - H * .6), 0, Math.min(fill, H * .6), H);
			}
			// basket-weave: two rows of cells, three bars each, turned alternately
			for (let c = 0; ; c++) {
				const cx = H * .15 + c * cw;
				if (cx + cw > W - H * .1) break;
				for (let row = 0; row < 2; row++) {
					const key = c * 2 + row, stamped = cx + cw * (row ? .9 : .5) < fill - H * .1;
					if (!stamped) continue;
					if (s.stampAge[key] === undefined) s.stampAge[key] = s.t;
					const fresh = clamp((s.t - s.stampAge[key]) / .25), cy = s.y0 + row * cw;
					const vert = (c + row) % 2 === 1;
					for (let b = 0; b < 3; b++) {
						const along = cw * .8, thick = cw * .17, o = (b - 1) * cw * .27;
						const x = vert ? cx + cw / 2 + o - thick / 2 : cx + cw * .1, y = vert ? cy + cw * .1 : cy + cw / 2 + o - thick / 2;
						const w = vert ? thick : along, h = vert ? along : thick;
						g.fillStyle = `rgba(30,13,4,${.78 * fresh})`; roundRectPath(g, x, y, w, h, thick * .45); g.fill();
						g.fillStyle = `rgba(255,226,190,${.3 * fresh})`; roundRectPath(g, x, y + h - Math.max(.6, thick * .22), w, Math.max(.6, thick * .22), thick * .2); g.fill();
					}
				}
			}
			// the stitching groove along both edges, scribed ahead and stitched behind
			const sp = H * .18;
			for (const y of [H * .07, H * .93]) {
				g.strokeStyle = 'rgba(40,20,8,.45)'; g.lineWidth = Math.max(.6, H * .02);
				g.beginPath(); g.moveTo(H * .1, y); g.lineTo(W - H * .1, y); g.stroke();
				for (let x = H * .12; x + sp * .6 < fill - H * .15; x += sp) strokeThread(g, () => { g.beginPath(); g.moveTo(x, y); g.lineTo(x + sp * .6, y); }, s.thread, Math.max(.8, H * .035));
			}
			const sh = g.createLinearGradient(0, 0, 0, H);
			sh.addColorStop(0, 'rgba(255,240,220,.12)'); sh.addColorStop(.3, 'rgba(255,240,220,0)'); sh.addColorStop(1, 'rgba(0,0,0,.18)');
			g.fillStyle = sh; g.fillRect(0, 0, W, H);
			// strikes throw a little leather dust
			const P = .34, phase = (s.t / P + s.ph) % 1;
			if (s.casting && s.lastPhase !== undefined && phase < s.lastPhase && fill > H * .3) {
				for (let i = 0; i < 6; i++) s.parts.emit({ x: fill - H * .05, y: H * .5, vx: rand(-1, 1) * H, vy: rand(-1.6, -.4) * H, ay: H * 4, life: rand(.3, .6), size: H * rand(.015, .03), color: mix(s.tone.base, [255, 230, 200], .3), alpha: .8 });
			}
			s.lastPhase = phase;
			s.parts.update(s.dt); s.parts.draw(g);
			g.restore();
		},
		over(g, s) {
			const { H, t, fill } = s;
			if (fill <= 0 && !s.casting) return;
			const lift = s.done ? easeIn(clamp(s.doneT / .4)) : 0, alpha = 1 - lift;
			const P = .34, phase = s.casting ? (t / P + s.ph) % 1 : 0;
			// the stamp: stands on the leather at the cast edge, pushed down a touch on each blow
			const press = phase < .12 ? (1 - phase / .12) * H * .05 : 0;
			const x = Math.max(H * .2, fill - H * .05), base = H * .5 + press - lift * H, top = base - H * .95, w = H * .13;
			g.save(); g.globalAlpha = alpha;
			g.save(); g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = H * .12; g.shadowOffsetX = H * .05;
			const sg = g.createLinearGradient(x - w / 2, 0, x + w / 2, 0);
			sg.addColorStop(0, '#e8eaee'); sg.addColorStop(.4, '#a2a6ae'); sg.addColorStop(1, '#4d5058');
			g.fillStyle = sg; roundRectPath(g, x - w / 2, top, w, base - top, w * .2); g.fill();
			g.restore();
			g.strokeStyle = 'rgba(30,30,36,.35)'; g.lineWidth = Math.max(.5, H * .012);   // knurled grip
			for (let y = top + H * .25; y < top + H * .6; y += H * .045) { g.beginPath(); g.moveTo(x - w / 2, y); g.lineTo(x + w / 2, y + H * .02); g.stroke(); }
			g.strokeStyle = 'rgba(255,255,255,.55)'; g.lineWidth = Math.max(.5, w * .15);
			g.beginPath(); g.moveTo(x - w * .25, top + H * .05); g.lineTo(x - w * .25, base - H * .1); g.stroke();
			// the maul: raised, then a fast blow onto the stamp's head with a small bounce
			let up;
			if (phase < .08) up = phase / .08 * .12;
			else if (phase < .7) up = .12 + .88 * easeOut((phase - .08) / .62);
			else up = 1 - easeIn((phase - .7) / .3);
			if (!s.casting) up = 1;
			const hx = x + H * .05, hy = top - H * .02 - up * H * .7 - lift * H * .5, hw = H * .5, hh = H * .3;
			g.save(); g.shadowColor = 'rgba(0,0,0,.45)'; g.shadowBlur = H * .12; g.shadowOffsetY = H * .04;
			const handle = g.createLinearGradient(0, hy - H * .1, 0, hy + H * .02);
			handle.addColorStop(0, '#b47a44'); handle.addColorStop(1, '#5a3416');
			g.strokeStyle = handle; g.lineWidth = H * .085; g.lineCap = 'round';
			g.beginPath(); g.moveTo(hx, hy - hh * .5); g.lineTo(hx + H * .85, hy - hh * .5 - H * .45); g.stroke();
			const mg = g.createLinearGradient(0, hy - hh, 0, hy);
			mg.addColorStop(0, '#efe4cc'); mg.addColorStop(.5, '#c9b691'); mg.addColorStop(1, '#7c6a4a');
			g.fillStyle = mg; roundRectPath(g, hx - hw / 2, hy - hh, hw, hh, hh * .45); g.fill();
			g.restore();
			g.fillStyle = 'rgba(255,255,255,.25)'; roundRectPath(g, hx - hw * .4, hy - hh * .9, hw * .8, hh * .22, hh * .1); g.fill();
			g.restore();
		},
	});
})();
