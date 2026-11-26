import 'package:flutter_test/flutter_test.dart';
import 'package:fietsradar/services/ride_history_service.dart';

void main() {
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
