import '../models/user_model.dart';
import '../models/care_request.dart';

class AppDataService {
  AppDataService._();
  static final AppDataService instance = AppDataService._();

  AppUser? currentUser;
  List<NurseMatch>? lastMatches;

  final List<AppUser> _users = [
    AppUser(
      id: 'n1',
      name: 'أنس الحريري',
      email: 'anas@nursenet.com',
      phone: '0501234567',
      role: UserRole.nurse,
      status: UserStatus.active,
      createdAt: DateTime(2024, 3, 15),
      location: 'الرياض',
      specialty: 'تمريض عناية مشددة وغيار جروح',
      experienceYears: 5,
      isResidentNurse: true,
      certificateVerified: true,
    ),
    AppUser(
      id: 'n2',
      name: 'رنا اليوسف',
      email: 'rana@nursenet.com',
      phone: '0509876543',
      role: UserRole.nurse,
      status: UserStatus.active,
      createdAt: DateTime(2024, 6, 20),
      location: 'جدة',
      specialty: 'رعاية مسنين وعلاج طبيعي',
      experienceYears: 3,
      isResidentNurse: false,
      certificateVerified: true,
    ),
    AppUser(
      id: 'n3',
      name: 'محمد العتيبي',
      email: 'mohammed@nursenet.com',
      phone: '0551112233',
      role: UserRole.nurse,
      status: UserStatus.pending,
      createdAt: DateTime(2025, 1, 10),
      location: 'الدمام',
      specialty: 'تمريض عام',
      experienceYears: 2,
      isResidentNurse: true,
      certificateVerified: false,
    ),
    AppUser(
      id: 'p1',
      name: 'سارة الأحمد',
      email: 'sara@email.com',
      phone: '0544445566',
      role: UserRole.patient,
      status: UserStatus.active,
      createdAt: DateTime(2025, 2, 1),
      location: 'الرياض',
      medicalCategory: 'أمراض العظام والحركة',
      medicalTags: ['غيار جروح', 'رعاية مسنين'],
      medicalDescription: 'مريض يعاني من صعوبة في الحركة ويحتاج غيار جروح يومي.',
    ),
    AppUser(
      id: 'p2',
      name: 'خالد المنصور',
      email: 'khaled@email.com',
      phone: '0533337788',
      role: UserRole.patient,
      status: UserStatus.active,
      createdAt: DateTime(2025, 3, 5),
      location: 'جدة',
      medicalCategory: 'أمراض القلب والشرايين',
      medicalTags: ['ضغط دم', 'حقن وريدية'],
      medicalDescription: 'مريض يعاني من ارتفاع ضغط الدم ويحتاج متابعة يومية.',
    ),
    AppUser(
      id: 'a1',
      name: 'مدير النظام',
      email: 'admin@nursenet.com',
      phone: '0500000000',
      role: UserRole.admin,
      status: UserStatus.active,
      createdAt: DateTime(2024, 1, 1),
    ),
  ];

  final List<CareRequest> _requests = [
    CareRequest(
      id: 'r1',
      patientId: 'p1',
      patientName: 'سارة الأحمد',
      nurseId: 'n1',
      nurseName: 'أنس الحريري',
      description: 'مريض يعاني من صعوبة في الحركة ويحتاج غيار جروح يومي.',
      tags: ['غيار جروح', 'رعاية مسنين'],
      needsResidentNurse: true,
      status: RequestStatus.inProgress,
      createdAt: DateTime(2025, 7, 10),
      location: 'الرياض',
    ),
    CareRequest(
      id: 'r2',
      patientId: 'p2',
      patientName: 'خالد المنصور',
      description: 'مريض يعاني من ارتفاع ضغط الدم ويحتاج متابعة يومية.',
      tags: ['ضغط دم', 'حقن وريدية'],
      needsResidentNurse: false,
      status: RequestStatus.pending,
      createdAt: DateTime(2025, 8, 1),
      location: 'جدة',
    ),
    CareRequest(
      id: 'r3',
      patientId: 'p1',
      patientName: 'سارة الأحمد',
      nurseId: 'n2',
      nurseName: 'رنا اليوسف',
      description: 'جلسة علاج طبيعي أسبوعية.',
      tags: ['علاج فيزيائي'],
      needsResidentNurse: false,
      status: RequestStatus.completed,
      createdAt: DateTime(2025, 5, 20),
      location: 'الرياض',
    ),
  ];

  List<AppUser> get allUsers => List.unmodifiable(_users);
  List<CareRequest> get allRequests => List.unmodifiable(_requests);

  List<AppUser> get patients =>
      _users.where((u) => u.role == UserRole.patient).toList();

