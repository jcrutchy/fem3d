/* End-to-end smoke test of the real page: index.html and all its scripts run in jsdom
 * (no browser needed), with the <canvas> backed by node-canvas so the pictures can be
 * looked at. Drives the app like a user: loads an example, picks elements, flips the
 * axes toggle, then breaks the model and checks that stale results are refused.
 *
 * Dev-time only. Needs jsdom and @napi-rs/canvas (not part of the viewer):
 *   npm install --prefix /tmp/njs jsdom @napi-rs/canvas
 *   node test/app_smoke.js [outdir]                                                   */
var fs = require('fs'), path = require('path');
var NM = process.env.NODE_MODULES || '/tmp/njs/node_modules';
var JSDOM = require(NM + '/jsdom').JSDOM, nc = require(NM + '/@napi-rs/canvas');
var outdir = process.argv[2] || '/tmp/vt';
var root = path.join(__dirname, '..');

var fails = 0, checks = 0;
function check(name, ok, detail) {
  checks++;
  if (ok) console.log('PASS  ' + name);
  else { fails++; console.log('FAIL  ' + name + (detail ? '  ' + detail : '')); }
}

var errors = [];
var dom = new JSDOM(fs.readFileSync(path.join(root, 'index.html'), 'utf8'), {
  url: 'file://' + root + '/index.html', runScripts: 'dangerously', resources: 'usable', pretendToBeVisual: true,
  beforeParse: function (w) {
    var W = 1000, H = 700, big = nc.createCanvas(W, H), real = big.getContext('2d');
    w.__big = big;
    w.HTMLCanvasElement.prototype.getContext = function () { return real; };
    w.HTMLCanvasElement.prototype.getBoundingClientRect = function () { return { left: 0, top: 0, width: W, height: H, right: W, bottom: H }; };
    w.HTMLCanvasElement.prototype.setPointerCapture = function () {};
    w.HTMLCanvasElement.prototype.toBlob = function (cb) { cb(new w.Blob([big.toBuffer('image/png')])); };
    w.TextEncoder = TextEncoder; w.TextDecoder = TextDecoder;
    w.addEventListener('error', function (e) { errors.push(e.message || String(e.error)); });
    w.requestAnimationFrame = function (f) { return setTimeout(function () { f(Date.now()); }, 0); };
  }
});
var w = dom.window, doc = w.document;

function tick(ms) { return new Promise(function (r) { setTimeout(r, ms || 30); }); }
function snap(name) { fs.writeFileSync(path.join(outdir, name), w.__big.toBuffer('image/png')); }
function ptr(type, x, y, extra) {
  var e = new w.MouseEvent(type, Object.assign({ bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0 }, extra || {}));
  Object.defineProperty(e, 'offsetX', { value: x }); Object.defineProperty(e, 'offsetY', { value: y });
  Object.defineProperty(e, 'pointerId', { value: 1 });
  return e;
}
function click(x, y) {
  var c = doc.getElementById('view');
  c.dispatchEvent(ptr('pointerdown', x, y)); c.dispatchEvent(ptr('pointerup', x, y));
}
function exampleIndex(id) {
  return w.FEMVIEW_EXAMPLES.findIndex(function (e) { return e.id === id; });
}

