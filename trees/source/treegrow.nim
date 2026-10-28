## Branch skeletons: space colonisation in 3D (branches grow towards points scattered through
## the crown's shape), pipe-model radii, and turning a skeleton into tubes, twigs and foliage.

import std/[math, random, tables]
import core/vec
import treecore

type
  Node* = object
    p*: Vec3
    parent*: int
    r*: float
    kids*: seq[int]
    u*: float              ## length from the root
    order*: int            ## 0 on a stem, +1 at every side branch

  Skeleton* = object
    nodes*: seq[Node]

  Envelope* = proc (p: Vec3): bool

proc key(p: Vec3, s: float): (int, int, int) =
  (int(floor(p.x / s)), int(floor(p.y / s)), int(floor(p.z / s)))

proc addNode*(s: var Skeleton, p: Vec3, parent: int): int =
  s.nodes.add Node(p: p, parent: parent)
  result = s.nodes.len - 1
  if parent >= 0: s.nodes[parent].kids.add result

proc stem*(s: var Skeleton, rng: var Rand, base, top: Vec3, step: float, wobble = 0.15, parent = -1): int =
  ## A chain of nodes from base to top; returns the last one.
  var prev = if parent >= 0: parent else: s.addNode(base, -1)
  let n = max(1, int(dist(base, top) / step))
  for i in 1 .. n:
    let t = float(i) / float(n)
    var p = lerp(base, top, t)
    # a gentle, smooth sway rather than a kink at every node
    let ph = float(s.nodes.len) * 0.37
    if i < n: p += vec3(noise(t * 2.5, ph, 3), 0, noise(t * 2.5, ph, 4)) * wobble * step * 6
    prev = s.addNode(p, prev)
  prev

proc colonise*(s: var Skeleton, rng: var Rand, pts: var seq[Vec3], step, influence, kill: float,
               tropism: Vec3, wobble = 0.1, maxIter = 400, growFrom = 0) =
  ## Grows the skeleton towards the attraction points until none are left near a branch.
  var grid = initTable[(int, int, int), seq[int]]()
  for i in growFrom ..< s.nodes.len:
    grid.mgetOrPut(key(s.nodes[i].p, influence), @[]).add i
  var alive = newSeq[bool](pts.len)
  for i in 0 ..< pts.len: alive[i] = true
  var seek = 60
  var grownAny = false   # only the trunk reaching for the crown may stretch; later strays stay put
  for iter in 0 ..< maxIter:
    var sums = initTable[int, Vec3]()
    var any = false
    for pi in 0 ..< pts.len:
      if not alive[pi]: continue
      let p = pts[pi]
      let (kx, ky, kz) = key(p, influence)
      var best = -1; var bd = influence
      for i in -1 .. 1:
        for j in -1 .. 1:
          for k in -1 .. 1:
            let cellp = grid.getOrDefault((kx + i, ky + j, kz + k))
            for ni in cellp:
              let d = dist(s.nodes[ni].p, p)
              if d < bd: bd = d; best = ni
      if best < 0: continue
      if bd < kill:
        alive[pi] = false
        continue
      any = true
      let d = (p - s.nodes[best].p) / max(bd, 1e-9)
      sums[best] = sums.getOrDefault(best) + d
    if not any:
      # nothing in reach: stretch the nearest branch towards the nearest point left
      var bp = -1; var bn = -1; var bd2 = 1e18
      for pi in 0 ..< pts.len:
        if not alive[pi]: continue
        for ni in growFrom ..< s.nodes.len:
          let d = (pts[pi] - s.nodes[ni].p).len2
          if d < bd2: bd2 = d; bp = pi; bn = ni
      if bp < 0 or seek <= 0 or grownAny: break
      dec seek
      let np = s.nodes[bn].p + (pts[bp] - s.nodes[bn].p).normalized * step
      let id = s.addNode(np, bn)
      grid.mgetOrPut(key(np, influence), @[]).add id
      continue
    var grew = 0
    for ni, sum in sums:
      if sum.len < 1e-6: continue
      var dir = sum.normalized + tropism + rng.randDir * wobble
      dir = dir.normalized
      let np = s.nodes[ni].p + dir * step
      # two pulls that cancel out make a node grow back on itself; skip those
      var dup = false
      for k in s.nodes[ni].kids:
        if dist(s.nodes[k].p, np) < step * 0.3: dup = true
      if dup: continue
      let id = s.addNode(np, ni)
      grid.mgetOrPut(key(np, influence), @[]).add id
      inc grew
    if grew == 0: break
    grownAny = true
  pts.setLen(0)

