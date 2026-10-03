# Installer and local setup

Phase A includes a source-based local setup command.

## Requirements

- Python 3.11+
- `uv`
- Godot 4.6+ editor binary
- an existing Godot project containing `project.godot`

## Install dependencies

```bash
git clone https://github.com/Gh0stDeveloper/Nexora-Godot-MCP.git
cd Nexora-Godot-MCP
uv sync --all-extras
```

## Configure a project

```bash
uv run nexora-godot setup --project /path/to/MyGame
```

Custom Godot binary:

```bash
uv run nexora-godot setup \
  --project /path/to/MyGame \
  --godot /path/to/godot
```

## What setup does

The command:

1. validates that `project.godot` exists;
2. generates a public MCP bearer token;
3. generates a different editor bridge secret;
4. writes the MCP repository `.env`;
5. installs the packaged editor addon into the target project;
6. writes `.nexora-godot/bridge.json` inside the project;
7. adds `.nexora-godot/` to the project's `.gitignore`;
8. enables the plugin through `project.godot`.

On Unix-like systems secret files are created with private file permissions where supported.

## Start Godot

Open or restart the configured project in Godot.

The enabled plugin reads its local bridge configuration and starts:

```text
127.0.0.1:9877
```

The dock should report **Bridge: Running**.

## Run diagnostics

```bash
uv run nexora-godot doctor
```

Current checks:

- `project.godot`;
- installed addon;
- local bridge configuration;
- Godot CLI version;
- MCP gateway status;
- editor bridge socket.

The gateway check will be offline until the MCP server is started.

## Start the MCP gateway

```bash
uv run nexora-godot start
```

Default MCP endpoint:

```text
http://127.0.0.1:8775/mcp
```

Default health endpoint:

```text
http://127.0.0.1:8775/health
```

## Show status

In another terminal:

```bash
uv run nexora-godot status
```

## Current Phase A limitation

`start` runs the gateway in the foreground.

Later installer phases will add background lifecycle management:

```text
nexora-godot start
nexora-godot stop
nexora-godot status
nexora-godot logs
nexora-godot update
nexora-godot project add
nexora-godot project list
```

The initial implementation favors a small verifiable core over pretending those lifecycle commands are already complete.

## Manual configuration

See `.env.example`.

The most important values are:

```env
NEXORA_GODOT_PROJECT_ROOT=/path/to/MyGame
NEXORA_GODOT_GODOT_BINARY=godot
NEXORA_GODOT_BRIDGE_SECRET=...
NEXORA_GODOT_PUBLIC_TOKEN=...
```

Keep the public token and bridge secret different.
