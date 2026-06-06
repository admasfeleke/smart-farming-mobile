import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_copy.dart';
import '../../language_config.dart';
import '../disease/disease_prevention_screen.dart';
import '../profile/profile_screen.dart';
import '../sync/sync_diagnostics_screen.dart';
import '../../language_store.dart';
import '../../localization.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _languageCode = 'am';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = LanguageConfig.normalize(prefs.getString('language'));
    if (!mounted) return;
    setState(() {
      _languageCode = code;
    });
  }

  Future<void> _setLanguage(String code) async {
    final normalized = LanguageConfig.normalize(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', normalized);
    await LanguageStore.setLanguage(normalized);
    if (!mounted) return;
    setState(() {
      _languageCode = normalized;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L.t(_languageCode, 'language_updated'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageLabel = LanguageConfig.labelFor(_languageCode);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _MoreHeader(),
          const SizedBox(height: 16),
          _MoreTile(
            icon: Icons.person_outline,
            title: L.t(_languageCode, 'profile'),
            subtitle: L.t(_languageCode, 'profile_sub'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          _MoreTile(
            icon: Icons.sync,
            title: L.t(_languageCode, 'offline_sync'),
            subtitle: L.t(_languageCode, 'offline_sync_sub'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncDiagnosticsScreen()),
              );
            },
          ),
          _MoreTile(
            icon: Icons.rule,
            title: L.t(_languageCode, 'guidelines'),
            subtitle: L.t(_languageCode, 'guidelines_sub'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiseasePreventionScreen()),
              );
            },
          ),
          _MoreTile(
            icon: Icons.language,
            title: L.t(_languageCode, 'language'),
            subtitle: languageLabel,
            onTap: () => _showLanguagePicker(context),
          ),
          _MoreTile(
            icon: Icons.info_outline,
            title: L.t(_languageCode, 'about'),
            subtitle: L.t(_languageCode, 'about_sub'),
            onTap: () => _showAboutDialog(context),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: LanguageConfig.options.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final lang = LanguageConfig.options[i];
              final selected = lang.code == _languageCode;
              return ListTile(
                title: Text(lang.label),
                trailing: selected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () {
                  Navigator.of(context).pop();
                  _setLanguage(lang.code);
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(L.t(_languageCode, 'about')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t(_languageCode, 'about_sub')),
                const SizedBox(height: 12),
                Text(
                  AppCopy.t(_languageCode, 'about_project_summary'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  AppCopy.t(_languageCode, 'about_project_promotion'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  AppCopy.t(_languageCode, 'about_project_supported_crops'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  AppCopy.t(_languageCode, 'about_project_developer'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _AboutContactTile(
                  icon: Icons.email_outlined,
                  label: L.t(_languageCode, 'email'),
                  value: 'admasu.feleke21@gmail.com',
                ),
                _AboutContactTile(
                  icon: Icons.phone_outlined,
                  label: L.t(_languageCode, 'phone'),
                  value: '0900824328',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L.t(_languageCode, 'close')),
            ),
          ],
        );
      },
    );
  }
}

class _AboutContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AboutContactTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label copied')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
            const Icon(Icons.copy_outlined, size: 16),
          ],
        ),
      ),
    );
  }
}

class _MoreHeader extends StatelessWidget {
  const _MoreHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<String>(
          valueListenable: LanguageStore.notifier,
          builder: (context, lang, _) {
            return Text(L.t(lang, 'more'), style: textTheme.headlineSmall);
          },
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<String>(
          valueListenable: LanguageStore.notifier,
          builder: (context, lang, _) {
            return Text(
              L.t(lang, 'more_subtitle'),
              style: textTheme.bodyMedium?.copyWith(color: Colors.grey),
            );
          },
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap ?? () {},
      ),
    );
  }
}
