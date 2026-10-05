import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'services/song_audio_generator.dart';

class PitchResult {
  final double frequencyHz;
  final double confidence;
  final bool isScratching;
  final bool isLegato;
  final double rmsEnergy;

  const PitchResult({
    required this.frequencyHz,
    required this.confidence,
    required this.isScratching,
    this.isLegato = false,
    this.rmsEnergy = 0.0,
  });

  @override
  String toString() {
    return 'PitchResult('
        'frequencyHz=${frequencyHz.toStringAsFixed(1)}, '
        'confidence=${(confidence * 100).toStringAsFixed(0)}%, '
        'isScratching=$isScratching, '
        'isLegato=$isLegato, '
        'rmsEnergy=${(rmsEnergy * 100).toStringAsFixed(0)}%'
        ')';
  }
}

/// Web implementation of AudioEngine using Web Audio API and HTML5 getUserMedia.
class AudioEngine {
  static Future<bool> ensureRecordAudioPermission() async {
    return true;
  }

  web.AudioContext? _audioCtx;
  web.AudioBufferSourceNode? _activeSource;
  web.MediaStream? _micStream;
  web.AnalyserNode? _analyser;

  Timer? _micTimer;
  Timer? _toneTimer;
  bool _isTonePlayingDart = false;
  bool _isMicActive = false;
  bool _isRunning = false;

  StreamController<PitchResult>? _controller;
  Stream<PitchResult>? _results;
  PitchResult? _lastPitchResult;

  PitchResult? get lastPitchResult => _lastPitchResult;
  bool get isRunning => _isRunning;
  bool get isMicActive => _isMicActive;
  bool get isTonePlaying => _isTonePlayingDart;

  Stream<PitchResult> get results {
    final stream = _results;
    if (stream == null) {
      throw StateError('AudioEngine has not been started');
    }
    return stream;
  }

  Future<Stream<PitchResult>> start() async {
    if (_isRunning) {
      return _results!;
    }
    final controller = StreamController<PitchResult>.broadcast();
    _controller = controller;
    _results = controller.stream;
    _isRunning = true;
    return _results!;
  }

  bool startMic() {
    try {
      _audioCtx ??= web.AudioContext();
      final ctx = _audioCtx!;
      if (ctx.state == 'suspended') {
        ctx.resume();
      }

      web.window.navigator.mediaDevices.getUserMedia(
        web.MediaStreamConstraints(audio: true.toJS),
      ).toDart.then((stream) {
        _micStream = stream;
        final source = ctx.createMediaStreamSource(stream);
        final analyser = ctx.createAnalyser();
        analyser.fftSize = 2048;
        source.connect(analyser);
        _analyser = analyser;
        _isMicActive = true;

        final timeData = Float32List(2048);
        _micTimer?.cancel();
        _micTimer = Timer.periodic(const Duration(milliseconds: 25), (_) {
          if (!_isMicActive || _analyser == null) return;
          _analyser!.getFloatTimeDomainData(timeData.toJS);
          _detectPitch(timeData);
        });
      }).catchError((_) {
        _isMicActive = false;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void stopMic() {
    _micTimer?.cancel();
    _micTimer = null;
    _isMicActive = false;
    if (_micStream != null) {
      final tracks = _micStream!.getTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
      _micStream = null;
    }
    _analyser = null;
  }

  void playPcmBuffer(Float32List samples) {
    if (samples.isEmpty) return;
    try {
      _audioCtx ??= web.AudioContext();
      final ctx = _audioCtx!;
      if (ctx.state == 'suspended') {
        ctx.resume();
      }

      _activeSource?.stop();
      _activeSource = null;

      final buffer = ctx.createBuffer(1, samples.length, 44100);
      final channelData = buffer.getChannelData(0).toDart;
      channelData.setAll(0, samples);

      final source = ctx.createBufferSource();
      source.buffer = buffer;
      source.connect(ctx.destination);
      source.start();
      _activeSource = source;

      _isTonePlayingDart = true;
      _toneTimer?.cancel();
      final durSec = samples.length / 44100.0;
      _toneTimer = Timer(Duration(milliseconds: (durSec * 1000).toInt() + 80), () {
        _isTonePlayingDart = false;
      });
    } catch (_) {}
  }

  void playTone(double frequencyHz, [double durationSec = 1.0]) {
    if (frequencyHz <= 20.0) return;
    final pcm = SongAudioGenerator.generateSingleNotePcm(frequencyHz, durationSec);
    playPcmBuffer(pcm);
  }

  void playSyntheticNote(double frequencyHz, [double durationSec = 1.0]) {
    playTone(frequencyHz, durationSec);
  }

  void stopTone() {
    _toneTimer?.cancel();
    _isTonePlayingDart = false;
    try {
      _activeSource?.stop();
      _activeSource = null;
    } catch (_) {}
  }

  void pushSynthNote(double frequencyHz, [double durationSec = 1.0]) {
    playTone(frequencyHz, durationSec);
  }

  Future<void> stop() async {
    stopTone();
    stopMic();
    _isRunning = false;
    await _controller?.close();
    _controller = null;
    _results = null;
  }

  void dispose() {
    stop();
    try {
      _audioCtx?.close();
      _audioCtx = null;
    } catch (_) {}
  }

  /// Autocorrelation pitch detector for Web
  void _detectPitch(Float32List buffer) {
    if (_isTonePlayingDart) return;

    double sumSq = 0.0;
    for (int i = 0; i < buffer.length; i++) {
      sumSq += buffer[i] * buffer[i];
    }
    final rms = math.sqrt(sumSq / buffer.length);
    if (rms < 0.015) {
      return; // Room noise / silence
    }

    // Normalized autocorrelation
    const minPeriod = 30;  // ~1470 Hz
    const maxPeriod = 225; // ~196 Hz (G3)
    double maxCorr = -1.0;
    int bestPeriod = -1;

    for (int tau = minPeriod; tau <= maxPeriod; tau++) {
      double corr = 0.0;
      for (int i = 0; i < 1024; i++) {
        corr += buffer[i] * buffer[i + tau];
      }
      if (corr > maxCorr) {
        maxCorr = corr;
        bestPeriod = tau;
      }
    }

    final confidence = (maxCorr / (sumSq * 0.5)).clamp(0.0, 1.0);
    if (confidence >= 0.45 && bestPeriod > 0) {
      final hz = 44100.0 / bestPeriod;
      final res = PitchResult(
        frequencyHz: hz,
        confidence: confidence,
        isScratching: false,
        rmsEnergy: (rms * 10.0).clamp(0.0, 1.0),
      );
      _lastPitchResult = res;
      _controller?.add(res);
    }
  }
}
