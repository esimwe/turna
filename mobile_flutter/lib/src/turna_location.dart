part of '../main.dart';

enum TurnaLocationShareMode { current, live }

class TurnaLocationPayload {
  const TurnaLocationPayload({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.title,
    this.subtitle,
    this.live = false,
    this.liveId,
    this.startedAt,
    this.expiresAt,
    this.updatedAt,
    this.endedAt,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String? title;
  final String? subtitle;
  final bool live;
  final String? liveId;
  final String? startedAt;
  final String? expiresAt;
  final String? updatedAt;
  final String? endedAt;

  bool get hasEnded => (endedAt?.trim().isNotEmpty ?? false) || !isLiveActive;

  bool get isLiveActive {
    if (!live) return false;
    if (endedAt?.trim().isNotEmpty ?? false) return false;
    final expires = DateTime.tryParse(expiresAt ?? '');
    if (expires == null) return false;
    return DateTime.now().isBefore(expires.toLocal());
  }

  String get previewLabel {
    if (live) {
      return isLiveActive ? 'Canli konum' : 'Canli konum (sona erdi)';
    }
    final trimmedTitle = title?.trim() ?? '';
    if (trimmedTitle.isNotEmpty) return trimmedTitle;
    return 'Konum';
  }

  String get displayTitle {
    if (live) return 'Canli konum';
    final trimmedTitle = title?.trim() ?? '';
    if (trimmedTitle.isNotEmpty) return trimmedTitle;
    return 'Konum';
  }

  String get displaySubtitle {
    if (live) {
      if (endedAt?.trim().isNotEmpty ?? false) {
        return 'Paylasim sona erdi';
      }
      final expires = DateTime.tryParse(expiresAt ?? '');
      if (expires != null) {
        final remaining = expires.toLocal().difference(DateTime.now());
        if (!remaining.isNegative) {
          return 'Kalan ${formatTurnaDurationShort(remaining)}';
        }
      }
      final updated = DateTime.tryParse(updatedAt ?? '');
      if (updated != null) {
        return 'Son guncelleme ${formatTurnaClockLabel(updated.toLocal())}';
      }
      return 'Canli paylasim';
    }

    final trimmedSubtitle = subtitle?.trim() ?? '';
    if (trimmedSubtitle.isNotEmpty) return trimmedSubtitle;
    return formatTurnaLocationCoordinates(latitude, longitude);
  }

  TurnaLocationPayload copyWith({
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? title,
    String? subtitle,
    bool? live,
    String? liveId,
    String? startedAt,
    String? expiresAt,
    String? updatedAt,
    String? endedAt,
  }) {
    return TurnaLocationPayload(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      live: live ?? this.live,
      liveId: liveId ?? this.liveId,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
    'title': title,
    'subtitle': subtitle,
    'live': live,
    'liveId': liveId,
    'startedAt': startedAt,
    'expiresAt': expiresAt,
    'updatedAt': updatedAt,
    'endedAt': endedAt,
  };

  factory TurnaLocationPayload.fromMap(Map<String, dynamic> map) {
    double? parseDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse('$value');
    }

    return TurnaLocationPayload(
      latitude: parseDouble(map['latitude']) ?? 0,
      longitude: parseDouble(map['longitude']) ?? 0,
      accuracyMeters: parseDouble(map['accuracyMeters']),
      title: TurnaUserProfile._nullableString(map['title']),
      subtitle: TurnaUserProfile._nullableString(map['subtitle']),
      live: map['live'] == true,
      liveId: TurnaUserProfile._nullableString(map['liveId']),
      startedAt: TurnaUserProfile._nullableString(map['startedAt']),
      expiresAt: TurnaUserProfile._nullableString(map['expiresAt']),
      updatedAt: TurnaUserProfile._nullableString(map['updatedAt']),
      endedAt: TurnaUserProfile._nullableString(map['endedAt']),
    );
  }
}

class TurnaLocationSelection {
  const TurnaLocationSelection({
    required this.payload,
    required this.mode,
    this.liveDuration,
  });

  final TurnaLocationPayload payload;
  final TurnaLocationShareMode mode;
  final Duration? liveDuration;
}

class TurnaPlaceSuggestion {
  const TurnaPlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.coordinates,
    this.layer,
  });

