# -*- coding: utf-8 -*-
"""
=====================================================================
 Google Colab Experiment — Patient SVM (NurseNet)
=====================================================================
This script EXACTLY replicates backend/ai_service/train_patient_model.py
so the metrics produced here match the deployed production model:

  - same dataset (patients_dataset.csv, downloaded from GitHub)
  - same feature engineering (10 numerical + TF-IDF 60 features)
  - same Arabic normalization + fixed vocabularies
  - same split: train_test_split(test_size=0.2, random_state=42)
  - same scaler: StandardScaler | same search: GridSearchCV cv=3
  - same estimator: SVC(random_state=42)

Outputs (all thesis-ready):
  1. Accuracy + 5-fold cross-validation score
  2. Full classification report (precision / recall / f1 / support)
     -> printed table + saved as CSV
  3. Confusion matrix (table CSV + English-label heatmap PNG)
  4. Per-class recall table
  5. Sample predictions: raw patient text -> predicted specialty
  6. Feature importance (top TF-IDF terms per class, linear kernel)

HOW TO USE IN GOOGLE COLAB:
  1. Open https://colab.research.google.com -> New notebook
  2. Paste this ENTIRE file into a single cell (or split at the
     '# =====' section markers into separate cells)
  3. Runtime -> Run all
  4. Download generated files from the Files panel on the left:
       - confusion_matrix.png
       - classification_report.csv
       - sample_predictions.csv
       - feature_importance.csv
=====================================================================
"""

# %% ==================== CELL 1: INSTALLS + IMPORTS ====================
# Colab has all packages preinstalled - no pip install needed.

import io
import urllib.request
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import GridSearchCV, train_test_split, cross_val_score
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.svm import SVC
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    ConfusionMatrixDisplay,
)

# NOTE: arabic-reshaper / python-bidi are NOT needed - all plots use
# English labels because matplotlib cannot render Arabic shaping.

RANDOM_STATE = 42
DATA_URL = (
    "https://raw.githubusercontent.com/hamzatoo/nurseNet/main/"
    "backend/ai_service/patients_dataset.csv"
)
LOCAL_CSV = "patients_dataset.csv"   # fallback: upload this file in Colab

# English labels for plots (matplotlib cannot render Arabic).
# Keys must match label_encoder.classes_ order (LabelEncoder sorts
# classes alphabetically - same order printed in CELL 4 output).
CLASS_EN = {
    "أطفال": "Pediatrics",
    "أورام": "Oncology",
    "تمريض منزلي": "Home Nursing",
    "تنفسية": "Respiratory",
    "داخلية": "Internal Medicine",
    "رعاية مسنين": "Elderly Care",
    "طوارئ": "Emergency",
    "عصبية": "Neurology",
    "عظمية": "Orthopedics",
    "عينية": "Ophthalmology",
    "قلبية": "Cardiology",
    "كلوية": "Nephrology",
}


def en_label(ar_name):
    return CLASS_EN.get(str(ar_name), str(ar_name))


def ar(text):
    """Kept for backward compatibility - returns text unchanged."""
    return str(text)


# %% ==================== CELL 2: LOAD DATA ====================
# The dataset is fetched automatically from the GitHub repository.
# If the download fails (private repo / no internet), upload
# backend/ai_service/patients_dataset.csv manually via the Files panel
# and the code falls back to the local file.
try:
    print(f"Downloading dataset from GitHub...")
    urllib.request.urlretrieve(DATA_URL, LOCAL_CSV)
    print("Download OK")
except Exception as e:
    print(f"Download failed ({e}) - using local upload if present")

df = pd.read_csv(LOCAL_CSV, encoding="utf-8-sig")
print(f"Loaded {len(df)} patient records")
print(df.head())
print("\nClass distribution (y):")
print(df["required_specialty"].value_counts())


# %% ==================== CELL 3: FIXED VOCABULARIES ====================
# MUST stay identical to train_patient_model.py — these encodings are
# baked into the production model.

LOCATION_MAPPING = {loc: i for i, loc in enumerate([
    "المزة", "المالكي", "الشعلان", "البرامكة", "القصاع", "الميدان",
    "الزرقاء", "أبو رمانة", "المرجة", "اليعقوبية", "جوبر", "دوما",
    "حرستا", "اليرموك", "القابون", "تشرين", "السيدة زينب",
])}

CATEGORY_MAPPING = {cat: i for i, cat in enumerate([
    "أمراض القلب والشرايين", "الأمراض العصبية", "أمراض الكلى وغسيل الكلى",
    "أمراض العظام والحركة", "أمراض الجهاز التنفسي", "أمراض العيون",
    "الأورام والسرطان", "الحالات الطارئة والإصابات",
])}

