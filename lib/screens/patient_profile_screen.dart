import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../services/app_data_service.dart';
import '../models/user_model.dart';

class PatientProfileScreen extends StatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _appDataService = AppDataService.instance;
  
  // Form controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  // State variables
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  
  // Patient data
  String? _medicalCategory;
  List<String> _medicalTags = [];
  String? _selectedCategory;
  
  // Medical categories (same as registration)
  final List<Map<String, dynamic>> _medicalCategories = [
    {
      'title': 'الأورام والسرطان',
      'icon': Icons.flare_rounded,
      'color': Colors.pinkAccent,
      'subDiseases': ['سرطان الثدي', 'سرطان الرئة', 'سرطان القولون', 'سرطان الدم (اللوكيميا)', 'سرطان البروستاتا'],
    },
    {
      'title': 'الحالات الطارئة والإصابات',
      'icon': Icons.emergency_rounded,
      'color': Colors.deepOrangeAccent,
      'subDiseases': ['حوادث السير', 'عيوب خلقية', 'إصابات الحروق', 'كسور مضاعفة', 'إصابات ما بعد العمليات'],
    },
    {
      'title': 'أمراض القلب والشرايين',
      'icon': Icons.favorite_rounded,
      'color': Colors.redAccent,
      'subDiseases': ['ارتفاع ضغط الدم', 'مرض الشريان التاجي', 'عدم انتظام ضربات القلب', 'قصور القلب', 'أمراض صمامات القلب'],
    },
    {
      'title': 'الأمراض العصبية',
      'icon': Icons.psychology_rounded,
      'color': Colors.purpleAccent,
      'subDiseases': ['جلطة دماغية', 'مرض باركنسون', 'التصلب اللويحي (MS)', 'شلل', 'صرع / تشنجات'],
    },
    {
      'title': 'أمراض الكلى وغسيل الكلى',
      'icon': Icons.water_drop_rounded,
      'color': Colors.blueAccent,
      'subDiseases': ['مرض الكلى المزمن (CKD)', 'مريض غسيل كلى', 'حصوات الكلى'],
    },
    {
      'title': 'أمراض العظام والحركة',
      'icon': Icons.accessible_forward_rounded,
      'color': Colors.orangeAccent,
      'subDiseases': ['خشونة المفاصل الشديدة', 'إصابة الحبل الشوكي', 'بتر أطراف', 'إعاقة حركية'],
    },
    {
      'title': 'أمراض الجهاز التنفسي',
      'icon': Icons.air_rounded,
      'color': Colors.teal,
      'subDiseases': ['ربو مزمن شديد', 'مرض الانسداد الرئوي المزمن (COPD)', 'تليف رئوي'],
    },
    {
      'title': 'أمراض العيون',
      'icon': Icons.visibility_rounded,
      'color': Colors.indigoAccent,
      'subDiseases': ['اعتلال الشبكية', 'المياه الزرقاء (الجلوكوما)', 'ضعف بصر شديد'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadPatientData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadPatientData() async {
    setState(() => _isLoading = true);
    
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _firestore.collection('patients').doc(user.uid).get();
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        setState(() {
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _addressController.text = data['location'] ?? '';
          _descriptionController.text = data['medicalDescription'] ?? '';
          _medicalCategory = data['medicalCategory'];
          _medicalTags = List<String>.from(data['medicalTags'] ?? []);
          _selectedCategory = data['medicalCategory'];
          
          // Update app data service
          _appDataService.currentUser = AppUser(
            id: user.uid,
            name: data['name'] ?? '',
            email: data['email'] ?? '',
            phone: data['phone'] ?? '',
            role: UserRole.patient,
            status: UserStatus.active,
            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            location: data['location'],
            medicalCategory: data['medicalCategory'],
            medicalTags: List<String>.from(data['medicalTags'] ?? []),
            medicalDescription: data['medicalDescription'],
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تحميل البيانات: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePatientData() async {
    setState(() => _isSaving = true);
    
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('patients').doc(user.uid).update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'location': _addressController.text.trim(),
        'medicalDescription': _descriptionController.text.trim(),
        'medicalCategory': _selectedCategory,
        'medicalTags': _medicalTags,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Update app data service
      _appDataService.currentUser = AppUser(
        id: user.uid,
        name: _nameController.text.trim(),
        email: _appDataService.currentUser?.email ?? '',
        phone: _phoneController.text.trim(),
        role: UserRole.patient,
        status: UserStatus.active,
        createdAt: _appDataService.currentUser?.createdAt ?? DateTime.now(),
        location: _addressController.text.trim(),
        medicalCategory: _selectedCategory,
        medicalTags: _medicalTags,
        medicalDescription: _descriptionController.text.trim(),
      );

      setState(() => _isEditing = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث البيانات بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في حفظ البيانات: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSaving = false);
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
                child: _isLoading
                    ? _buildLoadingState()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildProfileHeader(),
                            const SizedBox(height: 24),
                            _buildPersonalInfoSection(),
                            const SizedBox(height: 24),
                            _buildMedicalInfoSection(),
                            const SizedBox(height: 24),
                            _buildLogoutButton(),
                            const SizedBox(height: 24),
                            if (_isEditing) _buildSaveButton(),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'ملفي الشخصي',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (!_isLoading)
            IconButton(
              icon: Icon(
                _isEditing ? Icons.close : Icons.edit_outlined,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() => _isEditing = !_isEditing);
                if (!_isEditing) {
                  // Revert changes
                  _loadPatientData();
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final currentUser = _appDataService.currentUser;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 35,
              backgroundColor: Colors.transparent,
              child: Text(
                currentUser?.name.isNotEmpty == true ? currentUser!.name[0] : 'م',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentUser?.name ?? 'غير معروف',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currentUser?.email ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('المعلومات الشخصية'),
        const SizedBox(height: 12),
        Container(
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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildInfoField(
                'الاسم الكامل',
                _nameController,
                Icons.person_outline_rounded,
                enabled: _isEditing,
              ),
              const SizedBox(height: 16),
              _buildInfoField(
                'رقم الهاتف',
                _phoneController,
                Icons.phone_android_outlined,
                keyboardType: TextInputType.phone,
                enabled: _isEditing,
              ),
              const SizedBox(height: 16),
              _buildInfoField(
                'عنوان السكن',
                _addressController,
                Icons.location_on_rounded,
                maxLines: 2,
                enabled: _isEditing,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMedicalInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('المعلومات الطبية'),
        const SizedBox(height: 12),
        Container(
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Medical Category
              _buildMedicalCategorySelector(),
              const SizedBox(height: 16),
              
              // Medical Tags
              _buildMedicalTagsSection(),
              const SizedBox(height: 16),
              
              // Medical Description
              _buildInfoField(
                'الوصف الطبي',
                _descriptionController,
                Icons.description_outlined,
                maxLines: 4,
                enabled: _isEditing,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textDark,
      ),
    );
  }

  Widget _buildInfoField(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: TextStyle(
            color: enabled ? AppColors.textDark : Colors.grey[600],
            fontSize: 14,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled ? AppColors.background : Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMedicalCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.medical_services_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'الفئة الطبية',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isEditing)
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: _medicalCategories.map((category) {
              return DropdownMenuItem<String>(
                value: category['title'] as String,
                child: Row(
                  children: [
                    Icon(
                      category['icon'] as IconData,
                      size: 20,
                      color: category['color'] as Color,
                    ),
                    const SizedBox(width: 12),
                    Text(category['title'] as String),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedCategory = value;
                // Reset medical tags when category changes
                _medicalTags = [];
              });
            },
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (_selectedCategory != null) ...[
                  Icon(
                    _medicalCategories.firstWhere(
                      (cat) => cat['title'] == _selectedCategory,
                    )['icon'] as IconData,
                    size: 20,
                    color: _medicalCategories.firstWhere(
                      (cat) => cat['title'] == _selectedCategory,
                    )['color'] as Color,
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  _selectedCategory ?? 'غير محدد',
                  style: TextStyle(
                    color: _selectedCategory != null ? AppColors.textDark : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMedicalTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_hospital_outlined, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'الحالات المرضية',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isEditing && _selectedCategory != null)
          _buildEditableTags()
        else
          _buildReadOnlyTags(),
      ],
    );
  }

  Widget _buildReadOnlyTags() {
    if (_medicalTags.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'لا توجد حالات محددة',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _medicalTags.map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Text(
            tag,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEditableTags() {
    final category = _medicalCategories.firstWhere(
      (cat) => cat['title'] == _selectedCategory,
      orElse: () => _medicalCategories[0],
    );
    
    final subDiseases = category['subDiseases'] as List<String>;

    return Column(
      children: subDiseases.map((disease) {
        final isSelected = _medicalTags.contains(disease);
        return CheckboxListTile(
          title: Text(
            disease,
            style: const TextStyle(fontSize: 13),
          ),
          value: isSelected,
          activeColor: AppColors.primary,
          onChanged: (bool? value) {
            setState(() {
              if (value == true) {
                _medicalTags.add(disease);
              } else {
                _medicalTags.remove(disease);
              }
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        );
      }).toList(),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _savePatientData,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'حفظ التغييرات',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text(
          'تسجيل الخروج',
          style: TextStyle(
            fontSize: 16,
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'جاري تحميل البيانات...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}