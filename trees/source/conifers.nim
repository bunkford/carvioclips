## Conifers: whorls of boughs round a straight leader (spruces, firs, larches), or a trunk
## carrying tufts and pads of needles (pines, cedars, cypresses, junipers).

import std/[math, random]
import core/vec
import treecore, treegrow

type
  Needles* = object
    len*, wid*, th*: float
    density*: float        ## needles a square millimetre of bough
    spread*: float         ## angle off the twig (radians)
    hang*: float           ## how far needles swing towards straight down
    shape*: LeafShape
    toward*: float         ## the way they hang (straight down; up for upright sprays)

proc needles*(len = 2.6, wid = 0.42, th = 0.5, density = 0.45, spread = 0.9, hang = 0.3,
              shape = lsLance, toward = -PI / 2): Needles =
  Needles(len: len, wid: wid, th: th, density: density, spread: spread, hang: hang, shape: shape, toward: toward)

proc angTo(a, target, k: float): float =
  var d = target - a
  while d > PI: d -= 2 * PI
  while d < -PI: d += 2 * PI
  a + d * k

proc needlesOn*(t: var Tree, rng: var Rand, d: int, axis: float, n: Needles) =
  ## Needles over a pad, pointing out from its axis and forward along it, like a spray.
  let p = t.prims[d]
  let cnt = int(PI * p.rx * p.ry * n.density)
  for k in 0 ..< cnt:
    let a = rng.rnd(0, 2 * PI); let rr = sqrt(rng.rand(1.0)) * 0.95
    let lp = p.c.xy + vec2(cos(a) * p.rx * rr, 0) .rotated(p.rot) + vec2(0, sin(a) * p.ry * rr).rotated(p.rot)
    let rel = lp - p.c.xy
    let side = if cross(vec2(cos(axis), sin(axis)), rel) >= 0: 1.0 else: -1.0
    var ang = axis + side * n.spread * rng.rnd(0.6, 1.2)
    ang = angTo(ang, n.toward, n.hang * rng.rnd(0.5, 1.0))
    let ln = n.len * rng.rnd(0.75, 1.15)
    t.leaf(lp - vec2(cos(ang), sin(ang)) * ln * 0.35, d, ang, ln, n.wid, n.th * rng.rnd(0.8, 1.1), n.shape,
           lift = rng.rnd(-0.1, 0.2) * n.th)

proc bough*(t: var Tree, rng: var Rand, path: seq[Vec3], w0, w1: float, n: Needles, hangDown = 0.35,
            snow = 0.0, padH = 0.45) =
  ## A needled bough along a path: overlapping pads from w0 wide at the trunk to w1 at the tip,
  ## each sitting a little below the branch, as the hanging twigs of a spruce do.
  var total = 0.0
  for i in 1 ..< path.len: total += dist(path[i], path[i - 1])
  var acc = 0.0
  var nextAt = 0.0
  for i in 1 ..< path.len:
    let seg = dist(path[i], path[i - 1])
    acc += seg
    if acc < nextAt: continue
    let tt = acc / total
    let w = w0 + (w1 - w0) * tt
    nextAt = acc + w * 0.7
    let d2 = (path[i] - path[i - 1]).xy
    let axis = if d2.len > 1e-6: arctan2(d2.y, d2.x) else: -PI / 2
    let flat = d2.len / max(seg, 1e-6)   # 1 for a branch across the view, 0 pointing at it
    let rx = w * (0.75 + 0.6 * flat); let ry = w * (0.75 - 0.15 * flat)
    let c = path[i] + vec3(0, -w * hangDown, 0)
    let dm = t.dome(c, rx, ry, w * padH, axis, 0.5)
    t.needlesOn(rng, dm, axis, n)
    if snow > 0:
      # a smooth cap of snow lying on top of the bough
      let sc = path[i] + vec3(0, w * 0.25, w * 0.4)
      discard t.dome(sc, rx * 0.95, ry * 0.5, w * padH + 0.9 + snow * w * 0.25, axis, 0.6, txSnow)

