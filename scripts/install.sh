#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3.11+ is required."
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv..."
  python3 -m pip install --user uv
  export PATH="$HOME/.local/bin:$PATH"
fi

uv sync --all-extras
exec uv run nexora-godot setup "$@"
