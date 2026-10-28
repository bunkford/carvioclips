## Broadleaf trees: a trunk and limbs grown into a crown shape, leaf clumps on the twig ends,
## or fine twigs for the bare winter versions.

import std/[math, random]
import core/vec
import treecore, treegrow

type
  TreeDef* = object
    id*, name*, desc*: string
    tags*: seq[string]
    build*: proc (): Tree

  Broad* = object
    seed*: int
    crownBase*: float             ## top of the trunk
    crownC*, crownR*: Vec3        ## crown centre and radii
    trunkR*: float
    points*: int                  ## attraction points: more makes a finer branch structure
    f*: Foliage
    leafy*: bool
    tex*: Tex
    texAmp*: float
    lumps*: int
    lumpR*: float
    flatTop*: bool
    trop*: Vec3                   ## pull on every new branch (up, or down for weeping trees)
    wobble*: float                ## crookedness
    step*, influence*, kill*: float
    lean*: float
    twigs*: int
    twigLen*, twigSpread*, gravity*, twigUp*: float
    stems*: seq[(Vec3, Vec3)]     ## several trunks instead of one
    depthTo*: float
    roots*: int
    expo*, tipR*: float
    shellIn*, underOpen*: float
    limbs*: int
    limbRise*, limbReach*: float
    smoothPasses*: int
    limbCurve*: float             ## how steeply limbs leave the trunk before bending out

proc broad*(seed: int): Broad =
  Broad(seed: seed, crownBase: 45, crownC: vec3(0, 100, 0), crownR: vec3(60, 50, 55), trunkR: 7,
        points: 1400, f: defaultFoliage(), leafy: true, tex: txBark, texAmp: 0.45, lumps: 14, lumpR: 0.4,
        trop: vec3(0, 0.08, 0), wobble: 0.18, step: 2.6, influence: 21, kill: 5, twigs: 2, twigLen: 5,
        twigSpread: 0.6, depthTo: 7, roots: 5, expo: 2.4, tipR: 0.32, shellIn: 0.3, underOpen: 0.6,
        limbs: 3, limbRise: 0.7, limbReach: 0.5, smoothPasses: 3, limbCurve: 0.35)

proc scaled*(b: Broad, k: float): Broad =
  ## The same tree k times the size (a sapling of it, or a bigger one).
  result = b
  result.crownBase *= k; result.crownC = b.crownC * k; result.crownR = b.crownR * k
  result.trunkR *= k; result.step *= k; result.influence *= k; result.kill *= k
  result.depthTo *= sqrt(k); result.texAmp *= sqrt(k)
  result.f.clumpR *= sqrt(k)
  for i in 0 ..< result.stems.len:
    result.stems[i] = (b.stems[i][0] * k, b.stems[i][1] * k)

type Extra* = proc (t: var Tree, s: var Skeleton, rng: var Rand, clumps: seq[int])

