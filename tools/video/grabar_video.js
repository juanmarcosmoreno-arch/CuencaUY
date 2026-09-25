// Videos de presentación de CuencaUY (30 fps, 1920 × 1080). Dos guiones:
//   GUION=30 (por defecto): recorrido de 24 s → video de 30 s con el logo
//   GUION=45: recorrido de 39 s que suma rodeo, clima y Tendencias → video de 45 s
//
// Renderizado determinista: el reloj de la página (performance.now, Date.now,
// requestAnimationFrame, setTimeout/setInterval) se sustituye por uno que avanza
// exactamente 1/30 s por cuadro. Así las animaciones de MapLibre y la reproducción
// de la app salen fluidas aunque el WebGL por software sea lento.
//
// Requisitos: la app corriendo en APP_URL (por defecto http://127.0.0.1:3838),
// Node con playwright. Uso: [GUION=45] node tools/video/grabar_video.js <carpeta_cuadros>

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const APP_URL = process.env.APP_URL || 'http://127.0.0.1:3838';
const OUT = process.argv[2] || 'frames';
// tools/video/montar_video.sh le antepone la animación del logo (6 s).
const FPS = 30, DT = 1000 / FPS;
const GUION = process.env.GUION || '30';
const VW = 1536, VH = 864, DPR = 1.25;           // → 1920 × 1080
const AE_TARGET = { id: '0804006', lngLat: [-56.19734, -34.2405] };

// --- Reloj controlado (se inyecta antes que cualquier script de la página) ----
const CLOCK = `(() => {
  const rNow = performance.now.bind(performance);
  const rDate = Date.now.bind(Date);
  const rRAF = window.requestAnimationFrame.bind(window), rCAF = window.cancelAnimationFrame.bind(window);
  const rST = window.setTimeout.bind(window), rCT = window.clearTimeout.bind(window);
  const rSI = window.setInterval.bind(window), rCI = window.clearInterval.bind(window);
  const dateOff = rDate() - rNow();
  let on = false, t = 0, id = 1e7;
  const raf = new Map(), tim = new Map();
  performance.now = () => on ? t : rNow();
  Date.now = () => dateOff + performance.now();
  window.requestAnimationFrame = cb => { if (!on) return rRAF(cb); const i = ++id; raf.set(i, cb); return i; };
  window.cancelAnimationFrame = i => { raf.has(i) ? raf.delete(i) : rCAF(i); };
  window.setTimeout = (fn, d, ...a) => { if (!on || typeof fn !== 'function') return rST(fn, d, ...a); const i = ++id; tim.set(i, { at: t + (+d || 0), fn, a }); return i; };
  window.clearTimeout = i => { tim.has(i) ? tim.delete(i) : rCT(i); };
  window.setInterval = (fn, d, ...a) => { if (!on || typeof fn !== 'function') return rSI(fn, d, ...a); const i = ++id; tim.set(i, { at: t + Math.max(+d || 0, 1), fn, a, every: Math.max(+d || 0, 1) }); return i; };
  window.clearInterval = i => { tim.has(i) ? tim.delete(i) : rCI(i); };
  window.__clock = {
    start() { t = rNow(); on = true; },
    step(ms) {
      const end = t + ms;
      for (let guard = 0; guard < 500; guard++) {
        let nk = null, nv = null;
        for (const [k, v] of tim) if (v.at <= end && (!nv || v.at < nv.at)) { nk = k; nv = v; }
        if (!nv) break;
        t = Math.max(t, nv.at);
        if (nv.every) nv.at = t + nv.every; else tim.delete(nk);
        try { nv.fn(...nv.a); } catch (e) { console.error(e); }
      }
      t = end;
      const cbs = [...raf.values()]; raf.clear();
      for (const cb of cbs) { try { cb(t); } catch (e) { console.error(e); } }
    }
  };
})();`;

