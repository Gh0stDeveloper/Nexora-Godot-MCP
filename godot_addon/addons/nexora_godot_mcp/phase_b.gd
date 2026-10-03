@tool
extends RefCounted

var _plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func execute(operation: String, params: Dictionary) -> Dictionary:
	match operation:
		"scene.open_scenes":
			return _scene_open_scenes()
		"scene.reload":
			return _scene_reload(bool(params.get("confirm_discard", false)))
		"scene.close":
			return _scene_close(bool(params.get("confirm_discard", false)))
		"scene.create":
			return _scene_create(params)
		"scene.duplicate":
			return _scene_duplicate(params)
		"scene.instantiate":
			return _scene_instantiate(params)
		"scene.dependencies":
			return _scene_dependencies(String(params.get("path", "")))
		"node.create":
			return _node_create(params)
		"node.set_properties":
			return _node_set_properties(params)
		"node.delete":
			return _node_delete(String(params.get("node_path", "")))
		"node.rename":
			return _node_rename(params)
		"node.reparent":
			return _node_reparent(params)
		"node.transform_2d":
			return _node_transform_2d(params)
		"node.transform_3d":
			return _node_transform_3d(params)
		"node.repair_owner":
			return _node_repair_owner(params)
		"resource.inspect":
			return _resource_inspect(params)
		"filesystem.status":
			return _filesystem_status()
		"filesystem.scan":
			return _filesystem_scan()
		"filesystem.reimport":
			return _filesystem_reimport(params)
		_:
			return {"__nexora_unhandled": true}


func _scene_open_scenes() -> Dictionary:
	var open_scenes: Array[String] = []
	for path in EditorInterface.get_open_scenes():
		open_scenes.append(String(path))
	var unsaved_scenes: Array[String] = []
	for path in EditorInterface.get_unsaved_scenes():
		unsaved_scenes.append(String(path))
	var root := EditorInterface.get_edited_scene_root()
	return {
		"open_scenes": open_scenes,
		"unsaved_scenes": unsaved_scenes,
		"active_scene": root.scene_file_path if root else "",
		"active_scene_name": root.name if root else "",
	}


func _scene_reload(confirm_discard: bool) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var path := root.scene_file_path
	if path.is_empty():
		return _failure("active scene has never been saved")
	if _active_scene_is_unsaved(root) and not confirm_discard:
		return _failure("active scene has unsaved changes; confirm_discard=true is required")
	EditorInterface.reload_scene_from_path(path)
	return {"path": path, "reloaded": true}


func _scene_close(confirm_discard: bool) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var path := root.scene_file_path
	if _active_scene_is_unsaved(root) and not confirm_discard:
		return _failure("active scene has unsaved changes; confirm_discard=true is required")
	var error := EditorInterface.close_scene()
	if error != OK:
		return _failure("close_scene failed with error %d" % error)
	return {"path": path, "closed": true}


func _scene_create(params: Dictionary) -> Dictionary:
	var root_type := String(params.get("root_type", ""))
	var root_name := String(params.get("name", ""))
	var path := String(params.get("path", ""))
	var open_after_create := bool(params.get("open_after_create", true))
	var overwrite := bool(params.get("overwrite", false))

	if not _valid_resource_path(path, [".tscn"]):
		return _failure("scene path must be a project-local .tscn resource")
	if root_type.is_empty() or root_name.is_empty():
		return _failure("root_type and name are required")
	if not _valid_node_name(root_name):
		return _failure("invalid scene root name")
	if not ClassDB.class_exists(root_type):
		return _failure("unknown Godot class: %s" % root_type)

	var open_scenes := EditorInterface.get_open_scenes()
	if FileAccess.file_exists(path):
		if not overwrite:
			return _failure("destination scene already exists; overwrite=true is required")
		if path in open_scenes:
			return _failure("refusing to overwrite a scene that is currently open in the editor")

	var instance = ClassDB.instantiate(root_type)
	if not instance is Node:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("%s is not a Node-derived class" % root_type)

	var root: Node = instance
	root.name = root_name
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		return _failure("PackedScene.pack failed with error %d" % pack_error)

	var save_error := ResourceSaver.save(packed, path)
	root.free()
	if save_error != OK:
		return _failure("ResourceSaver.save failed with error %d" % save_error)

	EditorInterface.get_resource_filesystem().update_file(path)
	if open_after_create:
		EditorInterface.open_scene_from_path(path)

	return {
		"path": path,
		"root": root_name,
		"type": root_type,
		"created": true,
		"opened": open_after_create,
	}


