@tool
extends EditorPlugin

const PhaseC = preload("res://addons/nexora_godot_mcp/phase_c.gd")


func _enter_tree() -> void:
	call_deferred("_prepare_smoke")


func _prepare_smoke() -> void:
	EditorInterface.open_scene_from_path("res://phase_c_scene.tscn")
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var phase_c = PhaseC.new(self)

	var symbols: Dictionary = phase_c.execute(
		"script.symbols",
		{"path": "res://scripts/phase_c_fixture.gd"}
	)
	if symbols.has("__nexora_error") or int(symbols.get("methods", []).size()) < 2:
		print("NEXORA_PHASE_C_SMOKE_FAIL symbols: ", symbols)
		return

	var attach: Dictionary = phase_c.execute(
		"script.attach",
		{
			"node_path": "Target",
			"script_path": "res://scripts/phase_c_fixture.gd",
		}
	)
	if attach.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL attach: ", attach)
		return

	var connected: Dictionary = phase_c.execute(
		"signal.connect",
		{
			"source_path": "Source",
			"signal_name": "renamed",
			"target_path": "Target",
			"method": "_on_source_renamed",
			"persist": true,
		}
	)
	if connected.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL signal connect: ", connected)
		return

	var connections: Dictionary = phase_c.execute(
		"signal.connections",
		{
			"node_path": "Source",
			"signal_name": "renamed",
		}
	)
	if connections.has("__nexora_error") or int(connections.get("count", 0)) != 1:
		print("NEXORA_PHASE_C_SMOKE_FAIL signal inspect: ", connections)
		return

	var disconnected: Dictionary = phase_c.execute(
		"signal.disconnect",
		{
			"source_path": "Source",
			"signal_name": "renamed",
			"target_path": "Target",
			"method": "_on_source_renamed",
		}
	)
	if disconnected.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL signal disconnect: ", disconnected)
		return

	var input_created: Dictionary = phase_c.execute(
		"input.action_create",
		{"name": "nexora_phase_c_smoke", "deadzone": 0.25}
	)
	if input_created.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL input create: ", input_created)
		return

	var input_event: Dictionary = phase_c.execute(
		"input.event_add",
		{
			"action": "nexora_phase_c_smoke",
			"event": {"type": "key", "keycode": 32},
		}
	)
	if input_event.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL input event: ", input_event)
		return

	var input_removed: Dictionary = phase_c.execute(
		"input.event_remove",
		{"action": "nexora_phase_c_smoke", "index": 0}
	)
	if input_removed.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL input remove: ", input_removed)
		return

	var input_deleted: Dictionary = phase_c.execute(
		"input.action_delete",
		{"name": "nexora_phase_c_smoke"}
	)
	if input_deleted.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL input delete: ", input_deleted)
		return

	var settings_set: Dictionary = phase_c.execute(
		"project.settings_set",
		{"values": {"nexora_phase_c/smoke": "ok"}}
	)
	if settings_set.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL settings set: ", settings_set)
		return

	var settings_read: Dictionary = phase_c.execute(
		"project.settings_read",
		{"keys": ["nexora_phase_c/smoke"], "max_results": 10}
	)
	if settings_read.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL settings read: ", settings_read)
		return
	if String(settings_read.get("values", {}).get("nexora_phase_c/smoke", "")) != "ok":
		print("NEXORA_PHASE_C_SMOKE_FAIL settings value: ", settings_read)
		return

	var settings_clear: Dictionary = phase_c.execute(
		"project.settings_clear",
		{"keys": ["nexora_phase_c/smoke"]}
	)
	if settings_clear.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL settings clear: ", settings_clear)
		return

	var autoload_added: Dictionary = phase_c.execute(
		"autoload.add",
		{
			"name": "NexoraPhaseCSmoke",
			"path": "res://scripts/phase_c_fixture.gd",
		}
	)
	if autoload_added.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL autoload add: ", autoload_added)
		return

	var autoloads: Dictionary = phase_c.execute("autoload.list", {})
	if autoloads.has("__nexora_error") or int(autoloads.get("count", 0)) < 1:
		print("NEXORA_PHASE_C_SMOKE_FAIL autoload list: ", autoloads)
		return

	var autoload_removed: Dictionary = phase_c.execute(
		"autoload.remove",
		{"name": "NexoraPhaseCSmoke"}
	)
	if autoload_removed.has("__nexora_error"):
		print("NEXORA_PHASE_C_SMOKE_FAIL autoload remove: ", autoload_removed)
		return

	print("NEXORA_PHASE_C_SMOKE_OK")
