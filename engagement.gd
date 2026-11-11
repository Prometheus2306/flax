extends RefCounted
## User Engagement, Dynamic Difficulty Adjustment (DDA), Helper Spirit ("Slowy"),
## and Ad-Monetization KPI Controller.
##
## Optimizes the primary KPI:
##   `kpi_ad_watch_probability` in [0.0, 1.0]
## defined as the probability that the user chooses to watch a rewarded ad to continue playing
## when their run is in jeopardy or ends.
##
## Core responsibilities:
## 1. Increase difficulty after every completed wave (scaling belt speed & spawn cadence),
##    modulated by player performance so skilled players stay challenged.
## 2. Decrease difficulty and boost helpful-tile spawn probabilities ("mercy assist") when the
##    player fails waves repeatedly, loses lives quickly, or is in high bin-overflow danger,
##    preventing frustration churn and keeping the player in the high-KPI "near-miss" flow zone.
## 3. Orchestrate the "Slowy" Helper Spirit power-up (trapped inside a random spawned tile and
##    freed by a specific Klax combo type: horizontal, vertical, or diagonal). When freed, Slowy
##    cuts conveyor belt speed in half (`0.5x`), enabling struggling or deep-run players to
##    progress further and increasing run investment.

const BASE_BELT_SPEED := 150.0
const MAX_BELT_SPEED := 420.0
const MIN_BELT_SPEED := 105.0
const SLOWY_SPEED_FACTOR := 0.50     # Slowy halves the conveyor belt speed!

const BASE_SPAWN_INTERVAL := 1.70
const MIN_SPAWN_INTERVAL := 0.55
const MAX_SPAWN_INTERVAL := 2.15

const BASE_HELPFUL_COLOR_BIAS := 0.35
const MAX_HELPFUL_COLOR_BIAS := 0.82
const MIN_HELPFUL_COLOR_BIAS := 0.18

const COMBO_TYPES := ["horizontal", "vertical", "diagonal"]

# --- Persistent / cross-wave engagement state ------------------------------
var difficulty_scale := 1.0          # < 1.0 easier, 1.0 nominal, > 1.0 harder
var skill_ema := 0.5                 # Exponential moving average of player skill [0..1]
var frustration := 0.0               # Accumulated frustration from misses & failed waves [0..1]
var consecutive_failures := 0        # Waves/runs failed in a row without clearing a wave
var total_waves_cleared := 0
var total_failures := 0
var recent_misses := 0               # Misses in the current wave
var wave_flaxes := 0                 # Combos cleared in the current wave
var ads_watched_this_run := 0
var total_ads_watched := 0
var ad_offers_shown := 0

# --- Helper Spirit ("Slowy") engagement state ------------------------------
var tiles_since_last_slowy := 0      # Cooldown counter so Slowy spawns "every now and then"
var slowy_spawns_this_wave := 0
var slowy_freed_this_run := 0
var slowy_trapped_in_play := false   # True while a trapped Slowy is currently in play

# --- Live KPI telemetry ----------------------------------------------------
var kpi_ad_watch_probability := 0.50 # Primary KPI: P(user watches ad to continue) [0..1]
var mercy_assist_chance := 0.35      # Current probability of spawning a combo-helping tile


func reset_for_new_run() -> void:
	recent_misses = 0
	wave_flaxes = 0
	ads_watched_this_run = 0
	tiles_since_last_slowy = 2
	slowy_spawns_this_wave = 0
	slowy_freed_this_run = 0
	slowy_trapped_in_play = false
	# If the user just failed previous run(s), carry over a softer starting difficulty
	# and higher mercy assist so they don't fail early again.
	if consecutive_failures > 0:
		var relief := clampf(float(consecutive_failures) * 0.14, 0.0, 0.42)
		difficulty_scale = clampf(1.0 - relief, 0.58, 1.25)
	else:
		difficulty_scale = clampf(lerpf(difficulty_scale, 1.0, 0.5), 0.75, 1.35)
	_recompute_mercy(1, 3, 0.0, 0.0)