proc smooth*(s: var Skeleton, passes = 3) =
  for pass in 0 ..< passes:
    var np = newSeq[Vec3](s.nodes.len)
    for i, n in s.nodes:
      np[i] = n.p
      if n.parent >= 0 and n.kids.len == 1:
        np[i] = n.p * 0.5 + (s.nodes[n.parent].p + s.nodes[n.kids[0]].p) * 0.25
    for i in 0 ..< s.nodes.len: s.nodes[i].p = np[i]

proc computeRadii*(s: var Skeleton, tipR: float, expo = 2.4, baseR = 0.0) =
  ## Pipe model: a branch's cross-section feeds those of its children.
  var acc = newSeq[float](s.nodes.len)
  for i in countdown(s.nodes.len - 1, 0):
    if s.nodes[i].kids.len == 0: acc[i] += pow(tipR, expo)
    if s.nodes[i].parent >= 0: acc[s.nodes[i].parent] += acc[i]
  for i in 0 ..< s.nodes.len: s.nodes[i].r = pow(acc[i], 1 / expo)
  if baseR > 0:
    var top = 0.0
    for n in s.nodes:
      if n.parent < 0: top = max(top, n.r)
    # keep the twig ends at tipR and stretch the rest so the trunk comes out at baseR
    let g = ln(baseR / tipR) / ln(max(top / tipR, 1.0001))
    for i in 0 ..< s.nodes.len: s.nodes[i].r = tipR * pow(max(s.nodes[i].r / tipR, 1.0), g)
  for i in 0 ..< s.nodes.len:
    let n = s.nodes[i]
    if n.parent >= 0:
      s.nodes[i].u = s.nodes[n.parent].u + dist(n.p, s.nodes[n.parent].p)
  # side branches: every child but the thickest starts a new order
  for i in 0 ..< s.nodes.len:
    let n = s.nodes[i]
    var big = -1; var br = -1.0
    for k in n.kids:
      if s.nodes[k].r > br: br = s.nodes[k].r; big = k
    for k in n.kids:
      s.nodes[k].order = n.order + (if k == big: 0 else: 1)

proc isTip*(s: Skeleton, i: int): bool = s.nodes[i].kids.len == 0

proc addTwigs*(s: var Skeleton, rng: var Rand, levels: int, len0: float, spread: float, gravity = 0.0,
               perTip = 2, up = 0.0) =
  ## Fine twigs off the tips for bare trees: each tip forks into smaller ones.
  var tips: seq[int]
  for i in 0 ..< s.nodes.len:
    if s.isTip(i) and s.nodes[i].parent >= 0: tips.add i
  var l = len0
  for lev in 0 ..< levels:
    var next: seq[int]
    for ti in tips:
      let n = s.nodes[ti]
      let d0 = (n.p - s.nodes[n.parent].p).normalized
      let cnt = if lev == 0: perTip + rng.rand(1) else: perTip
      for c in 0 ..< cnt:
        var d = (d0 + rng.randDir * spread + vec3(0, up - gravity, 0)).normalized
        let ll = l * rng.rnd(0.6, 1.2)
        let mid = n.p + d * ll * 0.5
        d = (d + vec3(0, -gravity * 0.5, 0)).normalized
        let a = s.addNode(mid, ti)
        let b = s.addNode(mid + d * ll * 0.5, a)
        next.add b
    tips = next
    l *= 0.7

