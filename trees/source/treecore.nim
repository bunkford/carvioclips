## Core of the tree relief generator: a list of 3D primitives (branch tubes, foliage domes,
## leaves) projected onto a side-view height field. Each primitive keeps its own rounded
## profile and sits at a height set by how near the viewer it is (depth squeezed into a few
## millimetres, as a relief carver does), and the field takes the highest of them.
##
## Lengths are millimetres: x right, y up, z (depth) towards the viewer.

import std/[math, random, algorithm]
import core/vec

type
  Tex* = enum txNone, txBark, txSmooth, txBirch, txRings, txPlates, txFibre, txSnow
  LeafShape* = enum lsOval, lsLance, lsPalmate, lsFlower, lsRound, lsScale, lsHeart
  PrimKind* = enum pkTube, pkDome, pkLeaf

  Prim* = object
    case kind*: PrimKind
    of pkTube:
      a*, b*: Vec3
      ra*, rb*: float
      flat*: float          ## profile height as a share of the radius
      tex*: Tex
      texAmp*: float
      u0*: float            ## length along the branch at `a`, so bark runs on across joints
      seed*: float
      sharp*: float         ## 0: round tube; 1: ridge (a blade, as for leaflets)
    of pkDome:
      c*: Vec3
      rx*, ry*: float
      rot*: float
      h*: float
      pw*: float            ## profile power: 0.5 is a half ellipse, 1 a paraboloid
      dtex*: Tex
    of pkLeaf:
      p*: Vec2
      dome*: int            ## the dome it lies on (-1: on its own, at depth `ld`)
      ld*: float
      ang*: float
      ln*, wd*, th*: float
      shape*: LeafShape
      lift*: float          ## the tip stands this much higher than the base

  Tree* = object
    prims*: seq[Prim]
    depthTo*: float         ## relief height the depth range is squeezed into
    base*: float            ## height of the furthest part
    cell*: float

  Field* = object
    w*, h*: int
    cell*: float
    origin*: Vec2
    z*: seq[float32]

# ---------------------------------------------------------------- noise
proc hash2(ix, iy: int, s: int): float =
  var h = uint32(ix * 374761393 + iy * 668265263 + s * 2147483647)
  h = (h xor (h shr 13)) * 1274126177'u32
  h = h xor (h shr 16)
  float(h and 0xffffff) / float(0xffffff)

proc grad2(ix, iy, s: int, x, y: float): float =
  let a = hash2(ix, iy, s) * 2 * PI
  cos(a) * x + sin(a) * y

proc fade(t: float): float {.inline.} = t * t * t * (t * (t * 6 - 15) + 10)

proc noise*(x, y: float, s = 0): float =
  ## Gradient noise, about -0.7 .. 0.7.
  let ix = int(floor(x)); let iy = int(floor(y))
  let fx = x - float(ix); let fy = y - float(iy)
  let u = fade(fx); let v = fade(fy)
  let n00 = grad2(ix, iy, s, fx, fy)
  let n10 = grad2(ix + 1, iy, s, fx - 1, fy)
  let n01 = grad2(ix, iy + 1, s, fx, fy - 1)
  let n11 = grad2(ix + 1, iy + 1, s, fx - 1, fy - 1)
  let a = n00 + (n10 - n00) * u
  let b = n01 + (n11 - n01) * u
  a + (b - a) * v

proc fbm*(x, y: float, oct = 4, s = 0): float =
  var amp = 0.5; var f = 1.0
  for i in 0 ..< oct:
    result += amp * noise(x * f, y * f, s + i * 17)
    amp *= 0.5; f *= 2.03

proc sq*(x: float): float {.inline.} = x * x


proc cellNoise(x, y: float, s: int): (float, float) =
  ## Distances to the nearest and second nearest feature point (Worley noise).
  let ix = int(floor(x)); let iy = int(floor(y))
  var d1 = 9.0; var d2 = 9.0
  for j in -1 .. 1:
    for i in -1 .. 1:
      let cx = float(ix + i) + hash2(ix + i, iy + j, s)
      let cy = float(iy + j) + hash2(ix + i, iy + j, s + 91)
      let d = sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
      if d < d1: d2 = d1; d1 = d
      elif d < d2: d2 = d
  (d1, d2)

