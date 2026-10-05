import "dart:async";
import "dart:convert";
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
    final vId = extractVideoId(url);
    final client = http.Client();

    // 1. Try public Invidious API through CORS proxies
    final invidiousInstances = [
      "https://inv.nadeko.net",
      "https://invidious.nerdvpn.de",
      "https://vid.puffyan.us",
      "https://inv.tux.pizza",
    ];

    for (final host in invidiousInstances) {
      try {
        onProgress?.call("Подключение к аудиопотоку (Web Mirror)...", 0.15);
        final apiUrl = "$host/api/v1/videos/$vId";
        final proxyUrl = "https://api.allorigins.win/raw?url=${Uri.encodeComponent(apiUrl)}";
        final resp = await client.get(Uri.parse(proxyUrl)).timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final title = data["title"] as String? ?? "YouTube Audio";
          final formatStreams = data["adaptiveFormats"] as List?;

          if (formatStreams != null && formatStreams.isNotEmpty) {
            final audioStreams = formatStreams.where((f) {
              final type = f["type"] as String? ?? "";
              return type.startsWith("audio/");
            }).toList();

            if (audioStreams.isNotEmpty) {
              final target = audioStreams.first;
              final streamUrl = target["url"] as String?;
              if (streamUrl != null && streamUrl.isNotEmpty) {
                onProgress?.call("Загрузка аудиопотока...", 0.35);
                final audioProxy = "https://api.allorigins.win/raw?url=${Uri.encodeComponent(streamUrl)}";
                final audioRes = await client.get(Uri.parse(audioProxy)).timeout(const Duration(seconds: 40));
                if (audioRes.statusCode == 200 && audioRes.bodyBytes.isNotEmpty) {
                  onProgress?.call("Аудио получено!", 1.0);
                  return DownloadedAudioResult(
                    bytes: audioRes.bodyBytes,
                    title: title,
                    sourceUrl: url,
                  );
                }
              }
            }
          }
        }
      } catch (_) {
        // Continue to next mirror
      }
    }

    // 2. Fallback: Direct YoutubeExplode (will work if hosted behind proxy or in Electron/Tauri)
    try {
      final yt = yte.YoutubeExplode();
      try {
        onProgress?.call("Получение метаданных YouTube...", 0.2);
        final video = await yt.videos.get(url).timeout(const Duration(seconds: 8));
        final title = video.title;

        onProgress?.call("Поиск аудиопотока...", 0.35);
        final manifest = await yt.videos.streamsClient.getManifest(video.id).timeout(const Duration(seconds: 8));
        final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

        onProgress?.call("Загрузка аудиопотока...", 0.5);
        final stream = yt.videos.streamsClient.get(audioStreamInfo);

        final bytesBuilder = BytesBuilder();
        int downloaded = 0;
        final total = audioStreamInfo.size.totalBytes;

        await for (final chunk in stream.timeout(const Duration(seconds: 15))) {
          bytesBuilder.add(chunk);
          downloaded += chunk.length;
          if (total > 0) {
            final progress = 0.5 + (downloaded / total) * 0.48;
            onProgress?.call("Загрузка: ${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB...", progress.clamp(0.5, 0.98));
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
    } catch (e) {
      throw FormatException(
        "В веб-браузере YouTube блокирует скачивание политикой CORS.\n"
        "Для работы в Web используйте кнопку «Локальный файл» (MP3/WAV/AAC) или запустите нативное приложение macOS / Android.",
      );
    } finally {
      client.close();
    }
  }

  static Future<DownloadedAudioResult> downloadDirectAudio(
    String url, {
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call("Запрос к серверу...", 0.1);
    final uri = Uri.parse(url);

    Uint8List? bodyBytes;
    var title = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : "Аудиозапись";
    if (title.contains(".")) {
      title = title.substring(0, title.lastIndexOf("."));
    }

    // Try direct fetch first
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        bodyBytes = response.bodyBytes;
      }
    } catch (_) {
      // CORS block, try proxy
    }

    // If direct failed (CORS), fetch through CORS proxy
    if (bodyBytes == null || bodyBytes.isEmpty) {
      try {
        final proxyUri = Uri.parse("https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}");
        final resp = await http.get(proxyUri).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          bodyBytes = resp.bodyBytes;
        }
      } catch (_) {}
    }

    if (bodyBytes == null || bodyBytes.isEmpty) {
      throw const HttpException(
        "Не удалось загрузить аудиофайл по ссылке. Сервер источника недоступен или заблокирован браузером (CORS).",
      );
    }

    onProgress?.call("Загрузка завершена!", 1.0);
    return DownloadedAudioResult(
      bytes: bodyBytes,
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