// --- Capa de presentación: portada, rótulos, cursor y cierre --------------------
const OVERLAY = `(() => {
  const css = document.createElement('style');
  css.textContent = \`
  #v-intro, #v-outro { position: fixed; inset: 0; z-index: 9999; display: grid; place-items: center;
    background: #F5F3EE; font-family: var(--font); color: #172B2A; text-align: center; }
  .v-card { max-width: 900px; padding: 0 40px; }
  .v-mark { width: 64px; height: 64px; border-radius: 16px; background: #176B60; color: #fff;
    display: grid; place-items: center; margin: 0 auto 28px; }
  .v-mark svg { width: 38px; height: 38px; }
  .v-title { font-size: 64px; font-weight: 700; letter-spacing: -0.03em; line-height: 1.05; margin: 0; }
  .v-sub { font-size: 26px; color: #667773; margin: 14px 0 0; font-weight: 450; }
  .v-meta { margin-top: 38px; font-size: 17px; color: #667773; letter-spacing: .02em; }
  .v-meta b { color: #176B60; font-weight: 600; }
  .v-rule { width: 56px; height: 3px; background: #176B60; border-radius: 3px; margin: 30px auto 0; }
  #v-cap { position: fixed; right: 28px; top: 300px; z-index: 9990;
    background: rgba(23, 43, 42, .94); color: #fff; border-radius: 14px; padding: 16px 26px 17px;
    font-family: var(--font); box-shadow: 0 12px 40px -12px rgba(23,43,42,.5); text-align: left;
    width: 400px; opacity: 0; }
  #v-cap .t { font-size: 26px; font-weight: 650; letter-spacing: -0.015em; line-height: 1.2; }
  #v-cap .s { font-size: 17px; color: #B9D6CB; margin-top: 5px; line-height: 1.35; }
  #v-cap .k { font-size: 12.5px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; color: #7FC4AC; margin-bottom: 6px; }
  #v-cursor { position: fixed; z-index: 9995; left: 0; top: 0; width: 30px; height: 30px; pointer-events: none;
    opacity: 0; filter: drop-shadow(0 3px 6px rgba(0,0,0,.28)); }
  #v-ripple { position: fixed; z-index: 9994; width: 46px; height: 46px; margin: -23px 0 0 -23px;
    border-radius: 50%; border: 3px solid #176B60; opacity: 0; pointer-events: none; }\`;
  document.head.appendChild(css);
  const mk = (id, html) => { const d = document.createElement('div'); d.id = id; d.innerHTML = html; document.body.appendChild(d); return d; };
  mk('v-intro', '');
  mk('v-outro', '<div class="v-card"><img src="brand/cuencauy-logo.png" alt="CuencaUY" style="width:640px;height:auto;display:block;margin:0 auto">' +
     '<p class="v-sub" style="margin-top:30px">637 áreas · 19 departamentos · 5 ejercicios · mapa 3D interactivo</p><div class="v-rule"></div>' +
     '<div class="v-meta">Datos abiertos: <b>MGAP (DICOSE–SNIG)</b> e <b>INALE</b> &nbsp;·&nbsp; Hecho con R, Shiny y MapLibre</div></div>');
  document.getElementById('v-outro').style.opacity = 0;
  mk('v-cap', '<div class="k"></div><div class="t"></div><div class="s"></div>');
  mk('v-ripple', '');
  mk('v-cursor', '<svg viewBox="0 0 24 24" width="30" height="30"><path d="M4 2.5l15 8.2-6.6 1.6 3.9 7.3-2.9 1.5-3.9-7.3L4.6 18z" fill="#172B2A" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>');
  window.__ov = {
    set(id, prop, v) { document.getElementById(id).style[prop] = v; },
    cap(k, t, s) { const c = document.getElementById('v-cap'); c.querySelector('.k').textContent = k; c.querySelector('.t').textContent = t; c.querySelector('.s').textContent = s; },
    center(sel) { const r = document.querySelector(sel).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; },
    project(ll) { const m = HTMLWidgets.find('#map').getMap(); const p = m.project(ll); const r = m.getContainer().getBoundingClientRect(); return [r.left + p.x, r.top + p.y]; }
  };
})();`;

// --- Guion ------------------------------------------------------------------------
const ease = x => x < 0 ? 0 : x > 1 ? 1 : x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
const fade = (t, a, b, dur = 0.45) => Math.min(ease((t - a) / dur), 1 - ease((t - (b - dur)) / dur));

