import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/place.dart';

class BikeRoute {
  const BikeRoute({
    required this.points,
    required this.distanceMeters,
    required this.estimatedDuration,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final Duration estimatedDuration;
}

class RouteService {
  static const String _userAgent =
      'FietsRadar/0.1.0 (https://github.com/hamjordy/FietsRadar)';

  DateTime? _lastGeocodeRequest;

  Future<List<Place>> searchPlaces(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 3) {
      return const [];
    }

    // Public Nominatim servers ask clients to stay at or below one request per second.
    final previous = _lastGeocodeRequest;
    if (previous != null) {
      final elapsed = DateTime.now().difference(previous);
      if (elapsed < const Duration(seconds: 1)) {
        await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
      }
    }
    _lastGeocodeRequest = DateTime.now();

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'q': trimmedQuery,
        'format': 'jsonv2',
        'limit': '5',
        'countrycodes': 'nl',
        'accept-language': 'nl',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Locaties zoeken is tijdelijk niet beschikbaar.');
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Place.fromNominatim)
        .toList();
  }

  Future<BikeRoute> getBikeRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final uri = Uri.https(
      'brouter.de',
      '/brouter',
      {
        'lonlats':
            '${start.longitude},${start.latitude}|${destination.longitude},${destination.latitude}',
        'profile': 'trekking',
        'alternativeidx': '0',
        'format': 'geojson',
        'trackname': 'FietsRadar',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/geo+json, application/json',
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'De fietsroute kon niet worden berekend. Probeer het over een moment opnieuw.',
      );
    }

    final decoded = jsonDecode(response.body);
    final Map<String, dynamic> feature;

    if (decoded is Map<String, dynamic> &&
        decoded['type'] == 'FeatureCollection') {
      final features = decoded['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) {
        throw Exception('Er is geen fietsroute gevonden voor deze bestemming.');
      }
      feature = features.first as Map<String, dynamic>;
    } else if (decoded is Map<String, dynamic> &&
        decoded['type'] == 'Feature') {
      feature = decoded;
    } else {
      throw Exception('De routeprovider gaf een onbekend antwoord terug.');
    }

    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List<dynamic>?;
    if (coordinates == null || coordinates.length < 2) {
      throw Exception('De gevonden fietsroute bevat geen routepunten.');
    }

    final points = coordinates.map((coordinate) {
      final pair = coordinate as List<dynamic>;
      return LatLng(
        (pair[1] as num).toDouble(),
        (pair[0] as num).toDouble(),
      );
    }).toList();

    final distance = Distance();
    var totalMeters = 0.0;
    for (var index = 1; index < points.length; index++) {
      totalMeters += distance.as(
        LengthUnit.Meter,
        points[index - 1],
        points[index],
      );
    }

    // A conservative planning estimate for an ordinary city bicycle.
    final estimatedMinutes = (totalMeters / 1000 / 15 * 60).ceil();

    return BikeRoute(
      points: points,
      distanceMeters: totalMeters,
      estimatedDuration: Duration(minutes: estimatedMinutes),
    );
  }
}
