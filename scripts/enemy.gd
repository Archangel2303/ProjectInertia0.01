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

	# Assign groups to hitbox areas for regional detection
	var head_area = get_node_or_null("BASE_Low Poly Man_0/HeadHitbox")
	if head_area:
		head_area.add_to_group("hitbox_head")
		head_area.connect("area_entered", Callable(self, "_on_regional_hitbox_area_entered"))
	var torso_area = get_node_or_null("BASE_Low Poly Man_0/TorsoHitbox")
	if torso_area:
		torso_area.add_to_group("hitbox_body")
		torso_area.connect("area_entered", Callable(self, "_on_regional_hitbox_area_entered"))
	# Add more as needed for arms/legs/feet
	for area_name in ["LArmHitbox", "RArmHitbox", "LHandA3D", "RHandA3D", "LLegHitbox", "RLegHitbox", "LFootHitbox", "RFootHitbox"]:
		var area = get_node_or_null("BASE_Low Poly Man_0/" + area_name)
		if area:
			area.add_to_group("hitbox_limb")
			area.connect("area_entered", Callable(self, "_on_regional_hitbox_area_entered"))

	# Optionally connect broad collision for fallback (not needed, CollisionShape3D has no signals)
	# If broad detection is needed, use Area3D and connect its signals instead.

func take_hit(is_headshot: bool) -> void:
	if _dead:
		return
	if is_headshot:
		print("[Enemy] Headshot detected!")
		die(true)
		return

	print("[Enemy] Hit detected!")
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

# Called when a regional hitbox is entered by a bullet area
func _on_regional_hitbox_area_entered(area: Area3D) -> void:
	if area.is_in_group("bullet"):
		var is_headshot = false
		if get_tree().is_node_in_group(get_path(), "hitbox_head"):
			is_headshot = true
		take_hit(is_headshot)

## Broad collision fallback removed (CollisionShape3D has no signals, and this function is unused)

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
