
extends CharacterBody3D
class_name PlayerGun
# Signal for when the gun is fired, passing the shot direction
signal gun_fired(direction: Vector3)

const BULLET_VISUAL_SCENE := preload("res://scenes/bullet_visual.tscn")

@export var spin_speed_deg_per_sec: float = 180.0 # Visual spin speed (deg/sec). Increase to make the gun rotate faster; raises perceived motion and slow-time effect.
@export var slow_time_scale: float = 0.002 # Minimum time_scale when slow is active. Lower = stronger slow-motion; don't set to 0.
@export var slow_time_max: float = 1.0   # Normal time_scale (no slow). Keep at 1.0 for real-time playback.
@export var slow_time_spin_factor: float = 0.012 # How much spin reduces time_scale. Increase to tie spin strength to slowdown more tightly.
@export var recoil_bounce_strength: float = 0.9 # Scales rotational/spin impulses from firing and bounces. Higher = snappier rotational response.
@export var recoil_return_speed: float = 0.35 # Rate at which spin speeds lerp back to zero. Higher = quicker return to rest.

@export var fire_cooldown_sec: float = 0.12 # Seconds between allowed shots. Lower = faster firing rate.
@export var ray_length: float = 200.0 # Raycast distance for hit checks. Increase for longer-range hits.

@export var debug_raycast: bool = false # Enable to print raycast debug info to console.

# Recoil movement (used as a positioning tool)
@export var recoil_move_strength: float = 18.0 # Base magnitude of spatial impulse when firing. Increase to make each shot move the gun farther.
@export var move_damping: float = 1.8 # How quickly internal velocity decays toward zero. Higher = less floaty, faster stop.
@export var max_speed: float = 15.0 # Hard cap for internal velocity magnitude. Lower this to limit extreme motion.
@export var area_bounce_damping: float = 0.30 # Multiplier applied when bouncing off Area3D hitboxes (enemy parts). Lower = stronger bounce back.
@export var ray_bounce_damping: float = 0.25  # Multiplier applied to reflected vector from raycast collisions. Lower = stronger bounce from walls.
@export var bounds_x: float = 5.0 # Horizontal limit (X) from home position. Reduce to keep the gun closer to its origin.
@export var bounds_z: float = 2.75 # Depth limit (Z) from home position. Reduce to limit forward/backward travel.

# Bounce rotation tuning
@export var bounce_spin_scale: float = 0.6 # Scales rotational impulse applied on bounce. Increase to make bounces add more rotational energy.
@export var bounce_spin_random: float = 0.15 # Random jitter applied to bounce spin to avoid repetitive motion; keep small (0-0.5).

@onready var muzzle: Node3D = _find_descendant_node("Muzzle") as Node3D

func _find_descendant_node(target_name: String) -> Node:
	var lname := target_name.to_lower()
	for child in get_children():
		var found := _search_node_recursive(child, lname)
		if found != null:
			return found
	return null

func _search_node_recursive(node: Node, lname: String) -> Node:
	if node.name.to_lower() == lname:
		return node
	for c in node.get_children():
		var f := _search_node_recursive(c, lname)
		if f != null:
			return f
	return null

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
@export var blend_vel_weight: float = 0.6 # Weight of `_velocity` direction when computing movement direction. Higher = motion follows impulse more.
@export var blend_aim_weight: float = 0.4 # Weight of aim (muzzle forward) when computing movement direction. Higher = gun tries to align with aim.
@export var blend_y_weight: float = 0.0 # Vertical blending between velocity.y and aim.y. Set >0 to let vertical aim influence vertical movement.

var game: GameManager
var _bound_game: bool = false

func _ready() -> void:
	_bind_game()
	if muzzle == null:
		push_warning("PlayerGun is missing a child Node3D named 'Muzzle'")
	else:
		# ...existing code...
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

	# Connect any Area3D hitboxes under the gun (supporting multi-part hitbox names)
	var gun_areas: Array = _find_gun_areas()
	if gun_areas.size() > 0:
		for a in gun_areas:
			if a != null:
				a.connect("area_entered", Callable(self, "_on_gun_area_entered"))
	else:
		push_warning("PlayerGun: no Area3D hitboxes found under PlayerGun; melee/area collisions may not work")

