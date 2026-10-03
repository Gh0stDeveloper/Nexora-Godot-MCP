# Workflows

These examples show the intended separation between AI reasoning and structured Godot actions.

## Inspect before editing

```text
godot_status
 ↓
project_inspect
 ↓
scene_snapshot
 ↓
plan changes
```

This should be the default pattern before substantial scene edits.

## Create a scene

Phase B creates a PackedScene resource without closing or discarding the developer's current editor tab:

```text
scene_create(open_after_create=true)
 ↓
node_create
 ↓
node_set_properties
 ↓
scene_save
 ↓
project_validate
```

If a destination scene already exists, overwrite must be explicit. A scene that is currently open in the editor is never overwritten by `scene_create`.

## Fix a script

```text
script_read
 ↓
inspect SHA-256
 ↓
script_patch(expected_sha256)
 ↓
script_check
 ↓
project_validate
 ↓
project_run
 ↓
runtime_logs
```

The revision hash protects newer human edits from stale replacement. `script_patch` additionally rejects ambiguous search blocks rather than guessing which occurrence the AI intended.

## Run a gameplay test

```text
project_run
 ↓
run_id
 ├── runtime_status
 ├── runtime_logs
 └── runtime_stop
```

The host can keep reasoning while the process continues independently.

## Export Android

```text
export_presets
 ↓
project_validate
 ↓
export_debug("Android", "builds/game.apk")
 ↓
artifact metadata
```

Godot's installed export templates and project preset configuration remain the user's responsibility.

## Use Forge and Godot MCP together

The servers are independent.

A host may choose:

```text
"Create a game-ready zombie mesh"
→ Forge MCP
→ GLB

"Use zombie.glb in my Godot enemy scene"
→ Godot MCP
→ asset_reimport / filesystem_scan when needed
→ scene_instantiate
→ scene composition
→ gameplay
```

Godot MCP does not call Forge internally.

## Human review summary

After a meaningful workflow the MCP host should be able to report:

```text
Changed:
- res://enemy/enemy.gd
- res://enemy/enemy.tscn

Validation:
- project validation: passed
- runtime process: exited 0
- new stderr lines: none
```

The server should expose structured facts so the host does not invent this summary.


## Wire gameplay with signals

```text
scene_snapshot
 ↓
script_attach
 ↓
script_symbols
 ↓
signal_list
 ↓
signal_connect
 ↓
scene_save
 ↓
project_validate
```

Persistent signal connections default to the editor-persistent flag and remain undoable.

## Configure controls

```text
input_actions_list
 ↓
input_action_create("interact")
 ↓
input_event_add({"type":"key","physical_keycode":...})
 ↓
input_actions_list
```

Input actions and bindings are persisted to the Godot project rather than existing only for the current editor process.


## Build a HUD and menu

```text
scene_snapshot
 ↓
ui_create_hud
 ↓
ui_create_menu
 ↓
ui_set_layout
 ↓
ui_theme_apply
 ↓
signal_connect
 ↓
scene_save
```

Phase D creates the visual hierarchy while Phase C signal tools connect menu buttons to gameplay methods.

## Build a 2D gameplay scene

```text
tilemap_layer_create
 ↓
tilemap_set_cells
 ↓
sprite2d_create / animated_sprite2d_create
 ↓
collision2d_body_create
 ↓
camera2d_create
 ↓
scene_save
 ↓
project_validate
```

Tile erasure requires explicit confirmation. Texture and TileSet resources remain confined to the configured Godot project.
