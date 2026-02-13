
extends Node3D
class_name PlayerGun
# Signal for when the gun is fired, passing the shot direction
signal gun_fired(direction: Vector3)

const BULLET_VISUAL_SCENE := preload("res://scenes/bullet_visual.tscn")

@export var spin_speed_deg_per_sec: float = 180.0
@export var slow_time_scale: float = 0.25 # Minimum time scale (max slow)
@export var slow_time_max: float = 1.0   # Normal time scale (no slow)
@export var slow_time_spin_factor: float = 0.003 # How much spin speed affects slow (tune as needed)
@export var recoil_bounce_strength: float = 1.2
@export var recoil_return_speed: float = 0.35

@export var fire_cooldown_sec: float = 0.12
@export var ray_length: float = 200.0

@export var debug_raycast: bool = false

# Recoil movement (used as a positioning tool)
@export var recoil_move_strength: float = 22.0
@export var move_damping: float = 3.0
@export var max_speed: float = 16.0
@export var bounds_x: float = 5.0
@export var bounds_z: float = 2.75

@onready var muzzle: Node3D = get_node_or_null("Muzzle") as Node3D

var _spin_dir: float = 1.0
var _recoil: float = 0.0
var _x_spin_speed: float = 0.0
var _z_spin_speed: float = 0.0
var _fire_cooldown: float = 0.0

var _slow_touch_id: int = -1
var _fire_touch_id: int = -1

var _rotation_accum_rad: float = 0.0
var _rotation_bucket: int = 0

var _velocity: Vector3 = Vector3.ZERO

# Directional blending weights
@export_group("Gun Directional Blending")
@export var blend_vel_weight: float = 0.6
@export var blend_aim_weight: float = 0.4
@export var blend_y_weight: float = 0.0 # Set to >0 for vertical blending

var game: GameManager
var _bound_game: bool = false

func _ready() -> void:
	_bind_game()
	if muzzle == null:
		push_warning("PlayerGun is missing a child Node3D named 'Muzzle'")
	else:
		# Add a minimal arrow mesh to the muzzle to show the front
		var arrow = MeshInstance3D.new()
		arrow.mesh = ImmediateMesh.new()
		var arr = arrow.mesh as ImmediateMesh
		arr.clear_surfaces()
		arr.surface_begin(Mesh.PRIMITIVE_LINES)
		arr.surface_set_color(Color(1,0,0,1)) # Red
		arr.surface_add_vertex(Vector3.ZERO)
		arr.surface_add_vertex(Vector3(0,0,-0.6))
		arr.surface_set_color(Color(1,0,0,1))
		arr.surface_add_vertex(Vector3(0,0,-0.6))
		arr.surface_add_vertex(Vector3(0.08,0,-0.5))
		arr.surface_add_vertex(Vector3(0,0,-0.6))
		arr.surface_add_vertex(Vector3(-0.08,0,-0.5))
		arr.surface_end()
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arrow.material_override = StandardMaterial3D.new()
		arrow.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		arrow.material_override.albedo_color = Color(1,0,0,1)
		arrow.name = "DirectionArrow"
		muzzle.add_child(arrow)

func _bind_game() -> void:
	if _bound_game:
		return
	game = get_tree().get_first_node_in_group("game") as GameManager
	if game == null:
		call_deferred("_bind_game")
		return
	_bound_game = true

func _exit_tree() -> void:
	# Safety: don't leave global time slowed if the node is removed mid-touch.
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	# Spin around local Y at a constant pace
	var spin_step: float = deg_to_rad(spin_speed_deg_per_sec) * delta * _spin_dir
	rotate_object_local(Vector3.UP, spin_step)

	_rotation_accum_rad += absf(spin_step)
	var new_bucket: int = int(floor(_rotation_accum_rad / TAU))
	if new_bucket != _rotation_bucket:
		_rotation_bucket = new_bucket
		if game:
			game.register_rotation_bucket(_rotation_bucket)

	# X and Z axis spin from recoil, with falloff (use rotate_object_local to avoid gimbal lock)
	var x_spin_step: float = _x_spin_speed * delta
	var z_spin_step: float = _z_spin_speed * delta
	rotate_object_local(Vector3.RIGHT, x_spin_step)
	rotate_object_local(Vector3.BACK, z_spin_step)
	_x_spin_speed = lerpf(_x_spin_speed, 0.0, 1.0 - exp(-recoil_return_speed * delta))
	_z_spin_speed = lerpf(_z_spin_speed, 0.0, 1.0 - exp(-recoil_return_speed * delta))

	if _fire_cooldown > 0.0:
		_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	# Directional blending for movement
	var vel_dir: Vector3 = _velocity
	var aim_dir: Vector3 = -global_transform.basis.z

	# XZ blending
	var vel_xz := Vector3(vel_dir.x, 0.0, vel_dir.z)
	var aim_xz := Vector3(aim_dir.x, 0.0, aim_dir.z)
	var blend_xz := (vel_xz * blend_vel_weight + aim_xz * blend_aim_weight)
	if blend_xz.length() > 0.01:
		blend_xz = blend_xz.normalized()
	else:
		blend_xz = aim_xz.normalized()

	# Y blending (optional)
	var blend_y := vel_dir.y * (1.0 - blend_y_weight) + aim_dir.y * blend_y_weight

	# Final blended direction
	var blended_dir := Vector3(blend_xz.x, blend_y, blend_xz.z)

	# Recoil-driven movement
	if _velocity.length() > 0.001:
		var new_pos: Vector3 = global_position + blended_dir * _velocity.length() * delta
		set_global_position(new_pos)
		_velocity = _velocity.move_toward(Vector3.ZERO, move_damping * delta)
		if _velocity.length() > max_speed:
			_velocity = _velocity.normalized() * max_speed

	print("[PlayerGun] global_position:", global_position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventMouseButton:
		_handle_mouse(event as InputEventMouseButton)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)

