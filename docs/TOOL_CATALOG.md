# Tool catalog

This document distinguishes the **implemented Phase A–D surface** from the broader planned catalog.

## Implemented in Phase A–D

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

### `script_patch`

Applies up to 100 exact-match patches after verifying the SHA-256 revision that the AI previously read.

By default every patch search must match exactly once. `replace_all=true` can be used only with an explicit/derived match count. The final write is atomic.

Permission: standard/write.

### `script_check`

Runs Godot's GDScript parser using `--check-only --script` and returns structured diagnostics plus raw output.

Current structured checking targets `.gd`. C# source editing is supported, but compiler diagnostics require a Godot .NET/.NET toolchain and are not faked by the standard build.

Permission: read.

### `script_symbols`

Loads a Godot Script resource and returns language, global name, base script, methods, signals and script properties.

Permission: read.

### `script_attach` / `script_detach`

Attach or detach a Script resource on a node with editor Undo/Redo support.

Permission: standard/write.

## Signals

### `signal_list`

Lists signals exposed by a node and optionally their current connections.

Permission: read.

### `signal_connections`

Inspects the connections for one signal.

Permission: read.

### `signal_connect`

Creates an undoable connection to a target method. Persistent editor-scene connections are enabled by default.

Optional flags include deferred, one-shot and reference-counted connections.

Permission: standard/write.

### `signal_disconnect`

Disconnects one matching signal/callable pair while preserving an Undo action.

Permission: standard/write.

## Input Map

### `input_actions_list`

Returns actions, deadzones, persisted state and serialized key/mouse/joypad events.

Permission: read.

### `input_action_create`

Creates and persists a new action.

Permission: standard/write.

### `input_action_set_deadzone`

Changes and persists an existing action deadzone.

Permission: standard/write.

### `input_action_delete`

Deletes an action. `confirm=true` is required.

Permission: destructive/write.

### `input_event_add`

Adds a structured `key`, `mouse_button`, `joypad_button` or `joypad_motion` event and persists the action.

Permission: standard/write.

### `input_event_remove`

Removes an event by index. `confirm=true` is required.

Permission: destructive/write.

## Project settings and autoloads

### `project_settings_read`

Reads explicit settings or a bounded prefix-filtered subset.

Permission: read.

### `project_settings_set`

Sets up to 100 ordinary ProjectSettings values and saves `project.godot`.

The `input/`, `autoload/` and `editor_plugins/` namespaces are reserved for dedicated tools.

Permission: standard/write.

### `project_settings_clear`

Removes ordinary settings. `confirm=true` is required.

Permission: destructive/write.

### `autoload_list`

Lists project autoload singletons.

Permission: read.

### `autoload_add`

Registers an existing project-local `.gd`, `.cs`, `.tscn` or `.scn` as an autoload singleton.

Permission: standard/write.

### `autoload_remove`

Removes the autoload registration without deleting its source resource. `confirm=true` is required.

Permission: destructive/write.

## UI and 2D

### `ui_create_control`

Creates a Control-derived node with optional text, minimum size and bounded safe properties.

Permission: standard/write.

### `ui_create_container`

Creates supported Godot Container types such as VBoxContainer, HBoxContainer, GridContainer, MarginContainer, CenterContainer and PanelContainer.

Permission: standard/write.

### `ui_set_layout`

Sets Control anchors/offsets directly or through common responsive presets including `full_rect`, `center`, corner presets and wide-edge presets.

Layout mutations use editor Undo/Redo.

Permission: standard/write.

### `ui_theme_apply`

Applies an optional project-local Theme resource, theme type variation, and bounded color/font-size/constant overrides.

Permission: standard/write.

### `ui_text_set`

Updates text on supported Controls with Undo/Redo.

Permission: standard/write.

### `ui_create_hud`

Builds a CanvasLayer HUD scaffold containing margin/container structure and title, health and objective labels.

Permission: standard/write.

### `ui_create_menu`

Builds a centered CanvasLayer menu scaffold with a title and up to 20 buttons. Button signals remain configurable through the Phase C signal tools.

Permission: standard/write.

### `sprite2d_create`

Creates Sprite2D with optional project-local Texture2D, position, flip state and sprite-sheet frame configuration.

Permission: standard/write.

### `animated_sprite2d_create`

Creates AnimatedSprite2D plus an in-scene SpriteFrames resource from up to 32 animations and 256 project-local texture frames.

Permission: standard/write.

### `tilemap_layer_create`

Creates TileMapLayer using an existing project-local TileSet or a new empty TileSet with optional tile size.

Permission: standard/write.

### `tilemap_inspect`

Inspects either TileMapLayer or legacy TileMap and returns a bounded list of used cells, atlas identifiers and used bounds.

Permission: read.

### `tilemap_set_cells`

Writes up to 500 cells through editor Undo/Redo.

Any cell with `source_id=-1` is treated as an erase operation and requires `confirm_erase=true`.

Permission: standard/write with explicit erase gate.

### `camera2d_create`

Creates Camera2D with position, zoom, enabled state, position smoothing and optional limits.

Permission: standard/write.

### `collision2d_shape_create`

Creates CollisionShape2D beneath an existing CollisionObject2D.

Supported structured shapes include circle, rectangle, capsule, segment, world boundary and convex polygon.

Permission: standard/write.

### `collision2d_body_create`

Creates a StaticBody2D, CharacterBody2D, RigidBody2D or Area2D together with a child CollisionShape2D.

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
- feature-specific typed project-setting helpers

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

- range-aware patch helpers;
- C# diagnostics when a verified Godot .NET toolchain is available;
- code navigation helpers.

## Signals

- signal connection bulk validation;
- connection repair helpers.

## Input Map

- richer device-specific event types;
- conflict detection across actions.

## UI

- richer reusable Theme resource authoring;
- focus-neighbor/navigation helpers;
- advanced responsive layout recipes.

## 2D/3D

- Camera3D;
- MeshInstance3D;
- 3D collision shapes;
- lights;
- WorldEnvironment.

## Physics/navigation

- 2D/3D collision layers and masks;
- 3D CharacterBody/RigidBody/StaticBody creation;
- Area3D;
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
