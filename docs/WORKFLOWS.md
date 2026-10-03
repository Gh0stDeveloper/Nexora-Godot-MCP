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

Phase A can create a scene when the editor has an empty scene tab:

```text
scene_create
 ↓
node_create
 ↓
node_set_properties
 ↓
scene_save
 ↓
project_validate
```

Future phases will add safer new-tab/scene lifecycle helpers.

## Fix a script

```text
script_read
 ↓
inspect SHA-256
 ↓
produce corrected source
 ↓
script_replace(expected_sha256)
 ↓
project_validate
 ↓
project_run
 ↓
runtime_logs
```

The revision hash protects newer human edits from stale replacement.

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
→ import/reimport tools (planned)
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
