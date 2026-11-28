import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/splash_view.dart';
import 'theme.dart';
import 'services/notification_service.dart';
import 'services/medication_reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');

    // إعدادات Firestore للعمل بدون اتصال
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    print('✅ Firestore offline persistence enabled');

    // Initialize notification services
    await NotificationService.instance.initialize();
    await MedicationReminderService.instance.initialize();
    print('✅ Notification services initialized');
  } catch (e) {
    print('❌ Firebase initialization failed: $e');
    print('⚠️ Continuing without Firebase for testing...');
  }

  // Set up notification navigation callbacks
  _setupNotificationNavigation();

  runApp(const NurseNetApp());
}

void _setupNotificationNavigation() {
  // Set up FCM notification tap callback
  NotificationService.instance.setOnNotificationTapCallback(
    (type, data) {
      // Navigate based on notification type
      // This will be enhanced with proper navigation in a router-based setup
      if (type == 'high_hr_alert') {
        // Navigate to patient profile/vitals
        final patientId = data['patientId'];
        print('Navigate to patient vitals: $patientId');
      } else if (type == 'medication_reminder') {
        // Navigate to medication pouch
        print('Navigate to medication pouch');
      }
    },
  );

  // Set up medication reminder tap callback
  MedicationReminderService.instance.setOnReminderTapCallback(
    (medicationId, timeStr) {
      // Navigate to medication details
      print('Navigate to medication details: $medicationId at $timeStr');
    },
  );
}

class NurseNetApp extends StatelessWidget {
  const NurseNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NurseNet',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', ''), Locale('en', '')],
      theme: ThemeData(
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Segoe UI',
      ),
      home: const SplashView(),
    );
  }
}
