// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings_controller.dart';

class JellyfinSession {
  const JellyfinSession({required this.serverUrl, required this.userId, required this.token});

  final String serverUrl;
  final String userId;
  final String token;
}

class JellyfinApiService {
  JellyfinApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _clientIdentity = 'Client="BlackTheatre", Device="iOS", DeviceId="c78432a9-816f-45b6-b510-123456789abc", Version="1.0.0"';

  static String getImageUrl(String serverUrl, String itemId, {String? imageTag}) {
    final cleanUrl = serverUrl.trim().replaceAll(RegExp(r'/*$'), '');
    final tagParam = imageTag != null ? '&tag=$imageTag' : '';
    return '$cleanUrl/Items/$itemId/Images/Primary?quality=90$tagParam';
  }

  static String authorizationHeader(String token) => 'MediaBrowser $_clientIdentity, Token="$token"';

  static Map<String, String> authHeaders(String token) {
    final value = authorizationHeader(token);
    return {'Authorization': value, 'X-Emby-Authorization': value};
  }

  Future<JellyfinSession> login({required String serverUrl, required String username, required String password}) async {
    try {
      final cleanServerUrl = _normalizeUrl(serverUrl);
      // The explicit interpolation keeps the endpoint construction readable.
      // ignore: unnecessary_brace_in_string_interps
      final requestUri = Uri.parse('${cleanServerUrl}/Users/AuthenticateByName');
      const authorization = 'MediaBrowser $_clientIdentity';
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': authorization,
        'X-Emby-Authorization': authorization,
      };
      final body = jsonEncode({'Username': username.trim(), 'Pw': password});
      final request = http.Request('POST', requestUri)
        ..headers.addAll(headers)
        ..bodyBytes = utf8.encode(body);
      final response = await http.Response.fromStream(await _client.send(request));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        print('login failed: ${response.statusCode}');
        throw Exception('Unable to sign in.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return JellyfinSession(serverUrl: cleanServerUrl, userId: data['User']['Id'] as String, token: data['AccessToken'] as String);
    } catch (e) {
      print('login error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchHomeItems(JellyfinSession session) async {
    final uri = Uri.parse('${session.serverUrl}/Users/${session.userId}/Items').replace(queryParameters: {'SortBy': 'PremiereDate', 'SortOrder': 'Descending', 'IncludeItemTypes': 'Movie,Series,Episode', 'Recursive': 'true', 'Limit': '40', 'Fields': 'Overview,PrimaryImageAspectRatio,PrimaryImageTag,PremiereDate,DateCreated'});
    final response = await _client.get(uri, headers: authHeaders(session.token));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Unable to load your library.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['Items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
  }

  Future<List<dynamic>> getContinueWatching(String serverUrl, String userId, String token) {
    final cleanUrl = _normalizeUrl(serverUrl);
    return _getItemList('$cleanUrl/Users/$userId/Items/Resume?Limit=12&Fields=PrimaryImageTag,ImageTags,SeriesPrimaryImageTag', token);
  }

  Future<List<dynamic>> getRecentItemsForView(String serverUrl, String userId, String token, String viewId) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Users/$userId/Items').replace(queryParameters: {
      'ParentId': viewId,
      'SortBy': 'PremiereDate,ProductionYear,SortName',
      'SortOrder': 'Descending',
      'Recursive': 'true',
      'Filters': 'IsNotFolder',
      'Limit': '20',
      'Fields': 'PrimaryImageTag,ImageTags,SeriesPrimaryImageTag,PremiereDate',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getRecentItemsForView failed for $viewId: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load recent items.');
    }
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic> && data['Items'] is List<dynamic>) return data['Items'] as List<dynamic>;
    return const [];
  }

  Future<List<dynamic>> getLibraryItems(String serverUrl, String userId, String token, String viewId, {required SortOption sort}) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Users/$userId/Items').replace(queryParameters: {
      'ParentId': viewId,
      'SortBy': sort.jellyfinSortBy,
      'SortOrder': sort.jellyfinSortOrder,
      'Recursive': 'true',
      'Filters': 'IsNotFolder',
      'Limit': '200',
      'Fields': 'PrimaryImageTag,ImageTags,SeriesPrimaryImageTag,PremiereDate,CommunityRating',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getLibraryItems failed for $viewId: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load library items.');
    }
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic> && data['Items'] is List<dynamic>) return data['Items'] as List<dynamic>;
    return const [];
  }

  Future<List<dynamic>> getUpcomingItems(String serverUrl, String userId, String token) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final todayUtc = DateTime.now().toUtc();
    final minPremiereDate = DateTime.utc(todayUtc.year, todayUtc.month, todayUtc.day).toIso8601String();
    final uri = Uri.parse('$cleanUrl/Users/$userId/Items').replace(queryParameters: {
      'Recursive': 'true',
      'IncludeItemTypes': 'Movie,Episode',
      'Filters': 'IsUnaired',
      'MinPremiereDate': minPremiereDate,
      'SortBy': 'PremiereDate',
      'SortOrder': 'Ascending',
      'Limit': '100',
      'Fields': 'PrimaryImageTag,ImageTags,SeriesPrimaryImageTag,SeriesName,PremiereDate,IndexNumber,ParentIndexNumber',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getUpcomingItems failed: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load upcoming releases.');
    }
    final data = jsonDecode(response.body);
    final items = data is Map<String, dynamic> && data['Items'] is List<dynamic> ? data['Items'] as List<dynamic> : const [];
    // MinPremiereDate should already exclude these, but guard against items with no known air date at all.
    return items.where((item) => item is Map<String, dynamic> && item['PremiereDate'] is String).toList();
  }

  Future<List<dynamic>> getLibraryViews(String serverUrl, String userId, String token) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final response = await _client.get(
      Uri.parse('$cleanUrl/Users/$userId/Views').replace(queryParameters: {'Fields': 'PrimaryImageTag,ImageTags'}),
      headers: authHeaders(token),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getLibraryViews failed: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load library categories.');
    }
    final data = jsonDecode(response.body);
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic> && data['Items'] is List<dynamic>) return data['Items'] as List<dynamic>;
    return const [];
  }

  Future<List<dynamic>> _getItemList(String url, String token) async {
    final response = await _client.get(Uri.parse(url), headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('_getItemList failed for $url: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load home media.');
    }
    final data = jsonDecode(response.body);
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic> && data['Items'] is List<dynamic>) return data['Items'] as List<dynamic>;
    return const [];
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }
}