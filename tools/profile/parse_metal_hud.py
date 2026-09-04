#!/usr/bin/env python3
"""Parse Apple Metal Performance HUD logs and enforce QIX shipping budgets.

Apple's console log starts each metric batch with three metadata values
(frame number, graphics memory, and process memory). Every remaining pair is a
frame interval followed by GPU time, both expressed in milliseconds.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
import os
from pathlib import Path
import statistics
import sys
import tempfile
from typing import Sequence


SCHEMA = "qix.shipping.metal-hud.v1"
HUD_PREFIX = "metal-HUD:"

MINIMUM_VALID_PAIRS = 30
# The HUD can prefix its first metric batch with the host monotonic clock in
# milliseconds (observed as a multi-billion value paired with exactly 0 GPU
# time).  This is metadata, not a frame interval.  Keep every finite positive
# interval below one day -- including multi-second stalls -- so the max-frame
# gate can never hide a hitch merely because it exceeded an ingestion cutoff.
INITIAL_CLOCK_MARKER_MINIMUM_MS = 86_400_000.0
GPU_P95_BUDGET_MS = 8.0
GPU_MAX_BUDGET_MS = 16.667
FRAME_INTERVAL_P95_BUDGET_MS = 25.0
FRAME_INTERVAL_P99_BUDGET_MS = 40.0
FRAME_INTERVAL_MAX_BUDGET_MS = 150.0


def _finite_float(value: str) -> float:
    parsed = float(value.strip())
    if not math.isfinite(parsed):
        raise ArithmeticError("metric is not finite")
    return parsed


def _percentile(sorted_values: list[float], percentile: float) -> float:
    """Return a linearly interpolated percentile over an already sorted list."""

    if not sorted_values:
        raise ValueError("cannot calculate a percentile without samples")
    if len(sorted_values) == 1:
        return sorted_values[0]

    rank = (len(sorted_values) - 1) * percentile
    lower_index = math.floor(rank)
    upper_index = math.ceil(rank)
    if lower_index == upper_index:
        return sorted_values[lower_index]
    weight = rank - lower_index
    return (
        sorted_values[lower_index] * (1.0 - weight)
        + sorted_values[upper_index] * weight
    )


def _stable_number(value: float) -> float:
    # Metal HUD currently emits two decimal places. Six decimals preserve more
    # precision than the source while avoiding platform-specific float tails.
    return round(value, 6)


def summarize(samples: list[float]) -> dict[str, int | float | None]:
    if not samples:
        return {
            "sample_count": 0,
            "mean": None,
            "p50": None,
            "p95": None,
            "p99": None,
            "max": None,
        }

    ordered = sorted(samples)
    return {
        "sample_count": len(ordered),
        "mean": _stable_number(statistics.fmean(ordered)),
        "p50": _stable_number(_percentile(ordered, 0.50)),
        "p95": _stable_number(_percentile(ordered, 0.95)),
        "p99": _stable_number(_percentile(ordered, 0.99)),
        "max": _stable_number(ordered[-1]),
    }


def parse_samples(log_text: str) -> dict[str, object]:
    frame_intervals: list[float] = []
    gpu_times: list[float] = []
    hud_lines = 0
    malformed_hud_lines = 0
    candidate_pairs = 0
    unpaired_metrics = 0
    discarded_reasons: Counter[str] = Counter()

    for line in log_text.splitlines():
        prefix_position = line.find(HUD_PREFIX)
        if prefix_position < 0:
            continue

        hud_lines += 1
        payload = line[prefix_position + len(HUD_PREFIX) :].strip()
        fields = [field.strip() for field in payload.split(",")]
        line_is_malformed = False

        # A valid batch needs the three metadata fields and at least one pair.
        if len(fields) < 5:
            malformed_hud_lines += 1
            if len(fields) > 3 and (len(fields) - 3) % 2:
                unpaired_metrics += 1
            continue

        try:
            for metadata_field in fields[:3]:
                _finite_float(metadata_field)
        except (ValueError, ArithmeticError):
            malformed_hud_lines += 1
            continue

        metric_fields = fields[3:]
        if len(metric_fields) % 2:
            line_is_malformed = True
            unpaired_metrics += 1
            metric_fields = metric_fields[:-1]

        for metric_index in range(0, len(metric_fields), 2):
            candidate_pairs += 1
            try:
                interval = _finite_float(metric_fields[metric_index])
                gpu_time = _finite_float(metric_fields[metric_index + 1])
            except ValueError:
                discarded_reasons["non_numeric"] += 1
                line_is_malformed = True
                continue
            except ArithmeticError:
                discarded_reasons["non_finite"] += 1
                line_is_malformed = True
                continue

            if interval <= 0.0:
                discarded_reasons["interval_out_of_range"] += 1
                line_is_malformed = True
                continue
            if gpu_time < 0.0:
                discarded_reasons["negative_gpu_time"] += 1
                line_is_malformed = True
                continue
            if (
                interval >= INITIAL_CLOCK_MARKER_MINIMUM_MS
                and gpu_time == 0.0
            ):
                discarded_reasons["initial_clock_marker"] += 1
                continue

            frame_intervals.append(interval)
            gpu_times.append(gpu_time)

        if line_is_malformed:
            malformed_hud_lines += 1

    discarded_pairs = sum(discarded_reasons.values())
    return {
        "frame_intervals": frame_intervals,
        "gpu_times": gpu_times,
        "parsing": {
            "hud_lines": hud_lines,
            "malformed_hud_lines": malformed_hud_lines,
            "candidate_pairs": candidate_pairs,
            "valid_pairs": len(frame_intervals),
            "discarded_pairs": discarded_pairs,
            "unpaired_metrics": unpaired_metrics,
            "discarded_reasons": {
                "non_numeric": discarded_reasons["non_numeric"],
                "non_finite": discarded_reasons["non_finite"],
                "interval_out_of_range": discarded_reasons[
                    "interval_out_of_range"
                ],
                "initial_clock_marker": discarded_reasons[
                    "initial_clock_marker"
                ],
                "negative_gpu_time": discarded_reasons["negative_gpu_time"],
            },
        },
    }


def _within(stats: dict[str, int | float | None], metric: str, budget: float) -> bool:
    value = stats[metric]
    return isinstance(value, (int, float)) and value <= budget


def build_report(log_text: str, *, input_path: str = "<memory>") -> dict[str, object]:
    parsed = parse_samples(log_text)
    frame_stats = summarize(parsed["frame_intervals"])  # type: ignore[arg-type]
    gpu_stats = summarize(parsed["gpu_times"])  # type: ignore[arg-type]
    parsing = parsed["parsing"]
    valid_pairs = parsing["valid_pairs"]  # type: ignore[index]
    gpu_times = parsed["gpu_times"]
    frame_intervals = parsed["frame_intervals"]

    checks = {
        "metal_hud_lines_present": parsing["hud_lines"] > 0,  # type: ignore[index]
        "minimum_valid_pairs": valid_pairs >= MINIMUM_VALID_PAIRS,
        # A partially parseable line is still untrustworthy evidence.  The
        # explicit monotonic-clock marker is discarded without marking its
        # line malformed, so it remains the sole tolerated non-sample pair.
        "no_malformed_hud_lines": parsing["malformed_hud_lines"] == 0,  # type: ignore[index]
        "no_unpaired_metrics": parsing["unpaired_metrics"] == 0,  # type: ignore[index]
        "nonzero_gpu_signal": any(value > 0.0 for value in gpu_times),  # type: ignore[union-attr]
        "gpu_p95_within_budget": _within(gpu_stats, "p95", GPU_P95_BUDGET_MS),
        "gpu_max_within_budget": _within(gpu_stats, "max", GPU_MAX_BUDGET_MS),
        "frame_interval_p95_within_budget": _within(
            frame_stats, "p95", FRAME_INTERVAL_P95_BUDGET_MS
        ),
        "frame_interval_p99_within_budget": _within(
            frame_stats, "p99", FRAME_INTERVAL_P99_BUDGET_MS
        ),
        "frame_interval_max_within_budget": _within(
            frame_stats, "max", FRAME_INTERVAL_MAX_BUDGET_MS
        ),
    }
    passed = all(checks.values())

    return {
        "schema": SCHEMA,
        "input": input_path,
        "source": "Apple Metal Performance HUD console log",
        "unit": "milliseconds",
        "requirements": {
            "minimum_valid_pairs": MINIMUM_VALID_PAIRS,
            "initial_clock_marker_minimum_ms": INITIAL_CLOCK_MARKER_MINIMUM_MS,
            "gpu_p95_budget_ms": GPU_P95_BUDGET_MS,
            "gpu_max_budget_ms": GPU_MAX_BUDGET_MS,
            "frame_interval_p95_budget_ms": FRAME_INTERVAL_P95_BUDGET_MS,
            "frame_interval_p99_budget_ms": FRAME_INTERVAL_P99_BUDGET_MS,
            "frame_interval_max_budget_ms": FRAME_INTERVAL_MAX_BUDGET_MS,
        },
        "parsing": parsing,
        "observed_stall_pairs_over_150ms": sum(
            value > FRAME_INTERVAL_MAX_BUDGET_MS for value in frame_intervals
        ),
        "frame_interval_ms": frame_stats,
        "gpu_time_ms": gpu_stats,
        "checks": checks,
        "failed_checks": [name for name, succeeded in checks.items() if not succeeded],
        "passed": passed,
        "outcome": "passed" if passed else "failed",
    }


def write_report_atomic(output_path: Path, report: dict[str, object]) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    file_descriptor: int | None = None

    try:
        file_descriptor, raw_temporary_path = tempfile.mkstemp(
            dir=output_path.parent,
            prefix=f".{output_path.name}.",
            suffix=".tmp",
        )
        temporary_path = Path(raw_temporary_path)
        with os.fdopen(file_descriptor, "w", encoding="utf-8", newline="\n") as stream:
            file_descriptor = None
            json.dump(report, stream, indent=2, sort_keys=True, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, output_path)
        temporary_path = None

        # Persist the rename as well as the payload when the filesystem permits it.
        directory_descriptor = os.open(output_path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        if file_descriptor is not None:
            os.close(file_descriptor)
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Parse and gate an Apple Metal Performance HUD console log."
    )
    parser.add_argument("--input", required=True, type=Path, help="Metal HUD log path")
    parser.add_argument("--output", required=True, type=Path, help="JSON report path")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _argument_parser().parse_args(argv)

    try:
        log_text = arguments.input.read_text(encoding="utf-8", errors="strict")
    except (OSError, UnicodeError) as error:
        print(
            f"ERROR: unable to read Metal HUD log {arguments.input}: {error}",
            file=sys.stderr,
        )
        return 2

    report = build_report(log_text, input_path=str(arguments.input))
    try:
        write_report_atomic(arguments.output, report)
    except (OSError, TypeError, ValueError) as error:
        print(
            f"ERROR: unable to write Metal HUD report {arguments.output}: {error}",
            file=sys.stderr,
        )
        return 2

    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
