## Palms (feather and fan) and the Joshua tree.

import std/[math, random]
import core/vec
import treecore, treegrow, conifers

proc bezier(a, c, b: Vec3, t: float): Vec3 = a * sq(1 - t) + c * (2 * t * (1 - t)) + b * sq(t)

proc palmTrunk(t: var Tree, a, c, b: Vec3, r0, r1: float, tex = txRings, amp = 0.5): seq[Vec3] =
  ## A ringed trunk along a curve, swelling a little at the foot.
  let n = 60
  for i in 0 .. n: result.add bezier(a, c, b, float(i) / float(n))
  var acc = 0.0
  for i in 1 .. n:
    let ta = float(i - 1) / float(n); let tb = float(i) / float(n)
    let ra = r1 + (r0 - r1) * (1 - ta) + r0 * 0.5 * exp(-ta * 14)
    let rb = r1 + (r0 - r1) * (1 - tb) + r0 * 0.5 * exp(-tb * 14)
    t.tube(result[i - 1], result[i], ra, rb, tex, amp, acc, 0.75, 2)
    acc += dist(result[i - 1], result[i])

proc frond(t: var Tree, rng: var Rand, top: Vec3, az, el, len, leaflet: float, sag = 0.045, hang = 0.65,
           stiff = 0.0, dead = false) =
  ## A feather palm frond: an arching midrib with leaflets down both sides, hanging in a V.
  var dir = vec3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
  var p = top
  var pts = @[p]
  let step = 2.0
  var acc = 0.0
  while acc < len:
    dir = (dir + vec3(0, -sag * step * (1 - stiff), 0)).normalized
    p += dir * step
    acc += step
    pts.add p
  t.polyTube(pts, 1.5, 0.35, txNone, 0, 0.7)
  var i = 1
  var along = 0.0
  while i < pts.len:
    along += dist(pts[i], pts[i - 1])
    let tt = along / len
    if tt > 0.12:
      let d = (pts[i] - pts[i - 1]).normalized
      var side = cross(d, vec3(0, 1, 0))
      side = if side.len > 1e-6: side.normalized else: vec3(1, 0, 0)
      let ll = leaflet * pow(max(0.0, sin(PI * (tt * 0.88 + 0.06))), 0.6) * rng.rnd(0.85, 1.1)
      for sgn in [-1.0, 1.0]:
        var ld = (side * sgn + d * 0.45 + vec3(0, -hang, 0)).normalized
        if dead: ld = (ld + vec3(0, -1.5, 0)).normalized
        let mid = pts[i] + ld * ll * 0.5 + vec3(0, -ll * 0.08, 0)
        let tip = pts[i] + ld * ll + vec3(0, -ll * 0.22 * (1 - stiff), 0)
        t.polyTube(@[pts[i], mid, tip], 1.05, 0.15, txNone, 0, 0.55, sharp = 0.6)
    i += 1
    if i < pts.len and dist(pts[i], pts[i - 1]) < 1.9: i += 0

proc coconutPalm*(seed: int, bend = 0.0, height = 175.0, fronds = 17, nuts = true): Tree =
  var rng = initRand(seed)
  var t: Tree
  t.base = 0.8; t.depthTo = 7
  let top = vec3(bend, height - 22, 0)
  let ctrl = vec3(bend * 0.05, height * 0.45, 0)
  discard t.palmTrunk(vec3(0, -2, 0), ctrl, top, 5.2, 3.6)
  for k in 0 ..< fronds:
    let az = float(k) / float(fronds) * 2 * PI + rng.rnd(-0.25, 0.25)
    let el = rng.rnd(-0.15, 1.15)
    t.frond(rng, top + vec3(0, 2, 0), az, el, rng.rnd(58, 74), 15, 0.022, 0.45)
  discard t.dome(top + vec3(0, 2, 0), 7, 6, 4, 0, 0.5, txFibre)
  if nuts:
    for k in 0 ..< 6:
      let a = rng.rnd(0, 2 * PI)
      discard t.dome(top + vec3(cos(a) * 4.5, -4 + rng.rnd(-2, 1.5), sin(a) * 4.5 + 3), 3.3, 3.5, 3.4, 0, 0.5)
  t

proc palmPair*(seed: int): Tree =
  var a = coconutPalm(seed, -34, 165, 15)
  var b = coconutPalm(seed + 1, 42, 140, 14)
  for p in b.prims.mitems:
    case p.kind
    of pkTube: p.a.x += 18; p.b.x += 18; p.a.z -= 8; p.b.z -= 8
    of pkDome: p.c.x += 18; p.c.z -= 8
    of pkLeaf: p.p.x += 18; p.ld -= 8
  let off = a.prims.len
  for p in b.prims:
    var q = p
    if q.kind == pkLeaf and q.dome >= 0: q.dome += off
    a.prims.add q
  a

proc datePalm*(seed: int): Tree =
  var rng = initRand(seed)
  var t: Tree
  t.base = 0.8; t.depthTo = 7
  let top = vec3(3, 130, 0)
  discard t.palmTrunk(vec3(0, -2, 0), vec3(0, 65, 0), top, 8, 6.5, txPlates, 0.8)
  for k in 0 ..< 30:
    let az = float(k) / 30 * 2 * PI * 2.3 + rng.rnd(-0.2, 0.2)
    let el = rng.rnd(-0.3, 1.25)
    t.frond(rng, top + vec3(0, 3, 0), az, el, rng.rnd(48, 62), 11, 0.03, 0.3, 0.35)
  # a few old fronds hanging down under the crown
  for k in 0 ..< 6:
    let az = rng.rnd(0, 2 * PI)
    t.frond(rng, top + vec3(0, -2, 0), az, -1.2, rng.rnd(30, 40), 8, 0.02, 0.4, 0.5, dead = true)
  # hanging bunches of dates
  for k in 0 ..< 4:
    let a = rng.rnd(0, 2 * PI)
    let c = top + vec3(cos(a) * 9, -10, sin(a) * 9 + 4)
    for j in 0 ..< 14:
      discard t.dome(c + vec3(rng.rnd(-3.5, 3.5), rng.rnd(-6, 3), rng.rnd(0, 3)), 1.4, 1.8, 2.6 + rng.rnd(0, 0.8), 0, 0.5)
  discard t.dome(top + vec3(0, 3, 0), 9, 7, 4, 0, 0.5, txFibre)
  t

