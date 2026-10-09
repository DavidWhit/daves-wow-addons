// Lightning, painted cumulus (2026-10-09): clouds after the user's reference painting (crop.jpg): one dense
// mass of overlapping rounded puffs, grey tops lit from the upper left, darker rounded shadows between the
// puffs, a flat dark blue-grey underside, soft painterly edges. Each mass is built from rows of puffs
// (a flat bottom row, a bigger middle row, a domed top row and a few small caps), lower puffs drawn over the
// ones behind them, so the silhouette is a cauliflower and the body reads as solid cloud, not blobs.
// A3's sky, bolts, flashes, sheet lightning and leading edge are reused unchanged (its draw function).
(() => {
	function cnv(w, h) { const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c; }
	const BANK_TOP = .9;   // room above a mass in its canvas, in bar heights
	// the reference's greys, a touch cool
	const GREY = { lit: [150, 156, 164], mid: [92, 100, 111], dark: [56, 63, 76], under: [34, 39, 52] };
	const BLUE = { lit: [140, 152, 176], mid: [82, 94, 118], dark: [50, 58, 82], under: [28, 33, 54] };
	const DUSK = { lit: [156, 150, 162], mid: [94, 90, 106], dark: [58, 54, 72], under: [34, 32, 48] };

	// One puff: a soft rounded blob, a little lighter toward its upper left, painted as four jittered,
	// slightly squashed strokes at low contrast so neighbours melt into one mass, with a faint darker
	// shadow along its lower curve where it tucks under the puff in front.
	function puff(b, x, y, r, C, soft) {
		for (let i = 0; i < 2; i++) {
			const jx = x + rand(-.07, .07) * r, jy = y + rand(-.05, .05) * r, rx = r * rand(1.08, 1.3), ry = r * rand(.88, 1.04);
			const g0 = b.createRadialGradient(jx - rx * .3, jy - ry * .36, r * .12, jx, jy, rx);
			g0.addColorStop(0, rgba(mix(C.lit, C.mid, .15), .92)); g0.addColorStop(.55, rgba(C.mid, .92)); g0.addColorStop(1, rgba(mix(C.mid, C.dark, .85), .92));
			b.fillStyle = g0; b.beginPath(); b.ellipse(jx, jy, rx, ry, rand(-.2, .2), 0, 6.283); b.fill();
		}
		b.strokeStyle = rgba(C.dark, .42); b.lineWidth = Math.max(.8, r * .17 * soft); b.lineCap = 'round';
		b.beginPath(); b.ellipse(x, y + r * .06, r * 1.1, r * .94, 0, Math.PI * .15, Math.PI * .85); b.stroke();
	}

	// A bank: masses of puffs with sky between them, BW wide (tiles), painted at k device px per bar px.
	// B: y/base (mass top and bottom, bar heights from the bar's top), mass/gap (lengths, bar heights),
	// puff (scale), cols (colour set), a, v (drift), rows (how many puff rows up the mass: 2, 3 or 4).
	function paintPuffBank(B, BW, H, k) {
		const BH = (BANK_TOP + B.base - B.y + .6) * H, y0 = BANK_TOP * H, depth = (B.base - B.y) * H, C = B.cols;
		const puffs = [];
		for (let cx = rand(0, H * 1.5); cx < BW - H * .5;) {
			const len = Math.min(H * rand(...B.mass), BW - cx), rows = B.rows || 3;
			const ps = B.puff * H;
			// the bottom row: a flat base of mid-size puffs, slightly smaller toward the ends
			const vary = () => rand(.65, 1.35);   // puff sizes mixed, as the reference's
			for (let px = cx + ps * .5; px < cx + len - ps * .3; px += ps * rand(.55, .8)) {
				const u = (px - cx) / len, end = Math.min(1, Math.min(u, 1 - u) * 3);
				puffs.push({ x: px, y: y0 + depth * .78 + rand(-.03, .03) * depth, r: ps * rand(.46, .58) * vary() * (.75 + .25 * end), z: 3 });
			}
			// the middle row: the biggest puffs, offset half a step, the mass's belly
			for (let px = cx + ps * .9; px < cx + len - ps * .6; px += ps * rand(.6, .85)) {
				const u = (px - cx) / len, dome = Math.sin(Math.PI * clamp(u));
				puffs.push({ x: px, y: y0 + depth * (.52 - .06 * dome) + rand(-.05, .05) * depth, r: ps * rand(.55, .7) * vary() * (.8 + .2 * dome), z: 2 });
			}
			// the top row: smaller, domed (highest mid-mass), only over the middle of the mass
			if (rows >= 3) for (let px = cx + len * .18; px < cx + len * .82; px += ps * rand(.5, .8)) {
				const u = (px - cx) / len, dome = Math.sin(Math.PI * clamp(u));
				puffs.push({ x: px, y: y0 + depth * (.3 - .1 * dome) + rand(-.04, .04) * depth, r: ps * rand(.38, .52) * vary() * (.7 + .3 * dome), z: 1 });
			}
			// a few small caps on top, the cauliflower crown
			if (rows >= 4) for (let px = cx + len * .3; px < cx + len * .7; px += ps * rand(.45, .75)) {
				const u = (px - cx) / len, dome = Math.sin(Math.PI * clamp(u));
				puffs.push({ x: px, y: y0 + depth * (.14 - .06 * dome), r: ps * rand(.26, .4) * vary(), z: 0 });
			}
			cx += len + H * rand(...B.gap);
		}
		// back rows first; lower, nearer puffs overlap them, as in the reference
		puffs.sort((a, b) => a.z - b.z || a.y - b.y);
		const body = cnv(BW * k, BH * k), b = body.getContext('2d');
		b.scale(k, k);
		b.filter = `blur(${H * .022 * k}px)`;
		for (const p of puffs) for (const o of [-BW, 0, BW]) if (p.x + o > -H && p.x + o < BW + H) puff(b, p.x + o, p.y, p.r, C, B.soft || 1);
		b.filter = 'none';
		b.globalCompositeOperation = 'source-atop';
		// broad soft light and shade blotches across the mass, so the puffs read as one painted body
		b.filter = `blur(${H * .12 * k}px)`;
		for (let i = 0; i < BW / H * 1.5; i++) {
			const x = rand(0, BW), y = y0 + depth * rand(0, .8), r = H * rand(.3, .7), light = Math.random() < .45;
			b.fillStyle = rgba(light ? C.lit : C.dark, rand(.08, .18));
			for (const o of [-BW, 0, BW]) { b.beginPath(); b.ellipse(x + o, y, r * 1.6, r, 0, 0, 6.283); b.fill(); }
		}
		b.filter = 'none';
		// the underside: flat and dark, the reference's blue-grey shadow
		const sh = b.createLinearGradient(0, y0 + depth * .4, 0, y0 + depth * 1.05);
		sh.addColorStop(0, rgba(C.under, 0)); sh.addColorStop(1, rgba(C.under, .95));
		b.fillStyle = sh; b.fillRect(0, 0, BW, BH);
		// soft light over the tops, as the reference's grey highlights
		const tl = b.createLinearGradient(0, y0 - depth * .1, 0, y0 + depth * .45);
		tl.addColorStop(0, rgba(C.lit, .3)); tl.addColorStop(1, rgba(C.lit, 0));
		b.fillStyle = tl; b.fillRect(0, 0, BW, BH);
		b.globalCompositeOperation = 'source-over';
		// a lit copy for strikes lighting the mass from within
		const lit = cnv(BW * k, BH * k), lx = lit.getContext('2d');
		lx.drawImage(body, 0, 0); lx.globalCompositeOperation = 'source-in';
		const lg = lx.createLinearGradient(0, 0, 0, BH * k);
		lg.addColorStop(0, 'rgb(200,215,255)'); lg.addColorStop(.55, 'rgb(130,150,240)'); lg.addColorStop(1, 'rgb(50,60,130)');
		lx.fillStyle = lg; lx.fillRect(0, 0, BW * k, BH * k);
		return { c: body, lit, BW, BH, oy: (B.y - BANK_TOP) * H };
	}

	const A3 = () => CONCEPTS.find(c => c.id === 'light-a3');
	function painted(o) {
		CONCEPTS.push({
			group: 'Lightning', id: o.id, letter: o.letter, name: o.name, desc: o.desc,
			spell: 'Lightning Bolt', padTop: .9, padBottom: .6, flash: [190, 215, 255],
			init(s) {
				const H = s.H, k = Math.min(2, window.devicePixelRatio || 1), BW = Math.max(s.W, H * 8) + H * 4;
				s.weather = { tint: o.tint || [1, 1, 1] };
				s.banks = o.banks.map(B => Object.assign(paintPuffBank(B, BW, H, k), { B, u: rand(0, BW), ph: rand(0, 6.283), breath: rand(.02, .05) }));
				s.loose = [];
				s.bolts = []; s.nextBolt = .15; s.flash = 0; s.flashX = 0; s.sheet = 0; s.sheetX = 0;
				s.roll = wobble(2);
			},
			draw(g, s) { A3().draw(g, s); },
		});
	}

	painted({
		id: 'light-b1', letter: 'B1', name: 'Painted cumulus, banks',
		desc: 'Clouds painted after the reference: dense masses of overlapping rounded puffs, grey tops lit from the upper left, a flat dark underside; a faint far bank, a mid bank and a big near bank, each drifting at its own pace; A\'s bolts and flashes',
		banks: [
			{ y: -.05, base: .5, mass: [2.5, 4.5], gap: [1.2, 2.6], puff: .42, cols: BLUE, a: .55, v: .05, rows: 3, soft: .8 },
			{ y: .15, base: .85, mass: [2.8, 5], gap: [1.4, 3], puff: .5, cols: GREY, a: .9, v: .11, rows: 3 },
			{ y: .35, base: 1.3, mass: [3, 6], gap: [1.8, 3.4], puff: .6, cols: GREY, a: 1, v: .2, rows: 4 },
		],
	});
	painted({
		id: 'light-b2', letter: 'B2', name: 'Painted cumulus, rolling front',
		desc: 'One long near mass of big painted puffs rolling along the bar, its flat underside near the bottom and crowns reaching above the bar; a faint far bank behind it',
		banks: [
			{ y: 0, base: .55, mass: [3, 5], gap: [1.5, 3], puff: .4, cols: BLUE, a: .5, v: .06, rows: 3, soft: .8 },
			{ y: .2, base: 1.25, mass: [5, 9], gap: [.6, 1.6], puff: .72, cols: GREY, a: 1, v: .16, rows: 4 },
		],
	});
	painted({
		id: 'light-b3', letter: 'B3', name: 'Painted cumulus, thunderheads',
		desc: 'Tall separate thunderheads: each mass stacks four rows of puffs into a domed tower with a dark flat base, sky showing between them; darker, bluer greys',
		tint: [.96, .97, 1.04],
		banks: [
			{ y: .1, base: .7, mass: [2, 3.5], gap: [1.5, 3], puff: .44, cols: BLUE, a: .7, v: .07, rows: 3, soft: .8 },
			{ y: .05, base: 1.3, mass: [2.2, 4], gap: [2, 4], puff: .62, cols: DUSK, a: 1, v: .18, rows: 4 },
		],
	});
	painted({
		id: 'light-b4', letter: 'B4', name: 'Painted cumulus, scattered',
		desc: 'Smaller painted masses with more dark sky between them, at three depths, drifting apart; the strikes light whichever mass they hit',
		banks: [
			{ y: -.05, base: .45, mass: [1.5, 3], gap: [2, 4], puff: .36, cols: BLUE, a: .55, v: .05, rows: 3, soft: .8 },
			{ y: .2, base: .9, mass: [1.8, 3.2], gap: [2.2, 4.5], puff: .46, cols: GREY, a: .9, v: .12, rows: 3 },
			{ y: .4, base: 1.3, mass: [2, 3.5], gap: [2.5, 5], puff: .56, cols: GREY, a: 1, v: .22, rows: 4 },
		],
	});
})();
