import 'package:cloud_firestore/cloud_firestore.dart';

enum RequestStatus { pending, accepted, matched, inProgress, completed, cancelled, rejected }

class CareRequest {
  final String id;
  final String patientId;
  final String patientName;
  String? patientPhone; // Added for calling functionality
  String? nurseId;
  String? nurseName;
  String? nursePhone; // Added for calling functionality
  String? nurseSpecialty;
  final String description;
  final List<String> tags;
  final bool needsResidentNurse;
  RequestStatus status;
  final DateTime createdAt;
  final String location;
  final DateTime? requestedDate;
  final String? requestedTime;
  final bool? isRated;

  CareRequest({
    required this.id,
    required this.patientId,
    required this.patientName,
    this.patientPhone,
    this.nurseId,
    this.nurseName,
    this.nursePhone,
    this.nurseSpecialty,
    required this.description,
    required this.tags,
    required this.needsResidentNurse,
    this.status = RequestStatus.pending,
    required this.createdAt,
    required this.location,
    this.requestedDate,
    this.requestedTime,
    this.isRated,
  });

  // Factory constructor for safe Firestore document parsing
  factory CareRequest.fromFirestore(Map<String, dynamic> data, String documentId) {
    try {
      return CareRequest(
        id: documentId.isNotEmpty ? documentId : '',
        patientId: _safeString(data['patientId']),
        patientName: _safeString(data['patientName'], fallback: 'غير معروف'),
        patientPhone: _safeString(data['patientPhone']),
        nurseId: _safeString(data['nurseId']),
        nurseName: _safeString(data['nurseName']),
        nursePhone: _safeString(data['nursePhone']),
        nurseSpecialty: _safeString(data['nurseSpecialty']),
        description: _safeString(data['description']),
        tags: _safeParseList(data['tags']),
        needsResidentNurse: _safeBool(data['needsResidentNurse']),
        status: _parseStatus(_safeString(data['status'])),
        createdAt: _safeParseRequiredTimestamp(data['createdAt']),
        location: _safeString(data['location']),
        requestedDate: _safeParseTimestamp(data['requestedDate']),
        requestedTime: _safeString(data['requestedTime']),
        isRated: data['isRated'] is bool ? data['isRated'] as bool : null,
      );
    } catch (e) {
      // Return a safe default object if parsing fails
      return CareRequest(
        id: documentId.isNotEmpty ? documentId : '',
        patientId: '',
        patientName: 'غير معروف',
        description: '',
        tags: [],
        needsResidentNurse: false,
        status: RequestStatus.pending,
        createdAt: DateTime.now(),
        location: '',
        isRated: false,
      );
    }
  }

  // Factory constructor for JSON parsing
  factory CareRequest.fromJson(Map<String, dynamic> json) {
    try {
      return CareRequest(
        id: _safeString(json['id']),
        patientId: _safeString(json['patientId']),
        patientName: _safeString(json['patientName'], fallback: 'غير معروف'),
        nurseId: _safeString(json['nurseId']),
        nurseName: _safeString(json['nurseName']),
        nurseSpecialty: _safeString(json['nurseSpecialty']),
        description: _safeString(json['description']),
        tags: _safeParseList(json['tags']),
        needsResidentNurse: _safeBool(json['needsResidentNurse']),
        status: _parseStatus(_safeString(json['status'])),
        createdAt: _safeParseRequiredTimestamp(json['createdAt']),
        location: _safeString(json['location']),
        requestedDate: _safeParseTimestamp(json['requestedDate']),
        requestedTime: _safeString(json['requestedTime']),
        isRated: _safeBool(json['isRated']),
      );
    } catch (e) {
      // Return a safe default object if parsing fails
      return CareRequest(
        id: '',
        patientId: '',
        patientName: 'غير معروف',
        description: '',
        tags: [],
        needsResidentNurse: false,
        status: RequestStatus.pending,
        createdAt: DateTime.now(),
        location: '',
        isRated: false,
      );
    }
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'nurseId': nurseId,
      'nurseName': nurseName,
      'nurseSpecialty': nurseSpecialty,
      'description': description,
      'tags': tags,
      'needsResidentNurse': needsResidentNurse,
      'status': status.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'location': location,
      'requestedDate': requestedDate?.toIso8601String(),
      'requestedTime': requestedTime,
      'isRated': isRated,
    };
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'patientId': patientId,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'nurseId': nurseId,
      'nurseName': nurseName,
      'nursePhone': nursePhone,
      'nurseSpecialty': nurseSpecialty,
      'description': description,
      'tags': tags.isNotEmpty ? tags : [],
      'needsResidentNurse': needsResidentNurse,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'location': location,
      'requestedDate': requestedDate != null ? Timestamp.fromDate(requestedDate!) : null,
      'requestedTime': requestedTime,
      'isRated': isRated,
    };
  }

  // Safe string parsing helper
  static String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value.isNotEmpty ? value : fallback;
    return value.toString();
  }

  // Safe bool parsing helper
  static bool _safeBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    if (value is num) {
      return value != 0;
    }
    return false;
  }

  // Safe list parsing helper
  static List<String> _safeParseList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  // Safe timestamp parsing helper (optional)
  static DateTime? _safeParseTimestamp(dynamic value) {
    if (value == null) return null;
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
      // Return null if parsing fails
    }
    return null;
  }

  // Safe timestamp parsing helper (required)
  static DateTime _safeParseRequiredTimestamp(dynamic value) {
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
      // Return current date if parsing fails
    }
    return DateTime.now();
  }

  // Safe status parsing helper
  static RequestStatus _parseStatus(String? statusStr) {
    if (statusStr == null || statusStr.isEmpty) return RequestStatus.pending;
    
    try {
      switch (statusStr.toLowerCase().trim()) {
        case 'pending':
          return RequestStatus.pending;
        case 'accepted':
          return RequestStatus.accepted;
        case 'matched':
          return RequestStatus.matched;
        case 'in_progress':
        case 'inprogress':
          return RequestStatus.inProgress;
        case 'completed':
          return RequestStatus.completed;
        case 'cancelled':
          return RequestStatus.cancelled;
        case 'rejected':
          return RequestStatus.rejected;
        default:
          return RequestStatus.pending;
      }
    } catch (e) {
      return RequestStatus.pending;
    }
  }
}
