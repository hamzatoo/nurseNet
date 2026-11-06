import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { patient, nurse, admin }

enum UserStatus { active, pending, suspended }

enum VerificationStatus { pending, approved, rejected }

class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  UserStatus status;
  final DateTime createdAt;
  final String? location;
  final String? specialty;
  final int? experienceYears;
  final bool? isResidentNurse;
  bool? certificateVerified;
  final String? medicalCategory;
  final List<String> medicalTags;
  final String? medicalDescription;
  final String? licenseNumber;
  bool isVerified;
  VerificationStatus verificationStatus;
  final double averageRating;
  final int totalReviews;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.status = UserStatus.active,
    required this.createdAt,
    this.location,
    this.specialty,
    this.experienceYears,
    this.isResidentNurse,
    this.certificateVerified,
    this.medicalCategory,
    this.medicalTags = const [],
    this.medicalDescription,
    this.licenseNumber,
    this.isVerified = false,
    this.verificationStatus = VerificationStatus.pending,
    this.averageRating = 0.0,
    this.totalReviews = 0,
  });

  factory AppUser.fromFirestore(Map<String, dynamic> data, String id) {
    // Handle medical tags safely with strict null-safety
    List<String> medicalTags = [];
    try {
      if (data['medicalTags'] != null && data['medicalTags'] is List) {
        medicalTags = (data['medicalTags'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
    } catch (e) {
      print('Error parsing medical tags: $e');
    }

    return AppUser(
      id: id,
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      role: _parseRole(data['role']?.toString()),
      status: _parseStatus(data['status']?.toString()),
      createdAt: _safeParseTimestamp(data['createdAt']),
      location: data['location']?.toString(),
      specialty: data['specialty']?.toString(),
      experienceYears: _safeParseInt(data['experienceYears']),
      isResidentNurse: _safeParseBool(data['isResidentNurse']),
      certificateVerified: _safeParseBool(data['certificateVerified']),
      medicalCategory: data['medicalCategory']?.toString(),
      medicalTags: medicalTags.isNotEmpty ? medicalTags : const [],
      medicalDescription: data['medicalDescription']?.toString(),
      licenseNumber: data['licenseNumber']?.toString(),
      isVerified: _safeParseBool(data['isVerified']) ?? false,
      verificationStatus: _parseVerificationStatus(data['verificationStatus']?.toString()),
      averageRating: _safeParseDouble(data['averageRating']),
      totalReviews: _safeParseInt(data['totalReviews']) ?? 0,
    );
  }

  // Safe timestamp parsing helper
  static DateTime _safeParseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    try {
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is DateTime) {
        return value;
      }
      if (value is String) {
        return DateTime.parse(value);
      }
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
    } catch (e) {
      print('Error parsing timestamp: $e');
    }
    return DateTime.now();
  }

  // Safe int parsing helper
  static int? _safeParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  // Safe double parsing helper
  static double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  // Safe bool parsing helper
  static bool? _safeParseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    if (value is num) {
      return value != 0;
    }
    return null;
  }

  static UserRole _parseRole(String? role) {
    if (role == null || role.isEmpty) return UserRole.patient;
    switch (role.toLowerCase().trim()) {
      case 'nurse':
        return UserRole.nurse;
      case 'admin':
        return UserRole.admin;
      case 'patient':
      default:
        return UserRole.patient;
    }
  }

  static UserStatus _parseStatus(String? status) {
    if (status == null || status.isEmpty) return UserStatus.active;
    switch (status.toLowerCase().trim()) {
      case 'pending':
        return UserStatus.pending;
      case 'suspended':
        return UserStatus.suspended;
      case 'active':
      default:
        return UserStatus.active;
    }
  }

  static VerificationStatus _parseVerificationStatus(String? status) {
    if (status == null || status.isEmpty) return VerificationStatus.pending;
    switch (status.toLowerCase().trim()) {
      case 'approved':
        return VerificationStatus.approved;
      case 'rejected':
        return VerificationStatus.rejected;
      case 'pending':
      default:
        return VerificationStatus.pending;
    }
  }
}

class NurseMatch {
  final AppUser nurse;
  final int matchPercent;
  final String matchReason;

  NurseMatch({
    required this.nurse,
    required this.matchPercent,
    required this.matchReason,
  });
}
