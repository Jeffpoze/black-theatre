// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../settings_controller.dart';

/// Converts Jellyfin's tick-based playback position (100ns units) to a [Duration].
Duration ticksToDuration(dynamic ticks) => Duration(microseconds: ((ticks as num?) ?? 0).toInt() ~/ 10);

class JellyfinSession {
  const JellyfinSession({required this.serverUrl, required this.userId, required this.token, required this.username, this.isAdministrator = false});

  final String serverUrl;
  final String userId;
  final String token;
  final String username;
  final bool isAdministrator;
}

// A slow or overloaded Jellyfin server can otherwise leave a request pending
// forever, which stalls the whole homepage (it awaits every section before
// showing anything). Bound every request so a stuck one fails fast instead.
class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient(this._inner, this._timeout);
  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request).timeout(_timeout);

  @override
  void close() => _inner.close();
}

class JellyfinApiService {
  JellyfinApiService({http.Client? client}) : _client = _TimeoutHttpClient(client ?? http.Client(), const Duration(seconds: 30));

  final http.Client _client;

  static const _deviceId = 'c78432a9-816f-45b6-b510-123456789abc';
  static const _clientIdentity = 'Client="BlackTheatre", Device="iOS", DeviceId="$_deviceId", Version="1.0.0"';

  static String getImageUrl(String serverUrl, String itemId, {String? imageTag}) {
    final cleanUrl = serverUrl.trim().replaceAll(RegExp(r'/*$'), '');
    final tagParam = imageTag != null ? '&tag=$imageTag' : '';
    return '$cleanUrl/Items/$itemId/Images/Primary?quality=90$tagParam';
  }

  static String authorizationHeader(String token) => 'MediaBrowser $_clientIdentity, Token="$token"';

  static String getBackdropUrl(String serverUrl, String itemId, {String? imageTag}) {
    final cleanUrl = serverUrl.trim().replaceAll(RegExp(r'/*$'), '');
    final tagParam = imageTag != null ? '&tag=$imageTag' : '';
    return '$cleanUrl/Items/$itemId/Images/Backdrop?quality=90$tagParam';
  }

  /// Text-based subtitle codecs Jellyfin can embed as a WebVTT HLS rendition
  /// without re-encoding video. Anything else (e.g. PGS/VOBSUB image subs)
  /// needs to be burned into the video instead.
  static const _textSubtitleCodecs = {'subrip', 'srt', 'ass', 'ssa', 'vtt', 'webvtt', 'mov_text'};

  static String subtitleMethodFor(String? codec) => codec != null && _textSubtitleCodecs.contains(codec.toLowerCase()) ? 'Hls' : 'Encode';

  static String getStreamUrl(String serverUrl, String itemId, String token, {int? maxBitrateBps, int? subtitleStreamIndex, String? subtitleMethod}) {
    final cleanUrl = serverUrl.trim().replaceAll(RegExp(r'/*$'), '');
    final params = <String, String>{
      'api_key': token,
      'MediaSourceId': itemId,
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      if (maxBitrateBps != null) 'VideoBitrate': '$maxBitrateBps',
      if (subtitleStreamIndex != null) ...{'SubtitleStreamIndex': '$subtitleStreamIndex', 'SubtitleMethod': subtitleMethod ?? 'Hls'},
    };
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return '$cleanUrl/Videos/$itemId/master.m3u8?$query';
  }

