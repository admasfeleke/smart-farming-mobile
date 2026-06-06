import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_copy.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../localized_value.dart';
import '../../localized_phrase.dart';
import '../../api_client.dart';
import '../../connectivity_status_service.dart';
import '../../models/disease_report_model.dart';
import '../../widgets/farm_ui.dart';
import '../../offline/local_cache_store.dart';
import '../../offline/offline_repository.dart';
import '../../sync_refresh_notifier.dart';
import '../../reference/reference_data.dart';
import '../crop_health/crop_health_refresh_notifier.dart';
import '../crop_health/crop_health_screen.dart';
import '../disease/disease_check_screen.dart';
import '../disease/disease_refresh_notifier.dart';
import '../my_farm/models/planting_model.dart';
import '../../crop_scope.dart';
import '../../disease_naming.dart';
import 'local_scan_history_store.dart';
import 'offline_inference_service.dart';
import 'offline_model_registry.dart';
import 'offline_treatment_guidance_service.dart';
import 'pending_scan_queue_store.dart';

enum ScanMode { cropHealth, disease }

enum _ScanUiState {
  idle,
  capturing,
  qualityChecking,
  selectingMode,
  collectingContext,
  uploading,
  analyzing,
  showingResult,
  error,
}

enum _QualityDecision { cancel, retake, useAnyway }

enum _ScanExecutionMode { auto, preferOffline, preferOnline, offlineOnly }

class ScanScreen extends StatefulWidget {
  final ScanMode? initialMode;
  final bool isActive;

  const ScanScreen({super.key, this.initialMode, this.isActive = true});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  String? _errorKey;
  String? _errorDetail;
  bool _permissionGranted = false;
  XFile? _lastCaptured;
  bool _submitting = false;
  _ScanUiState _scanUiState = _ScanUiState.idle;
  bool _cameraInitializing = false;
  bool _cameraRequested = false;
  bool _autoScanEnabled = false;
  bool _captureInProgress = false;
  bool _qualityDialogOpen = false;
  int _cameraGeneration = 0;
  String _liveGuidance = _defaultGuidance;
  final List<int> _recentFrameHashes = <int>[];
  bool _drainingQueue = false;
  bool _queueStatusLoading = false;
  int _queuePendingCount = 0;
  int _queueRetryingCount = 0;
  DateTime? _queueNextRetryAt;
  Timer? _queueAutoDrainTimer;
  int _analysisPollAttempt = 0;
  int _analysisPollMaxAttempts = 8;
  String? _analysisLatestStatus;
  final List<_StructuredCaptureCandidate> _structuredCaptureCandidates =
      <_StructuredCaptureCandidate>[];
  bool _loadingCropContexts = false;
  String? _cropContextError;
  List<_ScanCropContext> _cropContexts = const [];
  _ScanCropContext? _selectedCropContext;
  String? _selectedGrowthStage;
  final TextEditingController _symptomDaysController = TextEditingController();
  bool? _recentRain;
  final TextEditingController _fieldNotesController = TextEditingController();
  bool _flashlightEnabled = false;
  bool _flashBusy = false;
  bool _zoomBusy = false;
  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  late final AnimationController _scanLineController;

  static const int _minImageBytes = 80 * 1024;
  static const int _minImageSide = 600;
  static const double _minLuminance = 28.0;
  static const double _maxLuminance = 230.0;
  static const double _minQualityStdDev = 8.5;
  static const double _minQualityGreenRatio = 0.04;
  static const double _minQualityEdgeRatio = 0.012;
  static const int _maxPendingQueueItems = 60;
  static const Duration _maxPendingQueueAge = Duration(days: 7);
  static const int _maxPendingRetryAttempts = 5;
  static const Duration _initialPendingRetryDelay = Duration(minutes: 1);
  static const Duration _maxPendingRetryDelay = Duration(hours: 12);
  static const Duration _connectivityProbeStaleAfter = Duration(seconds: 12);
  static const Duration _connectivityProbeTimeout = Duration(seconds: 3);
  static const Duration _queueAutoDrainInterval = Duration(minutes: 1);
  static const int _structuredCaptureRequiredShotsDefault = 1;
  static const int _structuredCaptureMaxShots = 4;
  static const Map<String, int> _structuredCaptureShotsByFamily =
      <String, int>{};
  static const List<String> _growthStageOptions = <String>[
    'seedling',
    'vegetative',
    'flowering',
    'fruiting',
    'maturity',
  ];
  static const int _cropContextFarmConcurrency = 3;
  static const int _cropContextPlotConcurrency = 4;
  static const String _legacyPendingScanQueueKey = 'pending_scan_queue_v1';
  static const String _offlineCropContextsCacheKey =
      'scan_crop_contexts_cache_v1';
  static const String _offlineSelectedContextCacheKey =
      'scan_selected_context_cache_v1';
  static const String _scanExecutionModePrefsKey = 'scan_execution_mode_v1';
  static const String _cropReferenceCacheKey = 'reference_crops_cache_v1';
  static const String _defaultGuidance = 'Put one leaf inside the box';
  _ScanExecutionMode _scanExecutionMode = _ScanExecutionMode.auto;

