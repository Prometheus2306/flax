extends SceneTree
## Headless unit tests for the User Engagement, Dynamic Difficulty Adjustment (DDA),
## and Ad-Monetization KPI Controller (`engagement.gd`).
## Run with:
##   godot --headless --path . --script res://tests/engagement_test.gd

const Engagement = preload("res://engagement.gd")

var failures := 0
var checks := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _initialize() -> void:
	print("Engagement & KPI Controller tests")

	var e = Engagement.new()
	e.reset_for_new_run()
	check(is_equal_approx(e.difficulty_scale, 1.0), "initial difficulty_scale is 1.0")

	# 1. Difficulty increases after every completed wave
	var speed_w1: float = e.get_belt_speed(1)
	var interval_w1: float = e.get_spawn_interval(1)
	e.on_wave_completed(2, 3, 3)
	var scale_after_w1: float = e.difficulty_scale
	var speed_w2: float = e.get_belt_speed(2)
	var interval_w2: float = e.get_spawn_interval(2)
	check(scale_after_w1 > 1.0, "difficulty_scale increases after completing wave 1")
	check(speed_w2 > speed_w1, "belt speed increases on wave 2")
	check(interval_w2 < interval_w1, "spawn interval tightens on wave 2")

	e.on_wave_completed(3, 3, 3)
	check(e.difficulty_scale > scale_after_w1, "difficulty_scale increases again after wave 2")
	check(e.get_belt_speed(3) > speed_w2, "belt speed increases further on wave 3")

	# 2. Difficulty decreases & mercy assist rises when user fails or loses lives
	var high_scale: float = e.difficulty_scale
	var base_mercy: float = e.get_helpful_color_probability(3, 3, 0.2, 0.2)
	e.on_life_lost(3, 2, 0.3, 0.65)
	e.on_life_lost(3, 1, 0.4, 0.75)
	check(e.difficulty_scale < high_scale, "losing lives dynamically lowers difficulty_scale intra-wave")
	var struggling_mercy: float = e.get_helpful_color_probability(3, 1, 0.4, 0.75)
	check(struggling_mercy > base_mercy, "struggling player receives higher helpful-color probability")

	var pre_fail_scale: float = e.difficulty_scale
	e.on_wave_failed(3, 0.85, 0.80, 1200, 1500)
	check(e.consecutive_failures == 1, "consecutive_failures incremented on wave failure")
	check(e.difficulty_scale < pre_fail_scale, "wave failure decreases difficulty_scale")

	e.on_wave_failed(3, 0.50, 0.85, 900, 1500)
	check(e.consecutive_failures == 2, "second consecutive failure tracked")
	e.reset_for_new_run()
	check(e.difficulty_scale < 1.0, "new run after repeated failures starts with softer difficulty_scale")
	check(e.mercy_assist_chance > Engagement.BASE_HELPFUL_COLOR_BIAS, "new run after failures starts with boosted mercy assist")

	# 3. KPI P(watch ad to continue) optimization behavior
	var e_kpi = Engagement.new()
	# Case A: Early failure at 10% wave progress on wave 1 -> lower ad-watch KPI
	var kpi_early: float = e_kpi.update_kpi(1, 0, 0.10, 0.25, 80, 2000)
	# Case B: Near-miss failure at 92% wave progress on wave 5 chasing high score -> high ad-watch KPI
	e_kpi.frustration = 0.40
	var kpi_near_miss: float = e_kpi.update_kpi(5, 0, 0.92, 0.55, 1950, 2000)
	check(kpi_near_miss > kpi_early + 0.30, "KPI P(watch ad) is significantly higher on near-miss deep run than early fail")
	check(kpi_near_miss >= 0.65 and kpi_near_miss <= 0.98, "near-miss KPI is in high-conversion range")

	# 4. Watching an ad grants post-ad mercy relief & applies diminishing returns to subsequent ad KPI
	check(e_kpi.can_offer_ad_continue(), "can offer ad continue initially")
	var scale_before_ad: float = e_kpi.difficulty_scale
	e_kpi.on_ad_watched(5, 2, 0.92)
	check(e_kpi.ads_watched_this_run == 1, "ads_watched_this_run incremented")
	check(e_kpi.difficulty_scale < scale_before_ad, "watching an ad grants post-ad difficulty relief")
	var kpi_after_1_ad: float = e_kpi.update_kpi(5, 0, 0.92, 0.55, 1950, 2000)
	check(kpi_after_1_ad < kpi_near_miss, "ad fatigue lowers KPI after an ad was already watched this run")

	e_kpi.on_ad_watched(5, 2, 0.95)
	e_kpi.on_ad_watched(5, 2, 0.95)
	check(not e_kpi.can_offer_ad_continue(), "ad continue capped at 3 per run")

	# 5. "Slowy" Helper Spirit engagement & half-speed mechanics
	var e_slowy = Engagement.new()
	e_slowy.reset_for_new_run()
	var normal_spd: float = e_slowy.get_belt_speed(4, false)
	var slowy_spd: float = e_slowy.get_belt_speed(4, true)
	check(is_equal_approx(slowy_spd, normal_spd * 0.5), "Slowy halves conveyor belt speed (0.5x)")
	check(e_slowy.get_spawn_interval(4, true) > e_slowy.get_spawn_interval(4, false), "Slowy widens spawn interval so belt slots do not crowd")

	# Cooldown & busy guard
	e_slowy.tiles_since_last_slowy = 2
	check(is_equal_approx(e_slowy.get_slowy_spawn_probability(3, 2, 0.5, false), 0.0), "Slowy respects minimum tile cooldown between spawns")
	e_slowy.tiles_since_last_slowy = 10
	check(is_equal_approx(e_slowy.get_slowy_spawn_probability(3, 2, 0.5, true), 0.0), "Slowy does not spawn when another Slowy is already trapped or active")

	# Struggle/frustration increases Slowy spawn probability
	var calm_prob: float = e_slowy.get_slowy_spawn_probability(2, 3, 0.15, false)
	e_slowy.frustration = 0.65
	var struggle_prob: float = e_slowy.get_slowy_spawn_probability(5, 1, 0.75, false)
	check(struggle_prob > calm_prob, "Slowy spawn probability increases when belt speed is high, lives are low, or bins are filling up")

	# Combo type selection adapts to pressure & covers horizontal, vertical, diagonal
	e_slowy.frustration = 0.0
	check(e_slowy.pick_slowy_combo_type(1, 3, 0.1, 0.10) == "vertical", "pick_slowy_combo_type selects vertical for low roll")
	check(e_slowy.pick_slowy_combo_type(1, 3, 0.1, 0.60) == "horizontal", "pick_slowy_combo_type selects horizontal for mid roll")
	check(e_slowy.pick_slowy_combo_type(3, 3, 0.1, 0.92) == "diagonal", "pick_slowy_combo_type selects diagonal for high roll on wave 3+")

	# KPI hook when Slowy is trapped in play or freed
	var kpi_base: float = e_slowy.update_kpi(2, 1, 0.45, 0.40, 400, 1500)
	e_slowy.on_tile_spawned(true)
	var kpi_trapped: float = e_slowy.update_kpi(2, 1, 0.45, 0.40, 400, 1500)
	check(kpi_trapped > kpi_base, "trapped Slowy on board boosts continuation KPI (unfinished helper spirit goal)")
	e_slowy.on_slowy_freed(2, 1)
	check(e_slowy.slowy_freed_this_run == 1 and not e_slowy.slowy_trapped_in_play, "on_slowy_freed records helper spirit rescue and clears trapped flag")

	print("")
	print("FAILURES: ", failures, "  (", checks, " checks)")
	quit(1 if failures > 0 else 0)
