part of 'home_screen.dart';

class _HomeWeatherStrip extends StatefulWidget {
  final String languageCode;

  const _HomeWeatherStrip({required this.languageCode});

  @override
  State<_HomeWeatherStrip> createState() => _HomeWeatherStripState();
}

class _HomeWeatherStripState extends State<_HomeWeatherStrip> {
  static const String _homeWeatherCacheKey = 'home_weather_cache_v1';

  String? _locationText;
  String? _regionText;
  String? _latLonText;
  String _tempText = '--\u00B0C';
  String _detailText = '';
  String _statusKey = 'loading_weather';
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    _load();
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    super.dispose();
  }

  void _handleSyncRefresh() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    await _loadCached();

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _markUnavailableWithoutFakeLocation();
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _markUnavailableWithoutFakeLocation();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      await _loadForLocation(
        pos.latitude,
        pos.longitude,
        'Farm area (${pos.latitude.toStringAsFixed(2)}, ${pos.longitude.toStringAsFixed(2)})',
      );
    } catch (_) {
      _markUnavailableWithoutFakeLocation();
    }
  }

  void _markUnavailableWithoutFakeLocation() {
    if (!mounted) return;
    if (_lastUpdated != null || _locationText != null) {
      return;
    }
    setState(() {
      _locationText = null;
      _regionText = null;
      _latLonText = null;
      _tempText = '--\u00B0C';
      _detailText = '';
      _statusKey = 'weather_unavailable';
    });
  }

  Future<void> _loadCached() async {
    final payload = await LocalCacheStore.instance.readMap(_homeWeatherCacheKey);
    if (payload == null || !mounted) return;
    setState(() {
      _locationText = payload['locationText']?.toString();
      _regionText = payload['regionText']?.toString();
      _latLonText = payload['latLonText']?.toString();
      _tempText = payload['tempText']?.toString() ?? '--\u00B0C';
      _detailText = payload['detailText']?.toString() ?? '';
      _statusKey = payload['statusKey']?.toString() ?? 'weather_unavailable';
      _lastUpdated = DateTime.tryParse(payload['lastUpdated']?.toString() ?? '');
    });
  }

  Future<void> _loadForLocation(double lat, double lon, String label) async {
    if (!mounted) return;
    setState(() {
      _locationText = label;
      _regionText = null;
      _latLonText = '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
    });

    await _loadPlaceName(lat, lon, label);
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat'
      '&longitude=$lon'
      '&current_weather=true'
      '&timezone=auto',
    );

    try {
      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'SmartFarm/1.0 (Flutter)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        if (!mounted) return;
        if (_lastUpdated != null) {
          return;
        }
        setState(() {
          _tempText = '--\u00B0C';
          _detailText = '';
          _statusKey = 'weather_unavailable';
        });
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current_weather'] as Map<String, dynamic>?;
      if (!mounted) return;
      if (current == null) {
        if (_lastUpdated != null) {
          return;
        }
        setState(() {
          _tempText = '--\u00B0C';
          _detailText = '';
          _statusKey = 'weather_unavailable';
        });
        return;
      }

      final temp = current['temperature'];
      final wind = current['windspeed'];
      final code = current['weathercode'];
      final tempC = temp is num ? temp.toDouble() : null;
      final weatherCode = code is int ? code : int.tryParse('$code') ?? 0;

      setState(() {
        _tempText = tempC != null ? '${tempC.round()}\u00B0C' : '--\u00B0C';
        _detailText = wind is num ? '${wind.round()} km/h' : '';
        _statusKey = _mapWeatherCode(weatherCode);
        _lastUpdated = DateTime.now();
      });
      await LocalCacheStore.instance.write(_homeWeatherCacheKey, <String, Object?>{
        'locationText': _locationText,
        'regionText': _regionText,
        'latLonText': _latLonText,
        'tempText': _tempText,
        'detailText': _detailText,
        'statusKey': _statusKey,
        'lastUpdated': _lastUpdated?.toIso8601String(),
      });
    } catch (_) {
      if (!mounted) return;
      if (_lastUpdated != null) {
        return;
      }
      setState(() {
        _tempText = '--\u00B0C';
        _detailText = '';
        _statusKey = 'weather_unavailable';
      });
    }
  }

  Future<void> _loadPlaceName(double lat, double lon, String fallbackLabel) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?format=jsonv2'
      '&lat=$lat'
      '&lon=$lon',
    );

    try {
      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'SmartFarm/1.0 (Flutter)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _locationText = fallbackLabel;
        });
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final address = json['address'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final place =
          address['city'] ??
          address['town'] ??
          address['village'] ??
          address['county'] ??
          address['state'] ??
          address['country'];
      final region =
          address['state'] ?? address['region'] ?? address['county'] ?? address['country'];

      if (!mounted) return;
      setState(() {
        _locationText = place?.toString() ?? fallbackLabel;
        _regionText = region?.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationText = fallbackLabel;
      });
    }
  }

  String _mapWeatherCode(int code) {
    if (code == 0) return 'weather_clear';
    if (code == 1 || code == 2) return 'weather_mostly_sunny';
    if (code == 3) return 'weather_cloudy';
    if (code == 45 || code == 48) return 'weather_foggy';
    if (code >= 51 && code <= 67) return 'weather_drizzle';
    if (code >= 71 && code <= 77) return 'weather_snow';
    if (code >= 80 && code <= 82) return 'weather_showers';
    if (code >= 95) return 'weather_stormy';
    return 'weather_generic';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = widget.languageCode;
    final updatedText = _lastUpdated == null
        ? L.t(lang, 'updated_now')
        : L.t(
            lang,
            'updated_at',
            params: {'time': _lastUpdated!.toLocal().toString().substring(11, 16)},
          );

    return FarmPanel(
      color: const Color(0xFFF8FAEA),
      padding: EdgeInsets.zero,
      onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WeatherScreen(
                snapshot: WeatherOverviewSnapshot(
                  locationText: _locationText,
                  regionText: _regionText,
                  latLonText: _latLonText,
                  tempText: _tempText,
                  detailText: _detailText,
                  statusKey: _statusKey,
                  lastUpdated: _lastUpdated,
                ),
              ),
            ),
          );
        },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFCFF36A), Color(0xFF7FA51E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.wb_sunny_rounded, color: Color(0xFF1E2A12), size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L.t(lang, 'weatherMonitoring'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1E2A12),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      L.t(lang, _statusKey),
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _tempText,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E2A12),
                  letterSpacing: -1.0,
                ),
              ),
            ],
          ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _WeatherMiniTile(
                  icon: Icons.place_rounded,
                  label: L.t(lang, 'farm_location'),
                  value: _locationText ?? L.t(lang, 'getting_location'),
                  tone: const Color(0xFF41670F),
                ),
                if (_regionText != null && _regionText!.isNotEmpty)
                  _WeatherMiniTile(
                    icon: Icons.public_rounded,
                    label: L.t(lang, 'region'),
                    value: _regionText!,
                    tone: const Color(0xFF386C91),
                  ),
                if (_latLonText != null && _latLonText!.isNotEmpty)
                  _WeatherMiniTile(
                    icon: Icons.my_location_rounded,
                    label: L.t(lang, 'lat_lon'),
                    value: _latLonText!,
                    tone: const Color(0xFF8A6500),
                  ),
                if (_detailText.isNotEmpty)
                  _WeatherMiniTile(
                    icon: Icons.air_rounded,
                    label: L.t(lang, 'wind'),
                    value: _detailText,
                    tone: const Color(0xFF53627A),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.update_rounded, size: 16, color: Colors.grey.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    updatedText,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: theme.colorScheme.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherMiniTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color tone;

  const _WeatherMiniTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final width = screenWidth >= 720 ? (screenWidth - 52) / 2 : screenWidth - 32;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: tone, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF1E2A12),
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
