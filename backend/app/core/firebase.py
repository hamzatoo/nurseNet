import firebase_admin
from firebase_admin import credentials, firestore, auth
from app.core.config import settings
import os
import json
from typing import Optional


class FirebaseManager:
    def __init__(self):
        self.app = None
        self.db = None
        self.auth = None
        self.is_initialized = False
        self._initialize_firebase()
    
    def _initialize_firebase(self):
        """
        تهيئة Firebase Admin SDK بأمان مع معالجة الأخطاء
        """
        try:
            # التحقق من أن Firebase لم يتم تهيئته من قبل
            if not firebase_admin._apps:
                # 1. محاولة قراءة ملف بيانات الاعتماد
                cred_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 
                                        settings.firebase_credentials_path)
                
                # 2. محاولة الحصول على بيانات الاعتماد من متغيرات البيئة
                firebase_creds_env = os.getenv("FIREBASE_CREDENTIALS_JSON")
                
                if os.path.exists(cred_path):
                    # استخدام ملف بيانات الاعتماد
                    cred = credentials.Certificate(cred_path)
                    self.app = firebase_admin.initialize_app(cred)
                    print("✅ Firebase initialized from credentials file")
                elif firebase_creds_env:
                    # استخدام متغيرات البيئة
                    cred_dict = json.loads(firebase_creds_env)
                    cred = credentials.Certificate(cred_dict)
                    self.app = firebase_admin.initialize_app(cred)
                    print("✅ Firebase initialized from environment variables")
                else:
                    # في بيئة التطوير، نسمح بالعمل بدون Firebase
                    print("⚠️ Firebase credentials not found - running in development mode")
                    self.is_initialized = False
                    return
            
            # تهيئة Firestore و Auth
            self.db = firestore.client()
            self.auth = auth
            self.is_initialized = True
            print("✅ Firebase services (Firestore & Auth) initialized successfully")
            
        except Exception as e:
            print(f"❌ Firebase initialization error: {e}")
            self.is_initialized = False
    
    def get_firestore(self) -> Optional[firestore.Client]:
        """
        الحصول على عميل Firestore
        """
        return self.db if self.is_initialized else None
    
    def get_auth(self) -> Optional[auth.Client]:
        """
        الحصول على عميل Firebase Auth
        """
        return self.auth if self.is_initialized else None
    
    def verify_token(self, id_token: str) -> Optional[dict]:
        """
        التحقق من صحة رمز Firebase Auth
        
        Args:
            id_token: رمز المصادقة من Firebase
            
        Returns:
            بيانات المستخدم إذا كان الرمز صحيحاً، None إذا لم يكن
        """
        if not self.is_initialized or not self.auth:
            print("⚠️ Firebase Auth not initialized")
            return None
        
        try:
            decoded_token = self.auth.verify_id_token(id_token)
            return decoded_token
        except Exception as e:
            print(f"❌ Token verification error: {e}")
            return None
    
    def save_prediction(self, user_id: str, features: list, prediction: any, 
                      collection_name: str = "predictions") -> bool:
        """
        حفظ توقعات المستخدم في Firestore
        
        Args:
            user_id: معرف المستخدم
            features: الميزات المستخدمة في التنبؤ
            prediction: نتيجة التنبؤ
            collection_name: اسم المجموعة في Firestore
            
        Returns:
            True إذا تم الحفظ بنجاح، False إذا فشل
        """
        if not self.is_initialized or not self.db:
            print("⚠️ Firestore not initialized - prediction not saved")
            return False
        
        try:
            doc_ref = self.db.collection(collection_name).document()
            doc_ref.set({
                "user_id": user_id,
                "features": features,
                "prediction": prediction,
                "timestamp": firestore.SERVER_TIMESTAMP
            })
            print(f"✅ Prediction saved for user {user_id}")
            return True
        except Exception as e:
            print(f"❌ Error saving prediction: {e}")
            return False
    
    def get_user_predictions(self, user_id: str, 
                            collection_name: str = "predictions",
                            limit: int = 10) -> list:
        """
        الحصول على توقعات المستخدم من Firestore
        
        Args:
            user_id: معرف المستخدم
            collection_name: اسم المجموعة في Firestore
            limit: الحد الأقصى للنتائج
            
        Returns:
            قائمة بالتوقعات
        """
        if not self.is_initialized or not self.db:
            print("⚠️ Firestore not initialized")
            return []
        
        try:
            docs = self.db.collection(collection_name)\
                         .where("user_id", "==", user_id)\
                         .order_by("timestamp", direction=firestore.DESCENDING)\
                         .limit(limit)\
                         .stream()
            return [doc.to_dict() for doc in docs]
        except Exception as e:
            print(f"❌ Error getting user predictions: {e}")
            return []
    
    def get_status(self) -> dict:
        """
        الحصول على حالة Firebase
        
        Returns:
            قاموس يحتوي على حالة Firebase
        """
        return {
            "initialized": self.is_initialized,
            "has_firestore": self.db is not None,
            "has_auth": self.auth is not None,
            "app_name": self.app.name if self.app else None
        }


# إنشاء نسخة واحدة من FirebaseManager
firebase_manager = FirebaseManager()
