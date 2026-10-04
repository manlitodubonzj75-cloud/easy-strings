import 'dart:async';
import 'dart:ffi';
import 'dart:io' show File, Platform, Directory;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show MethodChannel;

/// -------------------------------------------------------------------------
/// Native ABI
/// -------------------------------------------------------------------------

final class PitchResultNative extends Struct {
  @Float()
  external double frequencyHz;

  @Float()
  external double confidence;

  @Uint8()
  external int isScratching;

  @Uint8()
  external int isLegato;

  @Uint8()
  external int rmsEnergy;

  @Uint8()
  external int reserved;
}

typedef _PitchCallbackNative = Void Function(
  PitchResultNative result,
);

typedef _CreateNative = Pointer<Void> Function(Float sampleRate);
typedef _CreateDart = Pointer<Void> Function(double sampleRate);

typedef _StartNative = Int32 Function(Pointer<Void> handle);
typedef _StartDart = int Function(Pointer<Void> handle);

typedef _StopNative = Void Function(Pointer<Void> handle);
typedef _StopDart = void Function(Pointer<Void> handle);

typedef _DestroyNative = Void Function(Pointer<Void> handle);
typedef _DestroyDart = void Function(Pointer<Void> handle);

typedef _PushSamplesNative = Size Function(
  Pointer<Void> handle,
  Pointer<Float> samples,
  Size count,
);
typedef _PushSamplesDart = int Function(
  Pointer<Void> handle,
  Pointer<Float> samples,
  int count,
);

typedef _SetCallbackNative = Void Function(
  Pointer<Void> handle,
  Pointer<NativeFunction<_PitchCallbackNative>> callback,
);
typedef _SetCallbackDart = void Function(
  Pointer<Void> handle,
  Pointer<NativeFunction<_PitchCallbackNative>> callback,
);

typedef _StartMicNative = Int32 Function(Pointer<Void> handle);
typedef _StartMicDart = int Function(Pointer<Void> handle);

typedef _StopMicNative = Void Function(Pointer<Void> handle);
typedef _StopMicDart = void Function(Pointer<Void> handle);

typedef _IsMicActiveNative = Int32 Function(Pointer<Void> handle);
typedef _IsMicActiveDart = int Function(Pointer<Void> handle);

typedef _PushSynthNoteNative = Void Function(
  Pointer<Void> handle,
  Float frequencyHz,
  Float durationSec,
);
typedef _PushSynthNoteDart = void Function(
  Pointer<Void> handle,
  double frequencyHz,
  double durationSec,
);

typedef _PlayToneNative = Void Function(
  Float frequencyHz,
  Float durationSec,
);
typedef _PlayToneDart = void Function(
  double frequencyHz,
  double durationSec,
);

typedef _StopToneNative = Void Function();
typedef _StopToneDart = void Function();

typedef _PlayPcmBufferNative = Void Function(Pointer<Float>, Int32);
typedef _PlayPcmBufferDart = void Function(Pointer<Float>, int);

typedef _IsTonePlayingNative = Int32 Function();
typedef _IsTonePlayingDart = int Function();

/// -------------------------------------------------------------------------
/// Dart-level result
/// -------------------------------------------------------------------------

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

/// -------------------------------------------------------------------------
/// Worker isolate protocol
/// -------------------------------------------------------------------------

final class _WorkerStartPayload {
  final SendPort resultPort;
  _WorkerStartPayload(this.resultPort);
}

final class _WorkerInitializePayload {
  final SendPort replyPort;
  _WorkerInitializePayload(this.replyPort);
}

final class _WorkerStopPayload {
  final SendPort replyPort;
  _WorkerStopPayload(this.replyPort);
}

/// -------------------------------------------------------------------------
/// Public Audio Engine
/// -------------------------------------------------------------------------

class AudioEngine {
  static const MethodChannel _permissionsChannel =
      MethodChannel('com.easyviolin.easy_violin/permissions');