URGENCY_MAPPING = {"طارئ": 3, "متوسط": 2, "يومي": 1, "روتيني": 1, "مستمر": 1}


def normalize_arabic_text(text: str) -> str:
    """Identical to PatientModelTrainer._normalize_arabic_text."""
    if not isinstance(text, str):
        return ""
    for d in ["َ", "ً", "ُ", "ٌ", "ِ", "ٍ", "ْ", "ّ"]:
        text = text.replace(d, "")
    text = text.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
    text = text.replace("ة", "ه")
    return " ".join(text.split()).lower()


# %% ==================== CELL 4: FEATURE ENGINEERING ====================
# EXACT copy of PatientModelTrainer.engineer_features()

def engineer_features(df):
    numerical, texts, labels = [], [], []

    for _, row in df.iterrows():
        age = float(row.get("age", 0) or 0)
        gender_f = 1.0 if str(row.get("gender", "")) == "أنثى" else 0.0
        location = str(row.get("location", ""))
        category = str(row.get("care_category", ""))
        disease_count = float(row.get("disease_count", 0) or 0)
        severity = float(row.get("condition_severity", 0) or 0)
        needs_resident = (
            1.0 if str(row.get("needs_resident", "")).lower() == "true" else 0.0
        )
        urgency_raw = str(row.get("care_urgency", ""))
        urgency = URGENCY_MAPPING.get(urgency_raw, 1) / 3.0
        diagnosis = str(row.get("diagnosis_text", ""))
        label = str(row.get("required_specialty", ""))

        loc_enc = LOCATION_MAPPING.get(location, 0)
        cat_enc = CATEGORY_MAPPING.get(category, 0)

        numerical.append([
            age / 100.0,                                # 1 age normalized
            gender_f,                                   # 2 gender
            loc_enc / 16.0,                             # 3 location encoded
            cat_enc / 7.0,                              # 4 category encoded
            min(disease_count, 10) / 10.0,              # 5 disease count
            min(severity, 3) / 3.0,                     # 6 severity
            needs_resident,                             # 7 resident flag
            urgency,                                    # 8 urgency
            min(disease_count * severity, 30) / 30.0,   # 9 burden interaction
            (age / 100.0) * (min(severity, 3) / 3.0),   # 10 age x severity
        ])

        norm_diag = normalize_arabic_text(diagnosis)
        norm_cat = normalize_arabic_text(category)
        texts.append(f"{norm_diag} {norm_cat}")
        labels.append(label)

    X_num = np.array(numerical, dtype=np.float64)
    y_raw = np.array(labels)

    # TF-IDF on symptom/diagnosis text — identical params to production
    vectorizer = TfidfVectorizer(
        ngram_range=(1, 2),
        sublinear_tf=True,
        max_features=60,
    )
    X_text = vectorizer.fit_transform(texts).toarray()
    X = np.hstack([X_num, X_text])
    label_encoder = LabelEncoder()
    y = label_encoder.fit_transform(y_raw)

    feature_names = [
        "age_norm", "gender_f", "location_enc", "category_enc",
        "disease_count", "severity", "needs_resident", "urgency",
        "burden", "age_x_severity",
    ] + [f"tfidf_{i}" for i in range(X_text.shape[1])]

    return X, y, X_num, X_text, texts, vectorizer, label_encoder, feature_names


X, y, X_num, X_text, texts, vectorizer, label_encoder, feature_names = (
    engineer_features(df)
)
print(f"\nFeatures shape: {X.shape}  (10 numerical + {X_text.shape[1]} TF-IDF)")
print(f"Classes ({len(label_encoder.classes_)}): "
      f"{list(label_encoder.classes_)}")


# %% ==================== CELL 5: TRAIN (identical to production) ====================
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=RANDOM_STATE
)
scaler = StandardScaler()
X_train_s = scaler.fit_transform(X_train)
X_test_s = scaler.transform(X_test)

param_grid = {
    "C": [1, 10, 50, 100],
    "kernel": ["linear", "rbf"],
    "gamma": ["scale", "auto", 0.01, 0.1],
}
grid = GridSearchCV(
    SVC(random_state=RANDOM_STATE), param_grid, cv=3,
    scoring="accuracy", n_jobs=-1, verbose=1,
)
grid.fit(X_train_s, y_train)
model = grid.best_estimator_

print(f"\nBest params: {grid.best_params_}")
print(f"GridSearchCV mean CV accuracy: {grid.best_score_:.4f}")

