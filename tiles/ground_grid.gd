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
const CLIFF_SHADER_PATH := "res://tiles/cliff_rock.gdshader"
const ROCK_TEX_PATH := "res://tiles/textures/rock_cliff.jpg"
const ROCK_NORM_PATH := "res://tiles/textures/rock_cliff_normal.png"
const ROCK_ROUGH_PATH := "res://tiles/textures/rock_cliff_roughness.png"
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

@export_range(0.05, 0.45, 0.01) var bevel_radius: float = 0.22:
	set(value):
		bevel_radius = value
		_apply_material_params()
		if not get_used_cells().is_empty():
			_rebuild_cliffs(_surface_cells(get_used_cells()))

@export var cliff_uv_scale: float = 0.5:
	set(value):
		cliff_uv_scale = value
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
var _cliff_material: Material
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
	var viewport: Node = editor.call("get_editor_viewport_3d", 0)
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
	var needs_rebuild := false
	if (
		mesh_library == null
		or _material == null
		or mesh_library.get_item_list().size() != NAMES.size()
	):
		needs_rebuild = true
	else:
		var m := mesh_library.get_item_mesh(0) as PlaneMesh
		if m == null or m.subdivide_width < 16:
			needs_rebuild = true
	if not needs_rebuild:
		return
	_material = _make_material()
	var lib := MeshLibrary.new()
	for i in NAMES.size():
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(CELL, CELL)
		mesh.subdivide_width = 20
		mesh.subdivide_depth = 20
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
	mat.set_shader_parameter("elevation_step", cell_size.y)
	mat.set_shader_parameter("uv_scale", 1.0 / texture_world_size)
	mat.set_shader_parameter("blend_width", blend_width)
	mat.set_shader_parameter("bevel_radius", bevel_radius)
	return mat

