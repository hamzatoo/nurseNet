import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../models/medication_model.dart';

/// Error raised by the OCR pipeline that can be shown to the user as-is.
class OcrException implements Exception {
  const OcrException(this.message, {this.suggestion});

  final String message;
  final String? suggestion;

  @override
  String toString() => suggestion == null ? message : '$message\n$suggestion';
}

class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  final ImagePicker _imagePicker = ImagePicker();

  static const Duration _uploadTimeout = Duration(seconds: 90);

  /// Picks a prescription photo and returns the local [XFile].
  /// Returns null only when the user cancels the picker.
  /// Throws [OcrException] on permission or capture failures.
  Future<XFile?> pickImage({ImageSource source = ImageSource.camera}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      return image;
    } catch (e) {
      debugPrint('OCR pickImage error: $e');
      throw const OcrException(
        'تعذّر التقاط الصورة.',
        suggestion: 'تأكد من السماح للتطبيق باستخدام الكاميرا ثم أعد المحاولة.',
      );
    }
  }

  /// Sends the prescription image to the FastAPI backend
  /// (`POST /api/ocr-prescription`) and returns the parsed payload:
  /// `{ medications: [...], detected_duration: int?, confidence: double }`.
  Future<Map<String, dynamic>> parsePrescription(XFile image) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/ocr-prescription');
    http.StreamedResponse response;

    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          // image_picker cache files may lack a known extension, which makes
          // http send application/octet-stream - force the real MIME type.
          await http.MultipartFile.fromPath(
            'image',
            image.path,
            filename: 'prescription.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      response = await request.send().timeout(_uploadTimeout);
    } on TimeoutException {
      throw const OcrException(
        'استغرق تحليل الوصفة وقتاً أطول من المتوقع.',
        suggestion: 'تأكد من قوة الاتصال ثم أعد المحاولة.',
      );
    } on SocketException {
      throw const OcrException(
        'تعذّر الاتصال بخادم تحليل الوصفات.',
        suggestion: 'تحقق من اتصالك بالإنترنت ثم أعد المحاولة.',
      );
    } catch (e) {
      debugPrint('OCR upload failed: $e');
      throw const OcrException(
        'فشل إرسال الصورة إلى الخادم.',
        suggestion: 'أعد المحاولة بعد قليل.',
      );
    }

    final body = await response.stream.bytesToString();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw const OcrException(
        'استجابة الخادم غير مفهومة.',
        suggestion: 'تأكد من أن خدمة OCR تعمل على السيرفر.',
      );
    }

    if (response.statusCode != 200 || payload['status'] != 'success') {
      final detail = payload['detail'] as String?;
      final suggestion = payload['suggestion'] as String?;
      throw OcrException(
        detail ?? 'تعذّر قراءة الوصفة الطبية.',
        suggestion: suggestion,
      );
    }

    final medications = payload['medications'];
    if (medications is! List || medications.isEmpty) {
      throw const OcrException(
        'لم يتم العثور على أدوية في الوصفة.',
        suggestion: 'تأكد من وضوح الصورة واحتواءها على نص مقروء، أو أضف الدواء يدوياً.',
      );
    }

    // Normalise keys the UI already understands.
    return {
      'medications': medications,
      'detected_duration': payload['detected_duration'],
      'duration_days': payload['detected_duration'],
      'confidence': payload['confidence'],
      'imageUrl': null,
    };
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers (shared with the manual-entry flow)
  // ---------------------------------------------------------------------------

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

  /// Builds a [Medication] from one parsed medication map returned by the API.
  Medication createMedicationFromParsedData(
    Map<String, dynamic> medData, {
    required int durationDays,
    String? imageUrl,
  }) {
    final frequency =
        Medication.parseMedicationFrequency(medData['frequency'] as String?) ==
                MedicationFrequency.onceDaily &&
            medData['frequency'] != 'once_daily'
        ? _frequencyFromTimes(medData['scheduled_times'])
        : Medication.parseMedicationFrequency(medData['frequency'] as String?);

    final scheduledTimes =
        (medData['scheduled_times'] as List?)
            ?.whereType<String>()
            .toList() ??
        calculateScheduledTimes(frequency);

    final startDate = DateTime.now();
    final endDate = startDate.add(Duration(days: durationDays));

    return Medication(
      id: '',
      name: (medData['name'] as String?)?.trim().isNotEmpty == true
          ? medData['name'] as String
          : 'دواء غير معروف',
      dosage: (medData['dosage'] as String?)?.trim().isNotEmpty == true
          ? medData['dosage'] as String
          : 'حسب الوصفة',
      type: Medication.parseMedicationType(medData['type'] as String?),
      frequency: frequency,
      instructions: medData['instructions'] as String?,
      startDate: startDate,
      endDate: endDate,
      scheduledTimes: scheduledTimes,
      status: MedicationStatus.pending,
      createdAt: DateTime.now(),
      imageUrl: imageUrl,
      isFromOCR: true,
    );
  }

  /// Derives a frequency enum from the server-provided time slots when the
  /// frequency string is missing or unrecognised.
  MedicationFrequency _frequencyFromTimes(dynamic times) {
    final count = times is List ? times.length : 0;
    return switch (count) {
      0 => MedicationFrequency.asNeeded,
      1 => MedicationFrequency.onceDaily,
      2 => MedicationFrequency.twiceDaily,
      3 => MedicationFrequency.threeTimesDaily,
      _ => MedicationFrequency.fourTimesDaily,
    };
  }
}
