extends RefCounted
## Shared palette. Minimalist: a dark neutral UI so the five tile colors do all the talking.

const BG := Color("12141d")
const PANEL := Color("1a1d2a")
const PANEL_LIGHT := Color("252a3d")
const LINE := Color("2d3350")
const TEXT := Color("eef1fb")
const DIM := Color("7a82a3")
const DANGER := Color("ff4d5e")
const WARN := Color("ffc857")
const GOOD := Color("4ee3a0")

const TILE_COLORS := [
	Color("ff5c7a"), # coral
	Color("4cc9f0"), # sky
	Color("ffc857"), # amber
	Color("4ee3a0"), # mint
	Color("a78bfa"), # violet
]


static func tile_color(id: int) -> Color:
	return TILE_COLORS[id % TILE_COLORS.size()]
