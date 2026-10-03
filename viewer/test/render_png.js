/* Renders a viewer example to a PNG with node-canvas (dev-time visual check only;
 * the viewer itself needs nothing but a browser).  Usage:
 *   node test/render_png.js <example> <fieldId> <caseKey> <out.png> [deformed] [view]
 * @napi-rs/canvas is a throw-away test dependency: npm install --prefix /tmp/njs @napi-rs/canvas */
var fs = require('fs'), path = require('path');
var canvasPkg;
try { canvasPkg = require('@napi-rs/canvas'); }
catch (e) { canvasPkg = require(process.env.NODE_CANVAS || '/tmp/njs/node_modules/@napi-rs/canvas'); }
var P = require('../js/femparse.js'), M = require('../js/femmath.js'),
    S = require('../js/femscene.js'), R = require('../js/render3d.js');

var ex = process.argv[2], fieldId = process.argv[3] || 'none', caseKey = process.argv[4] || '', out = process.argv[5] || '/tmp/out.png';
var deformed = process.argv[6] !== 'undeformed', view = process.argv[7] || 'iso';
var dir = path.join(__dirname, '..', 'examples', ex);
var model = P.parseModel(fs.readFileSync(path.join(dir, 'model.fem'), 'utf8'));
var results = P.parseResults(fs.readFileSync(path.join(dir, 'results.txt'), 'utf8'));
var W = 900, Hh = 620;
var cv = canvasPkg.createCanvas(W, Hh), ctx = cv.getContext('2d');
var cam = new M.Camera(); cam.width = W; cam.height = Hh; cam.setView(view);
var s0 = S.build(model, results, caseKey, { deformed: false });
cam.fit(s0.center, s0.radius);
var scene = S.build(model, results, caseKey, { deformed: deformed, scale: s0.autoScale ? S.build(model, results, caseKey, {deformed:true,scale:1}).autoScale : 1, fieldId: fieldId });
var unit = '';
R.draw(ctx, scene, cam, { theme: process.env.THEME || 'dark', showGhost: true, showNodes: process.env.NODES !== '0', showNodeIds: !!process.env.NODEIDS, showElementIds: !!process.env.ELIDS,
  selectedEl: process.env.SELEL ? Number(process.env.SELEL) : null, selectedNode: process.env.SELNODE ? Number(process.env.SELNODE) : null, showSupports: true, showLoads: true,
  showMesh: true, detail: 'high', fmtVal: function (v) { return M.fmt(v, 3); } });
fs.writeFileSync(out, cv.toBuffer('image/png'));
console.log('wrote', out, 'range', JSON.stringify(scene.range), 'autoScale', scene.autoScale.toFixed(1), 'groups', scene.groups.length);
