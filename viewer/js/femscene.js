/* femscene.js -- turns (model + one case's results + display options) into
 * plain drawable geometry. No DOM, no canvas: the renderer only draws what this
 * module hands it, so everything here is testable in node. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./femmath.js'));
  else root.FemScene = factory(root.FemMath);
}(typeof self !== 'undefined' ? self : this, function (M) {
  'use strict';
  var V = M.V;

  /* ---------------------------------------------------------------- fields */
  // A "field" is a scalar the user can colour the structure by. Each one says how
  // to read its value from a truss result, a beam station and a shell location;
  // a field that does not apply to an element type leaves that element grey.
  function fin(v) { return (typeof v === 'number' && isFinite(v)) ? v : null; }
  function shellWorst(loc, a, b, pick) {
    var x = loc.top[a], y = loc.bot[b === undefined ? a : b];
    if (x === undefined || y === undefined) return null;
    return pick(x, y);
  }
  function mx(a, b) { return a > b ? a : b; }
  function mn(a, b) { return a < b ? a : b; }

  var FIELDS = [
    { id: 'none',  label: 'Geometry only', group: 'Display', kind: 'none' },
    { id: 'dmag',  label: 'Displacement magnitude', group: 'Displacement', kind: 'nodal', unit: 'length' },
    { id: 'dx',    label: 'Displacement X', group: 'Displacement', kind: 'nodal', unit: 'length' },
    { id: 'dy',    label: 'Displacement Y', group: 'Displacement', kind: 'nodal', unit: 'length' },
    { id: 'dz',    label: 'Displacement Z', group: 'Displacement', kind: 'nodal', unit: 'length' },
    { id: 'N',     label: 'Axial force N', group: 'Member forces', unit: 'force',
      truss: function (r) { return r.N; }, beam: function (s) { return s.N; } },
    { id: 'Vy',    label: 'Shear Vy (local)', group: 'Member forces', unit: 'force', beam: function (s) { return s.VY; } },
    { id: 'Vz',    label: 'Shear Vz (local)', group: 'Member forces', unit: 'force', beam: function (s) { return s.VZ; } },
    { id: 'T',     label: 'Torque T', group: 'Member forces', unit: 'moment', beam: function (s) { return s.T; } },
    { id: 'My',    label: 'Moment My (local)', group: 'Member forces', unit: 'moment', beam: function (s) { return s.MY; } },
    { id: 'Mz',    label: 'Moment Mz (local)', group: 'Member forces', unit: 'moment', beam: function (s) { return s.MZ; } },
    { id: 'Nxx',   label: 'Shell Nxx', group: 'Shell forces (per length)', unit: 'force/length', shell: function (l) { return l.NXX; } },
    { id: 'Nyy',   label: 'Shell Nyy', group: 'Shell forces (per length)', unit: 'force/length', shell: function (l) { return l.NYY; } },
    { id: 'Nxy',   label: 'Shell Nxy', group: 'Shell forces (per length)', unit: 'force/length', shell: function (l) { return l.NXY; } },
    { id: 'Mxx',   label: 'Shell Mxx', group: 'Shell forces (per length)', unit: 'moment/length', shell: function (l) { return l.MXX; } },
    { id: 'Myy',   label: 'Shell Myy', group: 'Shell forces (per length)', unit: 'moment/length', shell: function (l) { return l.MYY; } },
    { id: 'Mxy',   label: 'Shell Mxy', group: 'Shell forces (per length)', unit: 'moment/length', shell: function (l) { return l.MXY; } },
    { id: 'smax',  label: 'Maximum normal stress', group: 'Stress', unit: 'stress',
      truss: function (r) { return r.sigma; }, beam: function (s) { return s.SIGMAX; },
      shell: function (l) { return shellWorst(l, 'S1', 'S1', mx); } },
    { id: 'smin',  label: 'Minimum normal stress', group: 'Stress', unit: 'stress',
      truss: function (r) { return r.sigma; }, beam: function (s) { return s.SIGMIN; },
      shell: function (l) { return shellWorst(l, 'S2', 'S2', mn); } },
    { id: 'vm',    label: 'von Mises', group: 'Stress', unit: 'stress',
      truss: function (r) { return r.vm; }, beam: function (s) { return s.VM; },
      shell: function (l) { return shellWorst(l, 'VM', 'VM', mx); } },
    { id: 'tresca', label: 'Tresca', group: 'Stress', unit: 'stress',
      truss: function (r) { return r.tresca; }, beam: function (s) { return s.TRESCA; },
      shell: function (l) { return shellWorst(l, 'TRESCA', 'TRESCA', mx); } },
    { id: 'topvm', label: 'Shell von Mises, top face', group: 'Stress', unit: 'stress',
      shell: function (l) { return l.top.VM; } },
    { id: 'botvm', label: 'Shell von Mises, bottom face', group: 'Stress', unit: 'stress',
      shell: function (l) { return l.bot.VM; } }
  ];
  var FIELD_BY_ID = {};
  FIELDS.forEach(function (f) { FIELD_BY_ID[f.id] = f; });

  function nodalValue(fieldId, d) {
    if (!d) return 0;
    var x = d.x || 0, y = d.y || 0, z = d.z || 0;
    switch (fieldId) {
      case 'dx': return x;
      case 'dy': return y;
      case 'dz': return z;
      default: return Math.sqrt(x * x + y * y + z * z);
    }
  }

  /* ---------------------------------------------------- supports and loads */
  // Work out which freedom case / load case(s) a results prefix refers to.
  function caseInputs(model, prefix) {
    var fcNames = Object.keys(model.freedomCases);
    var fc = fcNames.length ? fcNames[0] : null;
    var lcName = null;
    var p = prefix.replace(/\.$/, '');
    var m = /^FC_([^.]+)\.(.*)$/.exec(p);
    if (m) { fc = m[1]; lcName = m[2]; }
    else if (p !== '') lcName = p;
    var terms = [];
    if (lcName === null) {
      var lcs = Object.keys(model.loadCases);
      if (lcs.length) terms.push({ lc: lcs[0], factor: 1 });
    } else if (model.combinations[lcName]) {
      terms = model.combinations[lcName].slice();
    } else if (model.loadCases[lcName]) {
      terms.push({ lc: lcName, factor: 1 });
    }
    var loads = {};   // node -> {f:[3], m:[3]}
    terms.forEach(function (t) {
      (model.loadCases[t.lc] || []).forEach(function (l) {
        var e = loads[l.node] || (loads[l.node] = { f: [0, 0, 0], m: [0, 0, 0] });
        var k = ['x', 'y', 'z'].indexOf(l.dof);
        if (k >= 0) e.f[k] += t.factor * l.value;
        else e.m[['rx', 'ry', 'rz'].indexOf(l.dof)] += t.factor * l.value;
      });
    });
    var supports = {};  // node -> {x:true,...}
    (model.freedomCases[fc] || []).forEach(function (c) {
      (supports[c.node] || (supports[c.node] = {}))[c.dof] = true;
    });
    return { freedomCase: fc, loadCase: lcName, loads: loads, supports: supports };
  }

  /* ------------------------------------------------------------ beam curve */
  // Hermite cubic through the nodal translations and rotations -- the shape an
  // Euler-Bernoulli beam actually takes between its nodes (the solver's own
  // shape functions), rather than a straight chord. Needs the member axes.
  function beamPolyline(p1, p2, d1, d2, axes, scale, n) {
    var L = V.norm(V.sub(p2, p1));
    var ex = axes.ex, ey = axes.ey, ez = axes.ez;
    var t1 = [d1.x || 0, d1.y || 0, d1.z || 0], t2 = [d2.x || 0, d2.y || 0, d2.z || 0];
    var r1 = [d1.rx || 0, d1.ry || 0, d1.rz || 0], r2 = [d2.rx || 0, d2.ry || 0, d2.rz || 0];
    var u1 = V.dot(t1, ex), v1 = V.dot(t1, ey), w1 = V.dot(t1, ez);
    var u2 = V.dot(t2, ex), v2 = V.dot(t2, ey), w2 = V.dot(t2, ez);
    var thy1 = V.dot(r1, ey), thz1 = V.dot(r1, ez);
    var thy2 = V.dot(r2, ey), thz2 = V.dot(r2, ez);
    var pts = [];
    for (var i = 0; i <= n; i++) {
      var xi = i / n;
      var N1 = 1 - 3 * xi * xi + 2 * xi * xi * xi, N2 = L * (xi - 2 * xi * xi + xi * xi * xi);
      var N3 = 3 * xi * xi - 2 * xi * xi * xi,     N4 = L * (-xi * xi + xi * xi * xi);
      var u = (1 - xi) * u1 + xi * u2;
      var v = N1 * v1 + N2 * thz1 + N3 * v2 + N4 * thz2;       // slope dv/ds = rz
      var w = N1 * w1 + N2 * (-thy1) + N3 * w2 + N4 * (-thy2); // slope dw/ds = -ry
      var base = V.lerp(p1, p2, xi);
      pts.push([
        base[0] + scale * (u * ex[0] + v * ey[0] + w * ez[0]),
        base[1] + scale * (u * ex[1] + v * ey[1] + w * ez[1]),
        base[2] + scale * (u * ex[2] + v * ey[2] + w * ez[2])]);
    }
    return pts;
  }

  // piecewise-linear interpolation of per-station values at fraction t in [0,1]
  function atStations(vals, t) {
    var n = vals.length - 1;
    if (n <= 0) return vals[0];
    var x = t * n, i = Math.min(Math.floor(x), n - 1), f = x - i;
    if (vals[i] === null || vals[i + 1] === null) return null;
    return vals[i] + (vals[i + 1] - vals[i]) * f;
  }

  /* ------------------------------------------------------------ the builder */
  /* opts: { deformed, scale, fieldId, curved } */
  function build(model, results, caseKey, opts) {
    opts = opts || {};
    var rc = results && results.cases[caseKey] ? results.cases[caseKey] : null;
    var field = FIELD_BY_ID[opts.fieldId] || FIELD_BY_ID.none;

    // base bounds and maximum displacement
    var minB = [Infinity, Infinity, Infinity], maxB = [-Infinity, -Infinity, -Infinity];
    model.nodes.forEach(function (n) {
      var p = [n.x, n.y, n.z];
      for (var k = 0; k < 3; k++) { if (p[k] < minB[k]) minB[k] = p[k]; if (p[k] > maxB[k]) maxB[k] = p[k]; }
    });
    if (!model.nodes.length) { minB = [0, 0, 0]; maxB = [1, 1, 1]; }
    var size = V.norm(V.sub(maxB, minB)) || 1;
    var maxDisp = 0;
    if (rc) Object.keys(rc.disp).forEach(function (id) {
      var d = rc.disp[id], m = Math.sqrt((d.x || 0) * (d.x || 0) + (d.y || 0) * (d.y || 0) + (d.z || 0) * (d.z || 0));
      if (m > maxDisp) maxDisp = m;
    });
    var autoScale = maxDisp > 0 ? 0.08 * size / maxDisp : 1;
    // opts.scale is an absolute factor; opts.scaleMul multiplies the automatic one
    // (chosen so the largest displacement is about 8% of the model's size)
    var scale = 0;
    if (opts.deformed && rc) scale = opts.scale !== undefined ? opts.scale : autoScale * (opts.scaleMul === undefined ? 1 : opts.scaleMul);

    var base = {}, pos = {};
    model.nodes.forEach(function (n) {
      base[n.id] = [n.x, n.y, n.z];
      var d = rc ? rc.disp[n.id] : null;
      pos[n.id] = d ? [n.x + scale * (d.x || 0), n.y + scale * (d.y || 0), n.z + scale * (d.z || 0)] : base[n.id].slice();
    });

    var groups = [], lo = Infinity, hi = -Infinity;
    function note(v) { if (v !== null && isFinite(v)) { if (v < lo) lo = v; if (v > hi) hi = v; } }

    model.elements.forEach(function (el) {
      var er = rc ? rc.elem[el.id] : null;
      var g = { el: el, kind: null, ghost: null };

      if (el.type === 'truss' || el.type === 'beam') {
        var a = pos[el.nodes[0]], b = pos[el.nodes[1]];
        if (!a || !b) return;
        g.kind = el.type;
        var ghostA = base[el.nodes[0]], ghostB = base[el.nodes[1]];
        g.ghost = [ghostA, ghostB];
        var pts = [a, b], npts = 2;
        if (el.type === 'beam' && opts.curved !== false && scale !== 0 && er && er.axes && rc.disp[el.nodes[0]] && rc.disp[el.nodes[1]]) {
          npts = 17;
          pts = beamPolyline(ghostA, ghostB, rc.disp[el.nodes[0]], rc.disp[el.nodes[1]], er.axes, scale, 16);
        }
        g.pts = pts;
        // values along the member
        var vals = null;
        if (field.kind === 'nodal') {
          var va = nodalValue(field.id, rc && rc.disp[el.nodes[0]]), vb = nodalValue(field.id, rc && rc.disp[el.nodes[1]]);
          vals = pts.map(function (_, i) { return va + (vb - va) * (i / (pts.length - 1)); });
        } else if (er && el.type === 'beam' && er.kind === 'beam' && field.beam) {
          var sv = er.stations.map(function (s) { return fin(field.beam(s)); });
          vals = pts.map(function (_, i) { return atStations(sv, i / (pts.length - 1)); });
        } else if (er && er.kind === 'truss' && field.truss) {
          var tv = fin(field.truss(er));
          vals = pts.map(function () { return tv; });
        } else if (er && el.type === 'beam' && er.kind === 'beam' && field.truss && !field.beam) {
          vals = null;
        }
        g.vals = vals;
        if (vals) vals.forEach(note);
      } else if (el.type === 'shellq4' || el.type === 'shellq8') {
        var nn = el.nodes.length;
        for (var q = 0; q < nn; q++) if (!pos[el.nodes[q]]) return;
        g.kind = 'shell';
        // outline ring: corners and (Q8) midside nodes in boundary order
        var ringIdx = nn === 8 ? [0, 4, 1, 5, 2, 6, 3, 7] : [0, 1, 2, 3];
        g.ring = ringIdx.map(function (i) { return pos[el.nodes[i]]; });
        g.ghostRing = ringIdx.map(function (i) { return base[el.nodes[i]]; });
        var cx = [0, 0, 0];
        for (var c = 0; c < 4; c++) cx = V.add(cx, pos[el.nodes[c]]);
        g.center = V.mul(cx, 0.25);
        // per-ring-point values, plus the centre value
        var rv = null, cv = null;
        if (field.kind === 'nodal') {
          rv = ringIdx.map(function (i) { return nodalValue(field.id, rc && rc.disp[el.nodes[i]]); });
          var s4 = 0; for (var c2 = 0; c2 < 4; c2++) s4 += nodalValue(field.id, rc && rc.disp[el.nodes[c2]]);
          cv = s4 / 4;
        } else if (er && er.kind === 'shell' && field.shell && er.loc.C) {
          var cornerVals = [1, 2, 3, 4].map(function (i) { return er.loc['N' + i] ? fin(field.shell(er.loc['N' + i])) : null; });
          cv = fin(field.shell(er.loc.C));
          if (cornerVals.every(function (x) { return x !== null; }) && cv !== null) {
            rv = nn === 8
              ? [cornerVals[0], (cornerVals[0] + cornerVals[1]) / 2, cornerVals[1], (cornerVals[1] + cornerVals[2]) / 2,
                 cornerVals[2], (cornerVals[2] + cornerVals[3]) / 2, cornerVals[3], (cornerVals[3] + cornerVals[0]) / 2]
              : cornerVals;
          }
        }
        g.ringVals = rv; g.centerVal = cv;
        if (rv) { rv.forEach(note); note(cv); }
      } else {
        return;
      }
      groups.push(g);
    });

    var range = null;
    if (lo <= hi) {
      if (hi - lo < 1e-12 * Math.max(1, Math.abs(hi))) { var pad = Math.max(1e-12, Math.abs(hi) * 0.5); lo -= pad; hi += pad; }
      range = { min: lo, max: hi };
    }

    // bounds sphere over deformed + undeformed nodes
    var bmin = minB.slice(), bmax = maxB.slice();
    Object.keys(pos).forEach(function (id) {
      var p = pos[id];
      for (var k = 0; k < 3; k++) { if (p[k] < bmin[k]) bmin[k] = p[k]; if (p[k] > bmax[k]) bmax[k] = p[k]; }
    });
    var center = V.mul(V.add(bmin, bmax), 0.5);
    var radius = V.norm(V.sub(bmax, bmin)) / 2 || 1;

    var inputs = caseInputs(model, rc ? rc.prefix : '');
    return {
      groups: groups, pos: pos, base: base, field: field, range: range,
      center: center, radius: radius, modelSize: size,
      maxDisp: maxDisp, autoScale: autoScale, scale: scale,
      supports: inputs.supports, loads: inputs.loads,
      freedomCase: inputs.freedomCase, loadCase: inputs.loadCase
    };
  }

  return { FIELDS: FIELDS, FIELD_BY_ID: FIELD_BY_ID, build: build, beamPolyline: beamPolyline,
           caseInputs: caseInputs, atStations: atStations };
}));
