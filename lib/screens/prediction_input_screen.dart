import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/app_data_service.dart';
import '../models/prediction_model.dart';
import '../models/user_model.dart';
import 'nurse_profile_screen.dart';
import 'booking_request_screen.dart';

class PredictionInputScreen extends StatefulWidget {
  const PredictionInputScreen({super.key});

  @override
  State<PredictionInputScreen> createState() => _PredictionInputScreenState();
}

class _PredictionInputScreenState extends State<PredictionInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _appDataService = AppDataService.instance;
  
  bool _isLoading = false;
  bool _isAnalyzing = false;
  PredictionResponse? _predictionResult;
  String? _errorMessage;
  
  // Patient data
  Map<String, dynamic>? _patientData;
  List<NurseMatch>? _matchedNurses;
  NurseMatch? _bestMatchedNurse;

  @override
  void initState() {
    super.initState();
    _loadPatientData();
  }

  Future<void> _loadPatientData() async {
    setState(() => _isLoading = true);
    
    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _errorMessage = 'يجب تسجيل الدخول لاستخدام هذه الميزة';
        });
        return;
      }

      // محاولة جلب البيانات من مجموعة patients أولاً
      try {
        final doc = await _firestore.collection('patients').doc(user.uid).get();
        
        if (doc.exists && doc.data() != null) {
          setState(() {
            _patientData = doc.data();
          });
          debugPrint('تم تحميل بيانات المريض من مجموعة patients');
          return;
        }
      } catch (e) {
        debugPrint('خطأ في جلب البيانات من patients: $e');
      }

      // محاولة بديلة من مجموعة users
      try {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data()!;
          // تحويل البيانات إلى تنسيق المريض
          final patientData = {
            'medicalCategory': userData['medicalCategory'] ?? 'غير محدد',
            'medicalTags': userData['medicalTags'] ?? [],
            'location': userData['location'] ?? 'غير محدد',
            'medicalDescription': userData['medicalDescription'] ?? '',
          };
          
          setState(() {
            _patientData = patientData;
          });
          debugPrint('تم تحميل بيانات المريض من مجموعة users');
          return;
        }
      } catch (e) {
        debugPrint('خطأ في جلب البيانات من users: $e');
      }

      setState(() {
        _errorMessage = 'لم يتم العثور على بيانات مريض. يرجى إكمال ملفك الشخصي أولاً.';
      });
    } catch (e) {
      debugPrint('خطأ عام في تحميل بيانات المريض: $e');
      setState(() {
        _errorMessage = 'حدث خطأ غير متوقع أثناء تحميل البيانات: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitPrediction() async {
    if (_patientData == null) {
      _showErrorSnackBar('لا توجد بيانات مريض. يرجى التأكد من تسجيل الدخول وإكمال ملفك الشخصي.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _predictionResult = null;
      _matchedNurses = null;
      _bestMatchedNurse = null;
    });

    try {
      debugPrint('=== بدء عملية تحليل الحالة وتطابق الممرضين ===');
      debugPrint('بيانات المريض: $_patientData');
      
      // 1. Map patient data to AI features
      final aiFeatures = _mapPatientDataToAIFeatures(_patientData!);
      debugPrint('الميزات المستخرجة للـ AI: ${aiFeatures.length} features');
      
      // 2. Send to AI API with patient data
      try {
        final result = await _apiService.sendPredictionWithPatientData(
          features: aiFeatures,
          patientData: _patientData!,
        );

        debugPrint('نتيجة API: $result');

        setState(() {
          _predictionResult = PredictionResponse.fromJson(result);
        });

        // 3. Process matched providers from backend response
        if (result.containsKey('matched_providers') && result['matched_providers'] != null) {
          final matchedProviders = result['matched_providers'] as List;
          debugPrint('عدد الممرضين المتطابقين من Backend: ${matchedProviders.length}');
          
          // Convert backend providers to NurseMatch format with Firestore fallback
          final matchedNurses = await Future.wait(matchedProviders.map((providerData) async {
            final provider = providerData['provider'] as Map<String, dynamic>;
            
            // التعامل مع score بشكل آمن وتحويله إلى نسبة مئوية
            final scoreValue = providerData['score'];
            final score = scoreValue is num ? scoreValue.toDouble() : 0.0;
            // إذا كانت الدرجة أكبر من 1، فهي بالفعل نسبة مئوية، وإلا نضربها في 100
            final matchPercent = (score > 1 ? score : score * 100).round();
            
            // التعامل مع reasons بشكل آمن
            final reasonsValue = providerData['match_reasons'];
            final reasons = reasonsValue is List 
                ? List<String>.from(reasonsValue.map((e) => e.toString()))
                : <String>[];
            
            debugPrint('ممرض متطابق: ${provider['name']} - الدرجة: $score%');
            debugPrint('الأسباب: ${reasons.join(", ")}');
            debugPrint('AI Nurse item: $provider');
            
            // محاولة العثور على الممرض في Firestore باستخدام المعرف
            final nurseId = provider['id']?.toString() ?? provider['_id']?.toString() ?? '';
            
            // استخدام الدالة المحسنة لاستخراج الاسم مع Firestore fallback
            final nurseName = await _getNurseNameWithFirestoreFallback(provider, nurseId);
            debugPrint('اسم الممرض بعد المعالجة: "$nurseName" (الطول: ${nurseName.length})');
            
            // جلب بيانات الممرض الإضافية من Firestore
            Map<String, dynamic>? firestoreData;
            try {
              if (nurseId.isNotEmpty) {
                final nurseDoc = await _firestore.collection('users').doc(nurseId).get();
                if (nurseDoc.exists && nurseDoc.data() != null) {
                  firestoreData = nurseDoc.data() as Map<String, dynamic>;
                  debugPrint('تم جلب بيانات الممرض الإضافية من Firestore للمستخدم: $nurseId');
                } else {
                  // محاولة البحث بالاسم إذا لم يتم العثور بالمعرف
                  final nameQuery = await _firestore
                      .collection('users')
                      .where('role', isEqualTo: 'nurse')
                      .where('name', isEqualTo: nurseName)
                      .limit(1)
                      .get();
                  
                  if (nameQuery.docs.isNotEmpty) {
                    firestoreData = nameQuery.docs.first.data() as Map<String, dynamic>;
                    debugPrint('تم جلب بيانات الممرض بالبحث بالاسم: $nurseName');
                  }
                }
              }
            } catch (e) {
              debugPrint('خطأ في جلب بيانات الممرض الإضافية من Firestore: $e');
            }
            
            final nurse = AppUser(
              id: nurseId,
              name: nurseName,
              email: firestoreData?['email']?.toString() ?? provider['email']?.toString() ?? '',
              phone: firestoreData?['phone']?.toString() ?? provider['phone']?.toString() ?? '',
              role: UserRole.nurse,
              status: UserStatus.active,
              createdAt: DateTime.now(),
              location: firestoreData?['location']?.toString() ?? provider['location']?.toString(),
              specialty: firestoreData?['specialty']?.toString() ?? provider['specialty']?.toString(),
              experienceYears: firestoreData?['experienceYears'] is num 
                  ? (firestoreData!['experienceYears'] as num).toInt() 
                  : (provider['experience_years'] is num 
                      ? (provider['experience_years'] as num).toInt() 
                      : 0),
              isResidentNurse: firestoreData?['isResidentNurse'] == true || provider['available'] == true,
              certificateVerified: firestoreData?['certificateVerified'] == true || provider['verified'] == true,
            );
            
            return NurseMatch(
              nurse: nurse,
              matchPercent: matchPercent,
              matchReason: reasons.isNotEmpty ? reasons.join(', ') : 'تطابق جيد',
            );
          }));
          
          // ترتيب الممرضين بترتيب تنازلي حسب نسبة التطابق
          matchedNurses.sort((a, b) => b.matchPercent.compareTo(a.matchPercent));
          
          setState(() {
            _matchedNurses = matchedNurses;
            _bestMatchedNurse = matchedNurses.isNotEmpty ? matchedNurses.first : null;
          });
        } else {
          debugPrint('لم يتم إرجاع ممرضين متطابقين من Backend، استخدام البحث المحلي');
          // Fallback to local matching
          await _findMatchingNurses();
        }

        _showSuccessSnackBar();
      } catch (apiError) {
        debugPrint('خطأ في الاتصال بالـ API: $apiError');
        debugPrint('استخدام البحث المحلي كبديل');
        // Fallback to local matching if API fails
        await _findMatchingNurses();
        if (_matchedNurses != null && _matchedNurses!.isNotEmpty) {
          _showSuccessSnackBar();
        } else {
          throw apiError;
        }
      }
    } catch (e) {
      debugPrint('=== خطأ في عملية التحليل ===');
      debugPrint('التفاصيل: ${e.toString()}');
      setState(() {
        _errorMessage = 'حدث خطأ أثناء التحليل: ${e.toString()}';
      });
      _showErrorSnackBar('حدث خطأ أثناء التحليل. يرجى المحاولة مرة أخرى.');
    } finally {
      setState(() => _isAnalyzing = false);
      debugPrint('=== انتهت عملية تحليل الحالة ===');
    }
  }

  String _getNurseName(Map<String, dynamic> nurse) {
    if (nurse['fullName'] != null && nurse['fullName'].toString().trim().isNotEmpty) {
      return nurse['fullName'].toString().trim();
    }
    if (nurse['name'] != null && nurse['name'].toString().trim().isNotEmpty) {
      return nurse['name'].toString().trim();
    }
    if (nurse['nurse_name'] != null && nurse['nurse_name'].toString().trim().isNotEmpty) {
      return nurse['nurse_name'].toString().trim();
    }
    if (nurse['displayName'] != null && nurse['displayName'].toString().trim().isNotEmpty) {
      return nurse['displayName'].toString().trim();
    }
    String combined = '${nurse['firstName'] ?? ''} ${nurse['lastName'] ?? ''}'.trim();
    if (combined.isNotEmpty) return combined;
    return 'ممرض متخصص'; // Safe non-empty fallback
  }

  Future<String> _getNurseNameWithFirestoreFallback(Map<String, dynamic> provider, String nurseId) async {
    // First try to get name from provider data
    final directName = _getNurseName(provider);
    if (directName != 'ممرض متخصص' && directName.isNotEmpty && directName.length > 3) {
      return directName;
    }

    // If name is not found or is fallback, try to fetch from Firestore
    try {
      if (nurseId.isNotEmpty) {
        final nurseDoc = await _firestore.collection('users').doc(nurseId).get();
        if (nurseDoc.exists && nurseDoc.data() != null) {
          final firestoreData = nurseDoc.data() as Map<String, dynamic>;
          final firestoreName = _getNurseName(firestoreData);
          if (firestoreName != 'ممرض متخصص' && firestoreName.isNotEmpty && firestoreName.length > 3) {
            debugPrint('تم جلب الاسم من Firestore: $firestoreName');
            return firestoreName;
          }
        }

        // Try nurses collection as fallback
        final nurseDocAlt = await _firestore.collection('nurses').doc(nurseId).get();
        if (nurseDocAlt.exists && nurseDocAlt.data() != null) {
          final firestoreData = nurseDocAlt.data() as Map<String, dynamic>;
          final firestoreName = _getNurseName(firestoreData);
          if (firestoreName != 'ممرض متخصص' && firestoreName.isNotEmpty && firestoreName.length > 3) {
            debugPrint('تم جلب الاسم من مجموعة nurses: $firestoreName');
            return firestoreName;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching nurse name from Firestore: $e');
    }

    // Final fallback - use the provider name if available
    final providerName = provider['name']?.toString() ?? 
                         provider['fullName']?.toString() ?? 
                         provider['nurse_name']?.toString() ?? '';
    if (providerName.isNotEmpty && providerName.length > 3) {
      debugPrint('استخدام اسم من provider data: $providerName');
      return providerName;
    }

    debugPrint('استخدام الاسم الافتراضي');
    return 'ممرض متخصص';
  }

  List<double> _mapPatientDataToAIFeatures(Map<String, dynamic> patientData) {
    // Extract patient medical data
    final medicalCategory = patientData['medicalCategory'] as String? ?? '';
    final medicalTags = List<String>.from(patientData['medicalTags'] ?? []);
    final location = patientData['location'] as String? ?? '';
    
    // 7 numerical features (matching the training features)
    final features = <double>[];
    
    // Feature 1: Medical category encoded
    final categoryMap = {
      'الأورام والسرطان': 1.0,
      'الحالات الطارئة والإصابات': 2.0,
      'أمراض القلب والشرايين': 3.0,
      'الأمراض العصبية': 4.0,
      'أمراض الكلى وغسيل الكلى': 5.0,
      'أمراض العظام والحركة': 6.0,
      'أمراض الجهاز التنفسي': 7.0,
      'أمراض العيون': 8.0,
    };
    features.add(categoryMap[medicalCategory] ?? 0.0);
    
    // Feature 2: Location encoded (simple hash)
    features.add(location.length > 0 ? location.hashCode.toDouble() % 10 : 0.0);
    
    // Feature 3: Experience years (use patient complexity as proxy)
    features.add(medicalTags.length.toDouble() / 10.0);
    
    // Feature 4: Verification status (assume verified)
    features.add(1.0);
    
    // Feature 5: Availability status (assume available)
    features.add(1.0);
    
    // Feature 6: Service count (number of medical tags)
    features.add(medicalTags.length.toDouble() / 10.0);
    
    // Feature 7: Service diversity (number of unique conditions)
    features.add(medicalTags.toSet().length.toDouble() / 20.0);
    
    // 30 text features (simplified placeholders for TfidfVectorizer)
    // In a real implementation, these would come from the actual vectorizer
    for (int i = 0; i < 30; i++) {
      features.add(0.0); // Placeholder for text features
    }
    
    return features;
  }

  Future<void> _findMatchingNurses() async {
    try {
      // Get all active nurses
      final nursesSnapshot = await _firestore
          .collection('nurses')
          .where('status', isEqualTo: 'active')
          .get();
      
      final nurses = nursesSnapshot.docs
          .map((doc) => AppUser.fromFirestore(doc.data(), doc.id))
          .toList();
      
      if (nurses.isEmpty) {
        setState(() {
          _matchedNurses = [];
        });
        return;
      }
      
      // Calculate match scores for each nurse
      final scoredNurses = nurses.map((nurse) {
        final score = _calculateMatchScore(_patientData!, nurse);
        // إذا كانت الدرجة أكبر من 1، فهي بالفعل نسبة مئوية، وإلا نضربها في 100
        final matchPercent = (score > 1 ? score : score * 100).round();
        return NurseMatch(
          nurse: nurse,
          matchPercent: matchPercent,
          matchReason: _getMatchReason(matchPercent),
        );
      }).toList();
      
      // Sort by score (highest first)
      scoredNurses.sort((a, b) => b.matchPercent.compareTo(a.matchPercent));
      
      // Get top matches
      final topMatches = scoredNurses.take(5).toList();
      
      setState(() {
        _matchedNurses = topMatches;
        _bestMatchedNurse = topMatches.isNotEmpty ? topMatches.first : null;
      });
    } catch (e) {
      print('Error finding matching nurses: $e');
    }
  }
  
  String _getMatchReason(int matchPercent) {
    if (matchPercent >= 80) return 'تطابق ممتاز';
    if (matchPercent >= 60) return 'تطابق جيد';
    if (matchPercent >= 40) return 'تطابق متوسط';
    return 'تطابق محدود';
  }

  double _calculateMatchScore(Map<String, dynamic> patientData, AppUser nurse) {
    double score = 0.0;
    
    final patientCategory = patientData['medicalCategory'] as String? ?? '';
    final patientLocation = patientData['location'] as String? ?? '';
    final patientTags = List<String>.from(patientData['medicalTags'] ?? []);
    
    // 1. Specialty match (40 points)
    if (nurse.specialty != null) {
      if (_categoryMatchesSpecialty(patientCategory, nurse.specialty!)) {
        score += 40;
      } else if (_isRelatedSpecialty(patientCategory, nurse.specialty!)) {
        score += 20;
      }
    }
    
    // 2. Location match (20 points)
    if (patientLocation.isNotEmpty && nurse.location != null) {
      if (patientLocation.contains(nurse.location!) || 
          nurse.location!.contains(patientLocation)) {
        score += 20;
      }
    }
    
    // 3. Experience points (20 points max)
    final experienceYears = nurse.experienceYears ?? 0;
    score += (experienceYears * 2).clamp(0.0, 20.0);
    
    // 4. Certification (10 points)
    if (nurse.certificateVerified == true) {
      score += 10;
    }
    
    // 5. Availability (10 points)
    if (nurse.status == UserStatus.active) {
      score += 10;
    }
    
    return score;
  }

  bool _categoryMatchesSpecialty(String category, String specialty) {
    final categoryLower = category.toLowerCase();
    final specialtyLower = specialty.toLowerCase();
    
    // Direct match
    if (categoryLower.contains(specialtyLower) || specialtyLower.contains(categoryLower)) {
      return true;
    }
    
    // Specific mappings
    final mappings = {
      'أمراض القلب والشرايين': ['قلب', 'قلبية', 'cardio', 'heart'],
      'الأمراض العصبية': ['عصبي', 'neuro', 'brain'],
      'أمراض الكلى وغسيل الكلى': ['كلى', 'kidney', 'renal'],
      'أمراض العظام والحركة': ['عظم', 'ortho', 'bone'],
      'أمراض الجهاز التنفسي': ['تنفس', 'respiratory', 'lung'],
      'أمراض العيون': ['عين', 'eye', 'ophthal'],
      'الأورام والسرطان': ['سرطان', 'cancer', 'oncology'],
    };
    
    final keywords = mappings[category] ?? [];
    return keywords.any((keyword) => specialtyLower.contains(keyword));
  }

  bool _isRelatedSpecialty(String category, String specialty) {
    // Check if specialty is in the same general medical field
    if (category.contains('قلب') && specialty.contains('داخلي')) return true;
    if (category.contains('عصبي') && specialty.contains('داخلي')) return true;
    if (category.contains('طارئة') && specialty.contains('طوارئ')) return true;
    
    return false;
  }

  void _showSuccessSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'تم إرسال التنبؤ بنجاح',
          style: TextStyle(color: Colors.white),
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
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _navigateToNurseProfile(AppUser nurse) async {
    // التحقق من أن الممرض غير فارغ
    if (nurse.id.isEmpty) {
      _showErrorSnackBar('بيانات الممرض غير صالحة');
      return;
    }

    // التنقل المباشر إلى شاشة ملف الممرض
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NurseProfileScreen(nurseId: nurse.id),
        ),
      );
    }
  }

  Future<void> _navigateToBooking(AppUser nurse) async {
    // التحقق من وجود المستخدم الحالي
    final user = _auth.currentUser;
    if (user == null) {
      _showErrorSnackBar('يجب تسجيل الدخول لحجز موعد');
      return;
    }

    // التحقق من أن الممرض غير فارغ
    if (nurse.id.isEmpty) {
      _showErrorSnackBar('بيانات الممرض غير صالحة');
      return;
    }

    // عرض مؤشر تحميل
    setState(() => _isLoading = true);

    try {
      // جلب بيانات المريض من Firestore مع معالجة أفضل للأخطاء
      Map<String, dynamic>? patientData;
      try {
        // محاولة جلب البيانات من مجموعة patients أولاً
        final patientDoc = await _firestore.collection('patients').doc(user.uid).get();
        if (patientDoc.exists && patientDoc.data() != null) {
          patientData = patientDoc.data();
          debugPrint('تم جلب بيانات المريض من مجموعة patients');
        } else {
          // محاولة بديلة من مجموعة users
          final userDoc = await _firestore.collection('users').doc(user.uid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final userData = userDoc.data()!;
            patientData = {
              'medicalCategory': userData['medicalCategory']?.toString() ?? 'غير محدد',
              'medicalTags': userData['medicalTags'] is List 
                  ? List<String>.from(userData['medicalTags']) 
                  : [],
              'location': userData['location']?.toString() ?? 'غير محدد',
              'medicalDescription': userData['medicalDescription']?.toString() ?? '',
              'name': userData['name']?.toString() ?? 'مريض',
            };
            debugPrint('تم جلب بيانات المريض من مجموعة users');
          }
        }
      } catch (e) {
        debugPrint('خطأ في جلب بيانات المريض: $e');
        // نستمر حتى بدون بيانات المريض
      }

      if (mounted) {
        // إخفاء مؤشر التحميل قبل التنقل
        setState(() => _isLoading = false);
        
        // التنقل المباشر إلى شاشة طلب الحجز مع بيانات الممرض
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookingRequestScreen(
              nurse: nurse,
              patientData: patientData,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في الانتقال: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('عذراً، حدث خطأ في الانتقال. يرجى المحاولة مرة أخرى.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _isLoading
            ? SafeArea(child: _buildLoadingState())
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 1200,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPatientInfoCard(),
                        const SizedBox(height: 24),
                        _buildAnalyzeButton(),
                        const SizedBox(height: 24),
                        if (_isAnalyzing) _buildAnalyzingState(),
                        if (_errorMessage != null) _buildErrorCard(),
                        if (_matchedNurses != null && _matchedNurses!.isNotEmpty) ...[
                          _buildBestMatchCard(),
                          const SizedBox(height: 16),
                          _buildOtherMatchesCard(),
                        ],
                        if (_matchedNurses != null && _matchedNurses!.isEmpty) _buildNoMatchesCard(),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'التنبؤ بالذكاء الاصطناعي',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildPatientInfoCard() {
    if (_patientData == null) {
      return _buildErrorCard('لا توجد بيانات مريض');
    }

    final medicalCategory = _patientData!['medicalCategory'] as String? ?? 'غير محدد';
    final medicalTags = List<String>.from(_patientData!['medicalTags'] ?? []);
    final location = _patientData!['location'] as String? ?? 'غير محدد';
    final description = _patientData!['medicalDescription'] as String? ?? 'لا يوجد وصف';

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_search_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'تحليل حالتك الصحية',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInfoRow('الفئة الطبية', medicalCategory, Icons.category),
          const SizedBox(height: 12),
          _buildInfoRow('الموقع', location, Icons.location_on),
          const SizedBox(height: 12),
          _buildInfoRow('عدد الحالات', '${medicalTags.length}', Icons.local_hospital),
          const SizedBox(height: 16),
          if (medicalTags.isNotEmpty) ...[
            const Text(
              'الحالات المرضية:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: medicalTags.take(5).map((tag) {
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
            ),
            if (medicalTags.length > 5)
              Text(
                '+${medicalTags.length - 5} حالة أخرى',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'الوصف الطبي',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzeButton() {
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
        onPressed: _isAnalyzing ? null : _submitPrediction,
        child: _isAnalyzing
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
                  Icon(Icons.psychology_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'تحليل الحالة',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAnalyzingState() {
    return Container(
      padding: const EdgeInsets.all(30),
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
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 20),
          const Text(
            'جاري تحليل حالتك الصحية...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'نقوم بمطابقة حالتك مع أفضل الممرضين المتاحين',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBestMatchCard() {
    if (_bestMatchedNurse == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.05), AppColors.accent.withOpacity(0.05)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'أفضل تنبؤ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildNurseCard(_bestMatchedNurse!, isBestMatch: true),
        ],
      ),
    );
  }

  Widget _buildOtherMatchesCard() {
    if (_matchedNurses == null || _matchedNurses!.length <= 1) return const SizedBox.shrink();

    final otherNurses = _matchedNurses!.skip(1).toList();

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'خيارات أخرى',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...otherNurses.map((nurseMatch) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildNurseCard(nurseMatch, isBestMatch: false),
          )),
        ],
      ),
    );
  }

  Widget _buildNurseCard(NurseMatch nurseMatch, {required bool isBestMatch}) {
    final nurse = nurseMatch.nurse;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isBestMatch 
            ? Border.all(color: AppColors.primary.withOpacity(0.3))
            : Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accent.withOpacity(0.2),
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    _getAvatarText(nurse.name),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nurse.name.isNotEmpty ? nurse.name : 'ممرض متخصص',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getMatchColor(nurseMatch.matchPercent),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${nurseMatch.matchPercent}% تطابق',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nurse.specialty ?? 'ممرض عام',
                      style: TextStyle(
                        color: AppColors.textDark.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.work_history_outlined,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${nurse.experienceYears ?? 0} سنوات',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          nurse.certificateVerified == true
                              ? Icons.verified
                              : Icons.pending,
                          size: 14,
                          color: nurse.certificateVerified == true
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            nurse.certificateVerified == true ? 'موثق' : 'قيد المراجعة',
                            style: TextStyle(
                              fontSize: 11,
                              color: nurse.certificateVerified == true
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.star,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            nurse.totalReviews > 0
                                ? '${nurse.averageRating.toStringAsFixed(1)} (${nurse.totalReviews} تقييم)'
                                : 'لا توجد تقييمات',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (nurse.location != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              nurse.location!,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: () => _navigateToNurseProfile(nurse),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('عرض الملف'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToBooking(nurse),
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: const Text('طلب حجز'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Color _getMatchColor(int percent) {
    if (percent >= 80) return Colors.green;
    if (percent >= 60) return Colors.blue;
    if (percent >= 40) return Colors.orange;
    return Colors.grey;
  }

  String _getAvatarText(String name) {
    if (name.isEmpty || name.length < 3) return 'م';
    
    final words = name.split(' ');
    if (words.length >= 2) {
      final firstInitial = words[0].isNotEmpty ? words[0][0] : '';
      final secondInitial = words[1].isNotEmpty ? words[1][0] : '';
      return '$firstInitial$secondInitial';
    }
    
    return name.substring(0, 2);
  }

  Widget _buildNoMatchesCard() {
    return Container(
      padding: const EdgeInsets.all(30),
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
      child: Column(
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'لا يوجد ممرضين متاحين',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'لم نعثر على ممرضين يتطابقون مع حالتك الصحية حالياً',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _matchedNurses = null;
                _bestMatchedNurse = null;
              });
              _submitPrediction();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard([String? customMessage]) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              customMessage ?? _errorMessage ?? 'حدث خطأ غير معروف',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.red,
              ),
            ),
          ),
        ],
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
            'جاري التحميل...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}