  void _showQueuedScanFeedback(String languageCode, String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Saved on this phone.\n$message\n${L.t(languageCode, 'action_next_scan_queued')}',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: L.t(languageCode, 'scan_queue_history'),
          onPressed: _openQueuedScanHistory,
        ),
      ),
    );
  }

  void _showOfflineSavedFeedback(String languageCode, {String? diseaseName}) {
    if (!mounted) return;
    final label = diseaseName?.trim();
    final message = label == null || label.isEmpty
        ? 'Saved on this phone. Open Scan history to review it.'
        : 'Saved on this phone: $label. Open Scan history to review it.';
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 7),
        action: SnackBarAction(
          label: L.t(languageCode, 'scan_queue_history'),
          onPressed: _openQueuedScanHistory,
        ),
      ),
    );
  }

  void _showOfflineQuickTestFeedback({
    required String languageCode,
    required String cropName,
    String? diseaseName,
  }) {
    if (!mounted) return;
    final diseaseLabel = diseaseName?.trim();
    final resultText = diseaseLabel == null || diseaseLabel.isEmpty
        ? 'Offline result saved on this phone.'
        : 'Offline result saved on this phone: $diseaseLabel.';
    final message =
        '$resultText\n$candidateUploadBlockedText\nAdd or sync a $cropName planting first, then scan again for server review.';
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 9),
        action: SnackBarAction(
          label: L.t(languageCode, 'scan_queue_history'),
          onPressed: _openQueuedScanHistory,
        ),
      ),
    );
  }

  String get candidateUploadBlockedText =>
      'Not uploaded: this crop is not linked to a real farm plot/planting.';

  _ScanExecutionMode _parseScanExecutionMode(String raw) {
    switch (raw.trim()) {
      case 'prefer_offline':
        return _ScanExecutionMode.preferOffline;
      case 'prefer_online':
        return _ScanExecutionMode.preferOnline;
      case 'offline_only':
        return _ScanExecutionMode.offlineOnly;
      case 'auto':
      default:
        return _ScanExecutionMode.auto;
    }
  }

  String _scanExecutionModeStorageValue(_ScanExecutionMode mode) {
    switch (mode) {
      case _ScanExecutionMode.auto:
        return 'auto';
      case _ScanExecutionMode.preferOffline:
        return 'prefer_offline';
      case _ScanExecutionMode.preferOnline:
        return 'prefer_online';
      case _ScanExecutionMode.offlineOnly:
        return 'offline_only';
    }
  }

  Future<void> _loadScanExecutionMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_scanExecutionModePrefsKey) ?? 'auto';
    final parsed = _parseScanExecutionMode(stored);
    if (!mounted) return;
    setState(() {
      _scanExecutionMode = parsed;
    });
  }

  Future<void> _setScanExecutionMode(_ScanExecutionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scanExecutionModePrefsKey,
      _scanExecutionModeStorageValue(mode),
    );
    if (!mounted) return;
    setState(() {
      _scanExecutionMode = mode;
    });
  }

  bool _shouldUseOfflineQueueFirst(ApiConnectivityStatus status) {
    switch (_scanExecutionMode) {
      case _ScanExecutionMode.auto:
        return status.state != ApiConnectivityState.apiOnline;
      case _ScanExecutionMode.preferOffline:
        return true;
      case _ScanExecutionMode.preferOnline:
        return status.state == ApiConnectivityState.offline;
      case _ScanExecutionMode.offlineOnly:
        return true;
    }
  }

  Future<ApiConnectivityStatus> _effectiveConnectivityStatusForSubmit() async {
    final current = ConnectivityStatusService.instance.notifier.value;
    final age = DateTime.now().difference(current.checkedAt);
    if (current.state != ApiConnectivityState.apiOnline) {
      return current;
    }
    if (age <= _connectivityProbeStaleAfter) {
      return current;
    }
    try {
      return await ConnectivityStatusService.instance.refreshNow().timeout(
        _connectivityProbeTimeout,
      );
    } on TimeoutException {
      return ApiConnectivityStatus(
        state: ApiConnectivityState.internetOnly,
        message: 'API availability check timed out.',
        checkedAt: DateTime.now(),
      );
    } catch (_) {
      return ApiConnectivityStatus(
        state: ApiConnectivityState.internetOnly,
        message: 'API availability check failed.',
        checkedAt: DateTime.now(),
      );
    }
  }

  String _scanExecutionModeLabel(String languageCode, _ScanExecutionMode mode) {
    switch (mode) {
      case _ScanExecutionMode.auto:
        return L.t(languageCode, 'scan_exec_auto');
      case _ScanExecutionMode.preferOffline:
        return L.t(languageCode, 'scan_exec_prefer_offline');
      case _ScanExecutionMode.preferOnline:
        return L.t(languageCode, 'scan_exec_prefer_online');
      case _ScanExecutionMode.offlineOnly:
        return L.t(languageCode, 'scan_exec_offline_only');
    }
  }

  String _scanExecutionModeDescription(
    String languageCode,
    _ScanExecutionMode mode,
  ) {
    switch (mode) {
      case _ScanExecutionMode.auto:
        return L.t(languageCode, 'scan_exec_auto_desc');
      case _ScanExecutionMode.preferOffline:
        return L.t(languageCode, 'scan_exec_prefer_offline_desc');
      case _ScanExecutionMode.preferOnline:
        return L.t(languageCode, 'scan_exec_prefer_online_desc');
      case _ScanExecutionMode.offlineOnly:
        return L.t(languageCode, 'scan_exec_offline_only_desc');
    }
  }

  void _openQueuedScanHistory() {
    final target = widget.initialMode == ScanMode.cropHealth
        ? const CropHealthScreen()
        : const DiseaseCheckScreen();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => target));
  }

  static const double _cameraPreviewHeightFraction = 0.52;
  static const double _cameraPreviewMinHeight = 220.0;
  static const double _cameraPreviewMaxHeight = 420.0;
  bool _legacyQueueMigrated = false;

  void _startScanLineAnimation() {
    if (!_scanLineController.isAnimating) {
      _scanLineController.repeat(reverse: true);
    }
  }

  void _stopScanLineAnimation() {
    if (_scanLineController.isAnimating) {
      _scanLineController.stop();
      _scanLineController.value = 0.0;
    }
  }

  void _redirectToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _setScanUiState(_ScanUiState next) {
    if (!mounted) return;
    final shouldAnimate = _shouldAnimateScanLine(next);
    setState(() {
      _scanUiState = next;
      if (next == _ScanUiState.collectingContext) {
        _analysisPollAttempt = 0;
        _analysisLatestStatus = 'collecting_context';
      } else if (next == _ScanUiState.uploading) {
        _analysisPollAttempt = 0;
        _analysisLatestStatus = 'uploading';
      } else if (next == _ScanUiState.analyzing) {
        _analysisPollAttempt = 0;
      } else if (next == _ScanUiState.idle ||
          next == _ScanUiState.error ||
          next == _ScanUiState.showingResult) {
        _analysisPollAttempt = 0;
        _analysisLatestStatus = null;
      }
    });
    if (next == _ScanUiState.collectingContext ||
        next == _ScanUiState.uploading ||
        next == _ScanUiState.analyzing) {
      unawaited(_ensurePreviewContinues());
    }
    if (shouldAnimate) {
      _startScanLineAnimation();
    } else {
      _stopScanLineAnimation();
    }
  }

  bool _shouldAnimateScanLine(_ScanUiState state) {
    return state == _ScanUiState.idle ||
        state == _ScanUiState.capturing ||
        state == _ScanUiState.qualityChecking;
  }

  IconData _flashIcon() {
    return _flashlightEnabled ? Icons.flash_on : Icons.flash_off;
  }

  String _flashLabel() {
    return LocalizedValue.fixed(
      LanguageStore.notifier.value,
      _flashlightEnabled ? 'flash_on' : 'flash_off',
    );
  }

  Future<void> _syncCameraCapabilities(CameraController controller) async {
    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      if (!mounted) return;
      setState(() {
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _zoomLevel = _zoomLevel.clamp(minZoom, maxZoom);
      });
      await controller.setZoomLevel(_zoomLevel);
    } catch (_) {
      // Keep defaults when unsupported.
    }
  }

  Future<void> _setFlashModeSafe(FlashMode mode) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_flashBusy) return;
    _flashBusy = true;
    try {
      await controller.setFlashMode(mode);
      if (!mounted) return;
      setState(() {
        _flashlightEnabled = mode == FlashMode.torch;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _flashlightEnabled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocalizedValue.fixed(
              LanguageStore.notifier.value,
              'flashlight_unavailable',
            ),
          ),
        ),
      );
    } finally {
      _flashBusy = false;
    }
  }

  Future<void> _toggleFlashlight() async {
    final next = _flashlightEnabled ? FlashMode.off : FlashMode.torch;
    await _setFlashModeSafe(next);
  }

  Future<void> _stepZoom({required bool zoomIn}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_zoomBusy) return;
    _zoomBusy = true;
    try {
      final current = _zoomLevel;
      final step = (_maxZoom - _minZoom) <= 0 ? 0.0 : (_maxZoom - _minZoom) / 6;
      final next = (zoomIn ? current + step : current - step).clamp(
        _minZoom,
        _maxZoom,
      );
      await controller.setZoomLevel(next);
      if (!mounted) return;
      setState(() {
        _zoomLevel = next;
      });
    } catch (_) {
      // Ignore zoom failures silently.
    } finally {
      _zoomBusy = false;
    }
  }

  Future<void> _uploadLastCaptured() async {
    if (_submitting || _isBusy) return;
    final last = _lastCaptured;
    if (last == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocalizedValue.fixed(
              LanguageStore.notifier.value,
              'scan_no_captured_image',
            ),
          ),
        ),
      );
      return;
    }
    final file = File(last.path);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocalizedValue.fixed(
              LanguageStore.notifier.value,
              'scan_last_image_unavailable',
            ),
          ),
        ),
      );
      return;
    }

    if (widget.initialMode == null && _selectedCropContext != null) {
      await _submitSelectedCropContext(last, _selectedCropContext!);
      return;
    }

    final forcedMode = widget.initialMode ?? ScanMode.disease;
    _handleScan(last, forcedMode);
  }

  bool get _isBusy {
    return _scanUiState != _ScanUiState.idle &&
        _scanUiState != _ScanUiState.selectingMode;
  }

  bool get _autoScanAllowed => false;

  int get _structuredCaptureRequiredShots {
    final family = _selectedCropContext?.family;
    if (family == null || family.trim().isEmpty) {
      return _structuredCaptureRequiredShotsDefault;
    }
    return _structuredCaptureShotsByFamily[family] ??
        _structuredCaptureRequiredShotsDefault;
  }

  bool get _isAnalysisInFlight {
    return _scanUiState == _ScanUiState.collectingContext ||
        _scanUiState == _ScanUiState.uploading ||
        _scanUiState == _ScanUiState.analyzing;
  }

  int get _analysisProgressPercent {
    if (_scanUiState == _ScanUiState.collectingContext) {
      return 12;
    }
    if (_scanUiState == _ScanUiState.uploading) {
      return 34;
    }
    if (_scanUiState == _ScanUiState.analyzing) {
      final ratio = _analysisPollMaxAttempts <= 0
          ? 0.0
          : (_analysisPollAttempt / _analysisPollMaxAttempts).clamp(0.0, 1.0);
      return (45 + (ratio * 50)).round();
    }
    return 0;
  }

  String _analysisStageLabel(String lang) {
    if (_scanUiState == _ScanUiState.analyzing) {
      return L.t(lang, 'scan_analyzing_image');
    }
    return _scanUiStateLabel(lang);
  }

  String _analysisDetailLine() {
    if (_scanUiState != _ScanUiState.analyzing) {
      return '';
    }
    final attempt = _analysisPollAttempt.clamp(0, _analysisPollMaxAttempts);
    final status = (_analysisLatestStatus ?? '').trim();
    final normalizedStatus = status.isEmpty ? '' : status.toLowerCase();
    final suffix = normalizedStatus.isEmpty ? '' : ' • $normalizedStatus';
    return 'Check $attempt/$_analysisPollMaxAttempts$suffix';
  }

  String _scanUiStateLabel(String lang) {
    switch (_scanUiState) {
      case _ScanUiState.idle:
        return L.t(lang, 'scan_crop');
      case _ScanUiState.capturing:
        return L.t(lang, 'scan_state_capturing');
      case _ScanUiState.qualityChecking:
        return L.t(lang, 'scan_state_quality_check');
      case _ScanUiState.selectingMode:
        return L.t(lang, 'what_to_check');
      case _ScanUiState.collectingContext:
        return L.t(lang, 'scan_state_collecting_context');
      case _ScanUiState.uploading:
        return L.t(lang, 'scan_state_uploading');
      case _ScanUiState.analyzing:
        return L.t(lang, 'scan_state_analyzing');
      case _ScanUiState.showingResult:
        return L.t(lang, 'scan_state_result_ready');
      case _ScanUiState.error:
        return L.t(lang, 'scan_state_failed');
    }
  }

  Widget _buildScanGuideOverlay(Size size) {
    final boxSize = size.width * 0.7;
    final lineColor = _isBusy ? Colors.lightGreenAccent : Colors.greenAccent;

    return Center(
      child: SizedBox(
        width: boxSize,
        height: boxSize,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _scanLineController,
              builder: (context, child) {
                final travel = boxSize - 6;
                final top = 3 + (_scanLineController.value * travel);
                return Positioned(
                  left: 6,
                  right: 6,
                  top: top,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: LinearGradient(
                        colors: [
                          lineColor.withValues(alpha: 0.0),
                          lineColor.withValues(alpha: 0.95),
                          lineColor.withValues(alpha: 0.0),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: lineColor.withValues(alpha: 0.55),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzingOverlay(String lang) {
    final progress = _analysisProgressPercent;
    final detail = _analysisDetailLine();
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.48),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_analysisStageLabel(lang)} ($progress%)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _ensurePreviewContinues() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPreviewPaused) {
        await controller.resumePreview();
      }
    } catch (_) {
      // Keep capture flow resilient when preview resume is unsupported.
    }
  }

  Widget _buildCameraPreviewFill(BoxConstraints constraints) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    final previewAspect = math.max(controller.value.aspectRatio, 0.001);
    final previewHeight = constraints.maxWidth / previewAspect;

    return ClipRect(
      child: ColoredBox(
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: constraints.maxWidth,
            height: previewHeight,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  bool _isDiseaseReportFinal(DiseaseReportModel report) {
    return ApiClient.isDiseaseReportFinalStatus(report.status);
  }

  bool _shouldPollDiseaseReport(DiseaseReportModel report) {
    return ApiClient.shouldPollDiseaseReportStatus(report.status);
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Map<String, dynamic> _currentScanMetadata({
    required int captureShots,
    required String captureProtocol,
  }) {
    final metadata = <String, dynamic>{
      'capture_shots': captureShots,
      'capture_protocol': captureProtocol,
    };

    final growthStage = _selectedGrowthStage?.trim();
    if (growthStage != null && growthStage.isNotEmpty) {
      metadata['growth_stage'] = growthStage;
    }

    final symptomDays = int.tryParse(_symptomDaysController.text.trim());
    if (symptomDays != null && symptomDays >= 0) {
      metadata['symptom_days'] = symptomDays;
    }

    if (_recentRain != null) {
      metadata['recent_rain'] = _recentRain;
    }

    final fieldNotes = _fieldNotesController.text.trim();
    if (fieldNotes.isNotEmpty) {
      metadata['field_notes'] = fieldNotes;
    }

    return metadata;
  }

  Map<String, dynamic> _metadataWithOfflineProvisional({
    required Map<String, dynamic> baseMetadata,
    required ({
      OfflineInferenceResult inference,
      DiseaseTreatmentGuidance? guidance,
      String message,
    })?
    provisional,
    required String? selectedCropName,
    String? selectedPlotName,
  }) {
    final metadata = Map<String, dynamic>.from(baseMetadata);
    final inference = provisional?.inference;
    if (selectedCropName != null && selectedCropName.trim().isNotEmpty) {
      metadata['crop_name'] = selectedCropName.trim();
    }
    if (selectedPlotName != null && selectedPlotName.trim().isNotEmpty) {
      metadata['plot_name'] = selectedPlotName.trim();
    }
    if (inference == null) {
      return metadata;
    }
    metadata['offline_local_inference'] = provisional!.message;
    metadata['offline_local_disease_name'] = inference.displayDiseaseName;
    metadata['offline_local_disease_key'] = inference.canonicalDiseaseName;
    metadata['offline_local_severity'] = inference.severity;
    metadata['offline_local_confidence'] = inference.confidenceScore;
    metadata['offline_local_provisional'] = true;
    if (inference.topScores.isNotEmpty) {
      metadata['offline_local_top_scores'] = inference.topScores
          .map((score) => score.toJson())
          .toList();
    }
    final guidance = provisional.guidance;
    if (guidance != null) {
      metadata['offline_local_guidance'] = guidance.toJson();
    }
    final service = OfflineInferenceService.instance;
    final modelId = service.modelIdForCropName(selectedCropName);
    final modelVersion = service.modelVersionForCropName(selectedCropName);
    if (modelId.trim().isNotEmpty) {
      metadata['offline_local_model_id'] = modelId.trim();
    }
    if (modelVersion.trim().isNotEmpty) {
      metadata['offline_local_model'] = modelVersion.trim();
    }
    return metadata;
  }

  bool _hasMeaningfulOfflineFinding(Map<String, dynamic>? metadata) {
    final value = metadata?['offline_local_disease_name']?.toString().trim();
    return value != null && value.isNotEmpty;
  }

  Future<void> _saveSyncedLocalHistory({
    required String submissionId,
    required int plotId,
    required int cropId,
    required int? plantingId,
    required String imagePath,
    required DateTime capturedAtUtc,
    required Map<String, dynamic>? metadata,
  }) async {
    if (submissionId.trim().isEmpty ||
        !_hasMeaningfulOfflineFinding(metadata)) {
      return;
    }
    final stableImagePath =
        imagePath.contains(
          '${Platform.pathSeparator}pending_scans${Platform.pathSeparator}',
        )
        ? imagePath
        : (await _persistImageForOfflineQueue(imagePath) ?? imagePath);
    await LocalScanHistoryStore.instance.upsert(
      LocalScanHistoryEntry(
        submissionId: submissionId.trim(),
        plotId: plotId,
        cropId: cropId,
        plantingId: plantingId,
        imagePath: stableImagePath,
        capturedAtUtc: capturedAtUtc.toUtc(),
        syncedAtUtc: DateTime.now().toUtc(),
        scanMetadata: metadata == null
            ? null
            : Map<String, dynamic>.from(metadata),
      ),
    );
  }

  Future<void> _clearSyncedLocalHistory(String? submissionId) async {
    final trimmed = submissionId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    await LocalScanHistoryStore.instance.deleteBySubmissionId(trimmed);
  }

  String? _metadataString(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }

  int? _metadataInt(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '');
  }

  double? _metadataDouble(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '');
  }

  bool? _metadataBool(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key];
    if (value is bool) return value;
    if (value is num) return value != 0;

    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
      return true;
    }
    if (normalized == '0' || normalized == 'false' || normalized == 'no') {
      return false;
    }

    return null;
  }

  bool _looksLikeConnectivityIssue(String message) {
    if (_looksLikeSslConfigurationIssue(message)) {
      return false;
    }
    return ApiClient.isConnectivityIssueMessage(message);
  }

  bool _looksLikeSslConfigurationIssue(String message) {
    final m = message.toLowerCase();
    return m.contains('ssl') ||
        m.contains('tls') ||
        m.contains('handshake') ||
        m.contains('certificate') ||
        m.contains('unsupported ssl');
  }

  String _localSslHintMessage(String fallback) {
    return '$fallback\nUse local API URL: http://<your-pc-ip>:8000';
  }

  String _formatOfflineInferenceUnavailableReason(
    String rawReason, {
    String? selectedCropName,
  }) {
    final normalized = rawReason.trim().toLowerCase();
    final crop = selectedCropName?.trim();
    final cropHint = crop == null || crop.isEmpty
        ? 'Use one clear photo of a supported crop leaf.'
        : 'Use one clear close-up photo of a $crop leaf.';

    if (normalized.contains('confidence is too low')) {
      return 'This photo is not clear enough for a safe result yet. '
          '$cropHint Keep random objects and background out of the frame.';
    }
    if (normalized.contains(
      'does not appear to contain enough crop leaf area',
    )) {
      return 'This photo does not show enough of the crop leaf yet. '
          '$cropHint Fill more of the frame with the leaf.';
    }
    if (normalized.contains('too blurry, flat, or unclear')) {
      return 'This photo is too blurry or unclear for a safe result. '
          '$cropHint Hold steady and keep one leaf clear in the frame.';
    }
    if (normalized.contains('too ambiguous')) {
      return 'This photo needs a clearer view before the app can help safely. '
          '$cropHint Keep one affected leaf filling most of the frame.';
    }
    if (normalized.contains('does not match the selected crop family')) {
      return 'This photo does not look like the crop you selected. '
          'Confirm the crop first, then retake with the correct leaf.';
    }
    if (normalized.contains('outside the active model scope')) {
      return L.t(
        LanguageStore.notifier.value,
        'scan_offline_not_available_crop',
      );
    }
    return 'The app could not give a safe result from this photo. $cropHint';
  }

  bool _shouldQueueRetry(ApiException exception) {
    if (_looksLikeSslConfigurationIssue(exception.message)) {
      return false;
    }
    // Queue only for connectivity failures.
    // Do not queue backend availability errors (e.g., 503 inference unavailable),
    // so users see the real server-side message immediately.
    return _looksLikeConnectivityIssue(exception.message);
  }

  String _scanQueuedMessageByConnectivity(
    String languageCode,
    ApiConnectivityState state, {
    String? detail,
  }) {
    if (_scanExecutionMode == _ScanExecutionMode.offlineOnly) {
      return L.t(languageCode, 'scan_exec_offline_only_queue');
    }
    if (_scanExecutionMode == _ScanExecutionMode.preferOffline &&
        state == ApiConnectivityState.apiOnline) {
      return L.t(languageCode, 'scan_exec_prefer_offline_queue');
    }
    switch (state) {
      case ApiConnectivityState.offline:
        return L.t(languageCode, 'scan_saved_offline_retry');
      case ApiConnectivityState.internetOnly:
        return detail?.trim().isNotEmpty == true
            ? 'Saved on this device. It will send when connection is working again.\n$detail'
            : 'Saved on this device. It will send when connection is working again.';
      case ApiConnectivityState.apiOnline:
        return L.t(languageCode, 'scan_saved_offline_retry');
    }
  }

  String _cropLoadErrorByConnectivity(
    ApiConnectivityState state, {
    String? detail,
  }) {
    switch (state) {
      case ApiConnectivityState.offline:
        return 'No internet connection. Check network and retry.';
      case ApiConnectivityState.internetOnly:
        return detail?.trim().isNotEmpty == true
            ? detail!
            : 'Internet is available, but API is unreachable.';
      case ApiConnectivityState.apiOnline:
        return 'Failed to load registered trained crops.';
    }
  }

  Future<
    ({
      OfflineInferenceResult inference,
      DiseaseTreatmentGuidance? guidance,
      String message,
    })?
  >
  _maybeRunOfflineProvisional(
    String imagePath, {
    String? selectedCropName,
  }) async {
    try {
      final inference = await OfflineInferenceService.instance
          .inferFromImagePath(
            imagePath: imagePath,
            selectedCropName: selectedCropName,
          );
      if (inference == null) {
        return null;
      }
      final guidance = await OfflineTreatmentGuidanceService.instance
          .guidanceForDiseaseLabel(
            inference.diseaseName,
            cropName: selectedCropName,
          );
      final lang = LanguageStore.notifier.value;
      final message =
          '${Phrase.t(lang, 'offline_provisional_result')}: '
          '${inference.displayDiseaseName} '
          '(${LocalizedValue.severity(lang, inference.severity)}).';
      return (inference: inference, guidance: guidance, message: message);
    } catch (_) {
      return null;
    }
  }

  List<Widget> _structuredTreatmentDetailsSection(
    String languageCode,
    DiseaseTreatmentGuidance? guidance,
  ) {
    if (guidance == null) return const <Widget>[];
    final rows = <MapEntry<String, String>>[];
    if ((guidance.activeIngredient ?? '').trim().isNotEmpty) {
      rows.add(
        MapEntry<String, String>(
          'Active ingredient',
          guidance.activeIngredient!.trim(),
        ),
      );
    }
    if ((guidance.dosage ?? '').trim().isNotEmpty) {
      rows.add(MapEntry<String, String>('Dosage', guidance.dosage!.trim()));
    }
    if ((guidance.ppe ?? '').trim().isNotEmpty) {
      rows.add(MapEntry<String, String>('PPE', guidance.ppe!.trim()));
    }
    if ((guidance.preHarvestInterval ?? '').trim().isNotEmpty) {
      rows.add(
        MapEntry<String, String>(
          'Pre-harvest interval',
          guidance.preHarvestInterval!.trim(),
        ),
      );
    }
    if ((guidance.reEntryInterval ?? '').trim().isNotEmpty) {
      rows.add(
        MapEntry<String, String>(
          'Re-entry interval',
          guidance.reEntryInterval!.trim(),
        ),
      );
    }
    if (rows.isEmpty) return const <Widget>[];

    return <Widget>[
      _buildGuidanceCard(
        title: Phrase.t(languageCode, 'before_you_treat'),
        icon: Icons.health_and_safety_outlined,
        accent: const Color(0xFF7B4B00),
        items: rows
            .map((row) => '${row.key}: ${row.value}')
            .toList(growable: false),
        intro: Phrase.t(languageCode, 'before_treatment_confirm'),
      ),
    ];
  }

  List<String> _avoidItemsForGuidance(
    DiseaseTreatmentGuidance? guidance, {
    required String languageCode,
    bool includeVerificationReminder = false,
  }) {
    if (guidance == null && !includeVerificationReminder) {
      return const <String>[];
    }

    final items = <String>[];
    final seen = <String>{};

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (seen.add(trimmed.toLowerCase())) {
        items.add(trimmed);
      }
    }

    bool looksAvoidance(String value) {
      final lower = value.toLowerCase();
      return lower.contains('avoid ') ||
          lower.startsWith('avoid') ||
          lower.contains('do not') ||
          lower.contains("don't") ||
          lower.contains('never ') ||
          lower.contains('wait ') ||
          lower.contains('without ');
    }

    final nextStep = guidance?.nextStep ?? '';
    if (looksAvoidance(nextStep)) {
      add(nextStep);
    }

    for (final item in <String>[
      ...(guidance?.actions ?? const <String>[]),
      ...(guidance?.prevention ?? const <String>[]),
      ...(guidance?.notes ?? const <String>[]),
    ]) {
      if (looksAvoidance(item)) {
        add(item);
      }
    }

    if (includeVerificationReminder) {
      add(Phrase.t(languageCode, 'do_not_treat_wait_confirmation'));
    }

    return items;
  }

  Widget _buildGuidanceCard({
    required String title,
    required IconData icon,
    required Color accent,
    required List<String> items,
    String? intro,
  }) {
    if (items.isEmpty && (intro == null || intro.trim().isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: accent),
                ),
              ),
            ],
          ),
          if (intro != null && intro.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              intro.trim(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          for (final item in items) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showOfflineProvisionalSheet({
    required String languageCode,
    required OfflineInferenceResult inference,
    required DiseaseTreatmentGuidance? guidance,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final nextStep = (guidance?.nextStep ?? '').trim();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + media.viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Phrase.t(languageCode, 'offline_provisional_result'),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoBadge(
                        label: L.t(
                          languageCode,
                          'scan_offline_preliminary_badge',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF2B8B5)),
                    ),
                    child: Text(
                      Phrase.t(languageCode, 'offline_guidance_warning'),
                      style: TextStyle(
                        color: Color(0xFF9F1D1D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Phrase.t(languageCode, 'likely_issue_label'),
                    style: Theme.of(sheetContext).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    inference.displayDiseaseName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${LocalizedValue.severityLabel(languageCode)}: ${LocalizedValue.severity(languageCode, inference.severity)}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Phrase.t(languageCode, 'treatment_after_verification'),
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (nextStep.isNotEmpty) ...[
                    _buildGuidanceCard(
                      title: Phrase.t(languageCode, 'next_step_label'),
                      icon: Icons.arrow_forward_rounded,
                      accent: const Color(0xFF2E7D32),
                      items: const <String>[],
                      intro: nextStep,
                    ),
                  ],
                  ..._buildFarmerGuidanceFlow(
                    languageCode: languageCode,
                    guidance: guidance,
                    includeVerificationReminder: true,
                    includeTreatmentDetails: false,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(L.t(languageCode, 'close')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOfflineInferenceStatusCard(
    String languageCode, {
    String? selectedCropName,
  }) {
    final hasSelectedCrop =
        selectedCropName != null && selectedCropName.trim().isNotEmpty;
    if (!hasSelectedCrop) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE7DC)),
        ),
        child: Text(
          L.t(languageCode, 'scan_choose_crop'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }
    return FutureBuilder<OfflineInferenceReadiness>(
      future: OfflineInferenceService.instance.checkReadiness(
        selectedCropName: selectedCropName,
      ),
      builder: (context, snapshot) {
        final readiness = snapshot.data;
        final waiting =
            snapshot.connectionState == ConnectionState.waiting &&
            readiness == null;
        final ready = readiness?.ready ?? false;
        final title = ready
            ? L.t(languageCode, 'scan_offline_ready')
            : L.t(languageCode, 'scan_offline_not_ready');
        final detail = waiting
            ? L.t(languageCode, 'scan_offline_checking')
            : ready
            ? (hasSelectedCrop
                  ? L.t(languageCode, 'scan_offline_ready_selected')
                  : L.t(languageCode, 'scan_offline_ready_device'))
            : (hasSelectedCrop
                  ? L.t(languageCode, 'scan_offline_not_ready_selected')
                  : L.t(languageCode, 'scan_offline_not_ready_yet_simple'));
        final accent = ready
            ? const Color(0xFF2E7D32)
            : const Color(0xFFB26A00);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ready ? const Color(0xFFF3FBF4) : const Color(0xFFFFF8E8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ready ? const Color(0xFFBFDDBF) : const Color(0xFFEACF9D),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    ready ? Icons.offline_bolt_rounded : Icons.info_outline,
                    size: 18,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(detail, style: const TextStyle(fontSize: 12)),
              if (hasSelectedCrop) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [_InfoBadge(label: selectedCropName.trim())],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _onAnalysisPollProgress({
    required int attempt,
    required int maxAttempts,
    required String status,
  }) {
    if (!mounted) return;
    setState(() {
      _analysisPollAttempt = attempt < 0 ? 0 : attempt;
      _analysisPollMaxAttempts = maxAttempts <= 0 ? 1 : maxAttempts;
      _analysisLatestStatus = status.trim().isEmpty ? null : status.trim();
    });
    unawaited(_ensurePreviewContinues());
  }

  Future<DiseaseReportModel> _pollDiseaseReportUntilReady(
    DiseaseReportModel initial,
  ) async {
    const maxAttempts = 8;
    _onAnalysisPollProgress(
      attempt: 0,
      maxAttempts: maxAttempts,
      status: initial.status,
    );
    return ApiClient.pollForScanCompletion(
      reportId: initial.id,
      initialReport: initial,
      maxAttempts: maxAttempts,
      pollInterval: const Duration(seconds: 2),
      onProgress: (attempt, total, status) {
        _onAnalysisPollProgress(
          attempt: attempt,
          maxAttempts: total,
          status: status,
        );
      },
    );
  }

  bool _isUncertainReport(DiseaseReportModel report) {
    final description = (report.description ?? '').toLowerCase();
    return description.contains('marked uncertain') ||
        description.contains('low confidence prediction') ||
        description.contains('review-only mode');
  }

  bool _hasCropFamilyMismatch({
    required String? selectedCropName,
    required String predictedDiseaseName,
  }) {
    final selectedFamily = cropFamilyFromName(selectedCropName);
    final predictedFamily = diseaseFamilyFromKey(predictedDiseaseName);
    if (selectedFamily == null || predictedFamily == null) return false;
    return selectedFamily != predictedFamily;
  }

  String _displayDiseaseNameForResult(
    DiseaseReportModel report,
    String languageCode,
  ) {
    if (!isPendingDiseaseKey(report.canonicalDiseaseName)) {
      final raw = report.diseaseName.trim();
      if (raw.isNotEmpty) {
        return raw;
      }
      final display = localizedDiseaseLabel(
        languageCode,
        report.canonicalDiseaseName,
      );
      if (display.isNotEmpty) {
        return display;
      }
    }

    final headline = (report.treatmentGuidance?.headline ?? '').trim();
    if (headline.isNotEmpty) {
      return headline;
    }

    return Phrase.t(languageCode, 'diagnosis_pending_review');
  }

  String? _farmerFacingReportDetail(
    DiseaseReportModel report,
    String languageCode,
  ) {
    final failure = report.inferenceFailure;
    if (failure != null && failure.hasFailure) {
      final message = (failure.message ?? '').trim();
      return message.isEmpty
          ? Phrase.t(languageCode, 'scan_rejected_validation')
          : message;
    }

    final description = (report.description ?? '').trim();
    if (description.isEmpty) {
      return null;
    }

    final lower = description.toLowerCase();
    if (lower.contains('marked uncertain') ||
        lower.contains('low confidence prediction') ||
        lower.contains('review-only mode')) {
      return Phrase.t(languageCode, 'summary_awaiting_verification');
    }
    if (lower.contains('does not match selected crop')) {
      return Phrase.t(languageCode, 'summary_family_mismatch_locked');
    }
    if (lower.contains('manual review required') ||
        lower.contains('inference unavailable')) {
      return Phrase.t(languageCode, 'supporter_verification_pending');
    }

    return null;
  }

  List<Widget> _buildFarmerGuidanceFlow({
    required String languageCode,
    required DiseaseTreatmentGuidance? guidance,
    bool includeVerificationReminder = false,
    bool includeTreatmentDetails = true,
  }) {
    if (guidance == null) return const <Widget>[];

    final avoidItems = _avoidItemsForGuidance(
      guidance,
      languageCode: languageCode,
      includeVerificationReminder: includeVerificationReminder,
    );

    return <Widget>[
      if (includeTreatmentDetails)
        ..._structuredTreatmentDetailsSection(languageCode, guidance),
      _buildGuidanceCard(
        title: Phrase.t(languageCode, 'what_to_do_now'),
        icon: Icons.task_alt_rounded,
        accent: const Color(0xFF1F6B45),
        items: guidance.actions,
      ),
      _buildGuidanceCard(
        title: Phrase.t(languageCode, 'what_to_avoid_now'),
        icon: Icons.do_not_disturb_on_outlined,
        accent: const Color(0xFFB26A00),
        items: avoidItems,
      ),
      _buildGuidanceCard(
        title: Phrase.t(languageCode, 'what_to_watch_next'),
        icon: Icons.visibility_outlined,
        accent: const Color(0xFF0C5D8F),
        items: guidance.monitoring,
      ),
      _buildGuidanceCard(
        title: Phrase.t(languageCode, 'protect_rest_of_field'),
        icon: Icons.shield_outlined,
        accent: const Color(0xFF5B7A1C),
        items: guidance.prevention,
      ),
      _buildGuidanceCard(
        title: Phrase.t(languageCode, 'get_help_quickly_if'),
        icon: Icons.support_agent_outlined,
        accent: const Color(0xFF8D1B3D),
        items: guidance.escalateIf,
      ),
    ];
  }

  Future<void> _showInferenceFailureFeedback(
    DiseaseReportModel report, {
    String? selectedCropName,
  }) async {
    if (!mounted) return;
    final failure = report.inferenceFailure;
    if (failure == null || !failure.hasFailure) {
      return;
    }

    final fallbackMessage = failure.isNotAPlant
        ? Phrase.t(LanguageStore.notifier.value, 'no_leaf_detected')
        : failure.isCropMismatch
        ? Phrase.t(LanguageStore.notifier.value, 'crop_mismatch_rescan')
        : Phrase.t(LanguageStore.notifier.value, 'scan_rejected_validation');
    final message = (failure.message ?? '').trim().isNotEmpty
        ? failure.message!.trim()
        : fallbackMessage;

    if (failure.isNotAPlant) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (failure.isCropMismatch) {
      final lang = LanguageStore.notifier.value;
      final selected = (failure.selected ?? selectedCropName ?? '').trim();
      final detected = (failure.detected ?? '').trim();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(Phrase.t(lang, 'crop_mismatch_title')),
            content: Text(
              '${Phrase.t(lang, 'selected_crop')}: ${LocalizedValue.crop(lang, selected.isEmpty ? LocalizedValue.fixed(lang, 'unknown') : selected)}\n'
              '${Phrase.t(lang, 'detected_crop')}: ${LocalizedValue.crop(lang, detected.isEmpty ? LocalizedValue.fixed(lang, 'unknown') : detected)}\n\n$message',
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
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDiseaseResultSheet(
    DiseaseReportModel report, {
    String? selectedCropName,
    ScanMode originMode = ScanMode.disease,
  }) async {
    if (!mounted) return;
    final lang = LanguageStore.notifier.value;
    _setScanUiState(_ScanUiState.showingResult);
    final guidance = report.treatmentGuidance;
    final failure = report.inferenceFailure;
    final hasFailure = failure != null && failure.hasFailure;
    final notAPlantFailure = failure?.isNotAPlant ?? false;
    final cropMismatchFailure = failure?.isCropMismatch ?? false;
    final displayDiseaseName = _displayDiseaseNameForResult(report, lang);
    final farmerFacingDetail = _farmerFacingReportDetail(report, lang);
    final healthyResult = isHealthyDiseaseKey(report.canonicalDiseaseName);
    final mode = guidance?.mode.trim().toLowerCase() ?? '';
    final status = report.status.trim().toLowerCase();
    final treatmentReady = guidance?.canShowTreatmentDetails ?? false;
    final rejected = mode == 'do_not_treat' || status == 'rejected';
    final diagnosisConfirmed =
        !hasFailure &&
        !rejected &&
        (status == 'confirmed' ||
            status == 'verified' ||
            report.reviewedAt != null ||
            report.verifiedAt != null);
    final advisoryTreatmentAvailable = diagnosisConfirmed && mode == 'treat';
    final treatmentApprovalPending = diagnosisConfirmed && !treatmentReady;
    final treatmentVisible = treatmentReady || advisoryTreatmentAvailable;
    final awaitingVerification = !rejected && !treatmentVisible;
    final uncertain = mode == 'pending_review' || _isUncertainReport(report);
    final treatmentLocked =
        hasFailure ||
        rejected ||
        uncertain ||
        awaitingVerification ||
        !treatmentVisible;
    final selectedFamily = cropFamilyFromName(selectedCropName);
    final predictedFamily = diseaseFamilyFromKey(report.canonicalDiseaseName);
    final cropMismatch =
        cropMismatchFailure ||
        (selectedFamily != null &&
            predictedFamily != null &&
            selectedFamily != predictedFamily);
    final fallbackNextAction = rejected
        ? Phrase.t(lang, 'do_not_treat_wait_feedback')
        : cropMismatch
        ? Phrase.t(lang, 'crop_family_mismatch_wait')
        : healthyResult
        ? Phrase.t(lang, 'healthy_leaf_next_step')
        : uncertain
        ? Phrase.t(lang, 'do_not_treat_wait_confirmation')
        : advisoryTreatmentAvailable
        ? Phrase.t(lang, 'summary_confirmed_advisory_treatment')
        : treatmentApprovalPending
        ? Phrase.t(lang, 'summary_confirmed_treatment_pending')
        : awaitingVerification
        ? Phrase.t(lang, 'supporter_verification_pending')
        : Phrase.t(lang, 'follow_approved_guidance');
    var nextAction = (guidance?.nextStep ?? '').trim().isNotEmpty
        ? guidance!.nextStep.trim()
        : fallbackNextAction;
    var headline = (guidance?.headline ?? '').trim().isNotEmpty
        ? guidance!.headline.trim()
        : (rejected
              ? Phrase.t(lang, 'diagnosis_rejected')
              : cropMismatch
              ? Phrase.t(lang, 'crop_mismatch_title')
              : healthyResult
              ? Phrase.t(lang, 'healthy_leaf_title')
              : uncertain
              ? Phrase.t(lang, 'diagnosis_pending_review')
              : advisoryTreatmentAvailable
              ? Phrase.t(lang, 'diagnosis_confirmed_treatment_pending')
              : treatmentApprovalPending
              ? Phrase.t(lang, 'diagnosis_confirmed_treatment_pending')
              : awaitingVerification
              ? Phrase.t(lang, 'verification_pending')
              : Phrase.t(lang, 'treatment_guidance_ready'));
    var statusText = rejected
        ? LocalizedValue.fixed(lang, 'scan_result_rejected')
        : cropMismatch
        ? Phrase.t(lang, 'crop_mismatch_title')
        : healthyResult
        ? Phrase.t(lang, 'healthy_leaf_status')
        : mode == 'monitor_only'
        ? LocalizedValue.status(lang, 'monitor_only')
        : uncertain
        ? LocalizedValue.fixed(lang, 'scan_result_pending_review')
        : advisoryTreatmentAvailable
        ? LocalizedValue.fixed(lang, 'scan_result_diagnosis_confirmed')
        : treatmentApprovalPending
        ? LocalizedValue.fixed(lang, 'scan_result_diagnosis_confirmed')
        : awaitingVerification
        ? LocalizedValue.fixed(lang, 'scan_result_needs_verification')
        : LocalizedValue.fixed(lang, 'scan_result_treatment_ready');
    Color statusColor = rejected
        ? Colors.red.shade700
        : cropMismatch
        ? Colors.red.shade700
        : healthyResult
        ? Colors.green.shade700
        : mode == 'monitor_only'
        ? Colors.blue.shade700
        : uncertain
        ? Colors.orange.shade700
        : awaitingVerification
        ? Colors.orange.shade700
        : Colors.green.shade700;
    if (notAPlantFailure) {
      statusText = Phrase.t(lang, 'no_leaf_detected');
      statusColor = Colors.red.shade700;
      headline = Phrase.t(lang, 'capture_rejected');
      nextAction = (failure?.message ?? '').trim().isNotEmpty
          ? failure!.message!.trim()
          : Phrase.t(lang, 'no_leaf_detected_capture_again');
    } else if (cropMismatchFailure) {
      statusText = Phrase.t(lang, 'crop_mismatch_title');
      statusColor = Colors.red.shade700;
      headline = Phrase.t(lang, 'selected_crop_mismatch');
      nextAction = (failure?.message ?? '').trim().isNotEmpty
          ? failure!.message!.trim()
          : Phrase.t(lang, 'selected_detected_crop_different');
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + media.viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L.t(lang, 'scan_state_result_ready'),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    displayDiseaseName,
                    style: Theme.of(sheetContext).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    headline,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasFailure
                        ? ((failure.message ?? '').trim().isNotEmpty
                              ? (failure.message ?? '').trim()
                              : Phrase.t(lang, 'scan_rejected_validation'))
                        : rejected
                        ? Phrase.t(lang, 'summary_rejected_no_treatment')
                        : cropMismatch
                        ? Phrase.t(lang, 'summary_family_mismatch_locked')
                        : healthyResult
                        ? Phrase.t(lang, 'healthy_leaf_summary')
                        : uncertain
                        ? Phrase.t(lang, 'summary_unreliable')
                        : advisoryTreatmentAvailable
                        ? Phrase.t(lang, 'summary_confirmed_advisory_treatment')
                        : treatmentApprovalPending
                        ? Phrase.t(lang, 'summary_confirmed_treatment_pending')
                        : awaitingVerification
                        ? Phrase.t(lang, 'summary_awaiting_verification')
                        : Phrase.t(lang, 'summary_ready'),
                  ),
                  if (selectedCropName != null &&
                      selectedCropName.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${Phrase.t(lang, 'selected_crop')}: ${LocalizedValue.crop(lang, selectedCropName)}',
                    ),
                  ],
                  _buildGuidanceCard(
                    title: Phrase.t(lang, 'next_step_label'),
                    icon: Icons.arrow_forward_rounded,
                    accent: const Color(0xFF2E7D32),
                    items: const <String>[],
                    intro: nextAction,
                  ),
                  if (treatmentLocked)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF2B8B5)),
                      ),
                      child: Text(
                        Phrase.t(
                          lang,
                          treatmentApprovalPending
                              ? 'treatment_hidden_until_approved'
                              : 'treatment_hidden_until_verification',
                        ),
                        style: const TextStyle(
                          color: Color(0xFF9F1D1D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (!treatmentLocked &&
                      advisoryTreatmentAvailable &&
                      !treatmentReady)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7E8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE6C77A)),
                      ),
                      child: Text(
                        Phrase.t(lang, 'treatment_advisory_after_confirmation'),
                        style: const TextStyle(
                          color: Color(0xFF7A4A00),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ..._buildFarmerGuidanceFlow(
                    languageCode: lang,
                    guidance: guidance,
                    includeVerificationReminder: treatmentLocked,
                    includeTreatmentDetails: !treatmentLocked,
                  ),
                  if (farmerFacingDetail != null &&
                      farmerFacingDetail.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(farmerFacingDetail),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop('rescan'),
                          icon: const Icon(Icons.camera_alt),
                          label: Text(L.t(lang, 'rescan')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop('history'),
                          icon: const Icon(Icons.history),
                          label: Text(L.t(lang, 'scan_history')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (mounted) {
      _setScanUiState(_ScanUiState.idle);
      if (action == 'rescan') {
        _capture();
      } else if (action == 'history') {
        final target = originMode == ScanMode.cropHealth
            ? const CropHealthScreen()
            : const DiseaseCheckScreen();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => target));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadScanExecutionMode());
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    // Avoid background API spam: only drain the pending scan queue when the
    // Scan tab is active (or when ScanScreen is pushed directly).
    if (widget.isActive) {
      unawaited(_refreshQueueStatus());
      unawaited(_drainPendingScanQueue());
      _startQueueAutoDrain();
    }
    if (widget.initialMode == null && widget.isActive) {
      _loadCropContextsForDirectScan();
    } else if (widget.initialMode != null) {
      _cameraRequested = true;
      _initCamera();
    }
  }

  @override
  void didUpdateWidget(covariant ScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMode != null) {
      return;
    }

    if (oldWidget.isActive && !widget.isActive) {
      _stopQueueAutoDrain();
      _resetDirectScanSession(clearSelection: true);
      return;
    }

    if (!oldWidget.isActive && widget.isActive) {
      unawaited(_refreshQueueStatus());
      unawaited(_drainPendingScanQueue());
      _startQueueAutoDrain();
      _loadCropContextsForDirectScan();
    }
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoScanLoop();
    _stopQueueAutoDrain();
    _scanLineController.dispose();
    _symptomDaysController.dispose();
    _fieldNotesController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _handleSyncRefresh() {
    if (!mounted || !widget.isActive) return;
    unawaited(_refreshQueueStatus());
    if (widget.initialMode == null) {
      unawaited(_loadCropContextsForDirectScan());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.isActive) {
        _startQueueAutoDrain();
        unawaited(_refreshQueueStatus());
        unawaited(_drainPendingScanQueue());
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopQueueAutoDrain();
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopAutoScanLoop();
      controller.dispose();
      if (mounted) {
        setState(() {
          _controller = null;
        });
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (widget.initialMode == null && (!widget.isActive || !_cameraRequested)) {
      return;
    }
    if (_cameraInitializing) return;
    final generation = ++_cameraGeneration;
    _cameraInitializing = true;
    try {
      final previous = _controller;
      if (previous != null) {
        await previous.dispose();
        if (mounted) {
          setState(() {
            _controller = null;
          });
        }
      }

      final status = await Permission.camera.status;
      if (!status.isGranted) {
        if (status.isPermanentlyDenied || status.isRestricted) {
          if (mounted) {
            setState(() {
              _errorKey = 'camera_permission_denied';
              _errorDetail = L.t(
                LanguageStore.notifier.value,
                'scan_permission_settings_required',
              );
            });
          }
          return;
        }
        final result = await Permission.camera.request();
        if (!result.isGranted) {
          if (result.isPermanentlyDenied || result.isRestricted) {
            if (mounted) {
              setState(() {
                _errorKey = 'camera_permission_denied';
                _errorDetail = L.t(
                  LanguageStore.notifier.value,
                  'scan_permission_settings_required',
                );
              });
            }
            return;
          }
          if (mounted) {
            setState(() {
              _errorKey = 'camera_permission_denied';
            });
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _permissionGranted = true;
          _errorKey = null;
          _errorDetail = null;
        });
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          setState(() {
            _errorKey = 'no_cameras';
          });
        }
        return;
      }

      final backCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high, // improved quality
        enableAudio: false,
      );

      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      final requestedFlashMode = _flashlightEnabled
          ? FlashMode.torch
          : FlashMode.off;
      try {
        await controller.setFlashMode(requestedFlashMode);
      } catch (_) {
        _flashlightEnabled = false;
        try {
          await controller.setFlashMode(FlashMode.off);
        } catch (_) {
          // Some devices may not support flash controls.
        }
      }

      if (!mounted ||
          generation != _cameraGeneration ||
          (widget.initialMode == null &&
              (!widget.isActive || !_cameraRequested))) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _errorKey = null;
        _errorDetail = null;
        _liveGuidance = _defaultGuidance;
      });
      _setScanUiState(_ScanUiState.idle);
      await _syncCameraCapabilities(controller);
      _stopAutoScanLoop();
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _errorKey = 'camera_error';
          _errorDetail = e.description ?? e.code;
        });
        _setScanUiState(_ScanUiState.error);
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _errorKey = 'camera_error';
          _errorDetail = 'Camera initialization timeout';
        });
        _setScanUiState(_ScanUiState.error);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorKey = 'unexpected_error';
          _errorDetail = e.toString();
        });
        _setScanUiState(_ScanUiState.error);
      }
    } finally {
      _cameraInitializing = false;
    }
  }

  Future<void> _capture() async {
    if (_captureInProgress) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (widget.initialMode == null && _selectedCropContext == null) {
      final lang = LanguageStore.notifier.value;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L.t(lang, 'scan_crop_required'))));
      return;
    }
    _captureInProgress = true;
    try {
      _setScanUiState(_ScanUiState.capturing);
      if (mounted) {
        setState(() {
          _liveGuidance = 'Hold still';
        });
      }
      final picked = await _captureBestFrame();
      final file = picked.file;
      final quality = picked.quality;
      _setScanUiState(_ScanUiState.qualityChecking);
      if (!quality.passed) {
        if (!mounted) return;
        _setScanUiState(_ScanUiState.error);
        _QualityDecision? decision = _QualityDecision.useAnyway;
        if (!_qualityDialogOpen) {
          _qualityDialogOpen = true;
          try {
            decision = await _showQualityGateDialog(quality);
          } finally {
            _qualityDialogOpen = false;
          }
        }
        if (mounted) {
          _setScanUiState(_ScanUiState.idle);
          setState(() {
            _liveGuidance = 'Move closer and retake';
          });
        }
        if (decision == _QualityDecision.retake) {
          Future<void>.delayed(const Duration(milliseconds: 120), _capture);
          return;
        }
        if (decision == _QualityDecision.useAnyway) {
          if (mounted) {
            setState(() {
              _liveGuidance = 'Saving this photo';
            });
          }
        } else {
          if (_autoScanAllowed && _autoScanEnabled) {
            if (mounted) {
              setState(() {
                _autoScanEnabled = false;
              });
            }
            _stopAutoScanLoop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    LocalizedValue.fixed(
                      LanguageStore.notifier.value,
                      'scan_auto_paused_low_quality',
                    ),
                  ),
                ),
              );
            }
          }
          return;
        }
      }
      final duplicateFrame =
          _structuredCaptureCandidates.isNotEmpty &&
          _isDuplicateFrame(quality.frameHash);
      if (duplicateFrame && mounted) {
        setState(() {
          _liveGuidance = 'Accepted. Turn leaf slightly';
        });
      }
      _rememberFrameHash(quality.frameHash);
      _structuredCaptureCandidates.add(
        _StructuredCaptureCandidate(file: file, quality: quality),
      );
      if (_structuredCaptureCandidates.length > _structuredCaptureMaxShots) {
        final dropped = _structuredCaptureCandidates.removeAt(0);
        if (dropped.file.path != file.path) {
          try {
            final droppedFile = File(dropped.file.path);
            if (await droppedFile.exists()) {
              await droppedFile.delete();
            }
          } catch (_) {
            // Ignore temp file cleanup errors.
          }
        }
      }

      final collected = _structuredCaptureCandidates.length;
      if (collected < _structuredCaptureRequiredShots) {
        final remaining = _structuredCaptureRequiredShots - collected;
        _setScanUiState(_ScanUiState.idle);
        if (mounted) {
          setState(() {
            _lastCaptured = file;
            _liveGuidance =
                'Take $remaining more photo${remaining == 1 ? '' : 's'}';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Capture saved ($collected/$_structuredCaptureRequiredShots). '
                'Take $remaining more.',
              ),
            ),
          );
        }
        return;
      }

      final selectedFile = _bestStructuredCaptureFile(file);
      await _clearStructuredCaptureCandidates(keepPath: selectedFile.path);
      setState(() {
        _lastCaptured = selectedFile;
        _liveGuidance = 'Saving scan';
      });

      if (!mounted) return;
      final forcedMode = widget.initialMode;
      if (forcedMode != null) {
        _handleScan(selectedFile, forcedMode);
      } else {
        _handleScan(selectedFile, ScanMode.disease);
      }
    } catch (e) {
      _setScanUiState(_ScanUiState.error);
      if (!mounted) return;
      final lang = LanguageStore.notifier.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${L.t(lang, 'capture_failed')}: $e')),
      );
      _setScanUiState(_ScanUiState.idle);
      if (mounted) {
        setState(() {
          _liveGuidance = 'Try again';
        });
      }
    } finally {
      _captureInProgress = false;
    }
  }

  Future<_BestCaptureResult> _captureBestFrame() async {
    final controller = _controller!;
    final attempts = _autoScanAllowed ? 3 : 1;
    _BestCaptureResult? bestOverall;
    _BestCaptureResult? bestPassed;

    for (var i = 0; i < attempts; i++) {
      final file = await controller.takePicture();
      await _ensurePreviewContinues();
      final quality = await _assessImageQuality(file);
      final current = _BestCaptureResult(file: file, quality: quality);
      if (bestOverall == null ||
          current.quality.score > bestOverall.quality.score) {
        bestOverall = current;
      }
      if (quality.passed) {
        if (bestPassed == null || quality.score > bestPassed.quality.score) {
          bestPassed = current;
        }
      }
      if (attempts > 1 && i < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
    await _ensurePreviewContinues();
    return bestPassed ?? bestOverall!;
  }

  Future<void> _startCameraForSelectedCrop() async {
    if (_selectedCropContext == null) return;
    unawaited(
      OfflineInferenceService.instance.prepareForCropName(
        _selectedCropContext!.cropName,
      ),
    );
    setState(() {
      _cameraRequested = true;
      _errorKey = null;
      _errorDetail = null;
      _liveGuidance = _defaultGuidance;
    });
    _setScanUiState(_ScanUiState.idle);
    await _initCamera();
    unawaited(_drainPendingScanQueue());
  }

  Future<void> _handleSupportedCropTap(_SupportedCropDefinition crop) async {
    final familyMatches = _cropContexts
        .where((item) => item.family == crop.family && !item.quickTestOnly)
        .toList(growable: false);

    _ScanCropContext selectedContext;
    if (familyMatches.isNotEmpty) {
      final picked = await _showCropContextPicker(
        crop: crop,
        contexts: familyMatches,
      );
      if (picked == null || !mounted) return;
      selectedContext = picked;
    } else {
      selectedContext = _ScanCropContext(
        farmId: 0,
        farmName: L.t(
          LanguageStore.notifier.value,
          'scan_offline_test_context',
        ),
        plotId: 0,
        plotName: L.t(
          LanguageStore.notifier.value,
          'scan_offline_test_no_plot',
        ),
        cropId: 0,
        cropName: crop.cropName,
        plantingId: null,
        quickTestOnly: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$candidateUploadBlockedText Add or sync a ${crop.cropName} planting first to upload for expert review.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 7),
          ),
        );
      }
    }

    setState(() {
      _selectedCropContext = selectedContext;
    });
    unawaited(
      OfflineInferenceService.instance.prepareForCropName(
        selectedContext.cropName,
      ),
    );
    unawaited(_cacheSelectedCropContext(selectedContext));
    unawaited(_startCameraForSelectedCrop());
  }

  Future<_ScanCropContext?> _showCropContextPicker({
    required _SupportedCropDefinition crop,
    required List<_ScanCropContext> contexts,
  }) {
    final lang = LanguageStore.notifier.value;
    return showModalBottomSheet<_ScanCropContext>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFCF0),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L.t(
                    lang,
                    'scan_choose_context_for_crop',
                    params: {'crop': LocalizedValue.crop(lang, crop.cropName)},
                  ),
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1E2A12),
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  L.t(lang, 'scan_context_picker_hint'),
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: contexts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = contexts[index];
                      final accent = _ScanCropSelectorGrid._cropAccent(crop.family);
                      return FarmPanel(
                        padding: EdgeInsets.zero,
                        onTap: () => Navigator.of(sheetContext).pop(item),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(Icons.place_outlined, color: accent),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.plotName,
                                      style: Theme.of(sheetContext)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF1E2A12),
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.farmName,
                                      style: Theme.of(sheetContext)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _CropCardPill(
                                          icon: Icons.eco_rounded,
                                          label: LocalizedValue.crop(lang, item.cropName),
                                          color: accent,
                                        ),
                                        if (item.plantingId != null)
                                          _CropCardPill(
                                            icon: Icons.spa_outlined,
                                            label: 'Planting #${item.plantingId}',
                                            color: const Color(0xFF4F7D12),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.chevron_right_rounded, color: accent),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  void _stopAutoScanLoop() {
    // Auto-scan is intentionally disabled; scan flow is manual-only.
  }

  Future<void> _releaseCamera() async {
    _cameraGeneration++;
    _stopAutoScanLoop();
    _stopScanLineAnimation();
    final controller = _controller;
    if (controller != null) {
      await controller.dispose();
    }
    if (!mounted) return;
    setState(() {
      _controller = null;
      _flashlightEnabled = false;
      _zoomLevel = 1.0;
      _minZoom = 1.0;
      _maxZoom = 1.0;
    });
  }

  Future<void> _resetDirectScanSession({bool clearSelection = true}) async {
    await _clearStructuredCaptureCandidates();
    if (mounted) {
      setState(() {
        _cameraRequested = false;
        _scanUiState = _ScanUiState.idle;
        _liveGuidance = _defaultGuidance;
        if (clearSelection) {
          _selectedCropContext = null;
        }
      });
    }
    await _releaseCamera();
  }

  Future<_QualityAssessment> _assessImageQuality(XFile file) async {
    try {
      final f = File(file.path);
      if (!await f.exists()) {
        return const _QualityAssessment(
          passed: false,
          reasons: ['Image file was not found. Please retake the photo.'],
        );
      }

      final fileSize = await f.length();
      if (fileSize < _minImageBytes) {
        return const _QualityAssessment(
          passed: false,
          reasons: ['Image quality is too low. Move closer and retake.'],
        );
      }

      final bytes = await file.readAsBytes();
      final analysis = await Isolate.run(() => _analyzeQualityBytes(bytes));
      if (analysis == null) {
        return const _QualityAssessment(
          passed: false,
          reasons: ['Unable to read image details. Please retake.'],
        );
      }

      final width = analysis['width'] as int;
      final height = analysis['height'] as int;
      final stats = _LuminanceStats(
        mean: analysis['mean'] as double,
        stdDev: analysis['std_dev'] as double,
        greenRatio: analysis['green_ratio'] as double,
        edgeRatio: analysis['edge_ratio'] as double,
      );
      final frameHash = analysis['frame_hash'] as int;

      if (width < _minImageSide || height < _minImageSide) {
        return _QualityAssessment(
          passed: false,
          reasons: [
            'Image resolution is too low ($width x $height). Retake closer.',
          ],
        );
      }

      final reasons = <String>[];
      if (stats.mean < _minLuminance) {
        reasons.add('Image is too dark. Improve lighting and retake.');
      } else if (stats.mean > _maxLuminance) {
        reasons.add('Image is too bright. Avoid direct glare and retake.');
      }
      if (stats.stdDev < _minQualityStdDev) {
        reasons.add(
          'Image appears blurry or low contrast. Hold steady and focus on leaves.',
        );
      }
      if (stats.greenRatio < _minQualityGreenRatio) {
        reasons.add('Leaf area is not clear. Move closer to affected leaves.');
      }
      if (stats.edgeRatio < _minQualityEdgeRatio) {
        reasons.add('Low texture detected. Refocus and avoid motion blur.');
      }

      final score = _qualityScore(stats);
      final passed = reasons.isEmpty;
      if (mounted) {
        setState(() {
          _liveGuidance = passed
              ? 'Quality good. Processing...'
              : reasons.first;
        });
      }

      return _QualityAssessment(
        passed: passed,
        reasons: reasons,
        score: score,
        frameHash: frameHash,
      );
    } catch (_) {
      return const _QualityAssessment(
        passed: false,
        reasons: ['Could not verify image quality. Please retake the photo.'],
      );
    }
  }

  bool _isDuplicateFrame(int frameHash) =>
      _recentFrameHashes.contains(frameHash);

  void _rememberFrameHash(int frameHash) {
    _recentFrameHashes.add(frameHash);
    if (_recentFrameHashes.length > 10) {
      _recentFrameHashes.removeAt(0);
    }
  }

  Future<String> _ensurePendingScanDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final queueDir = Directory(
      '${appDir.path}${Platform.pathSeparator}pending_scans',
    );
    if (!await queueDir.exists()) {
      await queueDir.create(recursive: true);
    }
    return queueDir.path;
  }

  String _queueImageExtension(String sourcePath) {
    final lower = sourcePath.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.jpeg')) return 'jpeg';
    return 'jpg';
  }

  Future<String?> _persistImageForOfflineQueue(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return null;
      }
      final queueDir = await _ensurePendingScanDirectory();
      final randomHex = math.Random()
          .nextInt(1 << 31)
          .toRadixString(16)
          .padLeft(8, '0');
      final extension = _queueImageExtension(sourcePath);
      final targetPath =
          '$queueDir${Platform.pathSeparator}scan_${DateTime.now().millisecondsSinceEpoch}_$randomHex.$extension';
      await source.copy(targetPath);
      return targetPath;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteManagedQueuedImage(String imagePath) async {
    try {
      final queueDir = await _ensurePendingScanDirectory();
      if (!imagePath.startsWith(queueDir)) return;
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup failures.
    }
  }

  bool _isQueuedEntryExpired(DateTime capturedAt) {
    return DateTime.now().difference(capturedAt.toUtc()) > _maxPendingQueueAge;
  }

  String _nextPendingQueueId() {
    final randomHex = math.Random()
        .nextInt(1 << 31)
        .toRadixString(16)
        .padLeft(8, '0');
    return 'scan_${DateTime.now().millisecondsSinceEpoch}_$randomHex';
  }

  DateTime _nextRetryAt(int attempts) {
    final boundedAttempts = attempts < 1 ? 1 : attempts;
    final multiplier = math.pow(2, boundedAttempts - 1).toInt();
    final seconds = _initialPendingRetryDelay.inSeconds * multiplier;
    final boundedSeconds = seconds > _maxPendingRetryDelay.inSeconds
        ? _maxPendingRetryDelay.inSeconds
        : seconds;
    return DateTime.now().toUtc().add(Duration(seconds: boundedSeconds));
  }

  void _startQueueAutoDrain() {
    _queueAutoDrainTimer?.cancel();
    if (!widget.isActive) return;
    _queueAutoDrainTimer = Timer.periodic(_queueAutoDrainInterval, (_) {
      if (!mounted) return;
      if (!widget.isActive) return;
      final status = ConnectivityStatusService.instance.notifier.value;
      if (status.state != ApiConnectivityState.apiOnline) {
        return;
      }
      unawaited(_refreshQueueStatus());
      unawaited(_drainPendingScanQueue());
    });
  }

  void _drainQueuedScanNowIfAllowed(ApiConnectivityStatus status) {
    if (_scanExecutionMode == _ScanExecutionMode.offlineOnly) {
      return;
    }
    if (status.state != ApiConnectivityState.apiOnline) {
      return;
    }
    unawaited(_refreshQueueStatus());
    unawaited(_drainPendingScanQueue());
  }

  void _stopQueueAutoDrain() {
    _queueAutoDrainTimer?.cancel();
    _queueAutoDrainTimer = null;
  }

  Future<void> _clearStructuredCaptureCandidates({String? keepPath}) async {
    final keep = keepPath?.trim();
    final paths = _structuredCaptureCandidates
        .map((candidate) => candidate.file.path)
        .where((path) => path.trim().isNotEmpty)
        .where((path) => keep == null || path != keep)
        .toSet();
    _structuredCaptureCandidates.clear();
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore temp file cleanup errors.
      }
    }
  }

  XFile _bestStructuredCaptureFile(XFile fallback) {
    if (_structuredCaptureCandidates.isEmpty) {
      return fallback;
    }
    var best = _structuredCaptureCandidates.first;
    for (final candidate in _structuredCaptureCandidates.skip(1)) {
      if (candidate.quality.score > best.quality.score) {
        best = candidate;
      }
    }
    return best.file;
  }

  Widget _buildScanMetadataCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE7DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocalizedValue.fixed(
              LanguageStore.notifier.value,
              'optional_field_context',
            ),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedGrowthStage,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Growth stage',
              isDense: true,
            ),
            items: _growthStageOptions
                .map(
                  (stage) => DropdownMenuItem<String>(
                    value: stage,
                    child: Text(stage),
                  ),
                )
                .toList(),
            onChanged: _isBusy
                ? null
                : (value) {
                    setState(() {
                      _selectedGrowthStage = value;
                    });
                  },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _symptomDaysController,
            keyboardType: TextInputType.number,
            enabled: !_isBusy,
            decoration: const InputDecoration(
              labelText: 'Symptom days (optional)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            value: _recentRain ?? false,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              LocalizedValue.fixed(
                LanguageStore.notifier.value,
                'recent_rain_last_7_days',
              ),
            ),
            onChanged: _isBusy
                ? null
                : (value) {
                    setState(() {
                      _recentRain = value;
                    });
                  },
          ),
          TextField(
            controller: _fieldNotesController,
            enabled: !_isBusy,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Field notes (optional)',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredCaptureCard() {
    final collected = _structuredCaptureCandidates.length;
    final remaining = _structuredCaptureRequiredShots - collected;
    final completed = remaining <= 0;
    final subtitle = completed
        ? 'Protocol complete. Ready to submit.'
        : 'Capture $remaining more leaf angle${remaining == 1 ? '' : 's'} before submit.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB8D6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Structured capture: $collected/$_structuredCaptureRequiredShots',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(subtitle),
        ],
      ),
    );
  }

  Future<void> _refreshQueueStatus() async {
    if (_queueStatusLoading) return;
    _queueStatusLoading = true;
    try {
      final all = await PendingScanQueueStore.instance.listAll();
      var retrying = 0;
      DateTime? nextRetry;
      for (final entry in all) {
        if (entry.attempts > 0) {
          retrying += 1;
        }
        if (nextRetry == null || entry.nextRetryAtUtc.isBefore(nextRetry)) {
          nextRetry = entry.nextRetryAtUtc;
        }
      }
      if (!mounted) return;
      setState(() {
        _queuePendingCount = all.length;
        _queueRetryingCount = retrying;
        _queueNextRetryAt = nextRetry;
      });
    } finally {
      _queueStatusLoading = false;
    }
  }

  Future<void> _migrateLegacyPendingQueueIfNeeded() async {
    if (_legacyQueueMigrated) return;
    _legacyQueueMigrated = true;

    final prefs = await SharedPreferences.getInstance();
    final legacy =
        prefs.getStringList(_legacyPendingScanQueueKey) ?? <String>[];
    if (legacy.isEmpty) {
      return;
    }

    final store = PendingScanQueueStore.instance;
    for (final item in legacy) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(item) as Map);
        final plotId = map['plot_id'] is num
            ? (map['plot_id'] as num).toInt()
            : null;
        final cropId = map['crop_id'] is num
            ? (map['crop_id'] as num).toInt()
            : null;
        final plantingId = map['planting_id'] is num
            ? (map['planting_id'] as num).toInt()
            : null;
        final imagePath = map['image_path']?.toString().trim() ?? '';
        if (plotId == null || cropId == null || imagePath.isEmpty) {
          continue;
        }
        if (!await File(imagePath).exists()) {
          continue;
        }

        final capturedAt =
            DateTime.tryParse(map['captured_at']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc();
        final queueIdRaw = map['queue_id']?.toString().trim();
        final queueId = (queueIdRaw == null || queueIdRaw.isEmpty)
            ? _nextPendingQueueId()
            : queueIdRaw;
        final attempts = map['attempts'] is num
            ? (map['attempts'] as num).toInt()
            : int.tryParse(map['attempts']?.toString() ?? '') ?? 0;
        final nextRetryAt =
            DateTime.tryParse(
              map['next_retry_at']?.toString() ?? '',
            )?.toUtc() ??
            DateTime.now().toUtc();

        Map<String, dynamic>? scanMetadata;
        final rawMetadata = map['scan_metadata'];
        if (rawMetadata is Map) {
          scanMetadata = rawMetadata.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }

        await store.enqueue(
          PendingScanQueueEntry(
            queueId: queueId,
            plotId: plotId,
            cropId: cropId,
            plantingId: plantingId,
            imagePath: imagePath,
            capturedAtUtc: capturedAt,
            attempts: attempts,
            nextRetryAtUtc: nextRetryAt,
            createdAtUtc: capturedAt,
            scanMetadata: scanMetadata,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    await prefs.remove(_legacyPendingScanQueueKey);
    await _prunePendingQueue();
  }

  Future<void> _prunePendingQueue() async {
    final store = PendingScanQueueStore.instance;
    final all = await store.listAll();
    final survivors = <PendingScanQueueEntry>[];
    for (final entry in all) {
      final imageMissing =
          entry.imagePath.isEmpty || !await File(entry.imagePath).exists();
      final expired = _isQueuedEntryExpired(entry.capturedAtUtc);
      if (imageMissing || expired) {
        await store.deleteByQueueId(entry.queueId);
        if (entry.imagePath.isNotEmpty) {
          await _deleteManagedQueuedImage(entry.imagePath);
        }
        continue;
      }
      survivors.add(entry);
    }

    if (survivors.length <= _maxPendingQueueItems) {
      return;
    }

    final overflow = survivors.length - _maxPendingQueueItems;
    for (var i = 0; i < overflow; i++) {
      final entry = survivors[i];
      await store.deleteByQueueId(entry.queueId);
      if (entry.imagePath.isNotEmpty) {
        await _deleteManagedQueuedImage(entry.imagePath);
      }
    }
  }

  Future<({String queueId, String imagePath})> _enqueuePendingScan({
    required int plotId,
    required int cropId,
    int? plantingId,
    required String imagePath,
    required DateTime capturedAt,
    Map<String, dynamic>? scanMetadata,
  }) async {
    await _migrateLegacyPendingQueueIfNeeded();
    final queueId = _nextPendingQueueId();
    final queuedPath =
        await _persistImageForOfflineQueue(imagePath) ?? imagePath;
    final nowUtc = DateTime.now().toUtc();
    await PendingScanQueueStore.instance.enqueue(
      PendingScanQueueEntry(
        queueId: queueId,
        plotId: plotId,
        cropId: cropId,
        plantingId: plantingId,
        imagePath: queuedPath,
        capturedAtUtc: capturedAt.toUtc(),
        attempts: 0,
        nextRetryAtUtc: nowUtc,
        createdAtUtc: nowUtc,
        scanMetadata: scanMetadata,
      ),
    );
    await _prunePendingQueue();
    await _refreshQueueStatus();
    return (queueId: queueId, imagePath: queuedPath);
  }

  Future<
    ({
      String userMessage,
      ({
        OfflineInferenceResult inference,
        DiseaseTreatmentGuidance? guidance,
        String message,
      })?
      provisional,
    })
  >
  _queueOfflineScanSubmission({
    required int plotId,
    required int cropId,
    int? plantingId,
    required String imagePath,
    required String languageCode,
    required String captureProtocol,
    required ApiConnectivityState connectivityState,
    String? connectivityDetail,
    String? selectedCropName,
    String? selectedPlotName,
  }) async {
    final offlineProvisional = await _maybeRunOfflineProvisional(
      imagePath,
      selectedCropName: selectedCropName,
    );
    final offlineInferenceService = OfflineInferenceService.instance;
    final offlineInferenceUnavailableReason =
        offlineProvisional == null && offlineInferenceService.isEnabled
        ? offlineInferenceService.unavailableReason
        : null;
    final userFacingUnavailableReason =
        offlineInferenceUnavailableReason == null
        ? null
        : _formatOfflineInferenceUnavailableReason(
            offlineInferenceUnavailableReason,
            selectedCropName: selectedCropName,
          );
    final capturedAt = DateTime.now();
    final scanMetadata =
        _metadataWithOfflineProvisional(
          baseMetadata: _currentScanMetadata(
            captureShots: _structuredCaptureRequiredShots,
            captureProtocol: captureProtocol,
          ),
          provisional: offlineProvisional,
          selectedCropName: selectedCropName,
          selectedPlotName: selectedPlotName,
        )..addAll(<String, dynamic>{
          if (offlineInferenceUnavailableReason != null &&
              offlineInferenceUnavailableReason.trim().isNotEmpty)
            'offline_local_inference_unavailable':
                offlineInferenceUnavailableReason.trim(),
        });
    final queuedScan = await _enqueuePendingScan(
      plotId: plotId,
      cropId: cropId,
      plantingId: plantingId,
      imagePath: imagePath,
      capturedAt: capturedAt,
      scanMetadata: scanMetadata,
    );
    await _saveSyncedLocalHistory(
      submissionId: queuedScan.queueId,
      plotId: plotId,
      cropId: cropId,
      plantingId: plantingId,
      imagePath: queuedScan.imagePath,
      capturedAtUtc: capturedAt.toUtc(),
      metadata: scanMetadata,
    );
    final queueMessage = _scanQueuedMessageByConnectivity(
      languageCode,
      connectivityState,
      detail: connectivityDetail,
    );
    final offlineInferenceMessage = offlineProvisional?.message;
    final userMessage = switch ((
      offlineInferenceMessage,
      offlineInferenceUnavailableReason,
    )) {
      (String offlineMessage, _) => '$offlineMessage\n$queueMessage',
      (_, String _) =>
        '$queueMessage\n${userFacingUnavailableReason ?? 'Offline model could not produce a trustworthy result.'}',
      _ => queueMessage,
    };
    if (offlineProvisional != null) {
      _showOfflineSavedFeedback(
        languageCode,
        diseaseName: offlineProvisional.inference.displayDiseaseName,
      );
    }
    return (userMessage: userMessage, provisional: offlineProvisional);
  }

  Future<void> _drainPendingScanQueue() async {
    if (_drainingQueue) return;
    _drainingQueue = true;
    try {
      await _migrateLegacyPendingQueueIfNeeded();
      final store = PendingScanQueueStore.instance;
      await _prunePendingQueue();
      final ready = await store.listReady(
        nowUtc: DateTime.now().toUtc(),
        limit: _maxPendingQueueItems,
      );
      if (ready.isEmpty) return;
      for (final entry in ready) {
        final imageMissing =
            entry.imagePath.isEmpty || !await File(entry.imagePath).exists();
        final expired = _isQueuedEntryExpired(entry.capturedAtUtc);
        if (imageMissing || expired) {
          await store.deleteByQueueId(entry.queueId);
          if (entry.imagePath.isNotEmpty) {
            await _deleteManagedQueuedImage(entry.imagePath);
          }
          continue;
        }
        try {
          final createdReport = await ApiClient.createDiseaseReport(
            plotId: entry.plotId,
            cropId: entry.cropId,
            plantingId: entry.plantingId,
            imagePath: entry.imagePath,
            capturedAt: entry.capturedAtUtc,
            submissionId: entry.queueId,
            growthStage: _metadataString(entry.scanMetadata, 'growth_stage'),
            symptomDays: _metadataInt(entry.scanMetadata, 'symptom_days'),
            recentRain: _metadataBool(entry.scanMetadata, 'recent_rain'),
            fieldNotes: _metadataString(entry.scanMetadata, 'field_notes'),
            captureShots:
                _metadataInt(entry.scanMetadata, 'capture_shots') ??
                _structuredCaptureRequiredShots,
            captureProtocol:
                _metadataString(entry.scanMetadata, 'capture_protocol') ??
                'guided_multi_leaf_offline',
            provisionalDiseaseName: _metadataString(
              entry.scanMetadata,
              'offline_local_disease_name',
            ),
            provisionalCanonicalDiseaseName: _metadataString(
              entry.scanMetadata,
              'offline_local_disease_key',
            ),
            provisionalSeverity: _metadataString(
              entry.scanMetadata,
              'offline_local_severity',
            ),
            provisionalConfidence: _metadataDouble(
              entry.scanMetadata,
              'offline_local_confidence',
            ),
            provisionalInferenceMessage: _metadataString(
              entry.scanMetadata,
              'offline_local_inference',
            ),
            provisionalInferenceUnavailable: _metadataString(
              entry.scanMetadata,
              'offline_local_inference_unavailable',
            ),
          );
          final submissionId =
              createdReport.clientSubmissionId?.trim().isNotEmpty == true
              ? createdReport.clientSubmissionId!.trim()
              : entry.queueId;
          await _saveSyncedLocalHistory(
            submissionId: submissionId,
            plotId: entry.plotId,
            cropId: entry.cropId,
            plantingId: entry.plantingId,
            imagePath: entry.imagePath,
            capturedAtUtc: entry.capturedAtUtc,
            metadata: entry.scanMetadata,
          );
          await store.deleteByQueueId(entry.queueId);
        } on ApiUnauthorized {
          // Keep queued scans untouched when session expires; retry after login.
          break;
        } catch (_) {
          final nextAttempts = entry.attempts + 1;
          if (nextAttempts >= _maxPendingRetryAttempts) {
            await store.updateRetry(
              queueId: entry.queueId,
              attempts: nextAttempts,
              nextRetryAtUtc: DateTime.now().toUtc().add(_maxPendingRetryDelay),
            );
            continue;
          }
          await store.updateRetry(
            queueId: entry.queueId,
            attempts: nextAttempts,
            nextRetryAtUtc: _nextRetryAt(nextAttempts),
          );
        }
      }
    } finally {
      _drainingQueue = false;
      unawaited(_refreshQueueStatus());
    }
  }

  Future<_QualityDecision?> _showQualityGateDialog(_QualityAssessment quality) {
    final lang = LanguageStore.notifier.value;
    return showDialog<_QualityDecision>(
      context: context,
      builder: (dialogContext) {
        const allowUseAnyway = true;
        return AlertDialog(
          title: Text(L.t(lang, 'scan_quality_retake_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L.t(lang, 'scan_quality_insufficient')),
              const SizedBox(height: 10),
              ...quality.reasons.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('- $reason'),
                ),
              ),
              const SizedBox(height: 8),
              Text(L.t(lang, 'scan_quality_checklist')),
              const SizedBox(height: 6),
              Text('- ${L.t(lang, 'scan_quality_step_hold_steady')}'),
              Text('- ${L.t(lang, 'scan_quality_step_fill_guide')}'),
              Text('- ${L.t(lang, 'scan_quality_step_avoid_glare')}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_QualityDecision.cancel),
              child: Text(L.t(lang, 'cancel')),
            ),
            if (allowUseAnyway)
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_QualityDecision.useAnyway),
                child: Text(L.t(lang, 'scan_use_anyway')),
              ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_QualityDecision.retake),
              child: Text(L.t(lang, 'retake')),
            ),
          ],
        );
      },
    );
  }

  void _handleScan(XFile file, ScanMode mode) {
    if (widget.initialMode == null && _selectedCropContext != null) {
      _submitSelectedCropContext(file, _selectedCropContext!);
      return;
    }
    _setScanUiState(_ScanUiState.collectingContext);
    _showDiseaseReportDialog(file, originMode: mode);
  }

  Future<void> _submitSelectedCropContext(
    XFile file,
    _ScanCropContext contextSelection,
  ) async {
    if (_submitting) {
      return;
    }
    final lang = LanguageStore.notifier.value;
    final selectedFamily = cropFamilyFromName(contextSelection.cropName);
    if (selectedFamily == null ||
        !kSupportedCropFamilies.contains(selectedFamily)) {
      _setScanUiState(_ScanUiState.error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t(lang, 'my_farm_error_crop_out_of_scope'))),
      );
      _setScanUiState(_ScanUiState.idle);
      return;
    }

    _setScanUiState(_ScanUiState.uploading);
    setState(() {
      _submitting = true;
    });
    if (contextSelection.quickTestOnly) {
      await _runOfflineQuickTest(file, contextSelection, lang);
      return;
    }
    final connectivityStatus = await _effectiveConnectivityStatusForSubmit();
    if (_shouldUseOfflineQueueFirst(connectivityStatus)) {
      final queued = await _queueOfflineScanSubmission(
        plotId: contextSelection.plotId,
        cropId: contextSelection.cropId,
        plantingId: contextSelection.plantingId,
        imagePath: file.path,
        languageCode: lang,
        captureProtocol: 'guided_multi_leaf_offline',
        connectivityState: connectivityStatus.state,
        connectivityDetail: connectivityStatus.message,
        selectedCropName: contextSelection.cropName,
        selectedPlotName: contextSelection.plotName,
      );
      _drainQueuedScanNowIfAllowed(connectivityStatus);
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
      if (queued.provisional != null) {
        unawaited(
          _showOfflineProvisionalSheet(
            languageCode: lang,
            inference: queued.provisional!.inference,
            guidance: queued.provisional!.guidance,
          ),
        );
      }
      _showQueuedScanFeedback(lang, queued.userMessage);
      _setScanUiState(_ScanUiState.idle);
      return;
    }
    try {
      final offlineProvisional = await _maybeRunOfflineProvisional(
        file.path,
        selectedCropName: contextSelection.cropName,
      );
      final submissionId = _nextPendingQueueId();
      final onlineMetadata = _metadataWithOfflineProvisional(
        baseMetadata: _currentScanMetadata(
          captureShots: _structuredCaptureRequiredShots,
          captureProtocol: 'guided_multi_leaf',
        ),
        provisional: offlineProvisional,
        selectedCropName: contextSelection.cropName,
        selectedPlotName: contextSelection.plotName,
      );
      final createdReport = await ApiClient.createDiseaseReport(
        plotId: contextSelection.plotId,
        cropId: contextSelection.cropId,
        plantingId: contextSelection.plantingId,
        imagePath: file.path,
        capturedAt: DateTime.now(),
        submissionId: submissionId,
        growthStage: _metadataString(onlineMetadata, 'growth_stage'),
        symptomDays: _metadataInt(onlineMetadata, 'symptom_days'),
        recentRain: _metadataBool(onlineMetadata, 'recent_rain'),
        fieldNotes: _metadataString(onlineMetadata, 'field_notes'),
        captureShots:
            _metadataInt(onlineMetadata, 'capture_shots') ??
            _structuredCaptureRequiredShots,
        captureProtocol:
            _metadataString(onlineMetadata, 'capture_protocol') ??
            'guided_multi_leaf',
        provisionalDiseaseName: _metadataString(
          onlineMetadata,
          'offline_local_disease_name',
        ),
        provisionalCanonicalDiseaseName: _metadataString(
          onlineMetadata,
          'offline_local_disease_key',
        ),
        provisionalSeverity: _metadataString(
          onlineMetadata,
          'offline_local_severity',
        ),
        provisionalConfidence: _metadataDouble(
          onlineMetadata,
          'offline_local_confidence',
        ),
        provisionalInferenceMessage: _metadataString(
          onlineMetadata,
          'offline_local_inference',
        ),
      );
      var finalReport = createdReport;
      if (!_isDiseaseReportFinal(createdReport) &&
          _shouldPollDiseaseReport(createdReport)) {
        _setScanUiState(_ScanUiState.analyzing);
        finalReport = await _pollDiseaseReportUntilReady(createdReport);
      }
      if (!finalReport.finding.isInferred && !finalReport.finding.isVerified) {
        await _saveSyncedLocalHistory(
          submissionId: finalReport.clientSubmissionId ?? submissionId,
          plotId: contextSelection.plotId,
          cropId: contextSelection.cropId,
          plantingId: contextSelection.plantingId,
          imagePath: file.path,
          capturedAtUtc: DateTime.now().toUtc(),
          metadata: onlineMetadata,
        );
      } else {
        await _clearSyncedLocalHistory(
          finalReport.clientSubmissionId ?? submissionId,
        );
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
      await _showInferenceFailureFeedback(
        finalReport,
        selectedCropName: contextSelection.cropName,
      );
      if (!mounted) return;
      if (finalReport.inferenceFailure?.isNotAPlant ?? false) {
        _setScanUiState(_ScanUiState.idle);
        return;
      }
      if (_hasCropFamilyMismatch(
            selectedCropName: contextSelection.cropName,
            predictedDiseaseName: finalReport.diseaseName,
          ) &&
          !(finalReport.inferenceFailure?.isCropMismatch ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t(lang, 'scan_prediction_mismatch_review'))),
        );
      }
      notifyDiseaseReportUpdated();
      unawaited(_drainPendingScanQueue());
      await _showDiseaseResultSheet(
        finalReport,
        selectedCropName: contextSelection.cropName,
      );
      await _ensurePreviewContinues();
    } on ApiUnauthorized {
      _setScanUiState(_ScanUiState.error);
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
      _redirectToLogin();
    } on ApiException catch (e) {
      _setScanUiState(_ScanUiState.error);
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
      if (!mounted) return;
      var msg = e.message;
      if (_looksLikeSslConfigurationIssue(e.message)) {
        msg = _localSslHintMessage(e.message);
      } else if (_shouldQueueRetry(e)) {
        final connectivityState = ApiClient.classifyConnectivityMessage(
          e.message,
        );
        final queued = await _queueOfflineScanSubmission(
          plotId: contextSelection.plotId,
          cropId: contextSelection.cropId,
          plantingId: contextSelection.plantingId,
          imagePath: file.path,
          languageCode: lang,
          captureProtocol: 'guided_multi_leaf_offline',
          connectivityState: connectivityState,
          connectivityDetail: e.message,
          selectedCropName: contextSelection.cropName,
          selectedPlotName: contextSelection.plotName,
        );
        if (!mounted) return;
        if (queued.provisional != null) {
          unawaited(
            _showOfflineProvisionalSheet(
              languageCode: lang,
              inference: queued.provisional!.inference,
              guidance: queued.provisional!.guidance,
            ),
          );
        }
        msg = queued.userMessage;
      }
      _showQueuedScanFeedback(lang, msg);
      _setScanUiState(_ScanUiState.idle);
    } catch (_) {
      _setScanUiState(_ScanUiState.error);
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L.t(lang, 'scan_submit_failed'))));
      _setScanUiState(_ScanUiState.idle);
    }
  }

  Future<void> _runOfflineQuickTest(
    XFile file,
    _ScanCropContext contextSelection,
    String languageCode,
  ) async {
    try {
      final provisional = await _maybeRunOfflineProvisional(
        file.path,
        selectedCropName: contextSelection.cropName,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
      if (provisional != null) {
        final capturedAt = DateTime.now();
        final metadata = _metadataWithOfflineProvisional(
          baseMetadata: _currentScanMetadata(
            captureShots: _structuredCaptureRequiredShots,
            captureProtocol: 'guided_multi_leaf_quick_test',
          ),
          provisional: provisional,
          selectedCropName: contextSelection.cropName,
          selectedPlotName: contextSelection.plotName,
        );
        await _saveSyncedLocalHistory(
          submissionId: _nextPendingQueueId(),
          plotId: contextSelection.plotId,
          cropId: contextSelection.cropId,
          plantingId: contextSelection.plantingId,
          imagePath: file.path,
          capturedAtUtc: capturedAt.toUtc(),
          metadata: metadata,
        );
        notifyDiseaseReportUpdated();
        _showOfflineQuickTestFeedback(
          languageCode: languageCode,
          cropName: contextSelection.cropName,
          diseaseName: provisional.inference.displayDiseaseName,
        );
        await _showOfflineProvisionalSheet(
          languageCode: languageCode,
          inference: provisional.inference,
          guidance: provisional.guidance,
        );
      } else {
        final unavailableReason =
            OfflineInferenceService.instance.unavailableReason;
        final message = unavailableReason == null
            ? L.t(languageCode, 'scan_offline_test_unavailable')
            : _formatOfflineInferenceUnavailableReason(
                unavailableReason,
                selectedCropName: contextSelection.cropName,
              );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      _setScanUiState(_ScanUiState.idle);
    }
  }

  Future<void> _loadCropContextsForDirectScan() async {
    if (widget.initialMode != null || _loadingCropContexts) {
      return;
    }
    setState(() {
      _loadingCropContexts = true;
      _cropContextError = null;
    });
    try {
      await _loadCropContextsCore().timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() {
        _loadingCropContexts = false;
      });
    } on TimeoutException {
      final restoredFromCache = await _restoreCropContextsFromCache();
      if (!mounted) return;
      setState(() {
        _loadingCropContexts = false;
        _cropContextError = restoredFromCache
            ? L.t(
                LanguageStore.notifier.value,
                'scan_offline_using_saved_crop_list',
              )
            : _cropLoadErrorByConnectivity(
                ApiConnectivityState.internetOnly,
                detail:
                    ConnectivityStatusService.instance.notifier.value.message,
              );
      });
    } on ApiUnauthorized {
      if (!mounted) return;
      setState(() {
        _loadingCropContexts = false;
      });
      _redirectToLogin();
    } on ApiException catch (e) {
      final restoredFromCache = await _restoreCropContextsFromCache();
      final state = ApiClient.classifyConnectivityMessage(e.message);
      if (!mounted) return;
      setState(() {
        _loadingCropContexts = false;
        _cropContextError = restoredFromCache
            ? L.t(
                LanguageStore.notifier.value,
                'scan_offline_using_saved_crop_list',
              )
            : _cropLoadErrorByConnectivity(state, detail: e.message);
      });
    } catch (_) {
      final restoredFromCache = await _restoreCropContextsFromCache();
      if (!mounted) return;
      setState(() {
        _loadingCropContexts = false;
        _cropContextError = restoredFromCache
            ? L.t(
                LanguageStore.notifier.value,
                'scan_offline_using_saved_crop_list',
              )
            : _cropLoadErrorByConnectivity(ApiConnectivityState.apiOnline);
      });
    }
  }

  Future<void> _loadCropContextsCore() async {
    try {
      final crops = await _loadCropOptions();
      final cropNameById = <int, String>{
        for (final crop in crops)
          (crop['id']
              as int): (crop['name']?.toString().trim().isNotEmpty == true
              ? crop['name']!.toString().trim()
              : AppCopy.cropFallback('en', crop['id'])),
      };
      final currentLang = LanguageStore.notifier.value;

      final farms = await _loadFarmOptions();
      final entriesByKey = <String, _ScanCropContext>{};
      final perFarmContexts =
          await _mapWithConcurrency<
            Map<String, dynamic>,
            List<_ScanCropContext>
          >(farms, _cropContextFarmConcurrency, (farm) async {
            final farmId = (farm['id'] as num).toInt();
            final farmName = farm['name']?.toString().trim().isNotEmpty == true
                ? farm['name']!.toString().trim()
                : AppCopy.farmFallback(currentLang, farmId);
            final plots = await _loadPlotOptions(farmId);
            if (plots.isEmpty) return const <_ScanCropContext>[];

            final perPlotContexts =
                await _mapWithConcurrency<
                  Map<String, dynamic>,
                  List<_ScanCropContext>
                >(plots, _cropContextPlotConcurrency, (plot) async {
                  final plotId = (plot['id'] as num).toInt();
                  final plotName =
                      plot['name']?.toString().trim().isNotEmpty == true
                      ? plot['name']!.toString().trim()
                      : AppCopy.plotFallback(currentLang, plotId);
                  final plantings = await _loadPlantingsForPlot(plotId);
                  if (plantings.isEmpty) return const <_ScanCropContext>[];
                  final contexts = <_ScanCropContext>[];
                  for (final planting in plantings) {
                    final cropId = planting.cropId;
                    final cropName = cropNameById[cropId];
                    if (cropName == null) continue;
                    contexts.add(
                      _ScanCropContext(
                        farmId: farmId,
                        farmName: farmName,
                        plotId: plotId,
                        plotName: plotName,
                        cropId: cropId,
                        cropName: cropName,
                        plantingId: planting.id,
                      ),
                    );
                  }
                  return contexts;
                });

            final farmContexts = <_ScanCropContext>[];
            for (final chunk in perPlotContexts) {
              farmContexts.addAll(chunk);
            }
            return farmContexts;
          });

      for (final farmChunk in perFarmContexts) {
        for (final contextEntry in farmChunk) {
          final key =
              '${contextEntry.farmId}-${contextEntry.plotId}-${contextEntry.cropId}';
          entriesByKey[key] = contextEntry;
        }
      }

      final contexts = entriesByKey.values.toList(growable: true)
        ..addAll(_buildQuickTestCropContexts(crops, entriesByKey.values))
        ..sort((a, b) {
          if (a.quickTestOnly != b.quickTestOnly) {
            return a.quickTestOnly ? 1 : -1;
          }
          return a.cropName.compareTo(b.cropName);
        });
      if (!mounted) return;
      setState(() {
        _cropContexts = contexts;
        _selectedCropContext = null;
      });
      unawaited(_cacheCropContexts(contexts));
      unawaited(_restoreSelectedCropContextFromCache());
    } on ApiUnauthorized {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  List<_ScanCropContext> _buildQuickTestCropContexts(
    List<Map<String, dynamic>> crops,
    Iterable<_ScanCropContext> existing,
  ) {
    final representedFamilies = existing
        .map((item) => cropFamilyFromName(item.cropName) ?? item.family)
        .toSet();
    final supportedFamilies =
        OfflineModelRegistry.instance.supportedCropFamilies
            .map((family) => cropFamilyFromName(family) ?? family)
            .toSet()
            .toList()
          ..sort();
    final representativeCropByFamily = <String, Map<String, dynamic>>{};
    for (final crop in crops) {
      final cropName = crop['name']?.toString().trim() ?? '';
      final family = cropFamilyFromName(cropName);
      if (family == null || representativeCropByFamily.containsKey(family)) {
        continue;
      }
      representativeCropByFamily[family] = crop;
    }

    final quickTestContexts = <_ScanCropContext>[];
    for (final family in supportedFamilies) {
      if (representedFamilies.contains(family)) continue;
      final crop = representativeCropByFamily[family];
      if (crop == null) continue;
      final cropIdRaw = crop['id'];
      final cropId = cropIdRaw is num
          ? cropIdRaw.toInt()
          : int.tryParse(cropIdRaw?.toString() ?? '');
      if (cropId == null) continue;
      quickTestContexts.add(
        _ScanCropContext(
          farmId: 0,
          farmName: L.t(
            LanguageStore.notifier.value,
            'scan_offline_test_context',
          ),
          plotId: -cropId,
          plotName: L.t(
            LanguageStore.notifier.value,
            'scan_offline_test_no_plot',
          ),
          cropId: cropId,
          cropName: crop['name']?.toString() ?? family,
          plantingId: null,
          quickTestOnly: true,
        ),
      );
    }
    return quickTestContexts;
  }

  Map<String, dynamic> _serializeCropContext(_ScanCropContext value) {
    return <String, dynamic>{
      'farm_id': value.farmId,
      'farm_name': value.farmName,
      'plot_id': value.plotId,
      'plot_name': value.plotName,
      'crop_id': value.cropId,
      'crop_name': value.cropName,
      'planting_id': value.plantingId,
      'quick_test_only': value.quickTestOnly,
    };
  }

  _ScanCropContext? _deserializeCropContext(Map<String, dynamic> value) {
    final farmIdRaw = value['farm_id'];
    final plotIdRaw = value['plot_id'];
    final cropIdRaw = value['crop_id'];
    final farmId = farmIdRaw is num
        ? farmIdRaw.toInt()
        : int.tryParse(farmIdRaw?.toString() ?? '');
    final plotId = plotIdRaw is num
        ? plotIdRaw.toInt()
        : int.tryParse(plotIdRaw?.toString() ?? '');
    final cropId = cropIdRaw is num
        ? cropIdRaw.toInt()
        : int.tryParse(cropIdRaw?.toString() ?? '');
    if (farmId == null || plotId == null || cropId == null) {
      return null;
    }
    final plantingIdRaw = value['planting_id'];
    final plantingId = plantingIdRaw is num
        ? plantingIdRaw.toInt()
        : int.tryParse(plantingIdRaw?.toString() ?? '');
    final lang = LanguageStore.notifier.value;
    return _ScanCropContext(
      farmId: farmId,
      farmName: value['farm_name']?.toString().trim().isNotEmpty == true
          ? value['farm_name']!.toString().trim()
          : AppCopy.farmFallback(lang, farmId),
      plotId: plotId,
      plotName: value['plot_name']?.toString().trim().isNotEmpty == true
          ? value['plot_name']!.toString().trim()
          : AppCopy.plotFallback(lang, plotId),
      cropId: cropId,
      cropName: value['crop_name']?.toString().trim().isNotEmpty == true
          ? value['crop_name']!.toString().trim()
          : AppCopy.cropFallback('en', cropId),
      plantingId: plantingId,
      quickTestOnly: value['quick_test_only'] == true,
    );
  }

  Future<void> _cacheCropContexts(List<_ScanCropContext> contexts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = contexts
          .map(_serializeCropContext)
          .toList(growable: false);
      await prefs.setString(_offlineCropContextsCacheKey, jsonEncode(payload));
    } catch (_) {
      // Ignore offline cache failures.
    }
  }

  Future<void> _cacheSelectedCropContext(_ScanCropContext selected) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _offlineSelectedContextCacheKey,
        jsonEncode(_serializeCropContext(selected)),
      );
    } catch (_) {
      // Ignore offline cache failures.
    }
  }

  Future<bool> _restoreCropContextsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_offlineCropContextsCacheKey)?.trim() ?? '';
      if (raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return false;
      final restored = decoded
          .whereType<Map>()
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .map(_deserializeCropContext)
          .whereType<_ScanCropContext>()
          .toList();
      if (restored.isEmpty) return false;
      if (!mounted) return true;
      setState(() {
        _cropContexts = restored;
      });
      await _restoreSelectedCropContextFromCache();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _restoreSelectedCropContextFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString(_offlineSelectedContextCacheKey)?.trim() ?? '';
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final parsed = _deserializeCropContext(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (parsed == null || !mounted) return;
      final matched = _cropContexts.where((item) {
        return item.farmId == parsed.farmId &&
            item.plotId == parsed.plotId &&
            item.cropId == parsed.cropId;
      }).toList();
      if (matched.isEmpty) return;
      setState(() {
        _selectedCropContext = matched.first;
      });
    } catch (_) {
      // Ignore cache restore failures.
    }
  }

  Future<List<R>> _mapWithConcurrency<T, R>(
    List<T> items,
    int concurrency,
    Future<R> Function(T item) task,
  ) async {
    if (items.isEmpty) return <R>[];
    final safeConcurrency = math.max(1, math.min(concurrency, items.length));
    final results = List<R?>.filled(items.length, null);
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (cursor >= items.length) break;
        final current = cursor;
        cursor += 1;
        results[current] = await task(items[current]);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(safeConcurrency, (_) => worker()),
    );

    return results.map((e) => e as R).toList();
  }

  Future<List<Map<String, dynamic>>> _loadFarmOptions() async {
    final farms = await OfflineRepository.instance.listFarms();
    return farms
        .where((f) => f.serverId != null && !f.deleted)
        .map((f) => <String, dynamic>{'id': f.serverId, 'name': f.farmName})
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadPlotOptions(int farmId) async {
    final plots = await OfflineRepository.instance.listPlotsByFarmServerId(
      farmId,
    );
    return plots
        .where((p) => p.serverId != null && !p.deleted)
        .map((p) => <String, dynamic>{'id': p.serverId, 'name': p.plotName})
        .toList();
  }

  Future<List<PlantingModel>> _loadPlantingsForPlot(int plotId) async {
    final plantings = await OfflineRepository.instance
        .listPlantingsByPlotServerId(plotId);
    return plantings
        .where((p) => p.serverId != null && !p.deleted)
        .map((p) => p.toPlantingModel(useServerId: true))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadCropOptions() async {
    final cached = await LocalCacheStore.instance.readList(
      _cropReferenceCacheKey,
    );
    final cachedItems = (cached ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
    final mergedItems =
        ReferenceData.mergeByIdThenName(cachedItems, ReferenceData.crops)
            .where(
              (item) =>
                  item['id'] != null &&
                  isSupportedCropName(item['name']?.toString()),
            )
            .map(
              (item) => <String, dynamic>{
                'id': item['id'] is num
                    ? (item['id'] as num).toInt()
                    : int.tryParse(item['id'].toString()),
                'name': item['name']?.toString().trim().isNotEmpty == true
                    ? LocalizedValue.crop(
                        LanguageStore.notifier.value,
                        item['name']!.toString().trim(),
                      )
                    : AppCopy.cropFallback(
                        LanguageStore.notifier.value,
                        item['id'],
                      ),
              },
            )
            .where((item) => item['id'] != null)
            .toList(growable: false);
    if (mergedItems.isNotEmpty) {
      return mergedItems
          .map((e) => {'id': e['id'] as int, 'name': e['name'] as String})
          .toList();
    }
    return _supportedCrops
        .asMap()
        .entries
        .map(
          (entry) => <String, dynamic>{
            'id': -(entry.key + 1),
            'name': entry.value.cropName,
          },
        )
        .toList(growable: false);
  }

  Future<Set<int>> _loadFarmRegisteredCropIds(int farmId) async {
    final plots = await OfflineRepository.instance.listPlotsByFarmServerId(
      farmId,
    );
    final cropIds = <int>{};
    for (final plot in plots) {
      if (plot.serverId == null) continue;
      final plantings = await OfflineRepository.instance
          .listPlantingsByPlotServerId(plot.serverId!);
      cropIds.addAll(plantings.map((p) => p.cropId));
    }
    return cropIds;
  }

  Future<Map<String, dynamic>?> _showSearchPicker({
    required String title,
    required List<Map<String, dynamic>> items,
  }) async {
    final searchController = TextEditingController();
    var filtered = List<Map<String, dynamic>>.from(items);

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setState) {
                void applyFilter(String value) {
                  final q = value.trim().toLowerCase();
                  setState(() {
                    if (q.isEmpty) {
                      filtered = List<Map<String, dynamic>>.from(items);
                    } else {
                      filtered = items
                          .where(
                            (item) =>
                                (item['name']
                                    ?.toString()
                                    .toLowerCase()
                                    .contains(q) ??
                                false),
                          )
                          .toList();
                    }
                  });
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          labelText: L.t(
                            LanguageStore.notifier.value,
                            'search',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: applyFilter,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ListTile(
                            title: Text(
                              item['name']?.toString().trim().isNotEmpty == true
                                  ? item['name']!.toString()
                                  : AppCopy.itemFallback(
                                      LanguageStore.notifier.value,
                                    ),
                            ),
                            onTap: () => Navigator.of(sheetContext).pop(item),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDiseaseReportDialog(
    XFile file, {
    required ScanMode originMode,
  }) async {
    final lang = LanguageStore.notifier.value;
    final titleKey = originMode == ScanMode.cropHealth
        ? 'crop_health'
        : 'disease_check';
    final plotController = TextEditingController();
    final cropController = TextEditingController();
    final plantingController = TextEditingController();
    int? selectedFarmId;
    int? selectedPlotId;
    int? selectedCropId;
    Set<int> farmRegisteredCropIds = <int>{};
    bool loadingPlots = false;
    bool loadingFarmCrops = false;
    String? formError;

    final farmOptions = <Map<String, dynamic>>[];
    final cropOptions = <Map<String, dynamic>>[];
    final scopedCropOptions = <Map<String, dynamic>>[];
    final plotOptions = <Map<String, dynamic>>[];
    String? optionsError;

    try {
      _setScanUiState(_ScanUiState.collectingContext);
      final loaded = await Future.wait<List<Map<String, dynamic>>>([
        _loadFarmOptions(),
        _loadCropOptions(),
      ]);
      farmOptions.addAll(loaded[0]);
      cropOptions.addAll(loaded[1]);
    } on ApiUnauthorized {
      if (!mounted) return;
      _setScanUiState(_ScanUiState.error);
      _redirectToLogin();
      return;
    } catch (_) {
      optionsError =
          'Unable to load farm/crop lists. You can still enter IDs manually.';
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !_submitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(L.t(lang, titleKey)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (optionsError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            optionsError,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    if (farmOptions.isNotEmpty)
                      InkWell(
                        onTap: _submitting
                            ? null
                            : () async {
                                final picked = await _showSearchPicker(
                                  title: L.t(lang, 'scan_select_farm'),
                                  items: farmOptions,
                                );
                                if (picked == null) return;
                                if (!dialogContext.mounted) return;
                                setDialogState(() {
                                  selectedFarmId = picked['id'] as int;
                                  selectedPlotId = null;
                                  selectedCropId = null;
                                  farmRegisteredCropIds = <int>{};
                                  plotController.clear();
                                  cropController.clear();
                                  plotOptions.clear();
                                  scopedCropOptions.clear();
                                  loadingPlots = true;
                                  loadingFarmCrops = true;
                                });
                                try {
                                  final loadedFutures =
                                      await Future.wait<dynamic>([
                                        _loadPlotOptions(selectedFarmId!),
                                        _loadFarmRegisteredCropIds(
                                          selectedFarmId!,
                                        ),
                                      ]);
                                  final loaded =
                                      loadedFutures[0]
                                          as List<Map<String, dynamic>>;
                                  final registeredIds =
                                      loadedFutures[1] as Set<int>;
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() {
                                    farmRegisteredCropIds = registeredIds;
                                    plotOptions
                                      ..clear()
                                      ..addAll(loaded);
                                    scopedCropOptions
                                      ..clear()
                                      ..addAll(
                                        cropOptions.where(
                                          (c) => farmRegisteredCropIds.contains(
                                            c['id'] as int,
                                          ),
                                        ),
                                      );
                                    loadingPlots = false;
                                    loadingFarmCrops = false;
                                    if (scopedCropOptions.isEmpty) {
                                      formError = L.t(
                                        lang,
                                        'scan_no_registered_scope_crops',
                                      );
                                    } else {
                                      formError = null;
                                    }
                                  });
                                } on ApiUnauthorized {
                                  if (!mounted) return;
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  _redirectToLogin();
                                } catch (_) {
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() {
                                    loadingPlots = false;
                                    loadingFarmCrops = false;
                                    formError = L.t(
                                      lang,
                                      'scan_failed_load_farm_plots',
                                    );
                                  });
                                }
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'farm_id',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            selectedFarmId == null
                                ? L.t(lang, 'scan_select_farm')
                                : farmOptions
                                          .firstWhere(
                                            (f) => f['id'] == selectedFarmId,
                                            orElse: () => const {'name': ''},
                                          )['name']
                                          ?.toString() ??
                                      L.t(lang, 'scan_select_farm'),
                          ),
                        ),
                      ),
                    if (farmOptions.isNotEmpty) const SizedBox(height: 12),
                    if (plotOptions.isNotEmpty ||
                        loadingPlots ||
                        selectedFarmId != null)
                      InkWell(
                        onTap:
                            (_submitting || loadingPlots || plotOptions.isEmpty)
                            ? null
                            : () async {
                                final picked = await _showSearchPicker(
                                  title: L.t(lang, 'scan_select_plot'),
                                  items: plotOptions,
                                );
                                if (picked == null) return;
                                setDialogState(() {
                                  selectedPlotId = picked['id'] as int;
                                  plotController.text = '$selectedPlotId';
                                });
                              },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'plot_id',
                            border: const OutlineInputBorder(),
                            helperText: loadingPlots
                                ? L.t(lang, 'scan_loading_plots')
                                : null,
                          ),
                          child: Text(
                            selectedPlotId == null
                                ? (loadingPlots
                                      ? L.t(lang, 'scan_loading_plots')
                                      : L.t(lang, 'scan_select_plot'))
                                : plotOptions
                                          .firstWhere(
                                            (p) => p['id'] == selectedPlotId,
                                            orElse: () => const {'name': ''},
                                          )['name']
                                          ?.toString() ??
                                      L.t(lang, 'scan_select_plot'),
                          ),
                        ),
                      )
                    else
                      TextField(
                        controller: plotController,
                        keyboardType: TextInputType.number,
                        enabled: !_submitting,
                        decoration: const InputDecoration(
                          labelText: 'plot_id',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (selectedFarmId == null)
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'crop_id',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(L.t(lang, 'scan_select_farm_first')),
                      )
                    else if (loadingFarmCrops)
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'crop_id',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(L.t(lang, 'scan_loading_farm_crops')),
                      )
                    else if (scopedCropOptions.isNotEmpty)
                      InkWell(
                        onTap: _submitting
                            ? null
                            : () async {
                                final picked = await _showSearchPicker(
                                  title: L.t(lang, 'select_crop'),
                                  items: scopedCropOptions,
                                );
                                if (picked == null) return;
                                setDialogState(() {
                                  selectedCropId = picked['id'] as int;
                                  cropController.text = '$selectedCropId';
                                });
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'crop_id',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            selectedCropId == null
                                ? L.t(lang, 'select_crop')
                                : scopedCropOptions
                                          .firstWhere(
                                            (c) => c['id'] == selectedCropId,
                                            orElse: () => const {'name': ''},
                                          )['name']
                                          ?.toString() ??
                                      L.t(lang, 'select_crop'),
                          ),
                        ),
                      )
                    else
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'crop_id',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          L.t(lang, 'scan_no_registered_scope_crops_short'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: plantingController,
                      keyboardType: TextInputType.number,
                      enabled: !_submitting,
                      decoration: const InputDecoration(
                        labelText: 'planting_id (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(L.t(lang, 'cancel')),
                ),
                ElevatedButton(
                  onPressed: _submitting
                      ? null
                      : () async {
                          final plotId = int.tryParse(
                            plotController.text.trim(),
                          );
                          final cropId =
                              selectedCropId ??
                              int.tryParse(cropController.text.trim());
                          final selectedCropName = scopedCropOptions
                              .firstWhere(
                                (c) => c['id'] == cropId,
                                orElse: () => const {'name': ''},
                              )['name']
                              ?.toString();
                          final selectedPlotName = plotOptions
                              .firstWhere(
                                (p) => p['id'] == selectedPlotId,
                                orElse: () => const {'name': ''},
                              )['name']
                              ?.toString();
                          final plantingRaw = plantingController.text.trim();
                          final plantingId = plantingRaw.isEmpty
                              ? null
                              : int.tryParse(plantingRaw);

                          if (selectedFarmId == null) {
                            setDialogState(() {
                              formError = L.t(lang, 'scan_farm_required');
                            });
                            return;
                          }
                          if (plotId == null || selectedPlotId == null) {
                            setDialogState(() {
                              formError = L.t(lang, 'scan_plot_required');
                            });
                            return;
                          }
                          if (cropId == null) {
                            setDialogState(() {
                              formError = L.t(lang, 'scan_crop_required');
                            });
                            return;
                          }
                          if (!farmRegisteredCropIds.contains(cropId)) {
                            setDialogState(() {
                              formError = L.t(
                                lang,
                                'scan_crop_not_registered_in_farm',
                              );
                            });
                            return;
                          }
                          if (plantingRaw.isNotEmpty && plantingId == null) {
                            setDialogState(() {
                              formError = 'planting_id must be numeric.';
                            });
                            return;
                          }

                          setDialogState(() {
                            formError = null;
                          });
                          setState(() {
                            _submitting = true;
                          });
                          _setScanUiState(_ScanUiState.uploading);
                          final connectivityStatus =
                              await _effectiveConnectivityStatusForSubmit();
                          if (_shouldUseOfflineQueueFirst(connectivityStatus)) {
                            final queued = await _queueOfflineScanSubmission(
                              plotId: plotId,
                              cropId: cropId,
                              plantingId: plantingId,
                              imagePath: file.path,
                              languageCode: lang,
                              captureProtocol: 'guided_multi_leaf_offline',
                              connectivityState: connectivityStatus.state,
                              connectivityDetail: connectivityStatus.message,
                              selectedCropName: selectedCropName,
                              selectedPlotName: selectedPlotName,
                            );
                            _drainQueuedScanNowIfAllowed(connectivityStatus);
                            if (mounted) {
                              setState(() {
                                _submitting = false;
                              });
                            }
                            if (queued.provisional != null && mounted) {
                              unawaited(
                                _showOfflineProvisionalSheet(
                                  languageCode: lang,
                                  inference: queued.provisional!.inference,
                                  guidance: queued.provisional!.guidance,
                                ),
                              );
                            }
                            final queueFollowUp =
                                '${queued.userMessage}\n${L.t(lang, 'action_next_scan_queued')}';
                            setDialogState(() {
                              formError = queueFollowUp;
                            });
                            _setScanUiState(_ScanUiState.idle);
                            return;
                          }

                          try {
                            final offlineProvisional =
                                await _maybeRunOfflineProvisional(
                                  file.path,
                                  selectedCropName: selectedCropName,
                                );
                            final submissionId = _nextPendingQueueId();
                            final onlineMetadata =
                                _metadataWithOfflineProvisional(
                                  baseMetadata: _currentScanMetadata(
                                    captureShots:
                                        _structuredCaptureRequiredShots,
                                    captureProtocol: 'guided_multi_leaf',
                                  ),
                                  provisional: offlineProvisional,
                                  selectedCropName: selectedCropName,
                                  selectedPlotName: selectedPlotName,
                                );
                            final createdReport =
                                await ApiClient.createDiseaseReport(
                                  plotId: plotId,
                                  cropId: cropId,
                                  plantingId: plantingId,
                                  imagePath: file.path,
                                  capturedAt: DateTime.now(),
                                  submissionId: submissionId,
                                  growthStage: _metadataString(
                                    onlineMetadata,
                                    'growth_stage',
                                  ),
                                  symptomDays: _metadataInt(
                                    onlineMetadata,
                                    'symptom_days',
                                  ),
                                  recentRain: _metadataBool(
                                    onlineMetadata,
                                    'recent_rain',
                                  ),
                                  fieldNotes: _metadataString(
                                    onlineMetadata,
                                    'field_notes',
                                  ),
                                  captureShots:
                                      _metadataInt(
                                        onlineMetadata,
                                        'capture_shots',
                                      ) ??
                                      _structuredCaptureRequiredShots,
                                  captureProtocol:
                                      _metadataString(
                                        onlineMetadata,
                                        'capture_protocol',
                                      ) ??
                                      'guided_multi_leaf',
                                  provisionalDiseaseName: _metadataString(
                                    onlineMetadata,
                                    'offline_local_disease_name',
                                  ),
                                  provisionalCanonicalDiseaseName:
                                      _metadataString(
                                        onlineMetadata,
                                        'offline_local_disease_key',
                                      ),
                                  provisionalSeverity: _metadataString(
                                    onlineMetadata,
                                    'offline_local_severity',
                                  ),
                                  provisionalConfidence: _metadataDouble(
                                    onlineMetadata,
                                    'offline_local_confidence',
                                  ),
                                  provisionalInferenceMessage: _metadataString(
                                    onlineMetadata,
                                    'offline_local_inference',
                                  ),
                                );
                            var finalReport = createdReport;
                            if (!_isDiseaseReportFinal(createdReport) &&
                                _shouldPollDiseaseReport(createdReport)) {
                              _setScanUiState(_ScanUiState.analyzing);
                              finalReport = await _pollDiseaseReportUntilReady(
                                createdReport,
                              );
                            }
                            if (!finalReport.finding.isInferred &&
                                !finalReport.finding.isVerified) {
                              await _saveSyncedLocalHistory(
                                submissionId:
                                    finalReport.clientSubmissionId ??
                                    submissionId,
                                plotId: plotId,
                                cropId: cropId,
                                plantingId: plantingId,
                                imagePath: file.path,
                                capturedAtUtc: DateTime.now().toUtc(),
                                metadata: onlineMetadata,
                              );
                            } else {
                              await _clearSyncedLocalHistory(
                                finalReport.clientSubmissionId ?? submissionId,
                              );
                            }
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            setState(() {
                              _submitting = false;
                            });
                            await _showInferenceFailureFeedback(
                              finalReport,
                              selectedCropName: selectedCropName,
                            );
                            if (!mounted) return;
                            if (finalReport.inferenceFailure?.isNotAPlant ??
                                false) {
                              _setScanUiState(_ScanUiState.idle);
                              return;
                            }
                            notifyDiseaseReportUpdated();
                            if (originMode == ScanMode.cropHealth) {
                              notifyCropHealthUpdated();
                            }
                            if (!mounted) return;
                            await _showDiseaseResultSheet(
                              finalReport,
                              selectedCropName: selectedCropName,
                              originMode: originMode,
                            );
                            await _ensurePreviewContinues();
                          } on ApiUnauthorized {
                            _setScanUiState(_ScanUiState.error);
                            if (mounted) {
                              setState(() {
                                _submitting = false;
                              });
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            _redirectToLogin();
                          } on ApiException catch (e) {
                            _setScanUiState(_ScanUiState.error);
                            if (mounted) {
                              setState(() {
                                _submitting = false;
                              });
                            }
                            if (_looksLikeSslConfigurationIssue(e.message)) {
                              setDialogState(() {
                                formError = _localSslHintMessage(e.message);
                              });
                            } else if (_shouldQueueRetry(e)) {
                              final connectivityState =
                                  ApiClient.classifyConnectivityMessage(
                                    e.message,
                                  );
                              final queued = await _queueOfflineScanSubmission(
                                plotId: plotId,
                                cropId: cropId,
                                plantingId: plantingId,
                                imagePath: file.path,
                                languageCode: lang,
                                captureProtocol: 'guided_multi_leaf_offline',
                                connectivityState: connectivityState,
                                connectivityDetail: e.message,
                                selectedCropName: selectedCropName,
                              );
                              if (queued.provisional != null && mounted) {
                                unawaited(
                                  _showOfflineProvisionalSheet(
                                    languageCode: lang,
                                    inference: queued.provisional!.inference,
                                    guidance: queued.provisional!.guidance,
                                  ),
                                );
                              }
                              final queueFollowUp =
                                  '${queued.userMessage}\n${L.t(lang, 'action_next_scan_queued')}';
                              setDialogState(() {
                                formError = queueFollowUp;
                              });
                            } else {
                              setDialogState(() {
                                formError = e.message;
                              });
                            }
                          } catch (_) {
                            _setScanUiState(_ScanUiState.error);
                            if (mounted) {
                              setState(() {
                                _submitting = false;
                              });
                            }
                            setDialogState(() {
                              formError = 'Failed to submit disease report.';
                            });
                          }
                        },
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(L.t(lang, 'save')),
                ),
              ],
            );
          },
        );
      },
    );
    if (mounted && _scanUiState != _ScanUiState.showingResult) {
      _setScanUiState(_ScanUiState.idle);
    }
  }

  Widget _buildQueueStatusCard() {
    if (_queuePendingCount <= 0) {
      return const SizedBox.shrink();
    }
    final lang = LanguageStore.notifier.value;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEACF9D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L.t(
              lang,
              'scan_queue_status_title',
              params: {'count': '$_queuePendingCount'},
            ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (_queueRetryingCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              L.t(
                lang,
                'scan_queue_status_retrying',
                params: {'count': '$_queueRetryingCount'},
              ),
            ),
          ],
          if (_queueNextRetryAt != null) ...[
            const SizedBox(height: 4),
            Text(
              L.t(
                lang,
                'scan_queue_status_next_retry',
                params: {'time': _formatDateTime(_queueNextRetryAt!)},
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _queueStatusLoading ? null : _refreshQueueStatus,
                icon: const Icon(Icons.refresh),
                label: Text(L.t(lang, 'scan_queue_refresh')),
              ),
              OutlinedButton.icon(
                onPressed: _openQueuedScanHistory,
                icon: const Icon(Icons.history),
                label: Text(L.t(lang, 'scan_queue_history')),
              ),
              ElevatedButton.icon(
                onPressed: _drainingQueue ? null : _drainPendingScanQueue,
                icon: const Icon(Icons.sync),
                label: Text(L.t(lang, 'scan_queue_retry_now')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanQuickLinks(String languageCode) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _openQueuedScanHistory,
          icon: const Icon(Icons.history),
          label: Text(L.t(languageCode, 'scan_queue_history')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PopScope(
        canPop: true,
        // onPopInvoked is deprecated; use onPopInvokedWithResult to match
        // the updated PopScope API. the second argument is ignored here.
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) return;
          if (widget.initialMode == null) {
            _resetDirectScanSession(clearSelection: true);
          } else {
            _releaseCamera();
          }
        },
        child: ValueListenableBuilder<String>(
          valueListenable: LanguageStore.notifier,
          builder: (context, lang, _) {
            final isDirectScan = widget.initialMode == null;
            if (isDirectScan && !_cameraRequested) {
              return SafeArea(
                child: FarmSurface(
                  padding: EdgeInsets.zero,
                  child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 32,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 178,
                              child: FarmHeroCard(
                                imageAsset: 'assets/images/crops/tomato.jpg',
                                eyebrow: L.t(lang, 'scan'),
                                title: L.t(lang, 'scan_choose_crop'),
                                body: L.t(lang, 'scan_crop_scope_hint'),
                                trailing: Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFCFF36A),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Color(0xFF15210B),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _ScanCropSelectorGrid(
                                languageCode: lang,
                                loading: _loadingCropContexts,
                                error: _cropContextError,
                                contexts: _cropContexts,
                                selected: _selectedCropContext,
                                onRetry: _loadCropContextsForDirectScan,
                                onSelected: (crop) =>
                                    unawaited(_handleSupportedCropTap(crop)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildExecutionModeCard(lang),
                            const SizedBox(height: 8),
                            _buildOfflineInferenceStatusCard(
                              lang,
                              selectedCropName: _selectedCropContext?.cropName,
                            ),
                            const SizedBox(height: 8),
                            _buildScanQuickLinks(lang),
                            const SizedBox(height: 8),
                            _buildQueueStatusCard(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                ),
              );
            }

            if (_errorKey != null) {
              final detail = _errorDetail;
              final text = detail == null
                  ? L.t(lang, _errorKey!)
                  : '${L.t(lang, _errorKey!)}: $detail';
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(text, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _initCamera,
                        icon: const Icon(Icons.refresh),
                        label: Text(L.t(lang, 'scan_reload_camera')),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: openAppSettings,
                        icon: const Icon(Icons.settings),
                        label: Text(L.t(lang, 'scan_open_app_settings')),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (!_permissionGranted) {
              return Center(
                child: ElevatedButton(
                  onPressed: _initCamera,
                  child: Text(L.t(lang, 'grant_camera_permission')),
                ),
              );
            }

            if (_controller == null || !_controller!.value.isInitialized) {
              return const Center(child: CircularProgressIndicator());
            }

            return LayoutBuilder(
              builder: (context, viewport) {
                final preferredPreviewHeight =
                    (viewport.maxHeight * _cameraPreviewHeightFraction)
                        .clamp(_cameraPreviewMinHeight, _cameraPreviewMaxHeight)
                        .toDouble();
                final maxAllowedPreviewHeight = math.max(
                  160.0,
                  viewport.maxHeight * 0.72,
                );
                final previewHeight = math.min(
                  preferredPreviewHeight,
                  maxAllowedPreviewHeight,
                );

                return Column(
                  children: [
                    SizedBox(
                      height: previewHeight,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final overlaySize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildCameraPreviewFill(constraints),
                              _buildScanGuideOverlay(overlaySize),
                              Positioned(
                                left: 12,
                                right: 12,
                                top: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.62),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (_isBusy)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8),
                                          child: SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _scanUiStateLabel(lang),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _liveGuidance,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                top: 86,
                                child: Container(
                                  width: 58,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.70),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        LocalizedValue.fixed(
                                          lang,
                                          'flash_panel',
                                        ),
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: LocalizedValue.fixed(
                                          lang,
                                          'flashlight',
                                        ),
                                        onPressed: _isBusy
                                            ? null
                                            : _toggleFlashlight,
                                        icon: Icon(
                                          _flashIcon(),
                                          color: _isBusy
                                              ? Colors.white54
                                              : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        _flashLabel(),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      IconButton(
                                        tooltip: LocalizedValue.fixed(
                                          lang,
                                          'zoom_in',
                                        ),
                                        onPressed: _isBusy
                                            ? null
                                            : () => _stepZoom(zoomIn: true),
                                        icon: Icon(
                                          Icons.zoom_in,
                                          color: _isBusy
                                              ? Colors.white54
                                              : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        '${_zoomLevel.toStringAsFixed(1)}x',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: LocalizedValue.fixed(
                                          lang,
                                          'zoom_out',
                                        ),
                                        onPressed: _isBusy
                                            ? null
                                            : () => _stepZoom(zoomIn: false),
                                        icon: Icon(
                                          Icons.zoom_out,
                                          color: _isBusy
                                              ? Colors.white54
                                              : Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      IconButton(
                                        tooltip: LocalizedValue.fixed(
                                          lang,
                                          'upload_last_image',
                                        ),
                                        onPressed: _isBusy
                                            ? null
                                            : _uploadLastCaptured,
                                        icon: Icon(
                                          Icons.cloud_upload_outlined,
                                          color: _isBusy
                                              ? Colors.white54
                                              : Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_isAnalysisInFlight)
                                _buildAnalyzingOverlay(lang),
                            ],
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            if (widget.initialMode == null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFFDF5),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFFDDE9B7),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF4D5B25)
                                                .withValues(alpha: 0.07),
                                            blurRadius: 16,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4F7D12)
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                            ),
                                            child: const Icon(
                                              Icons.eco_rounded,
                                              color: Color(0xFF4F7D12),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _selectedCropContext == null
                                                  ? L.t(lang, 'scan_no_crop_selected')
                                                  : L.t(
                                                      lang,
                                                      'scan_selected_context',
                                                      params: {
                                                        'crop':
                                                            LocalizedValue.crop(
                                                          lang,
                                                          _selectedCropContext!
                                                              .cropName,
                                                        ),
                                                        'farm':
                                                            _selectedCropContext!
                                                                .farmName,
                                                        'plot':
                                                            _selectedCropContext!
                                                                .plotName,
                                                      },
                                                    ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF1E2A12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () =>
                                            _resetDirectScanSession(
                                              clearSelection: true,
                                            ),
                                        icon: const Icon(Icons.swap_horiz),
                                        label: Text(
                                          L.t(lang, 'scan_change_crop'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: _ScanGuidancePanel(languageCode: lang),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _buildExecutionModeCard(lang),
                                  const SizedBox(height: 8),
                                  _buildOfflineInferenceStatusCard(
                                    lang,
                                    selectedCropName:
                                        _selectedCropContext?.cropName,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildScanQuickLinks(lang),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    onPressed:
                                        _isBusy ||
                                            (widget.initialMode == null &&
                                                _selectedCropContext == null)
                                        ? null
                                        : _capture,
                                    icon: const Icon(Icons.camera_alt),
                                    label: Text(L.t(lang, 'scan_crop')),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(56),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    L.t(lang, 'scan_manual_capture_mode'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildScanMetadataCard(),
                                  const SizedBox(height: 8),
                                  _buildStructuredCaptureCard(),
                                  const SizedBox(height: 8),
                                  _buildQueueStatusCard(),
                                ],
                              ),
                            ),
                            if (_lastCaptured != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  '${L.t(lang, 'last_captured')}: ${_lastCaptured!.name}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildExecutionModeCard(String languageCode) {
    return FarmPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L.t(languageCode, 'scan_exec_title'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _scanExecutionModeDescription(languageCode, _scanExecutionMode),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ScanExecutionMode.values
                .map(
                  (mode) => ChoiceChip(
                    label: Text(_scanExecutionModeLabel(languageCode, mode)),
                    selected: _scanExecutionMode == mode,
                    onSelected: (_) => _setScanExecutionMode(mode),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ScanGuidancePanel extends StatelessWidget {
  final String languageCode;
  const _ScanGuidancePanel({required this.languageCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE7DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L.t(languageCode, 'scan_guidance_title'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(L.t(languageCode, 'scan_guidance_step1')),
          Text(L.t(languageCode, 'scan_guidance_step2')),
          Text(L.t(languageCode, 'scan_guidance_step3')),
        ],
      ),
    );
  }
}

class _SupportedCropDefinition {
  final String family;
  final String cropName;
  final String imageAsset;

  const _SupportedCropDefinition({
    required this.family,
    required this.cropName,
    required this.imageAsset,
  });
}

const List<_SupportedCropDefinition> _supportedCrops =
    <_SupportedCropDefinition>[
      _SupportedCropDefinition(
        family: 'tomato',
        cropName: 'Tomato',
        imageAsset: 'assets/images/crops/tomato.jpg',
      ),
      _SupportedCropDefinition(
        family: 'potato',
        cropName: 'Potato',
        imageAsset: 'assets/images/crops/potato.jpg',
      ),
      _SupportedCropDefinition(
        family: 'pepper',
        cropName: 'Pepper',
        imageAsset: 'assets/images/crops/pepper.jpg',
      ),
      _SupportedCropDefinition(
        family: 'corn',
        cropName: 'Maize',
        imageAsset: 'assets/images/crops/maize.jpg',
      ),
    ];

class _ScanCropContext {
  final int farmId;
  final String farmName;
  final int plotId;
  final String plotName;
  final int cropId;
  final String cropName;
  final int? plantingId;
  final bool quickTestOnly;

  const _ScanCropContext({
    required this.farmId,
    required this.farmName,
    required this.plotId,
    required this.plotName,
    required this.cropId,
    required this.cropName,
    required this.plantingId,
    this.quickTestOnly = false,
  });

  String get family => cropFamilyFromName(cropName) ?? 'crop';
}

class _ScanCropSelectorGrid extends StatelessWidget {
  final String languageCode;
  final bool loading;
  final String? error;
  final List<_ScanCropContext> contexts;
  final _ScanCropContext? selected;
  final VoidCallback onRetry;
  final ValueChanged<_SupportedCropDefinition> onSelected;

  const _ScanCropSelectorGrid({
    required this.languageCode,
    required this.loading,
    required this.error,
    required this.contexts,
    required this.selected,
    required this.onRetry,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FarmSectionTitle(
          icon: Icons.eco_rounded,
          title: L.t(languageCode, 'scan_choose_crop'),
          subtitle: L.t(languageCode, 'scan_crop_scope_hint'),
        ),
        if (loading) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(L.t(languageCode, 'scan_loading_registered_crops')),
            ],
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8D4E00),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onRetry,
                child: Text(L.t(languageCode, 'retry')),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final available = constraints.maxWidth;
            final cardWidth = available >= 620
                ? (available - gap * 3) / 4
                : available >= 390
                    ? (available - gap) / 2
                    : available;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final crop in _supportedCrops)
                  SizedBox(
                    width: cardWidth,
                    child: _SupportedCropCard(
                      crop: crop,
                      selected: selected != null && selected!.family == crop.family,
                      accent: _ScanCropSelectorGrid._cropAccent(crop.family),
                      contextLabel: _contextLabelForCrop(crop),
                      onTap: () => onSelected(crop),
                    ),
                  ),
              ],
            );
          },
        ),
        if (!loading && contexts.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            L.t(languageCode, 'scan_no_trained_crops'),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ],
    );
  }

  String _contextLabelForCrop(_SupportedCropDefinition crop) {
    final selectedContext = selected;
    if (selectedContext != null && selectedContext.family == crop.family) {
      if (selectedContext.quickTestOnly) {
        return '${L.t(languageCode, 'scan_offline_test_context')} - not uploaded';
      }
      return '${selectedContext.farmName} / ${selectedContext.plotName}';
    }
    final realMatches = contexts
        .where((item) => item.family == crop.family && !item.quickTestOnly)
        .toList(growable: false);
    if (realMatches.length > 1) {
      return L.t(
        languageCode,
        'scan_contexts_count',
        params: {'count': '${realMatches.length}'},
      );
    }
    if (realMatches.length == 1) {
      return L.t(
        languageCode,
        'scan_contexts_count',
        params: {'count': '1'},
      );
    }
    return '${L.t(languageCode, 'scan_offline_test_context')} - not uploaded';
  }

  static IconData _cropIcon(String family) {
    switch (family) {
      case 'corn':
      case 'maize':
        return Icons.grain;
      case 'potato':
        return Icons.grass;
      case 'pepper':
        return Icons.local_fire_department_outlined;
      case 'tomato':
        return Icons.eco;
      default:
        return Icons.agriculture;
    }
  }

  static Color _cropAccent(String family) {
    switch (family) {
      case 'corn':
      case 'maize':
        return const Color(0xFFF9A825);
      case 'potato':
        return const Color(0xFF8D6E63);
      case 'pepper':
        return const Color(0xFFC62828);
      case 'tomato':
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF2E7D32);
    }
  }
}

class _SupportedCropCard extends StatelessWidget {
  final _SupportedCropDefinition crop;
  final bool selected;
  final Color accent;
  final String contextLabel;
  final VoidCallback onTap;

  const _SupportedCropCard({
    required this.crop,
    required this.selected,
    required this.accent,
    required this.contextLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final languageCode = LanguageStore.notifier.value;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 214),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF1FFD3) : const Color(0xFFFFFDF5),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected ? const Color(0xFF4F7D12) : Colors.white.withValues(alpha: 0.85),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: selected ? 0.24 : 0.12),
                blurRadius: selected ? 24 : 16,
                offset: Offset(0, selected ? 12 : 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 118,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        crop.imageAsset,
                        fit: BoxFit.cover,
                        cacheWidth: 360,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => Container(
                          color: accent.withValues(alpha: 0.12),
                          alignment: Alignment.center,
                          child: Icon(
                            _ScanCropSelectorGrid._cropIcon(crop.family),
                            color: accent,
                            size: 38,
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.58),
                              Colors.black.withValues(alpha: 0.10),
                              accent.withValues(alpha: 0.12),
                            ],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        right: 10,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _ScanCropSelectorGrid._cropIcon(crop.family),
                                color: accent,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                LocalizedValue.crop(languageCode, crop.cropName),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF4F7D12)
                                : Colors.white.withValues(alpha: 0.86),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.9),
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            selected ? Icons.check_rounded : Icons.add_rounded,
                            size: 18,
                            color: selected ? Colors.white : accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _CropCardPill(
                            icon: Icons.psychology_alt_outlined,
                            label: L.t(languageCode, 'ai_model'),
                            color: accent,
                          ),
                          const Spacer(),
                          if (selected)
                            _CropCardPill(
                              icon: Icons.check_circle_outline,
                              label: L.t(languageCode, 'selected'),
                              color: const Color(0xFF4F7D12),
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        contextLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected ? const Color(0xFF34570B) : Colors.grey.shade700,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CropCardPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CropCardPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;

  const _InfoBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _QualityAssessment {
  final bool passed;
  final List<String> reasons;
  final double score;
  final int frameHash;

  const _QualityAssessment({
    required this.passed,
    required this.reasons,
    this.score = 0,
    this.frameHash = 0,
  });
}

class _StructuredCaptureCandidate {
  final XFile file;
  final _QualityAssessment quality;

  const _StructuredCaptureCandidate({
    required this.file,
    required this.quality,
  });
}

class _BestCaptureResult {
  final XFile file;
  final _QualityAssessment quality;

  const _BestCaptureResult({required this.file, required this.quality});
}

class _LuminanceStats {
  final double mean;
  final double stdDev;
  final double greenRatio;
  final double edgeRatio;

  const _LuminanceStats({
    required this.mean,
    required this.stdDev,
    required this.greenRatio,
    required this.edgeRatio,
  });
}

double _qualityScore(_LuminanceStats stats) {
  final lumScore = 1 - ((stats.mean - 128).abs() / 128).clamp(0, 1);
  final blurScore = (stats.stdDev / 64).clamp(0, 1);
  final leafScore = (stats.greenRatio / 0.30).clamp(0, 1);
  final edgeScore = (stats.edgeRatio / 0.14).clamp(0, 1);
  return (lumScore * 0.25) +
      (blurScore * 0.35) +
      (leafScore * 0.25) +
      (edgeScore * 0.15);
}

Map<String, Object>? _analyzeQualityBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }

  final width = decoded.width;
  final height = decoded.height;
  final pixelCount = width * height;
  final step = math.max(1, pixelCount ~/ 12000);

  var sum = 0.0;
  var sumSquares = 0.0;
  var greenDominant = 0;
  var edgeLike = 0;
  double? prevLum;
  var sampleCount = 0;

  for (var i = 0; i < pixelCount; i += step) {
    final x = i % width;
    final y = i ~/ width;
    final pixel = decoded.getPixel(x, y);
    final r = pixel.r.toDouble();
    final g = pixel.g.toDouble();
    final b = pixel.b.toDouble();
    final luminance = (0.299 * r) + (0.587 * g) + (0.114 * b);
    sum += luminance;
    sumSquares += luminance * luminance;
    if (g > r * 1.08 && g > b * 1.08) {
      greenDominant += 1;
    }
    if (prevLum != null && (luminance - prevLum).abs() > 18) {
      edgeLike += 1;
    }
    prevLum = luminance;
    sampleCount += 1;
  }

  if (sampleCount == 0) {
    return <String, Object>{
      'width': width,
      'height': height,
      'mean': 0.0,
      'std_dev': 0.0,
      'green_ratio': 0.0,
      'edge_ratio': 0.0,
      'frame_hash': _quickFrameHash(bytes),
    };
  }

  final mean = sum / sampleCount;
  final variance = math.max(0, (sumSquares / sampleCount) - (mean * mean));
  return <String, Object>{
    'width': width,
    'height': height,
    'mean': mean,
    'std_dev': math.sqrt(variance),
    'green_ratio': greenDominant / sampleCount,
    'edge_ratio': edgeLike / sampleCount,
    'frame_hash': _quickFrameHash(bytes),
  };
}

int _quickFrameHash(Uint8List bytes) {
  var hash = 0x811C9DC5;
  final step = math.max(1, bytes.length ~/ 512);
  for (var i = 0; i < bytes.length; i += step) {
    hash ^= bytes[i];
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
