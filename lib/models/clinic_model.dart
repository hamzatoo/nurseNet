class ClinicCoordinates {
  final double latitude;
  final double longitude;

  const ClinicCoordinates({required this.latitude, required this.longitude});

  factory ClinicCoordinates.fromJson(Map<String, dynamic> json) {
    return ClinicCoordinates(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class Clinic {
  final String id;
  final String name;
  final String region;
  final String address;
  final ClinicCoordinates coordinates;
  final String phone;
  final List<String> specialties;
  final String imageUrl;

  const Clinic({
    required this.id,
    required this.name,
    required this.region,
    required this.address,
    required this.coordinates,
    required this.phone,
    required this.specialties,
    required this.imageUrl,
  });

  factory Clinic.fromJson(Map<String, dynamic> json) {
    return Clinic(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      region: json['region'] as String? ?? '',
      address: json['address'] as String? ?? '',
      coordinates: ClinicCoordinates.fromJson(
        (json['coordinates'] as Map<String, dynamic>?) ?? const {},
      ),
      phone: json['phone'] as String? ?? '',
      specialties: (json['specialties'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      imageUrl: json['image_url'] as String? ?? '',
    );
  }

  /// Whether the clinic has a real dialable phone number
  /// (filters out "غير متوفر" / "متاح بالمركز").
  bool get hasDialablePhone => RegExp(r'^\+?[\d\s]{6,}$').hasMatch(phone.trim());
}
