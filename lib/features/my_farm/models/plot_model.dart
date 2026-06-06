class Plot {
  final int id;
  final int farmId;
  final String plotName;
  final double? areaHectares;
  final String soilType;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Plot({
    required this.id,
    required this.farmId,
    required this.plotName,
    required this.areaHectares,
    required this.soilType,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Plot.fromJson(Map<String, dynamic> json) {
    return Plot(
      id: _toInt(json['id']),
      farmId: _toInt(json['farm_id']),
      plotName: json['plot_name'] as String,
      areaHectares: _toDouble(json['area_hectares']),
      soilType: json['soil_type']?.toString() ?? '',
      isActive: _toBool(json['is_active']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'farm_id': farmId,
      'plot_name': plotName,
      'area_hectares': areaHectares,
      'soil_type': soilType,
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

typedef PlotModel = Plot;
