import 'package:flutter_test/flutter_test.dart';

import 'package:black_theatre_tv/services/jellyfin_api_service.dart';

void main() {
  group('JellyfinApiService.getStreamUrl', () {
    test('offers a broad codec list instead of forcing h264/aac for original quality', () {
      final uri = Uri.parse(
        JellyfinApiService.getStreamUrl(
          'https://example.test/',
          'item-id',
          'token',
          playSessionId: 'session-id',
        ),
      );

      final videoCodecs = uri.queryParameters['VideoCodec']?.split(',') ?? [];
      final audioCodecs = uri.queryParameters['AudioCodec']?.split(',') ?? [];
      expect(videoCodecs, contains('h264'));
      expect(videoCodecs.length, greaterThan(1));
      expect(audioCodecs, contains('aac'));
      expect(audioCodecs.length, greaterThan(1));
      expect(uri.queryParameters['VideoBitrate'], isNull);
      expect(uri.queryParameters['PlaySessionId'], 'session-id');
    });

    test('requests H.264/AAC only for bandwidth-limited playback', () {
      final uri = Uri.parse(
        JellyfinApiService.getStreamUrl(
          'https://example.test',
          'item-id',
          'token',
          maxBitrateBps: 4000000,
        ),
      );

      expect(uri.queryParameters['VideoCodec'], 'h264');
      expect(uri.queryParameters['AudioCodec'], 'aac');
      expect(uri.queryParameters['VideoBitrate'], '4000000');
    });
  });
}
