import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  final String id;
  final String nurseId;
  final String patientId;
  final String patientName;
  final int rating;
  final String comment;
  final DateTime createdAt;

  Review({
    required this.id,
    required this.nurseId,
    required this.patientId,
    required this.patientName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory Review.fromFirestore(Map<String, dynamic> data, String id) {
    return Review(
      id: id,
      nurseId: data['nurseId']?.toString() ?? '',
      patientId: data['patientId']?.toString() ?? '',
      patientName: data['patientName']?.toString() ?? '',
      rating: data['rating'] is int ? data['rating'] as int : (data['rating'] is double ? (data['rating'] as double).toInt() : 0),
      comment: data['comment']?.toString() ?? '',
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nurseId': nurseId,
      'patientId': patientId,
      'patientName': patientName,
      'rating': rating,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

class ReviewsService {
  ReviewsService._();
  static final ReviewsService instance = ReviewsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// إضافة مراجعة جديدة وحساب متوسط التقييم
  Future<bool> addReview({
    required String nurseId,
    required String patientId,
    required String patientName,
    required int rating,
    required String comment,
  }) async {
    try {
      // 1. إضافة المراجعة إلى مجموعة reviews
      final reviewRef = _firestore.collection('reviews').doc();
      final review = Review(
        id: reviewRef.id,
        nurseId: nurseId,
        patientId: patientId,
        patientName: patientName,
        rating: rating,
        comment: comment,
        createdAt: DateTime.now(),
      );

      await reviewRef.set(review.toMap());

      // 2. تحديث إحصائيات التقييم للممرض
      await _updateNurseRating(nurseId);

      return true;
    } catch (e) {
      print('Error adding review: $e');
      return false;
    }
  }

  /// تحديث متوسط التقييم للممرض
  Future<void> _updateNurseRating(String nurseId) async {
    try {
      // جلب جميع مراجعات الممرض
      final reviewsSnapshot = await _firestore
          .collection('reviews')
          .where('nurseId', isEqualTo: nurseId)
          .get();

      final reviews = reviewsSnapshot.docs.map((doc) {
        return Review.fromFirestore(doc.data(), doc.id);
      }).toList();

      if (reviews.isEmpty) {
        // إذا لم توجد مراجعات، إعادة التعيين إلى الصفر
        await _firestore.collection('users').doc(nurseId).update({
          'averageRating': 0.0,
          'totalReviews': 0,
        });
        return;
      }

      // حساب المتوسط
      final totalRating = reviews.fold<int>(0, (accumulator, review) => accumulator + review.rating);
      final averageRating = totalRating / reviews.length;
      final totalReviews = reviews.length;

      // تحديث بيانات الممرض
      await _firestore.collection('users').doc(nurseId).update({
        'averageRating': averageRating,
        'totalReviews': totalReviews,
      });

      // تحديث مجموعة nurses أيضاً
      await _firestore.collection('nurses').doc(nurseId).update({
        'averageRating': averageRating,
        'totalReviews': totalReviews,
      });
    } catch (e) {
      print('Error updating nurse rating: $e');
    }
  }

  /// الحصول على مراجعات ممرض معين
  Stream<List<Review>> getNurseReviews(String nurseId) {
    return _firestore
        .collection('reviews')
        .where('nurseId', isEqualTo: nurseId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Review.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  /// التحقق مما إذا كان المريض قيّم الممرض من قبل
  Future<bool> hasPatientReviewedNurse(String patientId, String nurseId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('patientId', isEqualTo: patientId)
          .where('nurseId', isEqualTo: nurseId)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking if patient reviewed nurse: $e');
      return false;
    }
  }

  /// الحصول على مراجعة محددة
  Future<Review?> getReviewByPatientAndNurse(String patientId, String nurseId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('patientId', isEqualTo: patientId)
          .where('nurseId', isEqualTo: nurseId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      return Review.fromFirestore(doc.data(), doc.id);
    } catch (e) {
      print('Error getting review: $e');
      return null;
    }
  }
}