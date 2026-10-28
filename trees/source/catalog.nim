## Every tree in the pack, in pack order (the first nine make the pack picture).
## "{size}" in a description becomes the clip's size.
import treecore, species, conifers, palms

proc d(id, name, desc: string, tags: seq[string], build: proc (): Tree): TreeDef =
  TreeDef(id: id, name: name, desc: desc & " {size}.", tags: @["tree"] & tags, build: build)

proc catalog*(): seq[TreeDef] =
  let leafy = @["broadleaf", "summer"]
  let bare = @["broadleaf", "winter", "bare"]
  result.add d("oak", "Oak", "A big oak in full leaf: a broad, billowing crown on thick limbs and deeply furrowed bark,",
               @["oak"] & leafy, proc (): Tree = oak(12, true))
  result.add d("oak-winter", "Oak in winter", "The same oak in winter, bare, showing its thick crooked limbs and fine twigs,",
               @["oak"] & bare, proc (): Tree = oak(12, false))
  result.add d("oak-young", "Young oak", "A young oak with a small round crown on a slender trunk,",
               @["oak", "young", "small"] & leafy, proc (): Tree = youngOak(21))
  result.add d("oak-old", "Old spreading oak", "An old field oak, much wider than tall, with long low limbs,",
               @["oak", "old", "wide"] & leafy, proc (): Tree = oldOak(31, true))
  result.add d("oak-old-winter", "Old spreading oak in winter", "The old field oak bare in winter,",
               @["oak", "old", "wide"] & bare, proc (): Tree = oldOak(31, false))
  result.add d("maple", "Maple", "A maple with a dense, rounded crown of five-pointed leaves,",
               @["maple"] & leafy, proc (): Tree = maple(41, true))
  result.add d("maple-winter", "Maple in winter", "The maple bare in winter, its branches reaching upward,",
               @["maple"] & bare, proc (): Tree = maple(41, false))
  result.add d("maple-tall", "Tall maple", "A tall, oval maple,",
               @["maple", "tall"] & leafy, proc (): Tree = tallMaple(43))
  result.add d("birch", "Birch", "A slender birch with an airy crown of small leaves on drooping twigs and pale, marked bark,",
               @["birch"] & leafy, proc (): Tree = birch(51, true))
  result.add d("birch-clump", "Birch clump", "Three birch trunks growing together,",
               @["birch", "clump"] & leafy, proc (): Tree = birch(53, true, 3))
  result.add d("birch-winter", "Birch in winter", "A bare birch in winter with fine hanging twigs,",
               @["birch"] & bare, proc (): Tree = birch(51, false))
  result.add d("willow", "Weeping willow", "A weeping willow with long hanging curtains of narrow leaves,",
               @["willow", "weeping"] & leafy, proc (): Tree = willow(61, true))
  result.add d("willow-young", "Young weeping willow", "A young weeping willow,",
               @["willow", "weeping", "young", "small"] & leafy, proc (): Tree = willow(63, true, 0.6))
  result.add d("willow-winter", "Weeping willow in winter", "A weeping willow in winter, its long bare whips hanging to the ground,",
               @["willow", "weeping"] & bare, proc (): Tree = willow(61, false))
  result.add d("elm", "Elm", "A vase-shaped elm: limbs rising steeply from a short trunk to a wide, arching crown,",
               @["elm"] & leafy, proc (): Tree = elm(71, true))
  result.add d("elm-winter", "Elm in winter", "The elm bare in winter, showing its vase shape,",
               @["elm"] & bare, proc (): Tree = elm(71, false))
  result.add d("poplar", "Lombardy poplar", "A tall, narrow Lombardy poplar,",
               @["poplar", "tall", "narrow"] & leafy, proc (): Tree = poplar(81, true))
  result.add d("poplar-winter", "Lombardy poplar in winter", "A Lombardy poplar bare in winter, its branches all pointing up,",
               @["poplar", "tall", "narrow"] & bare, proc (): Tree = poplar(81, false))
  result.add d("apple", "Apple tree", "A small apple tree laden with apples,",
               @["apple", "fruit", "orchard"] & leafy, proc (): Tree = appleTree(91, false))
  result.add d("apple-blossom", "Apple tree in blossom", "A small apple tree in spring blossom,",
               @["apple", "fruit", "orchard", "spring", "blossom"], proc (): Tree = appleTree(93, true))
  result.add d("cherry-blossom", "Cherry blossom", "A spreading cherry tree covered in blossom,",
               @["cherry", "blossom", "spring", "sakura"], proc (): Tree = cherryBlossom(101))
  result.add d("beech", "Beech", "A big beech with smooth bark and a full crown sweeping low,",
               @["beech"] & leafy, proc (): Tree = beech(111))
  result.add d("olive", "Olive tree", "An old olive tree with a twisted double trunk and silvery narrow leaves,",
               @["olive", "mediterranean"] & leafy, proc (): Tree = olive(121))
  result.add d("acacia", "Acacia", "A flat-topped umbrella acacia of the savanna,",
               @["acacia", "savanna", "africa"] & leafy, proc (): Tree = acacia(131))
  result.add d("acacia-small", "Small acacia", "A smaller umbrella acacia,",
               @["acacia", "savanna", "africa", "small"] & leafy, proc (): Tree = acacia(133, 0.65))
  result.add d("baobab", "Baobab", "A baobab: a huge bottle-shaped trunk under a small crown of leaves,",
               @["baobab", "savanna", "africa"] & leafy, proc (): Tree = baobab(141, true))
  result.add d("baobab-bare", "Bare baobab", "A baobab in the dry season, its stubby branches bare,",
               @["baobab", "savanna", "africa", "bare"], proc (): Tree = baobab(141, false))
  result.add d("dead-tree", "Dead tree", "A dead tree with broken limbs, for spooky and wild scenes,",
               @["dead", "halloween", "bare", "spooky"], proc (): Tree = deadTree(151))
  result.add d("sapling", "Sapling", "A small young tree,",
               @["young", "small", "sapling"] & leafy, proc (): Tree = sapling(161))
  let con = @["conifer", "evergreen"]
  result.add d("spruce", "Spruce", "A tall spruce: a dark cone of drooping, needled boughs,",
               @["spruce", "christmas"] & con, proc (): Tree = spruce(201))
  result.add d("spruce-small", "Small spruce", "A small young spruce,",
               @["spruce", "small", "young"] & con, proc (): Tree = spruce(203, 90, 56))
  result.add d("spruce-wide", "Broad spruce", "A broad, full spruce, its lowest boughs sweeping the ground,",
               @["spruce", "wide"] & con, proc (): Tree = spruce(205, 150, 112))
  result.add d("spruce-snow", "Snowy spruce", "A tall spruce with snow lying on every bough,",
               @["spruce", "snow", "winter", "christmas"] & con, proc (): Tree = spruce(207, 170, 92, 1.0))
  result.add d("spruce-snow-small", "Small snowy spruce", "A small spruce under snow,",
               @["spruce", "snow", "winter", "small", "christmas"] & con, proc (): Tree = spruce(209, 95, 60, 1.0))
  result.add d("fir", "Fir", "A narrow, upright fir with neat tiers of level branches,",
               @["fir"] & con, proc (): Tree = fir(211))
  result.add d("fir-small", "Small fir", "A small fir,",
               @["fir", "small"] & con, proc (): Tree = fir(213, 100, 44))
  result.add d("christmas-tree", "Christmas tree", "A small spruce with a star on top and songbirds perched on its boughs,",
               @["christmas", "holiday", "spruce", "decorated"] & con, proc (): Tree = christmasTree(215))
  result.add d("pine", "Scots pine", "A Scots pine: a tall bare trunk and a high, uneven crown of needle tufts,",
               @["pine"] & con, proc (): Tree = scotsPine(221))
  result.add d("pine-leaning", "Leaning pine", "A Scots pine leaning to one side,",
               @["pine", "leaning"] & con, proc (): Tree = scotsPine(223, 18))
  result.add d("stone-pine", "Umbrella pine", "A Mediterranean umbrella pine with a wide, flat dome of needles,",
               @["pine", "umbrella", "mediterranean"] & con, proc (): Tree = stonePine(225))
  result.add d("windswept-pine", "Windswept pine", "A coastal pine bent by the wind, its branches streaming to one side,",
               @["pine", "windswept", "coast"] & con, proc (): Tree = windsweptPine(227))
  result.add d("cedar", "Cedar", "A cedar of Lebanon with flat, layered tables of foliage,",
               @["cedar"] & con, proc (): Tree = cedar(231))
  result.add d("cypress", "Italian cypress", "A tall, narrow Italian cypress, like a dark flame,",
               @["cypress", "mediterranean", "narrow", "tall"] & con, proc (): Tree = cypress(241))
  result.add d("cypress-small", "Small cypress", "A shorter Italian cypress,",
               @["cypress", "mediterranean", "narrow", "small"] & con, proc (): Tree = cypress(243, 110))
  result.add d("juniper", "Juniper", "A rugged juniper with a twisted trunk,",
               @["juniper"] & con, proc (): Tree = juniper(251))
  result.add d("larch-winter", "Larch in winter", "A larch in winter: a conifer that drops its needles, bare branches in tiers,",
               @["larch", "winter", "bare", "conifer"], proc (): Tree = larch(261))
  let palm = @["palm", "tropical", "beach"]
  result.add d("palm", "Coconut palm", "A coconut palm: a ringed trunk and a crown of arching, feathery fronds with coconuts,",
               palm, proc (): Tree = coconutPalm(301))
  result.add d("palm-curved", "Curved coconut palm", "A coconut palm leaning out over the beach on a curved trunk,",
               palm & @["curved", "leaning"], proc (): Tree = coconutPalm(303, 55))
  result.add d("palm-pair", "Pair of palms", "Two coconut palms growing together, leaning apart,",
               palm & @["pair"], proc (): Tree = palmPair(305))
  result.add d("palm-young", "Young palm", "A young coconut palm on a short trunk,",
               palm & @["young", "small"], proc (): Tree = youngPalm(307))
  result.add d("date-palm", "Date palm", "A date palm with a stout, patterned trunk, stiff fronds and hanging bunches of dates,",
               palm & @["date", "desert", "oasis"], proc (): Tree = datePalm(311))
  result.add d("fan-palm", "Fan palm", "A tall fan palm: a head of round fan leaves over a skirt of old ones,",
               palm & @["fan"], proc (): Tree = fanPalm(321))
  result.add d("joshua-tree", "Joshua tree", "A Joshua tree of the desert, its shaggy arms ending in spiky rosettes,",
               @["joshua", "desert", "yucca"], proc (): Tree = joshuaTree(331))
  # the pack picture shows the first nine: lead with a spread of the most different trees
  const front = ["oak", "spruce", "palm", "birch", "willow", "pine", "maple", "cypress", "cherry-blossom"]
  var ordered: seq[TreeDef]
  for id in front:
    for t in result:
      if t.id == id: ordered.add t
  for t in result:
    if t.id notin front: ordered.add t
  result = ordered
