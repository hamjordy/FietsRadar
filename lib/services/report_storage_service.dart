import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/road_report.dart';

/// Stores user-created road reports on this device only.
class ReportStorageService {
  ReportStorageService({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _storageKey = 'fietsradar.road_reports.v1';
  static const int _maxStoredReports = 300;

  final SharedPreferencesAsync _preferences;

  Future<List<RoadReport>> loadReports() async {
    final raw = await _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [];
    }

    if (decoded is! List) return [];

    final reports = <RoadReport>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      try {
        reports.add(RoadReport.fromJson(item));
      } on FormatException {
        // Skip a damaged entry without losing the remaining saved reports.
      }
    }

    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports.take(_maxStoredReports).toList();
  }

  Future<void> saveReports(Iterable<RoadReport> reports) async {
    final newestFirst = reports.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final data = newestFirst
        .take(_maxStoredReports)
        .map((report) => report.toJson())
        .toList();

    await _preferences.setString(_storageKey, jsonEncode(data));
  }
}
