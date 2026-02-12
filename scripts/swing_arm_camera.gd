extends Camera3D
class_name SwingArmCamera

@export var follow_distance: float = 8.5
@export var follow_height: float = 1.2
@export var look_lerp_speed: float = 24.0

var _target: Node3D
var _desired_look_dir: Vector3 = Vector3.FORWARD
var _current_look_dir: Vector3 = Vector3.FORWARD

func _ready() -> void:
	# Try to find PlayerGun directly in the scene tree
	_target = get_tree().get_current_scene().get_node_or_null("PlayerGun")
	if _target == null:
		push_warning("SwingArmCamera could not find PlayerGun node in scene tree")
		return
	_desired_look_dir = -_target.global_transform.basis.z
	_current_look_dir = _desired_look_dir
	_update_position()
	fov = 82.0

func _process(delta: float) -> void:
	if _target == null:
		return
	_update_position()
	_update_rotation(delta)

func _update_position() -> void:
	# Place camera behind and above the gun, but ignore PlayerGun's Y rotation for camera placement
	var gun_pos := _target.global_position
	# Use a fixed back vector (e.g., Vector3.FORWARD) instead of PlayerGun's rotation
	var back := Vector3.FORWARD
	global_position = gun_pos - back * follow_distance + Vector3.UP * follow_height
	print("[SwingArmCamera] Camera position:", global_position, " Player position:", gun_pos)

func _update_rotation(_delta: float) -> void:
	var gun_pos := _target.global_position
	# Smoothly lerp the look direction toward the desired direction
	_current_look_dir = _current_look_dir.slerp(_desired_look_dir, clampf(look_lerp_speed * _delta, 0.0, 1.0))
	var look_target := gun_pos + _current_look_dir.normalized() * 12.0
	look_at(look_target, Vector3.UP)

func set_look_direction(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	_desired_look_dir = dir.normalized()
	_current_look_dir = _desired_look_dir
