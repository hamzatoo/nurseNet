import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // دالة تسجيل الدخول والتحقق من الدور (Role)
  Future<void> loginWithRole({
    required String email,
    required String password,
    required String
    expectedRole, // الدور المتوقع للبوابة: 'patient', 'nurse', or 'admin'
    required BuildContext context,
    required Widget
    targetHomeScreen, // الشاشة الرئيسية للتوجيه إليها عند النجاح
  }) async {
    try {
      // 1. تسجيل الدخول عبر Firebase Auth
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      String uid = userCredential.user!.uid;

      // 2. جلب بيانات المستخدم من Firestore
      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get();

      if (userDoc.exists) {
        String actualRole = userDoc.get('role');

        // 3. التحقق من مطابقة الدور للبوابة
        if (actualRole == expectedRole) {
          // النجاح -> التوجيه للشاشة الرئيسية
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => targetHomeScreen),
          );
        } else {
          // عدم التطابق -> تسجيل الخروج وإظهار تنبيه
          await _auth.signOut();
          _showErrorDialog(
            context,
            'عذراً، هذا الحساب غير مجاز للدخول من هذه البوابة.',
          );
        }
      } else {
        await _auth.signOut();
        _showErrorDialog(context, 'بيانات الحساب غير موجودة في النظام.');
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'حدث خطأ أثناء تسجيل الدخول';
      if (e.code == 'user-not-found') {
        errorMessage = 'المستخدم غير موجود';
      } else if (e.code == 'wrong-password') {
        errorMessage = 'كلمة المرور غير صحيحة';
      }
      _showErrorDialog(context, errorMessage);
    } catch (e) {
      _showErrorDialog(context, 'حدث خطأ غير متوقع: $e');
    }
  }

  // رسالة تنبيه عند الخطأ
  void _showErrorDialog(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
