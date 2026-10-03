/* Unit tests for the viewer's pure modules -- plain node, no dependencies.
 *   node test/run_tests.js
 * They run against the checked-in examples (a model + the real solver output for it), so they also
 * prove the viewer reads what the Pascal solvers actually write, and that the JavaScript model
 * fingerprint equals the one the solver computed. Exit code 0 = all passed. */
var fs = require('fs'), path = require('path');
var H = require('../js/femhash.js'), P = require('../js/femparse.js'), M = require('../js/femmath.js'),
    S = require('../js/femscene.js'), C = require('../js/femcheck.js'), R = require('../js/render3d.js'), PN = require('../js/panels.js');

var fails = 0, checks = 0;
function check(name, ok, detail) { checks++; if (!ok) { fails++; console.log('FAIL  ' + name + (detail ? '  ' + detail : '')); } else console.log('PASS  ' + name); }
function near(name, a, b, tol) { check(name, Math.abs(a - b) <= (tol === undefined ? 1e-9 : tol) * (1 + Math.abs(b)), 'got ' + a + ' expected ' + b); }

function load(ex) {
  var dir = path.join(__dirname, '..', 'examples', ex);
  var mb = fs.readFileSync(path.join(dir, 'model.fem'));
  return { bytes: mb, model: P.parseModel(mb.toString('utf8')), results: P.parseResults(fs.readFileSync(path.join(dir, 'results.txt'), 'utf8')) };
}
var enc = function (s) { return new TextEncoder().encode(s); };

