from __future__ import annotations

import asyncio
import hashlib
import logging
import uuid
from pathlib import Path
from typing import Any, Literal

import uvicorn
from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.server.auth.settings import AuthSettings
from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations
from pydantic import AnyHttpUrl
from starlette.requests import Request
from starlette.responses import JSONResponse

from .audit import AuditLogger
from .auth import IntrospectionTokenVerifier
from .bridge import GodotBridgeClient, GodotBridgeError
from .config import get_settings
from .runner import GodotCliError, GodotCliRunner
from .script_ops import ScriptPatchError, apply_revision_patch, parse_godot_diagnostics
from .security import BearerTokenMiddleware

logger = logging.getLogger("nexora_godot_mcp")

settings = get_settings()
audit = AuditLogger(settings.audit_log)
bridge = GodotBridgeClient(
    host=settings.bridge_host,
    port=settings.bridge_port,
    secret=settings.bridge_secret,
    timeout_seconds=settings.request_timeout_seconds,
)
runner = GodotCliRunner(
    binary=settings.godot_binary,
    project_root=settings.resolved_project_root,
    runtime_log_dir=settings.runtime_log_dir,
    timeout_seconds=settings.request_timeout_seconds,
)


def _create_mcp() -> Any:
    instructions = (
        "This server controls Godot projects only. Do not use it for Blender modeling. "
        "Prefer structured Godot tools, inspect the current project/scene before edits, "
        "validate after script or scene changes, and use explicit run IDs for runtime work. "
        "The MCP host decides whether Nexora Godot MCP or another independent MCP server is appropriate."
    )
    if settings.auth_mode == "oauth":
        return MCPServer(
            "Nexora Godot MCP",
            title="Nexora Godot MCP",
            description="Secure local-first AI-native Godot development gateway",
            version="0.4.0",
            instructions=instructions,
            token_verifier=IntrospectionTokenVerifier(settings),
            auth=AuthSettings(
                issuer_url=AnyHttpUrl(settings.oauth_issuer_url),
                resource_server_url=AnyHttpUrl(settings.oauth_resource_url),
                required_scopes=settings.oauth_scope_list(),
                validate_token_resource=True,
            ),
        )
    return MCPServer(
        "Nexora Godot MCP",
        title="Nexora Godot MCP",
        description="Secure local-first AI-native Godot development gateway",
        version="0.4.0",
        instructions=instructions,
    )


mcp = _create_mcp()

READ_ONLY = ToolAnnotations(
    read_only_hint=True,
    destructive_hint=False,
    idempotent_hint=True,
    open_world_hint=False,
)
WRITE_TOOL = ToolAnnotations(
    read_only_hint=False,
    destructive_hint=False,
    idempotent_hint=False,
    open_world_hint=False,
)
DESTRUCTIVE_TOOL = ToolAnnotations(
    read_only_hint=False,
    destructive_hint=True,
    idempotent_hint=False,
    open_world_hint=False,
)


def _assert_permission(*, mutating: bool = False, unrestricted: bool = False) -> None:
    profile = settings.permission_profile
    if mutating and profile == "safe":
        raise PermissionError("This operation is disabled by the safe permission profile")
    if unrestricted and profile != "unrestricted":
        raise PermissionError(
            "This operation requires NEXORA_GODOT_PERMISSION_PROFILE=unrestricted"
        )
    if unrestricted and not settings.allow_editor_script:
        raise PermissionError(
            "Set NEXORA_GODOT_ALLOW_EDITOR_SCRIPT=true to enable unrestricted editor scripting"
        )

    if settings.auth_mode == "oauth":
        token = get_access_token()
        if token is None:
            raise PermissionError("Authenticated OAuth context is required")
        scopes = set(token.scopes)
        needed = "godot:write" if mutating else "godot:read"
        if needed not in scopes:
            raise PermissionError(f"OAuth token is missing required scope: {needed}")
        if unrestricted and "godot:script" not in scopes:
            raise PermissionError("OAuth token is missing required scope: godot:script")


def _project_file(raw_path: str, *, must_exist: bool = False) -> Path:
    root = settings.resolved_project_root
    candidate_text = raw_path.removeprefix("res://")
    candidate = Path(candidate_text).expanduser()
    if not candidate.is_absolute():
        candidate = root / candidate
    candidate = candidate.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise PermissionError(f"Path must stay inside Godot project root: {root}") from exc
    if must_exist and not candidate.exists():
        raise FileNotFoundError(str(candidate))
    return candidate


def _resource_path(raw_path: str, *, must_exist: bool = False) -> str:
    candidate = _project_file(raw_path, must_exist=must_exist)
    relative = candidate.relative_to(settings.resolved_project_root).as_posix()
    return f"res://{relative}"


async def _call_bridge(
    operation: str,
    params: dict[str, Any] | None = None,
    *,
    mutating: bool = False,
) -> dict[str, Any]:
    _assert_permission(mutating=mutating)
    request_id = str(uuid.uuid4())
    payload = params or {}
    try:
        result = await bridge.execute(
            operation=operation,
            params=payload,
            request_id=request_id,
        )
    except Exception as exc:
        audit.write(
            request_id=request_id,
            operation=operation,
            params=payload,
            status="error",
            detail=str(exc),
        )
        raise
    audit.write(
        request_id=request_id,
        operation=operation,
        params=payload,
        status="ok",
    )
    return result


def _audit_cli(
    *,
    operation: str,
    params: dict[str, Any],
    status: str,
    detail: str | None = None,
) -> str:
    request_id = str(uuid.uuid4())
    audit.write(
        request_id=request_id,
        operation=operation,
        params=params,
        status=status,
        detail=detail,
    )
    return request_id


