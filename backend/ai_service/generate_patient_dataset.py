"""
Generate a synthetic patient dataset for SVM training.

Each row = (X features, y label): patient features -> required care specialty.
The specialties match the vocabulary used in damascus_providers_fixed.csv so
the predicted label can directly filter providers at inference time.

Output: patients_dataset.csv
"""

import csv
import random

random.seed(42)

# ---------------------------------------------------------------------------
# Shared vocabularies (must stay consistent with the app + providers dataset)
# ---------------------------------------------------------------------------

LOCATIONS = [
    "المزة", "المالكي", "الشعلان", "البرامكة", "القصاع", "الميدان",
    "الزرقاء", "أبو رمانة", "المرجة", "اليعقوبية", "جوبر", "دوما",
    "حرستا", "اليرموك", "القابون", "تشرين", "السيدة زينب",
]

GENDERS = ["ذكر", "أنثى"]

# App medical categories -> sub-conditions (from patient_login_view.dart)
CATEGORY_CONDITIONS = {
    "أمراض القلب والشرايين": [
        "ارتفاع ضغط الدم", "مرض الشريان التاجي", "عدم انتظام ضربات القلب",
        "قصور القلب", "أمراض صمامات القلب",
    ],
    "الأمراض العصبية": [
        "جلطة دماغية / تاريخ جلطات", "مرض باركنسون", "التصلب اللويحي (MS)",
        "شلل (دائم أو مؤقت)", "صرع / تشنجات",
    ],
    "أمراض الكلى وغسيل الكلى": [
        "مرض الكلى المزمن (CKD)", "مريض غسيل كلى", "حصوات الكلى (متكررة)",
    ],
    "أمراض العظام والحركة": [
        "خشونة المفاصل الشديدة", "إصابة الحبل الشوكي", "بتر أطراف", "إعاقة حركية",
    ],
    "أمراض الجهاز التنفسي": [
        "ربو مزمن شديد", "مرض الانسداد الرئوي المزمن (COPD)", "تليف رئوي",
    ],
    "أمراض العيون": [
        "اعتلال الشبكية", "المياه الزرقاء (الجلوكوما)", "ضعف بصر شديد",
    ],
    "الأورام والسرطان": [
        "سرطان الثدي", "سرطان الرئة", "سرطان القولون", "سرطان الدم (اللوكيميا)",
        "سرطان البروستاتا",
    ],
    "الحالات الطارئة والإصابات": [
        "حوادث السير (إصابات متعددة)", "عيوب خلقية (تشوهات)", "إصابات الحروق",
        "كسور مضاعفة", "إصابات ما بعد العمليات الجراحية",
    ],
}

# Category -> default required specialty (matches providers vocabulary)
CATEGORY_TO_SPECIALTY = {
    "أمراض القلب والشرايين": "قلبية",
    "الأمراض العصبية": "عصبية",
    "أمراض الكلى وغسيل الكلى": "كلوية",
    "أمراض العظام والحركة": "عظمية",
    "أمراض الجهاز التنفسي": "تنفسية",
    "أمراض العيون": "عينية",
    "الأورام والسرطان": "أورام",
    "الحالات الطارئة والإصابات": "طوارئ",
}

# All classes the model can output (all exist in providers dataset)
ALL_SPECIALTIES = [
    "قلبية", "عصبية", "تنفسية", "كلوية", "عظمية", "عينية", "أورام", "طوارئ",
    "تمريض منزلي", "رعاية مسنين", "داخلية", "أطفال",
]

