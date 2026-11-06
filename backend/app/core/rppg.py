"""Contactless heart-rate estimation from a short facial video (rPPG).

Pipeline
--------
1. Decode the video with OpenCV and track the largest frontal face.
2. Isolate the forehead, where the blood-volume pulse modulates skin colour most.
3. Average the green channel inside that region for every frame, which yields a
   noisy 1-D signal (the raw PPG trace).
4. Detrend, band-pass filter to the plausible cardiac band (0.7-4.0 Hz), then
   take the FFT peak with parabolic interpolation to get beats per minute.

The module raises :class:`RppgError` for anything the user can act on
(unreadable video, no face, bad lighting, excessive motion, low quality) so the
API layer can return a clear message instead of a stack trace.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from scipy import signal as scipy_signal

FACE_CASCADE_PATH = Path(cv2.data.haarcascades) / "haarcascade_frontalface_default.xml"

# A measurement shorter than this cannot resolve a heart rate reliably.
MIN_DURATION_SECONDS = 5.0
MIN_FPS = 10.0
# Fraction of frames in which a face must be found.
MIN_FACE_RATIO = 0.5
# Mean ROI brightness (0-255). Below this the sensor is mostly noise.
MIN_BRIGHTNESS = 40.0
MAX_BRIGHTNESS = 245.0
MAX_MOTION_FRACTION = 0.35

BAND_LOW_HZ = 0.7  # 42 bpm
BAND_HIGH_HZ = 4.0  # 240 bpm
MIN_BPM = 40.0
MAX_BPM = 200.0
# Share of in-band power that must sit around the winning peak. Independent of
# the FFT length, unlike a single-bin ratio: clean pulses land near 0.9, sensor
# noise near 0.15.
MIN_QUALITY = 0.25
PEAK_WINDOW_HZ = 0.25

# Run the cascade on every third frame: the head barely moves within 100 ms,
# and this keeps an 8-second clip well under a second of CPU time.
DETECTION_INTERVAL = 3
ANALYSIS_WIDTH = 480


class RppgError(Exception):
    """A measurement failure with a message the patient can act on."""

    def __init__(
        self,
        code: str,
        message: str,
        suggestion: str | None = None,
        status_code: int = 422,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.suggestion = suggestion
        self.status_code = status_code


@dataclass
class RppgMeasurement:
    """Result of a successful measurement."""

    bpm: int
    quality: float
    duration_seconds: float
    face_ratio: float
    frames: int
    mean_brightness: float

    def to_dict(self) -> dict:
        return {
            "bpm": self.bpm,
            "quality": round(self.quality, 3),
            "duration_seconds": round(self.duration_seconds, 2),
            "face_ratio": round(self.face_ratio, 3),
            "frames": self.frames,
            "mean_brightness": round(self.mean_brightness, 1),
        }


def _load_detector() -> cv2.CascadeClassifier:
    detector = cv2.CascadeClassifier(str(FACE_CASCADE_PATH))
    if detector.empty():
        raise RppgError(
            "detector_unavailable",
            "تعذّر تحميل نموذج اكتشاف الوجه على الخادم.",
            "أعد المحاولة بعد قليل أو تواصل مع الدعم الفني.",
            status_code=503,
        )
    return detector


def _forehead_roi(face: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    """Return the forehead rectangle that sits inside a detected face box.

    The forehead is the band between 15% and 42% of the face height, trimmed
    horizontally so eyebrows, hair and background pixels stay out.
    """
    x, y, width, height = face
    top = y + int(round(height * 0.15))
    bottom = y + int(round(height * 0.42))
    left = x + int(round(width * 0.22))
    right = x + int(round(width * 0.78))

    top = max(top, 0)
    left = max(left, 0)
    return left, top, max(right - left, 0), max(bottom - top, 0)


def _band_pass(green: np.ndarray, fps: float) -> np.ndarray:
    """Detrend and band-pass the raw trace into the cardiac band."""
    nyquist = fps / 2.0
    high = min(BAND_HIGH_HZ, nyquist * 0.9)
    if high <= BAND_LOW_HZ:
        raise RppgError(
            "low_frame_rate",
            "معدل إطارات الفيديو منخفض جداً لتحليل النبض.",
            "أعد التصوير في إضاءة أفضل مع تثبيت الهاتف.",
        )

    sos = scipy_signal.butter(
        3, [BAND_LOW_HZ, high], btype="bandpass", fs=fps, output="sos"
    )
    # filtfilt needs the trace to be longer than the padding it applies.
    padlen = min(3 * (2 * len(sos) + 1), len(green) - 1)
    if padlen < 1:
        raise RppgError(
            "too_short",
            "مدة الفيديو قصيرة جداً لحساب النبض.",
            "أعد التصوير لمدة لا تقل عن 6 ثوانٍ.",
        )
    return scipy_signal.sosfiltfilt(sos, green, padlen=padlen)


def estimate_bpm_from_signal(green: np.ndarray, fps: float) -> tuple[int, float]:
    """Estimate (bpm, quality) from a green-channel trace sampled at ``fps``.

    ``quality`` is the share of in-band spectral power that falls on the winning
    peak: near 1 for a clean pulse, near 0 for noise. It is the value the app
    uses to decide whether a reading is trustworthy.
    """
    samples = np.asarray(green, dtype=np.float64).ravel()
    samples = samples[np.isfinite(samples)]
    if fps <= 0 or samples.size / fps < MIN_DURATION_SECONDS:
        raise RppgError(
            "too_short",
            "مدة الفيديو قصيرة جداً لحساب النبض.",
            "أعد التصوير لمدة لا تقل عن 6 ثوانٍ.",
        )

    samples = scipy_signal.detrend(samples - samples.mean())
    filtered = _band_pass(samples, fps)
    filtered = filtered * np.hanning(filtered.size)

    fft_size = 1 << int(np.ceil(np.log2(max(filtered.size * 8, 2048))))
    fft_size = min(fft_size, 16384)
    power = np.abs(np.fft.rfft(filtered, n=fft_size)) ** 2
    freqs = np.fft.rfftfreq(fft_size, d=1.0 / fps)

    band = (freqs >= BAND_LOW_HZ) & (freqs <= min(BAND_HIGH_HZ, fps / 2.0))
    if not band.any() or power[band].sum() <= 0:
        raise RppgError(
            "low_quality",
            "الإشارة ضعيفة جداً لحساب نبض موثوق.",
            "حاول مرة أخرى في إضاءة أقوى وبوجه ثابت.",
        )

    band_freqs = freqs[band]
    band_power = power[band]
    peak_index = int(np.argmax(band_power))
    peak_freq = band_freqs[peak_index]

    # Parabolic interpolation around the peak refines the frequency resolution.
    if 0 < peak_index < len(power) - 1:
        left, centre, right = power[peak_index - 1 : peak_index + 2]
        denominator = left - 2 * centre + right
        if denominator != 0:
            offset = 0.5 * (left - right) / denominator
            offset = float(np.clip(offset, -0.5, 0.5))
            peak_freq += offset * (freqs[1] - freqs[0])

    bpm = peak_freq * 60.0
    near_peak = np.abs(band_freqs - peak_freq) <= PEAK_WINDOW_HZ
    quality = float(band_power[near_peak].sum() / band_power.sum())

    if not (MIN_BPM <= bpm <= MAX_BPM):
        raise RppgError(
            "out_of_range",
            "القراءة الناتجة خارج النطاق الطبيعي للقياس.",
            "أعد التصوير مع تثبيت الوجه وبإضاءة جيدة.",
        )
    if quality < MIN_QUALITY:
        raise RppgError(
            "low_quality",
            "جودة الإشارة منخفضة، لذلك لا يمكن الوثوق بالقراءة.",
            "قرّب الهاتف قليلاً، واستقرّ تماماً، وتأكد من الإضاءة.",
        )

    return int(round(bpm)), quality


def _extract_trace(capture: cv2.VideoCapture, detector: cv2.CascadeClassifier):
    """Walk the video once, returning the green trace and its health metrics."""
    fps = float(capture.get(cv2.CAP_PROP_FPS) or 0)
    if fps <= 1:
        fps = 30.0

    greens: list[float] = []
    motions: list[float] = []
    face_hits = 0
    detection_attempts = 0
    last_hit_frame = -10**9
    processed = 0
    box: tuple[int, int, int, int] | None = None
    previous_gray: np.ndarray | None = None

    while True:
        ok, frame = capture.read()
        if not ok or frame is None:
            break

        if frame.shape[1] > ANALYSIS_WIDTH:
            scale = ANALYSIS_WIDTH / float(frame.shape[1])
            frame = cv2.resize(
                frame,
                (ANALYSIS_WIDTH, max(int(frame.shape[0] * scale), 1)),
                interpolation=cv2.INTER_AREA,
            )

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        if processed % DETECTION_INTERVAL == 0 or box is None:
            detection_attempts += 1
            faces = detector.detectMultiScale(
                cv2.equalizeHist(gray),
                scaleFactor=1.15,
                minNeighbors=5,
                minSize=(80, 80),
            )
            if len(faces) > 0:
                # Largest face wins: the patient is expected to fill the guide.
                box = max(faces, key=lambda face: int(face[2]) * int(face[3]))
                last_hit_frame = processed
                face_hits += 1

        # Drop a stale box: sampling the background would poison the trace.
        if box is not None and processed - last_hit_frame > fps:
            box = None

        if box is not None:
            left, top, width, height = _forehead_roi(box)
            if width >= 8 and height >= 8 and (
                top + height <= gray.shape[0] and left + width <= gray.shape[1]
            ):
                roi = frame[top : top + height, left : left + width]
                gray_roi = gray[top : top + height, left : left + width]
                # OpenCV uses BGR: channel 1 is green.
                greens.append(float(np.mean(roi[:, :, 1])))
                if previous_gray is not None and previous_gray.shape == gray_roi.shape:
                    motions.append(
                        float(np.mean(np.abs(gray_roi.astype(np.int16) - previous_gray)))
                    )
                else:
                    motions.append(0.0)
                previous_gray = gray_roi.astype(np.int16)

        processed += 1

    return (
        fps,
        greens,
        motions,
        face_hits / max(detection_attempts, 1),
        processed,
    )


def _analyse_video(path: str) -> RppgMeasurement:
    detector = _load_detector()
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        raise RppgError(
            "unreadable_video",
            "تعذّر فتح ملف الفيديو.",
            "أعد تسجيل الفيديو وحاول مرة أخرى.",
            status_code=400,
        )

    # Phones store rotation as container metadata; without this the frames arrive
    # sideways and the frontal-face cascade finds nothing.
    capture.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)

    try:
        fps, greens, motions, face_ratio, frames = _extract_trace(capture, detector)
    finally:
        capture.release()

    if not greens:
        raise RppgError(
            "no_face",
            "لم يتم اكتشاف وجه واضح في الفيديو.",
            "ضع وجهك داخل الإطار، في إضاءة جيدة، ثم أعد المحاولة.",
        )

    duration = len(greens) / fps
    if duration < MIN_DURATION_SECONDS:
        raise RppgError(
            "too_short",
            "مدة الفيديو قصيرة جداً لحساب النبض.",
            "أعد التصوير لمدة لا تقل عن 6 ثوانٍ.",
        )
    if fps < MIN_FPS:
        raise RppgError(
            "low_frame_rate",
            "معدل إطارات الفيديو منخفض جداً لتحليل النبض.",
            "استخدم الكاميرا الخلفية أو أمامية بجودة أعلى.",
        )
    if face_ratio < MIN_FACE_RATIO:
        raise RppgError(
            "face_lost",
            "فقدنا وجهك أثناء التصوير.",
            "ثبّت وجهك داخل الدائرة طوال مدة القياس.",
        )

    brightness = float(np.mean(greens))
    if brightness < MIN_BRIGHTNESS:
        raise RppgError(
            "too_dark",
            "الإضاءة ضعيفة جداً لقياس النبض.",
            "قف قرب نافذة أو في غرفة مضيئة، وتجنّب الإضاءة الخلفية القوية.",
        )
    if brightness > MAX_BRIGHTNESS:
        raise RppgError(
            "too_bright",
            "الإضاءة قوية جداً (انعكاس مباشر على البشرة).",
            "ابتعد عن مصدر ضوء مباشر موجه إلى وجهك.",
        )

    motion = np.asarray(motions, dtype=np.float64)
    if motion.size and float(np.mean(motion > 6.0)) > MAX_MOTION_FRACTION:
        raise RppgError(
            "too_much_motion",
            "تحرّكت كثيراً أثناء القياس.",
            "اجلس بثبات واستند على سطح مستقر أثناء التصوير.",
        )

    bpm, quality = estimate_bpm_from_signal(np.asarray(greens), fps)
    return RppgMeasurement(
        bpm=bpm,
        quality=quality,
        duration_seconds=duration,
        face_ratio=face_ratio,
        frames=frames,
        mean_brightness=brightness,
    )


def analyse_video_file(path: str) -> RppgMeasurement:
    """Analyse a saved video file. Never leaves a capture handle open."""
    try:
        return _analyse_video(path)
    except RppgError:
        raise
    except cv2.error as exc:  # corrupt container, unsupported codec, ...
        raise RppgError(
            "invalid_video",
            "ملف الفيديو غير صالح أو غير مدعوم.",
            "أعد تسجيل الفيديو بصيغة MP4.",
            status_code=400,
        ) from exc
    except Exception as exc:  # noqa: BLE001 - surfaced as a clean API error
        raise RppgError(
            "processing_failed",
            "حدث خطأ أثناء تحليل الفيديو.",
            "أعد المحاولة، وإذا تكرر الخطأ أبلغ الدعم الفني.",
            status_code=500,
        ) from exc
