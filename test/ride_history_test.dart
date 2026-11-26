import 'package:flutter_test/flutter_test.dart';
import 'package:fietsradar/services/ride_history_service.dart';

void main() {
  group('ActiveRideSession', () {
    test('round trips a paused session through JSON', () {
      final startedAt = DateTime.utc(2026, 11, 26, 18);
      final pausedAt = DateTime.utc(2026, 11, 26, 18, 20);
      final session = ActiveRideSession(
        startedAt: startedAt,
        destinationName: 'Apeldoorn',
        destinationDisplayName: 'Apeldoorn, Gelderland, Nederland',
        destinationLatitude: 52.2112,
        destinationLongitude: 5.9699,
        pausedDurationMs: 120000,
        pausedAt: pausedAt,
        isPaused: true,
        distanceMeters: 2450.5,
        routeProfile: 'trekking',
        savedAt: pausedAt,
      );

      final restored = ActiveRideSession.fromJson(session.toJson());

      expect(restored.startedAt, startedAt);
      expect(restored.destinationName, 'Apeldoorn');
      expect(restored.destinationDisplayName, session.destinationDisplayName);
      expect(restored.destinationLatitude, 52.2112);
      expect(restored.destinationLongitude, 5.9699);
      expect(restored.pausedDurationMs, 120000);
      expect(restored.pausedAt, pausedAt);
      expect(restored.isPaused, isTrue);
      expect(restored.distanceMeters, 2450.5);
      expect(restored.routeProfile, 'trekking');
    });

    test('rejects invalid coordinates and inconsistent pause state', () {
      final valid = {
        'startedAt': '2026-11-26T18:00:00Z',
        'destinationName': 'Apeldoorn',
        'destinationDisplayName': 'Apeldoorn, Nederland',
        'destinationLatitude': 52.2,
        'destinationLongitude': 5.9,
        'pausedDurationMs': 0,
        'pausedAt': null,
        'isPaused': false,
        'distanceMeters': 100,
        'routeProfile': 'trekking',
        'savedAt': '2026-11-26T18:10:00Z',
      };

      expect(
        () => ActiveRideSession.fromJson({...valid, 'destinationLatitude': 120}),
        throwsFormatException,
      );
      expect(
        () => ActiveRideSession.fromJson({...valid, 'isPaused': true}),
        throwsFormatException,
      );
    });
  });

  group('RideRecord', () {
    test('round trips a completed ride through JSON', () {
      final startedAt = DateTime.utc(2026, 11, 26, 18, 30);
      final ride = RideRecord(
        id: 'ride-1',
        startedAt: startedAt,
        durationSeconds: 1845,
        distanceMeters: 6320.5,
        destination: 'Apeldoorn',
      );

      final restored = RideRecord.fromJson(ride.toJson());

      expect(restored.id, ride.id);
      expect(restored.startedAt, startedAt);
      expect(restored.durationSeconds, 1845);
      expect(restored.distanceMeters, 6320.5);
      expect(restored.destination, 'Apeldoorn');
    });

    test('rejects invalid duration and distance values', () {
      expect(
        () => RideRecord.fromJson({
          'id': 'ride-2',
          'startedAt': '2026-11-26T18:30:00Z',
          'durationSeconds': -1,
          'distanceMeters': 250,
          'destination': 'Apeldoorn',
        }),
        throwsFormatException,
      );
      expect(
        () => RideRecord.fromJson({
          'id': 'ride-3',
          'startedAt': '2026-11-26T18:30:00Z',
          'durationSeconds': 60,
          'distanceMeters': double.infinity,
          'destination': 'Apeldoorn',
        }),
        throwsFormatException,
      );
    });

    test('rejects missing required fields', () {
      expect(
        () => RideRecord.fromJson({'id': 'incomplete'}),
        throwsFormatException,
      );
    });
  });
}