proc branchPath*(rng: var Rand, start: Vec3, az, len, e0, e1: float, step = 2.0, sway = 0.05): seq[Vec3] =
  ## A branch leaving the trunk at elevation e0 (radians, down is negative), ending at e1.
  var p = start
  result.add p
  var acc = 0.0
  var a = az
  while acc < len:
    let t = acc / len
    let e = e0 + (e1 - e0) * pow(t, 1.4)
    a += rng.gn * sway
    p += vec3(cos(a) * cos(e), sin(e), sin(a) * cos(e)) * step
    acc += step
    result.add p

type
  Spruce* = object
    seed*: int
    height*, width*: float
    trunkR*: float
    clearTrunk*: float       ## bare trunk at the bottom
    gap*: float              ## between whorls
    perWhorl*: int
    e0*, e1*: float          ## branch elevation at the trunk and at the tip
    shape*: float            ## outline power: 1 a cone, < 1 fuller, > 1 a spire
    w0*, w1*: float          ## bough width at the trunk and tip, as a share of the branch length
    wMin*: float
    n*: Needles
    hangDown*: float
    snow*: float
    bare*: bool              ## larch in winter: twigs, no needles
    lenVar*: float           ## branches this much shorter at random
    between*: int            ## short branches between the whorls
    depthTo*: float

proc spruceDef*(seed: int): Spruce =
  Spruce(seed: seed, height: 170, width: 92, trunkR: 4.5, clearTrunk: 10, gap: 5.2, perWhorl: 8,
         e0: -0.55, e1: 0.2, shape: 1.0, w0: 0.22, w1: 0.12, wMin: 2.8, n: needles(),
         hangDown: 0.6, depthTo: 7, lenVar: 0.45, between: 3)

proc grow*(sp: Spruce): Tree =
  var rng = initRand(sp.seed)
  var t: Tree
  t.base = 0.8; t.depthTo = sp.depthTo
  t.tube(vec3(0, -2, 0), vec3(0, sp.height * 0.97, 0), sp.trunkR, 0.4, txPlates, 0.35, 0, 0.75, 1)
  t.tube(vec3(0, -2, 0), vec3(0, sp.trunkR * 2.2, 0), sp.trunkR * 1.45, sp.trunkR, txPlates, 0.35, 0, 0.75, 1)
  var y = sp.clearTrunk
  var az0 = rng.rnd(0, 2 * PI)
  while y < sp.height - 4:
    let frac = (y - sp.clearTrunk) / (sp.height - sp.clearTrunk)
    let reach = sp.width * 0.5 * pow(1 - frac, sp.shape) + 3
    let nb = max(3, sp.perWhorl - (if frac > 0.85: 2 else: 0))
    az0 += 0.6
    for k in 0 ..< nb + sp.between:
      let short = k >= nb
      let az = if short: rng.rnd(0, 2 * PI) else: az0 + float(k) / float(nb) * 2 * PI + rng.rnd(-0.35, 0.35)
      let len = reach * rng.rnd(1 - sp.lenVar, 1.06) * (if short: 0.55 else: 1.0)
      let by = if short: y + sp.gap * rng.rnd(0.3, 0.7) else: y
      let path = branchPath(rng, vec3(0, by, 0), az, len, sp.e0 * (0.6 + 0.6 * (1 - frac)) * rng.rnd(0.7, 1.2), sp.e1, 2.0, 0.07)
      let br = max(0.35, sp.trunkR * 0.32 * (1 - frac * 0.7))
      t.polyTube(path, br, 0.3)
      if sp.bare:
        # side twigs along the branch, pointing out and up
        var acc = 0.0
        for i in 1 ..< path.len:
          acc += dist(path[i], path[i - 1])
          if rng.rand(1.0) < 0.55:
            let dir = (path[i] - path[i - 1]).normalized
            let side = (cross(dir, vec3(0, 1, 0)).normalized * (if rng.rand(1.0) < 0.5: 1.0 else: -1.0) +
                        dir * 0.6 + vec3(0, -0.25, 0)).normalized
            let l = min(len * 0.25, 9.0) * (1 - acc / len) + 1.5
            t.polyTube(@[path[i], path[i] + side * l * 0.5 + vec3(0, -l * 0.12, 0), path[i] + side * l + vec3(0, -l * 0.15, 0)], 0.3, 0.22)
      else:
        t.bough(rng, path, max(sp.wMin, len * sp.w0), max(sp.wMin * 0.7, len * sp.w1), sp.n, sp.hangDown, sp.snow)
    y += sp.gap * rng.rnd(0.8, 1.2)
  # the leader at the top
  if not sp.bare:
    let tip = @[vec3(0, sp.height - 10, 0), vec3(0, sp.height - 5, 0.5), vec3(0, sp.height, 0)]
    t.bough(rng, tip, sp.wMin * 1.1, sp.wMin * 0.6, sp.n, 0.0, sp.snow)
  t