@mcp.custom_route("/health", methods=["GET"])  # type: ignore[untyped-decorator]
async def health(_: Request) -> JSONResponse:
    try:
        bridge_data = await bridge.health()
        bridge_status = "online"
    except GodotBridgeError:
        bridge_data = {}
        bridge_status = "offline"

    try:
        godot_version = await runner.version()
        cli_status = "online"
    except GodotCliError:
        godot_version = None
        cli_status = "offline"

    return JSONResponse(
        {
            "service": "Nexora Godot MCP",
            "version": "0.4.0",
            "status": "ok",
            "auth_mode": settings.auth_mode,
            "permission_profile": settings.permission_profile,
            "bridge_status": bridge_status,
            "cli_status": cli_status,
            "godot_version": godot_version,
            "editor": bridge_data.get("result", {}),
        }
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def godot_status() -> dict[str, Any]:
    """Return Godot CLI and editor bridge status for the configured Godot project."""
    bridge_result: dict[str, Any]
    try:
        bridge_result = await bridge.health()
    except GodotBridgeError as exc:
        bridge_result = {"error": str(exc)}
    try:
        version: str | None = await runner.version()
    except GodotCliError:
        version = None
    return {
        "name": "Nexora Godot MCP",
        "version": "0.4.0",
        "godot_version": version,
        "project_root": str(settings.resolved_project_root),
        "bridge": bridge_result,
    }


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def project_inspect() -> dict[str, Any]:
    """Inspect the configured Godot project without changing source files."""
    root = settings.resolved_project_root
    project_file = root / "project.godot"
    if not project_file.is_file():
        raise FileNotFoundError(f"project.godot not found: {project_file}")
    text = project_file.read_text(encoding="utf-8", errors="replace")
    return {
        "root": str(root),
        "project_file": str(project_file),
        "project_file_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "project_file_size": len(text.encode("utf-8")),
        "has_export_presets": (root / "export_presets.cfg").is_file(),
        "permission_profile": settings.permission_profile,
    }


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def project_validate() -> dict[str, Any]:
    """Open the configured project headlessly for one editor iteration and return diagnostics."""
    _assert_permission()
    params = {"project_root": str(settings.resolved_project_root)}
    try:
        result = await runner.validate_project()
    except Exception as exc:
        request_id = _audit_cli(
            operation="project.validate",
            params=params,
            status="error",
            detail=str(exc),
        )
        raise
    request_id = _audit_cli(
        operation="project.validate",
        params=params,
        status="ok" if result.returncode == 0 else "error",
        detail=result.stderr[-500:] if result.returncode else None,
    )
    return {"request_id": request_id, **result.as_dict()}


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def project_import() -> dict[str, Any]:
    """Run Godot's documented headless import flow for the configured project."""
    _assert_permission(mutating=True)
    result = await runner.import_project()
    request_id = _audit_cli(
        operation="project.import",
        params={},
        status="ok" if result.returncode == 0 else "error",
        detail=result.stderr[-500:] if result.returncode else None,
    )
    return {"request_id": request_id, **result.as_dict()}


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def scene_snapshot(max_nodes: int = 500) -> dict[str, Any]:
    """Inspect the currently edited Godot scene tree."""
    if not 1 <= max_nodes <= 2000:
        raise ValueError("max_nodes must be between 1 and 2000")
    return await _call_bridge("scene.snapshot", {"max_nodes": max_nodes})


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def scene_open(path: str) -> dict[str, Any]:
    """Open an existing .tscn/.scn scene inside the configured Godot project."""
    resource_path = _resource_path(path, must_exist=True)
    if not resource_path.lower().endswith((".tscn", ".scn")):
        raise ValueError("scene_open accepts .tscn or .scn files")
    return await _call_bridge(
        "scene.open",
        {"path": resource_path},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def scene_save(path: str | None = None) -> dict[str, Any]:
    """Save the current scene, optionally to a project-confined path."""
    params: dict[str, Any] = {}
    if path:
        resource_path = _resource_path(path)
        if not resource_path.lower().endswith(".tscn"):
            raise ValueError("New scene paths must use .tscn")
        params["path"] = resource_path
    return await _call_bridge("scene.save", params, mutating=True)


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def scene_create(
    root_type: str,
    name: str,
    path: str,
    open_after_create: bool = True,
    overwrite: bool = False,
) -> dict[str, Any]:
    """Create a PackedScene resource without discarding the currently edited scene."""
    resource_path = _resource_path(path)
    if not resource_path.lower().endswith(".tscn"):
        raise ValueError("scene_create path must end in .tscn")
    return await _call_bridge(
        "scene.create",
        {
            "root_type": root_type,
            "name": name,
            "path": resource_path,
            "open_after_create": open_after_create,
            "overwrite": overwrite,
        },
        mutating=True,
    )





@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def scene_open_scenes() -> dict[str, Any]:
    """List open Godot editor scenes and the active scene."""
    return await _call_bridge("scene.open_scenes")


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def scene_reload(confirm_discard: bool = False) -> dict[str, Any]:
    """Reload the active scene from disk. confirm_discard=true is always required."""
    return await _call_bridge(
        "scene.reload",
        {"confirm_discard": confirm_discard},
        mutating=True,
    )


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def scene_close(confirm_discard: bool = False) -> dict[str, Any]:
    """Close the active scene. confirm_discard=true is always required."""
    return await _call_bridge(
        "scene.close",
        {"confirm_discard": confirm_discard},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def scene_duplicate(
    source_path: str,
    destination_path: str,
    overwrite: bool = False,
) -> dict[str, Any]:
    """Duplicate a PackedScene resource inside the configured Godot project."""
    source = _resource_path(source_path, must_exist=True)
    destination = _resource_path(destination_path)
    if not source.lower().endswith((".tscn", ".scn")):
        raise ValueError("source_path must be a .tscn or .scn scene")
    if not destination.lower().endswith((".tscn", ".scn")):
        raise ValueError("destination_path must be a .tscn or .scn scene")
    return await _call_bridge(
        "scene.duplicate",
        {
            "source_path": source,
            "destination_path": destination,
            "overwrite": overwrite,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def scene_instantiate(
    scene_path: str,
    parent_path: str = ".",
    name: str | None = None,
) -> dict[str, Any]:
    """Instantiate a PackedScene below a node in the currently edited scene with editor undo support."""
    resource_path = _resource_path(scene_path, must_exist=True)
    if not resource_path.lower().endswith((".tscn", ".scn")):
        raise ValueError("scene_path must be a .tscn or .scn scene")
    return await _call_bridge(
        "scene.instantiate",
        {
            "scene_path": resource_path,
            "parent_path": parent_path,
            "name": name or "",
        },
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def scene_dependencies(path: str) -> dict[str, Any]:
    """List external resource dependencies for a project-local Godot scene."""
    resource_path = _resource_path(path, must_exist=True)
    if not resource_path.lower().endswith((".tscn", ".scn")):
        raise ValueError("path must be a .tscn or .scn scene")
    return await _call_bridge(
        "scene.dependencies",
        {"path": resource_path},
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def node_create(
    parent_path: str,
    node_type: str,
    name: str,
    properties: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Create a Godot node below an existing parent in the edited scene."""
    return await _call_bridge(
        "node.create",
        {
            "parent_path": parent_path,
            "node_type": node_type,
            "name": name,
            "properties": properties or {},
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def node_set_properties(
    node_path: str,
    properties: dict[str, Any],
) -> dict[str, Any]:
    """Set validated Godot properties on a node in the edited scene."""
    if not properties:
        raise ValueError("properties cannot be empty")
    if len(properties) > 100:
        raise ValueError("A single call may change at most 100 properties")
    return await _call_bridge(
        "node.set_properties",
        {"node_path": node_path, "properties": properties},
        mutating=True,
    )


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def node_delete(node_path: str, confirm: bool = False) -> dict[str, Any]:
    """Delete a non-root node from the edited scene. confirm=true is required."""
    if not confirm:
        raise ValueError("confirm=true is required")
    return await _call_bridge(
        "node.delete",
        {"node_path": node_path},
        mutating=True,
    )





@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def node_rename(node_path: str, new_name: str) -> dict[str, Any]:
    """Rename a node in the edited scene and register the action with Godot editor undo/redo."""
    if not new_name.strip():
        raise ValueError("new_name cannot be empty")
    if "/" in new_name:
        raise ValueError("new_name cannot contain '/'")
    return await _call_bridge(
        "node.rename",
        {"node_path": node_path, "new_name": new_name},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def node_reparent(
    node_path: str,
    new_parent_path: str,
    new_index: int = -1,
) -> dict[str, Any]:
    """Reparent a non-root node while preserving its global transform and editor undo history."""
    if new_index < -1:
        raise ValueError("new_index must be -1 or greater")
    return await _call_bridge(
        "node.reparent",
        {
            "node_path": node_path,
            "new_parent_path": new_parent_path,
            "new_index": new_index,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def node_transform_2d(
    node_path: str,
    position: list[float] | None = None,
    rotation: float | None = None,
    scale: list[float] | None = None,
    skew: float | None = None,
    space: Literal["local", "global"] = "local",
) -> dict[str, Any]:
    """Set selected Node2D transform components in local or global space with undo/redo."""
    if position is not None and len(position) != 2:
        raise ValueError("position must contain exactly 2 numbers")
    if scale is not None and len(scale) != 2:
        raise ValueError("scale must contain exactly 2 numbers")
    if position is None and rotation is None and scale is None and skew is None:
        raise ValueError("At least one transform component is required")
    return await _call_bridge(
        "node.transform_2d",
        {
            "node_path": node_path,
            "position": position,
            "rotation": rotation,
            "scale": scale,
            "skew": skew,
            "space": space,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def node_transform_3d(
    node_path: str,
    position: list[float] | None = None,
    rotation: list[float] | None = None,
    scale: list[float] | None = None,
    space: Literal["local", "global"] = "local",
) -> dict[str, Any]:
    """Set selected Node3D transform components in local or global space with undo/redo."""
    for label, value in (
        ("position", position),
        ("rotation", rotation),
        ("scale", scale),
    ):
        if value is not None and len(value) != 3:
            raise ValueError(f"{label} must contain exactly 3 numbers")
    if position is None and rotation is None and scale is None:
        raise ValueError("At least one transform component is required")
    if scale is not None:
        numeric = [float(item) for item in scale]
        if any(abs(item) < 1e-8 for item in numeric):
            raise ValueError("3D scale components cannot be zero")
        all_positive = all(item > 0 for item in numeric)
        all_negative = all(item < 0 for item in numeric)
        if not (all_positive or all_negative):
            raise ValueError("Godot Node3D scale components must use the same sign")
    return await _call_bridge(
        "node.transform_3d",
        {
            "node_path": node_path,
            "position": position,
            "rotation": rotation,
            "scale": scale,
            "space": space,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def node_repair_owner(
    node_path: str = ".",
    recursive: bool = True,
    only_missing: bool = True,
) -> dict[str, Any]:
    """Repair scene ownership for a node/subtree so newly generated nodes persist when saved."""
    return await _call_bridge(
        "node.repair_owner",
        {
            "node_path": node_path,
            "recursive": recursive,
            "only_missing": only_missing,
        },
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def script_read(path: str) -> dict[str, Any]:
    """Read a GDScript or C# source file inside the configured Godot project."""
    target = _project_file(path, must_exist=True)
    if target.suffix.lower() not in {".gd", ".cs"}:
        raise ValueError("script_read supports .gd and .cs files")
    if target.stat().st_size > 2 * 1024 * 1024:
        raise ValueError("Script exceeds the 2 MiB read limit")
    content = target.read_text(encoding="utf-8", errors="replace")
    return {
        "path": _resource_path(path, must_exist=True),
        "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
        "content": content,
    }


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def script_create(
    path: str,
    content: str,
    overwrite: bool = False,
) -> dict[str, Any]:
    """Create a GDScript or C# source file inside the configured project."""
    _assert_permission(mutating=True)
    target = _project_file(path)
    if target.suffix.lower() not in {".gd", ".cs"}:
        raise ValueError("script_create supports .gd and .cs files")
    if len(content.encode("utf-8")) > 2 * 1024 * 1024:
        raise ValueError("Script exceeds the 2 MiB write limit")
    if target.exists() and not overwrite:
        raise FileExistsError(str(target))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    request_id = _audit_cli(
        operation="script.create",
        params={"path": _resource_path(path), "overwrite": overwrite},
        status="ok",
    )
    return {
        "request_id": request_id,
        "path": _resource_path(path, must_exist=True),
        "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
    }


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def script_replace(
    path: str,
    content: str,
    expected_sha256: str,
) -> dict[str, Any]:
    """Replace a script only when its current SHA-256 matches expected_sha256."""
    _assert_permission(mutating=True)
    target = _project_file(path, must_exist=True)
    if target.suffix.lower() not in {".gd", ".cs"}:
        raise ValueError("script_replace supports .gd and .cs files")
    current = target.read_text(encoding="utf-8", errors="replace")
    current_sha = hashlib.sha256(current.encode("utf-8")).hexdigest()
    if current_sha != expected_sha256:
        raise RuntimeError("script_revision_conflict")
    if len(content.encode("utf-8")) > 2 * 1024 * 1024:
        raise ValueError("Script exceeds the 2 MiB write limit")
    target.write_text(content, encoding="utf-8")
    new_sha = hashlib.sha256(content.encode("utf-8")).hexdigest()
    request_id = _audit_cli(
        operation="script.replace",
        params={"path": _resource_path(path), "expected_sha256": expected_sha256},
        status="ok",
    )
    return {
        "request_id": request_id,
        "path": _resource_path(path, must_exist=True),
        "sha256": new_sha,
    }







@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def script_patch(
    path: str,
    expected_sha256: str,
    patches: list[dict[str, Any]],
) -> dict[str, Any]:
    """Apply bounded exact-match patches only when the current script revision matches expected_sha256."""
    _assert_permission(mutating=True)
    target = _project_file(path, must_exist=True)
    if target.suffix.lower() not in {".gd", ".cs"}:
        raise ValueError("script_patch supports .gd and .cs files")
    try:
        result = await asyncio.to_thread(
            apply_revision_patch,
            target,
            expected_sha256=expected_sha256,
            patches=patches,
        )
    except ScriptPatchError as exc:
        raise RuntimeError(str(exc)) from exc
    request_id = _audit_cli(
        operation="script.patch",
        params={
            "path": _resource_path(path, must_exist=True),
            "expected_sha256": expected_sha256,
            "patch_count": len(patches),
        },
        status="ok",
    )
    return {
        "request_id": request_id,
        "path": _resource_path(path, must_exist=True),
        **result,
    }


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def script_check(path: str) -> dict[str, Any]:
    """Run Godot's GDScript parser and return structured diagnostics for one .gd script."""
    _assert_permission()
    target = _project_file(path, must_exist=True)
    if target.suffix.lower() != ".gd":
        raise ValueError("script_check currently supports GDScript (.gd)")
    result = await runner.check_script(target)
    diagnostics = parse_godot_diagnostics(result.stdout, result.stderr)
    valid = result.returncode == 0 and not any(
        item.get("severity") == "error" for item in diagnostics
    )
    request_id = _audit_cli(
        operation="script.check",
        params={"path": _resource_path(path, must_exist=True)},
        status="ok" if valid else "error",
        detail=result.stderr[-500:] if not valid else None,
    )
    return {
        "request_id": request_id,
        "path": _resource_path(path, must_exist=True),
        "valid": valid,
        "returncode": result.returncode,
        "diagnostics": diagnostics,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def script_symbols(path: str) -> dict[str, Any]:
    """Inspect methods, signals and properties exposed by a Godot Script resource."""
    resource_path = _resource_path(path, must_exist=True)
    if not resource_path.lower().endswith((".gd", ".cs")):
        raise ValueError("script_symbols supports .gd and .cs files")
    return await _call_bridge("script.symbols", {"path": resource_path})


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def script_attach(node_path: str, script_path: str) -> dict[str, Any]:
    """Attach a project-local Script resource to a node with editor Undo/Redo support."""
    resource_path = _resource_path(script_path, must_exist=True)
    if not resource_path.lower().endswith((".gd", ".cs")):
        raise ValueError("script_path must be a .gd or .cs file")
    return await _call_bridge(
        "script.attach",
        {"node_path": node_path, "script_path": resource_path},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def script_detach(node_path: str) -> dict[str, Any]:
    """Detach the current Script from a node with editor Undo/Redo support."""
    return await _call_bridge(
        "script.detach",
        {"node_path": node_path},
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def signal_list(node_path: str, include_connections: bool = True) -> dict[str, Any]:
    """List signals exposed by a node and optionally their current connections."""
    return await _call_bridge(
        "signal.list",
        {"node_path": node_path, "include_connections": include_connections},
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def signal_connections(node_path: str, signal_name: str) -> dict[str, Any]:
    """Inspect connections for one signal on a node."""
    if not signal_name.strip():
        raise ValueError("signal_name cannot be empty")
    return await _call_bridge(
        "signal.connections",
        {"node_path": node_path, "signal_name": signal_name},
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def signal_connect(
    source_path: str,
    signal_name: str,
    target_path: str,
    method: str,
    persist: bool = True,
    deferred: bool = False,
    one_shot: bool = False,
    reference_counted: bool = False,
) -> dict[str, Any]:
    """Connect a Godot signal to a target method with editor Undo/Redo support."""
    if not signal_name.strip() or not method.strip():
        raise ValueError("signal_name and method cannot be empty")
    return await _call_bridge(
        "signal.connect",
        {
            "source_path": source_path,
            "signal_name": signal_name,
            "target_path": target_path,
            "method": method,
            "persist": persist,
            "deferred": deferred,
            "one_shot": one_shot,
            "reference_counted": reference_counted,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def signal_disconnect(
    source_path: str,
    signal_name: str,
    target_path: str,
    method: str,
) -> dict[str, Any]:
    """Disconnect a Godot signal while keeping the change undoable in the editor."""
    if not signal_name.strip() or not method.strip():
        raise ValueError("signal_name and method cannot be empty")
    return await _call_bridge(
        "signal.disconnect",
        {
            "source_path": source_path,
            "signal_name": signal_name,
            "target_path": target_path,
            "method": method,
        },
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def input_actions_list() -> dict[str, Any]:
    """List Godot Input Map actions, deadzones and serialized input events."""
    return await _call_bridge("input.actions_list")


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def input_action_create(
    name: str,
    deadzone: float = 0.5,
) -> dict[str, Any]:
    """Create and persist a new Godot Input Map action."""
    if not name.strip():
        raise ValueError("name cannot be empty")
    if not 0.0 <= deadzone <= 1.0:
        raise ValueError("deadzone must be between 0 and 1")
    return await _call_bridge(
        "input.action_create",
        {"name": name, "deadzone": deadzone},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def input_action_set_deadzone(name: str, deadzone: float) -> dict[str, Any]:
    """Change and persist an existing Input Map action deadzone."""
    if not 0.0 <= deadzone <= 1.0:
        raise ValueError("deadzone must be between 0 and 1")
    return await _call_bridge(
        "input.action_set_deadzone",
        {"name": name, "deadzone": deadzone},
        mutating=True,
    )


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def input_action_delete(name: str, confirm: bool = False) -> dict[str, Any]:
    """Delete an Input Map action. confirm=true is required."""
    if not confirm:
        raise ValueError("confirm=true is required")
    return await _call_bridge(
        "input.action_delete",
        {"name": name},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def input_event_add(action: str, event: dict[str, Any]) -> dict[str, Any]:
    """Add and persist a structured key, mouse or joypad event to an Input Map action."""
    if not action.strip():
        raise ValueError("action cannot be empty")
    if not event:
        raise ValueError("event cannot be empty")
    return await _call_bridge(
        "input.event_add",
        {"action": action, "event": event},
        mutating=True,
    )


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def input_event_remove(
    action: str,
    index: int,
    confirm: bool = False,
) -> dict[str, Any]:
    """Remove one Input Map event by index. confirm=true is required."""
    if index < 0:
        raise ValueError("index must be >= 0")
    if not confirm:
        raise ValueError("confirm=true is required")
    return await _call_bridge(
        "input.event_remove",
        {"action": action, "index": index},
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def project_settings_read(
    keys: list[str] | None = None,
    prefix: str | None = None,
    max_results: int = 200,
) -> dict[str, Any]:
    """Read selected project settings or a bounded prefix-filtered subset."""
    if not 1 <= max_results <= 1000:
        raise ValueError("max_results must be between 1 and 1000")
    if keys is not None and len(keys) > 200:
        raise ValueError("At most 200 explicit setting keys may be read")
    return await _call_bridge(
        "project.settings_read",
        {"keys": keys or [], "prefix": prefix or "", "max_results": max_results},
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def project_settings_set(values: dict[str, Any]) -> dict[str, Any]:
    """Set and persist ordinary Godot ProjectSettings values outside Input Map and autoload namespaces."""
    if not values:
        raise ValueError("values cannot be empty")
    if len(values) > 100:
        raise ValueError("At most 100 project settings may be changed per call")
    if any(value is None for value in values.values()):
        raise ValueError("Use project_settings_clear to remove settings")
    return await _call_bridge(
        "project.settings_set",
        {"values": values},
        mutating=True,
    )


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def project_settings_clear(
    keys: list[str],
    confirm: bool = False,
) -> dict[str, Any]:
    """Remove persisted project settings. confirm=true is required."""
    if not keys or len(keys) > 100:
        raise ValueError("keys must contain between 1 and 100 settings")
    if not confirm:
        raise ValueError("confirm=true is required")
    return await _call_bridge(
        "project.settings_clear",
        {"keys": keys},
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def autoload_list() -> dict[str, Any]:
    """List project autoload singletons."""
    return await _call_bridge("autoload.list")


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def autoload_add(name: str, path: str) -> dict[str, Any]:
    """Add and persist a project-local autoload singleton."""
    if not name.strip():
        raise ValueError("name cannot be empty")
    resource_path = _resource_path(path, must_exist=True)
    if not resource_path.lower().endswith((".gd", ".cs", ".tscn", ".scn")):
        raise ValueError("autoload path must be a script or scene")
    return await _call_bridge(
        "autoload.add",
        {"name": name, "path": resource_path},
        mutating=True,
    )


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def autoload_remove(name: str, confirm: bool = False) -> dict[str, Any]:
    """Remove an autoload registration without deleting its source file. confirm=true is required."""
    if not confirm:
        raise ValueError("confirm=true is required")
    return await _call_bridge(
        "autoload.remove",
        {"name": name},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def ui_create_control(
    parent_path: str,
    control_type: str,
    name: str,
    text: str = "",
    minimum_size: list[float] | None = None,
    properties: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Create a Control-derived node with optional text, minimum size and safe properties."""
    if minimum_size is not None and len(minimum_size) != 2:
        raise ValueError("minimum_size must contain exactly 2 numbers")
    return await _call_bridge(
        "ui.control_create",
        {
            "parent_path": parent_path,
            "control_type": control_type,
            "name": name,
            "text": text,
            "minimum_size": minimum_size,
            "properties": properties or {},
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def ui_create_container(
    parent_path: str,
    container_type: str,
    name: str,
    columns: int = 1,
    minimum_size: list[float] | None = None,
    properties: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Create a supported Godot Container with editor Undo/Redo integration."""
    if not 1 <= columns <= 64:
        raise ValueError("columns must be between 1 and 64")
    if minimum_size is not None and len(minimum_size) != 2:
        raise ValueError("minimum_size must contain exactly 2 numbers")
    return await _call_bridge(
        "ui.container_create",
        {
            "parent_path": parent_path,
            "container_type": container_type,
            "name": name,
            "columns": columns,
            "minimum_size": minimum_size,
            "properties": properties or {},
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def ui_set_layout(
    node_path: str,
    preset: str = "",
    anchors: list[float] | None = None,
    offsets: list[float] | None = None,
    margin: float = 0.0,
    size: list[float] | None = None,
) -> dict[str, Any]:
    """Set responsive Control anchors/offsets directly or through a common layout preset."""
    if anchors is not None and len(anchors) != 4:
        raise ValueError("anchors must contain [left, top, right, bottom]")
    if offsets is not None and len(offsets) != 4:
        raise ValueError("offsets must contain [left, top, right, bottom]")
    if size is not None and len(size) != 2:
        raise ValueError("size must contain exactly 2 numbers")
    if not preset.strip() and anchors is None and offsets is None:
        raise ValueError("preset or anchors/offsets are required")
    return await _call_bridge(
        "ui.layout_set",
        {
            "node_path": node_path,
            "preset": preset,
            "anchors": anchors,
            "offsets": offsets,
            "margin": margin,
            "size": size,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def ui_theme_apply(
    node_path: str,
    theme_path: str | None = None,
    type_variation: str = "",
    colors: dict[str, list[float]] | None = None,
    font_sizes: dict[str, int] | None = None,
    constants: dict[str, int] | None = None,
) -> dict[str, Any]:
    """Apply a Theme resource/type variation and bounded local theme overrides to a Control."""
    resource_path = ""
    if theme_path:
        resource_path = _resource_path(theme_path, must_exist=True)
    return await _call_bridge(
        "ui.theme_apply",
        {
            "node_path": node_path,
            "theme_path": resource_path,
            "type_variation": type_variation,
            "colors": colors or {},
            "font_sizes": font_sizes or {},
            "constants": constants or {},
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def ui_text_set(node_path: str, text: str) -> dict[str, Any]:
    """Set the text property on a supported Godot Control with Undo/Redo."""
    return await _call_bridge(
        "ui.text_set",
        {"node_path": node_path, "text": text},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def ui_create_hud(
    parent_path: str = ".",
    name: str = "HUD",
    title: str = "",
    health_text: str = "Health: 100",
    objective_text: str = "",
) -> dict[str, Any]:
    """Create a compact CanvasLayer HUD scaffold with title, health and objective labels."""
    return await _call_bridge(
        "ui.hud_create",
        {
            "parent_path": parent_path,
            "name": name,
            "title": title,
            "health_text": health_text,
            "objective_text": objective_text,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def ui_create_menu(
    buttons: list[str | dict[str, Any]],
    parent_path: str = ".",
    name: str = "Menu",
    title: str = "Menu",
) -> dict[str, Any]:
    """Create a centered CanvasLayer menu scaffold with up to 20 buttons."""
    if len(buttons) > 20:
        raise ValueError("buttons may contain at most 20 entries")
    return await _call_bridge(
        "ui.menu_create",
        {
            "parent_path": parent_path,
            "name": name,
            "title": title,
            "buttons": buttons,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def sprite2d_create(
    parent_path: str,
    name: str,
    texture_path: str | None = None,
    position: list[float] | None = None,
    centered: bool = True,
    flip_h: bool = False,
    flip_v: bool = False,
    hframes: int = 1,
    vframes: int = 1,
    frame: int = 0,
) -> dict[str, Any]:
    """Create a Sprite2D using an optional project-local Texture2D resource."""
    if position is not None and len(position) != 2:
        raise ValueError("position must contain exactly 2 numbers")
    if not 1 <= hframes <= 1024 or not 1 <= vframes <= 1024:
        raise ValueError("hframes and vframes must be between 1 and 1024")
    resource_path = ""
    if texture_path:
        resource_path = _resource_path(texture_path, must_exist=True)
    return await _call_bridge(
        "sprite2d.create",
        {
            "parent_path": parent_path,
            "name": name,
            "texture_path": resource_path,
            "position": position,
            "centered": centered,
            "flip_h": flip_h,
            "flip_v": flip_v,
            "hframes": hframes,
            "vframes": vframes,
            "frame": frame,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def animated_sprite2d_create(
    parent_path: str,
    name: str,
    animations: list[dict[str, Any]],
    initial_animation: str | None = None,
    autoplay: bool = False,
    position: list[float] | None = None,
    speed_scale: float = 1.0,
    flip_h: bool = False,
    flip_v: bool = False,
) -> dict[str, Any]:
    """Create AnimatedSprite2D and SpriteFrames from project-local texture frame lists."""
    if not 1 <= len(animations) <= 32:
        raise ValueError("animations must contain between 1 and 32 entries")
    if position is not None and len(position) != 2:
        raise ValueError("position must contain exactly 2 numbers")
    normalized: list[dict[str, Any]] = []
    total_frames = 0
    for animation in animations:
        frame_paths = animation.get("frames")
        if not isinstance(frame_paths, list) or not frame_paths:
            raise ValueError("each animation requires a non-empty frames list")
        total_frames += len(frame_paths)
        if total_frames > 256:
            raise ValueError("A create call may contain at most 256 animation frames")
        normalized.append(
            {
                **animation,
                "frames": [
                    _resource_path(str(path), must_exist=True) for path in frame_paths
                ],
            }
        )
    return await _call_bridge(
        "animated_sprite2d.create",
        {
            "parent_path": parent_path,
            "name": name,
            "animations": normalized,
            "initial_animation": initial_animation or "",
            "autoplay": autoplay,
            "position": position,
            "speed_scale": speed_scale,
            "flip_h": flip_h,
            "flip_v": flip_v,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def tilemap_layer_create(
    parent_path: str,
    name: str,
    tile_set_path: str | None = None,
    create_empty_tileset: bool = True,
    tile_size: list[int] | None = None,
    position: list[float] | None = None,
) -> dict[str, Any]:
    """Create a TileMapLayer with an existing TileSet or a new empty TileSet."""
    if tile_size is not None and len(tile_size) != 2:
        raise ValueError("tile_size must contain exactly 2 integers")
    if position is not None and len(position) != 2:
        raise ValueError("position must contain exactly 2 numbers")
    resource_path = ""
    if tile_set_path:
        resource_path = _resource_path(tile_set_path, must_exist=True)
    return await _call_bridge(
        "tilemap_layer.create",
        {
            "parent_path": parent_path,
            "name": name,
            "tile_set_path": resource_path,
            "create_empty_tileset": create_empty_tileset,
            "tile_size": tile_size,
            "position": position,
        },
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def tilemap_inspect(
    node_path: str,
    layer: int = 0,
    max_cells: int = 500,
) -> dict[str, Any]:
    """Inspect a TileMapLayer or legacy TileMap and return bounded used-cell data."""
    if layer < 0:
        raise ValueError("layer must be >= 0")
    if not 1 <= max_cells <= 2000:
        raise ValueError("max_cells must be between 1 and 2000")
    return await _call_bridge(
        "tilemap.inspect",
        {"node_path": node_path, "layer": layer, "max_cells": max_cells},
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def tileset_atlas_source_add(
    node_path: str,
    texture_path: str,
    texture_region_size: list[int],
    tiles: list[list[int]],
    source_id: int = -1,
) -> dict[str, Any]:
    """Add a TileSetAtlasSource and selected atlas tiles to a TileMap node's TileSet."""
    if len(texture_region_size) != 2:
        raise ValueError("texture_region_size must contain exactly 2 integers")
    if not 1 <= len(tiles) <= 256:
        raise ValueError("tiles must contain between 1 and 256 atlas coordinates")
    if any(len(coords) != 2 for coords in tiles):
        raise ValueError("each tile atlas coordinate must contain exactly 2 integers")
    resource_path = _resource_path(texture_path, must_exist=True)
    return await _call_bridge(
        "tileset.atlas_source_add",
        {
            "node_path": node_path,
            "texture_path": resource_path,
            "texture_region_size": texture_region_size,
            "tiles": tiles,
            "source_id": source_id,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def tilemap_set_cells(
    node_path: str,
    cells: list[dict[str, Any]],
    layer: int = 0,
    confirm_erase: bool = False,
) -> dict[str, Any]:
    """Set up to 500 TileMap cells with Undo/Redo. Erasing cells requires confirm_erase=true."""
    if layer < 0:
        raise ValueError("layer must be >= 0")
    if not 1 <= len(cells) <= 500:
        raise ValueError("cells must contain between 1 and 500 entries")
    if any(int(cell.get("source_id", -1)) < 0 for cell in cells) and not confirm_erase:
        raise ValueError("confirm_erase=true is required when any source_id is -1")
    return await _call_bridge(
        "tilemap.set_cells",
        {
            "node_path": node_path,
            "layer": layer,
            "cells": cells,
            "confirm_erase": confirm_erase,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def camera2d_create(
    parent_path: str,
    name: str,
    position: list[float] | None = None,
    zoom: list[float] | None = None,
    enabled: bool = True,
    position_smoothing_enabled: bool = False,
    position_smoothing_speed: float = 5.0,
    limits: list[float] | None = None,
) -> dict[str, Any]:
    """Create a Camera2D with position, zoom, smoothing and optional limits."""
    for label, value, expected in (
        ("position", position, 2),
        ("zoom", zoom, 2),
        ("limits", limits, 4),
    ):
        if value is not None and len(value) != expected:
            raise ValueError(f"{label} must contain exactly {expected} numbers")
    return await _call_bridge(
        "camera2d.create",
        {
            "parent_path": parent_path,
            "name": name,
            "position": position,
            "zoom": zoom,
            "enabled": enabled,
            "position_smoothing_enabled": position_smoothing_enabled,
            "position_smoothing_speed": position_smoothing_speed,
            "limits": limits,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def collision2d_shape_create(
    parent_path: str,
    shape: dict[str, Any],
    name: str = "CollisionShape2D",
    position: list[float] | None = None,
    disabled: bool = False,
    one_way_collision: bool = False,
    one_way_collision_margin: float = 1.0,
) -> dict[str, Any]:
    """Create CollisionShape2D below an existing CollisionObject2D using a structured shape definition."""
    if position is not None and len(position) != 2:
        raise ValueError("position must contain exactly 2 numbers")
    if not shape:
        raise ValueError("shape cannot be empty")
    return await _call_bridge(
        "collision2d.shape_create",
        {
            "parent_path": parent_path,
            "name": name,
            "shape": shape,
            "position": position,
            "disabled": disabled,
            "one_way_collision": one_way_collision,
            "one_way_collision_margin": one_way_collision_margin,
        },
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def collision2d_body_create(
    parent_path: str,
    body_type: Literal["StaticBody2D", "CharacterBody2D", "RigidBody2D", "Area2D"],
    name: str,
    shape: dict[str, Any],
    position: list[float] | None = None,
    collision_layer: int = 1,
    collision_mask: int = 1,
    monitoring: bool = True,
    monitorable: bool = True,
) -> dict[str, Any]:
    """Create a supported CollisionObject2D body/area with a child CollisionShape2D."""
    if position is not None and len(position) != 2:
        raise ValueError("position must contain exactly 2 numbers")
    if not shape:
        raise ValueError("shape cannot be empty")
    if collision_layer < 0 or collision_mask < 0:
        raise ValueError("collision_layer and collision_mask must be non-negative bitmasks")
    return await _call_bridge(
        "collision2d.body_create",
        {
            "parent_path": parent_path,
            "body_type": body_type,
            "name": name,
            "shape": shape,
            "position": position,
            "collision_layer": collision_layer,
            "collision_mask": collision_mask,
            "monitoring": monitoring,
            "monitorable": monitorable,
        },
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def resource_inspect(
    path: str,
    max_properties: int = 100,
) -> dict[str, Any]:
    """Inspect a Godot Resource and a bounded set of stored properties."""
    if not 1 <= max_properties <= 500:
        raise ValueError("max_properties must be between 1 and 500")
    resource_path = _resource_path(path, must_exist=True)
    return await _call_bridge(
        "resource.inspect",
        {"path": resource_path, "max_properties": max_properties},
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def filesystem_status() -> dict[str, Any]:
    """Return Godot editor filesystem import/scan status."""
    return await _call_bridge("filesystem.status")


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def filesystem_scan() -> dict[str, Any]:
    """Ask the Godot editor filesystem to scan the configured project for changes."""
    return await _call_bridge("filesystem.scan", mutating=True)


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def asset_reimport(paths: list[str]) -> dict[str, Any]:
    """Reimport up to 100 existing project-local asset/resource files in Godot."""
    if not paths:
        raise ValueError("paths cannot be empty")
    if len(paths) > 100:
        raise ValueError("At most 100 files may be reimported per call")
    resource_paths = [_resource_path(path, must_exist=True) for path in paths]
    return await _call_bridge(
        "filesystem.reimport",
        {"paths": resource_paths},
        mutating=True,
    )


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def project_run(
    scene: str | None = None,
    headless: bool = False,
) -> dict[str, object]:
    """Run the configured Godot project or one scene and return an explicit run_id."""
    _assert_permission(mutating=True)
    resource_scene: str | None = None
    if scene:
        resource_scene = _resource_path(scene, must_exist=True)
    result = await runner.start_run(scene=resource_scene, headless=headless)
    _audit_cli(
        operation="project.run",
        params={"scene": resource_scene, "headless": headless},
        status="ok",
    )
    return result


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def runtime_status(run_id: str) -> dict[str, object]:
    """Return status for a managed Godot run."""
    return runner.runtime_status(run_id)


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def runtime_logs(run_id: str, tail: int = 200) -> dict[str, object]:
    """Return bounded stdout/stderr for a managed Godot run."""
    return runner.runtime_logs(run_id, tail=tail)


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def runtime_stop(run_id: str) -> dict[str, object]:
    """Stop a managed Godot run created by project_run."""
    _assert_permission(mutating=True)
    result = await runner.stop_run(run_id)
    _audit_cli(
        operation="runtime.stop",
        params={"run_id": run_id},
        status="ok",
    )
    return result


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def export_presets() -> dict[str, object]:
    """List Godot export presets without exposing signing credentials."""
    return {"presets": runner.export_presets()}


async def _export(
    mode: Literal["debug", "release", "pack"],
    preset: str,
    output_path: str,
) -> dict[str, object]:
    _assert_permission(mutating=True)
    target = _project_file(output_path)
    result = await runner.export(mode=mode, preset=preset, output_path=target)
    returncode = result.get("returncode")
    succeeded = isinstance(returncode, int) and returncode == 0
    request_id = _audit_cli(
        operation=f"export.{mode}",
        params={"preset": preset, "output_path": str(target)},
        status="ok" if succeeded else "error",
    )
    return {"request_id": request_id, **result}


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def export_debug(preset: str, output_path: str) -> dict[str, object]:
    """Create a Godot debug export inside the configured project root."""
    return await _export("debug", preset, output_path)


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def export_release(preset: str, output_path: str) -> dict[str, object]:
    """Create a Godot release export inside the configured project root."""
    return await _export("release", preset, output_path)


@mcp.tool(annotations=WRITE_TOOL)  # type: ignore[untyped-decorator]
async def export_pack(preset: str, output_path: str) -> dict[str, object]:
    """Create a PCK/ZIP export pack inside the configured project root."""
    return await _export("pack", preset, output_path)


@mcp.tool(annotations=DESTRUCTIVE_TOOL)  # type: ignore[untyped-decorator]
async def batch_execute(
    steps: list[dict[str, Any]],
    stop_on_error: bool = True,
) -> dict[str, Any]:
    """Execute a bounded batch of structured editor-bridge operations."""
    if not steps:
        raise ValueError("steps cannot be empty")
    if len(steps) > 50:
        raise ValueError("A batch may contain at most 50 steps")
    forbidden = {
        "batch.execute",
        "editor_script.execute",
        "node.delete",
        "scene.close",
        "scene.reload",
        "scene.create",
        "scene.duplicate",
        "input.action_delete",
        "input.event_remove",
        "project.settings_clear",
        "autoload.remove",
    }
    for step in steps:
        operation = str(step.get("operation", ""))
        if operation in forbidden:
            raise PermissionError(f"{operation} is not allowed inside batch_execute")
    return await _call_bridge(
        "batch.execute",
        {"steps": steps, "stop_on_error": stop_on_error},
        mutating=True,
    )


@mcp.tool(annotations=READ_ONLY)  # type: ignore[untyped-decorator]
async def nexora_capabilities() -> dict[str, Any]:
    """Describe the dedicated Godot MCP scope, permission mode and current Phase A-D surface."""
    return {
        "name": "Nexora Godot MCP",
        "version": "0.4.0",
        "dedicated_application": "Godot Engine",
        "all_in_one": False,
        "provider_agnostic": True,
        "local_models_supported_via_mcp_host": True,
        "auth_mode": settings.auth_mode,
        "permission_profile": settings.permission_profile,
        "project_root": str(settings.resolved_project_root),
        "categories": [
            "project",
            "scene",
            "nodes",
            "transforms",
            "resources",
            "filesystem",
            "scripts",
            "signals",
            "input",
            "project_settings",
            "autoloads",
            "ui",
            "2d",
            "sprites",
            "tilemaps",
            "camera2d",
            "collision2d",
            "runtime",
            "export",
            "batch",
        ],
    }


def build_app() -> Any:
    raw_app = mcp.streamable_http_app(
        host=settings.gateway_host,
        json_response=True,
        stateless_http=True,
        max_request_body_size=8 * 1024 * 1024,
        transport_security=settings.transport_security(),
    )
    if settings.auth_mode == "static":
        return BearerTokenMiddleware(
            raw_app,
            token=settings.public_token,
            exempt_paths={"/health"},
        )
    return raw_app


app = build_app()


def main() -> None:
    settings.validate_runtime()
    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    logger.info(
        "Starting Nexora Godot MCP on %s:%s for %s",
        settings.gateway_host,
        settings.gateway_port,
        settings.resolved_project_root,
    )
    uvicorn.run(
        app,
        host=settings.gateway_host,
        port=settings.gateway_port,
        log_level=settings.log_level.lower(),
    )


if __name__ == "__main__":
    main()
