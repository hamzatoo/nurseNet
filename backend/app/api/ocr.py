"""AI Prescription OCR endpoint - extracts medications from prescription images."""

from __future__ import annotations

import os
import re
import tempfile
from typing import Optional

from fastapi import APIRouter, File, UploadFile
from fastapi.responses import JSONResponse

router = APIRouter(prefix="/api", tags=["ocr"])

MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB
ALLOWED_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp", "image/bmp"}

# Arabic + English medication keywords for rule-based extraction
MEDICATION_KEYWORDS = [
    "أموكسيسيلين", "amoxicillin", "باراسيتامول", "paracetamol", "ibuprofen",
    "ايبوبروفين", "metformin", "ميتفورمين", "amlodipine", "املوديبين",
    "atorvastatin", "اتورفاستاتين", "omeprazole", "اوميبرازول", "aspirin",
    "أسبرين", "cetirizine", "سيتريزين", "loratadine", "لوراتادين",
    "insulin", "أنسولين", "penicillin", "بنيسيلين", "azithromycin",
    "ازيثروميسين", "ciprofloxacin", "سيبروفلوكساسين", "dexamethasone",
    "ديكساميثازون", "prednisone", "بريدنيزون", "warfarin", "وارفارين",
    "losartan", "لوزارتان", "valsartan", "فالسارتان", "sertraline",
    "سيرترالين", "fluoxetine", "فلوكستين", "gabapentin", "جابابنتين",
]

FREQUENCY_PATTERNS = {
    "three_times_daily": ["ثلاث", "3 مرات", "ثلاث مرات", "three times", "tid"],
    "twice_daily": ["مرتين", "2 مرات", "مرتين يوميا", "twice", "bid"],
    "once_daily": ["مرة", "يوميا", "يومياً", "once", "daily", "qd"],
    "four_times_daily": ["أربع", "4 مرات", "أربع مرات", "qid"],
    "as_needed": ["عند الحاجة", "عند اللزوم", "prn"],
    "weekly": ["أسبوعيا", "أسبوعياً", "weekly"],
    "monthly": ["شهريا", "شهرياً", "monthly"],
}

DOSAGE_PATTERN = re.compile(
    r"(\d+(?:[.,]\d+)?)\s*(mg|ml|g|mcg|وحدة|قرص|كبسولة|حبوب|drip|وحدة|unit)s?",
    re.IGNORECASE,
)

DURATION_PATTERN = re.compile(
    r"(?:لمدة|مدة|duration|for)\s*(\d+)\s*(يوم|أيام|شهر|أشهر|اسبوع|أسابيع|week|month|day)s?",
    re.IGNORECASE,
)

TIMING_PATTERN = re.compile(
    r"(?:قبل|بعد)\s*(?:الأكل|الطعام|الأكل|الوجبة|meal|food|الفطور|الغداء|العشاء)",
    re.IGNORECASE,
)


def _error(code: str, message: str, suggestion: Optional[str] = None, status_code: int = 422) -> JSONResponse:
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
    return suffix if suffix in ALLOWED_SUFFIXES else ".jpg"


def _content_type_allowed(upload: UploadFile) -> bool:
    content_type = (upload.content_type or "").lower()
    return content_type.startswith("image/") or content_type in ALLOWED_CONTENT_TYPES


def _extract_text_from_image(image_path: str) -> str:
    """Extract text using available OCR libraries (pytesseract, easyocr, or fallback)."""
    text_parts = []

    # Try pytesseract first (best for printed text)
    try:
        import pytesseract
        from PIL import Image

        img = Image.open(image_path)
        # Try Arabic first, fallback to English
        try:
            text = pytesseract.image_to_string(img, lang="ara")
        except Exception:
            text = pytesseract.image_to_string(img, lang="eng")
        if text.strip():
            text_parts.append(text)
    except ImportError:
        pass
    except Exception:
        pass

    # Try easyocr as fallback
    if not text_parts:
        try:
            import easyocr
            reader = easyocr.Reader(["ar", "en"], gpu=False)
            results = reader.readtext(image_path)
            text = " ".join([r[1] for r in results])
            if text.strip():
                text_parts.append(text)
        except ImportError:
            pass
        except Exception:
            pass

    # Try OpenCV + Tesseract via cv2
    if not text_parts:
        try:
            import cv2
            img = cv2.imread(image_path)
            if img is not None:
                gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
                # Simple threshold for better OCR
                _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                text = pytesseract.image_to_string(thresh, lang="ara+eng")
                if text.strip():
                    text_parts.append(text)
        except Exception:
            pass

    return "\n".join(text_parts)


