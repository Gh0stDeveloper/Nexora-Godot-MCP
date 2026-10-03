# Local web control center design

The web UI is a future optional local/private control surface.

It is not a hosted SaaS dashboard.

## Visual direction

- graphite/near-black background;
- Godot blue primary accent;
- restrained connected-state cyan;
- amber warnings;
- red only for errors/destructive actions;
- compact cards;
- subtle borders;
- responsive layout;
- minimal blur;
- icons instead of decorative emoji in the product UI.

## Header

```text
NEXORA GODOT
[Project ▼]        Gateway ●   Editor ●   Runtime ○
```

Navigation:

- Overview
- Scene
- Runtime
- Errors
- Exports
- Settings

## Overview

Show operational information only:

- selected project;
- Godot version;
- current scene;
- gateway status;
- editor bridge status;
- current runtime;
- permission profile;
- latest operations;
- active errors/warnings.

Avoid vanity metrics.

## Scene

The panel is not a replacement for Godot's Scene dock.

It should provide a compact structural preview and shortcuts to structured MCP actions.

## Runtime

- Run project
- Run current scene
- Stop
- stdout/stderr
- latest errors
- duration
- screenshot when implemented

## Errors

Group diagnostics by:

- parser errors;
- runtime errors;
- warnings;
- import errors;
- export failures.

File and line should be shown when known.

## Exports

Display presets and readiness without exposing secret signing credentials.

## Settings

- registered projects;
- Godot executable;
- gateway endpoint;
- bridge endpoint;
- permission profile;
- logs;
- update status;
- unrestricted-mode warning.

## Credits

Footer:

- Ghost Developer;
- GitHub profile;
- repository;
- ghostnexora@gmail.com;
- @Gh0stDeveloper on Telegram.

## Tone

Copy should read as product documentation written by the project's maintainer, consistent with Nexora Forge.
