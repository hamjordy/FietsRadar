import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RideRecord {
  const RideRecord({
    required this.id,
    required this.startedAt,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.destination,
  });

  final String id;
  final DateTime startedAt;
  final int durationSeconds;
  final double distanceMeters;
  final String destination;

  factory RideRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final startedAt = json['startedAt'];
    final durationSeconds = json['durationSeconds'];
    final distanceMeters = json['distanceMeters'];
    final destination = json['destination'];

    if (id is! String ||
        startedAt is! String ||
        durationSeconds is! num ||
        distanceMeters is! num ||
        destination is! String) {
      throw const FormatException('Ongeldige ritregistratie.');
    }

    final parsedDate = DateTime.tryParse(startedAt);
    final duration = durationSeconds.toInt();
    final distance = distanceMeters.toDouble();
    if (parsedDate == null ||
        duration < 0 ||
        !distance.isFinite ||
        distance < 0) {
      throw const FormatException('Ongeldige ritregistratie.');
    }

    return RideRecord(
      id: id,
      startedAt: parsedDate,
      durationSeconds: duration,
      distanceMeters: distance,
      destination: destination,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'durationSeconds': durationSeconds,
        'distanceMeters': distanceMeters,
        'destination': destination,
      };
}


/// Serializable snapshot used to recover an in-progress navigation session.
class ActiveRideSession {
  const ActiveRideSession({
    required this.startedAt,
    required this.destinationName,
    required this.destinationDisplayName,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.pausedDurationMs,
    required this.pausedAt,
    required this.isPaused,
    required this.distanceMeters,
    required this.routeProfile,
    required this.savedAt,
  });

  final DateTime startedAt;
  final String destinationName;
  final String destinationDisplayName;
  final double destinationLatitude;
  final double destinationLongitude;
  final int pausedDurationMs;
  final DateTime? pausedAt;
  final bool isPaused;
  final double distanceMeters;
  final String routeProfile;
  final DateTime savedAt;

  factory ActiveRideSession.fromJson(Map<String, dynamic> json) {
    final startedAt = json['startedAt'];
    final name = json['destinationName'];
    final displayName = json['destinationDisplayName'];
    final latitude = json['destinationLatitude'];
    final longitude = json['destinationLongitude'];
    final pausedDuration = json['pausedDurationMs'];
    final pausedAtValue = json['pausedAt'];
    final isPaused = json['isPaused'];
    final distance = json['distanceMeters'];
    final profile = json['routeProfile'];
    final savedAt = json['savedAt'];

    if (startedAt is! String ||
        name is! String || name.trim().isEmpty ||
        displayName is! String || displayName.trim().isEmpty ||
        latitude is! num || longitude is! num ||
        pausedDuration is! num || isPaused is! bool ||
        distance is! num || profile is! String || savedAt is! String ||
        (pausedAtValue != null && pausedAtValue is! String)) {
      throw const FormatException('Ongeldige actieve rit.');
    }

    final parsedStartedAt = DateTime.tryParse(startedAt);
    final parsedSavedAt = DateTime.tryParse(savedAt);
    final parsedPausedAt = pausedAtValue == null
        ? null
        : DateTime.tryParse(pausedAtValue as String);
    final lat = latitude.toDouble();
    final lon = longitude.toDouble();
    final meters = distance.toDouble();
    final pausedMs = pausedDuration.toInt();
    if (parsedStartedAt == null ||
        parsedSavedAt == null ||
        (pausedAtValue != null && parsedPausedAt == null) ||
        !lat.isFinite || lat < -90 || lat > 90 ||
        !lon.isFinite || lon < -180 || lon > 180 ||
        !meters.isFinite || meters < 0 ||
        pausedMs < 0 ||
        profile.isEmpty ||
        (isPaused && parsedPausedAt == null)) {
      throw const FormatException('Ongeldige actieve rit.');
    }

    return ActiveRideSession(
      startedAt: parsedStartedAt,
      destinationName: name,
      destinationDisplayName: displayName,
      destinationLatitude: lat,
      destinationLongitude: lon,
      pausedDurationMs: pausedMs,
      pausedAt: parsedPausedAt,
      isPaused: isPaused,
      distanceMeters: meters,
      routeProfile: profile,
      savedAt: parsedSavedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'destinationName': destinationName,
        'destinationDisplayName': destinationDisplayName,
        'destinationLatitude': destinationLatitude,
        'destinationLongitude': destinationLongitude,
        'pausedDurationMs': pausedDurationMs,
        'pausedAt': pausedAt?.toIso8601String(),
        'isPaused': isPaused,
        'distanceMeters': distanceMeters,
        'routeProfile': routeProfile,
        'savedAt': savedAt.toIso8601String(),
      };
}

/// Private, on-device ride history. No GPS track or location samples are stored.
class RideHistoryService {
  static const String _storageKey = 'fietsradar.ride_history.v1';
  static const String _activeSessionKey = 'fietsradar.active_ride_session.v1';
  static const int _maximumRecords = 100;

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> saveActiveSession(ActiveRideSession session) async {
    await _preferences.setString(_activeSessionKey, jsonEncode(session.toJson()));
  }

  Future<ActiveRideSession?> loadActiveSession() async {
    final raw = await _preferences.getString(_activeSessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return ActiveRideSession.fromJson(decoded);
    } on FormatException {
      await clearActiveSession();
      return null;
    } on TypeError {
      await clearActiveSession();
      return null;
    }
  }

  Future<void> clearActiveSession() async {
    await _preferences.remove(_activeSessionKey);
  }

  Future<List<RideRecord>> loadRides() async {
    final raw = await _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final rides = <RideRecord>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          rides.add(RideRecord.fromJson(item));
        } on FormatException {
          // Skip one damaged record without losing the rest of the history.
        }
      }
      rides.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return List.unmodifiable(rides.take(_maximumRecords));
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> saveRide(RideRecord ride) async {
    final rides = await loadRides();
    final updated = [
      ride,
      ...rides.where((saved) => saved.id != ride.id),
    ].take(_maximumRecords);
    await _preferences.setString(
      _storageKey,
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> deleteRide(String rideId) async {
    final rides = await loadRides();
    final updated = rides.where((ride) => ride.id != rideId);
    await _preferences.setString(
      _storageKey,
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
  }
}