proc grow*(b: Broad, extra: Extra = nil, pruneShare = 0.0): Tree =
  var rng = initRand(b.seed)
  var s: Skeleton
  if b.stems.len == 0:
    let top = s.stem(rng, vec3(0, 0, 0), vec3(b.lean, b.crownBase, 0), b.step, 0.12)
    # main limbs fork from the top of the trunk and spread into the crown
    for k in 0 ..< b.limbs:
      let az = float(k) / float(b.limbs) * 2 * PI + rng.rnd(-0.5, 0.5)
      let reach = rng.rnd(b.limbReach * 0.7, b.limbReach * 1.2)
      let goal = vec3(b.crownC.x + cos(az) * b.crownR.x * reach,
                      b.crownBase + (b.crownC.y - b.crownBase) * rng.rnd(b.limbRise * 0.7, b.limbRise),
                      b.crownC.z + sin(az) * b.crownR.z * reach)
      discard s.curvedStem(rng, top, goal, b.step, b.limbCurve, 0.2)
  else:
    for (a, c) in b.stems: discard s.stem(rng, a, c, b.step, 0.15)
  let env = lumpy(rng, b.crownC, b.crownR, b.lumps, b.lumpR, b.flatTop)
  # leaves gather on the crown's outside and top, so the points do too, leaving the limbs bare inside
  let cc = b.crownC; let cr = b.crownR; let shellIn = b.shellIn; let underOpen = b.underOpen
  let shellW = proc (p: Vec3): float =
    let q = sqrt(sq((p.x - cc.x) / cr.x) + sq((p.y - cc.y) / cr.y) + sq((p.z - cc.z) / cr.z))
    smoothstep(shellIn, shellIn + 0.35, q) *
      (if p.y < cc.y: 1 - underOpen * smoothstep(0.0, 0.8, (cc.y - p.y) / cr.y) else: 1.0)
  var pts = scatterW(rng, env, shellW, cc - cr * 1.3, cc + cr * 1.3, b.points)
  s.colonise(rng, pts, b.step, b.influence, b.kill, b.trop, b.wobble)
  s.smooth(b.smoothPasses)
  if not b.leafy and b.twigs > 0:
    s.computeRadii(b.tipR, b.expo, b.trunkR)
    s.addTwigs(rng, b.twigs, b.twigLen, b.twigSpread, b.gravity, up = b.twigUp)
    s.smooth(1)
  s.computeRadii(b.tipR, b.expo, b.trunkR)
  if pruneShare > 0:
    s.prune(rng, pruneShare, 1, b.trunkR * 0.6, b.tipR * 3)
  result.base = 0.8
  result.depthTo = b.depthTo
  s.toTubes(result, b.tex, b.texAmp, 0.75, float(b.seed mod 97))
  if b.roots > 0:
    if b.stems.len == 0: result.rootFlare(rng, b.trunkR, b.roots, b.tex, b.texAmp * 0.8)
    else:
      for (a, c) in b.stems:
        result.tube(a + vec3(0, -2, 0), a + (c - a).normalized * b.trunkR * 2.5, b.trunkR * 1.35, b.trunkR, b.tex, b.texAmp, 0, 0.75, 1)
  var clumps: seq[int]
  if b.leafy: clumps = s.foliage(result, rng, b.f, b.crownC, b.crownR)
  if extra != nil: extra(result, s, rng, clumps)

# ---------------------------------------------------------------- extras
proc fruit*(count: int, r: float): Extra =
  ## Round fruit sitting in the front clumps.
  result = proc (t: var Tree, s: var Skeleton, rng: var Rand, clumps: seq[int]) =
    if clumps.len == 0: return
    var zs: seq[float]
    for c in clumps: zs.add t.prims[c].c.z
    var placed = 0; var tries = 0
    while placed < count and tries < count * 30:
      inc tries
      let c = clumps[rng.rand(clumps.len - 1)]
      let d = t.prims[c]
      if d.c.z < 0: continue
      let a = rng.rnd(0, 2 * PI); let rr = sqrt(rng.rand(1.0)) * 0.8
      let p = d.c.xy + vec2(cos(a) * d.rx * rr, sin(a) * d.ry * rr)
      # sit the fruit on the leaves: its dome rises from the clump's base to past the leaf tops
      let dx = p.x - d.c.x; let dy = p.y - d.c.y
      let q = sq((dx * cos(d.rot) + dy * sin(d.rot)) / d.rx) + sq((-dx * sin(d.rot) + dy * cos(d.rot)) / d.ry)
      let surf = d.h * sqrt(max(0.0, 1 - q))
      let rf = r * rng.rnd(0.85, 1.15)
      discard t.dome(vec3(p.x, p.y, d.c.z), rf, rf * 0.95, surf + rf * 0.75 + 0.6, 0, 0.5)
      inc placed

