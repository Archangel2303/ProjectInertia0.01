extends CanvasLayer

@onready var ammo_label: Label = $UI/TopRow/AmmoLabel
@onready var score_label: Label = $UI/TopRow/ScoreLabel
@onready var time_label: Label = $UI/TopRow/TimeLabel
@onready var status_label: Label = $UI/Center/CenterVBox/StatusLabel
@onready var high_label: Label = $UI/Center/CenterVBox/HighLabel
@onready var hint_label: Label = $UI/Bottom/HintLabel

var _game: GameManager
var _bound: bool = false

func _ready() -> void:
	_bind_game()
	_hint_defaults()

func _bind_game() -> void:
	if _bound:
		return
	_game = get_tree().get_first_node_in_group("game") as GameManager
	if _game == null:
		call_deferred("_bind_game")
		return

	_game.ammo_changed.connect(_on_ammo_changed)
	_game.score_changed.connect(_on_score_changed)
	_game.status_changed.connect(_on_status_changed)
	_game.level_completed.connect(_on_level_completed)
	_game.level_failed.connect(_on_level_failed)
	_bound = true

func _process(_delta: float) -> void:
	if _game and not _game.is_queued_for_deletion():
		time_label.text = "Time: %.1fs" % _game.level_time_sec

func _on_ammo_changed(current: int, max_ammo: int) -> void:
	ammo_label.text = "Ammo: %d/%d" % [current, max_ammo]

func _on_score_changed(score: int) -> void:
	score_label.text = "Score: %d" % score

func _on_status_changed(text: String) -> void:
	status_label.text = text

func _on_level_completed(final_score: int, new_high_score: bool, high_score: int) -> void:
	high_label.text = "High: %d%s" % [high_score, " (NEW)" if new_high_score else ""]
	hint_label.text = "Tap / Click to restart"

func _on_level_failed(_final_score: int) -> void:
	var level_key := _game.level_id if _game != null else "level_01"
	high_label.text = "High: %d" % SaveData.get_high_score(level_key)
	hint_label.text = "Tap / Click to restart"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_restart()
	elif event is InputEventMouseButton and event.pressed:
		_restart()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_R:
		_restart()

func _restart() -> void:
	if status_label.text == "":
		return
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _hint_defaults() -> void:
	hint_label.text = "Left half: slow time | Right half: fire" + "\n" + "(Space: fire, Shift: slow, R: restart)"