// Tramos comunes a ambos guiones (0–21 s): producción, línea temporal, áreas,
// variación anual y detalle de una zona.
const BASE_CAPTIONS = [
  { a: 0.2, b: 3.6, k: 'Ejercicio 2025', t: 'Producción de leche por departamento', s: 'La altura y el color muestran los litros declarados.' },
  { a: 3.8, b: 10.4, k: 'Línea temporal', t: 'Cinco ejercicios, 2021 → 2025', s: 'Declaraciones juradas DICOSE–SNIG del MGAP.' },
  { a: 10.6, b: 13.8, k: 'Más detalle', t: '637 áreas de enumeración', s: 'Escala de raíz cuadrada para leer todo el territorio.' },
  { a: 14.0, b: 17.2, k: 'Cambio anual', t: 'Dónde crece y dónde cae', s: 'Variación de la producción respecto al ejercicio anterior.' },
  { a: 17.4, b: 20.8, k: 'Cada zona', t: 'Su serie histórica, con fuente', s: 'Valor, cambio anual y observaciones de método.', right: '392px' },
];
const BASE_MOVES = [
  { at: 3.9, move: 0.6, to: { sel: '.tl-year[data-year="2021"]' }, click: `document.querySelector('.tl-year[data-year="2021"]').click()` },
  { at: 4.8, move: 0.5, to: { sel: '#btn-play' }, click: `document.querySelector('#btn-play').click()` },
  { at: 10.7, move: 0.6, to: { sel: 'label:has(input[name=level][value=ae])' }, click: `document.querySelector('input[name=level][value=ae]').click()` },
  { at: 12.0, move: 0.5, to: { sel: 'label:has(input[name=transform][value=sqrt])' }, click: `document.querySelector('input[name=transform][value=sqrt]').click()` },
  { at: 14.1, move: 0.6, to: { sel: 'label:has(input[name=mode][value=change])' }, click: `document.querySelector('input[name=mode][value=change]').click()` },
  { at: 17.5, move: 0.8, to: { ll: AE_TARGET.lngLat }, click: `Shiny.setInputValue('atlas_select', {id: '${AE_TARGET.id}', level: 'ae', t: Date.now()}, {priority: 'event'})` },
];
const BASE_CAMERA = [
  { at: 0.1, js: `HTMLWidgets.find('#map').getMap().easeTo({bearing: -26, pitch: 50, duration: 3600, easing: t => t < .5 ? 2*t*t : 1 - Math.pow(-2*t+2, 2)/2})` },
  { at: 14.9, js: `HTMLWidgets.find('#map').getMap().easeTo({bearing: -10, pitch: 48, duration: 2200})` },
];

