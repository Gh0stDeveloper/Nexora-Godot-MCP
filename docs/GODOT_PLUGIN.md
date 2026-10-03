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

- script attach/detach;
- signal tools;
- Input Map and project settings;
- debugger integration;
- screenshot capture;
- animation/resource authoring operations;
- structured UI builders.


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
