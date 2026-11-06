import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/user_model.dart';

class BookingRequestScreen extends StatefulWidget {
  final AppUser nurse;
  final Map<String, dynamic>? patientData;

  const BookingRequestScreen({
    super.key,
    required this.nurse,
    this.patientData,
  });

  @override
  State<BookingRequestScreen> createState() => _BookingRequestScreenState();
}

class _BookingRequestScreenState extends State<BookingRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  
  final _descriptionController = TextEditingController();
  DateTime? _selectedDate;
  bool _needsResidentNurse = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with patient data if available
    if (widget.patientData != null) {
      _descriptionController.text = widget.patientData!['medicalDescription'] ?? '';
      _needsResidentNurse = widget.patientData!['needsResidentNurse'] ?? false;
      // Set the selected date if provided from patient data
      if (widget.patientData!['selectedDate'] != null) {
        _selectedDate = widget.patientData!['selectedDate'] as DateTime?;
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    try {
      if (!mounted) return;
      
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        locale: const Locale('ar', 'SA'),
      );
      
      if (mounted && picked != null) {
        setState(() => _selectedDate = picked);
      }
    } catch (e) {
      debugPrint('Error selecting date: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ في اختيار التاريخ. يرجى المحاولة مرة أخرى.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submitBookingRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // التحقق من وجود التاريخ المطلوب
    if (_selectedDate == null) {
      _showErrorSnackBar('يرجى اختيار التاريخ المطلوب');
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      _showErrorSnackBar('يجب تسجيل الدخول أولاً');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Create booking request with date only (no time)
      final bookingRequest = {
        'patientId': user.uid,
        'patientName': widget.patientData?['name'] ?? 'مريض',
        'patientPhone': widget.patientData?['phone'] ?? '',
        'nurseId': widget.nurse.id,
        'nurseName': widget.nurse.name,
        'nursePhone': widget.nurse.phone,
        'nurseSpecialty': widget.nurse.specialty,
        'description': _descriptionController.text.trim(),
        'location': widget.patientData?['location'] ?? widget.nurse.location ?? 'غير محدد',
        'needsResidentNurse': _needsResidentNurse,
        'status': 'pending',
        'requestedDate': _safeCreateTimestamp(_selectedDate!),
        'requestedTime': null, // Can be added later for time selection
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'tags': widget.patientData?['medicalTags'] ?? [],
      };

      await _firestore.collection('care_requests').add(bookingRequest);

      if (mounted) {
        _showSuccessSnackBar();
        Navigator.pop(context);
      }
    } on FirebaseException catch (e) {
      debugPrint('=== خطأ Firestore في طلب الحجز ===');
      debugPrint('الكود: ${e.code}');
      debugPrint('الرسالة: ${e.message}');
      
      String errorMessage = 'فشل إرسال الطلب';
      
      switch (e.code) {
        case 'permission-denied':
          errorMessage = 'ليس لديك صلاحية لإرسال هذا الطلب. يرجى التحقق من تسجيل الدخول.';
          break;
        case 'not-found':
          errorMessage = 'لم يتم العثور على البيانات المطلوبة. يرجى المحاولة مرة أخرى.';
          break;
        case 'already-exists':
          errorMessage = 'لديك طلب نشط بالفعل. يرجى التحقق من طلباتك السابقة.';
          break;
        case 'unavailable':
          errorMessage = 'الخدمة غير متاحة حالياً. يرجى المحاولة لاحقاً.';
          break;
        case 'deadline-exceeded':
          errorMessage = 'انتهت مهلة الاتصال. يرجى التحقق من اتصال الإنترنت والمحاولة مرة أخرى.';
          break;
        default:
          errorMessage = 'حدث خطأ أثناء إرسال الطلب: ${e.message ?? "خطأ غير معروف"}';
      }
      
      if (mounted) {
        _showErrorSnackBar(errorMessage);
      }
    } catch (e) {
      debugPrint('=== خطأ عام في طلب الحجز ===');
      debugPrint('التفاصيل: ${e.toString()}');
      
      String errorMessage = 'حدث خطأ غير متوقع';
      
      if (e.toString().contains('Network')) {
        errorMessage = 'خطأ في الاتصال بالإنترنت. يرجى التحقق من اتصالك والمحاولة مرة أخرى.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'انتهت مهلة العملية. يرجى المحاولة مرة أخرى.';
      } else {
        errorMessage = 'حدث خطأ: ${e.toString()}';
      }
      
      if (mounted) {
        _showErrorSnackBar(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Timestamp _safeCreateTimestamp(DateTime date) {
    try {
      // Create timestamp with date only (midnight)
      return Timestamp.fromDate(
        DateTime(date.year, date.month, date.day),
      );
    } catch (e) {
      debugPrint('Error creating timestamp: $e');
      // Fallback to current time if date creation fails
      return Timestamp.fromDate(DateTime.now());
    }
  }

  void _showSuccessSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('تم إرسال طلب الحجز بنجاح'),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
              ),
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

  String _formatDate(DateTime date) {
    try {
      final formatter = DateFormat('dd/MM/yyyy', 'ar');
      return formatter.format(date);
    } catch (e) {
      debugPrint('Error formatting date: $e');
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'طلب حجز ممرض',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNurseInfoCard(),
                const SizedBox(height: 24),
                _buildDateSelector(),
                const SizedBox(height: 16),
                _buildDescriptionField(),
                const SizedBox(height: 16),
                _buildResidentNurseToggle(),
                const SizedBox(height: 24),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildNurseInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(
              widget.nurse.name.isNotEmpty ? widget.nurse.name[0] : 'م',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.nurse.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.nurse.specialty ?? 'ممرض عام',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.nurse.location ?? 'غير محدد',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final datePreSelected = widget.patientData?.containsKey('selectedDate') == true && widget.patientData!['selectedDate'] != null;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'التاريخ المطلوب',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              if (datePreSelected) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'تم الاختيار',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: (_isLoading || datePreSelected) ? null : _selectDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: datePreSelected ? Colors.green : Colors.grey[300]!,
                  width: datePreSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: datePreSelected ? Colors.green.withOpacity(0.05) : Colors.white,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today, 
                    color: datePreSelected ? Colors.green : AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedDate != null
                          ? _formatDate(_selectedDate!)
                          : 'اختر التاريخ',
                      style: TextStyle(
                        color: _selectedDate != null ? AppColors.textDark : Colors.grey[600],
                        fontWeight: datePreSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (!datePreSelected)
                    Icon(Icons.arrow_back_ios, color: Colors.grey[400]),
                  if (datePreSelected)
                    const Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'وصف الحالة (اختياري)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'اكتب وصفاً موجزاً لحالتك الصحية...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResidentNurseToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: SwitchListTile(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.grey;
        }),
        title: const Text(
          'أحتاج ممرض مقيم',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: const Text(
          'الممرض المقيم يقيم في منزلك لتقديم رعاية 24/7',
          style: TextStyle(fontSize: 13),
        ),
        value: _needsResidentNurse,
        onChanged: (val) => setState(() => _needsResidentNurse = val),
        secondary: Icon(
          Icons.home_work_rounded,
          color: _needsResidentNurse ? AppColors.primary : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: _isLoading ? null : _submitBookingRequest,
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'إرسال طلب الحجز',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}