# ---------------------------------------------------------------- helpers
proc rnd*(r: var Rand, a, b: float): float = r.rand(1.0) * (b - a) + a
proc gn*(r: var Rand): float =
  let u = max(1e-9, r.rand(1.0)); let v = r.rand(1.0)
  sqrt(-2 * ln(u)) * cos(2 * PI * v)
proc randDir*(r: var Rand): Vec3 =
  while true:
    let v = vec3(r.rnd(-1, 1), r.rnd(-1, 1), r.rnd(-1, 1))
    let l = v.len
    if l > 0.05 and l <= 1: return v / l

proc tube*(t: var Tree, a, b: Vec3, ra, rb: float, tex = txNone, texAmp = 0.0, u0 = 0.0,
           flat = 0.75, seed = 0.0, sharp = 0.0) =
  t.prims.add Prim(kind: pkTube, a: a, b: b, ra: ra, rb: rb, flat: flat, tex: tex, texAmp: texAmp,
                   u0: u0, seed: seed, sharp: sharp)

proc dome*(t: var Tree, c: Vec3, rx, ry: float, h: float, rot = 0.0, pw = 0.5, tex = txNone): int =
  t.prims.add Prim(kind: pkDome, c: c, rx: rx, ry: ry, h: h, rot: rot, pw: pw, dtex: tex)
  t.prims.len - 1

proc leaf*(t: var Tree, p: Vec2, dome: int, ang, ln, wd, th: float, shape = lsOval, lift = 0.0, depth = 0.0) =
  t.prims.add Prim(kind: pkLeaf, p: p, dome: dome, ang: ang, ln: ln, wd: wd, th: th, shape: shape, lift: lift, ld: depth)

proc polyTube*(t: var Tree, pts: seq[Vec3], r0, r1: float, tex = txNone, texAmp = 0.0, flat = 0.75,
               seed = 0.0, sharp = 0.0, taperPow = 1.0) =
  ## A tapering tube along a path.
  var total = 0.0
  for i in 1 ..< pts.len: total += dist(pts[i - 1], pts[i])
  var acc = 0.0
  for i in 1 ..< pts.len:
    let l = dist(pts[i - 1], pts[i])
    let ta = pow(acc / max(total, 1e-9), taperPow)
    let tb = pow((acc + l) / max(total, 1e-9), taperPow)
    t.tube(pts[i - 1], pts[i], r0 + (r1 - r0) * ta, r0 + (r1 - r0) * tb, tex, texAmp, acc, flat, seed, sharp)
    acc += l

# ---------------------------------------------------------------- rendering
proc bounds2(p: Prim): (Vec2, Vec2) =
  case p.kind
  of pkTube:
    let r = max(p.ra, p.rb)
    (minv(p.a.xy, p.b.xy) - vec2(r), maxv(p.a.xy, p.b.xy) + vec2(r))
  of pkDome:
    let r = max(p.rx, p.ry)
    (p.c.xy - vec2(r), p.c.xy + vec2(r))
  of pkLeaf:
    let r = p.ln * 1.05
    (p.p - vec2(r), p.p + vec2(r))

proc depthOf(p: Prim, t: Tree): (float, float) =
  case p.kind
  of pkTube: (min(p.a.z, p.b.z), max(p.a.z, p.b.z))
  of pkDome: (p.c.z, p.c.z)
  of pkLeaf:
    if p.dome >= 0: (t.prims[p.dome].c.z, t.prims[p.dome].c.z) else: (p.ld, p.ld)

proc domeAt(p: Prim, x, y: float, zc: float): float =
  ## Height of a dome at (x, y), or its base height outside it.
  let dx = x - p.c.x; let dy = y - p.c.y
  let cr = cos(p.rot); let sr = sin(p.rot)
  let u = (dx * cr + dy * sr) / p.rx
  let v = (-dx * sr + dy * cr) / p.ry
  let q = u * u + v * v
  if q >= 1: return zc
  zc + p.h * pow(1 - q, p.pw)

