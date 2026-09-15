extends StaticBody3D

@export var dialogue_resource: DialogueResource
@export var dialogue_start_cue: String = "start"

@onready var box_mesh: MeshInstance3D = $BoxMeshInstance
@onready var prompt_pivot: Node3D = $PromptPivot
@onready var prompt_label: Label3D = $PromptPivot/PromptLabel
@onready var interaction_area: Area3D = $InteractionArea

var player_in_range: bool = false
var is_talking: bool = false
var prompt_tween: Tween
var box_tween: Tween

const COLOR_PALETTE: Array[Color] = [
	Color(0.85, 0.55, 0.22), # Warm golden amber
	Color(0.25, 0.75, 0.65), # Turquoise / Emerald
	Color(0.72, 0.32, 0.82), # Royal Purple
	Color(0.92, 0.35, 0.35), # Crimson Coral
	Color(0.28, 0.62, 0.95), # Sky Azure
	Color(0.95, 0.82, 0.25)  # Sunshine Gold
]
var color_index: int = 0


func _ready() -> void:
	# Ensure the mesh has a unique material instance so color changes only affect this box
	if box_mesh and box_mesh.get_surface_override_material(0):
		box_mesh.set_surface_override_material(0, box_mesh.get_surface_override_material(0).duplicate())
	elif box_mesh and box_mesh.material_override:
		box_mesh.material_override = box_mesh.material_override.duplicate()
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COLOR_PALETTE[0]
		mat.roughness = 0.4
		mat.metallic = 0.1
		box_mesh.material_override = mat

	# Connect area signals
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	# Connect dialogue manager signals
	if Engine.has_singleton("DialogueManager"):
		var dm: Node = Engine.get_singleton("DialogueManager")
		dm.dialogue_ended.connect(_on_dialogue_ended)
	elif has_node("/root/DialogueManager"):
		var dm: Node = get_node("/root/DialogueManager")
		dm.dialogue_ended.connect(_on_dialogue_ended)

	# Start with prompt hidden
	if prompt_pivot:
		prompt_pivot.visible = false
		prompt_pivot.scale = Vector3.ZERO


func _process(delta: float) -> void:
	# Gentle floating bob animation for the prompt when visible
	if prompt_pivot and prompt_pivot.visible:
		prompt_pivot.position.y = 1.3 + sin(Time.get_ticks_msec() * 0.005) * 0.06


func _unhandled_input(event: InputEvent) -> void:
	if not player_in_range or is_talking:
		return

	var is_interact: bool = event.is_action_pressed("interact")
	if not is_interact and event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		is_interact = key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_E

	if is_interact:
		get_viewport().set_input_as_handled()
		start_dialogue()


func start_dialogue() -> void:
	if is_talking:
		return

	is_talking = true
	_animate_bounce()
	_show_prompt(false)

	# Resolve or compile the dialogue resource
	var resource_to_use: DialogueResource = dialogue_resource
	if resource_to_use == null:
		if ResourceLoader.exists("res://dialogue/box.dialogue"):
			var loaded = load("res://dialogue/box.dialogue")
			if loaded is DialogueResource:
				resource_to_use = loaded

	if resource_to_use == null:
		# Fallback: compile directly from file text via DialogueManager
		var file_path := "res://dialogue/box.dialogue"
		if FileAccess.file_exists(file_path):
			var text := FileAccess.get_file_as_string(file_path)
			var dm: Node = null
			if Engine.has_singleton("DialogueManager"):
				dm = Engine.get_singleton("DialogueManager")
			elif has_node("/root/DialogueManager"):
				dm = get_node("/root/DialogueManager")
			if dm and dm.has_method("create_resource_from_text"):
				resource_to_use = dm.create_resource_from_text(text)

	if resource_to_use == null:
		printerr("InteractableBox: Could not load or compile dialogue resource!")
		is_talking = false
		if player_in_range:
			_show_prompt(true)
		return

	# Start dialogue balloon, passing self in extra_game_states so dialogue can call change_color()
	var balloon_scene_path := "res://dialogue/balloon.tscn"
	var dm_singleton: Node = null
	if Engine.has_singleton("DialogueManager"):
		dm_singleton = Engine.get_singleton("DialogueManager")
	elif has_node("/root/DialogueManager"):
		dm_singleton = get_node("/root/DialogueManager")

	if dm_singleton:
		if ResourceLoader.exists(balloon_scene_path):
			dm_singleton.show_dialogue_balloon_scene(balloon_scene_path, resource_to_use, dialogue_start_cue, [self])
		else:
			dm_singleton.show_dialogue_balloon(resource_to_use, dialogue_start_cue, [self])


## Called via dialogue mutation: `do change_color()`
func change_color() -> void:
	color_index = (color_index + 1) % COLOR_PALETTE.size()
	var next_color: Color = COLOR_PALETTE[color_index]

	var mat: StandardMaterial3D = null
	if box_mesh.material_override is StandardMaterial3D:
		mat = box_mesh.material_override as StandardMaterial3D
	elif box_mesh.get_surface_override_material(0) is StandardMaterial3D:
		mat = box_mesh.get_surface_override_material(0) as StandardMaterial3D

	if mat:
		var tween := create_tween().set_parallel(true)
		tween.tween_property(mat, "albedo_color", next_color, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_animate_bounce()


func _animate_bounce() -> void:
	if box_tween and box_tween.is_valid():
		box_tween.kill()

	box_tween = create_tween()
	# Squash down slightly
	box_tween.tween_property(box_mesh, "scale", Vector3(1.2, 0.75, 1.2), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Pop up
	box_tween.tween_property(box_mesh, "scale", Vector3(0.9, 1.25, 0.9), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Settle back to normal
	box_tween.tween_property(box_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _show_prompt(show_it: bool) -> void:
	if prompt_tween and prompt_tween.is_valid():
		prompt_tween.kill()

	prompt_tween = create_tween()
	if show_it:
		prompt_pivot.visible = true
		prompt_tween.tween_property(prompt_pivot, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		prompt_tween.tween_property(prompt_pivot, "scale", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		prompt_tween.tween_callback(func():
			if not player_in_range or is_talking:
				prompt_pivot.visible = false
		)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		player_in_range = true
		if not is_talking:
			_show_prompt(true)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		player_in_range = false
		_show_prompt(false)


func _on_dialogue_ended(_resource: DialogueResource) -> void:
	is_talking = false
	if player_in_range:
		_show_prompt(true)
