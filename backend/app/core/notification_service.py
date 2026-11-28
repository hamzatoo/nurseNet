"""Unified notification service for NurseNet.

Supports two notification types:
1. rPPG High Heart-Rate Alert (sent to nurse)
2. Medication Pouch Reminder (sent to patient)

Uses Firebase Cloud Messaging (FCM) via firebase-admin.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta
from typing import Optional

from firebase_admin import credentials, firestore, messaging
from pydantic import BaseModel


class NotificationPayload(BaseModel):
    """Structured payload for FCM notifications."""

    title: str
    body: str
    data: dict[str, str]
    notification_type: str  # "high_hr_alert" or "medication_reminder"


class NotificationService:
    """Service for sending FCM notifications with cooldown/deduplication."""

    _instance: Optional["NotificationService"] = None
    _initialized: bool = False

    # Configuration
    HIGH_HR_THRESHOLD = 180  # BPM
    HIGH_HR_COOLDOWN_MINUTES = 10  # Don't alert same nurse-patient pair within this window

    def __new__(cls) -> "NotificationService":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self) -> None:
        if self._initialized:
            return
        self._initialized = True
        self._db: Optional[firestore.Client] = None
        self._init_firebase()

    def _init_firebase(self) -> None:
        """Initialize Firebase Admin SDK from environment or default credentials."""
        try:
            if not self._db:
                # Use default credentials (set via GOOGLE_APPLICATION_CREDENTIALS env var)
                # or auto-discovery in production (like Render with GOOGLE_APPLICATION_CREDENTIALS)
                self._db = firestore.client()
        except Exception as e:
            print(f"⚠️ Failed to initialize Firebase for notifications: {e}")

    def _get_fcm_token(self, user_id: str) -> Optional[str]:
        """Retrieve the FCM token for a user from Firestore."""
        if not self._db:
            return None
        try:
            doc = self._db.collection("users").document(user_id).get()
            if doc.exists:
                return doc.to_dict().get("fcmToken")
        except Exception as e:
            print(f"⚠️ Failed to fetch FCM token for user {user_id}: {e}")
        return None

    def _is_in_cooldown(self, patient_id: str, nurse_id: str) -> bool:
        """Check if a high-HR alert is still in cooldown for this nurse-patient pair."""
        if not self._db:
            return False
        try:
            cooldown_end = datetime.utcnow() - timedelta(minutes=self.HIGH_HR_COOLDOWN_MINUTES)
            alerts_ref = (
                self._db.collection("notifications")
                .where("type", "==", "high_hr_alert")
                .where("patientId", "==", patient_id)
                .where("nurseId", "==", nurse_id)
                .where("sentAt", ">", cooldown_end)
                .limit(1)
            )
            return len(list(alerts_ref.stream())) > 0
        except Exception as e:
            print(f"⚠️ Failed to check cooldown: {e}")
            return False

    def _log_notification(
        self,
        notification_type: str,
        recipient_id: str,
        payload: NotificationPayload,
        success: bool,
        error_message: Optional[str] = None,
    ) -> None:
        """Log notification attempt to Firestore for audit and cooldown tracking."""
        if not self._db:
            return
        try:
            doc_data = {
                "type": notification_type,
                "recipientId": recipient_id,
                "title": payload.title,
                "body": payload.body,
                "data": payload.data,
                "success": success,
                "errorMessage": error_message,
                "sentAt": datetime.utcnow(),
            }
            # Add type-specific fields
            if notification_type == "high_hr_alert":
                doc_data["patientId"] = payload.data.get("patientId")
                doc_data["nurseId"] = recipient_id
            elif notification_type == "medication_reminder":
                doc_data["patientId"] = recipient_id
                doc_data["medicationId"] = payload.data.get("medicationId")

            self._db.collection("notifications").add(doc_data)
        except Exception as e:
            print(f"⚠️ Failed to log notification: {e}")

    def send_high_hr_alert(
        self,
        patient_id: str,
        patient_name: str,
        bpm: int,
        nurse_id: str,
        nurse_fcm_enabled: bool = True,
    ) -> bool:
        """Send a high heart-rate alert to the assigned nurse.

        Args:
            patient_id: Firestore user ID of the patient
            patient_name: Display name of the patient
            bpm: The heart rate value that triggered the alert
            nurse_id: Firestore user ID of the nurse to notify
            nurse_fcm_enabled: Whether the nurse has alerts enabled (default True)

        Returns:
            True if notification was sent successfully, False otherwise.
        """
        if not nurse_fcm_enabled:
            print("ℹ️ Nurse has disabled high-HR alerts; skipping notification.")
            return False

        if self._is_in_cooldown(patient_id, nurse_id):
            print(f"ℹ️ High-HR alert in cooldown for patient {patient_id} -> nurse {nurse_id}")
            return False

        token = self._get_fcm_token(nurse_id)
        if not token:
            print(f"⚠️ No FCM token found for nurse {nurse_id}")
            self._log_notification(
                "high_hr_alert",
                nurse_id,
                NotificationPayload(
                    title=f"تنبيه نبض مرتفع: {patient_name}",
                    body=f"نبض المريض {bpm} نبضة في الدقيقة (عتبة: {self.HIGH_HR_THRESHOLD})",
                    data={
                        "type": "high_hr_alert",
                        "patientId": patient_id,
                        "patientName": patient_name,
                        "bpm": str(bpm),
                        "timestamp": datetime.utcnow().isoformat(),
                    },
                    notification_type="high_hr_alert",
                ),
                success=False,
                error_message="No FCM token",
            )
            return False

        payload = NotificationPayload(
            title=f"تنبيه نبض مرتفع: {patient_name}",
            body=f"نبض المريض {bpm} نبضة في الدقيقة (عتبة: {self.HIGH_HR_THRESHOLD})",
            data={
                "type": "high_hr_alert",
                "patientId": patient_id,
                "patientName": patient_name,
                "bpm": str(bpm),
                "timestamp": datetime.utcnow().isoformat(),
            },
            notification_type="high_hr_alert",
        )

        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=payload.title,
                    body=payload.body,
                ),
                data=payload.data,
                token=token,
            )
            messaging.send(message)
            print(f"✅ High-HR alert sent to nurse {nurse_id} for patient {patient_id}")
            self._log_notification("high_hr_alert", nurse_id, payload, success=True)
            return True
        except Exception as e:
            print(f"❌ Failed to send high-HR alert: {e}")
            self._log_notification(
                "high_hr_alert",
                nurse_id,
                payload,
                success=False,
                error_message=str(e),
            )
            return False

    def send_medication_reminder(
        self,
        patient_id: str,
        patient_name: str,
        medication_name: str,
        dosage: str,
        scheduled_time: str,
    ) -> bool:
        """Send a medication reminder to the patient.

        Args:
            patient_id: Firestore user ID of the patient
            patient_name: Display name of the patient
            medication_name: Name of the medication
            dosage: Dosage information
            scheduled_time: Time string (e.g., "08:00")

        Returns:
            True if notification was sent successfully, False otherwise.
        """
        token = self._get_fcm_token(patient_id)
        if not token:
            print(f"⚠️ No FCM token found for patient {patient_id}")
            return False

        payload = NotificationPayload(
            title=f"حان موعد دوائك: {medication_name}",
            body=f"{dosage} من الحقيبة الطبية - الموعد: {scheduled_time}",
            data={
                "type": "medication_reminder",
                "medicationName": medication_name,
                "dosage": dosage,
                "scheduledTime": scheduled_time,
                "timestamp": datetime.utcnow().isoformat(),
            },
            notification_type="medication_reminder",
        )

        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=payload.title,
                    body=payload.body,
                ),
                data=payload.data,
                token=token,
            )
            messaging.send(message)
            print(f"✅ Medication reminder sent to patient {patient_id} for {medication_name}")
            self._log_notification("medication_reminder", patient_id, payload, success=True)
            return True
        except Exception as e:
            print(f"❌ Failed to send medication reminder: {e}")
            self._log_notification(
                "medication_reminder",
                patient_id,
                payload,
                success=False,
                error_message=str(e),
            )
            return False


# Singleton instance
notification_service = NotificationService()
