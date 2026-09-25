/* Atlas Lechero Uruguay — comportamiento del cliente
 *
 * El widget de mapgl se construye una sola vez. Este script trabaja sobre la
 * instancia de MapLibre del widget para: cámara (zoom, volver a Uruguay, 2D/3D),
 * selección por clic, tooltip, buscador, línea temporal y reproducción.
 * Los cambios de estilo por ejercicio llegan desde el servidor vía maplibre_proxy.
 */
(function () {
  "use strict";

  var UY_BOUNDS = [[-58.44, -35.0], [-53.07, -30.08]];
  var PITCH_3D = 45, BEARING_3D = -8;

  var S = {
    map: null,
    years: [], yearsAll: [], year: null,
    playing: false, timer: null, speed: 1200,
    ind: "prod", level: "dep", mode: "value", dim: "3d",
    label: "Producción", unit: "L",
    search: [], layers: ["dep-3d", "ae-3d"],
    popup: null, basemapFailed: false, detailOpen: false
  };

  var $ = function (sel) { return document.querySelector(sel); };
  var fmt = new Intl.NumberFormat("es-UY", { maximumFractionDigits: 0 });
  var fmt1 = new Intl.NumberFormat("es-UY", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  var isMobile = function () { return window.matchMedia("(max-width: 760px)").matches; };

  function setInput(name, value, event) {
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue(name, value, event ? { priority: "event" } : undefined);
    }
  }

  function norm(s) {
    return (s || "").toString().normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  /* Cámara ----------------------------------------------------------------- */

  function cameraPadding() {
    var gap = isMobile() ? 10 : 16;
    var atlas = $("#atlas");
    var left = gap, right = gap + (isMobile() ? 44 : 56), top = gap, bottom = gap;
    var panel = $("#panel-left");
    if (!isMobile() && panel && !panel.classList.contains("is-collapsed")) left += panel.offsetWidth + gap;
    var ov = $(".overlay-top");
    if (ov) top += ov.offsetHeight + (isMobile() ? 4 : 8);
    if (!isMobile() && atlas.classList.contains("detail-open")) {
      var d = $("#panel-detail"); if (d) right += d.offsetWidth + gap;
    }
    var lg = $(".legend");
    if (lg && isMobile()) bottom += lg.offsetHeight;
    return { top: top, bottom: bottom, left: left, right: right };
  }

  function fitHome(animate) {
    if (!S.map) return;
    var pitch = S.dim === "3d" ? PITCH_3D : 0;
    var bearing = S.dim === "3d" ? BEARING_3D : 0;
    var cam = S.map.cameraForBounds(UY_BOUNDS, { padding: cameraPadding(), bearing: bearing });
    if (!cam) return;
    // En vista oblicua el borde lejano se comprime: se aleja levemente para que
    // las extrusiones más altas no queden cortadas.
    var zoom = cam.zoom - (pitch ? 0.18 : 0);
    var opts = { center: cam.center, zoom: zoom, pitch: pitch, bearing: bearing };
    if (animate) S.map.easeTo(Object.assign(opts, { duration: 900 }));
    else S.map.jumpTo(opts);
  }

  function setDim(dim, fromUser) {
    S.dim = dim;
    var b = $("#btn-dim");
    if (b) {
      b.textContent = dim === "3d" ? "3D" : "2D";
      b.setAttribute("aria-pressed", dim === "3d" ? "true" : "false");
      b.setAttribute("aria-label", dim === "3d" ? "Cambiar a vista 2D" : "Cambiar a vista 3D");
    }
    setInput("dim", dim);
    if (S.map && fromUser) {
      S.map.easeTo({ pitch: dim === "3d" ? PITCH_3D : 0,
                     bearing: dim === "3d" ? S.map.getBearing() || BEARING_3D : 0,
                     duration: 700 });
    }
  }

  /* Línea temporal --------------------------------------------------------- */

  function renderTimeline() {
    var btns = document.querySelectorAll(".tl-year");
    var idx = S.yearsAll.indexOf(S.year);
    btns.forEach(function (b) {
      var y = parseInt(b.getAttribute("data-year"), 10);
      b.classList.toggle("is-active", y === S.year);
      b.classList.toggle("is-past", S.yearsAll.indexOf(y) < idx && S.years.indexOf(y) >= 0);
      b.setAttribute("aria-current", y === S.year ? "true" : "false");
    });
    var track = $("#tl-track"), prog = $("#tl-progress"), active = $(".tl-year.is-active");
    if (track && prog && active) {
      var tr = track.getBoundingClientRect(), ar = active.getBoundingClientRect();
      prog.style.width = Math.max(0, ar.left + ar.width / 2 - tr.left - 14) + "px";
    }
    var i = S.years.indexOf(S.year);
    var prev = $("#btn-prev"), next = $("#btn-next");
    if (prev) prev.disabled = i <= 0;
    if (next) next.disabled = i >= S.years.length - 1;
  }

  function setYear(y) {
    if (S.years.indexOf(y) < 0) return;
    S.year = y;
    renderTimeline();
    setInput("year", y);
  }

  function step(dir) {
    var i = S.years.indexOf(S.year) + dir;
    if (i >= 0 && i < S.years.length) setYear(S.years[i]);
  }

  function setPlaying(on) {
    S.playing = on;
    clearTimeout(S.timer);
    var b = $("#btn-play");
    if (b) {
      b.setAttribute("aria-label", on ? "Pausar" : "Reproducir");
      b.setAttribute("title", on ? "Pausar (barra espaciadora)" : "Reproducir (barra espaciadora)");
      b.querySelector(".ic-play").style.display = on ? "none" : "";
      b.querySelector(".ic-pause").style.display = on ? "" : "none";
    }
    if (on) {
      // Desde el último ejercicio, la reproducción recomienza por el primero.
      if (S.years.indexOf(S.year) === S.years.length - 1) setYear(S.years[0]);
      schedule();
    }
  }

  function schedule() {
    clearTimeout(S.timer);
    S.timer = setTimeout(function () {
      if (!S.playing) return;
      var i = S.years.indexOf(S.year);
      if (i >= S.years.length - 1) { setPlaying(false); return; }
      setYear(S.years[i + 1]);
      if (S.years.indexOf(S.year) >= S.years.length - 1) setPlaying(false);
      else schedule();
    }, S.speed);
  }

  /* Mapa: clic, tooltip, fallos del mapa base ------------------------------ */

  function activeLayer() { return S.level === "ae" ? "ae-3d" : "dep-3d"; }

  function tooltipHtml(p) {
    var y = S.year, k = S.ind;
    var v = p[k + "_" + y];
    var val;
    var prodLine = "";
    if (k === "lluvia" || k === "thi") {
      var pv = p["prod_" + y];
      prodLine = '<div class="tt-sub">Producción: ' + (pv === undefined || pv === null ? "sin datos" :
        pv >= 1e6 ? fmt1.format(pv / 1e6) + " M L" : fmt.format(pv) + " L") + "</div>";
    }
    if (v === undefined || v === null) val = "sin datos";
    else if (k === "lluvia") val = (v > 0 ? "+" : v < 0 ? "−" : "") + fmt.format(Math.abs(v)) + " % vs. normal";
    else if (k === "thi") val = fmt.format(v) + (v === 1 ? " día" : " días");
    else if (k === "vacas") val = fmt.format(v) + (v === 1 ? " vaca" : " vacas");
    else if (k === "lpv") val = fmt.format(v) + " L/vaca";
    else if (k === "tambos") val = fmt.format(v) + (v === 1 ? " tambo" : " tambos");
    else if (k === "prod" || k === "venta") val = v >= 1e6 ? fmt1.format(v / 1e6) + " M L" : fmt.format(v) + " L";
    else if (k === "dens") val = fmt.format(v) + " L/km²";
    else val = fmt.format(v) + (v === 1 ? " tenedor" : " tenedores");
    var sub = "";
    if (S.mode === "change" && !S.climate) {
      var s = p[k + "_" + y + "_s"], c = p[k + "_" + y + "_c"];
      if (s === 0 && c !== null && c !== undefined) sub = (c > 0 ? "+" : c < 0 ? "−" : "") + fmt1.format(Math.abs(c)) + " % vs. " + (y - 1);
      else if (s === 1) sub = "Sin base de comparación";
      else if (s === 2) sub = "Sin producción";
      else if (s === 4) sub = "Sin dato en este ejercicio";
      else sub = "Sin ejercicio anterior";
    }
    var name = S.level === "ae" ? p.name + " · " + p.dep_name : p.dep_name;
    return '<div class="tt-name">' + escapeHtml(name) + '</div>' +
      '<div class="tt-val">' + escapeHtml(S.label) + " " + y + ": <strong>" + val + "</strong></div>" +
      (sub ? '<div class="tt-sub">' + sub + "</div>" : "") + prodLine;
  }

  function bindMap(map) {
    S.map = map;
    S.popup = new maplibregl.Popup({ closeButton: false, closeOnClick: false, offset: 12, maxWidth: "260px" });

    S.layers.forEach(function (layer) {
      map.on("mousemove", layer, function (e) {
        if (!e.features || !e.features.length || isMobile()) return;
        map.getCanvas().style.cursor = "pointer";
        S.popup.setLngLat(e.lngLat).setHTML(tooltipHtml(e.features[0].properties)).addTo(map);
      });
      map.on("mouseleave", layer, function () {
        map.getCanvas().style.cursor = "";
        S.popup.remove();
      });
    });

    map.on("click", function (e) {
      var feats = map.queryRenderedFeatures(e.point, { layers: [activeLayer()] });
      if (feats.length) {
        setInput("atlas_select", { id: feats[0].properties.id, level: S.level, t: Date.now() }, true);
      } else if (S.detailOpen) {
        setInput("atlas_select", { id: "", t: Date.now() }, true);
      }
    });

    // Si las teselas, tipografías o íconos del mapa base fallan, se avisa y se
    // oculta el mapa base; las geometrías del atlas son locales.
    // Un error aislado de tesela (p. ej. al mover rápido la cámara) no basta:
    // se exige que la fuente nunca haya cargado o una racha de errores.
    var tileErrors = 0;
    map.on("error", function (e) {
      var err = e && e.error;
      var msg = (err && (err.message || err.status)) + "";
      if (err && err.name === "AbortError" || /abort/i.test(msg)) return;
      var src = e && e.sourceId;
      if (src === "openmaptiles" || /openfreemap|glyph|sprite|Failed to fetch|NetworkError/i.test(msg)) {
        tileErrors++;
        var loaded = false;
        try { loaded = map.isSourceLoaded("openmaptiles"); } catch (x) { /* sin fuente */ }
        if (tileErrors >= 12 || (!loaded && tileErrors >= 4 && !S.basemapSeen)) basemapFailed();
      }
    });
    map.on("sourcedata", function (e) {
      if (e.sourceId === "openmaptiles" && e.isSourceLoaded) S.basemapSeen = true;
    });
    // Si en 15 s ninguna tesela del mapa base llegó a cargar, se considera caído.
    setTimeout(function () {
      try {
        if (map.getSource("openmaptiles") && !S.basemapSeen) basemapFailed();
      } catch (err) { /* estilo sin mapa base */ }
    }, 15000);

    map.on("load", function () { fitHome(false); });
    if (map.loaded()) fitHome(false);
    map.on("pitchend", function () {
      var d = map.getPitch() > 5 ? "3d" : "2d";
      if (d !== S.dim) setDim(d, false);
    });
  }

  function basemapFailed() {
    if (S.basemapFailed || !S.map) return;
    S.basemapFailed = true;
    var el = $("#basemap-status"); if (el) el.classList.add("show");
    try {
      S.map.getStyle().layers.forEach(function (l) {
        if (l.source === "openmaptiles") S.map.setLayoutProperty(l.id, "visibility", "none");
      });
    } catch (err) { /* nada que ocultar */ }
    setTimeout(function () { if (el) el.classList.remove("show"); }, 9000);
  }

  function waitForMap() {
    var tries = 0;
    (function poll() {
      var w = window.HTMLWidgets && HTMLWidgets.find("#map");
      var m = w && w.getMap && w.getMap();
      if (m) { bindMap(m); return; }
      if (++tries < 600) setTimeout(poll, 50);
    })();
  }

  /* Buscador --------------------------------------------------------------- */

  var searchSel = -1, searchHits = [];

  function renderSearch(q) {
    var ul = $("#search-results"), box = $(".search");
    q = norm(q).trim();
    ul.innerHTML = "";
    searchSel = -1;
    if (!q) { searchHits = []; box.setAttribute("aria-expanded", "false"); return; }
    searchHits = S.search.filter(function (r) {
      return norm(r.name).indexOf(q) >= 0 || norm(r.dep).indexOf(q) >= 0 || r.id.indexOf(q) >= 0;
    }).sort(function (a, b) {
      // Primero departamentos y coincidencias al inicio del nombre.
      var sa = (a.level === "dep" ? 0 : 2) + (norm(a.name).indexOf(q) === 0 ? 0 : 1);
      var sb = (b.level === "dep" ? 0 : 2) + (norm(b.name).indexOf(q) === 0 ? 0 : 1);
      return sa - sb;
    }).slice(0, 8);
    searchHits.forEach(function (r, i) {
      var li = document.createElement("li");
      var b = document.createElement("button");
      b.type = "button"; b.setAttribute("role", "option"); b.id = "sr-" + i;
      b.innerHTML = "<span>" + escapeHtml(r.level === "dep" ? r.name : r.name + " · " + r.dep) +
        "</span><small>" + (r.level === "dep" ? "Departamento" : "AE " + r.id) + "</small>";
      b.addEventListener("click", function () { chooseSearch(r); });
      li.appendChild(b); ul.appendChild(li);
    });
    if (!searchHits.length) ul.innerHTML = '<li><button type="button" disabled><span>Sin resultados</span></button></li>';
    box.setAttribute("aria-expanded", "true");
  }

  function chooseSearch(r) {
    $("#search-input").value = r.level === "dep" ? r.name : r.name + " · " + r.dep;
    $("#search-results").innerHTML = "";
    setInput("atlas_select", { id: r.id, level: r.level, t: Date.now() }, true);
    if (S.map && r.bbox) {
      S.map.fitBounds([[r.bbox[0], r.bbox[1]], [r.bbox[2], r.bbox[3]]], {
        padding: cameraPadding(), maxZoom: r.level === "dep" ? 7.6 : 8.6,
        pitch: S.dim === "3d" ? PITCH_3D : 0, bearing: S.map.getBearing(), duration: 900
      });
    }
    if (isMobile()) toggleSheet(false);
  }

  /* Paneles ---------------------------------------------------------------- */

  function toggleSheet(open) {
    var atlas = $("#atlas"), panel = $("#panel-left");
    if (isMobile()) {
      atlas.classList.toggle("sheet-controls", open);
      panel.classList.toggle("is-collapsed", !open);
    } else {
      panel.classList.toggle("is-collapsed", !open);
      atlas.classList.toggle("left-collapsed", !open);
    }
    $("#btn-expand").setAttribute("aria-expanded", open ? "true" : "false");
    if (open) { var f = panel.querySelector("input:checked"); if (f && !isMobile()) f.focus({ preventScroll: true }); }
  }

  /* Enlaces con Shiny ------------------------------------------------------ */

  function bindShiny() {
    Shiny.addCustomMessageHandler("atlas-init", function (m) {
      S.years = m.years.map(Number);
      S.yearsAll = m.years_all.map(Number);
      S.search = m.search || [];
      S.layers = m.layers || S.layers;
      S.year = Number(m.year);
      renderTimeline();
      setInput("year", S.year);
      setInput("dim", S.dim);
    });
    Shiny.addCustomMessageHandler("atlas-state", function (m) {
      S.ind = m.ind; S.level = m.level; S.mode = m.mode; S.label = m.label; S.unit = m.unit;
      S.climate = !!m.climate;
      // El clima no tiene modo de variación: se desactiva mientras esté elegido.
      document.querySelectorAll('input[name="mode"]').forEach(function (r) {
        r.disabled = S.climate && r.value === "change";
      });
      var mg = document.getElementById("mode");
      if (mg) mg.setAttribute("title", S.climate ? "Con indicadores climáticos el color muestra el clima del ejercicio" : "");
      if (S.popup) S.popup.remove();
    });
    Shiny.addCustomMessageHandler("atlas-detail", function (m) {
      var was = S.detailOpen;
      S.detailOpen = !!m.open;
      $("#atlas").classList.toggle("detail-open", S.detailOpen);
      if (S.detailOpen && isMobile()) {
        toggleSheet(false);
        // La hoja de detalle cubre la mitad inferior: se sube la vista para que
        // la zona elegida quede visible encima.
        if (!was && S.map) {
          setTimeout(function () {
            var d = $("#panel-detail");
            if (d) S.map.panBy([0, Math.round(d.offsetHeight / 2)], { duration: 450 });
          }, 320);
        }
      }
      if (S.detailOpen && !was) {
        setTimeout(function () { var c = $("#btn-close-detail"); if (c && !isMobile()) c.focus({ preventScroll: true }); }, 350);
      }
    });
  }

  function bindUi() {
    document.addEventListener("click", function (e) {
      var t = e.target.closest("button");
      if (!t) return;
      switch (t.id) {
        case "btn-zoom-in": S.map && S.map.zoomIn(); break;
        case "btn-zoom-out": S.map && S.map.zoomOut(); break;
        case "btn-home": fitHome(true); break;
        case "btn-dim": setDim(S.dim === "3d" ? "2d" : "3d", true); break;
        case "btn-play": setPlaying(!S.playing); break;
        case "btn-prev": setPlaying(false); step(-1); break;
        case "btn-next": setPlaying(false); step(1); break;
        case "btn-collapse": toggleSheet(false); break;
        case "btn-expand": toggleSheet(!(isMobile() ? $("#atlas").classList.contains("sheet-controls") : !$("#panel-left").classList.contains("is-collapsed"))); break;
        case "btn-close-detail": setInput("close_detail", Date.now(), true); break;
        case "btn-about": setInput("about", Date.now(), true); break;
      }
      if (t.classList.contains("tl-year") && !t.disabled) {
        setYear(parseInt(t.getAttribute("data-year"), 10));
        if (S.playing) schedule();
      }
    });

    document.querySelectorAll('input[name="speed"]').forEach(function (r) {
      r.addEventListener("change", function () { S.speed = parseInt(r.value, 10); if (S.playing) schedule(); });
    });

    var si = $("#search-input");
    if (si) {
      si.addEventListener("input", function () { renderSearch(si.value); });
      si.addEventListener("keydown", function (e) {
        var n = searchHits.length;
        if (e.key === "ArrowDown" || e.key === "ArrowUp") {
          e.preventDefault();
          if (!n) return;
          searchSel = (searchSel + (e.key === "ArrowDown" ? 1 : -1) + n) % n;
          document.querySelectorAll("#search-results button").forEach(function (b, i) {
            b.setAttribute("aria-selected", i === searchSel ? "true" : "false");
          });
          si.setAttribute("aria-activedescendant", "sr-" + searchSel);
        } else if (e.key === "Enter") {
          e.preventDefault();
          if (n) chooseSearch(searchHits[Math.max(0, searchSel)]);
        } else if (e.key === "Escape") {
          si.value = ""; renderSearch("");
        }
      });
    }

    document.addEventListener("keydown", function (e) {
      var tag = (e.target.tagName || "").toLowerCase();
      if (tag === "input" && e.target.type !== "radio" || tag === "textarea" || document.querySelector(".modal.show")) return;
      if (e.target.type === "radio" && (e.key === "ArrowLeft" || e.key === "ArrowRight")) return;
      if (e.key === "ArrowRight") { setPlaying(false); step(1); e.preventDefault(); }
      else if (e.key === "ArrowLeft") { setPlaying(false); step(-1); e.preventDefault(); }
      else if (e.key === " " && tag !== "button") { setPlaying(!S.playing); e.preventDefault(); }
      else if (e.key === "Escape" && S.detailOpen) setInput("close_detail", Date.now(), true);
    });

    window.addEventListener("resize", function () { renderTimeline(); });
    window.addEventListener("pagehide", function () { setPlaying(false); });

    if (isMobile()) toggleSheet(false);
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (window.Shiny && Shiny.addCustomMessageHandler) bindShiny();
    bindUi();
    waitForMap();
  });
})();