proc toTubes*(s: Skeleton, t: var Tree, tex: Tex, texAmp: float, flat = 0.75, seed = 0.0,
              minR = 0.0, texMinR = 1.2) =
  for i, n in s.nodes:
    if n.parent < 0: continue
    let par = s.nodes[n.parent]
    # the thickest child carries on the parent's taper; side branches start a little fuller
    var big = -1; var br = -1.0
    for k in par.kids:
      if s.nodes[k].r > br: br = s.nodes[k].r; big = k
    # side branches start a little fuller; big limbs splitting off blend into the parent's width
    let ra = if big == i: par.r
             else: min(par.r, n.r * 1.15 + (par.r - n.r * 1.15) * 0.8 * smoothstep(0.3, 0.85, n.r / par.r))
    let rb = n.r
    if rb < minR: continue
    let amp = if rb > texMinR: texAmp * min(1.0, rb / (texMinR * 3)) else: 0.0
    t.tube(par.p, n.p, ra, rb, if amp > 0: tex else: txNone, amp, par.u, flat, seed)

proc rootFlare*(t: var Tree, rng: var Rand, r0: float, roots = 5, tex = txBark, texAmp = 0.4, spread = 2.6) =
  ## Buttress roots spreading from the foot of the trunk into the ground.
  t.tube(vec3(0, -r0 * 0.3, 0), vec3(0, r0 * 2.5, 0), r0 * 1.45, r0 * 1.0, tex, texAmp, 0, 0.75, 1)
  for k in 0 ..< roots:
    let az = float(k) / float(roots) * 2 * PI + rng.rnd(-0.4, 0.4)
    let reach = r0 * rng.rnd(spread * 0.7, spread * 1.1)
    let top = vec3(cos(az) * r0 * 0.4, r0 * rng.rnd(1.4, 2.4), sin(az) * r0 * 0.4)
    let mid = vec3(cos(az) * reach * 0.55, r0 * 0.35, sin(az) * reach * 0.55)
    let foot = vec3(cos(az) * reach, -r0 * 0.5, sin(az) * reach)
    t.tube(top, mid, r0 * 0.62, r0 * 0.42, tex, texAmp * 0.8, 0, 0.75, 2)
    t.tube(mid, foot, r0 * 0.42, r0 * 0.2, tex, texAmp * 0.5, 4, 0.75, 3)

# ---------------------------------------------------------------- envelopes and points
proc ellipsoid*(c, r: Vec3): Envelope =
  result = proc (p: Vec3): bool =
    ((p.x - c.x) / r.x) ^ 2 + ((p.y - c.y) / r.y) ^ 2 + ((p.z - c.z) / r.z) ^ 2 <= 1

proc lumpy*(rng: var Rand, c, r: Vec3, lumps: int, lumpR: float, flatTop = false): Envelope =
  ## A billowing crown: a core with round masses bulging out all over its surface, more on top.
  var cs: seq[(Vec3, float)]
  cs.add (c, 1 - lumpR * 0.9)
  for i in 0 ..< lumps:
    var d = rng.randDir
    if d.y < -0.3 and rng.rand(1.0) < 0.6: d.y = -d.y
    let s = lumpR * rng.rnd(0.75, 1.2)
    let reach = 1 - s * rng.rnd(0.7, 1.0)
    cs.add (vec3(c.x + d.x * r.x * reach, c.y + d.y * r.y * reach, c.z + d.z * r.z * reach), s)
  let rr = r
  result = proc (p: Vec3): bool =
    if flatTop and p.y > c.y + rr.y * 0.55: return false
    for (q, s) in cs:
      if ((p.x - q.x) / (rr.x * s)) ^ 2 + ((p.y - q.y) / (rr.y * s)) ^ 2 + ((p.z - q.z) / (rr.z * s)) ^ 2 <= 1:
        return true
    false

proc scatter*(rng: var Rand, env: Envelope, lo, hi: Vec3, n: int): seq[Vec3] =
  var tries = 0
  while result.len < n and tries < n * 400:
    inc tries
    let p = vec3(rng.rnd(lo.x, hi.x), rng.rnd(lo.y, hi.y), rng.rnd(lo.z, hi.z))
    if env(p): result.add p

