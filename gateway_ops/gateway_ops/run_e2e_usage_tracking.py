from __future__ import annotations

import logging

from ._e2e_common import build_test_environment, run_locust


def run(*, base_env: dict[str, str] | None = None) -> None:
    env = base_env or build_test_environment()
    run_locust(
        test_file="scenario_usage_tracking.py",
        endpoint_path="usage-tracking",
        user_count=3,
        run_time="3m",
        base_env=env,
    )


def main(argv: list[str] | None = None) -> int:  # noqa: ARG001
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