func _scene_duplicate(params: Dictionary) -> Dictionary:
	var source_path := String(params.get("source_path", ""))
	var destination_path := String(params.get("destination_path", ""))
	var overwrite := bool(params.get("overwrite", false))

	if not _valid_resource_path(source_path, [".tscn", ".scn"]):
		return _failure("source_path must be a project-local .tscn or .scn scene")
	if not _valid_resource_path(destination_path, [".tscn", ".scn"]):
		return _failure("destination_path must be a project-local .tscn or .scn scene")
	if source_path == destination_path:
		return _failure("source and destination must be different")
	if not ResourceLoader.exists(source_path, "PackedScene"):
		return _failure("source scene does not exist or is not importable")
	if FileAccess.file_exists(destination_path) and not overwrite:
		return _failure("destination scene already exists; overwrite=true is required")

	var loaded := ResourceLoader.load(
		source_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if not loaded is PackedScene:
		return _failure("source resource is not a PackedScene")

	var error := ResourceSaver.save(loaded, destination_path)
	if error != OK:
		return _failure("ResourceSaver.save failed with error %d" % error)

	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.update_file(destination_path)
	return {
		"source_path": source_path,
		"destination_path": destination_path,
		"duplicated": true,
	}


func _scene_instantiate(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")

	var scene_path := String(params.get("scene_path", ""))
	var parent_path := String(params.get("parent_path", "."))
	var requested_name := String(params.get("name", ""))
	if not _valid_resource_path(scene_path, [".tscn", ".scn"]):
		return _failure("scene_path must be a project-local .tscn or .scn scene")

	var parent := _find_node(root, parent_path)
	if parent == null:
		return _failure("parent node not found")

	var loaded := ResourceLoader.load(scene_path, "PackedScene")
	if not loaded is PackedScene:
		return _failure("scene resource could not be loaded as PackedScene")

	var instance: Node = loaded.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if not requested_name.is_empty():
		if not _valid_node_name(requested_name):
			instance.free()
			return _failure("invalid node name")
		instance.name = requested_name

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Instantiate Scene", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_undo_add_node", parent, instance, root, -1)
	undo_redo.add_undo_method(self, "_undo_remove_node", parent, instance)
	undo_redo.add_do_reference(instance)
	undo_redo.commit_action()

	return {
		"scene_path": scene_path,
		"path": str(root.get_path_to(instance)),
		"name": instance.name,
		"type": instance.get_class(),
		"undoable": true,
	}


func _scene_dependencies(path: String) -> Dictionary:
	if not _valid_resource_path(path, [".tscn", ".scn"]):
		return _failure("path must be a project-local .tscn or .scn scene")
	if not ResourceLoader.exists(path, "PackedScene"):
		return _failure("scene does not exist or is not importable")

	var dependencies: Array[Dictionary] = []
	for raw_variant in ResourceLoader.get_dependencies(path):
		var raw := String(raw_variant)
		var item := {"raw": raw, "uid": "", "path": raw}
		if raw.contains("::"):
			item["uid"] = raw.get_slice("::", 0)
			item["path"] = raw.get_slice("::", 2)
		dependencies.append(item)
	return {"path": path, "dependencies": dependencies, "count": dependencies.size()}


func _node_create(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var node_type := String(params.get("node_type", ""))
	var node_name := String(params.get("name", ""))
	if node_type.is_empty() or not _valid_node_name(node_name):
		return _failure("valid node_type and name are required")
	if not ClassDB.class_exists(node_type):
		return _failure("unknown Godot class: %s" % node_type)

	var instance = ClassDB.instantiate(node_type)
	if not instance is Node:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("%s is not a Node-derived class" % node_type)

	var node: Node = instance
	node.name = node_name
	var prepared := _prepare_property_changes(node, params.get("properties", {}))
	if prepared.has("__nexora_error"):
		node.free()
		return prepared
	for key_variant in prepared.get("changes", {}).keys():
		var change: Dictionary = prepared["changes"][key_variant]
		node.set(StringName(String(key_variant)), change.get("new"))

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Create Node", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_undo_add_node", parent, node, root, -1)
	undo_redo.add_undo_method(self, "_undo_remove_node", parent, node)
	undo_redo.add_do_reference(node)
	undo_redo.commit_action()

	return {
		"path": str(root.get_path_to(node)),
		"name": node.name,
		"type": node.get_class(),
		"properties_changed": prepared.get("names", []),
		"undoable": true,
	}


func _node_set_properties(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	if node == null:
		return _failure("node not found")

	var prepared := _prepare_property_changes(node, params.get("properties", {}))
	if prepared.has("__nexora_error"):
		return prepared
	var changes: Dictionary = prepared.get("changes", {})
	if changes.is_empty():
		return _failure("properties cannot be empty")

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Set Node Properties", UndoRedo.MERGE_DISABLE, root)
	for key_variant in changes.keys():
		var key := String(key_variant)
		var change: Dictionary = changes[key_variant]
		undo_redo.add_do_property(node, StringName(key), change.get("new"))
		undo_redo.add_undo_property(node, StringName(key), change.get("old"))
	undo_redo.commit_action()

	return {
		"node": node.name,
		"path": "." if node == root else str(root.get_path_to(node)),
		"changed": prepared.get("names", []),
		"undoable": true,
	}


func _node_delete(node_path: String) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, node_path)
	if node == null:
		return _failure("node not found")
	if node == root:
		return _failure("deleting the scene root is not allowed")
	var parent := node.get_parent()
	if parent == null:
		return _failure("node has no parent")
	var old_index := node.get_index()
	var old_owner = node.owner
	var deleted_path := str(root.get_path_to(node))

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Delete Node", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_undo_remove_node", parent, node)
	undo_redo.add_undo_method(self, "_undo_add_node", parent, node, old_owner, old_index)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()

	return {"deleted": true, "path": deleted_path, "undoable": true}


