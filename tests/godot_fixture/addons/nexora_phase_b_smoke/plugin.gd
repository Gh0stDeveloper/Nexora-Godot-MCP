@tool
extends EditorPlugin

const PhaseB = preload("res://addons/nexora_godot_mcp/phase_b.gd")


func _enter_tree() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var phase_b = PhaseB.new(self)

	var dependencies: Dictionary = phase_b.execute(
		"scene.dependencies",
		{"path": "res://main.tscn"}
	)
	if dependencies.has("__nexora_error"):
		print("NEXORA_PHASE_B_SMOKE_FAIL dependencies: ", dependencies)
		return

	var resource: Dictionary = phase_b.execute(
		"resource.inspect",
		{"path": "res://main.tscn", "max_properties": 20}
	)
	if resource.has("__nexora_error"):
		print("NEXORA_PHASE_B_SMOKE_FAIL resource: ", resource)
		return

	var filesystem: Dictionary = phase_b.execute("filesystem.status", {})
	if filesystem.has("__nexora_error"):
		print("NEXORA_PHASE_B_SMOKE_FAIL filesystem: ", filesystem)
		return

	var scenes: Dictionary = phase_b.execute("scene.open_scenes", {})
	if scenes.has("__nexora_error"):
		print("NEXORA_PHASE_B_SMOKE_FAIL scenes: ", scenes)
		return

	print("NEXORA_PHASE_B_SMOKE_OK")
