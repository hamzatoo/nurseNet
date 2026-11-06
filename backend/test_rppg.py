"""Self-check for the rPPG heart-rate pipeline.

Usage
-----
    python test_rppg.py              # synthetic signal + error-path checks
    python test_rppg.py clip.mp4     # also analyse a real face video end-to-end
"""

from __future__ import annotations

import os
import sys
import tempfile

import cv2
import numpy as np

from app.core import rppg

FPS = 30.0
SECONDS = 8.0


def synthetic_trace(bpm: float, noise: float = 0.25, seed: int = 7) -> np.ndarray:
    """Green-channel trace of one pulse frequency plus drift and sensor noise."""
    rng = np.random.default_rng(seed)
    t = np.arange(int(FPS * SECONDS)) / FPS
    pulse = 2.0 * np.sin(2 * np.pi * (bpm / 60.0) * t)
    drift = 0.8 * np.sin(2 * np.pi * 0.08 * t)
    return 120.0 + pulse + drift + rng.normal(0, noise, t.size)


def check_synthetic() -> list[str]:
    failures: list[str] = []
    for expected in (48, 60, 72, 96, 120, 150):
        measured, quality = rppg.estimate_bpm_from_signal(
            synthetic_trace(expected), FPS
        )
        error = abs(measured - expected)
        status = "ok" if error <= 3 else "FAIL"
        print(
            f"  [{status}] {expected:>3} bpm -> {measured:>3} bpm "
            f"(quality {quality:.2f}, error {error})"
        )
        if error > 3:
            failures.append(f"{expected} bpm measured as {measured} bpm")
    return failures


def check_low_quality() -> list[str]:
    failures: list[str] = []
    rng = np.random.default_rng(3)
    noise = 120.0 + rng.normal(0, 1.0, int(FPS * SECONDS))
    try:
        rppg.estimate_bpm_from_signal(noise, FPS)
        failures.append("pure noise was accepted as a pulse")
        print("  [FAIL] pure noise accepted")
    except rppg.RppgError as error:
        print(f"  [ok] pure noise rejected with code '{error.code}'")
    return failures


def check_short_clip() -> list[str]:
    failures: list[str] = []
    try:
        rppg.estimate_bpm_from_signal(synthetic_trace(72)[:60], FPS)
        failures.append("a 2 second trace was accepted")
        print("  [FAIL] short trace accepted")
    except rppg.RppgError as error:
        print(f"  [ok] short trace rejected with code '{error.code}'")
    return failures


def check_video_without_face() -> list[str]:
    """A real MP4 with no face must fail cleanly with the 'no_face' code."""
    failures: list[str] = []
    handle, path = tempfile.mkstemp(suffix=".mp4")
    os.close(handle)
    writer = cv2.VideoWriter(
        path, cv2.VideoWriter_fourcc(*"mp4v"), FPS, (320, 240)
    )
    try:
        for _ in range(int(FPS * SECONDS)):
            writer.write(np.full((240, 320, 3), 118, dtype=np.uint8))
    finally:
        writer.release()

    try:
        rppg.analyse_video_file(path)
        failures.append("a face-less video produced a reading")
        print("  [FAIL] face-less video accepted")
    except rppg.RppgError as error:
        expected = error.code in {"no_face", "face_lost", "too_dark"}
        print(
            f"  [{'ok' if expected else 'FAIL'}] face-less video rejected "
            f"with code '{error.code}'"
        )
        if not expected:
            failures.append(f"unexpected error code '{error.code}'")
    finally:
        os.unlink(path)
    return failures


class _FullFrameDetector:
    """Stand-in detector that reports the whole frame as a face.

    Lets the test exercise decoding, ROI averaging and filtering without
    shipping a face photo or depending on the Haar model.
    """

    def detectMultiScale(self, *_args, **_kwargs):
        return np.array([[40, 60, 400, 280]], dtype=np.int32)


def check_video_pipeline() -> list[str]:
    failures: list[str] = []
    handle, path = tempfile.mkstemp(suffix=".mp4")
    os.close(handle)
    writer = cv2.VideoWriter(
        path, cv2.VideoWriter_fourcc(*"mp4v"), FPS, (480, 360)
    )
    expected = 72.0
    t = np.arange(int(FPS * SECONDS)) / FPS
    try:
        for value in t:
            frame = np.full((360, 480, 3), 128, dtype=np.uint8)
            frame[:, :, 1] = np.clip(
                128 + 4 * np.sin(2 * np.pi * (expected / 60.0) * value), 0, 255
            )
            writer.write(frame)
    finally:
        writer.release()

    original_loader = rppg._load_detector
    rppg._load_detector = lambda: _FullFrameDetector()
    try:
        measurement = rppg.analyse_video_file(path)
        error = abs(measurement.bpm - expected)
        status = "ok" if error <= 3 else "FAIL"
        print(
            f"  [{status}] video pipeline {expected:.0f} bpm -> "
            f"{measurement.bpm} bpm (quality {measurement.quality:.2f})"
        )
        if error > 3:
            failures.append(
                f"video pipeline measured {measurement.bpm} bpm for {expected:.0f}"
            )
    except rppg.RppgError as error:
        failures.append(f"video pipeline raised {error.code}: {error.message}")
        print(f"  [FAIL] video pipeline raised {error.code}")
    finally:
        rppg._load_detector = original_loader
        os.unlink(path)
    return failures


def check_real_video(path: str) -> list[str]:
    try:
        measurement = rppg.analyse_video_file(path)
    except rppg.RppgError as error:
        print(f"  [info] {error.code}: {error.message} / {error.suggestion}")
        return []
    print(
        f"  [ok] {measurement.bpm} bpm, quality {measurement.quality:.2f}, "
        f"{measurement.duration_seconds:.1f}s, face ratio {measurement.face_ratio:.2f}"
    )
    return []


def main() -> int:
    print("rPPG synthetic signal checks")
    failures = check_synthetic()
    print("rPPG rejection checks")
    failures += check_low_quality()
    failures += check_short_clip()
    failures += check_video_without_face()
    failures += check_video_pipeline()

    if len(sys.argv) > 1:
        print(f"End-to-end analysis of {sys.argv[1]}")
        failures += check_real_video(sys.argv[1])

    if failures:
        print("\nFAILURES:")
        for failure in failures:
            print(f" - {failure}")
        return 1
    print("\nAll rPPG checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
