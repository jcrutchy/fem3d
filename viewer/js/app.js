/* app.js -- wires the modules to the page. The only file that touches the DOM.
 *
 * The viewer is deliberately "dumb": it displays what is in a model file and in a
 * solver's output, nothing more. It never solves anything, and it refuses to draw
 * results that do not belong to the model it was given (see femcheck.js). */
(function () {
  'use strict';
  var P = FemParse, M = FemMath, S = FemScene, R = FemRender, PN = FemPanels, C = FemCheck, H = FemHash;
  var $ = function (id) { return document.getElementById(id); };

  var state = {
    model: null, modelBytes: null, modelName: '',
    results: null, resultsName: '',
    check: null, override: false,
    caseKey: '', fieldId: 'none',
    deformed: true, scaleMul: 1,
    axes: 'local', station: undefined, shellLoc: 'C', shellField: 'vm',
    selected: null,
    show: { nodes: false, nodeIds: false, elIds: false }, // toolbar label toggles
    touchedNodes: false                                  // user has chosen for themselves: stop auto-defaulting
  };
  var cam = new M.Camera();
  var scene = null, hits = null;
  var canvas = $('view'), ctx = canvas.getContext('2d');
  var dpr = 1, dirty = false, quality = 'high', qualityTimer = null;

  /* ------------------------------------------------------------ small utils */
  function esc(s) { return PN.esc(s); }
  function opt(id) { return $(id).checked; }
  function usableResults() {
    if (!state.results || !state.check) return null;
    var st = state.check.status;
    return (st === 'match' || st === 'unverified' || state.override) ? state.results : null;
  }
  function currentCase() {
    var rs = usableResults();
    return rs && rs.cases[state.caseKey] ? rs.cases[state.caseKey] : null;
  }
  function units() { return PN.unitsOf(state.model); }
  function unitText(f) {
    var u = units();
    return { length: u.length, force: u.force, moment: u.moment, stress: u.stress,
             'force/length': u.fpl, 'moment/length': u.mpl }[f.unit] || '';
  }
  function fmtVal(v) { return M.fmt(v, 3); }
  function decode(bytes) { return new TextDecoder('utf-8').decode(bytes); }

  /* ------------------------------------------------------------- loading */
  function ingest(name, bytes) {
    var text = decode(bytes), kind = P.sniff(text);
    if (kind === 'model') {
      state.model = P.parseModel(text); state.modelBytes = bytes; state.modelName = name;
      state.selected = null; state.override = false; state.fresh = true;
      if (!state.touchedNodes) { state.show.nodes = state.model.nodes.length <= 400; syncToggles(); }
    } else if (kind === 'results') {
      state.results = P.parseResults(text); state.resultsName = name; state.override = false;
      state.caseKey = state.results.order[0] !== undefined ? state.results.order[0] : '';
    } else {
      showToastBanner('"' + name + '" is neither a model (.fem) nor solver output (key=value lines).', true);
      return false;
    }
    return true;
  }

  function afterLoad() {
    hideDrop();
    state.check = (state.model && state.results) ? C.verify(state.model, state.modelBytes, state.results) : null;
    if (state.results && state.results.order.indexOf(state.caseKey) < 0) state.caseKey = state.results.order[0] || '';
    populateCases();
    populateFields();
    rebuild(!!state.fresh);
    state.fresh = false;
    updateBanner();
    renderPanel();
    updateStatus();
  }

  function loadFiles(fileList) {
    var files = Array.prototype.slice.call(fileList);
    if (!files.length) return;
    var pending = files.length, bad = false;
    files.forEach(function (f) {
      var rd = new FileReader();
      rd.onload = function () {
        if (!ingest(f.name, new Uint8Array(rd.result))) bad = true;
        if (--pending === 0) afterLoad();
      };
      rd.onerror = function () { pending--; showToastBanner('Could not read ' + f.name, true); };
      rd.readAsArrayBuffer(f);
    });
  }

  function loadText(modelName, modelText, resultsName, resultsText) {
    state.results = null; state.check = null;
    ingest(modelName, new TextEncoder().encode(modelText));
    if (resultsText) ingest(resultsName, new TextEncoder().encode(resultsText));
    afterLoad();
  }

  function fetchBytes(url) {
    return fetch(url).then(function (r) {
      if (!r.ok) throw new Error(url + ': HTTP ' + r.status);
      return r.arrayBuffer();
    }).then(function (b) { return new Uint8Array(b); });
  }

  /* ------------------------------------------------------------ the banner */
  function updateBanner() {
    var b = $('banner'), c = state.check;
    if (state.toast) { return; }
    if (!c || c.status === 'match' || (state.override && c.status !== 'unverified')) {
      if (c && state.override && c.status !== 'match') {
        b.className = 'warn'; b.hidden = false;
        b.innerHTML = '<h4>Showing results that do not match this model</h4><p class="sub">You chose to display them anyway. Everything drawn below may be wrong for the model on screen.</p>' +
          '<div class="row"><button type="button" data-banner="hide">Hide them again</button></div>';
        return;
      }
      b.hidden = true; return;
    }
    if (c.status === 'unverified') {
      b.className = 'warn'; b.hidden = false;
      b.innerHTML = '<h4>Results not verified against this model</h4>' +
        '<p class="sub">These results carry no model fingerprint (they come from an older solver build), so there is no way to prove they were computed from this model file. Node and element numbers do line up.</p>' +
        '<div class="row"><button type="button" data-banner="dismiss">OK</button></div>';
      return;
    }
    b.className = ''; b.hidden = false;
    b.innerHTML = '<h4>' + (c.status === 'mismatch' ? 'These results are not for this model' : 'These results do not fit this model') + '</h4>' +
      '<ul>' + c.problems.map(function (p) { return '<li>' + esc(p) + '</li>'; }).join('') + '</ul>' +
      '<p class="sub">Only the geometry is shown. Run the solver on this model again and load its new output.</p>' +
      '<div class="row"><button type="button" data-banner="override">Show the results anyway</button></div>';
  }

  var toastTimer = null;
  function showToastBanner(msg, bad) {
    var b = $('banner'); state.toast = true;
    b.className = bad ? '' : 'warn'; b.hidden = false; b.innerHTML = '<h4>' + esc(msg) + '</h4>';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { state.toast = false; updateBanner(); }, 4500);
  }

  $('banner').addEventListener('click', function (e) {
    var a = e.target.getAttribute && e.target.getAttribute('data-banner');
    if (!a) return;
    if (a === 'override') { state.override = true; afterLoadKeepView(); }
    else if (a === 'hide') { state.override = false; afterLoadKeepView(); }
    else if (a === 'dismiss') { $('banner').hidden = true; state.dismissed = true; }
  });
  function afterLoadKeepView() { populateCases(); populateFields(); rebuild(false); updateBanner(); renderPanel(); updateStatus(); }

  /* ------------------------------------------------------------- controls */
  function populateCases() {
    var sel = $('case'), rs = usableResults();
    sel.innerHTML = '';
    if (!rs) { sel.disabled = true; return; }
    rs.order.forEach(function (p) {
      var o = document.createElement('option'); o.value = p; o.textContent = rs.cases[p].label === 'default' && rs.order.length === 1 ? 'Load case' : rs.cases[p].label;
      sel.appendChild(o);
    });
    sel.value = state.caseKey; sel.disabled = rs.order.length < 2;
  }

  function populateFields() {
    var sel = $('field'), rs = usableResults();
    sel.innerHTML = '';
    var groups = {}, order = [];
    S.FIELDS.forEach(function (f) {
      if (f.kind === 'nodal' && !rs) return;
      if (f.kind !== 'nodal' && f.id !== 'none' && !rs) return;
      var g = groups[f.group];
      if (!g) { g = groups[f.group] = document.createElement('optgroup'); g.label = f.group; order.push(g); }
      var o = document.createElement('option'); o.value = f.id; o.textContent = f.label; g.appendChild(o);
    });
    order.forEach(function (g) { sel.appendChild(g); });
    if (!rs) state.fieldId = 'none';
    else if (state.fieldId === 'none' && state.fresh) state.fieldId = 'vm';
    sel.value = state.fieldId; sel.disabled = !rs;
  }

  function scaleFromSlider() { return Math.pow(10, parseInt($('scale').value, 10) / 50); } // 0.01x .. 100x
  function updateScaleLabel() {
    var out = $('scaleOut');
    if (!scene || !scene.maxDisp) { out.textContent = ''; return; }
    out.textContent = '\u00d7' + M.fmt(scene.autoScale * state.scaleMul, 3);
    out.title = 'Displacements are drawn this many times larger than they really are';
  }

  /* ------------------------------------------------------------ scene/draw */
  function rebuild(fit) {
    if (!state.model) { scene = null; hits = null; schedule(); return; }
    var rs = usableResults();
    scene = S.build(state.model, rs, state.caseKey, {
      deformed: state.deformed, scaleMul: state.scaleMul, fieldId: state.fieldId, curved: opt('optCurved')
    });
    if (fit) {
      var s0 = S.build(state.model, null, '', {});
      cam.fit(s0.center, s0.radius);
      cam.setView('iso');
    }
    updateScaleLabel();
    schedule();
  }

  function resize() {
    var r = canvas.getBoundingClientRect();
    dpr = Math.max(1, Math.min(window.devicePixelRatio || 1, 2.5));
    canvas.width = Math.max(1, Math.round(r.width * dpr));
    canvas.height = Math.max(1, Math.round(r.height * dpr));
    cam.width = r.width; cam.height = r.height;
    schedule();
  }

  function schedule() {
    if (dirty) return;
    dirty = true;
    requestAnimationFrame(paint);
  }

  function drawOpts() {
    var u = units();
    return {
      theme: opt('optLight') ? 'light' : 'dark', detail: quality,
      showGhost: opt('optGhost'), showNodes: state.show.nodes, showNodeIds: state.show.nodeIds, showElementIds: state.show.elIds,
      showMesh: opt('optMesh'), showSupports: opt('optSupports'), showLoads: opt('optLoads'),
      selectedEl: state.selected && state.selected.type === 'element' ? state.selected.id : null,
      selectedNode: state.selected && state.selected.type === 'node' ? state.selected.id : null,
      fmtVal: fmtVal
    };
  }

  function paint() {
    dirty = false;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (!scene) {
      var T = R.THEMES[opt('optLight') ? 'light' : 'dark'];
      ctx.fillStyle = T.bg; ctx.fillRect(0, 0, cam.width, cam.height);
      ctx.fillStyle = T.dim; ctx.font = '15px system-ui, sans-serif'; ctx.textAlign = 'center';
      ctx.fillText('Open a model (.fem) and the solver output for it \u2014 or pick an example', cam.width / 2, cam.height / 2);
      return;
    }
    cam.ortho = !opt('optPersp');
    var o = drawOpts();
    if (scene.field && scene.field.id !== 'none') {
      var ut = unitText(scene.field);
      o.legendTitle = scene.field.label + (ut ? ' (' + ut + ')' : '');
    }
    hits = R.draw(ctx, scene, cam, o);
  }

  function interacting() {
    quality = 'low';
    clearTimeout(qualityTimer);
    qualityTimer = setTimeout(function () { quality = 'high'; schedule(); }, 160);
    schedule();
  }

  /* ------------------------------------------------------- pointer / camera */
  var pointers = {}, dragMode = null, downPos = null, moved = false, lastPinch = null;
  canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });
  canvas.addEventListener('pointerdown', function (e) {
    canvas.focus({ preventScroll: true });
    canvas.setPointerCapture(e.pointerId);
    pointers[e.pointerId] = { x: e.offsetX, y: e.offsetY };
    var n = Object.keys(pointers).length;
    if (n === 1) {
      downPos = { x: e.offsetX, y: e.offsetY }; moved = false;
      dragMode = (e.button === 2 || e.button === 1 || e.shiftKey || e.ctrlKey) ? 'pan' : 'orbit';
    } else if (n === 2) { dragMode = 'pinch'; lastPinch = pinchState(); moved = true; }
  });
  canvas.addEventListener('pointermove', function (e) {
    var p = pointers[e.pointerId];
    if (!p) return;
    var dx = e.offsetX - p.x, dy = e.offsetY - p.y;
    p.x = e.offsetX; p.y = e.offsetY;
    if (dragMode === 'pinch' && Object.keys(pointers).length >= 2) {
      var ps = pinchState();
      if (lastPinch) {
        cam.zoom(-(ps.dist - lastPinch.dist) * 2.2, ps.cx, ps.cy);
        cam.pan(ps.cx - lastPinch.cx, ps.cy - lastPinch.cy);
      }
      lastPinch = ps; interacting(); return;
    }
    if (downPos && (Math.abs(e.offsetX - downPos.x) > 4 || Math.abs(e.offsetY - downPos.y) > 4)) moved = true;
    if (!moved) return;
    if (dragMode === 'orbit') cam.orbit(dx, dy); else if (dragMode === 'pan') cam.pan(dx, dy);
    interacting();
  });
  function endPointer(e) {
    var had = pointers[e.pointerId];
    delete pointers[e.pointerId];
    if (!had) return;
    if (Object.keys(pointers).length === 0) {
      if (!moved && downPos && e.type === 'pointerup' && e.button === 0) selectAt(e.offsetX, e.offsetY);
      dragMode = null; downPos = null; lastPinch = null;
    } else if (Object.keys(pointers).length === 1) { dragMode = 'orbit'; lastPinch = null; moved = true; }
  }
  canvas.addEventListener('pointerup', endPointer);
  canvas.addEventListener('pointercancel', endPointer);
  function pinchState() {
    var k = Object.keys(pointers), a = pointers[k[0]], b = pointers[k[1]];
    return { dist: Math.hypot(a.x - b.x, a.y - b.y), cx: (a.x + b.x) / 2, cy: (a.y + b.y) / 2 };
  }
  canvas.addEventListener('wheel', function (e) {
    e.preventDefault();
    var d = e.deltaMode === 1 ? e.deltaY * 33 : e.deltaY;
    cam.zoom(d, e.offsetX, e.offsetY);
    interacting();
  }, { passive: false });

  canvas.addEventListener('keydown', function (e) {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.key === 'f' || e.key === 'F') { fitView(); }
    else if (e.key === 'n' || e.key === 'N') toggleShow('nodes');
    else if (e.key === 'm' || e.key === 'M') toggleShow('nodeIds');
    else if (e.key === 'e' || e.key === 'E') toggleShow('elIds');
    else if (e.key === 'Escape') { select(null); }
    else if (e.key === '1') setView('iso'); else if (e.key === '2') setView('top');
    else if (e.key === '3') setView('front'); else if (e.key === '4') setView('side');
  });

  function fitView() {
    if (!scene) return;
    var s0 = S.build(state.model, null, '', {});
    cam.fit(s0.center, s0.radius); interacting();
  }
  function setView(name) {
    if (name === 'fit') { fitView(); return; }
    cam.setView(name); interacting();
  }
  Array.prototype.forEach.call(document.querySelectorAll('[data-view]'), function (b) {
    b.addEventListener('click', function () { setView(b.getAttribute('data-view')); });
  });

  /* ------------------------------------------------------------- selection */
  function selectAt(x, y) {
    if (!hits) return;
    var p = R.pick(hits, x, y, 9, 8, 0.0);
    select(p ? { type: p.type, id: p.id } : null);
  }
  function select(sel) {
    state.selected = sel; state.station = undefined;
    renderPanel(); schedule();
  }

  /* ---------------------------------------------------------------- panel */
  function panelContext() {
    var rc = currentCase(), m = state.model;
    var sel = state.selected;
    var c = { model: m, units: units(), axes: state.axes, station: state.station, shellLoc: state.shellLoc, shellField: state.shellField, rc: rc };
    if (sel && sel.type === 'element') {
      c.element = m.elementById[sel.id];
      c.elem = rc ? rc.elem[sel.id] : null;
    } else if (sel && sel.type === 'node') {
      c.nodeId = sel.id;
      c.supports = scene ? scene.supports : null; c.loads = scene ? scene.loads : null;
    }
    return c;
  }

  function emptyPanel() {
    var m = state.model, h = [];
    if (!m) {
      return '<div class="empty"><h3>FEM results viewer</h3>' +
        '<p>Load a <b>model file</b> (<span class="mono">.fem</span>) and the <b>solver output</b> for it \u2014 pick both in <b>Open\u2026</b>, or drop them on the page.</p>' +
        '<p>The viewer only displays what those two files contain. It does not solve anything.</p>' +
        '<p class="sub">Try one of the built-in <b>Examples</b>.</p></div>';
    }
    h.push('<div class="empty"><h3>Nothing selected</h3>');
    h.push('<p>Click an <b>element</b> to see its forces and stresses here, or a <b>node</b> for its displacements and reactions.</p>');
    h.push('<p class="sub">Drag to orbit \u00b7 right-drag or Shift-drag to pan \u00b7 wheel to zoom \u00b7 <kbd>F</kbd> fit \u00b7 <kbd>1</kbd>\u2013<kbd>4</kbd> views \u00b7 <kbd>N</kbd> nodes \u00b7 <kbd>M</kbd> node numbers \u00b7 <kbd>E</kbd> element numbers \u00b7 <kbd>Esc</kbd> deselect</p>');
    var counts = {};
    m.elements.forEach(function (e) { counts[e.type] = (counts[e.type] || 0) + 1; });
    h.push('<div class="legendbox"><b>' + m.nodes.length + '</b> nodes \u00b7 ' + Object.keys(counts).map(function (k) { return '<b>' + counts[k] + '</b> ' + k; }).join(' \u00b7 ') +
      (state.model.header.Units ? '<br><span class="sub">' + esc(state.model.header.Units) + '</span>' : '') + '</div>');
    if (!usableResults()) h.push('<p class="sub">' + (state.results ? 'The loaded results are not being displayed (see the message over the view).' : 'No results loaded yet \u2014 geometry only.') + '</p>');
    h.push('</div>');
    return h.join('');
  }

  function renderPanel() {
    var body = $('panelBody'), sel = state.selected;
    if (!state.model || !sel) { body.innerHTML = emptyPanel(); return; }
    var c = panelContext();
    if (sel.type === 'node') { body.innerHTML = PN.nodePanel(c) + backLink(); return; }
    var el = c.element;
    var html;
    if (!c.rc) html = '<h3>' + esc(el.type) + ' ' + el.id + '</h3><p class="sub">nodes ' + el.nodes.join(', ') + ' \u00b7 property ' + el.prop + '</p><p class="warn">No results to show for this element.</p>';
    else if (el.type === 'truss') html = PN.trussPanel(c);
    else if (el.type === 'beam') html = PN.beamPanel(c);
    else html = PN.shellPanel(c);
    body.innerHTML = html + backLink();
  }
  function backLink() { return '<p><button type="button" class="btn" data-action="deselect">Clear selection</button></p>'; }

  var panelEl = $('panelBody');
  panelEl.addEventListener('change', function (e) {
    var a = e.target.getAttribute('data-action');
    if (a === 'axes') { state.axes = e.target.value; renderPanel(); }
    else if (a === 'shellfield') { state.shellField = e.target.value; renderPanel(); }
    else if (a === 'shellloc') { state.shellLoc = e.target.value; renderPanel(); }
  });
  panelEl.addEventListener('input', function (e) {
    if (e.target.getAttribute('data-action') === 'station') {
      state.station = parseInt(e.target.value, 10);
      var top = $('panel').scrollTop; renderPanel(); $('panel').scrollTop = top;
      var again = panelEl.querySelector('[data-action="station"]'); if (again) again.focus();
    }
  });
  panelEl.addEventListener('click', function (e) {
    var a = e.target.getAttribute('data-action');
    if (a === 'deselect') select(null);
    else if (a === 'copycsv') {
      var csv = PN.beamCSV(panelContext());
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(csv);
      else { var t = document.createElement('textarea'); t.value = csv; document.body.appendChild(t); t.select(); document.execCommand('copy'); t.remove(); }
      e.target.textContent = 'Copied';
      setTimeout(function () { e.target.textContent = 'Copy as CSV'; }, 1400);
    }
  });

  /* -------------------------------------------------------------- status */
  function updateStatus() {
    var el = $('statusText'), m = state.model, c = state.check;
    if (!m) { el.textContent = 'No model loaded.'; return; }
    var parts = [esc(state.modelName) + ' \u2014 ' + m.nodes.length + ' nodes, ' + m.elements.length + ' elements'];
    if (state.results) {
      parts.push(esc(state.resultsName) + ' \u2014 ' + state.results.order.length + ' case' + (state.results.order.length === 1 ? '' : 's'));
      if (c.status === 'match') parts.push('<span class="ok">\u2713 results match this model (' + c.modelFingerprint.slice(0, 12) + '\u2026)</span>');
      else if (c.status === 'unverified') parts.push('<span class="warn">results not verified (no fingerprint)</span>');
      else parts.push('<span class="bad">\u2717 results do not match this model' + (state.override ? ' \u2014 shown anyway' : '') + '</span>');
    } else parts.push('no results loaded');
    el.innerHTML = parts.join(' \u00b7 ');
  }

  /* --------------------------------------------------------- toolbar wiring */
  $('files').addEventListener('change', function (e) { loadFiles(e.target.files); e.target.value = ''; });
  $('case').addEventListener('change', function (e) { state.caseKey = e.target.value; rebuild(false); renderPanel(); });
  $('field').addEventListener('change', function (e) { state.fieldId = e.target.value; rebuild(false); });
  $('deformed').addEventListener('change', function (e) { state.deformed = e.target.checked; rebuild(false); });
  $('scale').addEventListener('input', function () { state.scaleMul = scaleFromSlider(); rebuild(false); });
  ['optGhost', 'optMesh', 'optSupports', 'optLoads', 'optPersp'].forEach(function (id) {
    $(id).addEventListener('change', schedule);
  });
  $('optCurved').addEventListener('change', function () { rebuild(false); });
  $('optLight').addEventListener('change', function () {
    document.documentElement.setAttribute('data-theme', opt('optLight') ? 'light' : 'dark'); schedule();
  });
  $('png').addEventListener('click', function () {
    if (!scene) return;
    quality = 'high'; paint();
    canvas.toBlob(function (blob) {
      var a = document.createElement('a'); a.href = URL.createObjectURL(blob);
      a.download = (state.modelName || 'view').replace(/\.[^.]+$/, '') + '.png';
      document.body.appendChild(a); a.click(); a.remove(); setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
    });
  });

  // examples
  (function () {
    var ex = (typeof FEMVIEW_EXAMPLES !== 'undefined') ? FEMVIEW_EXAMPLES : [];
    var sel = $('examples');
    ex.forEach(function (e, i) { var o = document.createElement('option'); o.value = i; o.textContent = e.name; sel.appendChild(o); });
    sel.addEventListener('change', function () {
      if (sel.value === '') return;
      var e = ex[parseInt(sel.value, 10)];
      state.fieldId = 'none';
      loadText(e.id + '/model.fem', e.model, e.id + '/results.txt', e.results);
      sel.value = '';
    });
  }());

  // label toggles (Nodes / Node # / Elem #): the toolbar buttons and the N / M / E keys share one state
  var TOGGLES = { nodes: 'tgNodes', nodeIds: 'tgNodeIds', elIds: 'tgElIds' };
  function syncToggles() {
    Object.keys(TOGGLES).forEach(function (k) {
      var b = $(TOGGLES[k]);
      b.setAttribute('aria-pressed', state.show[k] ? 'true' : 'false');
    });
  }
  function toggleShow(k) {
    state.show[k] = !state.show[k];
    if (k === 'nodes') state.touchedNodes = true;
    syncToggles(); schedule();
  }
  Object.keys(TOGGLES).forEach(function (k) { $(TOGGLES[k]).addEventListener('click', function () { toggleShow(k); }); });
  syncToggles();

  // drag and drop: the overlay exists only while FILES are being dragged over the page
  var dragDepth = 0;
  function hideDrop() { dragDepth = 0; $('drop').hidden = true; }
  function hasFiles(e) {
    var t = e.dataTransfer && e.dataTransfer.types;
    return !!t && Array.prototype.indexOf.call(t, 'Files') >= 0;
  }
  window.addEventListener('dragenter', function (e) { if (!hasFiles(e)) return; e.preventDefault(); dragDepth++; $('drop').hidden = false; });
  window.addEventListener('dragleave', function (e) {
    if (e.relatedTarget === null || --dragDepth <= 0) hideDrop();   // relatedTarget is null when the drag leaves the window
  });
  window.addEventListener('dragover', function (e) { if (hasFiles(e)) e.preventDefault(); });
  window.addEventListener('drop', function (e) {
    e.preventDefault(); hideDrop();
    if (e.dataTransfer && e.dataTransfer.files.length) loadFiles(e.dataTransfer.files);
  });
  window.addEventListener('dragend', hideDrop);
  window.addEventListener('blur', hideDrop);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') hideDrop(); });
  hideDrop();

  window.addEventListener('resize', resize);
  if (window.ResizeObserver) new ResizeObserver(resize).observe($('stage'));
  if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
    $('optLight').checked = true; document.documentElement.setAttribute('data-theme', 'light');
  }

  // ?model=URL&results=URL  (works when the page is served over http, e.g. by vdrx)
  (function () {
    var q = new URLSearchParams(location.search), mu = q.get('model'), ru = q.get('results');
    if (!mu) return;
    Promise.all([fetchBytes(mu), ru ? fetchBytes(ru) : Promise.resolve(null)]).then(function (r) {
      state.fresh = true;
      ingest(mu.split('/').pop(), r[0]);
      if (r[1]) ingest(ru.split('/').pop(), r[1]);
      state.fieldId = 'none';
      afterLoad();
    }).catch(function (err) { showToastBanner(String(err.message || err), true); });
  }());

  resize();
  renderPanel();
  updateStatus();

  // a hook for tests / debugging from the console
  window.FemViewApp = { state: state, loadText: loadText, select: select, getScene: function () { return scene; } };
}());
