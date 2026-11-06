import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/api_config.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  /// الحصول على عنوان السيرفر الحالي من ApiConfig
  static String get _baseUrl => ApiConfig.baseUrl;

  /// تعيين عنوان السيرفر ديناميكياً
  /// استخدم هذه الدالة لتغيير العنوان في وقت التشغيل
  /// مثال: ApiService.instance.setBaseUrl('http://192.168.1.5:8000');
  static void setBaseUrl(String url) {
    ApiConfig.updateBaseUrl(url);
  }

  /// تنظيف البيانات لجعلها قابلة للترميز إلى JSON
  /// يحول كائنات Timestamp إلى سلاسل نصية ISO8601
  static Map<String, dynamic> _sanitizeForJson(dynamic data) {
    if (data == null) {
      return {};
    }

    if (data is Map) {
      final sanitized = <String, dynamic>{};
      data.forEach((key, value) {
        sanitized[key.toString()] = _sanitizeValue(value);
      });
      return sanitized;
    }

    return {};
  }

  /// تنظيف قيمة واحدة للترميز إلى JSON
  static dynamic _sanitizeValue(dynamic value) {
    if (value == null) {
      return null;
    }

    // تحويل Timestamp إلى سلسلة نصية ISO8601
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }

    // التعامل مع DateTime
    if (value is DateTime) {
      return value.toIso8601String();
    }

    // التعامل مع Maps
    if (value is Map) {
      return _sanitizeForJson(value);
    }

    // التعامل مع Lists
    if (value is List) {
      return value.map((item) => _sanitizeValue(item)).toList();
    }

    // إرجاع القيمة كما هي للأنواع الأساسية
    return value;
  }

  /// Send prediction request with 37 features (7 numerical + 30 text features)
  Future<Map<String, dynamic>> sendPrediction({
    required List<double> features,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/predict/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'features': features,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to send prediction: $e');
    }
  }

  /// Send prediction request with 37 features and patient data
  Future<Map<String, dynamic>> sendPredictionWithPatientData({
    required List<double> features,
    required Map<String, dynamic> patientData,
  }) async {
    try {
      // تنظيف بيانات المريض من كائنات Timestamp وغيرها
      final sanitizedPatientData = _sanitizeForJson(patientData);
      
      final response = await http.post(
        Uri.parse('$_baseUrl/predict/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'features': features,
          'patient_data': sanitizedPatientData,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to send prediction with patient data: $e');
    }
  }

  /// Get Firebase status
  Future<Map<String, dynamic>> getFirebaseStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/firebase/status'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get Firebase status: $e');
    }
  }

  /// Add new provider to backend dataset
  Future<Map<String, dynamic>> addProvider({
    required String name,
    required String specialty,
    required String location,
    required int experienceYears,
    required bool verified,
    required bool available,
    required String services,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/predict/providers/add'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'specialty': specialty,
          'location': location,
          'experience_years': experienceYears,
          'verified': verified,
          'available': available,
          'services': services,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to add provider: $e');
    }
  }
}