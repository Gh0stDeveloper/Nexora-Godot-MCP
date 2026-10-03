from __future__ import annotations

from nexora_godot_mcp.security import sanitize_for_audit, valid_bearer


def test_valid_bearer() -> None:
    assert valid_bearer("Bearer abc123", "abc123")
    assert not valid_bearer("Bearer wrong", "abc123")
    assert not valid_bearer(None, "abc123")
    assert not valid_bearer("Basic abc123", "abc123")


def test_audit_sanitizes_nested_secrets() -> None:
    value = {
        "path": "res://player.gd",
        "secret": "hidden",
        "nested": {"api_key": "hidden-too"},
        "items": [{"token": "hidden-three"}],
    }
    assert sanitize_for_audit(value) == {
        "path": "res://player.gd",
        "secret": "***",
        "nested": {"api_key": "***"},
        "items": [{"token": "***"}],
    }