## Called after every wave clear: increases difficulty for the new wave while keeping
## the player inside the optimal engagement channel.
func on_wave_completed(new_wave: int, lives_left: int, max_lives: int) -> void:
	total_waves_cleared += 1
	consecutive_failures = maxi(0, consecutive_failures - 1)

	# Flawless or low-miss wave signals high skill -> stronger wave-over-wave step-up.
	var wave_perf := clampf(1.0 - float(recent_misses) * 0.28 + float(lives_left) / float(maxi(1, max_lives)) * 0.25, 0.0, 1.0)
	skill_ema = lerpf(skill_ema, wave_perf, 0.35)
	frustration = maxf(0.0, frustration - 0.28)

	# Always increase difficulty on a new wave, scaled by how well the user played.
	var step_up := 0.06 + 0.08 * wave_perf
	difficulty_scale = clampf(difficulty_scale + step_up, 0.60, 1.65)

	recent_misses = 0
	wave_flaxes = 0
	slowy_spawns_this_wave = 0
	_recompute_mercy(new_wave, lives_left, 0.0, 0.0)


## Called whenever the player misses a tile or overflows a bin.
## Immediately softens pressure and boosts mercy assist if the player is struggling.
func on_life_lost(wave: int, lives_left: int, wave_progress_ratio: float, board_fill_ratio: float) -> void:
	recent_misses += 1
	frustration = clampf(frustration + 0.22, 0.0, 1.0)
	skill_ema = maxf(0.0, skill_ema - 0.08)

	# Dynamic intra-wave relief so a struggling user has a better chance of not failing the wave.
	var relief := 0.07 + 0.04 * float(mini(recent_misses, 4)) + 0.05 * float(consecutive_failures)
	difficulty_scale = clampf(difficulty_scale - relief, 0.55, 1.65)

	_recompute_mercy(wave, lives_left, wave_progress_ratio, board_fill_ratio)
	update_kpi(wave, lives_left, wave_progress_ratio, board_fill_ratio, 0, 0)


## Called when the player clears a combination: rewards flow and slightly relaxes frustration.
func on_combo_cleared(chain_depth: int) -> void:
	wave_flaxes += 1
	frustration = maxf(0.0, frustration - 0.06 * float(mini(chain_depth, 3)))
	skill_ema = clampf(skill_ema + 0.03 * float(mini(chain_depth, 3)), 0.0, 1.0)


## Called when the user fails a wave (runs out of lives and does not continue, or hits 0 lives).
func on_wave_failed(wave: int, wave_progress_ratio: float, board_fill_ratio: float, score: int, best_score: int) -> void:
	consecutive_failures += 1
	total_failures += 1
	frustration = clampf(frustration + 0.25, 0.0, 1.0)

	# Lower difficulty significantly so the next attempt or ad-continue feels winnable.
	var drop := 0.14 + 0.06 * float(mini(consecutive_failures, 4))
	difficulty_scale = clampf(difficulty_scale - drop, 0.52, 1.50)

	_recompute_mercy(wave, 0, wave_progress_ratio, board_fill_ratio)
	update_kpi(wave, 0, wave_progress_ratio, board_fill_ratio, score, best_score)


## Called when the player watches a rewarded ad to continue the current wave.
func on_ad_watched(wave: int, lives_restored: int, wave_progress_ratio: float) -> void:
	ads_watched_this_run += 1
	total_ads_watched += 1
	# Post-ad mercy boost: give the player a smoother runway right after watching an ad
	# so they feel rewarded and complete the wave.
	frustration = maxf(0.0, frustration - 0.35)
	difficulty_scale = clampf(difficulty_scale - 0.12, 0.55, 1.40)
	_recompute_mercy(wave, lives_restored, wave_progress_ratio, 0.3)


