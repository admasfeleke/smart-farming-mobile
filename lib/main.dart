import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'features/my_farm/providers/farm_context_provider.dart';

void main() {
  runApp(ChangeNotifierProvider(create: (_) => FarmContextProvider(), child: const App()));
}
