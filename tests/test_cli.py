from __future__ import annotations

from pathlib import Path

from nexora_godot_mcp.cli import _enable_plugin, _ensure_project_gitignore


def test_enable_plugin_adds_editor_plugins_section(tmp_path: Path) -> None:
    project_file = tmp_path / "project.godot"
    project_file.write_text(
        '[application]\nconfig/name="Fixture"\n',
        encoding="utf-8",
    )
    _enable_plugin(project_file)
    content = project_file.read_text(encoding="utf-8")
    assert "[editor_plugins]" in content
    assert "res://addons/nexora_godot_mcp/plugin.cfg" in content

    _enable_plugin(project_file)
    content_again = project_file.read_text(encoding="utf-8")
    assert content_again.count("res://addons/nexora_godot_mcp/plugin.cfg") == 1


def test_project_gitignore_is_idempotent(tmp_path: Path) -> None:
    _ensure_project_gitignore(tmp_path)
    _ensure_project_gitignore(tmp_path)
    assert (tmp_path / ".gitignore").read_text(encoding="utf-8").count(
        ".nexora-godot/"
    ) == 1