## Computes the wave belt speed (px/s), combining baseline wave progression, DDA scaling,
## and the 0.5x Slowy Helper Spirit speed reduction when `slowy_active` is true.
func get_belt_speed(wave: int, slowy_active: bool = false) -> float:
	var base := minf(BASE_BELT_SPEED + 18.0 * float(wave - 1), 380.0)
	var speed := clampf(base * difficulty_scale, MIN_BELT_SPEED, MAX_BELT_SPEED)
	if slowy_active:
		speed *= SLOWY_SPEED_FACTOR
	return speed


## Computes the tile spawn interval (s), combining baseline wave progression, DDA scaling,
## and wider spacing while Slowy is active so tiles don't crowd the half-speed belt.
func get_spawn_interval(wave: int, slowy_active: bool = false) -> float:
	var base := maxf(BASE_SPAWN_INTERVAL - 0.09 * float(wave - 1), 0.62)
	var interval := clampf(base / maxf(0.5, difficulty_scale), MIN_SPAWN_INTERVAL, MAX_SPAWN_INTERVAL)
	if slowy_active:
		interval *= 1.65
	return interval


## Returns the probability [0..1] that the next spawned conveyor tile should be chosen
## from colors that match the player's top bin tiles or held stack.
func get_helpful_color_probability(wave: int, lives_left: int, wave_progress_ratio: float, board_fill_ratio: float) -> float:
	_recompute_mercy(wave, lives_left, wave_progress_ratio, board_fill_ratio)
	return mercy_assist_chance


func _recompute_mercy(wave: int, lives_left: int, wave_progress_ratio: float, board_fill_ratio: float) -> void:
	var bias := BASE_HELPFUL_COLOR_BIAS
	# Increase helpful tiles when the user has failed recently or lost lives.
	bias += float(consecutive_failures) * 0.11
	bias += float(recent_misses) * 0.07
	bias += frustration * 0.18
	if lives_left <= 1:
		bias += 0.16
	# If bins are getting dangerously full (> 55%), feed matching colors so they can clear space.
	if board_fill_ratio > 0.55:
		bias += (board_fill_ratio - 0.55) * 0.45
	# If difficulty_scale is high and the player is cruising on early waves, slightly reduce mercy.
	if difficulty_scale > 1.15 and lives_left >= 3 and consecutive_failures == 0:
		bias -= (difficulty_scale - 1.15) * 0.20
	# Near the end of a wave (75%..95% progress), keep combo opportunities high so near-misses feel exciting.
	if wave_progress_ratio >= 0.75:
		bias += 0.06
	mercy_assist_chance = clampf(bias, MIN_HELPFUL_COLOR_BIAS, MAX_HELPFUL_COLOR_BIAS)


# ---------------------------------------------------------------------------
# Helper Spirit ("Slowy") Engagement & Unlock Logic
# ---------------------------------------------------------------------------

## Computes the probability [0..1] that a newly spawned conveyor tile carries trapped "Slowy".
## Integrates with DDA so Slowy appears more reliably when belt speed is high, when the player
## has lost lives or failed recent runs, or when the bins are filling up.
func get_slowy_spawn_probability(wave: int, lives_left: int, board_fill_ratio: float, slowy_busy: bool) -> float:
	if slowy_busy or tiles_since_last_slowy < 3:
		return 0.0
	var prob := 0.10 + 0.025 * float(mini(wave - 1, 8))
	if difficulty_scale > 1.0:
		prob += (difficulty_scale - 1.0) * 0.22
	prob += float(recent_misses) * 0.11
	prob += float(consecutive_failures) * 0.12
	prob += frustration * 0.22
	if lives_left <= 2:
		prob += 0.12
	if lives_left <= 1:
		prob += 0.16
	if board_fill_ratio > 0.45:
		prob += (board_fill_ratio - 0.45) * 0.40
	if slowy_spawns_this_wave == 0 and tiles_since_last_slowy >= 6:
		prob += 0.18
	return clampf(prob, 0.08, 0.78)