/* ---- SHA-256 + fingerprint ---- */
check('SHA-256 of ""', H.sha256(enc('')) === 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
check('SHA-256 of "abc"', H.sha256(enc('abc')) === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
check('SHA-256 of one million "a"', H.sha256(enc('a'.repeat(1000000))) === 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
var nodeCrypto = require('crypto'), okSweep = true;
[0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 121, 4096, 100001].forEach(function (n) {
  var b = nodeCrypto.randomBytes(n);
  if (H.sha256(b) !== nodeCrypto.createHash('sha256').update(b).digest('hex')) okSweep = false;
});
check('SHA-256 agrees with node:crypto for message lengths around every padding boundary', okSweep);

var base = '[NODES]\n1, 0, 0, 0\n2, 1, 0, 0\n\n[ELEMENTS]\n1, truss, 1, 2, 1\n';
var fp = H.fingerprint(base);
check('fingerprint ignores CRLF', H.fingerprint(base.replace(/\n/g, '\r\n')) === fp);
check('fingerprint ignores lone CR', H.fingerprint(base.replace(/\n/g, '\r')) === fp);
check('fingerprint ignores indentation, trailing blanks, blank lines', H.fingerprint('  ' + base.replace(/\n/g, ' \t\n\n  ')) === fp);
check('fingerprint ignores whole-line comments', H.fingerprint('# top\n' + base + '   # bottom\n') === fp);
check('fingerprint ignores a UTF-8 BOM', H.fingerprint(new Uint8Array([0xEF, 0xBB, 0xBF].concat(Array.from(enc(base))))) === fp);
check('fingerprint changes with a value', H.fingerprint(base.replace('2, 1, 0, 0', '2, 1.001, 0, 0')) !== fp);
check('fingerprint changes with line order', H.fingerprint('[NODES]\n2, 1, 0, 0\n1, 0, 0, 0\n\n[ELEMENTS]\n1, truss, 1, 2, 1\n') !== fp);
check('a "#" after data is data, not a comment', H.fingerprint('1, 2 # x\n') !== H.fingerprint('1, 2\n'));
check('the empty file hashes to SHA-256 of nothing', H.fingerprint('') === 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');

['cantilever_beam', 'frame3d', 'plate_q8'].forEach(function (ex) {
  var d = load(ex);
  check(ex + ': JavaScript fingerprint equals the one the Pascal solver printed', d.results.fingerprint === H.fingerprint(d.bytes),
    (d.results.fingerprint || 'none').slice(0, 12) + ' vs ' + H.fingerprint(d.bytes).slice(0, 12));
  check(ex + ': verify() says match', C.verify(d.model, d.bytes, d.results).status === 'match');
});

/* ---- parsing ---- */
var cant = load('cantilever_beam'), frame = load('frame3d'), plate = load('plate_q8');
check('model: nodes, beam property with Cy/Cz, BeamDivisions', cant.model.nodes.length === 2 && cant.model.properties[1].Cy === 0.1 && cant.model.solverParams.BeamDivisions === '8');
check('model: shell element has 8 nodes and a property', plate.model.elements[0].nodes.length === 8 && plate.model.properties[1].thickness === 0.05);
check('model: combination terms', frame.model.combinations.ultimate.length === 2 && frame.model.combinations.ultimate[1].factor === 1.5);
check('results: one case per load case and combination', frame.results.order.join('|') === 'gravity.|wind.|ultimate.', frame.results.order.join('|'));
var st = cant.results.cases[''].elem[1].stations;
check('results: 9 beam stations (BeamDivisions=8)', st.length === 9);
near('results: Mz at the root is -3000', st[0].MZ, -3000);
near('results: station position of the 4th station is 1.125', st[3].POS, 1.125);
near('results: corner-1 stress at the root is 3.75E6', st[0].SIGC1, 3.75e6, 1e-6);

/* ---- the structural check catches the wrong results ---- */
var v = C.verify(cant.model, cant.bytes, frame.results);
check('another model\'s results: mismatch', v.status === 'mismatch');
var tampered = cant.bytes.toString('utf8').replace('2, y, -1000', '2, y, -1001');
v = C.verify(P.parseModel(tampered), enc(tampered), cant.results);
check('a one-character load change: mismatch', v.status === 'mismatch' && /different version of the model/.test(v.problems[0]));
var noFp = P.parseResults(fs.readFileSync(path.join(__dirname, '..', 'examples', 'cantilever_beam', 'results.txt'), 'utf8').replace(/^MODEL\.FINGERPRINT.*$/m, ''));
check('no fingerprint, structure fine: unverified', C.verify(cant.model, cant.bytes, noFp).status === 'unverified');
var moreNodes = tampered.replace('[MATERIALS]', '7, 5, 5, 5\n\n[MATERIALS]');
var noFpStruct = C.verify(P.parseModel(moreNodes), enc(moreNodes), noFp);
check('no fingerprint but the model gained a node: incompatible', noFpStruct.status === 'incompatible' && /node 7/.test(noFpStruct.problems.join(' ')), noFpStruct.status);
var wrongKind = P.parseModel(cant.bytes.toString('utf8').replace('1, beam, 1, 2, 1', '1, truss, 1, 2, 1'));
check('beam turned into a truss without re-solving: structural problem reported', C.structuralProblems(wrongKind, cant.results).some(function (p) { return /truss in the model/.test(p); }));

/* ---- scene: fields, ranges, curved beams ---- */
var s = S.build(cant.model, cant.results, '', { deformed: false, fieldId: 'Mz' });
near('scene: Mz range min', s.range.min, -3000, 1e-9); near('scene: Mz range max', s.range.max, 0, 1e-6);
s = S.build(cant.model, cant.results, '', { deformed: false, fieldId: 'vm' });
near('scene: von Mises peaks at 3.75E6 at the root', s.range.max, 3.75e6, 1e-6);
s = S.build(cant.model, cant.results, '', { deformed: false, fieldId: 'smax' });
near('scene: max normal stress 3.75E6', s.range.max, 3.75e6, 1e-6); near('scene: ... and 0 at the free end', s.range.min, 0, 1e-6);
near('scene: autoscale makes the biggest displacement 8% of the model size', s.autoScale * s.maxDisp, 0.08 * s.modelSize, 1e-9);
// curved cantilever: deflection at mid-span is 5PL^3/(48EI), at the tip PL^3/(3EI) (absolute scale 1)
var E = 2e11, I = 8e-5, Pld = 1000, L = 3;
s = S.build(cant.model, cant.results, '', { deformed: true, scale: 1, fieldId: 'none' });
var pts = s.groups[0].pts;
near('curved beam: tip deflection = PL^3/3EI', -pts[pts.length - 1][1], Pld * L * L * L / (3 * E * I), 1e-6);
near('curved beam: mid-span deflection = 5PL^3/48EI (a cubic, not the straight-chord half)', -pts[(pts.length - 1) / 2][1], 5 * Pld * L * L * L / (48 * E * I), 1e-3);
s = S.build(plate.model, plate.results, '', { deformed: false, fieldId: 'vm' });
check('scene: shell von Mises range from all elements', s.range && s.range.max > 4e8 && s.range.max < 6e8, JSON.stringify(s.range));
var sup = S.caseInputs(frame.model, 'ultimate.');
near('case inputs: combination load = 1.35*(-40000) on node 5 z', sup.loads[5].f[2], -54000);
near('case inputs: combination load = 1.5*25000 on node 5 x', sup.loads[5].f[0], 37500);
check('case inputs: supports from the freedom case', sup.supports[1] && sup.supports[1].rz === true);

/* ---- drawing (recording context: no pixels, just that it runs and returns hit data) ---- */
function fakeCtx() {
  var counts = {}, handler = {
    get: function (t, k) {
      if (k === '__counts') return counts;
      return t[k] || (t[k] = function () { counts[k] = (counts[k] || 0) + 1; return { addColorStop: function () {} }; });
    },
    set: function (t, k, v) { t[k] = v; return true; } };
  return new Proxy({}, handler);
}
var cam = new M.Camera(); cam.width = 900; cam.height = 600;
var sc = S.build(frame.model, frame.results, 'ultimate.', { deformed: true, scaleMul: 1, fieldId: 'vm' });
cam.fit(sc.center, sc.radius);
var ctx = fakeCtx();
var hits = R.draw(ctx, sc, cam, { theme: 'dark', showSupports: true, showLoads: true, showGhost: true, detail: 'high', fmtVal: String });
check('draw: one hit record per element and per node', hits.elements.length === frame.model.elements.length && hits.nodes.length === frame.model.nodes.length);
var first = hits.elements.filter(function (h) { return h.id === 1; })[0];
var mid = first.line[Math.floor(first.line.length / 2)];
var pk = R.pick(hits, mid[0], mid[1] + 1, 8, 7, 0);
check('pick: clicking on a beam picks that beam', pk && pk.type === 'element' && pk.id === 1, JSON.stringify(pk));
var nd = hits.nodes[0];
check('pick: clicking on a node picks the node (nodes win)', R.pick(hits, nd.x + 2, nd.y + 1, 8, 7, 0).type === 'node');
check('pick: empty space picks nothing', R.pick(hits, 2, 2, 8, 7, 0) === null);

/* ---- node / element numbering overlay ---- */
function labelCount(d, caseKey, camDistFactor, extra) {
  var scn = S.build(d.model, d.results, caseKey, { deformed: false, fieldId: 'none' });
  var c2 = new M.Camera(); c2.width = 900; c2.height = 600; c2.fit(scn.center, scn.radius); c2.dist *= camDistFactor;
  var cx = fakeCtx();
  R.draw(cx, scn, c2, Object.assign({ theme: 'dark', detail: 'high', fmtVal: String }, extra));
  return cx.__counts.fillText || 0;
}
// the view gizmo writes X, Y, Z with fillText too; measure labels as the excess over an unlabelled draw
var gizmoText = labelCount(plate, '', 1, {});
var nPlateNodes = plate.model.nodes.length;
check('numbering: the view gizmo is the only text when the toggles are off', gizmoText === 3, String(gizmoText));
var farLabels = labelCount(plate, '', 1.0, { showNodeIds: true }) - gizmoText;
check('numbering: a dense view shows a readable subset of node numbers, not all of them', farLabels > 0 && farLabels < nPlateNodes, farLabels + ' of ' + nPlateNodes);
var tinyLabels = labelCount(plate, '', 4.0, { showNodeIds: true }) - gizmoText;
check('numbering: zooming OUT crowds them, so fewer are shown (and zooming in shows more)', tinyLabels < farLabels, tinyLabels + ' vs ' + farLabels);
check('numbering: element numbers are drawn too', labelCount(plate, '', 1, { showElementIds: true }) - gizmoText > 0);
var frameLabels = labelCount(frame, 'gravity.', 1, { showNodeIds: true, showElementIds: true }) - gizmoText;
check('numbering: a sparse frame shows every node and element number (8 + 10)', frameLabels === 18, String(frameLabels));
check('numbering: a selected node is always labelled, even with the toggles off', labelCount(frame, 'gravity.', 1, { selectedNode: 3 }) - gizmoText === 1);
check('numbering: a selected element is always labelled, even with the toggles off', labelCount(frame, 'gravity.', 1, { selectedEl: 2 }) - gizmoText === 1);

/* ---- panels ---- */
function ctxFor(d, elId, extra) {
  var rc = d.results.cases[extra && extra.caseKey || ''];
  return Object.assign({ model: d.model, element: d.model.elementById[elId], elem: rc.elem[elId], units: PN.unitsOf(d.model), axes: 'local' }, extra || {});
}
var u = PN.unitsOf(cant.model);
check('units: SI header gives N, m, Pa', u.force === 'N' && u.length === 'm' && u.stress === 'Pa' && u.moment === 'N\u00b7m');
var bp = PN.beamPanel(ctxFor(cant, 1));
check('beam panel: six force charts + stress charts + section', (bp.match(/<svg class="chart"/g) || []).length === 9);
check('beam panel: root moment label -3000 appears', /-3000/.test(bp));
check('beam panel: all-zero axial chart says so (no invented axis)', /zero throughout/.test(bp));
var bg = PN.beamPanel(ctxFor(frame, 5, { caseKey: 'wind.', axes: 'global' }));
check('beam panel, global axes: Fx..Mz charts', /Force Fx/.test(bg) && /Moment Mz/.test(bg) && !/>Shear Vy/.test(bg.replace(/<details[\s\S]*/, '')));
check('beam CSV has a header and one row per station', PN.beamCSV(ctxFor(cant, 1)).split('\n').length === 10);
var sp = PN.shellPanel(ctxFor(plate, 12, { shellLoc: 'N2', shellField: 'topvm' }));
check('shell panel: tables for both faces, Q column for the Q8, sketch + 2 Mohr circles + thickness plot', /Qx/.test(sp) && (sp.match(/Stress on the/g) || []).length === 2 && (sp.match(/<svg class="chart"/g) || []).length === 4);
check('truss panel via the frame example', /axial force/.test(PN.trussPanel(ctxFor(frame, 9, { caseKey: 'gravity.' }))));
check('chart escapes its title', PN.chart({ title: '<b>&', xs: [0, 1], series: [{ ys: [0, 1], color: '#000' }] }).indexOf('<b>') < 0);

console.log('\n' + (fails === 0 ? 'ALL ' + checks + ' CHECKS PASSED' : fails + ' of ' + checks + ' CHECKS FAILED'));
process.exit(fails === 0 ? 0 : 1);
