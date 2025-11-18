from __future__ import annotations

import logging

from ._e2e_common import build_test_environment, run_locust


def run(*, base_env: dict[str, str] | None = None) -> None:
    env = base_env or build_test_environment()
    run_locust(
        test_file="scenario_manage_spikes_with_payg.py",
        endpoint_path="retry-with-payg",
        user_count=-1,
        run_time=None,
        base_env=env,
    )


def main(argv: list[str] | None = None) -> int:  # noqa: ARG001
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
