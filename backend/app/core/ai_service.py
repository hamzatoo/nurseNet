import joblib
import numpy as np
import pandas as pd
from app.core.config import settings
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class AIService:
    def __init__(self):
        self.model = None
        self.scaler = None
        self.vectorizer = None
        self.providers_df = None
        self._load_models()
        self._load_providers_dataset()
    
    def _load_models(self):
        try:
            base_path = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
            model_path = os.path.join(base_path, settings.ai_model_path)
            scaler_path = os.path.join(base_path, settings.ai_scaler_path)
            vectorizer_path = os.path.join(base_path, "ai_service", "vectorizer.pkl")
            
            if os.path.exists(model_path):
                self.model = joblib.load(model_path)
                logger.info("✅ Model loaded successfully")
            else:
                logger.warning(f"⚠️ Model file not found at: {model_path}")
            
            if os.path.exists(scaler_path):
                self.scaler = joblib.load(scaler_path)
                logger.info("✅ Scaler loaded successfully")
            else:
                logger.warning(f"⚠️ Scaler file not found at: {scaler_path}")
            
            if os.path.exists(vectorizer_path):
                self.vectorizer = joblib.load(vectorizer_path)
                logger.info("✅ Vectorizer loaded successfully")
            else:
                logger.warning(f"⚠️ Vectorizer file not found at: {vectorizer_path}")
        except Exception as e:
            logger.error(f"❌ Error loading AI models: {e}")

    def _load_providers_dataset(self):
        """Load the Damascus healthcare providers dataset with dynamic reload support"""
        try:
            base_path = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
            dataset_path = os.path.join(base_path, "ai_service", "damascus_providers_fixed.csv")
            
            if os.path.exists(dataset_path):
                self.providers_df = pd.read_csv(dataset_path, encoding='utf-8-sig')
                logger.info(f"✅ Loaded {len(self.providers_df)} providers from dataset")
                logger.info(f"📊 Available specialties: {self.providers_df['specialty'].unique().tolist()}")
                logger.info(f"📍 Available locations: {self.providers_df['location'].unique().tolist()}")
                logger.info(f"🔄 Dataset reloaded dynamically")
            else:
                logger.warning(f"⚠️ Dataset file not found at: {dataset_path}")
                self.providers_df = pd.DataFrame()
        except Exception as e:
            logger.error(f"❌ Error loading providers dataset: {e}")
            self.providers_df = pd.DataFrame()
    
    def reload_dataset(self):
        """Force reload the providers dataset - useful when new nurses are added"""
        logger.info("🔄 Forcing dataset reload...")
        self._load_providers_dataset()
        return len(self.providers_df) if not self.providers_df.empty else 0
    
    def add_provider_to_dataset(self, provider_data: dict):
        """
        Add a new provider to the dataset and sync with CSV file
        
        Args:
            provider_data: Dictionary containing provider information
                         (name, specialty, location, experience_years, verified, available, services)
        
        Returns:
            True if successful, False otherwise
        """
        try:
            if self.providers_df is None or self.providers_df.empty:
                logger.warning("⚠️ Dataset not loaded, initializing new dataset")
                self.providers_df = pd.DataFrame(columns=['name', 'specialty', 'location', 'experience_years', 'verified', 'available', 'services'])
            
            # Create new provider row
            new_provider = pd.DataFrame([{
                'name': provider_data.get('name', ''),
                'specialty': provider_data.get('specialty', ''),
                'location': provider_data.get('location', ''),
                'experience_years': provider_data.get('experience_years', 0),
                'verified': provider_data.get('verified', True),
                'available': provider_data.get('available', True),
                'services': provider_data.get('services', '')
            }])
            
            # Append to dataset
            self.providers_df = pd.concat([self.providers_df, new_provider], ignore_index=True)
            
            # Save to CSV file
            base_path = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
            dataset_path = os.path.join(base_path, "ai_service", "damascus_providers_fixed.csv")
            self.providers_df.to_csv(dataset_path, index=False)
            
            logger.info(f"✅ Added new provider: {provider_data.get('name')} - {provider_data.get('specialty')}")
            logger.info(f"📊 Total providers in dataset: {len(self.providers_df)}")
            
            return True
        except Exception as e:
            logger.error(f"❌ Error adding provider to dataset: {e}")
            return False

    def _normalize_arabic_text(self, text):
        """Normalize Arabic text for better matching"""
        if not isinstance(text, str):
            return ""
        
        # Remove Arabic diacritics (basic)
        arabic_diacritics = ['َ', 'ً', 'ُ', 'ٌ', 'ِ', 'ٍ', 'ْ', 'ّ']
        for diacritic in arabic_diacritics:
            text = text.replace(diacritic, '')
        
        # Normalize alef and variations
        text = text.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')
        
        # Normalize ha variations
        text = text.replace('ة', 'ه')
        
        # Remove extra spaces
        text = ' '.join(text.split())
        
        return text.lower()

    def _normalize_location(self, location):
        """Normalize location names for better matching"""
        if not isinstance(location, str):
            return ""
        
        # Remove common prefixes/suffixes
        location = location.replace('دمشق-', '').replace('-دمشق', '')
        location = location.replace('ريف دمشق', 'دمشق')
        location = location.replace('الرياض', 'الرياض')
        
        # Normalize the Arabic text
        return self._normalize_arabic_text(location)

    def predict(self, features):
        try:
            if self.model is None:
                raise ValueError("Model not loaded")
            
            logger.info(f"🔍 Received features for prediction: {features}")
            
            # 1. تحويل القائمة لمصفوفة 2D
            features_array = np.asarray(features).reshape(1, -1)
            logger.info(f"📊 Features array shape: {features_array.shape}")
            
            # 2. تطبيق التحويل مع إزالة أسماء الأعمدة لتفادي التضارب
            if self.scaler is not None:
                features_array = self.scaler.transform(features_array)
                logger.info(f"🔄 Applied scaler transformation")
            
            # 3. التنبؤ
            prediction = self.model.predict(features_array)
            logger.info(f"🎯 SVM Prediction: {prediction}")
            
            return {
                "prediction": prediction.tolist(),
                "status": "success"
            }
        except Exception as e:
            logger.error(f"❌ Error in predict: {str(e)}")
            return {
                "status": "error",
                "error": str(e)
            }

    def match_providers(self, patient_data):
        """
        Match providers based on patient data using both SVM results and rule-based matching
        
        Args:
            patient_data: Dictionary containing medicalCategory, medicalTags, location
            
        Returns:
            List of matched providers with scores
        """
        try:
            if self.providers_df is None or self.providers_df.empty:
                logger.warning("⚠️ No providers dataset available")
                return []
            
            logger.info(f"🏥 Matching providers for patient data: {patient_data}")
            
            # Extract patient data
            medical_category = patient_data.get('medicalCategory', '')
            medical_tags = patient_data.get('medicalTags', [])
            location = patient_data.get('location', '')
            
            # Normalize inputs
            normalized_category = self._normalize_arabic_text(medical_category)
            normalized_location = self._normalize_location(location)
            normalized_tags = [self._normalize_arabic_text(tag) for tag in medical_tags]
            
            logger.info(f"🔤 Normalized category: {normalized_category}")
            logger.info(f"📍 Normalized location: {normalized_location}")
            logger.info(f"🏷️ Normalized tags: {normalized_tags}")
            
            # Calculate match scores for each provider
            scored_providers = []
            
            for _, provider in self.providers_df.iterrows():
                score = 0.0
                match_reasons = []
                
                # Normalize provider data
                provider_specialty = self._normalize_arabic_text(provider['specialty'])
                provider_location = self._normalize_location(provider['location'])
                provider_services = [self._normalize_arabic_text(service) 
                                   for service in str(provider['services']).split(',')]
                
                # 1. Specialty matching (40 points max)
                if self._is_specialty_match(normalized_category, provider_specialty):
                    score += 40
                    match_reasons.append(f"تخصص مطابق: {provider['specialty']}")
                elif self._is_related_specialty(normalized_category, provider_specialty):
                    score += 20
                    match_reasons.append(f"تخصص مرتبط: {provider['specialty']}")
                
                # 2. Location matching (20 points max)
                if normalized_location and provider_location:
                    if (normalized_location in provider_location or 
                        provider_location in normalized_location or
                        normalized_location == provider_location):
                        score += 20
                        match_reasons.append(f"موقع مطابق: {provider['location']}")
                
                # 3. Experience points (20 points max)
                experience_years = provider.get('experience_years', 0)
                experience_score = min(experience_years * 2, 20)
                score += experience_score
                if experience_score > 0:
                    match_reasons.append(f"خبرة: {experience_years} سنة")
                
                # 4. Certification (10 points)
                if provider.get('verified', False):
                    score += 10
                    match_reasons.append("شهادة موثقة")
                
                # 5. Availability (10 points)
                if provider.get('available', False):
                    score += 10
                    match_reasons.append("متاح حالياً")
                
                # 6. Services matching (bonus points)
                for tag in normalized_tags:
                    for service in provider_services:
                        if tag in service or service in tag:
                            score += 5
                            match_reasons.append(f"خدمة مطابقة: {tag}")
                            break
                
                if score > 0:
                    scored_providers.append({
                        'provider': provider.to_dict(),
                        'score': score,
                        'match_reasons': match_reasons
                    })
            
            # Sort by score (highest first)
            scored_providers.sort(key=lambda x: x['score'], reverse=True)
            
            # Log top matches
            logger.info(f"🎯 Found {len(scored_providers)} matching providers")
            for i, match in enumerate(scored_providers[:3]):
                logger.info(f"  {i+1}. {match['provider']['name']} - Score: {match['score']:.1f}")
                logger.info(f"     Reasons: {', '.join(match['match_reasons'])}")
            
            return scored_providers[:5]  # Return top 5 matches
            
        except Exception as e:
            logger.error(f"❌ Error in match_providers: {str(e)}")
            return []

    def _is_specialty_match(self, category, specialty):
        """Check if category matches specialty"""
        # Direct match
        if category in specialty or specialty in category:
            return True
        
        # Specific mappings
        specialty_mappings = {
            'أمراض القلب والشرايين': ['قلب', 'قلبية', 'cardio', 'heart'],
            'الأمراض العصبية': ['عصبي', 'neuro', 'brain', 'أعصاب'],
            'أمراض الكلى وغسيل الكلى': ['كلى', 'kidney', 'renal', 'كلوية'],
            'أمراض العظام والحركة': ['عظم', 'ortho', 'bone', 'عظمية'],
            'أمراض الجهاز التنفسي': ['تنفس', 'respiratory', 'lung', 'تنفسية'],
            'أمراض العيون': ['عين', 'eye', 'ophthal', 'عينية'],
            'الأورام والسرطان': ['سرطان', 'cancer', 'oncology', 'أورام'],
            'الحالات الطارئة والإصابات': ['طارئ', 'emergency', 'trauma', 'طوارئ'],
        }
        
        keywords = specialty_mappings.get(category, [])
        return any(keyword in specialty for keyword in keywords)

    def _is_related_specialty(self, category, specialty):
        """Check if specialty is related to category"""
        # General medicine covers many conditions
        if 'داخلي' in specialty:
            return any(keyword in category for keyword in ['قلب', 'عصبي', 'كلى', 'تنفس'])
        
        # Emergency medicine
        if 'طارئ' in category and 'طوارئ' in specialty:
            return True
        
        return False


ai_service = AIService()