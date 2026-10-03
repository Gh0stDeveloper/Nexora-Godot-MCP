from __future__ import annotations

import asyncio
import hashlib
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal


class GodotCliError(RuntimeError):
    pass


@dataclass
class CommandResult:
    command: list[str]
    returncode: int
    stdout: str
    stderr: str

    def as_dict(self) -> dict[str, object]:
        return {
            "command": self.command,
            "returncode": self.returncode,
            "stdout": self.stdout,
            "stderr": self.stderr,
        }


@dataclass
class ManagedRun:
    run_id: str
    process: asyncio.subprocess.Process
    command: list[str]
    started_at: float
    stdout_lines: list[str] = field(default_factory=list)
    stderr_lines: list[str] = field(default_factory=list)
    readers: list[asyncio.Task[None]] = field(default_factory=list)


class GodotCliRunner:
    def __init__(
        self,
        *,
        binary: str,
        project_root: Path,
        runtime_log_dir: Path,
        timeout_seconds: float,
    ) -> None:
        self.binary = binary
        self.project_root = project_root.expanduser().resolve()
        self.runtime_log_dir = runtime_log_dir.expanduser().resolve()
        self.timeout_seconds = timeout_seconds
        self._runs: dict[str, ManagedRun] = {}

    def ensure_project(self) -> None:
        if not (self.project_root / "project.godot").is_file():
            raise GodotCliError(
                f"project.godot not found in configured project root: {self.project_root}"
            )

    async def _run_once(
        self,
        args: list[str],
        *,
        timeout_seconds: float | None = None,
    ) -> CommandResult:
        self.ensure_project()
        command = [self.binary, *args]
        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                cwd=self.project_root,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        except OSError as exc:
            raise GodotCliError(f"Could not start Godot binary: {exc}") from exc

        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout_seconds or self.timeout_seconds,
            )
        except TimeoutError as exc:
            process.kill()
            await process.wait()
            raise GodotCliError("Godot command timed out") from exc

        return CommandResult(
            command=command,
            returncode=int(process.returncode or 0),
            stdout=stdout.decode("utf-8", errors="replace"),
            stderr=stderr.decode("utf-8", errors="replace"),
        )

    async def version(self) -> str:
        try:
            process = await asyncio.create_subprocess_exec(
                self.binary,
                "--version",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        except OSError as exc:
            raise GodotCliError(f"Could not start Godot binary: {exc}") from exc
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=10)
        text = stdout.decode("utf-8", errors="replace").strip()
        if not text:
            text = stderr.decode("utf-8", errors="replace").strip()
        if int(process.returncode or 0) != 0:
            raise GodotCliError(text or "Godot --version failed")
        return text

    async def validate_project(self) -> CommandResult:
        result = await self._run_once(
            [
                "--headless",
                "--path",
                str(self.project_root),
                "--editor",
                "--quit-after",
                "1",
            ],
        )
        return result

    async def import_project(self) -> CommandResult:
        return await self._run_once(
            [
                "--headless",
                "--path",
                str(self.project_root),
                "--import",
            ],
        )

    @staticmethod
    async def _collect(
        stream: asyncio.StreamReader | None,
        target: list[str],
        *,
        limit: int = 5000,
    ) -> None:
        if stream is None:
            return
        while True:
            raw = await stream.readline()
            if not raw:
                return
            target.append(raw.decode("utf-8", errors="replace").rstrip())
            if len(target) > limit:
                del target[: len(target) - limit]

    async def start_run(
        self,
        *,
        scene: str | None = None,
        headless: bool = False,
    ) -> dict[str, object]:
        self.ensure_project()
        command = [self.binary]
        if headless:
            command.append("--headless")
        command.extend(["--path", str(self.project_root)])
        if scene:
            command.extend(["--scene", scene])

        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                cwd=self.project_root,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        except OSError as exc:
            raise GodotCliError(f"Could not start Godot project: {exc}") from exc

        run_id = f"run_{uuid.uuid4().hex}"
        run = ManagedRun(
            run_id=run_id,
            process=process,
            command=command,
            started_at=time.time(),
        )
        run.readers = [
            asyncio.create_task(self._collect(process.stdout, run.stdout_lines)),
            asyncio.create_task(self._collect(process.stderr, run.stderr_lines)),
        ]
        self._runs[run_id] = run
        return {
            "run_id": run_id,
            "pid": process.pid,
            "status": "running",
            "scene": scene,
            "headless": headless,
        }

    def _get_run(self, run_id: str) -> ManagedRun:
        run = self._runs.get(run_id)
        if run is None:
            raise GodotCliError(f"Unknown run_id: {run_id}")
        return run

    def runtime_status(self, run_id: str) -> dict[str, object]:
        run = self._get_run(run_id)
        returncode = run.process.returncode
        return {
            "run_id": run_id,
            "pid": run.process.pid,
            "status": "running" if returncode is None else "finished",
            "returncode": returncode,
            "started_at": run.started_at,
            "duration_seconds": max(0.0, time.time() - run.started_at),
            "command": run.command,
        }

    def runtime_logs(self, run_id: str, *, tail: int = 200) -> dict[str, object]:
        run = self._get_run(run_id)
        bounded = max(1, min(tail, 1000))
        return {
            "run_id": run_id,
            "stdout": run.stdout_lines[-bounded:],
            "stderr": run.stderr_lines[-bounded:],
        }

    async def stop_run(self, run_id: str) -> dict[str, object]:
        run = self._get_run(run_id)
        if run.process.returncode is None:
            run.process.terminate()
            try:
                await asyncio.wait_for(run.process.wait(), timeout=5)
            except TimeoutError:
                run.process.kill()
                await run.process.wait()
        await asyncio.gather(*run.readers, return_exceptions=True)
        return self.runtime_status(run_id)

    def export_presets(self) -> list[dict[str, object]]:
        path = self.project_root / "export_presets.cfg"
        if not path.is_file():
            return []
        presets: list[dict[str, object]] = []
        current: dict[str, object] | None = None
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if line.startswith("[preset.") and line.endswith("]"):
                if current:
                    presets.append(current)
                current = {"section": line[1:-1]}
                continue
            if current is None or "=" not in line or line.startswith(";"):
                continue
            key, value = line.split("=", 1)
            value = value.strip()
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            if key in {"name", "platform", "runnable", "export_filter"}:
                current[key] = value
        if current:
            presets.append(current)
        return presets

    @staticmethod
    def _artifact_metadata(output_path: Path) -> dict[str, object] | None:
        if not output_path.is_file():
            return None
        data = output_path.read_bytes()
        return {
            "path": str(output_path),
            "size_bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        }

    async def export(
        self,
        *,
        mode: Literal["debug", "release", "pack"],
        preset: str,
        output_path: Path,
    ) -> dict[str, object]:
        self.ensure_project()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        flag = {
            "debug": "--export-debug",
            "release": "--export-release",
            "pack": "--export-pack",
        }[mode]
        result = await self._run_once(
            [
                "--headless",
                "--path",
                str(self.project_root),
                flag,
                preset,
                str(output_path),
            ],
            timeout_seconds=max(self.timeout_seconds, 900.0),
        )
        payload = result.as_dict()
        if result.returncode == 0:
            artifact = await asyncio.to_thread(self._artifact_metadata, output_path)
            if artifact is not None:
                payload["artifact"] = artifact
        return payload
