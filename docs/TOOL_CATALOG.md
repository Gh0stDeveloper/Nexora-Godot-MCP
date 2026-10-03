# Tool catalog

This document distinguishes the **implemented Phase A–B surface** from the broader planned catalog.

## Implemented in Phase A–B

### System

#### `godot_status`

Returns:

- Godot CLI version when available;
- configured project root;
- editor bridge status;
- edited-scene metadata.

Permission: read.

#### `nexora_capabilities`

Describes server scope, version, authentication, permission profile and available categories.

It explicitly reports that this is a dedicated Godot server and not an all-in-one MCP.

Permission: read.

## Project

### `project_inspect`

Inspects the configured `project.godot` and reports basic metadata and SHA-256.

Permission: read.

### `project_validate`

Runs a bounded headless editor validation pass.

Permission: read.

### `project_import`

Runs Godot's documented headless import operation.

Permission: standard/write.

## Scene

### `scene_snapshot`

Returns a bounded tree of the current edited scene.

Permission: read.

Bridge operation: `scene.snapshot`.

### `scene_open`

Opens a project-local `.tscn` or `.scn`.

Permission: standard/write.

### `scene_save`

Saves the current scene or saves it to a project-local `.tscn`.

Permission: standard/write.

### `scene_create`

Creates a new PackedScene resource and saves it as `.tscn` without discarding the currently edited scene.

The new scene can optionally be opened after creation. Existing destinations require `overwrite=true`, and an open scene is never overwritten.

Permission: standard/write.

### `scene_open_scenes`

Lists currently open scenes and identifies the active scene. Godot 4.6 does not expose a stable unsaved-scene list through `EditorInterface`, so destructive scene actions use mandatory confirmation instead.

Permission: read.

### `scene_reload`

Reloads the active scene from disk. `confirm_discard=true` is always required because reloading can discard editor changes.

Permission: destructive/write.

### `scene_close`

Closes the active scene. `confirm_discard=true` is always required because Godot's close operation discards pending changes.

Permission: destructive/write.

### `scene_duplicate`

Duplicates a project-local PackedScene. Existing destinations require `overwrite=true`.

Permission: standard/write.

### `scene_instantiate`

Instantiates a PackedScene below a selected parent node with editor Undo/Redo integration.

Permission: standard/write.

### `scene_dependencies`

Returns the external Resource dependencies declared by a scene.

Permission: read.

## Nodes

### `node_create`

Creates a Node-derived Godot class below a parent in the edited scene.

Optional properties are validated against the target object's property list.

Permission: standard/write.

### `node_set_properties`

Changes up to 100 known properties.

Sensitive fields including `script`, `owner` and `scene_file_path` are not writable through this generic surface.

Permission: standard/write.

### `node_delete`

Deletes a non-root node through the Godot editor Undo/Redo history.

Requires:

```text
confirm=true
```

Permission: standard/destructive.

### `node_rename`

Renames a node and records the operation in editor Undo/Redo history.

Permission: standard/write.

### `node_reparent`

Moves a node to a new parent while preserving the supported global transform and retaining an undoable topology change.

Permission: standard/write.

### `node_transform_2d`

Updates selected Node2D position, rotation, scale and/or skew components in local or global space.

Permission: standard/write.

### `node_transform_3d`

Updates selected Node3D position, rotation and/or scale in local or global space. Unsafe mixed-sign/zero scales are rejected.

Permission: standard/write.

### `node_repair_owner`

Repairs owner metadata for generated nodes/subtrees so they remain persistent in PackedScene saves.

Permission: standard/write.

## Resources and editor filesystem

### `resource_inspect`

Loads a project-local Resource and returns its type, UID, dependencies and a bounded serialized subset of stored properties.

Permission: read.

### `filesystem_status`

Returns editor filesystem scan/import state and scan progress.

Permission: read.

### `filesystem_scan`

Starts an EditorFileSystem scan when the importer is not busy.

Permission: standard/write.

### `asset_reimport`

Reimports up to 100 existing project-local resource/source files.

Permission: standard/write.

## Scripts

### `script_read`

Reads a project-local `.gd` or `.cs` file with SHA-256.

Permission: read.

### `script_create`

Creates a bounded script file inside the project.

Existing files require explicit `overwrite=true`.

Permission: standard/write.

### `script_replace`

Revision-aware full replacement.

The current file SHA-256 must match `expected_sha256`.

Permission: standard/write.

## Runtime

### `project_run`

Runs the main project or a selected project-local scene and returns a `run_id`.

Permission: standard/write.

### `runtime_status`

Returns PID, duration and exit state.

Permission: read.

### `runtime_logs`

Returns bounded stdout/stderr.

Permission: read.

### `runtime_stop`

Stops a run created by `project_run`.

Permission: standard/destructive.

## Export

### `export_presets`

Reads the non-secret subset of `export_presets.cfg`.

Permission: read.

### `export_debug`

Runs `--export-debug`.

Permission: standard/write.

### `export_release`

Runs `--export-release`.

Permission: standard/write.

### `export_pack`

Runs `--export-pack`.

Permission: standard/write.

Exports remain inside the configured project root.

## Batch

### `batch_execute`

Executes up to 50 structured editor operations.

Nested batches are rejected. Destructive lifecycle operations such as node deletion, scene close/reload/create and scene overwrite/duplication are deliberately blocked inside batches so their dedicated confirmation or overwrite gates cannot be bypassed.

Permission: standard/write.

---

# Planned catalog

The following categories are intentionally planned as dedicated structured tools rather than immediately exposing arbitrary scripting.

## Project/settings

- `project_create`
- `project_settings_read`
- `project_settings_set`
- `autoload_list`
- `autoload_add`
- `autoload_remove`

## Scene composition

- `scene_validate`
- inherited-scene creation
- safe scene-tab creation helpers

## Nodes/transforms

- `node_set_owner`
- node duplication
- editor selection helpers

## Resources/assets

- `resource_create`
- `resource_duplicate`
- `resource_set_properties`
- `resource_save`
- `asset_import_status`

## Scripts

- `script_patch`
- `script_attach`
- `script_detach`
- `script_check`
- `script_symbols`

## Signals

- `signal_list`
- `signal_connections`
- `signal_connect`
- `signal_disconnect`

## Input Map

- `input_actions_list`
- `input_action_create`
- `input_action_delete`
- `input_event_add`
- `input_event_remove`

## UI

- `ui_create_control`
- `ui_create_container`
- `ui_set_layout`
- `ui_theme_apply`
- `ui_text_set`

## 2D/3D

- sprites and animated sprites;
- TileMap/TileMapLayer inspection;
- Camera2D/Camera3D;
- MeshInstance3D;
- collision shapes;
- lights;
- WorldEnvironment.

## Physics/navigation

- CharacterBody/RigidBody/StaticBody creation;
- collision layers and masks;
- Area2D/Area3D;
- NavigationRegion;
- NavigationAgent;
- NavigationLink.

## Animation/audio

- AnimationPlayer;
- animation libraries/tracks/keys;
- AnimationTree;
- audio buses;
- AudioStreamPlayer variants.

## Shaders/materials

- shader create/patch/check;
- StandardMaterial3D;
- ShaderMaterial;
- CanvasItem materials.

## Debug/performance

- structured parser/runtime diagnostics;
- screenshot/image results;
- performance snapshots;
- comparison of captured snapshots.

## Restricted advanced operations

A future `godot_execute_editor_script` remains disabled by default and will require unrestricted mode plus a second explicit opt-in.

Normal configurations will not expose a raw shell.
