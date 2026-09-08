#!/usr/bin/env python3
"""Contract tests for the Apple Metal Performance HUD shipping gate."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

PROFILE_TOOLS_DIRECTORY = Path(__file__).resolve().parent
if str(PROFILE_TOOLS_DIRECTORY) not in sys.path:
    sys.path.insert(0, str(PROFILE_TOOLS_DIRECTORY))

import parse_metal_hud


def _hud_log(
    frame_intervals_ms: list[float],
    gpu_times_ms: list[float],
    *,
    pairs_per_line: int = 8,
) -> str:
    if len(frame_intervals_ms) != len(gpu_times_ms):
        raise ValueError("fixture sample arrays must have the same length")

    lines = ["QIX exported runtime booted"]
    for offset in range(0, len(frame_intervals_ms), pairs_per_line):
        payload = [
            str(1000 + offset),
            "48.25",
            "212.50",
        ]
        for interval, gpu_time in zip(
            frame_intervals_ms[offset : offset + pairs_per_line],
            gpu_times_ms[offset : offset + pairs_per_line],
        ):
            payload.extend((str(interval), str(gpu_time)))
        lines.append("2026-09-03 02:00:00 metal-HUD: " + ",".join(payload))
    return "\n".join(lines) + "\n"


def _startup_hud_log(
    pairs: list[tuple[float, float]],
    *,
    frame_number: int = 35,
    startup_time: str = "06:32:23.765",
    batch_time: str = "06:32:25.311",
    batch_pid: int = 90679,
) -> str:
    payload = ",".join(str(value) for pair in pairs for value in pair)
    return (
        f"2026-09-07 {startup_time} QIX GAME[90679:732139] "
        "[libMTLHud] Metric com.apple.hud-stat.frame-interval already exist\n"
        f"2026-09-07 {batch_time} QIX GAME[{batch_pid}:732435] "
        f"metal-HUD: {frame_number},62.75,255.83,{payload}\n"
    )


class MetalHudParserTests(unittest.TestCase):
    def test_subday_initial_clock_pair_requires_complete_startup_evidence(self) -> None:
        # Forma observada: frame 35, 69 pares em dois buffers e dois marcadores
        # idênticos. As 8,66 horas do valor não cabem nos 1,546 segundos de startup.
        pairs = [(31176111.89, 0.0)] * 2 + [(16.667, 0.5)] * 67
        log = _startup_hud_log(pairs)

        report = parse_metal_hud.build_report(log)

        self.assertTrue(report["passed"])
        self.assertEqual(67, report["parsing"]["valid_pairs"])
        self.assertEqual(2, report["parsing"]["discarded_reasons"]["initial_clock_marker"])
        self.assertEqual(16.667, report["frame_interval_ms"]["max"])
        self.assertEqual(0, report["observed_stall_pairs_over_150ms"])

    def test_subday_large_interval_without_startup_proof_is_never_discarded(self) -> None:
        for interval in [151.0, 325.0, 3000.0, 90000.0, 31176111.89, 2527005586.86]:
            with self.subTest(interval=interval):
                report = parse_metal_hud.build_report(
                    _hud_log([interval] * 2 + [16.667] * 38, [0.0] * 2 + [0.5] * 38)
                )
                self.assertEqual(40, report["parsing"]["valid_pairs"])
                self.assertEqual(interval, report["frame_interval_ms"]["max"])
                self.assertEqual(2, report["observed_stall_pairs_over_150ms"])
                self.assertFalse(report["passed"])

    def test_ambiguous_startup_evidence_preserves_large_interval_and_fails(self) -> None:
        pairs = [(31176111.89, 0.0)] * 2 + [(16.667, 0.5)] * 67
        cases = {
            "missing-startup": _startup_hud_log(pairs).split("\n", 1)[1],
            "future-startup": _startup_hud_log(pairs, startup_time="06:32:26.000"),
            "different-process": _startup_hud_log(pairs, batch_pid=1234),
            "partial-first-batch": _startup_hud_log(pairs, frame_number=1000),
            "possible-real-nine-hour-stall": _startup_hud_log(
                pairs, startup_time="00:00:00.000", batch_time="09:00:00.000"
            ),
        }
        for reason, log in cases.items():
            with self.subTest(reason=reason):
                report = parse_metal_hud.build_report(log)
                self.assertEqual(69, report["parsing"]["valid_pairs"])
                self.assertEqual(0, report["parsing"]["discarded_pairs"])
                self.assertEqual(31176111.89, report["frame_interval_ms"]["max"])
                self.assertFalse(report["passed"])

    def test_initial_real_stalls_and_nonzero_gpu_never_receive_clock_exception(self) -> None:
        for interval, gpu_time in [(151.0, 0.0), (325.0, 0.0), (3000.0, 0.0),
                                   (90000.0, 0.0), (31176111.89, 0.5)]:
            with self.subTest(interval=interval, gpu_time=gpu_time):
                pairs = [(interval, gpu_time)] * 2 + [(16.667, 0.5)] * 67
                report = parse_metal_hud.build_report(_startup_hud_log(pairs))
                self.assertEqual(0, report["parsing"]["discarded_pairs"])
                self.assertEqual(interval, report["frame_interval_ms"]["max"])
                self.assertFalse(report["passed"])

    def test_out_of_order_timestamped_batches_fail_integrity_even_with_fast_samples(self) -> None:
        pairs = [(31176111.89, 0.0)] * 2 + [(16.667, 0.5)] * 67
        log = _startup_hud_log(pairs) + (
            "2026-09-07 06:32:24.000 QIX GAME[90679:732435] "
            "metal-HUD: 65,62.75,255.83,16.667,0.5\n"
        )
        report = parse_metal_hud.build_report(log)
        self.assertFalse(report["checks"]["no_malformed_hud_lines"])
        self.assertFalse(report["passed"])

    def test_large_zero_gpu_interval_after_first_pair_is_a_real_stall(self) -> None:
        for interval in [151.0, 3000.0, 31176111.89, 2527005586.86]:
            with self.subTest(interval=interval):
                report = parse_metal_hud.build_report(
                    _hud_log([16.667] * 39 + [interval], [0.5] * 39 + [0.0])
                )
                self.assertEqual(40, report["parsing"]["valid_pairs"])
                self.assertEqual(0, report["parsing"]["discarded_pairs"])
                self.assertEqual(interval, report["frame_interval_ms"]["max"])
                self.assertFalse(report["passed"])

    def test_valid_log_discards_clock_prefix_and_builds_passing_report(self) -> None:
        intervals = [2527005586.86] * 2 + [16.0 + (index % 4) * 0.2 for index in range(40)]
        gpu_times = [0.0] * 2 + [0.35 + (index % 5) * 0.05 for index in range(40)]

        report = parse_metal_hud.build_report(
            _startup_hud_log(list(zip(intervals, gpu_times)), frame_number=21)
        )

        self.assertEqual("qix.shipping.metal-hud.v1", report["schema"])
        self.assertTrue(report["passed"])
        self.assertEqual("passed", report["outcome"])
        self.assertEqual(40, report["parsing"]["valid_pairs"])
        self.assertEqual(2, report["parsing"]["discarded_pairs"])
        self.assertEqual(
            2,
            report["parsing"]["discarded_reasons"]["initial_clock_marker"],
        )
        self.assertEqual(40, report["frame_interval_ms"]["sample_count"])
        self.assertAlmostEqual(16.3, report["frame_interval_ms"]["mean"])
        self.assertAlmostEqual(0.45, report["gpu_time_ms"]["mean"])
        self.assertTrue(report["checks"]["no_malformed_hud_lines"])
        self.assertTrue(report["checks"]["no_unpaired_metrics"])
        self.assertTrue(all(report["checks"].values()))

    def test_frame_interval_above_250ms_is_preserved_and_fails_stall_gate(self) -> None:
        intervals = [16.667] * 39 + [325.0]
        # A CPU/frame-pacing stall can have no GPU work.  Zero GPU time must
        # not make an ordinary 325 ms interval look like a clock marker.
        gpu_times = [0.5] * 39 + [0.0]

        report = parse_metal_hud.build_report(_hud_log(intervals, gpu_times))

        self.assertEqual(40, report["parsing"]["valid_pairs"])
        self.assertEqual(0, report["parsing"]["discarded_pairs"])
        self.assertEqual(325.0, report["frame_interval_ms"]["max"])
        self.assertEqual(1, report["observed_stall_pairs_over_150ms"])
        self.assertFalse(report["checks"]["frame_interval_max_within_budget"])
        self.assertFalse(report["passed"])

    def test_log_without_metal_hud_lines_is_a_diagnostic_failure(self) -> None:
        report = parse_metal_hud.build_report("ordinary engine output\n")

        self.assertFalse(report["passed"])
        self.assertEqual("failed", report["outcome"])
        self.assertEqual(0, report["parsing"]["hud_lines"])
        self.assertFalse(report["checks"]["metal_hud_lines_present"])
        self.assertFalse(report["checks"]["minimum_valid_pairs"])
        self.assertFalse(report["checks"]["nonzero_gpu_signal"])
        self.assertIn("metal_hud_lines_present", report["failed_checks"])

    def test_malformed_payloads_are_counted_and_never_inflate_sample_count(self) -> None:
        malformed = "\n".join(
            [
                "metal-HUD: not-a-frame,40,200,16.0,0.5",
                "metal-HUD: 10,40,200,16.0",
                "metal-HUD: 11,40,200,nan,0.5,16.0,-0.1,0,0.2",
                "metal-HUD: 12,40,200,16.0,not-a-gpu",
                "metal-HUD: 13,40,200,16.0,0.4",
            ]
        )

        report = parse_metal_hud.build_report(malformed)

        self.assertFalse(report["passed"])
        self.assertEqual(5, report["parsing"]["hud_lines"])
        self.assertGreaterEqual(report["parsing"]["malformed_hud_lines"], 2)
        self.assertEqual(1, report["parsing"]["valid_pairs"])
        self.assertEqual(4, report["parsing"]["discarded_pairs"])
        self.assertEqual(1, report["parsing"]["discarded_reasons"]["non_finite"])
        self.assertEqual(1, report["parsing"]["discarded_reasons"]["negative_gpu_time"])
        self.assertEqual(
            1,
            report["parsing"]["discarded_reasons"]["interval_out_of_range"],
        )
        self.assertEqual(1, report["parsing"]["discarded_reasons"]["non_numeric"])

    def test_orphan_metric_fails_integrity_gate_despite_32_valid_pairs(self) -> None:
        lines = _hud_log([16.667] * 32, [0.5] * 32).splitlines()
        lines[-1] += ",orphan-token"

        report = parse_metal_hud.build_report("\n".join(lines) + "\n")

        self.assertEqual(32, report["parsing"]["valid_pairs"])
        self.assertEqual(1, report["parsing"]["malformed_hud_lines"])
        self.assertEqual(1, report["parsing"]["unpaired_metrics"])
        self.assertTrue(report["checks"]["minimum_valid_pairs"])
        self.assertFalse(report["checks"]["no_malformed_hud_lines"])
        self.assertFalse(report["checks"]["no_unpaired_metrics"])
        self.assertFalse(report["passed"])
        self.assertIn("no_malformed_hud_lines", report["failed_checks"])
        self.assertIn("no_unpaired_metrics", report["failed_checks"])

    def test_sufficient_samples_fail_each_explicit_performance_budget(self) -> None:
        intervals = [30.0] * 37 + [45.0, 80.0, 151.0]
        gpu_times = [9.0] * 37 + [12.0, 17.0, 20.0]

        report = parse_metal_hud.build_report(_hud_log(intervals, gpu_times))

        self.assertFalse(report["passed"])
        self.assertTrue(report["checks"]["minimum_valid_pairs"])
        self.assertTrue(report["checks"]["nonzero_gpu_signal"])
        self.assertFalse(report["checks"]["gpu_p95_within_budget"])
        self.assertFalse(report["checks"]["gpu_max_within_budget"])
        self.assertFalse(report["checks"]["frame_interval_p95_within_budget"])
        self.assertFalse(report["checks"]["frame_interval_p99_within_budget"])
        self.assertFalse(report["checks"]["frame_interval_max_within_budget"])


class MetalHudCliTests(unittest.TestCase):
    def test_cli_writes_atomic_json_and_returns_zero_for_passing_log(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            input_path = root / "metal-hud.log"
            output_path = root / "report" / "metal-hud.json"
            input_path.write_text(
                _hud_log([16.667] * 32, [0.5] * 32),
                encoding="utf-8",
            )

            exit_code = parse_metal_hud.main(
                ["--input", str(input_path), "--output", str(output_path)]
            )

            self.assertEqual(0, exit_code)
            report = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertTrue(report["passed"])
            self.assertEqual(str(input_path), report["input"])
            self.assertEqual([], list(output_path.parent.glob(f".{output_path.name}.*.tmp")))

    def test_cli_writes_failure_report_and_returns_one_when_gate_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            input_path = root / "slow.log"
            output_path = root / "slow.json"
            input_path.write_text(
                _hud_log([30.0] * 32, [9.0] * 32),
                encoding="utf-8",
            )

            exit_code = parse_metal_hud.main(
                ["--input", str(input_path), "--output", str(output_path)]
            )

            self.assertEqual(1, exit_code)
            self.assertFalse(json.loads(output_path.read_text(encoding="utf-8"))["passed"])

    def test_cli_returns_nonzero_for_missing_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            output_path = root / "never-created.json"
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                exit_code = parse_metal_hud.main(
                    [
                        "--input",
                        str(root / "missing.log"),
                        "--output",
                        str(output_path),
                    ]
                )

            self.assertEqual(2, exit_code)
            self.assertFalse(output_path.exists())
            self.assertIn("unable to read Metal HUD log", stderr.getvalue())

    def test_cli_returns_nonzero_when_atomic_output_cannot_be_created(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            input_path = root / "metal-hud.log"
            blocked_parent = root / "not-a-directory"
            input_path.write_text(
                _hud_log([16.0] * 32, [0.5] * 32),
                encoding="utf-8",
            )
            blocked_parent.write_text("occupied", encoding="utf-8")
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                exit_code = parse_metal_hud.main(
                    [
                        "--input",
                        str(input_path),
                        "--output",
                        str(blocked_parent / "report.json"),
                    ]
                )

            self.assertEqual(2, exit_code)
            self.assertIn("unable to write Metal HUD report", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
