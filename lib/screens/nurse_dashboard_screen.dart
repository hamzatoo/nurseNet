import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../services/app_data_service.dart';
import '../services/firestore_service.dart';
import '../models/care_request.dart';
import '../models/user_model.dart';
import 'nurse_approval_waiting_screen.dart';

class NurseDashboardScreen extends StatefulWidget {
  const NurseDashboardScreen({super.key});

  @override
  State<NurseDashboardScreen> createState() => _NurseDashboardScreenState();
}

class _NurseDashboardScreenState extends State<NurseDashboardScreen> {
  final _data = AppDataService.instance;
  final _firestoreService = FirestoreService.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  int _selectedTab = 0;
  bool _isAvailable = true;

  void _refresh() => setState(() {});

  AppUser? get _nurse => _data.currentUser;
  String? get _currentNurseId => _auth.currentUser?.uid;

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
        _data.logout();
        
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

  @override
  Widget build(BuildContext context) {
    // إذا لم يكن هناك مستخدم مسجل دخول، اعرض شاشة التحميل أو أعيد التوجيه
    if (_nurse == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'جاري التحميل...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // التحقق من حالة الموافقة - إذا لم تتم الموافقة، أعيد التوجيه لشاشة الانتظار
    if (_nurse!.status == UserStatus.pending || _nurse!.status == UserStatus.suspended) {
      return const NurseApprovalWaitingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildTabContent(),
                const SizedBox(height: 80), // مساحة للـ Bottom Navigation Bar
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.medical_services_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        'مرحباً ${_nurse!.name}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _nurse!.specialty ?? 'ممرض',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  _isAvailable ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _isAvailable ? 'متاح لاستقبال الطلبات' : 'غير متاح حالياً',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
                Switch(
                  value: _isAvailable,
                  onChanged: (v) => setState(() => _isAvailable = v),
                  activeTrackColor: Colors.green,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return Colors.grey;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: Icons.inbox_rounded,
                label: 'الطلبات الجديدة',
                index: 0,
              ),
              _buildNavItem(
                icon: Icons.assignment_rounded,
                label: 'طلباتي',
                index: 1,
              ),
              _buildNavItem(
                icon: Icons.people_rounded,
                label: 'مرضاي',
                index: 2,
              ),
              _buildNavItem(
                icon: Icons.person_rounded,
                label: 'ملفي',
                index: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.primary : Colors.grey[600],
                size: 24,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : Colors.grey[600],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 1:
        return _buildMyRequestsTab();
      case 2:
        return _buildMyPatientsTab();
      case 3:
        return _buildProfileTab();
      default:
        return _buildNewRequestsTab();
    }
  }

  // ==================== الطلبات الجديدة ====================
  Widget _buildNewRequestsTab() {
    if (_currentNurseId == null) {
      debugPrint('Auth Guard: No current nurse ID found');
      return _emptyState('لا توجد طلبات جديدة حالياً', Icons.inbox_rounded);
    }

    try {
      return StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('care_requests')
            .where('nurseId', isEqualTo: _currentNurseId)
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }

          if (snapshot.hasError) {
            debugPrint('Dashboard Stream Error (New Requests): ${snapshot.error}');
            debugPrint('Error Details: ${snapshot.error.toString()}');
            debugPrint('Stack Trace: ${StackTrace.current}');
            return _buildErrorState('حدث خطأ في تحميل الطلبات الجديدة');
          }

          if (!snapshot.hasData) {
            debugPrint('No data available for new requests');
            return _emptyState('لا توجد طلبات جديدة حالياً', Icons.inbox_rounded);
          }

          if (snapshot.data!.docs.isEmpty) {
            debugPrint('New requests snapshot is empty - displaying empty state');
            return _emptyState('لا توجد طلبات جديدة حالياً', Icons.inbox_rounded);
          }

          try {
            final requests = snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data == null) {
                debugPrint('Null document data for doc ${doc.id}');
                return null;
              }
              return CareRequest.fromFirestore(data, doc.id);
            }).where((request) => request != null).cast<CareRequest>().toList();

            // Sort locally in Dart memory to avoid composite index requirement
            requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            debugPrint('Successfully loaded ${requests.length} new requests');

            if (requests.isEmpty) {
              return _emptyState('لا توجد طلبات جديدة حالياً', Icons.inbox_rounded);
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: requests.map((request) => _buildRequestCard(request, isNew: true)).toList(),
              ),
            );
          } catch (e) {
            debugPrint('Error parsing request data: $e');
            debugPrint('Stack Trace: ${StackTrace.current}');
            return _buildErrorState('حدث خطأ في معالجة بيانات الطلبات');
          }
        },
      );
    } catch (e) {
      debugPrint('Fatal error in new requests stream: $e');
      return _emptyState('لا توجد طلبات جديدة حالياً', Icons.inbox_rounded);
    }
  }

  // ==================== طلباتي ====================
  Widget _buildMyRequestsTab() {
    if (_currentNurseId == null) {
      debugPrint('Auth Guard: No current nurse ID found');
      return _emptyState('لم تقبل أي طلبات بعد', Icons.assignment_outlined);
    }

    try {
      return StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('care_requests')
            .where('nurseId', isEqualTo: _currentNurseId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }

          if (snapshot.hasError) {
            debugPrint('Dashboard Stream Error (My Requests): ${snapshot.error}');
            debugPrint('Error Details: ${snapshot.error.toString()}');
            debugPrint('Stack Trace: ${StackTrace.current}');
            return _buildErrorState('حدث خطأ في تحميل طلباتي');
          }

          if (!snapshot.hasData) {
            debugPrint('No data available for my requests');
            return _emptyState('لم تقبل أي طلبات بعد', Icons.assignment_outlined);
          }

          if (snapshot.data!.docs.isEmpty) {
            debugPrint('My requests snapshot is empty - displaying empty state');
            return _emptyState('لم تقبل أي طلبات بعد', Icons.assignment_outlined);
          }

          try {
            final allRequests = snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data == null) {
                debugPrint('Null document data for doc ${doc.id}');
                return null;
              }
              return CareRequest.fromFirestore(data, doc.id);
            }).where((request) => request != null).cast<CareRequest>().toList();

            // Filter locally for accepted and in_progress status
            final filteredRequests = allRequests.where((request) {
              return request.status == RequestStatus.accepted ||
                     request.status == RequestStatus.inProgress;
            }).toList();

            // Sort locally in Dart memory to avoid composite index requirement
            filteredRequests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            debugPrint('Successfully loaded ${filteredRequests.length} active requests (filtered from ${allRequests.length} total)');

            if (filteredRequests.isEmpty) {
              return _emptyState('لم تقبل أي طلبات بعد', Icons.assignment_outlined);
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: filteredRequests.map((request) => _buildRequestCard(request)).toList(),
              ),
            );
          } catch (e) {
            debugPrint('Error parsing request data: $e');
            debugPrint('Stack Trace: ${StackTrace.current}');
            return _buildErrorState('حدث خطأ في معالجة بيانات الطلبات');
          }
        },
      );
    } catch (e) {
      debugPrint('Fatal error in my requests stream: $e');
      return _emptyState('لم تقبل أي طلبات بعد', Icons.assignment_outlined);
    }
  }

  // ==================== مرضاي ====================
  Widget _buildMyPatientsTab() {
    if (_currentNurseId == null) {
      debugPrint('Auth Guard: No current nurse ID found');
      return _emptyState('لم تقبل أي مرضى بعد', Icons.people_outline_rounded);
    }

    try {
      return StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('care_requests')
            .where('nurseId', isEqualTo: _currentNurseId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }

          if (snapshot.hasError) {
            debugPrint('Dashboard Stream Error (My Patients): ${snapshot.error}');
            debugPrint('Error Details: ${snapshot.error.toString()}');
            debugPrint('Stack Trace: ${StackTrace.current}');
            return _buildErrorState('حدث خطأ في تحميل مرضاي');
          }

          if (!snapshot.hasData) {
            debugPrint('No data available for my patients');
            return _emptyState('لم تقبل أي مرضى بعد', Icons.people_outline_rounded);
          }

          if (snapshot.data!.docs.isEmpty) {
            debugPrint('My patients snapshot is empty - displaying empty state');
            return _emptyState('لم تقبل أي مرضى بعد', Icons.people_outline_rounded);
          }

          try {
            final allRequests = snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>?;
              if (data == null) {
                debugPrint('Null document data for doc ${doc.id}');
                return null;
              }
              return CareRequest.fromFirestore(data, doc.id);
            }).where((request) => request != null).cast<CareRequest>().toList();

            // Filter locally for accepted, in_progress and completed status
            final filteredRequests = allRequests.where((request) {
              return request.status == RequestStatus.accepted ||
                     request.status == RequestStatus.inProgress ||
                     request.status == RequestStatus.completed;
            }).toList();

            // Sort locally in Dart memory to avoid composite index requirement
            filteredRequests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            debugPrint('Successfully loaded ${filteredRequests.length} patients (filtered from ${allRequests.length} total)');

            if (filteredRequests.isEmpty) {
              return _emptyState('لم تقبل أي مرضى بعد', Icons.people_outline_rounded);
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: filteredRequests.map((request) => _buildPatientCard(request)).toList(),
              ),
            );
          } catch (e) {
            debugPrint('Error parsing patient data: $e');
            debugPrint('Stack Trace: ${StackTrace.current}');
            return _buildErrorState('حدث خطأ في معالجة بيانات المرضى');
          }
        },
      );
    } catch (e) {
      debugPrint('Fatal error in my patients stream: $e');
      return _emptyState('لم تقبل أي مرضى بعد', Icons.people_outline_rounded);
    }
  }

  // ==================== ملفي ====================
  Widget _buildProfileTab() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _profileItem(Icons.person_rounded, 'الاسم', _nurse!.name),
          _profileItem(Icons.email_outlined, 'البريد', _nurse!.email),
          _profileItem(Icons.phone_outlined, 'الهاتف', _nurse!.phone),
          _profileItem(Icons.location_on_outlined, 'الموقع', _nurse!.location ?? '-'),
          _profileItem(Icons.medical_services_outlined, 'التخصص', _nurse!.specialty ?? '-'),
          _profileItem(Icons.work_history_outlined, 'سنوات الخبرة', '${_nurse!.experienceYears ?? 0} سنوات'),
          _profileItem(
            Icons.home_work_outlined,
            'ممرض مقيم',
            _nurse!.isResidentNurse == true ? 'نعم' : 'لا',
          ),
          _profileItem(
            Icons.verified_rounded,
            'حالة التوثيق',
            _nurse!.certificateVerified == true ? 'موثّق' : 'قيد المراجعة',
          ),
        ],
      ),
    );
  }

  // ==================== بطاقة الطلب ====================
  Widget _buildRequestCard(CareRequest request, {bool isNew = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.patientName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            request.location,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (request.requestedDate != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'التاريخ المطلوب: ${_formatDate(request.requestedDate)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (request.needsResidentNurse)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'مقيم',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              request.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: request.tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),
          if (isNew) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _acceptRequest(request);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'قبول الطلب',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _rejectRequest(request);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'رفض',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==================== بطاقة المريض ====================
  Widget _buildPatientCard(CareRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.patientName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            request.location,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (request.requestedDate != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'التاريخ المطلوب: ${_formatDate(request.requestedDate)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: request.status == RequestStatus.completed
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: request.status == RequestStatus.completed
                        ? Colors.green.withOpacity(0.3)
                        : Colors.orange.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  request.status == RequestStatus.completed ? 'مكتمل' : 'نشط',
                  style: TextStyle(
                    fontSize: 11,
                    color: request.status == RequestStatus.completed ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              request.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: request.tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _buildActionButton(
              icon: Icons.phone_rounded,
              label: 'اتصال',
              color: AppColors.primary,
              onTap: () async {
                try {
                  final patientDoc = await _firestore.collection('users').doc(request.patientId).get();
                  if (patientDoc.exists) {
                    final patientData = patientDoc.data() as Map<String, dynamic>;
                    final patientPhone = patientData['phone'] as String?;
                    
                    if (patientPhone != null && patientPhone.isNotEmpty) {
                      await _makePhoneCall(patientPhone);
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('رقم هاتف المريض غير متوفر'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('لم يتم العثور على بيانات المريض'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  debugPrint('Error fetching patient phone: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('حدث خطأ: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== عنصر الملف الشخصي ====================
  Widget _profileItem(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== حالات التحميل والخطأ والفارغ ====================
  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'جاري التحميل...',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'يرجى المحاولة مرة أخرى لاحقاً',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'سيتم تحديث القائمة تلقائياً عند توفر بيانات جديدة',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== دالة مساعدة للاتصال الهاتفي ====================
  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      // تنظيف الرقم من المسافات والأحرف غير الرقمية
      final cleanedPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      
      if (cleanedPhone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('رقم الهاتف غير صالح'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final Uri phoneUri = Uri(scheme: 'tel', path: cleanedPhone);
      
      if (await canLaunchUrl(phoneUri)) {
        final launched = await launchUrl(phoneUri);
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل فتح تطبيق الهاتف'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الجهاز لا يدعم ميزة الاتصال'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error making phone call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==================== دوال القبول والرفض ====================
  Future<void> _acceptRequest(CareRequest request) async {
    if (_currentNurseId == null) {
      debugPrint('Auth Guard: Cannot accept request - no nurse ID');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم يتم تحديد هوية الممرض'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      debugPrint('Accepting request: ${request.id}');
      
      // Get patient phone number for the request
      String? patientPhone;
      try {
        final patientDoc = await _firestore.collection('users').doc(request.patientId).get();
        if (patientDoc.exists) {
          final patientData = patientDoc.data() as Map<String, dynamic>;
          patientPhone = patientData['phone'] as String?;
        }
      } catch (e) {
        debugPrint('Error fetching patient phone: $e');
      }
      
      await _firestore.collection('care_requests').doc(request.id).update({
        'nurseId': _currentNurseId,
        'nurseName': _nurse!.name,
        'nursePhone': _nurse!.phone,
        'patientPhone': patientPhone,
        'status': 'accepted',
        'acceptedAt': Timestamp.now(),
      });

      debugPrint('Request accepted successfully: ${request.id}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم قبول الطلب بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error accepting request: $e');
      debugPrint('Stack Trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل قبول الطلب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'غير محدد';
    try {
      final formatter = DateFormat('dd/MM/yyyy', 'ar');
      return formatter.format(date);
    } catch (e) {
      debugPrint('Error formatting date: $e');
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _rejectRequest(CareRequest request) async {
    try {
      debugPrint('Rejecting request: ${request.id}');
      await _firestore.collection('care_requests').doc(request.id).update({
        'status': 'rejected',
        'rejectedAt': Timestamp.now(),
      });

      debugPrint('Request rejected successfully: ${request.id}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم رفض الطلب'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error rejecting request: $e');
      debugPrint('Stack Trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل رفض الطلب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
