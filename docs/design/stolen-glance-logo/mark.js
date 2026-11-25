// Stolen Glance mark (DS-10). One source for the static files, the app icon
// and the animated reveal: an eye under a lowered lid, whose pupil turns into
// a keyhole. Prosper/DesignSystem/GlanceGeometry.swift holds the same numbers
// for the app and scripts/make-app-icon.swift; change both together.
//
// Geometry lives in a 200 x 200 box. The eye's corners sit at (28,100) and
// (172,100). Each lid is a filled, tapered stroke: thick in the middle, a point
// at each corner, like a pen line. The lower lid is fixed; the upper lid moves
// with `lid`: 1 is wide open, 0.8 is the mark at rest (a lowered lid), -1 is
// shut, where it lies on the lower lid and the eye reads as a lowered gaze.
(function (root) {
  const L = 28, R = 172, C = 100, LOW = 156, SPAN = 56;
  const UT = 10;  // upper lid half-thickness, in control-point units (15 px at the middle)
  const LT = 5.5; // lower lid: the lighter line
  const f = (n) => n.toFixed(2);
  const upperY = (lid) => C - SPAN * lid;

  const curve = (y) => `C58,${f(y)} 142,${f(y)} ${R},${C}`;
  const back = (y) => `C142,${f(y)} 58,${f(y)} ${L},${C}`;
  const band = (y, t) => `M${L},${C} ${curve(y - t)} ${back(y + t)}Z`;
  const upperShape = (lid) => band(upperY(lid), UT);
  const lowerShape = () => band(LOW, LT);
  // The opening between the lids' inner edges: where the iris shows.
  const opening = (lid) => {
    const top = Math.min(upperY(lid) + UT, LOW - LT);
    return `M${L},${C} ${curve(top)} ${back(LOW - LT)}Z`;
  };
  const outline = (lid) => `M${L},${C} ${curve(upperY(lid))} ${back(LOW)}Z`;

  // The pupil is round at k = 0 and a keyhole at k = 1.
  const pupil = (k) => ({ cy: 100 - 7 * k, r: 13.5 - 2 * k });
  const STEM = 'M95,97 L105,97 L108.6,121 Q109,124.5 105.6,124.5 L94.4,124.5 Q91,124.5 91.4,121 Z';

  const DARK = { a: '#A58AFF', b: '#64CBE6', c: '#58E4B3', iris: '#F0F3FF' };
  const LIGHT = { a: '#6144DE', b: '#187290', c: '#08765C', iris: '#1C2440' };
  const THEMED = { a: 'var(--lid-a)', b: 'var(--lid-b)', c: 'var(--lid-c)', iris: 'var(--iris)' };

  // At rest the lid is lowered and the gaze sits a little low.
  const FINAL = { lid: 0.8, gx: 0, gy: 5, iris: 1, key: 1, draw: 1, blur: 0, halo: 0 };
  let seq = 0;

  const ballT = (s) =>
    `translate(${f(s.gx)} ${f(s.gy)}) translate(100 100) scale(${s.iris.toFixed(4)}) translate(-100 -100)`;
  const stemT = (k) => `translate(100 97) scale(1 ${Math.max(0, k).toFixed(4)}) translate(-100 -97)`;
  const haloT = (h) => `translate(100 100) scale(${(1 + 0.24 * (1 - h)).toFixed(4)}) translate(-100 -100)`;
  // Draw-in reveals the lids from the middle outward (a dot first, then the line).
  const revealX = (d) => 100 - 78 * d;
  const revealW = (d) => Math.max(0.001, 156 * d);

  // Returns SVG markup. `palette` is one of the objects above, or
  // { mono: '<color>' } for a one-colour mark.
  function markup(p = {}, palette = THEMED, opts = {}) {
    const s = Object.assign({}, FINAL, p);
    const id = (opts.idPrefix || 'sg') + (++seq);
    const mono = palette.mono;
    const lidPaint = mono ? mono : `url(#${id}g)`;
    const irisPaint = mono ? mono : palette.iris;
    const pu = pupil(s.key);
    const w = opts.width ? ` width="${opts.width}" height="${opts.width}"` : '';
    const title = opts.title === false ? '' : '<title>Stolen Glance</title>';
    const drawing = s.draw < 1;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"${w} role="img" class="sg-mark">${title}
<defs>
${mono ? '' : `<linearGradient id="${id}g" gradientUnits="userSpaceOnUse" x1="28" y1="58" x2="172" y2="142">
<stop offset="0" style="stop-color:${palette.a}"/><stop offset="0.52" style="stop-color:${palette.b}"/><stop offset="1" style="stop-color:${palette.c}"/></linearGradient>`}
<clipPath id="${id}c"><path data-r="clip" d="${opening(s.lid)}"/></clipPath>
<clipPath id="${id}r"><rect data-r="reveal" x="${f(revealX(s.draw))}" y="0" width="${f(revealW(s.draw))}" height="200" rx="${drawing ? 8 : 0}"/></clipPath>
<mask id="${id}m" maskUnits="userSpaceOnUse" x="0" y="0" width="200" height="200">
<g data-r="ball" transform="${ballT(s)}">
<circle cx="100" cy="100" r="43" fill="#fff"/>
<circle data-r="pupil" cx="100" cy="${f(pu.cy)}" r="${f(pu.r)}" fill="#000"/>
<path data-r="stem" d="${STEM}" fill="#000" transform="${stemT(s.key)}"/>
</g></mask>
<filter id="${id}f" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur data-r="blur" stdDeviation="${s.blur}"/></filter>
</defs>
<path data-r="halo" d="${outline(FINAL.lid)}" fill="none" style="stroke:${lidPaint}" stroke-width="4" opacity="${(0.6 * s.halo).toFixed(3)}" transform="${haloT(s.halo)}"${s.halo ? '' : ' display="none"'}/>
<g data-r="body"${s.blur ? ` filter="url(#${id}f)"` : ''} data-filter="url(#${id}f)">
<g clip-path="url(#${id}c)"><rect width="200" height="200" style="fill:${irisPaint}" mask="url(#${id}m)"/></g>
<g data-r="lids"${drawing ? ` clip-path="url(#${id}r)"` : ''} data-clip="url(#${id}r)" style="fill:${lidPaint}">
<path data-r="lower" d="${lowerShape()}"/>
<path data-r="upper" d="${upperShape(s.lid)}"/>
</g></g></svg>`;
  }

  // App icon: the mark on the Aurora night field, no alpha.
  function icon(size = 1024, p = {}) {
    const mark = markup(p, DARK, { title: false, idPrefix: 'ic' })
      .replace('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" role="img" class="sg-mark">',
        '<svg x="77" y="72" width="870" height="870" viewBox="0 0 200 200">');
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="${size}" height="${size}">
<defs>
<radialGradient id="icbg" cx="512" cy="430" r="760" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#1F2A48"/><stop offset="0.62" stop-color="#0E1424"/><stop offset="1" stop-color="#090D18"/></radialGradient>
<radialGradient id="icglow" cx="512" cy="540" r="320" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#A58AFF" stop-opacity="0.28"/><stop offset="1" stop-color="#A58AFF" stop-opacity="0"/></radialGradient>
</defs>
<rect width="1024" height="1024" fill="url(#icbg)"/>
<rect width="1024" height="1024" fill="url(#icglow)"/>
${mark}
</svg>`;
  }

  // Live handle for animation: mounts once, then only changes attributes.
  function mount(el, palette = THEMED, opts = {}) {
    el.innerHTML = markup({}, palette, opts);
    const q = (r) => el.querySelector(`[data-r="${r}"]`);
    const n = {
      clip: q('clip'), ball: q('ball'), pupil: q('pupil'), stem: q('stem'), blur: q('blur'),
      halo: q('halo'), body: q('body'), lids: q('lids'), upper: q('upper'), reveal: q('reveal'),
    };
    return {
      el,
      update(p) {
        const s = Object.assign({}, FINAL, p);
        n.clip.setAttribute('d', opening(s.lid));
        n.upper.setAttribute('d', upperShape(s.lid));
        n.ball.setAttribute('transform', ballT(s));
        const pu = pupil(s.key);
        n.pupil.setAttribute('cy', f(pu.cy));
        n.pupil.setAttribute('r', f(pu.r));
        n.stem.setAttribute('transform', stemT(s.key));
        if (s.draw < 1) {
          n.reveal.setAttribute('x', f(revealX(s.draw)));
          n.reveal.setAttribute('width', f(revealW(s.draw)));
          n.reveal.setAttribute('rx', '8');
          n.lids.setAttribute('clip-path', n.lids.dataset.clip);
        } else n.lids.removeAttribute('clip-path');
        if (s.blur > 0.01) {
          n.blur.setAttribute('stdDeviation', s.blur.toFixed(2));
          n.body.setAttribute('filter', n.body.dataset.filter);
        } else n.body.removeAttribute('filter');
        if (s.halo > 0.001) {
          n.halo.removeAttribute('display');
          n.halo.setAttribute('opacity', (0.6 * s.halo).toFixed(3));
          n.halo.setAttribute('transform', haloT(s.halo));
        } else n.halo.setAttribute('display', 'none');
      },
    };
  }

  root.StolenGlanceMark = { markup, icon, mount, FINAL, DARK, LIGHT, THEMED };
  if (typeof module !== 'undefined') module.exports = root.StolenGlanceMark;
})(typeof window !== 'undefined' ? window : globalThis);
