# -*- coding: utf-8 -*-
"""
=====================================================================
 Google Colab Experiment — rPPG Heart-Rate (NurseNet)
=====================================================================
Remote Photoplethysmography (rPPG): estimates heart rate from a short
facial video WITHOUT any sensor contact.

Pipeline (identical to backend/app/core/rppg.py):
  1. Decode video with OpenCV, track largest frontal face (Haar cascade)
  2. Isolate forehead ROI (15%-42% of face height)
  3. Average GREEN channel per frame -> raw PPG trace
  4. Detrend -> Butterworth band-pass 0.7-4.0 Hz -> Hanning window
  5. FFT -> peak with parabolic interpolation -> BPM + quality score

Libraries used (all preinstalled on Colab):
  opencv-python-headless : video decode, face detection, image ops
  numpy                  : arrays, FFT (np.fft.rfft)
  scipy                  : detrend, Butterworth filter (sosfiltfilt)
  matplotlib/seaborn     : thesis plots

NOTE ON AUTHORSHIP (for the thesis):
  The rPPG *technique* is established research methodology (Verkruysse
  et al., 2008). The *implementation* in this project is custom code
  written for NurseNet — it is NOT copied from a single library.
  Standard building blocks used: OpenCV Haar cascade (face detection),
  scipy Butterworth filter, numpy FFT. Describe it in the thesis as:
  "a custom rPPG pipeline implemented on top of standard computer-
  vision and signal-processing libraries".

HOW TO USE:
  1. Colab -> New notebook -> paste this file (or split at '# %%')
  2. Runtime -> Run all  (CELL 2 asks you to upload an .mp4 video)
  3. Record a video FIRST: face inside frame, 8+ seconds, good light,
     minimal motion — same rules as the mobile app.
  4. Download plots/CSVs from the Files panel.
=====================================================================
"""

# %% ==================== CELL 1: INSTALLS + IMPORTS ====================
# OpenCV 5.x removed cv2.CascadeClassifier. We pin opencv 4.x and make
# sure a STALE cv2 (already imported earlier in this session) cannot
# shadow the fresh install: purge sys.modules + importlib caches first.
import subprocess, sys, importlib

def _pip(*args):
    r = subprocess.run([sys.executable, "-m", "pip", *args],
                       capture_output=True, text=True)
    print("$ pip", " ".join(args))
    print((r.stdout or "")[-400:] + (r.stderr or "")[-400:])
    return r.returncode

# 1) remove every opencv variant that could conflict
for pkg in ["opencv-python", "opencv-python-headless",
            "opencv-contrib-python", "opencv-contrib-python-headless"]:
    _pip("uninstall", "-y", pkg)

# 2) force a clean install of the LAST 4.x (has CascadeClassifier)
_pip("install", "--force-reinstall", "--no-cache-dir",
     "opencv-python-headless<5")

# 3) purge any previously-imported cv2 so `import cv2` reloads from disk
for m in [m for m in list(sys.modules)
          if m == "cv2" or m.startswith("cv2.")]:
    del sys.modules[m]
try:
    importlib.invalidate_caches()
except Exception:
    pass

import os
import cv2

print("cv2 version:", cv2.__version__)
print("cv2 file   :", cv2.__file__)
print("has CascadeClassifier:", hasattr(cv2, "CascadeClassifier"))
if not hasattr(cv2, "CascadeClassifier"):
    raise RuntimeError(
        "OpenCV 4.x did not load correctly. Do: "
        "Runtime -> Restart session, then Run all again.")

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import signal as scipy_signal
from dataclasses import dataclass
from pathlib import Path
# (numpy, scipy, pandas, matplotlib, seaborn are preinstalled on Colab)

FACE_CASCADE_PATH = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"

