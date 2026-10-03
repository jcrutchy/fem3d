/* femhash.js -- SHA-256 and the model fingerprint, in plain JavaScript.
 *
 * Why not crypto.subtle? It only exists in "secure contexts" (https or
 * localhost); a page served to another machine over plain http -- e.g. by a
 * LAN-side vdrx -- would silently lose the integrity check. A 60-line pure
 * implementation works everywhere, with no dependencies, and is checked against
 * the same test vectors and against the solvers' own output.
 *
 * fingerprint() implements exactly the rule in src/common/fem_fingerprint.pas:
 *   drop a leading UTF-8 BOM; split into lines at LF, CR LF or lone CR; trim
 *   spaces and tabs from both ends of every line; drop lines that are then
 *   empty or begin with '#'; write each remaining line followed by one LF;
 *   SHA-256 of those bytes, as lowercase hex. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.FemHash = factory();
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  function rotr(x, n) { return (x >>> n) | (x << (32 - n)); }

  /* bytes: Uint8Array (or array of 0..255). Returns a 64-char lowercase hex string. */
  function sha256(bytes) {
    var n = bytes.length;
    var padded = new Uint8Array(((n + 9 + 63) >> 6) << 6);
    padded.set(bytes);
    padded[n] = 0x80;
    var bitsHi = Math.floor(n / 0x20000000), bitsLo = (n << 3) >>> 0;
    var L = padded.length;
    padded[L - 8] = bitsHi >>> 24; padded[L - 7] = bitsHi >>> 16; padded[L - 6] = bitsHi >>> 8; padded[L - 5] = bitsHi;
    padded[L - 4] = bitsLo >>> 24; padded[L - 3] = bitsLo >>> 16; padded[L - 2] = bitsLo >>> 8; padded[L - 1] = bitsLo;

    var H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    var w = new Int32Array(64);
    for (var off = 0; off < L; off += 64) {
      for (var i = 0; i < 16; i++) {
        var j = off + i * 4;
        w[i] = (padded[j] << 24) | (padded[j + 1] << 16) | (padded[j + 2] << 8) | padded[j + 3];
      }
      for (i = 16; i < 64; i++) {
        var s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        var s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }
      var a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
      for (i = 0; i < 64; i++) {
        var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        var ch = (e & f) ^ (~e & g);
        var t1 = (h + S1 + ch + K[i] + w[i]) | 0;
        var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var t2 = (S0 + maj) | 0;
        h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
      }
      H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + c) | 0; H[3] = (H[3] + d) | 0;
      H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
    }
    var hex = '';
    for (i = 0; i < 8; i++) hex += ('00000000' + (H[i] >>> 0).toString(16)).slice(-8);
    return hex;
  }

  /* The canonical form (see the header comment). raw: Uint8Array. */
  function canonicalBytes(raw) {
    var N = raw.length, out = new Uint8Array(N + 1), outLen = 0;
    var start = (N >= 3 && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF) ? 3 : 0;
    function emit(s, e) {
      while (s < e && (raw[s] === 32 || raw[s] === 9)) s++;
      while (e > s && (raw[e - 1] === 32 || raw[e - 1] === 9)) e--;
      if (e === s || raw[s] === 35) return;           // empty, or a '#' comment
      for (var k = s; k < e; k++) out[outLen++] = raw[k];
      out[outLen++] = 10;
    }
    var lineStart = start;
    for (var i = start; i < N; i++) {
      if (raw[i] === 10 || raw[i] === 13) {
        emit(lineStart, i);
        if (raw[i] === 13 && i + 1 < N && raw[i + 1] === 10) i++;
        lineStart = i + 1;
      }
    }
    if (lineStart < N) emit(lineStart, N);
    return out.subarray(0, outLen);
  }

  function toBytes(x) {
    if (typeof x === 'string') {
      if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(x);
      var utf8 = unescape(encodeURIComponent(x)), u = new Uint8Array(utf8.length);
      for (var i = 0; i < utf8.length; i++) u[i] = utf8.charCodeAt(i);
      return u;
    }
    return x instanceof Uint8Array ? x : new Uint8Array(x);
  }

  /* fingerprint(string | Uint8Array | ArrayBuffer) -> hex */
  function fingerprint(x) {
    return sha256(canonicalBytes(x instanceof ArrayBuffer ? new Uint8Array(x) : toBytes(x)));
  }

  return { sha256: sha256, canonicalBytes: canonicalBytes, fingerprint: fingerprint, toBytes: toBytes };
}));
