import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'patient_home_screen.dart';
import 'nurse_signup_view.dart';
import '../services/firestore_service.dart';
import '../services/app_data_service.dart';
import '../models/user_model.dart';

class PatientSignUpView extends StatefulWidget {
  const PatientSignUpView({super.key});

  @override
  State<PatientSignUpView> createState() => _PatientSignUpViewState();
}

class _PatientSignUpViewState extends State<PatientSignUpView> {
  // --- ميزة راحة العين ---
  bool _isEyeComfortMode = false;

  // --- التحكم بالواجهات ---
  bool isLogin = true;
  int _currentStep = 0;
  bool _isLoading = false;
  int _totalSteps = 2; // تغيير من 3 إلى 2

  @override
  void initState() {
    super.initState();
    // Initialize controllers for each category's "other" field
    for (var category in _medicalCategories) {
      _otherDiseaseControllers[category['title']] = TextEditingController();
      _allSelectedConditions[category['title']] = [];
    }
  }

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _diagnosisController.dispose();
    // Dispose all category controllers
    for (var controller in _otherDiseaseControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // --- الخدمات ---
  final _firestoreService = FirestoreService.instance;
  final _appDataService = AppDataService.instance;

  // --- متغيرات شاشة تسجيل الدخول ---
  final _loginFormKey = GlobalKey<FormState>();
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _isPasswordVisible = false;

  // --- متغيرات الخطوة 1: البيانات الشخصية ---
  final _formKeyStep1 = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();

  // --- متغيرات الخطوة 2: الأقسام الطبية ---
  String? _selectedCategory;
  final List<String> _selectedSubDiseases = [];
  final Map<String, List<String>> _allSelectedConditions = {}; // Store all conditions across all categories
  final Map<String, TextEditingController> _otherDiseaseControllers = {}; // Store "other" text fields for each category

  final List<Map<String, dynamic>> _medicalCategories = [
    {
      'title': 'الأورام والسرطان',
      'icon': Icons.flare_rounded,
      'color': Colors.pinkAccent,
      'subDiseases': [
        'سرطان الثدي',
        'سرطان الرئة',
        'سرطان القولون',
        'سرطان الدم (اللوكيميا)',
        'سرطان البروستاتا',
      ],
    },
    {
      'title': 'الحالات الطارئة والإصابات',
      'icon': Icons.emergency_rounded,
      'color': Colors.deepOrangeAccent,
      'subDiseases': [
        'حوادث السير (إصابات متعددة)',
        'عيوب خلقية (تشوهات)',
        'إصابات الحروق',
        'كسور مضاعفة',
        'إصابات ما بعد العمليات الجراحية',
      ],
    },
    {
      'title': 'أمراض القلب والشرايين',
      'icon': Icons.favorite_rounded,
      'color': Colors.redAccent,
      'subDiseases': [
        'ارتفاع ضغط الدم',
        'مرض الشريان التاجي',
        'عدم انتظام ضربات القلب',
        'قصور القلب',
        'أمراض صمامات القلب',
      ],
    },
    {
      'title': 'الأمراض العصبية',
      'icon': Icons.psychology_rounded,
      'color': Colors.purpleAccent,
      'subDiseases': [
        'جلطة دماغية / تاريخ جلطات',
        'مرض باركنسون',
        'التصلب اللويحي (MS)',
        'شلل (دائم أو مؤقت)',
        'صرع / تشنجات',
      ],
    },
    {
      'title': 'أمراض الكلى وغسيل الكلى',
      'icon': Icons.water_drop_rounded,
      'color': Colors.blueAccent,
      'subDiseases': [
        'مرض الكلى المزمن (CKD)',
        'مريض غسيل كلى',
        'حصوات الكلى (متكررة)',
      ],
    },
    {
      'title': 'أمراض العظام والحركة',
      'icon': Icons.accessible_forward_rounded,
      'color': Colors.orangeAccent,
      'subDiseases': [
        'خشونة المفاصل الشديدة',
        'إصابة الحبل الشوكي',
        'بتر أطراف',
        'إعاقة حركية',
      ],
    },
    {
      'title': 'أمراض الجهاز التنفسي',
      'icon': Icons.air_rounded,
      'color': Colors.teal,
      'subDiseases': [
        'ربو مزمن شديد',
        'مرض الانسداد الرئوي المزمن (COPD)',
        'تليف رئوي',
      ],
    },
    {
      'title': 'أمراض العيون',
      'icon': Icons.visibility_rounded,
      'color': Colors.indigoAccent,
      'subDiseases': [
        'اعتلال الشبكية',
        'المياه الزرقاء (الجلوكوما)',
        'ضعف بصر شديد',
      ],
    },
  ];

  // --- متغيرات الخطوة 2: التشخيص ---
  final _formKeyStep3 = GlobalKey<FormState>();
  final _diagnosisController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: _isEyeComfortMode
          ? const ColorFilter.mode(Color(0xFFFFF3E0), BlendMode.multiply)
          : const ColorFilter.mode(Colors.transparent, BlendMode.srcOver),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              children: [
                _buildCustomAppBar(),
                Expanded(
                  child: isLogin ? _buildLoginScreen() : _buildSignUpWizard(),
                ),
              ],
            ),
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
              if (!isLogin && _currentStep > 0) {
                setState(() => _currentStep--);
              } else if (!isLogin && _currentStep == 0) {
                setState(() => isLogin = true);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 8),
          Text(
            isLogin ? 'تسجيل الدخول' : 'الخطوة ${_currentStep + 1} من $_totalSteps',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _isEyeComfortMode
                  ? Icons.remove_red_eye
                  : Icons.remove_red_eye_outlined,
              color: _isEyeComfortMode ? Colors.amber[700] : Colors.grey,
              size: 28,
            ),
            onPressed: () {
              setState(() => _isEyeComfortMode = !_isEyeComfortMode);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _isEyeComfortMode
                        ? 'تم تفعيل وضع راحة العين'
                        : 'تم إيقاف وضع راحة العين',
                  ),
                  backgroundColor: _isEyeComfortMode
                      ? Colors.orange
                      : Colors.black87,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 1. شاشة تسجيل الدخول
  // ==========================================
  Widget _buildLoginScreen() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: 30.0,
        right: 30.0,
        top: 10.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20.0,
      ),
      child: Form(
        key: _loginFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const Icon(
              Icons.person_pin_rounded,
              size: 70,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'أهلاً بك مجدداً',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'سجل دخولك لمتابعة حالتك الصحية',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 30),

            TextFormField(
              controller: _loginEmailController,
              keyboardType: TextInputType.emailAddress,
              validator: (value) =>
                  value!.isEmpty ? 'يرجى إدخال البريد الإلكتروني' : null,
              decoration: _inputStyle(
                'البريد الإلكتروني',
                Icons.email_outlined,
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _loginPasswordController,
              obscureText: !_isPasswordVisible,
              validator: (value) =>
                  value!.isEmpty ? 'يرجى إدخال كلمة المرور' : null,
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
            const SizedBox(height: 30),

            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      if (_loginFormKey.currentState!.validate()) {
                        setState(() => _isLoading = true);

                        try {
                          // Trim both email and password to remove any accidental spaces
                          final trimmedEmail = _loginEmailController.text.trim();
                          final trimmedPassword = _loginPasswordController.text.trim();

                          final authenticatedUser = await _firestoreService.authenticateUser(
                            trimmedEmail,
                            trimmedPassword,
                            UserRole.patient,
                          );

                          setState(() => _isLoading = false);

                          if (authenticatedUser != null) {
                            // تسجيل الدخول ناجح
                            _appDataService.currentUser = authenticatedUser;

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'تم تسجيل الدخول بنجاح',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  duration: const Duration(seconds: 2),
                                ),
                              );

                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (context) => const PatientHomeScreen()),
                              );
                            }
                          } else {
                            // فشل تسجيل الدخول - رسالة عامة
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'فشل تسجيل الدخول: البريد الإلكتروني أو كلمة المرور غير صحيحة',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                            }
                          }
                        } on FirebaseAuthException catch (e) {
                          setState(() => _isLoading = false);

                          // Handle Firebase Auth specific errors
                          String errorMessage = 'فشل تسجيل الدخول';

                          switch (e.code) {
                            case 'user-not-found':
                              errorMessage = 'المستخدم غير موجود. يرجى التسجيل أولاً.';
                              break;
                            case 'wrong-password':
                              errorMessage = 'كلمة المرور غير صحيحة.';
                              break;
                            case 'invalid-email':
                              errorMessage = 'البريد الإلكتروني غير صالح.';
                              break;
                            case 'user-disabled':
                              errorMessage = 'تم تعطيل هذا الحساب.';
                              break;
                            case 'too-many-requests':
                              errorMessage = 'محاولات كثيرة. يرجى المحاولة لاحقاً.';
                              break;
                            default:
                              errorMessage = 'خطأ: ${e.message ?? "حدث خطأ غير معروف"}';
                          }

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  errorMessage,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() => _isLoading = false);

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'حدث خطأ غير متوقع: ${e.toString()}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
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
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    "ليس لديك حساب؟ ",
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      isLogin = false;
                      _currentStep = 0;
                    });
                  },
                  child: const Text(
                    'إنشاء حساب جديد',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // --- الخيار المضاف للانتقال لشاشة تسجيل الممرضين ---
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    "هل أنت كادر طبي؟ ",
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NurseSignUpView(),
                      ),
                    );
                  },
                  child: const Text(
                    'التسجيل كـ ممرض',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 2. معالج إنشاء الحساب (SignUp Wizard)
  // ==========================================
  Widget _buildSignUpWizard() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Row(
            children: List.generate(_totalSteps, (index) {
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
        return _buildPersonalDetailsStep();
      case 1:
        return _buildMedicalConditionStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- الخطوة 1: البيانات الشخصية ---
  Widget _buildPersonalDetailsStep() {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إنشاء حساب جديد 🌟',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'يرجى إدخال معلوماتك الأساسية لإنشاء ملف المريض.',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 25),

          TextFormField(
            controller: _nameController,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle(
              'الاسم الكامل',
              Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value!.isEmpty) {
                return 'هذا الحقل مطلوب';
              }
              final trimmedEmail = value.trim();
              if (!trimmedEmail.contains('@') || !trimmedEmail.contains('.')) {
                return 'يرجى إدخال بريد إلكتروني صالح';
              }
              return null;
            },
            decoration: _inputStyle('البريد الإلكتروني', Icons.email_outlined),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle('رقم الهاتف', Icons.phone_android_outlined),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle('العمر', Icons.calendar_today_rounded),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _addressController,
            maxLines: 2,
            validator: (value) => value!.isEmpty ? 'هذا الحقل مطلوب' : null,
            decoration: _inputStyle(
              'عنوان السكن بالتفصيل',
              Icons.location_on_rounded,
            ),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            validator: (value) {
              if (value!.isEmpty) {
                return 'هذا الحقل مطلوب';
              }
              if (value.length < 6) {
                return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
              }
              return null;
            },
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
        ],
      ),
    );
  }

  // --- الخطوة 2: الأقسام الطبية ---
  Widget _buildMedicalConditionStep() {
    return Form(
      key: _formKeyStep3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'التاريخ الطبي 🩺',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اختر حالتك الرئيسية وعلم على التفاصيل، أو أضف مرضك يدوياً.',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 24),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _medicalCategories.length,
            itemBuilder: (context, index) {
              final category = _medicalCategories[index];
              bool isSelected = _selectedCategory == category['title'];
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ExpansionTile(
                  initiallyExpanded: isSelected,
                  onExpansionChanged: (expanded) {
                    if (expanded) {
                      setState(() {
                        _selectedCategory = category['title'];

                        if (_selectedCategory == 'الأمراض العصبية' ||
                            _selectedCategory == 'أمراض العيون') {
                          _isEyeComfortMode = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'تم تفعيل وضع راحة العين تلقائياً لحالتك',
                              ),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      });
                    }
                  },
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: category['color'].withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      category['icon'],
                      color: category['color'],
                      size: 26,
                    ),
                  ),
                  title: Text(
                    category['title'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textDark,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(color: Colors.grey[200]),
                          ...category['subDiseases'].map<Widget>((subDisease) {
                            final categoryTitle = category['title'];
                            final categoryConditions = _allSelectedConditions[categoryTitle] ?? [];
                            bool isSubSelected = categoryConditions.contains(subDisease);
                            return CheckboxListTile(
                              activeColor: AppColors.primary,
                              title: Text(
                                subDisease,
                                style: const TextStyle(fontSize: 14),
                              ),
                              value: isSubSelected,
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    _allSelectedConditions[categoryTitle]!.add(subDisease);
                                  } else {
                                    _allSelectedConditions[categoryTitle]!.remove(subDisease);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            );
                          }).toList(),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _otherDiseaseControllers[category['title']],
                            decoration: InputDecoration(
                              hintText: 'أمراض أخرى (يرجى التحديد)...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[400],
                              ),
                              prefixIcon: const Icon(
                                Icons.add_circle_outline,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          
          // إضافة حقل التشخيص في الخطوة الثانية
          TextFormField(
            controller: _diagnosisController,
            maxLines: 4,
            validator: (value) =>
                value!.isEmpty ? 'يرجى كتابة لمحة عن تشخيصك الحالي' : null,
            decoration: _inputStyle('أحدث تشخيص للطبيب / ملاحظات', null)
                .copyWith(
                  hintText: 'اكتب أي تاريخ طبي مهم أو احتياجات خاصة هنا...',
                ),
          ),
        ],
      ),
    );
  }



  // --- أزرار التحكم ---
  Widget _buildBottomNavButtons() {
    bool isLastStep = _currentStep == _totalSteps - 1;
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
              onPressed: _isLoading ? null : () async {
                if (_currentStep == 0) {
                  if (_formKeyStep1.currentState!.validate()) {
                    setState(() => _currentStep++);
                  }
                } else if (_currentStep == 1) {
                  // Check if at least one condition is selected across all categories
                  bool hasAnySelection = _allSelectedConditions.values.any((conditions) => conditions.isNotEmpty);
                  
                  if (!hasAnySelection) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'يرجى اختيار حالة طبية واحدة على الأقل قبل المتابعة.',
                        ),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  } else if (_formKeyStep3.currentState!.validate()) {
                    await _submitPatientRegistration();
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      isLastStep ? 'إنهاء الإعداد' : 'متابعة',
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
  // دالة تسجيل المريض في Firebase
  // ==========================================
  Future<void> _submitPatientRegistration() async {
    setState(() => _isLoading = true);

    try {
      // 1. Client-side validation
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      
      debugPrint('=== بدء عملية تسجيل المريض ===');
      debugPrint('البريد الإلكتروني: $email');
      debugPrint('طول كلمة المرور: ${password.length}');

      if (password.length < 6) {
        throw Exception('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      }

      if (!email.contains('@') || !email.contains('.')) {
        throw Exception('البريد الإلكتروني غير صالح');
      }

      // 2. Collect all medical conditions from all categories
      List<String> allMedicalConditions = [];
      
      // Add all checked conditions from all categories
      for (var categoryConditions in _allSelectedConditions.values) {
        allMedicalConditions.addAll(categoryConditions);
      }
      
      // Add custom "other" conditions from text fields
      for (var entry in _otherDiseaseControllers.entries) {
        final otherText = entry.value.text.trim();
        if (otherText.isNotEmpty) {
          allMedicalConditions.add(otherText);
        }
      }

      debugPrint('عدد الحالات الطبية المجمعة: ${allMedicalConditions.length}');

      // 3. Create Firebase Auth account
      debugPrint('جاري إنشاء حساب Firebase Auth...');
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('فشل إنشاء حساب Firebase Auth: المستخدم فارغ');
      }

      debugPrint('تم إنشاء حساب Firebase Auth بنجاح');
      debugPrint('User ID: ${credential.user!.uid}');

      // 4. Create patient profile in Firestore (patients collection)
      debugPrint('جاري حفظ بيانات المريض في Firestore...');
      
      final patientData = {
        'name': _nameController.text.trim(),
        'email': email,
        'phone': _phoneController.text.trim(),
        'role': 'patient',
        'status': 'active',
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'location': _addressController.text.trim(),
        'medicalCategory': _selectedCategory,
        'medicalTags': allMedicalConditions,
        'medicalDescription': _diagnosisController.text.trim(),
      };

      await FirebaseFirestore.instance
          .collection('patients')
          .doc(credential.user!.uid)
          .set(patientData);

      debugPrint('تم حفظ بيانات المريض في Firestore بنجاح');

      // 5. Create AppUser object for app state
      final patientUser = AppUser(
        id: credential.user!.uid,
        name: _nameController.text.trim(),
        email: email,
        phone: _phoneController.text.trim(),
        role: UserRole.patient,
        status: UserStatus.active,
        createdAt: DateTime.now(),
        location: _addressController.text.trim(),
        medicalCategory: _selectedCategory,
        medicalTags: allMedicalConditions,
        medicalDescription: _diagnosisController.text.trim(),
      );

      // 6. Update app data service and navigate
      _appDataService.currentUser = patientUser;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء الحساب بنجاح!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const PatientHomeScreen(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('=== خطأ في Firebase Auth ===');
      debugPrint('الكود: ${e.code}');
      debugPrint('الرسالة: ${e.message}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ Firebase: ${e.message ?? "خطأ غير معروف"}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('=== خطأ في Firestore ===');
      debugPrint('الكود: ${e.code}');
      debugPrint('الرسالة: ${e.message}');
      
      // If Firestore fails, try to delete the Auth account
      try {
        await FirebaseAuth.instance.currentUser?.delete();
        debugPrint('تم حذف حساب Auth بسبب فشل Firestore');
      } catch (deleteError) {
        debugPrint('فشل حذف حساب Auth: $deleteError');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ Firestore: ${e.message ?? "خطأ غير معروف"}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint('=== خطأ عام ===');
      debugPrint('التفاصيل: ${e.toString()}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      debugPrint('=== انتهت عملية تسجيل المريض ===');
    }
  }

  // ==========================================
  // دالة مساعدة لتصميم الحقول
  // ==========================================
  InputDecoration _inputStyle(String label, IconData? icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: AppColors.primary) : null,
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
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }
}
