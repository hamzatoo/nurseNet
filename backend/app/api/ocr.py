"""AI Prescription OCR endpoint - extracts medications from prescription images.

Supports bilingual (Arabic + English) prescriptions and filters out
non-medication noise (doctor names, clinic headers, stamps, phones, dates)
before structured extraction.
"""

from __future__ import annotations

import os
import re
import tempfile
from typing import Optional

from fastapi import APIRouter, File, UploadFile
from fastapi.responses import JSONResponse

# easyocr pulls in PyTorch (~2 GB RAM) which exceeds free-tier hosting limits.
# It is only used when ENABLE_EASYOCR=true is set on a machine with enough RAM.
_ENABLE_EASYOCR = os.environ.get("ENABLE_EASYOCR", "false").lower() == "true"

router = APIRouter(prefix="/api", tags=["ocr"])

MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB
ALLOWED_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
# Mobile clients (image_picker cache files) often send application/octet-stream
# because the cached file has no recognised extension - accept it and verify
# the actual image bytes with Pillow instead of trusting the header.
ALLOWED_CONTENT_TYPES = {"application/octet-stream", "binary/octet-stream"}

# ---------------------------------------------------------------------------
# Medication knowledge base (Arabic + English, common in the region)
# ---------------------------------------------------------------------------
MEDICATION_KEYWORDS = [
    # Antibiotics
    "amoxicillin", "أموكسيسيلين", "amoxycillin", "أموكسيسيلين",
    "augmentin", "أوجمنتين", "azithromycin", "ازيثروميسين", "zithromax", "زيثروماكس",
    "ciprofloxacin", "سيبروفلوكساسين", "levofloxacin", "ليفوفلوكساسين",
    "ceftriaxone", "سيفترياكسون", "cefixime", "سيفيكسيم", "cephalexin", "سيفالكسين",
    "doxycycline", "دوكسيسيكلين", "metronidazole", "ميترونيدازول", "flagyl", "فلاجيل",
    "clindamycin", "كليندامايسين", "penicillin", "بنيسيلين", "ampicillin", "أمبيسيلين",
    # Analgesics / Antipyretics
    "paracetamol", "باراسيتامول", "acetaminophen", "أسيتامينوفين",
    "ibuprofen", "ايبوبروفين", "brufen", "بروفين", "nurofen", "نوروفين",
    "aspirin", "أسبرين", "diclofenac", "ديكلوفيناك", "voltaren", "فولتارين",
    "tramadol", "ترامادول", "morphine", "مورفين", "codeine", "كودايين",
    # Chronic disease
    "metformin", "ميتفورمين", "glucophage", "جلوكوفاج", "gliclazide", "جليكلازيد",
    "amlodipine", "املوديبين", "norvasc", "نورفاسك", "losartan", "لوزارتان",
    "valsartan", "فالسارتان", "telmisartan", "تلمسارتان", "atenolol", "أتينولول",
    "metoprolol", "ميتوبرولول", "propranolol", "بروبرانولول",
    "atorvastatin", "اتورفاستاتين", "lipitor", "ليبيتور", "rosuvastatin", "روسوفاستاتين",
    "omeprazole", "اوميبرازول", "losec", "لوسك", "pantoprazole", "بانتوبرازول",
    "ranitidine", "رانتدين", "antacid", "مضاد للحموضة",
    # Respiratory / Allergy
    "salbutamol", "سالبوتامول", "ventolin", "فنتولين", "budesonide", "بيكلوميتازون",
    "cetirizine", "سيتريزين", "zyrtec", "زيرتك", "loratadine", "لوراتادين",
    "claritine", "كلاريتين", "fexofenadine", "فيكسوفينادين", "desloratadine", "ديسلوراتادين",
    "montelukast", "مونتيلوكاست", "singulair", "سينغولير",
    # Chronic conditions
    "insulin", "أنسولين", "metformin", "ميتفورمين", "gliclazide", "جليكلازيد",
    "warfarin", "وارفارين", "aspirin", "أسبرين", "clopidogrel", "كلوبيدوغريل",
    "levothyroxine", "ليفوثيروكسين", "synthroid", "سينثرويد",
    # Psychiatric / Neurological
    "sertraline", "سيرترالين", "zoloft", "زولوفت", "fluoxetine", "فلوكستين",
    "prozac", "بروزاك", "escitalopram", "اسيتالوبرام", "lexapro", "ليكسيبرو",
    "alprazolam", "ألبرازولام", "xanax", "زانكس", "diazepam", "ديازيبام",
    "gabapentin", "جابابنتين", "neurontin", "نيورونتين", "pregabalin", "بريجابالين",
    "levodopa", "ليفودوبا", "madopar", "مادوبار", "carbidopa", "كاربيدوبا",
    # GI / Other
    "loperamide", "لوبيراميد", "imodium", "إيموديوم", "ondansetron", "أوندانسترون",
    "domperidone", "دومبيريدون", "motilium", "موتيليوم", "lactulose", "لاكتولوز",
    "bisacodyl", "بيساكوديل", "senna", "سينا", "suppository", "لبوس",
    # Vitamins / Supplements
    "vitamin d", "فيتامين د", "calcium", "كالسيوم", "iron", "حديد", "folic acid", "حمض الفوليك",
    "multivitamin", "مالتي فيتامين", "omega", "أوميغا", "zinc", "زنك",
    # Topical
    "hydrocortisone", "هيدروكورتيزون", "betamethasone", "بيتاميثازون",
    "mupirocin", "موبيروسين", "fusidic acid", "حمض الفوسيديك",
]

