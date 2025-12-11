from __future__ import annotations

import logging

from ._e2e_common import run_scenario


def run(*, base_env: dict[str, str] | None = None) -> None:
    run_scenario(
        test_file="scenario_manage_spikes_with_payg.py",
        endpoint_path="retry-with-payg-v2",
        user_count=-1,
        run_time=None,
        base_env=base_env,
    )


def main(argv: list[str] | None = None) -> int:  # noqa: ARG001
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
