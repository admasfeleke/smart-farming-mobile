import 'package:flutter/material.dart';
import '../../../offline/offline_models.dart';

class FarmContextProvider extends ChangeNotifier {
  FarmRecord? selectedFarm;
  PlotRecord? selectedPlot;
  PlantingRecord? selectedPlanting;

  void setFarm(FarmRecord farm) {
    selectedFarm = farm;
    selectedPlot = null;
    selectedPlanting = null;
    notifyListeners();
  }

  void setPlot(PlotRecord plot) {
    selectedPlot = plot;
    selectedPlanting = null;
    notifyListeners();
  }

  void setPlanting(PlantingRecord planting) {
    selectedPlanting = planting;
    notifyListeners();
  }

  void clearSelection() {
    selectedFarm = null;
    selectedPlot = null;
    selectedPlanting = null;
    notifyListeners();
  }

  void clearPlotSelection() {
    selectedPlot = null;
    selectedPlanting = null;
    notifyListeners();
  }
}
