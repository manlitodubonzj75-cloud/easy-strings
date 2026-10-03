import "package:easy_violin/services/url_audio_downloader.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  group("UrlAudioDownloader Tests", () {
    test("Normalizes URLs without scheme correctly", () {
      expect(UrlAudioDownloader.normalizeUrl("youtu.be/dQw4w9WgXcQ"), "https://youtu.be/dQw4w9WgXcQ");
      expect(UrlAudioDownloader.normalizeUrl("//www.youtube.com/watch?v=123"), "https://www.youtube.com/watch?v=123");
      expect(UrlAudioDownloader.normalizeUrl("  https://youtube.com/watch?v=123  "), "https://youtube.com/watch?v=123");
    });

    test("Identifies YouTube URLs correctly", () {
      expect(UrlAudioDownloader.isYouTubeUrl("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), isTrue);
      expect(UrlAudioDownloader.isYouTubeUrl("youtu.be/dQw4w9WgXcQ"), isTrue);
      expect(UrlAudioDownloader.isYouTubeUrl("https://music.youtube.com/watch?v=123"), isTrue);
      expect(UrlAudioDownloader.isYouTubeUrl("https://soundcloud.com/track"), isFalse);
    });

    test("Extracts video ID correctly", () {
      expect(UrlAudioDownloader.extractVideoId("https://youtu.be/0jXXWBt5URw"), "0jXXWBt5URw");
      expect(UrlAudioDownloader.extractVideoId("https://www.youtube.com/watch?v=0jXXWBt5URw"), "0jXXWBt5URw");
      expect(UrlAudioDownloader.extractVideoId("0jXXWBt5URw"), "0jXXWBt5URw");
    });

    test("Rejects empty URL with FormatException", () async {
      expect(
        () => UrlAudioDownloader.downloadFromUrl("   "),
        throwsA(isA<FormatException>()),
      );
    });

    test("Live test run: downloads Paganini Caprice No. 5 (0jXXWBt5URw)", () async {
      const testUrl = "https://youtu.be/0jXXWBt5URw";
      final progressUpdates = <(String, double)>[];

      final result = await UrlAudioDownloader.downloadYouTubeAudio(
        testUrl,
        onProgress: (status, p) {
          progressUpdates.add((status, p));
        },
      );

      expect(result.sourceUrl, equals(testUrl));
      expect(result.title.toLowerCase(), contains("paganini"));
      expect(result.bytes.isNotEmpty, isTrue);
      // Paganini Caprice No. 5 audio stream is ~2.5 MB (over 1 MB for sure)
      expect(result.bytes.length, greaterThan(1024 * 1024));
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last.$2, greaterThanOrEqualTo(0.5));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