# Frequency patterns - order matters: check specific before generic
FREQUENCY_PATTERNS = [
    # Specific multi-word patterns first
    ("four_times_daily", [
        "أربع مرات", "4 مرات", "أربع حبات", "4 حبات", "q.i.d", "qid",
        "four times", "every 6 hours", "كل 6 ساعات",
    ]),
    ("three_times_daily", [
        "ثلاث مرات", "3 مرات", "ثلاث حبات", "3 حبات", "t.i.d", "tid",
        "ثلاث مرات يومياً", "three times", "every 8 hours", "كل 8 ساعات",
    ]),
    ("twice_daily", [
        "مرتين", "2 مرات", "صباحاً ومساءً", "صباحا ومساءا", "twice",
        "كل 12 ساعة", "b.i.d", "bid", "b.d", "بعد الفطور والعشاء",
    ]),
    ("once_daily", [
        "مرة واحدة", "مرة يومياً", "مرة يوميا", "يومياً", "يوميا", "كل يوم",
        "once", "daily", "q.d", "qd", "صباحاً", "صباحا",
    ]),
    ("as_needed", [
        "عند الحاجة", "عند اللزوم", "عند الضرورة", "prn", "as needed",
        "عند الألم", "عند الشعور",
    ]),
    ("weekly", ["أسبوعياً", "اسبوعياً", "weekly", "once a week"]),
    ("monthly", ["شهرياً", "شهريا", "monthly", "once a month"]),
]

# Dosage patterns: number + unit (English or Arabic)
DOSAGE_PATTERN = re.compile(
    r"(\d+(?:[.,]\d+)?)\s*"
    r"(mg|ml|g|mcg|ug|iu|وحدة|حبة|قرص|كبسولة|قطرة|بخاخ|ملعقة|شراب|"
    r"tablet|capsule|drop|puff|unit|ampoule)s?",
    re.IGNORECASE,
)

# Standalone number before unit word
DOSAGE_NUMBER_PATTERN = re.compile(
    r"(\d+(?:[.,]\d+)?)\s*(?:mg|ml|g|mcg|وحدة|حبة|قرص|كبسولة|قطرة)",
    re.IGNORECASE,
)

DURATION_PATTERN = re.compile(
    r"(?:لمدة|مدة|duration|for|يستمر|يُستخدم)\s*(\d+)\s*"
    r"(يوم|أيام|يومًا|يومًا|شهر|أشهر|أسبوع|أسابيع|اسبوع|اسابيع|"
    r"week|weeks|month|months|day|days)s?",
    re.IGNORECASE,
)

# Instructions / timing patterns (expanded)
INSTRUCTION_PATTERNS = [
    # Before meals
    ("قبل الأكل", ["قبل الأكل", "قبل الطعام", "قبل الفطور", "قبل الغداء",
                    "قبل العشاء", "ac", "before meal", "on empty stomach",
                    "على معدة فارغة", "قبل الأكل بساعة"]),
    # After meals
    ("بعد الأكل", ["بعد الأكل", "بعد الطعام", "بعد الفطور", "بعد الغداء",
                    "بعد العشاء", "pc", "after meal", "مع الأكل",
                    "بعد الأكل مباشرة"]),
    # Specific times
    ("صباحاً", ["صباحاً", "صباحا", "في الصباح", "morning"]),
    ("مساءً", ["مساءً", "مساءا", "في المساء", "evening"]),
    ("ليلاً", ["ليلاً", "ليلا", "في الليل", "at night", "before bed", "قبل النوم"]),
    ("عند الحاجة", ["عند الحاجة", "عند اللزوم", "عند الألم", "عند الشعور"]),
    ("مع وجبة", ["مع وجبة", "مع الطعام", "with food", "with meal"]),
]

