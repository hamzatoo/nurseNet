from fastapi import Header, HTTPException, Depends, status
from typing import Optional
from app.core.firebase import firebase_manager


async def get_firebase_token(authorization: Optional[str] = Header(None)):
    """
    استخراج رمز Firebase Auth من رأس Authorization
    
    Args:
        authorization: رأس Authorization يحتوي على "Bearer <token>"
        
    Returns:
        الرمز المستخرج
        
    Raises:
        HTTPException: إذا لم يتم توفير الرمز بشكل صحيح
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header missing"
        )
    
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header format. Expected: Bearer <token>"
        )
    
    token = authorization.split("Bearer ")[1]
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing"
        )
    
    return token


async def get_current_user(token: str = Depends(get_firebase_token)):
    """
    التحقق من صحة رمز Firebase Auth والحصول على بيانات المستخدم
    
    Args:
        token: رمز Firebase Auth
        
    Returns:
        بيانات المستخدم
        
    Raises:
        HTTPException: إذا كان الرمز غير صحيح
    """
    decoded_token = firebase_manager.verify_token(token)
    
    if not decoded_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase token"
        )
    
    return decoded_token


async def optional_firebase_auth(authorization: Optional[str] = Header(None)):
    """
    مصادقة Firebase اختيارية - تستخدم للEndpoints التي تعمل مع أو بدون مصادقة
    
    Args:
        authorization: رأس Authorization الاختياري
        
    Returns:
        بيانات المستخدم إذا تم توفير رمز صحيح، None إذا لم يتم توفير رمز
    """
    if not authorization:
        return None
    
    try:
        if not authorization.startswith("Bearer "):
            return None
        
        token = authorization.split("Bearer ")[1]
        if not token:
            return None
        
        decoded_token = firebase_manager.verify_token(token)
        return decoded_token
    except Exception:
        return None