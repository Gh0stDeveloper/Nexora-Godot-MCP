@tool
extends RefCounted

var _plugin: EditorPlugin

const _CONTAINER_TYPES := {
	"HBoxContainer": true,
	"VBoxContainer": true,
	"GridContainer": true,
	"MarginContainer": true,
	"CenterContainer": true,
	"PanelContainer": true,
	"ScrollContainer": true,
	"AspectRatioContainer": true,
	"HFlowContainer": true,
	"VFlowContainer": true,
}

const _TEXT_CONTROL_TYPES := {
	"Label": true,
	"Button": true,
	"CheckButton": true,
	"CheckBox": true,
	"LinkButton": true,
	"LineEdit": true,
	"TextEdit": true,
	"RichTextLabel": true,
}

const _COLLISION_BODY_TYPES := {
	"StaticBody2D": true,
	"CharacterBody2D": true,
	"RigidBody2D": true,
	"Area2D": true,
}


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func execute(operation: String, params: Dictionary) -> Dictionary:
	match operation:
		"ui.control_create":
			return _ui_control_create(params)
		"ui.container_create":
			return _ui_container_create(params)
		"ui.layout_set":
			return _ui_layout_set(params)
		"ui.theme_apply":
			return _ui_theme_apply(params)
		"ui.text_set":
			return _ui_text_set(params)
		"ui.hud_create":
			return _ui_hud_create(params)
		"ui.menu_create":
			return _ui_menu_create(params)
		"sprite2d.create":
			return _sprite2d_create(params)
		"animated_sprite2d.create":
			return _animated_sprite2d_create(params)
		"tilemap_layer.create":
			return _tilemap_layer_create(params)
		"tilemap.inspect":
			return _tilemap_inspect(params)
		"tilemap.set_cells":
			return _tilemap_set_cells(params)
		"camera2d.create":
			return _camera2d_create(params)
		"collision2d.shape_create":
			return _collision2d_shape_create(params)
		"collision2d.body_create":
			return _collision2d_body_create(params)
		_:
			return {"__nexora_unhandled": true}


