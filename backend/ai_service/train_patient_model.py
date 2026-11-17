"""
SVM Model Trainer for Patient Care-Need Classification — NurseNet
=================================================================

Trains an SVM classifier that predicts the REQUIRED CARE SPECIALTY for a
patient case, using the synthetic patient dataset (patients_dataset.csv).

Pipeline (mirrors train_svm_model.py for thesis consistency):
1. Load patient dataset (X features + y label per row)
2. Feature engineering: ~10 numerical + TF-IDF text features
3. Arabic text normalization
4. SVC + GridSearchCV hyperparameter tuning + StandardScaler
5. train_test_split self-evaluation (accuracy + classification report)
6. Persist model/scaler/vectorizer/metadata as .pkl for production

At inference time ai_service.predict_patient_need() rebuilds the exact same
features and the predicted specialty filters damascus_providers by specialty.
"""

import csv
import os
import logging
from typing import Dict, List, Tuple

import joblib
import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import GridSearchCV, train_test_split
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.svm import SVC

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


def _accuracy(y_true, y_pred) -> float:
    """sklearn.metrics is blocked by Windows Application Control on some
    machines - compute accuracy with numpy instead."""
    return float(np.mean(np.asarray(y_true) == np.asarray(y_pred)))


def _classification_report(y_true, y_pred, class_names):
    """Minimal per-class report without sklearn.metrics."""
    y_true = np.asarray(y_true)
    y_pred = np.asarray(y_pred)
    lines = ["class | precision | recall | f1 | support"]
    for i, name in enumerate(class_names):
        tp = int(np.sum((y_true == i) & (y_pred == i)))
        fp = int(np.sum((y_true != i) & (y_pred == i)))
        fn = int(np.sum((y_true == i) & (y_pred != i)))
        support = int(np.sum(y_true == i))
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        lines.append(f"{name} | {prec:.2f} | {rec:.2f} | {f1:.2f} | {support}")
    lines.append(f"overall accuracy: {_accuracy(y_true, y_pred):.4f}")
    return "\n".join(lines)


def _scorer(estimator, X, y):
    """Callable scorer for GridSearchCV avoiding sklearn.metrics."""
    return _accuracy(y, estimator.predict(X))