# Type detection keywords (no empty strings!)
TYPE_KEYWORDS = {
    "injection": ["حقنة", "حقن", "إبرة", "ابر", "injection", "inject", "iv", "im", "sc"],
    "syrup": ["شراب", "syrup", "sirop", "suspension", "معلق"],
    "drops": ["قطرة", "قطرات", "drop", "drops", "goutte", "eyedrop", "ear drop"],
    "inhaler": ["بخاخ", "inhaler", "inhale", "puff", "nebulizer", "نيبولايزر"],
    "cream": ["مرهم", "كريم", "cream", "ointment", "gel", "لصق", "patch"],
    "capsule": ["كبسولة", "كبسولات", "capsule", "capsules", "gélule"],
    "tablet": ["قرص", "أقراص", "حبوب", "tablet", "tablets", "pill", "حب"],
    "suppository": ["لبوس", "suppository", "تحميلة"],
}

# ---------------------------------------------------------------------------
# Noise filtering patterns - lines to IGNORE
# ---------------------------------------------------------------------------
NOISE_PATTERNS = [
    # Phone numbers
    re.compile(r"^\+?\d[\d\s\-()]{6,}\d$"),
    # Dates (various formats)
    re.compile(r"^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$"),
    re.compile(r"^\d{1,2}\s+(يناير|فبراير|مارس|أبريل|مايو|يونيو|يوليو|أغسطس|سبتمبر|أكتوبر|نوفمبر|ديسمبر)"),
    # Page numbers
    re.compile(r"^(صفحة|page)\s*\d+", re.IGNORECASE),
    # Doctor names / titles
    re.compile(r"^(د\.\s*|دكتور|دكتورة|Dr\.?|Doctor|Physician)\s+\S+", re.IGNORECASE),
    # Clinic/hospital names
    re.compile(r"(عيادة|مستشفى|مركز|طبي|clinic|hospital|medical|health|center|centre)", re.IGNORECASE),
    # Stamps / signatures / watermarks
    re.compile(r"(ختم|معتمد|signed|signature|stamp|official|نسخة)", re.IGNORECASE),
    # Pure numbers or very short lines
    re.compile(r"^\d+$"),
    re.compile(r"^[-_=*.]{3,}$"),  # separator lines
    # Prescription headers (keep? no - they're noise)
    re.compile(r"^(روشتة|وصفة|prescription|rx|Rp)\b", re.IGNORECASE),
    # Age/weight lines that aren't medications
    re.compile(r"^(العمر|الوزن|age|weight|طول|طول):?\s*\d+", re.IGNORECASE),
]

# Lines that indicate end of medication list (doctor signature area)
SIGNATURE_INDICATORS = [
    "التوقيع", "signature", "الطبيب", "doctor", "معالج",
]


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
    return (
        content_type.startswith("image/")
        or content_type in ALLOWED_CONTENT_TYPES
        or not content_type
    )


def _is_valid_image(image_path: str) -> bool:
    """Verify the uploaded bytes are a decodable image via Pillow."""
    try:
        from PIL import Image
        with Image.open(image_path) as img:
            img.verify()
        return True
    except Exception:
        return False


def _preprocess_image(image_path: str) -> str:
    """Preprocess image for better OCR: grayscale, contrast, denoise, upscale."""
    try:
        import cv2
        import numpy as np

        img = cv2.imread(image_path)
        if img is None:
            return image_path

        # Convert to grayscale
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

        # Upscale if image is small (OCR needs ~300 DPI equivalent)
        h, w = gray.shape
        if max(h, w) < 1500:
            scale = 1500 / max(h, w)
            gray = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)

        # Denoise
        gray = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)

        # Contrast enhancement (CLAHE)
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        gray = clahe.apply(gray)

        # Binarize with Otsu for cleaner text
        _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

        # Save preprocessed image
        preprocessed_path = image_path + "_preprocessed.png"
        cv2.imwrite(preprocessed_path, binary)
        return preprocessed_path
    except Exception:
        return image_path


