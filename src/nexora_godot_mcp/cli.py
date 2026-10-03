from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import urllib.error
import urllib.request
from importlib.resources import files
from pathlib import Path
from typing import Any, cast

from .config import Settings
from .runner import GodotCliError, GodotCliRunner


def repository_root() -> Path:
    current = Path.cwd().resolve()
    for candidate in (current, *current.parents):
        if (candidate / "pyproject.toml").is_file():
            return candidate
    return current


def _write_private(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    if os.name != "nt":
        path.chmod(0o600)


def _copy_addon_tree(source: Any, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for child in source.iterdir():
        target = destination / child.name
        if child.is_dir():
            _copy_addon_tree(child, target)
        else:
            target.write_bytes(child.read_bytes())


def _ensure_project_gitignore(project_root: Path) -> None:
    path = project_root / ".gitignore"
    existing = path.read_text(encoding="utf-8") if path.is_file() else ""
    marker = ".nexora-godot/"
    if marker not in existing.splitlines():
        suffix = "" if not existing or existing.endswith("\n") else "\n"
        path.write_text(existing + suffix + marker + "\n", encoding="utf-8")


def _enable_plugin(project_file: Path) -> None:
    text = project_file.read_text(encoding="utf-8")
    plugin_path = '"res://addons/nexora_godot_mcp/plugin.cfg"'
    if plugin_path in text:
        return

    lines = text.splitlines()
    section_index: int | None = None
    next_section = len(lines)
    for index, line in enumerate(lines):
        if line.strip() == "[editor_plugins]":
            section_index = index
            continue
        if section_index is not None and index > section_index and line.startswith("["):
            next_section = index
            break

    if section_index is None:
        addition = [
            "",
            "[editor_plugins]",
            f"enabled=PackedStringArray({plugin_path})",
        ]
        lines.extend(addition)
    else:
        enabled_index: int | None = None
        for index in range(section_index + 1, next_section):
            if lines[index].strip().startswith("enabled="):
                enabled_index = index
                break
        if enabled_index is None:
            lines.insert(
                section_index + 1,
                f"enabled=PackedStringArray({plugin_path})",
            )
        else:
            raw = lines[enabled_index]
            open_paren = raw.find("(")
            close_paren = raw.rfind(")")
            if open_paren == -1 or close_paren == -1:
                lines[enabled_index] = f"enabled=PackedStringArray({plugin_path})"
            else:
                inside = raw[open_paren + 1 : close_paren].strip()
                items = [item.strip() for item in inside.split(",") if item.strip()]
                items.append(plugin_path)
                lines[enabled_index] = (
                    "enabled=PackedStringArray(" + ", ".join(dict.fromkeys(items)) + ")"
                )

    project_file.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_setup(args: argparse.Namespace) -> None:
    project_root = Path(args.project).expanduser().resolve()
    project_file = project_root / "project.godot"
    if not project_file.is_file():
        raise SystemExit(f"project.godot not found: {project_file}")

    bridge_secret = secrets.token_urlsafe(48)
    public_token = secrets.token_urlsafe(48)
    env_path = repository_root() / ".env"
    if env_path.exists() and not args.force:
        raise SystemExit(".env already exists. Re-run with --force to replace it.")

    env = {
        "NEXORA_GODOT_AUTH_MODE": "static",
        "NEXORA_GODOT_GATEWAY_HOST": "127.0.0.1",
        "NEXORA_GODOT_GATEWAY_PORT": "8775",
        "NEXORA_GODOT_PUBLIC_TOKEN": public_token,
        "NEXORA_GODOT_BRIDGE_HOST": "127.0.0.1",
        "NEXORA_GODOT_BRIDGE_PORT": "9877",
        "NEXORA_GODOT_BRIDGE_SECRET": bridge_secret,
        "NEXORA_GODOT_PERMISSION_PROFILE": "standard",
        "NEXORA_GODOT_ALLOW_EDITOR_SCRIPT": "false",
        "NEXORA_GODOT_PROJECT_ROOT": str(project_root),
        "NEXORA_GODOT_GODOT_BINARY": args.godot,
        "NEXORA_GODOT_AUDIT_LOG": "./var/audit.jsonl",
        "NEXORA_GODOT_RUNTIME_LOG_DIR": "./var/runs",
        "NEXORA_GODOT_LOG_LEVEL": "INFO",
    }
    _write_private(
        env_path,
        "\n".join(f"{key}={value}" for key, value in env.items()) + "\n",
    )

    addon_source = files("nexora_godot_mcp").joinpath("_addon")
    addon_destination = project_root / "addons" / "nexora_godot_mcp"
    if addon_destination.exists():
        shutil.rmtree(addon_destination)
    _copy_addon_tree(addon_source, addon_destination)

    bridge_config = {
        "host": "127.0.0.1",
        "port": 9877,
        "secret": bridge_secret,
        "auto_start": True,
    }
    bridge_path = project_root / ".nexora-godot" / "bridge.json"
    _write_private(
        bridge_path,
        json.dumps(bridge_config, indent=2) + "\n",
    )
    _ensure_project_gitignore(project_root)
    _enable_plugin(project_file)

    print("Nexora Godot MCP setup complete.")
    print(f"Project: {project_root}")
    print(f"Plugin: {addon_destination}")
    print("Open/restart the Godot editor so the enabled plugin starts the local bridge.")
    print("Then run: nexora-godot doctor")
    print("Start the MCP gateway with: nexora-godot start")


def _settings_from_env() -> Settings:
    return Settings()


def cmd_doctor(_args: argparse.Namespace) -> None:
    settings = _settings_from_env()
    checks: list[tuple[str, bool, str]] = []
    checks.append(
        (
            "project.godot",
            (settings.resolved_project_root / "project.godot").is_file(),
            str(settings.resolved_project_root),
        )
    )
    checks.append(
        (
            "Godot addon",
            (
                settings.resolved_project_root
                / "addons"
                / "nexora_godot_mcp"
                / "plugin.cfg"
            ).is_file(),
            "",
        )
    )
    checks.append(
        (
            "Bridge config",
            (
                settings.resolved_project_root
                / ".nexora-godot"
                / "bridge.json"
            ).is_file(),
            "",
        )
    )

    runner = GodotCliRunner(
        binary=settings.godot_binary,
        project_root=settings.resolved_project_root,
        runtime_log_dir=settings.runtime_log_dir,
        timeout_seconds=settings.request_timeout_seconds,
    )
    try:
        import asyncio

        version = asyncio.run(runner.version())
        checks.append(("Godot CLI", True, version))
    except GodotCliError as exc:
        checks.append(("Godot CLI", False, str(exc)))

    try:
        with urllib.request.urlopen("http://127.0.0.1:8775/health", timeout=2) as response:
            checks.append(("MCP gateway", response.status == 200, str(response.status)))
    except (urllib.error.URLError, TimeoutError):
        checks.append(("MCP gateway", False, "start it with nexora-godot start"))

    bridge_ok = False
    try:
        import socket

        with socket.create_connection(
            (settings.bridge_host, settings.bridge_port),
            timeout=2,
        ):
            bridge_ok = True
    except OSError:
        pass
    checks.append(
        (
            "Godot editor bridge",
            bridge_ok,
            "open/restart Godot with the plugin enabled" if not bridge_ok else "",
        )
    )

    for label, ok, detail in checks:
        suffix = f" · {detail}" if detail else ""
        print(f"[{'OK' if ok else 'FAIL':4}] {label}{suffix}")
    if not all(ok for _, ok, _ in checks):
        raise SystemExit("One or more Nexora Godot MCP checks need attention.")


def cmd_status(_args: argparse.Namespace) -> None:
    try:
        with urllib.request.urlopen("http://127.0.0.1:8775/health", timeout=3) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Nexora Godot MCP gateway is offline: {exc}") from exc
    print(json.dumps(payload, indent=2))


def cmd_start(_args: argparse.Namespace) -> None:
    from .server import main as server_main

    server_main()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nexora-godot",
        description="Local setup and lifecycle manager for Nexora Godot MCP.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    setup = sub.add_parser("setup", help="Install/configure Nexora Godot MCP for one project.")
    setup.add_argument("--project", required=True, help="Path containing project.godot.")
    setup.add_argument("--godot", default="godot", help="Godot editor binary.")
    setup.add_argument("--force", action="store_true")
    setup.set_defaults(func=cmd_setup)

    start = sub.add_parser("start", help="Start the local MCP gateway in the foreground.")
    start.set_defaults(func=cmd_start)

    status = sub.add_parser("status", help="Show MCP/editor/CLI status.")
    status.set_defaults(func=cmd_status)

    doctor = sub.add_parser("doctor", help="Validate local installation and connectivity.")
    doctor.set_defaults(func=cmd_doctor)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    function = cast(Any, args.func)
    function(args)


if __name__ == "__main__":
    main()
