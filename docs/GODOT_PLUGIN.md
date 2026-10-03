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

Changing the JSON `host` does not make the Phase A bridge listen publicly; the bridge server code fixes its listener to loopback.

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

- `system.status`
- `scene.snapshot`
- `scene.open`
- `scene.save`
- `scene.create`
- `node.create`
- `node.set_properties`
- `node.delete`
- `batch.execute`

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

- EditorUndoRedoManager integration;
- scene instancing;
- script attach/detach;
- signal tools;
- filesystem scan/reimport;
- debugger integration;
- screenshot capture;
- animation/resource operations;
- structured UI builders.
