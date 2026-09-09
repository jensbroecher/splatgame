@tool
extends GridMap

## Paintable RPG-Maker-style ground. Select this node, then paint from the
## GridMap palette in the 3D viewport. Solid tiles blend at edges; mix tiles
## (diagonals / corners) stamp a two-material split inside the cell.
## Each painted cell is also the floor collision — erasing a cell leaves a hole.

const TERRAIN_GRASS := 0
const TERRAIN_FOREST := 1
const TERRAIN_COBBLE := 2
const NAMES := [
	"Grass",
	"Forest",
	"Cobblestone",
	"Cobble/Grass /",
	"Cobble/Grass \\",
	"Forest/Grass /",
	"Forest/Grass \\",
	"Cobble/Forest /",
	"Cobble/Forest \\",
	"Cobble corner NE",
	"Cobble corner SE",
	"Cobble corner SW",
	"Cobble corner NW",
	"Forest corner NE",
	"Forest corner SE",
	"Forest corner SW",
	"Forest corner NW",
]
const TEX_PATHS := [
	"res://tiles/textures/grass.jpg",
	"res://tiles/textures/forest.jpg",
	"res://tiles/textures/cobble.jpg",
]
const SHADER_PATH := "res://tiles/ground_blend.gdshader"
const CELL := 2.0
const EMPTY_ID := 255

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
	collision_layer = 1
	collision_mask = 0
	_ensure_library()
	_flatten_orientations()
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
	_flatten_orientations()
	var h := _cells_hash()
	if h != _last_hash:
		_rebuild_id_map()

func _flatten_orientations() -> void:
	# Mix tiles are world-projected in the shader. A rotated GridMap item
	# stands the collision box on its side (invisible wall, then a ledge).
	for cell in get_used_cells():
		if get_cell_item_orientation(cell) != 0:
			set_cell_item(cell, get_cell_item(cell), 0)

func _ensure_library() -> void:
	if (
		mesh_library != null
		and _material != null
		and mesh_library.get_item_list().size() == NAMES.size()
	):
		return
	_material = _make_material()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL, 1.0, CELL)
	var box_xform := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, 0.0))
	var lib := MeshLibrary.new()
	for i in NAMES.size():
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(CELL, CELL)
		mesh.material = _material
		lib.create_item(i)
		lib.set_item_mesh(i, mesh)
		lib.set_item_name(i, NAMES[i])
		lib.set_item_shapes(i, [box, box_xform])
		lib.set_item_preview(i, _make_preview(i))
	mesh_library = lib

func _make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	var dummy := Image.create(1, 1, false, Image.FORMAT_RGB8)
	dummy.fill(Color(1.0, 0.0, 0.0))
	_id_tex = ImageTexture.create_from_image(dummy)
	mat.set_shader_parameter("terrain_ids", _id_tex)
	mat.set_shader_parameter("tex_grass", _load_tex(TEX_PATHS[0]))
	mat.set_shader_parameter("tex_forest", _load_tex(TEX_PATHS[1]))
	mat.set_shader_parameter("tex_cobble", _load_tex(TEX_PATHS[2]))
	mat.set_shader_parameter("map_origin", Vector2.ZERO)
	mat.set_shader_parameter("cell_size", CELL)
	mat.set_shader_parameter("uv_scale", 1.0 / texture_world_size)
	mat.set_shader_parameter("blend_width", blend_width)
	return mat

func _apply_material_params() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("uv_scale", 1.0 / texture_world_size)
	_material.set_shader_parameter("blend_width", blend_width)

const PREVIEW_GRASS := Color(0.40, 0.62, 0.32)
const PREVIEW_FOREST := Color(0.38, 0.24, 0.13)
const PREVIEW_COBBLE := Color(0.72, 0.68, 0.62)

func _make_preview(id: int) -> Texture2D:
	var s := 72
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var local := Vector2((float(x) + 0.5) / float(s), (float(y) + 0.5) / float(s))
			img.set_pixel(x, y, _preview_color(id, local))
	return ImageTexture.create_from_image(img)