proc barkTex(tex: Tex, s, u, r, amp, seed: float): float =
  ## Bark relief (<= 0, carved in) at `s` mm round the trunk from its middle, `u` mm along it.
  case tex
  of txBark:
    # long furrows winding up the trunk, broken across now and then
    let sp = 2.4
    let w = s / sp + 0.9 * noise(u / 11 + seed, s / 9, 3) + 0.3 * noise(u / 3.5, s / 3 + seed, 5)
    let ridge = abs(sin(PI * w))
    let crack = smoothstep(0.55, 0.75, noise(u / 4.5 + seed * 3, s / 1.6, 7) + 0.35)
    -amp * (1 - pow(ridge, 0.45)) - amp * 0.5 * crack * (1 - ridge)
  of txPlates:
    let (d1, d2) = cellNoise(s / 2.6, u / 4.2 + seed, 11)
    -amp * (1 - smoothstep(0.0, 0.16, d2 - d1))
  of txBirch:
    # smooth with short dark dashes across the trunk and the odd rough patch
    let row = floor(u / 2.6)
    let off = hash2(int(row), 3, int(seed * 13))
    let cu = (row + 0.3 + 0.4 * off) * 2.6
    let dash = smoothstep(0.32, 0.12, abs(u - cu)) *
               smoothstep(0.1, 0.25, noise(s / 2.2 + row * 7.3, row, 4) + 0.05)
    let rough = smoothstep(0.25, 0.45, noise(s / 5 + seed, u / 7, 9)) * (0.5 + 0.5 * noise(s * 1.7, u * 1.7, 2))
    -amp * dash - amp * 0.6 * rough
  of txRings:
    let fr = (u / 3.2 + 0.15 * noise(s / 4, u / 9 + seed, 6)) mod 1.0
    -amp * (1 - pow(fr, 0.6)) + 0.25 * amp * noise(s / 1.2, u / 0.8, 8)
  of txFibre:
    -amp * (0.5 + 0.5 * sin(s / 0.55 + 2.5 * noise(u / 3, s / 4 + seed, 2))) * (0.6 + 0.4 * noise(u / 1.3, s, 3))
  else: 0.0

proc leafShapeHalf(shape: LeafShape, u: float): float =
  ## Half-width (share of the widest) at u (0 base .. 1 tip).
  case shape
  of lsOval: pow(max(0.0, sin(PI * u)), 0.7) * (1 - 0.15 * u)
  of lsLance: pow(max(0.0, sin(PI * pow(u, 0.8))), 1.1)
  of lsRound: pow(max(0.0, sin(PI * u)), 0.5)
  of lsHeart: pow(max(0.0, sin(PI * u)), 0.55) * (1 - 0.35 * u * u) + 0.3 * smoothstep(0.25, 0.0, u)
  of lsScale: pow(max(0.0, sin(PI * u)), 0.6)
  else: pow(max(0.0, sin(PI * u)), 0.7)

