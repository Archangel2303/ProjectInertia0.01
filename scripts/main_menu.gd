extends Control

@onready var level1_button: Button = $Root/Buttons/Level1Button
@onready var endless_button: Button = $Root/Buttons/EndlessButton

func _ready() -> void:
	level1_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/levels/level_01.tscn"))
	endless_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/levels/endless.tscn"))
