import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../services/app_data_service.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import 'admin_dashboard_screen.dart';

class AdminLoginView extends StatefulWidget {
  const AdminLoginView({super.key});

  @override
  State<AdminLoginView> createState() => _AdminLoginViewState();
}

class _AdminLoginViewState extends State<AdminLoginView> {
  final _adminIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  final _firestoreService = FirestoreService.instance;
  final _appDataService = AppDataService.instance;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 30.0,
                      right: 30.0,
                      top: 10.0,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 20.0,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 5),
                          const Icon(
                            Icons.admin_panel_settings_rounded,
                            size: 65,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'بوابة مدير النظام',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'سجّل دخولك لإدارة المستخدمين والطلبات',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _adminIdController,
                            validator: (v) => v!.isEmpty
                                ? 'يرجى إدخال المعرف أو البريد'
                                : null,
                            decoration: InputDecoration(
                              labelText: 'معرف المدير / البريد الإلكتروني',
                              prefixIcon: const Icon(
                                Icons.badge_outlined,
                                color: AppColors.primary,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            validator: (v) =>
                                v!.isEmpty ? 'يرجى إدخال كلمة المرور' : null,
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: AppColors.primary,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(
                                  () =>
                                      _isPasswordVisible = !_isPasswordVisible,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : () async {
                                    if (_formKey.currentState!.validate()) {
                                      setState(() => _isLoading = true);

                                      final authenticatedUser =
                                          await _firestoreService
                                              .authenticateUser(
                                                _adminIdController.text.trim(),
                                                _passwordController.text,
                                                UserRole.admin,
                                              );

                                      setState(() => _isLoading = false);

                                      if (authenticatedUser != null) {
                                        _appDataService.currentUser =
                                            authenticatedUser;

                                        if (mounted) {
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const AdminDashboardScreen(),
                                            ),
                                          );
                                        }
                                      } else {
                                        // فشل تسجيل الدخول - التحقق من السبب
                                        String errorMessage =
                                            'بيانات الدخول غير صحيحة';

                                        // التحقق من سبب الفشل
                                        final user = await _firestoreService
                                            .getUserByEmail(
                                              _adminIdController.text.trim(),
                                            );
                                        if (user != null) {
                                          if (user.role != UserRole.admin) {
                                            errorMessage =
                                                'هذا الحساب ليس حساب مدير. يرجى استخدام شاشة تسجيل الدخول المناسبة.';
                                            // تسجيل الخروج من Firebase Auth إذا تم تسجيل الدخول
                                            await FirebaseAuth.instance
                                                .signOut();
                                          } else if (user.status !=
                                              UserStatus.active) {
                                            errorMessage =
                                                'الحساب معلق أو غير نشط';
                                            // تسجيل الخروج من Firebase Auth إذا تم تسجيل الدخول
                                            await FirebaseAuth.instance
                                                .signOut();
                                          }
                                        }

                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(errorMessage),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'تسجيل الدخول',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
