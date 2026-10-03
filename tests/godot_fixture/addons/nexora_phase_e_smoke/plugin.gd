@tool
extends EditorPlugin

const PhaseE = preload("res://addons/nexora_godot_mcp/phase_e.gd")

var _wait_frames := 0


func _enter_tree() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	_wait_frames += 1
	if _wait_frames < 24:
		return
	set_process(false)
	EditorInterface.open_scene_from_path("res://phase_e_scene.tscn")
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var phase_e = PhaseE.new(self)

	var mesh: Dictionary = phase_e.execute(
		"mesh3d.create",
		{
			"parent_path": ".",
			"name": "Crate",
			"primitive": "box",
			"size": [2, 1, 2],
			"position": [0, 0.5, 0],
		}
	)
	if _failed("mesh", mesh):
		return

	var camera: Dictionary = phase_e.execute(
		"camera3d.create",
		{
			"parent_path": ".",
			"name": "Camera3D",
			"position": [0, 3, 6],
			"rotation": [-0.3, 0, 0],
			"current": true,
		}
	)
	if _failed("camera", camera):
		return

	var light: Dictionary = phase_e.execute(
		"light3d.create",
		{
			"parent_path": ".",
			"light_type": "DirectionalLight3D",
			"name": "Sun",
			"rotation": [-0.7, -0.5, 0],
			"energy": 1.2,
			"shadow_enabled": true,
		}
	)
	if _failed("light", light):
		return

	var environment: Dictionary = phase_e.execute(
		"world_environment.create",
		{
			"parent_path": ".",
			"name": "Environment",
			"background_mode": "color",
			"background_color": [0.08, 0.1, 0.14, 1.0],
			"ambient_light_color": [0.4, 0.45, 0.55, 1.0],
			"ambient_light_energy": 0.8,
		}
	)
	if _failed("environment", environment):
		return

	var body: Dictionary = phase_e.execute(
		"collision3d.body_create",
		{
			"parent_path": ".",
			"body_type": "StaticBody3D",
			"name": "GroundBody",
			"shape": {"type": "box", "size": [8, 0.5, 8]},
			"position": [0, -0.25, 0],
		}
	)
	if _failed("body", body):
		return

	var extra_shape: Dictionary = phase_e.execute(
		"collision3d.shape_create",
		{
			"parent_path": "GroundBody",
			"name": "ExtraShape",
			"shape": {"type": "sphere", "radius": 0.4},
			"position": [2, 1, 0],
		}
	)
	if _failed("shape", extra_shape):
		return

	var skeleton: Dictionary = phase_e.execute(
		"skeleton3d.inspect",
		{"node_path": "Skeleton3D", "max_bones": 32}
	)
	if _failed("skeleton", skeleton):
		return
	if int(skeleton.get("bone_count", -1)) < 0:
		print("NEXORA_PHASE_E_SMOKE_FAIL invalid skeleton count: ", skeleton)
		return

	print("NEXORA_PHASE_E_SMOKE_OK")


func _failed(label: String, result: Dictionary) -> bool:
	if result.has("__nexora_error"):
		print("NEXORA_PHASE_E_SMOKE_FAIL ", label, ": ", result)
		return true
	return false