proc spruce*(seed: int, height = 170.0, width = 92.0, snow = 0.0): Tree =
  var sp = spruceDef(seed)
  sp.height = height; sp.width = width; sp.snow = snow
  sp.trunkR = 4.5 * height / 170
  sp.gap = 6.5 * sqrt(height / 170)
  sp.depthTo = 7 * sqrt(height / 170)
  if height < 100: sp.clearTrunk = 5; sp.wMin = 2.2
  if snow > 0: sp.n.hang = 0.15; sp.hangDown = 0.3
  sp.grow()

proc fir*(seed: int, height = 175.0, width = 64.0): Tree =
  var sp = spruceDef(seed)
  sp.height = height; sp.width = width
  sp.trunkR = 4 * height / 175
  sp.e0 = 0.05; sp.e1 = 0.3; sp.shape = 1.1; sp.gap = 4.8; sp.lenVar = 0.25; sp.between = 2
  sp.n = needles(len = 2.2, wid = 0.5, th = 0.55, density = 0.5, spread = 1.1, hang = 0.05)
  sp.hangDown = 0.1; sp.w0 = 0.2; sp.w1 = 0.12
  sp.clearTrunk = 8
  sp.grow()

proc larch*(seed: int): Tree =
  var sp = spruceDef(seed)
  sp.height = 170; sp.width = 84; sp.bare = true; sp.e0 = -0.5; sp.e1 = 0.4; sp.gap = 6; sp.perWhorl = 6
  sp.clearTrunk = 18; sp.shape = 0.9; sp.between = 2
  sp.grow()

proc bird*(t: var Tree, p: Vec2, depth: float, facing: float, size = 1.0) =
  ## A little songbird perched on a bough, facing right (1) or left (-1).
  let s = facing; let k = size
  let back = if s > 0: PI else: 0.0
  let body = t.dome(vec3(p.x, p.y, depth), 3.4 * k, 2.5 * k, 2.4 * k, s * 0.3, 0.5)
  let head = t.dome(vec3(p.x + s * 2.9 * k, p.y + 2.1 * k, depth + 2), 1.85 * k, 1.75 * k, 2.6 * k, 0, 0.5)
  # beak, tail and folded wing lie on the body and head
  t.leaf(vec2(p.x + s * 4.3 * k, p.y + 2.2 * k), head, (if s > 0: -0.15 else: PI + 0.15), 1.7 * k, 0.55 * k, 0.6 * k, lsLance)
  t.leaf(vec2(p.x - s * 2.4 * k, p.y + 0.2 * k), body, back - s * 0.75, 5.0 * k, 1.2 * k, 0.9 * k, lsLance)
  t.leaf(vec2(p.x + s * 1.4 * k, p.y + 0.7 * k), body, back - s * 0.2, 4.4 * k, 1.35 * k, 0.75 * k, lsOval)

proc christmasTree*(seed: int): Tree =
  ## A small spruce with a star on top and songbirds perched on its boughs.
  var sp = spruceDef(seed)
  sp.height = 120; sp.width = 78; sp.trunkR = 3.4; sp.gap = 5.5; sp.clearTrunk = 8; sp.wMin = 2.4
  sp.depthTo = 6
  var t = sp.grow()
  # birds on the boughs, out towards the front where they can be seen
  for (y, side, along) in [(36.0, -1.0, 0.72), (68.0, 1.0, 0.66), (92.0, -1.0, 0.5)]:
    let reach = 39 * (1 - (y - 8) / 112) + 3
    t.bird(vec2(side * reach * along, y + 3), reach + 10, -side, 1.3)
  # a five-pointed star on the top
  let sc = vec3(0, 124, 2)
  for k in 0 ..< 5:
    let a = PI / 2 + float(k) * 2 * PI / 5
    t.leaf(sc.xy, -1, a, 6.5, 2.4, 1.6, lsLance, depth = sc.z + 6)
  discard t.dome(sc + vec3(0, 0, 6), 2.6, 2.6, 2.0)
  t

