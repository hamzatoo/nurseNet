import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';

class NurseApprovalWaitingScreen extends StatefulWidget {
  const NurseApprovalWaitingScreen({super.key});

  @override
  State<NurseApprovalWaitingScreen> createState() => _NurseApprovalWaitingScreenState();
}

class _NurseApprovalWaitingScreenState extends State<NurseApprovalWaitingScreen> {
  final _firestoreService = FirestoreService.instance;
  final _auth = FirebaseAuth.instance;
  AppUser? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkApprovalStatus();
  }

  Future<void> _checkApprovalStatus() async {
    final user = _auth.currentUser;
    if (user != null) {
      final userData = await _firestoreService.getUserById(user.uid);
      if (mounted) {
        setState(() {
          _currentUser = userData;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshStatus() async {
    setState(() => _isLoading = true);
    await _checkApprovalStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  // Animated waiting icon
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.pending_actions_rounded,
                      size: 80,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Main message
                  const Text(
                    'بانتظار موافقة المدير',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  
                  // Subtitle
                  Text(
                    'جاري مراجعة طلبك للتسجيل كممرض',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  
                  // Info card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow(
                          Icons.person_rounded,
                          'الاسم',
                          _currentUser?.name ?? 'جاري التحميل...',
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          Icons.email_rounded,
                          'البريد الإلكتروني',
                          _currentUser?.email ?? 'جاري التحميل...',
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          Icons.medical_services_rounded,
                          'التخصص',
                          _currentUser?.specialty ?? 'جاري التحميل...',
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          Icons.access_time_rounded,
                          'الحالة',
                          'قيد المراجعة',
                          isStatus: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // What happens next section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'ماذا يحدث الآن؟',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildStepItem(
                          '1',
                          'سيقوم مدير النظام بمراجعة بياناتك وشهاداتك',
                        ),
                        const SizedBox(height: 8),
                        _buildStepItem(
                          '2',
                          'سيتم إعلامك فوراً عند قبول أو رفض طلبك',
                        ),
                        const SizedBox(height: 8),
                        _buildStepItem(
                          '3',
                          'بعد الموافقة، ستتمكن من استقبال طلبات المرضى',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Refresh button
                  ElevatedButton.icon(
                    onPressed: _refreshStatus,
                    icon: _isLoading 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(_isLoading ? 'جاري التحقق...' : 'تحديث الحالة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Logout button
                  TextButton.icon(
                    onPressed: () async {
                      await _auth.signOut();
                      if (mounted) {
                        Navigator.popUntil(context, (route) => route.isFirst);
                      }
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('تسجيل الخروج'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {bool isStatus = false}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isStatus ? Colors.orange : AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.orange.shade700,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }
}