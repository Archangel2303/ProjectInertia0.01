extends Node3D
class_name EnemySpawner

@export var enemy_scene: PackedScene
@export var spawn_radius: float = 6.0
@export var spawn_z: float = -18.0
@export var spawn_interval_sec: float = 1.1

var _t: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func _process(delta: float) -> void:
	if enemy_scene == null:
		return
	_t += delta
	if _t >= spawn_interval_sec:
		_t = 0.0
		_spawn_enemy()

func _spawn_enemy() -> void:
	var e := enemy_scene.instantiate() as Node3D
	add_child(e)
	var x := _rng.randf_range(-spawn_radius, spawn_radius)
	var y := _rng.randf_range(-1.0, 1.0)
	e.global_position = global_position + Vector3(x, y, spawn_z)
