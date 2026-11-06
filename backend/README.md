# Backend API

FastAPI backend service with AI prediction and Firebase integration.

## Structure

```
backend/
├── app/
│   ├── api/              # API endpoints
│   │   ├── predict.py    # AI prediction endpoints
│   │   └── firebase.py   # Firebase integration endpoints
│   └── core/             # Core services
│       ├── config.py     # Application configuration
│       ├── firebase.py   # Firebase manager
│       ├── ai_service.py # AI model service
│       └── dependencies.py # Firebase Auth dependencies
├── ai_service/           # AI model files
│   ├── svm_model.pkl
│   └── scaler.pkl
├── main.py               # Application entry point
├── requirements.txt      # Python dependencies
└── .env.example          # Environment variables template
```

## Installation

1. Navigate to the backend directory:
```bash
cd backend
```

2. Create a virtual environment:
```bash
python -m venv venv
```

3. Activate the virtual environment:
- Windows: `venv\Scripts\activate`
- Linux/Mac: `source venv/bin/activate`

4. Install dependencies:
```bash
pip install -r requirements.txt
```

5. Configure environment variables:
```bash
copy .env.example .env
```
Edit `.env` with your configuration.

## Configuration

### Firebase Setup

Add your Firebase credentials in one of these ways:

1. **File-based**: Add your Firebase service account key as `firebase_credentials.json` in the backend directory
2. **Environment variable**: Set `FIREBASE_CREDENTIALS_JSON` with the JSON content of your service account key

The server will work in development mode even without Firebase credentials, but Firebase features will be disabled.

## Running the Server

Development mode (with auto-reload):
```bash
python main.py
```

Or using uvicorn directly:
```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Production mode:
```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

## API Endpoints

### Health Check
- `GET /` - Root endpoint
- `GET /health` - Health check

### Prediction Endpoints
- `POST /predict/` - Make AI prediction (optional Firebase integration)
- `GET /predict/health` - Check AI service status

### Firebase Endpoints
- `GET /firebase/status` - Check Firebase connection status
- `POST /firebase/write` - Write data to Firestore (requires authentication)
- `GET /firebase/read/{collection}/{document_id}` - Read document from Firestore (requires authentication)
- `GET /firebase/collection/{collection}` - Read collection from Firestore (requires authentication)
- `POST /firebase/save-prediction` - Save prediction to Firestore (requires authentication)
- `GET /firebase/predictions/{user_id}` - Get user predictions from Firestore (requires authentication)

## Firebase Authentication

Most Firebase endpoints require authentication. Include the Firebase ID token in the Authorization header:

```
Authorization: Bearer <firebase_id_token>
```

## API Documentation

Once the server is running, access:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

## Features

### Firebase Integration
- **Safe Initialization**: Firebase initializes gracefully even without credentials (development mode)
- **Multiple Auth Methods**: Supports file-based and environment variable credentials
- **Token Verification**: Built-in Firebase Auth token verification
- **Firestore Operations**: Complete CRUD operations with user-specific data isolation
- **Prediction History**: Automatic saving of predictions to Firestore

### AI Service
- **Model Loading**: Automatic loading of SVM model and scaler
- **Error Handling**: Graceful error handling for missing models
- **Optional Firebase Integration**: Predictions can be saved to Firestore if desired
