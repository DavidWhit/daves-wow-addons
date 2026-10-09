// Skinning concepts: a knife dragged down an animal corpse that breaks into bones and blood spots.
(() => {
const BONE = [230, 220, 194], BONE_SH = [168, 150, 118], BONE_LINE = 'rgba(52,36,20,.95)';
const BLOOD = [104, 6, 10], BLOOD_L = [158, 18, 20];
const PELTS = [
	{ base: [98, 66, 40], dark: [46, 28, 14], light: [150, 110, 70], stroke: [[66, 42, 22], [124, 88, 54], [168, 128, 84]] },              // bear
	{ base: [102, 102, 108], dark: [44, 44, 50], light: [170, 168, 164], stroke: [[68, 68, 76], [136, 134, 134], [196, 194, 188]] },     // wolf
	{ base: [164, 114, 52], dark: [88, 56, 22], light: [214, 176, 116], stroke: [[118, 78, 34], [196, 150, 86], [232, 204, 150]], stripes: true },   // cat
];

// ---------------------------------------------------------------- shared drawing
// Fur: short curved strokes in three shades, flowing toward the tail (left), fanning out top and bottom.
function furStrokes(x0, x1, y0, y1, density, H) {
	const paths = [new Path2D(), new Path2D(), new Path2D()], mid = (y0 + y1) / 2, h = y1 - y0;
	const n = Math.round((x1 - x0) * h / (H * H) * density);
	for (let i = 0; i < n; i++) {
		const x = rand(x0, x1), y = rand(y0, y1), len = H * rand(.07, .15);
		const ang = Math.PI - (y - mid) / h * .9 + rand(-.18, .18), bend = H * rand(-.02, .02);
		const ex = x + Math.cos(ang) * len, ey = y + Math.sin(ang) * len;
		const r = Math.random(), p = paths[r < .4 ? 0 : r < .8 ? 1 : 2];
		p.moveTo(x, y); p.quadraticCurveTo((x + ex) / 2 - Math.sin(ang) * bend, (y + ey) / 2 + Math.cos(ang) * bend, ex, ey);
	}
	return paths;
}
function stripePath(W, H) {
	const p = new Path2D();
	for (let x = rand(0, H * .6); x < W + H; x += H * rand(.55, .95)) {
		for (const side of [0, 1]) {
			const w = H * rand(.05, .09), len = H * rand(.26, .4), lean = H * rand(.08, .18);
			const y = v => side ? H - v : v;
			p.moveTo(x - w, y(-1)); p.quadraticCurveTo(x - lean * .4 - w * .3, y(len * .5), x - lean, y(len));
			p.quadraticCurveTo(x - lean * .4 + w * .3, y(len * .5), x + w, y(-1)); p.closePath();
		}
	}
	return p;
}
function drawFur(g, x0, y0, w, h, pelt, strokes, stripes, H) {
	const gr = g.createLinearGradient(0, y0, 0, y0 + h);
	gr.addColorStop(0, rgba(pelt.dark)); gr.addColorStop(.45, rgba(pelt.base)); gr.addColorStop(1, rgba(pelt.light));
	g.fillStyle = gr; g.fillRect(x0, y0, w, h);
	if (stripes) { g.fillStyle = rgba(pelt.dark, .7); g.fill(stripes); }
	g.lineCap = 'round'; g.lineWidth = Math.max(.6, H * .022);
	strokes.forEach((p, i) => { g.strokeStyle = rgba(pelt.stroke[i], .85); g.stroke(p); });
	const sh = g.createLinearGradient(0, y0, 0, y0 + h);
	sh.addColorStop(0, 'rgba(0,0,0,.5)'); sh.addColorStop(.28, 'rgba(0,0,0,0)'); sh.addColorStop(.72, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,.45)');
	g.fillStyle = sh; g.fillRect(x0, y0, w, h);
}

// A blood spot: a splat with a few satellite drops; it pops in when the knife reaches it.
function makeSpot(x, y, r) {
	const sat = [];
	for (let i = 0, n = 2 + Math.floor(Math.random() * 4); i < n; i++) {
		const a = rand(0, 6.283), d = r * rand(1.1, 2);
		sat.push({ dx: Math.cos(a) * d, dy: Math.sin(a) * d * .7, r: r * rand(.15, .38) });
	}
	return { x, y, r, sat, sx: rand(.8, 1.3), born: null };
}
function drawSpots(g, spots, revealX, t, alpha = 1) {
	for (const sp of spots) {
		if (sp.born === null) { if (revealX >= sp.x) sp.born = t; else continue; }
		const k = easeOutBack(clamp((t - sp.born) / .28));
		if (k <= 0) continue;
		g.save(); g.translate(sp.x, sp.y); g.scale(k * sp.sx, k);
		g.fillStyle = rgba(BLOOD, .92 * alpha);
		g.beginPath(); g.arc(0, 0, sp.r, 0, 6.283);
		for (const q of sp.sat) { g.moveTo(q.dx + q.r, q.dy); g.arc(q.dx, q.dy, q.r, 0, 6.283); }
		g.fill();
		g.fillStyle = rgba(BLOOD_L, .55 * alpha); g.beginPath(); g.arc(-sp.r * .25, -sp.r * .25, sp.r * .45, 0, 6.283); g.fill();
		g.restore();
	}
}

// A bone along x, centred on 0: shaft with two knobs at each end. Outline first, fill over it.
function bonePath(len, w) {
	const p = new Path2D(), r = w * .42;
	p.rect(-len / 2, -w * .24, len, w * .48);
	for (const sx of [-1, 1]) for (const sy of [-1, 1]) { p.moveTo(sx * len / 2 + r, sy * w * .28); p.arc(sx * len / 2, sy * w * .28, r, 0, 6.283); }
	return p;
}
function drawBone(g, x, y, rot, len, w, alpha = 1) {
	g.save(); g.translate(x, y); g.rotate(rot); g.globalAlpha *= alpha;
	const p = bonePath(len, w);
	g.lineWidth = Math.max(1, w * .3); g.strokeStyle = BONE_LINE; g.stroke(p);
	const gr = g.createLinearGradient(0, -w * .6, 0, w * .6);
	gr.addColorStop(0, rgba([248, 242, 222])); gr.addColorStop(.5, rgba(BONE)); gr.addColorStop(1, rgba(BONE_SH));
	g.fillStyle = gr; g.fill(p);
	g.restore();
}
// A skull in profile facing right; kind adds tusks or antlers.
function drawSkull(g, x, y, size, kind, rot = 0, alpha = 1) {
	g.save(); g.translate(x, y); g.rotate(rot); g.globalAlpha *= alpha;
	const s = size, p = new Path2D();
	p.ellipse(-s * .12, -s * .05, s * .38, s * .32, 0, 0, 6.283);
	p.moveTo(s * .05, -s * .26); p.quadraticCurveTo(s * .5, -s * .2, s * .62, s * .02); p.lineTo(s * .6, s * .14);
	p.quadraticCurveTo(s * .3, s * .2, s * .02, s * .24); p.closePath();
	if (kind === 'stag') {
		g.lineCap = 'round';
		for (const [lw, col] of [[s * .16, BONE_LINE], [s * .09, rgba([214, 196, 160])]]) {
			g.lineWidth = lw; g.strokeStyle = col; g.beginPath();
			g.moveTo(-s * .2, -s * .3); g.quadraticCurveTo(-s * .5, -s * .8, -s * .2, -s * 1.15);
			g.moveTo(-s * .36, -s * .62); g.lineTo(-s * .62, -s * .78);
			g.moveTo(-s * .3, -s * .9); g.lineTo(-s * .05, -s * 1.02);
			g.stroke();
		}
	}
	g.lineWidth = Math.max(1, s * .1); g.strokeStyle = BONE_LINE; g.stroke(p);
	const gr = g.createLinearGradient(0, -s * .4, 0, s * .3);
	gr.addColorStop(0, rgba([250, 244, 226])); gr.addColorStop(1, rgba(BONE_SH));
	g.fillStyle = gr; g.fill(p);
	g.fillStyle = 'rgba(40,24,14,.9)';
	g.beginPath(); g.ellipse(-s * .04, -s * .08, s * .11, s * .09, 0, 0, 6.283); g.fill();
	g.beginPath(); g.ellipse(s * .5, s * .02, s * .04, s * .05, 0, 0, 6.283); g.fill();
	g.strokeStyle = 'rgba(40,24,14,.8)'; g.lineWidth = Math.max(.6, s * .04); g.beginPath();
	for (let i = 0; i < 4; i++) { const tx = s * (.12 + i * .1); g.moveTo(tx, s * .12); g.lineTo(tx, s * .21); }
	g.stroke();
	if (kind === 'boar') {
		g.lineCap = 'round'; g.lineWidth = s * .12; g.strokeStyle = BONE_LINE;
		g.beginPath(); g.moveTo(s * .38, s * .15); g.quadraticCurveTo(s * .55, s * .1, s * .5, -s * .14); g.stroke();
		g.lineWidth = s * .07; g.strokeStyle = '#fbf6e8'; g.stroke();
	}
	g.restore();
}

// The skinning knife: tip at (x, y), blade running up the angle, edge on the lower side.
function drawKnife(g, x, y, H, ang, alpha = 1, bloody = .7) {
	const L = H * 1.05, bw = H * .27, gw = bw * .32, hl = H * .78;
	g.save(); g.globalAlpha *= alpha; g.translate(x, y); g.rotate(ang);
	const blade = new Path2D();
	blade.moveTo(0, 0); blade.quadraticCurveTo(L * .35, -bw * .62, L, -bw * .5);
	blade.lineTo(L, bw * .5); blade.quadraticCurveTo(L * .3, bw * .8, 0, 0); blade.closePath();
	// drop shadow under the whole knife
	g.save(); g.translate(H * .05, H * .09); g.fillStyle = 'rgba(0,0,0,.35)'; g.fill(blade);
	g.fillRect(L, -bw * .5, gw + hl, bw); g.restore();
	// handle: dark wood with leather wraps and a brass pommel
	const hg = g.createLinearGradient(0, -bw * .5, 0, bw * .5);
	hg.addColorStop(0, '#9a6338'); hg.addColorStop(.4, '#6e3f1e'); hg.addColorStop(1, '#3a1e0c');
	g.fillStyle = hg; g.strokeStyle = 'rgba(20,10,4,.95)'; g.lineWidth = Math.max(.8, H * .03);
	roundRectPath(g, L + gw * .8, -bw * .46, hl, bw * .92, bw * .3); g.fill(); g.stroke();
	g.strokeStyle = 'rgba(30,14,6,.85)'; g.lineWidth = Math.max(.8, H * .045); g.beginPath();
	for (let i = 1; i <= 3; i++) { const hx = L + gw + hl * (.2 + i * .17); g.moveTo(hx, -bw * .45); g.lineTo(hx - bw * .12, bw * .45); }
	g.stroke();
	const pg = g.createRadialGradient(L + gw + hl - bw * .1, -bw * .15, 0, L + gw + hl, 0, bw * .5);
	pg.addColorStop(0, '#fbe8a8'); pg.addColorStop(1, '#8a6520');
	g.fillStyle = pg; g.beginPath(); g.arc(L + gw * .8 + hl, 0, bw * .42, 0, 6.283); g.fill();
	g.strokeStyle = 'rgba(20,10,4,.95)'; g.lineWidth = Math.max(.8, H * .03); g.stroke();
	// guard
	const gg = g.createLinearGradient(0, -bw * .8, 0, bw * .8);
	gg.addColorStop(0, '#f2d58a'); gg.addColorStop(.5, '#b08a3a'); gg.addColorStop(1, '#5e4214');
	g.fillStyle = gg; roundRectPath(g, L - gw * .1, -bw * .78, gw, bw * 1.56, gw * .4); g.fill(); g.stroke();
	// blade: polished steel, a bright bevel along the edge, blood on the tip
	const bg = g.createLinearGradient(0, -bw * .55, 0, bw * .6);
	bg.addColorStop(0, '#f6f9fc'); bg.addColorStop(.42, '#c2ccd6'); bg.addColorStop(.58, '#7d8995'); bg.addColorStop(.85, '#aeb8c2'); bg.addColorStop(1, '#eef3f7');
	g.fillStyle = bg; g.fill(blade);
	if (bloody > 0) {
		g.save(); g.clip(blade);
		const rg = g.createLinearGradient(0, 0, L * .55, 0);
		rg.addColorStop(0, rgba([120, 8, 10], bloody)); rg.addColorStop(1, rgba([120, 8, 10], 0));
		g.fillStyle = rg; g.fillRect(0, -bw, L * .55, bw * 2);
		g.restore();
	}
	g.strokeStyle = 'rgba(16,20,26,.95)'; g.lineWidth = Math.max(.8, H * .03); g.stroke(blade);
	g.strokeStyle = 'rgba(255,255,255,.75)'; g.lineWidth = Math.max(.5, H * .015);
	g.beginPath(); g.moveTo(L * .08, -bw * .08); g.quadraticCurveTo(L * .4, -bw * .4, L * .92, -bw * .3); g.stroke();
	g.restore();
}

function bleed(s, x, y, rate, spread = 1) {
	const H = s.H;
	s.dropAcc = (s.dropAcc || 0) + s.dt * rate;
	while (s.dropAcc >= 1) {
		s.dropAcc--;
		s.parts.emit({ x, y, vx: -H * rand(.3, 2.2) * spread, vy: -H * rand(.6, 2.6), ay: H * 14, life: rand(.5, .9),
			size: H * rand(.03, .06), kind: Math.random() < .7 ? 'drop' : 'dot', color: pick([BLOOD, BLOOD_L, [130, 10, 14]]) });
	}
}

// ---------------------------------------------------------------- A: the hide splits open
CONCEPTS.push({
	group: 'Skinning', id: 'skin-a', letter: 'A', name: 'Open the hide',
	desc: 'The bar is the hide; the knife splits it open, showing ribs and blood behind', spell: 'Skinning', padX: 1.15, flash: [255, 190, 170],
	init(s) {
		const { W, H } = s;
		s.pelt = pick(PELTS);
		s.fur = furStrokes(-H * .2, W + H * .2, 0, H, 140, H);
		s.stripes = s.pelt.stripes ? stripePath(W, H) : null;
		s.nT = noise1(); s.nB = noise1();
		s.spots = [];
		for (let x = H * rand(.3, .6); x < W; x += H * rand(.3, .75)) s.spots.push(makeSpot(x, H * (.5 + rand(-.26, .26)), H * rand(.05, .11)));
		s.ribStep = H * rand(.42, .5); s.ribPhase = rand(0, s.ribStep);
		s.sinew = new Path2D();
		for (let x = 0; x < W; x += H * rand(.2, .5)) { const y = H * rand(.2, .8); s.sinew.moveTo(x, y); s.sinew.quadraticCurveTo(x + H * .3, y + H * rand(-.1, .1), x + H * rand(.5, .9), y + H * rand(-.08, .08)); }
	},
	draw(g, s) {
		const { W, H, t } = s, mid = H * .5, maxGap = H * .37, open = H * 1.5;
		const saw = s.casting ? Math.sin(t * 15) * H * .05 : 0, kx = s.fill + saw;
		const gapAt = (x, n) => { const d = kx - x; if (d <= 0) return 0; const k = easeOut(clamp(d / open)); return k * (maxGap + n(x / H * 1.4) * H * .035); };
		g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
		drawFur(g, 0, 0, W, H, s.pelt, s.fur, s.stripes, H);
		if (kx > 1) {
			const top = [], bot = [];
			for (let x = 0; x < kx; x += 2) { top.push([x, mid - gapAt(x, s.nT)]); bot.push([x, mid + gapAt(x, s.nB)]); }
			const lens = new Path2D(); lens.moveTo(0, top[0][1]);
			for (const [x, y] of top) lens.lineTo(x, y);
			lens.lineTo(kx, mid);
			for (let i = bot.length - 1; i >= 0; i--) lens.lineTo(bot[i][0], bot[i][1]);
			lens.closePath();
			g.save(); g.clip(lens);
			const fg = g.createLinearGradient(0, 0, 0, H);
			fg.addColorStop(0, '#2a0405'); fg.addColorStop(.5, '#6e1416'); fg.addColorStop(1, '#2a0405');
			g.fillStyle = fg; g.fillRect(0, 0, kx + 2, H);
			g.strokeStyle = 'rgba(200,90,80,.22)'; g.lineWidth = Math.max(.6, H * .025); g.stroke(s.sinew);
			// spine and ribs, dimmed a little so the spell name stays readable
			g.lineCap = 'round';
			const ribs = new Path2D();
			for (let x = s.ribPhase; x < kx + s.ribStep; x += s.ribStep) {
				for (const sy of [-1, 1]) { ribs.moveTo(x, mid); ribs.quadraticCurveTo(x + H * .06, mid + sy * maxGap * .75, x - H * .16, mid + sy * maxGap * 1.15); }
			}
			g.strokeStyle = BONE_LINE; g.lineWidth = H * .085; g.stroke(ribs);
			g.strokeStyle = rgba([206, 194, 166]); g.lineWidth = H * .052; g.stroke(ribs);
			g.strokeStyle = 'rgba(255,250,235,.5)'; g.lineWidth = H * .016; g.stroke(ribs);
			g.strokeStyle = BONE_LINE; g.lineWidth = H * .13; g.beginPath(); g.moveTo(-2, mid); g.lineTo(kx, mid); g.stroke();
			g.strokeStyle = rgba([214, 202, 172]); g.lineWidth = H * .09; g.stroke();
			for (let x = s.ribPhase; x < kx; x += s.ribStep) {
				g.fillStyle = BONE_LINE; g.beginPath(); g.ellipse(x, mid, H * .075, H * .085, 0, 0, 6.283); g.fill();
				g.fillStyle = rgba([226, 214, 186]); g.beginPath(); g.ellipse(x, mid, H * .05, H * .06, 0, 0, 6.283); g.fill();
			}
			drawSpots(g, s.spots, kx - H * .2, t, .9);
			// shadow under the flaps
			g.strokeStyle = 'rgba(0,0,0,.6)'; g.lineWidth = H * .16; g.stroke(lens);
			g.restore();
			// the flap edges: the pale underside of the hide curling back
			for (const [edge, sy] of [[top, -1], [bot, 1]]) {
				g.beginPath(); edge.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y)); g.lineTo(kx, mid);
				g.strokeStyle = 'rgba(30,8,6,.9)'; g.lineWidth = Math.max(1.4, H * .085); g.stroke();
				g.strokeStyle = '#d9b09a'; g.lineWidth = Math.max(.8, H * .045); g.stroke();
			}
		}
		g.restore();
		// the head past the bar's end; it turns to a skull when the knife gets there
		const hx = W + H * .22, sk = clamp((kx - (W - H * .3)) / (H * .3));
		if (sk < 1) {
			g.save(); g.globalAlpha = 1 - sk;
			const p = new Path2D(), sz = H;
			p.ellipse(hx - sz * .05, mid, sz * .36, sz * .33, 0, 0, 6.283);
			p.ellipse(hx + sz * .3, mid + sz * .07, sz * .27, sz * .17, 0, 0, 6.283);
			p.moveTo(hx - sz * .15, mid - sz * .22); p.lineTo(hx - sz * .3, mid - sz * .6); p.lineTo(hx + sz * .08, mid - sz * .3); p.closePath();
			g.lineWidth = Math.max(1.2, H * .08); g.strokeStyle = 'rgba(14,8,4,.95)'; g.stroke(p);
			const hg = g.createLinearGradient(0, mid - sz * .4, 0, mid + sz * .3);
			hg.addColorStop(0, rgba(s.pelt.dark)); hg.addColorStop(.5, rgba(s.pelt.base)); hg.addColorStop(1, rgba(s.pelt.light));
			g.fillStyle = hg; g.fill(p);
			g.fillStyle = '#1a0e08'; g.beginPath(); g.arc(hx + sz * .54, mid + sz * .04, sz * .065, 0, 6.283); g.fill();
			g.strokeStyle = '#1a0e08'; g.lineWidth = Math.max(.8, H * .04); g.lineCap = 'round';   // a dead X eye
			const ex = hx + sz * .08, ey = mid - sz * .05, e = sz * .06;
			g.beginPath(); g.moveTo(ex - e, ey - e); g.lineTo(ex + e, ey + e); g.moveTo(ex + e, ey - e); g.lineTo(ex - e, ey + e); g.stroke();
			g.restore();
		}
		if (sk > 0) drawSkull(g, hx + H * .05, mid + H * .02, H * .75, '', 0, sk);
		// blood flying off the blade, then the knife on top
		if (s.casting && kx > 2) bleed(s, kx, mid, 26);
		s.parts.update(s.dt); s.parts.draw(g);
		const lift = s.done ? easeIn(clamp(s.doneT / .5)) : 0;
		drawKnife(g, kx + lift * H * .6, mid + H * .03 - lift * H * 1.2, H, -.95 + Math.sin(t * 8) * .06, 1 - lift);
	},
});