# ---- Constants: IDENTICAL to backend/app/core/rppg.py ----
MIN_DURATION_SECONDS = 5.0
MIN_FPS = 10.0
MIN_FACE_RATIO = 0.5
MIN_BRIGHTNESS = 40.0
MAX_BRIGHTNESS = 245.0
MAX_MOTION_FRACTION = 0.35
BAND_LOW_HZ = 0.7    # 42 bpm
BAND_HIGH_HZ = 4.0   # 240 bpm
MIN_BPM = 40.0
MAX_BPM = 200.0
MIN_QUALITY = 0.25
PEAK_WINDOW_HZ = 0.25
DETECTION_INTERVAL = 3
ANALYSIS_WIDTH = 480


class RppgError(Exception):
    """A measurement failure with a message the patient can act on."""

    def __init__(self, code, message, suggestion=None, status_code=422):
        super().__init__(message)
        self.code = code
        self.message = message
        self.suggestion = suggestion
        self.status_code = status_code


@dataclass
class RppgMeasurement:
    bpm: int
    quality: float
    duration_seconds: float
    face_ratio: float
    frames: int
    mean_brightness: float

    def to_dict(self):
        return {
            "bpm": self.bpm,
            "quality": round(self.quality, 3),
            "duration_seconds": round(self.duration_seconds, 2),
            "face_ratio": round(self.face_ratio, 3),
            "frames": self.frames,
            "mean_brightness": round(self.mean_brightness, 1),
        }


# %% ==================== CELL 2: UPLOAD VIDEO ====================
# Colab cannot use the phone camera — upload a recorded .mp4 instead.
# Same capture rules as the app: 8+ seconds, face centered, good light.
from google.colab import files

print("Upload your facial video (.mp4) recorded for the app:")
uploaded = files.upload()          # opens a file picker
VIDEO_PATH = next(iter(uploaded))  # first uploaded filename
print(f"Uploaded: {VIDEO_PATH}  ({os.path.getsize(VIDEO_PATH)/1e6:.1f} MB)")

# Quick sanity check that OpenCV can open it
cap_test = cv2.VideoCapture(VIDEO_PATH)
print(f"OpenCV opened: {cap_test.isOpened()} | "
      f"fps={cap_test.get(cv2.CAP_PROP_FPS):.1f} | "
      f"frames={int(cap_test.get(cv2.CAP_PROP_FRAME_COUNT))}")
cap_test.release()


# %% ==================== CELL 3: rPPG PIPELINE ====================
# VERBATIM copy of backend/app/core/rppg.py — same functions, same
# constants, same math => identical results to production.

def _load_detector():
    detector = cv2.CascadeClassifier(str(FACE_CASCADE_PATH))
    if detector.empty():
        raise RppgError("detector_unavailable",
                        "Face detector failed to load.")
    return detector


def _forehead_roi(face):
    """Forehead band: 15%-42% of face height, trimmed horizontally."""
    x, y, width, height = face
    top = y + int(round(height * 0.15))
    bottom = y + int(round(height * 0.42))
    left = x + int(round(width * 0.22))
    right = x + int(round(width * 0.78))
    top = max(top, 0)
    left = max(left, 0)
    return left, top, max(right - left, 0), max(bottom - top, 0)


def _band_pass(green, fps):
    """Detrend + Butterworth band-pass into the cardiac band."""
    nyquist = fps / 2.0
    high = min(BAND_HIGH_HZ, nyquist * 0.9)
    if high <= BAND_LOW_HZ:
        raise RppgError("low_frame_rate", "Frame rate too low.")
    sos = scipy_signal.butter(
        3, [BAND_LOW_HZ, high], btype="bandpass", fs=fps, output="sos")
    padlen = min(3 * (2 * len(sos) + 1), len(green) - 1)
    if padlen < 1:
        raise RppgError("too_short", "Video too short.")
    return scipy_signal.sosfiltfilt(sos, green, padlen=padlen)


