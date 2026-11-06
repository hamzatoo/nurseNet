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
    });
  }

  // Mark medication as skipped
  Future<void> markAsSkipped(String medicationId) async {
    await _medicationsCollection.doc(medicationId).update({
      'status': 'skipped',
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

  // Reset daily status for medications (call at midnight)
  Future<void> resetDailyStatus() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final endOfDay = startOfDay.add(const Duration(days: 1));
    final snapshot = await _medicationsCollection.get();

    for (final doc in snapshot.docs) {
      final medication = Medication.fromFirestore(doc);
      if (_isScheduledDuring(medication, startOfDay, endOfDay)) {
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
