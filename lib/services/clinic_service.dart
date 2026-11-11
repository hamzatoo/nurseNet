import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/clinic_model.dart';

/// Loads the bundled Damascus clinics dataset from the app assets.
class ClinicService {
  ClinicService._();

  static const String _assetPath = 'assets/data/damascus_clinics.json';

  static List<Clinic>? _cachedClinics;

  /// Returns all clinics, loading (and caching) the JSON asset on first call.
  static Future<List<Clinic>> getClinics() async {
    if (_cachedClinics != null) return _cachedClinics!;

    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = (decoded['clinics_damascus'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Clinic.fromJson)
        .toList();

    _cachedClinics = list;
    return list;
  }
}