# ---------------------------------------------------------------- tufted conifers
proc tuft*(t: var Tree, rng: var Rand, c: Vec3, r: float, n: Needles, flat = 1.0) =
  ## A brush of needles bursting out of a twig end, pointing out and up.
  let dm = t.dome(c, r * flat, r, r * 0.45, rng.rnd(-0.2, 0.2), 0.5)
  let p = t.prims[dm]
  let cnt = int(PI * p.rx * p.ry * n.density)
  for k in 0 ..< cnt:
    let a = rng.rnd(0, 2 * PI); let rr = pow(rng.rand(1.0), 0.6) * 0.95
    let lp = c.xy + vec2(cos(a) * p.rx * rr, sin(a) * p.ry * rr)
    var ang = arctan2(lp.y - c.y + r * 0.3, lp.x - c.x)
    ang = angTo(ang, PI / 2, 0.25) + rng.gn * 0.25
    let ln = n.len * rng.rnd(0.7, 1.1)
    t.leaf(lp - vec2(cos(ang), sin(ang)) * ln * 0.5, dm, ang, ln, n.wid, n.th, n.shape, lift = rng.rnd(0, 0.25) * n.th)

type TuftTree* = object
  seed*: int
  crownBase*: float
  crownC*, crownR*: Vec3
  trunkR*: float
  points*: int
  lumps*: int
  lumpR*: float
  flatTop*: bool
  trop*: Vec3
  wobble*: float
  tuftR*: float
  tuftFlat*: float
  spacing*: float
  n*: Needles
  tex*: Tex
  texAmp*: float
  depthTo*: float
  lean*: float
  stubs*: int              ## dead branch stubs on the bare trunk
  limbs*: int
  limbRise*: float
  shellIn*: float
  influence*, kill*, step*: float
  scaly*: bool             ## upright scale-leaved sprays instead of needle tufts

proc tuftDef*(seed: int): TuftTree =
  TuftTree(seed: seed, crownBase: 100, crownC: vec3(0, 140, 0), crownR: vec3(50, 30, 45), trunkR: 5.5,
           points: 700, lumps: 8, lumpR: 0.45, trop: vec3(0, 0.1, 0), wobble: 0.25, tuftR: 6.5,
           tuftFlat: 1.25, spacing: 0.95, n: needles(len = 3.6, wid = 0.4, th = 0.5, density = 0.5),
           tex: txPlates, texAmp: 0.45, depthTo: 7, stubs: 6, limbs: 3, limbRise: 0.6, shellIn: 0.25,
           influence: 20, kill: 5, step: 2.6)

