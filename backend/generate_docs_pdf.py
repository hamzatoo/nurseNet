# -*- coding: utf-8 -*-
"""Generates a comprehensive Arabic PDF documenting the NurseNet AI features."""

import os
import arabic_reshaper
from bidi.algorithm import get_display
from fpdf import FPDF

FONT_DIR = r"C:\Windows\Fonts"
FONT_REG = os.path.join(FONT_DIR, "tahoma.ttf")
FONT_BOLD = os.path.join(FONT_DIR, "tahomabd.ttf")

OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "NurseNet_AI_Documentation.pdf")


class Doc(FPDF):
    def __init__(self):
        super().__init__()
        self.add_font("tahoma", "", FONT_REG)
        self.add_font("tahoma", "B", FONT_BOLD)
        self.add_page()
        self.set_auto_page_break(auto=True, margin=18)
        self.set_margins(18, 18, 18)

    def ar_text(self, text):
        """Shape + reorder Arabic text for RTL rendering."""
        return get_display(arabic_reshaper.reshape(text))

    def multi_ar(self, text, size=11, style="", align="R", color=(38, 50, 56), line_h=6):
        """Write multi-line Arabic text, word-wrapping manually."""
        self.set_font("tahoma", style, size)
        self.set_text_color(*color)
        width = self.w - self.l_margin - self.r_margin
        for raw_line in text.split("\n"):
            line = raw_line.strip()
            if not line:
                self.ln(3)
                continue
            # wrap long lines
            words = line.split(" ")
            cur = ""
            for w in words:
                test = (cur + " " + w).strip()
                if self.get_string_width(self.ar_text(test)) > width and cur:
                    self.cell(0, line_h, self.ar_text(cur), new_x="LMARGIN", new_y="NEXT", align=align)
                    cur = w
                else:
                    cur = test
            if cur:
                self.cell(0, line_h, self.ar_text(cur), new_x="LMARGIN", new_y="NEXT", align=align)
        self.ln(2)

    def heading(self, text, size=16):
        self.ln(4)
        self.set_font("tahoma", "B", size)
        self.set_text_color(26, 115, 232)
        self.cell(0, 10, self.ar_text(text), new_x="LMARGIN", new_y="NEXT", align="R")
        self.set_draw_color(26, 115, 232)
        self.set_line_width(0.6)
        y = self.get_y()
        self.line(self.l_margin, y, self.w - self.r_margin, y)
        self.ln(4)

    def subheading(self, text, size=13):
        self.ln(2)
        self.set_font("tahoma", "B", size)
        self.set_text_color(38, 50, 56)
        self.cell(0, 8, self.ar_text(text), new_x="LMARGIN", new_y="NEXT", align="R")
        self.ln(1)

    def bullet(self, text, size=11):
        self.set_font("tahoma", "", size)
        self.set_text_color(38, 50, 56)
        width = self.w - self.l_margin - self.r_margin - 8
        self.cell(8, 6, "•", align="L")
        words = text.split(" ")
        cur = ""
        first = True
        for w in words:
            test = (cur + " " + w).strip()
            if self.get_string_width(self.ar_text(test)) > width and cur:
                self.cell(width, 6, self.ar_text(cur), new_x="LMARGIN", new_y="NEXT", align="R")
                cur = w
            else:
                cur = test
        if cur:
            self.cell(width, 6, self.ar_text(cur), new_x="LMARGIN", new_y="NEXT", align="R")

    def code_block(self, code, size=8.5):
        """Print LTR code/English snippet."""
        self.set_font("courier", "", size)
        self.set_text_color(30, 30, 30)
        self.set_fill_color(245, 247, 250)
        for line in code.strip("\n").split("\n"):
            # draw light bg rect
            x, y = self.l_margin, self.get_y()
            self.rect(x, y, self.w - self.l_margin - self.r_margin, 5, style="F")
            self.set_xy(x + 2, y + 0.5)
            self.cell(self.w - self.l_margin - self.r_margin - 4, 5, line[:110])
            self.set_y(y + 5)
        self.ln(3)

    def ltr_line(self, text, size=9):
        self.set_font("courier", "", size)
        self.set_text_color(26, 115, 232)
        self.cell(0, 6, text, new_x="LMARGIN", new_y="NEXT", align="L")


