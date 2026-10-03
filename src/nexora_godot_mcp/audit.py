from __future__ import annotations

import json
import threading
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .security import sanitize_for_audit


class AuditLogger:
    def __init__(self, path: Path) -> None:
        self.path = path.expanduser()
        self._lock = threading.Lock()

    def write(
        self,
        *,
        request_id: str,
        operation: str,
        params: dict[str, Any],
        status: str,
        detail: str | None = None,
    ) -> None:
        record = {
            "timestamp": datetime.now(UTC).isoformat(),
            "request_id": request_id,
            "operation": operation,
            "params": sanitize_for_audit(params),
            "status": status,
        }
        if detail:
            record["detail"] = detail[:500]

        self.path.parent.mkdir(parents=True, exist_ok=True)
        line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
        with self._lock, self.path.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
