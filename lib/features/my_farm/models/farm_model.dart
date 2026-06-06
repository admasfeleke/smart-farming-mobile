class Farm {
  final int id;
  final int farmerId;
  final int regionId;
  final String farmName;
  final double? latitude;
  final double? longitude;
  final double? areaHectares;
  final String? farmType;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Farm({
    required this.id,
    required this.farmerId,
    required this.regionId,
    required this.farmName,
    required this.latitude,
    required this.longitude,
    required this.areaHectares,
    required this.farmType,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Farm.fromJson(Map<String, dynamic> json) {
    return Farm(
      id: json['id'] as int,
      farmerId: _toInt(json['farmer_id']),
      regionId: json['region_id'] as int,
      farmName: json['farm_name'] as String,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      areaHectares: _toDouble(json['area_hectares']),
      farmType: json['farm_type'] as String?,
      isActive: _toBool(json['is_active']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'farmer_id': farmerId,
      'region_id': regionId,
      'farm_name': farmName,
      'latitude': latitude,
      'longitude': longitude,
      'area_hectares': areaHectares,
      'farm_type': farmType,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true' || normalized == 'yes';
    }
    return false;
  }
}

typedef FarmModel = Farm;