  // Audio-only items (audiobooks, music) don't have a video stream, so the
  // /Videos master.m3u8 endpoint isn't reliable for them; Jellyfin's audio
  // endpoint is built for exactly this.
  static String getAudioStreamUrl(String serverUrl, String itemId, String userId, String token, {int? maxBitrateBps}) {
    final cleanUrl = serverUrl.trim().replaceAll(RegExp(r'/*$'), '');
    final params = <String, String>{
      'api_key': token,
      'UserId': userId,
      'DeviceId': _deviceId,
      'Container': 'opus,mp3,aac,m4a,m4b,flac,wav,ogg,wma',
      'AudioCodec': 'aac',
      'TranscodingContainer': 'ts',
      if (maxBitrateBps != null) 'MaxStreamingBitrate': '$maxBitrateBps',
    };
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return '$cleanUrl/Audio/$itemId/universal?$query';
  }

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
      final user = data['User'] as Map<String, dynamic>;
      final policy = user['Policy'] as Map<String, dynamic>?;
      return JellyfinSession(
        serverUrl: cleanServerUrl,
        userId: user['Id'] as String,
        token: data['AccessToken'] as String,
        username: user['Name'] as String,
        isAdministrator: policy?['IsAdministrator'] == true,
      );
    } catch (e) {
      print('login error: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getFeaturedItems(String serverUrl, String userId, String token) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Users/$userId/Items').replace(queryParameters: {
      'SortBy': 'DateCreated',
      'SortOrder': 'Descending',
      'IncludeItemTypes': 'Movie,Series',
      'Recursive': 'true',
      'Limit': '10',
      'Fields': 'Overview,BackdropImageTags,PrimaryImageTag,ProductionYear',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getFeaturedItems failed: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load featured items.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['Items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>();
    return items.where((item) => (item['BackdropImageTags'] as List<dynamic>?)?.isNotEmpty == true).toList();
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
      'Fields': 'PrimaryImageTag,ImageTags,SeriesPrimaryImageTag,AlbumPrimaryImageTag,AlbumId,PremiereDate,ProductionYear,EndDate,Status',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getRecentItemsForView failed for $viewId: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load recent items.');
    }
    final data = jsonDecode(response.body);
    final items = data is Map<String, dynamic> && data['Items'] is List<dynamic> ? data['Items'] as List<dynamic> : const [];
    return _collapseToParentItems(items, serverUrl, userId, token);
  }

  // "Recently added" for a show/music library returns newly added episodes or
  // tracks, not the shows/albums themselves. Collapse those down to one entry
  // per series/album (using the parent's own poster/metadata) so the homepage
  // rows read like a show/album list instead of a flat file list.
  Future<List<dynamic>> _collapseToParentItems(List<dynamic> rawItems, String serverUrl, String userId, String token) async {
    final ordered = <dynamic>[];
    final seenParentIds = <String>{};
    final parentIdsNeeded = <String>[];
    final latestYearByParentId = <String, int>{};
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final parentId = switch (raw['Type']) {
        'Episode' => raw['SeriesId'] as String?,
        'Audio' => raw['AlbumId'] as String?,
        _ => null,
      };
      if (parentId == null) {
        ordered.add(raw);
        continue;
      }
      final rawYear = raw['ProductionYear'] as int? ?? DateTime.tryParse(raw['PremiereDate'] as String? ?? '')?.year;
      if (rawYear != null) {
        final current = latestYearByParentId[parentId];
        if (current == null || rawYear > current) latestYearByParentId[parentId] = rawYear;
      }
      if (seenParentIds.contains(parentId)) continue;
      seenParentIds.add(parentId);
      parentIdsNeeded.add(parentId);
      ordered.add(parentId);
    }
    if (parentIdsNeeded.isEmpty) return ordered;
    // One batched request for all parents in this row, instead of one request per item.
    final parentsById = await _getItemsByIds(serverUrl, userId, token, parentIdsNeeded);
    // A show's recorded end date can lag behind reality (e.g. a metadata
    // provider marking an anime "Ended" between seasons). If we just saw a
    // newer episode than that recorded end date, treat the show as ongoing.
    for (final id in parentIdsNeeded) {
      final parent = parentsById[id];
      final latestYear = latestYearByParentId[id];
      if (parent == null || latestYear == null) continue;
      final endYear = DateTime.tryParse(parent['EndDate'] as String? ?? '')?.year;
      if (endYear != null && endYear < latestYear) {
        parent.remove('EndDate');
        parent['Status'] = 'Continuing';
      }
    }
    return ordered.map((entry) {
      if (entry is String) {
        final parent = parentsById[entry];
        return parent != null && parent.isNotEmpty ? parent : null;
      }
      return entry;
    }).whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, Map<String, dynamic>>> _getItemsByIds(String serverUrl, String userId, String token, List<String> ids) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Users/$userId/Items').replace(queryParameters: {
      'Ids': ids.join(','),
      'Fields': 'PrimaryImageTag,ImageTags,ProductionYear,EndDate,Status',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('_getItemsByIds failed: ${response.statusCode} ${response.body}');
      return {};
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['Items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>();
    return {for (final item in items) if (item['Id'] is String) item['Id'] as String: item};
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
      'Fields': 'PrimaryImageTag,ImageTags,SeriesPrimaryImageTag,AlbumPrimaryImageTag,AlbumId,PremiereDate,ProductionYear,EndDate,Status,CommunityRating',
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
      // Jellyfin's IsUnaired filter depends on the item having been flagged
      // that way at scan time, which misses plenty of genuinely upcoming
      // items; MinPremiereDate alone is a more reliable "is this in the
      // future" check.
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

  Future<Map<String, dynamic>> getItemDetail(String serverUrl, String userId, String token, String itemId) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Users/$userId/Items/$itemId').replace(queryParameters: {
      'Fields': 'Overview,Genres,Studios,People,PrimaryImageTag,ImageTags,BackdropImageTags,CommunityRating,OfficialRating,PremiereDate,ProductionYear,EndDate,Status,RunTimeTicks',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getItemDetail failed for $itemId: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load details.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getSeasons(String serverUrl, String userId, String token, String seriesId) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Shows/$seriesId/Seasons').replace(queryParameters: {
      'userId': userId,
      'Fields': 'PrimaryImageTag,ImageTags',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getSeasons failed for $seriesId: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load seasons.');
    }
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic> && data['Items'] is List<dynamic>) return data['Items'] as List<dynamic>;
    return const [];
  }

  Future<List<dynamic>> getEpisodes(String serverUrl, String userId, String token, String seriesId, {String? seasonId}) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Shows/$seriesId/Episodes').replace(queryParameters: {
      'userId': userId,
      'Fields': 'PrimaryImageTag,ImageTags,Overview,PremiereDate',
      if (seasonId != null) 'SeasonId': seasonId,
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getEpisodes failed for $seriesId: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load episodes.');
    }
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic> && data['Items'] is List<dynamic>) return data['Items'] as List<dynamic>;
    return const [];
  }

  // For any playable folder that isn't a Series (music albums, audiobook
  // folders, playlists): its direct children are the actually-playable items.
  Future<List<dynamic>> getChildItems(String serverUrl, String userId, String token, String parentId) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Users/$userId/Items').replace(queryParameters: {
      'ParentId': parentId,
      'SortBy': 'IndexNumber,SortName',
      'SortOrder': 'Ascending',
      'Fields': 'PrimaryImageTag,ImageTags,RunTimeTicks,IndexNumber',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getChildItems failed for $parentId: ${response.statusCode} ${response.body}');
      throw Exception('Unable to load items.');
    }
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic> && data['Items'] is List<dynamic>) return data['Items'] as List<dynamic>;
    return const [];
  }

  Future<Map<String, dynamic>?> getNextUp(String serverUrl, String userId, String token, String seriesId) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Shows/NextUp').replace(queryParameters: {
      'userId': userId,
      'SeriesId': seriesId,
      'Limit': '1',
      'Fields': 'PrimaryImageTag,ImageTags,Overview,PremiereDate',
    });
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getNextUp failed for $seriesId: ${response.statusCode} ${response.body}');
      return null;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['Items'] as List<dynamic>?)?.whereType<Map<String, dynamic>>();
    return items == null || items.isEmpty ? null : items.first;
  }

  Future<List<dynamic>> getMediaStreams(String serverUrl, String userId, String token, String itemId) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Items/$itemId').replace(queryParameters: {'userId': userId, 'Fields': 'MediaStreams'});
    final response = await _client.get(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('getMediaStreams failed for $itemId: ${response.statusCode} ${response.body}');
      return const [];
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sources = data['MediaSources'] as List<dynamic>?;
    if (sources != null && sources.isNotEmpty) {
      final first = sources.first as Map<String, dynamic>;
      return (first['MediaStreams'] as List<dynamic>?) ?? const [];
    }
    return const [];
  }

  Future<void> setFavorite(String serverUrl, String userId, String token, String itemId, bool favorite) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Users/$userId/FavoriteItems/$itemId');
    final response = favorite ? await _client.post(uri, headers: authHeaders(token)) : await _client.delete(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Unable to update favorite.');
  }

  Future<void> setWatched(String serverUrl, String userId, String token, String itemId, bool watched) async {
    final cleanUrl = _normalizeUrl(serverUrl);
    final uri = Uri.parse('$cleanUrl/Users/$userId/PlayedItems/$itemId');
    final response = watched ? await _client.post(uri, headers: authHeaders(token)) : await _client.delete(uri, headers: authHeaders(token));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Unable to update watched status.');
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