extends RefCounted
## Pure board logic for the 5x5 bins. No nodes, no drawing, so it can be unit tested headless.
##
## `cols[c]` holds tile color ids for column `c`, ordered bottom -> top.
## `offs[c][r]` is a purely visual offset (in rows) used to animate tiles falling
## after neighbours were removed; the view eases it back to zero.
## `spirits[c][r]` holds an optional trapped helper spirit id (e.g. `"slowy"`) or `""`.

const COLS := 5
const ROWS := 5
## Search directions: horizontal, vertical, diagonal up-right, diagonal down-right.
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]

var cols: Array = []
var offs: Array = []
var spirits: Array = []


func _init() -> void:
	reset()


func reset() -> void:
	cols = []
	offs = []
	spirits = []
	for c in COLS:
		cols.append([])
		offs.append([])
		spirits.append([])


func height(c: int) -> int:
	return cols[c].size()


func is_full(c: int) -> bool:
	return cols[c].size() >= ROWS


func total_tiles() -> int:
	var n := 0
	for c in COLS:
		n += cols[c].size()
	return n


## Color id at (column, row) or -1 when out of range / empty.
func get_cell(c: int, r: int) -> int:
	if c < 0 or c >= COLS or r < 0 or r >= cols[c].size():
		return -1
	return cols[c][r]


## Helper spirit id at (column, row) or "" when empty / none.
func get_spirit(c: int, r: int) -> String:
	if c < 0 or c >= COLS or r < 0 or r >= spirits[c].size():
		return ""
	return spirits[c][r]


## Sets or clears the helper spirit at (column, row).
func set_spirit(c: int, r: int, spirit: String) -> void:
	if c >= 0 and c < COLS and r >= 0 and r < spirits[c].size():
		spirits[c][r] = spirit


## Finds the cell coordinates Vector2i(c, r) of a trapped spirit, or Vector2i(-1, -1).
func find_spirit(spirit: String = "slowy") -> Vector2i:
	for c in COLS:
		for r in spirits[c].size():
			if spirits[c][r] == spirit:
				return Vector2i(c, r)
	return Vector2i(-1, -1)


## Places a tile on top of a column. Capacity is enforced by the caller, because a
## column can briefly hold an extra tile while a clear animation is in flight.
func push(c: int, color: int, spirit: String = "") -> void:
	cols[c].append(color)
	offs[c].append(0.0)
	spirits[c].append(spirit)


## Finds every run of 3+ same-colored tiles in any of the four directions.
## Returns an Array of {cells: Array[Vector2i], diagonal: bool, kind: String, color: int, length: int}.
func find_lines() -> Array:
	var lines: Array = []
	for c in COLS:
		for r in cols[c].size():
			var color: int = cols[c][r]
			for d in DIRS:
				var here := Vector2i(c, r)
				var prev: Vector2i = here - d
				# Only start a run at its first tile so each run is reported once.
				if get_cell(prev.x, prev.y) == color:
					continue
				var run: Array = [here]
				var p: Vector2i = here + d
				while get_cell(p.x, p.y) == color:
					run.append(p)
					p += d
				if run.size() >= 3:
					var kind := "diagonal"
					if d == Vector2i(1, 0):
						kind = "horizontal"
					elif d == Vector2i(0, 1):
						kind = "vertical"
					lines.append({
						"cells": run,
						"diagonal": d.x != 0 and d.y != 0,
						"kind": kind,
						"color": color,
						"length": run.size(),
					})
	return lines


## Removes the given cells and lets the tiles above settle down. Remaining tiles get
## a visual offset equal to how far they fell so the view can animate it.
func remove_cells(cells: Array) -> void:
	var by_col := {}
	for cell in cells:
		if not by_col.has(cell.x):
			by_col[cell.x] = {}
		by_col[cell.x][cell.y] = true
	for c in by_col:
		var rows: Dictionary = by_col[c]
		var new_col: Array = []
		var new_offs: Array = []
		var new_spirits: Array = []
		var removed := 0
		for r in cols[c].size():
			if rows.has(r):
				removed += 1
			else:
				new_col.append(cols[c][r])
				new_offs.append(offs[c][r] + float(removed))
				new_spirits.append(spirits[c][r])
		cols[c] = new_col
		offs[c] = new_offs
		spirits[c] = new_spirits
