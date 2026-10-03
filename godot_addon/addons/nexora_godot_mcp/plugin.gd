@tool
extends EditorPlugin

const BridgeServer = preload("res://addons/nexora_godot_mcp/bridge_server.gd")
const PhaseB = preload("res://addons/nexora_godot_mcp/phase_b.gd")
const PhaseC = preload("res://addons/nexora_godot_mcp/phase_c.gd")
const PhaseD = preload("res://addons/nexora_godot_mcp/phase_d.gd")
const PhaseE = preload("res://addons/nexora_godot_mcp/phase_e.gd")
const PhaseF = preload("res://addons/nexora_godot_mcp/phase_f.gd")
const CONFIG_PATH := "res://.nexora-godot/bridge.json"

var _bridge = BridgeServer.new()
var _phase_b
var _phase_c
var _phase_d
var _phase_e
var _phase_f
var _dock: VBoxContainer
var _status_label: Label
var _project_label: Label
var _error_label: Label
var _bridge_config: Dictionary = {}


func _enter_tree() -> void:
	_phase_b = PhaseB.new(self)
	_phase_c = PhaseC.new(self)
	_phase_d = PhaseD.new(self)
	_phase_e = PhaseE.new(self)
	_phase_f = PhaseF.new(self)
	_build_dock()
	_bridge_config = _load_bridge_config()
	if bool(_bridge_config.get("auto_start", true)):
		_start_bridge()
	set_process(true)
	_refresh_status()


func _exit_tree() -> void:
	_bridge.stop()
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _process(_delta: float) -> void:
	_bridge.poll()
	_refresh_status()


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Nexora Godot MCP"

	var title := Label.new()
	title.text = "Nexora Godot MCP"
	title.add_theme_font_size_override("font_size", 16)
	_dock.add_child(title)

	_status_label = Label.new()
	_dock.add_child(_status_label)

	_project_label = Label.new()
	_project_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_project_label)

	var buttons := HBoxContainer.new()
	var start_button := Button.new()
	start_button.text = "Start Bridge"
	start_button.pressed.connect(_start_bridge)
	buttons.add_child(start_button)

	var stop_button := Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_stop_bridge)
	buttons.add_child(stop_button)
	_dock.add_child(buttons)

	_error_label = Label.new()
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_error_label)

	var hint := Label.new()
	hint.text = "AI chat stays in your MCP host. This plugin only exposes a private localhost execution bridge."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(hint)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _load_bridge_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {
			"host": "127.0.0.1",
			"port": 9877,
			"secret": OS.get_environment("NEXORA_GODOT_BRIDGE_SECRET"),
			"auto_start": true,
		}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _start_bridge() -> void:
	_bridge_config = _load_bridge_config()
	var secret := String(_bridge_config.get("secret", ""))
	var port := int(_bridge_config.get("port", 9877))
	var error := _bridge.start(port, secret, execute_operation)
	if error != OK:
		_error_label.text = _bridge.last_error()
	else:
		_error_label.text = ""
	_refresh_status()


func _stop_bridge() -> void:
	_bridge.stop()
	_refresh_status()


func _refresh_status() -> void:
	if _status_label == null:
		return
	_status_label.text = "Bridge: %s · 127.0.0.1:%d" % [
		"Running" if _bridge.is_running() else "Stopped",
		_bridge.port(),
	]
	_project_label.text = "Project: %s" % ProjectSettings.globalize_path("res://")
	if not _bridge.last_error().is_empty():
		_error_label.text = _bridge.last_error()


func execute_operation(operation: String, params: Dictionary) -> Dictionary:
	match operation:
		"system.status":
			return _system_status()
		"scene.snapshot":
			return _scene_snapshot(int(params.get("max_nodes", 500)))
		"scene.open":
			return _scene_open(String(params.get("path", "")))
		"scene.save":
			return _scene_save(String(params.get("path", "")))
		"batch.execute":
			return _batch_execute(params)

	if _phase_b != null:
		var phase_b_result: Dictionary = _phase_b.execute(operation, params)
		if not phase_b_result.has("__nexora_unhandled"):
			return phase_b_result

	if _phase_c != null:
		var phase_c_result: Dictionary = _phase_c.execute(operation, params)
		if not phase_c_result.has("__nexora_unhandled"):
			return phase_c_result

	if _phase_d != null:
		var phase_d_result: Dictionary = _phase_d.execute(operation, params)
		if not phase_d_result.has("__nexora_unhandled"):
			return phase_d_result

	if _phase_e != null:
		var phase_e_result: Dictionary = _phase_e.execute(operation, params)
		if not phase_e_result.has("__nexora_unhandled"):
			return phase_e_result

	if _phase_f != null:
		var phase_f_result: Dictionary = _phase_f.execute(operation, params)
		if not phase_f_result.has("__nexora_unhandled"):
			return phase_f_result

	return _failure("unsupported_operation: %s" % operation)