def estimate_bpm_from_signal(green, fps):
    """Estimate (bpm, quality) from a green-channel trace at `fps`."""
    samples = np.asarray(green, dtype=np.float64).ravel()
    samples = samples[np.isfinite(samples)]
    if fps <= 0 or samples.size / fps < MIN_DURATION_SECONDS:
        raise RppgError("too_short", "Video too short.")

    samples = scipy_signal.detrend(samples - samples.mean())
    filtered = _band_pass(samples, fps)
    filtered = filtered * np.hanning(filtered.size)

    fft_size = 1 << int(np.ceil(np.log2(max(filtered.size * 8, 2048))))
    fft_size = min(fft_size, 16384)
    power = np.abs(np.fft.rfft(filtered, n=fft_size)) ** 2
    freqs = np.fft.rfftfreq(fft_size, d=1.0 / fps)

    band = (freqs >= BAND_LOW_HZ) & (freqs <= min(BAND_HIGH_HZ, fps / 2.0))
    if not band.any() or power[band].sum() <= 0:
        raise RppgError("low_quality", "Signal too weak.")

    band_freqs = freqs[band]
    band_power = power[band]
    peak_index = int(np.argmax(band_power))
    peak_freq = band_freqs[peak_index]

    # Parabolic interpolation refines frequency resolution.
    if 0 < peak_index < len(power) - 1:
        left, centre, right = power[peak_index - 1:peak_index + 2]
        denominator = left - 2 * centre + right
        if denominator != 0:
            offset = 0.5 * (left - right) / denominator
            offset = float(np.clip(offset, -0.5, 0.5))
            peak_freq += offset * (freqs[1] - freqs[0])

    bpm = peak_freq * 60.0
    near_peak = np.abs(band_freqs - peak_freq) <= PEAK_WINDOW_HZ
    quality = float(band_power[near_peak].sum() / band_power.sum())

    if not (MIN_BPM <= bpm <= MAX_BPM):
        raise RppgError("out_of_range", "Reading out of range.")
    if quality < MIN_QUALITY:
        raise RppgError("low_quality", "Signal quality too low.")

    return int(round(bpm)), quality


def _extract_trace(capture, detector):
    """Walk the video once -> green trace + health metrics."""
    fps = float(capture.get(cv2.CAP_PROP_FPS) or 0)
    if fps <= 1:
        fps = 30.0

    greens, motions = [], []
    face_hits = 0
    detection_attempts = 0
    last_hit_frame = -10**9
    processed = 0
    box = None
    previous_gray = None

    while True:
        ok, frame = capture.read()
        if not ok or frame is None:
            break

        if frame.shape[1] > ANALYSIS_WIDTH:
            scale = ANALYSIS_WIDTH / float(frame.shape[1])
            frame = cv2.resize(
                frame,
                (ANALYSIS_WIDTH, max(int(frame.shape[0] * scale), 1)),
                interpolation=cv2.INTER_AREA)

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        if processed % DETECTION_INTERVAL == 0 or box is None:
            detection_attempts += 1
            faces = detector.detectMultiScale(
                cv2.equalizeHist(gray),
                scaleFactor=1.15, minNeighbors=5, minSize=(80, 80))
            if len(faces) > 0:
                box = max(faces, key=lambda f: int(f[2]) * int(f[3]))
                last_hit_frame = processed
                face_hits += 1

        if box is not None and processed - last_hit_frame > fps:
            box = None

        if box is not None:
            left, top, width, height = _forehead_roi(box)
            if (width >= 8 and height >= 8 and
                    top + height <= gray.shape[0] and
                    left + width <= gray.shape[1]):
                roi = frame[top:top + height, left:left + width]
                gray_roi = gray[top:top + height, left:left + width]
                greens.append(float(np.mean(roi[:, :, 1])))  # BGR -> green=1
                if (previous_gray is not None and
                        previous_gray.shape == gray_roi.shape):
                    motions.append(float(np.mean(
                        np.abs(gray_roi.astype(np.int16) - previous_gray))))
                else:
                    motions.append(0.0)
                previous_gray = gray_roi.astype(np.int16)

        processed += 1

    return (fps, greens, motions,
            face_hits / max(detection_attempts, 1), processed)


