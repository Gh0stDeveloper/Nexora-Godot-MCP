@tool
extends EditorPlugin

const PhaseD = preload("res://addons/nexora_godot_mcp/phase_d.gd")


func _enter_tree() -> void:
	call_deferred("_open_fixture")


func _open_fixture() -> void:
	EditorInterface.open_scene_from_path("res://phase_d_scene.tscn")
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var phase_d = PhaseD.new(self)

	var panel: Dictionary = phase_d.execute(
		"ui.control_create",
		{
			"parent_path": ".",
			"control_type": "PanelContainer",
			"name": "Panel",
			"minimum_size": [320, 180],
		}
	)
	if _failed("panel", panel):
		return

	var layout: Dictionary = phase_d.execute(
		"ui.layout_set",
		{
			"node_path": "Panel",
			"preset": "center",
			"size": [320, 180],
		}
	)
	if _failed("layout", layout):
		return

	var stack: Dictionary = phase_d.execute(
		"ui.container_create",
		{
			"parent_path": "Panel",
			"container_type": "VBoxContainer",
			"name": "Stack",
			"minimum_size": [280, 120],
		}
	)
	if _failed("container", stack):
		return

	var label: Dictionary = phase_d.execute(
		"ui.control_create",
		{
			"parent_path": "Panel/Stack",
			"control_type": "Label",
			"name": "Title",
			"text": "Phase D",
		}
	)
	if _failed("label", label):
		return

	var themed: Dictionary = phase_d.execute(
		"ui.theme_apply",
		{
			"node_path": "Panel/Stack/Title",
			"colors": {"font_color": [0.2, 0.7, 1.0, 1.0]},
			"font_sizes": {"font_size": 18},
		}
	)
	if _failed("theme", themed):
		return

	var text_result: Dictionary = phase_d.execute(
		"ui.text_set",
		{"node_path": "Panel/Stack/Title", "text": "Phase D Ready"}
	)
	if _failed("text", text_result):
		return

	var hud: Dictionary = phase_d.execute(
		"ui.hud_create",
		{
			"parent_path": ".",
			"name": "HUD",
			"title": "Nexora",
			"health_text": "Health: 100",
			"objective_text": "Smoke test",
		}
	)
	if _failed("hud", hud):
		return

	var menu: Dictionary = phase_d.execute(
		"ui.menu_create",
		{
			"parent_path": ".",
			"name": "PauseMenu",
			"title": "Paused",
			"buttons": ["Resume", "Settings", "Quit"],
		}
	)
	if _failed("menu", menu):
		return

	var sprite: Dictionary = phase_d.execute(
		"sprite2d.create",
		{
			"parent_path": ".",
			"name": "Icon",
			"texture_path": "res://phase_d_texture.svg",
			"position": [64, 64],
		}
	)
	if _failed("sprite", sprite):
		return

	var animated: Dictionary = phase_d.execute(
		"animated_sprite2d.create",
		{
			"parent_path": ".",
			"name": "AnimatedIcon",
			"position": [96, 64],
			"animations": [
				{
					"name": "idle",
					"frames": [
						"res://phase_d_texture.svg",
						"res://phase_d_texture.svg",
					],
					"fps": 8.0,
					"loop": true,
				},
			],
			"initial_animation": "idle",
			"autoplay": true,
		}
	)
	if _failed("animated", animated):
		return

	var tile_layer_result: Dictionary = phase_d.execute(
		"tilemap_layer.create",
		{
			"parent_path": ".",
			"name": "Ground",
			"create_empty_tileset": true,
			"tile_size": [32, 32],
		}
	)
	if _failed("tile layer", tile_layer_result):
		return

	var atlas_result: Dictionary = phase_d.execute(
		"tileset.atlas_source_add",
		{
			"node_path": "Ground",
			"texture_path": "res://phase_d_texture.svg",
			"texture_region_size": [32, 32],
			"tiles": [[0, 0]],
		}
	)
	if _failed("tileset atlas", atlas_result):
		return
	var source_id := int(atlas_result.get("source_id", -1))
	if source_id < 0:
		print("NEXORA_PHASE_D_SMOKE_FAIL invalid source id: ", atlas_result)
		return

	var cells: Dictionary = phase_d.execute(
		"tilemap.set_cells",
		{
			"node_path": "Ground",
			"cells": [
				{
					"coords": [0, 0],
					"source_id": source_id,
					"atlas_coords": [0, 0],
					"alternative_tile": 0,
				},
			],
		}
	)
	if _failed("tile cells", cells):
		return

	var inspected: Dictionary = phase_d.execute(
		"tilemap.inspect",
		{"node_path": "Ground", "max_cells": 20}
	)
	if _failed("tile inspect", inspected) or int(inspected.get("used_cell_count", 0)) != 1:
		print("NEXORA_PHASE_D_SMOKE_FAIL tile inspect count: ", inspected)
		return

	var erase_denied: Dictionary = phase_d.execute(
		"tilemap.set_cells",
		{
			"node_path": "Ground",
			"cells": [{"coords": [0, 0], "source_id": -1}],
		}
	)
	if not erase_denied.has("__nexora_error"):
		print("NEXORA_PHASE_D_SMOKE_FAIL unconfirmed tile erase was allowed")
		return

	var erased: Dictionary = phase_d.execute(
		"tilemap.set_cells",
		{
			"node_path": "Ground",
			"confirm_erase": true,
			"cells": [{"coords": [0, 0], "source_id": -1}],
		}
	)
	if _failed("confirmed tile erase", erased):
		return

	var camera: Dictionary = phase_d.execute(
		"camera2d.create",
		{
			"parent_path": ".",
			"name": "Camera2D",
			"position": [100, 100],
			"zoom": [1.5, 1.5],
			"enabled": true,
			"limits": [-500, -500, 500, 500],
		}
	)
	if _failed("camera", camera):
		return

	var body: Dictionary = phase_d.execute(
		"collision2d.body_create",
		{
			"parent_path": ".",
			"body_type": "StaticBody2D",
			"name": "Wall",
			"position": [200, 120],
			"shape": {
				"type": "rectangle",
				"size": [64, 24],
			},
		}
	)
	if _failed("collision body", body):
		return

	var shape: Dictionary = phase_d.execute(
		"collision2d.shape_create",
		{
			"parent_path": "Wall",
			"name": "ExtraCollision",
			"position": [40, 0],
			"shape": {
				"type": "circle",
				"radius": 12,
			},
		}
	)
	if _failed("collision shape", shape):
		return

	print("NEXORA_PHASE_D_SMOKE_OK")


func _failed(label: String, result: Dictionary) -> bool:
	if result.has("__nexora_error"):
		print("NEXORA_PHASE_D_SMOKE_FAIL ", label, ": ", result)
		return true
	return false
