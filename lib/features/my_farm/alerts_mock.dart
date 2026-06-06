import '../../models/alert_model.dart';
import '../../models/disease_report_model.dart';

List<AlertModel> _alerts = [];
List<DiseaseReportModel> _diseaseReports = [];
Map<int, int> _plotFarmMap = {};

void setAlerts(List<AlertModel> alerts) {
  _alerts = alerts;
}

void setDiseaseReports(List<DiseaseReportModel> reports) {
  _diseaseReports = reports;
}

void setPlotFarmMap(Map<int, int> map) {
  _plotFarmMap = map;
}

bool hasAlertsForScope({int? farmId, int? plotId, int? plantingId}) {
  if (farmId == null && plotId == null && plantingId == null) return false;
  if (_alerts.isEmpty) return false;

  int? reportPlotId(AlertModel alert) {
    for (final report in _diseaseReports) {
      if (report.id == alert.diseaseReportId) {
        return report.plotId;
      }
    }
    return null;
  }

  int? reportPlantingId(AlertModel alert) {
    for (final report in _diseaseReports) {
      if (report.id == alert.diseaseReportId) {
        return report.plantingId;
      }
    }
    return null;
  }

  return _alerts.any((alert) {
    final pId = reportPlotId(alert);
    final planting = reportPlantingId(alert);
    if (plantingId != null && planting != null && planting == plantingId) return true;
    if (plotId != null && pId != null && pId == plotId) return true;
    if (farmId != null && pId != null) {
      final mappedFarm = _plotFarmMap[pId];
      if (mappedFarm != null && mappedFarm == farmId) return true;
    }
    return false;
  });
}
