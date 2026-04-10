extends RefCounted
class_name DebugTools

# Prints available local debug shortcuts.
static func print_debug_hotkeys():
	print("Debug keys: F6=dump bins, F7=validate state, F8=run combo self-tests")

# Routes one keyboard event to the matching debug helper.
static func handle_debug_hotkey(main, event):
	if event.keycode == KEY_F6:
		debug_dump_bin_state(main)
	elif event.keycode == KEY_F7:
		debug_validate_state(main, true)
	elif event.keycode == KEY_F8:
		debug_run_combo_self_tests(main)

# Prints bin sizes/colors in bottom-to-top order for quick inspection.
static func debug_dump_bin_state(main):
	var lines = []
	for i in range(main.bin_contents.size()):
		lines.append("Bin " + str(i) + " (" + str(main.bin_contents[i].size()) + "): " + str(main.bin_contents[i]))
	print("[DEBUG] " + " | ".join(lines))

# Checks gameplay invariants and optionally prints a pass/fail summary.
static func debug_validate_state(main, print_result := false) -> bool:
	var ok = true
	if main.bin_contents.size() != main.bins.get_child_count():
		ok = false
		main.push_warning("[DEBUG] bin_contents size does not match bin node count.")
	
	for i in range(main.bin_contents.size()):
		var bin_size = main.bin_contents[i].size()
		if bin_size > main.MAX_BIN_HEIGHT:
			ok = false
			main.push_warning("[DEBUG] Bin " + str(i) + " exceeds MAX_BIN_HEIGHT.")
		var bin_node = main.bins.get_child(i)
		var visual_count = debug_get_stack_visual_count(bin_node)
		if visual_count != bin_size:
			ok = false
			main.push_warning("[DEBUG] Bin " + str(i) + " visual count (" + str(visual_count) + ") != data count (" + str(bin_size) + ").")
	
	if print_result:
		if ok:
			print("[DEBUG] State validation passed.")
		else:
			print("[DEBUG] State validation failed. Check warnings above.")
	return ok

# Counts generated stack tile visuals in a bin.
static func debug_get_stack_visual_count(bin_node) -> int:
	var count = 0
	for child in bin_node.get_children():
		if child.has_meta("is_stack_tile") and child.get_meta("is_stack_tile"):
			count += 1
	return count

# Replaces board state with supplied bin data and rebuilds visuals.
static func debug_set_board_state(main, new_state):
	for i in range(main.bin_contents.size()):
		main.bin_contents[i].clear()
		for color_value in new_state[i]:
			main.bin_contents[i].append(color_value)
		main.rebuild_bin_visual(i)

# Runs deterministic combo scenarios to verify scoring/removal logic.
static func debug_run_combo_self_tests(main):
	var saved_score = main.score
	var saved_lives = main.lives
	var saved_bins = main.bin_contents.duplicate(true)
	
	var tests_passed = true
	
	# Test 1: Vertical combo from one bin.
	main.score = 0
	debug_set_board_state(main, [
		[Color.RED, Color.RED, Color.RED],
		[], [], [], []
	])
	main.process_flax_checks(0)
	if not (main.bin_contents[0].is_empty() and main.score == 100):
		tests_passed = false
		main.push_warning("[DEBUG] Vertical test failed.")
	
	# Test 2: Horizontal combo at middle height (not top).
	main.score = 0
	debug_set_board_state(main, [
		[Color.BLUE, Color.RED, Color.GREEN],
		[Color.YELLOW, Color.RED, Color.PURPLE],
		[Color.GREEN, Color.RED, Color.BLUE],
		[], []
	])
	main.process_flax_checks(0)
	if not (main.score >= 150 and main.bin_contents[0].size() == 2 and main.bin_contents[1].size() == 2 and main.bin_contents[2].size() == 2):
		tests_passed = false
		main.push_warning("[DEBUG] Horizontal deep-height test failed.")
	
	# Test 3: Up-right diagonal combo away from top.
	main.score = 0
	debug_set_board_state(main, [
		[Color.BLUE, Color.GREEN],
		[Color.RED, Color.YELLOW, Color.GREEN],
		[Color.PURPLE, Color.RED, Color.BLUE, Color.GREEN],
		[], []
	])
	main.process_flax_checks(0)
	if not (main.score >= 200 and main.bin_contents[0].size() == 1 and main.bin_contents[1].size() == 2 and main.bin_contents[2].size() == 3):
		tests_passed = false
		main.push_warning("[DEBUG] Diagonal deep-height test failed.")
	
	# Restore gameplay state.
	main.score = saved_score
	main.lives = saved_lives
	debug_set_board_state(main, saved_bins)
	main.update_ui()
	
	if tests_passed:
		print("[DEBUG] Combo self-tests passed.")
	else:
		print("[DEBUG] Combo self-tests found failures.")
