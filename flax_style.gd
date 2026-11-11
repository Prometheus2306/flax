extends RefCounted
## Shared Paper Mario / Storybook Craft palette.
## Warm construction-paper & cardboard stage tones paired with bold cartoon ink outlines,
## crisp white die-cut sticker borders, and vibrant gouache/paint tile colors.

const BG := Color("fff5e1")          # warm cream craft-paper sky
const SKY_TOP := Color("cdeeff")     # pastel sky-blue paper backdrop
const HILL_BACK := Color("a5e396")   # pastel mint-green stitched paper hill
const HILL_FRONT := Color("7ad470")  # sunny meadow-green stitched paper hill
const PANEL := Color("f3dfc1")       # warm kraft-cardboard ramp & bin board
const PANEL_DARK := Color("d9be96")  # recessed cardboard lane groove
const PANEL_LIGHT := Color("fffdf7") # cream sticker card / button surface
const WOOD_RAIL := Color("e59f56")   # toy-wood side rail
const WOOD_DARK := Color("b46f2c")   # shaded wood lip
const LINE := Color("c7ab82")        # craft-paper fold / stitch line
const INK := Color("2b2038")         # bold cartoon dark-ink outline
const STICKER := Color("ffffff")     # crisp white die-cut sticker border
const SHADOW := Color(0.16, 0.10, 0.22, 0.22)

const TEXT := Color("2b2038")        # bold dark cartoon ink text
const DIM := Color("6e5a7a")         # warm plum-brown secondary ink
const DANGER := Color("ff4760")      # cherry-red construction paper
const WARN := Color("ffaa1d")        # marigold-gold star sticker
const GOOD := Color("2cc970")        # emerald-leaf sticker green

const TILE_COLORS := [
	Color("ff4d6d"), # strawberry red cutout
	Color("2eb5ff"), # sky blue cutout
	Color("ffc425"), # sunny yellow star cutout
	Color("34d178"), # meadow green cutout
	Color("9d65ff"), # grape purple cutout
]

## Secondary vibrant paint/gouache hue for fluid splashes, droplets, and color-shifts.
const TILE_FLUID_ALT := [
	Color("ff9233"), # red -> tangerine paint
	Color("18e0c8"), # blue -> aqua turquoise paint
	Color("ff6392"), # yellow -> bubblegum coral paint
	Color("28c9ff"), # green -> sky cyan paint
	Color("ff4da6"), # purple -> berry magenta paint
]


static func tile_color(id: int) -> Color:
	return TILE_COLORS[id % TILE_COLORS.size()]


static func fluid_alt_color(id: int) -> Color:
	return TILE_FLUID_ALT[id % TILE_FLUID_ALT.size()]
