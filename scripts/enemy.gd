extends Node3D
class_name Enemy

signal died(is_headshot: bool)

enum EnemyType { BASIC, ARMOURED, BASIC_SHIELD, ARMOURED_SHIELD }

@export var enemy_type: EnemyType = EnemyType.BASIC

var _hp: int = 1
var _shield_hp: int = 0
var _dead: bool = false

func _ready() -> void:
	add_to_group("enemies")
	match enemy_type:
		EnemyType.BASIC:
			_hp = 1
			_shield_hp = 0
		EnemyType.ARMOURED:
			_hp = 2
			_shield_hp = 0
		EnemyType.BASIC_SHIELD:
			_hp = 1
			_shield_hp = 1
		EnemyType.ARMOURED_SHIELD:
			_hp = 2
			_shield_hp = 1

func take_hit(is_headshot: bool) -> void:
	if is_headshot:
		die(true)
		return

	if _shield_hp > 0:
		_shield_hp -= 1
		# Quick visual cue by scaling a bit.
		scale *= 0.92
		return

	_hp -= 1
	if _hp <= 0:
		die(false)
	else:
		# Small flinch.
		rotation.y += deg_to_rad(12)

func die(is_headshot: bool) -> void:
	if _dead:
		return
	_dead = true
	if not is_inside_tree():
		return
	remove_from_group("enemies")
	var game := get_tree().get_first_node_in_group("game") as GameManager
	if game:
		game.register_kill(is_headshot)
	emit_signal("died", is_headshot)
	queue_free()