def _extract_text_from_image(image_path: str) -> str:
    """Extract text using pytesseract with Arabic+English support."""
    text_parts = []
    processed_path = None

    try:
        import pytesseract
        from PIL import Image

        # Preprocess for better OCR accuracy
        processed_path = _preprocess_image(image_path)
        img = Image.open(processed_path if processed_path else image_path)

        # Try Arabic+English combined first (most common for prescriptions)
        try:
            text = pytesseract.image_to_string(img, lang="ara+eng")
        except Exception:
            # Fallback to English only if Arabic data missing
            try:
                text = pytesseract.image_to_string(img, lang="eng")
            except Exception:
                text = pytesseract.image_to_string(img)

        if text.strip():
            text_parts.append(text)

        # Also try without preprocessing as backup (sometimes thresholding hurts)
        if not text.strip():
            img_orig = Image.open(image_path)
            try:
                text2 = pytesseract.image_to_string(img_orig, lang="ara+eng")
            except Exception:
                try:
                    text2 = pytesseract.image_to_string(img_orig, lang="eng")
                except Exception:
                    text2 = pytesseract.image_to_string(img_orig)
            if text2.strip():
                text_parts.append(text2)

    except ImportError:
        pass
    except Exception:
        pass
    finally:
        # Clean up preprocessed file
        if processed_path and os.path.exists(processed_path):
            try:
                os.unlink(processed_path)
            except OSError:
                pass

    # Optional heavy fallback: easyocr (requires ENABLE_EASYOCR=true + enough RAM)
    if not text_parts and _ENABLE_EASYOCR:
        try:
            import easyocr
            reader = easyocr.Reader(["ar", "en"], gpu=False)
            results = reader.readtext(image_path)
            text = " ".join([r[1] for r in results])
            if text.strip():
                text_parts.append(text)
        except Exception:
            pass

    return "\n".join(text_parts)


# ---------------------------------------------------------------------------
# Gemini Vision - PRIMARY prescription reader (handwriting + mixed AR/EN)
# ---------------------------------------------------------------------------
# GEMINI_API_KEY is read from the environment only - never hardcode it.
# The key format is owned by Google; do NOT validate its prefix or length.
_GEMINI_MODEL_NAME = os.environ.get("GEMINI_MODEL", "gemini-2.0-flash")
_gemini_model_cache = None

_GEMINI_PROMPT = """You are a medical prescription reader. The image shows a doctor's
prescription, usually HANDWRITTEN, often mixing English/Latin drug names with
Arabic dosage and usage instructions. Extract EVERY medication you can read.

Return ONLY a single valid JSON object - no markdown, no commentary:
{
  "medications": [
    {
      "medication_name": "drug name exactly as written (usually English/Latin)",
      "type": "tablet|capsule|syrup|injection|drops|inhaler|cream|suppository|other",
      "dosage": "e.g. 500mg, 5ml, one tablet - empty string if unreadable",
      "frequency": "how often, as written e.g. مرتين يومياً / كل 8 ساعات",
      "instructions": "Arabic usage notes e.g. بعد الطعام، لمدة أسبوع",
      "unclear_or_notes": "illegible words or parts needing manual review, else empty"
    }
  ],
  "duration_days": null,
  "warnings": ["short notes about unreadable/blurry areas, else empty list"],
  "notes": "one-line summary of what was read"
}

Rules:
- Read drug names as Latin/English text even if handwritten.
- Keep Arabic instruction text in Arabic.
- If a part is unreadable, put it in unclear_or_notes - do NOT guess.
- If NO medication is readable, return {"medications": [], "warnings": [...],
  "notes": "reason"}.
"""


def _gemini_model():
    """Return a configured Gemini model, or None when unavailable.

    Returns None (silent fallback to Tesseract) when the API key or the
    google-generativeai package is missing.
    """
    global _gemini_model_cache
    if _gemini_model_cache is not None:
        return _gemini_model_cache

    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not api_key:
        return None
    try:
        import google.generativeai as genai
    except ImportError:
        return None

    try:
        genai.configure(api_key=api_key)
        _gemini_model_cache = genai.GenerativeModel(_GEMINI_MODEL_NAME)
        return _gemini_model_cache
    except Exception:
        return None