proc grow*(d: TuftTree): Tree =
  var rng = initRand(d.seed)
  var t: Tree
  t.base = 0.8; t.depthTo = d.depthTo
  var s: Skeleton
  let top = s.stem(rng, vec3(0, 0, 0), vec3(d.lean, d.crownBase, 0), d.step, 0.08)
  for k in 0 ..< d.limbs:
    let az = float(k) / float(d.limbs) * 2 * PI + rng.rnd(-0.5, 0.5)
    let goal = vec3(d.crownC.x + cos(az) * d.crownR.x * 0.55, d.crownBase + (d.crownC.y - d.crownBase) * d.limbRise,
                    d.crownC.z + sin(az) * d.crownR.z * 0.55)
    discard s.curvedStem(rng, top, goal, d.step, 0.3, 0.25)
  let env = lumpy(rng, d.crownC, d.crownR, d.lumps, d.lumpR, d.flatTop)
  let cc = d.crownC; let cr = d.crownR; let si = d.shellIn
  let w = proc (p: Vec3): float =
    smoothstep(si, si + 0.35, sqrt(sq((p.x - cc.x) / cr.x) + sq((p.y - cc.y) / cr.y) + sq((p.z - cc.z) / cr.z)))
  var pts = scatterW(rng, env, w, cc - cr * 1.3, cc + cr * 1.3, d.points)
  s.colonise(rng, pts, d.step, d.influence, d.kill, d.trop, d.wobble)
  s.smooth(3)
  s.computeRadii(0.4, 2.4, d.trunkR)
  s.toTubes(t, d.tex, d.texAmp, 0.75, float(d.seed mod 31))
  t.rootFlare(rng, d.trunkR, 4, d.tex, d.texAmp * 0.8, 2.2)
  # dead stubs on the bare trunk, as pines shed their lower branches
  for k in 0 ..< d.stubs:
    let y = rng.rnd(d.crownBase * 0.35, d.crownBase * 0.95)
    let az = rng.rnd(0, 2 * PI)
    let l = rng.rnd(4, 10)
    let a = vec3(d.lean * y / d.crownBase, y, 0)
    t.tube(a, a + vec3(cos(az) * l, -l * 0.15, sin(az) * l), 1.1, 0.5, txNone, 0, 0, 0.75)
  # needle tufts at the twig ends, kept apart
  var placed: seq[Vec3]
  for i, nd in s.nodes:
    if not s.isTip(i) or nd.parent < 0: continue
    var ok = true
    for q in placed:
      if dist(q, nd.p) < d.tuftR * d.spacing: ok = false; break
    if not ok: continue
    placed.add nd.p
    if d.scaly:
      let r = d.tuftR * rng.rnd(0.8, 1.2)
      let dm = t.dome(nd.p + vec3(0, r * 0.3, 0), r * d.tuftFlat, r * 1.15, r * 0.4, rng.rnd(-0.25, 0.25), 0.5)
      t.needlesOn(rng, dm, PI / 2 + rng.rnd(-0.3, 0.3), d.n)
    else:
      t.tuft(rng, nd.p + vec3(0, d.tuftR * 0.2, 0), d.tuftR * rng.rnd(0.8, 1.2), d.n, d.tuftFlat)
  t

proc scotsPine*(seed: int, lean = 0.0): Tree =
  var d = tuftDef(seed)
  d.lean = lean
  d.grow()

proc stonePine*(seed: int): Tree =
  var d = tuftDef(seed)
  d.crownBase = 70; d.crownC = vec3(0, 118, 0); d.crownR = vec3(88, 22, 76); d.flatTop = false
  d.lumps = 12; d.lumpR = 0.4; d.limbs = 4; d.limbRise = 0.75; d.trunkR = 6.5; d.points = 1000
  d.tuftR = 7; d.tuftFlat = 1.5; d.stubs = 3; d.trop = vec3(0, 0.2, 0); d.shellIn = 0.1
  d.grow()

proc windsweptPine*(seed: int): Tree =
  ## A pine shaped by the wind: leaning, its branches all streaming to one side in flat layers.
  var d = tuftDef(seed)
  d.crownBase = 60; d.lean = 22; d.crownC = vec3(40, 105, 0); d.crownR = vec3(70, 34, 40)
  d.lumps = 9; d.lumpR = 0.38; d.limbs = 3; d.limbRise = 0.5; d.trop = vec3(0.35, 0.02, 0)
  d.tuftR = 6.5; d.tuftFlat = 1.8; d.stubs = 2; d.points = 800; d.wobble = 0.3
  d.grow()

