# Trees clip pack generator

Builds `trees.carvioclips`: 53 tree reliefs for outdoor scenes, each grown as a 3D tree
(trunk, limbs, twigs, leaf clumps, needles, fronds) and projected into a side-view relief with
its depth squeezed into a few millimetres, then rounded over at the outline so thin twigs and
leaf tips stay carvable.

Files: `treecore.nim` (primitives, rendering, finishing), `treegrow.nim` (branch growth and
foliage), `species.nim` (broadleaf), `conifers.nim`, `palms.nim`, `catalog.nim` (names,
descriptions, tags and pack order), `make_pack.nim` (clips, pack and Carvio 3D pictures),
`preview.nim` (quick shaded picture of one tree).

Build from the Carvio repo root with Nim 2.2:

    nim c -d:release --path:src --path:tests --path:<this folder> -o:make_pack <this folder>/make_pack.nim
    ./make_pack out                           # clips in out/clips, pack in out/trees.carvioclips
    xvfb-run -a ./make_pack out --shots shots  # also a picture of each tree in the 3D view
    xvfb-run -a ./make_pack out --shots shots --scene --only spruce,oak,birch   # trees side by side

    nim c -d:release --path:src --path:<this folder> -o:preview <this folder>/preview.nim
    ./preview oak oak.png                     # or: ./preview all <folder>
