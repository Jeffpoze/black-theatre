import 'dart:convert';

import 'package:http/http.dart' as http;

// TMDB network ids — verified against themoviedb.org/network/<id> for each
// entry below. Only networks we're confident about are mapped; anything
// else just falls back to the brand-color tile in networks_screen.dart.
// Real logo artwork can't be committed to this public repo, but fetching it
// live from TMDB's own image CDN (with attribution, as their API is meant
// to be used) is a different, legitimate thing.
const tmdbNetworkIds = <String, int>{
  'netflix': 213,
  'apple tv': 2552,
  'prime video': 1024,
  'amazon': 1024,
  'disney': 2739,
  'hulu': 453,
  'hbo': 49,
  'max': 3186,
  'paramount': 4330,
  'peacock': 3353,
  'showtime': 67,
  'starz': 318,
  'fx': 88,
  'amc': 174,
  'bbc': 4,
  'itv': 9,
  'adult swim': 80,
  'cartoon network': 56,
  'nickelodeon': 13,
  'youtube': 247,
  'crunchyroll': 1112,
};

class TmdbService {
  TmdbService._();
  static final _client = http.Client();

  // In-memory only — logos rarely change, and this avoids refetching on
  // every rebuild/screen visit within the same app session. A `null` value
  // means "looked it up, nothing usable" so we don't retry every rebuild.
  static final Map<int, String?> _logoUrlCache = {};

  static Future<String?> logoUrlForNetworkKey(String apiKey, String networkKey) async {
    final id = tmdbNetworkIds[networkKey];
    if (id == null || apiKey.isEmpty) return null;
    if (_logoUrlCache.containsKey(id)) return _logoUrlCache[id];
    try {
      final uri = Uri.parse('https://api.themoviedb.org/3/network/$id/images').replace(
        queryParameters: {'api_key': apiKey},
      );
      final response = await _client.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logoUrlCache[id] = null;
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final logos = (data['logos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      // Prefer a raster logo — CachedNetworkImage can't render .svg, and
      // TMDB stores most network marks as vector originals.
      final raster = logos.where((l) => !(l['file_path'] as String? ?? '').endsWith('.svg'));
      final chosen = raster.isNotEmpty ? raster.first : (logos.isNotEmpty ? logos.first : null);
      final filePath = chosen?['file_path'] as String?;
      if (filePath == null || filePath.endsWith('.svg')) {
        _logoUrlCache[id] = null;
        return null;
      }
      final url = 'https://image.tmdb.org/t/p/w300$filePath';
      _logoUrlCache[id] = url;
      return url;
    } catch (_) {
      _logoUrlCache[id] = null;
      return null;
    }
  }
}
