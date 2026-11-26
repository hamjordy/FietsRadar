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
    this.expiresAt,
    this.ownerId,
    this.isShared = false,
    this.isResolved = false,
    this.resolvedAt,
  });

  final String id;
  final ReportType type;
  final LatLng location;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? ownerId;
  final bool isShared;
  final bool isResolved;
  final DateTime? resolvedAt;

  /// Describes whether the report has a server-confirmed expiry.
  /// Local reports are retained on this device and have no shared validity.
  String validityLabelAt(DateTime now) {
    final expiry = expiresAt;
    if (!isShared || expiry == null) {
      return 'Alleen lokaal opgeslagen · geldigheid niet bevestigd';
    }
    final remaining = expiry.difference(now);
    if (remaining <= Duration.zero) return 'Verlopen';
    final remainingMinutes = remaining.inMinutes;
    final remainingHours = remaining.inHours;
    final remainingDays = remaining.inDays;
    if (remainingMinutes < 1) return 'Verloopt binnen een minuut';
    if (remainingHours < 1) {
      return 'Nog geldig · verloopt over $remainingMinutes min';
    }
    if (remainingDays < 1) {
      final hours = remainingHours;
      final minutes = remainingMinutes.remainder(60);
      return minutes == 0
          ? 'Nog geldig · verloopt over $hours uur'
          : 'Nog geldig · verloopt over $hours u $minutes min';
    }
    return 'Nog geldig · verloopt over $remainingDays dagen';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'createdAt': createdAt.toIso8601String(),
      };

  factory RoadReport.fromRemoteJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawType = json['report_type'];
    final rawLatitude = json['latitude'];
    final rawLongitude = json['longitude'];
    final rawCreatedAt = json['created_at'];
    final rawExpiresAt = json['expires_at'];
    final rawOwnerId = json['user_id'];
    final rawIsResolved = json['is_resolved'];
    final rawResolvedAt = json['resolved_at'];

    ReportType? parsedType;
    for (final candidate in ReportType.values) {
      if (candidate.name == rawType) {
        parsedType = candidate;
        break;
      }
    }

    if (rawId is! String || rawId.isEmpty ||
        parsedType == null ||
        rawLatitude is! num || !rawLatitude.isFinite ||
        rawLongitude is! num || !rawLongitude.isFinite ||
        rawCreatedAt is! String || rawExpiresAt is! String ||
        rawOwnerId is! String || rawOwnerId.isEmpty ||
        (rawIsResolved != null && rawIsResolved is! bool) ||
        (rawResolvedAt != null && rawResolvedAt is! String)) {
      throw const FormatException('Ongeldige gedeelde wegmelding.');
    }

    final latitude = rawLatitude.toDouble();
    final longitude = rawLongitude.toDouble();
    final createdAt = DateTime.tryParse(rawCreatedAt);
    final expiresAt = DateTime.tryParse(rawExpiresAt);
    if (latitude < -90 || latitude > 90 ||
        longitude < -180 || longitude > 180 ||
        createdAt == null || expiresAt == null) {
      throw const FormatException('Ongeldige gedeelde wegmelding.');
    }

    return RoadReport(
      id: rawId,
      type: parsedType,
      location: LatLng(latitude, longitude),
      createdAt: createdAt.toLocal(),
      expiresAt: expiresAt.toLocal(),
      ownerId: rawOwnerId,
      isShared: true,
      isResolved: rawIsResolved == true,
      resolvedAt: rawResolvedAt is String ? DateTime.tryParse(rawResolvedAt)?.toLocal() : null,
    );
  }

  factory RoadReport.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawType = json['type'];
    final rawLatitude = json['latitude'];
    final rawLongitude = json['longitude'];
    final rawCreatedAt = json['createdAt'];

    ReportType? parsedType;
    for (final candidate in ReportType.values) {
      if (candidate.name == rawType) {
        parsedType = candidate;
        break;
      }
    }

    if (rawId is! String || rawId.isEmpty ||
        parsedType == null ||
        rawLatitude is! num || !rawLatitude.isFinite ||
        rawLongitude is! num || !rawLongitude.isFinite ||
        rawCreatedAt is! String) {
      throw const FormatException('Ongeldige wegmelding.');
    }

    final latitude = rawLatitude.toDouble();
    final longitude = rawLongitude.toDouble();
    final createdAt = DateTime.tryParse(rawCreatedAt);
    if (latitude < -90 || latitude > 90 ||
        longitude < -180 || longitude > 180 ||
        createdAt == null) {
      throw const FormatException('Ongeldige wegmelding.');
    }

    return RoadReport(
      id: rawId,
      type: parsedType,
      location: LatLng(latitude, longitude),
      createdAt: createdAt,
    );
  }
}
