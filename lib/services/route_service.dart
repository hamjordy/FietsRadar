import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/place.dart';

class RouteInstruction {
  const RouteInstruction({
    required this.pointIndex,
    required this.command,
    required this.exitNumber,
    required this.distanceToNextMeters,
    required this.angleDegrees,
  });

  /// Index of the instruction location in the route's GeoJSON coordinate list.
  final int pointIndex;
  final int command;
  final int exitNumber;
  final double distanceToNextMeters;
  final int angleDegrees;

  String get label {
    switch (command) {
      case 1:
        return 'Ga rechtdoor';
      case 2:
        return 'Sla linksaf';
      case 3:
        return 'Houd licht links aan';
      case 4:
        return 'Sla scherp linksaf';
      case 5:
        return 'Sla rechtsaf';
      case 6:
        return 'Houd licht rechts aan';
      case 7:
        return 'Sla scherp rechtsaf';
      case 8:
        return 'Houd links aan';
      case 9:
        return 'Houd rechts aan';
      case 10:
      case 11:
      case 15:
        return 'Keer om';
      case 13:
      case 14:
        return exitNumber > 0
            ? 'Neem de ${exitNumber}e afslag op de rotonde'
            : 'Neem de volgende afslag op de rotonde';
      case 16:
        return 'Blijf links';
      case 17:
        return 'Neem de linker afslag';
      case 18:
        return 'Neem de rechter afslag';
      default:
        return 'Volg de fietsroute';
    }
  }

  String get spokenText {
    switch (command) {
      case 1:
        return 'Ga rechtdoor';
      case 2:
        return 'Sla linksaf';
      case 3:
        return 'Houd licht links aan';
      case 4:
        return 'Sla scherp linksaf';
      case 5:
        return 'Sla rechtsaf';
      case 6:
        return 'Houd licht rechts aan';
      case 7:
        return 'Sla scherp rechtsaf';
      case 8:
        return 'Houd links aan';
      case 9:
        return 'Houd rechts aan';
      case 10:
      case 11:
      case 15:
        return 'Keer om';
      case 13:
      case 14:
        return exitNumber > 0
            ? 'Neem op de rotonde de ${exitNumber}e afslag'
            : 'Neem op de rotonde de volgende afslag';
      case 16:
        return 'Blijf links';
      case 17:
        return 'Neem de linker afslag';
      case 18:
        return 'Neem de rechter afslag';
      default:
        return 'Volg de fietsroute';
    }
  }

  static List<RouteInstruction> parseAll(dynamic rawInstructions) {
    if (rawInstructions is! List) return const [];

    final parsed = <RouteInstruction>[];
    for (final raw in rawInstructions) {
      if (raw is! List || raw.length < 5) continue;

      final values = raw.whereType<num>().toList();
      if (values.length < 5) continue;

      final pointIndex = values[0].toInt();
      final command = values[1].toInt();
      if (pointIndex < 0 || command < 1 || command > 18) continue;

      parsed.add(
        RouteInstruction(
          pointIndex: pointIndex,
          command: command,
          exitNumber: values[2].toInt().abs(),
          distanceToNextMeters: values[3].toDouble().clamp(0, double.infinity).toDouble(),
          angleDegrees: values[4].toInt(),
        ),
      );
    }
    parsed.sort((a, b) => a.pointIndex.compareTo(b.pointIndex));
    return List.unmodifiable(parsed);
  }
}

class BikeRoute {
  const BikeRoute({
    required this.points,
    required this.distanceMeters,
    required this.estimatedDuration,
    this.instructions = const [],
  });

  final List<LatLng> points;
  final double distanceMeters;
  final Duration estimatedDuration;
  final List<RouteInstruction> instructions;
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
    String profile = 'trekking',
  }) async {
    final uri = Uri.https(
      'brouter.de',
      '/brouter',
      {
        'lonlats':
            '${start.longitude},${start.latitude}|${destination.longitude},${destination.latitude}',
        'profile': profile,
        'alternativeidx': '0',
        'format': 'geojson',
        'timode': '1',
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
      final routeFeatures = features.whereType<Map<String, dynamic>>().where(
        (item) {
          final geometry = item['geometry'];
          return geometry is Map<String, dynamic> &&
              geometry['type'] == 'LineString';
        },
      );
      if (routeFeatures.isEmpty) {
        throw Exception('Er is geen fietsroute gevonden voor deze bestemming.');
      }
      feature = routeFeatures.first;
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

    const distance = Distance();
    var totalMeters = 0.0;
    for (var index = 1; index < points.length; index++) {
      totalMeters += distance.as(
        LengthUnit.Meter,
        points[index - 1],
        points[index],
      );
    }

    final properties = feature['properties'] is Map<String, dynamic>
        ? feature['properties'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final rawSeconds = double.tryParse(
      properties['total-time']?.toString() ?? '',
    );
    final estimatedDuration = rawSeconds != null && rawSeconds > 0
        ? Duration(seconds: rawSeconds.round())
        : Duration(minutes: (totalMeters / 1000 / 15 * 60).ceil());
    final instructions = RouteInstruction.parseAll(properties['voicehints']);

    return BikeRoute(
      points: List.unmodifiable(points),
      distanceMeters: totalMeters,
      estimatedDuration: estimatedDuration,
      instructions: instructions,
    );
  }
}
