extends Camera3D

@export var target_position: Vector3 = Vector3.ZERO
@export var distance: float = 1.8
@export var min_distance: float = 0.1
@export var max_distance: float = 20.0
@export var rotate_speed: float = 0.005
@export var zoom_speed: float = 0.3
@export var auto_rotate: bool = true
@export var auto_rotate_speed: float = 0.3

var _yaw: float = 0.0
var _pitch: float = 0.1
var _dragging: bool = false

func _ready() -> void:
	_update_camera_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance - zoom_speed * maxf(distance * 0.15, 0.05), min_distance, max_distance)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance + zoom_speed * maxf(distance * 0.15, 0.05), min_distance, max_distance)
			_update_camera_transform()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * rotate_speed
		_pitch = clampf(_pitch - event.relative.y * rotate_speed, -1.4, 1.4)
		_update_camera_transform()

func _process(delta: float) -> void:
	if auto_rotate and not _dragging:
		_yaw += auto_rotate_speed * delta
		_update_camera_transform()

func _update_camera_transform() -> void:
	var rot := Basis.from_euler(Vector3(0, _yaw, 0)) * Basis.from_euler(Vector3(_pitch, 0, 0))
	var offset := rot * Vector3(0, 0, distance)
	global_position = target_position + offset
	look_at(target_position, Vector3.UP)
