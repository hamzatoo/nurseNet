import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication_model.dart';

class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  // Pick image from camera or gallery
  Future<String?> pickImage({ImageSource source = ImageSource.camera}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image == null) return null;

      // Upload to Firebase Storage
      final ref = _storage
          .ref()
          .child('prescriptions')
          .child(_currentUserId!)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final file = await image.readAsBytes();
      await ref.putData(file);
      final url = await ref.getDownloadURL();

      return url;
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  // Parse prescription using AI/OCR (simulated for now)
  // In production, this would call a Vision-Language Model API
  Future<Map<String, dynamic>> parsePrescription(String imageUrl) async {
    try {
      // Simulate OCR processing delay
      await Future.delayed(const Duration(seconds: 2));

      // TODO: Integrate with actual OCR service (Google Vision API, GPT-4 Vision, etc.)
      // For now, return simulated data structure
      return {
        'medications': [
          {
            'name': 'أموكسيسيلين',
            'dosage': '500 ملغ',
            'type': 'tablet',
            'frequency': 'three_times_daily',
            'instructions': 'بعد الأكل',
            'duration_days': 7,
          },
          {
            'name': 'باراسيتامول',
            'dosage': '1000 ملغ',
            'type': 'tablet',
            'frequency': 'as_needed',
            'instructions': 'عند الشعور بالألم',
            'duration_days': 30,
          },
        ],
        'detected_duration': null, // Will be null if not detected in OCR
        'confidence': 0.95,
      };
    } catch (e) {
      debugPrint('Error parsing prescription: $e');
      throw Exception('Failed to parse prescription');
    }
  }

  // Calculate scheduled times based on frequency
  List<String> calculateScheduledTimes(MedicationFrequency frequency) {
    switch (frequency) {
      case MedicationFrequency.onceDaily:
        return ['08:00'];
      case MedicationFrequency.twiceDaily:
        return ['08:00', '20:00'];
      case MedicationFrequency.threeTimesDaily:
        return ['08:00', '14:00', '20:00'];
      case MedicationFrequency.fourTimesDaily:
        return ['06:00', '12:00', '18:00', '00:00'];
      case MedicationFrequency.asNeeded:
        return [];
      case MedicationFrequency.weekly:
        return ['08:00'];
      case MedicationFrequency.monthly:
        return ['08:00'];
    }
  }

  // Create medication from parsed data
  Medication createMedicationFromParsedData(
    Map<String, dynamic> parsedData,
    int durationDays,
  ) {
    final meds = parsedData['medications'] as List;
    final firstMed = meds.first as Map<String, dynamic>;

    // Manual parsing since we can't access private static methods
    MedicationFrequency frequency;
    switch (firstMed['frequency'] as String?) {
      case 'once_daily':
        frequency = MedicationFrequency.onceDaily;
        break;
      case 'twice_daily':
        frequency = MedicationFrequency.twiceDaily;
        break;
      case 'three_times_daily':
        frequency = MedicationFrequency.threeTimesDaily;
        break;
      case 'four_times_daily':
        frequency = MedicationFrequency.fourTimesDaily;
        break;
      case 'as_needed':
        frequency = MedicationFrequency.asNeeded;
        break;
      case 'weekly':
        frequency = MedicationFrequency.weekly;
        break;
      case 'monthly':
        frequency = MedicationFrequency.monthly;
        break;
      default:
        frequency = MedicationFrequency.onceDaily;
    }

    MedicationType type;
    switch (firstMed['type'] as String?) {
      case 'tablet':
        type = MedicationType.tablet;
        break;
      case 'capsule':
        type = MedicationType.capsule;
        break;
      case 'injection':
        type = MedicationType.injection;
        break;
      case 'syrup':
        type = MedicationType.syrup;
        break;
      case 'drops':
        type = MedicationType.drops;
        break;
      case 'inhaler':
        type = MedicationType.inhaler;
        break;
      case 'cream':
        type = MedicationType.cream;
        break;
      default:
        type = MedicationType.other;
    }

    final scheduledTimes = calculateScheduledTimes(frequency);

    final startDate = DateTime.now();
    final endDate = startDate.add(Duration(days: durationDays));

    return Medication(
      id: '', // Will be assigned by Firestore
      name: firstMed['name'] as String,
      dosage: firstMed['dosage'] as String,
      type: type,
      frequency: frequency,
      instructions: firstMed['instructions'] as String?,
      startDate: startDate,
      endDate: endDate,
      scheduledTimes: scheduledTimes,
      status: MedicationStatus.pending,
      createdAt: DateTime.now(),
      imageUrl: parsedData['imageUrl'] as String?,
      isFromOCR: true,
    );
  }
}
