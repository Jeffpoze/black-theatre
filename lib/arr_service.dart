import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to a user's own Sonarr/Radarr instance (URL + API key entered in
/// Settings). Jellyfin only knows about episodes/movies it has already
/// scanned as files — Sonarr/Radarr know the full release schedule,
/// including not-yet-downloaded ("unaired"/"missing") items, which is what
/// makes a real weekly calendar possible.
class ArrService {
  ArrService._();
  static final _client = http.Client();

  static String _normalizeUrl(String url) {
    var clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return clean;
  }

  static Map<String, String> _headers(String apiKey) => {'X-Api-Key': apiKey};

  /// Hits GET /api/v3/system/status — used by the Settings screen's "Test
  /// Connection" button. Throws with a readable message on failure.
  static Future<void> testConnection(String url, String apiKey) async {
    final cleanUrl = _normalizeUrl(url);
    final uri = Uri.parse('$cleanUrl/api/v3/system/status');
    final response = await _client.get(uri, headers: _headers(apiKey)).timeout(const Duration(seconds: 10));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Rejected — check the API key.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server returned ${response.statusCode}.');
    }
  }

  static Future<List<dynamic>> getSonarrCalendar(
    String url,
    String apiKey,
    DateTime startUtc,
    DateTime endUtc,
  ) async {
    final cleanUrl = _normalizeUrl(url);
    final uri = Uri.parse('$cleanUrl/api/v3/calendar').replace(
      queryParameters: {
        'start': startUtc.toIso8601String(),
        'end': endUtc.toIso8601String(),
        'includeSeries': 'true',
        'includeEpisodeFile': 'true',
      },
    );
    final response = await _client.get(uri, headers: _headers(apiKey));
    if (response.statusCode < 200 || response.statusCode >= 300) return const [];
    final data = jsonDecode(response.body);
    return data is List<dynamic> ? data : const [];
  }

  static Future<List<dynamic>> getRadarrCalendar(
    String url,
    String apiKey,
    DateTime startUtc,
    DateTime endUtc,
  ) async {
    final cleanUrl = _normalizeUrl(url);
    final uri = Uri.parse('$cleanUrl/api/v3/calendar').replace(
      queryParameters: {
        'start': startUtc.toIso8601String(),
        'end': endUtc.toIso8601String(),
        'includeMovie': 'true',
      },
    );
    final response = await _client.get(uri, headers: _headers(apiKey));
    if (response.statusCode < 200 || response.statusCode >= 300) return const [];
    final data = jsonDecode(response.body);
    return data is List<dynamic> ? data : const [];
  }
}