func _system_status() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	return {
		"godot_version": Engine.get_version_info(),
		"project_path": ProjectSettings.globalize_path("res://"),
		"edited_scene": root.scene_file_path if root else "",
		"edited_scene_name": root.name if root else "",
		"is_playing": EditorInterface.is_playing_scene(),
		"bridge_port": _bridge.port(),
	}


func _scene_snapshot(max_nodes: int) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {
			"scene": null,
			"nodes": [],
			"node_count": 0,
		}

	var bounded := clampi(max_nodes, 1, 2000)
	var nodes: Array[Dictionary] = []
	_collect_nodes(root, root, nodes, bounded)
	return {
		"scene": {
			"name": root.name,
			"type": root.get_class(),
			"path": root.scene_file_path,
		},
		"nodes": nodes,
		"node_count": nodes.size(),
		"truncated": nodes.size() >= bounded,
	}


func _collect_nodes(root: Node, node: Node, output: Array[Dictionary], limit: int) -> void:
	if output.size() >= limit:
		return
	output.append({
		"name": node.name,
		"type": node.get_class(),
		"path": "." if node == root else str(root.get_path_to(node)),
		"child_count": node.get_child_count(),
	})
	for child in node.get_children():
		if output.size() >= limit:
			return
		_collect_nodes(root, child, output, limit)


func _scene_open(path: String) -> Dictionary:
	if not _valid_resource_path(path, [".tscn", ".scn"]):
		return _failure("scene path must be a project-local .tscn or .scn resource")
	EditorInterface.open_scene_from_path(path)
	return {"path": path, "opened": true}


func _scene_save(path: String) -> Dictionary:
	if path.is_empty():
		var error := EditorInterface.save_scene()
		if error != OK:
			return _failure("save_scene failed with error %d" % error)
		var root := EditorInterface.get_edited_scene_root()
		return {"path": root.scene_file_path if root else "", "saved": true}

	if not _valid_resource_path(path, [".tscn"]):
		return _failure("save path must be a project-local .tscn resource")
	EditorInterface.save_scene_as(path)
	return {"path": path, "saved": true}


func _scene_create(root_type: String, root_name: String, path: String) -> Dictionary:
	if EditorInterface.get_edited_scene_root() != null:
		return _failure("scene_create requires an empty editor scene tab in Phase A")
	if not _valid_resource_path(path, [".tscn"]):
		return _failure("scene path must be a project-local .tscn resource")
	if root_type.is_empty() or root_name.is_empty():
		return _failure("root_type and name are required")
	if not ClassDB.class_exists(root_type):
		return _failure("unknown Godot class: %s" % root_type)
	var instance = ClassDB.instantiate(root_type)
	if not instance is Node:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("%s is not a Node-derived class" % root_type)

	var root: Node = instance
	root.name = root_name
	EditorInterface.add_root_node(root)
	EditorInterface.save_scene_as(path)
	return {
		"path": path,
		"root": root.name,
		"type": root.get_class(),
	}