// ---------------------------------------------------------------- B: carcasses break into bones
const ANIMALS = {
	boar: { body: [92, 70, 58], belly: [170, 128, 112], dark: [40, 28, 22] },
	wolf: { body: [118, 118, 126], belly: [196, 192, 186], dark: [48, 48, 56] },
	stag: { body: [150, 100, 56], belly: [232, 214, 186], dark: [70, 42, 18] },
};
function drawCarcass(g, c, H, alpha, cutTo) {
	const A = ANIMALS[c.type], rx = c.rx, ry = c.ry, ol = 'rgba(16,10,6,.95)', lw = Math.max(1, H * .06);
	g.save(); g.translate(c.cx + c.shake, c.cy); g.globalAlpha *= alpha; g.lineCap = 'round'; g.lineJoin = 'round';
	// legs stuck in the air (it's on its back)
	for (const L of c.legs) {
		// thigh then shin, bent at the knee
		const kx = (L.x + L.tx) / 2 + L.knee, ky = (-ry * .5 + L.ty) / 2;
		g.strokeStyle = ol; g.lineWidth = H * .2; g.beginPath(); g.moveTo(L.x, -ry * .4); g.lineTo(kx, ky); g.stroke();
		g.lineWidth = H * .13; g.beginPath(); g.moveTo(kx, ky); g.lineTo(L.tx, L.ty); g.stroke();
		g.strokeStyle = rgba(A.body); g.lineWidth = H * .145; g.beginPath(); g.moveTo(L.x, -ry * .4); g.lineTo(kx, ky); g.stroke();
		g.lineWidth = H * .08; g.beginPath(); g.moveTo(kx, ky); g.lineTo(L.tx, L.ty); g.stroke();
		g.strokeStyle = rgba(A.belly, .45); g.lineWidth = H * .03; g.beginPath(); g.moveTo(L.x - H * .03, -ry * .4); g.lineTo(kx - H * .03, ky); g.stroke();
		g.fillStyle = rgba(A.dark); g.strokeStyle = ol; g.lineWidth = lw * .6;
		if (c.type === 'wolf') { g.beginPath(); g.arc(L.tx, L.ty, H * .07, 0, 6.283); g.fill(); g.stroke(); }
		else { g.beginPath(); g.moveTo(L.tx - H * .055, L.ty + H * .02); g.lineTo(L.tx - H * .045, L.ty - H * .09); g.lineTo(L.tx + H * .045, L.ty - H * .09); g.lineTo(L.tx + H * .055, L.ty + H * .02); g.closePath(); g.fill(); g.stroke(); }
	}
	// tail
	if (c.type === 'wolf') {
		g.fillStyle = rgba(A.body); g.strokeStyle = ol; g.lineWidth = lw;
		g.beginPath(); g.moveTo(-rx * .9, -ry * .1); g.quadraticCurveTo(-rx * 1.5, -ry * .2, -rx * 1.55, ry * .5); g.quadraticCurveTo(-rx * 1.3, ry * .2, -rx * .9, ry * .3); g.closePath(); g.fill(); g.stroke();
	}
	// head, facing right, lying on its side
	const hx = rx * .95, hy = ry * .1;
	const head = new Path2D();
	if (c.type === 'boar') { head.ellipse(hx, hy, H * .3, H * .23, .15, 0, 6.283); head.ellipse(hx + H * .3, hy + H * .06, H * .16, H * .14, 0, 0, 6.283); }
	else if (c.type === 'wolf') { head.ellipse(hx, hy, H * .26, H * .21, 0, 0, 6.283); head.moveTo(hx + H * .1, hy - H * .14); head.quadraticCurveTo(hx + H * .55, hy - H * .02, hx + H * .52, hy + H * .1); head.quadraticCurveTo(hx + H * .3, hy + H * .2, hx + H * .05, hy + H * .18); head.closePath(); }
	else { head.ellipse(hx, hy, H * .22, H * .19, 0, 0, 6.283); head.moveTo(hx + H * .05, hy - H * .14); head.quadraticCurveTo(hx + H * .5, hy - H * .05, hx + H * .48, hy + H * .08); head.quadraticCurveTo(hx + H * .3, hy + H * .16, hx + H * .02, hy + H * .16); head.closePath(); }
	if (c.type === 'stag') {
		g.strokeStyle = ol; g.lineWidth = H * .1; const ant = new Path2D();
		ant.moveTo(hx - H * .05, hy - H * .15); ant.quadraticCurveTo(hx - H * .35, hy - H * .5, hx - H * .1, hy - H * .95);
		ant.moveTo(hx - H * .22, hy - H * .45); ant.lineTo(hx - H * .45, hy - H * .62);
		ant.moveTo(hx - H * .18, hy - H * .72); ant.lineTo(hx + H * .05, hy - H * .82);
		g.stroke(ant); g.strokeStyle = '#d8c39a'; g.lineWidth = H * .055; g.stroke(ant);
	}
	// ear
	g.fillStyle = rgba(A.body); g.strokeStyle = ol; g.lineWidth = lw;
	g.beginPath(); g.moveTo(hx - H * .12, hy - H * .12); g.lineTo(hx - H * .3, hy - H * (c.type === 'wolf' ? .45 : .32)); g.lineTo(hx + H * .02, hy - H * .18); g.closePath(); g.fill(); g.stroke();
	// body
	const body = new Path2D(); body.ellipse(0, 0, rx, ry, 0, 0, 6.283);
	g.lineWidth = lw; g.strokeStyle = ol; g.stroke(body); g.stroke(head);
	const bg = g.createLinearGradient(0, -ry, 0, ry);
	bg.addColorStop(0, rgba(A.belly)); bg.addColorStop(.35, rgba(mix(A.belly, A.body, .6))); bg.addColorStop(.6, rgba(A.body)); bg.addColorStop(1, rgba(A.dark));
	g.fillStyle = bg; g.fill(body);
	g.save(); g.clip(body); g.lineWidth = Math.max(.6, H * .03); g.strokeStyle = rgba(A.dark, .5); g.stroke(c.fur); g.restore();
	const hg = g.createLinearGradient(0, hy - H * .25, 0, hy + H * .25);
	hg.addColorStop(0, rgba(mix(A.belly, A.body, .5))); hg.addColorStop(1, rgba(A.body));
	g.fillStyle = hg; g.fill(head);
	if (c.type === 'boar') {
		g.fillStyle = '#c99a8e'; g.beginPath(); g.ellipse(hx + H * .44, hy + H * .06, H * .05, H * .1, 0, 0, 6.283); g.fill(); g.stroke();
		g.strokeStyle = ol; g.lineWidth = H * .08; g.beginPath(); g.moveTo(hx + H * .3, hy + H * .14); g.quadraticCurveTo(hx + H * .42, hy + H * .12, hx + H * .4, hy - H * .06); g.stroke();
		g.strokeStyle = '#f6efdc'; g.lineWidth = H * .045; g.stroke();
	} else {
		g.fillStyle = '#1a0e08'; g.beginPath(); g.arc(hx + H * .5, hy + H * .04, H * .045, 0, 6.283); g.fill();
		if (c.type === 'wolf') { g.fillStyle = '#d0606a'; g.strokeStyle = ol; g.lineWidth = lw * .6; g.beginPath(); g.ellipse(hx + H * .36, hy + H * .2, H * .05, H * .09, -.3, 0, 6.283); g.fill(); g.stroke(); }
	}
	g.strokeStyle = '#140a04'; g.lineWidth = Math.max(.8, H * .04);
	const ex = hx + H * .02, ey = hy - H * .04, e = H * .05;
	g.beginPath(); g.moveTo(ex - e, ey - e); g.lineTo(ex + e, ey + e); g.moveTo(ex + e, ey - e); g.lineTo(ex - e, ey + e); g.stroke();
	// the cut along the belly so far
	if (cutTo > -rx) {
		const x1 = Math.min(cutTo, rx * .95);
		g.beginPath();
		for (let x = -rx * .92; x <= x1; x += 2) { const y = -ry * Math.sqrt(1 - (x / rx) ** 2) * .82; x === -rx * .92 ? g.moveTo(x, y) : g.lineTo(x, y); }
		g.strokeStyle = '#2a0204'; g.lineWidth = H * .09; g.stroke();
		g.strokeStyle = '#a3141a'; g.lineWidth = H * .045; g.stroke();
	}
	g.restore();
}
function bellyY(c, x) { const dx = (x - c.cx) / c.rx; return c.cy - c.ry * Math.sqrt(Math.max(0, 1 - dx * dx)) * .82; }

