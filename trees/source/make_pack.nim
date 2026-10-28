## Builds the trees clip pack: every tree in the catalogue as a 3D relief clip, the
## .carvioclips pack of them all, and pictures of them in Carvio's 3D view.
##
##   make_pack <out dir> [--shots <dir>] [--only id,id] [--scene] [--cell 0.25]
##
## Build from the repo root: nim c -d:release --path:src --path:<this folder> make_pack.nim

import std/[os, math, strutils, times]
import platform/[window, events, gl]
import core/vec
import model/[document, relief]
import ui/ui
import gfx/[png, scene3d]
import app/[state, app, actions, view3d, clipart, licence]
import treecore, species, catalog
import cliphelp   # tests/cliphelp.nim: puts a 3D clip straight into the job

const
  PackName = "Trees"
  PackDesc = "Trees for outdoor scenes: oaks, maples, birches, willows, elms, poplars, fruit trees, " &
    "cherry blossom, acacias, baobabs, olives, spruces, firs, pines, cedars, cypresses, junipers, " &
    "larches, palms and more, many in several shapes and sizes, with bare winter and snowy versions. " &
    "Every tree is a carved relief with leaves, needles and bark you can see, ready to place, size and " &
    "carve with 3D roughing and finishing."
  PackTags = @["tree", "trees", "forest", "landscape", "outdoor", "nature", "scene", "relief", "3D"]

var outDir = ""
var shots = ""
var only: seq[string]
var scene = false
var cell = 0.25
var i = 1
while i <= paramCount():
  let a = paramStr(i)
  case a
  of "--shots": inc i; shots = paramStr(i)
  of "--only": inc i; only = paramStr(i).split(',')
  of "--scene": scene = true
  of "--cell": inc i; cell = parseFloat(paramStr(i))
  else: outDir = a
  inc i
if outDir == "":
  echo "usage: make_pack <out dir> [--shots <dir>] [--only id,id] [--scene] [--cell 0.25]"
  quit 1
let clipsDir = outDir / "clips"
createDir(clipsDir)

proc mm(v: float): string = $int(round(v))

var files: seq[string]
var built: seq[(TreeDef, string, float, float)]   # def, clip path, width, height
for d in catalog():
  if only.len > 0 and d.id notin only: continue
  let t0 = epochTime()
  let tree = d.build()
  var f = tree.render(cell)
  f.finish()
  f.quantise()
  let wmm = float(f.w) * f.cell; let hmm = float(f.h) * f.cell
  let model = newReliefModel(wmm, hmm, vec2(0, 0), 64)
  let c = model.newComponent(d.name, "mesh")
  c.field = newHeightField(f.w, f.h, vec2(0, 0), f.cell)
  c.field.data = f.z
  c.mask = f.mask
  c.cropToMask()
  let cw = float(c.field.width) * f.cell; let ch = float(c.field.height) * f.cell
  let desc = d.desc.replace("{size}", mm(cw) & " x " & mm(ch) & " mm and " & mm(f.maxHeight) & " mm high")
  let path = writeComponentClip(c, clipsDir, d.name, desc, d.tags)
  files.add readFile(path)
  built.add (d, path, cw, ch)
  echo d.id, ": ", mm(cw), " x ", mm(ch), " mm, ", formatFloat(f.maxHeight, ffDecimal, 1), " mm high, ",
       getFileSize(path) div 1024, " KB, ", formatFloat(epochTime() - t0, ffDecimal, 1), " s"

if only.len == 0:
  let packPath = outDir / "trees.carvioclips"
  writeFile(packPath, packClipFiles(files, PackName, PackDesc, PackTags))
  echo "wrote ", packPath, " (", built.len, " clips, ", getFileSize(packPath) div 1024, " KB)"

if shots == "": quit 0
createDir(shots)
let win = newWindow("trees", 1500, 920)
let a = newApp(win)
a.useTestLicence()
a.configDir = getTempDir() / "carvio_trees"
createDir(a.configDir)
a.settings.ownWindows = false
a.settings.leftPanelOpen = false
a.settings.rightPanelOpen = false
a.dockLayoutDirty = true

proc tick(n = 1) =
  for i in 0 ..< n:
    for e in win.poll(): a.ui.processEvent(e)
    win.scale = 1.0
    a.frame(1.0 / 60.0)
    win.swap()

proc shot(name: string) =
  for e in win.poll(): a.ui.processEvent(e)
  a.frame(1.0 / 60.0)
  var img = newImage(win.width, win.height, 4)
  glPixelStorei(GL_PACK_ALIGNMENT, 1)
  glReadPixels(0, 0, GLsizei(win.width), GLsizei(win.height), GL_RGBA, GL_UNSIGNED_BYTE, addr img.data[0])
  img.flipY()
  win.swap()
  writeFile(shots / (name & ".png"), cast[string](encodePng(img, compress = true)))
  echo "shot ", name

proc place(path, name: string, at: Vec2) =
  var item = ClipItem(path: path, name: name)
  item.kind = ckComponent
  if not a.addClipComponent(item, at): echo "place failed: ", name

tick(5)
if only.len > 0:
  var sorted: seq[(TreeDef, string, float, float)]
  for id in only:
    for b in built:
      if b[0].id == id: sorted.add b
  built = sorted
if scene:
  # a little landscape: several trees side by side on one board
  var job = defaultJob()
  job.name = "Trees"; job.width = 600; job.height = 225; job.thickness = 25; job.material = "Hardwood"
  job.resolution = mrHigh
  a.newProject(job)
  tick(2)
  a.ensureRelief()
  var x = 0.0
  for (d, path, w, h) in built:
    place(path, d.name, vec2(x + w * 0.5 + 6, 8 + h * 0.5))
    x += w * 0.97
    if x > 560: break
  a.markReliefDirty()
  a.doc.clearSelection(); a.compSelection = @[]; a.selectedComponent = -1
  a.viewMode = vm3D
  tick(4)
  for (nm, pitch, zoom) in [("scene-front", 0.0, 0.62), ("scene-angled", -0.45, 0.6)]:
    a.scene.camera.setView("top"); a.fit3D()
    a.scene.camera.pitch += pitch
    if zoom != 1.0: a.scene.camera.zoom(zoom)
    tick(3)
    shot(nm)
  quit 0

for (d, path, w, h) in built:
  var job = defaultJob()
  job.name = d.name; job.width = w + 16; job.height = h + 16; job.thickness = 25; job.material = "Hardwood"
  job.resolution = mrHigh
  a.newProject(job)
  tick(2)
  a.ensureRelief()
  place(path, d.name, vec2(job.width * 0.5, 8 + h * 0.5))
  a.markReliefDirty()
  a.doc.clearSelection(); a.compSelection = @[]; a.selectedComponent = -1
  a.viewMode = vm3D
  tick(4)
  a.scene.camera.setView("top"); a.fit3D()
  a.scene.camera.pitch -= 0.38
  a.scene.camera.zoom(0.82 + 0.25 * clamp(h / w - 1, 0.0, 1.0))
  tick(3)
  shot(d.id)
