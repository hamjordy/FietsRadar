import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Zet de GPS-locatie van je telefoon aan.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Geef FietsRadar toestemming om je locatie te gebruiken.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Locatietoestemming is permanent geweigerd. Pas dit aan bij de Android-appinstellingen.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  /// Tracks GPS continuously. On Android, a user-started navigation session
  /// can opt into a location foreground service with an ongoing notification.
  Stream<Position> watchPosition({
    bool keepAliveInBackground = false,
  }) {
    if (defaultTargetPlatform == TargetPlatform.android &&
        keepAliveInBackground) {
      return Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 3),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'FietsRadar · Navigatie actief',
            notificationText:
                'Je GPS-route wordt bijgehouden. Open FietsRadar om de navigatie te stoppen.',
            notificationChannelName: 'FietsRadar navigatie',
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      );
    }

    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    );
  }
}
