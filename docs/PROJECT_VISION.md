# Project vision

## Purpose

I created **Nexora Godot MCP** as a dedicated Model Context Protocol server for Godot Engine.

It is intentionally separate from Nexora Forge MCP.

```text
AI / MCP Host
├── Nexora Forge MCP  → Blender
└── Nexora Godot MCP  → Godot
```

The AI host decides which independent MCP server is appropriate for the task. Nexora Godot MCP does not route Blender work, embed Forge, or try to become a generic all-in-one computer-control server.

## What I want the project to solve

Normal AI assistance often stops at instructions such as:

> Create a CharacterBody3D, attach this script, configure the collision and run the project.

Nexora Godot MCP is designed to turn that into an auditable production workflow:

```text
AI
 ↓
inspect project
 ↓
inspect scene
 ↓
create/configure nodes
 ↓
create or revise scripts
 ↓
save scene
 ↓
validate project
 ↓
run
 ↓
collect logs
 ↓
export
```

The developer remains in control of the local project and can inspect every source change.

## Product principles

### Dedicated

Every tool description should clearly refer to Godot concepts. This improves MCP routing when a host has multiple servers connected.

### Local-first

The editor, source files, runtime and export artifacts stay on infrastructure controlled by the user.

### Self-hosted

There is no required Nexora account, subscription or central hosted service.

### Provider-neutral

The MCP server does not require OpenAI, Anthropic, DeepSeek, xAI, Ollama or any other provider.

Hosted and local models are supported by the MCP host surrounding the model.

### Structured first

The normal API is made of explicit Godot operations instead of a raw shell endpoint.

### Human-controlled

Destructive actions require explicit intent and high-risk capabilities remain disabled by default.

### Auditable

Gateway activity is recorded in a sanitized JSONL audit log.

### Free and open source

The project is released under MIT and is intended to remain usable without a mandatory paid Nexora service.

## Non-goals

Nexora Godot MCP is not:

- a Blender modeling server;
- a replacement for Nexora Forge MCP;
- an AI model provider;
- a public hosted game-development service;
- a remote desktop implementation;
- an unrestricted shell by default;
- a replacement for Godot's editor UI.

The editor remains the primary human development environment. The MCP server adds a structured automation surface around it.
