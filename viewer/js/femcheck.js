/* femcheck.js -- are these results actually for this model?
 *
 * The viewer only displays what is in a model file and a solver's output, so the
 * one thing it must never do is draw results computed from a different version
 * of the model (someone edits a load or a node and forgets to re-run the solver).
 * Two independent checks:
 *
 *   1. FINGERPRINT. The solver prints MODEL.FINGERPRINT=<sha256 of the canonical
 *      model text>; we recompute it from the model file we were given. Equal =
 *      the results were computed from exactly this model (ignoring comments,
 *      blank lines, indentation and line endings -- see femhash.js).
 *   2. STRUCTURE. Whatever the fingerprint says, the results must refer to nodes
 *      and elements the model has (and only those), with the right kind of result
 *      for each element type. This catches results from older solver builds that
 *      have no fingerprint, and a results file pasted against the wrong model.
 *
 * verify() returns status 'match' | 'unverified' | 'mismatch' | 'incompatible'.
 * The UI shows results only for 'match' and 'unverified'. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./femhash.js'), require('./femscene.js'));
  else root.FemCheck = factory(root.FemHash, root.FemScene);
}(typeof self !== 'undefined' ? self : this, function (Hash, Scene) {
  'use strict';

  var KIND_OF_TYPE = { truss: 'truss', beam: 'beam', shellq4: 'shell', shellq8: 'shell' };

  function structuralProblems(model, results) {
    var problems = [];
    function add(msg) { if (problems.length < 8) problems.push(msg); }
    var nodeIds = {}, elIds = {};
    model.nodes.forEach(function (n) { nodeIds[n.id] = true; });
    model.elements.forEach(function (e) { elIds[e.id] = true; });

    results.order.forEach(function (prefix) {
      var c = results.cases[prefix];

      // does this case exist in the model?
      var inp = Scene.caseInputs(model, prefix);
      var lcName = inp.loadCase;
      if (lcName !== null && !model.loadCases[lcName] && !model.combinations[lcName])
        add('Results case "' + c.label + '" names a load case or combination that is not in the model.');
      if (/^FC_/.test(prefix) && !model.freedomCases[inp.freedomCase])
        add('Results case "' + c.label + '" names freedom case "' + inp.freedomCase + '", which is not in the model.');

      var dispIds = Object.keys(c.disp);
      dispIds.forEach(function (id) { if (!nodeIds[id]) add('Case "' + c.label + '": results for node ' + id + ', which the model does not have.'); });
      model.nodes.forEach(function (n) { if (!c.disp[n.id]) add('Case "' + c.label + '": the model has node ' + n.id + ' but the results do not.'); });

      var elKeys = Object.keys(c.elem);
      if (elKeys.length) {
        elKeys.forEach(function (id) {
          if (!elIds[id]) add('Case "' + c.label + '": results for element ' + id + ', which the model does not have.');
        });
        model.elements.forEach(function (e) {
          var want = KIND_OF_TYPE[e.type];
          if (!want) return;
          var r = c.elem[e.id];
          if (!r) add('Case "' + c.label + '": the model has element ' + e.id + ' but the results do not.');
          else if (r.kind !== want) add('Case "' + c.label + '": element ' + e.id + ' is a ' + e.type + ' in the model but its results are of a ' + (r.kind || 'unknown') + '.');
        });
        // station / divisions sanity: BeamDivisions in the model should match
        var bd = parseInt(model.solverParams.BeamDivisions || '4', 10);
        model.elements.forEach(function (e) {
          var r = c.elem[e.id];
          if (e.type === 'beam' && r && r.kind === 'beam' && r.stations.length !== bd + 1)
            add('Case "' + c.label + '": beam ' + e.id + ' has ' + r.stations.length + ' result stations but the model says BeamDivisions=' + bd + '.');
        });
      }
    });
    return problems;
  }

  /* modelBytes: Uint8Array | ArrayBuffer | string -- the model file exactly as loaded. */
  function verify(model, modelBytes, results) {
    var out = { status: 'unverified', modelFingerprint: null, resultsFingerprint: results.fingerprint || null, problems: [] };
    if (modelBytes !== undefined && modelBytes !== null) out.modelFingerprint = Hash.fingerprint(modelBytes);
    out.problems = structuralProblems(model, results);

    if (out.resultsFingerprint && out.modelFingerprint) {
      if (out.resultsFingerprint !== out.modelFingerprint) {
        out.status = 'mismatch';
        out.problems.unshift('These results were computed from a different version of the model (fingerprint ' +
          out.resultsFingerprint.slice(0, 12) + '\u2026 vs the model file\'s ' + out.modelFingerprint.slice(0, 12) +
          '\u2026). The model has changed since the solver was run \u2014 run the solver again.');
      } else {
        out.status = out.problems.length ? 'incompatible' : 'match';
      }
    } else {
      out.status = out.problems.length ? 'incompatible' : 'unverified';
    }
    return out;
  }

  return { verify: verify, structuralProblems: structuralProblems };
}));
