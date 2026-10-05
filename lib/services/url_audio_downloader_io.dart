import "dart:async";
import "dart:convert";
import "dart:io";
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

/// Service to download audio tracks from YouTube, direct audio URLs, or yt-dlp.
class UrlAudioDownloader {
  /// Normalizes user-entered URLs (adds https:// if missing, strips excess whitespace).
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

  /// Checks if URL is a YouTube link (watch, shorts, youtu.be, music.youtube)
  static bool isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains("youtube.com") ||
        lower.contains("youtu.be") ||
        lower.contains("youtube-nocookie.com");
  }

  /// Extracts YouTube video ID string from URL.
  static String extractVideoId(String url) {
    final clean = normalizeUrl(url);
    try {
      final vId = yte.VideoId(clean);
      return vId.value;
    } catch (_) {
      final match = RegExp(r"(?:v=|\/|youtu\.be\/|embed\/|shorts\/)([a-zA-Z0-9_-]{11})").firstMatch(clean);
      if (match != null) {
        return match.group(1)!;
      }
      throw FormatException("Неверная ссылка на видео YouTube: $url");
    }
  }

  /// Strips ID3v2 header tag from beginning of audio bytes to expose raw ADTS AAC frame stream.
  static Uint8List _stripId3Header(Uint8List bytes) {
    if (bytes.length >= 10 &&
        bytes[0] == 0x49 && // 'I'
        bytes[1] == 0x44 && // 'D'
        bytes[2] == 0x33) { // '3'
      final s0 = bytes[6] & 0x7F;
      final s1 = bytes[7] & 0x7F;
      final s2 = bytes[8] & 0x7F;
      final s3 = bytes[9] & 0x7F;
      final tagSize = (s0 << 21) | (s1 << 14) | (s2 << 7) | s3;
      final totalHeader = 10 + tagSize;
      if (totalHeader < bytes.length) {
        return bytes.sublist(totalHeader);
      }
    }
    return bytes;
  }

  /// Downloads YouTube audio stream using pure Dart VisionOS HLS segmented delivery.
  /// Bypasses rate-limiting, 403 Forbidden, and SABR throttling across Android, iOS, and Desktop.
  /// Concatenates clean ADTS AAC frames across all segments for full uninterrupted track duration.
  static Future<DownloadedAudioResult> downloadYouTubeAudio(
    String rawUrl, {
    void Function(String status, double progress)? onProgress,
  }) async {
    final normalized = normalizeUrl(rawUrl);
    final videoId = extractVideoId(normalized);
    final client = http.Client();

    try {
      onProgress?.call("Подключение к YouTube...", 0.05);

      // 1. Fetch watch page to obtain visitor token and cookies
      String? visitorData;
      String title = "YouTube Audio";

      try {
        final watchRes = await client.get(
          Uri.parse("https://www.youtube.com/watch?v=$videoId&bpctr=9999999999&has_verified=1"),
          headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.5",
          },
        ).timeout(const Duration(seconds: 10));

        if (watchRes.statusCode == 200) {
          final visitorMatch = RegExp(r'"VISITOR_DATA":\s*"([^"]+)"').firstMatch(watchRes.body);
          if (visitorMatch != null) {
            visitorData = visitorMatch.group(1);
          }
          final titleMatch = RegExp(r'<title>(.*?)(?: - YouTube)?</title>').firstMatch(watchRes.body);
          if (titleMatch != null) {
            title = titleMatch.group(1)!.replaceAll(" - YouTube", "").trim();
          }
        }
      } catch (_) {}

      onProgress?.call("Запрос аудиопотока (VisionOS HLS)...", 0.12);

      // 2. Query player API with VisionOS client
      final playerPayload = {
        "context": {
          "client": {
            "clientName": "VISIONOS",
            "clientVersion": "1.02",
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
            "osName": "visionOS",
            "osVersion": "26.5.23O471",
            "hl": "en",
            "timeZone": "UTC",
            "utcOffsetMinutes": 0,
            "visitorData": ?visitorData,
          },
        },
        "videoId": videoId,
        "playbackContext": {
          "contentPlaybackContext": {
            "html5Preference": "HTML5_PREF_WANTS",
            "signatureTimestamp": 20725,
          },
        },
        "contentCheckOk": true,
        "racyCheckOk": true,
      };

      final playerRes = await client.post(
        Uri.parse("https://www.youtube.com/youtubei/v1/player?prettyPrint=false"),
        headers: {
          "Content-Type": "application/json",
          "X-Youtube-Client-Name": "101",
          "X-Youtube-Client-Version": "1.02",
          "Origin": "https://www.youtube.com",
          "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
          "X-Goog-Visitor-Id": ?visitorData,
        },
        body: jsonEncode(playerPayload),
      ).timeout(const Duration(seconds: 12));

      if (playerRes.statusCode != 200) {
        throw HttpException("Ошибка подключения к YouTube API (HTTP ${playerRes.statusCode})");
      }

      final playerJson = jsonDecode(playerRes.body) as Map<String, dynamic>;
      final apiTitle = playerJson["videoDetails"]?["title"] as String?;
      if (apiTitle != null && apiTitle.isNotEmpty) {
        title = apiTitle;
      }

      final streamingData = playerJson["streamingData"] as Map<String, dynamic>?;
      final hlsManifestUrl = streamingData?["hlsManifestUrl"] as String?;

      if (hlsManifestUrl == null || hlsManifestUrl.isEmpty) {
        throw const FormatException("У данного видео отсутствует HLS манифест");
      }

      onProgress?.call("Получение плейлиста аудиосегментов...", 0.18);

      // 3. Fetch Master HLS Playlist
      final m3u8Res = await client.get(
        Uri.parse(hlsManifestUrl),
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
        },
      ).timeout(const Duration(seconds: 12));

      if (m3u8Res.statusCode != 200) {
        throw HttpException("Не удалось загрузить HLS манифест (HTTP ${m3u8Res.statusCode})");
      }

      // 4. Find audio stream playlist (GROUP-ID="234" (itag 140) or "233" (itag 139) or TYPE=AUDIO)
      final audioLineMatch = RegExp(r'#EXT-X-MEDIA:URI="([^"]+)",TYPE=AUDIO.*GROUP-ID="234"').firstMatch(m3u8Res.body) ??
          RegExp(r'#EXT-X-MEDIA:URI="([^"]+)",TYPE=AUDIO.*GROUP-ID="233"').firstMatch(m3u8Res.body) ??
          RegExp(r'#EXT-X-MEDIA:URI="([^"]+)",TYPE=AUDIO').firstMatch(m3u8Res.body);

      if (audioLineMatch == null) {
        throw const FormatException("Не найдена подходящая аудиодорожка в HLS манифесте");
      }

      final audioPlaylistUrl = audioLineMatch.group(1)!;

      // 5. Fetch audio segment list
      final subPlaylistRes = await client.get(
        Uri.parse(audioPlaylistUrl),
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
        },
      ).timeout(const Duration(seconds: 12));

      final segmentUrls = <String>[];
      for (final line in subPlaylistRes.body.split("\n")) {
        final trimmed = line.trim();
        if (trimmed.startsWith("https://") || trimmed.startsWith("http://")) {
          segmentUrls.add(trimmed);
        }
      }

      if (segmentUrls.isEmpty) {
        throw const FormatException("Плейлист аудиосегментов пуст");
      }

      // 6. Download segments sequentially, stripping ID3 tag on each to produce clean contiguous ADTS AAC
      final audioBuilder = BytesBuilder(copy: false);
      final totalSegments = segmentUrls.length;

      for (int i = 0; i < totalSegments; i++) {
        final segUrl = segmentUrls[i];
        final segRes = await client.get(
          Uri.parse(segUrl),
          headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
          },
        ).timeout(const Duration(seconds: 15));

        if (segRes.statusCode != 200) {
          throw HttpException("Ошибка скачивания сегмента $i (HTTP ${segRes.statusCode})");
        }

        final cleanChunk = _stripId3Header(segRes.bodyBytes);
        audioBuilder.add(cleanChunk);

        final ratio = ((i + 1) / totalSegments).clamp(0.0, 1.0);
        final pct = (ratio * 100).toInt();
        final dlMb = (audioBuilder.length / (1024 * 1024)).toStringAsFixed(1);
        final overallP = 0.20 + (ratio * 0.32);
        onProgress?.call("Загрузка аудио: $pct% ($dlMb МБ)...", overallP);
      }

      onProgress?.call("Распаковка аудиофайла...", 0.52);

      return DownloadedAudioResult(
        bytes: audioBuilder.takeBytes(),
        title: title,
        sourceUrl: normalized,
      );
    } finally {
      client.close();
    }
  }

  /// Downloads single continuous audio stream using YoutubeExplode (Fallback).
  static Future<DownloadedAudioResult> downloadWithYoutubeExplode(
    String videoId, {
    void Function(String status, double progress)? onProgress,
  }) async {
    final yt = yte.YoutubeExplode();
    try {
      onProgress?.call("Подключение через YoutubeExplode...", 0.10);
      final video = await yt.videos.get(videoId).timeout(const Duration(seconds: 8));
      final manifest = await yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 8));
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) {
        throw const FormatException("Не найден аудиопоток у видео");
      }

      final streamInfo = audioStreams.withHighestBitrate();
      final stream = yt.videos.streamsClient.get(streamInfo);
      final totalBytes = streamInfo.size.totalBytes;
      final builder = BytesBuilder(copy: false);
      int receivedBytes = 0;

      await for (final chunk in stream.timeout(const Duration(seconds: 12))) {
        builder.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final ratio = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          final pct = (ratio * 100).toInt();
          final dlMb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final overallP = 0.12 + (ratio * 0.40);
          onProgress?.call("Загрузка аудио: $pct% ($dlMb МБ)...", overallP);
        }
      }

      return DownloadedAudioResult(
        bytes: builder.takeBytes(),
        title: video.title,
        sourceUrl: "https://youtu.be/$videoId",
      );
    } finally {
      yt.close();
    }
  }

  /// Finds yt-dlp executable on the host machine (desktop fallback).
  static String? findYtDlpBinary() {
    if (Platform.isAndroid || Platform.isIOS) return null;

    final candidatePaths = [
      "/opt/homebrew/bin/yt-dlp",
      "/usr/local/bin/yt-dlp",
      "/usr/bin/yt-dlp",
      "yt-dlp",
    ];

    for (final path in candidatePaths) {
      if (path.startsWith("/")) {
        if (File(path).existsSync()) return path;
      }
    }

    try {
      final res = Process.runSync("which", ["yt-dlp"]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty && File(out).existsSync()) return out;
      }
    } catch (_) {}

    return null;
  }

  /// Finds ffmpeg binary location (desktop fallback).
  static String? findFfmpegBinary() {
    if (Platform.isAndroid || Platform.isIOS) return null;

    final candidatePaths = [
      "/usr/local/bin/ffmpeg",
      "/opt/homebrew/bin/ffmpeg",
      "/usr/bin/ffmpeg",
      "ffmpeg",
    ];

    for (final path in candidatePaths) {
      if (path.startsWith("/")) {
        if (File(path).existsSync()) return path;
      }
    }

    try {
      final res = Process.runSync("which", ["ffmpeg"]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty && File(out).existsSync()) return out;
      }
    } catch (_) {}

    return null;
  }

  /// Downloads audio from any supported URL (YouTube, SoundCloud, direct audio, yt-dlp).
  static Future<DownloadedAudioResult> downloadFromUrl(
    String url, {
    void Function(String status, double progress)? onProgress,
  }) async {
    final cleanUrl = normalizeUrl(url);
    if (cleanUrl.isEmpty) {
      throw const FormatException("URL не может быть пустым");
    }

    // 1. Direct audio URL (mp3, wav, aac, flac, ogg, m4a)
    final isDirectAudio = RegExp(r"\.(wav|mp3|m4a|aac|flac|ogg)(\?.*)?$", caseSensitive: false).hasMatch(cleanUrl);
    if (isDirectAudio) {
      onProgress?.call("Скачивание прямого аудиофайла...", 0.20);
      final bytes = await _downloadDirectFile(cleanUrl, onProgress: onProgress);
      final filename = Uri.parse(cleanUrl).pathSegments.isNotEmpty
          ? Uri.parse(cleanUrl).pathSegments.last.replaceAll(RegExp(r"\.[a-zA-Z0-9]+$"), "")
          : "Аудио по ссылке";
      return DownloadedAudioResult(bytes: bytes, title: filename, sourceUrl: cleanUrl);
    }

    // 2. Desktop yt-dlp first (fastest, cleanest 22050Hz WAV output, full duration)
    final ytDlp = findYtDlpBinary();
    if (ytDlp != null) {
      try {
        return await _downloadViaYtDlp(ytDlp, cleanUrl, onProgress: onProgress);
      } catch (_) {}
    }

    // 3. YouTube: High-speed VisionOS HLS pure-Dart engine (bypasses rate-limiting, 403, and SABR)
    if (isYouTubeUrl(cleanUrl)) {
      try {
        return await downloadYouTubeAudio(cleanUrl, onProgress: onProgress);
      } catch (e) {
        // Fallback: YoutubeExplode
        try {
          final vId = extractVideoId(cleanUrl);
          return await downloadWithYoutubeExplode(vId, onProgress: onProgress);
        } catch (_) {}
        throw Exception("Не удалось загрузить видео с YouTube: $e");
      }
    }

    // 4. Mobile unsupported non-YouTube links
    if (Platform.isAndroid || Platform.isIOS) {
      throw const FormatException(
        "На мобильных устройствах поддерживаются прямые ссылки на YouTube (видео / Shorts / Music) и аудиофайлы (.mp3, .wav, .m4a).",
      );
    }

    throw const FileSystemException(
      "Утилита yt-dlp не найдена в системе. Установите её через: brew install yt-dlp ffmpeg",
    );
  }

  static Future<DownloadedAudioResult> _downloadViaYtDlp(
    String ytDlp,
    String cleanUrl, {
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call("Получение информации о треке через yt-dlp...", 0.10);

    String title = "Аудио из сети";
    try {
      final titleResult = await Process.run(ytDlp, ["--no-playlist", "--print", "%(title)s", cleanUrl]);
      if (titleResult.exitCode == 0) {
        final rawTitle = titleResult.stdout.toString().trim();
        if (rawTitle.isNotEmpty) {
          title = rawTitle;
        }
      }
    } catch (_) {}

    onProgress?.call("Загрузка и конвертация аудиопотока в WAV (22050 Гц)...", 0.25);

    final tempDir = Directory.systemTemp;
    final fileId = "easy_violin_${DateTime.now().millisecondsSinceEpoch}";
    final outTemplate = "${tempDir.path}/$fileId.%(ext)s";
    final targetWav = "${tempDir.path}/$fileId.wav";

    final ffmpeg = findFfmpegBinary();
    final args = <String>[
      "--no-playlist",
      "-x",
      "--audio-format", "wav",
      "--audio-quality", "0",
      "--postprocessor-args", "ExtractAudio:-ar 22050 -ac 1",
      "-o", outTemplate,
    ];

    if (ffmpeg != null) {
      args.addAll(["--ffmpeg-location", ffmpeg]);
    }

    args.add(cleanUrl);

    final processResult = await Process.run(ytDlp, args);
    if (processResult.exitCode != 0) {
      final err = processResult.stderr.toString().trim();
      throw Exception("Ошибка yt-dlp: ${err.isNotEmpty ? err : processResult.stdout.toString()}");
    }

    final wavFile = File(targetWav);
    if (!wavFile.existsSync()) {
      final matchedFiles = tempDir.listSync().where((f) => f.path.contains(fileId)).toList();
      if (matchedFiles.isNotEmpty) {
        final f = File(matchedFiles.first.path);
        final bytes = await f.readAsBytes();
        try { f.deleteSync(); } catch (_) {}
        return DownloadedAudioResult(bytes: bytes, title: title, sourceUrl: cleanUrl);
      }
      throw const FileSystemException("Не удалось найти сгенерированный WAV файл");
    }

    final bytes = await wavFile.readAsBytes();
    try { wavFile.deleteSync(); } catch (_) {}

    return DownloadedAudioResult(
      bytes: bytes,
      title: title,
      sourceUrl: cleanUrl,
    );
  }

  static Future<Uint8List> _downloadDirectFile(
    String url, {
    void Function(String status, double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(normalizeUrl(url));
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        throw HttpException("HTTP ${resp.statusCode}: не удалось загрузить файл");
      }
      return resp.bodyBytes;
    } finally {
      client.close();
    }
  }
}