proc cedar*(seed: int): Tree =
  ## A cedar of Lebanon: flat, layered tables of foliage held out on long limbs.
  var rng = initRand(seed)
  var t: Tree
  t.base = 0.8; t.depthTo = 7
  let h = 150.0
  t.tube(vec3(0, -2, 0), vec3(2, h * 0.9, 0), 7, 1.5, txPlates, 0.5, 0, 0.75, 1)
  t.rootFlare(rng, 7, 4, txPlates, 0.4)
  var n = needles(len = 2.2, wid = 0.42, th = 0.45, density = 0.55, spread = 1.3, hang = 0.0)
  let tiers = [(40.0, 80.0), (62.0, 70.0), (84.0, 60.0), (104.0, 46.0), (122.0, 34.0), (138.0, 20.0)]
  for ti, (y0, r) in tiers:
    let nb = 4 + rng.rand(2)
    let y = y0 + rng.rnd(-4, 4)
    for k in 0 ..< nb:
      if rng.rand(1.0) < 0.15: continue          # gaps in the tiers, as on a real cedar
      let az = float(k) / float(nb) * 2 * PI + rng.rnd(-0.5, 0.5)
      let len = r * rng.rnd(0.6, 1.1)
      let path = branchPath(rng, vec3(1, y - 8, 0), az, len, 0.4, -0.08, 2.0, 0.1)
      t.polyTube(path, 2.6 * r / 82 + 0.6, 0.5, txPlates, 0.2)
      # the table: clumps of flat sprays spread along and either side of the branch's outer half
      var acc = 0.0
      for i in 1 ..< path.len:
        acc += dist(path[i], path[i - 1])
        if acc < len * 0.25 or i mod 2 != 0: continue
        let p = path[i]
        let spreadR = 4 + 9 * (acc / len)
        for j in 0 ..< 2:
          let off = vec3(rng.rnd(-spreadR, spreadR), rng.rnd(-1, 3.5), rng.rnd(-spreadR, spreadR))
          let pr = rng.rnd(4.5, 7.5)
          let dm = t.dome(p + off, pr * 1.45, pr * 0.6, pr * 0.38, rng.rnd(-0.2, 0.2), 0.5)
          t.needlesOn(rng, dm, if rng.rand(1.0) < 0.5: 0.3 else: PI - 0.3, n)
  t

proc sprays*(seed: int, height, R: float, rough = 0.12, clear = 6.0, lean = 0.0, fullAt = 0.12,
             tipPow = 0.75, sprayW = 2.6, trunkTex = txFibre): Tree =
  ## A dense column of upright scale-leaved sprays round a trunk: cypresses and junipers.
  var rng = initRand(seed)
  var t: Tree
  let k = height / 180
  t.base = 0.8; t.depthTo = 5.5 * sqrt(k) * pow(R / (19 * k), 0.3)
  let trunkTop = vec3(lean, height * 0.95, 0)
  t.tube(vec3(0, -2, 0), trunkTop, 4 * k + R * 0.06, 0.4, trunkTex, 0.5, 0, 0.75, 1)
  let n = needles(len = 1.9, wid = 0.7, th = 0.5, density = 0.5, spread = 0.45, hang = 0.5,
                  shape = lsScale, toward = PI / 2)
  var y = clear
  while y < height:
    let f = y / height
    # full low down, drawn to a point at the top, with a wavy uneven edge
    let r = R * pow(min(1.0, (y - clear * 0.7) / (height * fullAt)), 0.5) * pow(1 - f, tipPow) *
            (1 + rough * noise(y / 9, 0.5 + float(seed), 2) * 2) + 2
    let cx = lean * f
    for b in 0 ..< int(3 + R / 6):
      let az = rng.rnd(0, 2 * PI)
      let len = r * rng.rnd(0.5, 1.0) * (1 + rough * noise(cos(az) * 2 + y / 20, sin(az) * 2, 7))
      # the sprays climb steeply, so the branch is longer than the reach out from the trunk
      let path = branchPath(rng, vec3(cx, y, 0), az, len / 0.62, 0.7, 1.1, 1.6, 0.05)
      for i in 1 ..< path.len:
        if i mod 2 != 0 and i != path.len - 1: continue
        let w = sprayW * sqrt(k) * rng.rnd(0.8, 1.2)
        let dm = t.dome(path[i], w * 0.75, w * 1.35, w * 0.45, rng.rnd(-0.3, 0.3), 0.5)
        t.needlesOn(rng, dm, PI / 2 + rng.rnd(-0.3, 0.3), n)
    y += 2.4 * sqrt(k)
  t

proc cypress*(seed: int, height = 180.0): Tree =
  ## An Italian cypress: a narrow dark flame.
  sprays(seed, height, 21 * height / 180)

proc juniper*(seed: int): Tree =
  ## A rugged juniper: a leaning twisted trunk and an uneven, bushy cone.
  sprays(seed, 120, 34, rough = 0.4, clear = 18, lean = 8, fullAt = 0.25, tipPow = 0.9, sprayW = 3.0)
