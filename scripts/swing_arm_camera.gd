extends Camera3D
class_name SwingArmCamera
 
var _slow_time_active: bool = false
var _slow_time_timer: float = 0.0
var _fired_timer: float = 0.0

@export_group("Camera Event Effects")
@export var slow_time_fov_boost: float = 8.0
@export var slow_time_duration: float = 0.25
@export var fired_shake_strength: float = 0.04
@export var fired_shake_duration: float = 0.12

func set_slow_time(enabled: bool) -> void:
	if enabled and _target != null:
		set_look_direction(-_target.global_transform.basis.z)
	_slow_time_active = enabled
	if enabled:
		_slow_time_timer = slow_time_duration
	else:
		_slow_time_timer = 0.0

func on_fired() -> void:
	_fired_timer = fired_shake_duration

# Camera state machine
enum CameraState { DRIFT, LAUNCH, IMPACT_STABILIZE }
var _state: CameraState = CameraState.DRIFT
var _state_timer: float = 0.0
var _impact_timer: float = 0.0

# Tuning variables
@export_group("Camera State Thresholds")
@export var drift_threshold: float = 4.0
@export var launch_threshold: float = 8.0
@export var impact_threshold: float = 12.0
@export var drift_hysteresis: float = 0.25
@export var launch_hysteresis: float = 0.25
@export var impact_duration: float = 0.15



@export_group("Camera State Tuning")
# DRIFT
@export var drift_distance: float = 7.0
 # Removed unused variable drift_lookahead
@export var drift_yaw_cap: float = 60.0
@export var drift_damping: float = 0.18
# LAUNCH
@export var launch_distance: float = 10.0
 # Removed unused variable launch_lookahead
@export var launch_yaw_cap: float = 30.0
@export var launch_damping: float = 0.32
# IMPACT
@export var impact_distance: float = 8.0
 # Removed unused variable impact_lookahead
@export var impact_yaw_cap: float = 20.0
@export var impact_damping: float = 0.5

# Orbit camera tuning
@export_group("Camera Orbit")
@export var orbit_pitch_deg: float = 18.0 # Elevation angle above the gun
var _target_pitch_deg: float = 18.0 # Target pitch for smoothing
var pitch_lerp_speed: float = 6.0 # Smoothing factor for pitch changes
@export var orbit_lerp_speed: float = 8.0 # How fast the camera orbits to new direction

@export var follow_height: float = 1.2
@export var look_lerp_speed: float = 24.0

var _target: Node3D
var _desired_look_dir: Vector3 = Vector3.FORWARD
var _current_look_dir: Vector3 = Vector3.FORWARD
# Orbit state
var _current_orbit_yaw: float = 0.0 # radians
var _target_orbit_yaw: float = 0.0 # radians

# State weights
@export_group("Camera Direction Weights")
@export var drift_vel_weight: float = 0.4
@export var drift_aim_weight: float = 0.6
@export var launch_vel_weight: float = 0.7
@export var launch_aim_weight: float = 0.3
@export var impact_vel_weight: float = 0.5
@export var impact_aim_weight: float = 0.5

func _ready() -> void:
	# Try to find PlayerGun directly in the scene tree
	_target = get_tree().get_current_scene().get_node_or_null("PlayerGun")
	if _target == null:
		push_warning("SwingArmCamera could not find PlayerGun node in scene tree")
		return
	_desired_look_dir = -_target.global_transform.basis.z
	_current_look_dir = _desired_look_dir
	# Initialize orbit yaw from initial look direction
	_current_orbit_yaw = atan2(_desired_look_dir.x, _desired_look_dir.z)
	_target_orbit_yaw = _current_orbit_yaw
	# Connect to PlayerGun's gun_fired signal
	if _target.has_signal("gun_fired"):
		_target.connect("gun_fired", Callable(self, "_on_gun_fired"))
	_update_position()
	fov = 82.0

# Handler for gun fired event
func _on_gun_fired(direction: Vector3) -> void:
	set_look_direction(direction)

func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var speed: float = 0.0
	if _target.has_method("get_linear_velocity"):
		speed = _target.get_linear_velocity().length()
	elif _target.has_method("linear_velocity"):
		speed = _target.linear_velocity.length()

	# State transitions
	match _state:
		CameraState.DRIFT:
			if speed > launch_threshold + launch_hysteresis:
				_state = CameraState.LAUNCH
				_state_timer = 0.0
			elif _impact_timer > 0.0:
				_state = CameraState.IMPACT_STABILIZE
				_state_timer = 0.0
		CameraState.LAUNCH:
			if speed < drift_threshold - drift_hysteresis:
				_state = CameraState.DRIFT
				_state_timer = 0.0
			elif _impact_timer > 0.0:
				_state = CameraState.IMPACT_STABILIZE
				_state_timer = 0.0
		CameraState.IMPACT_STABILIZE:
			_impact_timer -= delta
			if _impact_timer <= 0.0:
				# Return to DRIFT or LAUNCH based on speed
				if speed > launch_threshold:
					_state = CameraState.LAUNCH
				else:
					_state = CameraState.DRIFT

	# Impact timer update
	if _impact_timer > 0.0:
		_impact_timer -= delta


	# Handle temporary event effects
	if _slow_time_active:
		_slow_time_timer -= delta
		if _slow_time_timer <= 0.0:
			_slow_time_active = false
			_slow_time_timer = 0.0
	if _fired_timer > 0.0:
		_fired_timer -= delta
		if _fired_timer < 0.0:
			_fired_timer = 0.0



	_update_position()
	_update_rotation(delta)

	# Subtle FOV boost for slow time
	if _slow_time_active:
		fov = 82.0 + slow_time_fov_boost
	else:
		fov = 82.0