proc render*(t: Tree, cell: float, clipBottom = true, margin = 1.0): Field =
  var lo = vec2(1e9, 1e9); var hi = vec2(-1e9, -1e9)
  var dmin = 1e9; var dmax = -1e9
  for p in t.prims:
    let (a, b) = p.bounds2
    lo = minv(lo, a); hi = maxv(hi, b)
    let (d0, d1) = p.depthOf(t)
    dmin = min(dmin, d0); dmax = max(dmax, d1)
  if clipBottom: lo.y = max(lo.y, 0.0)
  lo = lo - vec2(margin, if clipBottom: 0.0 else: margin)
  hi = hi + vec2(margin)
  result.cell = cell
  result.origin = lo
  result.w = int(ceil((hi.x - lo.x) / cell))
  result.h = int(ceil((hi.y - lo.y) / cell))
  result.z = newSeq[float32](result.w * result.h)
  let k = if dmax > dmin: t.depthTo / (dmax - dmin) else: 0.0
  template zOf(d: float): float = t.base + (d - dmin) * k
  for pi, p in t.prims:
    let (a, b) = p.bounds2
    let x0 = max(0, int(floor((a.x - lo.x) / cell)))
    let x1 = min(result.w - 1, int(ceil((b.x - lo.x) / cell)))
    let y0 = max(0, int(floor((a.y - lo.y) / cell)))
    let y1 = min(result.h - 1, int(ceil((b.y - lo.y) / cell)))
    if x1 < x0 or y1 < y0: continue
    case p.kind
    of pkTube:
      let a2 = p.a.xy; let b2 = p.b.xy
      let ab = b2 - a2
      let l2 = ab.len2
      let l = sqrt(l2)
      let dir = if l > 1e-9: ab / l else: vec2(0, 1)
      let za = zOf(p.a.z); let zb = zOf(p.b.z)
      for iy in y0 .. y1:
        let y = lo.y + (float(iy) + 0.5) * cell
        for ix in x0 .. x1:
          let x = lo.x + (float(ix) + 0.5) * cell
          let ap = vec2(x, y) - a2
          let tt = if l2 > 1e-12: clamp(dot(ap, ab) / l2, 0.0, 1.0) else: 0.0
          let r = p.ra + (p.rb - p.ra) * tt
          if r <= 0: continue
          let q = ap - ab * tt
          let d = q.len
          if d >= r: continue
          let sgn = if cross(dir, q) >= 0: 1.0 else: -1.0
          let v = d / r
          var prof = if p.sharp > 0: (1 - p.sharp) * sqrt(1 - v * v) + p.sharp * (1 - v) * (1 + 0.4 * v)
                     else: sqrt(1 - v * v)
          # thick trunks would stand far too proud: squeeze their roundness past 4 mm
          var ph = r * p.flat
          if ph > 4: ph = 4 + (ph - 4) * 0.3
          var hgt = zOf(p.a.z + (p.b.z - p.a.z) * tt) + ph * prof
          if p.tex != txNone and p.texAmp > 0:
            # measured square to the tube's axis line (not from its end), so the round ends of
            # joined tubes carry the bark straight on instead of in rings
            let vl = clamp(cross(dir, ap) / r, -1.0, 1.0)
            let s = arcsin(vl) * r
            # unclamped along the tube, so the round ends of two joined tubes carry the same bark
            let u = p.u0 + (if l2 > 1e-12: dot(ap, ab) / l2 else: 0.0) * l
            # the texture fades out round the sides, where the tube turns away
            hgt += barkTex(p.tex, s, u, r, p.texAmp, p.seed) * (1 - pow(v, 6))
          let i = iy * result.w + ix
          if hgt > result.z[i]: result.z[i] = float32(hgt)
    of pkDome:
      let zc = zOf(p.c.z)
      for iy in y0 .. y1:
        let y = lo.y + (float(iy) + 0.5) * cell
        for ix in x0 .. x1:
          let x = lo.x + (float(ix) + 0.5) * cell
          let dx = x - p.c.x; let dy = y - p.c.y
          let cr = cos(p.rot); let sr = sin(p.rot)
          let u = (dx * cr + dy * sr) / p.rx
          let v = (-dx * sr + dy * cr) / p.ry
          let q = u * u + v * v
          if q >= 1: continue
          var hgt = zc + p.h * pow(1 - q, p.pw)
          if p.dtex == txSnow:
            hgt += 0.12 * p.h * noise(x / 3, y / 3, 5) * (1 - q)
          let i = iy * result.w + ix
          if hgt > result.z[i]: result.z[i] = float32(hgt)
    of pkLeaf:
      let ca = cos(p.ang); let sa = sin(p.ang)
      let dz = if p.dome >= 0: zOf(t.prims[p.dome].c.z) else: zOf(p.ld)
      # a leaf is a flat plate lying on its dome where its middle touches it, tilted with the dome
      var hc = dz; var gx = 0.0; var gy = 0.0
      if p.dome >= 0:
        let dm = t.prims[p.dome]
        let mid = p.p + vec2(ca, sa) * p.ln * 0.5
        let e = 0.3
        hc = domeAt(dm, mid.x, mid.y, dz)
        gx = (domeAt(dm, mid.x + e, mid.y, dz) - domeAt(dm, mid.x - e, mid.y, dz)) / (2 * e)
        gy = (domeAt(dm, mid.x, mid.y + e, dz) - domeAt(dm, mid.x, mid.y - e, dz)) / (2 * e)
        let gl = sqrt(gx * gx + gy * gy)
        if gl > 1.3: gx *= 1.3 / gl; gy *= 1.3 / gl
      for iy in y0 .. y1:
        let y = lo.y + (float(iy) + 0.5) * cell
        for ix in x0 .. x1:
          let x = lo.x + (float(ix) + 0.5) * cell
          let dx = x - p.p.x; let dy = y - p.p.y
          let u = dx * ca + dy * sa
          let v = -dx * sa + dy * ca
          var prof = -1.0
          var along = 0.0
          case p.shape
          of lsPalmate:
            # five lobes round the stalk end
            let r = sqrt(u * u + v * v)
            let th = arctan2(v, u)
            if abs(th) > 2.3: continue
            let lob = p.ln * (0.55 + 0.45 * pow(abs(cos(th * 2.0 / 0.95 * 0.5 * 2.5)), 0.6)) * (1 - 0.25 * abs(th) / 2.3)
            if r >= lob: continue
            prof = sqrt(1 - (r / lob) ^ 2) * (1 - 0.5 * exp(-sq(sin(th * 2.5) * r / (0.09 * p.ln))) * smoothstep(0.1 * p.ln, 0.3 * p.ln, r))
            along = r / p.ln
          of lsFlower:
            let r = sqrt(u * u + v * v)
            let th = arctan2(v, u)
            let pet = p.ln * (0.62 + 0.38 * cos(5 * th + p.lift * 10))
            if r >= pet: continue
            prof = pow(1 - r / pet, 0.5) * (0.75 + 0.25 * smoothstep(0.0, 0.3 * p.ln, r)) + 0.35 * exp(-sq(r / (0.18 * p.ln)))
            along = 0
          else:
            if u <= 0 or u >= p.ln: continue
            let uu = u / p.ln
            let hw = p.wd * leafShapeHalf(p.shape, uu)
            if abs(v) >= hw or hw <= 0: continue
            let vv = abs(v) / hw
            # a pillow: as high as it is wide, so the ends round off instead of standing as walls
            prof = pow(hw / p.wd, 0.8) * sqrt(1 - vv * vv) * (1 - 0.35 * exp(-sq(vv / 0.14)) * smoothstep(0.05, 0.25, uu) * smoothstep(1.0, 0.7, uu))
            along = uu
          if prof < 0: continue
          let mx = p.p.x + ca * p.ln * 0.5; let my = p.p.y + sa * p.ln * 0.5
          let base = max(dz, hc + gx * (x - mx) + gy * (y - my))
          let hgt = base + p.th * prof + p.lift * along
          let i = iy * result.w + ix
          if hgt > result.z[i]: result.z[i] = float32(hgt)

