import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Unified notification service for NurseNet.
///
/// Handles:
/// - FCM token registration and synchronization with Firestore
/// - Remote message reception (nurse high-HR alerts, medication reminders)
/// - Local notification display
/// - Navigation to appropriate screens on notification tap
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialize the notification service.
  ///
  /// Call this once at app startup (e.g., in main.dart after Firebase init).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Request notification permissions
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (kDebugMode) {
      print('FCM Permission: ${settings.authorizationStatus}');
    }

    // Initialize local notifications (for Android foreground handling)
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Get FCM token and sync with Firestore
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveFcmToken(token);
      if (kDebugMode) print('FCM Token: $token');
    }

    // Handle token refresh
    _messaging.onTokenRefresh.listen(_saveFcmToken);

    // Handle incoming messages (when app is in foreground)
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle messages when app is opened from background/terminated state
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpened);
  }

  /// Save/update FCM token in Firestore for the current user.
  Future<void> _saveFcmToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) print('FCM token saved for user $uid');
    } catch (e) {
      if (kDebugMode) print('Failed to save FCM token: $e');
    }
  }

  /// Handle incoming FCM message when app is in foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      print('Received foreground message: ${message.notification?.title}');
    }

    // Display local notification
    final notification = message.notification;
    if (notification != null) {
      _showLocalNotification(
        title: notification.title ?? 'NurseNet',
        body: notification.body ?? '',
        payload: message.data['type'] ?? '',
      );
    }
  }

  /// Handle message opened from background/terminated state.
  void _handleMessageOpened(RemoteMessage message) {
    if (kDebugMode) {
      print('Message opened from background: ${message.data}');
    }
    _navigateBasedOnNotificationType(message.data);
  }

  /// Show a local notification (for foreground messages).
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'nursenet_channel',
      'NurseNet Notifications',
      channelDescription: 'Notifications for NurseNet app',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Handle notification tap (local or remote).
  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      // For local notifications, we need to reconstruct the data map
      _navigateBasedOnNotificationType({'type': payload});
    }
  }

  /// Navigate to the appropriate screen based on notification type.
  void _navigateBasedOnNotificationType(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    if (kDebugMode) {
      print('Navigating for notification type: $type');
    }

    // Navigation is handled via a callback that can be set by the app
    // This allows the service to be testable and decoupled from navigator
    _onNotificationTapCallback?.call(type, data);
  }

  /// Callback for notification tap navigation.
  void Function(String? type, Map<String, dynamic> data)? _onNotificationTapCallback;

  /// Set the navigation callback (call from main.dart or router).
  void setOnNotificationTapCallback(
    void Function(String? type, Map<String, dynamic> data) callback,
  ) {
    _onNotificationTapCallback = callback;
  }

  /// Nurse preference: enable/disable high-HR alerts.
  Future<void> setNurseHighHrAlertsEnabled(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'highHrAlertsEnabled': enabled,
      });
    } catch (e) {
      if (kDebugMode) print('Failed to update nurse alert preference: $e');
    }
  }

  /// Get nurse's high-HR alert preference.
  Future<bool> getNurseHighHrAlertsEnabled() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true; // Default enabled

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data()?['highHrAlertsEnabled'] as bool? ?? true;
      }
    } catch (e) {
      if (kDebugMode) print('Failed to fetch nurse alert preference: $e');
    }
    return true;
  }

  /// Patient preference: enable/disable medication reminders.
  Future<void> setPatientMedicationRemindersEnabled(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'medicationRemindersEnabled': enabled,
      });
    } catch (e) {
      if (kDebugMode) print('Failed to update medication reminder preference: $e');
    }
  }

  /// Get patient's medication reminder preference.
  Future<bool> getPatientMedicationRemindersEnabled() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true; // Default enabled

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data()?['medicationRemindersEnabled'] as bool? ?? true;
      }
    } catch (e) {
      if (kDebugMode) print('Failed to fetch medication reminder preference: $e');
    }
    return true;
  }
}
