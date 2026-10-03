# Local models

Nexora Godot MCP is designed to work with local AI without embedding a specific model runtime.

## Required architecture

```text
Local model
   │
MCP-capable host / agent
   │
Nexora Godot MCP
   │
Godot
```

The important component is the **MCP-capable host**.

A model served by Ollama, llama.cpp or another local inference runtime still needs an application that can:

- discover MCP tools;
- decide when to call them;
- validate tool arguments;
- send MCP requests;
- feed tool results back to the model.

## No mandatory cloud

The Godot bridge, source files and MCP gateway can all remain local.

If both the model and its host are local, the entire development loop can remain on the workstation.

## Same safety model

Local models do not bypass server permissions.

The server still enforces:

- project-root confinement;
- safe/standard/unrestricted profiles;
- destructive-operation requirements;
- bridge secret validation;
- CLI allowlists;
- audit logging.

## Model size

Nexora Godot MCP does not impose a minimum model size.

Smaller models may need stronger system instructions or more explicit task decomposition, but the server-side schemas remain identical.
