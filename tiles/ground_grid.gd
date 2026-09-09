@tool
extends GridMap

## Paintable RPG-Maker-style ground. Select this node, then paint Grass /
## Forest / Cobblestone from the GridMap palette in the 3D viewport.
## Neighbouring tiles blend in the shader, including corners of two materials.

const TERRAIN_GRASS := 0
const TERRAIN_FOREST := 1
const TERRAIN_COBBLE := 2
const NAMES := ["Grass", "Forest", "Cobblestone"]
const TEX_PATHS := [
	"res://tiles/textures/grass.jpg",
	"res://tiles/textures/forest.jpg",
	"res://tiles/textures/cobble.jpg",
]
const SHADER_PATH := "res://tiles/ground_blend.gdshader"
const CELL := 2.0
const MAP := 14
const MIN_CELL := -7

@export var texture_world_size: float = 12.0:
	set(value):
		texture_world_size = maxf(value, 0.5)
		_apply_material_params()

@export_range(0.02, 0.45, 0.01) var blend_width: float = 0.1:
	set(value):
		blend_width = value
		_apply_material_params()

@export var fill_default_layout: bool = false:
	set(value):
		if value:
			_paint_default_layout()

var _material: ShaderMaterial
var _id_tex: ImageTexture
var _last_hash := 0

func _enter_tree() -> void:
	cell_size = Vector3(CELL, 1.0, CELL)
	cell_center_x = true
	cell_center_y = false
	cell_center_z = true
	collision_layer = 0
	collision_mask = 0
	position = Vector3(1.0, 0.0, 1.0)
	_ensure_library()
	_rebuild_id_map()
	if Engine.is_editor_hint():
		set_process(true)
	if get_used_cells().is_empty():
		_paint_default_layout()

func _ready() -> void:
	_rebuild_id_map()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var h := _cells_hash()
	if h != _last_hash:
		_rebuild_id_map()

func _ensure_library() -> void:
	_material = _make_material()
	var lib := MeshLibrary.new()
	for i in 3:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(CELL, CELL)
		mesh.material = _material
		lib.create_item(i)
		lib.set_item_mesh(i, mesh)
		lib.set_item_name(i, NAMES[i])
	mesh_library = lib

func _make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	var dummy := Image.create(MAP, MAP, false, Image.FORMAT_RGB8)
	dummy.fill(Color(0.0, 0.0, 0.0))
	_id_tex = ImageTexture.create_from_image(dummy)
	mat.set_shader_parameter("terrain_ids", _id_tex)
	mat.set_shader_parameter("tex_grass", _load_tex(TEX_PATHS[0]))
	mat.set_shader_parameter("tex_forest", _load_tex(TEX_PATHS[1]))
	mat.set_shader_parameter("tex_cobble", _load_tex(TEX_PATHS[2]))
	mat.set_shader_parameter("map_origin", Vector2(-14.0, -14.0))
	mat.set_shader_parameter("cell_size", CELL)
	mat.set_shader_parameter("uv_scale", 1.0 / texture_world_size)
	mat.set_shader_parameter("blend_width", blend_width)
	return mat

func _apply_material_params() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("uv_scale", 1.0 / texture_world_size)
	_material.set_shader_parameter("blend_width", blend_width)

func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _rebuild_id_map() -> void:
	var img := Image.create(MAP, MAP, false, Image.FORMAT_RGB8)
	img.fill(Color(0.0, 0.0, 0.0))
	for cell in get_used_cells():
		var id := get_cell_item(cell)
		if id < TERRAIN_GRASS or id > TERRAIN_COBBLE:
			continue
		var px := cell.x - MIN_CELL
		var py := cell.z - MIN_CELL
		if px < 0 or py < 0 or px >= MAP or py >= MAP:
			continue
		img.set_pixel(px, py, Color(float(id) / 2.0, 0.0, 0.0))
	if _id_tex == null:
		_id_tex = ImageTexture.create_from_image(img)
	else:
		_id_tex.update(img)
	if _material != null:
		_material.set_shader_parameter("terrain_ids", _id_tex)
	_last_hash = _cells_hash()

func _cells_hash() -> int:
	var h := 0
	for cell in get_used_cells():
		h = hash([h, cell.x, cell.z, get_cell_item(cell)])
	return h

func _paint_default_layout() -> void:
	clear()
	for z in range(MIN_CELL, MIN_CELL + MAP):
		for x in range(MIN_CELL, MIN_CELL + MAP):
			set_cell_item(Vector3i(x, 0, z), TERRAIN_GRASS)
	# Forest patches under the cherry trees.
	for z in range(-7, -3):
		for x in range(-6, -2):
			set_cell_item(Vector3i(x, 0, z), TERRAIN_FOREST)
	for z in range(2, 6):
		for x in range(1, 5):
			set_cell_item(Vector3i(x, 0, z), TERRAIN_FOREST)
	# Cobble path through the middle, toward the trees.
	for z in range(-6, 6):
		set_cell_item(Vector3i(-1, 0, z), TERRAIN_COBBLE)
		set_cell_item(Vector3i(0, 0, z), TERRAIN_COBBLE)
	_rebuild_id_map()
