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

// ---------------------------------------------------------------- C2: the pelt rolls back over marbled meat
// The flesh side is painted once per cast into its own canvas (it never changes, only how much of it shows),
// like a marbled ribeye: deep wine-red muscle laced with fine creamy fat, larger swirling fat seams that
// split it into regions, and a waxy, pink-tinged fat cap along the top and bottom. Blood splatter is
// flung off the cut as the knife passes and lands straddling the bar's top and bottom edges.
const FAT = [236, 214, 152];

// smooth 2-D value noise in -1..1, seeded per call
function noise2(seed = Math.random() * 1000) {
	const h = (i, j) => { const v = Math.sin((i * 127.1 + j * 311.7 + seed) * 1.13) * 43758.5453; return v - Math.floor(v); };
	return (x, y) => {
		const i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j;
		const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
		return lerp(lerp(h(i, j), h(i + 1, j), u), lerp(h(i, j + 1), h(i + 1, j + 1), u), v) * 2 - 1;
	};
}
function fbm(n, x, y, oct) { let s = 0, a = .5, f = 1; for (let o = 0; o < oct; o++) { s += a * n(x * f, y * f); a *= .5; f *= 2.1; } return s; }
const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };

function makeMarble(W, H) {
	const k = typeof dpr === 'number' ? dpr : 1, cv = document.createElement('canvas');
	const PW = Math.ceil(W * k), PH = Math.ceil(H * k);
	cv.width = PW; cv.height = PH;
	const g = cv.getContext('2d'), img = g.createImageData(PW, PH), d = img.data;
	const nW1 = noise2(), nW2 = noise2(), nSeam = noise2(), nSeam2 = noise2(), nLace = noise2(), nFleck = noise2();
	const nDens = noise2(), nTone = noise2(), nCap = noise2(), nCap2 = noise2(), nWax = noise2();
	const sc = 1 / (H * k);                       // noise units: one per bar height
	const capT = rand(.1, .17), capB = rand(.1, .17);
	const MEAT_D = [78, 6, 18], MEAT = [142, 18, 32], MEAT_L = [186, 44, 52];
	const FAT_C = [246, 232, 222], FAT_P = [232, 196, 186];
	for (let py = 0; py < PH; py++) {
		const y = py * sc;
		for (let px = 0; px < PW; px++) {
			const x = px * sc;
			// swirl: warp the coordinates so seams and lace curl around like a ribeye's eye
			const wx = x + .45 * fbm(nW1, x * .7, y * 1.1, 3), wy = y + .3 * fbm(nW2, x * .7 + 5, y * 1.1, 3);
			// fat cap along the top and bottom, with a wavy inner edge
			const top = capT + .06 * nCap(x * 1.6, 0) + .03 * nCap2(x * 5, 1);
			const bot = 1 - capB - .06 * nCap(x * 1.6, 7) - .03 * nCap2(x * 5, 9);
			const cap = Math.max(1 - smooth(top - .04, top + .03, y), smooth(bot - .03, bot + .04, y));
			// large seams of fat between muscle regions: soft, broad and uneven in width
			const seamW = .045 + .035 * nSeam2(wx * 2, wy * 2);
			const seam = 1 - smooth(seamW * .35, seamW, Math.abs(fbm(nSeam, wx * 1.1, wy * 1.6, 3)));
			// fine marbling, denser in some regions: irregular fat patches, a dense spray of specks, and a
			// broken web of thin fat threads that never closes into lines
			const dens = clamp(.5 + .6 * fbm(nDens, x * .8, y * 1.3, 2));
			const patch = smooth(.3 - .12 * dens, .4 - .12 * dens, fbm(nLace, wx * 4.5, wy * 6, 3));
			const speck = smooth(.26 - .2 * dens, .34 - .2 * dens, fbm(nFleck, wx * 17, wy * 21, 3));
			const web = (1 - smooth(.01, .045, Math.abs(fbm(nW2, wx * 8 + 11, wy * 10, 2)))) * smooth(.05, .3, fbm(nWax, wx * 14 + 3, wy * 14, 2));
			const fine = Math.max(patch * .95, speck * .9, web * .75) * (.35 + .65 * dens);
			// muscle: wine-red, darker in the deep middle of each region, lighter toward the fat
			const tone = clamp(.5 + .55 * fbm(nTone, wx * 2.2, wy * 2.6, 3) + .25 * seam);
			let mr = tone < .5 ? lerp(MEAT_D[0], MEAT[0], tone * 2) : lerp(MEAT[0], MEAT_L[0], (tone - .5) * 2);
			let mg = tone < .5 ? lerp(MEAT_D[1], MEAT[1], tone * 2) : lerp(MEAT[1], MEAT_L[1], (tone - .5) * 2);
			let mb = tone < .5 ? lerp(MEAT_D[2], MEAT[2], tone * 2) : lerp(MEAT[2], MEAT_L[2], (tone - .5) * 2);
			// fat: creamy white with a pink blush where it is thin, a little waxy variation
			const wax = .5 + .5 * nWax(x * 4, y * 4);
			let fr = lerp(FAT_C[0], FAT_P[0], wax * .7), fg = lerp(FAT_C[1], FAT_P[1], wax * .7), fb = lerp(FAT_C[2], FAT_P[2], wax * .7);
			// thin fat is translucent: the red shows through it
			const thin = Math.max(fine * .55, seam * .2);
			const fatW = Math.max(cap, seam * .95, fine * .88);
			const blush = (1 - cap) * thin;
			fr = lerp(fr, mr + 70, blush); fg = lerp(fg, mg + 60, blush); fb = lerp(fb, mb + 60, blush);
			let r = lerp(mr, fr, fatW), gg = lerp(mg, fg, fatW), b = lerp(mb, fb, fatW);
			// the cap meets the meat in a pink, slightly translucent band
			const band = smooth(.0, .5, cap) * (1 - smooth(.5, 1, cap));
			r = lerp(r, 214, band * .5); gg = lerp(gg, 132, band * .5); b = lerp(b, 132, band * .5);
			// soft shading: a little darker toward the bar's edges and in broad dips
			const sh = (1 - .18 * Math.pow(Math.abs(y - .5) * 2, 3)) * (.92 + .08 * nTone(x * 1.1 + 20, y * 1.1));
			const i = (py * PW + px) * 4;
			d[i] = clamp(r * sh, 0, 255); d[i + 1] = clamp(gg * sh, 0, 255); d[i + 2] = clamp(b * sh, 0, 255); d[i + 3] = 255;
		}
	}
	g.putImageData(img, 0, 0);
	return { cv };
}

