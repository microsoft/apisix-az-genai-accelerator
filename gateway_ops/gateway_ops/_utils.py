from __future__ import annotations

import datetime as dt
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from typing import IO, Any, Iterable, Literal, Sequence

REPO_ROOT = Path(__file__).resolve().parents[2]


def repo_root() -> Path:
    return REPO_ROOT


def run_logged(
    cmd: Iterable[str],
    *,
    capture_output: bool = False,
    text: bool = True,
    check: bool = True,
    echo: Literal["always", "on_error", "never"] = "always",
    **kwargs: Any,
) -> subprocess.CompletedProcess[str]:
    """
    Run a subprocess, streaming stdout/stderr live while still capturing them.
    If the process fails and echo="on_error", buffered output is replayed.
    """
    if not text:
        raise ValueError("run_logged supports text mode only")

    cmd_list: Sequence[str] = list(cmd)

    if not capture_output:
        result = subprocess.run(
            cmd_list,
            capture_output=False,
            text=True,
            **kwargs,
        )
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(
                result.returncode,
                result.args,
                output=result.stdout,
                stderr=result.stderr,
            )
        return result

    proc = subprocess.Popen(
        cmd_list,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        **kwargs,
    )

    stdout_buf: list[str] = []
    stderr_buf: list[str] = []

    def _reader(stream: IO[str] | None, buffer: list[str], writer: IO[str]) -> None:
        if stream is None:
            return
        for line in iter(stream.readline, ""):
            buffer.append(line)
            if echo == "always":
                writer.write(line)
                writer.flush()
        stream.close()

    threads: list[threading.Thread] = []
    threads.append(
        threading.Thread(
            target=_reader, args=(proc.stdout, stdout_buf, sys.stdout), daemon=True
        )
    )
    threads.append(
        threading.Thread(
            target=_reader, args=(proc.stderr, stderr_buf, sys.stderr), daemon=True
        )
    )
    for thread in threads:
        thread.start()

    returncode = proc.wait()
    for thread in threads:
        thread.join()

    if echo == "on_error" and returncode != 0:
        if stdout_buf:
            sys.stdout.writelines(stdout_buf)
            sys.stdout.flush()
        if stderr_buf:
            sys.stderr.writelines(stderr_buf)
            sys.stderr.flush()

    stdout_joined = "".join(stdout_buf)
    stderr_joined = "".join(stderr_buf)

    completed = subprocess.CompletedProcess(
        cmd_list,
        returncode,
        stdout=stdout_joined,
        stderr=stderr_joined,
    )

    if check and returncode != 0:
        raise subprocess.CalledProcessError(
            returncode, cmd_list, output=stdout_joined, stderr=stderr_joined
        )
    return completed


def ensure(commands: Iterable[str]) -> None:
    for name in commands:
        if shutil.which(name) is None:
            sys.stderr.write(f"missing dependency: {name}\n")
            sys.exit(1)


def read_env(path: Path) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    with path.open() as handle:
        for raw in handle:
            line = raw.strip()
            if line == "" or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            pairs.append((key, value))
    return pairs


def derive_image_tag(root: Path) -> str:
    git = shutil.which("git")
    if git:
        try:
            commit = run_logged(
                ["git", "-C", str(root), "rev-parse", "--short=12", "HEAD"],
                capture_output=True,
            ).stdout.strip()
            timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
            dirty = False
            for diff_args in (
                [
                    "git",
                    "-C",
                    str(root),
                    "diff",
                    "--quiet",
                    "--no-ext-diff",
                    "--cached",
                ],
                ["git", "-C", str(root), "diff", "--quiet", "--no-ext-diff"],
            ):
                if (
                    run_logged(diff_args, capture_output=True, check=False).returncode
                    != 0
                ):
                    dirty = True
                    break
            suffix = "-dirty" if dirty else ""
            return f"{commit}-{timestamp}{suffix}"
        except subprocess.CalledProcessError:
            pass
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
