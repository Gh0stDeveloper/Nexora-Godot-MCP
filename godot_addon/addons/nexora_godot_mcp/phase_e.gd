@tool
extends RefCounted

var _plugin: EditorPlugin

const _BODY_TYPES := {
	"StaticBody3D": true,
	"CharacterBody3D": true,
	"RigidBody3D": true,
	"Area3D": true,
}

const _LIGHT_TYPES := {
	"DirectionalLight3D": true,
	"OmniLight3D": true,
	"SpotLight3D": true,
}


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func execute(operation: String, params: Dictionary) -> Dictionary:
	match operation:
		"mesh3d.create":
			return _mesh3d_create(params)
		"camera3d.create":
			return _camera3d_create(params)
		"light3d.create":
			return _light3d_create(params)
		"world_environment.create":
			return _world_environment_create(params)
		"collision3d.shape_create":
			return _collision3d_shape_create(params)
		"collision3d.body_create":
			return _collision3d_body_create(params)
		"skeleton3d.inspect":
			return _skeleton3d_inspect(params)
		_:
			return {"__nexora_unhandled": true}


func _mesh3d_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var name := String(params.get("name", "")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid MeshInstance3D name")

	var mesh_result := _mesh_from_params(params)
	if mesh_result.has("__nexora_error"):
		return mesh_result

	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh_result.get("mesh")
	var transform_result := _apply_node3d_transform(node, params)
	if transform_result.has("__nexora_error"):
		node.free()
		return transform_result

	_commit_add_node(root, parent, node, "Nexora: Create MeshInstance3D")
	return {
		"path": str(root.get_path_to(node)),
		"name": node.name,
		"mesh_type": node.mesh.get_class() if node.mesh else "",
		"undoable": true,
	}


func _camera3d_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var name := String(params.get("name", "")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid Camera3D name")

	var node := Camera3D.new()
	node.name = name
	node.fov = clampf(float(params.get("fov", 75.0)), 1.0, 179.0)
	node.near = maxf(0.001, float(params.get("near", 0.05)))
	node.far = maxf(node.near + 0.001, float(params.get("far", 4000.0)))
	var transform_result := _apply_node3d_transform(node, params)
	if transform_result.has("__nexora_error"):
		node.free()
		return transform_result

	_commit_add_node(root, parent, node, "Nexora: Create Camera3D")
	if bool(params.get("current", false)):
		node.make_current()

	return {
		"path": str(root.get_path_to(node)),
		"fov": node.fov,
		"near": node.near,
		"far": node.far,
		"current": node.is_current(),
		"undoable": true,
	}


func _light3d_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var light_type := String(params.get("light_type", "DirectionalLight3D"))
	if not _LIGHT_TYPES.has(light_type):
		return _failure("light_type must be DirectionalLight3D, OmniLight3D or SpotLight3D")
	var instance = ClassDB.instantiate(light_type)
	if not instance is Light3D:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("could not instantiate light type")
	var node: Light3D = instance
	node.name = String(params.get("name", "Light3D")).strip_edges()
	if not _valid_node_name(String(node.name)):
		node.free()
		return _failure("invalid Light3D name")

	node.light_energy = maxf(0.0, float(params.get("energy", 1.0)))
	node.shadow_enabled = bool(params.get("shadow_enabled", false))
	var color_result := _color_from_optional(params.get("color"))
	if color_result.has("__nexora_error"):
		node.free()
		return color_result
	if color_result.has("value"):
		node.light_color = color_result["value"]

	if node is OmniLight3D:
		node.omni_range = maxf(0.01, float(params.get("range", 5.0)))
	elif node is SpotLight3D:
		node.spot_range = maxf(0.01, float(params.get("range", 5.0)))
		node.spot_angle = clampf(float(params.get("spot_angle", 45.0)), 0.01, 89.9)

	var transform_result := _apply_node3d_transform(node, params)
	if transform_result.has("__nexora_error"):
		node.free()
		return transform_result

	_commit_add_node(root, parent, node, "Nexora: Create Light3D")
	return {
		"path": str(root.get_path_to(node)),
		"type": node.get_class(),
		"energy": node.light_energy,
		"shadow_enabled": node.shadow_enabled,
		"undoable": true,
	}


func _world_environment_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var node := WorldEnvironment.new()
	node.name = String(params.get("name", "WorldEnvironment")).strip_edges()
	if not _valid_node_name(String(node.name)):
		node.free()
		return _failure("invalid WorldEnvironment name")

	var environment := Environment.new()
	var background_mode := String(params.get("background_mode", "color")).to_lower()
	match background_mode:
		"clear_color":
			environment.background_mode = Environment.BG_CLEAR_COLOR
		"color":
			environment.background_mode = Environment.BG_COLOR
		"sky":
			environment.background_mode = Environment.BG_SKY
		"canvas":
			environment.background_mode = Environment.BG_CANVAS
		"keep":
			environment.background_mode = Environment.BG_KEEP
		_:
			node.free()
			return _failure("background_mode must be clear_color, color, sky, canvas or keep")

	var bg_result := _color_from_optional(params.get("background_color"))
	if bg_result.has("__nexora_error"):
		node.free()
		return bg_result
	if bg_result.has("value"):
		environment.background_color = bg_result["value"]

	var ambient_result := _color_from_optional(params.get("ambient_light_color"))
	if ambient_result.has("__nexora_error"):
		node.free()
		return ambient_result
	if ambient_result.has("value"):
		environment.ambient_light_color = ambient_result["value"]
	environment.ambient_light_energy = maxf(0.0, float(params.get("ambient_light_energy", 1.0)))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	node.environment = environment

	_commit_add_node(root, parent, node, "Nexora: Create WorldEnvironment")
	return {
		"path": str(root.get_path_to(node)),
		"background_mode": background_mode,
		"ambient_light_energy": environment.ambient_light_energy,
		"undoable": true,
	}


func _collision3d_shape_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null or not parent is CollisionObject3D:
		return _failure("parent_path must reference CollisionObject3D")

	var shape_result := _shape3d_from_dict(params.get("shape", {}))
	if shape_result.has("__nexora_error"):
		return shape_result

	var node := CollisionShape3D.new()
	node.name = String(params.get("name", "CollisionShape3D")).strip_edges()
	if not _valid_node_name(String(node.name)):
		node.free()
		return _failure("invalid CollisionShape3D name")
	node.shape = shape_result["shape"]
	node.disabled = bool(params.get("disabled", false))

	var transform_result := _apply_node3d_transform(node, params)
	if transform_result.has("__nexora_error"):
		node.free()
		return transform_result

	_commit_add_node(root, parent, node, "Nexora: Create CollisionShape3D")
	return {
		"path": str(root.get_path_to(node)),
		"shape_type": node.shape.get_class() if node.shape else "",
		"undoable": true,
	}


func _collision3d_body_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var body_type := String(params.get("body_type", "StaticBody3D"))
	if not _BODY_TYPES.has(body_type):
		return _failure("body_type must be StaticBody3D, CharacterBody3D, RigidBody3D or Area3D")

	var instance = ClassDB.instantiate(body_type)
	if not instance is CollisionObject3D:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("could not instantiate CollisionObject3D")
	var body: CollisionObject3D = instance
	body.name = String(params.get("name", body_type)).strip_edges()
	if not _valid_node_name(String(body.name)):
		body.free()
		return _failure("invalid body name")
	body.collision_layer = maxi(0, int(params.get("collision_layer", 1)))
	body.collision_mask = maxi(0, int(params.get("collision_mask", 1)))

	var transform_result := _apply_node3d_transform(body, params)
	if transform_result.has("__nexora_error"):
		body.free()
		return transform_result

	if body is Area3D:
		body.monitoring = bool(params.get("monitoring", true))
		body.monitorable = bool(params.get("monitorable", true))

	var shape_result := _shape3d_from_dict(params.get("shape", {}))
	if shape_result.has("__nexora_error"):
		body.free()
		return shape_result
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape_result["shape"]
	body.add_child(collision)
	collision.owner = body

	_commit_add_node(root, parent, body, "Nexora: Create CollisionObject3D")
	collision.owner = root

	return {
		"path": str(root.get_path_to(body)),
		"type": body.get_class(),
		"shape_type": collision.shape.get_class() if collision.shape else "",
		"collision_layer": body.collision_layer,
		"collision_mask": body.collision_mask,
		"undoable": true,
	}


func _skeleton3d_inspect(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var node := _find_node(root, String(params.get("node_path", "")))
	if not node is Skeleton3D:
		return _failure("node_path must reference Skeleton3D")

	var max_bones := clampi(int(params.get("max_bones", 256)), 1, 1024)
	var bones: Array[Dictionary] = []
	var count := node.get_bone_count()
	for index in range(mini(count, max_bones)):
		var rest := node.get_bone_rest(index)
		var pose := node.get_bone_pose(index)
		bones.append({
			"index": index,
			"name": String(node.get_bone_name(index)),
			"parent": node.get_bone_parent(index),
			"enabled": node.is_bone_enabled(index),
			"rest": _transform3d_dict(rest),
			"pose": _transform3d_dict(pose),
		})

	return {
		"path": "." if node == root else str(root.get_path_to(node)),
		"bone_count": count,
		"bones": bones,
		"truncated": count > max_bones,
	}


func _mesh_from_params(params: Dictionary) -> Dictionary:
	var resource_path := String(params.get("mesh_path", ""))
	if not resource_path.is_empty():
		if not _valid_project_path(resource_path) or not FileAccess.file_exists(resource_path):
			return _failure("mesh_path must be an existing project-local resource")
		var loaded := ResourceLoader.load(resource_path, "Mesh")
		if not loaded is Mesh:
			return _failure("mesh_path could not be loaded as Mesh")
		return {"mesh": loaded}

	var primitive := String(params.get("primitive", "box")).to_lower()
	match primitive:
		"box":
			var mesh := BoxMesh.new()
			var size_result := _vector3_optional(params.get("size"))
			if size_result.has("__nexora_error"):
				return size_result
			mesh.size = size_result.get("value", Vector3(1, 1, 1))
			return {"mesh": mesh}
		"sphere":
			var mesh := SphereMesh.new()
			mesh.radius = maxf(0.001, float(params.get("radius", 0.5)))
			mesh.height = maxf(mesh.radius * 2.0, float(params.get("height", 1.0)))
			return {"mesh": mesh}
		"capsule":
			var mesh := CapsuleMesh.new()
			mesh.radius = maxf(0.001, float(params.get("radius", 0.5)))
			mesh.height = maxf(mesh.radius * 2.0, float(params.get("height", 2.0)))
			return {"mesh": mesh}
		"cylinder":
			var mesh := CylinderMesh.new()
			mesh.top_radius = maxf(0.0, float(params.get("top_radius", 0.5)))
			mesh.bottom_radius = maxf(0.0, float(params.get("bottom_radius", 0.5)))
			mesh.height = maxf(0.001, float(params.get("height", 1.0)))
			return {"mesh": mesh}
		"plane":
			var mesh := PlaneMesh.new()
			var size_result := _vector2_optional(params.get("size2d"))
			if size_result.has("__nexora_error"):
				return size_result
			mesh.size = size_result.get("value", Vector2(2, 2))
			return {"mesh": mesh}
		"quad":
			var mesh := QuadMesh.new()
			var size_result := _vector2_optional(params.get("size2d"))
			if size_result.has("__nexora_error"):
				return size_result
			mesh.size = size_result.get("value", Vector2(1, 1))
			return {"mesh": mesh}
		_:
			return _failure("primitive must be box, sphere, capsule, cylinder, plane or quad")


func _shape3d_from_dict(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("shape must be an object")
	var data: Dictionary = raw
	var kind := String(data.get("type", "")).to_lower()
	match kind:
		"box":
			var shape := BoxShape3D.new()
			var size_result := _vector3_optional(data.get("size"))
			if size_result.has("__nexora_error"):
				return size_result
			shape.size = size_result.get("value", Vector3(1, 1, 1))
			if shape.size.x <= 0.0 or shape.size.y <= 0.0 or shape.size.z <= 0.0:
				return _failure("box size components must be positive")
			return {"shape": shape}
		"sphere":
			var shape := SphereShape3D.new()
			shape.radius = maxf(0.001, float(data.get("radius", 0.5)))
			return {"shape": shape}
		"capsule":
			var shape := CapsuleShape3D.new()
			shape.radius = maxf(0.001, float(data.get("radius", 0.5)))
			shape.height = maxf(shape.radius * 2.0, float(data.get("height", 2.0)))
			return {"shape": shape}
		"cylinder":
			var shape := CylinderShape3D.new()
			shape.radius = maxf(0.001, float(data.get("radius", 0.5)))
			shape.height = maxf(0.001, float(data.get("height", 1.0)))
			return {"shape": shape}
		"world_boundary":
			var shape := WorldBoundaryShape3D.new()
			var normal_result := _vector3_optional(data.get("normal"))
			if normal_result.has("__nexora_error"):
				return normal_result
			shape.normal = normal_result.get("value", Vector3(0, 1, 0)).normalized()
			shape.distance = float(data.get("distance", 0.0))
			return {"shape": shape}
		"convex_polygon":
			var raw_points = data.get("points", [])
			if typeof(raw_points) != TYPE_ARRAY or raw_points.size() < 4 or raw_points.size() > 256:
				return _failure("convex_polygon requires between 4 and 256 points")
			var points := PackedVector3Array()
			for point_variant in raw_points:
				var point_result := _vector3_optional(point_variant)
				if point_result.has("__nexora_error") or not point_result.has("value"):
					return _failure("invalid convex polygon point")
				points.append(point_result["value"])
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			return {"shape": shape}
		_:
			return _failure("shape.type must be box, sphere, capsule, cylinder, world_boundary or convex_polygon")


func _scene_context() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	return {"root": root}


func _find_node(root: Node, path: String) -> Node:
	if path.is_empty() or path == "." or path == "/":
		return root
	return root.get_node_or_null(NodePath(path))


func _commit_add_node(root: Node, parent: Node, node: Node, action_name: String) -> void:
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_undo_add_node", parent, node, root)
	undo_redo.add_undo_method(self, "_undo_remove_node", parent, node)
	undo_redo.add_do_reference(node)
	undo_redo.commit_action()


func _undo_add_node(parent: Node, node: Node, owner: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	parent.add_child(node, true)
	node.owner = owner
	for child in node.get_children():
		if child.owner == node or child.owner == null:
			child.owner = owner


func _undo_remove_node(parent: Node, node: Node) -> void:
	if node.get_parent() == parent:
		parent.remove_child(node)


func _apply_node3d_transform(node: Node3D, params: Dictionary) -> Dictionary:
	var position_result := _vector3_optional(params.get("position"))
	if position_result.has("__nexora_error"):
		return position_result
	var rotation_result := _vector3_optional(params.get("rotation"))
	if rotation_result.has("__nexora_error"):
		return rotation_result
	var scale_result := _vector3_optional(params.get("scale"))
	if scale_result.has("__nexora_error"):
		return scale_result

	if position_result.has("value"):
		node.position = position_result["value"]
	if rotation_result.has("value"):
		node.rotation = rotation_result["value"]
	if scale_result.has("value"):
		var value: Vector3 = scale_result["value"]
		if absf(value.x) < 0.00000001 or absf(value.y) < 0.00000001 or absf(value.z) < 0.00000001:
			return _failure("scale components cannot be zero")
		var all_positive := value.x > 0 and value.y > 0 and value.z > 0
		var all_negative := value.x < 0 and value.y < 0 and value.z < 0
		if not (all_positive or all_negative):
			return _failure("Node3D scale components must use the same sign")
		node.scale = value
	return {}


func _vector2_optional(raw) -> Dictionary:
	if raw == null:
		return {}
	if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
		return _failure("expected exactly 2 numeric values")
	return {"value": Vector2(float(raw[0]), float(raw[1]))}


func _vector3_optional(raw) -> Dictionary:
	if raw == null:
		return {}
	if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
		return _failure("expected exactly 3 numeric values")
	return {"value": Vector3(float(raw[0]), float(raw[1]), float(raw[2]))}


func _color_from_optional(raw) -> Dictionary:
	if raw == null:
		return {}
	if typeof(raw) != TYPE_ARRAY or raw.size() < 3 or raw.size() > 4:
		return _failure("color must use [r,g,b] or [r,g,b,a]")
	return {
		"value": Color(
			float(raw[0]),
			float(raw[1]),
			float(raw[2]),
			float(raw[3]) if raw.size() > 3 else 1.0
		)
	}


func _valid_project_path(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("..")


func _valid_node_name(value: String) -> bool:
	var name := value.strip_edges()
	return not name.is_empty() and not name.contains("/")


func _transform3d_dict(value: Transform3D) -> Dictionary:
	return {
		"origin": [value.origin.x, value.origin.y, value.origin.z],
		"basis": [
			[value.basis.x.x, value.basis.x.y, value.basis.x.z],
			[value.basis.y.x, value.basis.y.y, value.basis.y.z],
			[value.basis.z.x, value.basis.z.y, value.basis.z.z],
		],
	}


func _failure(message: String) -> Dictionary:
	return {"__nexora_error": message}
