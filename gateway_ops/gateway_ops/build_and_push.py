from __future__ import annotations

import json
import os
import re
import tempfile
from contextlib import contextmanager
from pathlib import Path
from shutil import copy2, copytree
from typing import Iterable, Iterator

from ._utils import derive_image_tag, ensure, repo_root, run_logged


def build_and_push(
    *,
    target: str,
    dockerfile: Path,
    build_context: Path,
    include_paths: Iterable[Path],
    local_docker: bool,
    tfvars_key: str | None,
    tfvars_path: Path | None,
) -> str:
    ensure(["terraform", "az"])
    if local_docker:
        ensure(["docker"])

    root = repo_root()
    stack = root / "infra" / "terraform" / "stacks" / "10-platform"
    template = root / "acr-build.yaml"
    image_tag = os.environ.get("IMAGE_TAG") or derive_image_tag(root)

    outputs = _terraform_outputs(stack)
    acr_login_server = outputs.get("platform_acr_login_server", {}).get("value")
    if not acr_login_server:
        raise RuntimeError("acr_login_server missing from terraform outputs")
    registry_name = _registry_name_from_login_server(acr_login_server)

    if local_docker:
        _acr_docker_login(registry_name)

    prefix = _image_repo_prefix()
    full_image = f"{acr_login_server}/{prefix}/{target}:{image_tag}"
    remote_image = f"{prefix}/{target}:{image_tag}"

    with _staged_context(
        root, template, include_paths, build_context, dockerfile, target
    ) as (
        context_root,
        dockerfile_rel,
        build_context_rel,
    ):
        if local_docker:
            _docker_build_and_push(
                image=full_image,
                dockerfile=context_root / dockerfile_rel,
                context_dir=context_root / build_context_rel,
            )
        else:
            _acr_run_build(
                registry=registry_name,
                template=context_root / "acr-build.yaml",
                image=remote_image,
                dockerfile=dockerfile_rel,
                build_context=build_context_rel,
                workdir=context_root,
            )

    tfvars = tfvars_path or _auto_tfvars_path(root, registry_name)
    if tfvars and tfvars_key:
        _update_tfvars(tfvars, [(tfvars_key, full_image)])

    print(full_image)
    return full_image


def _terraform_outputs(stack_dir: Path) -> dict:
    result = run_logged(
        ["terraform", f"-chdir={stack_dir}", "output", "-json"],
        capture_output=True,
    )
    return json.loads(result.stdout)


def _image_repo_prefix() -> str:
    return os.environ.get(
        "ACCELERATOR_IMAGE_REPOSITORY_PREFIX", "apisix-az-genai-accelerator"
    )


def _registry_name_from_login_server(login_server: str) -> str:
    return login_server.split(".")[0]


def _acr_docker_login(registry: str) -> None:
    run_logged(["az", "acr", "login", "--name", registry])


def _docker_build_and_push(image: str, dockerfile: Path, context_dir: Path) -> None:
    run_logged(
        [
            "docker",
            "build",
            "--platform",
            "linux/amd64",
            "-t",
            image,
            "-f",
            str(dockerfile),
            str(context_dir),
        ],
        capture_output=False,
    )
    run_logged(["docker", "push", image], capture_output=False)


def _acr_run_build(
    *,
    registry: str,
    template: Path,
    image: str,
    dockerfile: Path,
    build_context: Path,
    workdir: Path,
) -> None:
    template_path = template.relative_to(workdir)
    run_logged(
        [
            "az",
            "acr",
            "run",
            "-f",
            template_path.as_posix(),
            "--registry",
            registry,
            "--set",
            f"image={image}",
            "--set",
            f"dockerfile={dockerfile.as_posix()}",
            "--set",
            "platform=linux/amd64",
            "--set",
            f"context={build_context.as_posix()}",
            str(workdir),
        ],
        capture_output=True,
    )


def _copy_into_context(root: Path, destination_root: Path, rel_path: Path) -> None:
    source = root / rel_path
    if not source.exists():
        raise FileNotFoundError(f"Context path not found for build: {source}")

    destination = destination_root / rel_path
    destination.parent.mkdir(parents=True, exist_ok=True)

    if source.is_dir():
        copytree(source, destination, dirs_exist_ok=True)
    else:
        copy2(source, destination)


@contextmanager
def _staged_context(
    root: Path,
    template: Path,
    include_paths: Iterable[Path],
    build_context: Path,
    dockerfile: Path,
    target: str,
) -> Iterator[tuple[Path, Path, Path]]:
    with tempfile.TemporaryDirectory(prefix=f"{target}-ctx-") as tmpdir:
        context_root = Path(tmpdir)
        copy2(template, context_root / "acr-build.yaml")
        for rel_path in include_paths:
            _copy_into_context(root, context_root, rel_path)

        build_context_abs = context_root / build_context
        if not build_context_abs.exists():
            raise FileNotFoundError(
                f"Build context not found for {target}: {build_context_abs}"
            )

        yield context_root, dockerfile, build_context


def _update_tfvars(tfvars_path: Path, replacements: Iterable[tuple[str, str]]) -> None:
    if not tfvars_path.exists():
        raise FileNotFoundError(f"tfvars file not found: {tfvars_path}")

    content = tfvars_path.read_text()
    updated = content

    for key, value in replacements:
        pattern = rf"^{key}\s*=\s*\".*?\""
        replacement = f'{key} = "{value}"'
        updated = re.sub(pattern, replacement, updated, count=1, flags=re.MULTILINE)

    if updated != content:
        tfvars_path.write_text(updated)
        print(f"Updated image tags in {tfvars_path}")


def _auto_tfvars_path(root: Path, registry: str) -> Path | None:
    stack_dir = root / "infra" / "terraform" / "stacks" / "20-workload"
    if not stack_dir.exists():
        return None

    for tfvars in stack_dir.glob("*.tfvars"):
        match = re.search(
            r'^platform_acr_name\s*=\s*"([^"]+)"',
            tfvars.read_text(),
            flags=re.MULTILINE,
        )
        if match and match.group(1) == registry:
            print(f"Auto-selected tfvars: {tfvars} (registry match)")
            return tfvars

    return None
