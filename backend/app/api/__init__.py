from app.api.predict import router as predict_router
from app.api.firebase import router as firebase_router
from app.api.heart_rate import router as heart_rate_router
from app.api.ocr import router as ocr_router

__all__ = ["predict_router", "firebase_router", "heart_rate_router", "ocr_router"]
