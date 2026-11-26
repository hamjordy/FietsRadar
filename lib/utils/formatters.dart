String formatDistance(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }
  return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

String formatDuration(Duration duration) {
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60);
    return '${duration.inHours} u $minutes min';
  }
  return '${duration.inMinutes} min';
}

String formatClock(DateTime dateTime) {
  final hours = dateTime.hour.toString().padLeft(2, '0');
  final minutes = dateTime.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}


String formatRelativeTime(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime);
  if (difference.isNegative || difference.inSeconds < 60) {
    return 'Zojuist';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min geleden';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours} uur geleden';
  }
  if (difference.inDays == 1) {
    return 'Gisteren';
  }
  return '${difference.inDays} dagen geleden';
}