def _extract_json_object(text: str):
    """Pull the first JSON object out of a model response (fences tolerated)."""
    if not text:
        return None
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    try:
        import json
        return json.loads(cleaned[start:end + 1])
    except Exception:
        return None


def _map_gemini_frequency(text: str) -> str:
    """Map free-text frequency (usually Arabic) to the app enum key."""
    t = (text or "").lower()
    for freq, patterns in FREQUENCY_PATTERNS:
        for pattern in patterns:
            if pattern.lower() in t:
                return freq
    return "once_daily"


def _map_gemini_type(text: str) -> str:
    """Map free-text type to the app type enum key."""
    t = (text or "").lower()
    for med_type, keywords in TYPE_KEYWORDS.items():
        for keyword in keywords:
            if keyword.lower() in t:
                return med_type
    return "other"


def _normalise_gemini_medications(raw_meds) -> list:
    """Coerce Gemini output into the medication dict shape the API returns."""
    meds = []
    if not isinstance(raw_meds, list):
        return meds
    for item in raw_meds:
        if not isinstance(item, dict):
            continue
        name = str(item.get("medication_name") or item.get("name") or "").strip()
        if not name:
            continue
        freq_text = str(item.get("frequency") or "")
        frequency = _map_gemini_frequency(freq_text)
        instructions = str(item.get("instructions") or "").strip()
        # Keep the original frequency wording visible when it did not map.
        if freq_text and frequency == "once_daily" and freq_text.lower() not in (
            "once", "daily", "q.d", "qd", "صباحاً", "صباحا", "يومياً", "يوميا",
            "مرة واحدة", "مرة يومياً", "مرة يوميا", "كل يوم",
        ):
            instructions = (instructions + " | التكرار: " + freq_text).strip(" |")
        type_text = str(item.get("type") or "")
        med = {
            "name": name,
            "medication_name": name,
            "dosage": str(item.get("dosage") or "").strip(),
            "type": _map_gemini_type(type_text) if type_text else "other",
            "frequency": frequency,
            "instructions": instructions,
            "unclear_or_notes": str(item.get("unclear_or_notes") or "").strip(),
            "scheduled_times": _calculate_scheduled_times(frequency),
        }
        meds.append(med)
    return meds


def _run_gemini(image_path: str, warnings: list):
    """Primary OCR path: send the image to Gemini Vision.

    Returns a dict {medications, duration_days, confidence, notes} on success,
    or None on ANY failure so the caller can fall back to Tesseract.
    Never raises - all exceptions are converted into warnings.
    """
    model = _gemini_model()
    if model is None:
        if os.environ.get("GEMINI_API_KEY"):
            warnings.append("gemini_unavailable: package or init failed")
        return None

    try:
        from PIL import Image
        img = Image.open(image_path)
        img.load()
    except Exception as exc:
        warnings.append(f"gemini_image_error: {type(exc).__name__}")
        return None

    try:
        response = model.generate_content([_GEMINI_PROMPT, img])
        text = (response.text or "").strip()
    except Exception as exc:
        # Covers network failures, 429 rate limits, 5xx, safety blocks, etc.
        warnings.append(f"gemini_request_failed: {type(exc).__name__}")
        return None

    payload = _extract_json_object(text)
    if payload is None:
        warnings.append("gemini_invalid_json")
        return None

    meds = _normalise_gemini_medications(payload.get("medications"))
    notes = str(payload.get("notes") or "")[:300]
    for w in payload.get("warnings") or []:
        warnings.append(str(w)[:200])

    duration = payload.get("duration_days")
    try:
        duration = int(duration) if duration is not None else None
    except (TypeError, ValueError):
        duration = None

    return {
        "medications": meds,
        "duration_days": duration,
        "confidence": 0.9 if meds else 0.4,
        "notes": notes,
    }


def _is_noise_line(line: str) -> bool:
    """Check if a line should be ignored (noise filtering)."""
    line_stripped = line.strip()
    if not line_stripped:
        return True

    # Check against noise patterns
    for pattern in NOISE_PATTERNS:
        if pattern.search(line_stripped):
            return True

    # Very short lines (likely noise)
    if len(line_stripped) < 3:
        return True

    # Lines that are mostly numbers/symbols
    alpha_count = sum(1 for c in line_stripped if c.isalpha() or '\u0600' <= c <= '\u06FF')
    if alpha_count < 2:
        return True

    return False