proc weeping*(count: int, lenMin, lenMax: float, leafy: bool, leafLen = 3.4): Extra =
  ## Long hanging strands off the outer twigs, with narrow leaves along them.
  result = proc (t: var Tree, s: var Skeleton, rng: var Rand, clumps: seq[int]) =
    var lo = vec3(1e9, 1e9, 1e9); var hi = vec3(-1e9, -1e9, -1e9)
    for n in s.nodes: lo = minv(lo, n.p); hi = maxv(hi, n.p)
    let c = (lo + hi) * 0.5
    var cand: seq[int]
    for i, n in s.nodes:
      if n.r < 0.9 and n.p.y > lo.y + (hi.y - lo.y) * 0.35: cand.add i
    if cand.len == 0: return
    for k in 0 ..< count:
      let n = s.nodes[cand[rng.rand(cand.len - 1)]]
      var p = n.p
      var outw = vec3(p.x - c.x, 0, p.z - c.z)
      outw = if outw.len > 1e-6: outw.normalized else: vec3(1, 0, 0)
      var dir = (outw * 0.8 + vec3(0, rng.rnd(0.2, 0.7), 0)).normalized
      let total = rng.rnd(lenMin, lenMax)
      var pts = @[p]
      var acc = 0.0
      while acc < total and p.y > 5:
        dir = (dir + vec3(0, -0.3, 0) + outw * 0.01).normalized
        p += dir * 1.8
        acc += 1.8
        pts.add p
      if pts.len < 3: continue
      t.polyTube(pts, 0.42, 0.22)
      if leafy:
        var side = 1.0
        var along = 0.0
        for i in 1 ..< pts.len:
          along += dist(pts[i], pts[i - 1])
          if along < 2.5: continue
          let d2 = (pts[i] - pts[i - 1]).xy
          let a = arctan2(d2.y, d2.x)
          if rng.rand(1.0) < 0.3: continue
          let ang = a + side * rng.rnd(0.15, 0.7) + rng.gn * 0.15
          side = -side
          t.leaf(pts[i].xy, -1, ang, leafLen * rng.rnd(0.8, 1.15), leafLen * 0.2, 0.45, lsLance,
                 depth = pts[i].z + rng.rnd(-0.5, 1.5))

# ---------------------------------------------------------------- species
proc oakDef*(seed: int, leafy: bool): Broad =
  result = broad(seed)
  result.leafy = leafy
  result.crownBase = 48; result.crownC = vec3(0, 102, 0); result.crownR = vec3(76, 50, 70)
  result.trunkR = 8.5; result.points = 1600; result.texAmp = 0.55; result.wobble = 0.22
  result.trop = vec3(0, 0.05, 0); result.influence = 22
  result.f.clumpR = 8; result.f.leafLen = 4.4; result.f.leafWid = 1.9; result.f.leafTh = 0.85
  result.f.leavesPerArea = 0.2; result.f.spacing = 0.95; result.f.clumpH = 0.4; result.f.droop = 0.4
  result.f.sizeVar = 0.4; result.f.wideness = 1.3; result.f.holes = 5; result.f.holeR = 0.15; result.f.thinBelow = 0.35

proc oak*(seed: int, leafy: bool): Tree = oakDef(seed, leafy).grow()

proc youngOak*(seed: int): Tree =
  var b = oakDef(seed, true).scaled(0.55)
  b.points = 700; b.limbs = 2; b.trunkR *= 0.8
  b.f.holes = 3
  b.grow()

proc oldOak*(seed: int, leafy: bool): Tree =
  var b = oakDef(seed, leafy)
  b.crownBase = 36; b.crownC = vec3(0, 88, 0); b.crownR = vec3(100, 46, 80)
  b.trunkR = 11; b.points = 2000; b.wobble = 0.3; b.limbs = 4; b.limbRise = 0.55; b.limbReach = 0.65
  b.trop = vec3(0, 0.0, 0); b.texAmp = 0.7; b.f.holes = 7; b.limbCurve = 0.6
  b.grow()

proc mapleDef*(seed: int, leafy: bool): Broad =
  result = broad(seed)
  result.leafy = leafy
  result.crownBase = 38; result.crownC = vec3(0, 100, 0); result.crownR = vec3(60, 58, 56)
  result.trunkR = 6.5; result.points = 1600; result.texAmp = 0.35; result.trop = vec3(0, 0.16, 0)
  result.limbs = 3; result.limbRise = 0.8; result.limbReach = 0.4
  result.f.clumpR = 7; result.f.leafLen = 3.8; result.f.leafWid = 1.9; result.f.leafTh = 0.8
  result.f.leafShape = lsPalmate; result.f.leavesPerArea = 0.13; result.f.spacing = 0.85
  result.f.clumpH = 0.42; result.f.droop = 0.3; result.f.sizeVar = 0.35; result.f.wideness = 1.15
  result.f.holes = 2; result.f.holeR = 0.12; result.f.thinBelow = 0.4

proc maple*(seed: int, leafy: bool): Tree = mapleDef(seed, leafy).grow()

proc tallMaple*(seed: int): Tree =
  var b = mapleDef(seed, true)
  b.crownBase = 40; b.crownC = vec3(0, 112, 0); b.crownR = vec3(46, 72, 44); b.trop = vec3(0, 0.25, 0)
  b.points = 1500
  b.grow()

