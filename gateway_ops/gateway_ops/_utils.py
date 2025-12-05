from __future__ import annotations

import datetime as dt
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Literal

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
    **kwargs: object,
) -> subprocess.CompletedProcess[str]:
    """
    Run a subprocess, mirroring stdout/stderr to the caller even on failure.
    Returns the CompletedProcess; raises CalledProcessError when check=True.
    """
    result = subprocess.run(
        list(cmd),
        capture_output=capture_output,
        text=text,
        **kwargs,  # type: ignore[arg-type]
    )
    if capture_output and (
        echo == "always" or (echo == "on_error" and result.returncode != 0)
    ):
        if result.stdout:
            sys.stdout.write(result.stdout)
        if result.stderr:
            sys.stderr.write(result.stderr)
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode, result.args, output=result.stdout, stderr=result.stderr
        )
    return result


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
