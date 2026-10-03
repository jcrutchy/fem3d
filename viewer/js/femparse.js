/* femparse.js -- readers for the FEM suite's text formats.
 *
 *   parseModel(text)    the native model format (.fem)
 *   parseResults(text)  a solver's stdout: key=value lines (DISP.*, REACT.*, ELEM.*)
 *
 * Plain functions, no DOM: usable in a browser (<script>) and in node (require).
 * Nothing here knows how anything is drawn. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.FemParse = factory();
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var DOF_NAMES = ['x', 'y', 'z', 'rx', 'ry', 'rz'];

  function splitFields(line) {
    return line.split(',').map(function (s) { return s.trim(); });
  }
  function num(s) {
    if (s === undefined || s === '' || s === '-') return null;
    var v = Number(s);
    return isNaN(v) ? null : v;
  }

  /* ---------------------------------------------------------------- model */
  function parseModel(text) {
    var m = {
      header: {}, nodes: [], nodeById: {}, materials: {}, properties: {},
      elements: [], elementById: {}, freedomCases: {}, loadCases: {},
      combinations: {}, solverParams: {}, warnings: []
    };
    var section = '', name = '';
    var lines = text.split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var raw = lines[i].trim();
      if (raw === '' || raw.charAt(0) === '#') continue;
      var hm = /^\[\s*([A-Za-z]+)\s*(.*?)\s*\]$/.exec(raw);
      if (hm) {
        section = hm[1].toUpperCase(); name = hm[2];
        if (section === 'FREEDOMCASE') m.freedomCases[name] = [];
        else if (section === 'LOADCASE') m.loadCases[name] = [];
        else if (section === 'COMBINATION') m.combinations[name] = [];
        continue;
      }
      var f, v;
      switch (section) {
        case 'HEADER':
        case 'SOLVERPARAMS': {
          var eq = raw.indexOf('=');
          if (eq > 0) {
            var k = raw.substring(0, eq).trim(), val = raw.substring(eq + 1).trim();
            (section === 'HEADER' ? m.header : m.solverParams)[k] = val;
          }
          break;
        }
        case 'NODES': {
          f = splitFields(raw);
          var nd = { id: parseInt(f[0], 10), x: num(f[1]), y: num(f[2]), z: num(f[3]) };
          if (nd.x === null || nd.y === null || nd.z === null) { m.warnings.push('line ' + (i + 1) + ': bad node'); break; }
          m.nodes.push(nd); m.nodeById[nd.id] = nd;
          break;
        }
        case 'MATERIALS': {
          f = splitFields(raw);
          m.materials[parseInt(f[0], 10)] = { id: parseInt(f[0], 10), E: num(f[1]), nu: num(f[2]), rho: num(f[3]) };
          break;
        }
        case 'PROPERTIES': {
          f = splitFields(raw);
          var p = { id: parseInt(f[0], 10), type: f[1], mat: parseInt(f[2], 10) };
          if (p.type === 'shellq4' || p.type === 'shellq8') {
            p.thickness = num(f[3]);
          } else {
            p.area = num(f[3]); p.Iy = num(f[4]); p.Iz = num(f[5]); p.J = num(f[6]);
            p.Cy = num(f[7]) || 0; p.Cz = num(f[8]) || 0; p.Rt = num(f[9]) || 0;
          }
          m.properties[p.id] = p;
          break;
        }
        case 'ELEMENTS': {
          f = splitFields(raw);
          var el = { id: parseInt(f[0], 10), type: f[1], nodes: [], prop: 0, ref: null };
          var nn = el.type === 'shellq8' ? 8 : (el.type === 'shellq4' ? 4 : 2);
          for (var j = 0; j < nn; j++) el.nodes.push(parseInt(f[2 + j], 10));
          el.prop = parseInt(f[2 + nn], 10);
          if (f.length >= 3 + nn + 3) el.ref = [num(f[3 + nn]), num(f[4 + nn]), num(f[5 + nn])];
          m.elements.push(el); m.elementById[el.id] = el;
          break;
        }
        case 'FREEDOMCASE':
        case 'LOADCASE': {
          f = splitFields(raw);
          v = num(f[2]);
          if (DOF_NAMES.indexOf(f[1]) < 0 || v === null) { m.warnings.push('line ' + (i + 1) + ': bad dof entry'); break; }
          (section === 'FREEDOMCASE' ? m.freedomCases : m.loadCases)[name].push(
            { node: parseInt(f[0], 10), dof: f[1], value: v });
          break;
        }
        case 'COMBINATION': {
          var tm = /^Terms\s*=\s*(.*)$/i.exec(raw);
          if (tm) tm[1].split(',').forEach(function (t) {
            var pr = t.split(':');
            if (pr.length === 2) m.combinations[name].push({ lc: pr[0].trim(), factor: Number(pr[1]) });
          });
          break;
        }
        default: break;
      }
    }
    return m;
  }

  /* -------------------------------------------------------------- results */
  // One case's results: disp[nodeId][dof], react[nodeId][dof], and elem[elementId],
  // which starts as raw "tail -> value" pairs ("S2.MZ" -> 1500) and is turned into
  // a typed record by finishElement().
  function emptyCase(prefix) {
    return { prefix: prefix, label: prefix === '' ? 'default' : prefix.replace(/\.$/, ''), disp: {}, react: {}, elem: {} };
  }

  function finishElement(raw) {
    var out = { kind: null, axes: null };
    var keys = Object.keys(raw);
    var hasStation = false, hasLoc = false;
    for (var i = 0; i < keys.length; i++) {
      if (/^S\d+\./.test(keys[i])) hasStation = true;
      else if (/^(C|N\d)\./.test(keys[i])) hasLoc = true;
    }
    if (raw['EX.X'] !== undefined) {
      out.axes = { ex: [raw['EX.X'], raw['EX.Y'], raw['EX.Z']],
                   ey: [raw['EY.X'], raw['EY.Y'], raw['EY.Z']],
                   ez: [raw['EZ.X'], raw['EZ.Y'], raw['EZ.Z']] };
    }
    if (hasStation) {
      out.kind = 'beam'; out.stations = [];
      keys.forEach(function (k) {
        var mm = /^S(\d+)\.(.+)$/.exec(k);
        if (!mm) return;
        var idx = parseInt(mm[1], 10);
        if (!out.stations[idx]) out.stations[idx] = {};
        out.stations[idx][mm[2]] = raw[k];
      });
    } else if (hasLoc) {
      out.kind = 'shell'; out.loc = {};
      keys.forEach(function (k) {
        var mm = /^(C|N\d)\.(.+)$/.exec(k);
        if (!mm) return;
        var o = out.loc[mm[1]] || (out.loc[mm[1]] = { top: {}, bot: {} });
        var sub = /^(TOP|BOT)\.(.+)$/.exec(mm[2]);
        if (sub) o[sub[1] === 'TOP' ? 'top' : 'bot'][sub[2]] = raw[k];
        else o[mm[2]] = raw[k];
      });
    } else if (raw.N !== undefined) {
      out.kind = 'truss'; out.N = raw.N; out.sigma = raw.SIGMA; out.vm = raw.VM; out.tresca = raw.TRESCA;
    }
    return out;
  }

  function parseResults(text) {
    var cases = {}, order = [], fingerprint = null;
    var lines = text.split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
      var ln = lines[i];
      if (ln === '' || ln.charAt(0) === '#') continue;
      var eq = ln.indexOf('=');
      if (eq < 0) continue;
      var key = ln.substring(0, eq), val = Number(ln.substring(eq + 1));
      if (key === 'MODEL.FINGERPRINT') {   // the one non-numeric value: ties the results to their model
        var fp = ln.substring(eq + 1).trim().toLowerCase();
        if (/^[0-9a-f]{64}$/.test(fp)) fingerprint = fp;
        continue;
      }
      // "<prefix>.<KIND>.<rest>" -- the prefix may itself contain dots
      var m = /^(?:(.*?)\.)?(DISP|REACT|ELEM)\.(.+)$/.exec(key);
      if (!m) continue;
      var prefix = m[1] === undefined ? '' : m[1] + '.';
      var kind = m[2], rest = m[3];
      var c = cases[prefix];
      if (!c) { c = cases[prefix] = emptyCase(prefix); order.push(prefix); }
      if (kind === 'DISP' || kind === 'REACT') {
        var dm = /^(\d+)\.(x|y|z|rx|ry|rz)$/.exec(rest);
        if (!dm) continue;
        var tbl = kind === 'DISP' ? c.disp : c.react;
        var id = parseInt(dm[1], 10);
        (tbl[id] || (tbl[id] = {}))[dm[2]] = val;
      } else {
        var em = /^(\d+)\.(.+)$/.exec(rest);
        if (!em) continue;
        var eid = parseInt(em[1], 10);
        (c.elem[eid] || (c.elem[eid] = {}))[em[2]] = val;
      }
    }
    order.forEach(function (p) {
      var c = cases[p];
      Object.keys(c.elem).forEach(function (eid) { c.elem[eid] = finishElement(c.elem[eid]); });
    });
    return { cases: cases, order: order, fingerprint: fingerprint };
  }

  /* Which of the two a pasted/dropped file is. */
  function sniff(text) {
    if (/^\s*\[(HEADER|NODES)\]/m.test(text)) return 'model';
    if (/^(?:[^#\s=][^=]*\.)?(DISP|REACT|ELEM)\.\d+\.[^=]+=/m.test(text)) return 'results';
    return 'unknown';
  }

  return { parseModel: parseModel, parseResults: parseResults, sniff: sniff, DOF_NAMES: DOF_NAMES };
}));
