// Tailoring concepts: a loom weaving the bar into cloth, and a needle embroidering it.
// Painted like the approved looks (no hard outlines, soft shading, glints); tools in front of the bar are
// drawn in over(). Profession looks have no leading-edge marker: the weaving itself shows the progress.
(() => {
const K = () => (typeof dpr === 'number' ? dpr : 1);
function mkCanvas(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }
const smooth = t => t * t * (3 - 2 * t);

// One cloth per cast, in turn: warp (base), weft, the dark between threads, and how much it shines.
const CLOTHS = [
	{ base: [172, 156, 124], weft: [188, 172, 140], dark: [92, 80, 58], sheen: .08 },     // linen
	{ base: [120, 90, 64], weft: [136, 102, 74], dark: [56, 40, 26], sheen: .05 },        // wool
	{ base: [160, 36, 48], weft: [180, 52, 62], dark: [74, 12, 20], sheen: .22 },         // silk
	{ base: [112, 60, 136], weft: [128, 74, 152], dark: [48, 22, 64], sheen: .14 },       // mageweave
	{ base: [72, 56, 128], weft: [88, 70, 146], dark: [30, 22, 60], sheen: .12 },         // runecloth
	{ base: [146, 164, 196], weft: [166, 184, 214], dark: [66, 78, 108], sheen: .25 },    // mooncloth
];
let clothTurn = Math.floor(Math.random() * CLOTHS.length);
const nextCloth = () => CLOTHS[clothTurn++ % CLOTHS.length];

// ---------------------------------------------------------------- the woven cloth, painted once per cast
// A plain-weave unit (2x2 cells): warp over in two cells, weft over in the other two, each thread a
// rounded strand lit across its width.
function weaveTile(c, cl) {
	const S = c * 2, cv = mkCanvas(S, S), g = cv.getContext('2d');
	g.fillStyle = rgba(cl.dark); g.fillRect(0, 0, S, S);
	const strand = (x, y, horiz, col) => {
		const th = c * .8;
		const gr = horiz ? g.createLinearGradient(0, y, 0, y + c) : g.createLinearGradient(x, 0, x + c, 0);
		gr.addColorStop(0, rgba(mix(col, cl.dark, .6))); gr.addColorStop(.42, rgba(mix(col, [255, 255, 255], .2)));
		gr.addColorStop(.6, rgba(col)); gr.addColorStop(1, rgba(mix(col, cl.dark, .65)));
		g.fillStyle = gr;
		if (horiz) roundRectPath(g, x - c * .1, y + (c - th) / 2, c * 1.2, th, th / 2);
		else roundRectPath(g, x + (c - th) / 2, y - c * .1, th, c * 1.2, th / 2);
		g.fill();
	};
	strand(0, 0, true, cl.base); strand(c, c, true, cl.base);
	strand(c, 0, false, cl.weft); strand(0, c, false, cl.weft);
	return cv;
}
function makeCloth(w, H, cl) {
	const k = K(), cv = mkCanvas(w * k, H * k), g = cv.getContext('2d');
	const c = Math.max(3, Math.round(H * .075 * k));
	g.fillStyle = g.createPattern(weaveTile(c, cl), 'repeat'); g.fillRect(0, 0, cv.width, cv.height);
	// slubs: a few weft picks thicker and lighter, a few darker, as hand-spun thread is
	for (let x = 0; x < cv.width; x += c) {
		const r = Math.random();
		if (r < .1) { g.fillStyle = 'rgba(255,255,255,.07)'; g.fillRect(x, 0, c, cv.height); }
		else if (r < .2) { g.fillStyle = 'rgba(0,0,0,.1)'; g.fillRect(x, 0, c, cv.height); }
	}
	for (let i = 0; i < w / H * 8; i++) {   // soft mottling
		const x = rand(0, cv.width), y = rand(0, cv.height), r = H * k * rand(.3, .9), dark = Math.random() < .55;
		const gr = g.createRadialGradient(x, y, 0, x, y, r);
		gr.addColorStop(0, dark ? 'rgba(0,0,0,.12)' : 'rgba(255,255,255,.06)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
		g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
	}
	// the cloth curves away a little at top and bottom
	const vg = g.createLinearGradient(0, 0, 0, cv.height);
	vg.addColorStop(0, 'rgba(0,0,0,.3)'); vg.addColorStop(.2, 'rgba(0,0,0,0)'); vg.addColorStop(.75, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.38)');
	g.fillStyle = vg; g.fillRect(0, 0, cv.width, cv.height);
	return { cv, c: c / k };
}
// the cloth from 0 to x1 (bar px), its pattern shifted left by `offset` (the cloth winding onto a beam)
function drawCloth(g, s, x1, offset = 0) {
	const w = Math.min(x1, s.W), k = K();
	if (w <= .5) return;
	g.drawImage(s.cloth.cv, offset * k, 0, w * k, s.H * k, 0, 0, w, s.H);
	// a slow sheen sliding along it; silk and mooncloth catch the light most
	const H = s.H, cx = (s.t * H * 1.1 + s.sheenPh * s.W) % (s.W + H * 6) - H * 3;
	const sg = g.createLinearGradient(cx - H * 1.6, 0, cx + H * 1.6, H * .6);
	sg.addColorStop(0, 'rgba(255,255,255,0)'); sg.addColorStop(.5, `rgba(255,250,240,${s.cl.sheen})`); sg.addColorStop(1, 'rgba(255,255,255,0)');
	g.globalCompositeOperation = 'lighter'; g.fillStyle = sg; g.fillRect(0, 0, w, H);
	const hg = g.createLinearGradient(0, 0, 0, H);
	hg.addColorStop(.25, 'rgba(255,255,255,0)'); hg.addColorStop(.38, `rgba(255,255,255,${s.cl.sheen * .5})`); hg.addColorStop(.5, 'rgba(255,255,255,0)');
	g.fillStyle = hg; g.fillRect(0, 0, w, H);
	g.globalCompositeOperation = 'source-over';
	// the freshly beaten fell: weft packed tight, a hair darker, a moment brighter after each beat
	g.fillStyle = 'rgba(0,0,0,.25)'; g.fillRect(w - Math.max(1, s.cloth.c * .5), 0, Math.max(1, s.cloth.c * .5), H);
	if (s.fresh > 0) {
		const fg = g.createLinearGradient(w - H * .5, 0, w, 0);
		fg.addColorStop(0, 'rgba(255,245,225,0)'); fg.addColorStop(1, `rgba(255,245,225,${.22 * s.fresh})`);
		g.globalCompositeOperation = 'lighter'; g.fillStyle = fg; g.fillRect(w - H * .5, 0, H * .5, H); g.globalCompositeOperation = 'source-over';
	}
	// shade behind the spell name so it stays readable on pale cloth
	const tg = g.createLinearGradient(0, 0, H * 4, 0);
	tg.addColorStop(0, 'rgba(0,0,0,.28)'); tg.addColorStop(1, 'rgba(0,0,0,0)');
	g.fillStyle = tg; g.fillRect(0, 0, Math.min(w, H * 4), H);
}

// ---------------------------------------------------------------- warp threads ahead of the fell
// Taut warp runs along the bar into the fell; alternate threads part into the shed (shed -1..1).
function drawWarp(g, s, x0, x1, shed) {
	const H = s.H, c = s.cloth.c, n = Math.floor(H / c), y0 = (H - n * c) / 2, col = s.cl.base;
	if (x1 <= x0) return;
	g.fillStyle = 'rgba(4,4,8,.55)'; g.fillRect(x0, 0, x1 - x0, H);
	const lw = Math.max(.8, c * .5);
	for (let j = 0; j < n; j++) {
		const y = y0 + (j + .5) * c, d = (j % 2 ? 1 : -1) * shed * c * .45, xs = Math.min(x1, x0 + H * .7);
		for (const [w, cc, a, dy] of [[lw, mix(col, [0, 0, 0], .45), .9, 0], [lw * .35, mix(col, [255, 255, 255], .18), .55, -lw * .2]]) {
			g.strokeStyle = rgba(cc, a); g.lineWidth = w;
			g.beginPath(); g.moveTo(x0, y + dy); g.lineTo(xs, y + d + dy); g.lineTo(x1, y + d + dy); g.stroke();
		}
	}
}

// ---------------------------------------------------------------- the loom's tools
// A boat shuttle standing upright: painted wood, brass tips, a pirn of the cloth's thread in its cavity.
function drawShuttle(g, x, y, H, cl, alpha) {
	if (alpha <= 0) return;
	const L = H * 1.1, w = H * .25;
	g.save(); g.globalAlpha *= alpha; g.translate(x, y);
	const body = new Path2D();
	body.moveTo(0, -L / 2); body.bezierCurveTo(w * .66, -L * .3, w * .66, L * .3, 0, L / 2);
	body.bezierCurveTo(-w * .66, L * .3, -w * .66, -L * .3, 0, -L / 2); body.closePath();
	g.save(); g.shadowColor = 'rgba(0,0,0,.55)'; g.shadowBlur = H * .15; g.shadowOffsetX = H * .05; g.shadowOffsetY = H * .06;
	const wood = g.createLinearGradient(-w / 2, 0, w / 2, 0);
	wood.addColorStop(0, '#4a2a12'); wood.addColorStop(.35, '#a8703c'); wood.addColorStop(.55, '#c98d52'); wood.addColorStop(1, '#5a3416');
	g.fillStyle = wood; g.fill(body); g.restore();
	g.save(); g.clip(body);
	g.strokeStyle = 'rgba(60,30,10,.35)'; g.lineWidth = Math.max(.5, H * .01);
	for (let i = -2; i <= 2; i++) { g.beginPath(); g.moveTo(i * w * .12, -L / 2); g.bezierCurveTo(i * w * .22, -L * .15, i * w * .05, L * .15, i * w * .15, L / 2); g.stroke(); }
	const tg = g.createLinearGradient(-w * .3, 0, w * .3, 0);
	tg.addColorStop(0, '#6b4e14'); tg.addColorStop(.45, '#f1d488'); tg.addColorStop(1, '#7a5a1a');
	g.fillStyle = tg; g.fillRect(-w, -L / 2, w * 2, L * .15); g.fillRect(-w, L * .35, w * 2, L * .15);
	g.restore();
	// the cavity and the pirn wound with thread
	const ch = L * .46, cw = w * .44;
	g.fillStyle = 'rgba(28,14,4,.9)'; roundRectPath(g, -cw / 2, -ch / 2, cw, ch, cw / 2); g.fill();
	const bw = cw * .8, bl = ch * .84;
	const bg = g.createLinearGradient(-bw / 2, 0, bw / 2, 0);
	bg.addColorStop(0, rgba(cl.dark)); bg.addColorStop(.42, rgba(mix(cl.weft, [255, 255, 255], .3))); bg.addColorStop(1, rgba(cl.dark));
	g.fillStyle = bg; roundRectPath(g, -bw / 2, -bl / 2, bw, bl, bw * .3); g.fill();
	g.strokeStyle = rgba(cl.dark, .45); g.lineWidth = Math.max(.4, H * .006);
	for (let yy = -bl / 2 + bl * .08; yy < bl / 2; yy += Math.max(1.2, H * .025)) { g.beginPath(); g.moveTo(-bw / 2, yy); g.lineTo(bw / 2, yy + H * .006); g.stroke(); }
	// a glint down the lit side
	g.strokeStyle = 'rgba(255,240,210,.45)'; g.lineWidth = Math.max(.6, H * .018);
	g.beginPath(); g.moveTo(-w * .2, -L * .36); g.bezierCurveTo(-w * .34, -L * .12, -w * .34, L * .12, -w * .2, L * .36); g.stroke();
	g.restore();
}

// The beater: a wooden bar holding the steel reed that packs each weft pick into the fell.
function drawBeater(g, x, H, alpha) {
	if (alpha <= 0) return;
	const w = H * .13, top = -H * .42, bot = H * 1.42;
	g.save(); g.globalAlpha *= alpha;
	g.save(); g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = H * .12; g.shadowOffsetX = H * .05;
	const wd = g.createLinearGradient(x - w / 2, 0, x + w / 2, 0);
	wd.addColorStop(0, '#3e2410'); wd.addColorStop(.4, '#8e5a2e'); wd.addColorStop(.6, '#a46b38'); wd.addColorStop(1, '#43280f');
	g.fillStyle = wd; roundRectPath(g, x - w / 2 + w * .25, top, w * .75, bot - top, w * .2); g.fill(); g.restore();
	g.strokeStyle = 'rgba(40,20,6,.35)'; g.lineWidth = Math.max(.5, H * .01);
	for (let i = 0; i < 3; i++) { const gx = x - w * .1 + i * w * .15; g.beginPath(); g.moveTo(gx, top + H * .05); g.bezierCurveTo(gx + w * .05, H * .3, gx - w * .05, H * .7, gx, bot - H * .05); g.stroke(); }
	const rx = x - w / 2, rw = w * .32;
	const st = g.createLinearGradient(rx, 0, rx + rw, 0);
	st.addColorStop(0, '#5d636b'); st.addColorStop(.5, '#d9dee4'); st.addColorStop(1, '#6b7179');
	g.fillStyle = st; g.fillRect(rx, -H * .06, rw, H * 1.12);
	g.strokeStyle = 'rgba(30,32,36,.6)'; g.lineWidth = Math.max(.4, H * .008);
	for (let y = -H * .04; y < H * 1.06; y += Math.max(2, H * .075)) { g.beginPath(); g.moveTo(rx, y); g.lineTo(rx + rw, y); g.stroke(); }
	for (const y of [top, bot - H * .1]) {
		const bg = g.createLinearGradient(x - w / 2, 0, x + w / 2, 0);
		bg.addColorStop(0, '#6b4e14'); bg.addColorStop(.5, '#f0d184'); bg.addColorStop(1, '#6e5216');
		g.fillStyle = bg; roundRectPath(g, x - w / 2 + w * .2, y, w * .85, H * .1, H * .03); g.fill();
	}
	g.restore();
}

// The weft thread from where this pick entered the shed to the shuttle carrying it.
function drawWeft(g, s, L) {
	const H = s.H, lw = Math.max(1, s.cloth.c * .45), sy = clamp(L.sy, 0, H);
	for (const [w, col, a, dx] of [[lw, mix(s.cl.weft, [0, 0, 0], .25), .95, 0], [lw * .35, mix(s.cl.weft, [255, 255, 255], .35), .7, -lw * .2]]) {
		g.strokeStyle = rgba(col, a); g.lineWidth = w; g.lineCap = 'round';
		g.beginPath(); g.moveTo(L.fell + dx, L.from); g.lineTo(L.fell + H * .1 + dx, sy); g.lineTo(L.sx + dx, L.sy); g.stroke();
	}
}

// Loose weft ends poking out of the selvedges.
function makeTails(s) {
	const tails = [];
	for (let x = s.H * .6; x < s.W; x += s.H * rand(1.2, 2.6)) tails.push({ x, top: Math.random() < .5, len: s.H * rand(.12, .24), curl: rand(-1, 1) });
	return tails;
}
function drawTails(g, s, upTo) {
	const H = s.H, lw = Math.max(.8, s.cloth.c * .4);
	g.lineCap = 'round';
	for (const q of s.tails) {
		if (q.x > upTo - H * .15) continue;
		const sgn = q.top ? -1 : 1, y0 = q.top ? 0 : H;
		g.strokeStyle = rgba(mix(s.cl.weft, [255, 255, 255], .15), .9); g.lineWidth = lw;
		g.beginPath(); g.moveTo(q.x, y0 - sgn * H * .04);
		g.bezierCurveTo(q.x + q.curl * H * .05, y0 + sgn * q.len * .5, q.x + q.curl * H * .14, y0 + sgn * q.len * .7, q.x + q.curl * H * .08, y0 + sgn * q.len);
		g.stroke();
	}
}

// One pick of the weave: the shuttle crosses the shed, the beater packs the weft in, the shed changes.
// geo: reach = how far past the bar's top/bottom the shuttle travels (bar heights), sx = the shuttle's
// distance ahead of the fell, bx/swing = the beater's rest distance and how far it swings in to beat.
function pickState(s, geo = {}) {
	const H = s.H, P = s.period, u = (s.pickT % P) / P, k = Math.floor(s.pickT / P), fell = s.fill;
	const reach = geo.reach ?? .62, down = k % 2 === 0, yTop = -H * reach, yBot = H * (1 + reach);
	const f = smooth(clamp(u / .55));
	const sy = s.pickT <= 0 ? yTop : (down ? lerp(yTop, yBot, f) : lerp(yBot, yTop, f));
	const bump = u > .6 && u < .85 ? Math.sin(Math.PI * (u - .6) / .25) : 0;
	const sign = down ? 1 : -1, shed = u < .85 ? sign : lerp(sign, -sign, smooth((u - .85) / .15));
	return { u, k, fell, sx: fell + H * (geo.sx ?? .2), sy, from: down ? 0 : H, bx: fell + H * (geo.bx ?? .45) - bump * H * (geo.swing ?? .37), bump, shed };
}
function stepPicks(s) {
	if (!s.casting) return;
	const before = (s.pickT % s.period) / s.period;
	s.pickT += s.dt;
	const after = (s.pickT % s.period) / s.period;
	if (before < .725 && after >= .725 && s.fill > s.H * .3) {   // the beat: the pick packs in, fluff flies
		s.fresh = 1;
		for (let i = 0; i < 5; i++) s.parts.emit({ x: s.fill + rand(0, .1) * s.H, y: rand(.1, .9) * s.H, vx: rand(-8, 26), vy: rand(-28, -6), ay: 8, drag: 1.2,
			size: s.H * rand(.015, .035), life: rand(.5, 1.1), color: mix(s.cl.weft, [255, 255, 255], .55), alpha: .6 });
	}
	s.fresh = Math.max(0, s.fresh - s.dt * 3);
}
function loomInit(s, clothExtra = 0) {
	s.cl = nextCloth(); s.cloth = makeCloth(s.W + clothExtra, s.H, s.cl);
	s.period = rand(.38, .5); s.pickT = 0; s.fresh = 0; s.sheenPh = Math.random();
	s.tails = makeTails(s);
}
const toolAlpha = s => s.done ? clamp(1 - s.doneT * 2.2) : 1;

// ---------------------------------------------------------------- A: shuttle and reed
CONCEPTS.push({
	group: 'Tailoring', id: 'tail-a', letter: 'A', name: 'Shuttle and reed',
	desc: 'The bar is the loom: taut warp ahead, a painted shuttle flying through the shed at the cast edge, the reed beating each pick into woven cloth; the cloth changes every cast (linen, wool, silk, mageweave, runecloth, mooncloth)',
	spell: 'Bolt of Linen Cloth', padTop: 1.4, padBottom: 1.4, padX: .9, flash: [255, 245, 225],
	init(s) { loomInit(s); },
	draw(g, s) {
		stepPicks(s);
		const L = s.L = pickState(s);
		g.save(); roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip();
		drawWarp(g, s, s.fill, s.W, L.shed);
		drawCloth(g, s, s.fill);
		g.restore();
		s.parts.update(s.dt); s.parts.draw(g);
	},
	over(g, s) {
		const L = s.L, a = toolAlpha(s);
		if (!L || s.fill < .5) return;
		drawTails(g, s, s.fill);
		g.save(); g.globalAlpha = a; drawWeft(g, s, L); g.restore();
		drawShuttle(g, L.sx, L.sy, s.H, s.cl, a);
		drawBeater(g, L.bx, s.H, a);
	},
});

// ---------------------------------------------------------------- A2–A4: smaller, quieter looms
// The same weave as A, with the tools shrunk to the bar and painted plainer: worn, muted wood, no brass,
// soft shadows, fine threads. Each only just reaches past the bar's top and bottom lines.

// A small boat shuttle: worn dark wood, a hollow with a pirn of the cloth's thread.
function drawShuttleSmall(g, x, y, H, cl, alpha) {
	if (alpha <= 0) return;
	const L = H * .6, w = H * .14;
	g.save(); g.globalAlpha *= alpha; g.translate(x, y);
	const body = new Path2D();
	body.moveTo(0, -L / 2); body.bezierCurveTo(w * .62, -L * .28, w * .62, L * .28, 0, L / 2);
	body.bezierCurveTo(-w * .62, L * .28, -w * .62, -L * .28, 0, -L / 2); body.closePath();
	g.save(); g.shadowColor = 'rgba(0,0,0,.4)'; g.shadowBlur = H * .07; g.shadowOffsetX = H * .025; g.shadowOffsetY = H * .03;
	const wood = g.createLinearGradient(-w / 2, 0, w / 2, 0);
	wood.addColorStop(0, '#2e1c10'); wood.addColorStop(.4, '#6b4a2c'); wood.addColorStop(.6, '#7c5a38'); wood.addColorStop(1, '#2a1a0e');
	g.fillStyle = wood; g.fill(body); g.restore();
	g.save(); g.clip(body);
	g.strokeStyle = 'rgba(30,16,6,.3)'; g.lineWidth = Math.max(.4, H * .008);
	for (let i = -1; i <= 1; i++) { g.beginPath(); g.moveTo(i * w * .15, -L / 2); g.bezierCurveTo(i * w * .25, -L * .15, i * w * .05, L * .15, i * w * .18, L / 2); g.stroke(); }
	g.restore();
	const ch = L * .42, cw = w * .4;
	g.fillStyle = 'rgba(16,8,2,.85)'; roundRectPath(g, -cw / 2, -ch / 2, cw, ch, cw / 2); g.fill();
	const bw = cw * .78, bl = ch * .8;
	const bg = g.createLinearGradient(-bw / 2, 0, bw / 2, 0);
	bg.addColorStop(0, rgba(cl.dark)); bg.addColorStop(.45, rgba(mix(cl.weft, [255, 255, 255], .2))); bg.addColorStop(1, rgba(cl.dark));
	g.fillStyle = bg; roundRectPath(g, -bw / 2, -bl / 2, bw, bl, bw * .3); g.fill();
	g.strokeStyle = 'rgba(255,236,210,.22)'; g.lineWidth = Math.max(.5, H * .012);
	g.beginPath(); g.moveTo(-w * .22, -L * .32); g.bezierCurveTo(-w * .34, -L * .1, -w * .34, L * .1, -w * .22, L * .32); g.stroke();
	g.restore();
}
// A flat stick shuttle: a notched slat with the weft wound round its middle.
function drawStickShuttle(g, x, y, H, cl, alpha) {
	if (alpha <= 0) return;
	const L = H * .72, w = H * .1, n = w * .45;
	g.save(); g.globalAlpha *= alpha; g.translate(x, y);
	const body = new Path2D();
	body.moveTo(-w / 2, -L / 2); body.lineTo(0, -L / 2 + n); body.lineTo(w / 2, -L / 2); body.lineTo(w / 2, L / 2);
	body.lineTo(0, L / 2 - n); body.lineTo(-w / 2, L / 2); body.closePath();
	g.save(); g.shadowColor = 'rgba(0,0,0,.4)'; g.shadowBlur = H * .06; g.shadowOffsetX = H * .02; g.shadowOffsetY = H * .03;
	const wood = g.createLinearGradient(-w / 2, 0, w / 2, 0);
	wood.addColorStop(0, '#4a3220'); wood.addColorStop(.5, '#8a6a46'); wood.addColorStop(1, '#3a2614');
	g.fillStyle = wood; g.fill(body); g.restore();
	g.save(); g.clip(body);
	const lw = Math.max(.6, H * .02);
	for (let yy = -L * .22; yy < L * .22; yy += lw * 1.15) {   // the wound weft
		g.strokeStyle = rgba(mix(cl.weft, yy % (lw * 2.3) < lw * 1.15 ? [255, 255, 255] : [0, 0, 0], .22), .95); g.lineWidth = lw;
		g.beginPath(); g.moveTo(-w / 2, yy); g.lineTo(w / 2, yy + lw * .35); g.stroke();
	}
	g.restore();
	g.strokeStyle = 'rgba(255,236,210,.2)'; g.lineWidth = Math.max(.5, H * .01);
	g.beginPath(); g.moveTo(-w * .32, -L * .45); g.lineTo(-w * .32, -L * .25); g.moveTo(-w * .32, L * .25); g.lineTo(-w * .32, L * .45); g.stroke();
	g.restore();
}
// A slim steel reed in dark wood caps, only just taller than the bar.
function drawReedSmall(g, x, H, alpha) {
	if (alpha <= 0) return;
	const w = H * .075, top = -H * .1, bot = H * 1.1, cap = H * .06, cw = H * .12;
	g.save(); g.globalAlpha *= alpha;
	g.save(); g.shadowColor = 'rgba(0,0,0,.4)'; g.shadowBlur = H * .06; g.shadowOffsetX = H * .025;
	const st = g.createLinearGradient(x - w / 2, 0, x + w / 2, 0);
	st.addColorStop(0, '#4a4e55'); st.addColorStop(.5, '#a2a8b0'); st.addColorStop(1, '#55595f');
	g.fillStyle = st; g.fillRect(x - w / 2, top + cap, w, bot - top - cap * 2); g.restore();
	g.strokeStyle = 'rgba(30,32,36,.5)'; g.lineWidth = Math.max(.4, H * .007);
	for (let y = top + cap + H * .02; y < bot - cap; y += Math.max(1.5, H * .06)) { g.beginPath(); g.moveTo(x - w / 2, y); g.lineTo(x + w / 2, y); g.stroke(); }
	for (const y of [top, bot - cap]) {
		const wd = g.createLinearGradient(x - cw / 2, 0, x + cw / 2, 0);
		wd.addColorStop(0, '#2e1c10'); wd.addColorStop(.5, '#6b4a2c'); wd.addColorStop(1, '#2a1a0e');
		g.fillStyle = wd; roundRectPath(g, x - cw / 2, y, cw, cap, cap * .3); g.fill();
	}
	g.restore();
}
// A hardwood batten (weaving sword) that presses each pick home.
function drawBatten(g, x, H, alpha) {
	if (alpha <= 0) return;
	const w = H * .09, top = -H * .12, bot = H * 1.12;
	g.save(); g.globalAlpha *= alpha;
	g.save(); g.shadowColor = 'rgba(0,0,0,.4)'; g.shadowBlur = H * .06; g.shadowOffsetX = H * .025;
	const wd = g.createLinearGradient(x - w / 2, 0, x + w / 2, 0);
	wd.addColorStop(0, '#2c1a0e'); wd.addColorStop(.35, '#5e4228'); wd.addColorStop(.6, '#6e4e30'); wd.addColorStop(1, '#261608');
	g.fillStyle = wd; roundRectPath(g, x - w / 2, top, w, bot - top, w * .4); g.fill(); g.restore();
	g.strokeStyle = 'rgba(255,230,196,.18)'; g.lineWidth = Math.max(.5, H * .012);
	g.beginPath(); g.moveTo(x - w * .2, top + H * .08); g.lineTo(x - w * .2, bot - H * .08); g.stroke();
	g.strokeStyle = 'rgba(20,10,4,.35)'; g.lineWidth = Math.max(.4, H * .007);
	g.beginPath(); g.moveTo(x + w * .15, top + H * .1); g.bezierCurveTo(x + w * .25, H * .3, x + w * .05, H * .7, x + w * .18, bot - H * .1); g.stroke();
	g.restore();
}
// A fine weft laid straight down the shed, a loose end curling off it (A4 has no shuttle).
function drawWeftLaid(g, s, L) {
	const H = s.H, lw = Math.max(.8, s.cloth.c * .4), x = L.fell + H * .06, y0 = L.from, y1 = clamp(L.sy, -H * .08, H * 1.08);
	for (const [w, col, a] of [[lw, mix(s.cl.weft, [0, 0, 0], .25), .95], [lw * .35, mix(s.cl.weft, [255, 255, 255], .35), .7]]) {
		g.strokeStyle = rgba(col, a); g.lineWidth = w; g.lineCap = 'round';
		g.beginPath(); g.moveTo(x, y0); g.lineTo(x, y1); g.quadraticCurveTo(x + H * .12, y1 + (y1 > y0 ? H * .06 : -H * .06), x + H * .16, y1 + (y1 > y0 ? -H * .02 : H * .02)); g.stroke();
	}
}
function loomConcept(o) {
	CONCEPTS.push({
		group: 'Tailoring', id: o.id, letter: o.letter, name: o.name, desc: o.desc, spell: o.spell,
		padTop: o.pad, padBottom: o.pad, padX: .9, flash: [255, 245, 225],
		init(s) { loomInit(s); },
		draw(g, s) {
			stepPicks(s);
			const L = s.L = pickState(s, o.geo);
			g.save(); roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip();
			drawWarp(g, s, s.fill, s.W, L.shed);
			drawCloth(g, s, s.fill);
			g.restore();
			s.parts.update(s.dt); s.parts.draw(g);
		},
		over(g, s) {
			const L = s.L, a = toolAlpha(s);
			if (!L || s.fill < .5) return;
			drawTails(g, s, s.fill);
			o.tools(g, s, L, a);
		},
	});
}
loomConcept({
	id: 'tail-a2', letter: 'A2', name: 'Shuttle and reed, small', spell: 'Bolt of Woolen Cloth', pad: .55,
	desc: 'A shrunk to the bar: a small worn boat shuttle just clears the bar\'s lines, a slim steel reed in dark wood caps beats each pick; no brass, soft shadows',
	geo: { reach: .2, sx: .18, bx: .4, swing: .3 },
	tools(g, s, L, a) {
		g.save(); g.globalAlpha = a; drawWeft(g, s, L); g.restore();
		drawShuttleSmall(g, L.sx, L.sy, s.H, s.cl, a);
		drawReedSmall(g, L.bx, s.H, a);
	},
});
loomConcept({
	id: 'tail-a3', letter: 'A3', name: 'Stick shuttle and batten', spell: 'Bolt of Silk Cloth', pad: .55,
	desc: 'A flat notched stick shuttle wound with the weft slides through the shed inside the bar; a hardwood batten presses each pick home',
	geo: { reach: .12, sx: .16, bx: .4, swing: .3 },
	tools(g, s, L, a) {
		g.save(); g.globalAlpha = a; drawWeft(g, s, L); g.restore();
		drawStickShuttle(g, L.sx, L.sy, s.H, s.cl, a);
		drawBatten(g, L.bx, s.H, a);
	},
});
loomConcept({
	id: 'tail-a4', letter: 'A4', name: 'Reed only', spell: 'Bolt of Mageweave', pad: .5,
	desc: 'The quietest: no shuttle at all, each weft is laid straight down the open shed as a fine thread, then the slim reed packs it into the cloth',
	geo: { reach: .08, sx: .06, bx: .36, swing: .28 },
	tools(g, s, L, a) {
		g.save(); g.globalAlpha = a; drawWeftLaid(g, s, L); g.restore();
		drawReedSmall(g, L.bx, s.H, a);
	},
});

// ---------------------------------------------------------------- B: the cloth beam
// The woven cloth winds onto a cloth beam at the left, growing fat as the cast goes on, while the warp
// beam at the right end empties; two heddle shafts lift alternately to open the shed.
function drawRoller(g, H, cx, r, top, bot, col, tex) {
	const ry = r * .32, aw = Math.max(H * .08, r * .4);
	g.save(); g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = H * .12; g.shadowOffsetX = H * .04;
	const ag = g.createLinearGradient(cx - aw / 2, 0, cx + aw / 2, 0);
	ag.addColorStop(0, '#3a210d'); ag.addColorStop(.5, '#a06a38'); ag.addColorStop(1, '#3a210d');
	g.fillStyle = ag; roundRectPath(g, cx - aw / 2, top - H * .28, aw, bot - top + H * .56, aw * .3); g.fill();
	g.restore();
	const body = new Path2D();
	body.rect(cx - r, top, r * 2, bot - top); body.ellipse(cx, bot, r, ry, 0, 0, Math.PI);
	g.save(); g.shadowColor = 'rgba(0,0,0,.55)'; g.shadowBlur = H * .15; g.shadowOffsetX = H * .05;
	g.fillStyle = rgba(col); g.fill(body); g.restore();
	g.save(); g.clip(body);
	if (tex) tex(cx - r, top, r * 2, bot - top + ry);
	const sg = g.createLinearGradient(cx - r, 0, cx + r, 0);
	sg.addColorStop(0, 'rgba(0,0,0,.62)'); sg.addColorStop(.3, 'rgba(255,255,255,.1)'); sg.addColorStop(.42, 'rgba(255,255,255,.2)');
	sg.addColorStop(.75, 'rgba(0,0,0,.15)'); sg.addColorStop(1, 'rgba(0,0,0,.66)');
	g.fillStyle = sg; g.fillRect(cx - r, top - ry, r * 2, bot - top + ry * 2);
	g.restore();
	// the end: wound layers round a wooden core
	const cg = g.createRadialGradient(cx, top, 0, cx, top, r);
	cg.addColorStop(0, rgba(mix(col, [255, 255, 255], .12))); cg.addColorStop(1, rgba(mix(col, [0, 0, 0], .32)));
	g.fillStyle = cg; g.beginPath(); g.ellipse(cx, top, r, ry, 0, 0, 6.283); g.fill();
	g.strokeStyle = rgba(mix(col, [0, 0, 0], .45), .55); g.lineWidth = Math.max(.5, H * .008);
	for (let rr = r * .86; rr > aw * .7; rr -= Math.max(1.5, H * .03)) { g.beginPath(); g.ellipse(cx, top, rr, rr * ry / r, 0, 0, 6.283); g.stroke(); }
	const core = g.createRadialGradient(cx - aw * .1, top, 0, cx, top, aw * .6);
	core.addColorStop(0, '#a87444'); core.addColorStop(1, '#5a3618');
	g.fillStyle = core; g.beginPath(); g.ellipse(cx, top, aw * .55, aw * .55 * ry / r, 0, 0, 6.283); g.fill();
	// brass ferrules on the axle ends
	for (const y of [top - H * .28, bot + H * .2]) {
		const bg = g.createLinearGradient(cx - aw / 2, 0, cx + aw / 2, 0);
		bg.addColorStop(0, '#6b4e14'); bg.addColorStop(.5, '#f0d184'); bg.addColorStop(1, '#6e5216');
		g.fillStyle = bg; roundRectPath(g, cx - aw * .55, y, aw * 1.1, H * .08, H * .03); g.fill();
	}
}
// A heddle shaft: wooden bars above and below the bar, steel heddle wires between, each with an eye.
function drawShaft(g, x, off, H, alpha) {
	if (alpha <= 0) return;
	const w = H * .22, t = H * .08, top = -H * .4 + off, bot = H * 1.32 + off;
	g.save(); g.globalAlpha *= alpha;
	g.strokeStyle = 'rgba(200,206,214,.75)'; g.lineWidth = Math.max(.5, H * .01);
	for (let i = 0; i < 4; i++) {
		const wx = x - w * .35 + i * w * .23;
		g.beginPath(); g.moveTo(wx, top + t); g.lineTo(wx, bot); g.stroke();
		g.fillStyle = 'rgba(20,22,26,.8)'; g.beginPath(); g.ellipse(wx, H * .5 + off * .4 + (i % 2 ? H * .12 : -H * .12), H * .018, H * .04, 0, 0, 6.283); g.fill();
	}
	g.save(); g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = H * .1; g.shadowOffsetY = H * .04;
	for (const y of [top, bot]) {
		const wd = g.createLinearGradient(0, y, 0, y + t);
		wd.addColorStop(0, '#a46b38'); wd.addColorStop(1, '#4a2b12');
		g.fillStyle = wd; roundRectPath(g, x - w / 2, y, w, t, t * .4); g.fill();
	}
	g.restore(); g.restore();
}
CONCEPTS.push({
	group: 'Tailoring', id: 'tail-b', letter: 'B', name: 'Cloth beam',
	desc: 'A as a whole loom: the woven cloth winds onto a cloth beam at the left that grows as the cast goes on, the warp comes off a warp beam at the right that empties, and two heddle shafts lift in turn to open the shed',
	spell: 'Runecloth Bag', padTop: 1.4, padBottom: 1.4, padX: 1.1, flash: [255, 245, 225],
	init(s) { loomInit(s, s.H * 3); },
	draw(g, s) {
		stepPicks(s);
		const L = s.L = pickState(s);
		g.save(); roundRectPath(g, 0, 0, s.W, s.H, s.H * .18); g.clip();
		drawWarp(g, s, s.fill, s.W, L.shed);
		drawCloth(g, s, s.fill, s.p * s.H * 1.6);   // the cloth creeps left onto the beam
		g.restore();
		s.parts.update(s.dt); s.parts.draw(g);
	},
	over(g, s) {
		const L = s.L, H = s.H, a = toolAlpha(s), k = K();
		if (!L) return;
		// warp beam at the right end, emptying
		const rw = H * lerp(.34, .14, s.p), warpCol = mix(s.cl.base, [255, 255, 255], .1);
		drawRoller(g, H, s.W + rw * .6, rw, -H * .12, H * 1.06, warpCol, (x, y, w, h) => {
			g.lineWidth = Math.max(.5, s.cloth.c * .3);
			for (let yy = y, i = 0; yy < y + h; yy += Math.max(1, s.cloth.c * .5), i++) {
				g.strokeStyle = rgba(i % 2 ? mix(warpCol, [0, 0, 0], .35) : mix(warpCol, [255, 255, 255], .25), .6);
				g.beginPath(); g.moveTo(x, yy); g.lineTo(x + w, yy + H * .01); g.stroke();
			}
		});
		if (s.fill < .5) return;
		drawTails(g, s, s.fill);
		// heddle shafts lifting in turn
		drawShaft(g, L.fell + H * .78, -L.shed * H * .12, H, a);
		drawShaft(g, L.fell + H * 1.06, L.shed * H * .12, H, a);
		g.save(); g.globalAlpha = a; drawWeft(g, s, L); g.restore();
		drawShuttle(g, L.sx, L.sy, H, s.cl, a);
		drawBeater(g, L.bx, H, a);
		// cloth beam at the left end, growing
		const rc = H * (.16 + .22 * s.p);
		drawRoller(g, H, -rc * .15, rc, -H * .12, H * 1.06, s.cl.base, (x, y, w, h) => {
			g.drawImage(s.cloth.cv, 0, 0, Math.min(s.cloth.cv.width, w * 3 * k), s.cloth.cv.height, x, y, w, h);
		});
	},
});

// ---------------------------------------------------------------- C: embroidery hoop
// Finished cloth stretched in a wooden hoop that travels along the bar; a needle stitches an ornate vine
// in gold or coloured thread, with curling tendrils, satin-stitched leaves and knots. Ahead of the
// needle the cloth lies in shade with the pattern chalked on it.
const HOOP = .5;   // the hoop's radius, in bar heights
const THREADS_DARK =[[226, 182, 78], [214, 220, 232]];                  // gold, silver on dark cloth
const THREADS_LIGHT = [[176, 30, 44], [48, 74, 178], [34, 128, 78]];     // crimson, royal blue, emerald on pale cloth
// A pattern is stitched lines, satin leaves/petals and French knots, plus vy(x): where the needle works.
// A line is { pts } stitched in order as the needle passes each point, or { pts, x0, span } stitched over
// the stretch x0..x0+span (motifs that wind back on themselves: tendrils, stars, moons).
// One pattern per cast, in turn: vine, diamond chain, knotwork braid, blossom chain, stars and moons.
const STEP = .07;
const line = (H, W, fy) => { const pts = []; for (let x = H * .3; x <= W - H * .2; x += H * STEP) pts.push([x, fy(x)]); return { pts }; };
const PATTERNS = [
	function vinePattern(W, H) {
		const ph = rand(0, 6.283), amp = rand(.16, .24), wl = rand(1.1, 1.5);
		const vy = x => H * (.5 + amp * Math.sin(x / (H * wl) + ph));
		const vine = line(H, W, vy), lines = [vine], leaves = [], knots = [];
		let up = Math.random() < .5;
		for (let x = H * rand(1, 1.6); x < W - H * .8; x += H * rand(1.4, 2.1)) {
			const y = vy(x), sgn = up ? -1 : 1, pts = [vine.pts[Math.max(0, Math.round((x - H * .3) / (H * STEP)))] || [x, y]];
			const R = H * .2, cx = x + H * .18, cy = clamp(y + sgn * H * .22, H * .24, H * .76);
			for (let i = 0; i <= 24; i++) {   // a spiral tendril leaving the vine and winding in
				const t = i / 24, ang = -sgn * (Math.PI * .5) + sgn * t * Math.PI * 3.2, r = R * (1 - t * .8);
				pts.push([cx + Math.cos(ang) * r * .9, cy + Math.sin(ang) * r]);
			}
			lines.push({ pts, x0: x, span: H * .6, thin: true });
			const lx = x + H * rand(.55, .8), la = sgn * -.9 + rand(-.25, .25);   // a leaf on the other side
			leaves.push({ x: lx, y: vy(lx), ang: -la, len: H * rand(.28, .36), wid: H * rand(.1, .14) });
			for (let i = 0; i < 2; i++) knots.push({ x: x + H * rand(-.3, .5), y: clamp(vy(x) + rand(-.35, .35) * H, H * .14, H * .86), r: H * rand(.025, .04) });
			up = !up;
		}
		return { vy, lines, leaves, knots };
	},
	function diamondPattern(W, H) {   // a chain of diamonds between two running borders, a knot in each
		const p = H * rand(.75, .95), a = H * .26, mid = H * .5;
		const tri = x => 1 - Math.abs(((x / p) % 1) * 2 - 1);
		const knots = [];
		for (let x = H * .3 + p / 2; x < W - H * .3; x += p) knots.push({ x, y: mid, r: H * .045 });
		return {
			vy: x => mid - a * tri(x), knots, leaves: [],
			lines: [line(H, W, x => mid - a * tri(x)), line(H, W, x => mid + a * tri(x)),
				line(H, W, () => H * .12), line(H, W, () => H * .88)],
		};
	},
	function knotPattern(W, H) {   // a two-strand braid crossing back and forth, like a carved knotwork band
		const k = H * rand(.32, .4), A = H * .26, mid = H * .5;
		const s1 = x => mid + A * Math.sin(x / k), s2 = x => mid - A * Math.sin(x / k), s3 = x => mid + A * .55 * Math.cos(x / k);
		return { vy: s1, knots: [], leaves: [], lines: [line(H, W, s1), line(H, W, s2), line(H, W, s3)] };
	},
	function blossomPattern(W, H) {   // small five-petal blossoms along a gently curving stem
		const ph = rand(0, 6.283), vy = x => H * (.5 + .08 * Math.sin(x / (H * 1.3) + ph));
		const leaves = [], knots = [];
		let up = Math.random() < .5;
		for (let x = H * rand(.8, 1.2); x < W - H * .5; x += H * rand(.9, 1.2)) {
			const cx = x, cy = vy(x) + (up ? -1 : 1) * H * .2, r0 = rand(0, 1.2);
			for (let i = 0; i < 5; i++) leaves.push({ x: cx, y: cy, ang: r0 + i * Math.PI * .4, len: H * .17, wid: H * .1 });
			knots.push({ x: cx, y: cy, r: H * .04 });
			up = !up;
		}
		return { vy, lines: [line(H, W, vy)], leaves, knots };
	},
	function starPattern(W, H) {   // five-point stars and crescent moons strung on a fine wavy thread
		const ph = rand(0, 6.283), vy = x => H * (.5 + .1 * Math.sin(x / (H * .9) + ph));
		const lines = [line(H, W, vy)], knots = [];
		let star = Math.random() < .5;
		for (let x = H * rand(.9, 1.3); x < W - H * .5; x += H * rand(1, 1.35)) {
			const cx = x, cy = H * .5, pts = [];
			if (star) {
				const R = H * .26, r = R * .42, a0 = -Math.PI / 2 + rand(-.2, .2);
				for (let i = 0; i <= 10; i++) { const rr = i % 2 ? r : R, an = a0 + i * Math.PI / 5; pts.push([cx + Math.cos(an) * rr, cy + Math.sin(an) * rr]); }
			} else {   // the outer arc of a crescent, then back along the inner one
				const R = H * .26;
				for (let i = 0; i <= 14; i++) { const an = Math.PI * (.35 + i / 14 * 1.3); pts.push([cx + Math.cos(an) * R, cy + Math.sin(an) * R]); }
				for (let i = 14; i >= 0; i--) { const an = Math.PI * (.35 + i / 14 * 1.3); pts.push([cx + R * .35 + Math.cos(an) * R * .78, cy + Math.sin(an) * R * .8]); }
			}
			lines.push({ pts, x0: cx - H * .3, span: H * .6, thin: true });
			for (let i = 0; i < 2; i++) knots.push({ x: cx + H * rand(.35, .55), y: H * rand(.18, .82), r: H * .025 });
			star = !star;
		}
		return { vy, lines, leaves: [], knots };
	},
];
let patternTurn = Math.floor(Math.random() * PATTERNS.length);
function makePattern(s) { return PATTERNS[patternTurn++ % PATTERNS.length](s.W, s.H); }
// how many points of a line are stitched once the needle is at f
function lineN(L, f) {
	if (L.span) return Math.floor(clamp((f - L.x0) / L.span) * L.pts.length);
	let n = 0;
	while (n < L.pts.length && L.pts[n][0] <= f) n++;
	return n;
}
// stem stitches along a polyline, the first n points only (stitches overlap like the real thing)
function stitches(g, pts, n, H, col) {
	const tw = Math.max(1.4, H * .075);
	g.lineCap = 'round';
	for (const [w, c, a, oy] of [[tw * 1.25, [0, 0, 0], .3, H * .02], [tw, mix(col, [0, 0, 0], .2), 1, 0], [tw * .38, mix(col, [255, 255, 255], .45), .8, -tw * .2]]) {
		g.strokeStyle = rgba(c, a); g.lineWidth = w;
		for (let i = 1; i < n && i < pts.length; i++) {
			const [x0, y0] = pts[i - 1], [x1, y1] = pts[i];
			const dx = x1 - x0, dy = y1 - y0;
			g.beginPath(); g.moveTo(x0 + dx * .08, y0 + dy * .08 + oy + dx * .12); g.lineTo(x1 + dx * .25, y1 + dy * .25 + oy - dx * .12); g.stroke();
		}
	}
}
function satinLeaf(g, q, frac, H, col) {
	g.save(); g.translate(q.x, q.y); g.rotate(q.ang);
	const n = Math.max(1, Math.floor(10 * frac)), tw = Math.max(1, H * .03);
	for (let i = 0; i < n; i++) {
		const t = (i + .5) / 10, half = Math.sin(Math.PI * t) * q.wid * .5, x = t * q.len;
		for (const [w, c, a] of [[tw * 1.3, mix(col, [0, 0, 0], .35), 1], [tw * .45, mix(col, [255, 255, 255], .4), .8]]) {
			g.strokeStyle = rgba(c, a); g.lineWidth = w; g.lineCap = 'round';
			g.beginPath(); g.moveTo(x - H * .02, -half); g.lineTo(x + H * .02, half); g.stroke();
		}
	}
	g.restore();
}
function drawNeedle(g, x, y, H, ang, alpha, thread) {
	if (alpha <= 0) return;
	const L = H * .95, w = H * .05;
	g.save(); g.globalAlpha *= alpha; g.translate(x, y); g.rotate(ang);
	g.save(); g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = H * .1; g.shadowOffsetX = H * .04; g.shadowOffsetY = H * .05;
	const body = new Path2D();
	body.moveTo(0, 0); body.quadraticCurveTo(L * .3, -w * .45, L * .95, -w * .5); body.arc(L * .95, 0, w * .5, -Math.PI / 2, Math.PI / 2);
	body.quadraticCurveTo(L * .3, w * .45, 0, 0); body.closePath();
	const st = g.createLinearGradient(0, -w / 2, 0, w / 2);
	st.addColorStop(0, '#f2f5f8'); st.addColorStop(.45, '#a9b0b8'); st.addColorStop(1, '#4f555c');
	g.fillStyle = st; g.fill(body); g.restore();
	g.fillStyle = 'rgba(20,22,26,.9)'; g.beginPath(); g.ellipse(L * .86, 0, w * .9, w * .17, 0, 0, 6.283); g.fill();
	g.strokeStyle = 'rgba(255,255,255,.7)'; g.lineWidth = Math.max(.5, H * .01);
	g.beginPath(); g.moveTo(L * .12, -w * .12); g.lineTo(L * .7, -w * .3); g.stroke();
	// the thread through the eye
	g.strokeStyle = rgba(thread); g.lineWidth = Math.max(1, H * .03);
	g.beginPath(); g.moveTo(L * .86, 0); g.quadraticCurveTo(L * 1.02, w * 2, L * .98, w * 3.5); g.stroke();
	g.restore();
}
function drawHoop(g, x, y, R, H, alpha) {
	if (alpha <= 0) return;
	const bw = H * .09;
	g.save(); g.globalAlpha *= alpha;
	g.save(); g.shadowColor = 'rgba(0,0,0,.55)'; g.shadowBlur = H * .14; g.shadowOffsetX = H * .04; g.shadowOffsetY = H * .05;
	for (const [r, l, d] of [[R + bw * .55, '#b47a44', '#4e2e14'], [R - bw * .3, '#9c6636', '#3e2410']]) {
		const wd = g.createLinearGradient(0, y - r, 0, y + r);
		wd.addColorStop(0, l); wd.addColorStop(.5, d); wd.addColorStop(1, l);
		g.strokeStyle = wd; g.lineWidth = bw * .8; g.beginPath(); g.arc(x, y, r, 0, 6.283); g.stroke();
	}
	g.restore();
	g.strokeStyle = 'rgba(255,230,190,.35)'; g.lineWidth = Math.max(.5, H * .015);
	g.beginPath(); g.arc(x, y, R + bw * .7, Math.PI * 1.1, Math.PI * 1.6); g.stroke();
	// the brass screw clamp at the top
	const cy = y - R - bw * .9, bg = g.createLinearGradient(x - bw * .6, 0, x + bw * .6, 0);
	bg.addColorStop(0, '#6b4e14'); bg.addColorStop(.5, '#f0d184'); bg.addColorStop(1, '#6e5216');
	g.fillStyle = bg; roundRectPath(g, x - bw * .55, cy - bw * .4, bw * 1.1, bw * 1.1, bw * .25); g.fill();
	g.fillStyle = '#c9a85a'; g.beginPath(); g.arc(x, cy - bw * .55, bw * .32, 0, 6.283); g.fill();
	g.restore();
}
CONCEPTS.push({
	group: 'Tailoring', id: 'tail-c', letter: 'C', name: 'Embroidery hoop',
	desc: 'A small wooden hoop rides the cast edge; a steel needle stitches a different pattern each cast (vine, diamond chain, knotwork braid, blossoms, stars and moons) in gold, silver or coloured thread; ahead the pattern is chalked on shaded cloth',
	spell: 'Mooncloth Robe', padTop: .9, padBottom: .5, padX: 1, flash: [255, 245, 225],
	init(s) {
		s.cl = nextCloth(); s.cloth = makeCloth(s.W, s.H, s.cl); s.sheenPh = Math.random(); s.fresh = 0;
		const lum = s.cl.base[0] * .3 + s.cl.base[1] * .55 + s.cl.base[2] * .15;
		s.thread = pick(lum > 130 ? THREADS_LIGHT : THREADS_DARK);
		s.pat = makePattern(s); s.stab = 0;
	},
	draw(g, s) {
		const { W, H } = s, f = s.fill, P = s.pat;
		g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
		drawCloth(g, s, W);
		// the unworked cloth ahead lies in shade, the pattern chalked on it
		if (f < W) {
			g.fillStyle = 'rgba(0,0,0,.45)'; g.fillRect(f, 0, W - f, H);
			g.strokeStyle = 'rgba(255,255,255,.34)'; g.lineWidth = Math.max(.8, H * .02); g.setLineDash([H * .06, H * .06]);
			for (const L of P.lines) {
				const from = lineN(L, f);
				if (from >= L.pts.length - 1) continue;
				g.beginPath(); g.moveTo(...L.pts[Math.max(0, from - 1)]);
				for (let i = from; i < L.pts.length; i++) g.lineTo(...L.pts[i]);
				g.stroke();
			}
			g.setLineDash([]);
			g.fillStyle = 'rgba(255,255,255,.3)';   // chalk dots where knots and blossoms will go
			for (const q of P.knots) if (q.x > f) { g.beginPath(); g.arc(q.x, q.y, Math.max(.8, q.r * .5), 0, 6.283); g.fill(); }
		}
		// the hoop holds the cloth taut: a touch brighter inside it
		const R = H * HOOP;
		g.save(); g.beginPath(); g.arc(f, H / 2, R, 0, 6.283); g.clip();
		g.fillStyle = 'rgba(255,255,255,.07)'; g.fillRect(f - R, 0, R * 2, H);
		const rg = g.createRadialGradient(f, H / 2, R * .7, f, H / 2, R);
		rg.addColorStop(0, 'rgba(0,0,0,0)'); rg.addColorStop(1, 'rgba(0,0,0,.3)');
		g.fillStyle = rg; g.fillRect(f - R, 0, R * 2, H);
		g.restore();
		// what has been stitched so far
		for (const L of P.lines) {
			const n = lineN(L, f);
			if (n > 1) stitches(g, L.pts, n, L.thin ? H * .8 : H, s.thread);
		}
		for (const q of P.leaves) { const fr = clamp((f - q.x) / (H * .5)); if (fr > 0) satinLeaf(g, q, fr, H, s.thread); }
		for (const q of P.knots) {
			if (q.x > f) continue;
			const kg = g.createRadialGradient(q.x - q.r * .3, q.y - q.r * .3, 0, q.x, q.y, q.r);
			kg.addColorStop(0, rgba(mix(s.thread, [255, 255, 255], .5))); kg.addColorStop(1, rgba(mix(s.thread, [0, 0, 0], .4)));
			g.fillStyle = kg; g.beginPath(); g.arc(q.x, q.y, q.r, 0, 6.283); g.fill();
		}
		g.restore();
		if (s.casting) s.stab += s.dt / .32;
	},
	over(g, s) {
		const { H } = s, f = s.fill, a = toolAlpha(s);
		if (f < .5 && s.casting) return;
		const y = s.pat.vy(Math.max(H * .3, f));
		drawHoop(g, f, H / 2, H * HOOP, H, a);
		// the needle stabs down through the cloth and draws back up, the thread trailing to the last stitch
		const v = s.stab % 1, dip = v < .5 ? smooth(v * 2) : smooth((1 - v) * 2);
		const lift = s.done ? easeIn(clamp(s.doneT / .5)) * H : 0;
		const tipX = f + H * .04, tipY = y - H * .16 + dip * H * .2 - lift;
		g.save(); g.globalAlpha = a; g.strokeStyle = rgba(s.thread); g.lineWidth = Math.max(1, H * .03); g.lineCap = 'round';
		const ex = tipX + Math.cos(-1.1) * H * .82, ey = tipY + Math.sin(-1.1) * H * .82;
		g.beginPath(); g.moveTo(f - H * .02, y); g.quadraticCurveTo(f - H * .2, y - H * .5, ex, ey); g.stroke(); g.restore();
		if (dip > .6) {   // the puncture where the tip has gone through
			g.fillStyle = `rgba(0,0,0,${.4 * a})`; g.beginPath(); g.arc(tipX, y + H * .02, H * .025, 0, 6.283); g.fill();
		}
		drawNeedle(g, tipX, tipY, H, -1.1, a * (dip > .6 ? .9 : 1), s.thread);
	},
});
})();