func on_impact(impulse: float) -> void:
	if impulse > impact_threshold:
		_impact_timer = impact_duration
		# Optionally, add a subtle FOV or shake effect here if desired

func _update_position() -> void:
	# Orbit camera: travel along the orbit path (arc) to new resting spot
	var gun_pos := _target.global_position
	var distance := drift_distance
	match _state:
		CameraState.DRIFT:
			distance = drift_distance
		CameraState.LAUNCH:
			distance = clamp(launch_distance, 4.0, 20.0)
		CameraState.IMPACT_STABILIZE:
			distance = impact_distance

	# Interpolate orbit yaw (azimuth) for smooth arc travel
	var yaw_lerp_speed := orbit_lerp_speed
	var angle_diff := wrapf(_target_orbit_yaw - _current_orbit_yaw, -PI, PI)
	_current_orbit_yaw += angle_diff * clampf(yaw_lerp_speed * get_physics_process_delta_time(), 0.0, 1.0)

	# Smoothly interpolate pitch toward target
	orbit_pitch_deg = lerp(orbit_pitch_deg, _target_pitch_deg, clampf(pitch_lerp_speed * get_physics_process_delta_time(), 0.0, 1.0))
	var pitch_rad: float = deg_to_rad(orbit_pitch_deg)
	var orbit_dir: Vector3 = Vector3(sin(_current_orbit_yaw), 0, cos(_current_orbit_yaw))
	var orbit_offset: Vector3 = orbit_dir.rotated(orbit_dir.cross(Vector3.UP), pitch_rad)
	orbit_offset = orbit_offset.normalized() * distance

	var shake: Vector3 = Vector3.ZERO
	if _fired_timer > 0.0:
		# Subtle camera shake on fired
		shake = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * fired_shake_strength * (_fired_timer / fired_shake_duration)

	global_position = gun_pos - orbit_offset + Vector3.UP * follow_height + shake
	# (Optional: remove print for performance)
	# print("[SwingArmCamera] Camera position:", global_position, " Player position:", gun_pos)

func _update_rotation(_delta: float) -> void:
	var gun_pos := _target.global_position

	# Get velocity direction (XZ only)
	var vel_dir: Vector3 = Vector3.ZERO
	if _target.has_method("get_linear_velocity"):
		vel_dir = _target.get_linear_velocity()
	elif _target.has_method("linear_velocity"):
		vel_dir = _target.linear_velocity
	vel_dir.y = 0.0
	if vel_dir.length() > 0.01:
		vel_dir = vel_dir.normalized()
	else:
		vel_dir = Vector3.ZERO

	# Aim direction (XZ only)
	var aim_dir: Vector3 = _desired_look_dir
	aim_dir.y = 0.0
	if aim_dir.length() > 0.01:
		aim_dir = aim_dir.normalized()
	else:
		aim_dir = Vector3.ZERO

	# Blend weights and camera params by state
	var vel_w: float = 0.5
	var aim_w: float = 0.5
	var yaw_cap: float = drift_yaw_cap
	var damping: float = drift_damping
	match _state:
		CameraState.DRIFT:
			vel_w = drift_vel_weight
			aim_w = drift_aim_weight
			yaw_cap = drift_yaw_cap
			damping = drift_damping
		CameraState.LAUNCH:
			vel_w = launch_vel_weight
			aim_w = launch_aim_weight
			yaw_cap = launch_yaw_cap
			damping = launch_damping
		CameraState.IMPACT_STABILIZE:
			vel_w = impact_vel_weight
			aim_w = impact_aim_weight
			yaw_cap = impact_yaw_cap
			damping = impact_damping

	# Blend direction
	var blend_dir: Vector3 = (vel_dir * vel_w + aim_dir * aim_w)
	if blend_dir.length() > 0.01:
		blend_dir = blend_dir.normalized()
	else:
		blend_dir = aim_dir

	# Clamp yaw change per frame
	var target_dir: Vector3 = blend_dir.normalized()
	var current_dir: Vector3 = _current_look_dir.normalized()
	var angle_to: float = current_dir.signed_angle_to(target_dir, Vector3.UP)
	var max_yaw_step: float = deg_to_rad(yaw_cap) * _delta
	var clamped_angle: float = clamp(angle_to, -max_yaw_step, max_yaw_step)
	var new_dir: Vector3 = current_dir.rotated(Vector3.UP, clamped_angle)
	# Damping for smoothness and orbit lerp
	_current_look_dir = current_dir.lerp(new_dir, max(damping, clampf(orbit_lerp_speed * _delta, 0.0, 1.0)))
	var look_target: Vector3 = gun_pos
	look_at(look_target, Vector3.UP)

func set_look_direction(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	_desired_look_dir = dir.normalized()
	# Set new target orbit yaw (azimuth) for smooth pan
	_target_orbit_yaw = atan2(_desired_look_dir.x, _desired_look_dir.z)
	# Set new target pitch for tilt effect (smoothed)
	if abs(_desired_look_dir.y) > 0.01:
		_target_pitch_deg = rad_to_deg(asin(_desired_look_dir.y))
