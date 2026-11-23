import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication_model.dart';

class MedicationService {
  static final MedicationService _instance = MedicationService._internal();
  factory MedicationService() => _instance;
  MedicationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  // Get medications collection for current user
  CollectionReference get _medicationsCollection {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }
    return _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('medications');
  }

  // Add new medication
  Future<String> addMedication(Medication medication) async {
    final docRef = await _medicationsCollection.add(medication.toFirestore());
    return docRef.id;
  }

  // Update medication
  Future<void> updateMedication(Medication medication) async {
    await _medicationsCollection
        .doc(medication.id)
        .update(medication.toFirestore());
  }

  // Delete medication
  Future<void> deleteMedication(String medicationId) async {
    await _medicationsCollection.doc(medicationId).delete();
  }

  // Get all medications for current user. Sorting locally avoids requiring an index.
  Stream<List<Medication>> getMedicationsStream() {
    return _medicationsCollection.snapshots().map((snapshot) {
      final medications = snapshot.docs
          .map((doc) => Medication.fromFirestore(doc))
          .toList();
      return _sortByStartDateDescending(medications);
    });
  }

  // Get medications for a specific date
  Stream<List<Medication>> getMedicationsForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _medicationsCollection.snapshots().map((snapshot) {
      final medications = snapshot.docs
          .map((doc) => Medication.fromFirestore(doc))
          .where(
            (medication) =>
                _isScheduledDuring(medication, startOfDay, endOfDay),
          )
          .toList();
      return _sortByStartDateDescending(medications);
    });
  }

  // Mark medication as taken
  Future<void> markAsTaken(String medicationId) async {
    await _medicationsCollection.doc(medicationId).update({
      'status': 'taken',
      'lastTakenAt': FieldValue.serverTimestamp(),
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Mark medication as skipped
  Future<void> markAsSkipped(String medicationId) async {
    await _medicationsCollection.doc(medicationId).update({
      'status': 'skipped',
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Get medications scheduled for today
  Stream<List<Medication>> getTodayMedications() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _medicationsCollection.snapshots().map((snapshot) {
      final medications = snapshot.docs
          .map((doc) => Medication.fromFirestore(doc))
          .where(
            (medication) =>
                _isScheduledDuring(medication, startOfDay, endOfDay),
          )
          .toList();
      return _sortByStartDateDescending(medications);
    });
  }

  // Get medications that need to be taken today (not yet taken)
  Stream<List<Medication>> getPendingMedicationsForToday() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _medicationsCollection.snapshots().map((snapshot) {
      final medications = snapshot.docs
          .map((doc) => Medication.fromFirestore(doc))
          .where(
            (medication) =>
                medication.status == MedicationStatus.pending &&
                _isScheduledDuring(medication, startOfDay, endOfDay),
          )
          .toList();
      return _sortByStartDateDescending(medications);
    });
  }

  // Reset daily dose marks: any medication whose status was last changed
  // BEFORE today goes back to pending so the new day's doses appear.
  // Marks made today are preserved. Safe to call on every screen open.
  Future<void> resetDailyStatus() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final snapshot = await _medicationsCollection.get();
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      final status = data['status'] as String? ?? 'pending';
      if (status == 'pending') continue;

      // Latest known activity timestamp for this medication's status.
      DateTime? activity;
      for (final key in ['statusUpdatedAt', 'lastTakenAt']) {
        final ts = data[key];
        if (ts is Timestamp) {
          final dt = ts.toDate();
          if (activity == null || dt.isAfter(activity)) activity = dt;
        }
      }

      // No timestamp -> legacy doc, treat as stale. Timestamp before today
      // -> yesterday's (or older) mark, reset for the new day.
      final stale = activity == null || activity.isBefore(startOfDay);
      if (stale) {
        await doc.reference.update({'status': 'pending'});
      }
    }
  }

  bool _isScheduledDuring(
    Medication medication,
    DateTime startOfDay,
    DateTime endOfDay,
  ) {
    // A treatment overlaps this date when it starts before the next day and
    // ends on or after the start of this day. The end boundary is exclusive.
    return medication.startDate.isBefore(endOfDay) &&
        !medication.endDate.isBefore(startOfDay);
  }

  List<Medication> _sortByStartDateDescending(List<Medication> medications) {
    medications.sort((a, b) => b.startDate.compareTo(a.startDate));
    return medications;
  }
}