// Blood splatter, painted once per mark into its own little canvas: a dense ragged core stretched along
// the throw, long thin streaks and tendrils flung ahead, scattered droplets. The fresh red and a darker
// dried copy are both kept, so the mark can darken as it dries. Local +x is the direction of the throw.
const SPLAT_RED = [224, 18, 26], SPLAT_EDGE = 'rgba(70,0,6,.9)', SPLAT_DRY = [120, 6, 14];
function makeSplat(H, size) {
	const k = typeof dpr === 'number' ? dpr : 1, R = H * size, pad = R * 1.8;
	const cw = Math.ceil((R * 3.6 + pad) * k), ch = Math.ceil((R * 2.4 + pad) * k);
	const ox = R * 1.0 + pad * .5, oy = R * 1.2 + pad * .5;   // where the core sits in the canvas
	const shape = [];
	// core: overlapping ragged blobs along the throw
	const nb = 5 + Math.floor(Math.random() * 5);
	for (let i = 0; i < nb; i++) {
		const t = rand(-.3, 1), pts = [], n = 10 + Math.floor(Math.random() * 6), rr = R * rand(.18, .38) * (1 - .35 * Math.max(0, t));
		for (let j = 0; j < n; j++) { const a = j / n * 6.283; pts.push([Math.cos(a) * rr * rand(1.1, 1.9), Math.sin(a) * rr * rand(.45, .8)]); }
		shape.push({ kind: 'blob', x: t * R * .9, y: rand(-.12, .12) * R, pts });
	}
	// streaks: tapered, slightly curved, mostly along the throw, a few fanning wide
	const ns = 4 + Math.floor(Math.random() * 6);
	for (let i = 0; i < ns; i++) {
		const a = (Math.random() < .75 ? rand(-.3, .3) : rand(-.9, .9)) + (Math.random() < .12 ? Math.PI : 0);
		const len = R * rand(.8, 2.1) * (Math.abs(a) > 2 ? .4 : 1), w = R * rand(.05, .12);
		shape.push({ kind: 'streak', x: rand(-.1, .6) * R, y: rand(-.15, .15) * R, a, len, w, bend: rand(-.25, .25), drop: Math.random() < .5 });
	}
	// droplets thrown ahead in a cone, and a few behind
	const nd = 14 + Math.floor(Math.random() * 18);
	for (let i = 0; i < nd; i++) {
		const back = Math.random() < .15, a = rand(-.55, .55) + (back ? Math.PI : 0), dd = R * (back ? rand(.4, .9) : rand(.6, 2.3));
		shape.push({ kind: 'dot', x: Math.cos(a) * dd + R * .3, y: Math.sin(a) * dd * .8, r: R * rand(.02, .075) * (dd > R * 1.6 ? .7 : 1), e: rand(1, 1.8), a });
	}
	const paint = color => {
		const cv = document.createElement('canvas'); cv.width = cw; cv.height = ch;
		const g = cv.getContext('2d');
		g.scale(k, k); g.translate(ox, oy);
		g.fillStyle = rgba(color); g.strokeStyle = rgba(color); g.lineCap = 'round';
		g.shadowColor = SPLAT_EDGE; g.shadowBlur = Math.max(1, R * .05) * k;
		for (const p of shape) {
			if (p.kind === 'blob') {
				g.beginPath(); p.pts.forEach(([x, y], j) => j ? g.lineTo(p.x + x, p.y + y) : g.moveTo(p.x + x, p.y + y)); g.closePath(); g.fill();
			} else if (p.kind === 'streak') {
				const steps = 8, ca = Math.cos(p.a), sa = Math.sin(p.a);
				for (let j = 0; j < steps; j++) {
					const u0 = j / steps, u1 = (j + 1) / steps, b0 = p.bend * u0 * u0 * p.len, b1 = p.bend * u1 * u1 * p.len;
					g.lineWidth = Math.max(.35, p.w * (1 - u0) * (1 - u0 * .3));
					g.beginPath();
					g.moveTo(p.x + ca * u0 * p.len - sa * b0, p.y + sa * u0 * p.len + ca * b0);
					g.lineTo(p.x + ca * u1 * p.len - sa * b1, p.y + sa * u1 * p.len + ca * b1);
					g.stroke();
				}
				if (p.drop) { const ex = p.x + ca * p.len * 1.08 - sa * p.bend * p.len, ey = p.y + sa * p.len * 1.08 + ca * p.bend * p.len; g.beginPath(); g.arc(ex, ey, Math.max(.5, p.w * .7), 0, 6.283); g.fill(); }
			} else {
				g.beginPath(); g.ellipse(p.x, p.y, p.r * p.e, p.r, p.a, 0, 6.283); g.fill();
			}
		}
		return cv;
	};
	return { fresh: paint(SPLAT_RED), dry: paint(SPLAT_DRY), cw: cw / k, ch: ch / k, ox, oy };
}