# Realistic Arabic symptom/diagnosis phrases per specialty — these feed
# TF-IDF so the vectorizer learns patient-side symptom vocabulary.
SYMPTOM_POOLS = {
    "قلبية": [
        "ضغط دم مرتفع وضيق في الصدر", "خفقان مستمر وإرهاق شديد",
        "ألم صدري عند المجهود وضيق نفس", "تراكم سوائل في الساقين وضيق تنفس",
        "فشل قلبي مزمن يحتاج متابعة", "جلطة قلبية سابقة ودم خفيف",
        "ضغط دم غير منتظم يحتاج مراقبة يومية",
    ],
    "عصبية": [
        "شلل جزئي بعد جلطة دماغية", "رعشة اليدين وضعف توازن",
        "فقدان الذاكرة وتغيرات سلوكية", "صرع متكرر يحتاج إشراف مستمر",
        "مرض باركنسون وتصلب لويحي", "صداع نصفي حاد ومشاكل في الحركة",
    ],
    "تنفسية": [
        "ربو مزمن مع نوبات ضيق تنفس", "انخفاض الأكسجين يحتاج أكسجين منزلي",
        "سعال مزمن وضيق تنفس متكرر", "تليف رئوي مع عدوى متكررة",
        "انقطاع نفس ليلي واحتقان رئوي", "فشل تنفسي مزمن تحت المراقبة",
    ],
    "كلوية": [
        "غسيل كلى ثلاث مرات أسبوعياً", "انتفاخ الجسم وارتفاع اليوريا",
        "حصوات كلوية متكررة وألم خاصرة", "فشل كلوي مزمن مرحلة متقدمة",
        "حرمان من السوائل وتنظيم شرب الماء", "نقص كلسيوم وزيادة بوتاسيوم",
    ],
    "عظمية": [
        "كسور متعددة غير ملتئمة", "خشونة مفاصل شديدة في الركبة والورك",
        "بتر ساق بعد حادث يحتاج إعادة تأهيل", "إعاقة حركية وكرسي متحرك",
        "هشاشة عظام وكسر متكرر", "إصابة حبل شوكي مع شلل جزئي",
    ],
    "عينية": [
        "اعتلال شبكية السكري مع ضبابية رؤية", "مياه زرقاء تحتاج قطرات يومية",
        "ضعف بصر شديد مع صعوبة قراءة", "نزيف داخلي بالعين بعد إصابة",
        "زرقاء مفتوحة الزاوية متكررة", "اعتلال الشبكية المتقدم",
    ],
    "أورام": [
        "علاج كيميائي أسبوعي وآثار جانبية", "سرطان ثدي مرحلة متقدمة",
        "علاج إشعاعي يومي وإرهاق شديد", "سرطان قولون مع كورم مغذي",
        "رعاية تلطيفية لسرطان الرئة", "غثيان شديد بعد العلاج الكيميائي",
    ],
    "طوارئ": [
        "إصابات متعددة بعد حادث سير", "حروق من الدرجة الثانية",
        "كسور مضاعفة في الساق والذراع", "حالة ما بعد العمليات الجراحية",
        "نزيف حاد يحتاج مراقبة مكثفة", "إصابة عمود فقري مع شلل سفلي",
    ],
    "تمريض منزلي": [
        "رعاية يومية للوالد المسن", "حقن وريدية يومية في المنزل",
        "متابعة جرح بعد خياطة", "قياس ضغط وسكر يومي",
        "مساعدة في الأكل والحمام والتنقل", "تغيير ضمادات يومي",
        "رعاية بعد خروج من المستشفى", "إدارة أدوية متعددة يومياً",
    ],
    "رعاية مسنين": [
        "خرف مع نسيان شديد", "هشاشة عظام وكسور متكررة في المسنين",
        "عجز عن الحركة وقعود مستمر", "رعاية مسن طريح الفراش",
        "نسيان الأدوية ونوبات هلوسة", "سقوط متكرر بسبب ضعف التوازن",
    ],
    "داخلية": [
        "سكري منضبط مع ضغط دم", "أمراض مزمنة متعددة معاً",
        "فشل كلوي مع سكري وضغط", "أمراض جهاز هضمي مزمنة",
        "أنيميا مزمنة مع إرهاق", "أمراض مزمنة متعددة تحتاج متابعة",
        "قرحة معدة متكررة والتهاب البنكرياس",
    ],
    "أطفال": [
        "رضيع خديج في الحضانة المنزلية", "ربو عند الطفل مع نوبات",
        "حالات صرع عند الأطفال", "تغذية صناعية وخدج",
        "تطعيمات ومتابعة نمو", "إصابات رياضية عند المراهقين",
    ],
}

