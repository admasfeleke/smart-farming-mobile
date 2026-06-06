import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../auth_session.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../localized_value.dart';
import '../../offline/local_cache_store.dart';
import '../../widgets/farm_ui.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const String _profileCacheKey = 'profile_cache_v1';

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profile = <String, dynamic>{};
  DateTime? _cachedUpdatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final cachedName = await AuthSession.getUserName();
    final cachedRole = await AuthSession.getUserRole();

    if (mounted) {
      final cachedProfile = await LocalCacheStore.instance.readMap(_profileCacheKey);
      final cachedUpdatedAt = await LocalCacheStore.instance.readUpdatedAt(_profileCacheKey);
      setState(() {
        _profile = <String, dynamic>{
          ...(cachedProfile ?? const <String, dynamic>{}),
          if ((cachedName ?? '').trim().isNotEmpty) 'name': cachedName!.trim(),
          if ((cachedRole ?? '').trim().isNotEmpty) 'role_name': cachedRole!.trim(),
        };
        _cachedUpdatedAt = cachedUpdatedAt;
      });
    }

    try {
      final serverProfile = await ApiClient.getCurrentUserProfile();
      if ((serverProfile['name'] ?? '').toString().trim().isNotEmpty) {
        await AuthSession.saveUserName(serverProfile['name'].toString().trim());
      }
      if ((serverProfile['role_name'] ?? '').toString().trim().isNotEmpty) {
        await AuthSession.saveUserRole(serverProfile['role_name'].toString().trim());
      }
      await LocalCacheStore.instance.write(_profileCacheKey, serverProfile);
      if (!mounted) return;
      setState(() {
        _profile = serverProfile;
        _cachedUpdatedAt = DateTime.now();
        _loading = false;
      });
    } on ApiUnauthorized {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      final lang = LanguageStore.notifier.value;
      final friendlyMessage = _profile.isNotEmpty
          ? L.t(
              lang,
              'profile_refresh_failed_saved',
              params: {'error': ''},
            ).replaceAll(RegExp(r'\s*\{error\}\s*'), '').trim()
          : (ApiClient.isConnectivityIssueMessage(e.toString())
                ? L.t(lang, 'weather_unavailable')
                : L.t(lang, 'unexpected_error'));
      setState(() {
        _loading = false;
        _error = friendlyMessage;
      });
    }
  }

  String _value(String key, {String? fallback}) {
    final value = _profile[key]?.toString().trim() ?? '';
    final effectiveFallback =
        fallback ?? LocalizedValue.fixed(LanguageStore.notifier.value, 'not_available');
    return value.isEmpty ? effectiveFallback : value;
  }

  String _friendlyRole(String lang) {
    final role = _value('role_name', fallback: 'farmer').trim().toLowerCase();
    return LocalizedValue.role(lang, role);
  }

  String _statusLabel(String lang) {
    return _profile['is_active'] == true || _profile['is_active'] == 1
        ? L.t(lang, 'profile_status_active')
        : L.t(lang, 'profile_status_saved_only');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(L.t(lang, 'profile')),
          ),
          body: FarmSurface(
            padding: EdgeInsets.zero,
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: const Icon(Icons.person, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _value('name', fallback: L.t(lang, 'profile_role_farmer')),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _friendlyRole(lang),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                        tooltip: L.t(lang, 'profile_refresh_tooltip'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (_cachedUpdatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      L.t(
                        lang,
                        'profile_saved_updated_at',
                        params: {'time': _cachedUpdatedAt!.toLocal().toString()},
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _ProfileTile(
                    icon: Icons.badge_outlined,
                    label: L.t(lang, 'profile_full_name'),
                    value: _value('name', fallback: L.t(lang, 'profile_role_farmer')),
                  ),
                  _ProfileTile(
                    icon: Icons.verified_user_outlined,
                    label: L.t(lang, 'profile_role_label'),
                    value: _friendlyRole(lang),
                  ),
                  if ((_profile['phone'] ?? '').toString().trim().isNotEmpty)
                    _ProfileTile(
                      icon: Icons.phone_outlined,
                      label: L.t(lang, 'profile_phone_label'),
                      value: _value('phone'),
                    ),
                  if ((_profile['email'] ?? '').toString().trim().isNotEmpty)
                    _ProfileTile(
                      icon: Icons.email_outlined,
                      label: L.t(lang, 'profile_email_label'),
                      value: _value('email'),
                    ),
                  _ProfileTile(
                    icon: Icons.toggle_on_outlined,
                    label: L.t(lang, 'profile_status_label'),
                    value: _statusLabel(lang),
                  ),
                ],
              ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}
