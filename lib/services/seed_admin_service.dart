import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SeedAdminService {
  SeedAdminService._();
  static final SeedAdminService instance = SeedAdminService._();

  // بيانات المدير الافتراضي
  static const String defaultAdminEmail = 'admin@nursenet.com';
  static const String defaultAdminPassword = 'Admin123456';
  static const String defaultAdminName = 'System Admin';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// التحقق من وجود المدير وإنشائه إذا لم يكن موجوداً
  Future<bool> ensureDefaultAdminExists() async {
    try {
      print('🔍 التحقق من وجود حساب المدير الافتراضي...');

      // 1. التحقق من وجود المستخدم في Firebase Auth
      final authMethods = await _auth.fetchSignInMethodsForEmail(defaultAdminEmail);
      
      if (authMethods.isNotEmpty) {
        print('✅ حساب المدير موجود بالفعل في Firebase Auth');
        
        // التحقق من وجود المستخدم في Firestore
        final userDoc = await _firestore
            .collection('users')
            .where('email', isEqualTo: defaultAdminEmail)
            .where('role', isEqualTo: 'admin')
            .limit(1)
            .get();

        if (userDoc.docs.isNotEmpty) {
          print('✅ حساب المدير موجود بالفعل في Firestore');
          return true;
        } else {
          print('⚠️ حساب المدير موجود في Auth لكن غير موجود في Firestore - جاري الإضافة...');
          // الحصول على المستخدم من Auth وإضافته إلى Firestore
          final authUser = _auth.currentUser;
          if (authUser != null && authUser.email == defaultAdminEmail) {
            await _firestore.collection('users').doc(authUser.uid).set({
              'email': defaultAdminEmail,
              'role': 'admin',
              'name': defaultAdminName,
              'status': 'active',
              'createdAt': FieldValue.serverTimestamp(),
              'phone': '',
              'location': '',
            });
            print('✅ تم إضافة حساب المدير إلى Firestore');
            return true;
          }
        }
        return true;
      }

      // 2. إنشاء المستخدم إذا لم يكن موجوداً
      print('🔧 حساب المدير غير موجود - جاري الإنشاء...');
      
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: defaultAdminEmail,
        password: defaultAdminPassword,
      );

      print('✅ تم إنشاء حساب في Firebase Auth');

      // 3. إضافة المستخدم إلى Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'email': defaultAdminEmail,
        'role': 'admin',
        'name': defaultAdminName,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'phone': '',
        'location': '',
      });

      print('✅ تم إنشاء حساب المدير الافتراضي بنجاح');
      print('📧 البريد: $defaultAdminEmail');
      print('🔑 كلمة المرور: $defaultAdminPassword');

      return true;
    } on FirebaseAuthException catch (e) {
      print('❌ خطأ في Firebase Auth: ${e.code} - ${e.message}');
      
      // إذا كان الخطأ بسبب أن البريد مستخدم بالفعل، فقد يكون المدير موجوداً
      if (e.code == 'email-already-in-use') {
        print('⚠️ البريد مستخدم بالفعل - التحقق من Firestore...');
        final userDoc = await _firestore
            .collection('users')
            .where('email', isEqualTo: defaultAdminEmail)
            .where('role', isEqualTo: 'admin')
            .limit(1)
            .get();

        if (userDoc.docs.isEmpty) {
          print('⚠️ البريد مستخدم لكن ليس كمدير - محاولة التحديث...');
          // محاولة البحث عن المستخدم في Auth وتحديثه
          try {
            // تسجيل الدخول لإضافة المستخدم إلى Firestore
            await _auth.signInWithEmailAndPassword(
              email: defaultAdminEmail,
              password: defaultAdminPassword,
            );
            
            final currentUser = _auth.currentUser;
            if (currentUser != null) {
              await _firestore.collection('users').doc(currentUser.uid).set({
                'email': defaultAdminEmail,
                'role': 'admin',
                'name': defaultAdminName,
                'status': 'active',
                'createdAt': FieldValue.serverTimestamp(),
                'phone': '',
                'location': '',
              }, SetOptions(merge: true));
              
              print('✅ تم تحديث حساب المدير في Firestore');
              return true;
            }
          } catch (signInError) {
            print('❌ فشل تسجيل الدخول: $signInError');
          }
        }
        return false;
      }
      
      return false;
    } catch (e) {
      print('❌ خطأ غير متوقع: $e');
      return false;
    }
  }

  /// حذف حساب المدير الافتراضي (للاختبار فقط)
  Future<bool> deleteDefaultAdmin() async {
    try {
      print('🗑️ جاري حذف حساب المدير الافتراضي...');

      // حذف من Firestore
      final userDoc = await _firestore
          .collection('users')
          .where('email', isEqualTo: defaultAdminEmail)
          .where('role', isEqualTo: 'admin')
          .limit(1)
          .get();

      if (userDoc.docs.isNotEmpty) {
        await userDoc.docs.first.reference.delete();
        print('✅ تم حذف المستخدم من Firestore');
      }

      // حذف من Auth (يتطلب تسجيل الدخول أولاً)
      try {
        final user = _auth.currentUser;
        if (user != null && user.email == defaultAdminEmail) {
          await user.delete();
          print('✅ تم حذف المستخدم من Firebase Auth');
        }
      } catch (e) {
        print('⚠️ لم يتم حذف المستخدم من Auth: $e');
      }

      return true;
    } catch (e) {
      print('❌ خطأ في حذف حساب المدير: $e');
      return false;
    }
  }
}