func _node_rename(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	if node == null:
		return _failure("node not found")
	var new_name := String(params.get("new_name", ""))
	if not _valid_node_name(new_name):
		return _failure("invalid node name")
	var old_name := String(node.name)
	if old_name == new_name:
		return {"path": "." if node == root else str(root.get_path_to(node)), "renamed": false}

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Rename Node", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_property(node, &"name", StringName(new_name))
	undo_redo.add_undo_property(node, &"name", StringName(old_name))
	undo_redo.commit_action()

	return {
		"old_name": old_name,
		"new_name": String(node.name),
		"path": "." if node == root else str(root.get_path_to(node)),
		"undoable": true,
	}


func _node_reparent(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	var new_parent := _find_node(root, String(params.get("new_parent_path", "")))
	if node == null or new_parent == null:
		return _failure("node or new parent not found")
	if node == root:
		return _failure("the scene root cannot be reparented")
	if node == new_parent or node.is_ancestor_of(new_parent):
		return _failure("reparent would create a node cycle")

	var old_parent := node.get_parent()
	if old_parent == null:
		return _failure("node has no current parent")
	var old_index := node.get_index()
	var old_owner = node.owner
	var new_index := int(params.get("new_index", -1))
	if new_index < -1:
		return _failure("new_index must be -1 or greater")

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Reparent Node", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(
		self,
		"_undo_reparent_node",
		node,
		new_parent,
		new_index,
		root
	)
	undo_redo.add_undo_method(
		self,
		"_undo_reparent_node",
		node,
		old_parent,
		old_index,
		old_owner
	)
	undo_redo.commit_action()

	return {
		"path": str(root.get_path_to(node)),
		"parent_path": "." if new_parent == root else str(root.get_path_to(new_parent)),
		"index": node.get_index(),
		"global_transform_preserved": node is Node2D or node is Node3D or node is Control,
		"undoable": true,
	}


func _node_transform_2d(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	if not node is Node2D:
		return _failure("node is not Node2D")
	var node_2d: Node2D = node
	var space := String(params.get("space", "local"))
	if space != "local" and space != "global":
		return _failure("space must be local or global")

	var properties: Dictionary = {}
	if params.get("position") != null:
		var raw_position = params.get("position")
		if typeof(raw_position) != TYPE_ARRAY or raw_position.size() != 2:
			return _failure("position must contain 2 numbers")
		properties["global_position" if space == "global" else "position"] = Vector2(
			float(raw_position[0]),
			float(raw_position[1])
		)
	if params.get("rotation") != null:
		properties["global_rotation" if space == "global" else "rotation"] = float(params.get("rotation"))
	if params.get("scale") != null:
		var raw_scale = params.get("scale")
		if typeof(raw_scale) != TYPE_ARRAY or raw_scale.size() != 2:
			return _failure("scale must contain 2 numbers")
		properties["global_scale" if space == "global" else "scale"] = Vector2(
			float(raw_scale[0]),
			float(raw_scale[1])
		)
	if params.get("skew") != null:
		properties["global_skew" if space == "global" else "skew"] = float(params.get("skew"))
	if properties.is_empty():
		return _failure("at least one transform component is required")

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Transform Node2D", UndoRedo.MERGE_DISABLE, root)
	for property_name_variant in properties.keys():
		var property_name := String(property_name_variant)
		undo_redo.add_do_property(
			node_2d,
			StringName(property_name),
			properties[property_name_variant]
		)
		undo_redo.add_undo_property(
			node_2d,
			StringName(property_name),
			node_2d.get(property_name)
		)
	undo_redo.commit_action()

	return {
		"path": "." if node_2d == root else str(root.get_path_to(node_2d)),
		"space": space,
		"position": _vec2_array(node_2d.global_position if space == "global" else node_2d.position),
		"rotation": node_2d.global_rotation if space == "global" else node_2d.rotation,
		"scale": _vec2_array(node_2d.global_scale if space == "global" else node_2d.scale),
		"skew": node_2d.global_skew if space == "global" else node_2d.skew,
		"undoable": true,
	}


func _node_transform_3d(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var node := _find_node(root, String(params.get("node_path", "")))
	if not node is Node3D:
		return _failure("node is not Node3D")
	var node_3d: Node3D = node
	var space := String(params.get("space", "local"))
	if space != "local" and space != "global":
		return _failure("space must be local or global")

	var raw_position = params.get("position")
	var raw_rotation = params.get("rotation")
	var raw_scale = params.get("scale")
	if raw_position == null and raw_rotation == null and raw_scale == null:
		return _failure("at least one transform component is required")

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Transform Node3D", UndoRedo.MERGE_DISABLE, root)

	if space == "local":
		if raw_position != null:
			var position_result := _vector3_from_array(raw_position, "position")
			if position_result.has("__nexora_error"):
				return position_result
			undo_redo.add_do_property(node_3d, &"position", position_result["value"])
			undo_redo.add_undo_property(node_3d, &"position", node_3d.position)
		if raw_rotation != null:
			var rotation_result := _vector3_from_array(raw_rotation, "rotation")
			if rotation_result.has("__nexora_error"):
				return rotation_result
			undo_redo.add_do_property(node_3d, &"rotation", rotation_result["value"])
			undo_redo.add_undo_property(node_3d, &"rotation", node_3d.rotation)
		if raw_scale != null:
			var scale_result := _vector3_from_array(raw_scale, "scale")
			if scale_result.has("__nexora_error"):
				return scale_result
			var scale_value: Vector3 = scale_result["value"]
			if not _valid_scale3(scale_value):
				return _failure("Node3D scale components must be non-zero and share the same sign")
			undo_redo.add_do_property(node_3d, &"scale", scale_value)
			undo_redo.add_undo_property(node_3d, &"scale", node_3d.scale)
	else:
		var old_transform := node_3d.global_transform
		var next_position := old_transform.origin
		var next_rotation := node_3d.global_rotation
		var next_scale := old_transform.basis.get_scale()

		if raw_position != null:
			var global_position_result := _vector3_from_array(raw_position, "position")
			if global_position_result.has("__nexora_error"):
				return global_position_result
			next_position = global_position_result["value"]
		if raw_rotation != null:
			var global_rotation_result := _vector3_from_array(raw_rotation, "rotation")
			if global_rotation_result.has("__nexora_error"):
				return global_rotation_result
			next_rotation = global_rotation_result["value"]
		if raw_scale != null:
			var global_scale_result := _vector3_from_array(raw_scale, "scale")
			if global_scale_result.has("__nexora_error"):
				return global_scale_result
			next_scale = global_scale_result["value"]
			if not _valid_scale3(next_scale):
				return _failure("Node3D scale components must be non-zero and share the same sign")

		var next_basis := Basis.from_euler(next_rotation).scaled(next_scale)
		var next_transform := Transform3D(next_basis, next_position)
		undo_redo.add_do_property(node_3d, &"global_transform", next_transform)
		undo_redo.add_undo_property(node_3d, &"global_transform", old_transform)

	undo_redo.commit_action()

	var transform := node_3d.global_transform if space == "global" else node_3d.transform
	var rotation_value := node_3d.global_rotation if space == "global" else node_3d.rotation
	return {
		"path": "." if node_3d == root else str(root.get_path_to(node_3d)),
		"space": space,
		"position": _vec3_array(transform.origin),
		"rotation": _vec3_array(rotation_value),
		"scale": _vec3_array(transform.basis.get_scale()),
		"undoable": true,
	}


func _node_repair_owner(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	var target := _find_node(root, String(params.get("node_path", ".")))
	if target == null:
		return _failure("node not found")
	var recursive := bool(params.get("recursive", true))
	var only_missing := bool(params.get("only_missing", true))

	var candidates: Array[Node] = []
	_collect_owner_candidates(target, recursive, candidates)
	var changes: Array[Dictionary] = []
	for node in candidates:
		if node == root:
			continue
		if only_missing and node.owner != null:
			continue
		changes.append({
			"node": node,
			"path": str(root.get_path_to(node)),
			"old_owner": node.owner,
		})

	if changes.is_empty():
		return {"changed": [], "count": 0, "undoable": true}

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Repair Node Owners", UndoRedo.MERGE_DISABLE, root)
	for change in changes:
		var change_node: Node = change["node"]
		undo_redo.add_do_method(change_node, "set_owner", root)
		undo_redo.add_undo_method(change_node, "set_owner", change.get("old_owner"))
	undo_redo.commit_action()

	var changed_paths: Array[String] = []
	for change in changes:
		changed_paths.append(String(change["path"]))
	return {
		"changed": changed_paths,
		"count": changed_paths.size(),
		"owner": root.name,
		"undoable": true,
	}


func _resource_inspect(params: Dictionary) -> Dictionary:
	var path := String(params.get("path", ""))
	var max_properties := clampi(int(params.get("max_properties", 100)), 1, 500)
	if not _valid_any_resource_path(path):
		return _failure("resource path must be project-local")
	if not ResourceLoader.exists(path):
		return _failure("resource does not exist or is not imported")

	var resource := ResourceLoader.load(path)
	if resource == null:
		return _failure("resource could not be loaded")

	var properties: Array[Dictionary] = []
	for item_variant in resource.get_property_list():
		if properties.size() >= max_properties:
			break
		var item: Dictionary = item_variant
		var usage := int(item.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var key := String(item.get("name", ""))
		if key.is_empty():
			continue
		properties.append({
			"name": key,
			"type": int(item.get("type", TYPE_NIL)),
			"class_name": String(item.get("class_name", "")),
			"value": _serialize_variant(resource.get(key), 0),
		})

	var dependencies: Array[String] = []
	for dependency in ResourceLoader.get_dependencies(path):
		dependencies.append(String(dependency))

	return {
		"path": path,
		"type": resource.get_class(),
		"resource_name": resource.resource_name,
		"uid": ResourceLoader.get_resource_uid(path),
		"cached": ResourceLoader.has_cached(path),
		"properties": properties,
		"property_count": properties.size(),
		"properties_truncated": properties.size() >= max_properties,
		"dependencies": dependencies,
	}


func _filesystem_status() -> Dictionary:
	var filesystem := EditorInterface.get_resource_filesystem()
	return {
		"is_scanning": filesystem.is_scanning(),
		"scanning_progress": filesystem.get_scanning_progress(),
		"is_importing": filesystem.is_importing(),
	}


func _filesystem_scan() -> Dictionary:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.is_importing():
		return _failure("cannot start a filesystem scan while resources are importing")
	if filesystem.is_scanning():
		return {
			"started": false,
			"already_scanning": true,
			"scanning_progress": filesystem.get_scanning_progress(),
		}
	filesystem.scan()
	return {
		"started": true,
		"is_scanning": filesystem.is_scanning(),
		"scanning_progress": filesystem.get_scanning_progress(),
	}


func _filesystem_reimport(params: Dictionary) -> Dictionary:
	var raw_paths = params.get("paths", [])
	if typeof(raw_paths) != TYPE_ARRAY:
		return _failure("paths must be an array")
	if raw_paths.is_empty() or raw_paths.size() > 100:
		return _failure("reimport requires between 1 and 100 paths")

	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.is_importing() or filesystem.is_scanning():
		return _failure("filesystem is busy importing or scanning")

	var paths := PackedStringArray()
	for path_variant in raw_paths:
		var path := String(path_variant)
		if not _valid_any_resource_path(path):
			return _failure("invalid project-local path: %s" % path)
		if not FileAccess.file_exists(path):
			return _failure("file does not exist: %s" % path)
		paths.append(path)

	filesystem.reimport_files(paths)
	return {
		"reimported": Array(paths),
		"count": paths.size(),
		"is_importing": filesystem.is_importing(),
	}


func _active_scene_is_unsaved(root: Node) -> bool:
	if root.scene_file_path.is_empty():
		return true
	for path_variant in EditorInterface.get_unsaved_scenes():
		if String(path_variant) == root.scene_file_path:
			return true
	return false


func _prepare_property_changes(node: Node, raw_properties) -> Dictionary:
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
	for item_variant in node.get_property_list():
		var item: Dictionary = item_variant
		known[String(item.get("name", ""))] = true

	var changes := {}
	var names: Array[String] = []
	for key_variant in properties.keys():
		var key := String(key_variant)
		if denied.has(key):
			return _failure("property is not writable through node.set_properties: %s" % key)
		if not known.has(key):
			return _failure("unknown property for %s: %s" % [node.get_class(), key])
		var current = node.get(key)
		var coerced = _coerce_value(current, properties[key_variant])
		changes[key] = {"old": current, "new": coerced}
		names.append(key)

	return {"changes": changes, "names": names}


func _undo_add_node(parent: Node, node: Node, owner, index: int) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	parent.add_child(node, true)
	if index >= 0 and parent.get_child_count() > 0:
		parent.move_child(node, mini(index, parent.get_child_count() - 1))
	node.owner = owner


func _undo_remove_node(parent: Node, node: Node) -> void:
	if node.get_parent() == parent:
		parent.remove_child(node)


func _undo_reparent_node(node: Node, parent: Node, index: int, owner) -> void:
	node.reparent(parent, true)
	if index >= 0 and parent.get_child_count() > 0:
		parent.move_child(node, mini(index, parent.get_child_count() - 1))
	node.owner = owner


func _collect_owner_candidates(node: Node, recursive: bool, output: Array[Node]) -> void:
	output.append(node)
	if not recursive:
		return
	for child in node.get_children():
		_collect_owner_candidates(child, true, output)


func _find_node(root: Node, path: String) -> Node:
	if path.is_empty() or path == "." or path == "/":
		return root
	return root.get_node_or_null(NodePath(path))


func _valid_node_name(value: String) -> bool:
	var name := value.strip_edges()
	return not name.is_empty() and not name.contains("/")


func _valid_any_resource_path(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("..")


func _valid_resource_path(path: String, extensions: Array[String]) -> bool:
	if not _valid_any_resource_path(path):
		return false
	var lowered := path.to_lower()
	for extension in extensions:
		if lowered.ends_with(extension):
			return true
	return false


func _vector3_from_array(raw, label: String) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
		return _failure("%s must contain 3 numbers" % label)
	return {
		"value": Vector3(float(raw[0]), float(raw[1]), float(raw[2])),
	}


func _valid_scale3(value: Vector3) -> bool:
	if absf(value.x) < 0.00000001 or absf(value.y) < 0.00000001 or absf(value.z) < 0.00000001:
		return false
	var all_positive := value.x > 0.0 and value.y > 0.0 and value.z > 0.0
	var all_negative := value.x < 0.0 and value.y < 0.0 and value.z < 0.0
	return all_positive or all_negative


func _vec2_array(value: Vector2) -> Array[float]:
	return [value.x, value.y]


func _vec3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _serialize_variant(value, depth: int):
	if depth > 2:
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
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_ARRAY:
			var output: Array = []
			for index in range(mini(value.size(), 50)):
				output.append(_serialize_variant(value[index], depth + 1))
			return output
		TYPE_DICTIONARY:
			var output := {}
			var count := 0
			for key_variant in value.keys():
				if count >= 50:
					break
				output[String(key_variant)] = _serialize_variant(value[key_variant], depth + 1)
				count += 1
			return output
		TYPE_OBJECT:
			if value is Resource:
				return {
					"type": value.get_class(),
					"path": value.resource_path,
					"name": value.resource_name,
				}
			return str(value)
		_:
			return str(value)


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
		TYPE_NODE_PATH:
			return NodePath(String(incoming))
	return incoming


func _failure(message: String) -> Dictionary:
	return {"__nexora_error": message}
