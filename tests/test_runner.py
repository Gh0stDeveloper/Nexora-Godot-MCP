from __future__ import annotations

from pathlib import Path

from nexora_godot_mcp.runner import GodotCliRunner


def test_export_preset_parser(tmp_path: Path) -> None:
    (tmp_path / "project.godot").write_text(
        '[application]\nconfig/name="Fixture"\n',
        encoding="utf-8",
    )
    (tmp_path / "export_presets.cfg").write_text(
        """
[preset.0]
name="Android"
platform="Android"
runnable=true
export_filter="all_resources"

[preset.1]
name="Linux"
platform="Linux/X11"
runnable=true
""".strip()
        + "\n",
        encoding="utf-8",
    )
    runner = GodotCliRunner(
        binary="godot",
        project_root=tmp_path,
        runtime_log_dir=tmp_path / "runs",
        timeout_seconds=10,
    )
    presets = runner.export_presets()
    assert presets[0]["name"] == "Android"
    assert presets[0]["platform"] == "Android"
    assert presets[1]["name"] == "Linux"
