import 'package:latlong2/latlong.dart';

class Place {
  const Place({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String displayName;
  final double latitude;
  final double longitude;

  LatLng get location => LatLng(latitude, longitude);

  factory Place.fromNominatim(Map<String, dynamic> json) {
    final displayName = (json['display_name'] as String?) ?? 'Onbekende locatie';
    final firstPart = displayName.split(',').first.trim();

    return Place(
      name: firstPart.isEmpty ? displayName : firstPart,
      displayName: displayName,
      latitude: double.parse(json['lat'].toString()),
      longitude: double.parse(json['lon'].toString()),
    );
  }
}