proc birchDef*(seed: int, leafy: bool, stems = 1): Broad =
  result = broad(seed)
  result.leafy = leafy
  result.crownBase = 58; result.crownC = vec3(0, 118, 0); result.crownR = vec3(38, 62, 36)
  result.trunkR = 4.2; result.points = 1100; result.tex = txBirch; result.texAmp = 0.35
  result.trop = vec3(0, 0.1, 0); result.wobble = 0.15; result.limbs = 0; result.roots = 3
  result.gravity = 0.55; result.twigs = 3; result.twigLen = 4.5; result.twigSpread = 0.45
  result.influence = 18; result.kill = 4.5; result.depthTo = 5.5
  result.f.clumpR = 5.2; result.f.leafLen = 2.8; result.f.leafWid = 1.2; result.f.leafTh = 0.6
  result.f.leafShape = lsHeart; result.f.leavesPerArea = 0.3; result.f.spacing = 1.15
  result.f.clumpH = 0.4; result.f.droop = 0.6; result.f.sizeVar = 0.35; result.f.wideness = 1.0
  result.f.holes = 6; result.f.holeR = 0.22; result.f.thinBelow = 0.2
  if stems > 1:
    result.stems = @[(vec3(-3, 0, 0), vec3(-16, 70, 4)), (vec3(2, 0, 1), vec3(6, 80, -3)), (vec3(3, 0, -1), vec3(22, 62, 2))]
    result.crownR = vec3(55, 60, 40); result.crownC = vec3(2, 116, 0); result.trunkR = 3.4; result.points = 1500

proc birch*(seed: int, leafy: bool, stems = 1): Tree = birchDef(seed, leafy, stems).grow()

proc willow*(seed: int, leafy: bool, k = 1.0): Tree =
  var b = broad(seed)
  b.leafy = leafy
  b.crownBase = 36; b.crownC = vec3(0, 100, 0); b.crownR = vec3(70, 44, 64)
  b.trunkR = 8; b.points = 1100; b.texAmp = 0.6; b.trop = vec3(0, 0.1, 0); b.wobble = 0.2
  b.limbs = 4; b.limbRise = 0.75; b.limbReach = 0.55; b.twigs = 0; b.underOpen = 0.9
  b.f.clumpR = 6; b.f.leafShape = lsLance; b.f.leafLen = 3.4; b.f.leafWid = 0.7; b.f.leafTh = 0.5
  b.f.leavesPerArea = 0.45; b.f.droop = 0.85; b.f.spacing = 1.0; b.f.clumpH = 0.35; b.f.thinBelow = 0.0
  b.f.holes = 0
  if k != 1.0: b = b.scaled(k)
  b.grow(weeping(int(800 * k), 40 * k, 95 * k, leafy, 2.8))

proc elm*(seed: int, leafy: bool): Tree =
  var b = broad(seed)
  b.leafy = leafy
  b.crownBase = 34; b.crownC = vec3(0, 118, 0); b.crownR = vec3(74, 42, 66)
  b.trunkR = 7; b.points = 1500; b.trop = vec3(0, 0.2, 0); b.limbs = 4; b.limbRise = 1.0
  b.limbReach = 0.75; b.wobble = 0.14; b.underOpen = 0.95; b.shellIn = 0.4
  b.f.clumpR = 6.5; b.f.leafLen = 3.2; b.f.leafWid = 1.4; b.f.leafTh = 0.7; b.f.leavesPerArea = 0.22
  b.f.wideness = 1.25; b.f.holes = 3; b.f.thinBelow = 0.2
  b.grow()

proc poplar*(seed: int, leafy: bool): Tree =
  var b = broad(seed)
  b.leafy = leafy
  b.crownBase = 14; b.crownC = vec3(0, 104, 0); b.crownR = vec3(19, 88, 19)
  b.trunkR = 5; b.points = 1300; b.trop = vec3(0, 0.55, 0); b.limbs = 0; b.wobble = 0.1
  b.influence = 15; b.kill = 4; b.step = 2.2; b.lumps = 18; b.lumpR = 0.35; b.shellIn = 0.15
  b.underOpen = 0.2; b.twigUp = 0.5; b.twigSpread = 0.35; b.depthTo = 5
  b.f.clumpR = 4.6; b.f.leafLen = 2.5; b.f.leafWid = 1.2; b.f.leafTh = 0.55; b.f.leafShape = lsHeart
  b.f.leavesPerArea = 0.3; b.f.spacing = 0.85; b.f.wideness = 0.9; b.f.thinBelow = 0.0; b.f.droop = 0.3
  b.grow()

