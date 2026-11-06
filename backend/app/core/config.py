from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Backend API"
    app_version: str = "1.0.0"
    debug: bool = True
    
    # Firebase Configuration
    firebase_credentials_path: str = "firebase_credentials.json"
    firebase_project_id: str = ""
    
    # AI Model Configuration
    ai_model_path: str = "ai_service/svm_model.pkl"
    ai_scaler_path: str = "ai_service/scaler.pkl"
    
    # CORS Configuration
    cors_origins: list = ["*"]
    
    # Firestore Configuration
    firestore_predictions_collection: str = "predictions"
    firestore_users_collection: str = "users"
    
    model_config = {"protected_namespaces": (), "env_file": ".env"}


settings = Settings()
