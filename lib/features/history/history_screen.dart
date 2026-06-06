import 'package:flutter/material.dart';

import '../disease/disease_check_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DiseaseCheckScreen(showHeader: false);
  }
}