  final String title;
  final String subtitle;
  final ll.LatLng coordinates;
  final String? layer;

  TurnaLocationPayload toPayload() {
    return TurnaLocationPayload(
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      title: title,
      subtitle: subtitle,
    );
  }

  factory TurnaPlaceSuggestion.fromStadiaFeature(Map<String, dynamic> feature) {
    final geometry = Map<String, dynamic>.from(
      feature['geometry'] as Map<String, dynamic>? ?? const {},
    );
    final coordinates =
        (geometry['coordinates'] as List<dynamic>? ?? const []).toList();
    final lon = coordinates.isNotEmpty
        ? (coordinates[0] as num).toDouble()
        : 0.0;
    final lat = coordinates.length > 1
        ? (coordinates[1] as num).toDouble()
        : 0.0;
    final properties = Map<String, dynamic>.from(
      feature['properties'] as Map<String, dynamic>? ?? const {},
    );
    final label = (properties['label'] ?? '').toString().trim();
    final name = (properties['name'] ?? '').toString().trim();
    final title = name.isNotEmpty
        ? name
        : (label.isNotEmpty ? label.split(',').first.trim() : 'Konum');
    final subtitle = label.isNotEmpty && label != title
        ? label
        : formatTurnaLocationCoordinates(lat, lon);

    return TurnaPlaceSuggestion(
      title: title,
      subtitle: subtitle,
      coordinates: ll.LatLng(lat, lon),
      layer: TurnaUserProfile._nullableString(properties['layer']),
    );
  }
}

String formatTurnaLocationCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

String formatTurnaDurationShort(Duration duration) {
  final clamped = duration.isNegative ? Duration.zero : duration;
  if (clamped.inHours >= 1) {
    final hours = clamped.inHours;
    final minutes = clamped.inMinutes.remainder(60);
    return minutes > 0 ? '$hours sa $minutes dk' : '$hours sa';
  }
  final minutes = math.max(1, clamped.inMinutes);
  return '$minutes dk';
}