def _clean_medication_name(raw_name: str) -> str:
    """Clean up medication name - remove extra words, fix common OCR errors."""
    name = raw_name.strip()

    # Remove common OCR artifacts
    name = re.sub(r'[\[\]\(\)\{\}<>"\']', '', name)
    name = re.sub(r'\s+', ' ', name)

    # Remove leading/trailing punctuation
    name = name.strip('.,;:!?-–—')

    # Capitalize first letter for English names
    if name and name[0].isalpha() and name[0].isascii():
        name = name[0].upper() + name[1:]

    return name


def _parse_medications_from_text(text: str) -> list:
    """Parse medication information from extracted text using pattern matching.

    Handles multi-line medication entries and bilingual text.
    """
    medications = []
    lines = text.split("\n")

    current_med = None
    in_signature_area = False

    for line in lines:
        line = line.strip()
        if not line:
            continue

        # Check if we've entered signature/doctor area
        if any(indicator.lower() in line.lower() for indicator in SIGNATURE_INDICATORS):
            in_signature_area = True
            continue

        # Skip signature area entirely
        if in_signature_area:
            continue

        # Skip noise lines
        if _is_noise_line(line):
            # But don't skip if we're in the middle of a medication entry
            # and the line contains dosage/instruction info
            if current_med and not _is_noise_line(line):
                pass  # This shouldn't happen, but safety check
            continue

        # Check if line contains a medication name
        found_keyword = None
        line_lower = line.lower()
        for keyword in MEDICATION_KEYWORDS:
            if keyword.lower() in line_lower:
                found_keyword = keyword
                break

        # Also check if line starts with a capitalized word that might be a drug name
        # (for English prescriptions where drug names might not be in our list)
        if not found_keyword:
            # Look for patterns like "DrugName 500mg" or "DrugName tablet"
            med_match = re.search(
                r"^([A-Z][a-zA-Z]+)\s+\d+\s*(mg|ml|g|mcg|tablet|capsule|drop)",
                line,
                re.IGNORECASE,
            )
            if med_match:
                found_keyword = med_match.group(1)

        if found_keyword:
            # Start new medication entry
            if current_med:
                medications.append(current_med)
            current_med = {
                "name": _clean_medication_name(found_keyword),
                "dosage": "",
                "type": "other",
                "frequency": "once_daily",
                "instructions": "",
            }

        if current_med:
            # Extract dosage - try multiple patterns
            dosage_match = DOSAGE_PATTERN.search(line)
            if dosage_match and not current_med["dosage"]:
                current_med["dosage"] = dosage_match.group(0).strip()
            else:
                # Try number-only pattern
                num_match = DOSAGE_NUMBER_PATTERN.search(line)
                if num_match and not current_med["dosage"]:
                    current_med["dosage"] = num_match.group(0).strip()

            # Extract frequency (check all patterns)
            for freq, patterns in FREQUENCY_PATTERNS:
                for pattern in patterns:
                    if pattern.lower() in line_lower:
                        current_med["frequency"] = freq
                        break
                if current_med["frequency"] != "once_daily":
                    break

            # Extract instructions (check all patterns)
            for instruction, patterns in INSTRUCTION_PATTERNS:
                for pattern in patterns:
                    if pattern.lower() in line_lower:
                        if instruction not in current_med["instructions"]:
                            current_med["instructions"] = (
                                current_med["instructions"] + ", " + instruction
                            ).strip(", ")
                        break

            # Determine medication type from context
            for med_type, keywords in TYPE_KEYWORDS.items():
                for keyword in keywords:
                    if keyword.lower() in line_lower:
                        current_med["type"] = med_type
                        break
                if current_med["type"] != "other":
                    break

            # If type is still "other", try to infer from dosage unit
            if current_med["type"] == "other" and current_med["dosage"]:
                dosage_lower = current_med["dosage"].lower()
                if any(u in dosage_lower for u in ["قطرة", "drop", "goutte"]):
                    current_med["type"] = "drops"
                elif any(u in dosage_lower for u in ["كبسولة", "capsule"]):
                    current_med["type"] = "capsule"
                elif any(u in dosage_lower for u in ["شراب", "syrup", "ml"]):
                    current_med["type"] = "syrup"
                elif any(u in dosage_lower for u in ["حقنة", "injection", "ampoule"]):
                    current_med["type"] = "injection"
                elif any(u in dosage_lower for u in ["قرص", "tablet", "حبة", "حبوب"]):
                    current_med["type"] = "tablet"

    if current_med:
        medications.append(current_med)

    # Post-process: remove medications with no useful data
    medications = [
        med for med in medications
        if med["name"] and (med["dosage"] or med["frequency"] != "once_daily" or med["instructions"])
    ]

    return medications