func _apply_material_params() -> void:
	if _material != null:
		_material.set_shader_parameter("uv_scale", 1.0 / texture_world_size)
		_material.set_shader_parameter("blend_width", blend_width)
		_material.set_shader_parameter("bevel_radius", bevel_radius)
	if _cliff_material != null and _cliff_material is ShaderMaterial:
		(_cliff_material as ShaderMaterial).set_shader_parameter("uv_scale", cliff_uv_scale)

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
		img.set_pixel(
			cell.x - min_x,
			cell.z - min_z,
			Color(float(id) / 255.0, float(cell.y + 128) / 255.0, 0.0)
		)
	_id_tex = ImageTexture.create_from_image(img)
	if _material != null:
		var origin := to_global(Vector3(float(min_x) * CELL, 0.0, float(min_z) * CELL))
		_material.set_shader_parameter("terrain_ids", _id_tex)
		_material.set_shader_parameter("map_origin", Vector2(origin.x, origin.z))
		_material.set_shader_parameter("cell_size", CELL)
		_material.set_shader_parameter("elevation_step", cell_size.y)
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

	var hx := CELL * 0.5
	var hz := CELL * 0.5

	for key in top.keys():
		var xz: Vector2i = key
		var cell: Vector3i = top[xz]
		var origin := map_to_local(cell)
		var top_y := origin.y

		var n_east: float = map_to_local(top[xz + Vector2i(1, 0)]).y if top.has(xz + Vector2i(1, 0)) else collision_base
		var n_west: float = map_to_local(top[xz + Vector2i(-1, 0)]).y if top.has(xz + Vector2i(-1, 0)) else collision_base
		var n_north: float = map_to_local(top[xz + Vector2i(0, -1)]).y if top.has(xz + Vector2i(0, -1)) else collision_base
		var n_south: float = map_to_local(top[xz + Vector2i(0, 1)]).y if top.has(xz + Vector2i(0, 1)) else collision_base

		var is_cliff_e := (top_y - n_east >= 0.05)
		var is_cliff_w := (top_y - n_west >= 0.05)
		var is_cliff_n := (top_y - n_north >= 0.05)
		var is_cliff_s := (top_y - n_south >= 0.05)

		var r_eff_e := minf(bevel_radius, (top_y - n_east) * 0.7) if is_cliff_e else 0.0
		var r_eff_w := minf(bevel_radius, (top_y - n_west) * 0.7) if is_cliff_w else 0.0
		var r_eff_n := minf(bevel_radius, (top_y - n_north) * 0.7) if is_cliff_n else 0.0
		var r_eff_s := minf(bevel_radius, (top_y - n_south) * 0.7) if is_cliff_s else 0.0

		# Straight cliff walls
		if is_cliff_e:
			var z_start := (origin.z - hz + bevel_radius) if is_cliff_n else (origin.z - hz)
			var z_end := (origin.z + hz - bevel_radius) if is_cliff_s else (origin.z + hz)
			if z_end > z_start:
				_add_cliff_wall_quad(st, Vector2(origin.x + hx, z_start), Vector2(origin.x + hx, z_end), n_east, top_y - r_eff_e, Vector3(1.0, 0.0, 0.0))

		if is_cliff_w:
			var z_start := (origin.z - hz + bevel_radius) if is_cliff_n else (origin.z - hz)
			var z_end := (origin.z + hz - bevel_radius) if is_cliff_s else (origin.z + hz)
			if z_end > z_start:
				_add_cliff_wall_quad(st, Vector2(origin.x - hx, z_end), Vector2(origin.x - hx, z_start), n_west, top_y - r_eff_w, Vector3(-1.0, 0.0, 0.0))

		if is_cliff_s:
			var x_start := (origin.x - hx + bevel_radius) if is_cliff_w else (origin.x - hx)
			var x_end := (origin.x + hx - bevel_radius) if is_cliff_e else (origin.x + hx)
			if x_end > x_start:
				_add_cliff_wall_quad(st, Vector2(x_end, origin.z + hz), Vector2(x_start, origin.z + hz), n_south, top_y - r_eff_s, Vector3(0.0, 0.0, 1.0))

		if is_cliff_n:
			var x_start := (origin.x - hx + bevel_radius) if is_cliff_w else (origin.x - hx)
			var x_end := (origin.x + hx - bevel_radius) if is_cliff_e else (origin.x + hx)
			if x_end > x_start:
				_add_cliff_wall_quad(st, Vector2(x_start, origin.z - hz), Vector2(x_end, origin.z - hz), n_north, top_y - r_eff_n, Vector3(0.0, 0.0, -1.0))

		# Convex corner arcs
		if is_cliff_e and is_cliff_s:
			var center := Vector3(origin.x + hx - bevel_radius, 0.0, origin.z + hz - bevel_radius)
			var n_se: float = map_to_local(top[xz + Vector2i(1, 1)]).y if top.has(xz + Vector2i(1, 1)) else collision_base
			var bot_y := minf(n_east, minf(n_south, n_se))
			var top_y_corner := top_y - minf(r_eff_e, r_eff_s)
			_add_cliff_corner_arc(st, center, bevel_radius, 0.0, PI * 0.5, bot_y, top_y_corner, 4)

		if is_cliff_e and is_cliff_n:
			var center := Vector3(origin.x + hx - bevel_radius, 0.0, origin.z - hz + bevel_radius)
			var n_ne: float = map_to_local(top[xz + Vector2i(1, -1)]).y if top.has(xz + Vector2i(1, -1)) else collision_base
			var bot_y := minf(n_east, minf(n_north, n_ne))
			var top_y_corner := top_y - minf(r_eff_e, r_eff_n)
			_add_cliff_corner_arc(st, center, bevel_radius, -PI * 0.5, 0.0, bot_y, top_y_corner, 4)

		if is_cliff_w and is_cliff_s:
			var center := Vector3(origin.x - hx + bevel_radius, 0.0, origin.z + hz - bevel_radius)
			var n_sw: float = map_to_local(top[xz + Vector2i(-1, 1)]).y if top.has(xz + Vector2i(-1, 1)) else collision_base
			var bot_y := minf(n_west, minf(n_south, n_sw))
			var top_y_corner := top_y - minf(r_eff_w, r_eff_s)
			_add_cliff_corner_arc(st, center, bevel_radius, PI * 0.5, PI, bot_y, top_y_corner, 4)

		if is_cliff_w and is_cliff_n:
			var center := Vector3(origin.x - hx + bevel_radius, 0.0, origin.z - hz + bevel_radius)
			var n_nw: float = map_to_local(top[xz + Vector2i(-1, -1)]).y if top.has(xz + Vector2i(-1, -1)) else collision_base
			var bot_y := minf(n_west, minf(n_north, n_nw))
			var top_y_corner := top_y - minf(r_eff_w, r_eff_n)
			_add_cliff_corner_arc(st, center, bevel_radius, PI, PI * 1.5, bot_y, top_y_corner, 4)

	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = _cliff_mat()

