extends Node
class_name GameManager

signal ammo_changed(current: int, max_ammo: int)
signal score_changed(score: int)
signal status_changed(text: String)
signal level_completed(final_score: int, new_high_score: bool, high_score: int)
signal level_failed(final_score: int)

@export var level_id: String = "level_01"
@export var max_ammo: int = 5
@export var starting_ammo: int = 5

@export var auto_complete_on_clear: bool = true

@export var points_kill: int = 100
@export var points_headshot_bonus: int = 50
@export var points_rotation_multikill_bonus: int = 40
@export var points_time_multikill_bonus: int = 25

@export var multikill_window_sec: float = 1.25

var ammo: int
var score: int = 0

var level_time_sec: float = 0.0

var _kills_this_rotation: int = 0
var _last_rotation_bucket: int = 0

var _time_multikill_streak: int = 0
var _time_multikill_timer: float = 0.0

var _is_over: bool = false

func _ready() -> void:
	add_to_group("game")
	ammo = clampi(starting_ammo, 0, max_ammo)
	emit_signal("ammo_changed", ammo, max_ammo)
	emit_signal("score_changed", score)
	emit_signal("status_changed", "")

func _process(delta: float) -> void:
	if _is_over:
		return
	level_time_sec += delta
	if _time_multikill_timer > 0.0:
		_time_multikill_timer = maxf(0.0, _time_multikill_timer - delta)
		if _time_multikill_timer == 0.0:
			_time_multikill_streak = 0

func can_fire() -> bool:
	return (not _is_over) and ammo > 0

func consume_bullet() -> void:
	if _is_over:
		return
	ammo = maxi(0, ammo - 1)
	emit_signal("ammo_changed", ammo, max_ammo)
	if ammo == 0:
		# Defer the failure check to allow a last-bullet kill to remove the final enemy.
		call_deferred("_check_fail_deferred")

func _check_fail_deferred() -> void:
	if _is_over:
		return
	if ammo != 0:
		return
	if get_tree().get_nodes_in_group("enemies").size() > 0:
		fail_level()

func register_rotation_bucket(bucket: int) -> void:
	# Bucket increments each time the gun crosses another full 360deg.
	if bucket != _last_rotation_bucket:
		_last_rotation_bucket = bucket
		_kills_this_rotation = 0

func register_kill(is_headshot: bool) -> void:
	if _is_over:
		return

	score += points_kill
	if is_headshot:
		score += points_headshot_bonus
		ammo = mini(max_ammo, ammo + 1)
		emit_signal("ammo_changed", ammo, max_ammo)

	# Multikill before 360deg rotation
	_kills_this_rotation += 1
	if _kills_this_rotation >= 2:
		score += points_rotation_multikill_bonus

	# Multikill within time window
	if _time_multikill_timer > 0.0:
		_time_multikill_streak += 1
		score += points_time_multikill_bonus * _time_multikill_streak
	else:
		_time_multikill_streak = 0
	_time_multikill_timer = multikill_window_sec

	emit_signal("score_changed", score)

	# Level completes when no enemies remain.
	if auto_complete_on_clear and get_tree().get_nodes_in_group("enemies").size() == 0:
		complete_level()

func complete_level() -> void:
	if _is_over:
		return
	_is_over = true
	Engine.time_scale = 1.0

	# Time bonus (simple linear falloff)
	var time_bonus := maxi(0, int(1000 - level_time_sec * 40.0))
	score += time_bonus
	emit_signal("score_changed", score)

	var prev_high := SaveData.get_high_score(level_id)
	var is_new_high := score > prev_high
	if is_new_high:
		SaveData.set_high_score(level_id, score)
	var high := maxi(prev_high, score)

	emit_signal("status_changed", "LEVEL CLEAR")
	emit_signal("level_completed", score, is_new_high, high)

func fail_level() -> void:
	if _is_over:
		return
	_is_over = true
	Engine.time_scale = 1.0
	emit_signal("status_changed", "OUT OF AMMO")
	emit_signal("level_failed", score)
