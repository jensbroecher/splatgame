## Run headlessly to bake the walk animation to res://characters/animations/walk.tres
## and patch player.tscn to add an AnimationPlayer node.
##
## Usage (from project root):
##   godot --headless --script res://bake_walk_anim.gd
@tool
extends SceneTree

# ─── Tuning values ────────────────────────────────────────────────────────────
const FRAMES          := 60      # keyframes per cycle (60 = smooth at 60fps)
const DURATION        := 1.0     # seconds for one full gait cycle
const LEG_SWING       := 0.45    # rad, max hip swing
const KNEE_BEND       := 0.30    # rad, extra knee bend at mid-swing
const KNEE_IDLE       := 0.10    # rad, constant knee bend (never fully straight)
const ARM_SWING       := 0.30    # rad, arm counter-swing
const HIP_BOB         := 0.0003  # skeleton-units, vertical bob amplitude (centred ±)
const HIP_SWAY        := 0.0005  # skeleton-units, lateral sway amplitude
const SPINE_TWIST     := 0.06    # rad, spine counter-rotation

# Where to write the baked animation
const ANIM_OUT_PATH   := "res://characters/animations/walk.tres"
const IDLE_OUT_PATH   := "res://characters/animations/idle.tres"
const LIB_OUT_PATH    := "res://characters/animations/walk_library.tres"

# ─── Skeleton path relative to the AnimationPlayer's root node (Player) ───────
const SKEL_REL := "Visual/accurig/GeneralSkeleton"

