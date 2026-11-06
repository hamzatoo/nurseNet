import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();
  
  bool _useFallback = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  FirebaseFirestore get _firestore {
    try {
      return FirebaseFirestore.instance;
    } catch (e) {
      print('Firestore initialization error: $e');
      _useFallback = true;
      throw Exception('Firestore not available. Using fallback data.');
    }
  }
  
  // التحقق من إمكانية استخدام Firestore
  bool get isFirestoreAvailable {
    try {
      FirebaseFirestore.instance;
      return !_useFallback;
    } catch (e) {
      _useFallback = true;
      return false;
    }
  }

  // ==========================================
  // عمليات المستخدمين
  // ==========================================

  /// الحصول على تدفق المستخدمين حسب الدور
  Stream<List<AppUser>> getUsersByRole(UserRole role) {
    try {
      debugPrint('Fetching users with role: ${role.toString().split('.').last}');
      return _firestore
          .collection('users')
          .where('role', isEqualTo: role.toString().split('.').last)
          .where('status', isEqualTo: 'active')
          .snapshots()
          .map((snapshot) {
            debugPrint('Received ${snapshot.docs.length} users with role: ${role.toString().split('.').last}');
            return snapshot.docs
                .map((doc) => _mapDocumentToUser(doc))
                .toList();
          })
          .handleError((error, stackTrace) {
            debugPrint('Error in getUsersByRole stream: $error');
            debugPrint('Stack trace: $stackTrace');
            throw error;
          });
    } catch (e) {
      debugPrint('Error creating getUsersByRole stream: $e');
      rethrow;
    }
  }

  /// الحصول على المستخدم حسب المعرف
  Future<AppUser?> getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return _mapDocumentToUser(doc);
      }
      return null;
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  /// الحصول على المستخدم حسب البريد الإلكتروني
  Future<AppUser?> getUserByEmail(String email) async {
    try {
      // First try to get from patients collection
      final patientSnapshot = await _firestore
          .collection('patients')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      if (patientSnapshot.docs.isNotEmpty) {
        return _mapDocumentToUser(patientSnapshot.docs.first);
      }

      // If not found in patients, try users collection
      final userSnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      if (userSnapshot.docs.isNotEmpty) {
        return _mapDocumentToUser(userSnapshot.docs.first);
      }

      return null;
    } catch (e) {
      print('Error getting user by email: $e');
      return null;
    }
  }

  /// الحصول على جميع الممرضين النشطين
  Stream<List<AppUser>> getActiveNurses() {
    return getUsersByRole(UserRole.nurse);
  }

  /// الحصول على الممرضين بانتظار الموافقة
  Stream<List<AppUser>> getPendingNurses() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'nurse')
        .where('verificationStatus', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _mapDocumentToUser(doc))
            .toList());
  }

  /// الحصول على جميع الممرضين النشطين من مجموعة nurses
  Stream<List<AppUser>> getActiveNursesFromNursesCollection() {
    return _firestore
        .collection('nurses')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _mapDocumentToUser(doc))
            .toList());
  }

  /// الحصول على جميع المرضى النشطين
  Stream<List<AppUser>> getActivePatients() {
    return getUsersByRole(UserRole.patient);
  }

  // ==========================================
  // عمليات المصادقة
  // ==========================================

  /// التحقق من بيانات تسجيل الدخول باستخدام Firebase Auth
  Future<AppUser?> authenticateUser(String email, String password, UserRole expectedRole) async {
    try {
      // 1. تسجيل الدخول باستخدام Firebase Auth
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        print('Authentication failed: User is null after sign in');
        return null;
      }

      print('Authentication successful for user: ${credential.user!.uid}');

      // 2. جلب بيانات المستخدم من Firestore (التحقق من المجموعة المناسبة حسب الدور)
      DocumentSnapshot userDoc;
      String collectionName;
      
      if (expectedRole == UserRole.nurse || expectedRole == UserRole.admin) {
        // للممرضين والمديرين، ابحث في users collection
        userDoc = await _firestore.collection('users').doc(credential.user!.uid).get();
        collectionName = 'users';
      } else {
        // للمرضى، ابحث في patients collection
        userDoc = await _firestore.collection('patients').doc(credential.user!.uid).get();
        collectionName = 'patients';
      }
      
      if (!userDoc.exists) {
        print('User not found in $collectionName collection');
        // المستخدم غير موجود في Firestore، تسجيل الخروج
        await FirebaseAuth.instance.signOut();
        return null;
      }

      // 3. تحويل البيانات إلى AppUser
      final userData = userDoc.data() as Map<String, dynamic>;
      final user = AppUser.fromFirestore(userData, userDoc.id);

      // 4. التحقق من الدور
      if (user.role != expectedRole) {
        print('Role mismatch: expected $expectedRole, got ${user.role}');
        // الدور غير متطابق، تسجيل الخروج
        await FirebaseAuth.instance.signOut();
        return null;
      }

      // 5. التحقق من الحالة (تجاوز التحقق للممرضين والمديرين للاختبار)
      if (user.status != UserStatus.active && expectedRole != UserRole.nurse && expectedRole != UserRole.admin) {
        print('User status is not active: ${user.status}');
        // الحساب غير نشط، تسجيل الخروج
        await FirebaseAuth.instance.signOut();
        return null;
      }

      print('User authenticated successfully: ${user.name} (${user.email})');
      return user;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth error: ${e.code} - ${e.message}');
      // معالجة الأخطاء الشائعة بدون إعادة رمي الاستثناء
      // الـ UI ستتعامل مع النتيجة null وتعرض رسالة مناسبة
      return null;
    } catch (e) {
      print('Authentication error: $e');
      // معالجة الأخطاء الأخرى بدون إعادة رمي الاستثناء
      return null;
    }
  }

  // ==========================================
  // دوال مساعدة
  // ==========================================

  AppUser _mapDocumentToUser(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // تحويل سلسلة الدور إلى enum
    UserRole role;
    try {
      final roleString = data['role'] as String? ?? 'patient';
      role = UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == roleString,
        orElse: () => UserRole.patient,
      );
    } catch (e) {
      role = UserRole.patient;
    }

    // تحويل سلسلة الحالة إلى enum
    UserStatus status;
    try {
      final statusString = data['status'] as String? ?? 'active';
      status = UserStatus.values.firstWhere(
        (e) => e.toString().split('.').last == statusString,
        orElse: () => UserStatus.active,
      );
    } catch (e) {
      status = UserStatus.active;
    }

    // Handle medical tags safely
    List<String> medicalTags = [];
    try {
      if (data['medicalTags'] != null) {
        medicalTags = List<String>.from(data['medicalTags']);
      }
    } catch (e) {
      print('Error parsing medical tags: $e');
    }

    return AppUser(
      id: doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      role: role,
      status: status,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      location: data['location'] as String?,
      specialty: data['specialty'] as String?,
      experienceYears: data['experienceYears'] as int?,
      isResidentNurse: data['isResidentNurse'] as bool? ?? false,
      certificateVerified: data['certificateVerified'] as bool? ?? false,
      medicalCategory: data['medicalCategory'] as String?,
      medicalTags: medicalTags,
      medicalDescription: data['medicalDescription'] as String?,
      licenseNumber: data['licenseNumber'] as String?,
      isVerified: data['isVerified'] as bool? ?? false,
      verificationStatus: _parseVerificationStatus(data['verificationStatus'] as String?),
    );
  }

  Map<String, dynamic> _mapUserToDocument(AppUser user) {
    return {
      'name': user.name,
      'email': user.email,
      'phone': user.phone,
      'role': user.role.toString().split('.').last,
      'status': user.status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(user.createdAt),
      'location': user.location,
      'specialty': user.specialty,
      'experienceYears': user.experienceYears,
      'isResidentNurse': user.isResidentNurse,
      'certificateVerified': user.certificateVerified,
      'medicalCategory': user.medicalCategory,
      'medicalTags': user.medicalTags.isNotEmpty ? user.medicalTags : [],
      'medicalDescription': user.medicalDescription,
      'licenseNumber': user.licenseNumber,
      'isVerified': user.isVerified,
      'verificationStatus': user.verificationStatus.toString().split('.').last,
    };
  }

  VerificationStatus _parseVerificationStatus(String? status) {
    if (status == null || status.isEmpty) return VerificationStatus.pending;
    switch (status.toLowerCase().trim()) {
      case 'approved':
        return VerificationStatus.approved;
      case 'rejected':
        return VerificationStatus.rejected;
      case 'pending':
      default:
        return VerificationStatus.pending;
    }
  }

  // ==========================================
  // عمليات الإنشاء والتحديث
  // ==========================================

  /// إنشاء مستخدم جديد
  Future<bool> createUser(AppUser user) async {
    try {
      await _firestore.collection('users').doc(user.id).set(_mapUserToDocument(user));
      return true;
    } catch (e) {
      print('Error creating user: $e');
      return false;
    }
  }

  /// إنشاء مستخدم ممرض جديد مع البيانات الكاملة
  Future<bool> createNurseUser({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required String location,
    required String specialty,
    required int experienceYears,
    required bool isResidentNurse,
    String? licenseNumber,
  }) async {
    try {
      final nurseData = {
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'nurse',
        'status': 'pending', // حالة انتظار الموافقة من المدير
        'isApproved': false, // لم يتم الموافقة عليه بعد
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'location': location,
        'specialty': specialty,
        'experienceYears': experienceYears,
        'isResidentNurse': isResidentNurse,
        'certificateVerified': false, // لم يتم التوثيق بعد
        'licenseNumber': licenseNumber,
        'isVerified': false, // لم يتم التحقق من الترخيص بعد
        'verificationStatus': 'pending', // حالة التحقق معلقة
        'averageRating': 0.0, // متوسط التقييم الافتراضي
        'totalReviews': 0, // عدد المراجعات الافتراضي
      };

      await _firestore.collection('users').doc(uid).set(nurseData);
      print('Nurse user created successfully in Firestore with pending status: $email');
      return true;
    } catch (e) {
      print('Error creating nurse user: $e');
      return false;
    }
  }

  /// مزامنة بيانات الممرض إلى مجموعة nurses بشكل صامت
  Future<bool> syncNurseToNursesCollection({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required String location,
    required String specialty,
    required int experienceYears,
    required bool isResidentNurse,
    String? licenseNumber,
  }) async {
    try {
      final nurseData = {
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'nurse',
        'status': 'pending', // حالة انتظار الموافقة
        'isApproved': false, // لم يتم الموافقة عليه بعد
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'location': location,
        'specialty': specialty,
        'experienceYears': experienceYears,
        'isResidentNurse': isResidentNurse,
        'certificateVerified': false, // لم يتم التوثيق بعد
        'licenseNumber': licenseNumber,
        'isVerified': false, // لم يتم التحقق من الترخيص بعد
        'verificationStatus': 'pending', // حالة التحقق معلقة
        'available': false, // غير متاح حتى الموافقة
        'verified': false, // غير موثق حتى الموافقة
        'services': specialty, // استخدام التخصص كخدمات
        'averageRating': 0.0, // متوسط التقييم الافتراضي
        'totalReviews': 0, // عدد المراجعات الافتراضي
      };

      await _firestore.collection('nurses').doc(uid).set(nurseData);
      print('Nurse synced to nurses collection successfully with pending status: $email');
      return true;
    } catch (e) {
      print('Error syncing nurse to nurses collection: $e');
      return false;
    }
  }

  /// تحديث بيانات المستخدم
  Future<bool> updateUser(AppUser user) async {
    try {
      await _firestore.collection('users').doc(user.id).update(_mapUserToDocument(user));
      return true;
    } catch (e) {
      print('Error updating user: $e');
      return false;
    }
  }

  /// قبول طلب توثيق الممرض
  Future<bool> approveNurse(String nurseId) async {
    try {
      print('=== بدء عملية موافقة الممرض ===');
      print('معرف الممرض: $nurseId');
      print('المستخدم الحالي: ${_auth.currentUser?.uid}');
      
      // التحقق من وجود المستخدم أولاً
      print('التحقق من وجود المستخدم في مجموعة users...');
      final userDoc = await _firestore.collection('users').doc(nurseId).get();
      if (!userDoc.exists) {
        print('خطأ: المستخدم غير موجود في مجموعة users');
        return false;
      }
      
      final userData = userDoc.data() as Map<String, dynamic>;
      print('بيانات المستخدم الحالية: $userData');
      print('الحقول الموجودة: ${userData.keys.toList()}');
      
      // تحديث في مجموعة users
      print('جاري تحديث مجموعة users...');
      print('الحقول المراد تحديثها: status, isVerified, verificationStatus, certificateVerified');
      
      try {
        await _firestore.collection('users').doc(nurseId).update({
          'status': 'active',
          'isVerified': true,
          'verificationStatus': 'approved',
          'certificateVerified': true,
        });
        print('تم تحديث مجموعة users بنجاح');
      } catch (usersError) {
        print('خطأ في تحديث مجموعة users: $usersError');
        print('نوع الخطأ: ${usersError.runtimeType}');
        rethrow;
      }

      // تحديث في مجموعة nurses أيضاً
      print('جاري التحقق من مجموعة nurses...');
      final nurseDoc = await _firestore.collection('nurses').doc(nurseId).get();
      if (nurseDoc.exists) {
        print('المستند موجود في مجموعة nurses');
        final nurseData = nurseDoc.data() as Map<String, dynamic>;
        print('بيانات الممرض الحالية: $nurseData');
        
        try {
          await _firestore.collection('nurses').doc(nurseId).update({
            'status': 'active',
            'verified': true,
            'available': true,
          });
          print('تم تحديث مجموعة nurses بنجاح');
        } catch (nursesError) {
          print('خطأ في تحديث مجموعة nurses: $nursesError');
          print('نوع الخطأ: ${nursesError.runtimeType}');
          // لا نعيد إلقاء الخطأ هنا لأن تحديث users نجح
        }
      } else {
        print('تحذير: المستخدم غير موجود في مجموعة nurses (سيتم إنشاء السجل)');
        try {
          await _firestore.collection('nurses').doc(nurseId).set({
            'status': 'active',
            'verified': true,
            'available': true,
            'userId': nurseId,
            'createdAt': DateTime.now().toIso8601String(),
          });
          print('تم إنشاء سجل في مجموعة nurses بنجاح');
        } catch (createError) {
          print('خطأ في إنشاء سجل nurses: $createError');
          print('نوع الخطأ: ${createError.runtimeType}');
        }
      }

      print('تمت الموافقة على الممرض بنجاح: $nurseId');
      return true;
    } on FirebaseException catch (e) {
      print('=== خطأ Firebase في موافقة الممرض ===');
      print('الكود: ${e.code}');
      print('الرسالة: ${e.message}');
      print('المسار الكامل: ${e.toString()}');
      
      switch (e.code) {
        case 'permission-denied':
          print('خطأ الصلاحيات: المستخدم الحالي ليس لديه صلاحية الكتابة');
          print('المستخدم الحالي: ${_auth.currentUser?.uid}');
          break;
        case 'not-found':
          print('خطأ: المستند غير موجود');
          break;
        case 'invalid-argument':
          print('خطأ: معاملات غير صالحة');
          break;
        case 'already-exists':
          print('خطأ: المستند موجود بالفعل');
          break;
        default:
          print('خطأ Firebase غير معروف: ${e.code}');
      }
      
      return false;
    } catch (e) {
      print('=== خطأ عام في موافقة الممرض ===');
      print('التفاصيل: ${e.toString()}');
      print('نوع الخطأ: ${e.runtimeType}');
      print('Stack Trace: ${StackTrace.current}');
      return false;
    }
  }

  /// رفض طلب توثيق الممرض
  Future<bool> rejectNurse(String nurseId, {String? reason}) async {
    try {
      print('=== بدء عملية رفض الممرض ===');
      print('معرف الممرض: $nurseId');
      print('سبب الرفض: $reason');
      print('المستخدم الحالي: ${_auth.currentUser?.uid}');
      
      // التحقق من وجود المستخدم أولاً
      print('التحقق من وجود المستخدم في مجموعة users...');
      final userDoc = await _firestore.collection('users').doc(nurseId).get();
      if (!userDoc.exists) {
        print('خطأ: المستخدم غير موجود في مجموعة users');
        return false;
      }
      
      final userData = userDoc.data() as Map<String, dynamic>;
      print('بيانات المستخدم الحالية: $userData');
      print('الحقول الموجودة: ${userData.keys.toList()}');
      
      // تحديث في مجموعة users
      print('جاري تحديث مجموعة users...');
      print('الحقول المراد تحديثها: status, isVerified, verificationStatus, rejectionReason');
      
      try {
        await _firestore.collection('users').doc(nurseId).update({
          'status': 'suspended',
          'isVerified': false,
          'verificationStatus': 'rejected',
          'rejectionReason': reason,
        });
        print('تم تحديث مجموعة users بنجاح');
      } catch (usersError) {
        print('خطأ في تحديث مجموعة users: $usersError');
        print('نوع الخطأ: ${usersError.runtimeType}');
        rethrow;
      }

      // تحديث في مجموعة nurses أيضاً
      print('جاري التحقق من مجموعة nurses...');
      final nurseDoc = await _firestore.collection('nurses').doc(nurseId).get();
      if (nurseDoc.exists) {
        print('المستند موجود في مجموعة nurses');
        final nurseData = nurseDoc.data() as Map<String, dynamic>;
        print('بيانات الممرض الحالية: $nurseData');
        
        try {
          await _firestore.collection('nurses').doc(nurseId).update({
            'status': 'suspended',
            'verified': false,
            'available': false,
          });
          print('تم تحديث مجموعة nurses بنجاح');
        } catch (nursesError) {
          print('خطأ في تحديث مجموعة nurses: $nursesError');
          print('نوع الخطأ: ${nursesError.runtimeType}');
          // لا نعيد إلقاء الخطأ هنا لأن تحديث users نجح
        }
      } else {
        print('تحذير: المستخدم غير موجود في مجموعة nurses');
      }

      print('تم رفض الممرض بنجاح: $nurseId');
      return true;
    } on FirebaseException catch (e) {
      print('=== خطأ Firebase في رفض الممرض ===');
      print('الكود: ${e.code}');
      print('الرسالة: ${e.message}');
      print('المسار الكامل: ${e.toString()}');
      
      switch (e.code) {
        case 'permission-denied':
          print('خطأ الصلاحيات: المستخدم الحالي ليس لديه صلاحية الكتابة');
          print('المستخدم الحالي: ${_auth.currentUser?.uid}');
          break;
        case 'not-found':
        case 'invalid-argument':
          print('خطأ: معاملات غير صالحة أو المستند غير موجود');
          break;
        default:
          print('خطأ Firebase غير معروف: ${e.code}');
      }
      
      return false;
    } catch (e) {
      print('=== خطأ عام في رفض الممرض ===');
      print('التفاصيل: ${e.toString()}');
      print('نوع الخطأ: ${e.runtimeType}');
      print('Stack Trace: ${StackTrace.current}');
      return false;
    }
  }

  // ==========================================
  // عمليات البحث والتصفية
  // ==========================================

  /// البحث عن ممرضين حسب الموقع
  Stream<List<AppUser>> searchNursesByLocation(String location) {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'nurse')
        .where('status', isEqualTo: 'active')
        .where('location', isEqualTo: location)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _mapDocumentToUser(doc))
            .toList());
  }

  /// البحث عن ممرضين حسب التخصص
  Stream<List<AppUser>> searchNursesBySpecialty(String specialty) {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'nurse')
        .where('status', isEqualTo: 'active')
        .where('specialty', isGreaterThanOrEqualTo: specialty)
        .where('specialty', isLessThanOrEqualTo: specialty + '\uf8ff')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _mapDocumentToUser(doc))
            .toList());
  }
}