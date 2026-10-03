from __future__ import annotations

from pathlib import Path

import pytest

from nexora_godot_mcp.config import Settings


def test_static_runtime_requires_separate_long_secrets(tmp_path: Path) -> None:
    settings = Settings(
        auth_mode="static",
        public_token="p" * 48,
        bridge_secret="b" * 48,
        project_root=tmp_path,
    )
    settings.validate_runtime()


def test_bridge_must_remain_loopback(tmp_path: Path) -> None:
    settings = Settings(
        auth_mode="static",
        public_token="p" * 48,
        bridge_secret="b" * 48,
        bridge_host="0.0.0.0",
        project_root=tmp_path,
    )
    with pytest.raises(RuntimeError, match="loopback"):
        settings.validate_runtime()


def test_local_mode_requires_loopback_gateway(tmp_path: Path) -> None:
    settings = Settings(
        auth_mode="local",
        gateway_host="0.0.0.0",
        bridge_secret="b" * 48,
        project_root=tmp_path,
    )
    with pytest.raises(RuntimeError, match="loopback"):
        settings.validate_runtime()