func _init() -> void:
	var acc := load("res://characters/accurig.fbx").instantiate() as Node
	var skel := _find_skel(acc)
	if skel == null:
		push_error("Skeleton not found – aborting bake")
		quit(1)
		return

	# Cache rest rotations (pose is initialised to rest on load)
	var B := {
		"hips":  skel.find_bone("Hips"),
		"spine": skel.find_bone("Spine"),
		"lul":   skel.find_bone("LeftUpperLeg"),
		"lll":   skel.find_bone("LeftLowerLeg"),
		"lf":    skel.find_bone("LeftFoot"),
		"rul":   skel.find_bone("RightUpperLeg"),
		"rll":   skel.find_bone("RightLowerLeg"),
		"rf":    skel.find_bone("RightFoot"),
		"lua":   skel.find_bone("LeftUpperArm"),
		"rua":   skel.find_bone("RightUpperArm"),
	}
	var R := {}
	for k in B:
		R[k] = skel.get_bone_pose_rotation(B[k])
	var rest_hips_pos: Vector3 = skel.get_bone_pose(B["hips"]).origin

	# ── Build walk animation ─────────────────────────────────────────────────
	var walk := Animation.new()
	walk.length      = DURATION
	walk.loop_mode   = Animation.LOOP_LINEAR

	# Add rotation track helper
	var t_hips_p  : int = _add_pos_track(walk, SKEL_REL, "Hips")
	var t_hips_r  : int = _add_rot_track(walk, SKEL_REL, "Hips")
	var t_spine   : int = _add_rot_track(walk, SKEL_REL, "Spine")
	var t_lul     : int = _add_rot_track(walk, SKEL_REL, "LeftUpperLeg")
	var t_lll     : int = _add_rot_track(walk, SKEL_REL, "LeftLowerLeg")
	var t_lf      : int = _add_rot_track(walk, SKEL_REL, "LeftFoot")
	var t_rul     : int = _add_rot_track(walk, SKEL_REL, "RightUpperLeg")
	var t_rll     : int = _add_rot_track(walk, SKEL_REL, "RightLowerLeg")
	var t_rf      : int = _add_rot_track(walk, SKEL_REL, "RightFoot")
	var t_lua     : int = _add_rot_track(walk, SKEL_REL, "LeftUpperArm")
	var t_rua     : int = _add_rot_track(walk, SKEL_REL, "RightUpperArm")

	for frame in range(FRAMES + 1):
		var time   := (float(frame) / FRAMES) * DURATION
		var t      := (float(frame) / FRAMES) * TAU   # 0 → 2π

		var l_swing := sin(t) * LEG_SWING
		var r_swing := sin(t + PI) * LEG_SWING
		var l_knee  := KNEE_IDLE + absf(sin(t)) * KNEE_BEND
		var r_knee  := KNEE_IDLE + absf(sin(t + PI)) * KNEE_BEND

		# Hip: bob at 2× freq (centred around 0 so no net downward drift)
		var hip_bob  := sin(2.0 * t) * HIP_BOB
		var hip_sway := sin(t) * HIP_SWAY
		walk.position_track_insert_key(t_hips_p, time,
			rest_hips_pos + Vector3(hip_sway, hip_bob, 0.0))
		walk.rotation_track_insert_key(t_hips_r, time, R["hips"])

		walk.rotation_track_insert_key(t_spine, time,
			R["spine"] * Quaternion(Vector3(0, 1, 0), sin(t) * SPINE_TWIST))

		# Legs  (local +X axis; positive = backward, negative = forward)
		walk.rotation_track_insert_key(t_lul, time,
			R["lul"] * Quaternion(Vector3(1, 0, 0), -l_swing))
		walk.rotation_track_insert_key(t_lll, time,
			R["lll"] * Quaternion(Vector3(1, 0, 0), l_knee))
		walk.rotation_track_insert_key(t_lf, time,
			R["lf"]  * Quaternion(Vector3(1, 0, 0), l_swing * 0.5))

		walk.rotation_track_insert_key(t_rul, time,
			R["rul"] * Quaternion(Vector3(1, 0, 0), -r_swing))
		walk.rotation_track_insert_key(t_rll, time,
			R["rll"] * Quaternion(Vector3(1, 0, 0), r_knee))
		walk.rotation_track_insert_key(t_rf, time,
			R["rf"]  * Quaternion(Vector3(1, 0, 0), r_swing * 0.5))

		# Arms (local +Y axis; counter-swing to legs)
		walk.rotation_track_insert_key(t_lua, time,
			R["lua"] * Quaternion(Vector3(0, 1, 0),  l_swing * (ARM_SWING / LEG_SWING)))
		walk.rotation_track_insert_key(t_rua, time,
			R["rua"] * Quaternion(Vector3(0, 1, 0), -r_swing * (ARM_SWING / LEG_SWING)))

	# ── Build idle animation (single frame at full rest) ──────────────────────
	var idle := Animation.new()
	idle.length    = 0.001
	idle.loop_mode = Animation.LOOP_LINEAR

	_add_idle_bone_pos(idle, SKEL_REL, "Hips",  rest_hips_pos)
	_add_idle_bone_rot(idle, SKEL_REL, "Hips",  R["hips"])
	_add_idle_bone_rot(idle, SKEL_REL, "Spine", R["spine"])
	_add_idle_bone_rot(idle, SKEL_REL, "LeftUpperLeg",  R["lul"])
	_add_idle_bone_rot(idle, SKEL_REL, "LeftLowerLeg",  R["lll"])
	_add_idle_bone_rot(idle, SKEL_REL, "LeftFoot",      R["lf"])
	_add_idle_bone_rot(idle, SKEL_REL, "RightUpperLeg", R["rul"])
	_add_idle_bone_rot(idle, SKEL_REL, "RightLowerLeg", R["rll"])
	_add_idle_bone_rot(idle, SKEL_REL, "RightFoot",     R["rf"])
	_add_idle_bone_rot(idle, SKEL_REL, "LeftUpperArm",  R["lua"])
	_add_idle_bone_rot(idle, SKEL_REL, "RightUpperArm", R["rua"])

	# ── Build AnimationLibrary ────────────────────────────────────────────────
	var lib := AnimationLibrary.new()
	lib.add_animation("walk", walk)
	lib.add_animation("idle", idle)

	# ── Save ──────────────────────────────────────────────────────────────────
	DirAccess.make_dir_recursive_absolute("res://characters/animations")
	var err := ResourceSaver.save(lib, LIB_OUT_PATH)
	if err != OK:
		push_error("Failed to save animation library: %d" % err)
		quit(1)
		return

	print("Saved animation library → ", LIB_OUT_PATH)
	print("Open player.tscn in Godot, select WalkAnimPlayer and use the Animation editor to tweak.")
	quit()


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s: return s
	return null


func _add_rot_track(anim: Animation, skel_rel: String, bone: String) -> int:
	var idx: int = anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(idx, NodePath("%s:%s" % [skel_rel, bone]))
	anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	return idx


func _add_pos_track(anim: Animation, skel_rel: String, bone: String) -> int:
	var idx: int = anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(idx, NodePath("%s:%s" % [skel_rel, bone]))
	anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	return idx


func _add_idle_bone_rot(anim: Animation, skel_rel: String, bone: String, rest_rot: Quaternion) -> void:
	var idx: int = anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(idx, NodePath("%s:%s" % [skel_rel, bone]))
	anim.rotation_track_insert_key(idx, 0.0, rest_rot)


func _add_idle_bone_pos(anim: Animation, skel_rel: String, bone: String, rest_pos: Vector3) -> void:
	var idx: int = anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(idx, NodePath("%s:%s" % [skel_rel, bone]))
	anim.position_track_insert_key(idx, 0.0, rest_pos)
