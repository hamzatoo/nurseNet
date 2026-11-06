# Deployment Guide for NurseNet Backend

## Prerequisites
- Python 3.11+
- Docker (optional, for containerized deployment)
- Firebase service account credentials (firebase_credentials.json)

## Local Development
```bash
cd backend
python -m venv venv
venv\Scripts\activate  # Windows
# or source venv/bin/activate  # Linux/Mac
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## Deploy to Render (Recommended)

### Option 1: Using Docker (render.yaml)
1. Push your code to GitHub
2. Go to [Render.com](https://render.com)
3. Click "New +" → "Web Service"
4. Connect your GitHub repository
5. Select "Docker" as the runtime
6. Set build command: `docker build -t app .`
7. Set start command: `docker run -p $PORT:8000 app`
8. Add environment variables:
   - `PORT=8000`
   - `FIREBASE_CREDENTIALS_PATH=/app/firebase_credentials.json`

### Option 2: Manual Deployment
1. Go to [Render.com](https://render.com)
2. Click "New +" → "Web Service"
3. Connect your GitHub repository
4. Select "Python" as the runtime
5. Set build command: `pip install -r requirements.txt`
6. Set start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
7. Add environment variables

## Deploy to Railway

1. Go to [Railway.app](https://railway.app)
2. Click "New Project" → "Deploy from GitHub repo"
3. Select your repository
4. Railway will auto-detect Python
5. Add environment variables
6. Deploy!

## Deploy to Hugging Face Spaces

1. Go to [Hugging Face Spaces](https://huggingface.co/spaces)
2. Click "Create new Space"
3. Select "Docker" SDK
4. Upload your code or connect GitHub
5. Add environment variables
6. Deploy!

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `PORT` | Server port | Yes |
| `FIREBASE_CREDENTIALS_PATH` | Path to Firebase credentials | Yes |
| `FIREBASE_PROJECT_ID` | Firebase project ID | Yes |
| `DEBUG` | Debug mode (true/false) | No |

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Root endpoint |
| `/health` | GET | Health check |
| `/predict/` | POST | AI nurse prediction |
| `/api/calculate-heart-rate` | POST | Heart rate from video |
| `/api/ocr-prescription` | POST | Prescription OCR |
| `/firebase/status` | GET | Firebase status |

## Testing the Deployment

Once deployed, test with:
```bash
curl https://your-app.onrender.com/health
```

Expected response:
```json
{"status":"healthy","app_name":"Backend API","version":"1.0.0"}
```

## Updating Flutter App

After deployment, update `lib/config/api_config.dart`:

```dart
static String baseUrl = 'https://your-app.onrender.com';
```

Or use `ApiService.setBaseUrl('https://your-app.onrender.com')` in your code.