# ---------------------------------------------------------------- foliage
type
  Foliage* = object
    clumpR*: float         ## clump radius
    clumpH*: float         ## clump dome height, as a share of the radius
    spacing*: float        ## clumps at least this many radii apart
    leafLen*, leafWid*, leafTh*: float
    leafShape*: LeafShape
    leavesPerArea*: float  ## leaves a square millimetre of clump
    droop*: float          ## how much leaves point down (0 .. 1)
    sizeVar*: float
    outward*: float        ## clump centres pushed out from the twig by this share of the radius
    minOrder*: int
    extra*: float          ## clumps also on nodes thinner than this radius (not only tips)
    wideness*: float       ## clumps this much wider than tall
    holes*: int            ## gaps through the crown where the limbs show
    holeR*: float          ## their radius, as a share of the crown's
    thinBelow*: float      ## clumps thin out under this share of the crown's height (0: no thinning)
    flowerShare*: float    ## share of the leaves that are blossoms instead
    flowerLen*: float

proc defaultFoliage*(): Foliage =
  Foliage(clumpR: 7, clumpH: 0.45, spacing: 0.7, leafLen: 3.2, leafWid: 1.2, leafTh: 0.55, leafShape: lsOval,
          leavesPerArea: 0.22, droop: 0.35, sizeVar: 0.3, outward: 0.3, minOrder: 0, extra: 0, wideness: 1.2, holes: 0, holeR: 0.15, thinBelow: 0, flowerShare: 0, flowerLen: 1.8)

proc leavesOn*(t: var Tree, rng: var Rand, d: int, f: Foliage, center: Vec2) =
  let p = t.prims[d]
  let area = PI * p.rx * p.ry
  let n = int(area * f.leavesPerArea)
  for k in 0 ..< n:
    # spread over the clump, a little past its edge so the outline is leafy
    let a = rng.rnd(0, 2 * PI)
    let rr = sqrt(rng.rand(1.0)) * 1.02
    let lp = p.c.xy + vec2(cos(a) * p.rx * rr, sin(a) * p.ry * rr)
    var outward = lp - p.c.xy
    if outward.len < 0.3: outward = lp - center
    var ang = arctan2(outward.y, outward.x)
    # leaves hang: pull the direction towards straight down
    let down = -PI / 2
    var dd = down - ang
    while dd > PI: dd -= 2 * PI
    while dd < -PI: dd += 2 * PI
    ang += dd * f.droop * rng.rnd(0.5, 1.0) + rng.gn * 0.25
    let sz = rng.rnd(0.8, 1.15)
    if f.flowerShare > 0 and rng.rand(1.0) < f.flowerShare:
      t.leaf(lp, d, 0, f.flowerLen * sz, f.flowerLen * sz, f.leafTh * 1.1, lsFlower, lift = rng.rnd(0, 1.0))
      continue
    let ln = f.leafLen * sz
    # leaves start at their stalk, so step back half a leaf
    let start = lp - vec2(cos(ang), sin(ang)) * ln * 0.45
    t.leaf(start, d, ang, ln, f.leafWid * sz, f.leafTh * rng.rnd(0.8, 1.1), f.leafShape,
           lift = rng.rnd(-0.15, 0.25) * f.leafTh)

