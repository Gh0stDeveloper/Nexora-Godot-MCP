from __future__ import annotations

from pathlib import Path

import pytest

from nexora_godot_mcp.script_ops import (
    ScriptPatchError,
    apply_revision_patch,
    parse_godot_diagnostics,
    sha256_text,
)


def test_revision_patch_is_atomic_and_hash_guarded(tmp_path: Path) -> None:
    path = tmp_path / "player.gd"
    original = "extends Node\n\nvar speed = 5\n"
    path.write_text(original, encoding="utf-8")

    result = apply_revision_patch(
        path,
        expected_sha256=sha256_text(original),
        patches=[{"search": "var speed = 5", "replace": "var speed = 8"}],
    )

    updated = path.read_text(encoding="utf-8")
    assert "speed = 8" in updated
    assert result["old_sha256"] == sha256_text(original)
    assert result["sha256"] == sha256_text(updated)
    assert result["replacement_count"] == 1


def test_revision_patch_rejects_ambiguous_match(tmp_path: Path) -> None:
    path = tmp_path / "player.gd"
    original = "var hp = 10\nvar hp = 10\n"
    path.write_text(original, encoding="utf-8")

    with pytest.raises(ScriptPatchError, match="match count mismatch"):
        apply_revision_patch(
            path,
            expected_sha256=sha256_text(original),
            patches=[{"search": "var hp = 10", "replace": "var hp = 20"}],
        )


def test_revision_patch_supports_explicit_replace_all(tmp_path: Path) -> None:
    path = tmp_path / "player.gd"
    original = "foo\nfoo\n"
    path.write_text(original, encoding="utf-8")

    result = apply_revision_patch(
        path,
        expected_sha256=sha256_text(original),
        patches=[
            {
                "search": "foo",
                "replace": "bar",
                "replace_all": True,
                "expected_matches": 2,
            }
        ],
    )

    assert path.read_text(encoding="utf-8") == "bar\nbar\n"
    assert result["replacement_count"] == 2


def test_parse_godot_diagnostics_extracts_location() -> None:
    stderr = """
SCRIPT ERROR: Parse Error: Expected closing ")" after call arguments.
          at: GDScript::reload (res://scripts/player.gd:14)
ERROR: Failed to load script "res://scripts/player.gd" with error "Parse error".
""".strip()

    diagnostics = parse_godot_diagnostics("", stderr)

    assert diagnostics[0]["severity"] == "error"
    assert diagnostics[0]["kind"] == "parse_error"
    assert diagnostics[0]["path"] == "res://scripts/player.gd"
    assert diagnostics[0]["line"] == 14
