import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../app.dart';
import '../models/place.dart';
import '../models/road_report.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
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
  int _lastAnnouncedProgressIndex = -1;

  LatLng get _currentLocation => _position == null
      ? _netherlandsCenter
      : LatLng(_position!.latitude, _position!.longitude);

  double get _speedKmh {
    final speed = (_position?.speed ?? 0) * 3.6;
    return speed.isFinite ? math.max(0, speed) : 0;
  }

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _searchController.dispose();
    _speechService.dispose();
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
      _mapController.move(_currentLocation, 15);
      await _positionSubscription?.cancel();
      _positionSubscription = _locationService.watchPosition().listen(
        _onPositionChanged,
        onError: (Object error) {
          if (!mounted) return;
          setState(() => _locationError = 'GPS-signaal tijdelijk niet beschikbaar.');
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationLoading = false;
        _locationError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onPositionChanged(Position position) {
    if (!mounted) return;
    setState(() {
      _position = position;
      _locationError = null;
    });

    if (_navigating && _route != null) {
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

  Future<void> _selectDestination(Place place) async {
    FocusScope.of(context).unfocus();
    if (_position == null) {
      await _initializeLocation();
    }
    if (!mounted) return;

    final position = _position;
    if (position == null) {
      _showMessage('Zet GPS aan om een fietsroute te berekenen.');
      return;
    }

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
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _routeLoading = false;
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
      _lastAnnouncedProgressIndex = -1;
    });
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
    });
    await _speechService.stop();
  }

  void _checkRouteProgress() {
    final route = _route;
    final position = _position;
    if (route == null || position == null || route.points.isEmpty) return;

    final current = LatLng(position.latitude, position.longitude);
    final distance = const Distance();
    var nearestDistance = double.infinity;
    var nearestIndex = 0;

    for (var index = 0; index < route.points.length; index++) {
      final meters = distance.as(LengthUnit.Meter, current, route.points[index]);
      if (meters < nearestDistance) {
        nearestDistance = meters;
        nearestIndex = index;
      }
    }

    if (nearestDistance > 100 && !_offRoute) {
      setState(() => _offRoute = true);
      _speechService.announce(
        'Let op. Je lijkt van de geplande fietsroute af te wijken.',
      );
    } else if (nearestDistance <= 55 && _offRoute) {
      setState(() => _offRoute = false);
    }

    if (nearestIndex > _lastAnnouncedProgressIndex &&
        nearestIndex == route.points.length - 1) {
      _lastAnnouncedProgressIndex = nearestIndex;
      _speechService.announce('Je hebt je bestemming bijna bereikt.');
    }
  }

  double get _remainingMeters {
    final route = _route;
    final position = _position;
    if (route == null || position == null || route.points.isEmpty) {
      return _route?.distanceMeters ?? 0;
    }

    final current = LatLng(position.latitude, position.longitude);
    const distance = Distance();
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < route.points.length; index++) {
      final meters = distance.as(LengthUnit.Meter, current, route.points[index]);
      if (meters < nearestDistance) {
        nearestDistance = meters;
        nearestIndex = index;
      }
    }

    var remaining = 0.0;
    for (var index = nearestIndex + 1; index < route.points.length; index++) {
      remaining += distance.as(
        LengthUnit.Meter,
        route.points[index - 1],
        route.points[index],
      );
    }
    return remaining;
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
              const Text(
                'Kies het soort melding. De melding wordt in deze eerste versie lokaal opgeslagen.',
                style: TextStyle(color: Colors.black54),
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
      _addReport(selectedType);
    }
  }

  void _addReport(ReportType type) {
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

    setState(() {
      _reports = [report, ..._reports];
      _selectedTab = 1;
    });

    _showMessage(
      'Melding opgeslagen op dit toestel. Andere fietsers zien deze nog niet.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
          options: MapOptions(
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
            RichAttributionWidget(
              attributions: const [
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
                              if (value.trim().length < 3 &&
                                  _suggestions.isNotEmpty) {
                                setState(() => _suggestions = []);
                              }
                            },
                            decoration: const InputDecoration(
                              hintText: 'Waar wil je naartoe fietsen?',
                              filled: false,
                              contentPadding: EdgeInsets.symmetric(vertical: 17),
                              border: InputBorder.none,
                            ),
                          ),
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
                      separatorBuilder: (_, __) =>
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
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: const [
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
    final minutes = (remaining / 1000 / 15 * 60).ceil();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: FietsRadarApp.lime.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.directions_bike_rounded,
                    color: FietsRadarApp.forest,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _navigating
                            ? (_offRoute ? 'Route controleren' : 'Navigatie actief')
                            : 'Fietsroute gevonden',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
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
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: FietsRadarApp.forest,
                      ),
                    ),
                    Text(
                      '$minutes min',
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            if (_offRoute)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFD97706), size: 18),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Je lijkt buiten de geplande route te fietsen.',
                        style: TextStyle(
                          color: Color(0xFF9A5B00),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 13),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _navigating
                      ? const Color(0xFFB42318)
                      : FietsRadarApp.forest,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _navigating ? _stopNavigation : _startNavigation,
                icon: Icon(
                  _navigating ? Icons.stop_rounded : Icons.navigation_rounded,
                ),
                label: Text(
                  _navigating ? 'Navigatie stoppen' : 'Start navigatie',
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
              '${_reports.length} melding(en) op dit toestel',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 13),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2E6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Let op: meldingen worden in deze eerste versie alleen lokaal bewaard. Ze worden nog niet met andere fietsers gedeeld.',
                style: TextStyle(
                  color: FietsRadarApp.forest,
                  fontSize: 12,
                  height: 1.4,
                ),
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
                      separatorBuilder: (_, __) =>
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
                              'Geplaatst om ${formatClock(report.createdAt)} · GPS-locatie',
                            ),
                            trailing: IconButton(
                              tooltip: 'Toon op kaart',
                              onPressed: () {
                                setState(() => _selectedTab = 0);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _mapController.move(report.location, 17);
                                });
                              },
                              icon: const Icon(Icons.map_outlined),
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