proc appleTree*(seed: int, blossom: bool): Tree =
  var b = broad(seed)
  b.crownBase = 30; b.crownC = vec3(0, 72, 0); b.crownR = vec3(56, 36, 50)
  b.trunkR = 5.5; b.points = 1000; b.wobble = 0.28; b.trop = vec3(0, 0.05, 0); b.limbs = 3
  b.limbRise = 0.6; b.limbReach = 0.55; b.depthTo = 6; b.influence = 18
  b.f.clumpR = 6; b.f.leafLen = 3.2; b.f.leafWid = 1.5; b.f.leafTh = 0.7; b.f.leavesPerArea = 0.22
  b.f.holes = 3; b.f.thinBelow = 0.3
  if blossom:
    b.f.flowerShare = 0.55; b.f.flowerLen = 1.7
    b.grow()
  else:
    b.grow(fruit(38, 2.6))

proc cherryBlossom*(seed: int): Tree =
  var b = broad(seed)
  b.crownBase = 34; b.crownC = vec3(0, 90, 0); b.crownR = vec3(74, 40, 64)
  b.trunkR = 6.5; b.points = 1500; b.wobble = 0.3; b.trop = vec3(0, 0.03, 0); b.limbs = 3
  b.limbRise = 0.55; b.limbReach = 0.7; b.tex = txBirch; b.texAmp = 0.3; b.underOpen = 0.8
  b.f.clumpR = 6.5; b.f.leafLen = 2.4; b.f.leafWid = 1.0; b.f.leafTh = 0.6; b.f.leavesPerArea = 0.42
  b.f.flowerShare = 0.85; b.f.flowerLen = 1.6; b.f.holes = 6; b.f.thinBelow = 0.2; b.f.wideness = 1.35
  b.f.spacing = 1.0
  b.grow()

proc beech*(seed: int): Tree =
  var b = broad(seed)
  b.crownBase = 26; b.crownC = vec3(0, 92, 0); b.crownR = vec3(70, 66, 62)
  b.trunkR = 8; b.points = 1900; b.tex = txSmooth; b.texAmp = 0; b.trop = vec3(0, 0.1, 0)
  b.limbs = 4; b.limbRise = 0.6; b.underOpen = 0.3
  b.f.clumpR = 7.5; b.f.leafLen = 3.6; b.f.leafWid = 1.6; b.f.leafTh = 0.75; b.f.leavesPerArea = 0.2
  b.f.wideness = 1.4; b.f.holes = 4; b.f.thinBelow = 0.6; b.f.droop = 0.5
  b.grow()

proc olive*(seed: int): Tree =
  var b = broad(seed)
  b.stems = @[(vec3(-3, 0, 0), vec3(-20, 46, 8)), (vec3(3, 0, -1), vec3(18, 42, -6))]
  b.crownC = vec3(0, 68, 0); b.crownR = vec3(58, 32, 50); b.trunkR = 5.0; b.points = 1300
  b.tex = txFibre; b.texAmp = 0.55; b.wobble = 0.35; b.trop = vec3(0, 0.0, 0); b.influence = 17
  b.depthTo = 6; b.underOpen = 0.3
  b.f.clumpR = 5.2; b.f.leafShape = lsLance; b.f.leafLen = 3.0; b.f.leafWid = 0.55; b.f.leafTh = 0.5
  b.f.leavesPerArea = 0.55; b.f.spacing = 1.1; b.f.holes = 7; b.f.holeR = 0.24; b.f.droop = 0.15
  b.f.wideness = 1.3
  b.grow()

