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

/// Private, on-device ride history. No GPS track or location samples are stored.
class RideHistoryService {
  static const String _storageKey = 'fietsradar.ride_history.v1';
  static const int _maximumRecords = 100;

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

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
