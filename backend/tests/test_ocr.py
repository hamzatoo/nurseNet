"""Unit tests for the prescription OCR pipeline (app/api/ocr.py).

These tests cover the pure logic layer - JSON extraction, frequency/type
mapping, medication normalisation, noise filtering and the Tesseract pattern
parser - WITHOUT calling Gemini or Tesseract. They run offline:

    cd backend
    python -m pytest tests/test_ocr.py -v

The module is loaded directly from file so importing it does not pull in the
FastAPI app or the sklearn models.
"""

import importlib.util
import os
import sys
from pathlib import Path

import pytest

OCR_PATH = Path(__file__).resolve().parent.parent / "app" / "api" / "ocr.py"


def _load_ocr():
    spec = importlib.util.spec_from_file_location("ocr_module", OCR_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ocr = _load_ocr()


# ---------------------------------------------------------------------------
# _extract_json_object
# ---------------------------------------------------------------------------

class TestExtractJsonObject:
    def test_plain_object(self):
        assert ocr._extract_json_object('{"a": 1}') == {"a": 1}

    def test_markdown_fenced(self):
        text = '```json\n{"medications": []}\n```'
        assert ocr._extract_json_object(text) == {"medications": []}

    def test_fenced_without_lang(self):
        text = '```\n{"a": 2}\n```'
        assert ocr._extract_json_object(text) == {"a": 2}

    def test_surrounding_prose(self):
        text = 'Here is the result: {"a": 3} hope this helps'
        assert ocr._extract_json_object(text) == {"a": 3}

    def test_no_json(self):
        assert ocr._extract_json_object("no json here") is None

    def test_empty(self):
        assert ocr._extract_json_object("") is None
        assert ocr._extract_json_object(None) is None

    def test_broken_json(self):
        assert ocr._extract_json_object('{"a": }') is None


# ---------------------------------------------------------------------------
# _map_gemini_frequency / _map_gemini_type
# ---------------------------------------------------------------------------

class TestFrequencyMapping:
    @pytest.mark.parametrize("text,expected", [
        ("مرتين يومياً", "twice_daily"),
        ("ثلاث مرات يومياً", "three_times_daily"),
        ("كل 8 ساعات", "three_times_daily"),
        ("أربع مرات", "four_times_daily"),
        ("مرة واحدة يومياً", "once_daily"),
        ("عند الحاجة", "as_needed"),
        ("prn", "as_needed"),
        ("أسبوعياً", "weekly"),
        ("شهرياً", "monthly"),
        ("twice daily", "twice_daily"),
        ("", "once_daily"),          # empty -> safe default
        ("كل شيء غريب", "once_daily"),  # unknown -> safe default
    ])
    def test_mapping(self, text, expected):
        assert ocr._map_gemini_frequency(text) == expected


class TestTypeMapping:
    @pytest.mark.parametrize("text,expected", [
        ("tablet", "tablet"),
        ("قرص", "tablet"),
        ("syrup", "syrup"),
        ("شراب", "syrup"),
        ("injection", "injection"),
        ("حقنة", "injection"),
        ("cream", "cream"),
        ("كريم", "cream"),
        ("", "other"),
        ("unknown-xyz", "other"),
    ])
    def test_mapping(self, text, expected):
        assert ocr._map_gemini_type(text) == expected


# ---------------------------------------------------------------------------
# _normalise_gemini_medications
# ---------------------------------------------------------------------------

class TestNormaliseGemications:
    def test_valid_medication(self):
        meds = ocr._normalise_gemications if hasattr(ocr, "_normalise_gemications") else ocr._normalise_gemini_medications
        raw = [{
            "medication_name": "Augmentin",
            "type": "tablet",
            "dosage": "1g",
            "frequency": "ثلاث مرات يومياً",
            "instructions": "بعد الطعام",
            "unclear_or_notes": "",
        }]
        out = ocr._normalise_gemini_medications(raw)
        assert len(out) == 1
        m = out[0]
        assert m["name"] == "Augmentin"
        assert m["medication_name"] == "Augmentin"
        assert m["frequency"] == "three_times_daily"
        assert m["type"] == "tablet"
        assert m["scheduled_times"] == ["08:00", "14:00", "20:00"]

    def test_skips_empty_names(self):
        out = ocr._normalise_gemini_medications([{"dosage": "5mg"}, {"medication_name": "  "}])
        assert out == []

    def test_unmapped_frequency_preserved_in_instructions(self):
        out = ocr._normalise_gemini_medications([{
            "medication_name": "X",
            "frequency": "كل ساعتين",
            "instructions": "",
        }])
        assert out[0]["frequency"] == "once_daily"
        assert "كل ساعتين" in out[0]["instructions"]

    def test_non_list_input(self):
        assert ocr._normalise_gemini_medications(None) == []
        assert ocr._normalise_gemini_medications("not a list") == []
        assert ocr._normalise_gemini_medications([42, "x", None]) == []

    def test_unclear_notes_kept(self):
        out = ocr._normalise_gemini_medications([{
            "medication_name": "Panadol",
            "unclear_or_notes": "الجرعة غير واضحة",
        }])
        assert out[0]["unclear_or_notes"] == "الجرعة غير واضحة"


# ---------------------------------------------------------------------------
# _calculate_scheduled_times
# ---------------------------------------------------------------------------

class TestScheduledTimes:
    def test_all_frequencies(self):
        assert ocr._calculate_scheduled_times("once_daily") == ["08:00"]
        assert ocr._calculate_scheduled_times("twice_daily") == ["08:00", "20:00"]
        assert ocr._calculate_scheduled_times("three_times_daily") == [
            "08:00", "14:00", "20:00"]
        assert ocr._calculate_scheduled_times("four_times_daily") == [
            "06:00", "12:00", "18:00", "00:00"]
        assert ocr._calculate_scheduled_times("as_needed") == []
        assert ocr._calculate_scheduled_times("weekly") == ["08:00"]
        assert ocr._calculate_scheduled_times("unknown") == ["08:00"]


# ---------------------------------------------------------------------------
# _is_noise_line
# ---------------------------------------------------------------------------

class TestNoiseFiltering:
    @pytest.mark.parametrize("line", [
        "",
        "   ",
        "+963 944 123 456",
        "12/05/2024",
        "د. أحمد محمد",
        "عيادة النور الطبية",
        "صفحة 2",
        "---",
        "42",
        "Ro",
    ])
    def test_noise_lines(self, line):
        assert ocr._is_noise_line(line) is True

    @pytest.mark.parametrize("line", [
        "Augmentin 1g",
        "باراسيتامول 500mg",
        "مرتين يومياً بعد الطعام",
    ])
    def test_content_lines(self, line):
        assert ocr._is_noise_line(line) is False


# ---------------------------------------------------------------------------
# _parse_medications_from_text (Tesseract fallback parser)
# ---------------------------------------------------------------------------

class TestTesseractParser:
    def test_extracts_known_medication(self):
        text = "Augmentin 1g\nثلاث مرات يومياً بعد الطعام"
        meds = ocr._parse_medications_from_text(text)
        assert len(meds) == 1
        assert "Augmentin" in meds[0]["name"] or "augmentin" in meds[0]["name"].lower()
        assert meds[0]["frequency"] == "three_times_daily"

    def test_skips_doctor_noise(self):
        text = "د. سارة أحمد\nعيادة الشفاء\nAugmentin 500mg مرتين يومياً"
        meds = ocr._parse_medications_from_text(text)
        names = [m["name"].lower() for m in meds]
        assert all("د." not in n and "عيادة" not in n for n in names)

    def test_empty_text(self):
        assert ocr._parse_medications_from_text("") == []
        assert ocr._parse_medications_from_text("   \n  \n") == []


# ---------------------------------------------------------------------------
# _extract_duration
# ---------------------------------------------------------------------------

class TestDuration:
    @pytest.mark.parametrize("text,expected", [
        ("لمدة 7 أيام", 7),
        ("for 2 weeks", 14),
        ("لمدة 1 شهر", 30),
        ("for 1 month", 30),
        ("no duration here", None),
    ])
    def test_duration(self, text, expected):
        assert ocr._extract_duration(text) == expected


# ---------------------------------------------------------------------------
# Gemini availability (no real API calls)
# ---------------------------------------------------------------------------

class TestGeminiAvailability:
    def test_no_key_returns_none(self, monkeypatch):
        monkeypatch.delenv("GEMINI_API_KEY", raising=False)
        # force cache reset
        ocr._gemini_model_cache = None
        assert ocr._gemini_model() is None
        assert ocr._run_gemini("nonexistent.jpg", []) is None

    def test_run_gemini_never_raises_on_bad_path(self, monkeypatch):
        monkeypatch.setenv("GEMINI_API_KEY", "fake-key-for-test")
        ocr._gemini_model_cache = None
        warnings = []
        # whatever happens (no package / bad key / missing file) -> None, no raise
        result = ocr._run_gemini("/path/that/does/not/exist.jpg", warnings)
        assert result is None
        assert isinstance(warnings, list)
