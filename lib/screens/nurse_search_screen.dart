import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import 'nurse_profile_screen.dart';

class NurseSearchScreen extends StatefulWidget {
  const NurseSearchScreen({super.key});

  @override
  State<NurseSearchScreen> createState() => _NurseSearchScreenState();
}

class _NurseSearchScreenState extends State<NurseSearchScreen> {
  final _firestoreService = FirestoreService.instance;
  final _searchController = TextEditingController();
  List<AppUser> _nurses = [];
  List<AppUser> _filteredNurses = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // تحديث القائمة المفلترة بدون setState لأن StreamBuilder سيعيد البناء تلقائياً
    _filteredNurses = _filterNurses(_nurses, _searchController.text);
    // ندعو setState فقط لتحديث الـ UI إذا لزم الأمر
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.primary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'البحث عن ممرضين',
          style: TextStyle(
            color: AppColors.textDark,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildNursesList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم، التخصص، أو المدينة...',
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.primary,
            ),
            suffixIcon: ValueListenableBuilder(
              valueListenable: _searchController,
              builder: (context, TextEditingValue value, child) {
                return value.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : const SizedBox.shrink();
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNursesList() {
    return StreamBuilder<List<AppUser>>(
      stream: _firestoreService.getActiveNurses(),
      builder: (context, snapshot) {
        // معالجة حالة التحميل
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // معالجة الأخطاء
        if (snapshot.hasError) {
          debugPrint('Nurse Search Stream Error: ${snapshot.error}');
          debugPrint('Error Type: ${snapshot.error.runtimeType}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'حدث خطأ في تحميل بيانات الممرضين',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'يرجى التحقق من اتصال الإنترنت',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          );
        }

        // معالجة البيانات
        final nurses = snapshot.data ?? [];
        
        // تحديث القائمة المحلية بدون setState لتجنب حلقات إعادة البناء
        _nurses = nurses;
        _filteredNurses = _filterNurses(nurses, _searchController.text);

        if (_filteredNurses.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  _searchController.text.isEmpty
                      ? 'لا يوجد ممرضين متاحين حالياً'
                      : 'لم يتم العثور على نتائج مطابقة',
                  style: TextStyle(color: Colors.grey[500], fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _filteredNurses.length,
          itemBuilder: (context, index) => _buildNurseCard(_filteredNurses[index]),
        );
      },
    );
  }

  List<AppUser> _filterNurses(List<AppUser> nurses, String query) {
    if (query.isEmpty) return nurses;
    final lowerQuery = query.toLowerCase();
    return nurses.where((nurse) {
      final name = nurse.name.toLowerCase();
      final specialty = (nurse.specialty ?? '').toLowerCase();
      final location = (nurse.location ?? '').toLowerCase();

      return name.contains(lowerQuery) ||
          specialty.contains(lowerQuery) ||
          location.contains(lowerQuery);
    }).toList();
  }

  Widget _buildNurseCard(AppUser nurse) {
    final name = nurse.name.isNotEmpty ? nurse.name : 'غير معروف';
    final specialty = nurse.specialty?.isNotEmpty == true ? nurse.specialty! : 'ممرض عام';
    final location = nurse.location ?? '';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NurseProfileScreen(nurseId: nurse.id),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.medical_services_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        specialty,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (location.isNotEmpty)
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    location,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
