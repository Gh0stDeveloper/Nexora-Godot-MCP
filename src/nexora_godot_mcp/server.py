from __future__ import annotations

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
            version="0.1.0",
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
        version="0.1.0",
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
            "version": "0.1.0",
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
        "version": "0.1.0",
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
) -> dict[str, Any]:
    """Create a new Godot scene with a Node-derived root type and save it as .tscn."""
    resource_path = _resource_path(path)
    if not resource_path.lower().endswith(".tscn"):
        raise ValueError("scene_create path must end in .tscn")
    return await _call_bridge(
        "scene.create",
        {"root_type": root_type, "name": name, "path": resource_path},
        mutating=True,
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
    forbidden = {"batch.execute", "editor_script.execute"}
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
    """Describe the dedicated Godot MCP scope, permission mode and current Phase A surface."""
    return {
        "name": "Nexora Godot MCP",
        "version": "0.1.0",
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
            "scripts",
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