func _find_gun_areas() -> Array:
	var matches: Array = []
	var whitelist := ["gunbarreltiphitbox", "gunbarrelmidfarhitbox", "gunbarrelmidclosehitbox", "gunbarrelstemhitbox", "gunchamberhitbox", "guntriggerhitbox", "guncollisionshape3d"]
	for child in get_children():
		_collect_areas_recursive(child, whitelist, matches)
	return matches

func _collect_areas_recursive(node: Node, whitelist: Array, out_arr: Array) -> void:
	if node is Area3D:
		var lname := node.name.to_lower()
		if lname.find("gun") >= 0 or whitelist.has(lname):
			out_arr.append(node as Area3D)
	for c in node.get_children():
		_collect_areas_recursive(c, whitelist, out_arr)

	# Connect enemy died signal for camera focus
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy != null:
			enemy.connect("died", Callable(self, "_on_enemy_died"))
# Camera focus handler for enemy death
func _on_enemy_died(_is_headshot: bool) -> void:
	var cam := get_node_or_null("Camera")
	if cam != null and cam.has_method("set_look_direction"):
		var enemies: Array = get_tree().get_nodes_in_group("enemies")
		var best_enemy: Enemy = null
		var best_dot: float = -1.0
		var cam_pos: Vector3 = cam.global_position
		var cam_forward: Vector3 = -cam.global_transform.basis.z
		for enemy in enemies:
			if enemy == null or enemy._dead:
				continue
			var to_enemy: Vector3 = (enemy.global_position - cam_pos).normalized()
			var dot: float = cam_forward.dot(to_enemy)
			if dot > 0.5 and dot > best_dot:
				best_dot = dot
				best_enemy = enemy
		if best_enemy:
			cam.set_look_direction((best_enemy.global_position - cam_pos).normalized())
# Called when GunArea3D enters another Area3D (enemy hitbox)
func _on_gun_area_entered(area: Area3D) -> void:
	# Check if area is part of enemy hitbox groups
	if area.is_in_group("hitbox_head") or area.is_in_group("hitbox_body") or area.is_in_group("hitbox_limb"):
		# Apply bounce effect: reverse velocity and add rotational impulse
		var incoming := _velocity
		_velocity = -incoming * area_bounce_damping # Bounce back with damping
		_apply_bounce_rotation_from_velocity(incoming)
		print("[PlayerGun] Bounced off enemy hitbox!")

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


