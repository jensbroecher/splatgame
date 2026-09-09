extends Camera3D

## HD-2D / Octopath-style diorama camera.
## Yaw 0 so the ground stays axis-aligned (not an isometric diamond).
## Moderate look-down, narrow FOV, screen-space tilt-shift.

@export var target: Node3D
@export var distance: float = 24.0
@export var elevation_angle_deg: float = 34.0
@export var rotation_angle_deg: float = 0.0
@export var follow_smooth_speed: float = 7.0
@export var look_offset: Vector3 = Vector3(0.0, 0.7, 0.0)
@export var look_ahead: float = 1.4
@export var camera_fov: float = 26.0

@export_group("Tilt Shift")
@export var tilt_shift_rect: ColorRect
@export var tilt_shift_blur_px: float = 5.5
@export var tilt_shift_focus_width: float = 0.14
@export var tilt_shift_focus_falloff: float = 0.26
@export var tilt_shift_top_heaviness: float = 1.35

func _ready() -> void:
	fov = camera_fov
	near = 0.2
	far = 160.0
	_configure_tilt_shift()
	if target:
		_snap_to_target()

func _physics_process(delta: float) -> void:
	if not target:
		return
	var desired_pos := target.global_position + _calculate_offset()
	global_position = global_position.lerp(desired_pos, follow_smooth_speed * delta)
	look_at(_look_at_position(), Vector3.UP)
	_update_tilt_shift_focus()

func _snap_to_target() -> void:
	if not target:
		return
	global_position = target.global_position + _calculate_offset()
	look_at(_look_at_position(), Vector3.UP)
	_update_tilt_shift_focus()

func _look_at_position() -> Vector3:
	var ahead := Vector3.ZERO
	if look_ahead != 0.0:
		var yaw := deg_to_rad(rotation_angle_deg)
		# Camera looks toward -offset, i.e. into the scene along this ground dir.
		ahead = Vector3(-sin(yaw), 0.0, -cos(yaw)) * look_ahead
	return target.global_position + look_offset + ahead

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

func _configure_tilt_shift() -> void:
	if tilt_shift_rect == null:
		return
	var material := tilt_shift_rect.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("blur_px", tilt_shift_blur_px)
	material.set_shader_parameter("focus_width", tilt_shift_focus_width)
	material.set_shader_parameter("focus_falloff", tilt_shift_focus_falloff)
	material.set_shader_parameter("top_heaviness", tilt_shift_top_heaviness)

func _update_tilt_shift_focus() -> void:
	if tilt_shift_rect == null or target == null:
		return
	var material := tilt_shift_rect.material as ShaderMaterial
	if material == null:
		return
	var screen := unproject_position(target.global_position + look_offset)
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.y <= 1.0:
		return
	var focus_y := clampf(screen.y / vp_size.y, 0.28, 0.78)
	material.set_shader_parameter("focus_y", focus_y)