func _preview_color(id: int, local: Vector2) -> Color:
	var grass := PREVIEW_GRASS
	var forest := PREVIEW_FOREST
	var cobble := PREVIEW_COBBLE
	var slash := smoothstep(-0.07, 0.07, local.x - local.y)
	var backslash := smoothstep(-0.07, 0.07, local.x + local.y - 1.0)
	var ne := 1.0 - smoothstep(0.62, 0.88, local.distance_to(Vector2(1.0, 0.0)))
	var se := 1.0 - smoothstep(0.62, 0.88, local.distance_to(Vector2(1.0, 1.0)))
	var sw := 1.0 - smoothstep(0.62, 0.88, local.distance_to(Vector2(0.0, 1.0)))
	var nw := 1.0 - smoothstep(0.62, 0.88, local.distance_to(Vector2(0.0, 0.0)))
	match id:
		1:
			return forest
		2:
			return cobble
		3:
			return grass.lerp(cobble, slash)
		4:
			return grass.lerp(cobble, backslash)
		5:
			return grass.lerp(forest, slash)
		6:
			return grass.lerp(forest, backslash)
		7:
			return forest.lerp(cobble, slash)
		8:
			return forest.lerp(cobble, backslash)
		9:
			return grass.lerp(cobble, ne)
		10:
			return grass.lerp(cobble, se)
		11:
			return grass.lerp(cobble, sw)
		12:
			return grass.lerp(cobble, nw)
		13:
			return grass.lerp(forest, ne)
		14:
			return grass.lerp(forest, se)
		15:
			return grass.lerp(forest, sw)
		16:
			return grass.lerp(forest, nw)
		_:
			return grass

func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _rebuild_id_map() -> void:
	var cells := get_used_cells()
	var min_x := 0
	var min_z := 0
	var max_x := 0
	var max_z := 0
	if not cells.is_empty():
		min_x = cells[0].x
		min_z = cells[0].z
		max_x = min_x
		max_z = min_z
		for cell in cells:
			min_x = mini(min_x, cell.x)
			min_z = mini(min_z, cell.z)
			max_x = maxi(max_x, cell.x)
			max_z = maxi(max_z, cell.z)
	var w := maxi(1, max_x - min_x + 1)
	var h := maxi(1, max_z - min_z + 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 0.0, 0.0))
	for cell in cells:
		var id := get_cell_item(cell)
		if id < 0 or id >= NAMES.size():
			continue
		img.set_pixel(cell.x - min_x, cell.z - min_z, Color(float(id) / 255.0, 0.0, 0.0))
	_id_tex = ImageTexture.create_from_image(img)
	if _material != null:
		var origin := to_global(Vector3(float(min_x) * CELL, 0.0, float(min_z) * CELL))
		_material.set_shader_parameter("terrain_ids", _id_tex)
		_material.set_shader_parameter("map_origin", Vector2(origin.x, origin.z))
		_material.set_shader_parameter("cell_size", CELL)
	_last_hash = _cells_hash()

func _cells_hash() -> int:
	var h := 0
	for cell in get_used_cells():
		h = hash([h, cell.x, cell.z, get_cell_item(cell)])
	return h

func _paint_default_layout() -> void:
	clear()
	for z in range(-7, 7):
		for x in range(-7, 7):
			set_cell_item(Vector3i(x, 0, z), TERRAIN_GRASS)
	for z in range(-7, -3):
		for x in range(-6, -2):
			set_cell_item(Vector3i(x, 0, z), TERRAIN_FOREST)
	for z in range(2, 6):
		for x in range(1, 5):
			set_cell_item(Vector3i(x, 0, z), TERRAIN_FOREST)
	for z in range(-6, 6):
		set_cell_item(Vector3i(-1, 0, z), TERRAIN_COBBLE)
		set_cell_item(Vector3i(0, 0, z), TERRAIN_COBBLE)
	# Mix tiles so the path and woods don't read as a perfect grid.
	set_cell_item(Vector3i(-1, 0, 6), 9)
	set_cell_item(Vector3i(0, 0, 6), 12)
	set_cell_item(Vector3i(-1, 0, -7), 10)
	set_cell_item(Vector3i(0, 0, -7), 11)
	set_cell_item(Vector3i(1, 0, 1), 5)
	set_cell_item(Vector3i(-2, 0, -3), 6)
	set_cell_item(Vector3i(2, 0, 2), 3)
	_rebuild_id_map()
