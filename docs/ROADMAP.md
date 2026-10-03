# Roadmap

The roadmap is organized by capability phases. Features are only marked complete when implementation and validation exist.

## Phase A — Foundation

Status: **complete in main**

- Python package and MCP server;
- Streamable HTTP gateway;
- local/static/OAuth configuration foundation;
- permission profiles;
- transport security;
- audit log;
- project-root confinement;
- Godot CLI runner;
- managed runtime handles;
- export preset parser;
- Godot EditorPlugin;
- loopback TCP bridge;
- independent bridge secret;
- plugin dock;
- setup/doctor/status/start CLI;
- source-based addon installer;
- CI for Python plus Godot 4.6.3 addon smoke test.

Initial MCP tools:

- status/capabilities;
- project inspect/validate/import;
- scene snapshot/open/save/create;
- node create/set/delete;
- script read/create/revision replacement;
- project run/status/logs/stop;
- export presets/debug/release/pack;
- batch editor execution.

## Phase B — Scene and node production

Status: **implemented**

- editor Undo/Redo integration for node creation, deletion, rename, reparent, property changes and transforms;
- safer scene lifecycle inspection, reload and close flows;
- scene creation with explicit replacement/discard gates;
- scene duplication;
- PackedScene instancing;
- scene dependency inspection;
- node rename/reparent;
- 2D local/global transform tools;
- 3D local/global transform tools;
- owner repair for generated scene subtrees;
- Resource inspection with bounded stored-property serialization;
- editor filesystem status;
- filesystem rescan;
- bounded resource reimport.

## Phase C — Code, signals and input

- revision-aware patch operations;
- attach/detach scripts;
- structured script diagnostics;
- script symbols;
- signals;
- Input Map tools;
- project settings/autoload tools.

## Phase D — UI and 2D

- Control creation;
- container layouts;
- anchors/offsets;
- themes;
- common HUD/menu workflows;
- Sprite2D/AnimatedSprite2D;
- TileMap/TileMapLayer;
- Camera2D;
- 2D collision.

## Phase E — 3D and gameplay structures

- MeshInstance3D;
- Camera3D;
- light creation;
- WorldEnvironment;
- collisions;
- physics bodies;
- areas;
- Skeleton3D inspection.

Godot MCP will configure game-engine structures; it will not replace Forge for 3D modeling.

## Phase F — Navigation and animation

- NavigationRegion;
- NavigationAgent;
- NavigationLink;
- AnimationPlayer;
- animation resources/tracks/keys;
- AnimationTree/state machines.

## Phase G — Audio, shaders and materials

- audio buses;
- audio players;
- stream assignment;
- shaders;
- shader validation;
- StandardMaterial3D;
- ShaderMaterial;
- CanvasItem materials.

## Phase H — Debugging, screenshots and performance

- debugger integration;
- structured parser/runtime errors;
- screenshot MCP image content;
- performance snapshots;
- smoke-test workflows.

## Phase I — Installer and local control center

- background lifecycle service;
- multi-project registry;
- project add/remove/list;
- automatic update command;
- logs command;
- Windows installer;
- Linux/macOS packaging;
- local web control center.

## Phase J — Release hardening

- complete tool-schema tests;
- security regression suite;
- versioned addon compatibility;
- release artifacts;
- checksums;
- signed/reproducible distribution where practical;
- complete user installation guide;
- public 1.0 release criteria.
