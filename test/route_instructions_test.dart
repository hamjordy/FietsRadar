import 'package:flutter_test/flutter_test.dart';
import 'package:fietsradar/services/route_service.dart';

void main() {
  group('RouteInstruction', () {
    test('parses BRouter voice hints and sorts them by route position', () {
      final instructions = RouteInstruction.parseAll([
        [18, 5, 0, 120, 90],
        [4, 2, 0, 85, -90],
        ['invalid', 'row'],
      ]);

      expect(instructions, hasLength(2));
      expect(instructions.first.pointIndex, 4);
      expect(instructions.first.label, 'Sla linksaf');
      expect(instructions.first.spokenText, 'Sla linksaf');
      expect(instructions.last.pointIndex, 18);
      expect(instructions.last.label, 'Sla rechtsaf');
    });

    test('formats roundabout exit instructions in Dutch', () {
      final instructions = RouteInstruction.parseAll([
        [12, 13, 3, 240, 180],
      ]);

      expect(instructions.single.label, 'Neem de 3e afslag op de rotonde');
      expect(
        instructions.single.spokenText,
        'Neem op de rotonde de 3e afslag',
      );
    });

    test('ignores malformed and unsupported commands', () {
      final instructions = RouteInstruction.parseAll([
        [2, 25, 0, 60, 90],
        [3, 2],
        ['not-a-number', 5, 0, 60, 90],
      ]);

      expect(instructions, isEmpty);
    });

    test('uses a safe fallback label for unknown commands', () {
      final instruction = RouteInstruction(
        pointIndex: 1,
        command: 12,
        exitNumber: 0,
        distanceToNextMeters: 80,
        angleDegrees: 0,
      );

      expect(instruction.label, 'Volg de fietsroute');
    });
  });
}