CONCEPTS.push({
	group: 'Skinning', id: 'skin-b', letter: 'B', name: 'Carcass line',
	desc: 'Boar, wolf and stag on their backs; each one the knife finishes bursts into bones', spell: 'Skinning', padTop: 1.5, padBottom: .9, flash: [255, 190, 170],
	init(s) {
		const { W, H } = s, n = W / H > 9 ? 3 : 2, seg = W / n;
		const types = ['boar', 'wolf', 'stag'].sort(() => Math.random() - .5);
		s.corpses = [];
		for (let i = 0; i < n; i++) {
			const rx = Math.min(seg * .3, H * 1.15) * rand(.88, 1), ry = H * .3;
			const c = { type: types[i % 3], cx: seg * (i + .5) + rand(-.08, .08) * seg - H * .2, cy: H * .58, rx, ry, shake: 0, broken: false, legs: [], fur: new Path2D() };
			for (const f of [-.6, -.34, .22, .48]) c.legs.push({ x: f * rx, tx: f * rx + Math.sign(f) * H * rand(.06, .16), ty: -ry - H * rand(.48, .64), knee: Math.sign(f) * H * rand(.06, .12) });
			for (let k = 0; k < rx * ry / (H * H) * 60; k++) { const x = rand(-rx, rx), y = rand(-ry * .1, ry); c.fur.moveTo(x, y); c.fur.lineTo(x - H * .1, y + H * rand(-.03, .05)); }
			s.corpses.push(c);
		}
		s.bones = []; s.stains = []; s.ky = H * .55;
		s.tufts = new Path2D();
		for (let x = 0; x < W; x += H * rand(.15, .4)) { for (let k = 0; k < 3; k++) { s.tufts.moveTo(x + k * H * .04, H); s.tufts.quadraticCurveTo(x + k * H * .05, H * .85, x + k * H * .05 + H * rand(-.08, .08), H * rand(.6, .78)); } }
	},
	draw(g, s) {
		const { W, H, t, dt } = s, f = s.fill, floor = H * .84;
		// ground: dusk grass; the cut part soaks red
		g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
		const gg = g.createLinearGradient(0, 0, 0, H);
		gg.addColorStop(0, '#2c3448'); gg.addColorStop(.55, '#3a3a2c'); gg.addColorStop(1, '#22281a');
		g.fillStyle = gg; g.fillRect(0, 0, W, H);
		g.strokeStyle = 'rgba(70,92,48,.8)'; g.lineWidth = Math.max(.7, H * .035); g.lineCap = 'round'; g.stroke(s.tufts);
		const rg = g.createLinearGradient(0, 0, Math.max(1, f), 0);
		rg.addColorStop(0, 'rgba(110,8,10,.45)'); rg.addColorStop(.85, 'rgba(110,8,10,.35)'); rg.addColorStop(1, 'rgba(110,8,10,0)');
		g.fillStyle = rg; g.fillRect(0, 0, f, H);
		for (const st of s.stains) {
			const k = easeOut(clamp((t - st.born) / .5));
			g.fillStyle = rgba(BLOOD, .9); g.beginPath(); g.ellipse(st.x, st.y, st.rx * k, st.ry * k, 0, 0, 6.283); g.fill();
			g.fillStyle = rgba(BLOOD_L, .5); g.beginPath(); g.ellipse(st.x - st.rx * .2, st.y - st.ry * .2, st.rx * .45 * k, st.ry * .4 * k, 0, 0, 6.283); g.fill();
		}
		g.restore();
		// carcasses
		let target = H * .5, inside = null;
		for (const c of s.corpses) {
			if (!c.broken && f >= c.cx + c.rx * .85) {
				c.broken = true; c.breakT = t;
				for (let k = 0; k < 28; k++) s.parts.emit({ x: c.cx + rand(-c.rx, c.rx) * .7, y: c.cy - c.ry * rand(0, .8), vx: H * rand(-2.5, 2.5), vy: -H * rand(1, 4), ay: H * 14, life: rand(.5, 1), size: H * rand(.03, .07), kind: 'drop', color: pick([BLOOD, BLOOD_L]) });
				s.bones.push({ skull: true, type: c.type, x: c.cx + c.rx * .8, y: c.cy, vx: H * rand(.5, 2), vy: -H * rand(2.5, 3.5), rot: 0, vr: rand(-4, 4), size: H * .62 });
				for (let k = 0, m = 4 + Math.floor(Math.random() * 3); k < m; k++)
					s.bones.push({ x: c.cx + rand(-c.rx, c.rx) * .7, y: c.cy, vx: H * rand(-2.2, 2.2), vy: -H * rand(2, 4.2), rot: rand(0, 6.283), vr: rand(-14, 14), len: H * rand(.35, .6), w: H * rand(.13, .17) });
				for (let k = 0; k < 4; k++) s.stains.push({ x: c.cx + rand(-c.rx, c.rx) * .9, y: floor + H * rand(-.08, .06), rx: H * rand(.15, .4), ry: H * rand(.06, .1), born: t + k * .06 });
			}
			if (!c.broken && f > c.cx - c.rx * .92) { inside = c; target = bellyY(c, f); }
			c.shake = inside === c && s.casting ? Math.sin(t * 40) * H * .015 : 0;
			const a = c.broken ? 1 - clamp((t - c.breakT) / .12) : 1;
			if (a > 0) {
				g.save();
				if (c.broken) { const k = 1 + (t - c.breakT) * 1.5; g.translate(c.cx, c.cy); g.scale(k, k); g.translate(-c.cx, -c.cy); }
				drawCarcass(g, c, H, a, f - c.cx);
				g.restore();
			}
		}
		// bones tumble and settle on the ground
		for (const b of s.bones) {
			if (!b.rest) {
				b.vy += H * 16 * dt; b.x += b.vx * dt; b.y += b.vy * dt; b.rot += b.vr * dt;
				const fl = floor - (b.skull ? H * .05 : H * .02);
				if (b.y > fl) {
					b.y = fl; b.vy *= -.32; b.vx *= .55; b.vr *= .4;
					if (Math.abs(b.vy) < H * .8) { b.vy = 0; b.rest = true; }
				}
				if (b.x < H * .2 || b.x > W - H * .2) b.vx *= -.5, b.x = clamp(b.x, H * .2, W - H * .2);
			} else {
				const goal = b.skull ? 0 : Math.round(b.rot / Math.PI) * Math.PI;
				b.rot += (goal - b.rot) * Math.min(1, dt * 10); b.vx *= Math.max(0, 1 - dt * 8); b.x += b.vx * dt;
			}
			if (b.skull) drawSkull(g, b.x, b.y - H * .08, b.size, b.type, b.rest ? b.rot * .3 : b.rot);
			else drawBone(g, b.x, b.y, b.rot, b.len, b.w);
		}
		// knife: rides the bellies, hops between carcasses
		s.ky += (target - s.ky) * Math.min(1, dt * 14);
		if (s.casting && inside) bleed(s, f, s.ky, 30);
		s.parts.update(dt); s.parts.draw(g);
		const lift = s.done ? easeIn(clamp(s.doneT / .5)) : 0, saw = s.casting ? Math.sin(t * 14) * H * .05 : 0;
		drawKnife(g, f + saw + lift * H * .6, s.ky - lift * H * 1.2, H, -.9 + Math.sin(t * 8) * .06 + (inside ? 0 : -.15), 1 - lift);
	},
});

