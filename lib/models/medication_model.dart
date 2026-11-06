import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum MedicationType {
  tablet,
  capsule,
  injection,
  syrup,
  drops,
  inhaler,
  cream,
  other;

  String get typeDisplay {
    switch (this) {
      case MedicationType.tablet: return 'أقراص';
      case MedicationType.capsule: return 'كبسولات';
      case MedicationType.injection: return 'حقن';
      case MedicationType.syrup: return 'شراب';
      case MedicationType.drops: return 'قطرات';
      case MedicationType.inhaler: return 'بخاخ';
      case MedicationType.cream: return 'مرهم';
      case MedicationType.other: return 'أخرى';
    }
  }

  IconData get typeIcon {
    switch (this) {
      case MedicationType.tablet: return Icons.medication;
      case MedicationType.capsule: return Icons.blur_circular;
      case MedicationType.injection: return Icons.vaccines;
      case MedicationType.syrup: return Icons.science;
      case MedicationType.drops: return Icons.water_drop;
      case MedicationType.inhaler: return Icons.air;
      case MedicationType.cream: return Icons.clean_hands;
      case MedicationType.other: return Icons.healing;
    }
  }
}

enum MedicationFrequency {
  onceDaily,
  twiceDaily,
  threeTimesDaily,
  fourTimesDaily,
  asNeeded,
  weekly,
  monthly;

  String get frequencyDisplay {
    switch (this) {
      case MedicationFrequency.onceDaily: return 'مرة يومياً';
      case MedicationFrequency.twiceDaily: return 'مرتين يومياً';
      case MedicationFrequency.threeTimesDaily: return '3 مرات يومياً';
      case MedicationFrequency.fourTimesDaily: return '4 مرات يومياً';
      case MedicationFrequency.asNeeded: return 'عند الحاجة';
      case MedicationFrequency.weekly: return 'أسبوعياً';
      case MedicationFrequency.monthly: return 'شهرياً';
    }
  }
}

enum MedicationStatus {
  pending,
  taken,
  skipped,
  missed,
}

