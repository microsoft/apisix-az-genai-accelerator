from __future__ import annotations

import datetime as dt
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[2]


def repo_root() -> Path:
    return REPO_ROOT


def ensure(commands: Iterable[str]) -> None:
    for name in commands:
        if shutil.which(name) is None:
            sys.stderr.write(f"missing dependency: {name}\n")
            sys.exit(1)


def derive_image_tag(root: Path) -> str:
    git = shutil.which("git")
    if git:
        try:
            commit = subprocess.run(
                ["git", "-C", str(root), "rev-parse", "--short=12", "HEAD"],
                text=True,
                capture_output=True,
                check=True,
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
                    subprocess.run(diff_args, text=True, capture_output=True).returncode
                    != 0
                ):
                    dirty = True
                    break
            suffix = "-dirty" if dirty else ""
            return f"{commit}-{timestamp}{suffix}"
        except subprocess.CalledProcessError:
            pass
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
