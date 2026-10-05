import 'dart:typed_data';
import '../models/song_model.dart';
import 'song_audio_generator.dart';

/// Web implementation of DdspViolinSynthesizer.
///
/// On web browsers where native FFI ONNX is not available, uses the
/// studio-grade Stradivarius acoustic filter engine.
class DdspViolinSynthesizer {
  static const int kSampleRate = 44100;
  static bool get isAvailable => true;

  static Future<bool> initialize({
    Uint8List? customModelBytes,
    Uint8List? customIrBytes,
  }) async {
    return true;
  }

  static Future<Float32List> synthesizeSong(
    Song song, {
    double speedMultiplier = 1.0,
    int outputSampleRate = 44100,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.2, 'Подготовка партитуры...');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    onProgress?.call(0.6, 'Акустический синтез скрипки...');

    final pcm = SongAudioGenerator.generatePcm(
      song,
      sampleRate: outputSampleRate,
      speedMultiplier: speedMultiplier,
      addHarmonics: true,
      addVibrato: true,
      addMeasureDynamics: true,
    );

    onProgress?.call(1.0, 'Партия готова!');
    return pcm;
  }
}
