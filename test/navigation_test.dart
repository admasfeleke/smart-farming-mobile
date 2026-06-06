import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_farm/app.dart';
import 'package:smart_farm/features/my_farm/providers/farm_context_provider.dart';
import 'package:smart_farm/language_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'language': 'en',
      'auth_token': 'test-token',
    });
    await LanguageStore.setLanguage('en');
  });

  testWidgets('Bottom navigation switches tabs and keeps shell stable', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FarmContextProvider(),
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('My Farm'), findsWidgets);
    expect(find.text('Scan'), findsWidgets);
    expect(find.text('Alerts'), findsWidgets);
    expect(find.text('Pest Detection'), findsWidgets);

    await tester.tap(find.text('My Farm').last);
    await tester.pumpAndSettle();
    expect(find.text('My Farm'), findsWidgets);

    await tester.tap(find.text('Alerts').last);
    await tester.pumpAndSettle();
    expect(find.text('Alerts'), findsWidgets);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('Smart Farming'), findsOneWidget);
  });
}
