# Contributing

Contributions are welcome when they preserve Nexora Godot MCP's dedicated, local-first architecture.

## Principles

- Prefer typed Godot tools over arbitrary scripting.
- Keep the editor bridge loopback-only.
- Do not combine Forge into this server.
- Do not add AI-provider coupling to the Godot execution layer.
- Do not send project telemetry externally by default.
- Keep destructive actions explicit.
- Preserve project-root confinement.
- Add tests for security/validation boundaries.
- Keep documentation aligned with actual implementation.

## New MCP tools

A tool contribution should document:

- purpose;
- input schema;
- output;
- permission profile;
- whether it mutates state;
- whether it is destructive;
- bridge vs CLI execution path;
- expected error cases.

Tool names/descriptions should be Godot-specific so MCP hosts can route correctly when multiple servers are connected.

## Godot addon changes

Test against the supported Godot 4.6+ baseline.

The CI fixture currently uses Godot 4.6.3 to parse/load the addon.

Editor operations should avoid silently discarding unsaved human work.

## Pull requests

Use focused pull requests and clear conventional commit messages.

Required checks should be green before merge:

- Ruff;
- Mypy;
- Pytest;
- Python compilation;
- Godot addon smoke validation.
