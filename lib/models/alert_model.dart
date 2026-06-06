class AlertModel {
  final int id;
  final int diseaseReportId;
  final int farmId;
  final int plotId;
  final int plantingId;
  final String alertType;
  final String severity;
  final String title;
  final String message;
  final String status;
  final bool isPreventive;
  final double? riskLevel;
  final String? farmName;
  final String? plotName;
  final DateTime triggeredAt;

  AlertModel({
    required this.id,
    required this.diseaseReportId,
    required this.farmId,
    required this.plotId,
    required this.plantingId,
    required this.alertType,
    required this.severity,
    required this.title,
    required this.message,
    required this.status,
    required this.isPreventive,
    required this.riskLevel,
    required this.farmName,
    required this.plotName,
    required this.triggeredAt,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    return AlertModel(
      id: _toInt(json['id']),
      diseaseReportId: _toInt(json['disease_report_id']),
      farmId: _toInt(json['farm_id']),
      plotId: _toInt(json['plot_id']),
      plantingId: _toInt(json['planting_id']),
      alertType: json['alert_type']?.toString() ?? '',
      severity: json['severity']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      isPreventive: json['is_preventive'] == true,
      riskLevel: _toDouble(json['risk_level']),
      farmName: _nullableTrimmed(json['farm_name']),
      plotName: _nullableTrimmed(json['plot_name']),
      triggeredAt: _parseDate(json['triggered_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
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

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String? _nullableTrimmed(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