## Chooses which Klax combo type ("horizontal", "vertical", or "diagonal") is required
## to free Slowy from its trapped tile, adapting to player pressure.
func pick_slowy_combo_type(wave: int, lives_left: int, board_fill_ratio: float, roll: float = -1.0) -> String:
	var r := randf() if roll < 0.0 else clampf(roll, 0.0, 0.999)
	# Under high danger/frustration, favor vertical or horizontal so freeing Slowy is achievable.
	if lives_left <= 1 or board_fill_ratio >= 0.60 or frustration >= 0.45:
		if r < 0.52:
			return "vertical"
		elif r < 0.88:
			return "horizontal"
		return "diagonal"
	# Balanced mid-pressure distribution.
	if wave <= 2 or lives_left == 2:
		if r < 0.36:
			return "vertical"
		elif r < 0.78:
			return "horizontal"
		return "diagonal"
	# Skilled / cruising player on deeper waves: more horizontal & diagonal skill goals.
	if r < 0.24:
		return "vertical"
	elif r < 0.62:
		return "horizontal"
	return "diagonal"


func on_tile_spawned(has_slowy: bool) -> void:
	if has_slowy:
		tiles_since_last_slowy = 0
		slowy_spawns_this_wave += 1
		slowy_trapped_in_play = true
	else:
		tiles_since_last_slowy += 1


func on_slowy_freed(wave: int, lives_left: int) -> void:
	slowy_freed_this_run += 1
	slowy_trapped_in_play = false
	tiles_since_last_slowy = 0
	frustration = maxf(0.0, frustration - 0.22)
	skill_ema = clampf(skill_ema + 0.05, 0.0, 1.0)
	_recompute_mercy(wave, lives_left, 0.5, 0.3)


# ---------------------------------------------------------------------------
# Primary KPI Model: P(user watches rewarded ad to continue)
# ---------------------------------------------------------------------------

func update_kpi(wave: int, lives_left: int, wave_progress_ratio: float, board_fill_ratio: float, score: int, best_score: int) -> float:
	var prog := clampf(wave_progress_ratio, 0.0, 1.0)
	# Sunk-cost / near-miss effect: strongest driver of rewarded-ad continues.
	var near_miss := pow(prog, 0.75) * 0.42

	# Run depth & high-score chase investment.
	var wave_commit := (1.0 - exp(-float(wave) / 3.2)) * 0.24
	var score_ratio := clampf(float(score) / float(maxi(200, best_score)), 0.0, 1.25)
	var score_commit := score_ratio * 0.16

	# Tension / flow curve: an inverted-U around optimal arousal (frustration ~ 0.40, board fill ~ 0.55).
	var arousal := clampf(0.5 * frustration + 0.5 * board_fill_ratio, 0.0, 1.0)
	var flow_bonus := (1.0 - pow((arousal - 0.45) / 0.55, 2.0)) * 0.22

	# Unfinished micro-goal (Zeigarnik effect): if Slowy is trapped in play when the user fails,
	# or if Slowy helped them progress deeper in this run, continuation desire increases.
	var spirit_hook := (0.06 if slowy_trapped_in_play else 0.0) + minf(0.06, float(slowy_freed_this_run) * 0.03)

	# Penalty if the user is overwhelmed by consecutive unassisted failures (rage-quit risk).
	var churn_risk := maxf(0.0, float(consecutive_failures - 2) * 0.08)
	# Urgency factor when low on lives.
	var urgency := 0.10 if lives_left <= 1 else 0.0

	var raw := 0.12 + near_miss + wave_commit + score_commit + flow_bonus + spirit_hook + urgency - churn_risk
	var fatigue := pow(0.78, float(ads_watched_this_run))
	kpi_ad_watch_probability = clampf(raw * fatigue, 0.05, 0.98)
	return kpi_ad_watch_probability


## Whether to offer a rewarded-ad continue when lives reach 0.
func can_offer_ad_continue() -> bool:
	return ads_watched_this_run < 3