proc foliage*(s: Skeleton, t: var Tree, rng: var Rand, f: Foliage, center: Vec3, crownR = vec3(0, 0, 0)): seq[int] {.discardable.} =
  ## Leaf clumps on the twig ends, kept apart so each reads as its own puff of leaves.
  var cand: seq[int]
  for i, n in s.nodes:
    if n.parent < 0 or n.order < f.minOrder: continue
    if s.isTip(i) or (f.extra > 0 and n.r < f.extra): cand.add i
  rng.shuffle(cand)
  var holes: seq[Vec3]
  for h in 0 ..< f.holes:
    # gaps sit in the front half, where they can be seen
    let d = vec3(rng.rnd(-0.75, 0.75), rng.rnd(-0.7, 0.5), rng.rnd(0.35, 0.9))
    holes.add vec3(center.x + d.x * crownR.x, center.y + d.y * crownR.y, center.z + d.z * crownR.z)
  var placed: seq[Vec3]
  var grid = initTable[(int, int, int), seq[int]]()
  let minD = f.clumpR * f.spacing
  for i in cand:
    let n = s.nodes[i]
    var outv = n.p - center
    outv = if outv.len > 1e-6: outv.normalized else: vec3(0, 1, 0)
    let c = n.p + outv * f.clumpR * f.outward
    var inHole = false
    for h in holes:
      let hr = f.holeR * crownR.x
      if sq((c.x - h.x) / hr) + sq((c.y - h.y) / (hr * 0.8)) + sq((c.z - h.z) / (hr * 1.6)) < 1: inHole = true
    if inHole: continue
    if f.thinBelow > 0 and crownR.y > 0:
      let below = (center.y - crownR.y * f.thinBelow - c.y) / (crownR.y * 0.5)
      if below > 0 and rng.rand(1.0) < min(0.85, below): continue
    let (kx, ky, kz) = key(c, minD)
    var near = false
    for a in -1 .. 1:
      for b in -1 .. 1:
        for e in -1 .. 1:
          for j in grid.getOrDefault((kx + a, ky + b, kz + e)):
            if dist(placed[j], c) < minD: near = true
    if near: continue
    grid.mgetOrPut((kx, ky, kz), @[]).add placed.len
    placed.add c
    let r = f.clumpR * rng.rnd(1 - f.sizeVar, 1 + f.sizeVar)
    let d = t.dome(c, r * f.wideness * rng.rnd(0.9, 1.1), r * rng.rnd(0.85, 1.0) / f.wideness, r * f.clumpH, rng.rnd(-0.3, 0.3), 0.5)
    t.leavesOn(rng, d, f, center.xy)
    result.add d

proc scatterW*(rng: var Rand, env: Envelope, weight: proc (p: Vec3): float, lo, hi: Vec3, n: int): seq[Vec3] =
  var tries = 0
  while result.len < n and tries < n * 600:
    inc tries
    let p = vec3(rng.rnd(lo.x, hi.x), rng.rnd(lo.y, hi.y), rng.rnd(lo.z, hi.z))
    if env(p) and rng.rand(1.0) < weight(p): result.add p

proc prune*(s: var Skeleton, rng: var Rand, share: float, minOrder: int, maxR: float, minR = 0.0) =
  ## Breaks branches off: drops every node past a cut, keeping the radii, so the stubs end blunt.
  var dead = newSeq[bool](s.nodes.len)
  for i in 1 ..< s.nodes.len:
    let n = s.nodes[i]
    if n.parent >= 0 and dead[n.parent]: dead[i] = true; continue
    if n.order >= minOrder and n.r <= maxR and n.r >= minR and n.parent >= 0 and
       s.nodes[n.parent].order == n.order and rng.rand(1.0) < share:
      dead[i] = true
  var remap = newSeq[int](s.nodes.len)
  var kept: seq[Node]
  for i, n in s.nodes:
    if dead[i]: remap[i] = -1; continue
    remap[i] = kept.len
    var m = n
    m.parent = if n.parent >= 0: remap[n.parent] else: -1
    m.kids = @[]
    kept.add m
  for i in 0 ..< kept.len:
    if kept[i].parent >= 0: kept[kept[i].parent].kids.add i
  s.nodes = kept

proc curvedStem*(s: var Skeleton, rng: var Rand, parent: int, goal: Vec3, step: float, rise: float, wobble = 0.2): int =
  ## A limb that leaves its parent rising and bends out towards the goal.
  let a = s.nodes[parent].p
  let ctrl = a + vec3((goal.x - a.x) * 0.25, dist(a, goal) * rise, (goal.z - a.z) * 0.25)
  let n = max(2, int(dist(a, goal) * 1.2 / step))
  var prev = parent
  for i in 1 .. n:
    let t = float(i) / float(n)
    var p = a * sq(1 - t) + ctrl * (2 * t * (1 - t)) + goal * sq(t)
    if i < n: p += vec3(rng.gn * wobble * step, rng.gn * wobble * step * 0.5, rng.gn * wobble * step)
    prev = s.addNode(p, prev)
  prev
