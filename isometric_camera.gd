extends Camera3D

@export var target: Node3D
@export var distance: float = 16.0
@export var elevation_angle_deg: float = 35.264
@export var rotation_angle_deg: float = 45.0
@export var follow_smooth_speed: float = 8.0
@export var look_offset: Vector3 = Vector3(0.0, 0.9, 0.0)

func _ready() -> void:
	fov = 30.0
	if target:
		_snap_to_target()

func _snap_to_target() -> void:
	if not target:
		return
	global_position = target.global_position + _calculate_offset()
	look_at(target.global_position + look_offset, Vector3.UP)

func _physics_process(delta: float) -> void:
	if not target:
		return
	var desired_pos := target.global_position + _calculate_offset()
	global_position = global_position.lerp(desired_pos, follow_smooth_speed * delta)
	look_at(target.global_position + look_offset, Vector3.UP)

func _calculate_offset() -> Vector3:
	var pitch := deg_to_rad(elevation_angle_deg)
	var yaw := deg_to_rad(rotation_angle_deg)
	var horizontal_dist := distance * cos(pitch)
	var vertical_dist := distance * sin(pitch)
	return Vector3(
		horizontal_dist * sin(yaw),
		vertical_dist,
		horizontal_dist * cos(yaw)
	)
