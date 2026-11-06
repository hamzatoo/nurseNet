import 'package:flutter/material.dart';
import '../models/medication_model.dart';

// Temporarily disabled due to build issues
// This is a stub implementation that does nothing
// Will be re-enabled when flutter_local_notifications is restored

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('⚠️ Notification service disabled (build issues)');
  }

  Future<void> scheduleMedicationNotification(Medication medication) async {
    debugPrint('⚠️ Notification scheduling disabled');
  }

  Future<void> cancelMedicationNotification(String medicationId) async {
    debugPrint('⚠️ Notification cancellation disabled');
  }

  Future<void> cancelAllNotifications() async {
    debugPrint('⚠️ Notification cancellation disabled');
  }

  Future<void> showTestNotification() async {
    debugPrint('⚠️ Test notification disabled');
  }
}