class PatientModelTrainer:
    """Trains the patient -> required-specialty SVM classifier."""

    def __init__(self, dataset_path: str = None):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        self.dataset_path = dataset_path or os.path.join(script_dir, "patients_dataset.csv")
        self.df = None
        self.scaler = StandardScaler()
        self.label_encoder = LabelEncoder()
        self.model = None
        self.vectorizer = None
        self.feature_names = []

        # Fixed vocabularies — MUST stay identical at inference time
        # (saved into patient_metadata.pkl and reused by ai_service).
        self.location_mapping = self._create_location_mapping()
        self.category_mapping = self._create_category_mapping()
        self.urgency_mapping = {"طارئ": 3, "متوسط": 2, "يومي": 1, "روتيني": 1, "مستمر": 1}

    # ------------------------------------------------------------------
    # Vocabulary builders (fixed ordering = stable encodings)
    # ------------------------------------------------------------------
    def _create_location_mapping(self) -> Dict[str, int]:
        locations = [
            "المزة", "المالكي", "الشعلان", "البرامكة", "القصاع", "الميدان",
            "الزرقاء", "أبو رمانة", "المرجة", "اليعقوبية", "جوبر", "دوما",
            "حرستا", "اليرموك", "القابون", "تشرين", "السيدة زينب",
        ]
        return {loc: idx for idx, loc in enumerate(locations)}

    def _create_category_mapping(self) -> Dict[str, int]:
        categories = [
            "أمراض القلب والشرايين", "الأمراض العصبية", "أمراض الكلى وغسيل الكلى",
            "أمراض العظام والحركة", "أمراض الجهاز التنفسي", "أمراض العيون",
            "الأورام والسرطان", "الحالات الطارئة والإصابات",
        ]
        return {cat: idx for idx, cat in enumerate(categories)}

    # ------------------------------------------------------------------
    # Text helpers (same normalization rules as the providers trainer)
    # ------------------------------------------------------------------
    @staticmethod
    def _normalize_arabic_text(text: str) -> str:
        if not isinstance(text, str):
            return ""
        for d in ["َ", "ً", "ُ", "ٌ", "ِ", "ٍ", "ْ", "ّ"]:
            text = text.replace(d, "")
        text = text.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
        text = text.replace("ة", "ه")
        return " ".join(text.split()).lower()

    # ------------------------------------------------------------------
    # Pipeline steps
    # ------------------------------------------------------------------
    def load_data(self) -> pd.DataFrame:
        self.df = pd.read_csv(self.dataset_path, encoding="utf-8-sig")
        logger.info(f"Loaded {len(self.df)} patient records from {self.dataset_path}")
        return self.df

    def engineer_features(self) -> Tuple[np.ndarray, np.ndarray]:
        if self.df is None:
            raise ValueError("Data not loaded. Call load_data() first.")

        logger.info("Engineering patient features...")
        numerical = []
        texts = []
        labels = []

        for _, row in self.df.iterrows():
            try:
                age = float(row.get("age", 0) or 0)
                gender_f = 1.0 if str(row.get("gender", "")) == "أنثى" else 0.0
                location = str(row.get("location", ""))
                category = str(row.get("care_category", ""))
                disease_count = float(row.get("disease_count", 0) or 0)
                severity = float(row.get("condition_severity", 0) or 0)
                needs_resident = 1.0 if str(row.get("needs_resident", "")).lower() == "true" else 0.0
                urgency_raw = str(row.get("care_urgency", ""))
                urgency = self.urgency_mapping.get(urgency_raw, 1) / 3.0
                diagnosis = str(row.get("diagnosis_text", ""))
                label = str(row.get("required_specialty", ""))
            except Exception as e:
                logger.error(f"Row parse error: {e}")
                continue

            loc_enc = self.location_mapping.get(location, 0)
            cat_enc = self.category_mapping.get(category, 0)

            numerical.append([
                age / 100.0,                                  # 1 age normalized
                gender_f,                                     # 2 gender
                loc_enc / 16.0,                               # 3 location encoded
                cat_enc / 7.0,                                # 4 category encoded
                min(disease_count, 10) / 10.0,                # 5 disease count
                min(severity, 3) / 3.0,                       # 6 severity
                needs_resident,                               # 7 resident nurse flag
                urgency,                                      # 8 urgency
                min(disease_count * severity, 30) / 30.0,     # 9 burden interaction
                (age / 100.0) * (min(severity, 3) / 3.0),     # 10 age x severity
            ])

            norm_diag = self._normalize_arabic_text(diagnosis)
            norm_cat = self._normalize_arabic_text(category)
            texts.append(f"{norm_diag} {norm_cat}")
            labels.append(label)

        X_num = np.array(numerical, dtype=np.float64)
        y_raw = np.array(labels)

        # TF-IDF on symptom/diagnosis text — learns patient-side vocabulary
        self.vectorizer = TfidfVectorizer(
            ngram_range=(1, 2),
            sublinear_tf=True,
            max_features=60,
        )
        X_text = self.vectorizer.fit_transform(texts).toarray()
        X = np.hstack([X_num, X_text])
        y = self.label_encoder.fit_transform(y_raw)

        self.feature_names = [
            "age_norm", "gender_f", "location_enc", "category_enc",
            "disease_count", "severity", "needs_resident", "urgency",
            "burden", "age_x_severity",
        ] + [f"tfidf_{i}" for i in range(X_text.shape[1])]

        logger.info(f"Features shape: {X.shape} | classes: {self.label_encoder.classes_.tolist()}")
        logger.info(f"Label distribution: {dict(zip(*np.unique(y, return_counts=True)))}")
        return X, y

    def train_model(self, X: np.ndarray, y: np.ndarray) -> SVC:
        logger.info("Training patient SVM with GridSearchCV...")

        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)

        param_grid = {
            "C": [1, 10, 50, 100],
            "kernel": ["linear", "rbf"],
            "gamma": ["scale", "auto", 0.01, 0.1],
        }
        grid = GridSearchCV(
            SVC(random_state=42), param_grid, cv=3,
            scoring=_scorer, n_jobs=-1, verbose=1,
        )
        grid.fit(X_train_scaled, y_train)
        self.model = grid.best_estimator_
        logger.info(f"Best params: {grid.best_params_} | CV acc: {grid.best_score_:.4f}")

        y_pred = self.model.predict(X_test_scaled)
        acc = _accuracy(y_test, y_pred)
        logger.info(f"Test accuracy: {acc:.4f}")
        logger.info("\n" + _classification_report(
            y_test, y_pred,
            [str(c) for c in self.label_encoder.classes_],
        ))
        return self.model

    def save_model(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        joblib.dump(self.model, os.path.join(script_dir, "patient_svm_model.pkl"))
        joblib.dump(self.scaler, os.path.join(script_dir, "patient_scaler.pkl"))
        joblib.dump(self.vectorizer, os.path.join(script_dir, "patient_vectorizer.pkl"))
        joblib.dump(self.label_encoder, os.path.join(script_dir, "patient_label_encoder.pkl"))
        metadata = {
            "feature_names": self.feature_names,
            "location_mapping": self.location_mapping,
            "category_mapping": self.category_mapping,
            "urgency_mapping": self.urgency_mapping,
            "classes": [str(c) for c in self.label_encoder.classes_],
        }
        joblib.dump(metadata, os.path.join(script_dir, "patient_metadata.pkl"))
        logger.info("Saved patient_svm_model.pkl, patient_scaler.pkl, patient_vectorizer.pkl, patient_label_encoder.pkl, patient_metadata.pkl")

    def run(self):
        self.load_data()
        X, y = self.engineer_features()
        self.train_model(X, y)
        self.save_model()
        logger.info("Patient model training pipeline completed.")


def main():
    PatientModelTrainer().run()


if __name__ == "__main__":
    main()
