# Godot editor plugin

## Purpose

The editor addon is the local execution bridge between the Python MCP gateway and Godot's editor API.

It does not implement MCP and it does not connect to AI providers.

## Location

```text
godot_addon/
└── addons/
    └── nexora_godot_mcp/
        ├── plugin.cfg
        ├── plugin.gd
        ├── phase_b.gd
        ├── phase_c.gd
        ├── phase_d.gd
        └── bridge_server.gd
```

The installer copies this directory into the selected Godot project.

## Local configuration

The installer writes:

```text
<project>/.nexora-godot/bridge.json
```

Example:

```json
{
  "host": "127.0.0.1",
  "port": 9877,
  "secret": "...",
  "auto_start": true
}
```

The project `.gitignore` is updated so this private local configuration is not committed.

## Network boundary

The bridge always binds explicitly to:

```text
127.0.0.1
```

Changing the JSON `host` does not make the bridge listen publicly; the bridge server code fixes its listener to loopback.

## Protocol

One newline-delimited JSON request is sent over TCP.

The request contains:

- request ID;
- bridge secret;
- structured operation;
- JSON params.

The bridge returns one JSON response with either:

```json
{"ok": true, "result": {}}
```

or:

```json
{"ok": false, "error": "..."}
```

## Dock

The plugin adds a compact **Nexora Godot MCP** dock with:

- bridge status;
- loopback endpoint;
- current project;
- Start Bridge;
- Stop;
- latest bridge error;
- explanation that AI chat remains in the MCP host.

No chat interface is embedded into Godot.

## Implemented editor operations

Phase A core:

- `system.status`
- `scene.snapshot`
- `scene.open`
- `scene.save`
- `batch.execute`

Phase B production layer:

- `scene.open_scenes`
- `scene.reload`
- `scene.close`
- `scene.create`
- `scene.duplicate`
- `scene.instantiate`
- `scene.dependencies`
- `node.create`
- `node.set_properties`
- `node.delete`
- `node.rename`
- `node.reparent`
- `node.transform_2d`
- `node.transform_3d`
- `node.repair_owner`
- `resource.inspect`
- `filesystem.status`
- `filesystem.scan`
- `filesystem.reimport`

## Scene inspection

The snapshot serializer returns compact records:

```json
{
  "name": "Player",
  "type": "CharacterBody3D",
  "path": "World/Player",
  "child_count": 4
}
```

The caller chooses a bounded maximum number of nodes.

## Node creation

The plugin uses `ClassDB` to instantiate a requested Godot class and confirms the object is Node-derived.

New nodes are assigned to the edited scene root so they can be persisted in the packed scene.

## Property conversion

JSON arrays are converted to common Godot value types when the existing property type requires them:

- Vector2;
- Vector2i;
- Vector3;
- Vector3i;
- Color.

Generic property editing intentionally blocks sensitive fields that should receive dedicated tools later.

## Future plugin work

- debugger integration;
- screenshot capture;
- animation/resource authoring operations.


## Undo/Redo integration

Phase B routes scene-node mutations through `EditorPlugin.get_undo_redo()`.

Undoable actions include:

- node creation;
- scene instancing;
- node property edits;
- node deletion;
- node rename;
- node reparent;
- Node2D transforms;
- Node3D transforms;
- owner repair.

This keeps AI-generated editor work compatible with the same Undo/Redo workflow used by human editor operations.

Filesystem/resource writes such as scene duplication and import rescans are not represented as scene-history actions because they operate on project resources rather than the active scene history.

## Resource and filesystem handling

Resource inspection uses `ResourceLoader` and serializes only a bounded set of stored properties into JSON-safe values.

Filesystem refresh/reimport uses `EditorInterface.get_resource_filesystem()`. Reimport operations refuse to start while the editor filesystem is already scanning/importing.


## Godot 4.6 scene-discard safety

Godot 4.6 exposes open-scene information but does not provide a stable `EditorInterface` API for listing every unsaved scene. Because `close_scene()` discards pending changes, Nexora Godot MCP does not guess.

`scene_close` and `scene_reload` therefore require `confirm_discard=true` every time. This conservative gate protects manual editor work even when the MCP cannot determine dirty-tab state.


## Phase C production layer

Phase C adds editor operations for:

- Script symbols;
- Script attach/detach;
- signal discovery and connection management;
- Input Map persistence;
- ProjectSettings access;
- autoload singletons.

Script attachment and signal connection changes use the editor Undo/Redo history.

Input Map actions are read and written directly through the project's `input/*` entries in `ProjectSettings`. This is intentional: inside an editor plugin, the `InputMap` singleton can represent editor actions rather than the project's bindings. Generic settings tools deliberately reject the `input/`, `autoload/` and `editor_plugins/` namespaces so callers cannot bypass the typed tools.

Autoload operations use the EditorPlugin autoload API and never delete the underlying script/scene when a registration is removed.


## Phase D UI and 2D production layer

Phase D adds typed editor operations for:

- Control and Container creation;
- responsive anchors/offsets and common layout presets;
- Theme resources and local theme overrides;
- text updates;
- HUD and menu scaffolds;
- Sprite2D and AnimatedSprite2D authoring;
- TileMapLayer creation and TileMap/TileMapLayer inspection;
- undoable TileMap cell updates;
- Camera2D;
- structured CollisionShape2D and 2D collision-body workflows.

UI/node creation and TileMap changes participate in the editor Undo/Redo history.

Theme paths and texture paths remain project-local resources. AnimatedSprite2D creation is bounded to 32 animations and 256 frames per call.

TileMap cell erasure is never implicit: a cell update with `source_id=-1` requires an explicit `confirm_erase=true` request at the MCP gateway and is checked again by the editor bridge.


## Phase E — 3D/gameplay production layer

Phase E adds typed editor operations for MeshInstance3D, Camera3D, Light3D, WorldEnvironment, CollisionShape3D, supported 3D physics bodies/areas and Skeleton3D inspection.

The 3D layer configures Godot engine structures only. It does not attempt to replace Nexora Forge MCP for modeling or mesh authoring.

Created 3D nodes participate in the editor Undo/Redo history.

## Phase F — navigation and animation layer

Phase F adds NavigationRegion/Agent/Link creation for both 2D and 3D plus navigation inspection.

Animation authoring includes AnimationPlayer, AnimationLibrary/Animation resources, typed tracks, key insertion, AnimationTree backed by AnimationNodeStateMachine, state creation, transitions and inspection.

These editor mutations are designed to remain undoable where Godot's resource APIs permit it.