def build():
    pdf = Doc()

    # ===================== COVER =====================
    pdf.ln(30)
    pdf.set_font("tahoma", "B", 26)
    pdf.set_text_color(26, 115, 232)
    pdf.cell(0, 16, pdf.ar_text("NurseNet — التوثيق التقني الكامل"), new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.set_font("tahoma", "", 14)
    pdf.set_text_color(90, 100, 110)
    pdf.cell(0, 10, pdf.ar_text("أنظمة الذكاء الاصطناعي والتعلم الآلي في التطبيق"), new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(10)
    pdf.set_font("tahoma", "", 11)
    pdf.set_text_color(120, 120, 120)
    pdf.multi_ar(
        "وثيقة شاملة تشرح المعمارية والمنطق البرمجي والمنطق الفيزيائي "
        "لأدوات الذكاء الاصطناعي الثلاث: قياس النبض بدون تلامس (rPPG)، "
        "مسح الوصفات الطبية (OCR)، ونظام التنبؤ بالممرضين الأنسب (SVM).\n\n"
        "Flutter + FastAPI + Firebase — مشروع التخرج",
        align="C", color=(90, 100, 110),
    )
    pdf.add_page()

    # ===================== 1. rPPG =====================
    pdf.heading("1) قياس النبض بدون تلامس — rPPG")
    pdf.subheading("1.1 الفكرة الفيزيائية")
    pdf.multi_ar(
        "المبدأ العلمي (Photoplethysmography): كل نبضة قلب تدفع دفعة دم جديدة "
        "إلى الأوعية الدموية في الوجه. هذا يسبب تموجاً طفيفاً في كمية الدم تحت الجلد "
        "(~1% من الإشارة الضوئية). الضوء المرتد عن الوجه يمتص جزئياً من الدم، "
        "والقناة الخضراء في الكاميرا هي الأكثر حساسية لهذا التموج لأن الهيموجلوب "
        "يمتص الأخضر بشدة — لذلك نستخدم القناة الخضراء وليس الأحمر أو الأزرق.\n\n"
        "المعادلة الذهنية: نبضة ← دم أكثر تحت الجلد ← امتصاص أخضر أعلى ← "
        "قيمة أخضر تنخفض قليلاً ← يتكرر كل ~0.8 ثانية (75 نبضة/دقيقة)."
    )

    pdf.subheading("1.2 المعمارية والتدفق")
    pdf.code_block(
        "Flutter (camera front, 8s) --multipart MP4--> FastAPI\n"
        "  POST /api/calculate-heart-rate\n"
        "    -> save temp file -> run_in_threadpool(rppg.analyse)\n"
        "    -> delete temp file -> JSON {bpm, quality, ...}"
    )
    pdf.bullet("Flutter: الكاميرا الأمامية ResolutionPreset.medium، تسجيل ~8 ثوانٍ، رفع multipart مع timeouts متسلسلة (75s upload + 30s read) + زر إلغاء.")
    pdf.bullet("Backend: تحقق من النوع، كتابة الملف مؤقتاً، تشغيل التحليل في threadpool (لا يحجب السيرفر)، حذف الملف في finally.")

    pdf.subheading("1.3 خط المعالجة داخل rppg.py")
    pdf.bullet("كشف الوجه: OpenCV Haar Cascade (haarcascade_frontalface_default.xml) + equalizeHist — نعيد الكشف كل 3 إطارات فقط ونأخذ أكبر وجه.")
    pdf.bullet("منطقة الجبهة ROI: الشريط بين 15% و42% من ارتفاع الوجه، مقصوص أفقياً 22%-78% — أنظف منطقة بدون شعر/حواجب.")
    pdf.bullet("استخراج الإشارة: متوسط القناة الخضراء داخل الـ ROI لكل إطار = trace إشارية 1D (~240 عينة لـ 8 ثوانٍ @30fps).")
    pdf.bullet("فحوصات الصحة: مدة >= 5s، fps >= 10، وجود وجه >= 50% من الإطارات، سطوع 40-245، حركة < 35% — كل فشل يرجع RppgError برسالة عربية.")
    pdf.bullet("تنظيف الإشارة: scipy.signal.detrend (إزالة انجراف الإضاءة) ثم Butterworth band-pass 3rd order بنطاق 0.7-4.0 Hz (= 42-240 bpm) عبر sosfiltfilt (صفر انحراف طور).")
    pdf.bullet("نافذة Hanning ثم FFT (zero-padding حتى 16384) → طيف قدرة → الذروة في النطاق → تردد × 60 = BPM.")
    pdf.bullet("Parabolic interpolation حول الذروة لدقة أعلى، وquality = نسبة القدرة المتمركزة حول الذروة (نظيف ~0.9، ضوضاء ~0.15، نرفض تحت 0.25).")

    pdf.subheading("1.4 المكتبات المستخدمة")
    pdf.bullet("opencv-python-headless: فك الفيديو، كشف الوجه، resize، BGR→Gray.")
    pdf.bullet("numpy: المصفوفات، المتوسطات، np.fft.rfft.")
    pdf.bullet("scipy: butter/sosfiltfilt (فلتر)، detrend.")
    pdf.bullet("fastapi + starlette run_in_threadpool: تنفيذ غير حاجب.")
    pdf.add_page()

    # ===================== 2. OCR =====================
    pdf.heading("2) مسح الوصفات الطبية — OCR")
    pdf.subheading("2.1 خط المعالجة")
    pdf.code_block(
        "صورة وصفة -> [معالجة مسبقة OpenCV] -> [Tesseract ara+eng]\n"
        "  -> [فلترة ضوضاء regex] -> [تحليل أدوية] -> JSON منظم"
    )

    pdf.subheading("2.2 المعالجة المسبقة (_preprocess_image)")
    pdf.bullet("تحويل لرمادي، تكبير تلقائي حتى 1500px (Tesseract يحتاج ~300 DPI)، إزالة ضوضاء fastNlMeansDenoising، تحسين تباين CLAHE، عتبة Otsu ثنائية — مع fallback للصورة الأصلية.")

    pdf.subheading("2.3 استخراج النص")
    pdf.bullet("pytesseract + Pillow: image_to_string بـ lang='ara+eng' مع fallback لـ eng ثم الافتراضي — يتعرف على Paracetamol وباراسيتامول بنفس السطر.")
    pdf.bullet("easyocr اختياري خلف ENABLE_EASYOCR=true (يسحب PyTorch ~2GB — غير مناسب للـ free tier).")

    pdf.subheading("2.4 فلترة الضوضاء")
    pdf.multi_ar(
        "قبل التحليل نحذف كل سطر يطابق أنماط الضوضاء: أرقام هواتف، تواريخ، "
        "أسماء عيادات/مستشفيات، ألقاب أطباء (د. / Dr.)، أختام وتوقيعات، "
        "أرقام صفحات، فواصل، سطور أقصر من 3 أحرف أو بلا أحرف تقريباً. "
        "كما نتوقف عن التحليل عند الوصول لمنطقة التوقيع (كلمة 'التوقيع'/'الطبيب')."
    )

    pdf.subheading("2.5 تحليل الأدوية")
    pdf.bullet("قاعدة معرفة ~100 دواء: أسماء عربية + إنجليزية + تجارية (Augmentin، Zithromax، Panadol، Losec...) بمطابقة substring غير حساسة لحالة الأحرف.")
    pdf.bullet("الجرعة: regex لرقم + وحدة (mg/ml/g/mcg/حبة/قرص/كبسولة/قطرة/وحدة/ملعقة) مع fallback للرقم وحده.")
    pdf.bullet("التكرار: أنماط متعددة — 'مرتين'/'صباحاً ومساءً'/'كل 12 ساعة'→twice_daily، 'ثلاث مرات'→three_times، q.i.d/t.i.d/b.i.d/prn اختصارات طبية.")
    pdf.bullet("التعليمات: قبل/بعد الأكل بأنواعه، على معدة فارغة، مع وجبة، صباحاً/مساءً/ليلاً — تتراكم عبر الأسطر.")
    pdf.bullet("النوع: حقنة/شراب/قطرة/كبسولة/قرص/بخاخ/مرهم — أو يُستنتج من وحدة الجرعة إذا لم يوجد مفتاح.")
    pdf.bullet("إخراج JSON: medications[] + detected_duration + confidence + scheduled_times — متوافق 100% مع شاشة المراجعة في Flutter.")

    pdf.subheading("2.6 المكتبات")
    pdf.bullet("opencv-python-headless: معالجة الصورة. pytesseract + Pillow: OCR + التحقق من الصورة. python-multipart: استقبال الرفع. re: كل الأنماط.")
    pdf.add_page()

    # ===================== 3. AI PREDICTION =====================
    pdf.heading("3) نظام التنبؤ بالممرضين — AI Prediction")
    pdf.subheading("3.1 البنية الحالية: طبقتان")
    pdf.multi_ar(
        "النظام الحالي مكوّن من طبقتين منفصلتين: (1) SVM Classifier يصنّف نوع "
        "الرعاية إلى 7 فئات، و(2) محرك نقاط (rule-based scoring) يرتب الممرضين "
        "المطابقين ويعيد أفضل 5. الـ SVM لا يتنبأ باسم ممرض — يصنّف 'نوع الرعاية "
        "المطلوبة' فقط."
    )

    pdf.subheading("3.2 كيف تدرّب الموديل الحالي")
    pdf.bullet("البيانات: damascus_providers_fixed.csv — 200 مقدم خدمة (name, specialty, location, experience_years, verified, available, services).")
    pdf.bullet("هندسة الميزات: 37 ميزة = 7 رقمية (specialty_encoded, location_encoded, experience/30, verified, available, service_count/10, diversity/20) + 30 TF-IDF (TfidfVectorizer, ngram 1-2, max_features=30) على نص 'specialty + location + services'.")
    pdf.bullet("تطبيع عربي: توحيد الألف (أ/إ/آ→ا)، التاء المربوطة (ة→ه)، إزالة التشكيل، ضغط المسافات.")
    pdf.bullet("التصنيفات: 7 فئات — قلب/عقل=0، كلى/عظام=1، تنفس/عيون=2، سرطان/طوارئ=3، باطنية/أطفال=4، تمريض منزلي=5، أخرى=6.")
    pdf.bullet("التدريب: train_test_split(0.2) + StandardScaler + SVC + GridSearchCV على C/kernel/gamma، مع fallback لـ class_weight='balanced' إذا الدقة < 80%. الحفظ بـ joblib في 4 ملفات pkl.")

    pdf.subheading("3.3 الاستدلال ومطابقة الممرضين")
    pdf.bullet("ai_service.predict(): reshape(1,-1) → scaler.transform → model.predict → فئة 0-6.")
    pdf.bullet("match_providers(): نظام نقاط — تخصص مطابق +40، مرتبط +20، نفس الموقع +20، خبرة min(years*2,20)، موثّق +10، متاح +10، كل خدمة مطابقة +5 → ترتيب → Top 5 مع match_reasons.")

    pdf.subheading("3.4 المشاكل المعروفة (تقييم صادق)")
    pdf.bullet("الـ 30 TF-IDF features تُرسل كأصفار من Flutter — نص المريض لا يصل للموديل.")
    pdf.bullet("عدم تطابق الترميز: التطبيق يرسل medicalCategory مرمّزة 1-8 وlocation.hashCode%10 — مختلف كلياً عن قواميس التدريب.")
    pdf.bullet("عدم اتساق المفهوم: الموديل اتدرّب على 'صفوف الممرضين' لا على 'حالات المرضى' — لا توجد بيانات تدريب لحالات مرضى.")
    pdf.add_page()

    # ===================== 4. ML CONCEPTS =====================
    pdf.heading("4) مفاهيم التعلم الآلي الأساسية")
    pdf.subheading("4.1 ما هو X و y")
    pdf.multi_ar(
        "X = المدخلات (features) — 'شو بعرف عن الحالة'. y = المخرج (label) — "
        "'شو الجواب الصحيح'. مثال: X = [age=72, gender=F, category=عظام, "
        "tags=[خشونة], needs_resident=True] و y = 'عظمية'. الموديل يتعلم "
        "الحدود (hyperplane) التي تفصل الفئات في فضاء الـ features."
    )

    pdf.subheading("4.2 train_test_split — كيف يختبر الموديل نفسه")
    pdf.multi_ar(
        "نقسم البيانات: ~80% تدريب + ~20% اختبار. الموديل يتدرب على التدريب فقط، "
        "ثم نختبره على بيانات لم يشاهدها إطلاقاً ونقيس accuracy — هكذا نعرف إن "
        "كان يتعمم (generalization) أم يحفظ الإجابات (overfitting). "
        "GridSearchCV يضيف طبقة اختبار داخلية لاختيار أفضل hyperparameters."
    )

    pdf.subheading("4.3 لماذا لا يمكن تدريب موديل واحد على datasetين؟")
    pdf.multi_ar(
        "كل صف في بيانات التدريب يجب أن يكون (X → y) بنفس الـ schema. "
        "dataset المرضى: X=ميزات مريض، y=فئة الرعاية المطلوبة — متسق. "
        "dataset الممرضين: X=ميزات ممرض لكن لا يوجد y (الممرض ليس له 'إجابة صحيحة'). "
        "لذلك الممرضين ليسوا training data — هم candidate pool (قاعدة بحث) "
        "تُستخدم فقط وقت الاستدلال بعد التنبؤ."
    )

    pdf.subheading("4.4 المعمارية الصحيحة: مرحلتان")
    pdf.code_block(
        "TRAINING:  patients_dataset.csv (300 rows)\n"
        "          X=50 features/row -> SVM learns X->y\n"
        "          y=8 care categories -> saved as .pkl\n\n"
        "INFERENCE: new patient -> same 50 features -> SVM -> y_pred\n"
        "          y_pred='عظمية' = الجسر\n"
        "          providers_dataset -> filter by specialty -> score -> Top5"
    )
    pdf.bullet("الربط بين الـ datasetين = predicted_specialty — الجسر الوحيد، ويشترط توافق الـ vocabulary (نفس أسماء التخصصات).")
    pdf.bullet("'هاد الأنسب' لا يقرره الـ SVM — بل محرك النقاط (deterministic scoring) هو من يرتب المرشحين.")
    pdf.add_page()

    # ===================== 5. THE PLAN =====================
    pdf.heading("5) الخطة الجديدة: SVM يتدرب على بيانات مرضى")
    pdf.subheading("5.1 dataset المرضى (patients_dataset.csv)")
    pdf.multi_ar(
        "سنولّد ~300-400 حالة مريض وهمية بنفس منطق dataset الممرضين. "
        "الأعمدة: patient_id, age, gender, location, care_category, "
        "disease_count, condition_severity, needs_resident, care_urgency, "
        "diagnosis_text, required_specialty.\n\n"
        "required_specialty هو الـ y — 8 فئات مطابقة لتخصصات الممرضين "
        "(قلبية، عصبية، تنفسية، باطنية، رعاية منزلية، عظمية، نسائية وأطفال، طوارئ) "
        "حتى يكون الجسر مباشراً: SVM يتنبأ التخصص ← نفلتر الممرضين بنفس التخصص."
    )

    pdf.subheading("5.2 قواعد توليد الـ dummy data")
    pdf.bullet("CATEGORY_TO_SPECIALTY: كل فئة طبية من الـ 8 → تخصص رعاية منطقي (قلب→قلبية، أعصاب→عصبية، عظام→عظمية...).")
    pdf.bullet("age > 65 → 'رعاية منزلية' غالباً. needs_resident=True + age>70 → رعاية منزلية.")
    pdf.bullet("disease_count >= 3 → severity عالية → أولوية باطنية/رعاية منزلية.")
    pdf.bullet("diagnosis_text = دمج medicalDescription + medicalTags — نص حر تتعلمه TF-IDF.")

    pdf.subheading("5.3 هندسة الميزات (~10 رقمية + TF-IDF)")
    pdf.bullet("الرقمية: age/100، gender، location_encoded (نفس location_mapping)، category_encoded، disease_count/10، severity/3، needs_resident، urgency/3، disease_count*severity/30، age_factor.")
    pdf.bullet("النصية: TF-IDF على diagnosis_text + tags + category — يتعلم مفردات الأعراض (ضغط، سكر، جلطة، كسور) — وهنا تصبح TF-IDF منطقية 100% لأنها على نصوص مرضى لا ممرضين.")

    pdf.subheading("5.4 ملفات جديدة في backend/ai_service/")
    pdf.bullet("patients_dataset.csv — البيانات المولّدة. generate_patient_dataset.py — سكربت التوليد.")
    pdf.bullet("train_patient_model.py — تدريب SVM بنفس أسلوب train_svm_model.py.")
    pdf.bullet("patient_svm_model.pkl + patient_scaler.pkl + patient_vectorizer.pkl + patient_metadata.pkl — المخرجات.")

    pdf.subheading("5.5 التعديلات على الكود")
    pdf.bullet("ai_service.py: دالة predict_patient_need() تحمّل الموديلات الجديدة وتبني نفس الميزات، وmatch_providers تستقبل predicted_specialty وتفلتر به أولاً.")
    pdf.bullet("predict.py: استقبال patient_data كامل (age, gender, needsResidentNurse, medicalDescription).")
    pdf.bullet("Flutter: إرسال البيانات الخام بدل الـ 37 صفراً؛ حفظ age وgender في Firestore (حالياً العمر لا يُحفظ — bug يجب إصلاحه).")
    pdf.bullet("العرض: بطاقة 'الفئة المتوقعة + درجة الثقة' فوق قائمة الممرضين.")

    pdf.subheading("5.6 نقاط قوة الأطروحة")
    pdf.bullet("Dataset منظم بميزات ديموغرافية + سريرية + نصية حرة.")
    pdf.bullet("SVM + TF-IDF + StandardScaler + GridSearchCV — Toolkit بحثي قياسي.")
    pdf.bullet("Two-stage AI: تصنيف احتياج (SVM) ← ترتيب ترشيح (scoring) — معمارية موصى بها.")
    pdf.bullet("Interpretability: predicted_specialty + match_reasons + confidence — شفافية القرار.")
    pdf.bullet("End-to-end: تسجيل → Firestore → AI → نتائج عملية.")

    # ===================== 6. SEQUENCE =====================
    pdf.heading("6) التسلسل الزمني للتنفيذ")
    pdf.multi_ar(
        "1) generate_patient_dataset.py → patients_dataset.csv (300+ صف).\n"
        "2) train_patient_model.py → تشغيل → 4 ملفات pkl.\n"
        "3) تحديث ai_service.py → predict_patient_need() + فلترة بالمتخصص.\n"
        "4) تحديث predict.py → استقبال patient_data الكامل.\n"
        "5) تحديث Flutter → إرسال البيانات الحقيقية + حفظ age/gender.\n"
        "6) اختبار end-to-end → commit → push → Render يعيد النشر.\n\n"
        "النتيجة: مريض يسجل أمراضه/عمره/منطقته/يحتاج ممرض مقيم → يضغط 'حلل' → "
        "SVM يتنبأ بفئة الرعاية → النظام يفلتر الممرضين المناسبين ويرتبهم "
        "بالخبرة والموثوقية والموقع → Top 5 مع أسباب المطابقة."
    )

    pdf.ln(10)
    pdf.set_font("tahoma", "", 9)
    pdf.set_text_color(150, 150, 150)
    pdf.cell(0, 6, pdf.ar_text("NurseNet Graduation Project — AI Documentation — generated by Devin"), align="C")

    pdf.output(OUT_PATH)
    print(f"PDF generated: {OUT_PATH}")


if __name__ == "__main__":
    build()
","file_path":"C:\Users\hamza\Desktop\flutter_tt\test1\backend\generate_docs_pdf.py