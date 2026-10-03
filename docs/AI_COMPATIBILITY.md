# AI compatibility

## Principle

Nexora Godot MCP is an MCP server, not an AI provider.

The same Godot tool surface is exposed regardless of which compatible model host calls it.

## Hosted model APIs

A compatible application or agent can connect hosted models to Nexora Godot MCP.

Provider API credentials belong to that host/application, not to the Godot execution layer.

Nexora Godot MCP itself does not need a GPT, Claude, DeepSeek, Grok or other provider key to manipulate Godot.

## Local AI

Local models work when the surrounding local application implements MCP client behavior.

```text
Local inference runtime
        │
Local agent / MCP host
        │
        └── MCP → Nexora Godot MCP → Godot
```

A raw local inference HTTP endpoint is not automatically an MCP client.

## Multiple independent MCP servers

A host may connect to both projects simultaneously:

```text
MCP Host
├── Nexora Forge MCP
└── Nexora Godot MCP
```

They remain separate servers.

The host sees separate tool catalogs and chooses between them.

Examples:

```text
"Make the zombie mesh thinner."
→ Nexora Forge MCP

"Add this imported zombie to the enemy scene and configure NavigationAgent3D."
→ Nexora Godot MCP
```

## Routing quality

Tool descriptions deliberately use Godot-specific terms such as:

- scene;
- node;
- CharacterBody;
- GDScript;
- Godot project;
- export preset.

This is preferable to vague cross-application descriptions such as "create object".

## Connection modes

### Local MCP client

Use:

```env
NEXORA_GODOT_AUTH_MODE=local
```

The gateway must remain on loopback.

### Private Streamable HTTP

Use static bearer mode with a strong generated token.

### OAuth resource server

OAuth mode supports token introspection and Godot scopes when a compatible remote deployment requires it.

## Stateless operation

Runtime tasks return explicit handles such as `run_id`.

The server does not depend on hidden transport-session state for a running game.
