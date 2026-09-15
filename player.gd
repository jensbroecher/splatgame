extends CharacterBody3D

@export var speed: float = 6.0
@export var walk_speed: float = 3.2
@export var acceleration: float = 24.0
@export var friction: float = 20.0
@export var jump_velocity: float = 5.5
@export var rotation_speed: float = 12.0
@export var anim_blend_in: float  = 0.18   # seconds to blend idle→walk
@export var anim_blend_out: float = 0.25   # seconds to blend walk→idle

@onready var visual_node: Node3D  = $Visual
@onready var anim_player: AnimationPlayer = $WalkAnimPlayer

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _ready() -> void:
	_harden_materials(visual_node)
	# Route the AnimationPlayer to the skeleton inside the FBX sub-scene
	anim_player.root_node = anim_player.get_path_to(visual_node.get_parent())
	anim_player.play("idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var jump_pressed := Input.is_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("ui_accept")
	if is_on_floor() and jump_pressed:
		velocity.y = jump_velocity

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

	if move_dir.length_squared() > 0.01:
		var target_vel := move_dir * speed
		velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)
		if visual_node:
			var target_angle := atan2(-move_dir.x, -move_dir.z)
			visual_node.rotation.y = lerp_angle(visual_node.rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	move_and_slide()
	_update_animation()


func _update_animation() -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var is_walking := planar > 0.3

	if is_walking:
		# Scale animation speed proportionally to movement speed
		var speed_scale := clampf(planar / maxf(walk_speed, 0.01), 0.6, 1.5)
		if anim_player.current_animation != "walk":
			anim_player.play("walk", anim_blend_in)
		anim_player.speed_scale = speed_scale
	else:
		if anim_player.current_animation != "idle":
			anim_player.play("idle", anim_blend_out)
		anim_player.speed_scale = 1.0


## AccuRig hair/clothing often imports as alpha-blend, which draws AFTER the
## Gaussian compositor and does not write depth. That lets the player punch
## through splats and flicker with TAA. Hashing writes depth in the opaque pass
## so the compositor can occlude the character correctly.
func _harden_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.material_override != null:
			mi.material_override = _make_occluding_material(mi.material_override)
		var mesh := mi.mesh
		if mesh != null:
			for i in range(mesh.get_surface_count()):
				var mat := mi.get_surface_override_material(i)
				if mat == null:
					mat = mesh.surface_get_material(i)
				var fixed := _make_occluding_material(mat)
				if fixed != null:
					mi.set_surface_override_material(i, fixed)
	for child in root.get_children():
		_harden_materials(child)


func _make_occluding_material(mat: Material) -> Material:
	if mat == null:
		return null
	var dup := mat.duplicate()
	if dup is BaseMaterial3D:
		var b := dup as BaseMaterial3D
		if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			b.alpha_hash_scale = 1.0
			b.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		b.no_depth_test = false
		b.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return dup
