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
}