def _parse_medications_from_text(text: str) -> list:
    """Parse medication information from extracted text using pattern matching."""
    medications = []
    lines = text.split("\n")

    current_med = None
    for line in lines:
        line = line.strip()
        if not line:
            continue

        # Check if line contains a medication name
        found_keyword = None
        for keyword in MEDICATION_KEYWORDS:
            if keyword.lower() in line.lower():
                found_keyword = keyword
                break

        if found_keyword:
            # Start new medication entry
            if current_med:
                medications.append(current_med)
            current_med = {
                "name": found_keyword,
                "dosage": "",
                "type": "tablet",
                "frequency": "once_daily",
                "instructions": "",
            }

        if current_med:
            # Extract dosage
            dosage_match = DOSAGE_PATTERN.search(line)
            if dosage_match and not current_med["dosage"]:
                current_med["dosage"] = dosage_match.group(0)

            # Extract frequency
            for freq, patterns in FREQUENCY_PATTERNS.items():
                for pattern in patterns:
                    if pattern.lower() in line.lower():
                        current_med["frequency"] = freq
                        break

            # Extract timing/instructions
            timing_match = TIMING_PATTERN.search(line)
            if timing_match:
                current_med["instructions"] = timing_match.group(0)

            # Determine medication type from context
            if any(word in line.lower() for word in ["حقن", "injection", ""]):
                current_med["type"] = "injection"
            elif any(word in line.lower() for word in ["شراب", "syrup", "sirop"]):
                current_med["type"] = "syrup"
            elif any(word in line.lower() for word in ["قطرة", "drop", "goutte"]):
                current_med["type"] = "drops"
            elif any(word in line.lower() for word in ["كبسولة", "capsule", "gélule"]):
                current_med["type"] = "capsule"

    if current_med:
        medications.append(current_med)

    return medications


def _extract_duration(text: str) -> Optional[int]:
    """Extract treatment duration in days from text."""
    match = DURATION_PATTERN.search(text)
    if match:
        amount = int(match.group(1))
        unit = match.group(2).lower()
        if any(u in unit for u in ["شهر", "month"]):
            return amount * 30
        elif any(u in unit for u in ["اسبوع", "week"]):
            return amount * 7
        else:
            return amount
    return None


def _calculate_scheduled_times(frequency: str) -> list:
    """Calculate scheduled times based on frequency."""
    freq_map = {
        "once_daily": ["08:00"],
        "twice_daily": ["08:00", "20:00"],
        "three_times_daily": ["08:00", "14:00", "20:00"],
        "four_times_daily": ["06:00", "12:00", "18:00", "00:00"],
        "as_needed": [],
        "weekly": ["08:00"],
        "monthly": ["08:00"],
    }
    return freq_map.get(frequency, ["08:00"])


@router.post("/ocr-prescription")
async def ocr_prescription(image: UploadFile = File(...)):
    """
    Extract medication information from a prescription image.

    Accepts: multipart/form-data with 'image' field
    Returns: structured JSON with medications, duration, and confidence
    """
    if not _content_type_allowed(image):
        return _error(
            "unsupported_media_type",
            "نوع الملف غير مدعوم.",
            "أرسل صورة بصيغة JPG أو PNG.",
            status_code=415,
        )

    temporary_path = ""
    total_bytes = 0
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=_suffix_for(image)) as handle:
            temporary_path = handle.name
            while chunk := await image.read(1024 * 1024):
                total_bytes += len(chunk)
                if total_bytes > MAX_UPLOAD_BYTES:
                    return _error(
                        "file_too_large",
                        "حجم الصورة أكبر من الحد المسموح.",
                        "أرسل صورة أصغر.",
                        status_code=413,
                    )
                handle.write(chunk)

        if total_bytes < 100:
            return _error(
                "empty_file",
                "لم تصل أي صورة إلى الخادم.",
                "أعد التقاط الصورة.",
                status_code=400,
            )

        # Extract text from image
        extracted_text = _extract_text_from_image(temporary_path)

        if not extracted_text.strip():
            return _error(
                "no_text_detected",
                "لم يتم العثور على نص في الصورة.",
                "تأكد من وضوح الصورة وحاول مرة أخرى.",
                status_code=422,
            )

        # Parse medications from text
        medications = _parse_medications_from_text(extracted_text)

        # Extract duration
        duration_days = _extract_duration(extracted_text)

        # Calculate confidence based on text extraction quality
        confidence = min(0.95, len(extracted_text.split()) / 50.0) if extracted_text else 0.0

        # Add scheduled times to each medication
        for med in medications:
            med["scheduled_times"] = _calculate_scheduled_times(med["frequency"])

        return {
            "status": "success",
            "medications": medications,
            "detected_duration": duration_days,
            "confidence": round(confidence, 2),
            "raw_text": extracted_text[:500],  # First 500 chars for debugging
            "detail": f"تم استخراج {len(medications)} دواء من الوصفة",
        }

    except Exception as e:
        return _error(
            "processing_failed",
            "حدث خطأ أثناء معالجة الصورة.",
            str(e),
            status_code=500,
        )
    finally:
        if temporary_path and os.path.exists(temporary_path):
            try:
                os.unlink(temporary_path)
            except OSError:
                pass
