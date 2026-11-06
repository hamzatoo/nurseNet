import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../services/app_data_service.dart';
import '../services/firestore_service.dart';
import '../services/api_service.dart';
import '../models/user_model.dart';
import 'nurse_approval_waiting_screen.dart';

class NurseSignUpView extends StatefulWidget {
  const NurseSignUpView({super.key});

  @override
  State<NurseSignUpView> createState() => _NurseSignUpViewState();
}

class _NurseSignUpViewState extends State<NurseSignUpView> {
  // --- التحكم بالواجهات ---
  int _currentStep = 0;
  bool _isLoading = false;

  // --- الخدمات ---
  final _firestoreService = FirestoreService.instance;
  final _appDataService = AppDataService.instance;
  final _apiService = ApiService.instance;

  // --- متغيرات الخطوة 1: البيانات الشخصية والموقع ---
  final _formKeyStep1 = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _passwordController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  bool _isPasswordVisible = false;

  // --- متغيرات الخطوة 2: الاختصاص والخبرات ---
  final _formKeyStep2 = GlobalKey<FormState>();
  String? _selectedSpecialty;
  final _experienceYearsController = TextEditingController();

  final List<String> _specialties = [
    'تمريض عام',
    'رعاية مسنين',
    'عناية مركزة (ICU)',
    'تمريض أطفال وحديثي ولادة',
    'إسعافات أولية وطوارئ',
    'علاج طبيعي وإعادة تأهيل',
    'تمريض جراحي (ما بعد العمليات)',
  ];

