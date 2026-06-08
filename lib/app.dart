import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/language_selection.dart';
import 'features/auth/login_screen.dart';
import 'features/advisory/advisory_screen.dart';
import 'features/insect/insect_detection_screen.dart';
import 'features/my_farm/my_farm_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/scan/scan_screen.dart';
import 'features/scan/pending_scan_replay_service.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/sync/sync_diagnostics_screen.dart';
import 'offline/offline_sync_service.dart';
import 'offline/account_data_reset_service.dart';
import 'auth_session.dart';
import 'api_client.dart';
import 'connectivity_status_service.dart';
import 'widgets/app_header.dart';
import 'language_store.dart';
import 'language_config.dart';
import 'localization.dart';
import 'app_copy.dart';

class App extends StatelessWidget {
  const App({super.key});

  ThemeData _buildTheme() {
    const seedColor = Color(0xFF4F7D12);
    const soilBrown = Color(0xFF7A4F21);
    const fieldCream = Color(0xFFF7F1D7);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        primary: seedColor,
        secondary: soilBrown,
        tertiary: const Color(0xFFB8D95B),
        surface: const Color(0xFFFFFCF0),
      ),
    );

    // Readability-first typography for farmers (larger body, clearer hierarchy).
    final textTheme = base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        height: 1.45,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      scaffoldBackgroundColor: fieldCream,
      cardTheme: base.cardTheme.copyWith(
        color: const Color(0xFFFFFCF0),
        elevation: 0,
        margin: const EdgeInsets.all(0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: false,
        filled: true,
        fillColor: const Color(0xFFFFFDF5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: seedColor.withValues(alpha: 0.14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: seedColor, width: 1.8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          textStyle: textTheme.labelLarge,
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        height: 74,
        backgroundColor: const Color(0xFF11140E),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? const Color(0xFFCFF36A) : Colors.white70,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? const Color(0xFFCFF36A) : Colors.white70,
            size: selected ? 25 : 23,
          );
        }),
        indicatorColor: const Color(0xFFCFF36A).withValues(alpha: 0.16),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: base.colorScheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
      ),
      listTileTheme: base.listTileTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        iconColor: base.colorScheme.primary,
      ),
      dropdownMenuTheme: base.dropdownMenuTheme.copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFDF5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: L.t(LanguageStore.notifier.value, 'app_name'),
      theme: _buildTheme(),
      home: const StartupDecider(),
      routes: {
        '/home': (_) => const AppShell(),
        '/login': (_) => const LoginScreen(),
      },
    );
  }
}

class StartupDecider extends StatelessWidget {
  const StartupDecider({super.key});