  List<AppUser> get nurses =>
      _users.where((u) => u.role == UserRole.nurse).toList();

  List<AppUser> get pendingNurses =>
      _users.where((u) => u.role == UserRole.nurse && u.status == UserStatus.pending).toList();

  List<CareRequest> get pendingRequests =>
      _requests.where((r) => r.status == RequestStatus.pending).toList();

  int get totalUsers => _users.length;
  int get totalPatients => patients.length;
  int get totalNurses => nurses.length;
  int get totalPendingRequests => pendingRequests.length;
  int get totalActiveRequests => _requests
      .where((r) =>
          r.status == RequestStatus.inProgress ||
          r.status == RequestStatus.matched)
      .length;

  bool login(String email, String password, UserRole expectedRole) {
    if (password.isEmpty) return false;
    final user = _users.where((u) => u.email == email && u.role == expectedRole).firstOrNull;
    if (user != null && user.status != UserStatus.suspended) {
      currentUser = user;
      return true;
    }
    if (expectedRole == UserRole.admin && email.isNotEmpty && password.isNotEmpty) {
      currentUser = _users.firstWhere((u) => u.role == UserRole.admin);
      return true;
    }
    if (expectedRole == UserRole.nurse && email.isNotEmpty && password.isNotEmpty) {
      final activeNurse = nurses.where((n) => n.status == UserStatus.active).firstOrNull;
      if (activeNurse != null) {
        currentUser = activeNurse;
        return true;
      }
    }
    return false;
  }

  void logout() => currentUser = null;

  void approveNurse(String nurseId) {
    final nurse = _users.firstWhere((u) => u.id == nurseId);
    nurse.status = UserStatus.active;
    nurse.certificateVerified = true;
  }

  void rejectNurse(String nurseId) {
    final nurse = _users.firstWhere((u) => u.id == nurseId);
    nurse.status = UserStatus.suspended;
  }

  void suspendUser(String userId) {
    final user = _users.firstWhere((u) => u.id == userId);
    user.status = UserStatus.suspended;
  }

  void activateUser(String userId) {
    final user = _users.firstWhere((u) => u.id == userId);
    user.status = UserStatus.active;
  }

  void updateRequestStatus(String requestId, RequestStatus status) {
    final request = _requests.firstWhere((r) => r.id == requestId);
    request.status = status;
  }

  List<NurseMatch> findMatchingNurses({
    required String description,
    required List<String> tags,
    required bool needsResidentNurse,
  }) {
    final activeNurses =
        nurses.where((n) => n.status == UserStatus.active).toList();
    final matches = <NurseMatch>[];

    for (final nurse in activeNurses) {
      int score = 50;
      final reasons = <String>[];

      if (needsResidentNurse && nurse.isResidentNurse == true) {
        score += 20;
        reasons.add('متاح للإقامة');
      } else if (!needsResidentNurse) {
        score += 10;
      }

      if (nurse.experienceYears != null) {
        score += (nurse.experienceYears! * 3).clamp(0, 15);
        reasons.add('${nurse.experienceYears} سنوات خبرة');
      }

      final specialty = nurse.specialty?.toLowerCase() ?? '';
      for (final tag in tags) {
        if (specialty.contains(tag.toLowerCase()) ||
            description.contains(tag)) {
          score += 8;
          reasons.add('تخصص متوافق: $tag');
        }
      }

      if (description.contains('جروح') && specialty.contains('جروح')) {
        score += 15;
        reasons.add('خبرة في غيار الجروح');
      }
      if (description.contains('مسن') && specialty.contains('مسن')) {
        score += 12;
        reasons.add('تخصص رعاية مسنين');
      }
      if (description.contains('ضغط') && specialty.contains('ضغط')) {
        score += 12;
      }

      score = score.clamp(60, 99);
      matches.add(NurseMatch(
        nurse: nurse,
        matchPercent: score,
        matchReason: reasons.isNotEmpty ? reasons.first : 'تطابق عام',
      ));
    }

    matches.sort((a, b) => b.matchPercent.compareTo(a.matchPercent));
    lastMatches = matches;
    return matches;
  }

  List<CareRequest> getNurseRequests(String nurseId) =>
      _requests.where((r) => r.nurseId == nurseId || r.status == RequestStatus.pending).toList();

  void registerNurse(AppUser nurse) {
    _users.add(nurse);
    currentUser = nurse;
  }

  void registerPatient(AppUser patient) {
    _users.add(patient);
    currentUser = patient;
  }

  void addCareRequest(CareRequest request) {
    _requests.insert(0, request);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