  // --- متغيرات الخطوة 3: التفضيلات ---
  bool _isResidentNurse = false; // خيار الممرض المقيم

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            children: [
              _buildCustomAppBar(),
              Expanded(
                child: _buildSignUpWizard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // شريط التنقل العلوي
  // ==========================================
  Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: AppColors.primary,
            ),
            onPressed: () {
              if (_currentStep > 0) {
                setState(() => _currentStep--);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'إنشاء حساب ممرض - خطوة ${_currentStep + 1}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // معالج إنشاء حساب الممرض (WIZARD)
  // ==========================================
  Widget _buildSignUpWizard() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: index <= _currentStep
                        ? AppColors.primary
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: _buildCurrentStepContent(),
          ),
        ),
        _buildBottomNavButtons(),
      ],
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildPersonalInfoStep();
      case 1:
        return _buildSpecialtyStep();
      case 2:
        return _buildPreferencesStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- الخطوة 1: البيانات الشخصية والموقع ---
  Widget _buildPersonalInfoStep() {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'البيانات الأساسية 🩺',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'أدخل بياناتك الشخصية للتواصل والموقع الجغرافي.',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 25),
          TextFormField(
            controller: _nameController,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle(
              'الاسم الكامل الثلاثي',
              Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle('البريد الإلكتروني', Icons.email_outlined),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle(
              'رقم الهاتف للتواصل السريع',
              Icons.phone_in_talk_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _locationController,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle(
              'موقعك (المدينة، المنطقة)',
              Icons.location_on_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle('كلمة المرور', Icons.lock_outline_rounded)
                .copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible,
                    ),
                  ),
                ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _licenseNumberController,
            validator: (value) => value!.isEmpty ? 'رقم الترخيص مطلوب' : null,
            decoration: _inputStyle(
              'رقم الترخيص المهني (وزارة الصحة)',
              Icons.badge_rounded,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text(
                'لديك حساب بالفعل؟ ',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context); // العودة لشاشة تسجيل الدخول
                },
                child: const Text(
                  'سجل دخولك هنا',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- الخطوة 2: الاختصاص والخبرات ---
  Widget _buildSpecialtyStep() {
    return Form(
      key: _formKeyStep2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الاختصاص والخبرة 💼',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'حدد مجال عملك الدقيق وسنوات خبرتك المهنية.',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 25),
          DropdownButtonFormField<String>(
            decoration: _inputStyle(
              'الاختصاص التمريضي',
              Icons.local_hospital_rounded,
            ),
            value: _selectedSpecialty,
            isExpanded: true,
            items: _specialties.map((specialty) {
              return DropdownMenuItem(
                value: specialty,
                child: Text(
                  specialty,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) => setState(() => _selectedSpecialty = value),
            validator: (value) => value == null ? 'يرجى اختيار الاختصاص' : null,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _experienceYearsController,
            keyboardType: TextInputType.number,
            validator: (value) =>
                value!.isEmpty ? 'يرجى تحديد سنوات الخبرة' : null,
            decoration: _inputStyle(
              'سنوات الخبرة (أرقام فقط)',
              Icons.timeline_rounded,
            ),
          ),
        ],
      ),
    );
  }

  // --- الخطوة 3: التفضيلات والشهادات ---
  Widget _buildPreferencesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'نظام العمل والتوثيق 📋',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'حدد تفضيلات نظام العمل والتوفر لخدمات الرعاية.',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        const SizedBox(height: 25),

        // خيار الممرض المقيم
        Container(
          decoration: BoxDecoration(
            color: _isResidentNurse
                ? AppColors.primary.withOpacity(0.1)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isResidentNurse ? AppColors.primary : Colors.grey[300]!,
              width: 1.5,
            ),
          ),
          child: SwitchListTile(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.primary;
              }
              return Colors.grey;
            }),
            title: const Text(
              'متاح كممرض مقيم',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: const Text(
              'أستطيع الإقامة في منزل المريض لتقديم رعاية 24/7',
              style: TextStyle(fontSize: 13),
            ),
            value: _isResidentNurse,
            onChanged: (val) => setState(() => _isResidentNurse = val),
            secondary: Icon(
              Icons.home_work_rounded,
              color: _isResidentNurse ? AppColors.primary : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }

  // --- أزرار التحكم ---
  Widget _buildBottomNavButtons() {
    bool isLastStep = _currentStep == 2;
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _currentStep--),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'رجوع',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: () async {
                if (_currentStep == 0) {
                  if (_formKeyStep1.currentState!.validate())
                    setState(() => _currentStep++);
                } else if (_currentStep == 1) {
                  if (_formKeyStep2.currentState!.validate())
                    setState(() => _currentStep++);
                } else if (_currentStep == 2) {
                  // إنشاء حساب الممرض في Firebase Auth و Firestore
                  setState(() => _isLoading = true);

                  try {
                    // 1. إنشاء حساب Firebase Auth
                    final credential = await FirebaseAuth.instance
                        .createUserWithEmailAndPassword(
                      email: _emailController.text.trim(),
                      password: _passwordController.text,
                    );

                    if (credential.user == null) {
                      throw Exception('فشل إنشاء حساب Firebase Auth');
                    }

                    print('Firebase Auth user created: ${credential.user!.uid}');

                    // 2. حفظ بيانات الممرض في Firestore
                    final success = await _firestoreService.createNurseUser(
                      uid: credential.user!.uid,
                      name: _nameController.text,
                      email: _emailController.text.trim(),
                      phone: _phoneController.text,
                      location: _locationController.text,
                      specialty: _selectedSpecialty ?? 'تمريض عام',
                      experienceYears:
                          int.tryParse(_experienceYearsController.text) ?? 0,
                      isResidentNurse: _isResidentNurse,
                      licenseNumber: _licenseNumberController.text.trim(),
                    );

                    if (!success) {
                      throw Exception('فشل حفظ بيانات الممرض في Firestore');
                    }

                    // 3. مزامنة صامتة مع مجموعة nurses
                    await _firestoreService.syncNurseToNursesCollection(
                      uid: credential.user!.uid,
                      name: _nameController.text,
                      email: _emailController.text.trim(),
                      phone: _phoneController.text,
                      location: _locationController.text,
                      specialty: _selectedSpecialty ?? 'تمريض عام',
                      experienceYears:
                          int.tryParse(_experienceYearsController.text) ?? 0,
                      isResidentNurse: _isResidentNurse,
                      licenseNumber: _licenseNumberController.text.trim(),
                    );

                    // 4. مزامنة مع backend AI dataset ستتم بعد الموافقة فقط

                    // 5. إنشاء كائن المستخدم وتعيينه في AppDataService
                    final nurseUser = AppUser(
                      id: credential.user!.uid,
                      name: _nameController.text,
                      email: _emailController.text.trim(),
                      phone: _phoneController.text,
                      role: UserRole.nurse,
                      status: UserStatus.pending, // حالة انتظار الموافقة
                      createdAt: DateTime.now(),
                      location: _locationController.text,
                      specialty: _selectedSpecialty ?? 'تمريض عام',
                      experienceYears:
                          int.tryParse(_experienceYearsController.text) ?? 0,
                      isResidentNurse: _isResidentNurse,
                      certificateVerified: false, // لم يتم التوثيق بعد
                      licenseNumber: _licenseNumberController.text.trim(),
                      isVerified: false, // لم يتم التحقق من الترخيص بعد
                      verificationStatus: VerificationStatus.pending, // حالة التحقق معلقة
                    );

                    _appDataService.currentUser = nurseUser;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تم إنشاء حساب الممرض بنجاح! بانتظار موافقة المدير.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );

                    // الانتقال لشاشة انتظار الموافقة
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NurseApprovalWaitingScreen(),
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error creating nurse account: $e');
                    
                    // التحقق من نوع الخطأ وعرض رسالة مناسبة
                    String errorMessage = 'فشل إنشاء الحساب';
                    
                    if (e is FirebaseAuthException) {
                      switch (e.code) {
                        case 'email-already-in-use':
                          errorMessage = 'البريد الإلكتروني مستخدم بالفعل، يرجى تسجيل الدخول';
                          break;
                        case 'weak-password':
                          errorMessage = 'كلمة المرور ضعيفة جداً';
                          break;
                        case 'invalid-email':
                          errorMessage = 'البريد الإلكتروني غير صالح';
                          break;
                        default:
                          errorMessage = 'فشل إنشاء الحساب: ${e.message}';
                      }
                    } else {
                      errorMessage = 'فشل إنشاء الحساب: $e';
                    }
                    
                    // عرض رسالة الخطأ فقط إذا كان الـ widget لا يزال mounted
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    
                    // في حالة الخطأ، حذف مستخدم Firebase Auth إذا تم إنشاؤه
                    try {
                      await FirebaseAuth.instance.currentUser?.delete();
                    } catch (deleteError) {
                      print('Error deleting Firebase Auth user: $deleteError');
                    }
                  } finally {
                    // التحقق من أن الـ widget لا يزال mounted قبل setState
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isLastStep ? 'إرسال الطلب' : 'متابعة',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // دالة تصميم الحقول
  // ==========================================
  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
