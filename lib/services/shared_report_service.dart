import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/road_report.dart';

/// Optional live road-report backend. Local app features work without keys.
class SharedReportService {
  static const String _projectUrl =
      String.fromEnvironment('SUPABASE_URL');
  static const String _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool _initialized = false;
  static bool _initializationFailed = false;

  bool get isConfigured =>
      _projectUrl.startsWith('https://') && _publishableKey.isNotEmpty;

  bool get isReady => _initialized && !_initializationFailed;

  String? get currentUserId =>
      isReady ? Supabase.instance.client.auth.currentUser?.id : null;

  static Future<void> initialize() async {
    if (!_projectUrl.startsWith('https://') || _publishableKey.isEmpty) {
      return;
    }

    try {
      await Supabase.initialize(
        url: _projectUrl,
        publishableKey: _publishableKey,
      );
      _initialized = true;
    } catch (_) {
      _initializationFailed = true;
    }
  }

  SupabaseClient get _client {
    if (!isReady) {
      throw StateError('De gedeelde meldingenbackend is niet ingesteld.');
    }
    return Supabase.instance.client;
  }

  Future<void> ensureSignedIn() async {
    if (_client.auth.currentUser != null) return;
    await _client.auth.signInAnonymously();
    if (_client.auth.currentUser == null) {
      throw StateError('Anonieme aanmelding is niet gelukt.');
    }
  }

  Stream<List<RoadReport>> watchReports() {
    final now = DateTime.now().toUtc().toIso8601String();
    return _client
        .from('road_reports')
        .stream(primaryKey: ['id'])
        .gt('expires_at', now)
        .order('created_at', ascending: false)
        .limit(300)
        .map((rows) {
          final reports = <RoadReport>[];
          for (final row in rows) {
            try {
              final report = RoadReport.fromRemoteJson(row);
              if (report.expiresAt?.isAfter(DateTime.now()) ?? false) {
                reports.add(report);
              }
            } on FormatException {
              // Ignore malformed remote rows instead of breaking the feed.
            }
          }
          return reports;
        });
  }

  Future<RoadReport> publishReport(RoadReport report) async {
    await ensureSignedIn();
    final row = await _client
        .from('road_reports')
        .insert({
          'report_type': report.type.name,
          'latitude': report.location.latitude,
          'longitude': report.location.longitude,
        })
        .select()
        .single();
    return RoadReport.fromRemoteJson(row);
  }

  Future<void> deleteReport(String reportId) async {
    final userId = currentUserId;
    if (userId == null) {
      throw StateError('Je bent niet verbonden met de meldingenserver.');
    }
    await _client
        .from('road_reports')
        .delete()
        .eq('id', reportId)
        .eq('user_id', userId);
  }
}