# 5-fold CV on the full dataset with best params (extra stability evidence)
cv_scores = cross_val_score(model, scaler.transform(X), y, cv=5)
print(f"5-fold CV accuracy: {cv_scores.mean():.4f} "
      f"(+/- {cv_scores.std():.4f})")


# %% ==================== CELL 6: TEST-SET METRICS ====================
y_pred = model.predict(X_test_s)
acc = accuracy_score(y_test, y_pred)
print(f"\n{'='*55}")
print(f"TEST ACCURACY (holdout 20%): {acc:.4f}")
print(f"{'='*55}")

class_names = [str(c) for c in label_encoder.classes_]
report_dict = classification_report(
    y_test, y_pred, target_names=class_names,
    output_dict=True, zero_division=0,
)
report_df = pd.DataFrame(report_dict).T
report_df = report_df.drop(index=["accuracy", "macro avg", "weighted avg"],
                           errors="ignore")

print("\nPer-class metrics (test set):")
print(report_df[["precision", "recall", "f1-score", "support"]]
      .round(3).to_string())

print("\n" + classification_report(
    y_test, y_pred, target_names=class_names, zero_division=0))

# Save classification report for the thesis
report_df.to_csv("classification_report.csv")
print("Saved: classification_report.csv")


# %% ==================== CELL 6b: THESIS TABLES + METRICS CHART ====================
# Per-class Precision / Recall / F1 as a clean table + bar chart.
# Everything is in English so it can be pasted straight into a thesis.

metrics_df = report_df[["precision", "recall", "f1-score", "support"]].copy()
metrics_df.index = [en_label(c) for c in metrics_df.index]
metrics_df = metrics_df.round(4)

print("=" * 78)
print("PER-CLASS METRICS  (test set, holdout 20%)")
print("=" * 78)
print(metrics_df.to_string())

# --- LaTeX (booktabs) table: copy-paste directly into a .tex thesis ---
NL = chr(10)
BS = chr(92)
latex_rows = []
for name, row in metrics_df.iterrows():
    latex_rows.append(
        name + " & " + format(row["precision"], ".3f") + " & "
        + format(row["recall"], ".3f") + " & "
        + format(row["f1-score"], ".3f") + " & "
        + str(int(row["support"])) + " " + BS + BS + NL)
latex_table = (
    BS + "begin{table}[htbp]" + NL + BS + "centering" + NL
    + BS + "caption{Per-class classification metrics of the patient SVM "
    + "(holdout test set).}" + NL
    + BS + "begin{tabular}{lcccc}" + NL + BS + "toprule" + NL
    + "Specialty & Precision & Recall & F1-Score & Support "
    + BS + BS + NL + BS + "midrule" + NL
    + "".join(latex_rows) + NL
    + BS + "midrule" + NL
    + BS + "textbf{Macro avg} & "
    + format(metrics_df["precision"].mean(), ".3f") + " & "
    + format(metrics_df["recall"].mean(), ".3f") + " & "
    + format(metrics_df["f1-score"].mean(), ".3f") + " & "
    + str(int(metrics_df["support"].sum())) + " " + BS + BS + NL
    + BS + "bottomrule" + NL + BS + "end{tabular}" + NL
    + BS + "end{table}"
)
with open("metrics_table.tex", "w", encoding="utf-8") as f:
    f.write(latex_table)
print(NL + "--- LaTeX table (also saved to metrics_table.tex) ---")
print(latex_table)

# --- Markdown table for Word/Google Docs ---
md = ["| Specialty | Precision | Recall | F1-Score | Support |",
      "|---|---|---|---|---|"]
for name, row in metrics_df.iterrows():
    md.append("| " + name + " | " + format(row["precision"], ".3f")
              + " | " + format(row["recall"], ".3f")
              + " | " + format(row["f1-score"], ".3f")
              + " | " + str(int(row["support"])) + " |")
md.append("| **Macro avg** | "
          + format(metrics_df["precision"].mean(), ".3f")
          + " | " + format(metrics_df["recall"].mean(), ".3f")
          + " | " + format(metrics_df["f1-score"].mean(), ".3f")
          + " | " + str(int(metrics_df["support"].sum())) + " |")
with open("metrics_table.md", "w", encoding="utf-8") as f:
    f.write(NL.join(md))
print(NL + "--- Markdown table (also saved to metrics_table.md) ---")
print(NL.join(md))

# --- Bar chart: per-class Recall + F1 ---
plot_df = metrics_df[["recall", "f1-score"]].copy()
plot_df.columns = ["Recall", "F1-Score"]
ax = plot_df.plot(kind="bar", figsize=(12, 5),
                  color=["#1a73e8", "#34a853"])