proc mask*(f: Field, eps = 0.02): seq[uint8] =
  result = newSeq[uint8](f.z.len)
  for i, v in f.z:
    if v > eps: result[i] = 1

proc softenEdges*(f: var Field) =
  ## One pass of a 3x3 blur over the tree only, to take the stair steps off sharp primitive edges.
  var o = f.z
  for y in 1 ..< f.h - 1:
    for x in 1 ..< f.w - 1:
      let i = y * f.w + x
      if f.z[i] <= 0: continue
      var s = 0.0; var n = 0.0
      for j in -1 .. 1:
        for k in -1 .. 1:
          let v = f.z[i + j * f.w + k]
          let wgt = (if j == 0 and k == 0: 4.0 elif j == 0 or k == 0: 2.0 else: 1.0)
          if v > 0: s += v * wgt; n += wgt
      o[i] = float32(s / n)
  f.z = o

proc maxHeight*(f: Field): float =
  for v in f.z: result = max(result, float(v))

proc quantise*(f: var Field, step = 1.0 / 256) =
  ## Rounds heights to `step`: invisible after carving, and the clip compresses far better.
  for v in f.z.mitems:
    if v > 0: v = float32(round(float(v) / step) * step)

proc limitSlope*(f: var Field, s: float, passes = 2) =
  ## Caps every wall at slope `s` (rise over run): the field becomes the highest surface under
  ## it that is no steeper than that. Thin twigs and leaf tips standing in front of something far
  ## behind them come down to a carvable height instead of standing as thin fins, and the
  ## outline gets a sloped wall a ball-nose can follow. Off the field's edge there is no limit,
  ## so the foot of the trunk keeps its square cut.
  let o = s * f.cell
  let d = s * f.cell * sqrt(2.0)
  let w = f.w; let h = f.h
  for pass in 0 ..< passes:
    for y in 0 ..< h:
      for x in 0 ..< w:
        let i = y * w + x
        var v = float(f.z[i])
        if x > 0: v = min(v, float(f.z[i - 1]) + o)
        if y > 0:
          v = min(v, float(f.z[i - w]) + o)
          if x > 0: v = min(v, float(f.z[i - w - 1]) + d)
          if x < w - 1: v = min(v, float(f.z[i - w + 1]) + d)
        f.z[i] = float32(v)
    for y in countdown(h - 1, 0):
      for x in countdown(w - 1, 0):
        let i = y * w + x
        var v = float(f.z[i])
        if x < w - 1: v = min(v, float(f.z[i + 1]) + o)
        if y < h - 1:
          v = min(v, float(f.z[i + w]) + o)
          if x < w - 1: v = min(v, float(f.z[i + w + 1]) + d)
          if x > 0: v = min(v, float(f.z[i + w - 1]) + d)
        f.z[i] = float32(v)