def analyse_video_with_details(path):
    """Same as _analyse_video but ALSO returns intermediates for plots."""
    detector = _load_detector()
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        raise RppgError("unreadable_video", "Cannot open video file.")
    capture.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    try:
        fps, greens, motions, face_ratio, frames = _extract_trace(capture, detector)
    finally:
        capture.release()

    if not greens:
        raise RppgError("no_face", "No face detected.")
    duration = len(greens) / fps
    if duration < MIN_DURATION_SECONDS:
        raise RppgError("too_short", "Video too short.")
    if fps < MIN_FPS:
        raise RppgError("low_frame_rate", "Frame rate too low.")
    if face_ratio < MIN_FACE_RATIO:
        raise RppgError("face_lost", "Face lost during recording.")

    brightness = float(np.mean(greens))
    if brightness < MIN_BRIGHTNESS:
        raise RppgError("too_dark", "Too dark.")
    if brightness > MAX_BRIGHTNESS:
        raise RppgError("too_bright", "Too bright.")

    motion = np.asarray(motions, dtype=np.float64)
    if motion.size and float(np.mean(motion > 6.0)) > MAX_MOTION_FRACTION:
        raise RppgError("too_much_motion", "Too much motion.")

    green_arr = np.asarray(greens)
    bpm, quality = estimate_bpm_from_signal(green_arr, fps)

    # Recompute intermediates for plotting (same math as the estimator)
    samples = scipy_signal.detrend(green_arr - green_arr.mean())
    filtered = _band_pass(samples, fps)
    filtered_win = filtered * np.hanning(filtered.size)
    fft_size = 1 << int(np.ceil(np.log2(max(filtered.size * 8, 2048))))
    fft_size = min(fft_size, 16384)
    power = np.abs(np.fft.rfft(filtered_win, n=fft_size)) ** 2
    freqs = np.fft.rfftfreq(fft_size, d=1.0 / fps)

    meas = RppgMeasurement(
        bpm=bpm, quality=quality, duration_seconds=duration,
        face_ratio=face_ratio, frames=frames, mean_brightness=brightness)
    details = dict(fps=fps, greens=green_arr, filtered=filtered,
                   filtered_win=filtered_win, freqs=freqs, power=power,
                   duration=duration)
    return meas, details


# %% ==================== CELL 4: RUN ANALYSIS ====================
try:
    measurement, D = analyse_video_with_details(VIDEO_PATH)
    print("=" * 55)
    print("rPPG MEASUREMENT RESULT")
    print("=" * 55)
    for k, v in measurement.to_dict().items():
        print(f"  {k:20s}: {v}")
    print("=" * 55)
except RppgError as e:
    print(f"MEASUREMENT FAILED [{e.code}]: {e.message}")
    print(f"Suggestion: {e.suggestion}")
    measurement, D = None, None


