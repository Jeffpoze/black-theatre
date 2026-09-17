import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:path_provider/path_provider.dart';

// A single shared VideoDownloadController for the whole app — its on-disk
// index needs to stay consistent regardless of which screen touches it, so
// this is a lazily-created singleton rather than one per screen.
class DownloadManager {
  DownloadManager._();
  static final instance = DownloadManager._();

  VideoDownloadController? _controller;

  Future<VideoDownloadController> get controller async {
    final existing = _controller;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    final created = VideoDownloadController(directoryPath: '${dir.path}/video_downloads');
    _controller = created;
    return created;
  }

  Future<bool> isDownloaded(String itemId) async => (await controller).isDownloaded(itemId);

  Future<String?> localPathFor(String itemId) async => (await controller).localPathFor(itemId);

  Future<Stream<VideoDownloadProgress>> download(String itemId, String url, Map<String, String> headers) async =>
      (await controller).download(id: itemId, url: url, headers: headers);

  Future<void> remove(String itemId) async => (await controller).remove(itemId);

  Future<void> cancel(String itemId) async => (await controller).cancel(itemId);
}
