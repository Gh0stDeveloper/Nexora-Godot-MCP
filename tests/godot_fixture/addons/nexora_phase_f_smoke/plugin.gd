@tool
extends EditorPlugin

const PhaseF = preload("res://addons/nexora_godot_mcp/phase_f.gd")

var _wait_frames := 0


func _enter_tree() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	_wait_frames += 1
	if _wait_frames < 34:
		return
	set_process(false)
	EditorInterface.open_scene_from_path("res://phase_f_scene.tscn")
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var phase_f = PhaseF.new(self)

	var region: Dictionary = phase_f.execute(
		"navigation.region_create",
		{
			"parent_path": ".",
			"name": "NavigationRegion3D",
			"dimension": "3d",
		}
	)
	if _failed("region", region):
		return

	var agent: Dictionary = phase_f.execute(
		"navigation.agent_create",
		{
			"parent_path": "Target",
			"name": "NavigationAgent3D",
			"dimension": "3d",
			"target_position": [3, 0, 3],
			"avoidance_enabled": false,
		}
	)
	if _failed("agent", agent):
		return

	var link: Dictionary = phase_f.execute(
		"navigation.link_create",
		{
			"parent_path": ".",
			"name": "JumpLink",
			"dimension": "3d",
			"start_position": [0, 0, 0],
			"end_position": [2, 0, 0],
			"bidirectional": true,
		}
	)
	if _failed("link", link):
		return

	var navigation: Dictionary = phase_f.execute(
		"navigation.inspect",
		{"node_path": "NavigationRegion3D"}
	)
	if _failed("navigation inspect", navigation):
		return

	var player_result: Dictionary = phase_f.execute(
		"animation.player_create",
		{"parent_path": ".", "name": "AnimationPlayer"}
	)
	if _failed("animation player", player_result):
		return

	for animation_name in ["Idle", "Run"]:
		var created: Dictionary = phase_f.execute(
			"animation.create",
			{
				"player_path": "AnimationPlayer",
				"library": "",
				"animation": animation_name,
				"length": 1.0,
				"loop_mode": "linear",
			}
		)
		if _failed("animation " + animation_name, created):
			return

	var track: Dictionary = phase_f.execute(
		"animation.track_add",
		{
			"player_path": "AnimationPlayer",
			"library": "",
			"animation": "Idle",
			"track_type": "position_3d",
			"path": "Target",
		}
	)
	if _failed("track", track):
		return

	var key: Dictionary = phase_f.execute(
		"animation.key_insert",
		{
			"player_path": "AnimationPlayer",
			"library": "",
			"animation": "Idle",
			"track_index": int(track.get("track_index", 0)),
			"time": 0.0,
			"value": [0, 0, 0],
		}
	)
	if _failed("key", key):
		return

	var inspected: Dictionary = phase_f.execute(
		"animation.inspect",
		{"player_path": "AnimationPlayer"}
	)
	if _failed("animation inspect", inspected):
		return

	var tree: Dictionary = phase_f.execute(
		"animation_tree.create",
		{
			"parent_path": ".",
			"animation_player_path": "AnimationPlayer",
			"name": "AnimationTree",
			"active": false,
		}
	)
	if _failed("animation tree", tree):
		return

	var idle_state: Dictionary = phase_f.execute(
		"animation_tree.state_add",
		{
			"tree_path": "AnimationTree",
			"state_name": "Idle",
			"animation": "Idle",
			"position": [0, 0],
		}
	)
	if _failed("idle state", idle_state):
		return

	var run_state: Dictionary = phase_f.execute(
		"animation_tree.state_add",
		{
			"tree_path": "AnimationTree",
			"state_name": "Run",
			"animation": "Run",
			"position": [240, 0],
		}
	)
	if _failed("run state", run_state):
		return

	var transition: Dictionary = phase_f.execute(
		"animation_tree.transition_add",
		{
			"tree_path": "AnimationTree",
			"from_state": "Idle",
			"to_state": "Run",
			"xfade_time": 0.15,
			"switch_mode": "immediate",
			"advance_mode": "disabled",
		}
	)
	if _failed("transition", transition):
		return

	var tree_inspect: Dictionary = phase_f.execute(
		"animation_tree.inspect",
		{"tree_path": "AnimationTree"}
	)
	if _failed("tree inspect", tree_inspect):
		return

	print("NEXORA_PHASE_F_SMOKE_OK")


func _failed(label: String, result: Dictionary) -> bool:
	if result.has("__nexora_error"):
		print("NEXORA_PHASE_F_SMOKE_FAIL ", label, ": ", result)
		return true
	return false