# %% ==================== CELL 5: SIGNAL PLOTS ====================
if D is not None:
    t = np.arange(len(D["greens"])) / D["fps"]

    # --- Plot 1: raw green trace vs band-passed signal ---
    fig, axes = plt.subplots(2, 1, figsize=(12, 7), sharex=True)
    axes[0].plot(t, D["greens"], color="#1a73e8", lw=0.8)
    axes[0].set_title("Raw Green-Channel PPG Trace (forehead ROI)", fontsize=12)
    axes[0].set_ylabel("Mean green intensity")
    axes[1].plot(t, D["filtered"], color="#d93025", lw=0.9)
    axes[1].set_title("Band-Passed Signal (0.7-4.0 Hz cardiac band)",
                      fontsize=12)
    axes[1].set_xlabel("Time (s)")
    axes[1].set_ylabel("Filtered intensity")
    plt.tight_layout()
    plt.savefig("rppg_signals.png", dpi=150, bbox_inches="tight")
    plt.show()

    # --- Plot 2: FFT power spectrum with cardiac band + peak ---
    freqs, power = D["freqs"], D["power"]
    fig, ax = plt.subplots(figsize=(11, 5))
    ax.plot(freqs, power, color="#1a73e8", lw=0.9)
    ax.axvspan(BAND_LOW_HZ, BAND_HIGH_HZ, color="#34a853", alpha=0.15,
               label="Cardiac band (0.7-4.0 Hz)")
    peak_freq = measurement.bpm / 60.0
    ax.axvline(peak_freq, color="#d93025", ls="--", lw=1.5,
               label=f"Detected: {measurement.bpm} bpm")
    ax.set_xlim(0, min(6.0, D["fps"] / 2))
    ax.set_xlabel("Frequency (Hz)")
    ax.set_ylabel("Power")
    ax.set_title("FFT Power Spectrum - Heart-Rate Peak Detection", fontsize=12)
    ax.legend()
    plt.tight_layout()
    plt.savefig("rppg_spectrum.png", dpi=150, bbox_inches="tight")
    plt.show()

    # --- Plot 3: face + forehead ROI overlay on a middle frame ---
    cap = cv2.VideoCapture(VIDEO_PATH)
    cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.set(cv2.CAP_PROP_POS_FRAMES, max(total // 2, 0))
    ok, frame = cap.read()
    cap.release()
    if ok:
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        det = _load_detector()
        faces = det.detectMultiScale(cv2.equalizeHist(gray),
                                     scaleFactor=1.15, minNeighbors=5,
                                     minSize=(80, 80))
        vis = frame.copy()
        if len(faces):
            box = max(faces, key=lambda f: int(f[2]) * int(f[3]))
            l, t2, w, h = _forehead_roi(tuple(box))
            cv2.rectangle(vis, (box[0], box[1]),
                          (box[0] + box[2], box[1] + box[3]),
                          (0, 255, 0), 2)
            cv2.rectangle(vis, (l, t2), (l + w, t2 + h),
                          (0, 0, 255), 2)
            cv2.putText(vis, "face", (box[0], box[1] - 6),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
            cv2.putText(vis, "forehead ROI", (l, t2 - 6),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
        vis_rgb = cv2.cvtColor(vis, cv2.COLOR_BGR2RGB)
        plt.figure(figsize=(8, 6))
        plt.imshow(vis_rgb)
        plt.title("Face Detection + Forehead ROI", fontsize=12)
        plt.axis("off")
        plt.tight_layout()
        plt.savefig("rppg_roi.png", dpi=150, bbox_inches="tight")
        plt.show()


# %% ==================== CELL 6: THESIS TABLES ====================
if measurement is not None:
    row = {
        "Metric": ["Heart Rate (BPM)", "Quality Score", "Duration (s)",
                   "Face Detection Ratio", "Frames Processed",
                   "Mean Brightness", "FPS"],
        "Value": [measurement.bpm, round(measurement.quality, 3),
                  round(measurement.duration_seconds, 2),
                  round(measurement.face_ratio, 3), measurement.frames,
                  round(measurement.mean_brightness, 1),
                  round(D["fps"], 1)],
    }
    res_df = pd.DataFrame(row)
    print("=" * 60)
    print("RESULTS TABLE (paste into thesis)")
    print("=" * 60)
    print(res_df.to_string(index=False))
    res_df.to_csv("rppg_results.csv", index=False)

    # Markdown version for Word/Google Docs
    md = ["| Metric | Value |", "|---|---|"]
    for _, r in res_df.iterrows():
        md.append(f"| {r['Metric']} | {r['Value']} |")
    with open("rppg_results.md", "w", encoding="utf-8") as f:
        f.write("\n".join(md))
    print("\n--- Markdown ---")
    print("\n".join(md))
    print("\nSaved: rppg_results.csv / .md")


# %% ==================== CELL 7: ACCURACY EVALUATION (optional) ====================
# To prove accuracy in the thesis: record N videos, measure the REAL
# heart rate with a pulse oximeter / watch / manual count, then fill
# ground_truth below and run — you get MAE, RMSE and % within +/-5 bpm.
#
# Example:
#   results = [
#       {"video": "v1.mp4", "pred_bpm": 72, "true_bpm": 74},
#       {"video": "v2.mp4", "pred_bpm": 81, "true_bpm": 80},
#   ]
#   evaluate(results)

def evaluate(results):
    """results: list of dicts with pred_bpm and true_bpm."""
    if not results:
        print("No results provided.")
        return
    df = pd.DataFrame(results)
    df["error"] = df["pred_bpm"] - df["true_bpm"]
    df["abs_error"] = df["error"].abs()
    mae = df["abs_error"].mean()
    rmse = float(np.sqrt((df["error"] ** 2).mean()))
    within5 = float((df["abs_error"] <= 5).mean() * 100)
    within10 = float((df["abs_error"] <= 10).mean() * 100)
    summary = pd.DataFrame({
        "Metric": ["Samples", "MAE (bpm)", "RMSE (bpm)",
                   "Within +/-5 bpm (%)", "Within +/-10 bpm (%)",
                   "Mean |error|"],
        "Value": [len(df), round(mae, 2), round(rmse, 2),
                  round(within5, 1), round(within10, 1),
                  round(df["abs_error"].mean(), 2)],
    })
    print("=" * 60)
    print("rPPG ACCURACY EVALUATION vs GROUND TRUTH")
    print("=" * 60)
    print(df.to_string(index=False))
    print("-" * 60)
    print(summary.to_string(index=False))
    df.to_csv("rppg_evaluation.csv", index=False)
    summary.to_csv("rppg_evaluation_summary.csv", index=False)
    print("\nSaved: rppg_evaluation.csv / rppg_evaluation_summary.csv")


# %% ==================== CELL 8: THESIS NARRATIVE ====================
print("=" * 70)
print("WHAT IS rPPG? (paragraph you can adapt for the thesis)")
print("=" * 70)
print("""
Remote photoplethysmography (rPPG) is a non-contact technique that
estimates heart rate from a short facial video. With every heartbeat,
a pulse wave travels through the facial blood vessels and modulates the
amount of light absorbed and reflected by the skin (~1% intensity
change). Because haemoglobin absorbs green light strongly, the green
channel of a standard camera is the most sensitive to this modulation.

Our pipeline detects the largest frontal face with an OpenCV Haar
cascade, isolates the forehead region (15%-42% of face height, free of
hair and eyebrows), and averages the green channel per frame to obtain
a raw PPG trace. The trace is then detrended, band-pass filtered with
a 3rd-order Butterworth filter (0.7-4.0 Hz = 42-240 bpm), windowed with
a Hanning function, and transformed with an FFT. The cardiac frequency
is the spectral peak inside the band, refined by parabolic
interpolation; beats per minute = peak frequency x 60. A quality score
(share of in-band power concentrated around the peak) rejects noisy
measurements below 0.25.

The implementation is custom project code built on standard open-
source libraries (OpenCV, NumPy, SciPy) — the same building blocks a
researcher would use, assembled into a validated medical-adjacent
measurement pipeline with explicit failure modes (no face, low light,
excessive motion, short duration).
""")
print("=" * 70)
print("Files to download from the Files panel:")
print("  rppg_signals.png      - raw vs filtered PPG trace")
print("  rppg_spectrum.png     - FFT spectrum with detected peak")
print("  rppg_roi.png          - face + forehead ROI overlay")
print("  rppg_results.csv/.md  - measurement metrics table")
print("  rppg_evaluation*.csv  - accuracy vs ground truth (CELL 7)")
print("=" * 70)

# %% ==================== EOF ====================
print("Done. Paste outputs into your thesis results chapter.")
# Colab: Runtime -> Run all. Nothing else needed.