func _handle_touch(ev: InputEventScreenTouch) -> void:
	var is_left_side := ev.position.x < (get_viewport().get_visible_rect().size.x * 0.5)
	if ev.pressed:
		if is_left_side and _slow_touch_id == -1:
			_slow_touch_id = ev.index
			_set_slow_time(true)
		elif (not is_left_side) and _fire_touch_id == -1:
			_fire_touch_id = ev.index
			_try_fire()
	else:
		if ev.index == _slow_touch_id:
			_slow_touch_id = -1
			_set_slow_time(false)
		if ev.index == _fire_touch_id:
			_fire_touch_id = -1

func _handle_mouse(ev: InputEventMouseButton) -> void:
	if ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if ev.pressed:
		var is_left_side := ev.position.x < (get_viewport().get_visible_rect().size.x * 0.5)
		if is_left_side:
			_set_slow_time(true)
		else:
			_try_fire()
	else:
		_set_slow_time(false)

func _handle_key(ev: InputEventKey) -> void:
	if ev.keycode == KEY_SHIFT:
		_set_slow_time(ev.pressed)
	elif ev.pressed and ev.keycode == KEY_SPACE:
		_try_fire()

func _set_slow_time(enabled: bool) -> void:
	if enabled:
		# Calculate spin speed (Y axis only, in deg/sec)
		var spin_speed: float = abs(spin_speed_deg_per_sec)
		var slow: float = clampf(slow_time_max - spin_speed * slow_time_spin_factor, slow_time_scale, slow_time_max)
		Engine.time_scale = slow
		if enabled and muzzle != null:
			# Emit gun_fired signal with the full 3D direction to trigger camera pan and tilt
			emit_signal("gun_fired", -muzzle.global_transform.basis.z)
	else:
		Engine.time_scale = 1.0

func _try_fire() -> void:
	if _fire_cooldown > 0.0:
		return
	if game and not game.can_fire():
		return

	_fire_cooldown = fire_cooldown_sec
	var prev_spin_dir := _spin_dir
	_spin_dir *= -1.0

	# Only apply recoil based on firing, not spin direction
	_recoil = clampf(_recoil + recoil_bounce_strength, 0.0, 0.35)

	if game:
		game.consume_bullet()

	_spawn_bullet_visual()
	_apply_recoil_impulse()

	# Emit signal with the shot direction (negative Z of muzzle)
	if muzzle != null:
		emit_signal("gun_fired", -muzzle.global_transform.basis.z)

	_fire_ray()

func _apply_recoil_impulse() -> void:
	# When firing, reset momentum and dictate new velocity from shot direction
	if muzzle == null:
		return
	var recoil_dir: Vector3 = muzzle.global_transform.basis.z
	if recoil_dir.length() < 0.001:
		return
	recoil_dir = recoil_dir.normalized()

	# Set velocity to only the new shot's impulse (ignore previous momentum)
	var upward_impulse: Vector3 = Vector3.UP * recoil_move_strength * 0.18
	var backward_impulse: Vector3 = recoil_dir * recoil_move_strength * 0.22
	_velocity = backward_impulse + upward_impulse

	# Stronger backspin: increase X-axis spin speed impact
	_x_spin_speed += recoil_bounce_strength * 14.0
	_z_spin_speed += recoil_bounce_strength * 2.0

	# Tell the camera to rotate toward the bullet direction
	var cam := get_node_or_null("Camera")
	if cam != null and cam.has_method("set_look_direction"):
		cam.set_look_direction(-muzzle.global_transform.basis.z)

func _spawn_bullet_visual() -> void:
	if muzzle == null:
		return
	var bullet := BULLET_VISUAL_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = muzzle.global_transform
	bullet.set("direction", -muzzle.global_transform.basis.z)

func _fire_ray() -> void:
	if muzzle == null:
		return
	var origin := muzzle.global_position
	var dir := -muzzle.global_transform.basis.z
	var to := origin + dir * ray_length

	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var w := get_world_3d()
	if w == null:
		return
	var raw := w.direct_space_state.intersect_ray(query)
	# Defensive: some engine/platforms may return non-dictionary for empty/no-hit.
	if not (raw is Dictionary):
		if debug_raycast:
			print("[PlayerGun] intersect_ray returned non-dictionary:", raw, "Engine:", Engine.get_version_info())
		return
	var result: Dictionary = raw
	if result.is_empty():
		return

	# Safer access: ensure collider exists before indexing to satisfy analyzers.
	if not result.has("collider"):
		return
	var collider: Object = result["collider"]
	if collider is Area3D:
		var area := collider as Area3D
		var enemy := area.get_parent()
		while enemy != null and not (enemy is Enemy):
			enemy = enemy.get_parent()
		if enemy is Enemy:
			var is_headshot := area.is_in_group("hitbox_head")
			(enemy as Enemy).take_hit(is_headshot)
