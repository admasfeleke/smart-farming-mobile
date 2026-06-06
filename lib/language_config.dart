class LanguageOption {
  final String code;
  final String label;

  const LanguageOption({required this.code, required this.label});
}

class LanguageConfig {
  static const List<LanguageOption> options = [
    LanguageOption(code: 'am', label: 'አማርኛ'),
    LanguageOption(code: 'om', label: 'Afaan Oromo'),
    LanguageOption(code: 'ti', label: 'ትግርኛ'),
    LanguageOption(code: 'en', label: 'English'),
  ];

  static const String fallbackCode = 'am';

  static String normalize(String? raw) {
    final value = (raw ?? '').trim().toLowerCase().replaceAll('_', '-');
    if (value.isEmpty) return fallbackCode;

    if (value == 'am' || value == 'am-et' || value == 'amh' || value == 'amharic') {
      return 'am';
    }
    if (value == 'om' ||
        value == 'om-et' ||
        value == 'or' ||
        value == 'oromo' ||
        value == 'afaan-oromo' ||
        value == 'afaan oromo') {
      return 'om';
    }
    if (value == 'ti' ||
        value == 'ti-et' ||
        value == 'tigriya' ||
        value == 'tigrinya') {
      return 'ti';
    }
    if (value == 'en' || value == 'en-us' || value == 'en-gb' || value == 'english') {
      return 'en';
    }

    return fallbackCode;
  }

  static String labelFor(String? code) {
    final normalized = normalize(code);
    for (final option in options) {
      if (option.code == normalized) return option.label;
    }
    return options.last.label;
  }
}
