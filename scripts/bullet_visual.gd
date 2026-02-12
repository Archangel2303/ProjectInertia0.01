extends Node3D
class_name BulletVisual

@export var speed: float = 40.0
@export var lifetime_sec: float = 0.7

var direction: Vector3 = Vector3.FORWARD

var _t: float = 0.0

func _process(delta: float) -> void:
	global_position += direction * speed * delta
	_t += delta
	if _t >= lifetime_sec:
		queue_free()
