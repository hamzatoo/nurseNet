class PredictionRequest {
  final double feature1;
  final double feature2;
  final double feature3;
  final double feature4;
  final double feature5;
  final double feature6;
  final double feature7;
  final double feature8;

  PredictionRequest({
    required this.feature1,
    required this.feature2,
    required this.feature3,
    required this.feature4,
    required this.feature5,
    required this.feature6,
    required this.feature7,
    required this.feature8,
  });

  Map<String, dynamic> toJson() {
    return {
      'feature1': feature1,
      'feature2': feature2,
      'feature3': feature3,
      'feature4': feature4,
      'feature5': feature5,
      'feature6': feature6,
      'feature7': feature7,
      'feature8': feature8,
    };
  }

  factory PredictionRequest.fromJson(Map<String, dynamic> json) {
    // التعامل مع القيم بشكل آمن - قد تكون Lists أو nums
    safeDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is num) return first.toDouble();
      }
      return 0.0;
    }

    return PredictionRequest(
      feature1: safeDouble(json['feature1']),
      feature2: safeDouble(json['feature2']),
      feature3: safeDouble(json['feature3']),
      feature4: safeDouble(json['feature4']),
      feature5: safeDouble(json['feature5']),
      feature6: safeDouble(json['feature6']),
      feature7: safeDouble(json['feature7']),
      feature8: safeDouble(json['feature8']),
    );
  }
}

class PredictionResponse {
  final dynamic prediction; // يمكن أن يكون List أو double
  final String? message;
  final DateTime timestamp;
  final String? status;
  final bool? saved;
  final List<dynamic>? matchedProviders;

  PredictionResponse({
    required this.prediction,
    this.message,
    required this.timestamp,
    this.status,
    this.saved,
    this.matchedProviders,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    // التعامل مع prediction بشكل آمن - يمكن أن يكون List أو num
    dynamic predictionValue = json['prediction'];
    if (predictionValue is List) {
      // إذا كان List، نحافظه كما هو
      predictionValue = predictionValue;
    } else if (predictionValue is num) {
      // إذا كان رقم، نحوله إلى double
      predictionValue = predictionValue.toDouble();
    }

    return PredictionResponse(
      prediction: predictionValue,
      message: json['message'] as String?,
      timestamp: DateTime.now(),
      status: json['status'] as String?,
      saved: json['saved'] as bool?,
      matchedProviders: json['matched_providers'] as List<dynamic>?,
    );
  }
}

class FirebaseStatus {
  final bool isConnected;
  final String? message;
  final DateTime timestamp;

  FirebaseStatus({
    required this.isConnected,
    this.message,
    required this.timestamp,
  });

  factory FirebaseStatus.fromJson(Map<String, dynamic> json) {
    return FirebaseStatus(
      isConnected: json['connected'] as bool? ?? json['isConnected'] as bool? ?? false,
      message: json['message'] as String?,
      timestamp: DateTime.now(),
    );
  }
}