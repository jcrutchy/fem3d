/* femmath.js -- small vector maths, the orbit camera, the colour map and number
 * formatting. No DOM; works in a browser and in node. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.FemMath = factory();
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /* --------------------------------------------------------------- vectors */
  var V = {
    add: function (a, b) { return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]; },
    sub: function (a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; },
    mul: function (a, s) { return [a[0] * s, a[1] * s, a[2] * s]; },
    dot: function (a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; },
    cross: function (a, b) {
      return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    },
    norm: function (a) { return Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]); },
    normalize: function (a) {
      var n = V.norm(a);
      return n > 0 ? [a[0] / n, a[1] / n, a[2] / n] : [0, 0, 0];
    },
    lerp: function (a, b, t) {
      return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
    },
    mid: function (a, b) { return V.lerp(a, b, 0.5); }
  };

  /* ---------------------------------------------------------------- camera */
  // Z-up orbit camera. yaw turns about +Z, pitch lifts the eye above the XY plane.
  function Camera() {
    this.target = [0, 0, 0];
    this.dist = 10;
    this.yaw = -Math.PI / 4;       // looking from -Y,-X toward +X,+Y ... a standard isometric corner
    this.pitch = Math.PI / 6;
    this.fov = 35 * Math.PI / 180; // vertical field of view
    this.ortho = false;
    this.width = 800;
    this.height = 600;
    this.panX = 0; this.panY = 0;  // screen-space offset in pixels
  }

  Camera.prototype.eye = function () {
    var cp = Math.cos(this.pitch);
    return [
      this.target[0] + this.dist * cp * Math.cos(this.yaw),
      this.target[1] + this.dist * cp * Math.sin(this.yaw),
      this.target[2] + this.dist * Math.sin(this.pitch)
    ];
  };

  // right / up / forward unit vectors (forward points from the eye to the target)
  Camera.prototype.basis = function () {
    var e = this.eye();
    var f = V.normalize(V.sub(this.target, e));
    var r = V.normalize(V.cross(f, [0, 0, 1]));
    if (V.norm(r) === 0) r = [1, 0, 0];
    var u = V.cross(r, f);
    return { eye: e, f: f, r: r, u: u };
  };

  // Prepare a projector once per frame; returns function(p) -> [sx, sy, depth].
  Camera.prototype.projector = function () {
    var b = this.basis();
    var w = this.width, h = this.height;
    var t = Math.tan(this.fov / 2);
    var focal = (h / 2) / t;
    var orthoScale = (h / 2) / (this.dist * t);
    var ortho = this.ortho, px = this.panX, py = this.panY;
    return function (p) {
      var rx = p[0] - b.eye[0], ry = p[1] - b.eye[1], rz = p[2] - b.eye[2];
      var x = rx * b.r[0] + ry * b.r[1] + rz * b.r[2];
      var y = rx * b.u[0] + ry * b.u[1] + rz * b.u[2];
      var z = rx * b.f[0] + ry * b.f[1] + rz * b.f[2];
      var s = ortho ? orthoScale : (z > 1e-9 ? focal / z : focal * 1e9);
      return [w / 2 + px + x * s, h / 2 + py - y * s, z];
    };
  };

  // world units per screen pixel at the target distance
  Camera.prototype.unitsPerPixel = function () {
    return (2 * this.dist * Math.tan(this.fov / 2)) / this.height;
  };

  Camera.prototype.orbit = function (dxPixels, dyPixels) {
    this.yaw -= dxPixels * 0.008;
    this.pitch += dyPixels * 0.008;
    var lim = Math.PI / 2 - 0.01;
    if (this.pitch > lim) this.pitch = lim;
    if (this.pitch < -lim) this.pitch = -lim;
  };

  Camera.prototype.pan = function (dxPixels, dyPixels) {
    this.panX += dxPixels; this.panY += dyPixels;
  };

  Camera.prototype.zoom = function (wheelDelta, anchorX, anchorY) {
    var k = Math.exp(wheelDelta * 0.0015);
    var newDist = Math.min(Math.max(this.dist * k, this.minDist || 1e-6), this.maxDist || 1e12);
    // keep the point under the cursor fixed on screen (the pan absorbs the shift)
    if (anchorX !== undefined) {
      var cx = this.width / 2 + this.panX, cy = this.height / 2 + this.panY;
      var ratio = this.dist / newDist; // > 1 when zooming in
      if (this.ortho || true) {
        this.panX = anchorX - (anchorX - cx) * ratio - this.width / 2;
        this.panY = anchorY - (anchorY - cy) * ratio - this.height / 2;
      }
    }
    this.dist = newDist;
  };

  // Frame a bounding sphere.
  Camera.prototype.fit = function (center, radius) {
    this.target = center.slice();
    this.panX = 0; this.panY = 0;
    var r = Math.max(radius, 1e-9);
    this.dist = r / Math.sin(this.fov / 2) * 1.15;
    this.minDist = r * 0.01; this.maxDist = r * 100;
  };

  Camera.prototype.setView = function (name) {
    var P = Math.PI;
    switch (name) {
      case 'top':   this.yaw = -P / 2; this.pitch = P / 2 - 0.0101; break; // looking down -Z, +Y up the screen
      case 'front': this.yaw = -P / 2; this.pitch = 0; break;              // looking along +Y, Z up
      case 'side':  this.yaw = 0;      this.pitch = 0; break;              // looking along -X, Z up
      default:      this.yaw = -P / 4 - P / 2; this.pitch = P / 6;         // iso
    }
    this.panX = 0; this.panY = 0;
  };

  /* ------------------------------------------------------------ colour map */
  // Classic blue -> cyan -> green -> yellow -> red contour ramp. t in [0,1].
  function rainbow(t) {
    if (!(t >= 0)) t = 0; if (t > 1) t = 1;
    var h = (1 - t) * 240;              // 240 (blue) .. 0 (red)
    var s = 0.9, v = 0.95;
    var c = v * s, hp = h / 60, x = c * (1 - Math.abs(hp % 2 - 1));
    var r = 0, g = 0, b = 0;
    if (hp < 1) { r = c; g = x; } else if (hp < 2) { r = x; g = c; }
    else if (hp < 3) { g = c; b = x; } else if (hp < 4) { g = x; b = c; }
    else { r = x; b = c; }
    var m = v - c;
    return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
  }
  function rgbCss(c) { return 'rgb(' + c[0] + ',' + c[1] + ',' + c[2] + ')'; }

  /* ------------------------------------------------------------ formatting */
  // Compact number: 6 significant digits at most, no trailing zeros, E-notation
  // for very large or small magnitudes. zeroBelow snaps round-off noise to 0.
  function fmt(v, digits, zeroBelow) {
    if (v === null || v === undefined || isNaN(v)) return '–';
    if (!isFinite(v)) return v > 0 ? '∞' : '-∞';
    if (zeroBelow !== undefined && Math.abs(v) <= zeroBelow) return '0';
    if (v === 0) return '0';
    var d = digits || 4;
    var a = Math.abs(v);
    if (a >= 1e5 || a < 1e-3) {
      var e = v.toExponential(d - 1).replace(/\.?0+e/, 'e');
      return e.replace('e+', 'E').replace('e-', 'E-');
    }
    var s = v.toPrecision(d);
    if (s.indexOf('e') >= 0) return Number(s).toString();
    if (s.indexOf('.') >= 0) s = s.replace(/\.?0+$/, '');
    return s;
  }

  // Round tick step: 1, 2 or 5 times a power of ten.
  function niceStep(span, targetTicks) {
    var raw = span / Math.max(targetTicks, 1);
    var p = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10));
    var f = raw / p;
    var n = f < 1.5 ? 1 : (f < 3.5 ? 2 : (f < 7.5 ? 5 : 10));
    return n * p;
  }

  return { V: V, Camera: Camera, rainbow: rainbow, rgbCss: rgbCss, fmt: fmt, niceStep: niceStep };
}));
