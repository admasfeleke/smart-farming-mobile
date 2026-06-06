import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_farm/features/home/home_screen.dart';
import 'package:smart_farm/language_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await LanguageStore.setLanguage('en');
  });

  testWidgets('Home screen shows primary smart farming action cards', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.text('Smart Farming'), findsOneWidget);
    expect(find.text('Crop Health'), findsOneWidget);
    expect(find.text('Disease Check'), findsOneWidget);
    expect(find.text('Soil & Water'), findsOneWidget);
    expect(find.text('Market Prices'), findsOneWidget);
  });
}
