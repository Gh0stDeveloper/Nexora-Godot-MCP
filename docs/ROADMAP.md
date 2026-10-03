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

Status: **implemented**

- SHA-256 guarded exact-match script patch operations with atomic file replacement;
- GDScript parser diagnostics through Godot's `--check-only --script` flow;
- script symbol inspection from Godot Script resources;
- undoable script attach/detach;
- signal listing and connection inspection;
- undoable persistent signal connect/disconnect;
- Input Map action list/create/delete/deadzone management;
- structured key/mouse/joypad event add/remove with project persistence;
- bounded ProjectSettings read/set/clear;
- protected Input Map/autoload/editor-plugin namespaces;
- autoload singleton list/add/remove;
- Phase C Godot 4.6.3 editor smoke coverage.

## Phase D — UI and 2D

Status: **implemented**

- Control-derived node creation;
- supported Container creation, including GridContainer columns;
- responsive anchors/offsets through explicit values and common layout presets;
- Theme resource assignment, type variations and bounded local overrides;
- undoable text editing for supported Controls;
- common HUD scaffold generation;
- common centered menu scaffold generation;
- Sprite2D creation with project-local textures and sprite-sheet frames;
- AnimatedSprite2D + SpriteFrames creation with bounded animation/frame lists;
- TileMapLayer creation with existing or empty TileSet resources;
- TileSetAtlasSource creation from project-local textures with bounded atlas-tile selection;
- TileMapLayer and legacy TileMap inspection;
- undoable TileMap cell editing with explicit erase confirmation;
- Camera2D creation with zoom, smoothing and limits;
- CollisionShape2D creation with structured Shape2D definitions;
- StaticBody2D/CharacterBody2D/RigidBody2D/Area2D collision workflow creation;
- Phase D Godot 4.6.3 editor smoke coverage.

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
