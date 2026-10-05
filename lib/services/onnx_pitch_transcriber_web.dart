import 'dart:typed_data';
import '../models/song_model.dart';

/// Web fallback for OnnxPitchTranscriber.
///
/// On web platforms where native FFI is unavailable, transcription
/// automatically routes through the high-precision algorithmic MPM engine.
class OnnxPitchTranscriber {
  static const int kSampleRate = 22050;

  static bool get isAvailable => false;
  static dynamic get session => null;

  static Future<bool> initialize({Uint8List? customModelBytes}) async {
    return false;
  }

  static Future<List<SongNote>> transcribe({
    required Float32List audioSamples,
    double speedMultiplier = 1.0,
    double noteThreshold = 0.25,
    double onsetThreshold = 0.50,
    void Function(double progress, String status)? onProgress,
  }) async {
    return [];
  }
}
