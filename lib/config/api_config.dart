import 'package:flutter/foundation.dart';

/// إعدادات API للاتصال بالسيرفر
class ApiConfig {
  // منع إنشاء نسخ من هذه الفئة
  ApiConfig._();

  /// عنوان السيرفر السحابي (Render.com)
  ///
  /// للإنتاج:
  /// يستخدم هذا العنوان في كل الأوضاع (debug و release)
  ///
  /// للتطوير المحلي (اختياري):
  /// - المحاكي: 'http://10.0.2.2:8000'
  /// - الجهاز الحقيقي: 'http://192.168.1.110:8000' (IP جهازك)
  static String baseUrl = 'https://nursenet-backend.onrender.com';

  /// منفذ السيرفر
  static const int serverPort = 8000;

  /// مهلة الاتصال بالثواني
  static const int connectionTimeout = 30;

  /// مهلة الاستقبال بالثواني
  static const int receiveTimeout = 30;

  /// تحديث عنوان السيرفر
  static void updateBaseUrl(String url) {
    baseUrl = url;
    debugPrint('🔄 تم تحديث عنوان السيرفر إلى: $baseUrl');
  }

  /// الحصول على عنوان URL كامل للمسار المحدد
  static String getEndpoint(String path) {
    return '$baseUrl$path';
  }

  /// التحقق من العنوان الحالي
  static String getCurrentBaseUrl() {
    return baseUrl;
  }

  /// عنوان IP مقترح للشبكات المنزلية
  /// يجب التحقق من عنوان IP الفعلي للكمبيوتر
  static String get suggestedLocalIp {
    return '192.168.1.100'; // قم بتغيير هذا إلى عنوان IP الفعلي
  }
}