func _node_create(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var node_type := String(params.get("node_type", ""))
	var node_name := String(params.get("name", ""))
	if node_type.is_empty() or node_name.is_empty():
		return _failure("node_type and name are required")
	if not ClassDB.class_exists(node_type):
		return _failure("unknown Godot class: %s" % node_type)

	var instance = ClassDB.instantiate(node_type)
	if not instance is Node:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("%s is not a Node-derived class" % node_type)

	var node: Node = instance
	node.name = node_name
	parent.add_child(node)
	node.owner = root

	var property_result := _apply_properties(node, params.get("properties", {}))
	if property_result.has("__nexora_error"):
		parent.remove_child(node)
		node.free()
		return property_result

	EditorInterface.mark_scene_as_unsaved()
	return {
		"path": str(root.get_path_to(node)),
		"name": node.name,
		"type": node.get_class(),
		"properties_changed": property_result.get("changed", []),
	}


func _node_set_properties(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	if node == null:
		return _failure("node not found")
	var result := _apply_properties(node, params.get("properties", {}))
	if not result.has("__nexora_error"):
		EditorInterface.mark_scene_as_unsaved()
	return result


func _node_delete(node_path: String) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, node_path)
	if node == null:
		return _failure("node not found")
	if node == root:
		return _failure("deleting the scene root is not allowed")
	var deleted_path := str(root.get_path_to(node))
	var parent := node.get_parent()
	if parent:
		parent.remove_child(node)
	node.free()
	EditorInterface.mark_scene_as_unsaved()
	return {"deleted": true, "path": deleted_path}


func _batch_execute(params: Dictionary) -> Dictionary:
	var steps = params.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return _failure("steps must be an array")
	if steps.is_empty() or steps.size() > 50:
		return _failure("batch size must be between 1 and 50")
	var stop_on_error := bool(params.get("stop_on_error", true))
	var results: Array[Dictionary] = []

	for index in range(steps.size()):
		var step = steps[index]
		if typeof(step) != TYPE_DICTIONARY:
			var invalid := {"index": index, "ok": false, "error": "step must be an object"}
			results.append(invalid)
			if stop_on_error:
				break
			continue
		var operation := String(step.get("operation", ""))
		var forbidden := {
			"batch.execute": true,
			"editor_script.execute": true,
			"node.delete": true,
			"scene.close": true,
			"scene.reload": true,
			"scene.create": true,
			"scene.duplicate": true,
			"input.action_delete": true,
			"input.event_remove": true,
			"project.settings_clear": true,
			"autoload.remove": true,
		}
		if forbidden.has(operation):
			var blocked := {
				"index": index,
				"ok": false,
				"error": "operation is not allowed inside batch_execute: %s" % operation,
			}
			results.append(blocked)
			if stop_on_error:
				break
			continue
		var step_params = step.get("params", {})
		if typeof(step_params) != TYPE_DICTIONARY:
			step_params = {}
		var result := execute_operation(operation, step_params)
		if result.has("__nexora_error"):
			results.append({
				"index": index,
				"operation": operation,
				"ok": false,
				"error": result.get("__nexora_error"),
			})
			if stop_on_error:
				break
		else:
			results.append({
				"index": index,
				"operation": operation,
				"ok": true,
				"result": result,
			})

	return {"results": results, "count": results.size()}


func _find_node(root: Node, path: String) -> Node:
	if path.is_empty() or path == "." or path == "/":
		return root
	return root.get_node_or_null(NodePath(path))


func _apply_properties(node: Node, raw_properties) -> Dictionary:
	if typeof(raw_properties) != TYPE_DICTIONARY:
		return _failure("properties must be an object")
	var properties: Dictionary = raw_properties
	if properties.size() > 100:
		return _failure("too many properties")

	var denied := {
		"script": true,
		"owner": true,
		"scene_file_path": true,
	}
	var known := {}
	for item in node.get_property_list():
		known[String(item.get("name", ""))] = true

	var changed: Array[String] = []
	for key_variant in properties.keys():
		var key := String(key_variant)
		if denied.has(key):
			return _failure("property is not writable through node.set_properties: %s" % key)
		if not known.has(key):
			return _failure("unknown property for %s: %s" % [node.get_class(), key])
		var current = node.get(key)
		var coerced = _coerce_value(current, properties[key_variant])
		node.set(key, coerced)
		changed.append(key)

	return {"changed": changed, "node": node.name}


func _coerce_value(current, incoming):
	match typeof(current):
		TYPE_VECTOR2:
			if typeof(incoming) == TYPE_ARRAY and incoming.size() >= 2:
				return Vector2(float(incoming[0]), float(incoming[1]))
		TYPE_VECTOR2I:
			if typeof(incoming) == TYPE_ARRAY and incoming.size() >= 2:
				return Vector2i(int(incoming[0]), int(incoming[1]))
		TYPE_VECTOR3:
			if typeof(incoming) == TYPE_ARRAY and incoming.size() >= 3:
				return Vector3(float(incoming[0]), float(incoming[1]), float(incoming[2]))
		TYPE_VECTOR3I:
			if typeof(incoming) == TYPE_ARRAY and incoming.size() >= 3:
				return Vector3i(int(incoming[0]), int(incoming[1]), int(incoming[2]))
		TYPE_COLOR:
			if typeof(incoming) == TYPE_ARRAY and incoming.size() >= 3:
				var alpha := float(incoming[3]) if incoming.size() > 3 else 1.0
				return Color(float(incoming[0]), float(incoming[1]), float(incoming[2]), alpha)
		TYPE_STRING_NAME:
			return StringName(String(incoming))
	return incoming


func _valid_resource_path(path: String, extensions: Array[String]) -> bool:
	if not path.begins_with("res://"):
		return false
	if path.contains(".."):
		return false
	var lowered := path.to_lower()
	for extension in extensions:
		if lowered.ends_with(extension):
			return true
	return false


func _failure(message: String) -> Dictionary:
	return {"__nexora_error": message}