URGENCY_POOL = {
    "طوارئ": ["طارئ", "حالة حرجة", "تحتاج تدخل فوري"],
    "أورام": ["متوسط", "علاج مكثف", "متابعة دورية"],
    "تمريض منزلي": ["روتيني", "يومي", "مستمر"],
    "رعاية مسنين": ["يومي", "روتيني", "مستمر"],
    "داخلية": ["متوسط", "يومي", "متابعة أسبوعية"],
}


def age_for_specialty(spec):
    """Realistic age distribution per care type."""
    if spec == "رعاية مسنين":
        return random.randint(65, 92)
    if spec == "تمريض منزلي":
        return random.choice([random.randint(40, 60), random.randint(60, 85)])
    if spec == "أطفال":
        return random.randint(0, 12)
    if spec == "طوارئ":
        return random.randint(18, 70)
    return random.randint(30, 78)


def severity_for(urgency, count):
    if urgency == "طارئ":
        return random.choice([2, 3])
    if count >= 3:
        return random.choice([2, 3])
    return random.choice([1, 2])


def build_row(idx, spec):
    """Build one patient row for a given required specialty."""
    age = age_for_specialty(spec)
    gender = random.choice(GENDERS)
    location = random.choice(LOCATIONS)

    # pick care_category consistent with specialty when possible
    cat_to_spec = CATEGORY_TO_SPECIALTY
    spec_to_cats = {}
    for cat, sp in cat_to_spec.items():
        spec_to_cats.setdefault(sp, []).append(cat)
    cats = spec_to_cats.get(spec, list(CATEGORY_CONDITIONS.keys()))
    care_category = random.choice(cats)

    # conditions: pick 1-4 sub-diseases; add generic chronic tags for internal/home care
    conds = CATEGORY_CONDITIONS.get(care_category, list(CATEGORY_CONDITIONS.values())[0])
    count = random.choice([1, 2, 2, 3, 3, 4])
    tags = random.sample(conds, min(count, len(conds)))

    if spec in ("داخلية", "رعاية مسنين", "تمريض منزلي") and len(tags) < count:
        extras = ["ضغط الدم", "السكري", "قصور القلب", "فشل كلوي مزمن"]
        tags += random.sample(extras, min(count - len(tags), len(extras)))

    urgency = random.choice(URGENCY_POOL.get(spec, ["متوسط", "يومي", "روتيني"]))
    needs_resident = spec in ("تمريض منزلي", "رعاية مسنين") or (
        spec == "داخلية" and random.random() < 0.3
    ) or (age >= 78 and random.random() < 0.35)

    symptom = random.choice(SYMPTOM_POOLS.get(spec, SYMPTOM_POOLS["داخلية"]))
    diagnosis = f"{symptom} — {', '.join(tags[:3])}"
    sev = severity_for(urgency, count)

    return {
        "patient_id": f"P{idx:04d}",
        "age": age,
        "gender": gender,
        "location": location,
        "care_category": care_category,
        "disease_count": len(tags),
        "condition_severity": sev,
        "needs_resident": "True" if needs_resident else "False",
        "care_urgency": urgency,
        "diagnosis_text": diagnosis,
        "required_specialty": spec,
    }


def main():
    rows = []
    idx = 1
    # ~35 rows per specialty for 13 classes = ~455 rows
    per_class = 35
    for spec in ALL_SPECIALTIES:
        for _ in range(per_class):
            rows.append(build_row(idx, spec))
            idx += 1

    # extra "داخلية" multi-morbidity examples with mixed categories
    for _ in range(45):
        spec = "داخلية"
        row = build_row(idx, spec)
        # force mixed tags from multiple categories for realism
        all_conds = [c for conds in CATEGORY_CONDITIONS.values() for c in conds]
        row["diagnosis_text"] = (
            random.choice(SYMPTOM_POOLS["داخلية"])
            + " — " + ", ".join(random.sample(all_conds, 3))
        )
        row["disease_count"] = 3 + random.randint(0, 2)
        row["condition_severity"] = random.choice([2, 3])
        rows.append(row)
        idx += 1

    random.shuffle(rows)

    out_path = "patients_dataset.csv"
    with open(out_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    # class distribution report
    from collections import Counter
    dist = Counter(r["required_specialty"] for r in rows)
    print(f"Generated {len(rows)} patients -> {out_path}")
    for k, v in sorted(dist.items(), key=lambda x: -x[1]):
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