  Future<({bool seenOnboarding, bool canResumeSession})> _startupState() async {
    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
    var hasServerSession = await ApiClient.hasServerSessionCapability();
    final offlineActive = await AuthSession.isOfflineModeActive();
    final offlineProofValid = await AuthSession.hasValidOfflineLoginProof();
    final hasPendingLocalRegistration =
        await AuthSession.hasPendingLocalRegistration();
    final pendingLocalRegistration =
        await AuthSession.getPendingLocalRegistration();
    if (pendingLocalRegistration != null && hasServerSession) {
      await AuthSession.clearToken();
      await AuthSession.clearRefreshToken();
      hasServerSession = false;
    }
    final activeFarmerPhone = await AuthSession.getActiveFarmerPhone();
    if (hasServerSession && activeFarmerPhone == null) {
      await AccountDataResetService.instance.clearFarmerOwnedData();
      await AuthSession.markActiveFarmerUnknown();
    }
    if (offlineActive && pendingLocalRegistration != null) {
      if (await AuthSession.isDifferentActiveFarmer(
        pendingLocalRegistration.phone,
      )) {
        await AccountDataResetService.instance.clearFarmerOwnedData();
      }
      await AuthSession.saveActiveFarmerPhone(pendingLocalRegistration.phone);
    }
    final canResumeSession =
        hasServerSession ||
        (offlineActive && offlineProofValid) ||
        (offlineActive && hasPendingLocalRegistration);
    return (seenOnboarding: seenOnboarding, canResumeSession: canResumeSession);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({bool seenOnboarding, bool canResumeSession})>(
      future: _startupState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final state =
            snapshot.data ?? (seenOnboarding: false, canResumeSession: false);
        if (state.canResumeSession) {
          return const AppShell();
        }
        if (state.seenOnboarding) return const LoginScreen();
        return const LanguageSelectionScreen();
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  int _refreshTick = 0;
  bool _logoutInProgress = false;
  bool _startupHealthChecked = false;
  bool _syncInProgress = false;
  bool _manualRefreshInProgress = false;
  bool _permissionPromptRunning = false;
  bool _offlinePopupVisible = false;
  String _offlinePopupMessage = 'Offline mode active. Using saved data.';
  Timer? _offlinePopupTimer;
  Timer? _sessionRevalidateTimer;
  static const Duration _sessionRevalidateInterval = Duration(minutes: 1);
  static const String _firstUsePermissionsKey = 'first_use_permissions_prompted_v1';

  static const List<String> _titles = [
    'home',
    'my_farm',
    'scan',
    'pest_detection',
    'alerts',
  ];

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return HomeScreen(
          key: ValueKey('home-$_refreshTick'),
          onRequestTabChange: _onItemTapped,
          onRequestRefresh: _handleGlobalRefresh,
        );
      case 1:
        return MyFarmScreen(key: ValueKey('myfarm-$_refreshTick'));
      case 2:
        return ScanScreen(
          key: ValueKey('scan-$_refreshTick'),
          isActive: _selectedIndex == 2,
        );
      case 3:
        return InsectDetectionScreen(key: ValueKey('insect-$_refreshTick'));
      case 4:
        return AlertsScreen(key: ValueKey('alerts-$_refreshTick'));
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void initState() {
    super.initState();
    LanguageStore.load();
    ConnectivityStatusService.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 350),
          _runStartupHealthCheck,
        ),
      );
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 800),
          _runFirstUsePermissionPrompt,
        ),
      );
    });
    _startSessionRevalidateLoop();
  }

  @override
  void dispose() {
    ConnectivityStatusService.instance.stop();
    _sessionRevalidateTimer?.cancel();
    _sessionRevalidateTimer = null;
    _offlinePopupTimer?.cancel();
    _offlinePopupTimer = null;
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openDrawer() {
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffold = _scaffoldKey.currentState;
    if (scaffold == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scaffoldKey.currentState?.openDrawer();
      });
      return;
    }
    scaffold.openDrawer();
  }

  Future<void> _runFirstUsePermissionPrompt() async {
    if (_permissionPromptRunning || !mounted) return;
    _permissionPromptRunning = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_firstUsePermissionsKey) ?? false) return;

      final cameraStatus = await Permission.camera.status;
      final locationStatus = await Geolocator.checkPermission();
      final needsCamera = cameraStatus.isDenied || cameraStatus.isRestricted;
      final needsLocation =
          locationStatus == LocationPermission.denied ||
          locationStatus == LocationPermission.unableToDetermine;
      if (!needsCamera && !needsLocation) {
        await prefs.setBool(_firstUsePermissionsKey, true);
        return;
      }

      final lang = LanguageStore.notifier.value;
      if (!mounted) return;
      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            title: Text(L.t(lang, 'permissions_first_use_title')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t(lang, 'permissions_first_use_body')),
                const SizedBox(height: 12),
                _PermissionRow(
                  icon: Icons.camera_alt_outlined,
                  title: L.t(lang, 'permissions_camera_title'),
                  body: L.t(lang, 'permissions_camera_body'),
                ),
                const SizedBox(height: 10),
                _PermissionRow(
                  icon: Icons.my_location_outlined,
                  title: L.t(lang, 'permissions_location_title'),
                  body: L.t(lang, 'permissions_location_body'),
                ),
                const SizedBox(height: 8),
                Text(
                  L.t(lang, 'permissions_first_use_note'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(L.t(lang, 'later')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(L.t(lang, 'continue_label')),
              ),
            ],
          );
        },
      );

      if (shouldRequest == true) {
        if (needsCamera) {
          await Permission.camera.request();
        }
        if (needsLocation) {
          await Geolocator.requestPermission();
        }
      }
      await prefs.setBool(_firstUsePermissionsKey, true);
    } finally {
      _permissionPromptRunning = false;
    }
  }

  void _showOfflinePopup(String message) {
    if (!mounted) return;
    _offlinePopupTimer?.cancel();
    setState(() {
      _offlinePopupMessage = message;
      _offlinePopupVisible = true;
    });
    _offlinePopupTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _offlinePopupVisible = false;
      });
    });
  }

  String _offlineSessionNeedsOnlineSignInMessage(ApiConnectivityStatus status) {
    return switch (status.state) {
      ApiConnectivityState.apiOnline =>
        'API is online, but this offline session is not signed in. Keep working offline or sign in online when ready to sync.',
      ApiConnectivityState.internetOnly =>
        'Internet is available, but the API is not reachable. Keep working offline; saved work will sync when the API is available.',
      ApiConnectivityState.offline =>
        'No internet connection. Keep working offline; saved work will sync after connection returns.',
    };
  }

  Future<bool> _tryRegisterPendingLocalAccount() async {
    final pending = await AuthSession.getPendingLocalRegistration();
    if (pending == null) {
      return false;
    }

    try {
      LoginResult result;
      try {
        result = await ApiClient.registerFarmer(
          name: pending.name,
          phone: pending.phone,
          password: pending.password,
          email: pending.email,
          regionId: pending.regionId,
        );
      } on ApiException catch (e) {
        if (!e.message.toLowerCase().contains('already registered')) {
          rethrow;
        }
        result = await ApiClient.login(
          phone: pending.phone,
          password: pending.password,
        );
      }
      if (await AuthSession.isDifferentActiveFarmer(pending.phone)) {
        await AccountDataResetService.instance.clearFarmerOwnedData();
      }
      await AuthSession.saveActiveFarmerPhone(pending.phone);
      await AuthSession.saveToken(result.token);
      await AuthSession.saveRefreshToken(result.refreshToken);
      await AuthSession.setOfflineModeActive(false);
      await AuthSession.saveUserName((result.userName ?? pending.name).trim());
      await AuthSession.saveUserRole((result.roleName ?? 'farmer').trim());
      await AuthSession.saveOfflineLoginProof(
        phone: pending.phone,
        password: pending.password,
      );
      await AuthSession.clearPendingLocalRegistration();
      _showOfflinePopup(
        'Local account synced. Saved farm data can upload now.',
      );
      return true;
    } on ApiException catch (e) {
      _showOfflinePopup(e.message);
      return false;
    }
  }

  Future<void> _handleGlobalRefresh() async {
    if (_manualRefreshInProgress) return;
    _manualRefreshInProgress = true;
    try {
      final status = await ConnectivityStatusService.instance.refreshNow();
      if (status.state != ApiConnectivityState.apiOnline) {
        _showOfflinePopup(status.message);
        return;
      }

      final hasServerSession = await ApiClient.hasServerSessionCapability();
      if (!hasServerSession) {
        await AuthSession.setOfflineModeActive(true);
        final registered = await _tryRegisterPendingLocalAccount();
        if (registered) {
          await PendingScanReplayService.instance.drainReadyOnce();
          await OfflineSyncService.instance.syncNow(
            force: true,
            pullFirst: true,
          );
          if (!mounted) return;
          setState(() {
            _refreshTick += 1;
          });
          return;
        }
        if (!mounted) return;
        _showOfflinePopup(L.t(LanguageStore.notifier.value, 'no_online_session_active'));
        return;
      }

      try {
        await ApiClient.healthCheck();
        await AuthSession.setOfflineModeActive(false);
        await PendingScanReplayService.instance.drainReadyOnce();
        await OfflineSyncService.instance.syncNow(force: true, pullFirst: true);
        if (!mounted) return;
        setState(() {
          _refreshTick += 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t(LanguageStore.notifier.value, 'data_refreshed'))),
        );
      } on ApiUnauthorized {
        await AuthSession.clearToken();
        if (await AuthSession.hasValidOfflineLoginProof()) {
          await AuthSession.setOfflineModeActive(true);
          if (!mounted) return;
          _showOfflinePopup(L.t(LanguageStore.notifier.value, 'server_session_expired_offline'));
          return;
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
      } on ApiException {
        final probe = await ConnectivityStatusService.instance.refreshNow();
        _showOfflinePopup(probe.message);
      }
    } finally {
      _manualRefreshInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      // onPopInvoked is deprecated; use onPopInvokedWithResult instead.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _AppDrawer(onLogout: _handleLogout),
        body: Stack(
          children: [
            Column(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: LanguageStore.notifier,
                  builder: (context, _, _) {
                    return AppHeader(
                      titleKey: _titles[_selectedIndex],
                      onMenuTap: _openDrawer,
                      onSearchTap: () {
                        setState(() {
                          _selectedIndex = 1;
                        });
                      },
                      onRefreshTap: _handleGlobalRefresh,
                    );
                  },
                ),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey<String>('tab-$_selectedIndex-$_refreshTick'),
                    child: _buildScreen(_selectedIndex),
                  ),
                ),
              ],
            ),
            if (_offlinePopupVisible)
              Positioned(
                bottom: 96,
                left: 16,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: AnimatedOpacity(
                    opacity: _offlinePopupVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _offlinePopupMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder<String>(
          valueListenable: LanguageStore.notifier,
          builder: (context, lang, _) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _onItemTapped,
                    destinations: [
                      NavigationDestination(
                        icon: const Icon(Icons.home_rounded),
                        label: L.t(lang, 'home'),
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.grass_rounded),
                        label: L.t(lang, 'my_farm'),
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: L.t(lang, 'scan'),
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.bug_report_rounded),
                        label: L.t(lang, 'pest_detection'),
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.warning_amber_rounded),
                        label: L.t(lang, 'alerts'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    if (_logoutInProgress) return;
    setState(() {
      _logoutInProgress = true;
    });

    final token = await AuthSession.getToken();
    final refreshToken = await AuthSession.getRefreshToken();
    final baseUrl = await AuthSession.getApiBaseUrl();

    // Project policy: explicit logout ends the live server session but keeps
    // offline proof on the device, so a farmer who already authenticated once
    // can still unlock the app offline in the field.
    await AuthSession.clearActiveSessionPreservingOfflineProof();
    if (!mounted) return;
    unawaited(
      ApiClient.logout(
        tokenOverride: token,
        refreshTokenOverride: refreshToken,
        baseUrlOverride: baseUrl,
      ).timeout(const Duration(seconds: 4)).catchError((_) {
        // Best-effort server logout after local session is already gone.
      }),
    );
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _runStartupHealthCheck() async {
    if (_startupHealthChecked) {
      return;
    }
    _startupHealthChecked = true;

    final hasServerSession = await ApiClient.hasServerSessionCapability();
    if (!hasServerSession) {
      final offlineActive = await AuthSession.isOfflineModeActive();
      if (offlineActive) {
        final probe = await ConnectivityStatusService.instance.refreshNow();
        if (probe.state == ApiConnectivityState.apiOnline) {
          final registered = await _tryRegisterPendingLocalAccount();
          if (registered) {
            await PendingScanReplayService.instance.drainReadyOnce().timeout(
              const Duration(seconds: 12),
              onTimeout: () {},
            );
            await OfflineSyncService.instance
                .syncNow(force: true, pullFirst: true)
                .timeout(const Duration(seconds: 15), onTimeout: () {});
            if (!mounted) return;
            setState(() {
              _refreshTick += 1;
            });
            return;
          }
          _showOfflinePopup(_offlineSessionNeedsOnlineSignInMessage(probe));
        }
      }
      return;
    }

    final wasOffline = await AuthSession.isOfflineModeActive();
    if (wasOffline) {
      final probe = await ConnectivityStatusService.instance.refreshNow();
      if (probe.state != ApiConnectivityState.apiOnline) {
        return;
      }
      if (!await AuthSession.hasRefreshToken()) {
        _showOfflinePopup(_offlineSessionNeedsOnlineSignInMessage(probe));
        return;
      }
    }

    try {
      await ApiClient.healthCheck();
      await AuthSession.setOfflineModeActive(false);
      await PendingScanReplayService.instance.drainReadyOnce().timeout(
        const Duration(seconds: 12),
        onTimeout: () {},
      );
      await OfflineSyncService.instance.syncNow().timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
      if (wasOffline && mounted) {
        setState(() {
          _refreshTick += 1;
        });
      }
    } on ApiUnauthorized {
      await AuthSession.clearToken();
      if (!mounted) return;
      final canStayOffline =
          wasOffline && await AuthSession.hasValidOfflineLoginProof();
      if (!mounted) return;
      if (canStayOffline) {
        _showOfflinePopup(
          'Server session expired. Continue offline and log in online later to sync.',
        );
        return;
      }
      Navigator.of(context).pushReplacementNamed('/login');
    } on ApiException catch (e) {
      final offlineMode = await AuthSession.isOfflineModeActive();
      if (!mounted) return;
      if (!offlineMode) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server health check warning: ${e.message}')),
        );
      }
    }
  }

  void _startSessionRevalidateLoop() {
    _sessionRevalidateTimer?.cancel();
    _sessionRevalidateTimer = Timer.periodic(_sessionRevalidateInterval, (_) {
      unawaited(_revalidateSessionAndSync());
    });
  }

  Future<void> _revalidateSessionAndSync() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final hasServerSession = await ApiClient.hasServerSessionCapability();
      if (!hasServerSession) {
        final offlineActive = await AuthSession.isOfflineModeActive();
        if (offlineActive) {
          final probe = await ConnectivityStatusService.instance.refreshNow();
          if (probe.state == ApiConnectivityState.apiOnline) {
            final registered = await _tryRegisterPendingLocalAccount();
            if (registered) {
              await PendingScanReplayService.instance.drainReadyOnce().timeout(
                const Duration(seconds: 12),
                onTimeout: () {},
              );
              await OfflineSyncService.instance
                  .syncNow(force: true, pullFirst: true)
                  .timeout(const Duration(seconds: 15), onTimeout: () {});
              if (!mounted) return;
              setState(() {
                _refreshTick += 1;
              });
              return;
            }
            _showOfflinePopup(_offlineSessionNeedsOnlineSignInMessage(probe));
          }
        }
        return;
      }

      final wasOffline = await AuthSession.isOfflineModeActive();
      if (wasOffline) {
        final probe = await ConnectivityStatusService.instance.refreshNow();
        if (probe.state != ApiConnectivityState.apiOnline) {
          return;
        }
        if (!await AuthSession.hasRefreshToken()) {
          _showOfflinePopup(_offlineSessionNeedsOnlineSignInMessage(probe));
          return;
        }
      }

      try {
        await ApiClient.healthCheck();
      } on ApiUnauthorized {
        await AuthSession.clearToken();
        if (!mounted) return;
        final canStayOffline =
            wasOffline && await AuthSession.hasValidOfflineLoginProof();
        if (!mounted) return;
        if (canStayOffline) {
          _showOfflinePopup(
            'Server session expired. Continue offline and log in online later to sync.',
          );
          return;
        }
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      } on ApiException {
        return;
      }

      await AuthSession.setOfflineModeActive(false);
      await PendingScanReplayService.instance.drainReadyOnce().timeout(
        const Duration(seconds: 12),
        onTimeout: () {},
      );
      try {
        await OfflineSyncService.instance.syncNow().timeout(
          const Duration(seconds: 15),
          onTimeout: () {},
        );
      } on ApiException {
        // Ignore sync errors during background revalidation.
      }
      if (wasOffline && mounted) {
        setState(() {
          _refreshTick += 1;
        });
      }
    } finally {
      _syncInProgress = false;
    }
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppDrawer extends StatelessWidget {
  final VoidCallback onLogout;
  const _AppDrawer({required this.onLogout});

  static final List<Map<String, String>> _languages = LanguageConfig.options
      .map((l) => {'code': l.code, 'label': l.label})
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF7F1D7),
      child: SafeArea(
        child: ValueListenableBuilder<String>(
          valueListenable: LanguageStore.notifier,
          builder: (context, lang, _) {
            final languageLabel = _languages.firstWhere(
              (l) => l['code'] == lang,
              orElse: () => _languages.last,
            )['label']!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
              children: [
                _DrawerUserHeader(languageCode: lang),
                const SizedBox(height: 16),
                _DrawerTile(
                  icon: Icons.person_outline,
                  title: L.t(lang, 'profile'),
                  subtitle: L.t(lang, 'profile_sub'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                ),
                _DrawerTile(
                  icon: Icons.sync,
                  title: L.t(lang, 'offline_sync'),
                  subtitle: L.t(lang, 'offline_sync_sub'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SyncDiagnosticsScreen(),
                      ),
                    );
                  },
                ),
                _DrawerTile(
                  icon: Icons.rule,
                  title: L.t(lang, 'guidelines'),
                  subtitle: L.t(lang, 'guidelines_sub'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdvisoryScreen()),
                    );
                  },
                ),
                _DrawerTile(
                  icon: Icons.support_agent,
                  title: L.t(lang, 'admin_contact'),
                  subtitle: L.t(lang, 'admin_contact_sub'),
                  onTap: () => _showAdminContactDialog(context, lang),
                ),
                _DrawerTile(
                  icon: Icons.language,
                  title: L.t(lang, 'language'),
                  subtitle: languageLabel,
                  onTap: () => _showLanguagePicker(context, lang),
                ),
                _DrawerTile(
                  icon: Icons.info_outline,
                  title: L.t(lang, 'about'),
                  subtitle: L.t(lang, 'about_sub'),
                  onTap: () => _showAboutDialog(context, lang),
                ),
                const SizedBox(height: 8),
                Material(
                  color: const Color(0xFF1E2415),
                  borderRadius: BorderRadius.circular(20),
                  child: ListTile(
                    leading: const Icon(Icons.logout_rounded, color: Colors.white),
                    title: Text(
                      L.t(lang, 'logout'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onLogout();
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showLanguagePicker(BuildContext context, String current) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _languages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final lang = _languages[i];
              final selected = lang['code'] == current;
              return ListTile(
                title: Text(lang['label']!),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () async {
                  Navigator.of(context).pop();
                  final prefs = await SharedPreferences.getInstance();
                  final code = LanguageConfig.normalize(lang['code']);
                  await prefs.setString('language', code);
                  await LanguageStore.setLanguage(code);
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showAdminContactDialog(BuildContext context, String lang) {
    Navigator.of(context).pop();
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(L.t(lang, 'admin_contact')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L.t(lang, 'admin_contact_body')),
              const SizedBox(height: 12),
              _AboutContactTile(
                icon: Icons.person_outline,
                label: L.t(lang, 'name'),
                value: 'Admasu Feleke Mulatu',
              ),
              _AboutContactTile(
                icon: Icons.email_outlined,
                label: L.t(lang, 'email'),
                value: 'admasu.feleke21@gmail.com',
              ),
              _AboutContactTile(
                icon: Icons.phone_outlined,
                label: L.t(lang, 'phone'),
                value: '0900824328',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(L.t(lang, 'close')),
            ),
          ],
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context, String lang) {
    Navigator.of(context).pop();
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(L.t(lang, 'about')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t(lang, 'about_sub')),
                const SizedBox(height: 12),
                Text(
                  AppCopy.t(lang, 'about_project_summary'),
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  AppCopy.t(lang, 'about_project_promotion'),
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  AppCopy.t(lang, 'about_project_supported_crops'),
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  AppCopy.t(lang, 'about_project_developer'),
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _AboutContactTile(
                  icon: Icons.email_outlined,
                  label: L.t(lang, 'email'),
                  value: 'admasu.feleke21@gmail.com',
                ),
                _AboutContactTile(
                  icon: Icons.phone_outlined,
                  label: L.t(lang, 'phone'),
                  value: '0900824328',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(L.t(lang, 'close')),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label copied')));
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

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFFFFDF5),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        minVerticalPadding: 14,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFDDEF9D),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: const Color(0xFF41670F)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap ?? () {},
      ),
    );
  }
}

class _DrawerUserHeader extends StatelessWidget {
  final String languageCode;
  const _DrawerUserHeader({required this.languageCode});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String?>>(
      future: Future.wait([
        AuthSession.getUserName(),
        AuthSession.getUserRole(),
      ]),
      builder: (context, snapshot) {
        final name = (snapshot.data?[0] ?? '').trim();
        final role = (snapshot.data?[1] ?? '').trim();
        final displayName = name.isNotEmpty ? name : 'Farmer';
        final roleLabel = role.isNotEmpty ? role : 'User';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2F5E12), Color(0xFF7EA120)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Image.asset(
                  'assets/images/logo/smart.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(Icons.eco_rounded),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      roleLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