func _physics_process(delta: float) -> void:
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

	# Recoil-driven movement — use physics movement so collisions apply
	if _velocity.length() > 0.001:
		var speed: float = _velocity.length()
		var move_vec: Vector3 = blended_dir * speed
		# Pre-check for impending collisions using a short raycast along the travel vector.
		var travel: Vector3 = move_vec * delta
		var w := get_world_3d()
		var collided: bool = false
		if w != null:
			var origin: Vector3 = global_position
			var to_pos: Vector3 = origin + travel
			var query := PhysicsRayQueryParameters3D.create(origin, to_pos)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var raw := w.direct_space_state.intersect_ray(query)
			if raw is Dictionary and not raw.is_empty():
				# Reflect the move vector around the collision normal to produce a bounce
				var normal: Vector3 = raw.get("normal", Vector3.UP).normalized()
				# Reflect move_vec around the collision normal: r = v - 2*(v·n)*n
				var reflected: Vector3 = move_vec - 2.0 * move_vec.dot(normal) * normal
				# Damp the reflected speed a bit to simulate energy loss
				reflected *= ray_bounce_damping
				velocity = reflected
				# Mirror the internal impulse so subsequent frames continue the bounce
				_velocity = reflected
				# Add rotational impulse derived from the collision
				_apply_bounce_rotation_from_velocity(move_vec, normal)
				collided = true
		# If nothing collided this frame, proceed normally
		if not collided:
			velocity = move_vec
		# Execute physics move
		move_and_slide()
		# Decay the impulse driver separately
		_velocity = _velocity.move_toward(Vector3.ZERO, move_damping * delta)
		if _velocity.length() > max_speed:
			_velocity = _velocity.normalized() * max_speed

	# (Optional) debug print of the physics position
	# print("[PlayerGun] global_position:", global_position)


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
	var gun_top_dir: Vector3 = muzzle.global_transform.basis.y
	if recoil_dir.length() < 0.001 or gun_top_dir.length() < 0.001:
		return
	recoil_dir = recoil_dir.normalized()
	gun_top_dir = gun_top_dir.normalized()

	# Additive impulse: backwards and towards gun's top
	var top_impulse: Vector3 = gun_top_dir * recoil_move_strength * 0.18
	var backward_impulse: Vector3 = recoil_dir * recoil_move_strength * 0.22
	_velocity += backward_impulse + top_impulse
	# Clamp velocity to avoid exploding speeds
	if _velocity.length() > max_speed:
		_velocity = _velocity.normalized() * max_speed

	# Stronger backspin: increase X-axis spin speed impact
	_x_spin_speed += recoil_bounce_strength * 14.0
	_z_spin_speed += recoil_bounce_strength * 2.0

	# Camera focus logic: after firing, if an enemy was killed, focus on another visible enemy
	var cam := get_node_or_null("Camera")
	if cam != null and cam.has_method("set_look_direction"):
		var killed_enemy: Enemy = null
		# Check if last shot killed an enemy (optional: you may need to track this via signal)
		# Find all enemies in group
		var enemies: Array = get_tree().get_nodes_in_group("enemies")
		var best_enemy: Enemy = null
		var best_dot: float = -1.0
		var cam_pos: Vector3 = cam.global_position
		var cam_forward: Vector3 = -cam.global_transform.basis.z
		for enemy in enemies:
			if enemy == null or enemy == killed_enemy or enemy._dead:
				continue
			var to_enemy: Vector3 = (enemy.global_position - cam_pos).normalized()
			var dot: float = cam_forward.dot(to_enemy)
			if dot > 0.5 and dot > best_dot:
				best_dot = dot
				best_enemy = enemy
		if best_enemy:
			cam.set_look_direction((best_enemy.global_position - cam_pos).normalized())
		else:
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
	if not (raw is Dictionary):
		if debug_raycast:
			print("[PlayerGun] intersect_ray returned non-dictionary:", raw, "Engine:", Engine.get_version_info())
		return
	var result: Dictionary = raw
	if result.is_empty():
		return

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
			# Check if enemy will die from this shot (1 HP, no shield, or headshot)
			var will_die: bool = (enemy._hp == 1 and enemy._shield_hp == 0) or is_headshot
			if will_die:
				# Camera focus logic for kill: maximize visible enemies
				var cam := get_node_or_null("Camera")
				if cam != null and cam.has_method("set_look_direction"):
					var enemies: Array = get_tree().get_nodes_in_group("enemies")
					var cam_pos: Vector3 = cam.global_position
					var best_dir: Vector3 = Vector3.ZERO
					var max_visible: int = 0
					# Try several directions and pick the one that keeps most enemies in view
					for i in range(16):
						var angle: float = i * (TAU / 16)
						var test_dir: Vector3 = Vector3(sin(angle), 0, -cos(angle)).normalized()
						var visible_count: int = 0
						for other_enemy in enemies:
							if other_enemy == null or other_enemy == enemy or other_enemy._dead:
								continue
							var to_enemy: Vector3 = (other_enemy.global_position - cam_pos).normalized()
							var dot: float = test_dir.dot(to_enemy)
							if dot > 0.5:
								visible_count += 1
						if visible_count > max_visible:
							max_visible = visible_count
							best_dir = test_dir
					if max_visible > 0:
						cam.set_look_direction(best_dir)
				enemy.take_hit(is_headshot)
				return
			enemy.take_hit(is_headshot)


func _apply_bounce_rotation_from_velocity(vel: Vector3, normal: Vector3 = Vector3.ZERO) -> void:
	if vel.length() < 0.001:
		return
	var n: Vector3 = normal
	if n == Vector3.ZERO:
		n = -vel.normalized()
	else:
		n = n.normalized()

	var axis_world: Vector3 = vel.cross(n)
	if axis_world.length() < 0.001:
		axis_world = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)

	var axis_world_n: Vector3 = axis_world.normalized()
	var axis_local: Vector3 = Vector3(
		axis_world_n.dot(global_transform.basis.x),
		axis_world_n.dot(global_transform.basis.y),
		axis_world_n.dot(global_transform.basis.z)
	)
	var mag: float = vel.length()
	var rand_component: float = (randf() - 0.5) * 2.0 * bounce_spin_random
	var factor: float = bounce_spin_scale * mag * recoil_bounce_strength * (1.0 + rand_component)

	_x_spin_speed += axis_local.x * factor
	_z_spin_speed += axis_local.z * factor
	# Adjust overall spin direction from the Y component of the axis
	_spin_dir = -1.0 if axis_local.y < 0.0 else 1.0
