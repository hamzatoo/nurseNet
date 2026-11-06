import 'package:cloud_firestore/cloud_firestore.dart';

/// Medical category derived from a resting heart-rate reading.
enum HeartRateCategory { low, normal, elevated, high }

/// A single contactless (rPPG) heart-rate measurement.
class HeartRateReading {
  const HeartRateReading({
    required this.bpm,
    required this.quality,
    required this.durationSeconds,
    required this.measuredAt,
    this.id,
  });

  /// Beats per minute estimated by the backend.
  final int bpm;

  /// Share of in-band spectral power on the winning peak (0-1). Higher is more
  /// trustworthy; values under 0.25 are shown as a weak signal.
  final double quality;

  /// Length of the analysed clip in seconds.
  final double durationSeconds;

  final DateTime measuredAt;

  /// Firestore document id, present once the reading is saved.
  final String? id;

  HeartRateCategory get category {
    if (bpm < 60) return HeartRateCategory.low;
    if (bpm <= 100) return HeartRateCategory.normal;
    if (bpm <= 120) return HeartRateCategory.elevated;
    return HeartRateCategory.high;
  }

  String get categoryLabel => switch (category) {
    HeartRateCategory.low => 'منخفض',
    HeartRateCategory.normal => 'طبيعي',
    HeartRateCategory.elevated => 'مرتفع',
    HeartRateCategory.high => 'مرتفع جداً',
  };

  String get advice => switch (category) {
    HeartRateCategory.low =>
      'نبضك أبطأ من المعتاد. إن رافقه دوار أو تعب، راجع مختصاً صحياً.',
    HeartRateCategory.normal =>
      'نبضك ضمن النطاق الطبيعي للراحة. استمر في نشاطك وترطيب جسمك.',
    HeartRateCategory.elevated =>
      'نبضك أعلى قليلاً من الطبيعي. اجلس واسترح 5 دقائق ثم أعد القياس.',
    HeartRateCategory.high =>
      'نبضك مرتفع بشكل ملحوظ. أعد القياس بعد الراحة، وإن استمر فاستشر طبيباً.',
  };

  /// Confidence wording shown under the BPM value.
  String get qualityLabel {
    if (quality >= 0.45) return 'إشارة ممتازة';
    if (quality >= 0.25) return 'إشارة جيدة';
    return 'إشارة ضعيفة';
  }

  double get qualityPercent => (quality.clamp(0.0, 1.0) * 100);

  HeartRateReading copyWith({String? id}) => HeartRateReading(
    bpm: bpm,
    quality: quality,
    durationSeconds: durationSeconds,
    measuredAt: measuredAt,
    id: id ?? this.id,
  );

  /// Builds a reading from the `POST /api/calculate-heart-rate` response.
  factory HeartRateReading.fromApi(Map<String, dynamic> json) {
    return HeartRateReading(
      bpm: (json['bpm'] as num).toInt(),
      quality: (json['quality'] as num?)?.toDouble() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0,
      measuredAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'bpm': bpm,
    'quality': quality,
    'durationSeconds': durationSeconds,
    'category': category.name,
    'measuredAt': Timestamp.fromDate(measuredAt),
    'source': 'rppg',
  };

  factory HeartRateReading.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final timestamp = data['measuredAt'];
    return HeartRateReading(
      id: doc.id,
      bpm: (data['bpm'] as num?)?.toInt() ?? 0,
      quality: (data['quality'] as num?)?.toDouble() ?? 0,
      durationSeconds: (data['durationSeconds'] as num?)?.toDouble() ?? 0,
      measuredAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
    );
  }
}