(async function () {
  await new Promise(function (r) { w.addEventListener('load', r); });
  await tick(100);
  var App = w.FemViewApp;
  check('page scripts loaded without errors', errors.length === 0 && !!App, errors.join(' | '));
  check('empty state shown before anything is loaded', /FEM results viewer/.test(doc.getElementById('panelBody').textContent));

  // ---- the drop overlay must exist only while files are being dragged
  function shown(id) { return w.getComputedStyle(doc.getElementById(id)).display !== 'none'; }
  check('drop overlay is NOT visible at start-up (computed style, so the stylesheet counts)', !shown('drop'), 'display=' + w.getComputedStyle(doc.getElementById('drop')).display);
  var hiddenButShown = Array.prototype.filter.call(doc.querySelectorAll('[hidden]'), function (el) { return w.getComputedStyle(el).display !== 'none'; }).map(function (el) { return el.id || el.tagName; });
  check('no element carrying [hidden] is displayed', hiddenButShown.length === 0, hiddenButShown.join(','));
  function drag(type, files) {
    var e = new w.Event(type, { bubbles: true, cancelable: true });
    e.dataTransfer = { types: files ? ['Files'] : ['text/plain'], files: [] };
    e.relatedTarget = null;
    w.dispatchEvent(e);
  }
  drag('dragenter', false);
  check('dragging text (not files) over the page does not show the overlay', !shown('drop'));
  drag('dragenter', true);
  check('dragging files over the page shows the overlay', shown('drop'));
  drag('dragleave', true);
  check('dragging out of the window hides it again', !shown('drop'));
  drag('dragenter', true); drag('dragend', true);
  check('ending a drag hides it', !shown('drop'));
  check('three examples embedded', w.FEMVIEW_EXAMPLES.length === 3);

  // ---- 1. load the frame example through the real Examples menu
  var sel = doc.getElementById('examples');
  sel.value = String(exampleIndex('frame3d'));
  sel.dispatchEvent(new w.Event('change'));
  await tick(80);
  check('frame3d: results match the model (fingerprint verified)', App.state.check && App.state.check.status === 'match', App.state.check && App.state.check.status);
  check('frame3d: banner hidden', doc.getElementById('banner').hidden === true && !shown('banner'));
  check('overlay still hidden after loading (via the Examples menu)', !shown('drop'));
  check('small model: nodes switched on by default (8 nodes)', doc.getElementById('tgNodes').getAttribute('aria-pressed') === 'true');
  check('numbering toggles start off', doc.getElementById('tgNodeIds').getAttribute('aria-pressed') === 'false' && doc.getElementById('tgElIds').getAttribute('aria-pressed') === 'false');
  var tg = doc.getElementById('tgNodeIds'); tg.click(); await tick(30);
  check('Node # button turns node numbers on (button shows pressed, app state changes)', tg.getAttribute('aria-pressed') === 'true' && App.state.show.nodeIds === true);
  tg.click(); await tick(30);
  check('...and off again', tg.getAttribute('aria-pressed') === 'false' && App.state.show.nodeIds === false);
  doc.getElementById('tgElIds').click(); await tick(30);
  check('Elem # button turns element numbers on', App.state.show.elIds === true);
  var cv = doc.getElementById('view');
  function key(k) { var e = new w.KeyboardEvent('keydown', { key: k, bubbles: true }); cv.dispatchEvent(e); }
  key('n'); await tick(20);
  check('N key toggles the nodes (shortcut and button stay in step)', App.state.show.nodes === false && doc.getElementById('tgNodes').getAttribute('aria-pressed') === 'false');
  key('m'); key('e'); await tick(20);
  check('M and E keys toggle node / element numbers', App.state.show.nodeIds === true && App.state.show.elIds === false);
  key('m'); key('n'); await tick(20);
  check('once the user has chosen, loading another model keeps their choice for nodes', App.state.touchedNodes === true);
  check('frame3d: status line says the results match', /results match this model/.test(doc.getElementById('statusText').textContent));
  var caseOpts = Array.prototype.map.call(doc.getElementById('case').options, function (o) { return o.value; });
  check('frame3d: all three cases offered', caseOpts.length === 3 && caseOpts.indexOf('ultimate.') >= 0, caseOpts.join(','));
  App.state.fieldId = 'vm'; doc.getElementById('field').value = 'vm';
  doc.getElementById('field').dispatchEvent(new w.Event('change'));
  doc.getElementById('case').value = 'ultimate.'; doc.getElementById('case').dispatchEvent(new w.Event('change'));
  await tick(80);
  var sc = App.getScene();
  check('frame3d: von Mises range computed', sc && sc.range && sc.range.max > sc.range.min, JSON.stringify(sc && sc.range));
  snap('app_frame.png');

  // ---- 2. pick an element by clicking it (find a column's mid-point on screen)
  var hit = null;
  for (var x = 150; x < 850 && !hit; x += 6) for (var y = 100; y < 600 && !hit; y += 6) {
    App.select(null); click(x, y);
    if (App.state.selected && App.state.selected.type === 'element') hit = { x: x, y: y, id: App.state.selected.id };
  }
  check('clicking the structure selects an element', !!hit);
  await tick(40);
  var panel = doc.getElementById('panelBody').innerHTML;
  var el = App.state.model.elementById[App.state.selected.id];
  check('panel shows the selected element\'s heading', new RegExp((el.type === 'beam' ? 'Beam ' : 'Truss ') + el.id).test(panel));

  // ---- 3. a beam: diagrams in both axes systems
  App.select({ type: 'element', id: 1 }); await tick(30);
  panel = doc.getElementById('panelBody').innerHTML;
  check('beam panel has six force diagrams + stress charts', (panel.match(/<svg class="chart"/g) || []).length >= 8, String((panel.match(/<svg class="chart"/g) || []).length));
  check('beam panel starts in member (principal) axes', /Axial N/.test(panel) && /Shear Vy/.test(panel));
  var g = doc.querySelector('input[data-action="axes"][value="global"]');
  g.checked = true; g.dispatchEvent(new w.Event('change', { bubbles: true })); await tick(30);
  panel = doc.getElementById('panelBody').innerHTML;
  check('switching to global axes swaps the diagrams', /Force Fx/.test(panel) && /Moment Mz/.test(panel) && !/Shear Vy/.test(panel.replace(/Station table[\s\S]*/, '')));
  var sl = doc.querySelector('input[data-action="station"]');
  check('section view has a station slider', !!sl);
  sl.value = '2'; sl.dispatchEvent(new w.Event('input', { bubbles: true })); await tick(30);
  check('moving the slider re-renders the section at that station', /station 2 of 8/.test(doc.getElementById('panelBody').textContent));
  check('CSV button present', !!doc.querySelector('[data-action="copycsv"]'));

  // ---- 4. truss, node
  App.select({ type: 'element', id: 9 }); await tick(30);
  check('truss panel shows axial force', /axial force/.test(doc.getElementById('panelBody').textContent));
  App.select({ type: 'node', id: 5 }); await tick(30);
  check('node panel lists displacements and applied load', /Node 5/.test(doc.getElementById('panelBody').innerHTML) && /applied load/.test(doc.getElementById('panelBody').innerHTML));

  // ---- 5. the plate: shell panel
  sel.value = String(exampleIndex('plate_q8')); sel.dispatchEvent(new w.Event('change')); await tick(80);
  App.state.fieldId = 'vm'; doc.getElementById('field').value = 'vm'; doc.getElementById('field').dispatchEvent(new w.Event('change')); await tick(60);
  App.select({ type: 'element', id: 12 }); await tick(40);
  panel = doc.getElementById('panelBody').innerHTML;
  check('shell panel: forces table, two stress tables, Mohr circles', /Mxx/.test(panel) && (panel.match(/von Mises/g) || []).length >= 2 && /Mohr/.test(panel));
  var sf = doc.querySelector('select[data-action="shellloc"]'); sf.value = 'N3'; sf.dispatchEvent(new w.Event('change', { bubbles: true })); await tick(30);
  check('changing the sampling point updates the panel', /corner 3/.test(doc.getElementById('panelBody').innerHTML));
  snap('app_plate.png');

  // ---- 6. stale results are refused
  var ex = w.FEMVIEW_EXAMPLES[exampleIndex('cantilever_beam')];
  var edited = ex.model.replace('2, y, -1000', '2, y, -1500');
  App.loadText('cantilever_beam/model.fem', edited, 'cantilever_beam/results.txt', ex.results); await tick(60);
  var banner = doc.getElementById('banner');
  check('edited model: status is mismatch', App.state.check.status === 'mismatch', App.state.check.status);
  check('edited model: red banner is shown', banner.hidden === false && /not for this model/.test(banner.textContent), banner.textContent.slice(0, 80));
  check('edited model: results are NOT drawn (no colour range, geometry only)', App.getScene().range === null && App.getScene().maxDisp === 0);
  check('edited model: case and field menus are disabled', doc.getElementById('field').disabled === true);
  App.select({ type: 'element', id: 1 }); await tick(30);
  check('edited model: the element panel shows no results', /No results to show/.test(doc.getElementById('panelBody').textContent));
  snap('app_mismatch.png');
  banner.querySelector('[data-banner="override"]').click(); await tick(60);
  check('"show anyway" displays them, with a warning', App.getScene().maxDisp > 0 && /do not match/.test(doc.getElementById('banner').textContent));
  // comment / line-ending changes alone must NOT trigger it
  var restyled = '# an added comment\n' + ex.model.replace(/\n/g, '\r\n');
  App.loadText('cantilever_beam/model.fem', restyled, 'cantilever_beam/results.txt', ex.results); await tick(60);
  check('comment + CRLF edits do not invalidate the results', App.state.check.status === 'match', App.state.check.status);
  // results from an older solver build (no fingerprint)
  App.loadText('cantilever_beam/model.fem', ex.model, 'old.txt', ex.results.replace(/^MODEL\.FINGERPRINT.*\n/m, '')); await tick(60);
  check('fingerprint-less results: amber "not verified" notice, still displayed', App.state.check.status === 'unverified' && App.getScene().maxDisp > 0 && /not verified/i.test(doc.getElementById('banner').textContent));
  // results for a different model entirely
  var fr = w.FEMVIEW_EXAMPLES[exampleIndex('frame3d')];
  App.loadText('cantilever_beam/model.fem', ex.model, 'frame_results.txt', fr.results); await tick(60);
  check('another model\'s results are refused', App.state.check.status === 'mismatch' && App.getScene().range === null);

  console.log('\n' + (fails === 0 ? 'ALL ' + checks + ' CHECKS PASSED' : fails + ' of ' + checks + ' CHECKS FAILED'));
  process.exit(fails === 0 ? 0 : 1);
}()).catch(function (e) { console.log('CRASH', e && e.stack || e); process.exit(2); });