class Medication {
  final String id;
  final String name;
  final String dosage;
  final MedicationType type;
  final MedicationFrequency frequency;
  final String? instructions;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> scheduledTimes; // e.g., ["08:00", "14:00", "20:00"]
  final MedicationStatus status;
  final DateTime? lastTakenAt;
  final DateTime? createdAt;
  final String? imageUrl; // OCR image URL
  final bool isFromOCR;

  Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.type,
    required this.frequency,
    this.instructions,
    required this.startDate,
    required this.endDate,
    required this.scheduledTimes,
    this.status = MedicationStatus.pending,
    this.lastTakenAt,
    this.createdAt,
    this.imageUrl,
    this.isFromOCR = false,
  });

  factory Medication.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Medication(
      id: doc.id,
      name: data['name'] as String,
      dosage: data['dosage'] as String,
      type: _parseMedicationType(data['type'] as String?),
      frequency: _parseMedicationFrequency(data['frequency'] as String?),
      instructions: data['instructions'] as String?,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      scheduledTimes: List<String>.from(data['scheduledTimes'] as List),
      status: _parseMedicationStatus(data['status'] as String?),
      lastTakenAt: data['lastTakenAt'] != null 
          ? (data['lastTakenAt'] as Timestamp).toDate() 
          : null,
      createdAt: data['createdAt'] != null 
          ? (data['createdAt'] as Timestamp).toDate() 
          : null,
      imageUrl: data['imageUrl'] as String?,
      isFromOCR: data['isFromOCR'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'dosage': dosage,
      'type': type.name,
      'frequency': frequency.name,
      'instructions': instructions,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'scheduledTimes': scheduledTimes,
      'status': status.name,
      'lastTakenAt': lastTakenAt != null ? Timestamp.fromDate(lastTakenAt!) : null,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : Timestamp.fromDate(DateTime.now()),
      'imageUrl': imageUrl,
      'isFromOCR': isFromOCR,
    };
  }

  Medication copyWith({
    String? id,
    String? name,
    String? dosage,
    MedicationType? type,
    MedicationFrequency? frequency,
    String? instructions,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? scheduledTimes,
    MedicationStatus? status,
    DateTime? lastTakenAt,
    DateTime? createdAt,
    String? imageUrl,
    bool? isFromOCR,
  }) {
    return Medication(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      type: type ?? this.type,
      frequency: frequency ?? this.frequency,
      instructions: instructions ?? this.instructions,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      scheduledTimes: scheduledTimes ?? this.scheduledTimes,
      status: status ?? this.status,
      lastTakenAt: lastTakenAt ?? this.lastTakenAt,
      createdAt: createdAt ?? this.createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
      isFromOCR: isFromOCR ?? this.isFromOCR,
    );
  }

  static MedicationType parseMedicationType(String? value) {
    switch (value?.toLowerCase()) {
      case 'tablet': return MedicationType.tablet;
      case 'capsule': return MedicationType.capsule;
      case 'injection': return MedicationType.injection;
      case 'syrup': return MedicationType.syrup;
      case 'drops': return MedicationType.drops;
      case 'inhaler': return MedicationType.inhaler;
      case 'cream': return MedicationType.cream;
      default: return MedicationType.other;
    }
  }

  static MedicationFrequency parseMedicationFrequency(String? value) {
    switch (value?.toLowerCase()) {
      case 'once_daily': return MedicationFrequency.onceDaily;
      case 'twice_daily': return MedicationFrequency.twiceDaily;
      case 'three_times_daily': return MedicationFrequency.threeTimesDaily;
      case 'four_times_daily': return MedicationFrequency.fourTimesDaily;
      case 'as_needed': return MedicationFrequency.asNeeded;
      case 'weekly': return MedicationFrequency.weekly;
      case 'monthly': return MedicationFrequency.monthly;
      default: return MedicationFrequency.onceDaily;
    }
  }

  static MedicationStatus parseMedicationStatus(String? value) {
    switch (value?.toLowerCase()) {
      case 'taken': return MedicationStatus.taken;
      case 'skipped': return MedicationStatus.skipped;
      case 'missed': return MedicationStatus.missed;
      default: return MedicationStatus.pending;
    }
  }

  static MedicationType _parseMedicationType(String? value) {
    switch (value?.toLowerCase()) {
      case 'tablet': return MedicationType.tablet;
      case 'capsule': return MedicationType.capsule;
      case 'injection': return MedicationType.injection;
      case 'syrup': return MedicationType.syrup;
      case 'drops': return MedicationType.drops;
      case 'inhaler': return MedicationType.inhaler;
      case 'cream': return MedicationType.cream;
      default: return MedicationType.other;
    }
  }

  static MedicationFrequency _parseMedicationFrequency(String? value) {
    switch (value?.toLowerCase()) {
      case 'once_daily': return MedicationFrequency.onceDaily;
      case 'twice_daily': return MedicationFrequency.twiceDaily;
      case 'three_times_daily': return MedicationFrequency.threeTimesDaily;
      case 'four_times_daily': return MedicationFrequency.fourTimesDaily;
      case 'as_needed': return MedicationFrequency.asNeeded;
      case 'weekly': return MedicationFrequency.weekly;
      case 'monthly': return MedicationFrequency.monthly;
      default: return MedicationFrequency.onceDaily;
    }
  }

  static MedicationStatus _parseMedicationStatus(String? value) {
    switch (value?.toLowerCase()) {
      case 'taken': return MedicationStatus.taken;
      case 'skipped': return MedicationStatus.skipped;
      case 'missed': return MedicationStatus.missed;
      default: return MedicationStatus.pending;
    }
  }

  String get typeDisplay => type.typeDisplay;
  String get frequencyDisplay => frequency.frequencyDisplay;
  IconData get typeIcon => type.typeIcon;
}
