extends Node3D
class_name BulletVisual

@export var speed: float = 40.0
@export var lifetime_sec: float = 0.7

var direction: Vector3 = Vector3.FORWARD

var _t: float = 0.0

func _ready() -> void:
	# Add this bullet to the 'bullet' group for hit detection
	add_to_group("bullet")
	# Connect Area3D signal for hit detection
	var area := get_node_or_null("Bullet_bullet_0/BulletHitbox")
	if area and area is Area3D:
		area.connect("area_entered", Callable(self, "_on_area_entered"))

func _on_area_entered(other_area: Area3D) -> void:
	# If the area is an enemy hitbox, queue_free bullet
	if other_area.is_in_group("hitbox_head") or other_area.is_in_group("hitbox_body") or other_area.is_in_group("hitbox_limb"):
		queue_free()

func _process(delta: float) -> void:
	global_position += direction * speed * delta
	_t += delta
	if _t >= lifetime_sec:
		queue_free()