// ---------------------------------------------------------------- C2's painted pelt, roll and knife
// No hard outlines: the fur is thousands of layered strands (dark roots, light tips) painted once per cast;
// the roll is that fur wrapped round a soft-shaded cylinder whose end shows the hide's spiral; the knife is
// brushed steel with a ground bevel, a bolster and a wood or antler handle.
const PELTS_REAL = [
	{ root: [30, 19, 10], mid: [86, 57, 33], tip: [170, 132, 92], base: [58, 38, 21], sheen: [236, 206, 166] },     // brown bear
	{ root: [28, 28, 32], mid: [92, 90, 92], tip: [214, 210, 202], base: [58, 57, 61], sheen: [236, 236, 240] },    // grey wolf
	{ root: [64, 38, 14], mid: [146, 100, 48], tip: [230, 194, 134], base: [104, 68, 30], sheen: [252, 226, 178] },  // tawny cat
	{ root: [70, 22, 6], mid: [168, 74, 26], tip: [236, 168, 104], base: [124, 50, 16], sheen: [255, 214, 170] },   // red fox
	{ root: [120, 120, 126], mid: [196, 196, 200], tip: [246, 246, 248], base: [168, 168, 174], sheen: [255, 255, 255] }, // arctic white
	{ root: [8, 8, 10], mid: [30, 28, 30], tip: [86, 80, 76], base: [20, 19, 21], sheen: [170, 164, 160] },         // black bear
	{ root: [26, 22, 52], mid: [70, 62, 122], tip: [164, 150, 214], base: [48, 42, 92], sheen: [214, 206, 255] },    // nightsaber
	{ root: [40, 30, 22], mid: [96, 80, 62], tip: [170, 152, 126], base: [70, 58, 44], sheen: [220, 206, 182] },     // boar bristle
];
let peltTurn = Math.floor(Math.random() * PELTS_REAL.length);   // each cast takes the next pelt in turn
const KNIFE_BELLY = .22;   // how far the blade's curved edge bulges from its tip line, in bar heights (it rests on the roll)
const HIDE = [216, 178, 150], HIDE_D = [168, 120, 96];   // the leathery flesh side of the pelt
function mkCanvas(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }

// Fur painted into its own canvas (w x h bar pixels). Strands flow toward the tail (left) and fan out top and
// bottom; `around` makes them run down instead, for the fur wrapped round the roll.
function makeFurTex(w, h, H, pelt, around = false) {
	const k = typeof dpr === 'number' ? dpr : 1, cv = mkCanvas(w * k, h * k), g = cv.getContext('2d');
	g.scale(k, k);
	const bg = g.createLinearGradient(0, 0, 0, h);
	bg.addColorStop(0, rgba(mix(pelt.base, pelt.mid, .25))); bg.addColorStop(.5, rgba(pelt.base)); bg.addColorStop(1, rgba(mix(pelt.base, pelt.root, .5)));
	g.fillStyle = bg; g.fillRect(0, 0, w, h);
	// soft mottling, so the coat isn't one flat tone
	for (let i = 0; i < w * h / (H * H) * 6; i++) {
		const x = rand(0, w), y = rand(0, h), r = H * rand(.15, .45), c = Math.random() < .5 ? pelt.root : pelt.mid;
		const gr = g.createRadialGradient(x, y, 0, x, y, r);
		gr.addColorStop(0, rgba(c, .28)); gr.addColorStop(1, rgba(c, 0));
		g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
	}
	const n = noise2(), mid = h / 2;
	const angAt = (x, y) => around
		? Math.PI / 2 + .35 * n(x / (H * .25), y / (H * .25)) + .25
		: Math.PI - (y - mid) / h * 1.0 + .55 * n(x / (H * .3), y / (H * .3));
	// three coats: dense short undercoat, the main coat, and long guard hairs with dark roots and light tips
	const coats = [
		{ n: 1100, len: [.05, .09], lw: .02, cols: [pelt.root, mix(pelt.root, pelt.base, .5)], a: .75 },
		{ n: 800, len: [.08, .14], lw: .016, cols: [pelt.base, pelt.mid, mix(pelt.mid, pelt.tip, .3)], a: .7 },
		{ n: 380, len: [.12, .22], lw: .012, guard: true, a: .85 },
	];
	g.lineCap = 'round';
	for (const c of coats) {
		const count = Math.round(c.n * w * h / (H * H));
		const paths = c.guard ? [new Path2D(), new Path2D(), new Path2D()] : c.cols.map(() => new Path2D());
		for (let i = 0; i < count; i++) {
			const x = rand(-H * .1, w + H * .1), y = rand(-H * .05, h + H * .05), ang = angAt(x, y) + rand(-.12, .12);
			const len = H * rand(...c.len), bend = H * rand(-.025, .025);
			const ex = x + Math.cos(ang) * len, ey = y + Math.sin(ang) * len;
			const cx = (x + ex) / 2 - Math.sin(ang) * bend, cy = (y + ey) / 2 + Math.cos(ang) * bend;
			if (c.guard) {
				// root half dark, tip half light, a thin bright tip end
				const mx = (x + 2 * cx + ex) / 4, my = (y + 2 * cy + ey) / 4;
				paths[0].moveTo(x, y); paths[0].quadraticCurveTo((x + cx) / 2, (y + cy) / 2, mx, my);
				paths[1].moveTo(mx, my); paths[1].quadraticCurveTo((cx + ex) / 2, (cy + ey) / 2, ex, ey);
				const tx = ex - Math.cos(ang) * len * .18, ty = ey - Math.sin(ang) * len * .18;
				paths[2].moveTo(tx, ty); paths[2].lineTo(ex, ey);
			} else {
				const p = paths[Math.floor(Math.random() * paths.length)];
				p.moveTo(x, y); p.quadraticCurveTo(cx, cy, ex, ey);
			}
		}
		g.lineWidth = Math.max(.45, H * c.lw);
		if (c.guard) {
			g.strokeStyle = rgba(pelt.root, .75); g.stroke(paths[0]);
			g.strokeStyle = rgba(pelt.tip, .7); g.stroke(paths[1]);
			g.lineWidth = Math.max(.35, H * c.lw * .8); g.strokeStyle = rgba(mix(pelt.tip, [255, 255, 255], .3), .55); g.stroke(paths[2]);
		} else c.cols.forEach((col, i) => { g.strokeStyle = rgba(col, c.a); g.stroke(paths[i]); });
	}
	// a soft sheen where the light catches the coat, and the body rounding off top and bottom
	g.globalCompositeOperation = 'soft-light';
	const sg = g.createLinearGradient(0, 0, 0, h);
	sg.addColorStop(0, rgba(pelt.sheen, 0)); sg.addColorStop(.3, rgba(pelt.sheen, .5)); sg.addColorStop(.55, rgba(pelt.sheen, 0));
	g.fillStyle = sg; g.fillRect(0, 0, w, h);
	g.globalCompositeOperation = 'source-over';
	if (!around) {
		const sh = g.createLinearGradient(0, 0, 0, h);
		sh.addColorStop(0, 'rgba(0,0,0,.32)'); sh.addColorStop(.25, 'rgba(0,0,0,0)'); sh.addColorStop(.75, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,.4)');
		g.fillStyle = sh; g.fillRect(0, 0, w, h);
	}
	return { cv, w, h, k };
}

