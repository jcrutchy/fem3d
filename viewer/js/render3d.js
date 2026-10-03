/* render3d.js -- draws a FemScene on a 2D canvas context (CSS-pixel coordinates).
 *
 * Plain Canvas 2D with a painter's algorithm (elements sorted far-to-near by
 * centre depth), so it needs no WebGL and the same code runs under node for the
 * image tests. draw() also returns a hit list that pick() searches. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./femmath.js'));
  else root.FemRender = factory(root.FemMath);
}(typeof self !== 'undefined' ? self : this, function (M) {
  'use strict';
  var V = M.V;

  var THEMES = {
    dark: {
      bg: '#14181d', text: '#cfd6dd', dim: '#7d8893', ghost: 'rgba(160,170,180,0.45)',
      beam: '#6aa0d8', truss: '#d8a06a', shell: [92, 128, 160], edge: 'rgba(10,14,18,0.75)',
      node: '#e6edf3', accent: '#ffcc33', support: '#58c26a', load: '#ff6b6b', none: '#59626b',
      nodeLabel: '#9cc4ee', elLabel: '#f0c27a', halo: 'rgba(20,24,29,0.85)'
    },
    light: {
      bg: '#f4f6f8', text: '#25303b', dim: '#6b7783', ghost: 'rgba(90,100,110,0.45)',
      beam: '#2f6fb0', truss: '#b5651d', shell: [120, 160, 195], edge: 'rgba(20,28,36,0.7)',
      node: '#1c242c', accent: '#d18a00', support: '#2f9e44', load: '#d63a3a', none: '#9aa5af',
      nodeLabel: '#1f5f9f', elLabel: '#9a5300', halo: 'rgba(244,246,248,0.9)'
    }
  };

  function colorFor(v, range) {
    if (v === null || v === undefined || !range) return null;
    return M.rainbow((v - range.min) / (range.max - range.min));
  }
  function mix3(c1, c2, c3) {
    return [(c1[0] + c2[0] + c3[0]) / 3, (c1[1] + c2[1] + c3[1]) / 3, (c1[2] + c2[2] + c3[2]) / 3];
  }
  function css(c) { return 'rgb(' + Math.round(c[0]) + ',' + Math.round(c[1]) + ',' + Math.round(c[2]) + ')'; }

  function drawArrow(ctx, x0, y0, x1, y1, head) {
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
    var a = Math.atan2(y1 - y0, x1 - x0);
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x1 - head * Math.cos(a - 0.45), y1 - head * Math.sin(a - 0.45));
    ctx.lineTo(x1 - head * Math.cos(a + 0.45), y1 - head * Math.sin(a + 0.45));
    ctx.closePath(); ctx.fill();
  }

  function fillTri(ctx, a, b, c, color, seam) {
    ctx.fillStyle = color;
    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(c[0], c[1]); ctx.closePath();
    ctx.fill();
    if (seam) { ctx.strokeStyle = color; ctx.lineWidth = 0.6; ctx.stroke(); } // hides anti-aliasing hairlines
  }

  // Subdivide triangle (A,B,C) with values (va,vb,vc) into n*n flat-coloured pieces.
  function contourTri(ctx, A, B, C, va, vb, vc, range, n) {
    if (n <= 1) {
      var col = colorFor((va + vb + vc) / 3, range);
      fillTri(ctx, A, B, C, css(col), true);
      return;
    }
    function P(i, j) { // barycentric lattice point: i steps toward B, j steps toward C
      var u = i / n, w = j / n, o = 1 - u - w;
      return [A[0] * o + B[0] * u + C[0] * w, A[1] * o + B[1] * u + C[1] * w];
    }
    function Vv(i, j) { var u = i / n, w = j / n; return va * (1 - u - w) + vb * u + vc * w; }
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n - i; j++) {
        var p00 = P(i, j), p10 = P(i + 1, j), p01 = P(i, j + 1);
        fillTri(ctx, p00, p10, p01, css(colorFor((Vv(i, j) + Vv(i + 1, j) + Vv(i, j + 1)) / 3, range)), true);
        if (i + j < n - 1) {
          var p11 = P(i + 1, j + 1);
          fillTri(ctx, p10, p11, p01, css(colorFor((Vv(i + 1, j) + Vv(i + 1, j + 1) + Vv(i, j + 1)) / 3, range)), true);
        }
      }
    }
  }

  // Draws the collected node / element numbers. A label is skipped when it would
  // overlap one already drawn, so a dense mesh shows a readable subset that fills
  // in as you zoom, instead of an unreadable smear. The selected item's label is
  // always drawn (and drawn first, so it wins). Overlap is tested on estimated
  // text boxes, bucketed on a coarse grid so thousands of labels stay cheap.
  function drawLabels(ctx, labels, T, W, H) {
    if (!labels.length) return 0;
    labels.sort(function (a, b) { return (b.sel ? 1 : 0) - (a.sel ? 1 : 0); });
    var GX = 48, GY = 20, grid = {}, drawn = 0;
    ctx.textBaseline = 'middle'; ctx.lineJoin = 'round'; ctx.lineWidth = 3;
    function box(l) {
      var w = l.t.length * 6.3 + 4, h = 12;
      var x0 = l.a === 'center' ? l.x - w / 2 : l.x;
      return [x0, l.y - h / 2, x0 + w, l.y + h / 2];
    }
    function cells(r, fn) {
      for (var gx = Math.floor(r[0] / GX); gx <= Math.floor(r[2] / GX); gx++)
        for (var gy = Math.floor(r[1] / GY); gy <= Math.floor(r[3] / GY); gy++) fn(gx + ',' + gy);
    }
    labels.forEach(function (l) {
      if (l.x < -20 || l.x > W + 20 || l.y < -10 || l.y > H + 10) return;
      var r = box(l), clash = false;
      if (!l.sel) {
        cells(r, function (k) {
          var list = grid[k];
          if (!list || clash) return;
          for (var i = 0; i < list.length; i++) {
            var o = list[i];
            if (r[0] < o[2] && r[2] > o[0] && r[1] < o[3] && r[3] > o[1]) { clash = true; return; }
          }
        });
        if (clash) return;
      }
      cells(r, function (k) { (grid[k] || (grid[k] = [])).push(r); });
      ctx.textAlign = l.a;
      ctx.font = (l.sel ? 'bold ' : '') + '10.5px sans-serif';
      ctx.strokeStyle = T.halo;
      ctx.strokeText(l.t, l.x, l.y);
      ctx.fillStyle = l.sel ? T.accent : (l.k === 'node' ? T.nodeLabel : T.elLabel);
      ctx.fillText(l.t, l.x, l.y);
      drawn++;
    });
    return drawn;
  }

  function legend(ctx, scene, theme, fmtVal, x, y, h, legendTitle) {
    if (!scene.range) return;
    var w = 14, steps = 48;
    for (var i = 0; i < steps; i++) {
      ctx.fillStyle = css(M.rainbow(1 - (i + 0.5) / steps));
      ctx.fillRect(x, y + (i * h) / steps, w, h / steps + 1);
    }
    ctx.strokeStyle = theme.dim; ctx.lineWidth = 1; ctx.strokeRect(x + 0.5, y + 0.5, w, h);
    ctx.fillStyle = theme.text; ctx.font = '11px sans-serif'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    for (var k = 0; k <= 4; k++) {
      var v = scene.range.max - (scene.range.max - scene.range.min) * k / 4;
      ctx.fillText(fmtVal(v), x + w + 6, y + (h * k) / 4);
    }
    ctx.textBaseline = 'bottom';
    ctx.fillText(legendTitle || scene.field.label, x, y - 6);
  }

  function gizmo(ctx, cam, theme, x, y, len) {
    var b = cam.basis();
    var axes = [[[1, 0, 0], '#e5484d', 'X'], [[0, 1, 0], '#3fb950', 'Y'], [[0, 0, 1], '#4c8dff', 'Z']];
    ctx.font = 'bold 11px sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    axes.forEach(function (a) {
      var sx = V.dot(a[0], b.r) * len, sy = -V.dot(a[0], b.u) * len;
      ctx.strokeStyle = a[1]; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + sx, y + sy); ctx.stroke();
      ctx.fillStyle = a[1]; ctx.fillText(a[2], x + sx * 1.22, y + sy * 1.22);
    });
  }

  /* opts: { theme:'dark'|'light', showGhost, showNodes, showNodeIds, showElementIds, showMesh,
   *         showSupports, showLoads, selectedEl, selectedNode, detail:'low'|'high',
   *         fmtVal(v) -> string, legend:true, width, height }                       */
  function draw(ctx, scene, cam, opts) {
    var T = THEMES[opts.theme] || THEMES.dark;
    var W = cam.width, H = cam.height;
    ctx.save();
    ctx.fillStyle = T.bg; ctx.fillRect(0, 0, W, H);
    var proj = cam.projector();
    var hits = [];
    var labels = []; // node / element numbers, drawn last so nothing covers them
    var P = {}; // projected node cache
    function node(id) { return P[id] || (P[id] = proj(scene.pos[id])); }
    var cb = cam.basis();
    var fv = opts.fmtVal || function (v) { return String(v); };
    var n = opts.detail === 'low' ? 1 : 4;
    var big = scene.groups.length;
    if (big > 4000) n = 1; else if (big > 1500) n = Math.min(n, 2);

    // undeformed outline underneath
    if (opts.showGhost && scene.scale !== 0) {
      ctx.strokeStyle = T.ghost; ctx.lineWidth = 1; ctx.setLineDash([4, 3]);
      scene.groups.forEach(function (g) {
        ctx.beginPath();
        if (g.kind === 'shell') {
          var r = g.ghostRing.map(proj);
          ctx.moveTo(r[0][0], r[0][1]);
          for (var i = 1; i < r.length; i++) ctx.lineTo(r[i][0], r[i][1]);
          ctx.closePath();
        } else {
          var a = proj(g.ghost[0]), b = proj(g.ghost[1]);
          ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
        }
        ctx.stroke();
      });
      ctx.setLineDash([]);
    }

    // depth-sort the elements, far first
    var order = scene.groups.map(function (g, i) {
      var c = g.kind === 'shell' ? g.center : V.mid(g.pts[0], g.pts[g.pts.length - 1]);
      var pc = proj(c);
      return { g: g, depth: pc[2] };
    }).sort(function (a, b) { return b.depth - a.depth; });

    var range = scene.range;
    var shellBase = T.shell;
    order.forEach(function (o) {
      var g = o.g, el = g.el;
      var sel = opts.selectedEl === el.id;
      if (g.kind === 'shell') {
        var ring = g.ring.map(proj), c2 = proj(g.center);
        var hasField = range && g.ringVals && g.centerVal !== null;
        if (hasField) {
          for (var i = 0; i < ring.length; i++) {
            var j = (i + 1) % ring.length;
            contourTri(ctx, c2, ring[i], ring[j], g.centerVal, g.ringVals[i], g.ringVals[j], range, n);
          }
        } else {
          // neutral face, lit by a headlight so folds and tilts read in 3D
          var nrm = V.normalize(V.cross(V.sub(g.ring[1], g.ring[0]), V.sub(g.ring[g.ring.length - 1], g.ring[0])));
          var lit = 0.5 + 0.5 * Math.abs(V.dot(nrm, cb.f));
          var col = css([shellBase[0] * lit, shellBase[1] * lit, shellBase[2] * lit]);
          ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(ring[0][0], ring[0][1]);
          for (var q = 1; q < ring.length; q++) ctx.lineTo(ring[q][0], ring[q][1]);
          ctx.closePath(); ctx.fill();
          if (range) { ctx.fillStyle = 'rgba(128,128,128,0.0)'; }
        }
        if (opts.showMesh !== false || sel) {
          ctx.strokeStyle = sel ? T.accent : T.edge; ctx.lineWidth = sel ? 2.5 : 0.8;
          ctx.beginPath(); ctx.moveTo(ring[0][0], ring[0][1]);
          for (var q2 = 1; q2 < ring.length; q2++) ctx.lineTo(ring[q2][0], ring[q2][1]);
          ctx.closePath(); ctx.stroke();
        }
        hits.push({ kind: 'shell', id: el.id, poly: ring, depth: o.depth });
        if (opts.showElementIds || sel && opts.labelSelected !== false)
          labels.push({ t: String(el.id), x: c2[0], y: c2[1], a: 'center', k: 'el', sel: sel });
      } else {
        var pp = g.pts.map(proj);
        var w = g.kind === 'beam' ? 5 : 3.5;
        if (sel) {
          ctx.strokeStyle = T.accent; ctx.globalAlpha = 0.55; ctx.lineWidth = w + 7; ctx.lineCap = 'round';
          ctx.beginPath(); ctx.moveTo(pp[0][0], pp[0][1]);
          for (var s0 = 1; s0 < pp.length; s0++) ctx.lineTo(pp[s0][0], pp[s0][1]);
          ctx.stroke(); ctx.globalAlpha = 1;
        }
        // dark outline, then the coloured core
        ctx.strokeStyle = T.edge; ctx.lineWidth = w + 2; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
        ctx.beginPath(); ctx.moveTo(pp[0][0], pp[0][1]);
        for (var s1 = 1; s1 < pp.length; s1++) ctx.lineTo(pp[s1][0], pp[s1][1]);
        ctx.stroke();
        ctx.lineWidth = w;
        if (range && g.vals && g.vals.every(function (x) { return x !== null; })) {
          for (var s = 0; s + 1 < pp.length; s++) {
            var ca = colorFor(g.vals[s], range), cb2 = colorFor(g.vals[s + 1], range);
            var grad = ctx.createLinearGradient(pp[s][0], pp[s][1], pp[s + 1][0], pp[s + 1][1]);
            grad.addColorStop(0, css(ca)); grad.addColorStop(1, css(cb2));
            ctx.strokeStyle = grad;
            ctx.beginPath(); ctx.moveTo(pp[s][0], pp[s][1]); ctx.lineTo(pp[s + 1][0], pp[s + 1][1]); ctx.stroke();
          }
        } else {
          ctx.strokeStyle = (range && opts.fadeUncoloured !== false) ? T.none : (g.kind === 'beam' ? T.beam : T.truss);
          ctx.beginPath(); ctx.moveTo(pp[0][0], pp[0][1]);
          for (var s2 = 1; s2 < pp.length; s2++) ctx.lineTo(pp[s2][0], pp[s2][1]);
          ctx.stroke();
        }
        hits.push({ kind: g.kind, id: el.id, line: pp, depth: o.depth });
        if (opts.showElementIds || sel && opts.labelSelected !== false) {
          // middle of the member: the middle vertex of a curved beam, or halfway along a straight one
          var mid = pp.length % 2 === 1 ? pp[(pp.length - 1) / 2]
            : [(pp[pp.length / 2 - 1][0] + pp[pp.length / 2][0]) / 2, (pp[pp.length / 2 - 1][1] + pp[pp.length / 2][1]) / 2];
          labels.push({ t: String(el.id), x: mid[0], y: mid[1] - 9, a: 'center', k: 'el', sel: sel });
        }
      }
    });

    // supports
    if (opts.showSupports) {
      ctx.lineWidth = 1.5;
      Object.keys(scene.supports).forEach(function (id) {
        if (!scene.pos[id]) return;
        var p = node(id), d = scene.supports[id];
        var nt = (d.x ? 1 : 0) + (d.y ? 1 : 0) + (d.z ? 1 : 0), nr = (d.rx ? 1 : 0) + (d.ry ? 1 : 0) + (d.rz ? 1 : 0);
        ctx.fillStyle = T.support; ctx.strokeStyle = T.edge;
        ctx.beginPath();
        if (nt === 3) { // fixed or pinned: triangle below the node; boxed if rotations are fixed too
          ctx.moveTo(p[0], p[1] + 1); ctx.lineTo(p[0] - 8, p[1] + 14); ctx.lineTo(p[0] + 8, p[1] + 14); ctx.closePath();
          ctx.fill(); ctx.stroke();
          if (nr === 3) { ctx.fillRect(p[0] - 10, p[1] + 14, 20, 3); }
        } else if (nt > 0 || nr > 0) { // partial restraint: diamond
          ctx.moveTo(p[0], p[1] + 2); ctx.lineTo(p[0] + 6, p[1] + 8); ctx.lineTo(p[0], p[1] + 14); ctx.lineTo(p[0] - 6, p[1] + 8);
          ctx.closePath(); ctx.fill(); ctx.stroke();
        }
      });
    }

    // applied forces (and a ring glyph for moments)
    if (opts.showLoads) {
      var maxF = 0;
      Object.keys(scene.loads).forEach(function (id) { maxF = Math.max(maxF, V.norm(scene.loads[id].f)); });
      ctx.strokeStyle = T.load; ctx.fillStyle = T.load; ctx.lineWidth = 2;
      Object.keys(scene.loads).forEach(function (id) {
        if (!scene.pos[id]) return;
        var l = scene.loads[id], f = V.norm(l.f), p = node(id);
        if (f > 0 && maxF > 0) {
          var dir = V.mul(l.f, 1 / f);
          var Lw = 0.14 * scene.modelSize * (0.35 + 0.65 * f / maxF);
          var tail = proj(V.sub(scene.pos[id], V.mul(dir, Lw)));
          drawArrow(ctx, tail[0], tail[1], p[0], p[1], 8);
        }
        if (V.norm(l.m) > 0) {
          ctx.beginPath(); ctx.arc(p[0], p[1], 11, 0.4, 5.4); ctx.stroke();
          var ax = p[0] + 11 * Math.cos(5.4), ay = p[1] + 11 * Math.sin(5.4);
          drawArrow(ctx, ax - 3, ay + 1, ax, ay, 6);
        }
      });
    }

    // nodes
    if (opts.showNodes || opts.showNodeIds || opts.selectedNode) {
      Object.keys(scene.pos).forEach(function (id) {
        var p = node(id), sel = opts.selectedNode === Number(id);
        if (!opts.showNodes && !opts.showNodeIds && !sel) return;
        if (p[0] < -10 || p[0] > W + 10 || p[1] < -10 || p[1] > H + 10) return;
        ctx.fillStyle = sel ? T.accent : T.node;
        ctx.strokeStyle = T.edge; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.arc(p[0], p[1], sel ? 5.5 : 3, 0, 6.2832); ctx.fill(); ctx.stroke();
        if (opts.showNodeIds || sel) labels.push({ t: id, x: p[0] + 6, y: p[1] - 7, a: 'left', k: 'node', sel: sel });
      });
    }
    drawLabels(ctx, labels, T, W, H);
    // node hit targets (always present so nodes can be picked even when hidden)
    var nodeHits = Object.keys(scene.pos).map(function (id) { var p = node(id); return { id: Number(id), x: p[0], y: p[1], depth: p[2] }; });

    if (opts.legend !== false) legend(ctx, scene, T, fv, 16, 44, Math.min(180, H - 120), opts.legendTitle);
    gizmo(ctx, cam, T, 40, H - 40, 26);
    ctx.restore();
    return { elements: hits, nodes: nodeHits };
  }

  function inPoly(pt, poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      var xi = poly[i][0], yi = poly[i][1], xj = poly[j][0], yj = poly[j][1];
      if (((yi > pt[1]) !== (yj > pt[1])) && (pt[0] < (xj - xi) * (pt[1] - yi) / (yj - yi) + xi)) inside = !inside;
    }
    return inside;
  }
  function distSeg(p, a, b) {
    var dx = b[0] - a[0], dy = b[1] - a[1], l2 = dx * dx + dy * dy;
    var t = l2 > 0 ? ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2 : 0;
    t = Math.max(0, Math.min(1, t));
    var qx = a[0] + t * dx, qy = a[1] + t * dy;
    return Math.sqrt((p[0] - qx) * (p[0] - qx) + (p[1] - qy) * (p[1] - qy));
  }

  /* Returns {type:'node'|'element', id} or null. Nodes win when the pointer is
   * within nodeTol pixels; otherwise the nearest element under the pointer, with
   * thin members favoured over a shell lying behind them. */
  function pick(hitList, x, y, nodeTol, lineTol, bias) {
    var pt = [x, y], best = null, bestD = Infinity;
    var nt = nodeTol === undefined ? 8 : nodeTol, lt = lineTol === undefined ? 7 : lineTol;
    hitList.nodes.forEach(function (n) {
      var d = Math.sqrt((n.x - x) * (n.x - x) + (n.y - y) * (n.y - y));
      if (d <= nt && d < bestD) { bestD = d; best = { type: 'node', id: n.id }; }
    });
    if (best) return best;
    var bestDepth = Infinity;
    hitList.elements.forEach(function (h) {
      var ok = false, depth = h.depth;
      if (h.poly) ok = inPoly(pt, h.poly);
      else {
        for (var i = 0; i + 1 < h.line.length && !ok; i++) ok = distSeg(pt, h.line[i], h.line[i + 1]) <= lt;
        if (ok) depth -= (bias || 0);
      }
      if (ok && depth < bestDepth) { bestDepth = depth; best = { type: 'element', id: h.id }; }
    });
    return best;
  }

  return { draw: draw, pick: pick, THEMES: THEMES };
}));
