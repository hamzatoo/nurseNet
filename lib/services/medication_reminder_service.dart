import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication_model.dart';

/// Service for scheduling and managing medication reminders.
///
/// Uses flutter_local_notifications with timezone support to schedule
/// reminders for each medication dose time. Automatically schedules daily
/// reminders for active medications.
class MedicationReminderService {
  MedicationReminderService._();
  static final MedicationReminderService instance = MedicationReminderService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialize the reminder service.
  ///
  /// Call this once at app startup (after notification_service.initialize).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Initialize timezone database
    tz_data.initializeTimeZones();
    final localTimezone = await tz.getTimeZone('Asia/Damascus'); // Default to Syria
    tz.setLocalLocation(localTimezone);

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request permissions for Android 13+
    if (Platform.isAndroid) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }

    if (kDebugMode) {
      print('MedicationReminderService initialized');
    }
  }

  /// Schedule reminders for a medication.
  ///
  /// Schedules a daily notification for each scheduled time in the medication.
  /// If the medication is already scheduled, existing notifications are replaced.
  Future<void> scheduleMedication(Medication medication) async {
    if (!_initialized) {
      await initialize();
    }

    // Check if reminders are enabled for the patient
    final enabled = await NotificationService.instance
        .getPatientMedicationRemindersEnabled();
    if (!enabled) {
      if (kDebugMode) {
        print('Medication reminders disabled for patient; skipping schedule');
      }
      return;
    }

    // Cancel existing notifications for this medication
    await cancelMedicationReminders(medication.id);

    // Schedule new notifications for each time slot
    for (final timeStr in medication.scheduledTimes) {
      final scheduledTime = _parseTime(timeStr);
      if (scheduledTime == null) continue;

      final notificationId = _generateNotificationId(medication.id, timeStr);

      // Schedule daily notification at this time
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        scheduledTime.hour,
        scheduledTime.minute,
      );

      // If the time has already passed today, schedule for tomorrow
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      const androidDetails = AndroidNotificationDetails(
        'medication_reminders_channel',
        'تذكيرات الأدوية',
        channelDescription: 'تذكيرات مواعيد الأدوية من الحقيبة الطبية',
        importance: Importance.high,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.zonedSchedule(
        notificationId,
        'حان موعد دوائك: ${medication.name}',
        '${medication.dosage} - الموعد: $timeStr',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // Repeat daily
        payload: 'medication_reminder|${medication.id}|$timeStr',
      );

      if (kDebugMode) {
        print('Scheduled reminder for ${medication.name} at $timeStr ($scheduledDate)');
      }
    }
  }

  /// Cancel all reminders for a specific medication.
  Future<void> cancelMedicationReminders(String medicationId) async {
    for (final hour in List.generate(24, (i) => i)) {
      for (final minute in [0, 15, 30, 45]) {
        final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        final notificationId = _generateNotificationId(medicationId, timeStr);
        await _notifications.cancel(notificationId);
      }
    }
  }

  /// Reschedule all active medications for the current patient.
  ///
  /// Call this after app restart or when the patient logs in.
  Future<void> rescheduleAllMedications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications')
          .get();

      for (final doc in snapshot.docs) {
        final medication = Medication.fromFirestore(doc);
        // Only schedule active medications (within date range)
        final now = DateTime.now();
        if (now.isBefore(medication.endDate) && now.isAfter(medication.startDate)) {
          await scheduleMedication(medication);
        }
      }

      if (kDebugMode) {
        print('Rescheduled ${snapshot.docs.length} medications');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to reschedule medications: $e');
      }
    }
  }

  /// Cancel all medication reminders (e.g., on logout).
  Future<void> cancelAllReminders() async {
    await _notifications.cancelAll();
  }

  /// Parse time string (HH:mm) to TimeOfDay.
  TimeOfDay? _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Generate a unique notification ID for a medication time slot.
  int _generateNotificationId(String medicationId, String timeStr) {
    // Hash the medication ID and time to create a consistent integer ID
    final hash = '$medicationId|$timeStr'.hashCode;
    return hash.abs();
  }

  /// Handle notification tap (navigate to medication details).
  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.startsWith('medication_reminder|')) {
      final parts = payload.split('|');
      if (parts.length >= 3) {
        final medicationId = parts[1];
        final timeStr = parts[2];
        _onReminderTapCallback?.call(medicationId, timeStr);
      }
    }
  }

  /// Callback for reminder tap navigation.
  void Function(String medicationId, String timeStr)? _onReminderTapCallback;

  /// Set the navigation callback (call from main.dart or router).
  void setOnReminderTapCallback(
    void Function(String medicationId, String timeStr) callback,
  ) {
    _onReminderTapCallback = callback;
  }
}
