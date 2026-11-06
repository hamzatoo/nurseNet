import 'package:flutter/material.dart';
import '../theme.dart';
import 'patient_login_view.dart';
import 'provider_login_view.dart';
import 'admin_login_view.dart';

class UserTypeView extends StatelessWidget {
  const UserTypeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // قلبنا الواجهة بالكامل من اليمين لليسار عشان اللغة العربية
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 30.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),

                  // الشعار (Logo)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_hospital_rounded,
                        size: 60,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'NurseNet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'يرجى تحديد نوع الحساب للمتابعة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  const SizedBox(height: 35),

                  // 1. كرت المريض
                  _buildTypeCard(
                    context,
                    title: ' مريض',
                    subtitle: 'ابحث عن رعاية طبية منزلية بسهولة',
                    icon: Icons.personal_injury_rounded,
                    onTap: () {
                      Navigator.push(
                        context,
                        // ملاحظة: تأكد إنك حطيت اسم كلاس المريض الحقيقي هنا مكان PatientLoginView إذا كان مختلف
                        MaterialPageRoute(
                          builder: (context) => PatientSignUpView(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2. كرت الممرض / الدكتور
                  _buildTypeCard(
                    context,
                    title: 'الكادر الطبي',
                    subtitle: 'بوابة الأطباء والممرضين لخدمة المرضى',
                    icon: Icons.medical_services_rounded,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProviderLoginView(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 3. كرت الآدمين
                  _buildTypeCard(
                    context,
                    title: 'مدير النظام',
                    subtitle: 'إدارة المستخدمين، العيادات، والطلبات',
                    icon: Icons.admin_panel_settings_rounded,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AdminLoginView(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            // السهم انقلب لليسار عشان يتماشى مع اتجاه اللغة العربية
            const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