String formatTurnaClockLabel(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatTurnaLocationAccuracy(double? accuracyMeters) {
  if (accuracyMeters == null || !accuracyMeters.isFinite) {
    return 'Konum dogrulaniyor';
  }
  return '~${accuracyMeters.round()} m dogruluk';
}

class TurnaStadiaMapsApi {
  static const _host = 'api.stadiamaps.com';

  static Future<List<TurnaPlaceSuggestion>> reverseNearby(ll.LatLng center) async {
    if (!TurnaAppConfig.hasStadiaMapsKey) return const [];

    final uri = Uri.https(_host, '/geocoding/v1/reverse', {
      'api_key': TurnaAppConfig.stadiaMapsApiKey,
      'point.lat': '${center.latitude}',
      'point.lon': '${center.longitude}',
      'size': '8',
      'layers': 'venue,address,street',
      'lang': 'tr',
    });
    return _requestPlaces(uri);
  }

  static Future<List<TurnaPlaceSuggestion>> searchPlaces(
    String query, {
    ll.LatLng? focus,
  }) async {
    if (!TurnaAppConfig.hasStadiaMapsKey) return const [];
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final params = <String, String>{
      'api_key': TurnaAppConfig.stadiaMapsApiKey,
      'text': trimmed,
      'size': '8',
      'layers': 'venue,address,street',
      'lang': 'tr',
    };
    if (focus != null) {
      params['focus.point.lat'] = '${focus.latitude}';
      params['focus.point.lon'] = '${focus.longitude}';
    }

    final uri = Uri.https(_host, '/geocoding/v1/search', params);
    return _requestPlaces(uri);
  }

  static Future<List<TurnaPlaceSuggestion>> _requestPlaces(Uri uri) async {
    try {
      final response = await http.get(uri);
      if (response.statusCode >= 400) return const [];
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = decoded['features'] as List<dynamic>? ?? const [];
      return features
          .whereType<Map>()
          .map((item) => TurnaPlaceSuggestion.fromStadiaFeature(
                Map<String, dynamic>.from(item),
              ))
          .where(
            (item) =>
                item.coordinates.latitude != 0 || item.coordinates.longitude != 0,
          )
          .toList();
    } catch (error) {
      turnaLog('stadia geocoding skipped', error);
      return const [];
    }
  }
}

TileLayer buildTurnaStadiaTileLayer() {
  return TileLayer(
    urlTemplate:
        'https://tiles.stadiamaps.com/tiles/$kTurnaStadiaRasterStyle/{z}/{x}/{y}{r}.png?api_key={api_key}',
    additionalOptions: {'api_key': TurnaAppConfig.stadiaMapsApiKey},
    userAgentPackageName: 'com.turna.chat',
  );
}

Future<void> openTurnaLocationInMaps(TurnaLocationPayload payload) async {
  final label = Uri.encodeComponent(payload.displayTitle);
  final uri = Platform.isIOS
      ? Uri.parse(
          'http://maps.apple.com/?ll=${payload.latitude},${payload.longitude}&q=$label',
        )
      : Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${payload.latitude},${payload.longitude}',
        );

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _TurnaMapMarker extends StatelessWidget {
  const _TurnaMapMarker({this.live = false});

  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: live ? 22 : 18,
      height: live ? 22 : 18,
      decoration: BoxDecoration(
        color: live ? TurnaColors.success : TurnaColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [TurnaColors.shadowSoft],
      ),
    );
  }
}

class _TurnaLocationMapPreview extends StatelessWidget {
  const _TurnaLocationMapPreview({
    required this.payload,
    this.height = 168,
  });

