## Quick look: builds one tree and writes a shaded picture of its relief.
##   preview <name> <out.png> [cell]
import std/[os, math, strutils, times]
import core/vec
import gfx/png
import treecore, species, catalog

proc shade*(f: Field, path: string) =
  var img = newImage(f.w, f.h, 3)
  let l = vec3(-0.5, 0.6, 0.62).normalized
  for y in 0 ..< f.h:
    for x in 0 ..< f.w:
      let i = y * f.w + x
      let o = ((f.h - 1 - y) * f.w + x) * 3
      if f.z[i] <= 0:
        img.data[o] = 236; img.data[o + 1] = 232; img.data[o + 2] = 224
        continue
      let xl = max(0, x - 1); let xr = min(f.w - 1, x + 1)
      let yd = max(0, y - 1); let yu = min(f.h - 1, y + 1)
      let dx = (float(f.z[y * f.w + xr]) - float(f.z[y * f.w + xl])) / (float(xr - xl) * f.cell)
      let dy = (float(f.z[yu * f.w + x]) - float(f.z[yd * f.w + x])) / (float(yu - yd) * f.cell)
      let n = vec3(-dx, -dy, 1).normalized
      let d = max(0.0, dot(n, l))
      let v = 0.18 + 0.82 * d
      img.data[o] = uint8(clamp(v * 222, 0, 255))
      img.data[o + 1] = uint8(clamp(v * 190, 0, 255))
      img.data[o + 2] = uint8(clamp(v * 150, 0, 255))
  writeFile(path, cast[string](encodePng(img, compress = true)))

when isMainModule:
  let name = paramStr(1)
  let outp = paramStr(2)
  let cell = if paramCount() >= 3: parseFloat(paramStr(3)) else: 0.25
  let t0 = epochTime()
  for d in catalog():
    if d.id == name or name == "all":
      let t = d.build()
      var f = t.render(cell)
      f.finish()
      echo d.id, ": ", t.prims.len, " prims, ", f.w, "x", f.h, " cells (", formatFloat(float(f.w) * cell, ffDecimal, 0), " x ",
           formatFloat(float(f.h) * cell, ffDecimal, 0), " mm), top ", formatFloat(f.maxHeight, ffDecimal, 1), " mm, ",
           formatFloat(epochTime() - t0, ffDecimal, 1), " s"
      shade(f, if name == "all": outp / (d.id & ".png") else: outp)
