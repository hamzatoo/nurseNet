import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/heart_rate_reading.dart';

/// A measurement failure that can be shown to the patient as-is.
class HeartRateException implements Exception {
  const HeartRateException(this.code, this.message, {this.suggestion});

  final String code;
  final String message;
  final String? suggestion;

  @override
  String toString() => 'HeartRateException($code): $message';
}

class HeartRateService {
  HeartRateService._();
  static final HeartRateService instance = HeartRateService._();

  static const Duration _uploadTimeout = Duration(seconds: 120);

  /// Uploads the recorded clip and returns the analysed reading.
  Future<HeartRateReading> measure(File video) async {
    if (!await video.exists() || await video.length() < 1024) {
      throw const HeartRateException(
        'empty_file',
        'لم يتم تسجيل فيديو صالح.',
        suggestion: 'أعد المحاولة وتأكد من السماح للتطبيق باستخدام الكاميرا.',
      );
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/calculate-heart-rate');
    http.StreamedResponse response;

    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          await http.MultipartFile.fromPath(
            'video',
            video.path,
            filename: 'face_capture.mp4',
          ),
        );
      response = await request.send().timeout(_uploadTimeout);
    } on TimeoutException {
      throw const HeartRateException(
        'timeout',
        'استغرق التحليل وقتاً أطول من المتوقع.',
        suggestion: 'تأكد من قوة الاتصال بالإنترنت ثم أعد المحاولة.',
      );
    } on SocketException {
      throw const HeartRateException(
        'network_error',
        'تعذّر الاتصال بخادم تحليل النبض.',
        suggestion:
            'تحقق من أن الهاتف والسيرفر على نفس الشبكة، وأن عنوان السيرفر صحيح.',
      );
    } catch (error) {
      debugPrint('Heart rate upload failed: $error');
      throw const HeartRateException(
        'upload_failed',
        'فشل إرسال الفيديو إلى الخادم.',
        suggestion: 'أعد المحاولة بعد قليل.',
      );
    }

    final body = await response.stream.bytesToString();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw const HeartRateException(
        'invalid_response',
        'استجابة الخادم غير مفهومة.',
        suggestion: 'تأكد من أن خدمة تحليل النبض تعمل على السيرفر.',
      );
    }

    if (response.statusCode != 200 || payload['status'] != 'success') {
      throw HeartRateException(
        payload['code'] as String? ?? 'server_error',
        payload['detail'] as String? ?? 'تعذّر حساب النبض من الفيديو.',
        suggestion: payload['suggestion'] as String?,
      );
    }

    return HeartRateReading.fromApi(payload);
  }

  /// Stores a reading inside the signed-in patient's own profile document tree,
  /// under `users/{uid}/vitals`.
  Future<HeartRateReading> saveReading(HeartRateReading reading) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const HeartRateException(
        'unauthenticated',
        'يجب تسجيل الدخول لحفظ القياس في ملفك الطبي.',
      );
    }

    final saved = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('vitals')
        .add(reading.toFirestore());

    return reading.copyWith(id: saved.id);
  }
}