// ---------------------------------------------------------------- C: the pelt rolls back
CONCEPTS.push({
	group: 'Skinning', id: 'skin-c', letter: 'C', name: 'Pelt roll',
	desc: 'The pelt peels back into a growing roll behind the knife; bones tumble out the bottom', spell: 'Skinning', padTop: 1.4, padBottom: 1.6, flash: [255, 200, 175],
	init(s) {
		const { W, H } = s;
		s.pelt = pick(PELTS);
		s.fur = furStrokes(-H * .2, W + H * .2, 0, H, 140, H);
		s.stripes = s.pelt.stripes ? stripePath(W, H) : null;
		s.rollFur = furStrokes(-H, H, -H * .1, H * 1.1, 40, H);
		s.spots = [];
		for (let x = H * rand(.2, .5); x < W; x += H * rand(.28, .6)) s.spots.push(makeSpot(x, H * rand(.15, .85), H * rand(.04, .1)));
		s.marble = new Path2D();
		for (let x = 0; x < W; x += H * rand(.3, .7)) { const y = H * rand(.1, .9); s.marble.moveTo(x, y); s.marble.bezierCurveTo(x + H * .2, y - H * .15, x + H * .4, y + H * .15, x + H * rand(.6, 1), y + H * rand(-.1, .1)); }
		s.tumble = []; s.boneT = rand(.3, .6);
	},
	draw(g, s) {
		const { W, H, t, dt } = s, f = s.fill, mid = H * .5;
		const r = H * (.2 + .16 * s.p), xc = f - r * .9;
		g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
		drawFur(g, 0, 0, W, H, s.pelt, s.fur, s.stripes, H);
		if (xc > 0) {
			// the raw underside, marbled, dotted with blood
			g.save(); g.beginPath(); g.rect(0, 0, xc, H); g.clip();
			const lg = g.createLinearGradient(0, 0, 0, H);
			lg.addColorStop(0, '#6a2a22'); lg.addColorStop(.5, '#a85848'); lg.addColorStop(1, '#5a2018');
			g.fillStyle = lg; g.fillRect(0, 0, xc, H);
			g.strokeStyle = 'rgba(240,206,180,.35)'; g.lineWidth = Math.max(.8, H * .04); g.stroke(s.marble);
			g.strokeStyle = 'rgba(240,206,180,.2)'; g.lineWidth = Math.max(1.5, H * .1); g.stroke(s.marble);
			drawSpots(g, s.spots, xc - r * .5, t);
			const sg = g.createLinearGradient(xc - H * .6, 0, xc, 0);   // the roll's shadow
			sg.addColorStop(0, 'rgba(0,0,0,0)'); sg.addColorStop(1, 'rgba(0,0,0,.55)');
			g.fillStyle = sg; g.fillRect(xc - H * .6, 0, H * .6, H);
			const vg = g.createLinearGradient(0, 0, 0, H);
			vg.addColorStop(0, 'rgba(0,0,0,.4)'); vg.addColorStop(.3, 'rgba(0,0,0,0)'); vg.addColorStop(.7, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.4)');
			g.fillStyle = vg; g.fillRect(0, 0, xc, H);
			g.restore();
		}
		g.restore();
		// blood dripping off the bottom edge of the raw part
		if (s.casting && xc > H * .3 && Math.random() < dt * 7)
			s.parts.emit({ x: rand(0, xc), y: H, vx: 0, vy: H * rand(.2, .6), ay: H * 10, life: rand(.4, .7), size: H * rand(.03, .05), kind: 'drop', color: BLOOD });
		// bones tumble out of the roll and off the bottom
		s.boneT -= dt;
		if (s.casting && s.boneT <= 0 && f > H) {
			s.boneT = rand(.4, .85);
			s.tumble.push({ x: xc, y: H * .7, vx: -H * rand(.4, 2), vy: -H * rand(.8, 2.2), rot: rand(0, 6.283), vr: rand(-9, 9), len: H * rand(.3, .5), w: H * rand(.11, .15), age: 0, skull: Math.random() < .15 });
		}
		for (const b of s.tumble) { b.age += dt; b.vy += H * 12 * dt; b.x += b.vx * dt; b.y += b.vy * dt; b.rot += b.vr * dt; }
		s.tumble = s.tumble.filter(b => b.age < 1.3);
		// the roll: a cylinder of pelt, fur outward, with the curled end showing on top
		if (f > 1) {
			const y0 = -H * .08, y1 = H * 1.08;
			g.save(); g.beginPath(); g.rect(xc - r, y0, r * 2, y1 - y0); g.clip();
			drawFur(g, xc - r, y0, r * 2, y1 - y0, s.pelt, [], null, H);
			g.translate(xc, 0); g.strokeStyle = rgba(s.pelt.stroke[1], .6); g.lineWidth = Math.max(.7, H * .035); g.stroke(s.rollFur[0]);
			g.strokeStyle = rgba(s.pelt.stroke[2], .5); g.stroke(s.rollFur[1]); g.translate(-xc, 0);
			const cg = g.createLinearGradient(xc - r, 0, xc + r, 0);
			cg.addColorStop(0, 'rgba(0,0,0,.65)'); cg.addColorStop(.35, 'rgba(255,240,210,.18)'); cg.addColorStop(.6, 'rgba(0,0,0,0)'); cg.addColorStop(1, 'rgba(0,0,0,.6)');
			g.fillStyle = cg; g.fillRect(xc - r, y0, r * 2, y1 - y0);
			g.restore();
			g.strokeStyle = 'rgba(14,8,4,.9)'; g.lineWidth = Math.max(1, H * .05); g.strokeRect(xc - r, y0, r * 2, y1 - y0);
			for (const cy of [y1, y0]) {
				g.beginPath(); g.ellipse(xc, cy, r, r * .32, 0, 0, 6.283);
				g.fillStyle = cy === y0 ? '#b8705c' : '#7a3a2e'; g.fill(); g.stroke();
				if (cy === y0) {   // the spiral of the rolled hide
					g.beginPath();
					for (let a = 0; a < 6.283 * 2.2; a += .2) { const rr = r * (1 - a / (6.283 * 2.6)); g.lineTo(xc + Math.cos(a) * rr, cy + Math.sin(a) * rr * .32); }
					g.strokeStyle = rgba(s.pelt.dark, .9); g.lineWidth = Math.max(.8, H * .035); g.stroke();
				}
			}
		}
		for (const b of s.tumble) {
			const a = 1 - clamp((b.age - .9) / .4);
			if (b.skull) drawSkull(g, b.x, b.y, H * .45, '', b.rot, a); else drawBone(g, b.x, b.y, b.rot, b.len, b.w, a);
		}
		s.parts.update(dt); s.parts.draw(g);
		// the knife slides under the pelt just ahead of the roll
		const lift = s.done ? easeIn(clamp(s.doneT / .5)) : 0, saw = s.casting ? Math.sin(t * 13) * H * .05 : 0;
		if (s.casting && f > 2) bleed(s, f + saw, mid + H * .15, 14, .6);
		drawKnife(g, f + saw + H * .05 + lift * H * .6, mid + H * .18 - lift * H * 1.2, H, -.55 + Math.sin(t * 8) * .05, 1 - lift, .5);
	},
});
})();
