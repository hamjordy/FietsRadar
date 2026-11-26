import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../models/place.dart';
import '../models/road_report.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/report_storage_service.dart';
import '../services/shared_report_service.dart';
import '../services/speech_service.dart';
import '../utils/formatters.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const LatLng _netherlandsCenter = LatLng(52.0907, 5.1214);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final LocationService _locationService = LocationService();
  final RouteService _routeService = RouteService();
  final SpeechService _speechService = SpeechService();
  final ReportStorageService _reportStorageService = ReportStorageService();
  final SharedReportService _sharedReportService = SharedReportService();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  static const String _favoritePlacesKey = 'fietsradar.favorite_places.v1';
  static const String _recentPlacesKey = 'fietsradar.recent_places.v1';
  List<Place> _favoritePlaces = [];
  List<Place> _recentPlaces = [];

  static const String _routeProfileKey = 'fietsradar.route_profile.v1';
  String _routeProfile = 'trekking';
  static const Map<String, String> _routeProfiles = {
    'trekking': 'Gebalanceerd',
    'fastbike': 'Vlot doorfietsen',
    'safety': 'Veiligere route',
  };

  Future<void>? _reportsLoadFuture;
  StreamSubscription<List<RoadReport>>? _sharedReportsSubscription;
  Timer? _reportExpiryTimer;
  List<RoadReport> _sharedReports = [];
  bool _sharingConnecting = false;
  bool _sharingActive = false;
  String? _sharingError;

  StreamSubscription<Position>? _positionSubscription;
  Position? _position;
  List<Place> _suggestions = [];
  List<RoadReport> _reports = [];
  BikeRoute? _route;
  Place? _destination;

  bool _locationLoading = true;
  bool _searchLoading = false;
  bool _routeLoading = false;
  bool _navigating = false;
  bool _offRoute = false;
  int _selectedTab = 0;
  String? _locationError;
  String? _searchError;
  int _instructionCursor = 0;
  int? _lastApproachInstructionIndex;
  int? _lastSpokenInstructionIndex;
  int _offRouteUpdates = 0;
  bool _rerouting = false;
  bool _backgroundTrackingActive = false;
  bool _arrivalAnnounced = false;
  DateTime? _lastRerouteAttempt;

  LatLng get _currentLocation => _position == null
      ? _netherlandsCenter
      : LatLng(_position!.latitude, _position!.longitude);

  double get _speedKmh {
    final speed = (_position?.speed ?? 0) * 3.6;
    return speed.isFinite ? math.max(0.0, speed).toDouble() : 0.0;
  }

  @override
  void initState() {
    super.initState();
    _reportsLoadFuture = _loadReports();
    unawaited(_loadSavedPlaces());
    unawaited(_loadRouteProfile());
    unawaited(_connectSharedReports());
    _reportExpiryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _removeExpiredSharedReports(),
    );
    _initializeLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _sharedReportsSubscription?.cancel();
    _reportExpiryTimer?.cancel();
    _searchController.dispose();
    unawaited(_speechService.dispose());
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    try {
      final position = await _locationService.determinePosition();
      if (!mounted) return;
      setState(() {
        _position = position;
        _locationLoading = false;
        _locationError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(_currentLocation, 15);
      });
      await _startPositionTracking();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationLoading = false;
        _locationError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _startPositionTracking({
    bool keepAliveInBackground = false,
  }) async {
    await _positionSubscription?.cancel();
    if (!mounted) return;

    _positionSubscription = _locationService
        .watchPosition(keepAliveInBackground: keepAliveInBackground)
        .listen(
      _onPositionChanged,
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _locationError = keepAliveInBackground
              ? 'Achtergrond-GPS kon niet worden gestart.'
              : 'GPS-signaal tijdelijk niet beschikbaar.';
          if (keepAliveInBackground) {
            _backgroundTrackingActive = false;
            _navigating = false;
            _offRoute = false;
          }
        });

        if (keepAliveInBackground) {
          _showMessage(
            'Achtergrond-GPS kon niet starten. De navigatie is gestopt. '
            'Controleer je locatietoestemming en probeer opnieuw.',
          );
          unawaited(
            _speechService.announce(
              'De achtergrond GPS kon niet starten. De navigatie is gestopt.',
            ),
          );
          unawaited(_startPositionTracking());
        }
      },
    );

    setState(() {
      _backgroundTrackingActive = keepAliveInBackground &&
          defaultTargetPlatform == TargetPlatform.android;
    });
  }

  void _onPositionChanged(Position position) {
    if (!mounted) return;
    setState(() {
      _position = position;
      _locationError = null;
    });

    if (_navigating && _route != null) {
      // Keep the rider centered on the map while turn-by-turn navigation runs.
      _mapController.move(_currentLocation, 16);
      _checkRouteProgress();
    }
  }

  Future<void> _searchPlaces(String value) async {
    if (value.trim().length < 3) {
      setState(() {
        _suggestions = [];
        _searchError = null;
      });
      return;
    }

    setState(() {
      _searchLoading = true;
      _searchError = null;
    });

    try {
      final places = await _routeService.searchPlaces(value);
      if (!mounted) return;
      setState(() {
        _suggestions = places;
        _searchLoading = false;
        if (places.isEmpty) {
          _searchError = 'Geen Nederlandse locaties gevonden.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searchLoading = false;
        _searchError = error.toString().replaceFirst('Exception: ', '');
        _suggestions = [];
      });
    }
  }

  Future<void> _loadRouteProfile() async {
    try {
      final saved = await _preferences.getString(_routeProfileKey);
      if (!mounted || saved == null || !_routeProfiles.containsKey(saved)) return;
      setState(() => _routeProfile = saved);
    } catch (_) {}
  }

  Future<void> _showRoutePreferences() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 18),
                const Text('Routevoorkeuren', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: FietsRadarApp.forest)),
                const SizedBox(height: 5),
                const Text('Kies hoe FietsRadar jouw fietsroute berekent.', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 14),
                RadioGroup<String>(
                  groupValue: _routeProfile,
                  onChanged: (value) {
                    if (value == null) return;
                    Navigator.pop(sheetContext, value);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _routeProfiles.entries.map((entry) => RadioListTile<String>(
                      value: entry.key,
                      activeColor: FietsRadarApp.forest,
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(entry.key == 'trekking' ? 'Een goede balans tussen comfort en afstand.' : entry.key == 'fastbike' ? 'Gericht op vlot en efficiënt doorfietsen.' : 'Geeft meer prioriteit aan rustigere fietsroutes.'),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Sluiten'))),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !_routeProfiles.containsKey(selected)) return;
    setState(() => _routeProfile = selected);
    try {
      await _preferences.setString(_routeProfileKey, selected);
    } catch (_) {
      _showMessage('Routevoorkeur kon niet worden opgeslagen.');
    }
    if (_destination != null && !_navigating) {
      final destination = _destination!;
      await _selectDestination(destination);
    } else {
      _showMessage('Routevoorkeur ingesteld op ${_routeProfiles[selected]}.');
    }
  }

  Future<void> _loadSavedPlaces() async {
    try {
      final favoritesRaw = await _preferences.getString(_favoritePlacesKey);
      final recentRaw = await _preferences.getString(_recentPlacesKey);
      List<Place> decode(String? raw) {
        if (raw == null || raw.isEmpty) return [];
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! List) return [];
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((item) => Place(
                    name: item['name'] as String,
                    displayName: item['displayName'] as String,
                    latitude: (item['latitude'] as num).toDouble(),
                    longitude: (item['longitude'] as num).toDouble(),
                  ))
              .toList();
        } catch (_) {
          return [];
        }
      }

      if (!mounted) return;
      setState(() {
        _favoritePlaces = decode(favoritesRaw);
        _recentPlaces = decode(recentRaw);
      });
    } catch (_) {
      // Saved destinations are optional; the map remains usable without them.
    }
  }

  Future<void> _savePlaces() async {
    Map<String, dynamic> encode(Place place) => {
          'name': place.name,
          'displayName': place.displayName,
          'latitude': place.latitude,
          'longitude': place.longitude,
        };
    await _preferences.setString(
      _favoritePlacesKey,
      jsonEncode(_favoritePlaces.map(encode).toList()),
    );
    await _preferences.setString(
      _recentPlacesKey,
      jsonEncode(_recentPlaces.map(encode).toList()),
    );
  }

  bool _isFavorite(Place place) => _favoritePlaces.any(
        (saved) =>
            saved.latitude == place.latitude &&
            saved.longitude == place.longitude,
      );

  Future<void> _toggleFavorite(Place place) async {
    setState(() {
      if (_isFavorite(place)) {
        _favoritePlaces.removeWhere((saved) =>
            saved.latitude == place.latitude &&
            saved.longitude == place.longitude);
      } else {
        _favoritePlaces.insert(0, place);
      }
    });
    try {
      await _savePlaces();
      _showMessage(_isFavorite(place)
          ? '${place.name} toegevoegd aan favorieten.'
          : '${place.name} verwijderd uit favorieten.');
    } catch (_) {
      _showMessage('Favorieten konden niet worden opgeslagen.');
    }
  }

  Future<void> _rememberRecentPlace(Place place) async {
    _recentPlaces.removeWhere((saved) =>
        saved.latitude == place.latitude &&
        saved.longitude == place.longitude);
    _recentPlaces.insert(0, place);
    if (_recentPlaces.length > 8) {
      _recentPlaces = _recentPlaces.take(8).toList();
    }
    try {
      await _savePlaces();
    } catch (_) {
      // Recent destinations are a convenience, not required for navigation.
    }
  }

  Widget _buildQuickDestinations() {
    if (_favoritePlaces.isEmpty && _recentPlaces.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget destinationChips(List<Place> places, IconData icon) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: places
              .map((place) => Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ActionChip(
                      avatar: Icon(icon, size: 16, color: FietsRadarApp.forest),
                      label: Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _selectDestination(place),
                    ),
                  ))
              .toList(),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_favoritePlaces.isNotEmpty) ...[
            const Text('Favorieten',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            destinationChips(_favoritePlaces.take(8).toList(), Icons.star_rounded),
          ],
          if (_recentPlaces.isNotEmpty) ...[
            const Text('Recent',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            destinationChips(_recentPlaces.take(5).toList(), Icons.history_rounded),
          ],
        ],
      ),
    );
  }

  Future<void> _selectDestination(Place place) async {
    FocusScope.of(context).unfocus();
    if (_navigating) {
      await _stopNavigation();
    }
    if (_position == null) {
      await _initializeLocation();
    }
    if (!mounted) return;

    final position = _position;
    if (position == null) {
      _showMessage('Zet GPS aan om een fietsroute te berekenen.');
      return;
    }

    await _rememberRecentPlace(place);
    if (!mounted) return;

    setState(() {
      _destination = place;
      _suggestions = [];
      _searchController.text = place.name;
      _routeLoading = true;
      _route = null;
      _navigating = false;
    });

    try {
      final route = await _routeService.getBikeRoute(
        start: LatLng(position.latitude, position.longitude),
        destination: place.location,
        profile: _routeProfile,
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _routeLoading = false;
        _offRoute = false;
        _offRouteUpdates = 0;
        _instructionCursor = 0;
        _lastApproachInstructionIndex = null;
        _lastSpokenInstructionIndex = null;
        _arrivalAnnounced = false;
      });
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(route.points),
          padding: const EdgeInsets.fromLTRB(44, 150, 44, 170),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _routeLoading = false;
        _destination = null;
      });
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _startNavigation() async {
    if (_route == null || _destination == null) return;
    setState(() {
      _navigating = true;
      _offRoute = false;
      _offRouteUpdates = 0;
      _instructionCursor = 0;
      _lastApproachInstructionIndex = null;
      _lastSpokenInstructionIndex = null;
      _arrivalAnnounced = false;
    });
    // Start the foreground location service while the app is visible. Android
    // can then keep the user-initiated navigation session alive with the
    // persistent notification when the screen is turned off.
    await _startPositionTracking(keepAliveInBackground: true);
    if (!mounted || !_navigating) return;
    await _speechService.announce(
      'FietsRadar navigatie gestart. '
      'Je route is ${formatDistance(_route!.distanceMeters)}. '
      'Volg de route op de kaart en let op het verkeer.',
    );
  }

  Future<void> _stopNavigation() async {
    setState(() {
      _navigating = false;
      _offRoute = false;
      _backgroundTrackingActive = false;
      _offRouteUpdates = 0;
    });
    await _speechService.stop();
    // Stopping navigation removes the ongoing foreground notification and
    // returns location updates to normal foreground-only tracking.
    await _startPositionTracking();
  }

  int _nearestRouteIndex(BikeRoute route, LatLng current) {
    const distance = Distance();
    var nearestIndex = 0;
    var nearestDistance = double.infinity;

    for (var index = 0; index < route.points.length; index++) {
      final meters = distance.as(
        LengthUnit.Meter,
        current,
        route.points[index],
      );
      if (meters < nearestDistance) {
        nearestDistance = meters;
        nearestIndex = index;
      }
    }
    return nearestIndex;
  }

  double _distanceAlongRoute(BikeRoute route, int fromIndex, int toIndex) {
    if (route.points.length < 2 || toIndex <= fromIndex) return 0;
    const distance = Distance();
    final start = fromIndex.clamp(0, route.points.length - 1).toInt();
    final end = toIndex.clamp(0, route.points.length - 1).toInt();
    var meters = 0.0;

    for (var index = start + 1; index <= end; index++) {
      meters += distance.as(
        LengthUnit.Meter,
        route.points[index - 1],
        route.points[index],
      );
    }
    return meters;
  }

  RouteInstruction? get _nextInstruction {
    final route = _route;
    if (route == null || route.instructions.isEmpty) return null;
    final index = _navigating ? _instructionCursor : 0;
    if (index >= route.instructions.length) return null;
    return route.instructions[index];
  }

  double get _metersToNextInstruction {
    final route = _route;
    final position = _position;
    final instruction = _nextInstruction;
    if (route == null || position == null || instruction == null) return 0;

    final nearestIndex = _nearestRouteIndex(
      route,
      LatLng(position.latitude, position.longitude),
    );
    return _distanceAlongRoute(route, nearestIndex, instruction.pointIndex);
  }

  void _checkRouteProgress() {
    final route = _route;
    final position = _position;
    if (route == null || position == null || route.points.isEmpty) return;

    // Ignore poor GPS fixes: they should not trigger a false reroute or a wrong turn.
    if (position.accuracy > 55) return;

    final current = LatLng(position.latitude, position.longitude);
    const distance = Distance();
    final nearestIndex = _nearestRouteIndex(route, current);
    final nearestDistance = distance.as(
      LengthUnit.Meter,
      current,
      route.points[nearestIndex],
    );

    if (nearestDistance > 90) {
      _offRouteUpdates++;
      if (_offRouteUpdates >= 2 && !_offRoute) {
        setState(() => _offRoute = true);
      }

      final lastAttempt = _lastRerouteAttempt;
      final retryAllowed = lastAttempt == null ||
          DateTime.now().difference(lastAttempt) > const Duration(seconds: 20);
      if (_offRouteUpdates >= 2 && !_rerouting && retryAllowed) {
        unawaited(_recalculateRoute());
      }
      return;
    }

    _offRouteUpdates = 0;
    if (_offRoute && !_rerouting) {
      setState(() => _offRoute = false);
    }

    while (_instructionCursor < route.instructions.length &&
        nearestIndex > route.instructions[_instructionCursor].pointIndex + 5) {
      _instructionCursor++;
      _lastApproachInstructionIndex = null;
      _lastSpokenInstructionIndex = null;
    }

    final instruction = _nextInstruction;
    if (instruction != null) {
      final metersToTurn = _distanceAlongRoute(
        route,
        nearestIndex,
        instruction.pointIndex,
      );
      if (metersToTurn <= 30 &&
          _lastSpokenInstructionIndex != _instructionCursor) {
        _lastSpokenInstructionIndex = _instructionCursor;
        _lastApproachInstructionIndex = _instructionCursor;
        unawaited(_speechService.announce('Nu: ${instruction.spokenText}.'));
      } else if (metersToTurn > 30 &&
          metersToTurn <= 180 &&
          _lastApproachInstructionIndex != _instructionCursor) {
        _lastApproachInstructionIndex = _instructionCursor;
        final roundedMeters = (metersToTurn / 10).round() * 10;
        unawaited(
          _speechService.announce(
            'Over ongeveer $roundedMeters meter, ${instruction.spokenText}.',
          ),
        );
      }
    }

    final remaining = _distanceAlongRoute(
      route,
      nearestIndex,
      route.points.length - 1,
    );
    final destinationDistance = distance.as(
      LengthUnit.Meter,
      current,
      route.points.last,
    );
    if (remaining <= 20 &&
        destinationDistance <= 30 &&
        !_arrivalAnnounced) {
      _arrivalAnnounced = true;
      setState(() {});
      unawaited(
        _speechService.announce('Je bent aangekomen op je bestemming.'),
      );
    }
  }

  Future<void> _recalculateRoute() async {
    final destination = _destination;
    final position = _position;
    if (!_navigating || destination == null || position == null || _rerouting) {
      return;
    }

    _lastRerouteAttempt = DateTime.now();
    setState(() => _rerouting = true);
    await _speechService.announce(
      'Je bent van de route afgeweken. Ik bereken een nieuwe fietsroute.',
    );

    try {
      final route = await _routeService.getBikeRoute(
        start: LatLng(position.latitude, position.longitude),
        destination: destination.location,
        profile: _routeProfile,
      );
      if (!mounted) return;

      setState(() {
        _route = route;
        _rerouting = false;
        _offRoute = false;
        _offRouteUpdates = 0;
        _instructionCursor = 0;
        _lastApproachInstructionIndex = null;
        _lastSpokenInstructionIndex = null;
        _arrivalAnnounced = false;
      });

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(route.points),
          padding: const EdgeInsets.fromLTRB(44, 150, 44, 170),
        ),
      );
      await _speechService.announce(
        'De nieuwe fietsroute is klaar. ${formatDistance(route.distanceMeters)} naar ${destination.name}.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _rerouting = false);
      _showMessage(
        'Nieuwe route berekenen is niet gelukt. Controleer je internetverbinding.',
      );
      await _speechService.announce(
        'Het opnieuw berekenen van de route is niet gelukt. Volg de kaart voorzichtig.',
      );
    }
  }

  double get _remainingMeters {
    final route = _route;
    final position = _position;
    if (route == null || position == null || route.points.isEmpty) {
      return _route?.distanceMeters ?? 0;
    }

    final nearestIndex = _nearestRouteIndex(
      route,
      LatLng(position.latitude, position.longitude),
    );
    return _distanceAlongRoute(route, nearestIndex, route.points.length - 1);
  }

  Future<void> _showReportSheet() async {
    final selectedType = await showModalBottomSheet<ReportType>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Wat zie je onderweg?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _sharingActive
                    ? 'Deze melding wordt met andere FietsRadar-gebruikers gedeeld.'
                    : 'De melding wordt op dit toestel bewaard. Online delen is nog niet actief.',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              for (final type in ReportType.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: type.color.withValues(alpha: 0.12),
                    child: Icon(type.icon, color: type.color),
                  ),
                  title: Text(
                    type.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(type.description),
                  onTap: () => Navigator.pop(context, type),
                ),
            ],
          ),
        ),
      ),
    );

    if (selectedType != null) {
      await _addReport(selectedType);
    }
  }

  List<RoadReport> _combineReports(
    Iterable<RoadReport> local,
    Iterable<RoadReport> shared,
  ) {
    final byId = <String, RoadReport>{};
    for (final report in [...local, ...shared]) {
      byId[report.id] = report;
    }
    final combined = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return combined;
  }

  Future<void> _loadReports() async {
    try {
      final savedReports = await _reportStorageService.loadReports();
      if (!mounted) return;
      setState(() {
        _reports = _combineReports(savedReports, _sharedReports);
      });
    } catch (_) {
      if (mounted) {
        _showMessage('Opgeslagen meldingen konden niet worden geladen.');
      }
    }
  }

  Future<void> _connectSharedReports() async {
    if (!_sharedReportService.isConfigured) return;

    await _sharedReportsSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _sharingConnecting = true;
      _sharingError = null;
    });

    try {
      await _sharedReportService.ensureSignedIn();
      if (!mounted) return;
      _sharedReportsSubscription = _sharedReportService.watchReports().listen(
        (reports) {
          if (!mounted) return;
          _sharedReports = reports;
          setState(() {
            _sharingConnecting = false;
            _sharingActive = true;
            _sharingError = null;
            _reports = _combineReports(
              _reports.where((report) => !report.isShared),
              _sharedReports,
            );
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _sharingConnecting = false;
            _sharingActive = false;
            _sharingError =
                'Live meldingen konden niet worden bijgewerkt. Controleer je verbinding.';
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sharingConnecting = false;
        _sharingActive = false;
        _sharingError =
            'Verbinden met gedeelde meldingen is niet gelukt. Probeer opnieuw.';
      });
    }
  }

  void _removeExpiredSharedReports() {
    final now = DateTime.now();
    final activeReports = _sharedReports
        .where((report) =>
            report.expiresAt == null || report.expiresAt!.isAfter(now))
        .toList();
    if (activeReports.length == _sharedReports.length || !mounted) return;
    _sharedReports = activeReports;
    setState(() {
      _reports = _combineReports(
        _reports.where((report) => !report.isShared),
        _sharedReports,
      );
    });
  }

  Future<void> _addReport(ReportType type) async {
    await _reportsLoadFuture;
    final position = _position;
    if (position == null) {
      _showMessage('Je GPS-locatie is nodig om een melding te plaatsen.');
      return;
    }

    final report = RoadReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: type,
      location: LatLng(position.latitude, position.longitude),
      createdAt: DateTime.now(),
    );
    final localReports = <RoadReport>[
      report,
      ..._reports.where((saved) => !saved.isShared),
    ];

    setState(() {
      _reports = _combineReports(localReports, _sharedReports);
      _selectedTab = 1;
    });

    try {
      await _reportStorageService.saveReports(localReports);
    } catch (_) {
      _showMessage(
        'Melding staat voorlopig alleen in deze sessie. Opslaan is mislukt.',
      );
      return;
    }

    if (_sharingActive) {
      try {
        final sharedReport =
            await _sharedReportService.publishReport(report);
        if (!mounted) return;
        _sharedReports = [
          sharedReport,
          ..._sharedReports.where((saved) => saved.id != sharedReport.id),
        ];
        final remainingLocal = localReports
            .where((saved) => saved.id != report.id)
            .toList();
        await _reportStorageService.saveReports(remainingLocal);
        setState(() {
          _reports = _combineReports(remainingLocal, _sharedReports);
        });
        _showMessage('Melding gedeeld met andere FietsRadar-gebruikers.');
      } catch (_) {
        _showMessage(
          'Melding lokaal opgeslagen. Online delen is niet gelukt; probeer later opnieuw.',
        );
      }
    } else {
      _showMessage(
        _sharedReportService.isConfigured
            ? 'Melding lokaal opgeslagen. Live delen is niet verbonden.'
            : 'Melding lokaal opgeslagen. Online delen is nog niet ingesteld.',
      );
    }
  }

  Future<void> _deleteReport(String reportId) async {
    RoadReport? target;
    for (final report in _reports) {
      if (report.id == reportId) {
        target = report;
        break;
      }
    }
    if (target == null) return;

    if (target.isShared) {
      if (target.ownerId != _sharedReportService.currentUserId) {
        _showMessage('Je kunt alleen je eigen gedeelde meldingen verwijderen.');
        return;
      }
      try {
        await _sharedReportService.deleteReport(reportId);
        _sharedReports =
            _sharedReports.where((report) => report.id != reportId).toList();
        if (!mounted) return;
        setState(() {
          _reports = _combineReports(
            _reports.where((report) => !report.isShared),
            _sharedReports,
          );
        });
        _showMessage('Gedeelde melding verwijderd.');
      } catch (_) {
        _showMessage('De gedeelde melding kon niet worden verwijderd.');
      }
      return;
    }

    final previousReports = List<RoadReport>.of(_reports);
    final localReports = _reports
        .where((report) => !report.isShared && report.id != reportId)
        .toList();
    setState(() {
      _reports = _combineReports(localReports, _sharedReports);
    });

    try {
      await _reportStorageService.saveReports(localReports);
      _showMessage('Melding verwijderd.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _reports = previousReports);
      _showMessage('Verwijderen kon niet worden opgeslagen.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showReportDetails(RoadReport report) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: report.type.color.withValues(alpha: 0.13),
                    child: Icon(report.type.icon, color: report.type.color, size: 27),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      report.type.label,
                      style: const TextStyle(
                        color: FietsRadarApp.forest,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                report.type.description,
                style: const TextStyle(color: Colors.black87, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 18, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(
                    'Gemeld om ${formatClock(report.createdAt)}',
                    style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    report.isShared ? Icons.public_rounded : Icons.phone_android_rounded,
                    size: 18,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    report.isShared ? 'Gedeeld met andere fietsers' : 'Alleen zichtbaar op dit toestel',
                    style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _mapController.move(report.location, 17);
                  },
                  icon: const Icon(Icons.center_focus_strong_rounded),
                  label: const Text('Toon melding op kaart'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_position != null) {
      markers.add(
        Marker(
          point: _currentLocation,
          width: 48,
          height: 48,
          child: Container(
            decoration: BoxDecoration(
              color: FietsRadarApp.forest,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const Icon(Icons.pedal_bike, color: Colors.white, size: 25),
          ),
        ),
      );
    }

    final destination = _destination;
    if (destination != null) {
      markers.add(
        Marker(
          point: destination.location,
          width: 42,
          height: 50,
          child: const Icon(
            Icons.location_on,
            color: Color(0xFFDC3D45),
            size: 44,
          ),
        ),
      );
    }

    for (final report in _reports) {
      markers.add(
        Marker(
          point: report.location,
          width: 38,
          height: 38,
          child: GestureDetector(
            onTap: () => _showReportDetails(report),
            child: Container(
              decoration: BoxDecoration(
                color: report.type.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 7,
                  ),
                ],
              ),
              child: Icon(report.type.icon, color: Colors.white, size: 19),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildMapView() {
    final route = _route;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: _netherlandsCenter,
            initialZoom: 7.5,
            minZoom: 4,
            maxZoom: 19,
          ),
          children: [
            TileLayer(
              urlTemplate: const String.fromEnvironment(
                'FIETSRADAR_TILE_URL',
                defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              userAgentPackageName: 'nl.fietsradar.fietsradar',
            ),
            if (route != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route.points,
                    strokeWidth: 7,
                    color: FietsRadarApp.forest.withValues(alpha: 0.18),
                  ),
                  Polyline(
                    points: route.points,
                    strokeWidth: 4,
                    color: const Color(0xFF358B5C),
                  ),
                ],
              ),
            MarkerLayer(markers: _buildMarkers()),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 8,
          left: 14,
          right: 14,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Material(
                  color: Colors.white,
                  elevation: 5,
                  shadowColor: Colors.black.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(19),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          color: FietsRadarApp.forest,
                          size: 25,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: _searchPlaces,
                            onChanged: (value) {
                              setState(() {
                                if (value.trim().length < 3) {
                                  _suggestions = [];
                                }
                                _searchError = null;
                              });
                            },
                            decoration: const InputDecoration(
                              hintText: 'Waar wil je naartoe fietsen?',
                              filled: false,
                              contentPadding: EdgeInsets.symmetric(vertical: 17),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Routevoorkeuren',
                          onPressed: _showRoutePreferences,
                          icon: const Icon(Icons.tune_rounded),
                          color: FietsRadarApp.forest,
                        ),
                        if (_searchLoading)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            tooltip: 'Zoeken',
                            onPressed: () =>
                                _searchPlaces(_searchController.text),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            color: FietsRadarApp.forest,
                          ),
                      ],
                    ),
                  ),
                ),
                if (_suggestions.isEmpty && _searchController.text.trim().isEmpty)
                  _buildQuickDestinations(),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 54),
                      itemBuilder: (context, index) {
                        final place = _suggestions[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.place_outlined,
                            color: FietsRadarApp.forest,
                          ),
                          title: Text(
                            place.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            place.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: _isFavorite(place)
                                ? 'Verwijder favoriet'
                                : 'Voeg toe aan favorieten',
                            onPressed: () => _toggleFavorite(place),
                            icon: Icon(
                              _isFavorite(place)
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: _isFavorite(place)
                                  ? const Color(0xFFE5A000)
                                  : Colors.black45,
                            ),
                          ),
                          onTap: () => _selectDestination(place),
                        );
                      },
                    ),
                  ),
                if (_searchError != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 7),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _searchError!,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 94,
          right: 16,
          child: _speedCard(),
        ),
        Positioned(
          right: 16,
          bottom: route == null ? 92 : 178,
          child: FloatingActionButton.small(
            heroTag: 'my-location',
            backgroundColor: Colors.white,
            foregroundColor: FietsRadarApp.forest,
            onPressed: () async {
              if (_position == null) {
                await _initializeLocation();
              } else {
                _mapController.move(_currentLocation, 16);
              }
            },
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
        Positioned(
          left: 15,
          bottom: route == null ? 18 : 176,
          child: FloatingActionButton.extended(
            heroTag: 'new-report',
            backgroundColor: FietsRadarApp.forest,
            foregroundColor: Colors.white,
            onPressed: _showReportSheet,
            icon: const Icon(Icons.add_alert_rounded),
            label: const Text('Melding'),
          ),
        ),
        if (_locationError != null)
          Positioned(
            left: 14,
            right: 14,
            bottom: route == null ? 82 : 235,
            child: Material(
              color: const Color(0xFFFFF3D6),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Row(
                  children: [
                    const Icon(Icons.gps_off_rounded, color: Color(0xFF8A5A00)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationError!,
                        style: const TextStyle(color: Color(0xFF654300)),
                      ),
                    ),
                    if (!_locationLoading)
                      TextButton(
                        onPressed: _initializeLocation,
                        child: const Text('Opnieuw'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_routeLoading)
          const Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'De beste fietsroute wordt berekend…',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (route != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: _routePanel(route),
          ),
      ],
    );
  }

  Widget _speedCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'SNELHEID',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 9,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            _position == null ? '—' : _speedKmh.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w900,
              color: FietsRadarApp.forest,
            ),
          ),
          const Text(
            'km/u',
            style: TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _routePanel(BikeRoute route) {
    final remaining = _navigating ? _remainingMeters : route.distanceMeters;
    final minutes = _navigating
        ? (remaining / 1000 / 15 * 60).ceil()
        : route.estimatedDuration.inMinutes;
    final instruction = _nextInstruction;
    final metersToTurn = _metersToNextInstruction;
    final progress = _navigating && route.distanceMeters > 0
        ? (1 - remaining / route.distanceMeters).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final turnIcon = instruction == null
        ? Icons.flag_rounded
        : instruction.command == 1
            ? Icons.arrow_upward_rounded
            : instruction.command == 13 || instruction.command == 14
                ? Icons.alt_route_rounded
                : instruction.command == 5 ||
                        instruction.command == 6 ||
                        instruction.command == 7 ||
                        instruction.command == 9 ||
                        instruction.command == 18
                    ? Icons.turn_right_rounded
                    : Icons.turn_left_rounded;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_navigating) ...[
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _arrivalAnnounced
                          ? const Color(0xFF358B5C)
                          : FietsRadarApp.forest,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      _arrivalAnnounced ? Icons.flag_rounded : turnIcon,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _arrivalAnnounced
                              ? 'Bestemming bereikt'
                              : instruction?.label ?? 'Volg de route naar je bestemming',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: FietsRadarApp.forest,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _arrivalAnnounced
                              ? 'Je bent aangekomen op je bestemming.'
                              : instruction == null
                                  ? 'Volgende aanwijzing'
                                  : 'Over ${formatDistance(metersToTurn)}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_rerouting && !_arrivalAnnounced)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: FietsRadarApp.lime.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.directions_bike_rounded,
                    color: FietsRadarApp.forest,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _navigating
                            ? (_arrivalAnnounced
                                ? 'Aangekomen'
                                : _offRoute
                                    ? 'Route controleren'
                                    : 'Je bent onderweg')
                            : 'Fietsroute gevonden',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _destination?.name ?? 'Bestemming',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatDistance(remaining),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: FietsRadarApp.forest,
                      ),
                    ),
                    Text(
                      _navigating ? 'nog $minutes min' : '$minutes min fietsen',
                      style: const TextStyle(color: Colors.black54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            if (_navigating) ...[
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ROUTEVOORTGANG',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                      color: FietsRadarApp.forest,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: FietsRadarApp.lime.withValues(alpha: 0.35),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    FietsRadarApp.forest,
                  ),
                ),
              ),
            ],
            if (_navigating && _backgroundTrackingActive)
              const Padding(
                padding: EdgeInsets.only(top: 9),
                child: Row(
                  children: [
                    Icon(Icons.screen_lock_portrait_rounded,
                        color: Color(0xFF358B5C), size: 15),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Navigatie blijft actief met je scherm uit',
                        style: TextStyle(
                          color: Color(0xFF358B5C),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_offRoute)
              const Padding(
                padding: EdgeInsets.only(top: 9),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFD97706), size: 17),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Je fietst buiten de geplande route. We zoeken een nieuwe route.',
                        style: TextStyle(
                          color: Color(0xFF9A5B00),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _navigating
                      ? const Color(0xFFB42318)
                      : FietsRadarApp.forest,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _navigating ? _stopNavigation : _startNavigation,
                icon: Icon(
                  _navigating ? Icons.stop_rounded : Icons.navigation_rounded,
                ),
                label: Text(
                  _navigating ? 'Navigatie stoppen' : 'Start navigatie',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Meldingen onderweg',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: FietsRadarApp.forest,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _sharingActive
                  ? '${_reports.length} actieve meldingen · live gedeeld'
                  : '${_reports.length} meldingen op dit toestel',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 13),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _sharingActive
                    ? const Color(0xFFEAF2E6)
                    : const Color(0xFFFFF3D6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _sharingActive
                        ? Icons.cell_tower_rounded
                        : Icons.cloud_off_rounded,
                    color: _sharingActive
                        ? FietsRadarApp.forest
                        : const Color(0xFF8A5A00),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sharingActive
                              ? 'Live meldingen actief'
                              : _sharingConnecting
                                  ? 'Verbinden met live meldingen…'
                                  : 'Live meldingen niet actief',
                          style: TextStyle(
                            color: _sharingActive
                                ? FietsRadarApp.forest
                                : const Color(0xFF654300),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _sharingActive
                              ? 'Meldingen van andere fietsers verschijnen automatisch. Eigen meldingen kun je verwijderen.'
                              : _sharedReportService.isConfigured
                                  ? (_sharingError ??
                                      'Je meldingen blijven lokaal totdat de verbinding is hersteld.')
                                  : 'De online backend moet nog worden ingesteld. Je meldingen blijven veilig lokaal bewaard.',
                          style: TextStyle(
                            color: _sharingActive
                                ? FietsRadarApp.forest
                                : const Color(0xFF654300),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        if (_sharedReportService.isConfigured &&
                            !_sharingActive &&
                            !_sharingConnecting)
                          TextButton(
                            onPressed: _connectSharedReports,
                            child: const Text('Opnieuw verbinden'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _reports.isEmpty
                  ? _emptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'Nog geen meldingen',
                      message:
                          'Zie je onderweg een obstakel of gevaarlijke plek? Plaats dan een melding op de kaart.',
                      buttonLabel: 'Melding plaatsen',
                      onPressed: _showReportSheet,
                    )
                  : ListView.separated(
                      itemCount: _reports.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final report = _reports[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 5,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  report.type.color.withValues(alpha: 0.12),
                              child: Icon(
                                report.type.icon,
                                color: report.type.color,
                              ),
                            ),
                            title: Text(
                              report.type.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${report.isShared ? 'Gedeeld' : 'Alleen op dit toestel'} · ${formatClock(report.createdAt)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Toon op kaart',
                                  onPressed: () {
                                    setState(() => _selectedTab = 0);
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      _mapController.move(report.location, 17);
                                    });
                                  },
                                  icon: const Icon(Icons.map_outlined),
                                ),
                                if (!report.isShared ||
                                    report.ownerId ==
                                        _sharedReportService.currentUserId)
                                  IconButton(
                                    tooltip: 'Melding verwijderen',
                                    onPressed: () => _deleteReport(report.id),
                                    icon: const Icon(Icons.delete_outline_rounded),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _showReportSheet,
                icon: const Icon(Icons.add_alert_rounded),
                label: const Text('Nieuwe melding plaatsen'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildRideView() {
    final route = _route;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mijn rit',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: FietsRadarApp.forest,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Je huidige fietsroute en ritgegevens',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            if (route == null)
              Expanded(
                child: _emptyState(
                  icon: Icons.route_rounded,
                  title: 'Nog geen route gepland',
                  message:
                      'Zoek een bestemming op de kaart om je fietsroute te berekenen.',
                  buttonLabel: 'Naar de kaart',
                  onPressed: () => setState(() => _selectedTab = 0),
                ),
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(19),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.route_rounded,
                            color: FietsRadarApp.forest,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Geplande fietsroute',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          if (_navigating)
                            const Chip(
                              avatar: Icon(Icons.circle, size: 9, color: Colors.green),
                              label: Text('Actief'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Text(
                        formatDistance(
                          _navigating ? _remainingMeters : route.distanceMeters,
                        ),
                        style: const TextStyle(
                          color: FietsRadarApp.forest,
                          fontWeight: FontWeight.w900,
                          fontSize: 34,
                        ),
                      ),
                      Text(
                        'naar ${_destination?.name ?? 'bestemming'}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const Divider(height: 28),
                      _detailRow(
                        Icons.schedule_rounded,
                        'Geschatte reistijd',
                        formatDuration(route.estimatedDuration),
                      ),
                      const SizedBox(height: 12),
                      _detailRow(
                        Icons.speed_rounded,
                        'Huidige snelheid',
                        _position == null
                            ? 'Geen GPS'
                            : '${_speedKmh.toStringAsFixed(0)} km/u',
                      ),
                      const SizedBox(height: 12),
                      _detailRow(
                        Icons.my_location_rounded,
                        'GPS-status',
                        _position == null ? 'Niet beschikbaar' : 'Verbonden',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => setState(() => _selectedTab = 0),
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Toon route op kaart'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _stopNavigation();
                    setState(() {
                      _route = null;
                      _destination = null;
                      _rerouting = false;
                      _offRouteUpdates = 0;
                      _instructionCursor = 0;
                      _searchController.clear();
                    });
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Route wissen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 19, color: Colors.black54),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: FietsRadarApp.lime.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(icon, size: 37, color: FietsRadarApp.forest),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildMapView(),
          _buildReportsView(),
          _buildRideView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Kaart',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Meldingen',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bike_outlined),
            selectedIcon: Icon(Icons.directions_bike_rounded),
            label: 'Mijn rit',
          ),
        ],
      ),
    );
  }
}
