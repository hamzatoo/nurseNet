from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import Dict, Any, Optional, List
from app.core.firebase import firebase_manager
from app.core.dependencies import get_current_user, optional_firebase_auth

router = APIRouter(prefix="/firebase", tags=["firebase"])


class FirestoreData(BaseModel):
    collection: str
    document_id: Optional[str] = None
    data: Dict[str, Any]


class FirestoreResponse(BaseModel):
    status: str
    data: Optional[Dict[str, Any]] = None
    message: str = None


class PredictionSaveRequest(BaseModel):
    user_id: str
    features: List[float]
    prediction: Any
    collection_name: str = "predictions"


@router.get("/status")
async def firebase_status():
    """
    التحقق من حالة Firebase Admin SDK
    
    Returns:
        حالة Firebase والخدمات المتاحة
    """
    status_info = firebase_manager.get_status()
    
    return {
        "firebase": {
            "initialized": status_info["initialized"],
            "app_name": status_info["app_name"],
            "services": {
                "firestore": status_info["has_firestore"],
                "auth": status_info["has_auth"]
            }
        },
        "message": "Firebase is ready" if status_info["initialized"] else "Firebase not initialized - running in development mode"
    }


@router.post("/write", response_model=FirestoreResponse)
async def write_to_firestore(request: FirestoreData, user_data: dict = Depends(get_current_user)):
    """
    كتابة البيانات إلى Firestore (يتطلب مصادقة)
    
    Args:
        request: بيانات Firestore
        user_data: بيانات المستخدم من Firebase Auth
        
    Returns:
        نتيجة عملية الكتابة
    """
    try:
        db = firebase_manager.get_firestore()
        if db is None:
            raise HTTPException(status_code=500, detail="Firebase not initialized")
        
        collection_ref = db.collection(request.collection)
        
        # إضافة معرف المستخدم إلى البيانات
        request.data["user_id"] = user_data.get("uid")
        request.data["user_email"] = user_data.get("email")
        
        if request.document_id:
            doc_ref = collection_ref.document(request.document_id)
            doc_ref.set(request.data)
            doc_id = request.document_id
        else:
            doc_ref = collection_ref.add(request.data)
            doc_id = doc_ref[1].id
        
        return {
            "status": "success",
            "data": {"document_id": doc_id},
            "message": "Data written successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/read/{collection}/{document_id}", response_model=FirestoreResponse)
async def read_from_firestore(collection: str, document_id: str, user_data: dict = Depends(get_current_user)):
    """
    قراءة البيانات من Firestore (يتطلب مصادقة)
    
    Args:
        collection: اسم المجموعة
        document_id: معرف المستند
        user_data: بيانات المستخدم من Firebase Auth
        
    Returns:
        بيانات المستند
    """
    try:
        db = firebase_manager.get_firestore()
        if db is None:
            raise HTTPException(status_code=500, detail="Firebase not initialized")
        
        doc_ref = db.collection(collection).document(document_id)
        doc = doc_ref.get()
        
        if doc.exists:
            doc_data = doc.to_dict()
            # التحقق من أن المستخدم يمتلك البيانات
            if doc_data.get("user_id") != user_data.get("uid"):
                raise HTTPException(status_code=403, detail="Access denied")
            
            return {
                "status": "success",
                "data": doc_data,
                "message": "Data retrieved successfully"
            }
        else:
            raise HTTPException(status_code=404, detail="Document not found")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/collection/{collection}", response_model=FirestoreResponse)
async def read_collection(collection: str, limit: int = 10, user_data: dict = Depends(get_current_user)):
    """
    قراءة جميع المستندات من مجموعة (يتطلب مصادقة)
    
    Args:
        collection: اسم المجموعة
        limit: الحد الأقصى للمستندات
        user_data: بيانات المستخدم من Firebase Auth
        
    Returns:
        بيانات المجموعة
    """
    try:
        db = firebase_manager.get_firestore()
        if db is None:
            raise HTTPException(status_code=500, detail="Firebase not initialized")
        
        # قراءة المستندات الخاصة بالمستخدم فقط
        docs = db.collection(collection)\
                  .where("user_id", "==", user_data.get("uid"))\
                  .limit(limit)\
                  .stream()
        data = [doc.to_dict() for doc in docs]
        
        return {
            "status": "success",
            "data": {"documents": data, "count": len(data)},
            "message": "Collection retrieved successfully"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/save-prediction")
async def save_prediction(request: PredictionSaveRequest, user_data: dict = Depends(get_current_user)):
    """
    حفظ توقعات المستخدم في Firestore (يتطلب مصادقة)
    
    Args:
        request: بيانات التنبؤ
        user_data: بيانات المستخدم من Firebase Auth
        
    Returns:
        نتيجة عملية الحفظ
    """
    try:
        success = firebase_manager.save_prediction(
            user_id=request.user_id,
            features=request.features,
            prediction=request.prediction,
            collection_name=request.collection_name
        )
        
        if success:
            return {
                "status": "success",
                "message": "Prediction saved successfully"
            }
        else:
            raise HTTPException(status_code=500, detail="Failed to save prediction")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/predictions/{user_id}")
async def get_user_predictions(user_id: str, limit: int = 10, user_data: dict = Depends(get_current_user)):
    """
    الحصول على توقعات المستخدم من Firestore (يتطلب مصادقة)
    
    Args:
        user_id: معرف المستخدم
        limit: الحد الأقصى للنتائج
        user_data: بيانات المستخدم من Firebase Auth
        
    Returns:
        قائمة التوقعات
    """
    try:
        # التحقق من أن المستخدم يطلب بياناته الخاصة
        if user_id != user_data.get("uid"):
            raise HTTPException(status_code=403, detail="Access denied")
        
        predictions = firebase_manager.get_user_predictions(
            user_id=user_id,
            limit=limit
        )
        
        return {
            "status": "success",
            "data": {
                "predictions": predictions,
                "count": len(predictions)
            },
            "message": "Predictions retrieved successfully"
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
