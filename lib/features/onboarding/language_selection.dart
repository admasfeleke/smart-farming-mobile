import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'intro_slides.dart';
import '../../language_store.dart';
import '../../language_config.dart';
import '../../localization.dart';
import '../../widgets/farm_ui.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  final List<Map<String, String>> _languages = LanguageConfig.options
      .map((l) => {'code': l.code, 'label': l.label, 'flag': 'ET'})
      .toList(growable: false);

  int _selectedIndex = 0; // default to Amharic

  Future<void> _saveLanguageAndContinue() async {
    final prefs = await SharedPreferences.getInstance();
    final code = LanguageConfig.normalize(_languages[_selectedIndex]['code']);
    await prefs.setString('language', code);
    await LanguageStore.setLanguage(code);
    // Show intro slides next
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const IntroSlides()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(L.t(LanguageStore.notifier.value, 'language'))),
      body: SafeArea(
        child: FarmSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 170,
                child: FarmHeroCard(
                  imageAsset: 'assets/images/crops/maize.jpg',
                  eyebrow: 'Smart Farming Ethiopia',
                  title: L.t(LanguageStore.notifier.value, 'language'),
                  body: 'Choose the language farmers will use in the field.',
                  trailing: const Icon(Icons.language_rounded, color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  itemCount: _languages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final lang = _languages[i];
                    final selected = i == _selectedIndex;
                    return Material(
                      color: selected ? const Color(0xFFF1FFD3) : const Color(0xFFFFFDF5),
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        onTap: () => setState(() => _selectedIndex = i),
                        borderRadius: BorderRadius.circular(22),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.language, size: 24, color: theme.colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(lang['label']!, style: theme.textTheme.titleMedium),
                              ),
                              if (selected) const Icon(Icons.check_circle, color: Color(0xFF4F7D12)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              ElevatedButton(
                onPressed: _saveLanguageAndContinue,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: Text(L.t(LanguageStore.notifier.value, 'save'), style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

