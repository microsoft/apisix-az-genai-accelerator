from __future__ import annotations

import argparse
import logging

from ._e2e_common import run_scenario

DEFAULT_ENDPOINT_PATH = "prioritization-simple"


def run(
    *,
    base_env: dict[str, str] | None = None,
    endpoint_path: str = DEFAULT_ENDPOINT_PATH,
    load_pattern: str = "cycle",
    ramp_rate: int = 1,
    request_type: str = "embeddings",
    max_tokens: int = -1,
) -> None:
    extra_env = {
        "LOAD_PATTERN": load_pattern,
        "RAMP_RATE": str(ramp_rate),
        "REQUEST_TYPE": request_type,
        "MAX_TOKENS": str(max_tokens),
    }
    run_scenario(
        test_file="scenario_prioritization.py",
        endpoint_path=endpoint_path,
        user_count=-1,
        run_time=None,
        extra_env=extra_env,
        base_env=base_env,
    )


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    parser = argparse.ArgumentParser(
        prog="run-e2e-prioritization",
        description="Run the prioritization Locust scenario against the gateway.",
    )
    parser.add_argument("--endpoint-path", default=DEFAULT_ENDPOINT_PATH)
    parser.add_argument(
        "--load-pattern",
        choices=["cycle", "low-priority", "high-priority"],
        default="cycle",
    )
    parser.add_argument("--ramp-rate", type=int, default=1)
    parser.add_argument(
        "--request-type", choices=["embeddings", "chat"], default="embeddings"
    )
    parser.add_argument("--max-tokens", type=int, default=-1)
    args = parser.parse_args(argv)

    run(
        endpoint_path=args.endpoint_path,
        load_pattern=args.load_pattern,
        ramp_rate=args.ramp_rate,
        request_type=args.request_type,
        max_tokens=args.max_tokens,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