func _add_cliff_wall_quad(
	st: SurfaceTool,
	p0: Vector2,
	p1: Vector2,
	y0: float,
	y1: float,
	normal: Vector3
) -> void:
	if y1 - y0 < 0.02:
		return
	var a := Vector3(p0.x, y0, p0.y)
	var b := Vector3(p1.x, y0, p1.y)
	var c := Vector3(p1.x, y1, p1.y)
	var d := Vector3(p0.x, y1, p0.y)

	var uv_scale := cliff_uv_scale
	var u_a := a.x + a.z
	var u_b := b.x + b.z

	# Triangle 1: a -> b -> c
	st.set_normal(normal)
	st.set_uv(Vector2(u_a, -a.y) * uv_scale)
	st.set_uv2(Vector2(y1 - a.y, 0.0))
	st.add_vertex(a)

	st.set_normal(normal)
	st.set_uv(Vector2(u_b, -b.y) * uv_scale)
	st.set_uv2(Vector2(y1 - b.y, 0.0))
	st.add_vertex(b)

	st.set_normal(normal)
	st.set_uv(Vector2(u_b, -c.y) * uv_scale)
	st.set_uv2(Vector2(y1 - c.y, 0.0))
	st.add_vertex(c)

	# Triangle 2: a -> c -> d
	st.set_normal(normal)
	st.set_uv(Vector2(u_a, -a.y) * uv_scale)
	st.set_uv2(Vector2(y1 - a.y, 0.0))
	st.add_vertex(a)

	st.set_normal(normal)
	st.set_uv(Vector2(u_b, -c.y) * uv_scale)
	st.set_uv2(Vector2(y1 - c.y, 0.0))
	st.add_vertex(c)

	st.set_normal(normal)
	st.set_uv(Vector2(u_a, -d.y) * uv_scale)
	st.set_uv2(Vector2(y1 - d.y, 0.0))
	st.add_vertex(d)

func _add_cliff_corner_arc(
	st: SurfaceTool,
	center: Vector3,
	radius: float,
	start_angle: float,
	end_angle: float,
	y0: float,
	y1: float,
	segments: int = 4
) -> void:
	if y1 - y0 < 0.02:
		return
	var da := (end_angle - start_angle) / float(segments)
	var uv_scale := cliff_uv_scale
	for i in segments:
		var a0 := start_angle + float(i) * da
		var a1 := start_angle + float(i + 1) * da

		var cos0 := cos(a0)
		var sin0 := sin(a0)
		var cos1 := cos(a1)
		var sin1 := sin(a1)

		var p0_bot := Vector3(center.x + radius * cos0, y0, center.z + radius * sin0)
		var p1_bot := Vector3(center.x + radius * cos1, y0, center.z + radius * sin1)
		var p1_top := Vector3(center.x + radius * cos1, y1, center.z + radius * sin1)
		var p0_top := Vector3(center.x + radius * cos0, y1, center.z + radius * sin0)

		var n0 := Vector3(cos0, 0.0, sin0)
		var n1 := Vector3(cos1, 0.0, sin1)

		var u0 := p0_bot.x + p0_bot.z
		var u1 := p1_bot.x + p1_bot.z

		# Triangle 1: p0_bot -> p1_bot -> p1_top
		st.set_normal(n0)
		st.set_uv(Vector2(u0, -p0_bot.y) * uv_scale)
		st.set_uv2(Vector2(y1 - p0_bot.y, 0.0))
		st.add_vertex(p0_bot)

		st.set_normal(n1)
		st.set_uv(Vector2(u1, -p1_bot.y) * uv_scale)
		st.set_uv2(Vector2(y1 - p1_bot.y, 0.0))
		st.add_vertex(p1_bot)

		st.set_normal(n1)
		st.set_uv(Vector2(u1, -p1_top.y) * uv_scale)
		st.set_uv2(Vector2(y1 - p1_top.y, 0.0))
		st.add_vertex(p1_top)

		# Triangle 2: p0_bot -> p1_top -> p0_top
		st.set_normal(n0)
		st.set_uv(Vector2(u0, -p0_bot.y) * uv_scale)
		st.set_uv2(Vector2(y1 - p0_bot.y, 0.0))
		st.add_vertex(p0_bot)

		st.set_normal(n1)
		st.set_uv(Vector2(u1, -p1_top.y) * uv_scale)
		st.set_uv2(Vector2(y1 - p1_top.y, 0.0))
		st.add_vertex(p1_top)

		st.set_normal(n0)
		st.set_uv(Vector2(u0, -p0_top.y) * uv_scale)
		st.set_uv2(Vector2(y1 - p0_top.y, 0.0))
		st.add_vertex(p0_top)

func _cliff_mat() -> ShaderMaterial:
	if _cliff_material == null or not (_cliff_material is ShaderMaterial):
		var mat := ShaderMaterial.new()
		mat.shader = load(CLIFF_SHADER_PATH)
		mat.set_shader_parameter("tex_rock_albedo", _load_tex(ROCK_TEX_PATH))
		mat.set_shader_parameter("tex_rock_normal", _load_tex(ROCK_NORM_PATH))
		mat.set_shader_parameter("tex_rock_roughness", _load_tex(ROCK_ROUGH_PATH))
		mat.set_shader_parameter("tex_grass", _load_tex(TEX_PATHS[0]))
		mat.set_shader_parameter("uv_scale", cliff_uv_scale)
		mat.set_shader_parameter("normal_depth", 1.3)
		mat.set_shader_parameter("roughness_scale", 1.0)
		mat.set_shader_parameter("top_blend_height", 0.25)
		mat.set_shader_parameter("top_blend_strength", 0.45)
		_cliff_material = mat
	return _cliff_material as ShaderMaterial

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