// The roll: the pelt wrapped round itself, fur outward, seen a little from above. The hide's pale flesh side
// shows where it curls off the meat, and the end shows the spiral of hide layers.
function drawRealRoll(g, s, xc, r, y0, y1) {
	const H = s.H, ry = r * .3, T = s.rollTex;
	const body = new Path2D();
	body.moveTo(xc - r, y0); body.lineTo(xc - r, y1); body.ellipse(xc, y1, r, ry, 0, Math.PI, 0, true); body.lineTo(xc + r, y0); body.closePath();
	// soft shadow cast on the bar, offset down-right
	g.save(); g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = H * .25 * dpr; g.shadowOffsetX = H * .08 * dpr; g.shadowOffsetY = H * .06 * dpr;
	g.fillStyle = rgba(s.peltReal.base); g.fill(body); g.restore();
	g.save(); g.clip(body);
	// fur wrapped round the roll; it turns as the roll rolls along
	const pat = g.createPattern(T.cv, 'repeat'), off = (xc / Math.max(1, r)) * r * .9;
	pat.setTransform(new DOMMatrix().translate(xc - r, y0 + off).scale(1 / T.k));
	g.fillStyle = pat; g.fillRect(xc - r, y0 - ry, r * 2, y1 - y0 + ry * 2);
	// the flesh side showing on the curl, along the side that faces the meat
	const hg = g.createLinearGradient(xc - r, 0, xc - r * .45, 0);
	hg.addColorStop(0, rgba(HIDE_D, .95)); hg.addColorStop(.45, rgba(HIDE, .85)); hg.addColorStop(1, rgba(HIDE, 0));
	g.fillStyle = hg; g.fillRect(xc - r, y0, r * .6, y1 - y0 + ry);
	// cylinder shading: lit from the upper left, deep shade on the far side
	const cg = g.createLinearGradient(xc - r, 0, xc + r, 0);
	cg.addColorStop(0, 'rgba(0,0,0,.35)'); cg.addColorStop(.28, 'rgba(255,240,215,.12)'); cg.addColorStop(.45, 'rgba(0,0,0,0)');
	cg.addColorStop(.8, 'rgba(0,0,0,.35)'); cg.addColorStop(1, 'rgba(0,0,0,.6)');
	g.fillStyle = cg; g.fillRect(xc - r, y0 - ry, r * 2, y1 - y0 + ry * 2);
	const vg = g.createLinearGradient(0, y0, 0, y1 + ry);
	vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(.7, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.4)');
	g.fillStyle = vg; g.fillRect(xc - r, y0, r * 2, y1 - y0 + ry);
	g.restore();
	// stray hairs breaking the silhouette, so the edge reads as fur rather than a drawn line
	g.lineCap = 'round'; g.lineWidth = Math.max(.4, H * .012);
	for (const h of s.rollHairs) {
		const x = xc + h.side * r, y = lerp(y0, y1, h.v);
		g.strokeStyle = rgba(h.tip ? s.peltReal.tip : s.peltReal.mid, .7);
		g.beginPath(); g.moveTo(x - h.side * H * .02, y); g.quadraticCurveTo(x + h.side * h.len * .5, y + h.len * .2, x + h.side * h.len, y + h.len * h.droop); g.stroke();
	}
	// the end: hide rolled on itself, pale flesh layers between thin dark lines of fur, a dark core
	g.save();
	g.beginPath(); g.ellipse(xc, y0, r, ry, 0, 0, 6.283); g.clip();
	const eg = g.createRadialGradient(xc - r * .2, y0 - ry * .3, 0, xc, y0, r);
	eg.addColorStop(0, rgba(mix(HIDE, [255, 240, 225], .2))); eg.addColorStop(.75, rgba(HIDE)); eg.addColorStop(1, rgba(HIDE_D));
	g.fillStyle = eg; g.fillRect(xc - r, y0 - ry, r * 2, ry * 2);
	const turns = 2.6, path = new Path2D();
	for (let a = 0; a <= 6.283 * turns; a += .12) {
		const rr = r * (1 - a / (6.283 * (turns + .35)));
		const px = xc + Math.cos(a + s.rollAng) * rr, py = y0 + Math.sin(a + s.rollAng) * rr * .3;
		a ? path.lineTo(px, py) : path.moveTo(px, py);
	}
	g.lineJoin = 'round';
	g.strokeStyle = rgba(s.peltReal.mid, .85); g.lineWidth = Math.max(.7, r * .13); g.stroke(path);
	g.strokeStyle = rgba(s.peltReal.root, .7); g.lineWidth = Math.max(.4, r * .05); g.stroke(path);
	const core = g.createRadialGradient(xc, y0, 0, xc, y0, r * .3);
	core.addColorStop(0, 'rgba(20,10,6,.7)'); core.addColorStop(1, 'rgba(20,10,6,0)');
	g.fillStyle = core; g.fillRect(xc - r, y0 - ry, r * 2, ry * 2);
	g.restore();
	g.strokeStyle = 'rgba(0,0,0,.3)'; g.lineWidth = Math.max(.5, H * .015);
	g.beginPath(); g.ellipse(xc, y0, r, ry, 0, 0, 6.283); g.stroke();
}

