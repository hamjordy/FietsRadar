import 'package:material_ui/material_ui.dart';
import 'package:latlong2/latlong.dart';

enum ReportType {
  danger(
    label: 'Gevaarlijke situatie',
    description: 'Een plek waar fietsers extra moeten opletten',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFD97706),
  ),
  roadworks(
    label: 'Wegwerkzaamheden',
    description: 'Werkzaamheden of een afgesloten fietspad',
    icon: Icons.construction_rounded,
    color: Color(0xFF2563EB),
  ),
  obstacle(
    label: 'Obstakel op de weg',
    description: 'Bijvoorbeeld glas, een paaltje of een tak',
    icon: Icons.report_problem_outlined,
    color: Color(0xFF7C3AED),
  ),
  slippery(
    label: 'Glad wegdek',
    description: 'Gladheid, bladeren, ijs of modder',
    icon: Icons.ac_unit_rounded,
    color: Color(0xFF0891B2),
  ),
  incident(
    label: 'Ongeval',
    description: 'Een ongeval of incident op de fietsroute',
    icon: Icons.health_and_safety_outlined,
    color: Color(0xFFDC2626),
  );

  const ReportType({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

class RoadReport {
  const RoadReport({
    required this.id,
    required this.type,
    required this.location,
    required this.createdAt,
  });

  final String id;
  final ReportType type;
  final LatLng location;
  final DateTime createdAt;
}