ax.set_title("Per-Class Recall and F1-Score - Patient SVM", fontsize=13)
ax.set_ylabel("Score", fontsize=11)
ax.set_xlabel("Care Specialty", fontsize=11)
ax.set_ylim(0, 1.05)
ax.legend(loc="lower right")
plt.xticks(rotation=45, ha="right")
plt.tight_layout()
plt.savefig("metrics_bar_chart.png", dpi=150, bbox_inches="tight")
plt.show()
print("Saved: metrics_bar_chart.png")


# %% ==================== CELL 7: CONFUSION MATRIX ====================
# %% ==================== CELL 7: CONFUSION MATRIX ====================
cm = confusion_matrix(y_test, y_pred)
cm_df = pd.DataFrame(cm, index=class_names, columns=class_names)
cm_df.to_csv("confusion_matrix.csv", encoding="utf-8-sig")
print("Confusion matrix (rows=true, cols=predicted):")
print(cm_df.to_string())

# English labels for the heatmap - matplotlib cannot render Arabic.
en_names = [en_label(c) for c in class_names]
cm_en = pd.DataFrame(cm, index=en_names, columns=en_names)
cm_en.to_csv("confusion_matrix_en.csv")

fig, ax = plt.subplots(figsize=(11, 9))
sns.heatmap(cm_en.values.astype(int), annot=True, fmt="d", cmap="Blues",
            xticklabels=en_names, yticklabels=en_names, ax=ax)
ax.set_xlabel("Predicted Specialty", fontsize=12)
ax.set_ylabel("True Specialty", fontsize=12)
ax.set_title("Confusion Matrix - Patient SVM", fontsize=14)
plt.xticks(rotation=45, ha="right")
plt.yticks(rotation=0)
plt.tight_layout()
plt.savefig("confusion_matrix.png", dpi=150, bbox_inches="tight")
plt.show()
print("Saved: confusion_matrix.png")


# %% ==================== CELL 8: SAMPLE PREDICTIONS ====================
# Show raw patient cases from the holdout set: text -> true vs predicted
sample_idx = np.random.RandomState(RANDOM_STATE).choice(
    len(X_test), size=min(10, len(X_test)), replace=False
)
rows = []
for i in sample_idx:
    orig_idx = X_test_indices = None
    # map back: X_test rows correspond to positions in X; recover via index
# simpler: rebuild index mapping
idx_map = np.arange(len(X))
# recompute the same split indices deterministically
tr_idx, te_idx = train_test_split(
    np.arange(len(X)), test_size=0.2, random_state=RANDOM_STATE
)
sample_global = np.random.RandomState(RANDOM_STATE).choice(
    te_idx, size=min(12, len(te_idx)), replace=False
)

print("\n" + "=" * 70)
print("SAMPLE PREDICTIONS (holdout cases)")
print("=" * 70)
for gi in sample_global:
    true_c = class_names[y[gi]]
    pred_c = class_names[model.predict(scaler.transform(X[gi:gi+1]))[0]]
    ok = "OK " if true_c == pred_c else "MISS"
    diag = str(df.iloc[gi]["diagnosis_text"])[:60]
    print(f"[{ok}] true={true_c} | pred={pred_c}")
    print(f"      text: {diag}...")
    rows.append({
        "diagnosis": df.iloc[gi]["diagnosis_text"],
        "true_specialty": true_c,
        "predicted_specialty": pred_c,
        "correct": true_c == pred_c,
    })
pd.DataFrame(rows).to_csv("sample_predictions.csv", index=False, encoding="utf-8-sig")
print("\nSaved: sample_predictions.csv")


# %% ==================== CELL 9: FEATURE IMPORTANCE ====================
# For a LINEAR SVM, coef_ gives per-class weights — the top positive
# TF-IDF terms per class are the "symptoms" that drive each prediction.
if getattr(model, "kernel", None) == "linear":
    coef = model.coef_                      # shape (n_classes, n_features)
    vocab = vectorizer.get_feature_names_out()
    rows = []
    for ci, cname in enumerate(class_names):
        weights = coef[ci]
        # top 8 positive-weight features overall (numerical + tfidf)
        top = np.argsort(weights)[::-1][:8]
        for rank, fi in enumerate(top, 1):
            if fi < 10:
                fname = feature_names[fi]
            else:
                fname = vocab[fi - 10] if (fi - 10) < len(vocab) else f"f{fi}"
            rows.append({
                "class": cname,
                "rank": rank,
                "feature": fname,
                "weight": round(float(weights[fi]), 4),
            })
    imp_df = pd.DataFrame(rows)
    imp_df.to_csv("feature_importance.csv", index=False, encoding="utf-8-sig")
    print("\nTop features per class (linear SVM coefficients):")
    for cname in class_names:
        sub = imp_df[imp_df["class"] == cname].head(5)
        terms = ", ".join(sub["feature"].tolist())
        print(f"  {cname}: {terms}")
    print("Saved: feature_importance.csv")
