import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:fietsradar/models/road_report.dart';

void main() {
  group('RoadReport serialization', () {
    test('keeps report details when encoded and decoded', () {
      final original = RoadReport(
        id: 'report-123',
        type: ReportType.roadworks,
        location: const LatLng(52.0907, 5.1214),
        createdAt: DateTime(2026, 11, 26, 18, 30),
      );

      final restored = RoadReport.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.location.latitude, original.location.latitude);
      expect(restored.location.longitude, original.location.longitude);
      expect(restored.createdAt, original.createdAt);
    });

    test('rejects unknown report types', () {
      expect(
        () => RoadReport.fromJson({
          'id': 'report-unknown',
          'type': 'not_a_report_type',
          'latitude': 52.0,
          'longitude': 5.0,
          'createdAt': '2026-11-26T18:30:00',
        }),
        throwsFormatException,
      );
    });
  });

  group('Remote road reports', () {
    test('parses a shared report including its owner and expiry', () {
      final report = RoadReport.fromRemoteJson({
        'id': '2ba7e54e-3671-4d05-b66f-19ef7f88f88d',
        'user_id': 'a6e2fc01-a5ed-4e56-aebd-1136951aa51f',
        'report_type': 'slippery',
        'latitude': 52.0907,
        'longitude': 5.1214,
        'created_at': '2026-11-26T17:00:00Z',
        'expires_at': '2026-11-26T21:00:00Z',
      });

      expect(report.isShared, isTrue);
      expect(report.type, ReportType.slippery);
      expect(report.ownerId, 'a6e2fc01-a5ed-4e56-aebd-1136951aa51f');
      expect(report.location.latitude, 52.0907);
      expect(report.createdAt.toUtc(), DateTime.utc(2026, 11, 26, 17));
      expect(report.expiresAt?.toUtc(), DateTime.utc(2026, 11, 26, 21));
    });

    test('rejects invalid coordinates from the shared feed', () {
      expect(
        () => RoadReport.fromRemoteJson({
          'id': '2ba7e54e-3671-4d05-b66f-19ef7f88f88d',
          'user_id': 'a6e2fc01-a5ed-4e56-aebd-1136951aa51f',
          'report_type': 'danger',
          'latitude': 120,
          'longitude': 5.0,
          'created_at': '2026-11-26T17:00:00Z',
          'expires_at': '2026-11-26T20:00:00Z',
        }),
        throwsFormatException,
      );
    });
  });
}
