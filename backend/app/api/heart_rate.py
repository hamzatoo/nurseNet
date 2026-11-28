"""Contactless heart-rate endpoint backed by the rPPG pipeline."""

from __future__ import annotations

import os
import tempfile
from typing import Optional

from fastapi import APIRouter, File, UploadFile
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

try:  # OpenCV is optional at import time so the rest of the API keeps working.
    from app.core import rppg
except ImportError:  # pragma: no cover - depends on the deployment image
    rppg = None  # type: ignore[assignment]

try:
    from app.core.notification_service import notification_service
except ImportError:
    notification_service = None  # Fallback if notification service not available

try:
    from app.core.firebase import db as firestore_db
except ImportError:
    firestore_db = None

router = APIRouter(prefix="/api", tags=["heart-rate"])

MAX_UPLOAD_BYTES = 80 * 1024 * 1024
MIN_UPLOAD_BYTES = 1024
ALLOWED_SUFFIXES = {".mp4", ".mov", ".m4v", ".3gp", ".avi", ".mkv", ".webm"}
ALLOWED_CONTENT_TYPES = {"application/octet-stream", "binary/octet-stream"}


def _error(
    code: str,
    message: str,
    suggestion: Optional[str] = None,
    status_code: int = 422,
) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={
            "status": "error",
            "code": code,
            "detail": message,
            "suggestion": suggestion,
        },
    )


def _suffix_for(upload: UploadFile) -> str:
    suffix = os.path.splitext(upload.filename or "")[1].lower()
    return suffix if suffix in ALLOWED_SUFFIXES else ".mp4"


def _content_type_allowed(upload: UploadFile) -> bool:
    content_type = (upload.content_type or "").lower()
    return content_type.startswith("video/") or content_type in ALLOWED_CONTENT_TYPES


@router.post("/calculate-heart-rate")
async def calculate_heart_rate(
    video: UploadFile = File(...),
    patient_id: Optional[str] = None,
):
    """Estimate the heart rate (BPM) from a 6-10 second face video.

    The clip is written to a temporary file, analysed with the rPPG pipeline in a
    worker thread, and always deleted afterwards.

    If patient_id is provided and BPM exceeds the high-risk threshold,
    a notification is sent to the assigned nurse.
    """
    if rppg is None:
        return _error(
            "engine_unavailable",
            "خدمة تحليل النبض غير متوفرة على الخادم حالياً.",
            "أبلغ الدعم الفني أو أعد المحاولة لاحقاً.",
            status_code=503,
        )

    if not _content_type_allowed(video):
        return _error(
            "unsupported_media_type",
            "نوع الملف غير مدعوم.",
            "أرسل فيديو بصيغة MP4 أو MOV.",
            status_code=415,
        )

    temporary_path = ""
    total_bytes = 0
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=_suffix_for(video)) as handle:
            temporary_path = handle.name
            while chunk := await video.read(1024 * 1024):
                total_bytes += len(chunk)
                if total_bytes > MAX_UPLOAD_BYTES:
                    return _error(
                        "file_too_large",
                        "حجم الفيديو أكبر من الحد المسموح.",
                        "أعد التصوير لمدة 8 ثوانٍ فقط.",
                        status_code=413,
                    )
                handle.write(chunk)

        if total_bytes < MIN_UPLOAD_BYTES:
            return _error(
                "empty_file",
                "لم يصل أي فيديو إلى الخادم.",
                "أعد تسجيل الفيديو وحاول مرة أخرى.",
                status_code=400,
            )

        measurement = await run_in_threadpool(rppg.analyse_video_file, temporary_path)

        # High HR alert: notify assigned nurse if threshold exceeded
        if (
            patient_id
            and notification_service
            and measurement.bpm >= notification_service.HIGH_HR_THRESHOLD
        ):
            try:
                # Fetch patient name and assigned nurse from Firestore
                if firestore_db:
                    patient_doc = firestore_db.collection("users").document(patient_id).get()
                    if patient_doc.exists:
                        patient_data = patient_doc.to_dict()
                        patient_name = patient_data.get("name", "مريض")

                        # Find assigned nurse (check active care requests)
                        requests_ref = (
                            firestore_db.collection("requests")
                            .where("patientId", "==", patient_id)
                            .where("status", "in", ["accepted", "inProgress", "matched"])
                            .limit(1)
                        )
                        assigned_request = list(requests_ref.stream())
                        if assigned_request:
                            req_data = assigned_request[0].to_dict()
                            nurse_id = req_data.get("nurseId")
                            if nurse_id:
                                # Check nurse alert preference
                                nurse_doc = firestore_db.collection("users").document(nurse_id).get()
                                if nurse_doc.exists:
                                    nurse_data = nurse_doc.to_dict()
                                    nurse_alerts_enabled = nurse_data.get("highHrAlertsEnabled", True)
                                    notification_service.send_high_hr_alert(
                                        patient_id=patient_id,
                                        patient_name=patient_name,
                                        bpm=measurement.bpm,
                                        nurse_id=nurse_id,
                                        nurse_fcm_enabled=nurse_alerts_enabled,
                                    )
            except Exception as e:
                # Don't fail the heart rate measurement if notification fails
                print(f"⚠️ Failed to send high-HR alert: {e}")

        return {
            "status": "success",
            "bpm": measurement.bpm,
            "quality": round(measurement.quality, 3),
            "duration_seconds": round(measurement.duration_seconds, 2),
            "face_ratio": round(measurement.face_ratio, 3),
            "frames": measurement.frames,
            "mean_brightness": round(measurement.mean_brightness, 1),
            "detail": "تم قياس النبض بنجاح.",
        }
    except rppg.RppgError as error:
        return _error(
            error.code,
            error.message,
            error.suggestion,
            status_code=error.status_code,
        )
    except Exception as error:  # noqa: BLE001 - never leak a stack trace to the app
        print(f"❌ Heart rate analysis failed: {error}")
        return _error(
            "processing_failed",
            "حدث خطأ غير متوقع أثناء تحليل الفيديو.",
            "أعد المحاولة بعد قليل.",
            status_code=500,
        )
    finally:
        if temporary_path and os.path.exists(temporary_path):
            try:
                os.unlink(temporary_path)
            except OSError:
                pass
