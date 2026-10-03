@tool
extends RefCounted

var _plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func execute(operation: String, params: Dictionary) -> Dictionary:
	match operation:
		"script.symbols":
			return _script_symbols(String(params.get("path", "")))
		"script.attach":
			return _script_attach(params)
		"script.detach":
			return _script_detach(String(params.get("node_path", "")))
		"signal.list":
			return _signal_list(params)
		"signal.connections":
			return _signal_connections(params)
		"signal.connect":
			return _signal_connect(params)
		"signal.disconnect":
			return _signal_disconnect(params)
		"input.actions_list":
			return _input_actions_list()
		"input.action_create":
			return _input_action_create(params)
		"input.action_set_deadzone":
			return _input_action_set_deadzone(params)
		"input.action_delete":
			return _input_action_delete(String(params.get("name", "")))
		"input.event_add":
			return _input_event_add(params)
		"input.event_remove":
			return _input_event_remove(params)
		"project.settings_read":
			return _project_settings_read(params)
		"project.settings_set":
			return _project_settings_set(params)
		"project.settings_clear":
			return _project_settings_clear(params)
		"autoload.list":
			return _autoload_list()
		"autoload.add":
			return _autoload_add(params)
		"autoload.remove":
			return _autoload_remove(String(params.get("name", "")))
		_:
			return {"__nexora_unhandled": true}


func _script_symbols(path: String) -> Dictionary:
	if not _valid_script_path(path):
		return _failure("script path must be a project-local .gd or .cs file")
	if not FileAccess.file_exists(path):
		return _failure("script file does not exist")

	var loaded := ResourceLoader.load(path)
	if not loaded is Script:
		return _failure("resource could not be loaded as a Script")

	var script: Script = loaded
	var base_script := script.get_base_script()
	return {
		"path": path,
		"language": script.get_language().get_name() if script.get_language() else "",
		"global_name": String(script.get_global_name()),
		"base_script": base_script.resource_path if base_script else "",
		"can_instantiate": script.can_instantiate(),
		"methods": _serialize_variant(script.get_script_method_list(), 0),
		"signals": _serialize_variant(script.get_script_signal_list(), 0),
		"properties": _serialize_variant(script.get_script_property_list(), 0),
	}


func _script_attach(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	if node == null:
		return _failure("node not found")

	var script_path := String(params.get("script_path", ""))
	if not _valid_script_path(script_path):
		return _failure("script_path must be a project-local .gd or .cs file")
	if not FileAccess.file_exists(script_path):
		return _failure("script file does not exist")

	var loaded := ResourceLoader.load(script_path)
	if not loaded is Script:
		return _failure("script resource could not be loaded")
	var new_script: Script = loaded
	var old_script = node.get_script()
	if old_script == new_script:
		return {
			"node_path": "." if node == root else str(root.get_path_to(node)),
			"script_path": script_path,
			"changed": false,
			"undoable": true,
		}

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Attach Script", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(node, "set_script", new_script)
	undo_redo.add_undo_method(node, "set_script", old_script)
	undo_redo.commit_action()

	return {
		"node_path": "." if node == root else str(root.get_path_to(node)),
		"script_path": script_path,
		"previous_script": old_script.resource_path if old_script is Script else "",
		"changed": true,
		"undoable": true,
	}


func _script_detach(node_path: String) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, node_path)
	if node == null:
		return _failure("node not found")
	var old_script = node.get_script()
	if old_script == null:
		return {
			"node_path": "." if node == root else str(root.get_path_to(node)),
			"changed": false,
			"undoable": true,
		}

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Detach Script", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(node, "set_script", null)
	undo_redo.add_undo_method(node, "set_script", old_script)
	undo_redo.commit_action()

	return {
		"node_path": "." if node == root else str(root.get_path_to(node)),
		"previous_script": old_script.resource_path if old_script is Script else "",
		"changed": true,
		"undoable": true,
	}


