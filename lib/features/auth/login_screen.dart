import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth_session.dart';
import '../../api_client.dart';
import '../../app_copy.dart';
import '../../connectivity_status_service.dart';
import '../../language_store.dart';
import '../../language_config.dart';
import '../../offline/account_data_reset_service.dart';
import '../../reference/reference_data.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _apiController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;
  String _languageCode = 'am';
  bool _useCustomApi = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  static const String _rememberMeKey = 'auth_remember_me';
  static const String _rememberedPhoneKey = 'auth_remembered_phone';

  List<Map<String, String>> get _languages => LanguageConfig.options
      .map((l) => {'code': l.code, 'label': l.label})
      .toList(growable: false);

  Future<void> _prepareFarmerSession(String phone) async {
    final normalizedPhone = AuthSession.normalizeFarmerPhone(phone);
    if (normalizedPhone.isEmpty) return;
    if (await AuthSession.isDifferentActiveFarmer(normalizedPhone)) {
      await AccountDataResetService.instance.clearFarmerOwnedData();
    }
    await AuthSession.saveActiveFarmerPhone(normalizedPhone);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _apiController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = LanguageConfig.normalize(prefs.getString('language'));
    await prefs.setString('language', code);
    final storedBaseUrl = await AuthSession.getApiBaseUrl();
    final rememberMe = prefs.getBool(_rememberMeKey) ?? false;
    final rememberedPhone = prefs.getString(_rememberedPhoneKey) ?? '';
    if (!mounted) return;
    setState(() {
      _languageCode = LanguageConfig.normalize(code);
      if (storedBaseUrl != null && storedBaseUrl.isNotEmpty) {
        _apiController.text = storedBaseUrl;
        _useCustomApi = true;
      }
      _rememberMe = rememberMe;
      if (rememberMe && rememberedPhone.isNotEmpty) {
        _phoneController.text = rememberedPhone;
      }
    });
  }

  Future<void> _setLanguage(String code) async {
    final normalized = LanguageConfig.normalize(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', normalized);
    await LanguageStore.setLanguage(normalized);
    if (!mounted) return;
    setState(() {
      _languageCode = LanguageConfig.normalize(code);
    });
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final normalizedPhone = ApiClient.normalizePhoneForLogin(phone);
    final password = _passwordController.text;
    final baseUrl = _apiController.text.trim();

    setState(() {
      _errorText = null;
    });

    if (phone.isEmpty || password.isEmpty) {
      setState(() {
        _errorText = _t('error_required');
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, _rememberMe);
    if (_rememberMe) {
      await prefs.setString(
        _rememberedPhoneKey,
        normalizedPhone.isEmpty ? phone : normalizedPhone,
      );
    } else {
      await prefs.remove(_rememberedPhoneKey);
    }

    if (_useCustomApi || baseUrl.isNotEmpty) {
      if (baseUrl.isEmpty) {
        setState(() {
          _errorText = _t('error_api_required');
        });
        return;
      }
      try {
        final normalized = ApiClient.validateAndNormalizeBaseUrl(baseUrl);
        await AuthSession.saveApiBaseUrl(normalized);
      } on ApiException catch (e) {
        setState(() {
          _errorText = e.message;
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final loginPhone = normalizedPhone.isEmpty ? phone : normalizedPhone;
      final offlineProofValid = await AuthSession.hasValidOfflineLoginProof();
      if (offlineProofValid) {
        final status = await ConnectivityStatusService.instance.refreshNow();
        if (status.state != ApiConnectivityState.apiOnline) {
          final unlocked = await AuthSession.tryOfflineUnlock(
            phone: loginPhone,
            password: password,
          );
          if (unlocked) {
            await _prepareFarmerSession(loginPhone);
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorText = null;
            });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_t('offline_unlocked'))));
            Navigator.of(context).pushReplacementNamed('/home');
            return;
          }
        }
      }
      final result = await ApiClient.login(
        phone: loginPhone,
        password: password,
      );
      await _prepareFarmerSession(loginPhone);
      await AuthSession.saveToken(result.token);
      await AuthSession.saveRefreshToken(result.refreshToken);
      await AuthSession.setOfflineModeActive(false);
      if (result.userName != null && result.userName!.trim().isNotEmpty) {
        await AuthSession.saveUserName(result.userName!.trim());
      }
      if (result.roleName != null && result.roleName!.trim().isNotEmpty) {
        await AuthSession.saveUserRole(result.roleName!.trim());
      }
      try {
        await AuthSession.saveOfflineLoginProof(
          phone: normalizedPhone.isEmpty ? phone : normalizedPhone,
          password: password,
        );
      } catch (error, stackTrace) {
        developer.log(
          'Offline login proof save failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      Navigator.of(context).pushReplacementNamed('/home');
    } on ApiException catch (e) {
      var hasProof = false;
      if (_looksLikeConnectivityIssue(e.message)) {
        final currentBaseUrl = await ApiClient.currentBaseUrlForDisplay();
        if (mounted && !_useCustomApi) {
          setState(() {
            _useCustomApi = true;
            if (_apiController.text.trim().isEmpty) {
              _apiController.text = currentBaseUrl;
            }
          });
        }
        hasProof = await AuthSession.hasValidOfflineLoginProof();
        final blockedUntil = await AuthSession.offlineUnlockBlockedUntil();
        if (blockedUntil != null) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorText = _t('offline_lockout');
          });
          return;
        }
        final unlocked = await AuthSession.tryOfflineUnlock(
          phone: normalizedPhone.isEmpty ? phone : normalizedPhone,
          password: password,
        );
        if (unlocked) {
          await _prepareFarmerSession(
            normalizedPhone.isEmpty ? phone : normalizedPhone,
          );
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorText = null;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_t('offline_unlocked'))));
          Navigator.of(context).pushReplacementNamed('/home');
          return;
        }
      }
      final pending = await AuthSession.getPendingLocalRegistration();
      final loginPhone = normalizedPhone.isEmpty ? phone : normalizedPhone;
      if (pending != null &&
          pending.phone == loginPhone &&
          pending.password == password &&
          !_looksLikeConnectivityIssue(e.message)) {
        try {
          final result = await ApiClient.registerFarmer(
            name: pending.name,
            phone: pending.phone,
            password: pending.password,
            email: pending.email,
            regionId: pending.regionId,
          );
          await _prepareFarmerSession(pending.phone);
          await AuthSession.saveToken(result.token);
          await AuthSession.saveRefreshToken(result.refreshToken);
          await AuthSession.setOfflineModeActive(false);
          await AuthSession.saveUserName(
            (result.userName ?? pending.name).trim(),
          );
          await AuthSession.saveUserRole((result.roleName ?? 'farmer').trim());
          await AuthSession.saveOfflineLoginProof(
            phone: pending.phone,
            password: pending.password,
          );
          await AuthSession.clearPendingLocalRegistration();
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });
          Navigator.of(context).pushReplacementNamed('/home');
          return;
        } on ApiException catch (registrationError) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorText = registrationError.message;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = _looksLikeConnectivityIssue(e.message)
            ? (hasProof
                  ? _t('offline_login_retry')
                  : '${e.message} ${_t('first_login_online')}')
            : e.message;
      });
    } catch (error, stackTrace) {
      developer.log(
        'Login submit failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = kDebugMode ? error.toString() : _t('error_generic');
      });
    }
  }

  bool _looksLikeConnectivityIssue(String message) {
    return ApiClient.isConnectivityIssueMessage(message);
  }

  Future<void> _showCreateLocalAccountDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController(
      text: _phoneController.text.trim(),
    );
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final regionOptions = ReferenceData.regions
        .where((item) => (item['is_active'] as int? ?? 1) == 1)
        .map(
          (item) => MapEntry<int, String>(
            item['id'] as int,
            '${item['name']} (${item['level']})',
          ),
        )
        .toList(growable: false);
    var selectedRegionId = 3001;
    var obscurePassword = true;
    var dialogError = '';

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: !_isLoading,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> createAccount() async {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final normalizedPhone = ApiClient.normalizePhoneForLogin(phone);
              final password = passwordController.text;
              final confirm = confirmController.text;
              final email = emailController.text.trim();

              if (name.isEmpty ||
                  normalizedPhone.isEmpty ||
                  password.isEmpty ||
                  confirm.isEmpty ||
                  selectedRegionId <= 0) {
                setDialogState(() {
                  dialogError = _t('local_account_required');
                });
                return;
              }
              if (password.length < 6) {
                setDialogState(() {
                  dialogError = _t('local_account_password_short');
                });
                return;
              }
              if (password != confirm) {
                setDialogState(() {
                  dialogError = _t('local_account_password_mismatch');
                });
                return;
              }
              if (_apiController.text.trim().isNotEmpty) {
                try {
                  final normalizedApi = ApiClient.validateAndNormalizeBaseUrl(
                    _apiController.text.trim(),
                  );
                  await AuthSession.saveApiBaseUrl(normalizedApi);
                } on ApiException catch (e) {
                  setDialogState(() {
                    dialogError = e.message;
                  });
                  return;
                }
              }

              await AuthSession.clearSession();
              await AuthSession.savePendingLocalRegistration(
                name: name,
                phone: normalizedPhone,
                password: password,
                email: email.isEmpty ? null : email,
                regionId: selectedRegionId,
              );
              await _prepareFarmerSession(normalizedPhone);
              await AuthSession.saveOfflineLoginProof(
                phone: normalizedPhone,
                password: password,
                ttl: const Duration(days: 30),
              );
              await AuthSession.saveUserName(name);
              await AuthSession.saveUserRole('farmer');
              await AuthSession.setOfflineModeActive(true);
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop(true);
            }

            return AlertDialog(
              title: Text(_t('local_account_title')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t('local_account_note'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: _t('local_account_name'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: _t('phone'),
                        hintText: _t('phone_hint'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: _t('local_account_email_optional'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedRegionId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t('local_account_region'),
                        border: const OutlineInputBorder(),
                      ),
                      items: regionOptions
                          .map(
                            (item) => DropdownMenuItem<int>(
                              value: item.key,
                              child: Text(
                                item.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedRegionId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: _t('password'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setDialogState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => createAccount(),
                      decoration: InputDecoration(
                        labelText: _t('local_account_confirm_password'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (dialogError.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_t('local_account_cancel')),
                ),
                ElevatedButton(
                  onPressed: createAccount,
                  child: Text(_t('local_account_create')),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();

    if (created == true && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final languageLabel = _languages.firstWhere(
      (l) => l['code'] == _languageCode,
      orElse: () => _languages.last,
    )['label']!;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/crops/tomato.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(color: primary.withValues(alpha: 0.08)),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF17210D).withValues(alpha: 0.86),
                      primary.withValues(alpha: 0.55),
                      const Color(0xFFFFF4C2).withValues(alpha: 0.76),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              top: -40,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: PopupMenuButton<String>(
                        onSelected: _setLanguage,
                        itemBuilder: (_) => _languages
                            .map(
                              (lang) => PopupMenuItem(
                                value: lang['code']!,
                                child: Text(lang['label']!),
                              ),
                            )
                            .toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.language, size: 16, color: primary),
                              const SizedBox(width: 6),
                              Text(
                                languageLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.expand_more, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Image.asset(
                            'assets/images/logo/smart.png',
                            height: 34,
                            width: 34,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(Icons.eco, size: 28, color: primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _t('brand'),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _t('welcome'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.7,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _t('subtitle'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.58)),
                        ),
                        color: Colors.white.withValues(alpha: 0.94),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: _t('phone'),
                                  hintText: _t('phone_hint'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: _t('password'),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              CheckboxListTile(
                                value: _rememberMe,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(_t('remember_me')),
                                onChanged: (value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                              ),
                              Row(
                                children: [
                                  Switch(
                                    value: _useCustomApi,
                                    onChanged: (value) {
                                      setState(() {
                                        _useCustomApi = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _t('api_toggle'),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                              if (_useCustomApi) ...[
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _apiController,
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    labelText: _t('api_label'),
                                    hintText: _t('api_hint'),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ],
                              if (_errorText != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _errorText!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ],
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    backgroundColor: const Color(0xFF496F12),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(_t('login')),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : _showCreateLocalAccountDialog,
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: Text(_t('local_account_create')),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _t('admin_only'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _t(String key) {
    return AppCopy.t(_languageCode, key);
  }
}