  static Future<bool> ensureRecordAudioPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool hasPermission =
          await _permissionsChannel.invokeMethod<bool>('hasRecordAudioPermission') ?? false;
      if (hasPermission) return true;
      final bool granted =
          await _permissionsChannel.invokeMethod<bool>('requestRecordAudioPermission') ?? false;
      return granted;
    } catch (_) {
      return false;
    }
  }

  Isolate? _workerIsolate;
  SendPort? _workerCommandPort;
  ReceivePort? _resultReceivePort;

  Pointer<Void>? _nativeHandle;
  DynamicLibrary? _mainLibrary;

  DynamicLibrary? get mainLibrary => _mainLibrary;

  _StartMicDart? _startMic;
  _StopMicDart? _stopMic;
  _IsMicActiveDart? _isMicActive;
  _PushSamplesDart? _pushSamples;
  _PushSynthNoteDart? _pushSynthNote;
  _PlayToneDart? _playTone;
  _StopToneDart? _stopTone;
  _IsTonePlayingDart? _isTonePlayingNative;
  _PlayPcmBufferDart? _playPcmBuffer;
  bool _isTonePlayingDart = false;
  Timer? _tonePlayingTimer;

  bool get isTonePlaying {
    final nativeCheck = _isTonePlayingNative;
    if (nativeCheck != null && nativeCheck() != 0) {
      return true;
    }
    return _isTonePlayingDart;
  }

  StreamController<PitchResult>? _controller;
  Stream<PitchResult>? _results;
  PitchResult? _lastPitchResult;

  PitchResult? get lastPitchResult => _lastPitchResult;

  bool get isRunning => _workerIsolate != null;

  bool get isMicActive {
    final handle = _nativeHandle;
    final fn = _isMicActive;
    if (handle == null || fn == null) return false;
    return fn(handle) != 0;
  }

  /// Start the C++ worker and Dart callback isolate.
  Future<Stream<PitchResult>> start() async {
    if (_workerIsolate != null) {
      throw StateError('AudioEngine is already running');
    }

    final resultPort = ReceivePort();
    _resultReceivePort = resultPort;

    final initPort = ReceivePort();

    final isolate = await Isolate.spawn(
      _workerMain,
      initPort.sendPort,
      debugName: 'violin-dsp-worker',
    );

    _workerIsolate = isolate;

    final SendPort workerCommandPort = await initPort.first as SendPort;
    initPort.close();
    _workerCommandPort = workerCommandPort;

    final controller = StreamController<PitchResult>.broadcast();
    _controller = controller;
    _results = controller.stream;

    resultPort.listen((dynamic message) {
      if (message is PitchResult) {
        _lastPitchResult = message;
        controller.add(message);
      }
    });

    workerCommandPort.send(
      _WorkerStartPayload(resultPort.sendPort),
    );

    final startResponse = ReceivePort();
    workerCommandPort.send(
      _WorkerInitializePayload(startResponse.sendPort),
    );

    final reply = await startResponse.first;
    startResponse.close();

    if (reply is int && reply != 0) {
      _nativeHandle = Pointer<Void>.fromAddress(reply);
    } else {
      resultPort.close();
      await controller.close();
      isolate.kill(priority: Isolate.immediate);

      _workerIsolate = null;
      _workerCommandPort = null;
      throw StateError('Failed to initialize native violin processor');
    }

    _openMainLibrary();

    return _results!;
  }

  bool startMic() {
    final handle = _nativeHandle;
    final fn = _startMic;
    if (handle == null || fn == null) {
      return false;
    }
    return fn(handle) != 0;
  }

  void stopMic() {
    final handle = _nativeHandle;
    final fn = _stopMic;
    if (handle == null || fn == null) return;
    fn(handle);
  }

  void pushSynthNote(double frequencyHz, [double durationSec = 1.0]) {
    final handle = _nativeHandle;
    final fn = _pushSynthNote;
    if (handle == null || fn == null) return;
    fn(handle, frequencyHz, durationSec);
  }

  void playPcmBuffer(Float32List samples) {
    if (samples.isEmpty) return;
    _isTonePlayingDart = true;
    _tonePlayingTimer?.cancel();
    final durSec = samples.length / 44100.0;
    _tonePlayingTimer = Timer(Duration(milliseconds: (durSec * 1000).toInt() + 100), () {
      _isTonePlayingDart = false;
    });

    final fn = _playPcmBuffer;
    if (fn != null) {
      final ptr = calloc<Float>(samples.length);
      ptr.asTypedList(samples.length).setAll(0, samples);
      fn(ptr, samples.length);
      calloc.free(ptr);
    }
  }

  void playTone(double frequencyHz, [double durationSec = 1.0]) {
    _isTonePlayingDart = true;
    _tonePlayingTimer?.cancel();
    _tonePlayingTimer = Timer(Duration(milliseconds: (durationSec * 1000).toInt() + 100), () {
      _isTonePlayingDart = false;
    });

    final fn = _playTone;
    if (fn != null) {
      fn(frequencyHz, durationSec);
    } else {
      pushSynthNote(frequencyHz, durationSec);
    }
  }

  /// Immediately silences any active acoustic tone or synthesizer output.
  void stopTone() {
    _tonePlayingTimer?.cancel();
    _isTonePlayingDart = false;
    final fn = _stopTone;
    if (fn != null) {
      fn();
    }
  }

  void playSyntheticNote(double frequencyHz, [double durationSec = 1.0]) {
    playTone(frequencyHz, durationSec);
  }

  int pushSamples(
    Pointer<Float> samples,
    int count,
  ) {
    final handle = _nativeHandle;
    final push = _pushSamples;
    if (handle == null || push == null) return 0;
    return push(handle, samples, count);
  }

  Stream<PitchResult> get results {
    final stream = _results;
    if (stream == null) {
      throw StateError('AudioEngine has not been started');
    }
    return stream;
  }

  Future<void> stop() async {
    final commandPort = _workerCommandPort;
    if (commandPort == null) return;

    stopTone();
    stopMic();

    final responsePort = ReceivePort();
    commandPort.send(_WorkerStopPayload(responsePort.sendPort));
    await responsePort.first;
    responsePort.close();

    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerCommandPort = null;
    _nativeHandle = null;

    _mainLibrary = null;
    _startMic = null;
    _stopMic = null;
    _isMicActive = null;
    _pushSamples = null;
    _pushSynthNote = null;
    _playTone = null;
    _stopTone = null;

    _resultReceivePort?.close();
    _resultReceivePort = null;
    await _controller?.close();
    _controller = null;
    _results = null;
  }

  void dispose() {
    stop();
  }

  void _openMainLibrary() {
    final library = _openLibrary();
    _mainLibrary = library;

    _startMic = library.lookupFunction<_StartMicNative, _StartMicDart>(
      'violin_processor_start_mic',
    );
    _stopMic = library.lookupFunction<_StopMicNative, _StopMicDart>(
      'violin_processor_stop_mic',
    );
    _isMicActive = library.lookupFunction<_IsMicActiveNative, _IsMicActiveDart>(
      'violin_processor_is_mic_active',
    );
    _pushSamples = library.lookupFunction<_PushSamplesNative, _PushSamplesDart>(
      'violin_processor_push_samples',
    );
    _pushSynthNote = library.lookupFunction<_PushSynthNoteNative, _PushSynthNoteDart>(
      'violin_processor_push_synth_note',
    );
    try {
      _playTone = library.lookupFunction<_PlayToneNative, _PlayToneDart>('violin_play_tone');
    } catch (_) {}
    try {
      _stopTone = library.lookupFunction<_StopToneNative, _StopToneDart>('violin_stop_tone');
    } catch (_) {}
    try {
      _playPcmBuffer = library.lookupFunction<_PlayPcmBufferNative, _PlayPcmBufferDart>('violin_play_pcm_buffer');
    } catch (_) {}
    try {
      _isTonePlayingNative = library.lookupFunction<_IsTonePlayingNative, _IsTonePlayingDart>('violin_is_tone_playing');
    } catch (_) {}
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }

    if (Platform.isAndroid) {
      return DynamicLibrary.open('libviolin_engine.so');
    }

    if (Platform.isMacOS) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir/../Frameworks/libviolin_engine.dylib',
        '$exeDir/libviolin_engine.dylib',
        'libviolin_engine.dylib',
        '${Directory.current.path}/libviolin_engine.dylib',
        '/Users/user/Documents/творчество/easy-violin/libviolin_engine.dylib',
      ];

      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          try {
            return DynamicLibrary.open(candidate);
          } catch (_) {}
        }
      }

      return DynamicLibrary.open('libviolin_engine.dylib');
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

