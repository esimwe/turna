part of turna_app;

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
    final coordinates = (geometry['coordinates'] as List<dynamic>? ?? const [])
        .toList();
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
      layer: turnaProfileNullableString(properties['layer']),
    );
  }
}

String formatTurnaLocationAccuracy(double? accuracyMeters) {
  if (accuracyMeters == null || !accuracyMeters.isFinite) {
    return 'Konum doğrulanıyor';
  }
  return '~${accuracyMeters.round()} m dogruluk';
}

class TurnaStadiaMapsApi {
  static const _host = 'api.stadiamaps.com';

  static Future<List<TurnaPlaceSuggestion>> reverseNearby(
    ll.LatLng center,
  ) async {
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
          .map(
            (item) => TurnaPlaceSuggestion.fromStadiaFeature(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (item) =>
                item.coordinates.latitude != 0 ||
                item.coordinates.longitude != 0,
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

enum TurnaExternalMapApp { system, apple, google, browser }

Uri _turnaAppleMapsUri(TurnaLocationPayload payload) {
  final label = Uri.encodeComponent(payload.displayTitle);
  return Uri.parse(
    'http://maps.apple.com/?ll=${payload.latitude},${payload.longitude}&q=$label',
  );
}

Uri _turnaGoogleMapsAppUri(TurnaLocationPayload payload) {
  final label = Uri.encodeComponent(payload.displayTitle);
  if (Platform.isIOS) {
    return Uri.parse(
      'comgooglemaps://?center=${payload.latitude},${payload.longitude}&q=${payload.latitude},${payload.longitude}($label)',
    );
  }
  return Uri.parse(
    'geo:${payload.latitude},${payload.longitude}?q=${payload.latitude},${payload.longitude}($label)',
  );
}

Uri _turnaGoogleMapsWebUri(TurnaLocationPayload payload) {
  return Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${payload.latitude},${payload.longitude}',
  );
}

Future<bool> _launchTurnaMapUri(Uri uri) async {
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> openTurnaLocationInMaps(
  TurnaLocationPayload payload, {
  TurnaExternalMapApp preferredApp = TurnaExternalMapApp.system,
}) async {
  if (preferredApp == TurnaExternalMapApp.apple) {
    await _launchTurnaMapUri(_turnaAppleMapsUri(payload));
    return;
  }
  if (preferredApp == TurnaExternalMapApp.google) {
    final openedApp = await _launchTurnaMapUri(_turnaGoogleMapsAppUri(payload));
    if (!openedApp) {
      await _launchTurnaMapUri(_turnaGoogleMapsWebUri(payload));
    }
    return;
  }
  if (preferredApp == TurnaExternalMapApp.browser) {
    await _launchTurnaMapUri(_turnaGoogleMapsWebUri(payload));
    return;
  }

  if (Platform.isIOS) {
    final openedApple = await _launchTurnaMapUri(_turnaAppleMapsUri(payload));
    if (openedApple) return;
  }
  final openedGoogle = await _launchTurnaMapUri(
    _turnaGoogleMapsAppUri(payload),
  );
  if (openedGoogle) return;
  await _launchTurnaMapUri(_turnaGoogleMapsWebUri(payload));
}

Future<void> showTurnaLocationMapChooser(
  BuildContext context,
  TurnaLocationPayload payload,
) async {
  final hasGoogleApp = await canLaunchUrl(_turnaGoogleMapsAppUri(payload));
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Platform.isIOS)
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Apple Haritalar'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await openTurnaLocationInMaps(
                    payload,
                    preferredApp: TurnaExternalMapApp.apple,
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: Text(hasGoogleApp ? 'Google Maps' : 'Google Maps (web)'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await openTurnaLocationInMaps(
                  payload,
                  preferredApp: TurnaExternalMapApp.google,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('Tarayıcıda aç'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await openTurnaLocationInMaps(
                  payload,
                  preferredApp: TurnaExternalMapApp.browser,
                );
              },
            ),
          ],
        ),
      );
    },
  );
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
  const _TurnaLocationMapPreview({required this.payload, this.height = 168});

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
          key: ValueKey(
            'location-preview:${payload.latitude.toStringAsFixed(5)}:${payload.longitude.toStringAsFixed(5)}:${payload.updatedAt ?? ''}:${payload.endedAt ?? ''}',
          ),
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

