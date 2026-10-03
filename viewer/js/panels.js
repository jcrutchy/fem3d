/* panels.js -- the element/node detail panel.
 *
 * Selecting an element in the 3D view shows its internal forces and stresses
 * HERE, in a 2D panel, rather than as diagrams drawn in perspective on the
 * structure (which hide each other and are hard to read). Every function returns
 * an HTML string (with inline SVG); app.js drops it into the page and wires the
 * few controls (data-action attributes). No DOM is touched here, so it all runs
 * under node for testing. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./femmath.js'), require('./femscene.js'));
  else root.FemPanels = factory(root.FemMath, root.FemScene);
}(typeof self !== 'undefined' ? self : this, function (M, Scene) {
  'use strict';
  var V = M.V, fmt = M.fmt;

  var COL = { a: '#4c8dff', b: '#e5484d', c: '#3fb950', d: '#e3b341', e: '#b392f0', f: '#39c5cf' };

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function r1(v) { return (isFinite(v) ? v : 0).toFixed(1); }
  function fin(v) { return (typeof v === 'number' && isFinite(v)) ? v : 0; }

  /* ----------------------------------------------------------------- units */
  function unitsOf(model) {
    var u = { force: '', length: '', stress: '', moment: '', fpl: '', mpl: '' };
    var s = (model && model.header && model.header.Units) || '';
    var m = /\(([^)]*)\)/.exec(s);
    var toks = m ? m[1].split(',').map(function (t) { return t.trim(); }) : [];
    toks.forEach(function (t) {
      if (/^(N|kN|MN|lbf|kip|kgf|tf)$/.test(t)) u.force = t;
      else if (/^(m|mm|cm|in|ft)$/.test(t)) u.length = t;
      else if (/^(Pa|kPa|MPa|GPa|psi|ksi)$/.test(t)) u.stress = t;
    });
    if (u.force && u.length) {
      u.moment = u.force + '\u00b7' + u.length;
      u.fpl = u.force + '/' + u.length;
      u.mpl = u.force + '\u00b7' + u.length + '/' + u.length;
    }
    return u;
  }
  function withUnit(label, unit) { return unit ? label + ' (' + unit + ')' : label; }

  /* ----------------------------------------------------------------- chart */
  /* o: { title, unit, xs, series:[{ys, color, name}], xlabel, mark (index), W, H } */
  function chart(o) {
    var W = o.W || 320, H = o.H || 120, ml = 52, mr = 12, mt = 24, mb = 24;
    var xs = o.xs.map(fin), n = xs.length;
    var lo = 0, hi = 0;
    o.series.forEach(function (s) { s.ys.forEach(function (v) { v = fin(v); if (v < lo) lo = v; if (v > hi) hi = v; }); });
    var allZero = hi - lo < 1e-300;
    if (allZero) { lo = -1; hi = 1; }
    var pad = (hi - lo) * 0.1;
    var ymin = lo < 0 ? lo - pad : lo, ymax = hi > 0 ? hi + pad : hi;
    if (ymax === ymin) ymax = ymin + 1;
    var x0 = xs[0], x1 = xs[n - 1] === xs[0] ? xs[0] + 1 : xs[n - 1];
    function X(v) { return ml + (v - x0) / (x1 - x0) * (W - ml - mr); }
    function Y(v) { return H - mb - (v - ymin) / (ymax - ymin) * (H - mb - mt); }

    var svg = ['<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="' + esc(o.title) + '">'];
    svg.push('<text x="' + ml + '" y="13" font-size="11" font-weight="600" fill="currentColor">' + esc(withUnit(o.title, o.unit)) + '</text>');
    // grid + y ticks
    var step = allZero ? 2 * (ymax - ymin) : M.niceStep(ymax - ymin, 3);   // all zero: a single tick, at 0
    var t0 = allZero ? 0 : Math.ceil(ymin / step - 1e-9) * step;
    for (var t = t0; t <= ymax + 1e-9 * step; t += step) {
      var tv = Math.abs(t) < step * 1e-6 ? 0 : t, yy = Y(tv);
      svg.push('<line x1="' + ml + '" x2="' + (W - mr) + '" y1="' + r1(yy) + '" y2="' + r1(yy) + '" stroke="currentColor" stroke-opacity="' + (tv === 0 ? 0.55 : 0.14) + '" stroke-width="' + (tv === 0 ? 1.1 : 0.7) + '"/>');
      svg.push('<text x="' + (ml - 5) + '" y="' + r1(yy + 3) + '" font-size="9" text-anchor="end" fill="currentColor" fill-opacity="0.75">' + fmt(tv, 3) + '</text>');
    }
    // frame + x labels
    svg.push('<line x1="' + ml + '" x2="' + ml + '" y1="' + mt + '" y2="' + (H - mb) + '" stroke="currentColor" stroke-opacity="0.35"/>');
    svg.push('<text x="' + ml + '" y="' + (H - 9) + '" font-size="9" fill="currentColor" fill-opacity="0.75">' + fmt(x0, 3) + '</text>');
    svg.push('<text x="' + (W - mr) + '" y="' + (H - 9) + '" font-size="9" text-anchor="end" fill="currentColor" fill-opacity="0.75">' + fmt(x1, 3) + '</text>');
    if (o.xlabel) svg.push('<text x="' + ((ml + W - mr) / 2) + '" y="' + (H - 9) + '" font-size="9" text-anchor="middle" fill="currentColor" fill-opacity="0.6">' + esc(o.xlabel) + '</text>');
    if (o.mark !== undefined && o.mark >= 0 && o.mark < n)
      svg.push('<line x1="' + r1(X(xs[o.mark])) + '" x2="' + r1(X(xs[o.mark])) + '" y1="' + mt + '" y2="' + (H - mb) + '" stroke="#e3b341" stroke-dasharray="3 3" stroke-width="1.2"/>');

    if (allZero) svg.push('<text x="' + r1((ml + W - mr) / 2) + '" y="' + r1(Y(0) - 7) + '" font-size="10" text-anchor="middle" fill="currentColor" fill-opacity="0.55">zero throughout</text>');
    o.series.forEach(function (s, si) {
      var pts = s.ys.map(function (v, i) { return r1(X(xs[i])) + ',' + r1(Y(fin(v))); });
      if (si === 0 && o.series.length === 1 && n > 1)
        svg.push('<polygon points="' + r1(X(xs[0])) + ',' + r1(Y(0)) + ' ' + pts.join(' ') + ' ' + r1(X(xs[n - 1])) + ',' + r1(Y(0)) + '" fill="' + s.color + '" fill-opacity="0.18"/>');
      svg.push('<polyline points="' + pts.join(' ') + '" fill="none" stroke="' + s.color + '" stroke-width="1.8" stroke-linejoin="round"/>');
      if (n <= 25) s.ys.forEach(function (v, i) { svg.push('<circle cx="' + r1(X(xs[i])) + '" cy="' + r1(Y(fin(v))) + '" r="2.1" fill="' + s.color + '"/>'); });
    });

    // label the largest-magnitude value of each series, keeping labels inside the plot
    // area and off each other
    var placed = [];
    o.series.forEach(function (s, si) {
      var bi = 0, bm = -1;
      s.ys.forEach(function (v, i) { if (Math.abs(fin(v)) > bm) { bm = Math.abs(fin(v)); bi = i; } });
      if (bm <= 1e-12 * Math.max(Math.abs(lo), Math.abs(hi), 1e-300)) return;
      var px = X(xs[bi]), py = Y(fin(s.ys[bi]));
      var anchor = px > W - 60 ? 'end' : (px < ml + 40 ? 'start' : 'middle');
      var ty = py + (fin(s.ys[bi]) >= 0 ? -5 : 11);
      if (ty > H - mb - 3) ty = py - 5;          // would run into the x-axis labels: go above the point
      if (ty < mt + 8) ty = py + 11;             // would run into the title: go below
      for (var q = 0; q < placed.length; q++)    // another label already sits here: step down
        if (Math.abs(placed[q][0] - px) < 34 && Math.abs(placed[q][1] - ty) < 10) ty = placed[q][1] + 10;
      placed.push([px, ty]);
      svg.push('<text x="' + r1(px) + '" y="' + r1(ty) + '" font-size="9.5" font-weight="600" text-anchor="' + anchor + '" fill="' + s.color + '">' + fmt(s.ys[bi], 4) + '</text>');
    });
    // legend for multi-series charts
    if (o.series.length > 1) {
      var lx = W - mr;
      for (var k = o.series.length - 1; k >= 0; k--) {
        var nm = o.series[k].name || '';
        svg.push('<text x="' + lx + '" y="13" font-size="9.5" text-anchor="end" fill="' + o.series[k].color + '">' + esc(nm) + '</text>');
        lx -= 7 * nm.length + 10;
      }
    }
    svg.push('</svg>');
    return svg.join('');
  }

  /* ----------------------------------------------------------------- tables */
  function table(headers, rows, opts) {
    opts = opts || {};
    var scale = 0;
    rows.forEach(function (r) { r.cells.forEach(function (v) { if (typeof v === 'number' && isFinite(v) && Math.abs(v) > scale) scale = Math.abs(v); }); });
    var h = ['<table class="vals' + (opts.cls ? ' ' + opts.cls : '') + '"><thead><tr>'];
    headers.forEach(function (t) { h.push('<th>' + esc(t) + '</th>'); });
    h.push('</tr></thead><tbody>');
    rows.forEach(function (r) {
      h.push('<tr' + (r.cls ? ' class="' + r.cls + '"' : '') + '><th>' + esc(r.label) + '</th>');
      r.cells.forEach(function (v) {
        h.push('<td>' + (typeof v === 'number' ? fmt(v, 5, scale * 1e-9) : esc(v)) + '</td>');
      });
      h.push('</tr>');
    });
    h.push('</tbody></table>');
    return h.join('');
  }

  function axesToggle(mode, localLabel) {
    return '<div class="seg" role="radiogroup" aria-label="Axes">' +
      '<label><input type="radio" name="axes" data-action="axes" value="local"' + (mode !== 'global' ? ' checked' : '') + '> ' + esc(localLabel) + '</label>' +
      '<label><input type="radio" name="axes" data-action="axes" value="global"' + (mode === 'global' ? ' checked' : '') + '> Global axes</label></div>';
  }

  function dirText(v) { return '(' + v.map(function (x) { return fmt(x, 3, 1e-9); }).join(', ') + ')'; }

  /* ------------------------------------------------------------------ truss */
  function trussPanel(c) {
    var el = c.element, r = c.elem, u = c.units;
    var p = c.model.properties[el.prop] || {};
    var a = c.model.nodeById[el.nodes[0]], b = c.model.nodeById[el.nodes[1]];
    var L = a && b ? V.norm(V.sub([b.x, b.y, b.z], [a.x, a.y, a.z])) : 0;
    var h = ['<h3>Truss ' + el.id + '</h3><p class="sub">nodes ' + el.nodes.join(' \u2192 ') + ' \u00b7 property ' + el.prop +
      ' \u00b7 length ' + fmt(L, 5) + (u.length ? ' ' + u.length : '') + (p.area ? ' \u00b7 area ' + fmt(p.area, 4) : '') + '</p>'];
    if (!r || r.kind !== 'truss') return h.join('') + '<p class="warn">No truss results for this element in the selected case.</p>';
    var state = r.N > 0 ? 'tension' : (r.N < 0 ? 'compression' : 'unloaded');
    h.push('<div class="big ' + (r.N > 0 ? 'tens' : (r.N < 0 ? 'comp' : '')) + '">' + fmt(r.N, 5) + (u.force ? ' ' + u.force : '') + '<small>axial force \u2014 ' + state + '</small></div>');
    h.push(table(['Quantity', 'Value'], [
      { label: withUnit('Axial force N', u.force), cells: [r.N] },
      { label: withUnit('Axial stress \u03c3 = N/A', u.stress), cells: [r.sigma] },
      { label: withUnit('von Mises', u.stress), cells: [r.vm] },
      { label: withUnit('Tresca', u.stress), cells: [r.tresca] }]));
    h.push('<p class="note">A truss carries axial force only, so von Mises and Tresca both equal |\u03c3|.</p>');
    return h.join('');
  }

  /* ------------------------------------------------------------------- beam */
  var LOCAL_FORCES = [['N', 'Axial N', 'force'], ['VY', 'Shear Vy', 'force'], ['VZ', 'Shear Vz', 'force'],
                      ['T', 'Torque T', 'moment'], ['MY', 'Moment My', 'moment'], ['MZ', 'Moment Mz', 'moment']];
  var GLOBAL_FORCES = [['GFX', 'Force Fx', 'force'], ['GFY', 'Force Fy', 'force'], ['GFZ', 'Force Fz', 'force'],
                       ['GMX', 'Moment Mx', 'moment'], ['GMY', 'Moment My', 'moment'], ['GMZ', 'Moment Mz', 'moment']];

  function argmax(arr, f) {
    var bi = 0, bv = -Infinity;
    arr.forEach(function (x, i) { var v = f(x); if (v > bv) { bv = v; bi = i; } });
    return bi;
  }

  // Draw the beam section at one station: the linear stress plane through the four
  // corner values, with the neutral axis where the stress changes sign.
  function sectionSVG(st, prop, u) {
    var cy = prop.Cy, cz = prop.Cz;
    var s1 = st.SIGC1, s2 = st.SIGC2, s3 = st.SIGC3, s4 = st.SIGC4;
    var W = 300, H = 210, cx0 = 150, cy0 = 100;
    var half = Math.max(cy, cz), k = 70 / half;           // pixels per unit length
    var wpx = cy * k, hpx = cz * k;
    var a = (s1 + s2 + s3 + s4) / 4;
    var b = (s1 - s2 + s3 - s4) / (4 * cy), c = (s1 + s2 - s3 - s4) / (4 * cz);
    var lo = Math.min(s1, s2, s3, s4), hi = Math.max(s1, s2, s3, s4);
    if (hi - lo < 1e-12 * Math.max(1, Math.abs(hi))) { var p = Math.max(1e-12, Math.abs(hi) * 0.5); lo -= p; hi += p; }
    var svg = ['<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Section stress">'];
    var N = 18, i, j;
    for (j = 0; j < N; j++) for (i = 0; i < N; i++) {
      var y = -cy + (i + 0.5) * 2 * cy / N, z = cz - (j + 0.5) * 2 * cz / N;
      var col = M.rgbCss(M.rainbow((a + b * y + c * z - lo) / (hi - lo)));
      svg.push('<rect x="' + r1(cx0 - wpx + i * 2 * wpx / N) + '" y="' + r1(cy0 - hpx + j * 2 * hpx / N) + '" width="' + r1(2 * wpx / N + 0.6) + '" height="' + r1(2 * hpx / N + 0.6) + '" fill="' + col + '"/>');
    }
    svg.push('<rect x="' + r1(cx0 - wpx) + '" y="' + r1(cy0 - hpx) + '" width="' + r1(2 * wpx) + '" height="' + r1(2 * hpx) + '" fill="none" stroke="currentColor" stroke-opacity="0.8"/>');
    // neutral axis: a + b*y + c*z = 0, clipped to the rectangle
    var pts = [];
    [[-cy, null], [cy, null]].forEach(function (e) { if (Math.abs(c) > 1e-30) { var z0 = -(a + b * e[0]) / c; if (z0 >= -cz - 1e-12 && z0 <= cz + 1e-12) pts.push([e[0], z0]); } });
    [[null, -cz], [null, cz]].forEach(function (e) { if (Math.abs(b) > 1e-30) { var y0 = -(a + c * e[1]) / b; if (y0 >= -cy - 1e-12 && y0 <= cy + 1e-12) pts.push([y0, e[1]]); } });
    if (pts.length >= 2 && lo < 0 && hi > 0)
      svg.push('<line x1="' + r1(cx0 + pts[0][0] * k) + '" y1="' + r1(cy0 - pts[0][1] * k) + '" x2="' + r1(cx0 + pts[1][0] * k) + '" y2="' + r1(cy0 - pts[1][1] * k) + '" stroke="#fff" stroke-width="2" stroke-dasharray="5 3"/>' +
        '<line x1="' + r1(cx0 + pts[0][0] * k) + '" y1="' + r1(cy0 - pts[0][1] * k) + '" x2="' + r1(cx0 + pts[1][0] * k) + '" y2="' + r1(cy0 - pts[1][1] * k) + '" stroke="#000" stroke-width="0.8" stroke-dasharray="5 3"/>');
    // corner values
    var lab = [[cx0 + wpx, cy0 - hpx, s1, 'end', -6], [cx0 - wpx, cy0 - hpx, s2, 'start', -6], [cx0 + wpx, cy0 + hpx, s3, 'end', 14], [cx0 - wpx, cy0 + hpx, s4, 'start', 14]];
    lab.forEach(function (l, idx) {
      svg.push('<text x="' + r1(l[0] + (l[3] === 'end' ? 0 : 0)) + '" y="' + r1(l[1] + l[4]) + '" font-size="10" font-weight="600" text-anchor="' + (l[3] === 'end' ? 'end' : 'start') + '" fill="currentColor">' + (idx + 1) + ': ' + fmt(l[2], 4) + '</text>');
    });
    // axes
    svg.push('<g stroke="currentColor" stroke-opacity="0.6" fill="currentColor" fill-opacity="0.8" font-size="10">' +
      '<line x1="' + (W - 38) + '" y1="' + (H - 22) + '" x2="' + (W - 12) + '" y2="' + (H - 22) + '"/><text x="' + (W - 10) + '" y="' + (H - 19) + '" stroke="none">y</text>' +
      '<line x1="' + (W - 38) + '" y1="' + (H - 22) + '" x2="' + (W - 38) + '" y2="' + (H - 48) + '"/><text x="' + (W - 41) + '" y="' + (H - 51) + '" stroke="none">z</text></g>');
    svg.push('<text x="8" y="' + (H - 6) + '" font-size="9" fill="currentColor" fill-opacity="0.65">viewed from +x toward the member \u00b7 stress' + (u.stress ? ' in ' + u.stress : '') + '</text>');
    svg.push('</svg>');
    return svg.join('');
  }

  function beamPanel(c) {
    var el = c.element, r = c.elem, u = c.units, mode = c.axes === 'global' ? 'global' : 'local';
    var prop = c.model.properties[el.prop] || {};
    var a = c.model.nodeById[el.nodes[0]], b = c.model.nodeById[el.nodes[1]];
    var L = a && b ? V.norm(V.sub([b.x, b.y, b.z], [a.x, a.y, a.z])) : 0;
    var h = ['<h3>Beam ' + el.id + '</h3><p class="sub">nodes ' + el.nodes.join(' \u2192 ') + ' \u00b7 property ' + el.prop +
      ' \u00b7 length ' + fmt(L, 5) + (u.length ? ' ' + u.length : '') + '</p>'];
    if (!r || r.kind !== 'beam') return h.join('') + '<p class="warn">No beam results for this element in the selected case.</p>';
    var st = r.stations, n = st.length;
    var xs = st.map(function (s) { return s.POS; });
    var hasBend = st[0].SIGC1 !== undefined;
    var sel = c.station !== undefined && c.station >= 0 && c.station < n ? c.station : argmax(st, function (s) { return s.VM || 0; });

    if (r.axes) h.push('<p class="sub">local x ' + dirText(r.axes.ex) + ' \u00b7 y ' + dirText(r.axes.ey) + ' \u00b7 z ' + dirText(r.axes.ez) + '</p>');
    h.push(axesToggle(mode, 'Member axes (principal)'));
    h.push('<p class="note">' + (mode === 'local'
      ? 'Resultants on the + face of each section, in the member\u2019s own axes. They are also the section\u2019s principal axes: a section is entered as Iy and Iz with no product of inertia.'
      : 'The same resultants resolved on the global X, Y, Z axes.') + '</p>');

    h.push('<h4>Forces and moments</h4><div class="grid2">');
    (mode === 'local' ? LOCAL_FORCES : GLOBAL_FORCES).forEach(function (f, i) {
      h.push(chart({ title: f[1], unit: f[2] === 'force' ? u.force : u.moment, xs: xs, xlabel: 's' + (u.length ? ' (' + u.length + ')' : ''), mark: sel,
        series: [{ ys: st.map(function (s) { return s[f[0]]; }), color: [COL.a, COL.c, COL.d, COL.e, COL.b, COL.f][i] }] }));
    });
    h.push('</div>');

    h.push('<h4>Stresses</h4>');
    if (!hasBend) h.push('<p class="note">Axial stress only (N/A). Add Cy and Cz \u2014 the distances from the centroid to the extreme fibres \u2014 to this beam\u2019s property line to get bending stress, and Rt for torsional shear.</p>');
    h.push('<div class="grid2">');
    h.push(chart({ title: 'Normal stress', unit: u.stress, xs: xs, mark: sel, xlabel: 's',
      series: [{ ys: st.map(function (s) { return s.SIGMAX; }), color: COL.b, name: 'max' }, { ys: st.map(function (s) { return s.SIGMIN; }), color: COL.a, name: 'min' }] }));
    h.push(chart({ title: 'Equivalent stress', unit: u.stress, xs: xs, mark: sel, xlabel: 's',
      series: [{ ys: st.map(function (s) { return s.VM; }), color: COL.d, name: 'von Mises' }, { ys: st.map(function (s) { return s.TRESCA; }), color: COL.e, name: 'Tresca' }] }));
    if (st.some(function (s) { return Math.abs(s.TAU) > 0; }))
      h.push(chart({ title: 'Torsional shear \u03c4', unit: u.stress, xs: xs, mark: sel, xlabel: 's', series: [{ ys: st.map(function (s) { return s.TAU; }), color: COL.c }] }));
    h.push('</div><p class="note">Stresses are the worst of the four section corners. Transverse (flexural) shear stress is not included \u2014 it depends on the section shape.</p>');

    if (hasBend && prop.Cy > 0 && prop.Cz > 0) {
      h.push('<h4>Section at s = ' + fmt(st[sel].POS, 4) + (u.length ? ' ' + u.length : '') + '</h4>');
      h.push('<input class="slider" type="range" min="0" max="' + (n - 1) + '" step="1" value="' + sel + '" data-action="station" aria-label="Station">');
      h.push('<div class="slidelabels"><span>node ' + el.nodes[0] + '</span><span>station ' + sel + ' of ' + (n - 1) + '</span><span>node ' + el.nodes[1] + '</span></div>');
      h.push(sectionSVG(st[sel], prop, u));
      h.push('<p class="note">Corners 1\u20134 are (+y,+z), (\u2212y,+z), (+y,\u2212z), (\u2212y,\u2212z). The dashed line is the neutral axis (zero stress).</p>');
    }

    // station table
    var heads = ['s'].concat((mode === 'local' ? LOCAL_FORCES : GLOBAL_FORCES).map(function (f) { return f[1].split(' ').pop(); }), ['\u03c3max', '\u03c3min', '\u03c4', 'vM', 'Tresca']);
    var rows = st.map(function (s, i) {
      return { label: String(i), cls: i === sel ? 'sel' : '', cells: [s.POS].concat((mode === 'local' ? LOCAL_FORCES : GLOBAL_FORCES).map(function (f) { return s[f[0]]; }),
        [s.SIGMAX, s.SIGMIN, s.TAU, s.VM, s.TRESCA]) };
    });
    h.push('<details><summary>Station table (' + n + ' stations)</summary><div class="scroll">' + table(['#'].concat(heads), rows) + '</div>' +
      '<button type="button" class="btn" data-action="copycsv">Copy as CSV</button></details>');
    return h.join('');
  }

  // CSV of the beam station table (used by the copy button)
  function beamCSV(c) {
    var r = c.elem; if (!r || r.kind !== 'beam') return '';
    var keys = ['POS', 'N', 'VY', 'VZ', 'T', 'MY', 'MZ', 'GFX', 'GFY', 'GFZ', 'GMX', 'GMY', 'GMZ', 'SIGAX', 'SIGMAX', 'SIGMIN', 'TAU', 'VM', 'TRESCA'];
    var out = ['station,' + keys.join(',')];
    r.stations.forEach(function (s, i) { out.push(i + ',' + keys.map(function (k) { return s[k] === undefined ? '' : s[k]; }).join(',')); });
    return out.join('\n');
  }

  /* ------------------------------------------------------------------ shell */
  var LOCS = ['C', 'N1', 'N2', 'N3', 'N4'];
  var LOCNAME = { C: 'centre', N1: 'corner 1', N2: 'corner 2', N3: 'corner 3', N4: 'corner 4' };

  function mohrSVG(st, title, u) {
    var W = 300, H = 200, ml = 18, mr = 18;
    var avg = (st.Sxx + st.Syy) / 2, R = Math.sqrt(Math.pow((st.Sxx - st.Syy) / 2, 2) + st.Txy * st.Txy);
    var lo = avg - R, hi = avg + R, span = Math.max(hi - lo, 1e-300);
    var lim = Math.max(Math.abs(lo), Math.abs(hi), R) * 1.18 || 1;
    var xmin = Math.min(lo, 0) - 0.18 * lim, xmax = Math.max(hi, 0) + 0.18 * lim;
    var k = (W - ml - mr) / (xmax - xmin);
    function X(v) { return ml + (v - xmin) * k; }
    var cyp = H / 2 - 2;
    function Y(t) { return cyp - t * k; }
    var svg = ['<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Mohr circle, ' + esc(title) + '">'];
    svg.push('<text x="' + ml + '" y="13" font-size="11" font-weight="600" fill="currentColor">' + esc(title) + '</text>');
    svg.push('<line x1="' + ml + '" x2="' + (W - mr) + '" y1="' + r1(Y(0)) + '" y2="' + r1(Y(0)) + '" stroke="currentColor" stroke-opacity="0.5"/>');
    svg.push('<line x1="' + r1(X(0)) + '" x2="' + r1(X(0)) + '" y1="24" y2="' + (H - 8) + '" stroke="currentColor" stroke-opacity="0.3"/>');
    svg.push('<text x="' + (W - mr) + '" y="' + r1(Y(0) - 4) + '" font-size="9" text-anchor="end" fill="currentColor" fill-opacity="0.7">\u03c3</text>');
    svg.push('<text x="' + r1(X(0) + 4) + '" y="34" font-size="9" fill="currentColor" fill-opacity="0.7">\u03c4</text>');
    svg.push('<text x="' + ml + '" y="' + (H - 4) + '" font-size="9" fill="' + COL.d + '">\u25cf (\u03c3xx, \u03c4xy) and (\u03c3yy, \u2212\u03c4xy): the two face states</text>');
    if (R > 1e-12 * Math.max(Math.abs(avg), 1e-300) || R > 0)
      svg.push('<circle cx="' + r1(X(avg)) + '" cy="' + r1(Y(0)) + '" r="' + r1(R * k) + '" fill="' + COL.a + '" fill-opacity="0.12" stroke="' + COL.a + '" stroke-width="1.6"/>');
    // the two stress-state points A (sxx, txy) and B (syy, -txy)
    svg.push('<line x1="' + r1(X(st.Sxx)) + '" y1="' + r1(Y(st.Txy)) + '" x2="' + r1(X(st.Syy)) + '" y2="' + r1(Y(-st.Txy)) + '" stroke="' + COL.d + '" stroke-width="1.2" stroke-dasharray="3 2"/>');
    svg.push('<circle cx="' + r1(X(st.Sxx)) + '" cy="' + r1(Y(st.Txy)) + '" r="3.2" fill="' + COL.d + '"/>');
    svg.push('<circle cx="' + r1(X(st.Syy)) + '" cy="' + r1(Y(-st.Txy)) + '" r="3.2" fill="' + COL.d + '"/>');
    // principal stresses on the axis
    [[hi, 'S1', COL.b], [lo, 'S2', COL.c]].forEach(function (p) {
      svg.push('<circle cx="' + r1(X(p[0])) + '" cy="' + r1(Y(0)) + '" r="3.4" fill="' + p[2] + '"/>');
      svg.push('<text x="' + r1(X(p[0])) + '" y="' + r1(Y(0) + 15) + '" font-size="9.5" font-weight="600" text-anchor="middle" fill="' + p[2] + '">' + p[1] + ' ' + fmt(p[0], 4) + '</text>');
    });
    svg.push('<text x="' + r1(X(avg)) + '" y="' + r1(Y(R) - 4) + '" font-size="9.5" text-anchor="middle" fill="currentColor" fill-opacity="0.85">\u03c4max ' + fmt(R, 4) + '</text>');
    svg.push('</svg>');
    return svg.join('');
  }

  function thicknessSVG(top, bot, t, u) {
    var W = 300, H = 200, ml = 40, mr = 14, mt = 22, mb = 52;
    var comps = [['\u03c3xx', top.Sxx, bot.Sxx, COL.b], ['\u03c3yy', top.Syy, bot.Syy, COL.a], ['\u03c4xy', top.Txy, bot.Txy, COL.c]];
    var lim = 0;
    comps.forEach(function (c) { lim = Math.max(lim, Math.abs(c[1]), Math.abs(c[2])); });
    if (lim === 0) lim = 1;
    function X(v) { return ml + (v + lim * 1.12) / (2.24 * lim) * (W - ml - mr); }
    function Y(z) { return mt + (0.5 - z) * (H - mt - mb); }  // z in [-0.5, 0.5] of the thickness
    var svg = ['<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Stress through the thickness">'];
    svg.push('<text x="' + ml + '" y="13" font-size="11" font-weight="600" fill="currentColor">Through the thickness' + (u.stress ? ' (' + u.stress + ')' : '') + '</text>');
    svg.push('<rect x="' + ml + '" y="' + mt + '" width="' + (W - ml - mr) + '" height="' + (H - mt - mb) + '" fill="currentColor" fill-opacity="0.04" stroke="currentColor" stroke-opacity="0.3"/>');
    svg.push('<line x1="' + r1(X(0)) + '" x2="' + r1(X(0)) + '" y1="' + mt + '" y2="' + (H - mb) + '" stroke="currentColor" stroke-opacity="0.55"/>');
    svg.push('<text x="' + (ml - 4) + '" y="' + (mt + 8) + '" font-size="9" text-anchor="end" fill="currentColor" fill-opacity="0.75">top</text>');
    svg.push('<text x="' + (ml - 4) + '" y="' + (H - mb) + '" font-size="9" text-anchor="end" fill="currentColor" fill-opacity="0.75">bottom</text>');
    svg.push('<text x="' + (ml - 4) + '" y="' + r1((mt + H - mb) / 2 + 3) + '" font-size="9" text-anchor="end" fill="currentColor" fill-opacity="0.75">mid</text>');
    comps.forEach(function (c, i) {
      svg.push('<line x1="' + r1(X(c[1])) + '" y1="' + r1(Y(0.5)) + '" x2="' + r1(X(c[2])) + '" y2="' + r1(Y(-0.5)) + '" stroke="' + c[3] + '" stroke-width="2"/>');
      svg.push('<circle cx="' + r1(X(c[1])) + '" cy="' + r1(Y(0.5)) + '" r="2.6" fill="' + c[3] + '"/><circle cx="' + r1(X(c[2])) + '" cy="' + r1(Y(-0.5)) + '" r="2.6" fill="' + c[3] + '"/>');
      svg.push('<text x="' + ml + '" y="' + (H - mb + 14 + i * 12) + '" font-size="9.5" fill="' + c[3] + '">' + c[0] + ':  top ' + fmt(c[1], 4) + '   \u2192   bottom ' + fmt(c[2], 4) + '</text>');
    });
    svg.push('</svg>');
    return svg.join('');
  }

  // Element sketch in its own plane with values at the centre and corners.
  function sketchSVG(c, fieldId) {
    var el = c.element, r = c.elem, m = c.model, f = Scene.FIELD_BY_ID[fieldId];
    var ax = r.axes;
    var p1 = m.nodeById[el.nodes[0]];
    var corners = [0, 1, 2, 3].map(function (i) {
      var n = m.nodeById[el.nodes[i]], d = V.sub([n.x, n.y, n.z], [p1.x, p1.y, p1.z]);
      return [V.dot(d, ax.ex), V.dot(d, ax.ey)];
    });
    var cen = [(corners[0][0] + corners[1][0] + corners[2][0] + corners[3][0]) / 4, (corners[0][1] + corners[1][1] + corners[2][1] + corners[3][1]) / 4];
    var minx = Infinity, maxx = -Infinity, miny = Infinity, maxy = -Infinity;
    corners.forEach(function (q) { minx = Math.min(minx, q[0]); maxx = Math.max(maxx, q[0]); miny = Math.min(miny, q[1]); maxy = Math.max(maxy, q[1]); });
    var W = 300, H = 210, pad = 36;
    var k = Math.min((W - 2 * pad) / Math.max(maxx - minx, 1e-30), (H - 2 * pad) / Math.max(maxy - miny, 1e-30));
    var ox = (W - (maxx - minx) * k) / 2, oy = (H + (maxy - miny) * k) / 2;
    function P(q) { return [ox + (q[0] - minx) * k, oy - (q[1] - miny) * k]; }
    var vals = LOCS.map(function (l) { return r.loc[l] ? f.shell(r.loc[l]) : null; });
    var good = vals.filter(function (v) { return v !== null && isFinite(v); });
    var lo = Math.min.apply(null, good), hi = Math.max.apply(null, good);
    if (!(hi - lo > 1e-12 * Math.max(1, Math.abs(hi)))) { var pd = Math.max(1e-12, Math.abs(hi) * 0.5); lo -= pd; hi += pd; }
    var svg = ['<svg class="chart" viewBox="0 0 ' + W + ' ' + H + '" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Element sketch">'];
    var pc = P(cen);
    for (var i = 0; i < 4; i++) {
      var a = P(corners[i]), b = P(corners[(i + 1) % 4]);
      var v = (vals[0] + vals[1 + i] + vals[1 + (i + 1) % 4]) / 3;
      svg.push('<polygon points="' + r1(pc[0]) + ',' + r1(pc[1]) + ' ' + r1(a[0]) + ',' + r1(a[1]) + ' ' + r1(b[0]) + ',' + r1(b[1]) + '" fill="' + M.rgbCss(M.rainbow((v - lo) / (hi - lo))) + '" stroke="' + M.rgbCss(M.rainbow((v - lo) / (hi - lo))) + '" stroke-width="0.6"/>');
    }
    svg.push('<polygon points="' + corners.map(function (q) { var a2 = P(q); return r1(a2[0]) + ',' + r1(a2[1]); }).join(' ') + '" fill="none" stroke="currentColor" stroke-width="1.4"/>');
    corners.forEach(function (q, i) {
      var a3 = P(q), v2 = vals[1 + i];
      var dx = a3[0] < W / 2 ? -1 : 1, dy = a3[1] < H / 2 ? -1 : 1;
      svg.push('<circle cx="' + r1(a3[0]) + '" cy="' + r1(a3[1]) + '" r="3" fill="currentColor"/>');
      svg.push('<text x="' + r1(a3[0] + dx * 6) + '" y="' + r1(a3[1] + dy * 9) + '" font-size="9.5" font-weight="600" text-anchor="' + (dx < 0 ? 'end' : 'start') + '" fill="currentColor">' +
        'n' + el.nodes[i] + ': ' + (v2 === null ? '\u2013' : fmt(v2, 4)) + '</text>');
    });
    var cl = vals[0] === null ? '\u2013' : fmt(vals[0], 4);
    svg.push('<text x="' + r1(pc[0]) + '" y="' + r1(pc[1] + 3) + '" font-size="10" font-weight="700" text-anchor="middle" fill="none" stroke="#fff" stroke-width="3" stroke-linejoin="round">' + cl + '</text>');
    svg.push('<text x="' + r1(pc[0]) + '" y="' + r1(pc[1] + 3) + '" font-size="10" font-weight="700" text-anchor="middle" fill="#000">' + cl + '</text>');
    svg.push('<g stroke="currentColor" fill="currentColor" font-size="10"><line x1="10" y1="' + (H - 10) + '" x2="36" y2="' + (H - 10) + '"/><text x="39" y="' + (H - 6) + '" stroke="none">x</text>' +
      '<line x1="10" y1="' + (H - 10) + '" x2="10" y2="' + (H - 36) + '"/><text x="7" y="' + (H - 39) + '" stroke="none">y</text></g>');
    svg.push('</svg>');
    return svg.join('');
  }

  function shellPanel(c) {
    var el = c.element, r = c.elem, u = c.units;
    var prop = c.model.properties[el.prop] || {};
    var h = ['<h3>' + (el.type === 'shellq8' ? 'Shell Q8 ' : 'Shell Q4 ') + el.id + '</h3><p class="sub">nodes ' + el.nodes.join('\u2013') + ' \u00b7 property ' + el.prop +
      (prop.thickness ? ' \u00b7 thickness ' + fmt(prop.thickness, 4) + (u.length ? ' ' + u.length : '') : '') + '</p>'];
    if (!r || r.kind !== 'shell' || !r.loc.C) return h.join('') + '<p class="warn">No shell results for this element in the selected case.</p>';
    var loc = LOCS.indexOf(c.shellLoc) >= 0 ? c.shellLoc : 'C';
    var fieldId = Scene.FIELD_BY_ID[c.shellField] && Scene.FIELD_BY_ID[c.shellField].shell ? c.shellField : 'vm';
    var hasQ = r.loc.C.QX !== undefined;
    if (r.axes) h.push('<p class="sub">element x ' + dirText(r.axes.ex) + ' \u00b7 y ' + dirText(r.axes.ey) + ' \u00b7 normal z ' + dirText(r.axes.ez) + '</p>');

    h.push('<div class="row"><label>Show <select data-action="shellfield">' +
      Scene.FIELDS.filter(function (f) { return f.shell; }).map(function (f) {
        return '<option value="' + f.id + '"' + (f.id === fieldId ? ' selected' : '') + '>' + esc(f.label) + '</option>';
      }).join('') + '</select></label>' +
      '<label>Point <select data-action="shellloc">' + LOCS.map(function (l) {
        return '<option value="' + l + '"' + (l === loc ? ' selected' : '') + '>' + LOCNAME[l] + '</option>';
      }).join('') + '</select></label></div>');
    if (r.axes) h.push(sketchSVG(c, fieldId));
    h.push('<p class="note">Values are at the centre and the four corner nodes of this element alone, not averaged with its neighbours, so adjacent elements can disagree on a coarse mesh.</p>');

    h.push('<h4>Forces and moments per unit length</h4>');
    var hd = ['Point', 'Nxx', 'Nyy', 'Nxy', 'Mxx', 'Myy', 'Mxy'].concat(hasQ ? ['Qx', 'Qy'] : []);
    h.push('<div class="scroll">' + table(hd, LOCS.map(function (l) {
      var o = r.loc[l] || {};
      return { label: l === 'C' ? 'centre' : l.replace('N', 'corner '), cls: l === loc ? 'sel' : '', cells: [o.NXX, o.NYY, o.NXY, o.MXX, o.MYY, o.MXY].concat(hasQ ? [o.QX, o.QY] : []) };
    })) + '</div>');
    h.push('<p class="note">N' + (u.fpl ? ' in ' + u.fpl : '') + ' (tension +), M' + (u.mpl ? ' in ' + u.mpl : '') + ', in the element axes.' +
      (hasQ ? ' Q is noisy at the corners; read it at the centre.' : ' This thin-plate element carries no transverse shear strain, so there is no Q.') + '</p>');

    ['top', 'bot'].forEach(function (face) {
      h.push('<h4>Stress on the ' + (face === 'top' ? 'top (+z)' : 'bottom (\u2212z)') + ' face' + (u.stress ? ' (' + u.stress + ')' : '') + '</h4>');
      h.push('<div class="scroll">' + table(['Point', '\u03c3xx', '\u03c3yy', '\u03c4xy', 'S1', 'S2', '\u03b8 (\u00b0)', 'von Mises', 'Tresca'], LOCS.map(function (l) {
        var o = (r.loc[l] || {})[face] || {};
        return { label: l === 'C' ? 'centre' : l.replace('N', 'corner '), cls: l === loc ? 'sel' : '',
                 cells: [o.SXX, o.SYY, o.TXY, o.S1, o.S2, (o.ANG || 0) * 180 / Math.PI, o.VM, o.TRESCA] };
      })) + '</div>');
    });
    h.push('<p class="note">\u03b8 is the angle from the element x axis to the S1 direction. Both criteria use plane stress (\u03c3zz = 0); transverse shear stress is not included.</p>');

    var sel = r.loc[loc];
    h.push('<h4>Mohr\u2019s circle \u2014 ' + LOCNAME[loc] + '</h4><div class="grid2">');
    h.push(mohrSVG({ Sxx: sel.top.SXX, Syy: sel.top.SYY, Txy: sel.top.TXY }, 'Top face', u));
    h.push(mohrSVG({ Sxx: sel.bot.SXX, Syy: sel.bot.SYY, Txy: sel.bot.TXY }, 'Bottom face', u));
    h.push('</div><div class="grid2">' + thicknessSVG({ Sxx: sel.top.SXX, Syy: sel.top.SYY, Txy: sel.top.TXY },
      { Sxx: sel.bot.SXX, Syy: sel.bot.SYY, Txy: sel.bot.TXY }, prop.thickness, u) + '</div>');
    return h.join('');
  }

  /* ------------------------------------------------------------------- node */
  function nodePanel(c) {
    var n = c.model.nodeById[c.nodeId], u = c.units, rc = c.rc;
    var h = ['<h3>Node ' + c.nodeId + '</h3>'];
    if (!n) return h.join('') + '<p class="warn">Not in the model.</p>';
    h.push('<p class="sub">at (' + fmt(n.x, 5) + ', ' + fmt(n.y, 5) + ', ' + fmt(n.z, 5) + ')' + (u.length ? ' ' + u.length : '') + '</p>');
    var d = rc ? rc.disp[c.nodeId] : null, re = rc ? rc.react[c.nodeId] : null;
    var sup = c.supports && c.supports[c.nodeId] ? Object.keys(c.supports[c.nodeId]).filter(function (k) { return c.supports[c.nodeId][k]; }) : [];
    var ld = c.loads && c.loads[c.nodeId];
    if (sup.length) h.push('<p class="sub">restrained: ' + sup.join(', ') + '</p>');
    var rows = [];
    ['x', 'y', 'z', 'rx', 'ry', 'rz'].forEach(function (dof, i) {
      rows.push({ label: dof, cells: [d ? d[dof] : null, re && re[dof] !== undefined ? re[dof] : '\u2013',
                  ld ? (i < 3 ? ld.f[i] : ld.m[i - 3]) : '\u2013'].map(function (v) { return v === null ? '\u2013' : v; }) });
    });
    h.push(table(['dof', withUnit('displacement', i0(dofUnit(u, 'x'))), 'reaction', 'applied load'], rows));
    h.push('<p class="note">Displacements in ' + (u.length || 'model length units') + ' and radians; reactions only at restrained dofs.</p>');
    return h.join('');
  }
  function dofUnit(u) { return u.length; }
  function i0(x) { return x; }

  return { chart: chart, table: table, unitsOf: unitsOf, trussPanel: trussPanel, beamPanel: beamPanel, shellPanel: shellPanel,
           nodePanel: nodePanel, beamCSV: beamCSV, sectionSVG: sectionSVG, mohrSVG: mohrSVG, thicknessSVG: thicknessSVG,
           sketchSVG: sketchSVG, esc: esc };
}));
