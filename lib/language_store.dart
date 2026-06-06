import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_config.dart';

class LanguageStore {
  static const String _languageKey = 'language';
  static final ValueNotifier<String> notifier =
      ValueNotifier<String>(LanguageConfig.fallbackCode);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = LanguageConfig.normalize(prefs.getString(_languageKey));
    if (prefs.getString(_languageKey) != code) {
      await prefs.setString(_languageKey, code);
    }
    notifier.value = code;
  }

  static Future<void> setLanguage(String code) async {
    final normalized = LanguageConfig.normalize(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, normalized);
    notifier.value = normalized;
  }
}