// A skinning knife, tip at (x, y), the blade running up the angle with its curved edge on the lower side.
function makeKnifeLook(H) {
	const antler = Math.random() < .4, smears = [];
	for (let i = 0; i < 6; i++) smears.push({ u: rand(.02, .42), v: rand(-.1, .55), rx: rand(.05, .14), ry: rand(.08, .22), a: rand(.35, .7) });
	const grain = [];
	for (let i = 0; i < 7; i++) grain.push({ v: rand(-.8, .8), amp: rand(.03, .1), f: rand(5, 11), ph: rand(0, 6.283) });
	const knobs = [];
	for (let i = 0; i < 9; i++) knobs.push({ u: rand(.05, .95), v: rand(-.6, .6), r: rand(.04, .09) });
	return { antler, brass: Math.random() < .5, smears, grain, knobs };
}
function drawRealKnife(g, x, y, H, ang, alpha, look, glint) {
	const L = H * 1.05, bw = H * .27, hc = bw * .16, gw = bw * .3, hl = H * .76, hh = bw * .44;
	g.save(); g.globalAlpha *= alpha; g.translate(x, y); g.rotate(ang);
	// blade: upswept tip, concave spine, a full curved belly for the edge
	const blade = new Path2D();
	blade.moveTo(0, 0);
	blade.bezierCurveTo(L * .05, bw * .55, L * .45, bw * .98, L, bw * .62);
	blade.lineTo(L, -bw * .3);
	blade.quadraticCurveTo(L * .45, bw * .1, 0, 0);
	blade.closePath();
	const hx0 = L + gw, hx1 = L + gw + hl;
	const handle = new Path2D();
	handle.moveTo(hx0, hc - hh);
	handle.bezierCurveTo(hx0 + hl * .4, hc - hh * 1.08, hx1 - hl * .2, hc - hh * 1.15, hx1 - hh * .5, hc - hh * 1.05);
	handle.quadraticCurveTo(hx1 + hh * .35, hc, hx1 - hh * .5, hc + hh * 1.0);
	handle.bezierCurveTo(hx1 - hl * .25, hc + hh * 1.05, hx0 + hl * .35, hc + hh * .95, hx0, hc + hh);
	handle.closePath();
	const bolster = new Path2D();
	roundRectPathTo(bolster, L - gw * .05, hc - hh * 1.18, gw * 1.1, hh * 2.36, gw * .35);
	// one soft shadow under the whole knife
	g.save(); g.shadowColor = 'rgba(0,0,0,.45)'; g.shadowBlur = H * .14 * dpr; g.shadowOffsetX = H * .05 * dpr; g.shadowOffsetY = H * .08 * dpr;
	g.fillStyle = '#555'; g.fill(blade); g.fill(handle); g.fill(bolster); g.restore();

	// handle
	g.save(); g.clip(handle);
	const hg = g.createLinearGradient(0, hc - hh, 0, hc + hh);
	if (look.antler) { hg.addColorStop(0, '#e6dac4'); hg.addColorStop(.45, '#b7a385'); hg.addColorStop(1, '#5d4c38'); }
	else { hg.addColorStop(0, '#9a6a40'); hg.addColorStop(.4, '#6a4322'); hg.addColorStop(1, '#2a160a'); }
	g.fillStyle = hg; g.fillRect(hx0, hc - hh * 1.3, hl + hh, hh * 2.6);
	if (look.antler) {
		// pitted, ridged antler
		for (const kn of look.knobs) {
			const kx = lerp(hx0, hx1, kn.u), ky = hc + kn.v * hh, kr = H * kn.r;
			const kg = g.createRadialGradient(kx - kr * .3, ky - kr * .3, 0, kx, ky, kr);
			kg.addColorStop(0, 'rgba(255,248,232,.35)'); kg.addColorStop(.6, 'rgba(120,96,70,.25)'); kg.addColorStop(1, 'rgba(60,44,30,0)');
			g.fillStyle = kg; g.beginPath(); g.arc(kx, ky, kr, 0, 6.283); g.fill();
		}
		g.strokeStyle = 'rgba(70,52,34,.35)'; g.lineWidth = Math.max(.4, H * .01);
		for (const gr of look.grain) {
			g.beginPath();
			for (let u = 0; u <= 1; u += .05) { const px = lerp(hx0, hx1, u), py = hc + gr.v * hh * .8 + Math.sin(u * gr.f + gr.ph) * gr.amp * hh; u ? g.lineTo(px, py) : g.moveTo(px, py); }
			g.stroke();
		}
	} else {
		// wood grain running the length of the handle
		g.lineWidth = Math.max(.4, H * .01);
		for (const gr of look.grain) {
			g.strokeStyle = `rgba(30,14,4,${.25 + gr.amp * 2})`;
			g.beginPath();
			for (let u = 0; u <= 1; u += .04) { const px = lerp(hx0, hx1, u), py = hc + gr.v * hh + Math.sin(u * gr.f + gr.ph) * gr.amp * hh; u ? g.lineTo(px, py) : g.moveTo(px, py); }
			g.stroke();
		}
		const wg = g.createRadialGradient(lerp(hx0, hx1, .55), hc - hh * .3, 0, lerp(hx0, hx1, .55), hc - hh * .3, hl * .35);   // worn, handled spot
		wg.addColorStop(0, 'rgba(255,225,190,.12)'); wg.addColorStop(1, 'rgba(255,225,190,0)');
		g.fillStyle = wg; g.fillRect(hx0, hc - hh * 1.3, hl, hh * 2.6);
	}
	const hs = g.createLinearGradient(0, hc - hh, 0, hc - hh * .4);   // highlight along the top
	hs.addColorStop(0, 'rgba(255,245,225,.28)'); hs.addColorStop(1, 'rgba(255,245,225,0)');
	g.fillStyle = hs; g.fillRect(hx0, hc - hh * 1.3, hl + hh, hh);
	g.restore();
	// pins
	const pin = look.brass ? ['#fff0b8', '#b88a36', '#5a3e12'] : ['#ffffff', '#a8b0b8', '#4a5058'];
	for (const u of [.28, .72]) {
		const px = lerp(hx0, hx1, u), pr = bw * .075, pg = g.createRadialGradient(px - pr * .35, hc - pr * .35, 0, px, hc, pr);
		pg.addColorStop(0, pin[0]); pg.addColorStop(.55, pin[1]); pg.addColorStop(1, pin[2]);
		g.fillStyle = pg; g.beginPath(); g.arc(px, hc, pr, 0, 6.283); g.fill();
	}
	g.strokeStyle = 'rgba(0,0,0,.3)'; g.lineWidth = Math.max(.5, H * .012); g.stroke(handle);

	// bolster
	const bg2 = g.createLinearGradient(0, hc - hh * 1.18, 0, hc + hh * 1.18);
	if (look.brass) { bg2.addColorStop(0, '#fbe6a8'); bg2.addColorStop(.35, '#c79a44'); bg2.addColorStop(.7, '#7a5418'); bg2.addColorStop(1, '#3e2a0a'); }
	else { bg2.addColorStop(0, '#f2f5f8'); bg2.addColorStop(.35, '#a9b2bb'); bg2.addColorStop(.7, '#5c646d'); bg2.addColorStop(1, '#2a2f35'); }
	g.fillStyle = bg2; g.fill(bolster);
	g.strokeStyle = 'rgba(0,0,0,.3)'; g.stroke(bolster);

	// blade: brushed steel, a brighter ground bevel along the edge, a sharp edge line, the spine catching light
	g.save(); g.clip(blade);
	const sg = g.createLinearGradient(0, -bw * .35, 0, bw * .9);
	sg.addColorStop(0, '#e4e9ee'); sg.addColorStop(.3, '#a7b0b9'); sg.addColorStop(.55, '#7b858f'); sg.addColorStop(1, '#5d6670');
	g.fillStyle = sg; g.fillRect(-H * .1, -bw, L + H * .2, bw * 2.2);
	g.strokeStyle = 'rgba(255,255,255,.07)'; g.lineWidth = Math.max(.3, H * .006);
	for (let i = 0; i < 9; i++) { const yy = lerp(-bw * .25, bw * .7, i / 8); g.beginPath(); g.moveTo(L * .1, yy); g.lineTo(L, yy + bw * .02); g.stroke(); }
	const belly = new Path2D(); belly.moveTo(0, 0); belly.bezierCurveTo(L * .05, bw * .55, L * .45, bw * .98, L, bw * .62);
	g.strokeStyle = 'rgba(214,224,232,.55)'; g.lineWidth = bw * .5; g.stroke(belly);   // the ground bevel
	g.strokeStyle = 'rgba(70,78,88,.35)'; g.lineWidth = Math.max(.4, H * .012);   // bevel line
	g.save(); g.translate(0, -bw * .22); g.stroke(belly); g.restore();
	// a glint that slides along the blade as it saws
	const gx = L * (.25 + .5 * glint), gl = g.createRadialGradient(gx, bw * .25, 0, gx, bw * .25, L * .22);
	gl.addColorStop(0, 'rgba(255,255,255,.55)'); gl.addColorStop(1, 'rgba(255,255,255,0)');
	g.globalCompositeOperation = 'lighter'; g.fillStyle = gl; g.fillRect(-H * .1, -bw, L + H * .2, bw * 2.2); g.globalCompositeOperation = 'source-over';
	// blood smeared toward the tip, thinning out up the blade
	for (const sm of look.smears) {
		const sx = L * sm.u, sy = bw * sm.v, a = sm.a * (1 - sm.u * 1.6);
		if (a <= 0) continue;
		const bgr = g.createRadialGradient(sx, sy, 0, sx, sy, L * sm.rx);
		bgr.addColorStop(0, rgba([118, 10, 14], a)); bgr.addColorStop(.7, rgba([96, 6, 10], a * .6)); bgr.addColorStop(1, rgba([96, 6, 10], 0));
		g.fillStyle = bgr; g.beginPath(); g.ellipse(sx, sy, L * sm.rx, bw * sm.ry * 2, 0, 0, 6.283); g.fill();
	}
	g.restore();
	g.strokeStyle = 'rgba(255,255,255,.85)'; g.lineWidth = Math.max(.4, H * .01); g.stroke(belly);    // the sharp edge
	g.strokeStyle = 'rgba(255,255,255,.4)'; g.lineWidth = Math.max(.4, H * .012);                   // spine highlight
	g.beginPath(); g.moveTo(L, -bw * .28); g.quadraticCurveTo(L * .45, bw * .1, L * .04, bw * .01); g.stroke();
	g.strokeStyle = 'rgba(0,0,0,.28)'; g.lineWidth = Math.max(.5, H * .012); g.stroke(blade);
	g.restore();
}
function roundRectPathTo(p, x, y, w, h, r) {
	r = Math.min(r, h / 2, w / 2);
	p.moveTo(x + r, y); p.arcTo(x + w, y, x + w, y + h, r); p.arcTo(x + w, y + h, x, y + h, r);
	p.arcTo(x, y + h, x, y, r); p.arcTo(x, y, x + w, y, r); p.closePath();
}

