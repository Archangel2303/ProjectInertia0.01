extends Control

@onready var level1_button: Button = $Root/Buttons/Level1Button
@onready var endless_button: Button = $Root/Buttons/EndlessButton

func _ready() -> void:
	level1_button.pressed.connect(Callable(self, "_on_level1_pressed"))
	endless_button.pressed.connect(Callable(self, "_on_endless_pressed"))

func _on_level1_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/level_01.tscn")

func _on_endless_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/endless.tscn")
