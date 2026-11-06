import 'package:flutter/material.dart';
import '../theme.dart';
import '../models/medication_model.dart';
import '../services/medication_service.dart';

class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({super.key});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _medicationService = MedicationService();

  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _durationController = TextEditingController(text: '7');

  MedicationType _selectedType = MedicationType.tablet;
  MedicationFrequency _selectedFrequency = MedicationFrequency.onceDaily;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));

  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'إضافة دواء',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('معلومات الدواء'),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _nameController,
                  label: 'اسم الدواء',
                  icon: Icons.medication,
                  validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _dosageController,
                  label: 'الجرعة',
                  icon: Icons.science,
                  validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 16),
                _buildTypeSelector(),
                const SizedBox(height: 16),
                _buildFrequencySelector(),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _instructionsController,
                  label: 'تعليمات إضافية',
                  icon: Icons.info_outline,
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('الجدول الزمني'),
                const SizedBox(height: 16),
                _buildDateSelector('تاريخ البدء', _startDate, (date) {
                  setState(() => _startDate = date);
                }),
                const SizedBox(height: 16),
                _buildDurationInput(),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveMedication,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                            'حفظ الدواء',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textDark,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'نوع الدواء',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<MedicationType>(
          initialValue: _selectedType,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          items: MedicationType.values.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Row(
                children: [
                  Icon(type.typeIcon, size: 20, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text(type.typeDisplay),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedType = value!);
          },
        ),
      ],
    );
  }

  Widget _buildFrequencySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'التكرار',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<MedicationFrequency>(
          initialValue: _selectedFrequency,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          items: MedicationFrequency.values.map((freq) {
            return DropdownMenuItem(
              value: freq,
              child: Text(freq.frequencyDisplay),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedFrequency = value!);
          },
        ),
      ],
    );
  }

  Widget _buildDateSelector(String label, DateTime date, Function(DateTime) onDateSelected) {
    return InkWell(
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (selected != null) {
          onDateSelected(selected);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(
              '$label: ${date.day}/${date.month}/${date.year}',
              style: const TextStyle(fontSize: 14),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationInput() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'مدة العلاج (أيام)',
              prefixIcon: const Icon(Icons.access_time, color: AppColors.primary),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (v) {
              if (v!.isEmpty) return 'مطلوب';
              final days = int.tryParse(v);
              if (days == null || days! <= 0) return 'قيمة غير صحيحة';
              return null;
            },
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _endDate = _startDate.add(Duration(days: int.parse(_durationController.text ?? '7')));
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
          child: const Text('حساب'),
        ),
      ],
    );
  }

  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final scheduledTimes = _calculateScheduledTimes(_selectedFrequency);

      final medication = Medication(
        id: '', // Will be assigned by Firestore
        name: _nameController.text.trim(),
        dosage: _dosageController.text.trim(),
        type: _selectedType,
        frequency: _selectedFrequency,
        instructions: _instructionsController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        scheduledTimes: scheduledTimes,
        status: MedicationStatus.pending,
        createdAt: DateTime.now(),
        isFromOCR: false,
      );

      await _medicationService.addMedication(medication);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الدواء بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<String> _calculateScheduledTimes(MedicationFrequency frequency) {
    switch (frequency) {
      case MedicationFrequency.onceDaily:
        return ['08:00'];
      case MedicationFrequency.twiceDaily:
        return ['08:00', '20:00'];
      case MedicationFrequency.threeTimesDaily:
        return ['08:00', '14:00', '20:00'];
      case MedicationFrequency.fourTimesDaily:
        return ['06:00', '12:00', '18:00', '00:00'];
      case MedicationFrequency.asNeeded:
        return [];
      case MedicationFrequency.weekly:
        return ['08:00'];
      case MedicationFrequency.monthly:
        return ['08:00'];
    }
  }
}