// ---------------------------------------------------------------- C2's pool of blood
// The pool is a union of soft lobes laid down just behind the knife as it goes; each lobe swells
// quickly, then keeps creeping outward slowly, so the puddle spreads and joins up behind the cut.
// It is painted every frame into its own canvas in flat layers (a brighter rim, then the darker
// body), so overlapping lobes merge into one shape, then shaded with a wet sheen and a few glints.
// Lobes laid near the start (under the spell name) stay smaller, and the pool thins toward the left.
function addPoolLobe(s, x) {
	const H = s.H, nearText = clamp((x - H * .6) / (H * 3.2)), sub = [];
	const n = Math.floor(rand(3, 6));
	for (let i = 0; i < n; i++) sub.push({ dx: rand(-.55, .55), dy: rand(-.5, .5), k: rand(.45, .85), ph: rand(0, 6.283) });
	s.pool.push({ x, y: H * (.5 + rand(-.14, .14)), max: H * rand(.3, .46) * lerp(.55, 1, nearText), born: s.t, grow: rand(.5, .9), sub });
}
function lobeRadius(q, t) {
	const age = t - q.born;
	return q.max * (easeOut(clamp(age / q.grow)) * .75 + .25 * clamp(Math.log1p(age * .6) / 2.2));   // swell, then creep
}
function drawPool(g, s) {
	const { W, H, t } = s;
	if (!s.pool.length) return;
	const k = dpr, cv = s.poolCv;
	if (cv.width !== Math.round(W * k) || cv.height !== Math.round(H * k)) { cv.width = Math.round(W * k); cv.height = Math.round(H * k); }
	const p = cv.getContext('2d');
	p.setTransform(k, 0, 0, k, 0, 0); p.clearRect(0, 0, W, H);
	const blob = (q, scale) => {
		const r = lobeRadius(q, t) * scale;
		if (r <= .2) return;
		p.beginPath(); p.arc(q.x, q.y, r, 0, 6.283); p.fill();
		for (const b of q.sub) {   // satellite lobes give the edge its rounded, uneven bulges
			const rr = r * b.k * (1 + .04 * Math.sin(t * .7 + b.ph));
			p.beginPath(); p.arc(q.x + b.dx * r, q.y + b.dy * r, rr, 0, 6.283); p.fill();
		}
	};
	p.fillStyle = '#a3121a'; for (const q of s.pool) blob(q, 1);        // thin, brighter rim
	p.fillStyle = '#6e050b'; for (const q of s.pool) blob(q, .84);      // the body, one merged shape
	// depth: the pool is thicker and darker along its middle, thinner toward its edges and the bottom
	p.globalCompositeOperation = 'source-atop';
	const dep = p.createLinearGradient(0, 0, 0, H);
	dep.addColorStop(0, 'rgba(0,0,0,0)'); dep.addColorStop(.5, 'rgba(30,0,3,.35)'); dep.addColorStop(1, 'rgba(0,0,0,.15)');
	p.fillStyle = dep; p.fillRect(0, 0, W, H);
	// wet sheen: a broad soft band of reflected light across the whole pool, drifting slowly, and a
	// few small sharp glints fixed per cast (not one per lobe, so it reads as one puddle)
	let x0 = W, x1 = 0;
	for (const q of s.pool) { const r = lobeRadius(q, t); x0 = Math.min(x0, q.x - r); x1 = Math.max(x1, q.x + r); }
	const band = H * (.32 + .04 * Math.sin(t * .4)), bg = p.createLinearGradient(0, band - H * .14, 0, band + H * .14);
	bg.addColorStop(0, 'rgba(255,190,190,0)'); bg.addColorStop(.5, 'rgba(255,190,190,.2)'); bg.addColorStop(1, 'rgba(255,190,190,0)');
	p.fillStyle = bg; p.fillRect(x0, band - H * .14, x1 - x0, H * .28);
	for (const gl of s.glints) {
		const gx = lerp(x0, x1, gl.u) + Math.sin(t * .3 + gl.ph) * H * .08, gy = H * gl.v;
		const gg = p.createRadialGradient(gx, gy, 0, gx, gy, H * gl.r);
		gg.addColorStop(0, 'rgba(255,245,245,.7)'); gg.addColorStop(.4, 'rgba(255,220,220,.25)'); gg.addColorStop(1, 'rgba(255,220,220,0)');
		p.fillStyle = gg; p.beginPath(); p.ellipse(gx, gy, H * gl.r * 2.4, H * gl.r, 0, 0, 6.283); p.fill();
	}
	// thin toward the far left, so the oldest part reads as a spread-out film and the name stays clear
	p.globalCompositeOperation = 'destination-out';
	const fade = p.createLinearGradient(0, 0, H * 4, 0);
	fade.addColorStop(0, 'rgba(0,0,0,.55)'); fade.addColorStop(1, 'rgba(0,0,0,0)');
	p.fillStyle = fade; p.fillRect(0, 0, H * 4, H);
	p.globalCompositeOperation = 'source-over';
	// a soft dark seep under the edge, then the pool
	g.save(); g.shadowColor = 'rgba(40,0,4,.6)'; g.shadowBlur = H * .1 * dpr; g.globalAlpha = .95;
	g.drawImage(cv, 0, 0, W, H); g.restore();
}