class _TurnaMapZoomButton extends StatelessWidget {
  const _TurnaMapZoomButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: const Color(0xFF17212B)),
        ),
      ),
    );
  }
}

class TurnaLocationViewerPage extends StatefulWidget {
  const TurnaLocationViewerPage({
    super.key,
    required this.initialPayload,
    this.messageId,
    this.liveClient,
  });

  final TurnaLocationPayload initialPayload;
  final String? messageId;
  final TurnaSocketClient? liveClient;

  @override
  State<TurnaLocationViewerPage> createState() =>
      _TurnaLocationViewerPageState();
}

class _TurnaLocationViewerPageState extends State<TurnaLocationViewerPage> {
  late TurnaLocationPayload _payload = widget.initialPayload;
  final MapController _mapController = MapController();
  double _currentZoom = 16;
  bool _followLivePosition = true;

  @override
  void initState() {
    super.initState();
    widget.liveClient?.addListener(_handleLiveMessageUpdated);
    _handleLiveMessageUpdated();
  }

  @override
  void dispose() {
    widget.liveClient?.removeListener(_handleLiveMessageUpdated);
    super.dispose();
  }

  void _handleLiveMessageUpdated() {
    final messageId = widget.messageId;
    final client = widget.liveClient;
    if (messageId == null || client == null) return;
    ChatMessage? target;
    for (final message in client.messages) {
      if (message.id == messageId) {
        target = message;
        break;
      }
    }
    if (target == null) return;
    final next = parseTurnaMessageText(target.text).location;
    if (next == null) return;
    if (_payload.latitude == next.latitude &&
        _payload.longitude == next.longitude &&
        _payload.updatedAt == next.updatedAt &&
        _payload.endedAt == next.endedAt) {
      return;
    }
    if (!mounted) return;
    setState(() => _payload = next);
    if (_followLivePosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(
          ll.LatLng(next.latitude, next.longitude),
          _currentZoom,
        );
      });
    }
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    final zoom = camera.zoom;
    if ((_currentZoom - zoom).abs() > 0.001) {
      _currentZoom = zoom;
    }
    if (hasGesture) {
      _followLivePosition = false;
    }
  }

  void _adjustZoom(double delta) {
    final nextZoom = (_currentZoom + delta).clamp(3.0, 19.0).toDouble();
    _currentZoom = nextZoom;
    _followLivePosition = false;
    _mapController.move(
      ll.LatLng(_payload.latitude, _payload.longitude),
      nextZoom,
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final textColor = Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFF101416),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(payload.displayTitle),
        actions: [
          IconButton(
            onPressed: () => showTurnaLocationMapChooser(context, payload),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: ll.LatLng(
                      payload.latitude,
                      payload.longitude,
                    ),
                    initialZoom: _currentZoom,
                    onPositionChanged: _handlePositionChanged,
                  ),
                  children: [
                    buildTurnaStadiaTileLayer(),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: ll.LatLng(payload.latitude, payload.longitude),
                          width: 40,
                          height: 40,
                          child: _TurnaMapMarker(live: payload.live),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 18,
                  child: Column(
                    children: [
                      _TurnaMapZoomButton(
                        icon: Icons.add_rounded,
                        onPressed: () => _adjustZoom(1),
                      ),
                      const SizedBox(height: 10),
                      _TurnaMapZoomButton(
                        icon: Icons.remove_rounded,
                        onPressed: () => _adjustZoom(-1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              decoration: const BoxDecoration(
                color: Color(0xFF11181D),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (payload.live)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: payload.isLiveActive
                            ? TurnaColors.success.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        payload.isLiveActive
                            ? 'Canlı takip açık'
                            : 'Canlı konum sona erdi',
                        style: TextStyle(
                          color: payload.isLiveActive
                              ? TurnaColors.success
                              : Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (payload.live) const SizedBox(height: 12),
                  Text(
                    payload.displayTitle,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    payload.displaySubtitle,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.78),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatTurnaLocationCoordinates(
                      payload.latitude,
                      payload.longitude,
                    ),
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.62),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () =>
                        showTurnaLocationMapChooser(context, payload),
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('Haritalarda aç'),
                  ),
                ],
              ),
            ),
          ),
        ],
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
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
          title: 'Canlı konum',
          live: true,
          liveId:
              '${now.millisecondsSinceEpoch}-${center.latitude}-${center.longitude}',
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
        'Mevcut konumu gönder',
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
          child: const Text('İptal'),
        ),
        title: const Text('Konum gönder'),
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
                hintText: 'Arama yapın/adres girin',
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
                            child:
                                center == null ||
                                    !TurnaAppConfig.hasStadiaMapsKey
                                ? Center(
                                    child: _locating
                                        ? const CircularProgressIndicator()
                                        : Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Text(
                                              _error ??
                                                  'Harita için Stadia anahtarı veya konum bilgisi gerekli.',
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
                          label: const Text('Canlı konumu paylaş'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Yakındaki yerler',
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
                                  title: Text('Yakındaki yerler aranıyor...'),
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
                                  title: Text('Aranıyor...'),
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
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                  ),
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
      title: 'Canlı konum',
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
              DateTime.tryParse(
                share.expiresAt,
              )?.isBefore(DateTime.now().toUtc()) ==
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
              notificationText: 'Canlı konum paylaşımı sürüyor.',
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

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
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
      title: 'Canlı konum',
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
    _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () async {
      final expiredIds = _sharesByMessageId.values
          .where(
            (share) =>
                DateTime.tryParse(
                  share.expiresAt,
                )?.isBefore(DateTime.now().toUtc()) ==
                true,
          )
          .map((share) => share.messageId)
          .toList();
      for (final messageId in expiredIds) {
        await stopShare(messageId);
      }
      _scheduleExpiryCheck();
    });
  }
}

