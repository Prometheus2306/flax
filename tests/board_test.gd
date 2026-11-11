extends SceneTree
## Headless logic tests. Run with:
##   godot --headless --path . --script res://tests/board_test.gd

const Board = preload("res://board.gd")

var failures := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _initialize() -> void:
	print("Board tests")

	var b = Board.new()
	for i in 3:
		b.push(0, 1)
	var lines: Array = b.find_lines()
	check(lines.size() == 1 and lines[0].length == 3 and not lines[0].diagonal, "vertical 3")
	b.remove_cells(lines[0].cells)
	check(b.height(0) == 0, "vertical clear empties column")

	b = Board.new()
	b.push(0, 2)
	b.push(1, 2)
	b.push(2, 2)
	lines = b.find_lines()
	check(lines.size() == 1 and lines[0].length == 3, "horizontal 3 on floor")

	b = Board.new()
	for c in 5:
		b.push(c, 3)
	lines = b.find_lines()
	check(lines.size() == 1 and lines[0].length == 5, "horizontal 5 is one line")

	# Diagonal up-right: heights 0,1,2 across columns 0,1,2.
	b = Board.new()
	b.push(0, 4)
	b.push(1, 0)
	b.push(1, 4)
	b.push(2, 1)
	b.push(2, 2)
	b.push(2, 4)
	lines = b.find_lines()
	check(lines.size() == 1 and lines[0].diagonal and lines[0].length == 3, "diagonal up-right")

	# Diagonal down-right.
	b = Board.new()
	b.push(0, 1)
	b.push(0, 1)
	b.push(0, 4)
	b.push(1, 0)
	b.push(1, 4)
	b.push(2, 4)
	lines = b.find_lines()
	var diag := 0
	for ln in lines:
		if ln.diagonal and ln.color == 4:
			diag += 1
	check(diag == 1, "diagonal down-right")

	# Two in a row is not a match.
	b = Board.new()
	b.push(0, 1)
	b.push(1, 1)
	b.push(2, 2)
	check(b.find_lines().is_empty(), "two in a row is not a match")

	# Gravity: removing the middle of a stack drops tiles above and records offsets.
	b = Board.new()
	b.push(0, 1)
	b.push(1, 1)
	b.push(2, 1)
	b.push(0, 2)
	b.push(0, 3)
	lines = b.find_lines()
	check(lines.size() == 1, "horizontal at floor with stack above")
	b.remove_cells(lines[0].cells)
	check(b.cols[0] == [2, 3] and b.height(1) == 0 and b.height(2) == 0, "tiles above settle down")
	check(b.offs[0][0] == 1.0 and b.offs[0][1] == 1.0, "fall offsets recorded")

	# L-shape: horizontal and vertical lines sharing a tile are both found.
	b = Board.new()
	b.push(0, 0)
	b.push(0, 0)
	b.push(0, 0)
	b.push(1, 0)
	b.push(2, 0)
	lines = b.find_lines()
	check(lines.size() == 2, "L-shape yields two lines")

	# Chain: clearing a vertical run drops a tile that completes a horizontal run.
	b = Board.new()
	b.push(0, 1)
	b.push(1, 1)
	for i in 3:
		b.push(2, 2)
	b.push(2, 1)
	lines = b.find_lines()
	check(lines.size() == 1 and lines[0].color == 2, "chain setup: only the vertical run matches")
	b.remove_cells(lines[0].cells)
	lines = b.find_lines()
	check(lines.size() == 1 and lines[0].color == 1 and lines[0].length == 3, "chain: new match after gravity")

	print("")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
