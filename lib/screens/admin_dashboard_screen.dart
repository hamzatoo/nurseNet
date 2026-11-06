import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/app_data_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _firestoreService = FirestoreService.instance;
  final _appDataService = AppDataService.instance;
  int _selectedTab = 0;
  AppUser? _currentUser;

  // Stats data
  Map<String, int> _stats = {};
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadStats();
  }

  Future<void> _loadCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _currentUser = AppUser(
              id: doc.id,
              name: data['name'] as String? ?? '',
              email: data['email'] as String? ?? '',
              phone: data['phone'] as String? ?? '',
              role: data['role'] == 'nurse' ? UserRole.nurse : 
                    data['role'] == 'admin' ? UserRole.admin : UserRole.patient,
              status: data['status'] == 'active' ? UserStatus.active :
                    data['status'] == 'pending' ? UserStatus.pending : UserStatus.suspended,
              createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              location: data['location'] as String?,
              specialty: data['specialty'] as String?,
              experienceYears: data['experienceYears'] as int?,
              isResidentNurse: data['isResidentNurse'] as bool? ?? false,
              certificateVerified: data['certificateVerified'] as bool? ?? false,
            );
          });
        }
      } catch (e) {
        debugPrint('Error loading current user: $e');
      }
    }
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    
    setState(() => _isLoadingStats = true);
    try {
      // Load requests
      final requestsSnapshot = await _firestore.collection('care_requests').get();
      final totalRequests = requestsSnapshot.docs.length;
      final completedRequests = requestsSnapshot.docs
          .where((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            return data != null && data['status'] == 'completed';
          })
          .length;
      final pendingRequests = requestsSnapshot.docs
          .where((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            return data != null && data['status'] == 'pending';
          })
          .length;

      // Load total nurses (all nurses regardless of status)
      final allNursesSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'nurse')
          .get();
      final totalNurses = allNursesSnapshot.docs.length;

      // Load active nurses
      final activeNurseSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'nurse')
          .where('status', isEqualTo: 'active')
          .get();
      final activeNurses = activeNurseSnapshot.docs.length;

      // Load pending nurses
      final pendingNurseSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'nurse')
          .where('status', isEqualTo: 'pending')
          .get();
      final pendingNurses = pendingNurseSnapshot.docs.length;

      // Load patients
      final patientSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'patient')
          .get();
      final patientCount = patientSnapshot.docs.length;

      final completionRate = totalRequests > 0
          ? ((completedRequests / totalRequests) * 100).toStringAsFixed(1)
          : '0.0';

      if (mounted) {
        setState(() {
          _stats = {
            'totalRequests': totalRequests,
            'completedRequests': completedRequests,
            'pendingRequests': pendingRequests,
            'totalNurses': totalNurses,
            'activeNurses': activeNurses,
            'pendingNurses': pendingNurses,
            'patientCount': patientCount,
            'completionRate': double.parse(completionRate).toInt(),
          };
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من أنك تريد تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تسجيل الخروج', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _auth.signOut();
        _appDataService.currentUser = null;
        
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في تسجيل الخروج: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadCurrentUser();
    await _loadStats();
    if (mounted) {
      setState(() {});
    }
  }

  void _switchTab(int index) {
    if (mounted) {
      setState(() {
        _selectedTab = index;
      });
    }
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
            child: Column(
              children: [
                _buildCompactHeader(),
                _buildStatsGrid(),
                _buildPendingNursesSection(),
                _buildTabBar(),
                _buildTabContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const Text(
                    'لوحة تحكم مدير النظام',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'مرحباً ${_currentUser?.name ?? "مدير"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _refreshData,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                tooltip: 'تحديث',
                padding: const EdgeInsets.all(8),
              ),
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                tooltip: 'تسجيل الخروج',
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    if (_isLoadingStats) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        children: [
          _interactiveStatCard(
            'إجمالي الطلبات',
            '${_stats['totalRequests'] ?? 0}',
            Icons.inbox_rounded,
            AppColors.primary,
            () => _switchTab(2),
          ),
          _interactiveStatCard(
            'الممرضون النشطون',
            '${_stats['activeNurses'] ?? 0}',
            Icons.people_rounded,
            AppColors.accent,
            () => _switchTab(1),
          ),
          _interactiveStatCard(
            'المرضى المسجلون',
            '${_stats['patientCount'] ?? 0}',
            Icons.personal_injury_rounded,
            Colors.teal,
            () => _switchTab(1),
          ),
          _interactiveStatCard(
            'نسبة الإنجاز',
            '${_stats['completionRate'] ?? 0}%',
            Icons.trending_up_rounded,
            Colors.green,
            () => _switchTab(2),
          ),
        ],
      ),
    );
  }

  Widget _interactiveStatCard(String label, String value, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingNursesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const Text(
                    'الممرضون بانتظار التوثيق',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${_stats['pendingNurses'] ?? 0}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<QuerySnapshot>(
            future: _firestore
                .collection('users')
                .where('role', isEqualTo: 'nurse')
                .where('verificationStatus', isEqualTo: 'pending')
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('حدث خطأ في تحميل البيانات', style: TextStyle(color: Colors.grey[600])),
                  ),
                );
              }

              final pendingNurses = snapshot.data?.docs ?? [];

              if (pendingNurses.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.verified_rounded, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'لا توجد طلبات توثيق معلقة',
                            style: TextStyle(color: Colors.grey[500], fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: pendingNurses.take(3).map((doc) => _buildNurseApprovalCard(doc)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNurseApprovalCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    final name = data != null && data.containsKey('name') ? data['name'] as String? : 'غير معروف';
    final specialty = data != null && data.containsKey('specialty') ? data['specialty'] as String? : '';
    final experienceYears = data != null && data.containsKey('experienceYears') ? data['experienceYears'] as int? : 0;
    final isResidentNurse = data != null && data.containsKey('isResidentNurse') ? data['isResidentNurse'] as bool? : false;
    final email = data != null && data.containsKey('email') ? data['email'] as String? : '';
    final phone = data != null && data.containsKey('phone') ? data['phone'] as String? : '';
    final location = data != null && data.containsKey('location') ? data['location'] as String? : '';
    final licenseNumber = data != null && data.containsKey('licenseNumber') ? data['licenseNumber'] as String? : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.orange.withValues(alpha: 0.1),
                child: const Icon(Icons.medical_services_rounded, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(name ?? 'غير معروف', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(specialty ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('$experienceYears سنوات', AppColors.accent),
              const SizedBox(width: 8),
              if (isResidentNurse == true) _chip('ممرض مقيم', AppColors.primary),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.email_outlined, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(email ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.phone_outlined, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(phone ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ),
              ),
            ],
          ),
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(location, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ),
                ),
              ],
            ),
          ],
          if (licenseNumber != null && licenseNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.badge_rounded, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'رقم الترخيص: $licenseNumber',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveNurse(doc),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('قبول', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rejectNurse(doc),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('رفض', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approveNurse(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      final nurseId = doc.id;
      final name = data != null && data.containsKey('name') ? data['name'] as String? : 'الممرض';
      
      debugPrint('=== بدء عملية الموافقة من لوحة التحكم ===');
      debugPrint('معرف الممرض: $nurseId');
      debugPrint('اسم الممرض: $name');
      debugPrint('البيانات الكاملة: $data');
      
      // استخدام FirestoreService للموافقة على الممرض
      final success = await _firestoreService.approveNurse(nurseId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Text('تم توثيق حساب $name بنجاح'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          await _loadStats(); // Refresh stats
          // إعادة تحميل البيانات لتحديث القوائم
          if (_selectedTab == 1) {
            // إذا كنا في تبويب التوثيق، نعيد تحميل قائمة الانتظار
            setState(() {});
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('فشل الموافقة على الممرض. يرجى التحقق من سجلات التطبيق للتفاصيل.'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } on FirebaseException catch (e) {
      debugPrint('=== خطأ Firebase في الموافقة من لوحة التحكم ===');
      debugPrint('الكود: ${e.code}');
      debugPrint('الرسالة: ${e.message}');
      debugPrint('التفاصيل الكاملة: ${e.toString()}');
      
      String errorMessage = 'فشل الموافقة على الممرض';
      
      switch (e.code) {
        case 'permission-denied':
          errorMessage = 'ليس لديك صلاحية للموافقة على الممرضين. يرجى التحقق من حسابك.';
          break;
        case 'not-found':
          errorMessage = 'لم يتم العثور على بيانات الممرض. قد يكون تم حذف الحساب.';
          break;
        case 'unavailable':
          errorMessage = 'الخدمة غير متاحة حالياً. يرجى المحاولة لاحقاً.';
          break;
        default:
          errorMessage = 'حدث خطأ أثناء الموافقة: ${e.message ?? "خطأ غير معروف"}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(errorMessage),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'إغلاق',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('=== خطأ عام في الموافقة من لوحة التحكم ===');
      debugPrint('التفاصيل: ${e.toString()}');
      debugPrint('نوع الخطأ: ${e.runtimeType}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('حدث خطأ غير متوقع: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _rejectNurse(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      final nurseId = doc.id;
      final name = data != null && data.containsKey('name') ? data['name'] as String? : 'الممرض';
      
      // استخدام FirestoreService لرفض الممرض
      final success = await _firestoreService.rejectNurse(nurseId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم رفض طلب $name'), backgroundColor: Colors.orange),
          );
          await _loadStats(); // Refresh stats
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل رفض الممرض'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = ['نظرة عامة', 'المستخدمون', 'الطلبات', 'توثيق الممرضين'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = _selectedTab == i;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: () => _switchTab(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: selected
                      ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 8)]
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.textDark,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabContent() {
    // Use a fixed height container for tab content to prevent overflow
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: IndexedStack(
        index: _selectedTab,
        children: [
          _OverviewTab(stats: _stats),
          const _UsersTab(),
          const _RequestsTab(),
          const _NurseVerificationTab(),
        ],
      ),
    );
  }
}

// Separate tab widgets to prevent setState issues
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.stats});

  final Map<String, int> stats;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionTitle('إحصائيات سريعة'),
          const SizedBox(height: 12),
          _overviewCard(
            'الممرضون المسجلون',
            '${stats['totalNurses'] ?? 0}',
            Icons.medical_services_rounded,
            Colors.teal,
          ),
          const SizedBox(height: 12),
          _overviewCard(
            'الممرضون النشطون',
            '${stats['activeNurses'] ?? 0}',
            Icons.people_rounded,
            AppColors.accent,
          ),
          const SizedBox(height: 12),
          _overviewCard(
            'ممرضون بانتظار التوثيق',
            '${stats['pendingNurses'] ?? 0}',
            Icons.verified_user_outlined,
            Colors.deepPurple,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark),
      ),
    );
  }

  Widget _overviewCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title, 
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _firestore = FirebaseFirestore.instance;
  List<QueryDocumentSnapshot> _users = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      if (mounted) {
        setState(() {
          _users = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('خطأ: $_errorMessage', style: TextStyle(color: Colors.grey[600])),
            ),
          ],
        ),
      );
    }

    if (_users.isEmpty) {
      return _emptyState('لا يوجد مستخدمين', Icons.people_outline);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) => _buildFirestoreUserCard(_users[index]),
    );
  }

  Widget _buildFirestoreUserCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    final role = data != null && data.containsKey('role') ? data['role'] as String? : 'patient';
    final status = data != null && data.containsKey('status') ? data['status'] as String? : 'pending';
    final name = data != null && data.containsKey('name') ? data['name'] as String? : 'غير معروف';
    final email = data != null && data.containsKey('email') ? data['email'] as String? : '';
    final location = data != null && data.containsKey('location') ? data['location'] as String? : null;
    final specialty = data != null && data.containsKey('specialty') ? data['specialty'] as String? : null;

    final roleLabel = role == 'patient' ? 'مريض' : 'ممرض';
    final statusColor = status == 'active'
        ? Colors.green
        : status == 'pending'
            ? Colors.orange
            : Colors.red;
    final statusLabel = status == 'active'
        ? 'نشط'
        : status == 'pending'
            ? 'قيد المراجعة'
            : 'موقوف';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Icon(
                  role == 'patient'
                      ? Icons.person_rounded
                      : Icons.medical_services_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(name ?? 'غير معروف', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(email ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(roleLabel, AppColors.accent),
              if (location != null) ...[
                const SizedBox(width: 8),
                _chip(location, Colors.grey),
              ],
              if (specialty != null && role == 'nurse') ...[
                const SizedBox(width: 8),
                _chip(specialty, AppColors.primary),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(message, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _RequestsTab extends StatefulWidget {
  const _RequestsTab();

  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  final _firestore = FirebaseFirestore.instance;
  List<QueryDocumentSnapshot> _requests = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _searchQuery = '';
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final snapshot = await _firestore.collection('care_requests').get();
      if (mounted) {
        setState(() {
          _requests = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<QueryDocumentSnapshot> _getFilteredRequests() {
    var filtered = _requests;
    
    if (_statusFilter != 'all') {
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return data != null && data['status'] == _statusFilter;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;
        final patientName = (data['patientName'] ?? '').toString().toLowerCase();
        final nurseName = (data['nurseName'] ?? '').toString().toLowerCase();
        final location = (data['location'] ?? '').toString().toLowerCase();
        return patientName.contains(query) ||
            nurseName.contains(query) ||
            location.contains(query);
      }).toList();
    }

    filtered.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>?;
      final bData = b.data() as Map<String, dynamic>?;
      final aTimestamp = aData != null && aData.containsKey('timestamp') ? aData['timestamp'] as Timestamp? : null;
      final bTimestamp = bData != null && bData.containsKey('timestamp') ? bData['timestamp'] as Timestamp? : null;
      if (aTimestamp == null || bTimestamp == null) return 0;
      return bTimestamp.compareTo(aTimestamp);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('خطأ: $_errorMessage', style: TextStyle(color: Colors.grey[600])),
            ),
          ],
        ),
      );
    }

    final filteredRequests = _getFilteredRequests();

    return Column(
      children: [
        _buildSearchAndFilter(),
        Expanded(
          child: filteredRequests.isEmpty
              ? _emptyState('لا توجد طلبات', Icons.inbox_rounded)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredRequests.length,
                  itemBuilder: (context, index) => _buildFirestoreRequestCard(filteredRequests[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: TextField(
              onChanged: (value) {
                if (mounted) {
                  setState(() => _searchQuery = value);
                }
              },
              decoration: InputDecoration(
                hintText: 'بحث بالاسم، الممرض، أو المنطقة...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                        onPressed: () {
                          if (mounted) {
                            setState(() => _searchQuery = '');
                          }
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('الكل', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('قيد الانتظار', 'pending'),
                const SizedBox(width: 8),
                _buildFilterChip('مقبول', 'accepted'),
                const SizedBox(width: 8),
                _buildFilterChip('قيد التنفيذ', 'in_progress'),
                const SizedBox(width: 8),
                _buildFilterChip('مكتمل', 'completed'),
                const SizedBox(width: 8),
                _buildFilterChip('ملغي', 'cancelled'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return FilterChip(
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (mounted) {
          setState(() => _statusFilter = value);
        }
      },
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : AppColors.textDark,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? AppColors.primary : Colors.grey[300]!,
      ),
    );
  }

  Widget _buildFirestoreRequestCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    final status = data != null && data.containsKey('status') ? data['status'] as String? : 'pending';
    final statusInfo = _requestStatusInfoFromString(status ?? 'pending');
    final patientName = data != null && data.containsKey('patientName') ? data['patientName'] as String? : 'غير معروف';
    final description = data != null && data.containsKey('description') ? data['description'] as String? : '';
    final location = data != null && data.containsKey('location') ? data['location'] as String? : '';
    final nurseName = data != null && data.containsKey('nurseName') ? data['nurseName'] as String? : null;
    final needsResidentNurse = data != null && data.containsKey('needsResidentNurse') ? data['needsResidentNurse'] as bool? : false;
    final timestamp = data != null && data.containsKey('timestamp') ? data['timestamp'] as Timestamp? : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    patientName ?? 'غير معروف',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusInfo.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    statusInfo.label,
                    style: TextStyle(color: statusInfo.color, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              description ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(location ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ),
              ),
              if (needsResidentNurse == true)
                _chip('ممرض مقيم', AppColors.primary),
              if (timestamp != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatTimestamp(timestamp),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ),
            ],
          ),
          if (nurseName != null && nurseName.isNotEmpty) ...[
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'الممرض: $nurseName',
                style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showRequestDetails(doc),
                  icon: const Icon(Icons.visibility_rounded, size: 16),
                  label: const Text('التفاصيل', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (value) => _handleRequestAction(doc, value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'pending', child: Text('قيد الانتظار')),
                    const PopupMenuItem(value: 'accepted', child: Text('مقبول')),
                    const PopupMenuItem(value: 'in_progress', child: Text('قيد التنفيذ')),
                    const PopupMenuItem(value: 'completed', child: Text('مكتمل')),
                    const PopupMenuItem(value: 'cancelled', child: Text('ملغي', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) return 'الآن';
    if (difference.inMinutes < 60) return 'منذ ${difference.inMinutes} دقيقة';
    if (difference.inHours < 24) return 'منذ ${difference.inHours} ساعة';
    if (difference.inDays < 7) return 'منذ ${difference.inDays} يوم';

    return '${date.day}/${date.month}/${date.year}';
  }

  ({String label, Color color}) _requestStatusInfoFromString(String status) {
    switch (status) {
      case 'pending':
        return (label: 'قيد الانتظار', color: Colors.orange);
      case 'accepted':
        return (label: 'مقبول', color: Colors.green);
      case 'rejected':
        return (label: 'مرفوض', color: Colors.red);
      case 'matched':
        return (label: 'تمت المطابقة', color: AppColors.accent);
      case 'in_progress':
        return (label: 'قيد التنفيذ', color: AppColors.primary);
      case 'completed':
        return (label: 'مكتمل', color: Colors.green);
      case 'cancelled':
        return (label: 'ملغي', color: Colors.red);
      default:
        return (label: status, color: Colors.grey);
    }
  }

  void _showRequestDetails(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تفاصيل الطلب'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('اسم المريض', data != null && data.containsKey('patientName') ? data['patientName'] ?? '-' : '-'),
                _detailRow('الوصف', data != null && data.containsKey('description') ? data['description'] ?? '-' : '-'),
                _detailRow('الموقع', data != null && data.containsKey('location') ? data['location'] ?? '-' : '-'),
                _detailRow('الممرض الم Assigned', data != null && data.containsKey('nurseName') ? data['nurseName'] ?? 'غير محدد' : 'غير محدد'),
                _detailRow('الحالة', data != null && data.containsKey('status') ? data['status'] ?? '-' : '-'),
                _detailRow('ممرض مقيم', data != null && data.containsKey('needsResidentNurse') && data['needsResidentNurse'] == true ? 'نعم' : 'لا'),
                if (data != null && data.containsKey('timestamp') && data['timestamp'] != null)
                  _detailRow('التاريخ', _formatTimestamp(data['timestamp'] as Timestamp)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRequestAction(QueryDocumentSnapshot doc, String action) async {
    try {
      if (action == 'cancelled') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد الإلغاء'),
            content: const Text('هل أنت متأكد من إلغاء هذا الطلب؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('لا'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('نعم، إلغاء'),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          await doc.reference.delete();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم حذف الطلب بنجاح'), backgroundColor: Colors.green),
            );
            await _loadRequests();
          }
        }
      } else {
        await doc.reference.update({'status': action});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم تحديث الحالة إلى $action'), backgroundColor: Colors.green),
          );
          await _loadRequests();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(message, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _NurseVerificationTab extends StatefulWidget {
  const _NurseVerificationTab();

  @override
  State<_NurseVerificationTab> createState() => _NurseVerificationTabState();
}

class _NurseVerificationTabState extends State<_NurseVerificationTab> {
  final _firestore = FirebaseFirestore.instance;
  final _firestoreService = FirestoreService.instance;
  List<QueryDocumentSnapshot> _pendingNurses = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadPendingNurses();
  }

  Future<void> _loadPendingNurses() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'nurse')
          .where('verificationStatus', isEqualTo: 'pending')
          .get();
      if (mounted) {
        setState(() {
          _pendingNurses = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('خطأ: $_errorMessage', style: TextStyle(color: Colors.grey[600])),
            ),
          ],
        ),
      );
    }

    if (_pendingNurses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('لا توجد طلبات توثيق معلقة', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingNurses.length,
      itemBuilder: (context, index) {
        final doc = _pendingNurses[index];
        final data = doc.data() as Map<String, dynamic>?;
        final name = data != null && data.containsKey('name') ? data['name'] as String? : 'غير معروف';
        final specialty = data != null && data.containsKey('specialty') ? data['specialty'] as String? : '';
        final experienceYears = data != null && data.containsKey('experienceYears') ? data['experienceYears'] as int? : 0;
        final isResidentNurse = data != null && data.containsKey('isResidentNurse') ? data['isResidentNurse'] as bool? : false;
        final email = data != null && data.containsKey('email') ? data['email'] as String? : '';
        final phone = data != null && data.containsKey('phone') ? data['phone'] as String? : '';
        final location = data != null && data.containsKey('location') ? data['location'] as String? : '';
        final licenseNumber = data != null && data.containsKey('licenseNumber') ? data['licenseNumber'] as String? : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    child: const Icon(Icons.medical_services_rounded, color: Colors.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(name ?? 'غير معروف', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(specialty ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _chip('$experienceYears سنوات', AppColors.accent),
                  const SizedBox(width: 8),
                  if (isResidentNurse == true) _chip('ممرض مقيم', AppColors.primary),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.email_outlined, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(email ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(phone ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ),
                  ),
                ],
              ),
              if (location != null && location.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(location, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      ),
                    ),
                  ],
                ),
              ],
              if (licenseNumber != null && licenseNumber.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.badge_rounded, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'رقم الترخيص: $licenseNumber',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveNurse(doc),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('قبول وتوثيق', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectNurse(doc),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('رفض', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _approveNurse(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      final nurseId = doc.id;
      final name = data != null && data.containsKey('name') ? data['name'] as String? : 'الممرض';
      
      debugPrint('=== بدء عملية الموافقة من قائمة الانتظار ===');
      debugPrint('معرف الممرض: $nurseId');
      debugPrint('اسم الممرض: $name');
      debugPrint('البيانات الكاملة: $data');

      // استخدام FirestoreService للموافقة على الممرض
      final success = await _firestoreService.approveNurse(nurseId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Text('تم توثيق حساب $name بنجاح'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          await _loadPendingNurses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('فشل الموافقة على الممرض. يرجى التحقق من سجلات التطبيق للتفاصيل.'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } on FirebaseException catch (e) {
      debugPrint('=== خطأ Firebase في الموافقة من قائمة الانتظار ===');
      debugPrint('الكود: ${e.code}');
      debugPrint('الرسالة: ${e.message}');
      debugPrint('التفاصيل الكاملة: ${e.toString()}');
      
      String errorMessage = 'فشل الموافقة على الممرض';
      
      switch (e.code) {
        case 'permission-denied':
          errorMessage = 'ليس لديك صلاحية للموافقة على الممرضين. يرجى التحقق من حسابك.';
          break;
        case 'not-found':
          errorMessage = 'لم يتم العثور على بيانات الممرض. قد يكون تم حذف الحساب.';
          break;
        case 'unavailable':
          errorMessage = 'الخدمة غير متاحة حالياً. يرجى المحاولة لاحقاً.';
          break;
        default:
          errorMessage = 'حدث خطأ أثناء الموافقة: ${e.message ?? "خطأ غير معروف"}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(errorMessage),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'إغلاق',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('=== خطأ عام في الموافقة من قائمة الانتظار ===');
      debugPrint('التفاصيل: ${e.toString()}');
      debugPrint('نوع الخطأ: ${e.runtimeType}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('حدث خطأ غير متوقع: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _rejectNurse(QueryDocumentSnapshot doc) async {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      final nurseId = doc.id;
      final name = data != null && data.containsKey('name') ? data['name'] as String? : 'الممرض';
      
      // استخدام FirestoreService لرفض الممرض
      final success = await _firestoreService.rejectNurse(nurseId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم رفض طلب $name'), backgroundColor: Colors.orange),
          );
          await _loadPendingNurses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل رفض الممرض'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}