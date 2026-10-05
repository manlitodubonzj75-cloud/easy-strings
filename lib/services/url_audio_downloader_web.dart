import "dart:async";
import "dart:typed_data";
import "package:http/http.dart" as http;
import "package:youtube_explode_dart/youtube_explode_dart.dart" as yte;

class DownloadedAudioResult {
  final Uint8List bytes;
  final String title;
  final String sourceUrl;

  const DownloadedAudioResult({
    required this.bytes,
    required this.title,
    required this.sourceUrl,
  });
}

/// Web-compatible URL Audio Downloader service.
class UrlAudioDownloader {
  static String normalizeUrl(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return "";

    if (raw.startsWith("//")) {
      raw = "https:$raw";
    } else if (!raw.contains("://")) {
      raw = "https://$raw";
    }
    return raw;
  }

  static bool isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains("youtube.com") ||
        lower.contains("youtu.be") ||
        lower.contains("youtube-nocookie.com");
  }

  static String extractVideoId(String url) {
    final clean = normalizeUrl(url);
    try {
      final vId = yte.VideoId(clean);
      return vId.value;
    } catch (_) {
      final match = RegExp(r"(?:v=|\/|youtu\.be\/|embed\/|shorts\/)([a-zA-Z0-9_-]{11})").firstMatch(clean);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!;
      }
      return clean;
    }
  }

  static Future<DownloadedAudioResult> downloadFromUrl(
    String url, {
    void Function(String status, double progress)? onProgress,
  }) => downloadAudio(url, onProgress: onProgress);

  static Future<DownloadedAudioResult> downloadAudio(
    String url, {
    void Function(String status, double progress)? onProgress,
  }) async {
    final cleanUrl = normalizeUrl(url);
    if (cleanUrl.isEmpty) {
      throw const FormatException("Введите корректную ссылку на аудио или YouTube");
    }

    if (isYouTubeUrl(cleanUrl)) {
      return downloadYouTubeAudio(cleanUrl, onProgress: onProgress);
    } else {
      return downloadDirectAudio(cleanUrl, onProgress: onProgress);
    }
  }

  static Future<DownloadedAudioResult> downloadYouTubeAudio(
    String url, {
    void Function(String status, double progress)? onProgress,
  }) async {
    final yt = yte.YoutubeExplode();
    try {
      onProgress?.call("Получение метаданных YouTube...", 0.1);
      final video = await yt.videos.get(url);
      final title = video.title;

      onProgress?.call("Поиск аудиопотока...", 0.3);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      onProgress?.call("Загрузка аудиопотока...", 0.4);
      final stream = yt.videos.streamsClient.get(audioStreamInfo);

      final bytesBuilder = BytesBuilder();
      int downloaded = 0;
      final total = audioStreamInfo.size.totalBytes;

      await for (final chunk in stream) {
        bytesBuilder.add(chunk);
        downloaded += chunk.length;
        if (total > 0) {
          final progress = 0.4 + (downloaded / total) * 0.55;
          onProgress?.call("Загрузка: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB...", progress.clamp(0.4, 0.95));
        }
      }

      onProgress?.call("Загрузка завершена!", 1.0);
      return DownloadedAudioResult(
        bytes: bytesBuilder.takeBytes(),
        title: title,
        sourceUrl: url,
      );
    } finally {
      yt.close();
    }
  }

  static Future<DownloadedAudioResult> downloadDirectAudio(
    String url, {
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call("Запрос к серверу...", 0.1);
    final uri = Uri.parse(url);
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw HttpException("Ошибка скачивания: HTTP ${response.statusCode}");
    }

    onProgress?.call("Загрузка завершена!", 1.0);
    var title = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : "Аудиозапись";
    if (title.contains(".")) {
      title = title.substring(0, title.lastIndexOf("."));
    }

    return DownloadedAudioResult(
      bytes: response.bodyBytes,
      title: title,
      sourceUrl: url,
    );
  }
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
