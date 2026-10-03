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

	var created: Dictionary = phase_b.execute(
		"scene.create",
		{
			"root_type": "Node3D",
			"name": "GeneratedSmoke",
			"path": "res://generated_smoke.tscn",
			"open_after_create": false,
			"overwrite": true,
		}
	)
	if created.has("__nexora_error"):
		print("NEXORA_PHASE_B_SMOKE_FAIL create: ", created)
		return

	var duplicated: Dictionary = phase_b.execute(
		"scene.duplicate",
		{
			"source_path": "res://generated_smoke.tscn",
			"destination_path": "res://generated_smoke_copy.tscn",
			"overwrite": true,
		}
	)
	if duplicated.has("__nexora_error"):
		print("NEXORA_PHASE_B_SMOKE_FAIL duplicate: ", duplicated)
		return

	var generated_resource: Dictionary = phase_b.execute(
		"resource.inspect",
		{"path": "res://generated_smoke_copy.tscn", "max_properties": 20}
	)
	if generated_resource.has("__nexora_error"):
		print("NEXORA_PHASE_B_SMOKE_FAIL generated resource: ", generated_resource)
		return

	print("NEXORA_PHASE_B_SMOKE_OK")
