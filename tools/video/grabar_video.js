// Video de presentación del Atlas Lechero Uruguay (30 s, 30 fps, 1920 × 1080).
//
// Renderizado determinista: el reloj de la página (performance.now, Date.now,
// requestAnimationFrame, setTimeout/setInterval) se sustituye por uno que avanza
// exactamente 1/30 s por cuadro. Así las animaciones de MapLibre y la reproducción
// de la app salen fluidas aunque el WebGL por software sea lento.
//
// Requisitos: la app corriendo en APP_URL (por defecto http://127.0.0.1:3838),
// Node con playwright. Uso: node tools/video/grabar_video.js <carpeta_cuadros>

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const APP_URL = process.env.APP_URL || 'http://127.0.0.1:3838';
const OUT = process.argv[2] || 'frames';
const FPS = 30, DURATION = 30, DT = 1000 / FPS;
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
  const mark = document.querySelector('.brand-mark').innerHTML;
  const mk = (id, html) => { const d = document.createElement('div'); d.id = id; d.innerHTML = html; document.body.appendChild(d); return d; };
  mk('v-intro', '<div class="v-card"><div class="v-mark">' + mark + '</div><h1 class="v-title">Atlas Lechero Uruguay</h1>' +
     '<p class="v-sub">La producción de leche, territorio por territorio</p><div class="v-rule"></div>' +
     '<div class="v-meta">Datos oficiales <b>DICOSE–SNIG · MGAP</b> &nbsp;·&nbsp; ejercicios 2021–2025</div></div>');
  mk('v-outro', '<div class="v-card"><div class="v-mark">' + mark + '</div><h1 class="v-title">Atlas Lechero Uruguay</h1>' +
     '<p class="v-sub">637 áreas · 19 departamentos · 5 ejercicios · mapa 3D interactivo</p><div class="v-rule"></div>' +
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

const CAPTIONS = [
  { a: 3.1, b: 7.5, k: 'Ejercicio 2025', t: 'Producción de leche por departamento', s: 'La altura y el color muestran los litros declarados.' },
  { a: 7.8, b: 14.2, k: 'Línea temporal', t: 'Cinco ejercicios, 2021 → 2025', s: 'Declaraciones juradas DICOSE–SNIG del MGAP.' },
  { a: 14.5, b: 18.0, k: 'Más detalle', t: '637 áreas de enumeración', s: 'Escala de raíz cuadrada para leer todo el territorio.' },
  { a: 18.3, b: 21.8, k: 'Cambio anual', t: 'Dónde crece y dónde cae', s: 'Variación de la producción respecto al ejercicio anterior.' },
  { a: 22.1, b: 26.4, k: 'Cada zona', t: 'Su serie histórica, con fuente', s: 'Valor, cambio anual y observaciones de método.' },
];

// Movimientos del cursor: [inicio, fin, destino] y clics [tiempo, acción]
function plan() {
  return [
    { at: 7.9, move: 0.7, to: { sel: '.tl-year[data-year="2021"]' }, click: `document.querySelector('.tl-year[data-year="2021"]').click()` },
    { at: 8.9, move: 0.6, to: { sel: '#btn-play' }, click: `document.querySelector('#btn-play').click()` },
    { at: 14.6, move: 0.7, to: { sel: 'label:has(input[name=level][value=ae])' }, click: `document.querySelector('input[name=level][value=ae]').click()` },
    { at: 15.9, move: 0.6, to: { sel: 'label:has(input[name=transform][value=sqrt])' }, click: `document.querySelector('input[name=transform][value=sqrt]').click()` },
    { at: 18.4, move: 0.7, to: { sel: 'label:has(input[name=mode][value=change])' }, click: `document.querySelector('input[name=mode][value=change]').click()` },
    { at: 22.2, move: 0.9, to: { ll: AE_TARGET.lngLat }, click: `Shiny.setInputValue('atlas_select', {id: '${AE_TARGET.id}', level: 'ae', t: Date.now()}, {priority: 'event'})` },
  ];
}

const CAMERA = [
  { at: 3.0, js: `HTMLWidgets.find('#map').getMap().easeTo({bearing: -26, pitch: 50, duration: 4800, easing: t => t < .5 ? 2*t*t : 1 - Math.pow(-2*t+2, 2)/2})` },
  { at: 18.8, js: `HTMLWidgets.find('#map').getMap().easeTo({bearing: -10, pitch: 48, duration: 2600})` },
];

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--hide-scrollbars'] });
  const ctx = await browser.newContext({ viewport: { width: VW, height: VH }, deviceScaleFactor: DPR });
  await ctx.addInitScript(CLOCK);
  const page = await ctx.newPage();
  page.on('pageerror', e => console.error('pageerror', e.message));
  await page.goto(APP_URL, { waitUntil: 'networkidle' });
  await page.waitForTimeout(6000);                     // carga del mapa base y datos
  await page.evaluate(OVERLAY);
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
                          : await page.evaluate(ll => window.__ov.project(ll), m.to.ll);
      }
      if (cur === i && t < m.at + m.move) {
        const k = ease((t - m.at) / m.move);
        cursor = [from[0] + (m.dest[0] - from[0]) * k, from[1] + (m.dest[1] - from[1]) * k];
      }
      if (t >= m.at + m.move + 0.1 && !clicked.has(i)) {
        clicked.add(i); cursor = m.dest.slice(); m.clickAt = t;
        await page.evaluate(m.click);
      }
    }
    const lastClick = Math.max(...moves.map(m => (m.clickAt !== undefined && t - m.clickAt < 0.5) ? m.clickAt : -9));
    const rp = lastClick > 0 ? (t - lastClick) / 0.5 : 1;
    const cursorOpacity = (t > 7.5 && t < 26.3) ? Math.min(1, (t - 7.5) / 0.3) : 0;

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
    }, { intro: 1 - ease((t - 2.4) / 0.6), outro: ease((t - 26.5) / 0.6), cap: capOp, capY,
         capRight: ci === 4 ? '392px' : '28px', cur: cursorOpacity, x: cursor[0], y: cursor[1], rp });

    const shot = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 93 });
    fs.writeFileSync(path.join(OUT, `f${String(f).padStart(4, '0')}.jpg`), Buffer.from(shot.data, 'base64'));
    if (f % 60 === 0) console.log(`cuadro ${f}/${FPS * DURATION} (t = ${t.toFixed(1)} s, año ${await page.evaluate(() => document.querySelector('.year-value').textContent)})`);
  }
  await browser.close();
})();