  final TurnaLocationPayload payload;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!TurnaAppConfig.hasStadiaMapsKey) {
      return Container(
        height: height,
        color: TurnaColors.backgroundMuted,
        alignment: Alignment.center,
        child: const Icon(Icons.map_outlined, color: TurnaColors.textMuted),
      );
    }

    return SizedBox(
      height: height,
      child: IgnorePointer(
        child: FlutterMap(
          options: MapOptions(
            initialCenter: ll.LatLng(payload.latitude, payload.longitude),
            initialZoom: 15.5,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            buildTurnaStadiaTileLayer(),
            MarkerLayer(
              markers: [
                Marker(
                  point: ll.LatLng(payload.latitude, payload.longitude),
                  width: 34,
                  height: 34,
                  child: _TurnaMapMarker(live: payload.live),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  Timer? _searchDebounce;

  ll.LatLng? _currentLatLng;
  double? _currentAccuracyMeters;
  bool _locating = true;
  bool _loadingNearby = false;
  bool _searching = false;
  String? _error;
  List<TurnaPlaceSuggestion> _nearbyPlaces = const [];
  List<TurnaPlaceSuggestion> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    unawaited(_loadInitialLocation());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _searchResults = const [];
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 280), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final results = await TurnaStadiaMapsApi.searchPlaces(
        query,
        focus: _currentLatLng,
      );
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    });
  }

  Future<void> _loadInitialLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      final position = await _fetchCurrentPosition();
      final center = ll.LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _currentLatLng = center;
        _currentAccuracyMeters = position.accuracy;
        _locating = false;
      });
      if (TurnaAppConfig.hasStadiaMapsKey) {
        _mapController.move(center, 15.5);
      }
      unawaited(_loadNearbyPlaces(center));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = error.toString();
      });
    }
  }

  Future<Position> _fetchCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw TurnaApiException('Konum servisi kapali.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw TurnaApiException('Konum izni gerekli.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
      ),
    );
  }

  Future<void> _loadNearbyPlaces(ll.LatLng center) async {
    setState(() => _loadingNearby = true);
    final places = await TurnaStadiaMapsApi.reverseNearby(center);
    if (!mounted) return;
    setState(() {
      _nearbyPlaces = places;
      _loadingNearby = false;
    });
  }

  Future<void> _shareCurrentLocation() async {
    final center = _currentLatLng;
    if (center == null) return;
    final subtitle = _nearbyPlaces.isNotEmpty
        ? _nearbyPlaces.first.subtitle
        : formatTurnaLocationCoordinates(center.latitude, center.longitude);
    Navigator.pop(
      context,
      TurnaLocationSelection(
        mode: TurnaLocationShareMode.current,
        payload: TurnaLocationPayload(
          latitude: center.latitude,
          longitude: center.longitude,
          accuracyMeters: _currentAccuracyMeters,
          title: 'Mevcut konum',
          subtitle: subtitle,
        ),
      ),
    );
  }

  Future<void> _shareLiveLocation() async {
    final center = _currentLatLng;
    if (center == null) return;
    final duration = await showModalBottomSheet<Duration>(
      context: context,
      builder: (sheetContext) {
        const options = <MapEntry<String, Duration>>[
          MapEntry('15 dakika', Duration(minutes: 15)),
          MapEntry('30 dakika', Duration(minutes: 30)),
          MapEntry('1 saat', Duration(hours: 1)),
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                ListTile(
                  leading: const Icon(Icons.location_history_rounded),
                  title: Text(option.key),
                  onTap: () => Navigator.pop(sheetContext, option.value),
                ),
            ],
          ),
        );
      },
    );
    if (duration == null || !mounted) return;

    final now = DateTime.now().toUtc();
    Navigator.pop(
      context,
      TurnaLocationSelection(
        mode: TurnaLocationShareMode.live,
        liveDuration: duration,
        payload: TurnaLocationPayload(
          latitude: center.latitude,
          longitude: center.longitude,
          accuracyMeters: _currentAccuracyMeters,
          title: 'Canli konum',
          live: true,
          liveId: '${now.millisecondsSinceEpoch}-${center.latitude}-${center.longitude}',
          startedAt: now.toIso8601String(),
          expiresAt: now.add(duration).toIso8601String(),
          updatedAt: now.toIso8601String(),
        ),
      ),
    );
  }

  Widget _buildCurrentLocationTile() {
    final center = _currentLatLng;
    final subtitle = center == null
        ? 'Konum bekleniyor'
        : formatTurnaLocationAccuracy(_currentAccuracyMeters);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: TurnaColors.success.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.my_location_rounded,
          color: TurnaColors.success,
          size: 18,
        ),
      ),
      title: const Text(
        'Mevcut konumu gonder',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      onTap: center == null ? null : _shareCurrentLocation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentLatLng;
    final showingSearch = _searchController.text.trim().isNotEmpty;
    final listItems = showingSearch ? _searchResults : _nearbyPlaces;

    return Scaffold(
      backgroundColor: TurnaColors.backgroundSoft,
      appBar: AppBar(
        leadingWidth: 84,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Iptal'),
        ),
        title: const Text('Konum gonder'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadInitialLocation,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Arama yapin/adres girin',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            color: Colors.white,
                            child: center == null || !TurnaAppConfig.hasStadiaMapsKey
                                ? Center(
                                    child: _locating
                                        ? const CircularProgressIndicator()
                                        : Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Text(
                                              _error ??
                                                  'Harita icin Stadia anahtari veya konum bilgisi gerekli.',
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                  )
                                : FlutterMap(
                                    mapController: _mapController,
                                    options: MapOptions(
                                      initialCenter: center,
                                      initialZoom: 15.5,
                                    ),
                                    children: [
                                      buildTurnaStadiaTileLayer(),
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: center,
                                            width: 34,
                                            height: 34,
                                            child: const _TurnaMapMarker(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 18,
                          child: FloatingActionButton.small(
                            heroTag: 'location-picker-center',
                            onPressed: _loadInitialLocation,
                            backgroundColor: Colors.white,
                            foregroundColor: TurnaColors.primary,
                            child: const Icon(Icons.navigation_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    decoration: const BoxDecoration(
                      color: TurnaColors.backgroundSoft,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        FilledButton.icon(
                          onPressed: center == null ? null : _shareLiveLocation,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: Colors.white,
                            foregroundColor: TurnaColors.success,
                          ),
                          icon: const Icon(Icons.location_history_rounded),
                          label: const Text('Canli konumu paylas'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Yakindaki yerler',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: TurnaColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView(
                            children: [
                              _buildCurrentLocationTile(),
                              if (_loadingNearby && !showingSearch)
                                const ListTile(
                                  title: Text('Yakindaki yerler aranıyor...'),
                                  trailing: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              if (_searching)
                                const ListTile(
                                  title: Text('Araniyor...'),
                                  trailing: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              for (final place in listItems)
                                ListTile(
                                  leading: const Icon(Icons.location_on_outlined),
                                  title: Text(
                                    place.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    place.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => Navigator.pop(
                                    context,
                                    TurnaLocationSelection(
                                      mode: TurnaLocationShareMode.current,
                                      payload: place.toPayload(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (TurnaAppConfig.hasStadiaMapsKey)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Harita verisi: Stadia Maps, OpenMapTiles, OpenStreetMap',
                              style: TextStyle(
                                fontSize: 11,
                                color: TurnaColors.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TurnaLiveLocationShare {
  const TurnaLiveLocationShare({
    required this.messageId,
    required this.chatId,
    required this.liveId,
    required this.startedAt,
    required this.expiresAt,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final String messageId;
  final String chatId;
  final String liveId;
  final String startedAt;
  final String expiresAt;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  TurnaLiveLocationShare copyWith({
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) {
    return TurnaLiveLocationShare(
      messageId: messageId,
      chatId: chatId,
      liveId: liveId,
      startedAt: startedAt,
      expiresAt: expiresAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
    );
  }

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'chatId': chatId,
    'liveId': liveId,
    'startedAt': startedAt,
    'expiresAt': expiresAt,
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
  };

  factory TurnaLiveLocationShare.fromMap(Map<String, dynamic> map) {
    double? parseDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse('$value');
    }

    return TurnaLiveLocationShare(
      messageId: (map['messageId'] ?? '').toString(),
      chatId: (map['chatId'] ?? '').toString(),
      liveId: (map['liveId'] ?? '').toString(),
      startedAt: (map['startedAt'] ?? '').toString(),
      expiresAt: (map['expiresAt'] ?? '').toString(),
      latitude: parseDouble(map['latitude']) ?? 0,
      longitude: parseDouble(map['longitude']) ?? 0,
      accuracyMeters: parseDouble(map['accuracyMeters']),
    );
  }
}

class TurnaLiveLocationManager extends ChangeNotifier {
  TurnaLiveLocationManager._();

  static final TurnaLiveLocationManager instance = TurnaLiveLocationManager._();

  final Map<String, TurnaLiveLocationShare> _sharesByMessageId = {};
  StreamSubscription<Position>? _positionSubscription;
  Timer? _expiryTimer;
  AuthSession? _session;
  Position? _pendingPosition;
  bool _dispatching = false;
  String? _restoredUserId;

  bool isActive(String messageId) => _sharesByMessageId.containsKey(messageId);

  Future<void> bindSession(AuthSession? session) async {
    if (session == null) {
      _session = null;
      _restoredUserId = null;
      _sharesByMessageId.clear();
      await _stopPositionStream();
      notifyListeners();
      return;
    }

    _session = session;
    if (_restoredUserId != session.userId) {
      _restoredUserId = session.userId;
      await _restoreShares(session.userId);
    }

    _scheduleExpiryCheck();
    await _ensurePositionStream();
  }

  Future<void> startShare({
    required AuthSession session,
    required String chatId,
    required ChatMessage message,
    required TurnaLocationPayload payload,
  }) async {
    final liveId = payload.liveId;
    final startedAt = payload.startedAt;
    final expiresAt = payload.expiresAt;
    if (liveId == null || startedAt == null || expiresAt == null) {
      return;
    }

    _session = session;
    _restoredUserId = session.userId;
    _sharesByMessageId[message.id] = TurnaLiveLocationShare(
      messageId: message.id,
      chatId: chatId,
      liveId: liveId,
      startedAt: startedAt,
      expiresAt: expiresAt,
      latitude: payload.latitude,
      longitude: payload.longitude,
      accuracyMeters: payload.accuracyMeters,
    );
    await _persistShares();
    _scheduleExpiryCheck();
    await _ensurePositionStream();
    notifyListeners();
  }

  Future<void> stopShare(String messageId) async {
    final share = _sharesByMessageId.remove(messageId);
    if (share == null) return;

    await _persistShares();
    _scheduleExpiryCheck();
    notifyListeners();

    final session = _session;
    if (session == null) {
      await _stopPositionStream();
      return;
    }

    final expiresAt = DateTime.tryParse(share.expiresAt)?.toUtc();
    final stoppedAt = DateTime.now().toUtc();
    final endedAt = expiresAt != null && stoppedAt.isAfter(expiresAt)
        ? expiresAt
        : stoppedAt;
    final now = stoppedAt.toIso8601String();
    final payload = TurnaLocationPayload(
      latitude: share.latitude,
      longitude: share.longitude,
      accuracyMeters: share.accuracyMeters,
      title: 'Canli konum',
      live: true,
      liveId: share.liveId,
      startedAt: share.startedAt,
      expiresAt: share.expiresAt,
      updatedAt: now,
      endedAt: endedAt.toIso8601String(),
    );
    try {
      await ChatApi.editMessage(
        session,
        messageId: share.messageId,
        text: buildTurnaLocationEncodedText(location: payload),
      );
    } catch (error) {
      turnaLog('live location stop skipped', error);
    }

    await _ensurePositionStream();
  }

  Future<void> _restoreShares(String userId) async {
    _sharesByMessageId.clear();
    final prefs = await SharedPreferences.getInstance();
    final rawItems =
        prefs.getStringList('turna_live_location_shares_$userId') ?? const [];
    for (final raw in rawItems) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final share = TurnaLiveLocationShare.fromMap(decoded);
        _sharesByMessageId[share.messageId] = share;
      } catch (_) {}
    }

    final expiredIds = _sharesByMessageId.values
        .where(
          (share) =>
              DateTime.tryParse(share.expiresAt)?.isBefore(DateTime.now().toUtc()) ==
              true,
        )
        .map((share) => share.messageId)
        .toList();
    for (final messageId in expiredIds) {
      await stopShare(messageId);
    }
  }

  Future<void> _persistShares() async {
    final session = _session;
    if (session == null) return;
    final prefs = await SharedPreferences.getInstance();
    final rawItems = _sharesByMessageId.values
        .map((share) => jsonEncode(share.toMap()))
        .toList();
    await prefs.setStringList(
      'turna_live_location_shares_${session.userId}',
      rawItems,
    );
  }

  Future<void> _ensurePositionStream() async {
    if (_sharesByMessageId.isEmpty || _session == null) {
      await _stopPositionStream();
      return;
    }
    if (_positionSubscription != null) return;

    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: kTurnaLiveLocationUpdateDistanceMeters,
            intervalDuration: const Duration(
              seconds: kTurnaLiveLocationUpdateIntervalSeconds,
            ),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Turna',
              notificationText: 'Canli konum paylasimi suruyor.',
              enableWakeLock: true,
            ),
          )
        : Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            activityType: ActivityType.otherNavigation,
            distanceFilter: kTurnaLiveLocationUpdateDistanceMeters,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: kTurnaLiveLocationUpdateDistanceMeters,
          );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) {
        _enqueuePosition(position);
      },
      onError: (Object error) {
        turnaLog('live location stream skipped', error);
      },
    );
  }

  Future<void> _stopPositionStream() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _enqueuePosition(Position position) {
    _pendingPosition = position;
    if (_dispatching) return;
    unawaited(_flushPendingPosition());
  }

  Future<void> _flushPendingPosition() async {
    if (_dispatching) return;
    _dispatching = true;
    try {
      while (_pendingPosition != null) {
        final position = _pendingPosition!;
        _pendingPosition = null;
        final activeShares = _sharesByMessageId.values.toList(growable: false);
        for (final share in activeShares) {
          final expiresAt = DateTime.tryParse(share.expiresAt);
          if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
            await stopShare(share.messageId);
            continue;
          }
          await _sendPositionUpdate(share, position);
        }
      }
    } finally {
      _dispatching = false;
    }
  }

  Future<void> _sendPositionUpdate(
    TurnaLiveLocationShare share,
    Position position,
  ) async {
    final session = _session;
    if (session == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = TurnaLocationPayload(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      title: 'Canli konum',
      live: true,
      liveId: share.liveId,
      startedAt: share.startedAt,
      expiresAt: share.expiresAt,
      updatedAt: now,
    );

    try {
      await ChatApi.editMessage(
        session,
        messageId: share.messageId,
        text: buildTurnaLocationEncodedText(location: payload),
      );
      _sharesByMessageId[share.messageId] = share.copyWith(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
      await _persistShares();
    } catch (error) {
      turnaLog('live location update skipped', error);
    }
  }

  void _scheduleExpiryCheck() {
    _expiryTimer?.cancel();
    if (_sharesByMessageId.isEmpty) return;

    final nextExpiry = _sharesByMessageId.values
        .map((share) => DateTime.tryParse(share.expiresAt))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (current, item) {
          if (current == null) return item;
          return item.isBefore(current) ? item : current;
        });
    if (nextExpiry == null) return;

    final delay = nextExpiry.difference(DateTime.now().toUtc());
    _expiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () async {
        final expiredIds = _sharesByMessageId.values
            .where(
              (share) =>
                  DateTime.tryParse(share.expiresAt)?.isBefore(
                        DateTime.now().toUtc(),
                      ) ==
                  true,
            )
            .map((share) => share.messageId)
            .toList();
        for (final messageId in expiredIds) {
          await stopShare(messageId);
        }
        _scheduleExpiryCheck();
      },
    );
  }
}

class _TurnaLocationMessageCard extends StatelessWidget {
  const _TurnaLocationMessageCard({
    required this.payload,
    required this.mine,
    this.onStopShare,
  });

  final TurnaLocationPayload payload;
  final bool mine;
  final Future<void> Function()? onStopShare;

  @override
  Widget build(BuildContext context) {
    final cardColor = mine ? Colors.white.withValues(alpha: 0.18) : Colors.white;
    final textColor = mine
        ? TurnaColors.chatOutgoingText
        : TurnaColors.chatIncomingText;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openTurnaLocationInMaps(payload),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: payload.live
                ? TurnaColors.success.withValues(alpha: 0.28)
                : TurnaColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: _TurnaLocationMapPreview(payload: payload, height: 150),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        payload.live
                            ? Icons.location_history_rounded
                            : Icons.location_on_rounded,
                        color: payload.live
                            ? TurnaColors.success
                            : TurnaColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          payload.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    payload.displaySubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.78),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatTurnaLocationCoordinates(
                      payload.latitude,
                      payload.longitude,
                    ),
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.62),
                      fontSize: 11.5,
                    ),
                  ),
                  if (payload.live &&
                      payload.isLiveActive &&
                      mine &&
                      onStopShare != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onStopShare,
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('Canli konumu durdur'),
                        style: TextButton.styleFrom(
                          foregroundColor: TurnaColors.error,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