class _TurnaLocationMessageCard extends StatelessWidget {
  const _TurnaLocationMessageCard({
    required this.payload,
    required this.mine,
    this.messageId,
    this.liveClient,
    this.overlayFooter,
    this.onStopShare,
  });

  final TurnaLocationPayload payload;
  final bool mine;
  final String? messageId;
  final TurnaSocketClient? liveClient;
  final Widget? overlayFooter;
  final Future<void> Function()? onStopShare;

  @override
  Widget build(BuildContext context) {
    final cardColor = mine ? TurnaColors.chatOutgoing : Colors.white;
    final textColor = mine
        ? TurnaColors.chatOutgoingText
        : TurnaColors.chatIncomingText;
    final showOverlayFooter = overlayFooter != null;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TurnaLocationViewerPage(
              initialPayload: payload,
              messageId: messageId,
              liveClient: liveClient,
            ),
          ),
        );
      },
      child: Container(
        width: 250,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: payload.live
                ? TurnaColors.success.withValues(alpha: mine ? 0.24 : 0.28)
                : (mine
                      ? TurnaColors.chatOutgoing.withValues(alpha: 0.92)
                      : TurnaColors.border),
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  child: _TurnaLocationMapPreview(
                    payload: payload,
                    height: 150,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    10,
                    12,
                    showOverlayFooter ? 46 : 12,
                  ),
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
                            icon: const Icon(
                              Icons.stop_circle_outlined,
                              size: 18,
                            ),
                            label: const Text('Canlı konumu durdur'),
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
            if (showOverlayFooter)
              Positioned(right: 8, bottom: 8, child: overlayFooter!),
          ],
        ),
      ),
    );
  }
}