proc distToOutline*(f: Field, eps = 0.02): seq[float32] =
  ## Distance (mm) from each cell to the nearest empty cell; nothing below the field's bottom
  ## edge counts as empty, so the foot of the trunk stays square.
  let w = f.w; let h = f.h
  let big = 1e6'f32
  result = newSeq[float32](w * h)
  for i in 0 ..< w * h: result[i] = if f.z[i] > eps: big else: 0
  let o = float32(f.cell); let d = float32(f.cell * sqrt(2.0))
  for pass in 0 ..< 2:
    for y in 0 ..< h:
      for x in 0 ..< w:
        let i = y * w + x
        var v = result[i]
        if v == 0: continue
        if x > 0: v = min(v, result[i - 1] + o)
        if y > 0:
          v = min(v, result[i - w] + o)
          if x > 0: v = min(v, result[i - w - 1] + d)
          if x < w - 1: v = min(v, result[i - w + 1] + d)
        result[i] = v
    for y in countdown(h - 1, 0):
      for x in countdown(w - 1, 0):
        let i = y * w + x
        var v = result[i]
        if v == 0: continue
        if x < w - 1: v = min(v, result[i + 1] + o)
        if y < h - 1:
          v = min(v, result[i + w] + o)
          if x < w - 1: v = min(v, result[i + w + 1] + d)
          if x > 0: v = min(v, result[i + w - 1] + d)
        result[i] = v

proc sinkEdges*(f: var Field, reach: float, keep: float) =
  ## Lowers the tree towards its outline, as a carver rounds a relief over into the background:
  ## heights scale from `keep` of themselves at the edge up to all of themselves `reach` mm in.
  let dist = f.distToOutline()
  for i in 0 ..< f.z.len:
    if f.z[i] <= 0: continue
    let t = smoothstep(0.0, reach, float(dist[i]))
    f.z[i] = float32(float(f.z[i]) * (keep + (1 - keep) * t))

proc sinkFoot*(f: var Field, reach: float, keep: float) =
  ## Lowers the foot of the trunk into the ground over its bottom `reach` mm.
  for y in 0 ..< f.h:
    let yy = (float(y) + 0.5) * f.cell
    if yy >= reach: break
    let k = keep + (1 - keep) * smoothstep(0.0, reach, yy)
    for x in 0 ..< f.w:
      f.z[y * f.w + x] = float32(float(f.z[y * f.w + x]) * k)

proc finish*(f: var Field) =
  ## The carver's pass over a rendered tree: round the outline over into the background, set
  ## the foot into the ground, take thin fins down and smooth off the stair steps.
  f.sinkEdges(4.0, 0.3)
  f.sinkFoot(4.0, 0.25)
  f.limitSlope(5.0)
  f.softenEdges()