const GUIONES = {
  '30': { duration: 24, captions: BASE_CAPTIONS, moves: BASE_MOVES, camera: BASE_CAMERA, cursor: [3.7, 20.9], outro: 21.0 },
  '45': {
    duration: 39,
    captions: [
      ...BASE_CAPTIONS,
      { a: 21.2, b: 24.6, k: 'Rodeo y tambos', t: 'Litros por vaca', s: 'Vacas, productividad y tambos lecheros, también por área.' },
      { a: 24.8, b: 28.0, k: 'Clima', t: 'La sequía de 2022–23', s: 'Lluvia frente a lo normal (CHIRPS); la altura sigue siendo la leche.' },
      { a: 28.2, b: 32.4, k: 'Tendencias', t: 'La leche mes a mes', s: 'Una línea por año, con el valor exacto al pasar el cursor.' },
      { a: 32.6, b: 35.6, k: 'Tendencias', t: 'Precio, rodeo y clima', s: 'Gráficas interactivas con datos públicos, descargables en CSV.' },
    ],
    moves: [
      ...BASE_MOVES,
      { at: 21.1, move: 0.5, to: { sel: '#btn-close-detail' }, click: `document.querySelector('#btn-close-detail').click()` },
      { at: 21.8, move: 0.5, to: { sel: 'label:has(input[name=mode][value=value])' }, click: `document.querySelector('input[name=mode][value=value]').click()` },
      { at: 22.5, move: 0.6, to: { sel: 'label:has(input[name=indicator][value=lpv])' }, click: `document.querySelector('input[name=indicator][value=lpv]').click()` },
      { at: 24.8, move: 0.6, to: { sel: 'label:has(input[name=indicator][value=lluvia])' }, click: `document.querySelector('input[name=indicator][value=lluvia]').click()` },
      { at: 25.8, move: 0.6, to: { sel: '.tl-year[data-year="2023"]' }, click: `document.querySelector('.tl-year[data-year="2023"]').click()` },
      { at: 28.1, move: 0.7, to: { sel: '#btn-tendencias' }, click: `document.querySelector('#btn-tendencias').click()` },
      // Sobre la línea de 2026 (el mouse real también se mueve para que Shiny muestre el tooltip).
      { at: 30.0, move: 0.9, real: true, to: { plot: [0.545, 0.2] }, click: "" },
      { at: 32.7, move: 0.6, to: { sel: '#tv_view label:has(input[value=precio])' }, click: `document.querySelector('#tv_view input[value=precio]').click()` },
      { at: 34.3, move: 0.5, to: { sel: '#tv_view label:has(input[value=clima])' }, click: `document.querySelector('#tv_view input[value=clima]').click()` },
    ],
    camera: [
      ...BASE_CAMERA,
      { at: 21.3, js: `HTMLWidgets.find('#map').getMap().easeTo({bearing: -18, pitch: 50, zoom: HTMLWidgets.find('#map').getMap().getZoom() - 0.35, duration: 3000})` },
    ],
    cursor: [3.7, 35.4], outro: 35.8,
    outroSub: '637 áreas · 19 departamentos · rodeo, clima y tendencias',
    outroMeta: 'Datos abiertos: <b>MGAP (DICOSE–SNIG)</b>, <b>INALE</b> y <b>CHIRPS</b> &nbsp;·&nbsp; Hecho con R, Shiny y MapLibre',
    // La ventana de Tendencias se corre a la izquierda para dejar lugar al rótulo.
    css: `.modal-xl { max-width: 1010px !important; margin-left: 36px !important; } #v-cap { top: 360px; }`,
  },
};
const G = GUIONES[GUION];
if (!G) throw new Error('GUION desconocido: ' + GUION);
const DURATION = G.duration, CAPTIONS = G.captions, CAMERA = G.camera;
const plan = () => G.moves.map(m => ({ ...m }));

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--hide-scrollbars'] });
  const ctx = await browser.newContext({ viewport: { width: VW, height: VH }, deviceScaleFactor: DPR });
  await ctx.addInitScript(CLOCK);
  const page = await ctx.newPage();
  page.on('pageerror', e => console.error('pageerror', e.message));
  await page.goto(APP_URL, { waitUntil: 'networkidle' });
  await page.waitForTimeout(6000);                     // carga del mapa base y datos
  await page.evaluate(() => { const i = document.getElementById('intro'); if (i) i.remove(); });   // la intro de la app se monta aparte
  await page.evaluate(OVERLAY);
  if (G.outroSub) await page.evaluate(g => {
    document.querySelector('#v-outro .v-sub').textContent = g.outroSub;
    document.querySelector('#v-outro .v-meta').innerHTML = g.outroMeta;
  }, { outroSub: G.outroSub, outroMeta: G.outroMeta });
  if (G.css) await page.evaluate(css => { const st = document.createElement('style'); st.textContent = css; document.head.appendChild(st); }, G.css);
  await page.waitForTimeout(500);
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Animation.enable');
  await page.evaluate(() => window.__clock.start());

  const moves = plan();
  let cursor = [VW * 0.62, VH * 0.58], from = null, cur = null;
  let capIdx = -1, lastReal = Date.now(), rate = 0.15;
  const pending = new Set(CAMERA.map((_, i) => i));
  const clicked = new Set();

  for (let f = 0; f < FPS * DURATION; f++) {
    const t = f / FPS;
    // Transiciones CSS al ritmo del video (el tiempo real por cuadro varía).
    const now = Date.now(); const realMs = Math.max(now - lastReal, 30); lastReal = now;
    const target = Math.min(1, Math.max(0.03, DT / realMs));
    if (Math.abs(target - rate) / rate > 0.25) { rate = target; await cdp.send('Animation.setPlaybackRate', { playbackRate: rate }); }

    await page.evaluate(ms => window.__clock.step(ms), DT);

    for (const i of [...pending]) if (t >= CAMERA[i].at) { await page.evaluate(CAMERA[i].js); pending.delete(i); }

    // Cursor
    for (const [i, m] of moves.entries()) {
      if (t >= m.at && t < m.at + m.move && (cur !== i)) {
        cur = i; from = cursor.slice();
        m.dest = m.to.sel ? await page.evaluate(s => window.__ov.center(s), m.to.sel)
               : m.to.plot ? await page.evaluate(f => { const r = document.querySelector('#tv_plot img').getBoundingClientRect(); return [r.left + r.width * f[0], r.top + r.height * f[1]]; }, m.to.plot)
               : await page.evaluate(ll => window.__ov.project(ll), m.to.ll);
      }
      if (cur === i && t < m.at + m.move) {
        const k = ease((t - m.at) / m.move);
        cursor = [from[0] + (m.dest[0] - from[0]) * k, from[1] + (m.dest[1] - from[1]) * k];
        if (m.real) await page.mouse.move(cursor[0], cursor[1]);
      }
      if (t >= m.at + m.move + 0.1 && !clicked.has(i)) {
        clicked.add(i); cursor = m.dest.slice();
        if (m.real) await page.mouse.move(cursor[0] + 1, cursor[1]);
        if (m.click) { m.clickAt = t; await page.evaluate(m.click); }
      }
    }
    const lastClick = Math.max(...moves.map(m => (m.clickAt !== undefined && t - m.clickAt < 0.5) ? m.clickAt : -9));
    const rp = lastClick > 0 ? (t - lastClick) / 0.5 : 1;
    const cursorOpacity = (t > G.cursor[0] && t < G.cursor[1]) ? Math.min(1, (t - G.cursor[0]) / 0.3) : 0;

    // Rótulos
    let ci = CAPTIONS.findIndex(c => t >= c.a && t < c.b);
    if (ci !== capIdx && ci >= 0) { const c = CAPTIONS[ci]; await page.evaluate(c => window.__ov.cap(c.k, c.t, c.s), c); }
    capIdx = ci >= 0 ? ci : capIdx;
    const capOp = ci >= 0 ? fade(t, CAPTIONS[ci].a, CAPTIONS[ci].b) : 0;
    const capY = ci >= 0 ? (1 - ease(Math.min(1, (t - CAPTIONS[ci].a) / 0.45))) * 14 : 0;

    await page.evaluate(s => {
      const o = window.__ov;
      o.set('v-intro', 'opacity', s.intro); o.set('v-intro', 'display', s.intro > 0 ? 'grid' : 'none');
      o.set('v-outro', 'opacity', s.outro); o.set('v-outro', 'display', s.outro > 0 ? 'grid' : 'none');
      o.set('v-cap', 'opacity', s.cap); o.set('v-cap', 'right', s.capRight); o.set('v-cap', 'transform', `translateY(${s.capY}px)`);
      o.set('v-cursor', 'opacity', s.cur); o.set('v-cursor', 'transform', `translate(${s.x - 4}px, ${s.y - 3}px)`);
      o.set('v-ripple', 'left', s.x + 'px'); o.set('v-ripple', 'top', s.y + 'px');
      o.set('v-ripple', 'opacity', s.rp < 1 ? (1 - s.rp) * 0.9 : 0);
      o.set('v-ripple', 'transform', `scale(${0.4 + s.rp * 0.9})`);
    }, { intro: 0, outro: ease((t - G.outro) / 0.6), cap: capOp, capY,
         capRight: (ci >= 0 && CAPTIONS[ci].right) || '28px', cur: cursorOpacity, x: cursor[0], y: cursor[1], rp });

    const shot = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 93 });
    fs.writeFileSync(path.join(OUT, `f${String(f).padStart(4, '0')}.jpg`), Buffer.from(shot.data, 'base64'));
    if (f % 60 === 0) console.log(`cuadro ${f}/${FPS * DURATION} (t = ${t.toFixed(1)} s, año ${await page.evaluate(() => document.querySelector('.year-value').textContent)})`);
  }
  await browser.close();
})();