CONCEPTS.push({
	group: 'Skinning', id: 'skin-c2', letter: 'C2', name: 'Pelt roll, raw',
	desc: 'C with marbled meat behind the roll, like a ribeye: wine-red muscle laced with creamy fat, swirling fat seams and a fat cap; a glossy pool of blood spreads out behind the knife and keeps creeping; painted fur that changes every cast (bear, wolf, tawny cat, red fox, arctic white, black bear, nightsaber, boar), a fur roll showing the hide\'s spiral, and a steel skinning knife standing upright beside the roll, its edge against it, sawing up and down',
	spell: 'Skinning', padTop: 1.6, padBottom: 1.6, padX: 1.3, flash: [255, 200, 175],
	init(s) {
		const { W, H } = s;
		s.peltReal = PELTS_REAL[peltTurn++ % PELTS_REAL.length];
		s.furTex = makeFurTex(W, H, H, s.peltReal);
		s.rollTex = makeFurTex(H * 1.2, H * 1.2, H, s.peltReal, true);
		s.rollHairs = [];
		for (let i = 0; i < 26; i++) s.rollHairs.push({ side: Math.random() < .5 ? -1 : 1, v: rand(0, 1), len: H * rand(.04, .1), droop: rand(-.4, .5), tip: Math.random() < .4 });
		s.rollAng = rand(0, 6.283);
		s.knife = makeKnifeLook(H);
		s.inner = makeMarble(W, H);
		s.pool = []; s.poolNext = H * rand(.5, .9); s.poolCv = document.createElement('canvas');
		s.glints = [];
		for (let i = 0; i < Math.max(2, Math.round(W / H / 2.5)); i++) s.glints.push({ u: rand(.15, .95), v: rand(.28, .42), r: rand(.035, .06), ph: rand(0, 6.283) });
	},
	draw(g, s) {
		const { W, H, t } = s, f = s.fill;
		const r = H * (.2 + .16 * s.p), xc = f - r * .9;
		s.xc = xc; s.r = r;
		// blood wells up just behind the knife as it goes, and the pool keeps spreading behind it
		while (s.casting && xc - r * 1.6 > s.poolNext) {
			addPoolLobe(s, s.poolNext);
			s.poolNext += H * rand(.22, .38);
		}
		g.save(); roundRectPath(g, 0, 0, W, H, H * .18); g.clip();
		g.drawImage(s.furTex.cv, 0, 0, W, H);
		// the coat ahead of the roll lies in its shadow for a little way
		const fs = g.createLinearGradient(xc + r, 0, xc + r + H * .5, 0);
		fs.addColorStop(0, 'rgba(0,0,0,.45)'); fs.addColorStop(1, 'rgba(0,0,0,0)');
		g.fillStyle = fs; g.fillRect(xc + r, 0, H * .5, H);
		if (xc > 0) {
			g.save(); g.beginPath(); g.rect(0, 0, xc, H); g.clip();
			g.drawImage(s.inner.cv, 0, 0, W, H);
			// fresh cut by the roll is moist and a little brighter; older meat dulls slightly
			const dg = g.createLinearGradient(0, 0, xc, 0);
			dg.addColorStop(0, 'rgba(20,0,4,.22)'); dg.addColorStop(clamp(1 - H * 2 / Math.max(1, xc)), 'rgba(20,0,4,0)'); dg.addColorStop(1, 'rgba(20,0,4,0)');
			g.fillStyle = dg; g.fillRect(0, 0, xc, H);
			g.globalCompositeOperation = 'lighter';
			const wg = g.createLinearGradient(xc - H * 1.4, 0, xc, 0);
			wg.addColorStop(0, 'rgba(255,120,110,0)'); wg.addColorStop(1, 'rgba(255,120,110,.12)');
			g.fillStyle = wg; g.fillRect(xc - H * 1.4, 0, H * 1.4, H);
			g.globalCompositeOperation = 'source-over';
			const sg = g.createLinearGradient(xc - H * .6, 0, xc, 0);   // the roll's shadow
			sg.addColorStop(0, 'rgba(0,0,0,0)'); sg.addColorStop(1, 'rgba(0,0,0,.55)');
			g.fillStyle = sg; g.fillRect(xc - H * .6, 0, H * .6, H);
			drawPool(g, s);
			g.restore();
		}
		g.restore();
	},
	// in front of the bar's frame line: the roll, then the knife, its tip on the meat pointing back over the
	// cut and its handle rising up and right over the roll (drawn after the roll, so it stays in view)
	over(g, s) {
		const { H, t } = s, f = s.fill, xc = s.xc, r = s.r, mid = H * .5;
		const lift = s.done ? easeIn(clamp(s.doneT / .5)) : 0, saw = s.casting ? Math.sin(t * 13) * H * .05 : 0;
		if (f > 1) drawRealRoll(g, s, xc, r, -H * .08, H * 1.08);
		// upright beside the roll, parallel to its edge: tip down at the bottom of the cut, the blade's
		// edge against the roll, handle standing up above the bar; it saws up and down along the roll
		const tipX = xc - r - KNIFE_BELLY * H - lift * H * .6, tipY = H * .96 + saw - lift * H * 1.2;
		drawRealKnife(g, tipX, tipY, H, -Math.PI / 2, 1 - lift, s.knife, .5 + .5 * Math.sin(t * 13));
	},
});
})();
