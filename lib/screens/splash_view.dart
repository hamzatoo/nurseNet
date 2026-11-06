import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../models/user_model.dart';
import '../services/app_data_service.dart';
import 'user_type_view.dart';
import 'patient_home_screen.dart';
import 'nurse_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  double _opacity = 0.0;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AppDataService _appDataService = AppDataService.instance;

  @override
  void initState() {
    super.initState();

    // بدء تأثير الـ Fade-in بعد 200 ميلي ثانية من فتح التطبيق
    Future.delayed(const Duration(milliseconds: 200), () {
      setState(() {
        _opacity = 1.0;
      });
    });

    // التحقق من حالة المصادقة والتوجيه بعد 2 ثانية
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    await Future.delayed(const Duration(seconds: 2));

    try {
      // التحقق من وجود مستخدم مسجل دخول
      final User? user = _auth.currentUser;

      if (user != null) {
        print('✅ User is logged in: ${user.email}');
        print('🔄 Fetching user data from Firestore...');

        // جلب بيانات المستخدم من Firestore
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          final String role = data['role'] as String? ?? 'patient';

          print('📋 User role: $role');

          // إنشاء كائن AppUser
          final appUser = AppUser(
            id: user.uid,
            name: data['name'] as String? ?? '',
            email: data['email'] as String? ?? user.email ?? '',
            phone: data['phone'] as String? ?? '',
            role: role == 'nurse' ? UserRole.nurse :
                  role == 'admin' ? UserRole.admin : UserRole.patient,
            status: data['status'] == 'active' ? UserStatus.active :
                  data['status'] == 'pending' ? UserStatus.pending : UserStatus.suspended,
            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            location: data['location'] as String?,
            specialty: data['specialty'] as String?,
            experienceYears: data['experienceYears'] as int?,
            medicalCategory: data['medicalCategory'] as String?,
            medicalTags: data['medicalTags'] != null 
                ? List<String>.from(data['medicalTags'] as List) 
                : [],
            medicalDescription: data['medicalDescription'] as String?,
          );

          // تحديث AppDataService
          _appDataService.currentUser = appUser;

          // التوجيه حسب الدور
          if (mounted) {
            Widget targetScreen;
            switch (role) {
              case 'patient':
                targetScreen = const PatientHomeScreen();
                break;
              case 'nurse':
                targetScreen = const NurseDashboardScreen();
                break;
              case 'admin':
                targetScreen = const AdminDashboardScreen();
                break;
              default:
                targetScreen = const UserTypeView();
            }

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => targetScreen),
            );
          }
        } else {
          print('⚠️ User document not found in Firestore');
          _navigateToUserType();
        }
      } else {
        print('ℹ️ No user logged in');
        _navigateToUserType();
      }
    } catch (e) {
      print('❌ Error checking auth: $e');
      _navigateToUserType();
    }
  }

  void _navigateToUserType() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const UserTypeView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // خلفية بيضاء صافية للإقلاع
      body: Center(
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(
            seconds: 2,
          ), // تأثير الأنميشن يستمر لمجال ثانيتين
          curve: Curves.easeIn,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // شعار طبي متحرك بالـ Fade
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded, // أيقونة حماية صحية فخمة
                  size: 100,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'NurseNet',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'صحتك أولويتنا',
                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