func _ui_control_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var control_type := String(params.get("control_type", "Control"))
	var name := String(params.get("name", "")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid control name")
	if not ClassDB.class_exists(control_type) or not ClassDB.is_parent_class(control_type, "Control"):
		return _failure("control_type must be a Control-derived Godot class")

	var instance = ClassDB.instantiate(control_type)
	if not instance is Control:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("could not instantiate Control-derived class")
	var control: Control = instance
	control.name = name

	var text := String(params.get("text", ""))
	if not text.is_empty() and _has_property(control, "text"):
		control.set("text", text)

	var minimum_size_result := _vector2_from_optional(params.get("minimum_size"))
	if minimum_size_result.has("__nexora_error"):
		control.free()
		return minimum_size_result
	if minimum_size_result.has("value"):
		control.custom_minimum_size = minimum_size_result["value"]

	var properties_result := _apply_safe_properties(
		control,
		params.get("properties", {}),
		{"script": true, "owner": true, "theme": true}
	)
	if properties_result.has("__nexora_error"):
		control.free()
		return properties_result

	_commit_add_node(root, parent, control, "Nexora: Create UI Control")
	return {
		"path": str(root.get_path_to(control)),
		"name": control.name,
		"type": control.get_class(),
		"undoable": true,
	}


func _ui_container_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var container_type := String(params.get("container_type", "VBoxContainer"))
	var name := String(params.get("name", "")).strip_edges()
	if not _CONTAINER_TYPES.has(container_type):
		return _failure("unsupported container_type")
	if not _valid_node_name(name):
		return _failure("invalid container name")

	var instance = ClassDB.instantiate(container_type)
	if not instance is Container:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("container_type must instantiate a Container")
	var container: Container = instance
	container.name = name

	if container is GridContainer:
		var columns := int(params.get("columns", 1))
		if columns < 1 or columns > 64:
			container.free()
			return _failure("GridContainer columns must be between 1 and 64")
		container.columns = columns

	var minimum_size_result := _vector2_from_optional(params.get("minimum_size"))
	if minimum_size_result.has("__nexora_error"):
		container.free()
		return minimum_size_result
	if minimum_size_result.has("value"):
		container.custom_minimum_size = minimum_size_result["value"]

	var properties_result := _apply_safe_properties(
		container,
		params.get("properties", {}),
		{"script": true, "owner": true, "theme": true}
	)
	if properties_result.has("__nexora_error"):
		container.free()
		return properties_result

	_commit_add_node(root, parent, container, "Nexora: Create UI Container")
	return {
		"path": str(root.get_path_to(container)),
		"name": container.name,
		"type": container.get_class(),
		"undoable": true,
	}


func _ui_layout_set(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var node := _find_node(root, String(params.get("node_path", "")))
	if not node is Control:
		return _failure("node must be a Control")
	var control: Control = node

	var preset := String(params.get("preset", "")).strip_edges().to_lower()
	var margin := float(params.get("margin", 0.0))
	var size_result := _vector2_from_optional(params.get("size"))
	if size_result.has("__nexora_error"):
		return size_result
	var explicit_anchors = params.get("anchors")
	var explicit_offsets = params.get("offsets")

	var old_state := _control_layout_state(control)
	var next_state := old_state.duplicate(true)

	if not preset.is_empty():
		var preset_result := _layout_preset_state(control, preset, margin)
		if preset_result.has("__nexora_error"):
			return preset_result
		next_state = preset_result
	elif explicit_anchors != null or explicit_offsets != null:
		if explicit_anchors != null:
			var anchors_result := _quad_from_array(explicit_anchors, "anchors")
			if anchors_result.has("__nexora_error"):
				return anchors_result
			next_state["anchors"] = anchors_result["value"]
		if explicit_offsets != null:
			var offsets_result := _quad_from_array(explicit_offsets, "offsets")
			if offsets_result.has("__nexora_error"):
				return offsets_result
			next_state["offsets"] = offsets_result["value"]
	else:
		return _failure("preset or anchors/offsets are required")

	if size_result.has("value"):
		var requested_size: Vector2 = size_result["value"]
		var anchors: Array = next_state["anchors"]
		if (
			is_equal_approx(float(anchors[0]), float(anchors[2]))
			and is_equal_approx(float(anchors[1]), float(anchors[3]))
		):
			var offsets: Array = next_state["offsets"]
			offsets[2] = float(offsets[0]) + requested_size.x
			offsets[3] = float(offsets[1]) + requested_size.y
			next_state["offsets"] = offsets
		else:
			next_state["minimum_size"] = requested_size

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Set UI Layout", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_apply_control_layout_state", control, next_state)
	undo_redo.add_undo_method(self, "_apply_control_layout_state", control, old_state)
	undo_redo.commit_action()

	return {
		"path": "." if control == root else str(root.get_path_to(control)),
		"preset": preset,
		"anchors": next_state["anchors"],
		"offsets": next_state["offsets"],
		"undoable": true,
	}


func _ui_theme_apply(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var node := _find_node(root, String(params.get("node_path", "")))
	if not node is Control:
		return _failure("node must be a Control")
	var control: Control = node

	var theme_path := String(params.get("theme_path", ""))
	var next_theme = control.theme
	if not theme_path.is_empty():
		if not _valid_project_path(theme_path) or not FileAccess.file_exists(theme_path):
			return _failure("theme_path must be an existing project-local resource")
		var loaded := ResourceLoader.load(theme_path, "Theme")
		if not loaded is Theme:
			return _failure("theme_path could not be loaded as Theme")
		next_theme = loaded

	var type_variation := String(params.get("type_variation", ""))
	var colors_result := _validate_theme_override_map(params.get("colors", {}), "color")
	if colors_result.has("__nexora_error"):
		return colors_result
	var font_sizes_result := _validate_theme_override_map(params.get("font_sizes", {}), "int")
	if font_sizes_result.has("__nexora_error"):
		return font_sizes_result
	var constants_result := _validate_theme_override_map(params.get("constants", {}), "int")
	if constants_result.has("__nexora_error"):
		return constants_result

	var old_state := _capture_theme_state(
		control,
		colors_result.get("values", {}),
		font_sizes_result.get("values", {}),
		constants_result.get("values", {})
	)
	var new_state := {
		"theme": next_theme,
		"type_variation": type_variation if not type_variation.is_empty() else String(control.theme_type_variation),
		"colors": colors_result.get("values", {}),
		"font_sizes": font_sizes_result.get("values", {}),
		"constants": constants_result.get("values", {}),
	}

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Apply UI Theme", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_apply_theme_state", control, new_state)
	undo_redo.add_undo_method(self, "_restore_theme_state", control, old_state)
	undo_redo.commit_action()

	return {
		"path": "." if control == root else str(root.get_path_to(control)),
		"theme_path": next_theme.resource_path if next_theme is Theme else "",
		"type_variation": String(control.theme_type_variation),
		"color_overrides": colors_result.get("values", {}).keys(),
		"font_size_overrides": font_sizes_result.get("values", {}).keys(),
		"constant_overrides": constants_result.get("values", {}).keys(),
		"undoable": true,
	}


func _ui_text_set(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var node := _find_node(root, String(params.get("node_path", "")))
	if not node is Control:
		return _failure("node must be a Control")
	var control: Control = node
	if not _TEXT_CONTROL_TYPES.has(control.get_class()) and not _has_property(control, "text"):
		return _failure("control does not expose a supported text property")

	var text := String(params.get("text", ""))
	var old_text = control.get("text")
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Set UI Text", UndoRedo.MERGE_ENDS, root)
	undo_redo.add_do_property(control, &"text", text)
	undo_redo.add_undo_property(control, &"text", old_text)
	undo_redo.commit_action()

	return {
		"path": "." if control == root else str(root.get_path_to(control)),
		"text": text,
		"undoable": true,
	}


func _ui_hud_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var name := String(params.get("name", "HUD")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid HUD name")

	var layer := CanvasLayer.new()
	layer.name = name
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	layer.add_child(margin)

	var stack := VBoxContainer.new()
	stack.name = "Status"
	margin.add_child(stack)

	var title := Label.new()
	title.name = "Title"
	title.text = String(params.get("title", ""))
	stack.add_child(title)

	var health := Label.new()
	health.name = "Health"
	health.text = String(params.get("health_text", "Health: 100"))
	stack.add_child(health)

	var objective := Label.new()
	objective.name = "Objective"
	objective.text = String(params.get("objective_text", ""))
	stack.add_child(objective)

	_commit_add_node(root, parent, layer, "Nexora: Create HUD")
	return {
		"path": str(root.get_path_to(layer)),
		"title_path": str(root.get_path_to(title)),
		"health_path": str(root.get_path_to(health)),
		"objective_path": str(root.get_path_to(objective)),
		"undoable": true,
	}


func _ui_menu_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")

	var name := String(params.get("name", "Menu")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid menu name")
	var raw_buttons = params.get("buttons", [])
	if typeof(raw_buttons) != TYPE_ARRAY or raw_buttons.size() > 20:
		return _failure("buttons must be an array with at most 20 entries")

	var layer := CanvasLayer.new()
	layer.name = name

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var stack := VBoxContainer.new()
	stack.name = "Content"
	stack.custom_minimum_size = Vector2(280, 0)
	center.add_child(stack)

	var title := Label.new()
	title.name = "Title"
	title.text = String(params.get("title", "Menu"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	var button_paths: Array[String] = []
	for index in range(raw_buttons.size()):
		var item = raw_buttons[index]
		var button_text := ""
		var button_name := ""
		if typeof(item) == TYPE_STRING:
			button_text = String(item)
			button_name = _identifier_from_text(button_text, "Button%d" % (index + 1))
		elif typeof(item) == TYPE_DICTIONARY:
			button_text = String(item.get("text", ""))
			button_name = String(item.get("name", "")).strip_edges()
			if button_name.is_empty():
				button_name = _identifier_from_text(button_text, "Button%d" % (index + 1))
		else:
			layer.free()
			return _failure("each menu button must be a string or object")
		if button_text.is_empty() or not _valid_node_name(button_name):
			layer.free()
			return _failure("menu button text/name is invalid")
		var button := Button.new()
		button.name = button_name
		button.text = button_text
		stack.add_child(button)
		button_paths.append(button.name)

	_commit_add_node(root, parent, layer, "Nexora: Create Menu")
	var resolved_buttons: Array[String] = []
	for child in stack.get_children():
		if child is Button:
			resolved_buttons.append(str(root.get_path_to(child)))
	return {
		"path": str(root.get_path_to(layer)),
		"title_path": str(root.get_path_to(title)),
		"button_paths": resolved_buttons,
		"undoable": true,
	}


func _sprite2d_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")
	var name := String(params.get("name", "")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid Sprite2D name")

	var sprite := Sprite2D.new()
	sprite.name = name
	var texture_result := _load_texture(String(params.get("texture_path", "")))
	if texture_result.has("__nexora_error"):
		sprite.free()
		return texture_result
	if texture_result.has("texture"):
		sprite.texture = texture_result["texture"]

	var position_result := _vector2_from_optional(params.get("position"))
	if position_result.has("__nexora_error"):
		sprite.free()
		return position_result
	if position_result.has("value"):
		sprite.position = position_result["value"]

	sprite.centered = bool(params.get("centered", true))
	sprite.flip_h = bool(params.get("flip_h", false))
	sprite.flip_v = bool(params.get("flip_v", false))
	sprite.hframes = clampi(int(params.get("hframes", 1)), 1, 1024)
	sprite.vframes = clampi(int(params.get("vframes", 1)), 1, 1024)
	var max_frame := sprite.hframes * sprite.vframes - 1
	sprite.frame = clampi(int(params.get("frame", 0)), 0, maxi(max_frame, 0))

	_commit_add_node(root, parent, sprite, "Nexora: Create Sprite2D")
	return {
		"path": str(root.get_path_to(sprite)),
		"texture_path": sprite.texture.resource_path if sprite.texture else "",
		"hframes": sprite.hframes,
		"vframes": sprite.vframes,
		"frame": sprite.frame,
		"undoable": true,
	}


func _animated_sprite2d_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")
	var name := String(params.get("name", "")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid AnimatedSprite2D name")

	var raw_animations = params.get("animations", [])
	if typeof(raw_animations) != TYPE_ARRAY or raw_animations.is_empty() or raw_animations.size() > 32:
		return _failure("animations must contain between 1 and 32 entries")

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	var total_frames := 0
	var first_animation := ""
	for animation_variant in raw_animations:
		if typeof(animation_variant) != TYPE_DICTIONARY:
			return _failure("animation entries must be objects")
		var animation: Dictionary = animation_variant
		var animation_name := String(animation.get("name", "")).strip_edges()
		if animation_name.is_empty():
			return _failure("animation name cannot be empty")
		if frames.has_animation(StringName(animation_name)):
			return _failure("duplicate animation name: %s" % animation_name)

		var fps := float(animation.get("fps", 8.0))
		if fps <= 0.0 or fps > 240.0:
			return _failure("animation fps must be > 0 and <= 240")
		var raw_paths = animation.get("frames", [])
		if typeof(raw_paths) != TYPE_ARRAY or raw_paths.is_empty():
			return _failure("each animation requires at least one texture frame")
		total_frames += raw_paths.size()
		if total_frames > 256:
			return _failure("AnimatedSprite2D supports at most 256 frames per create call")

		frames.add_animation(StringName(animation_name))
		frames.set_animation_speed(StringName(animation_name), fps)
		frames.set_animation_loop(StringName(animation_name), bool(animation.get("loop", true)))
		for path_variant in raw_paths:
			var texture_result := _load_texture(String(path_variant))
			if texture_result.has("__nexora_error"):
				return texture_result
			if not texture_result.has("texture"):
				return _failure("animated frame texture path cannot be empty")
			frames.add_frame(StringName(animation_name), texture_result["texture"])
		if first_animation.is_empty():
			first_animation = animation_name

	var sprite := AnimatedSprite2D.new()
	sprite.name = name
	sprite.sprite_frames = frames
	sprite.animation = StringName(String(params.get("initial_animation", first_animation)))
	if not frames.has_animation(sprite.animation):
		sprite.free()
		return _failure("initial_animation does not exist in supplied animations")
	sprite.speed_scale = float(params.get("speed_scale", 1.0))
	sprite.flip_h = bool(params.get("flip_h", false))
	sprite.flip_v = bool(params.get("flip_v", false))

	var position_result := _vector2_from_optional(params.get("position"))
	if position_result.has("__nexora_error"):
		sprite.free()
		return position_result
	if position_result.has("value"):
		sprite.position = position_result["value"]

	_commit_add_node(root, parent, sprite, "Nexora: Create AnimatedSprite2D")
	if bool(params.get("autoplay", false)):
		sprite.play()
	return {
		"path": str(root.get_path_to(sprite)),
		"animations": Array(frames.get_animation_names()),
		"initial_animation": String(sprite.animation),
		"frame_count": total_frames,
		"autoplay": bool(params.get("autoplay", false)),
		"undoable": true,
	}


func _tilemap_layer_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")
	var name := String(params.get("name", "")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid TileMapLayer name")

	var layer := TileMapLayer.new()
	layer.name = name
	var tile_set_path := String(params.get("tile_set_path", ""))
	if not tile_set_path.is_empty():
		if not _valid_project_path(tile_set_path) or not FileAccess.file_exists(tile_set_path):
			layer.free()
			return _failure("tile_set_path must be an existing project-local TileSet resource")
		var loaded := ResourceLoader.load(tile_set_path, "TileSet")
		if not loaded is TileSet:
			layer.free()
			return _failure("tile_set_path could not be loaded as TileSet")
		layer.tile_set = loaded
	elif bool(params.get("create_empty_tileset", true)):
		var tile_set := TileSet.new()
		var size_result := _vector2i_from_optional(params.get("tile_size"))
		if size_result.has("__nexora_error"):
			layer.free()
			return size_result
		if size_result.has("value"):
			var tile_size: Vector2i = size_result["value"]
			if tile_size.x <= 0 or tile_size.y <= 0:
				layer.free()
				return _failure("tile_size components must be positive")
			tile_set.tile_size = tile_size
		layer.tile_set = tile_set

	var position_result := _vector2_from_optional(params.get("position"))
	if position_result.has("__nexora_error"):
		layer.free()
		return position_result
	if position_result.has("value"):
		layer.position = position_result["value"]

	_commit_add_node(root, parent, layer, "Nexora: Create TileMapLayer")
	return {
		"path": str(root.get_path_to(layer)),
		"tile_set_path": layer.tile_set.resource_path if layer.tile_set else "",
		"tile_size": [
			layer.tile_set.tile_size.x,
			layer.tile_set.tile_size.y,
		] if layer.tile_set else null,
		"undoable": true,
	}


func _tilemap_inspect(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var node := _find_node(root, String(params.get("node_path", "")))
	if node == null:
		return _failure("tile map node not found")
	var max_cells := clampi(int(params.get("max_cells", 500)), 1, 2000)
	var layer_index := int(params.get("layer", 0))
	var used_cells: Array[Vector2i] = []
	var tile_set: TileSet

	if node is TileMapLayer:
		var tile_layer: TileMapLayer = node
		used_cells = tile_layer.get_used_cells()
		tile_set = tile_layer.tile_set
	elif node is TileMap:
		var legacy: TileMap = node
		if layer_index < 0 or layer_index >= legacy.get_layers_count():
			return _failure("TileMap layer index is out of range")
		used_cells = legacy.get_used_cells(layer_index)
		tile_set = legacy.tile_set
	else:
		return _failure("node must be TileMapLayer or legacy TileMap")

	var cells: Array[Dictionary] = []
	for coords in used_cells:
		if cells.size() >= max_cells:
			break
		cells.append(_tile_cell_to_dict(node, layer_index, coords))
	var used_rect = node.get_used_rect()
	return {
		"path": "." if node == root else str(root.get_path_to(node)),
		"type": node.get_class(),
		"layer": layer_index,
		"tile_set_path": tile_set.resource_path if tile_set else "",
		"used_rect": [
			used_rect.position.x,
			used_rect.position.y,
			used_rect.size.x,
			used_rect.size.y,
		],
		"used_cell_count": used_cells.size(),
		"cells": cells,
		"truncated": used_cells.size() > cells.size(),
	}


func _tilemap_set_cells(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var node := _find_node(root, String(params.get("node_path", "")))
	if not (node is TileMapLayer or node is TileMap):
		return _failure("node must be TileMapLayer or legacy TileMap")
	var layer_index := int(params.get("layer", 0))
	if node is TileMap and (layer_index < 0 or layer_index >= node.get_layers_count()):
		return _failure("TileMap layer index is out of range")

	var raw_cells = params.get("cells", [])
	if typeof(raw_cells) != TYPE_ARRAY or raw_cells.is_empty() or raw_cells.size() > 500:
		return _failure("cells must contain between 1 and 500 entries")

	var confirm_erase := bool(params.get("confirm_erase", false))
	var changes: Array[Dictionary] = []
	for cell_variant in raw_cells:
		if typeof(cell_variant) != TYPE_DICTIONARY:
			return _failure("each cell must be an object")
		var cell: Dictionary = cell_variant
		var coords_result := _vector2i_from_required(cell.get("coords"), "coords")
		if coords_result.has("__nexora_error"):
			return coords_result
		var coords: Vector2i = coords_result["value"]
		var source_id := int(cell.get("source_id", -1))
		if source_id < 0 and not confirm_erase:
			return _failure("confirm_erase=true is required when erasing TileMap cells")
		var atlas_coords := Vector2i(-1, -1)
		if cell.has("atlas_coords"):
			var atlas_result := _vector2i_from_required(cell.get("atlas_coords"), "atlas_coords")
			if atlas_result.has("__nexora_error"):
				return atlas_result
			atlas_coords = atlas_result["value"]
		var alternative_tile := int(cell.get("alternative_tile", 0))
		var old := _tile_cell_to_dict(node, layer_index, coords)
		changes.append({
			"coords": coords,
			"new_source_id": source_id,
			"new_atlas_coords": atlas_coords,
			"new_alternative_tile": alternative_tile,
			"old_source_id": int(old["source_id"]),
			"old_atlas_coords": Vector2i(
				int(old["atlas_coords"][0]),
				int(old["atlas_coords"][1])
			),
			"old_alternative_tile": int(old["alternative_tile"]),
		})

	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Nexora: Set TileMap Cells", UndoRedo.MERGE_DISABLE, root)
	for change in changes:
		undo_redo.add_do_method(
			self,
			"_set_tile_cell",
			node,
			layer_index,
			change["coords"],
			change["new_source_id"],
			change["new_atlas_coords"],
			change["new_alternative_tile"]
		)
		undo_redo.add_undo_method(
			self,
			"_set_tile_cell",
			node,
			layer_index,
			change["coords"],
			change["old_source_id"],
			change["old_atlas_coords"],
			change["old_alternative_tile"]
		)
	undo_redo.commit_action()

	return {
		"path": "." if node == root else str(root.get_path_to(node)),
		"layer": layer_index,
		"changed_cells": changes.size(),
		"undoable": true,
	}


func _camera2d_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")
	var name := String(params.get("name", "")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid Camera2D name")

	var camera := Camera2D.new()
	camera.name = name
	camera.enabled = bool(params.get("enabled", true))
	camera.position_smoothing_enabled = bool(params.get("position_smoothing_enabled", false))
	camera.position_smoothing_speed = maxf(0.0, float(params.get("position_smoothing_speed", 5.0)))

	var position_result := _vector2_from_optional(params.get("position"))
	if position_result.has("__nexora_error"):
		camera.free()
		return position_result
	if position_result.has("value"):
		camera.position = position_result["value"]

	var zoom_result := _vector2_from_optional(params.get("zoom"))
	if zoom_result.has("__nexora_error"):
		camera.free()
		return zoom_result
	if zoom_result.has("value"):
		var zoom: Vector2 = zoom_result["value"]
		if zoom.x <= 0.0 or zoom.y <= 0.0:
			camera.free()
			return _failure("Camera2D zoom components must be positive")
		camera.zoom = zoom

	var limits = params.get("limits")
	if limits != null:
		var limits_result := _quad_from_array(limits, "limits")
		if limits_result.has("__nexora_error"):
			camera.free()
			return limits_result
		var values: Array = limits_result["value"]
		camera.limit_left = int(values[0])
		camera.limit_top = int(values[1])
		camera.limit_right = int(values[2])
		camera.limit_bottom = int(values[3])

	_commit_add_node(root, parent, camera, "Nexora: Create Camera2D")
	return {
		"path": str(root.get_path_to(camera)),
		"enabled": camera.enabled,
		"position": [camera.position.x, camera.position.y],
		"zoom": [camera.zoom.x, camera.zoom.y],
		"undoable": true,
	}


func _collision2d_shape_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if not parent is CollisionObject2D:
		return _failure("parent must be a CollisionObject2D-derived node")
	var name := String(params.get("name", "CollisionShape2D")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid CollisionShape2D name")

	var shape_result := _shape2d_from_dict(params.get("shape", {}))
	if shape_result.has("__nexora_error"):
		return shape_result
	var collision := CollisionShape2D.new()
	collision.name = name
	collision.shape = shape_result["shape"]
	collision.disabled = bool(params.get("disabled", false))
	collision.one_way_collision = bool(params.get("one_way_collision", false))
	collision.one_way_collision_margin = maxf(
		0.0,
		float(params.get("one_way_collision_margin", 1.0))
	)
	var position_result := _vector2_from_optional(params.get("position"))
	if position_result.has("__nexora_error"):
		collision.free()
		return position_result
	if position_result.has("value"):
		collision.position = position_result["value"]

	_commit_add_node(root, parent, collision, "Nexora: Create CollisionShape2D")
	return {
		"path": str(root.get_path_to(collision)),
		"shape_type": collision.shape.get_class(),
		"disabled": collision.disabled,
		"undoable": true,
	}


func _collision2d_body_create(params: Dictionary) -> Dictionary:
	var context := _scene_context()
	if context.has("__nexora_error"):
		return context
	var root: Node = context["root"]
	var parent := _find_node(root, String(params.get("parent_path", ".")))
	if parent == null:
		return _failure("parent node not found")
	var body_type := String(params.get("body_type", "StaticBody2D"))
	if not _COLLISION_BODY_TYPES.has(body_type):
		return _failure("body_type must be StaticBody2D, CharacterBody2D, RigidBody2D or Area2D")
	var name := String(params.get("name", "")).strip_edges()
	if not _valid_node_name(name):
		return _failure("invalid collision body name")

	var instance = ClassDB.instantiate(body_type)
	if not instance is CollisionObject2D:
		if instance and instance.has_method("free"):
			instance.free()
		return _failure("could not instantiate CollisionObject2D")
	var body: CollisionObject2D = instance
	body.name = name

	var shape_result := _shape2d_from_dict(params.get("shape", {}))
	if shape_result.has("__nexora_error"):
		body.free()
		return shape_result
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = shape_result["shape"]
	body.add_child(collision)

	var position_result := _vector2_from_optional(params.get("position"))
	if position_result.has("__nexora_error"):
		body.free()
		return position_result
	if position_result.has("value") and body is Node2D:
		body.position = position_result["value"]

	_commit_add_node(root, parent, body, "Nexora: Create 2D Collision Body")
	return {
		"path": str(root.get_path_to(body)),
		"body_type": body.get_class(),
		"collision_path": str(root.get_path_to(collision)),
		"shape_type": collision.shape.get_class(),
		"undoable": true,
	}


func _scene_context() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _failure("no edited scene")
	return {"root": root}


func _commit_add_node(root: Node, parent: Node, node: Node, action_name: String) -> void:
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(self, "_undo_add_node", parent, node, root)
	undo_redo.add_undo_method(self, "_undo_remove_node", parent, node)
	undo_redo.add_do_reference(node)
	undo_redo.commit_action()


func _undo_add_node(parent: Node, node: Node, root: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	parent.add_child(node, true)
	_set_subtree_owner(node, root)


func _undo_remove_node(parent: Node, node: Node) -> void:
	if node.get_parent() == parent:
		parent.remove_child(node)


func _set_subtree_owner(node: Node, owner: Node) -> void:
	if node != owner:
		node.owner = owner
	for child in node.get_children():
		_set_subtree_owner(child, owner)


func _find_node(root: Node, path: String) -> Node:
	if path.is_empty() or path == "." or path == "/":
		return root
	return root.get_node_or_null(NodePath(path))


func _valid_node_name(value: String) -> bool:
	var name := value.strip_edges()
	return not name.is_empty() and not name.contains("/")


func _valid_project_path(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("..")


func _has_property(object: Object, property_name: String) -> bool:
	for item_variant in object.get_property_list():
		var item: Dictionary = item_variant
		if String(item.get("name", "")) == property_name:
			return true
	return false


func _apply_safe_properties(
	object: Object,
	raw_properties,
	denied: Dictionary
) -> Dictionary:
	if typeof(raw_properties) != TYPE_DICTIONARY:
		return _failure("properties must be an object")
	var properties: Dictionary = raw_properties
	if properties.size() > 100:
		return _failure("too many properties")

	var known := {}
	for item_variant in object.get_property_list():
		var item: Dictionary = item_variant
		known[String(item.get("name", ""))] = true

	var changed: Array[String] = []
	for key_variant in properties.keys():
		var key := String(key_variant)
		if denied.has(key):
			return _failure("property is not writable through this tool: %s" % key)
		if not known.has(key):
			return _failure("unknown property for %s: %s" % [object.get_class(), key])
		object.set(key, _coerce_value(object.get(key), properties[key_variant]))
		changed.append(key)
	return {"changed": changed}


func _coerce_value(current, incoming):
	match typeof(current):
		TYPE_VECTOR2:
			if typeof(incoming) == TYPE_ARRAY and incoming.size() == 2:
				return Vector2(float(incoming[0]), float(incoming[1]))
		TYPE_VECTOR2I:
			if typeof(incoming) == TYPE_ARRAY and incoming.size() == 2:
				return Vector2i(int(incoming[0]), int(incoming[1]))
		TYPE_COLOR:
			if typeof(incoming) == TYPE_ARRAY and incoming.size() >= 3:
				var alpha := float(incoming[3]) if incoming.size() > 3 else 1.0
				return Color(float(incoming[0]), float(incoming[1]), float(incoming[2]), alpha)
		TYPE_STRING_NAME:
			return StringName(String(incoming))
		TYPE_NODE_PATH:
			return NodePath(String(incoming))
	return incoming


func _vector2_from_optional(raw) -> Dictionary:
	if raw == null:
		return {}
	if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
		return _failure("value must contain exactly 2 numbers")
	return {"value": Vector2(float(raw[0]), float(raw[1]))}


func _vector2i_from_optional(raw) -> Dictionary:
	if raw == null:
		return {}
	return _vector2i_from_required(raw, "value")


func _vector2i_from_required(raw, label: String) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
		return _failure("%s must contain exactly 2 integers" % label)
	return {"value": Vector2i(int(raw[0]), int(raw[1]))}


func _quad_from_array(raw, label: String) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 4:
		return _failure("%s must contain exactly 4 numbers" % label)
	return {
		"value": [
			float(raw[0]),
			float(raw[1]),
			float(raw[2]),
			float(raw[3]),
		]
	}


func _control_layout_state(control: Control) -> Dictionary:
	return {
		"anchors": [
			control.anchor_left,
			control.anchor_top,
			control.anchor_right,
			control.anchor_bottom,
		],
		"offsets": [
			control.offset_left,
			control.offset_top,
			control.offset_right,
			control.offset_bottom,
		],
		"minimum_size": control.custom_minimum_size,
	}


func _layout_preset_state(control: Control, preset: String, margin: float) -> Dictionary:
	var size := control.size
	if size.x <= 0.0:
		size.x = maxf(control.custom_minimum_size.x, 100.0)
	if size.y <= 0.0:
		size.y = maxf(control.custom_minimum_size.y, 40.0)

	match preset:
		"full_rect":
			return {
				"anchors": [0.0, 0.0, 1.0, 1.0],
				"offsets": [margin, margin, -margin, -margin],
			}
		"center":
			return {
				"anchors": [0.5, 0.5, 0.5, 0.5],
				"offsets": [-size.x / 2.0, -size.y / 2.0, size.x / 2.0, size.y / 2.0],
			}
		"top_left":
			return {
				"anchors": [0.0, 0.0, 0.0, 0.0],
				"offsets": [margin, margin, margin + size.x, margin + size.y],
			}
		"top_right":
			return {
				"anchors": [1.0, 0.0, 1.0, 0.0],
				"offsets": [-margin - size.x, margin, -margin, margin + size.y],
			}
		"bottom_left":
			return {
				"anchors": [0.0, 1.0, 0.0, 1.0],
				"offsets": [margin, -margin - size.y, margin + size.x, -margin],
			}
		"bottom_right":
			return {
				"anchors": [1.0, 1.0, 1.0, 1.0],
				"offsets": [-margin - size.x, -margin - size.y, -margin, -margin],
			}
		"top_wide":
			return {
				"anchors": [0.0, 0.0, 1.0, 0.0],
				"offsets": [margin, margin, -margin, margin + size.y],
			}
		"bottom_wide":
			return {
				"anchors": [0.0, 1.0, 1.0, 1.0],
				"offsets": [margin, -margin - size.y, -margin, -margin],
			}
		"left_wide":
			return {
				"anchors": [0.0, 0.0, 0.0, 1.0],
				"offsets": [margin, margin, margin + size.x, -margin],
			}
		"right_wide":
			return {
				"anchors": [1.0, 0.0, 1.0, 1.0],
				"offsets": [-margin - size.x, margin, -margin, -margin],
			}
		_:
			return _failure(
				"preset must be full_rect, center, top_left, top_right, bottom_left, bottom_right, top_wide, bottom_wide, left_wide or right_wide"
			)


func _apply_control_layout_state(control: Control, state: Dictionary) -> void:
	var anchors: Array = state.get("anchors", [0.0, 0.0, 0.0, 0.0])
	var offsets: Array = state.get("offsets", [0.0, 0.0, 0.0, 0.0])
	control.anchor_left = float(anchors[0])
	control.anchor_top = float(anchors[1])
	control.anchor_right = float(anchors[2])
	control.anchor_bottom = float(anchors[3])
	control.offset_left = float(offsets[0])
	control.offset_top = float(offsets[1])
	control.offset_right = float(offsets[2])
	control.offset_bottom = float(offsets[3])
	if state.has("minimum_size"):
		control.custom_minimum_size = state["minimum_size"]


func _validate_theme_override_map(raw, kind: String) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("%s overrides must be an object" % kind)
	var values: Dictionary = raw
	if values.size() > 100:
		return _failure("theme override map is too large")
	var normalized := {}
	for key_variant in values.keys():
		var key := String(key_variant).strip_edges()
		if key.is_empty():
			return _failure("theme override names cannot be empty")
		var value = values[key_variant]
		if kind == "color":
			if typeof(value) != TYPE_ARRAY or value.size() < 3:
				return _failure("color overrides must use [r,g,b] or [r,g,b,a]")
			var alpha := float(value[3]) if value.size() > 3 else 1.0
			normalized[key] = Color(float(value[0]), float(value[1]), float(value[2]), alpha)
		else:
			normalized[key] = int(value)
	return {"values": normalized}


func _capture_theme_state(
	control: Control,
	colors: Dictionary,
	font_sizes: Dictionary,
	constants: Dictionary
) -> Dictionary:
	var color_state := {}
	for key in colors.keys():
		color_state[key] = {
			"had": control.has_theme_color_override(StringName(String(key))),
			"value": control.get_theme_color(StringName(String(key))),
		}
	var font_state := {}
	for key in font_sizes.keys():
		font_state[key] = {
			"had": control.has_theme_font_size_override(StringName(String(key))),
			"value": control.get_theme_font_size(StringName(String(key))),
		}
	var constant_state := {}
	for key in constants.keys():
		constant_state[key] = {
			"had": control.has_theme_constant_override(StringName(String(key))),
			"value": control.get_theme_constant(StringName(String(key))),
		}
	return {
		"theme": control.theme,
		"type_variation": String(control.theme_type_variation),
		"colors": color_state,
		"font_sizes": font_state,
		"constants": constant_state,
	}


func _apply_theme_state(control: Control, state: Dictionary) -> void:
	control.theme = state.get("theme")
	control.theme_type_variation = StringName(String(state.get("type_variation", "")))
	for key in state.get("colors", {}).keys():
		control.add_theme_color_override(StringName(String(key)), state["colors"][key])
	for key in state.get("font_sizes", {}).keys():
		control.add_theme_font_size_override(StringName(String(key)), int(state["font_sizes"][key]))
	for key in state.get("constants", {}).keys():
		control.add_theme_constant_override(StringName(String(key)), int(state["constants"][key]))


func _restore_theme_state(control: Control, state: Dictionary) -> void:
	control.theme = state.get("theme")
	control.theme_type_variation = StringName(String(state.get("type_variation", "")))
	for key in state.get("colors", {}).keys():
		var entry: Dictionary = state["colors"][key]
		if bool(entry.get("had", false)):
			control.add_theme_color_override(StringName(String(key)), entry.get("value"))
		else:
			control.remove_theme_color_override(StringName(String(key)))
	for key in state.get("font_sizes", {}).keys():
		var entry: Dictionary = state["font_sizes"][key]
		if bool(entry.get("had", false)):
			control.add_theme_font_size_override(StringName(String(key)), int(entry.get("value", 0)))
		else:
			control.remove_theme_font_size_override(StringName(String(key)))
	for key in state.get("constants", {}).keys():
		var entry: Dictionary = state["constants"][key]
		if bool(entry.get("had", false)):
			control.add_theme_constant_override(StringName(String(key)), int(entry.get("value", 0)))
		else:
			control.remove_theme_constant_override(StringName(String(key)))


func _load_texture(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	if not _valid_project_path(path) or not FileAccess.file_exists(path):
		return _failure("texture path must be an existing project-local resource")
	var loaded := ResourceLoader.load(path, "Texture2D")
	if not loaded is Texture2D:
		return _failure("resource could not be loaded as Texture2D")
	return {"texture": loaded}


func _tile_cell_to_dict(node: Node, layer_index: int, coords: Vector2i) -> Dictionary:
	var source_id := -1
	var atlas_coords := Vector2i(-1, -1)
	var alternative_tile := -1
	if node is TileMapLayer:
		source_id = node.get_cell_source_id(coords)
		atlas_coords = node.get_cell_atlas_coords(coords)
		alternative_tile = node.get_cell_alternative_tile(coords)
	elif node is TileMap:
		source_id = node.get_cell_source_id(layer_index, coords)
		atlas_coords = node.get_cell_atlas_coords(layer_index, coords)
		alternative_tile = node.get_cell_alternative_tile(layer_index, coords)
	return {
		"coords": [coords.x, coords.y],
		"source_id": source_id,
		"atlas_coords": [atlas_coords.x, atlas_coords.y],
		"alternative_tile": alternative_tile,
	}


func _set_tile_cell(
	node: Node,
	layer_index: int,
	coords: Vector2i,
	source_id: int,
	atlas_coords: Vector2i,
	alternative_tile: int
) -> void:
	if node is TileMapLayer:
		node.set_cell(coords, source_id, atlas_coords, alternative_tile)
	elif node is TileMap:
		node.set_cell(layer_index, coords, source_id, atlas_coords, alternative_tile)


func _shape2d_from_dict(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("shape must be an object")
	var data: Dictionary = raw
	var kind := String(data.get("type", "")).to_lower()
	match kind:
		"circle":
			var shape := CircleShape2D.new()
			shape.radius = maxf(0.001, float(data.get("radius", 16.0)))
			return {"shape": shape}
		"rectangle":
			var shape := RectangleShape2D.new()
			var size_result := _vector2_from_optional(data.get("size"))
			if size_result.has("__nexora_error"):
				return size_result
			shape.size = size_result.get("value", Vector2(32, 32))
			if shape.size.x <= 0.0 or shape.size.y <= 0.0:
				return _failure("rectangle size components must be positive")
			return {"shape": shape}
		"capsule":
			var shape := CapsuleShape2D.new()
			shape.radius = maxf(0.001, float(data.get("radius", 8.0)))
			shape.height = maxf(shape.radius * 2.0, float(data.get("height", 32.0)))
			return {"shape": shape}
		"segment":
			var shape := SegmentShape2D.new()
			var a_result := _vector2_from_optional(data.get("a"))
			var b_result := _vector2_from_optional(data.get("b"))
			if not a_result.has("value") or not b_result.has("value"):
				return _failure("segment shape requires a and b vectors")
			shape.a = a_result["value"]
			shape.b = b_result["value"]
			return {"shape": shape}
		"world_boundary":
			var shape := WorldBoundaryShape2D.new()
			var normal_result := _vector2_from_optional(data.get("normal"))
			if normal_result.has("__nexora_error"):
				return normal_result
			shape.normal = normal_result.get("value", Vector2(0, -1)).normalized()
			shape.distance = float(data.get("distance", 0.0))
			return {"shape": shape}
		"convex_polygon":
			var raw_points = data.get("points", [])
			if typeof(raw_points) != TYPE_ARRAY or raw_points.size() < 3 or raw_points.size() > 128:
				return _failure("convex_polygon requires between 3 and 128 points")
			var points := PackedVector2Array()
			for point_variant in raw_points:
				var point_result := _vector2_from_optional(point_variant)
				if point_result.has("__nexora_error") or not point_result.has("value"):
					return _failure("invalid convex polygon point")
				points.append(point_result["value"])
			var shape := ConvexPolygonShape2D.new()
			shape.points = points
			return {"shape": shape}
		_:
			return _failure("shape.type must be circle, rectangle, capsule, segment, world_boundary or convex_polygon")


func _identifier_from_text(text: String, fallback: String) -> String:
	var output := ""
	for character in text:
		var value := String(character)
		if value.to_lower() != value.to_upper() or value >= "0" and value <= "9" or value == "_":
			output += value
	if output.is_empty() or not output.is_valid_identifier():
		return fallback
	return output


func _failure(message: String) -> Dictionary:
	return {"__nexora_error": message}