else:
    print(f"\nBest kernel is '{model.kernel}' — coefficient inspection "
          f"only applies to linear SVM. Skipping feature importance.")


# %% ==================== CELL 10: SUMMARY FOR THESIS ====================
print("\n" + "=" * 60)
print("THESIS-READY SUMMARY")
print("=" * 60)
print(f"Dataset            : {len(df)} synthetic patient cases, "
      f"{X.shape[1]} features "
      f"({X_num.shape[1]} numerical + {X_text.shape[1]} TF-IDF)")
print(f"Classes            : {len(class_names)} care specialties")
print(f"Best model         : {grid.best_params_}")
print(f"Holdout accuracy   : {acc:.4f}  ({int(acc*len(y_test))}/{len(y_test)})")
print(f"5-fold CV accuracy : {cv_scores.mean():.4f} "
      f"(+/- {cv_scores.std():.4f})")
print(f"GridSearchCV score : {grid.best_score_:.4f}")
print("=" * 60)
print("Files to download from the left panel:")
print("  confusion_matrix.png / .csv")
print("  classification_report.csv")
print("  sample_predictions.csv")
print("  feature_importance.csv")
print("=" * 60)


# %% ==================== OPTIONAL: single-case predictor ====================
# Paste a real patient case to see the live prediction + confidence.
def predict_patient_case(age, gender, location, category,
                         disease_count, severity, needs_resident,
                         urgency_raw, diagnosis_text):
    """Replicates ai_service.predict_patient_need feature building."""
    gender_f = 1.0 if gender == "أنثى" else 0.0
    loc_enc = LOCATION_MAPPING.get(location, 0)
    cat_enc = CATEGORY_MAPPING.get(category, 0)
    urgency = URGENCY_MAPPING.get(urgency_raw, 1) / 3.0
    nr = 1.0 if needs_resident else 0.0
    num = np.array([[
        age / 100.0, gender_f, loc_enc / 16.0, cat_enc / 7.0,
        min(disease_count, 10) / 10.0, min(severity, 3) / 3.0,
        nr, urgency,
        min(disease_count * severity, 30) / 30.0,
        (age / 100.0) * (min(severity, 3) / 3.0),
    ]])
    text = f"{normalize_arabic_text(diagnosis_text)} " \
           f"{normalize_arabic_text(category)}"
    xt = vectorizer.transform([text]).toarray()
    Xc = scaler.transform(np.hstack([num, xt]))
    pred = model.predict(Xc)[0]
    # decision_function margin as confidence proxy (ovo SVM)
    df_score = model.decision_function(Xc)
    conf = float(1.0 / (1.0 + np.exp(-abs(float(np.max(df_score))))))
    print(f"Predicted specialty : {class_names[pred]}")
    print(f"Confidence (margin) : {conf:.3f}")
    return class_names[pred]


# Example — 72-year-old woman, amputation, needs resident nurse:
# predict_patient_case(
#     age=72, gender="أنثى", location="المزة",
#     category="أمراض العظام والحركة",
#     disease_count=2, severity=2, needs_resident=True,
#     urgency_raw="يومي",
#     diagnosis_text="بتر ساق بعد حادث يحتاج إعادة تأهيل",
# )

print("\nDone — all metrics above are identical to the production model "
      "because every step replicates train_patient_model.py.")
print("Upload the generated files to your thesis folder.")


# %% ==================== ALTERNATIVE: run the ORIGINAL trainer ==========
# If you prefer to execute the repo's own script verbatim on Colab:
#   !wget -q https://raw.githubusercontent.com/hamzatoo/nurseNet/main/\
#     backend/ai_service/train_patient_model.py -O train_patient_model.py
#   !wget -q $DATA_URL -O patients_dataset.csv
#   !python train_patient_model.py
# NOTE: that script uses numpy-based metrics (sklearn.metrics is blocked
# only on Windows). On Colab you can also uncomment the sklearn.metrics
# import inside it — but the experiment script above is recommended
# because it produces all thesis artifacts (CSV + PNG) directly.

# %% ==================== EOF ====================
if __name__ == "__main__":
    pass
# Colab: just press Runtime -> Run all. No __main__ needed.
# (kept for local python execution compatibility)