/// -------------------------------------------------------------------------
/// Worker isolate
/// -------------------------------------------------------------------------

void _workerMain(SendPort parentPort) {
  final commandPort = ReceivePort();
  parentPort.send(commandPort.sendPort);

  DynamicLibrary? library;
  NativeCallable<_PitchCallbackNative>? callback;

  Pointer<Void>? handle;
  SendPort? resultPort;

  _StartDart? nativeStart;
  _StopDart? nativeStop;
  _DestroyDart? nativeDestroy;
  _SetCallbackDart? nativeSetCallback;

  bool started = false;

  commandPort.listen((dynamic message) {
    if (message is _WorkerStartPayload) {
      resultPort = message.resultPort;
      return;
    }

    if (message is _WorkerInitializePayload) {
      try {
        library = AudioEngine._openLibrary();

        final create = library!.lookupFunction<_CreateNative, _CreateDart>(
          'violin_processor_create',
        );

        nativeStart = library!.lookupFunction<_StartNative, _StartDart>(
          'violin_processor_start',
        );

        nativeStop = library!.lookupFunction<_StopNative, _StopDart>(
          'violin_processor_stop',
        );

        nativeDestroy = library!.lookupFunction<_DestroyNative, _DestroyDart>(
          'violin_processor_destroy',
        );

        nativeSetCallback =
            library!.lookupFunction<_SetCallbackNative, _SetCallbackDart>(
          'violin_processor_set_callback',
        );

        handle = create(44100.0);

        if (handle == null || handle!.address == 0) {
          message.replyPort.send(0);
          return;
        }

        callback = NativeCallable<_PitchCallbackNative>.listener(
          (PitchResultNative nativeResult) {
            final port = resultPort;
            if (port == null) return;

            port.send(
              PitchResult(
                frequencyHz: nativeResult.frequencyHz,
                confidence: nativeResult.confidence,
                isScratching: nativeResult.isScratching != 0,
                isLegato: nativeResult.isLegato != 0,
                rmsEnergy: nativeResult.rmsEnergy / 255.0,
              ),
            );
          },
        );

        nativeSetCallback!(
          handle!,
          callback!.nativeFunction,
        );

        started = nativeStart!(handle!) != 0;

        if (!started) {
          callback?.close();
          callback = null;
          nativeDestroy!(handle!);
          handle = null;
          message.replyPort.send(0);
          return;
        }

        message.replyPort.send(handle!.address);
      } catch (e) {
        message.replyPort.send(0);
      }

      return;
    }

    if (message is _WorkerStopPayload) {
      if (handle != null) {
        if (started) {
          nativeStop?.call(handle!);
          started = false;
        }

        callback?.close();
        callback = null;

        nativeDestroy?.call(handle!);
        handle = null;
      }

      message.replyPort.send(true);
      commandPort.close();
      return;
    }
  });
}