proc fanPalm*(seed: int, height = 190.0): Tree =
  ## A tall fan palm with a round head of fan leaves and a skirt of old ones hanging below.
  var rng = initRand(seed)
  var t: Tree
  t.base = 0.8; t.depthTo = 7
  let top = vec3(2, height - 20, 0)
  discard t.palmTrunk(vec3(0, -2, 0), vec3(0, height * 0.5, 0), top, 6.5, 4, txRings, 0.35)
  # the skirt: a thick thatch of old leaves hanging down the trunk, ragged at the bottom
  t.polyTube(@[top + vec3(0, 3, 0), top + vec3(0, -25, 0), top + vec3(0, -48, 0)], 10.5, 8.0, txFibre, 0.9, 0.8, 4)
  for k in 0 ..< 110:
    let az = rng.rnd(0, 2 * PI)
    let r = rng.rnd(6, 11)
    let l = rng.rnd(36, 58)
    let a = top + vec3(cos(az) * r, rng.rnd(-4, 2), sin(az) * r)
    t.polyTube(@[a, a + vec3(cos(az) * 1.5, -l * 0.5, sin(az) * 1.5), a + vec3(cos(az) * -0.5, -l, sin(az) * -0.5)],
               2.0, 1.1, txFibre, 0.35, 0.6)
  # live fans all round the head
  for k in 0 ..< 26:
    let az = float(k) * 2.39996 + rng.rnd(-0.2, 0.2)
    let el = rng.rnd(-0.55, 1.3)
    let d = vec3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
    let pl = rng.rnd(18, 28)
    let hub = top + vec3(0, 4, 0) + d * pl + vec3(0, -pl * 0.12, 0)
    t.polyTube(@[top + vec3(0, 4, 0), top + vec3(0, 4, 0) + d * pl * 0.5, hub], 1.1, 0.75)
    var side = cross(d, vec3(0, 1, 0))
    side = if side.len > 1e-6: side.normalized else: vec3(1, 0, 0)
    let upv = cross(side, d).normalized
    let segs = 30
    for j in 0 ..< segs:
      let a = (float(j) / float(segs - 1) - 0.5) * 2.4
      let sd = (d * cos(a) + side * sin(a) + upv * 0.35 * cos(a)).normalized
      let l = rng.rnd(16, 20)
      let mid = hub + sd * l * 0.55
      let tip = hub + sd * l + vec3(0, -l * 0.35 * abs(sin(a)) - 2, 0)
      t.polyTube(@[hub, mid, tip], 1.5, 0.45, txNone, 0, 0.45, sharp = 0.5)
  discard t.dome(top + vec3(0, 4, 0), 7, 7, 4, 0, 0.5, txFibre)
  t

proc youngPalm*(seed: int): Tree =
  coconutPalm(seed, 8, 85, 13, false)

proc joshuaTree*(seed: int): Tree =
  ## A Joshua tree: stout shaggy arms forking at angles, each ending in a spiky rosette.
  var rng = initRand(seed)
  var t: Tree
  t.base = 0.8; t.depthTo = 7
  proc arm(t: var Tree, rng: var Rand, a: Vec3, dir: Vec3, len, r: float, depth: int) =
    let mid = a + dir * len * 0.5 + vec3(rng.gn, 0, rng.gn) * len * 0.06
    let b = a + dir * len
    t.polyTube(@[a, mid, b], r, r * 0.88, txFibre, 0.6, 0.75, float(depth))
    if depth == 0:
      # rosette of stiff spikes bursting out all round, old dead ones hanging beneath
      let c = b + dir * 3
      let dm = t.dome(c, 5.5, 5.5, 3.5)
      for k in 0 ..< 60:
        let ang = rng.rnd(0, 2 * PI)
        let ln = rng.rnd(7, 11)
        t.leaf(c.xy + vec2(cos(ang), sin(ang)) * 1.5, dm, ang, ln, 0.6, 0.6, lsLance, lift = rng.rnd(0, 0.6))
      for k in 0 ..< 14:
        let ang = -PI / 2 + rng.rnd(-0.6, 0.6)
        t.leaf(b.xy + vec2(rng.rnd(-2, 2), 0), -1, ang, rng.rnd(7, 10), 0.6, 0.5, lsLance, depth = b.z)
      return
    let kids = if depth == 3: 3 else: 2 + (if rng.rand(1.0) < 0.3: 1 else: 0)
    for k in 0 ..< kids:
      let az = float(k) / float(kids) * 2 * PI + rng.rnd(-0.6, 0.6)
      let nd = (dir * 0.35 + vec3(cos(az), rng.rnd(0.3, 1.0), sin(az)) * 0.9).normalized
      arm(t, rng, b, nd, len * rng.rnd(0.65, 0.9), r * 0.78, depth - 1)
  t.tube(vec3(0, -2, 0), vec3(0, 6, 0), 9, 7, txFibre, 0.6, 0, 0.75, 1)
  arm(t, rng, vec3(0, 0, 0), vec3(0.05, 1, 0).normalized, 36, 7, 3)
  t