def _extract_duration(text: str) -> Optional[int]:
    """Extract treatment duration in days from text."""
    match = DURATION_PATTERN.search(text)
    if match:
        amount = int(match.group(1))
        unit = match.group(2).lower()
        if any(u in unit for u in ["شهر", "month"]):
            return amount * 30
        elif any(u in unit for u in ["اسبوع", "week", "أسبوع"]):
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
async def ocr_prescription(
    image: UploadFile = File(...),
    engine: Optional[str] = None,
):
    """
    Extract medication information from a prescription image.

    Accepts: multipart/form-data with 'image' field
    Optional query param `engine`: "gemini" | "tesseract" | unset (auto).
    Used by the evaluation harness for A/B comparison; production clients
    leave it unset and get the automatic Gemini->Tesseract fallback.
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

        # Verify the payload is a real decodable image (magic bytes)
        if not _is_valid_image(temporary_path):
            return _error(
                "unsupported_media_type",
                "الملف المرسل ليس صورة صالحة.",
                "أعد التقاط صورة الوصفة بصيغة JPG أو PNG.",
                status_code=415,
            )

        warnings = []
        engine = None
        notes = ""
        medications = []
        duration_days = None
        confidence = 0.0
        cleaned_text = ""

        engine_param = (engine or "").lower().strip()

        # PRIMARY PATH: Gemini Vision - built for handwriting + mixed AR/EN.
        # Skipped entirely when engine=tesseract is requested (A/B testing).
        gemini_result = None
        if engine_param != "tesseract":
            gemini_result = _run_gemini(temporary_path, warnings)

        if engine_param == "gemini" and (
            gemini_result is None or not gemini_result["medications"]
        ):
            # Forced-Gemini mode (evaluation): report failure instead of
            # silently falling back so metrics stay pure.
            return _error(
                "gemini_no_result",
                "Gemini لم يتعرّف على أدوية في الصورة.",
                "حسّن جودة الصورة أو جرّب محركاً آخر.",
                status_code=422,
            )

        if gemini_result and gemini_result["medications"]:
            engine = "gemini"
            medications = gemini_result["medications"]
            duration_days = gemini_result["duration_days"]
            confidence = gemini_result["confidence"]
            notes = gemini_result["notes"]
        else:
            # FALLBACK PATH: Tesseract OCR + pattern parser (printed text).
            engine = "tesseract"
            extracted_text = _extract_text_from_image(temporary_path)

            if not extracted_text.strip():
                if gemini_result is not None:
                    # Gemini read the image but found no medication.
                    return {
                        "status": "success",
                        "medications": [],
                        "detected_duration": None,
                        "confidence": 0.0,
                        "raw_text": "",
                        "engine": "gemini",
                        "warnings": warnings,
                        "notes": gemini_result["notes"],
                        "detail": "لم يتم العثور على أدوية مقروءة في الصورة",
                    }
                return _error(
                    "no_text_detected",
                    "لم يتم العثور على نص في الصورة.",
                    "تأكد من وضوح الصورة وحاول مرة أخرى.",
                    status_code=422,
                )

            # Clean and filter the text
            cleaned_lines = [
                line for line in extracted_text.split("\n")
                if not _is_noise_line(line)
            ]
            cleaned_text = "\n".join(cleaned_lines)

            # Parse medications from cleaned text
            medications = _parse_medications_from_text(cleaned_text)

            # Extract duration
            duration_days = _extract_duration(cleaned_text)

            # Calculate confidence based on text extraction quality
            confidence = min(0.95, len(cleaned_text.split()) / 50.0) if cleaned_text else 0.0

            # Add scheduled times to each medication
            for med in medications:
                med["scheduled_times"] = _calculate_scheduled_times(med["frequency"])

        return {
            "status": "success",
            "medications": medications,
            "detected_duration": duration_days,
            "confidence": round(confidence, 2),
            "raw_text": (notes or cleaned_text)[:500],
            "engine": engine,
            "warnings": warnings,
            "notes": notes,
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
