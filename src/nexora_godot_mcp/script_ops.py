from __future__ import annotations

import hashlib
import os
import re
import tempfile
from pathlib import Path
from typing import Any


class ScriptPatchError(RuntimeError):
    pass


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def apply_revision_patch(
    path: Path,
    *,
    expected_sha256: str,
    patches: list[dict[str, Any]],
    max_bytes: int = 2 * 1024 * 1024,
) -> dict[str, object]:
    if not patches:
        raise ScriptPatchError("patches cannot be empty")
    if len(patches) > 100:
        raise ScriptPatchError("A single script_patch call may contain at most 100 patches")

    current = path.read_text(encoding="utf-8", errors="replace")
    current_sha = sha256_text(current)
    if current_sha != expected_sha256:
        raise ScriptPatchError("script_revision_conflict")

    updated = current
    applied = 0
    details: list[dict[str, object]] = []

    for index, patch in enumerate(patches):
        search = patch.get("search")
        replace = patch.get("replace")
        replace_all = bool(patch.get("replace_all", False))
        expected_matches_raw = patch.get("expected_matches")

        if not isinstance(search, str) or not search:
            raise ScriptPatchError(f"patch[{index}].search must be a non-empty string")
        if not isinstance(replace, str):
            raise ScriptPatchError(f"patch[{index}].replace must be a string")

        count = updated.count(search)
        if expected_matches_raw is not None:
            if not isinstance(expected_matches_raw, int) or expected_matches_raw < 1:
                raise ScriptPatchError(
                    f"patch[{index}].expected_matches must be an integer >= 1"
                )
            expected_matches = expected_matches_raw
        else:
            expected_matches = count if replace_all else 1

        if count != expected_matches:
            raise ScriptPatchError(
                f"patch[{index}] match count mismatch: expected {expected_matches}, found {count}"
            )

        if replace_all:
            updated = updated.replace(search, replace)
            replacements = count
        else:
            updated = updated.replace(search, replace, 1)
            replacements = 1

        applied += replacements
        details.append(
            {
                "index": index,
                "matches": count,
                "replacements": replacements,
                "replace_all": replace_all,
            }
        )

    encoded = updated.encode("utf-8")
    if len(encoded) > max_bytes:
        raise ScriptPatchError("Patched script exceeds the 2 MiB write limit")
    if updated == current:
        raise ScriptPatchError("script_patch produced no content change")

    mode = path.stat().st_mode & 0o7777
    temp_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".nexora.tmp",
            delete=False,
        ) as handle:
            handle.write(updated)
            handle.flush()
            os.fsync(handle.fileno())
            temp_name = handle.name
        os.chmod(temp_name, mode)
        os.replace(temp_name, path)
        temp_name = None
    finally:
        if temp_name is not None:
            try:
                os.unlink(temp_name)
            except FileNotFoundError:
                pass

    return {
        "old_sha256": current_sha,
        "sha256": sha256_text(updated),
        "patch_count": len(patches),
        "replacement_count": applied,
        "patches": details,
        "size_bytes": len(encoded),
    }


_LOCATION_RE = re.compile(r"\((res://[^():]+):(\d+)(?::(\d+))?\)")
_SCRIPT_ERROR_RE = re.compile(r"^SCRIPT ERROR:\s*([^:]+):\s*(.*)$")
_GENERIC_ERROR_RE = re.compile(r"^ERROR:\s*(.*)$")
_WARNING_RE = re.compile(r"^WARNING:\s*(.*)$")


def parse_godot_diagnostics(stdout: str, stderr: str) -> list[dict[str, object]]:
    lines = [*stdout.splitlines(), *stderr.splitlines()]
    diagnostics: list[dict[str, object]] = []
    pending: dict[str, object] | None = None

    def flush_pending() -> None:
        nonlocal pending
        if pending is not None:
            diagnostics.append(pending)
            pending = None

    for raw in lines:
        line = raw.strip()
        if not line:
            continue

        script_match = _SCRIPT_ERROR_RE.match(line)
        if script_match:
            flush_pending()
            pending = {
                "severity": "error",
                "kind": script_match.group(1).strip().lower().replace(" ", "_"),
                "message": script_match.group(2).strip(),
            }
            continue

        warning_match = _WARNING_RE.match(line)
        if warning_match:
            flush_pending()
            pending = {
                "severity": "warning",
                "kind": "warning",
                "message": warning_match.group(1).strip(),
            }
            continue

        error_match = _GENERIC_ERROR_RE.match(line)
        if error_match:
            flush_pending()
            pending = {
                "severity": "error",
                "kind": "engine_error",
                "message": error_match.group(1).strip(),
            }
            continue

        if pending is not None:
            location = _LOCATION_RE.search(line)
            if location:
                pending["path"] = location.group(1)
                pending["line"] = int(location.group(2))
                if location.group(3):
                    pending["column"] = int(location.group(3))
                flush_pending()

    flush_pending()
    return diagnostics
