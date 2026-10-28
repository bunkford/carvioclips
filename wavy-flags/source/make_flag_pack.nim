## Builds the wavy flag bases clip pack the store sells (store/clipart/wavy-flags.carvioclips,
## listed in store/listings.json for web/bin/seed_store.php): one 3D clip a flag ratio, each the
## top surface of a generated STL relief of a flag rippling in the wind.
##
##   nim r -d:release tools/make_flag_pack.nim <folder of wavy-flag-*.stl> [store-dir]
##
## The STLs (200 mm on the hoist, an 8 mm ripple on a 3 mm base) are made outside the repo by
## make_wavy_flags.py (in the project files' wavy-flags folder).

import std/[os, strutils]
import core/vec
import io/[mesh, carviofile]
import model/relief
import app/clipart

const
  Cell = 0.5   ## mm a relief cell: the STLs' mesh is 1 mm, so nothing is lost
  Flags = [("1x1", "1:1"), ("2x3", "2:3"), ("3x5", "3:5"), ("1x2", "1:2"), ("1x1.9", "1:1.9")]
  Tags = @["flag", "wavy", "relief", "base", "3D"]

if paramCount() < 1:
  echo "usage: make_flag_pack <folder of wavy-flag-*.stl> [store-dir]"
  quit 1
let stlDir = paramStr(1)
let storeDir = if paramCount() >= 2: paramStr(2) else: "store"
let work = getTempDir() / "carvio_flag_pack"
removeDir(work)
createDir(work)

proc mm(v: float): string =
  ## A size to a tenth of a millimetre, without a trailing ".0" ("200", "333.3").
  result = formatFloat(v, ffDecimal, 1)
  if result.endsWith(".0"): result.setLen(result.len - 2)

var files: seq[string]
for (file, ratio) in Flags:
  let path = stlDir / "wavy-flag-" & file & ".stl"
  let m = loadStl(path)
  m.computeBounds()
  let size = m.bounds.size
  let r = rasterMeshComponent(m, vec2(0, 0), Cell)
  let model = newReliefModel(size.x, size.y, vec2(0, 0), 64)
  let c = model.newComponent("Wavy flag " & ratio, "mesh")
  c.field = newHeightField(r.w, r.h, r.origin, Cell)
  c.field.data = r.data
  c.mask = r.mask
  let name = "Wavy flag " & ratio
  let description = "A flag rippling in the wind, " & ratio & " (hoist to fly), " & mm(size.x) & " x " & mm(size.y) &
                    " mm and " & mm(size.z) & " mm high (an 8 mm ripple on a 3 mm base). Lay flag artwork over it to give the flag a waving look."
  let written = writeComponentClip(c, work, name, description, Tags)
  files.add readFile(written)
  echo "packed ", name, " (", r.w, " x ", r.h, " cells, ", files[^1].len div 1024, " KB)"

createDir(storeDir / "clipart")
let packPath = storeDir / "clipart" / "wavy-flags.carvioclips"
writeFile(packPath, packClipFiles(files, "Wavy flag bases",
  "Turn any flag into a wavy piece of art with these waving flag bases available in these convenient ratios: 1:1, 2:3, 3:5, 1:2 and 1:1.9.",
  Tags))
echo "wrote ", packPath, " (", getFileSize(packPath) div 1024, " KB)"
removeDir(work)