func _signal_list(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	if node == null:
		return _failure("node not found")
	var include_connections := bool(params.get("include_connections", true))
	var signals: Array[Dictionary] = []

	for signal_variant in node.get_signal_list():
		var signal_info: Dictionary = signal_variant
		var signal_name := String(signal_info.get("name", ""))
		var item := {
			"name": signal_name,
			"args": _serialize_variant(signal_info.get("args", []), 0),
			"default_args": _serialize_variant(signal_info.get("default_args", []), 0),
			"flags": int(signal_info.get("flags", 0)),
		}
		if include_connections:
			var connections: Array[Dictionary] = []
			for connection_variant in node.get_signal_connection_list(StringName(signal_name)):
				connections.append(_connection_to_dict(root, connection_variant))
			item["connections"] = connections
			item["connection_count"] = connections.size()
		signals.append(item)

	return {
		"node_path": "." if node == root else str(root.get_path_to(node)),
		"signals": signals,
		"count": signals.size(),
	}


func _signal_connections(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	if node == null:
		return _failure("node not found")
	var signal_name := String(params.get("signal_name", ""))
	if signal_name.is_empty() or not node.has_signal(StringName(signal_name)):
		return _failure("signal not found on node")

	var connections: Array[Dictionary] = []
	for connection_variant in node.get_signal_connection_list(StringName(signal_name)):
		connections.append(_connection_to_dict(root, connection_variant))
	return {
		"node_path": "." if node == root else str(root.get_path_to(node)),
		"signal_name": signal_name,
		"connections": connections,
		"count": connections.size(),
	}


func _signal_connect(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var source := _find_node(root, String(params.get("source_path", "")))
	var target := _find_node(root, String(params.get("target_path", "")))
	if source == null or target == null:
		return _failure("source or target node not found")

	var signal_name := String(params.get("signal_name", ""))
	var method := String(params.get("method", ""))
	if signal_name.is_empty() or not source.has_signal(StringName(signal_name)):
		return _failure("signal not found on source node")
	if method.is_empty() or not target.has_method(StringName(method)):
		return _failure("target method not found")

	var target_callable := Callable(target, StringName(method))
	if source.is_connected(StringName(signal_name), target_callable):
		return _failure("signal is already connected to target method")

	var flags := 0
	if bool(params.get("deferred", false)):
		flags |= Object.CONNECT_DEFERRED
	if bool(params.get("persist", true)):
		flags |= Object.CONNECT_PERSIST
	if bool(params.get("one_shot", false)):
		flags |= Object.CONNECT_ONE_SHOT
	if bool(params.get("reference_counted", false)):
		flags |= Object.CONNECT_REFERENCE_COUNTED

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Connect Signal", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(
		self,
		"_do_connect_signal",
		source,
		StringName(signal_name),
		target_callable,
		flags
	)
	undo_redo.add_undo_method(
		self,
		"_do_disconnect_signal",
		source,
		StringName(signal_name),
		target_callable
	)
	undo_redo.commit_action()

	return {
		"source_path": "." if source == root else str(root.get_path_to(source)),
		"signal_name": signal_name,
		"target_path": "." if target == root else str(root.get_path_to(target)),
		"method": method,
		"flags": flags,
		"persistent": (flags & Object.CONNECT_PERSIST) != 0,
		"undoable": true,
	}


func _signal_disconnect(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var source := _find_node(root, String(params.get("source_path", "")))
	var target := _find_node(root, String(params.get("target_path", "")))
	if source == null or target == null:
		return _failure("source or target node not found")

	var signal_name := String(params.get("signal_name", ""))
	var method := String(params.get("method", ""))
	if signal_name.is_empty() or not source.has_signal(StringName(signal_name)):
		return _failure("signal not found on source node")

	var target_callable := Callable(target, StringName(method))
	if not source.is_connected(StringName(signal_name), target_callable):
		return _failure("signal is not connected to target method")

	var flags := _connection_flags(source, StringName(signal_name), target_callable)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Disconnect Signal", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(
		self,
		"_do_disconnect_signal",
		source,
		StringName(signal_name),
		target_callable
	)
	undo_redo.add_undo_method(
		self,
		"_do_connect_signal",
		source,
		StringName(signal_name),
		target_callable,
		flags
	)
	undo_redo.commit_action()

	return {
		"source_path": "." if source == root else str(root.get_path_to(source)),
		"signal_name": signal_name,
		"target_path": "." if target == root else str(root.get_path_to(target)),
		"method": method,
		"disconnected": true,
		"undoable": true,
	}


func _do_connect_signal(
	source: Object,
	signal_name: StringName,
	target_callable: Callable,
	flags: int
) -> void:
	if not source.is_connected(signal_name, target_callable):
		source.connect(signal_name, target_callable, flags)


func _do_disconnect_signal(
	source: Object,
	signal_name: StringName,
	target_callable: Callable
) -> void:
	if source.is_connected(signal_name, target_callable):
		source.disconnect(signal_name, target_callable)


func _connection_flags(
	source: Object,
	signal_name: StringName,
	target_callable: Callable
) -> int:
	for connection_variant in source.get_signal_connection_list(signal_name):
		var connection: Dictionary = connection_variant
		if connection.get("callable") == target_callable:
			return int(connection.get("flags", 0))
	return 0


func _connection_to_dict(root: Node, raw_connection) -> Dictionary:
	var connection: Dictionary = raw_connection
	var target_callable: Callable = connection.get("callable", Callable())
	var target_object = target_callable.get_object()
	var target_path := ""
	if target_object is Node:
		var target_node: Node = target_object
		if target_node == root:
			target_path = "."
		elif root.is_ancestor_of(target_node):
			target_path = str(root.get_path_to(target_node))
	return {
		"target_path": target_path,
		"target_class": target_object.get_class() if target_object != null else "",
		"method": String(target_callable.get_method()),
		"flags": int(connection.get("flags", 0)),
	}


func _input_actions_list() -> Dictionary:
	var actions: Array[Dictionary] = []
	for item_variant in ProjectSettings.get_property_list():
		var item: Dictionary = item_variant
		var key := String(item.get("name", ""))
		if not key.begins_with("input/"):
			continue
		var action_name := key.trim_prefix("input/")
		var setting = ProjectSettings.get_setting(key, {})
		if typeof(setting) != TYPE_DICTIONARY:
			continue
		var action_data: Dictionary = setting
		var raw_events = action_data.get("events", [])
		var events: Array[Dictionary] = []
		if typeof(raw_events) == TYPE_ARRAY:
			for event_variant in raw_events:
				if event_variant is InputEvent:
					events.append(_input_event_to_dict(event_variant))
		actions.append({
			"name": action_name,
			"deadzone": float(action_data.get("deadzone", 0.5)),
			"events": events,
			"event_count": events.size(),
			"persisted": true,
		})
	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	return {"actions": actions, "count": actions.size()}


func _input_action_create(params: Dictionary) -> Dictionary:
	var name := String(params.get("name", "")).strip_edges()
	var deadzone := float(params.get("deadzone", 0.5))
	if name.is_empty():
		return _failure("input action name cannot be empty")
	if name.contains("/"):
		return _failure("input action name cannot contain '/'")
	if deadzone < 0.0 or deadzone > 1.0:
		return _failure("deadzone must be between 0 and 1")
	var key := "input/%s" % name
	if ProjectSettings.has_setting(key):
		return _failure("input action already exists")

	ProjectSettings.set_setting(key, {"deadzone": deadzone, "events": []})
	var save_error := ProjectSettings.save()
	if save_error != OK:
		ProjectSettings.set_setting(key, null)
		return _failure("ProjectSettings.save failed with error %d" % save_error)
	return {
		"name": name,
		"deadzone": deadzone,
		"created": true,
		"persisted": true,
	}


func _input_action_set_deadzone(params: Dictionary) -> Dictionary:
	var name := String(params.get("name", ""))
	var deadzone := float(params.get("deadzone", 0.5))
	var key := "input/%s" % name
	if not ProjectSettings.has_setting(key):
		return _failure("input action does not exist")
	if deadzone < 0.0 or deadzone > 1.0:
		return _failure("deadzone must be between 0 and 1")
	var previous = ProjectSettings.get_setting(key)
	if typeof(previous) != TYPE_DICTIONARY:
		return _failure("input action setting is malformed")
	var updated: Dictionary = previous.duplicate(true)
	updated["deadzone"] = deadzone
	ProjectSettings.set_setting(key, updated)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		ProjectSettings.set_setting(key, previous)
		return _failure("ProjectSettings.save failed with error %d" % save_error)
	return {"name": name, "deadzone": deadzone, "persisted": true}


func _input_action_delete(name: String) -> Dictionary:
	var key := "input/%s" % name
	if not ProjectSettings.has_setting(key):
		return _failure("input action does not exist")
	var previous = ProjectSettings.get_setting(key)
	ProjectSettings.set_setting(key, null)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		ProjectSettings.set_setting(key, previous)
		return _failure("ProjectSettings.save failed with error %d" % save_error)
	return {"name": name, "deleted": true}


func _input_event_add(params: Dictionary) -> Dictionary:
	var name := String(params.get("action", ""))
	var key := "input/%s" % name
	if not ProjectSettings.has_setting(key):
		return _failure("input action does not exist")

	var event_result := _input_event_from_dict(params.get("event", {}))
	if event_result.has("__nexora_error"):
		return event_result
	var event: InputEvent = event_result["event"]

	var previous = ProjectSettings.get_setting(key)
	if typeof(previous) != TYPE_DICTIONARY:
		return _failure("input action setting is malformed")
	var updated: Dictionary = previous.duplicate(true)
	var raw_events = updated.get("events", [])
	if typeof(raw_events) != TYPE_ARRAY:
		return _failure("input action events are malformed")
	var events: Array = raw_events.duplicate(true)

	for existing_variant in events:
		if existing_variant is InputEvent:
			var existing: InputEvent = existing_variant
			if existing.is_match(event, true):
				return _failure("equivalent input event is already assigned to action")

	events.append(event)
	updated["events"] = events
	ProjectSettings.set_setting(key, updated)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		ProjectSettings.set_setting(key, previous)
		return _failure("ProjectSettings.save failed with error %d" % save_error)

	return {
		"action": name,
		"index": events.size() - 1,
		"event": _input_event_to_dict(event),
		"persisted": true,
	}


func _input_event_remove(params: Dictionary) -> Dictionary:
	var name := String(params.get("action", ""))
	var index := int(params.get("index", -1))
	var key := "input/%s" % name
	if not ProjectSettings.has_setting(key):
		return _failure("input action does not exist")

	var previous = ProjectSettings.get_setting(key)
	if typeof(previous) != TYPE_DICTIONARY:
		return _failure("input action setting is malformed")
	var updated: Dictionary = previous.duplicate(true)
	var raw_events = updated.get("events", [])
	if typeof(raw_events) != TYPE_ARRAY:
		return _failure("input action events are malformed")
	var events: Array = raw_events.duplicate(true)
	if index < 0 or index >= events.size():
		return _failure("input event index is out of range")
	var removed = events[index]
	events.remove_at(index)
	updated["events"] = events
	ProjectSettings.set_setting(key, updated)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		ProjectSettings.set_setting(key, previous)
		return _failure("ProjectSettings.save failed with error %d" % save_error)

	return {
		"action": name,
		"index": index,
		"removed": _input_event_to_dict(removed) if removed is InputEvent else str(removed),
		"persisted": true,
	}


func _input_event_from_dict(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("event must be an object")
	var data: Dictionary = raw
	var kind := String(data.get("type", "")).to_lower()
	var event: InputEvent

	match kind:
		"key":
			var key := InputEventKey.new()
			key.keycode = int(data.get("keycode", 0))
			key.physical_keycode = int(data.get("physical_keycode", 0))
			key.unicode = int(data.get("unicode", 0))
			key.location = int(data.get("location", 0))
			event = key
		"mouse_button":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(data.get("button_index", 0))
			event = mouse
		"joypad_button":
			var joy_button := InputEventJoypadButton.new()
			joy_button.button_index = int(data.get("button_index", 0))
			event = joy_button
		"joypad_motion":
			var joy_motion := InputEventJoypadMotion.new()
			joy_motion.axis = int(data.get("axis", 0))
			joy_motion.axis_value = float(data.get("axis_value", 1.0))
			event = joy_motion
		_:
			return _failure(
				"event.type must be key, mouse_button, joypad_button or joypad_motion"
			)

	event.device = int(data.get("device", -1))
	if event is InputEventWithModifiers:
		var modified: InputEventWithModifiers = event
		modified.alt_pressed = bool(data.get("alt", false))
		modified.shift_pressed = bool(data.get("shift", false))
		modified.ctrl_pressed = bool(data.get("ctrl", false))
		modified.meta_pressed = bool(data.get("meta", false))
	return {"event": event}


func _input_event_to_dict(event: InputEvent) -> Dictionary:
	var result := {
		"type": event.get_class(),
		"device": event.device,
		"text": event.as_text(),
	}
	if event is InputEventWithModifiers:
		var modified: InputEventWithModifiers = event
		result["alt"] = modified.alt_pressed
		result["shift"] = modified.shift_pressed
		result["ctrl"] = modified.ctrl_pressed
		result["meta"] = modified.meta_pressed
	if event is InputEventKey:
		result["kind"] = "key"
		result["keycode"] = event.keycode
		result["physical_keycode"] = event.physical_keycode
		result["unicode"] = event.unicode
		result["location"] = event.location
	elif event is InputEventMouseButton:
		result["kind"] = "mouse_button"
		result["button_index"] = event.button_index
	elif event is InputEventJoypadButton:
		result["kind"] = "joypad_button"
		result["button_index"] = event.button_index
	elif event is InputEventJoypadMotion:
		result["kind"] = "joypad_motion"
		result["axis"] = event.axis
		result["axis_value"] = event.axis_value
	return result


func _project_settings_read(params: Dictionary) -> Dictionary:
	var raw_keys = params.get("keys", [])
	var prefix := String(params.get("prefix", ""))
	var max_results := clampi(int(params.get("max_results", 200)), 1, 1000)
	var keys: Array[String] = []

	if typeof(raw_keys) == TYPE_ARRAY and not raw_keys.is_empty():
		for key_variant in raw_keys:
			var key := String(key_variant)
			if not key.is_empty():
				keys.append(key)
	else:
		for item_variant in ProjectSettings.get_property_list():
			if keys.size() >= max_results:
				break
			var item: Dictionary = item_variant
			var name := String(item.get("name", ""))
			if name.is_empty():
				continue
			if not prefix.is_empty() and not name.begins_with(prefix):
				continue
			keys.append(name)

	var values := {}
	for key in keys:
		if values.size() >= max_results:
			break
		if ProjectSettings.has_setting(key):
			values[key] = _serialize_variant(ProjectSettings.get_setting(key), 0)

	return {
		"values": values,
		"count": values.size(),
		"prefix": prefix,
		"truncated": values.size() >= max_results,
	}


func _project_settings_set(params: Dictionary) -> Dictionary:
	var raw_values = params.get("values", {})
	if typeof(raw_values) != TYPE_DICTIONARY:
		return _failure("values must be an object")
	var values: Dictionary = raw_values
	if values.is_empty() or values.size() > 100:
		return _failure("values must contain between 1 and 100 settings")

	var changed: Array[Dictionary] = []
	for key_variant in values.keys():
		var key := String(key_variant)
		var reserved_error := _validate_generic_setting_key(key)
		if not reserved_error.is_empty():
			return _failure(reserved_error)
		var value = values[key_variant]
		if value == null:
			return _failure("null removes a setting; use project_settings_clear")
		changed.append({
			"key": key,
			"had_previous": ProjectSettings.has_setting(key),
			"previous": _serialize_variant(ProjectSettings.get_setting(key), 0)
				if ProjectSettings.has_setting(key) else null,
		})
		ProjectSettings.set_setting(key, value)

	var save_error := ProjectSettings.save()
	if save_error != OK:
		for change in changed:
			if bool(change.get("had_previous", false)):
				ProjectSettings.set_setting(String(change["key"]), change.get("previous"))
			else:
				ProjectSettings.set_setting(String(change["key"]), null)
		return _failure("ProjectSettings.save failed with error %d" % save_error)

	return {
		"changed": values.keys(),
		"count": values.size(),
		"saved": true,
	}


func _project_settings_clear(params: Dictionary) -> Dictionary:
	var raw_keys = params.get("keys", [])
	if typeof(raw_keys) != TYPE_ARRAY or raw_keys.is_empty() or raw_keys.size() > 100:
		return _failure("keys must contain between 1 and 100 settings")
	var removed: Array[String] = []
	for key_variant in raw_keys:
		var key := String(key_variant)
		var reserved_error := _validate_generic_setting_key(key)
		if not reserved_error.is_empty():
			return _failure(reserved_error)
		if ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, null)
			removed.append(key)

	var save_error := ProjectSettings.save()
	if save_error != OK:
		return _failure("ProjectSettings.save failed with error %d" % save_error)
	return {"removed": removed, "count": removed.size(), "saved": true}


func _validate_generic_setting_key(key: String) -> String:
	if key.is_empty():
		return "project setting key cannot be empty"
	for prefix in ["input/", "autoload/", "editor_plugins/"]:
		if key.begins_with(prefix):
			return "%s settings require their dedicated MCP tools" % prefix.trim_suffix("/")
	if key == "_global_script_classes" or key == "_global_script_class_icons":
		return "global script class registry is managed by Godot and cannot be edited directly"
	return ""


func _autoload_list() -> Dictionary:
	var autoloads: Array[Dictionary] = []
	for item_variant in ProjectSettings.get_property_list():
		var item: Dictionary = item_variant
		var key := String(item.get("name", ""))
		if not key.begins_with("autoload/"):
			continue
		var raw := String(ProjectSettings.get_setting(key, ""))
		var singleton := raw.begins_with("*")
		var path := raw.substr(1) if singleton else raw
		autoloads.append({
			"name": key.trim_prefix("autoload/"),
			"path": path,
			"singleton": singleton,
		})
	autoloads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)
	return {"autoloads": autoloads, "count": autoloads.size()}


func _autoload_add(params: Dictionary) -> Dictionary:
	var name := String(params.get("name", "")).strip_edges()
	var path := String(params.get("path", ""))
	if not name.is_valid_identifier():
		return _failure("autoload name must be a valid Godot identifier")
	if not _valid_autoload_path(path) or not FileAccess.file_exists(path):
		return _failure("autoload path must be an existing project-local script or scene")
	var key := "autoload/%s" % name
	if ProjectSettings.has_setting(key):
		return _failure("autoload already exists")

	_plugin.add_autoload_singleton(name, path)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		_plugin.remove_autoload_singleton(name)
		return _failure("ProjectSettings.save failed with error %d" % save_error)
	return {
		"name": name,
		"path": path,
		"added": true,
		"singleton": true,
	}


func _autoload_remove(name: String) -> Dictionary:
	var normalized := name.strip_edges()
	if normalized.is_empty():
		return _failure("autoload name cannot be empty")
	var key := "autoload/%s" % normalized
	if not ProjectSettings.has_setting(key):
		return _failure("autoload does not exist")
	var raw := String(ProjectSettings.get_setting(key, ""))
	var path := raw.substr(1) if raw.begins_with("*") else raw

	_plugin.remove_autoload_singleton(normalized)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		_plugin.add_autoload_singleton(normalized, path)
		return _failure("ProjectSettings.save failed with error %d" % save_error)
	return {
		"name": normalized,
		"path": path,
		"removed": true,
		"source_deleted": false,
	}


func _find_node(root: Node, path: String) -> Node:
	if path.is_empty() or path == "." or path == "/":
		return root
	return root.get_node_or_null(NodePath(path))


func _valid_script_path(path: String) -> bool:
	if not _valid_project_path(path):
		return false
	var lowered := path.to_lower()
	return lowered.ends_with(".gd") or lowered.ends_with(".cs")


func _valid_autoload_path(path: String) -> bool:
	if not _valid_project_path(path):
		return false
	var lowered := path.to_lower()
	return (
		lowered.ends_with(".gd")
		or lowered.ends_with(".cs")
		or lowered.ends_with(".tscn")
		or lowered.ends_with(".scn")
	)


func _valid_project_path(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("..")


func _serialize_variant(value, depth: int):
	if depth > 3:
		return "<max-depth>"
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(value)
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4:
			return [value.x, value.y, value.z, value.w]
		TYPE_VECTOR4I:
			return [value.x, value.y, value.z, value.w]
		TYPE_RECT2:
			return [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_ARRAY:
			var output: Array = []
			for index in range(mini(value.size(), 100)):
				output.append(_serialize_variant(value[index], depth + 1))
			return output
		TYPE_DICTIONARY:
			var output := {}
			var count := 0
			for key_variant in value.keys():
				if count >= 100:
					break
				output[String(key_variant)] = _serialize_variant(value[key_variant], depth + 1)
				count += 1
			return output
		TYPE_OBJECT:
			if value is InputEvent:
				return _input_event_to_dict(value)
			if value is Resource:
				return {
					"type": value.get_class(),
					"path": value.resource_path,
					"name": value.resource_name,
				}
			return str(value)
		_:
			return str(value)


func _failure(message: String) -> Dictionary:
	return {"__nexora_error": message}
