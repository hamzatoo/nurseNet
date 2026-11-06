from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Any, Optional
from app.core.ai_service import ai_service
from app.core.firebase import firebase_manager
from app.core.dependencies import optional_firebase_auth

router = APIRouter(prefix="/predict", tags=["prediction"])


class PredictionRequest(BaseModel):
    features: List[float]
    save_to_firestore: bool = False
    user_id: Optional[str] = None
    patient_data: Optional[dict] = None
    
    class Config:
        # Allow both individual fields and list format
        extra = "allow"


class PredictionResponse(BaseModel):
    prediction: Any
    status: str
    error: str = None
    saved: bool = False


class ProviderRegistrationRequest(BaseModel):
    """Request model for adding a new provider"""
    name: str
    specialty: str
    location: str
    experience_years: int
    verified: bool = True
    available: bool = True
    services: str
    
    class Config:
        extra = "allow"


@router.post("/")
async def make_prediction(request: PredictionRequest, user_data: Optional[dict] = Depends(optional_firebase_auth)):
    """
    عمل تنبؤ باستخدام نموذج الذكاء الاصطناعي ومطابقة مقدمي الخدمات
    
    Args:
        request: طلب التنبؤ يحتوي على الميزات وبيانات المريض
        user_data: بيانات المستخدم الاختيارية من Firebase Auth
        
    Returns:
        نتيجة التنبؤ ومقدمي الخدمات المتطابقين
    """
    try:
        # Handle both old format (individual feature fields) and new format (features list)
        features = request.features
        
        # If features is empty, try to extract from individual fields (backward compatibility)
        if not features:
            # Try to get individual feature fields if they exist
            feature_fields = ['feature1', 'feature2', 'feature3', 'feature4', 
                            'feature5', 'feature6', 'feature7', 'feature8']
            features = []
            for field in feature_fields:
                if hasattr(request, field):
                    value = getattr(request, field)
                    if value is not None:
                        features.append(float(value))
        
        if not features:
            raise HTTPException(status_code=400, detail="No features provided")
        
        print(f"🔍 Received prediction request with features: {features}")
        
        # Get SVM prediction
        result = ai_service.predict(features)
        print(f"🎯 SVM Prediction result: {result}")
        
        if result["status"] == "error":
            raise HTTPException(status_code=500, detail=result["error"])
        
        # Get provider matches if patient data is provided
        matched_providers = []
        if request.patient_data:
            print(f"🏥 Matching providers for patient data: {request.patient_data}")
            matched_providers = ai_service.match_providers(request.patient_data)
            print(f"✅ Found {len(matched_providers)} matched providers")
        
        saved = False
        # حفظ التنبؤ في Firestore إذا طلب المستخدم وكان Firebase متاحاً
        if request.save_to_firestore and firebase_manager.is_initialized:
            user_id = request.user_id or (user_data.get("uid") if user_data else None)
            if user_id:
                saved = firebase_manager.save_prediction(
                    user_id=user_id,
                    features=features,
                    prediction=result["prediction"]
                )
        
        return {
            "prediction": result["prediction"], 
            "status": result["status"],
            "saved": saved,
            "matched_providers": matched_providers
        }
    except HTTPException as he:
        print(f"❌ HTTP Exception in prediction endpoint: {he.detail}")
        raise he
    except Exception as e:
        print(f"❌ Error in prediction endpoint: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/health")
async def health_check():
    """
    التحقق من أن خدمة الذكاء الاصطناعي جاهزة
    """
    return {
        "status": "healthy" if ai_service.model is not None else "unhealthy",
        "model_loaded": ai_service.model is not None,
        "scaler_loaded": ai_service.scaler is not None,
        "vectorizer_loaded": ai_service.vectorizer is not None,
        "firebase_initialized": firebase_manager.is_initialized
    }


@router.post("/providers/add")
async def add_provider(request: ProviderRegistrationRequest):
    """
    إضافة ممرض جديد إلى قاعدة البيانات وإعادة تحميل مجموعة البيانات
    
    Args:
        request: بيانات الممرض الجديد
        
    Returns:
        نتيجة الإضافة مع عدد الممرضين الحالي
    """
    try:
        # Prepare provider data
        provider_data = {
            'name': request.name,
            'specialty': request.specialty,
            'location': request.location,
            'experience_years': request.experience_years,
            'verified': request.verified,
            'available': request.available,
            'services': request.services
        }
        
        # Add to dataset
        success = ai_service.add_provider_to_dataset(provider_data)
        
        if success:
            # Reload dataset
            provider_count = ai_service.reload_dataset()
            
            return {
                "status": "success",
                "message": "Provider added successfully",
                "provider_count": provider_count,
                "provider_data": provider_data
            }
        else:
            raise HTTPException(status_code=500, detail="Failed to add provider")
            
    except Exception as e:
        logger.error(f"❌ Error adding provider: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