proc acacia*(seed: int, k = 1.0): Tree =
  var b = broad(seed)
  b.crownBase = 30; b.crownC = vec3(0, 108, 0); b.crownR = vec3(92, 13, 74)
  b.trunkR = 6; b.points = 1300; b.wobble = 0.22; b.trop = vec3(0, 0.12, 0); b.limbs = 4
  b.limbRise = 0.85; b.limbReach = 0.6; b.lumps = 10; b.lumpR = 0.55; b.shellIn = 0.0
  b.underOpen = 0.0; b.influence = 24; b.depthTo = 6; b.texAmp = 0.5
  b.f.clumpR = 8; b.f.clumpH = 0.28; b.f.wideness = 2.0; b.f.leafShape = lsRound; b.f.leafLen = 1.8
  b.f.leafWid = 0.9; b.f.leafTh = 0.55; b.f.leavesPerArea = 0.55; b.f.spacing = 0.9; b.f.droop = 0.0
  b.f.thinBelow = 0.0; b.f.outward = 0.0
  if k != 1.0: b = b.scaled(k)
  b.grow()

proc baobab*(seed: int, leafy: bool): Tree =
  var rng = initRand(seed)
  var t: Tree
  t.base = 0.8; t.depthTo = 6
  # the bottle-shaped trunk, swelling in the middle and drawn in under the crown
  let topY = 72.0
  var prev = vec3(0, -2, 0)
  var y = 0.0
  while y < topY:
    let ny = min(topY, y + 3)
    let r0 = 21 + 5 * sin(PI * clamp(y / topY, 0, 1) * 0.8) - 9 * smoothstep(0.55, 1.0, y / topY)
    let r1 = 21 + 5 * sin(PI * clamp(ny / topY, 0, 1) * 0.8) - 9 * smoothstep(0.55, 1.0, ny / topY)
    let nxt = vec3(0, ny, 0)
    t.tube(prev, nxt, r0, r1, txFibre, 0.7, y, 0.62, 3)
    prev = nxt; y = ny
  var s: Skeleton
  let c = vec3(0, 96, 0); let r = vec3(58, 24, 50)
  discard s.addNode(vec3(0, topY - 6, 0), -1)
  for k in 0 ..< 5:
    let az = float(k) / 5 * 2 * PI + rng.rnd(-0.4, 0.4)
    discard s.stem(rng, vec3(0, topY - 6, 0), vec3(cos(az) * 24, topY + 10, sin(az) * 20), 2.6, 0.3, 0)
  let env = lumpy(rng, c, r, 8, 0.5, false)
  var pts = scatter(rng, env, c - r * 1.3, c + r * 1.3, 500)
  s.colonise(rng, pts, 2.8, 22, 6, vec3(0, 0.15, 0), 0.35, growFrom = 1)
  s.smooth(2)
  if not leafy:
    s.computeRadii(0.45, 2.3, 11)
    s.addTwigs(rng, 1, 4, 0.7)
  s.computeRadii(0.45, 2.3, 11)
  s.toTubes(t, txFibre, 0.5, 0.7, 5)
  if leafy:
    var f = defaultFoliage()
    f.clumpR = 5.5; f.leafShape = lsPalmate; f.leafLen = 2.8; f.leafWid = 1.4; f.leafTh = 0.6
    f.leavesPerArea = 0.18; f.spacing = 1.3; f.droop = 0.3
    s.foliage(t, rng, f, c, r)
  t

proc deadTree*(seed: int): Tree =
  var b = oakDef(seed, false)
  b.crownBase = 52; b.crownC = vec3(0, 100, 0); b.crownR = vec3(60, 50, 50)
  b.points = 900; b.twigs = 0; b.wobble = 0.35; b.influence = 26; b.kill = 7; b.texAmp = 0.8
  b.tipR = 0.6; b.limbs = 3; b.points = 1300; b.twigs = 1; b.twigLen = 6; b.twigSpread = 0.8
  b.grow(pruneShare = 0.05)

proc sapling*(seed: int): Tree =
  var b = mapleDef(seed, true)
  b.crownBase = 26; b.crownC = vec3(0, 50, 0); b.crownR = vec3(20, 22, 18); b.trunkR = 1.8
  b.points = 300; b.step = 1.6; b.influence = 10; b.kill = 3; b.limbs = 0; b.roots = 0; b.texAmp = 0
  b.depthTo = 3.5; b.tipR = 0.25
  b.f.clumpR = 4.2; b.f.leafShape = lsOval; b.f.leafLen = 2.6; b.f.leafWid = 1.2; b.f.leafTh = 0.55
  b.f.leavesPerArea = 0.3; b.f.holes = 1; b.f.thinBelow = 0.2
  b.grow()
