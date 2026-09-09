extends CharacterBody3D

@export var speed: float = 6.0
@export var acceleration: float = 24.0
@export var friction: float = 20.0
@export var jump_velocity: float = 5.5
@export var rotation_speed: float = 12.0

@onready var visual_node: Node3D = $Visual

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _walk_cycle: float = 0.0

func _physics_process(delta: float) -> void:
	# 1. Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Jump
	var jump_pressed := Input.is_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("ui_accept")
	if is_on_floor() and jump_pressed:
		velocity.y = jump_velocity

	# 3. Movement input (WASD + Arrow keys + UI actions)
	var input_x: float = 0.0
	var input_z: float = 0.0

	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) or Input.is_action_pressed("ui_right"):
		input_x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) or Input.is_action_pressed("ui_left"):
		input_x -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down"):
		input_z += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_action_pressed("ui_up"):
		input_z -= 1.0

	var input_dir := Vector2(input_x, input_z).normalized()

	# 4. Map movement direction relative to camera orientation
	var move_dir := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam:
		var cam_forward := -cam.global_transform.basis.z
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()
		var cam_right := cam.global_transform.basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		move_dir = (cam_right * input_dir.x + cam_forward * -input_dir.y).normalized()
	else:
		move_dir = Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	# 5. Apply horizontal velocity
	if move_dir.length_squared() > 0.01:
		var target_vel := move_dir * speed
		velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)

		# Face direction of movement
		if visual_node:
			var target_angle := atan2(-move_dir.x, -move_dir.z)
			visual_node.rotation.y = lerp_angle(visual_node.rotation.y, target_angle, rotation_speed * delta)
			# Subtle walk bob
			_walk_cycle += delta * speed * 3.0
			visual_node.position.y = abs(sin(_walk_cycle)) * 0.08
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		if visual_node:
			visual_node.position.y = move_toward(visual_node.position.y, 0.0, 5.0 * delta)

	move_and_slide()
