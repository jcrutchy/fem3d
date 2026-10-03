/* Dev-time visual check: build a panel for one element and rasterise its SVGs (and a table-less
 * HTML-free preview) into a PNG with node-canvas.
 *   node test/render_panel.js <example> <elementId> <caseKey> <out.png> [axes] [station] */
var fs = require('fs'), path = require('path');
var cv;
try { cv = require('@napi-rs/canvas'); } catch (e) { cv = require(process.env.NODE_CANVAS || '/tmp/njs/node_modules/@napi-rs/canvas'); }
var P = require('../js/femparse.js'), PN = require('../js/panels.js');
var ex = process.argv[2], elId = parseInt(process.argv[3], 10), caseKey = process.argv[4] || '', out = process.argv[5] || '/tmp/panel.png';
var axes = process.argv[6] || 'local', station = process.argv[7] !== undefined ? parseInt(process.argv[7], 10) : undefined;
var dir = path.join(__dirname, '..', 'examples', ex);
var model = P.parseModel(fs.readFileSync(path.join(dir, 'model.fem'), 'utf8'));
var results = P.parseResults(fs.readFileSync(path.join(dir, 'results.txt'), 'utf8'));
var rc = results.cases[caseKey], el = model.elementById[elId];
var c = { model: model, element: el, elem: rc.elem[elId], units: PN.unitsOf(model), axes: axes, station: station, shellLoc: process.env.LOC || 'C', shellField: process.env.FIELD || 'vm' };
var html = el.type === 'truss' ? PN.trussPanel(c) : el.type === 'beam' ? PN.beamPanel(c) : PN.shellPanel(c);
var svgs = html.match(/<svg[\s\S]*?<\/svg>/g) || [];
fs.writeFileSync(out.replace('.png', '.html'), html);
(async function () {
  var cols = 2, cw = 330, ch = 215;
  var rows = Math.ceil(svgs.length / cols);
  var canvas = cv.createCanvas(cols * cw + 10, rows * ch + 10), ctx = canvas.getContext('2d');
  ctx.fillStyle = '#1b2026'; ctx.fillRect(0, 0, canvas.width, canvas.height);
  for (var i = 0; i < svgs.length; i++) {
    var s = svgs[i].replace(/currentColor/g, '#d5dbe1');
    var vb = /viewBox="0 0 (\d+) (\d+)"/.exec(s);
    var w = +vb[1], h = +vb[2];
    s = s.replace('<svg ', '<svg width="' + w + '" height="' + h + '" ');
    var img = await cv.loadImage(Buffer.from(s));
    ctx.drawImage(img, 5 + (i % cols) * cw, 5 + Math.floor(i / cols) * ch, w, h);
  }
  fs.writeFileSync(out, canvas.toBuffer('image/png'));
  console.log('wrote', out, svgs.length, 'svgs; html bytes', html.length);
})();
