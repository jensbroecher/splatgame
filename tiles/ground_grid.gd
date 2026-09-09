@tool
extends GridMap

## Paintable RPG-Maker-style ground. Select this node, then paint from the
## GridMap palette in the 3D viewport. Solid tiles blend at edges; mix tiles
## (diagonals / corners) stamp a two-material split inside the cell.
## Hills and valleys: select this node and use Raise / Lower (inspector or
## on-screen buttons). Paint and erase always apply on that height.

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

@export var collision_base: float = -2.0

@export_range(-8, 8, 1, "suffix:m") var paint_floor: int = 0:
	set(value):
		paint_floor = clampi(value, -8, 8)
		_update_height_hud()

@export_tool_button("Raise hill (+1 m)") var raise_floor_action = _raise_floor
@export_tool_button("Lower valley (-1 m)") var lower_floor_action = _lower_floor

var _material: ShaderMaterial
var _id_tex: ImageTexture
var _last_hash := 0
var _cliff_material: StandardMaterial3D
var _layer_items: Dictionary = {}
var _height_hud: Control
var _height_label: Label

func _enter_tree() -> void:
	cell_size = Vector3(CELL, 1.0, CELL)
	cell_center_x = true
	cell_center_y = false
	cell_center_z = true
	collision_layer = 0
	collision_mask = 0
	_ensure_library()
	_flatten_orientations()
	_rebuild_id_map()
	if Engine.is_editor_hint():
		set_process(true)
		_ensure_height_hud()
	if get_used_cells().is_empty():
		_paint_default_layout()
	_snapshot_layer()

func _ready() -> void:
	_rebuild_id_map()

func _exit_tree() -> void:
	if _height_hud != null and is_instance_valid(_height_hud):
		_height_hud.queue_free()
		_height_hud = null
		_height_label = null

func _raise_floor() -> void:
	paint_floor += 1

func _lower_floor() -> void:
	paint_floor -= 1

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_flatten_orientations()
	_redirect_paints_to_floor()
	_update_height_hud()
	var h := _cells_hash()
	if h != _last_hash:
		_rebuild_id_map()

func _snapshot_layer() -> void:
	_layer_items.clear()
	for cell in get_used_cells():
		_layer_items[cell] = get_cell_item(cell)

func _redirect_paints_to_floor() -> void:
	if paint_floor == 0:
		_snapshot_layer()
		return
	var current: Dictionary = {}
	for cell in get_used_cells():
		current[cell] = get_cell_item(cell)
	# Erase on the editor's default floor (0) means erase at paint_floor.
	for old_cell in _layer_items.keys():
		if old_cell.y != 0:
			continue
		if current.has(old_cell):
			continue
		set_cell_item(old_cell, int(_layer_items[old_cell]), 0)
		set_cell_item(Vector3i(old_cell.x, paint_floor, old_cell.z), INVALID_CELL_ITEM)
	# New or changed cells at y=0 are stamps for paint_floor.
	for cell in current.keys():
		if cell.y != 0:
			continue
		var item: int = current[cell]
		var old: int = int(_layer_items.get(cell, INVALID_CELL_ITEM))
		if item == old:
			continue
		set_cell_item(Vector3i(cell.x, paint_floor, cell.z), item, 0)
		if old == INVALID_CELL_ITEM:
			set_cell_item(cell, INVALID_CELL_ITEM)
		else:
			set_cell_item(cell, old, 0)
	_snapshot_layer()

func _is_selected_in_editor() -> bool:
	if not Engine.has_singleton("EditorInterface"):
		return false
	var editor := Engine.get_singleton("EditorInterface")
	if editor == null or not editor.has_method("get_selection"):
		return false
	var selection: Object = editor.call("get_selection")
	if selection == null or not selection.has_method("get_selected_nodes"):
		return false
	var nodes: Array = selection.call("get_selected_nodes")
	return nodes.has(self)

func _ensure_height_hud() -> void:
	if _height_hud != null and is_instance_valid(_height_hud):
		return
	if not Engine.has_singleton("EditorInterface"):
		return
	var editor := Engine.get_singleton("EditorInterface")
	if editor == null or not editor.has_method("get_editor_viewport_3d"):
		return
	var viewport: Control = editor.call("get_editor_viewport_3d", 0)
	if viewport == null:
		return
	_height_hud = HBoxContainer.new()
	_height_hud.name = "_GdgsHeightHud"
	_height_hud.offset_left = 16.0
	_height_hud.offset_top = 16.0
	_height_hud.add_theme_constant_override("separation", 12)
	var down := Button.new()
	down.text = "  Valley -1m  "
	down.custom_minimum_size = Vector2(180, 64)
	down.pressed.connect(_lower_floor)
	var up := Button.new()
	up.text = "  Hill +1m  "
	up.custom_minimum_size = Vector2(180, 64)
	up.pressed.connect(_raise_floor)
	_height_label = Label.new()
	_height_label.custom_minimum_size = Vector2(200, 64)
	_height_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_height_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_height_hud.add_child(down)
	_height_hud.add_child(_height_label)
	_height_hud.add_child(up)
	viewport.add_child(_height_hud)
	_update_height_hud()

