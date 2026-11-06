import requests
import json

# Test the health endpoint
try:
    response = requests.get('http://localhost:8000/predict/health')
    print(f"Health Check Status: {response.status_code}")
    print(f"Response: {response.json()}")
except Exception as e:
    print(f"Health check failed: {e}")

# Test the prediction endpoint
try:
    # Generate 37 features (7 numerical + 30 text placeholders)
    features = [3.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0] + [0.0] * 30
    
    test_data = {
        "features": features,
        "patient_data": {
            "medicalCategory": "أمراض القلب والشرايين",
            "medicalTags": ["ضغط دم", "سكر"],
            "location": "دمشق-المزة"
        }
    }
    response = requests.post('http://localhost:8000/predict/', json=test_data)
    print(f"\nPrediction Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2, ensure_ascii=False)}")
    
    # Check if we got matched providers
    if response.status_code == 200:
        result = response.json()
        matched_providers = result.get('matched_providers', [])
        print(f"\nNumber of matched providers: {len(matched_providers)}")
        if matched_providers:
            print("Top matched provider:")
            print(json.dumps(matched_providers[0], indent=2, ensure_ascii=False))
        else:
            print("No matched providers found. Let's test with a different category...")
            
            # Try with nursing care category
            test_data2 = {
                "features": features,
                "patient_data": {
                    "medicalCategory": "رعاية مسنين",
                    "medicalTags": ["رعاية", "مراقبة"],
                    "location": "دمشق-المزة"
                }
            }
            response2 = requests.post('http://localhost:8000/predict/', json=test_data2)
            print(f"\nSecond test - Prediction Status: {response2.status_code}")
            result2 = response2.json()
            matched_providers2 = result2.get('matched_providers', [])
            print(f"Number of matched providers: {len(matched_providers2)}")
            if matched_providers2:
                print("Top matched provider:")
                print(json.dumps(matched_providers2[0], indent=2, ensure_ascii=False))
except Exception as e:
    print(f"Prediction test failed: {e}")

# Test the add provider endpoint
try:
    provider_data = {
        "name": "د. مريم سعيد",
        "specialty": "رعاية مسنين",
        "location": "دمشق-المزة",
        "experience_years": 8,
        "verified": True,
        "available": True,
        "services": "رعاية المسنين, المراقبة الصحية, الدواء اليومي"
    }
    response = requests.post('http://localhost:8000/predict/providers/add', json=provider_data)
    print(f"\nAdd Provider Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2, ensure_ascii=False)}")
except Exception as e:
    print(f"Add provider test failed: {e}")