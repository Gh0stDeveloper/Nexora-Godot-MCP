@tool
extends RefCounted

var _plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func execute(operation: String, params: Dictionary) -> Dictionary:
	match operation:
		"navigation.region_create":
			return _navigation_region_create(params)
		"navigation.agent_create":
			return _navigation_agent_create(params)
		"navigation.link_create":
			return _navigation_link_create(params)
		"navigation.inspect":
			return _navigation_inspect(params)
		"animation.player_create":
			return _animation_player_create(params)
		"animation.create":
			return _animation_create(params)
		"animation.inspect":
			return _animation_inspect(params)
		"animation.track_add":
			return _animation_track_add(params)
		"animation.key_insert":
			return _animation_key_insert(params)
		"animation_tree.create":
			return _animation_tree_create(params)
		"animation_tree.state_add":
			return _animation_tree_state_add(params)
		"animation_tree.transition_add":
			return _animation_tree_transition_add(params)
		"animation_tree.inspect":
			return _animation_tree_inspect(params)
		_:
			return {"__nexora_unhandled": true}


func _navigation_region_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var dimension := String(params.get("dimension", "3d")).to_lower()
	var name := String(params.get("name", "NavigationRegion")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid navigation region name")

	var node: Node
	if dimension == "2d":
		var region := NavigationRegion2D.new()
		region.name = name
		region.enabled = bool(params.get("enabled", true))
		region.navigation_layers = maxi(0, int(params.get("navigation_layers", 1)))
		region.enter_cost = maxf(0.0, float(params.get("enter_cost", 0.0)))
		region.travel_cost = maxf(0.0, float(params.get("travel_cost", 1.0)))
		var polygon_path := String(params.get("map_resource_path", ""))
		if not polygon_path.is_empty():
			var loaded := _load_navigation_resource(polygon_path, "NavigationPolygon")
			if loaded.has("__nexora_error"):
				region.free()
				return loaded
			region.navigation_polygon = loaded["resource"]
		else:
			region.navigation_polygon = NavigationPolygon.new()
		node = region
	elif dimension == "3d":
		var region := NavigationRegion3D.new()
		region.name = name
		region.enabled = bool(params.get("enabled", true))
		region.navigation_layers = maxi(0, int(params.get("navigation_layers", 1)))
		region.enter_cost = maxf(0.0, float(params.get("enter_cost", 0.0)))
		region.travel_cost = maxf(0.0, float(params.get("travel_cost", 1.0)))
		var mesh_path := String(params.get("map_resource_path", ""))
		if not mesh_path.is_empty():
			var loaded := _load_navigation_resource(mesh_path, "NavigationMesh")
			if loaded.has("__nexora_error"):
				region.free()
				return loaded
			region.navigation_mesh = loaded["resource"]
		else:
			region.navigation_mesh = NavigationMesh.new()
		var transform_result := _apply_node3d_transform(region, params)
		if transform_result.has("__nexora_error"):
			region.free()
			return transform_result
		node = region
	else:
		return _failure("dimension must be 2d or 3d")

	_commit_add_node(root, parent, node, "Nexora: Create NavigationRegion")
	return {
		"path": str(root.get_path_to(node)),
		"type": node.get_class(),
		"dimension": dimension,
		"undoable": true,
	}


func _navigation_agent_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var dimension := String(params.get("dimension", "3d")).to_lower()
	var name := String(params.get("name", "NavigationAgent")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid navigation agent name")
	var node: Node

	if dimension == "2d":
		var agent := NavigationAgent2D.new()
		agent.name = name
		agent.navigation_layers = maxi(0, int(params.get("navigation_layers", 1)))
		agent.path_desired_distance = maxf(0.0, float(params.get("path_desired_distance", 20.0)))
		agent.target_desired_distance = maxf(0.0, float(params.get("target_desired_distance", 20.0)))
		agent.radius = maxf(0.0, float(params.get("radius", 10.0)))
		agent.max_speed = maxf(0.0, float(params.get("max_speed", 100.0)))
		agent.avoidance_enabled = bool(params.get("avoidance_enabled", false))
		var target := _vector2_optional(params.get("target_position"))
		if target.has("__nexora_error"):
			agent.free()
			return target
		if target.has("value"):
			agent.target_position = target["value"]
		node = agent
	elif dimension == "3d":
		var agent := NavigationAgent3D.new()
		agent.name = name
		agent.navigation_layers = maxi(0, int(params.get("navigation_layers", 1)))
		agent.path_desired_distance = maxf(0.0, float(params.get("path_desired_distance", 1.0)))
		agent.target_desired_distance = maxf(0.0, float(params.get("target_desired_distance", 1.0)))
		agent.radius = maxf(0.0, float(params.get("radius", 0.5)))
		agent.height = maxf(0.0, float(params.get("height", 1.0)))
		agent.max_speed = maxf(0.0, float(params.get("max_speed", 10.0)))
		agent.avoidance_enabled = bool(params.get("avoidance_enabled", false))
		var target := _vector3_optional(params.get("target_position"))
		if target.has("__nexora_error"):
			agent.free()
			return target
		if target.has("value"):
			agent.target_position = target["value"]
		node = agent
	else:
		return _failure("dimension must be 2d or 3d")

	_commit_add_node(root, parent, node, "Nexora: Create NavigationAgent")
	return {
		"path": str(root.get_path_to(node)),
		"type": node.get_class(),
		"dimension": dimension,
		"avoidance_enabled": bool(node.get("avoidance_enabled")),
		"undoable": true,
	}


func _navigation_link_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var dimension := String(params.get("dimension", "3d")).to_lower()
	var name := String(params.get("name", "NavigationLink")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid navigation link name")
	var node: Node

	if dimension == "2d":
		var link := NavigationLink2D.new()
		link.name = name
		link.enabled = bool(params.get("enabled", true))
		link.bidirectional = bool(params.get("bidirectional", true))
		link.navigation_layers = maxi(0, int(params.get("navigation_layers", 1)))
		link.enter_cost = maxf(0.0, float(params.get("enter_cost", 0.0)))
		link.travel_cost = maxf(0.0, float(params.get("travel_cost", 1.0)))
		var start_result := _vector2_required(params.get("start_position"), "start_position")
		if start_result.has("__nexora_error"):
			link.free()
			return start_result
		var end_result := _vector2_required(params.get("end_position"), "end_position")
		if end_result.has("__nexora_error"):
			link.free()
			return end_result
		link.start_position = start_result["value"]
		link.end_position = end_result["value"]
		node = link
	elif dimension == "3d":
		var link := NavigationLink3D.new()
		link.name = name
		link.enabled = bool(params.get("enabled", true))
		link.bidirectional = bool(params.get("bidirectional", true))
		link.navigation_layers = maxi(0, int(params.get("navigation_layers", 1)))
		link.enter_cost = maxf(0.0, float(params.get("enter_cost", 0.0)))
		link.travel_cost = maxf(0.0, float(params.get("travel_cost", 1.0)))
		var start_result := _vector3_required(params.get("start_position"), "start_position")
		if start_result.has("__nexora_error"):
			link.free()
			return start_result
		var end_result := _vector3_required(params.get("end_position"), "end_position")
		if end_result.has("__nexora_error"):
			link.free()
			return end_result
		link.start_position = start_result["value"]
		link.end_position = end_result["value"]
		node = link
	else:
		return _failure("dimension must be 2d or 3d")

	_commit_add_node(root, parent, node, "Nexora: Create NavigationLink")
	return {
		"path": str(root.get_path_to(node)),
		"type": node.get_class(),
		"dimension": dimension,
		"bidirectional": bool(node.get("bidirectional")),
		"undoable": true,
	}


func _navigation_inspect(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var node := _find_node(root, String(params.get("node_path", "")))
	if node == null:
		return _failure("node not found")

	if node is NavigationRegion3D:
		return {
			"path": str(root.get_path_to(node)),
			"type": node.get_class(),
			"enabled": node.enabled,
			"navigation_layers": node.navigation_layers,
			"enter_cost": node.enter_cost,
			"travel_cost": node.travel_cost,
			"has_navigation_mesh": node.navigation_mesh != null,
		}
	if node is NavigationRegion2D:
		return {
			"path": str(root.get_path_to(node)),
			"type": node.get_class(),
			"enabled": node.enabled,
			"navigation_layers": node.navigation_layers,
			"enter_cost": node.enter_cost,
			"travel_cost": node.travel_cost,
			"has_navigation_polygon": node.navigation_polygon != null,
		}
	if node is NavigationAgent3D or node is NavigationAgent2D:
		return {
			"path": str(root.get_path_to(node)),
			"type": node.get_class(),
			"navigation_layers": node.navigation_layers,
			"path_desired_distance": node.path_desired_distance,
			"target_desired_distance": node.target_desired_distance,
			"radius": node.radius,
			"max_speed": node.max_speed,
			"avoidance_enabled": node.avoidance_enabled,
		}
	if node is NavigationLink3D or node is NavigationLink2D:
		return {
			"path": str(root.get_path_to(node)),
			"type": node.get_class(),
			"enabled": node.enabled,
			"bidirectional": node.bidirectional,
			"navigation_layers": node.navigation_layers,
			"enter_cost": node.enter_cost,
			"travel_cost": node.travel_cost,
		}
	return _failure("node is not a supported navigation node")


func _animation_player_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")
	var name := String(params.get("name", "AnimationPlayer")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid AnimationPlayer name")

	var player := AnimationPlayer.new()
	player.name = name
	_commit_add_node(root, parent, player, "Nexora: Create AnimationPlayer")
	return {
		"path": str(root.get_path_to(player)),
		"undoable": true,
	}


func _animation_create(params: Dictionary) -> Dictionary:
	var found := _animation_context(params)
	if found.has("__nexora_error"):
		return found
	var root: Node = found["root"]
	var player: AnimationPlayer = found["player"]
	var library_name := String(params.get("library", ""))
	var animation_name := String(params.get("animation", "")).strip_edges()
	if animation_name.is_empty():
		return _failure("animation name cannot be empty")

	var library := player.get_animation_library(library_name)
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true
	if library.has_animation(animation_name):
		return _failure("animation already exists")

	var animation := Animation.new()
	animation.length = maxf(0.001, float(params.get("length", 1.0)))
	var loop_mode := String(params.get("loop_mode", "none")).to_lower()
	match loop_mode:
		"none":
			animation.loop_mode = Animation.LOOP_NONE
		"linear":
			animation.loop_mode = Animation.LOOP_LINEAR
		"pingpong":
			animation.loop_mode = Animation.LOOP_PINGPONG
		_:
			return _failure("loop_mode must be none, linear or pingpong")

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Create Animation", UndoRedo.MERGE_DISABLE, root)
	if created_library:
		undo_redo.add_do_method(player, "add_animation_library", StringName(library_name), library)
		undo_redo.add_undo_method(player, "remove_animation_library", StringName(library_name))
	undo_redo.add_do_method(library, "add_animation", StringName(animation_name), animation)
	undo_redo.add_undo_method(library, "remove_animation", StringName(animation_name))
	undo_redo.add_do_reference(animation)
	if created_library:
		undo_redo.add_do_reference(library)
	undo_redo.commit_action()

	return {
		"player_path": str(root.get_path_to(player)),
		"library": library_name,
		"animation": animation_name,
		"length": animation.length,
		"loop_mode": loop_mode,
		"undoable": true,
	}


func _animation_inspect(params: Dictionary) -> Dictionary:
	var found := _animation_context(params)
	if found.has("__nexora_error"):
		return found
	var root: Node = found["root"]
	var player: AnimationPlayer = found["player"]
	var libraries: Array[Dictionary] = []
	for library_name_variant in player.get_animation_library_list():
		var library_name := String(library_name_variant)
		var library := player.get_animation_library(library_name)
		var animations: Array[Dictionary] = []
		if library != null:
			for animation_name_variant in library.get_animation_list():
				var animation_name := String(animation_name_variant)
				var animation := library.get_animation(animation_name)
				animations.append({
					"name": animation_name,
					"length": animation.length,
					"loop_mode": animation.loop_mode,
					"track_count": animation.get_track_count(),
				})
		libraries.append({
			"name": library_name,
			"animations": animations,
		})
	return {
		"player_path": "." if player == root else str(root.get_path_to(player)),
		"autoplay": String(player.autoplay),
		"libraries": libraries,
	}


func _animation_track_add(params: Dictionary) -> Dictionary:
	var animation_result := _get_animation(params)
	if animation_result.has("__nexora_error"):
		return animation_result
	var root: Node = animation_result["root"]
	var animation: Animation = animation_result["animation"]
	var track_type_name := String(params.get("track_type", "value")).to_lower()
	var track_type := _track_type_from_name(track_type_name)
	if track_type < 0:
		return _failure("unsupported track_type")
	var path := String(params.get("path", "")).strip_edges()
	if path.is_empty():
		return _failure("track path cannot be empty")

	var index := animation.get_track_count()
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Add Animation Track", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_animation_track_add_do", animation, track_type, NodePath(path), index)
	undo_redo.add_undo_method(animation, "remove_track", index)
	undo_redo.commit_action()

	return {
		"track_index": index,
		"track_type": track_type_name,
		"path": path,
		"undoable": true,
	}


func _animation_key_insert(params: Dictionary) -> Dictionary:
	var animation_result := _get_animation(params)
	if animation_result.has("__nexora_error"):
		return animation_result
	var root: Node = animation_result["root"]
	var animation: Animation = animation_result["animation"]
	var track_index := int(params.get("track_index", -1))
	if track_index < 0 or track_index >= animation.get_track_count():
		return _failure("track_index is out of range")
	var time := float(params.get("time", 0.0))
	if time < 0.0:
		return _failure("key time cannot be negative")
	var transition := maxf(0.001, float(params.get("transition", 1.0)))
	var converted := _animation_key_value(animation.track_get_type(track_index), params.get("value"))
	if converted.has("__nexora_error"):
		return converted

	var previous_index := animation.track_find_key(track_index, time, Animation.FIND_MODE_EXACT)
	var had_previous := previous_index >= 0
	var previous_value = null
	var previous_transition := 1.0
	if had_previous:
		previous_value = animation.track_get_key_value(track_index, previous_index)
		previous_transition = animation.track_get_key_transition(track_index, previous_index)

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Insert Animation Key", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(animation, "track_insert_key", track_index, time, converted["value"], transition)
	if had_previous:
		undo_redo.add_undo_method(animation, "track_insert_key", track_index, time, previous_value, previous_transition)
	else:
		undo_redo.add_undo_method(self, "_remove_animation_key_at_time", animation, track_index, time)
	undo_redo.commit_action()

	return {
		"track_index": track_index,
		"time": time,
		"key_count": animation.track_get_key_count(track_index),
		"replaced_existing": had_previous,
		"undoable": true,
	}


func _animation_tree_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")
	var player := _find_node(root, String(params.get("animation_player_path", "")))
	if not player is AnimationPlayer:
		return _failure("animation_player_path must reference AnimationPlayer")

	var name := String(params.get("name", "AnimationTree")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid AnimationTree name")

	var tree := AnimationTree.new()
	tree.name = name
	tree.tree_root = AnimationNodeStateMachine.new()
	var requested_active := bool(params.get("active", true))

	_commit_add_node(root, parent, tree, "Nexora: Create AnimationTree")
	tree.anim_player = tree.get_path_to(player)
	tree.active = requested_active
	return {
		"path": str(root.get_path_to(tree)),
		"animation_player_path": String(tree.anim_player),
		"active": tree.active,
		"undoable": true,
	}


func _animation_tree_state_add(params: Dictionary) -> Dictionary:
	var found := _state_machine_context(params)
	if found.has("__nexora_error"):
		return found
	var root: Node = found["root"]
	var tree: AnimationTree = found["tree"]
	var machine: AnimationNodeStateMachine = found["machine"]
	var state_name := String(params.get("state_name", "")).strip_edges()
	if state_name.is_empty():
		return _failure("state_name cannot be empty")
	if machine.has_node(state_name):
		return _failure("state already exists")

	var animation_name := String(params.get("animation", "")).strip_edges()
	if animation_name.is_empty():
		return _failure("animation cannot be empty")
	var position_result := _vector2_optional(params.get("position"))
	if position_result.has("__nexora_error"):
		return position_result
	var position: Vector2 = position_result.get("value", Vector2.ZERO)

	var node := AnimationNodeAnimation.new()
	node.animation = StringName(animation_name)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Add AnimationTree State", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(machine, "add_node", StringName(state_name), node, position)
	undo_redo.add_undo_method(machine, "remove_node", StringName(state_name))
	undo_redo.add_do_reference(node)
	undo_redo.commit_action()

	return {
		"tree_path": str(root.get_path_to(tree)),
		"state": state_name,
		"animation": animation_name,
		"position": [position.x, position.y],
		"undoable": true,
	}


func _animation_tree_transition_add(params: Dictionary) -> Dictionary:
	var found := _state_machine_context(params)
	if found.has("__nexora_error"):
		return found
	var root: Node = found["root"]
	var tree: AnimationTree = found["tree"]
	var machine: AnimationNodeStateMachine = found["machine"]
	var from_state := String(params.get("from_state", "")).strip_edges()
	var to_state := String(params.get("to_state", "")).strip_edges()
	if not machine.has_node(from_state) or not machine.has_node(to_state):
		return _failure("from_state and to_state must already exist")
	if machine.has_transition(from_state, to_state):
		return _failure("transition already exists")

	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = maxf(0.0, float(params.get("xfade_time", 0.0)))
	var switch_mode := String(params.get("switch_mode", "immediate")).to_lower()
	match switch_mode:
		"immediate":
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		"sync":
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
		"at_end":
			transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		_:
			return _failure("switch_mode must be immediate, sync or at_end")

	var advance_mode := String(params.get("advance_mode", "disabled")).to_lower()
	match advance_mode:
		"disabled":
			transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		"enabled":
			transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		"auto":
			transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		_:
			return _failure("advance_mode must be disabled, enabled or auto")

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Add AnimationTree Transition", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(machine, "add_transition", StringName(from_state), StringName(to_state), transition)
	undo_redo.add_undo_method(machine, "remove_transition", StringName(from_state), StringName(to_state))
	undo_redo.add_do_reference(transition)
	undo_redo.commit_action()

	return {
		"tree_path": str(root.get_path_to(tree)),
		"from_state": from_state,
		"to_state": to_state,
		"xfade_time": transition.xfade_time,
		"switch_mode": switch_mode,
		"advance_mode": advance_mode,
		"undoable": true,
	}


func _animation_tree_inspect(params: Dictionary) -> Dictionary:
	var found := _state_machine_context(params)
	if found.has("__nexora_error"):
		return found
	var root: Node = found["root"]
	var tree: AnimationTree = found["tree"]
	var machine: AnimationNodeStateMachine = found["machine"]
	var states: Array[Dictionary] = []
	for state_variant in machine.get_node_list():
		var state_name := String(state_variant)
		var state_node := machine.get_node(state_name)
		var position := machine.get_node_position(state_name)
		states.append({
			"name": state_name,
			"type": state_node.get_class() if state_node else "",
			"position": [position.x, position.y],
			"animation": String(state_node.animation) if state_node is AnimationNodeAnimation else "",
		})

	var transitions: Array[Dictionary] = []
	for index in range(machine.get_transition_count()):
		var transition := machine.get_transition(index)
		transitions.append({
			"from": String(machine.get_transition_from(index)),
			"to": String(machine.get_transition_to(index)),
			"xfade_time": transition.xfade_time,
			"switch_mode": transition.switch_mode,
			"advance_mode": transition.advance_mode,
		})

	return {
		"tree_path": str(root.get_path_to(tree)),
		"active": tree.active,
		"states": states,
		"transitions": transitions,
	}


func _animation_context(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var player := _find_node(root, String(params.get("player_path", "")))
	if not player is AnimationPlayer:
		return _failure("player_path must reference AnimationPlayer")
	return {"root": root, "player": player}


func _get_animation(params: Dictionary) -> Dictionary:
	var found := _animation_context(params)
	if found.has("__nexora_error"):
		return found
	var player: AnimationPlayer = found["player"]
	var library_name := String(params.get("library", ""))
	var animation_name := String(params.get("animation", "")).strip_edges()
	if animation_name.is_empty():
		return _failure("animation cannot be empty")
	var library := player.get_animation_library(library_name)
	if library == null:
		return _failure("animation library not found")
	var animation := library.get_animation(animation_name)
	if animation == null:
		return _failure("animation not found")
	found["library"] = library
	found["animation"] = animation
	return found


func _state_machine_context(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var tree := _find_node(root, String(params.get("tree_path", "")))
	if not tree is AnimationTree:
		return _failure("tree_path must reference AnimationTree")
	if not tree.tree_root is AnimationNodeStateMachine:
		return _failure("AnimationTree root is not AnimationNodeStateMachine")
	return {
		"root": root,
		"tree": tree,
		"machine": tree.tree_root,
	}


func _track_type_from_name(name: String) -> int:
	match name:
		"value":
			return Animation.TYPE_VALUE
		"position_3d":
			return Animation.TYPE_POSITION_3D
		"rotation_3d":
			return Animation.TYPE_ROTATION_3D
		"scale_3d":
			return Animation.TYPE_SCALE_3D
		"blend_shape":
			return Animation.TYPE_BLEND_SHAPE
		"method":
			return Animation.TYPE_METHOD
		"bezier":
			return Animation.TYPE_BEZIER
		"audio":
			return Animation.TYPE_AUDIO
		"animation":
			return Animation.TYPE_ANIMATION
		_:
			return -1


func _animation_key_value(track_type: int, raw) -> Dictionary:
	match track_type:
		Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D:
			var result := _vector3_required(raw, "animation key")
			return result
		Animation.TYPE_ROTATION_3D:
			if typeof(raw) == TYPE_ARRAY and raw.size() == 4:
				return {
					"value": Quaternion(
						float(raw[0]),
						float(raw[1]),
						float(raw[2]),
						float(raw[3])
					).normalized()
				}
			if typeof(raw) == TYPE_ARRAY and raw.size() == 3:
				var euler := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
				return {"value": Quaternion.from_euler(euler)}
			return _failure("rotation_3d key must use [x,y,z] Euler radians or [x,y,z,w] quaternion")
		Animation.TYPE_METHOD:
			if typeof(raw) != TYPE_DICTIONARY:
				return _failure("method key value must be {method, args}")
			return {"value": raw}
		_:
			return {"value": raw}


func _animation_track_add_do(
	animation: Animation,
	track_type: int,
	path: NodePath,
	expected_index: int
) -> void:
	var index := animation.add_track(track_type, expected_index)
	animation.track_set_path(index, path)


func _remove_animation_key_at_time(animation: Animation, track_index: int, time: float) -> void:
	var key_index := animation.track_find_key(track_index, time, Animation.FIND_MODE_EXACT)
	if key_index >= 0:
		animation.track_remove_key(track_index, key_index)


func _load_navigation_resource(path: String, expected_type: String) -> Dictionary:
	if not _valid_project_path(path) or not FileAccess.file_exists(path):
		return _failure("map_resource_path must be an existing project-local resource")
	var loaded := ResourceLoader.load(path, expected_type)
	if loaded == null or not loaded.is_class(expected_type):
		return _failure("navigation resource is not %s" % expected_type)
	return {"resource": loaded}


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
		var scale_value: Vector3 = scale_result["value"]
		if absf(scale_value.x) < 0.00000001 or absf(scale_value.y) < 0.00000001 or absf(scale_value.z) < 0.00000001:
			return _failure("scale components cannot be zero")
		node.scale = scale_value
	return {}


func _vector2_optional(raw) -> Dictionary:
	if raw == null:
		return {}
	if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
		return _failure("expected exactly 2 numeric values")
	return {"value": Vector2(float(raw[0]), float(raw[1]))}


func _vector2_required(raw, label: String) -> Dictionary:
	var result := _vector2_optional(raw)
	if result.has("__nexora_error"):
		return result
	if not result.has("value"):
		return _failure("%s is required" % label)
	return result


func _vector3_optional(raw) -> Dictionary:
	if raw == null:
		return {}
	if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
		return _failure("expected exactly 3 numeric values")
	return {"value": Vector3(float(raw[0]), float(raw[1]), float(raw[2]))}


func _vector3_required(raw, label: String) -> Dictionary:
	var result := _vector3_optional(raw)
	if result.has("__nexora_error"):
		return result
	if not result.has("value"):
		return _failure("%s is required" % label)
	return result


func _valid_project_path(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("..")


func _valid_node_name(value: String) -> bool:
	var name := value.strip_edges()
	return not name.is_empty() and not name.contains("/")


func _failure(message: String) -> Dictionary:
	return {"__nexora_error": message}