func _update_height_hud() -> void:
	if _height_hud != null and is_instance_valid(_height_hud):
		_height_hud.visible = Engine.is_editor_hint() and _is_selected_in_editor()
	if _height_label != null and is_instance_valid(_height_label):
		var tag := "ground"
		if paint_floor > 0:
			tag = "hill"
		elif paint_floor < 0:
			tag = "valley"
		_height_label.text = "Height %d m (%s)" % [paint_floor, tag]

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
	var lib := MeshLibrary.new()
	for i in NAMES.size():
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(CELL, CELL)
		mesh.material = _material
		lib.create_item(i)
		lib.set_item_mesh(i, mesh)
		lib.set_item_name(i, NAMES[i])
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
	var top := _surface_cells(cells)
	for key in top.keys():
		var cell: Vector3i = top[key]
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
	_rebuild_volume(cells)
	_last_hash = _cells_hash()

func _surface_cells(cells: Array) -> Dictionary:
	var top: Dictionary = {}
	for cell in cells:
		var key := Vector2i(cell.x, cell.z)
		if not top.has(key) or cell.y > (top[key] as Vector3i).y:
			top[key] = cell
	return top

func _rebuild_volume(cells: Array) -> void:
	var top := _surface_cells(cells)
	_rebuild_columns(top)
	_rebuild_cliffs(top)

func _height_body() -> StaticBody3D:
	var body := get_node_or_null("_HeightCollision") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "_HeightCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body, false, Node.INTERNAL_MODE_BACK)
	return body

func _rebuild_columns(top: Dictionary) -> void:
	var body := _height_body()
	for child in body.get_children():
		child.queue_free()
	if top.is_empty():
		return
	var min_top := INF
	for cell in top.values():
		min_top = minf(min_top, map_to_local(cell).y)
	var base := minf(collision_base, min_top - cell_size.y)
	for cell in top.values():
		var origin := map_to_local(cell)
		var col_h := origin.y - base
		if col_h < 0.05:
			continue
		var box := BoxShape3D.new()
		box.size = Vector3(CELL, col_h, CELL)
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = Vector3(origin.x, base + col_h * 0.5, origin.z)
		body.add_child(shape, false, Node.INTERNAL_MODE_BACK)

func _rebuild_cliffs(top: Dictionary) -> void:
	var mesh_inst := get_node_or_null("_Cliffs") as MeshInstance3D
	if mesh_inst == null:
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "_Cliffs"
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mesh_inst, false, Node.INTERNAL_MODE_BACK)
	if top.is_empty():
		mesh_inst.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for key in top.keys():
		var xz: Vector2i = key
		var cell: Vector3i = top[xz]
		var origin := map_to_local(cell)
		var top_y := origin.y
		for d in dirs:
			var nkey: Vector2i = xz + d
			var n_top := collision_base
			if top.has(nkey):
				n_top = map_to_local(top[nkey]).y
			if top_y - n_top < 0.05:
				continue
			_add_cliff_quad(st, origin, d, n_top, top_y)
	st.generate_normals()
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = _cliff_mat()

func _add_cliff_quad(st: SurfaceTool, origin: Vector3, dir: Vector2i, y0: float, y1: float) -> void:
	var hx := CELL * 0.5
	var hz := CELL * 0.5
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	if dir.x == 1:
		a = Vector3(origin.x + hx, y0, origin.z - hz)
		b = Vector3(origin.x + hx, y0, origin.z + hz)
	elif dir.x == -1:
		a = Vector3(origin.x - hx, y0, origin.z + hz)
		b = Vector3(origin.x - hx, y0, origin.z - hz)
	elif dir.y == 1:
		a = Vector3(origin.x + hx, y0, origin.z + hz)
		b = Vector3(origin.x - hx, y0, origin.z + hz)
	else:
		a = Vector3(origin.x - hx, y0, origin.z - hz)
		b = Vector3(origin.x + hx, y0, origin.z - hz)
	var c := Vector3(b.x, y1, b.z)
	var d := Vector3(a.x, y1, a.z)
	var uv_scale := 1.0 / texture_world_size
	var uvs := PackedVector2Array([
		Vector2(a.x, a.y) * uv_scale,
		Vector2(b.x, b.y) * uv_scale,
		Vector2(c.x, c.y) * uv_scale,
		Vector2(d.x, d.y) * uv_scale,
	])
	st.set_uv(uvs[0])
	st.add_vertex(a)
	st.set_uv(uvs[1])
	st.add_vertex(b)
	st.set_uv(uvs[2])
	st.add_vertex(c)
	st.set_uv(uvs[0])
	st.add_vertex(a)
	st.set_uv(uvs[2])
	st.add_vertex(c)
	st.set_uv(uvs[3])
	st.add_vertex(d)

func _cliff_mat() -> StandardMaterial3D:
	if _cliff_material == null:
		_cliff_material = StandardMaterial3D.new()
		_cliff_material.albedo_texture = _load_tex(TEX_PATHS[1])
		_cliff_material.roughness = 0.95
	return _cliff_material

func _cells_hash() -> int:
	var h := 0
	for cell in get_used_cells():
		h = hash([h, cell.x, cell.y, cell.z, get_cell_item(cell)])
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
