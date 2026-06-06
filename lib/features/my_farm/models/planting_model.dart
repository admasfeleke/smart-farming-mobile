class Planting {
  final int id;
  final int plotId;
  final int cropId;
  final DateTime plantingDate;
  final DateTime? expectedHarvestDate;
  final String status;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Planting({
    required this.id,
    required this.plotId,
    required this.cropId,
    required this.plantingDate,
    required this.expectedHarvestDate,
    required this.status,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Planting.fromJson(Map<String, dynamic> json) {
    return Planting(
      id: _toInt(json['id']),
      plotId: _toInt(json['plot_id']),
      cropId: _toInt(json['crop_id']),
      plantingDate:
          _parseDate(json['planting_date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      expectedHarvestDate: json['expected_harvest_date'] != null
          ? _parseDate(json['expected_harvest_date'])
          : null,
      status: json['status']?.toString() ?? '',
      isActive: _toBool(json['is_active']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'plot_id': plotId,
      'crop_id': cropId,
      'planting_date': plantingDate.toIso8601String(),
      'expected_harvest_date': expectedHarvestDate?.toIso8601String(),
      'status': status,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
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
}

typedef PlantingModel = Planting;
