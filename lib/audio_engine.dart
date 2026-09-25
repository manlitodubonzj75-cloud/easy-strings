import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io' show Platform;

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

  @Array<Uint8>(3)
  external Array<Uint8> reserved;
}

/// C++:
/// using PitchCallback = void (*)(PitchResult result);
typedef _PitchCallbackNative = Void Function(
  PitchResultNative result,
);

typedef _PitchCallbackDart = void Function(
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

/// -------------------------------------------------------------------------
/// Dart-level result
/// -------------------------------------------------------------------------

class PitchResult {
  final double frequencyHz;
  final double confidence;
  final bool isScratching;

  const PitchResult({
    required this.frequencyHz,
    required this.confidence,
    required this.isScratching,
  });

  @override
  String toString() {
    return 'PitchResult('
        'frequencyHz=$frequencyHz, '
        'confidence=$confidence, '
        'isScratching=$isScratching'
        ')';
  }
}

/// -------------------------------------------------------------------------
/// Worker isolate protocol
/// -------------------------------------------------------------------------

sealed class _WorkerCommand {}

final class _StartCommand extends _WorkerCommand {
  final SendPort replyPort;

  _StartCommand(this.replyPort);
}

final class _StopCommand extends _WorkerCommand {
  final SendPort replyPort;

  _StopCommand(this.replyPort);
}

/// -------------------------------------------------------------------------
/// Public engine
/// -------------------------------------------------------------------------

class AudioEngine {
  Isolate? _workerIsolate;

  SendPort? _workerCommandPort;

  ReceivePort? _resultReceivePort;

  Pointer<Void>? _nativeHandle;

  DynamicLibrary? _mainLibrary;

  _CreateDart? _create;
  _StartDart? _start;
  _StopDart? _stop;
  _DestroyDart? _destroy;
  _PushSamplesDart? _pushSamples;

  Stream<PitchResult>? _results;

  /// Start the C++ worker and Dart callback isolate.
  Future<Stream<PitchResult>> start() async {
    if (_workerIsolate != null) {
      throw StateError('AudioEngine is already running');
    }

    final resultPort = ReceivePort();

    final initPort = ReceivePort();

    final isolate = await Isolate.spawn(
      _workerMain,
      initPort.sendPort,
      debugName: 'violin-dsp-worker',
    );

    _workerIsolate = isolate;

    final SendPort workerCommandPort =
        await initPort.first as SendPort;

    _workerCommandPort = workerCommandPort;

    // Create a response stream.
    final controller =
        StreamController<PitchResult>.broadcast();

    _results = controller.stream;

    resultPort.listen((dynamic message) {
      if (message is PitchResult) {
        controller.add(message);
      }
    });

    // Tell worker isolate which port should receive results.
    workerCommandPort.send(
      _WorkerStartPayload(
        resultPort.sendPort,
      ),
    );

    final startResponse =
        ReceivePort();

    workerCommandPort.send(
      _WorkerInitializePayload(
        startResponse.sendPort,
      ),
    );

    final reply =
        await startResponse.first;

    startResponse.close();

    if (reply is int) {
      _nativeHandle =
          Pointer<Void>.fromAddress(reply);
    } else {
      resultPort.close();
      await controller.close();

      isolate.kill(
        priority: Isolate.immediate,
      );

      _workerIsolate = null;
      _workerCommandPort = null;

      throw StateError(
        'Failed to initialize native violin processor',
      );
    }

    _openMainLibrary();

    return _results!;
  }

  /// The native audio callback should call this method with its
  /// already-owned native PCM buffer.
  ///
  /// IMPORTANT:
  ///   - Do not allocate a Dart Float32List here.
  ///   - Do not copy PCM into Dart.
  ///   - The pointer must remain valid while this FFI call executes.
  ///
  /// The recommended production integration is to expose the native
  /// microphone buffer directly from the iOS/Android audio layer.
  int pushSamples(
    Pointer<Float> samples,
    int count,
  ) {
    final handle = _nativeHandle;

    if (handle == null) {
      return 0;
    }

    final push = _pushSamples;

    if (push == null) {
      throw StateError(
        'Native audio processor is not initialized',
      );
    }

    return push(
      handle,
      samples,
      count,
    );
  }

  Stream<PitchResult> get results {
    final stream = _results;

    if (stream == null) {
      throw StateError(
        'AudioEngine has not been started',
      );
    }

    return stream;
  }

  Future<void> stop() async {
    final commandPort = _workerCommandPort;

    if (commandPort == null) {
      return;
    }

    final responsePort = ReceivePort();

    commandPort.send(
      _WorkerStopPayload(
        responsePort.sendPort,
      ),
    );

    await responsePort.first;

    responsePort.close();

    _workerIsolate?.kill(
      priority: Isolate.immediate,
    );

    _workerIsolate = null;
    _workerCommandPort = null;
    _nativeHandle = null;

    _mainLibrary = null;

    _create = null;
    _start = null;
    _stop = null;
    _destroy = null;
    _pushSamples = null;

    await Future<void>.value();
  }

  void dispose() {
    _resultReceivePort?.close();
    _resultReceivePort = null;
  }

  void _openMainLibrary() {
    final library = _openLibrary();

    _mainLibrary = library;

    _create = library
        .lookupFunction<_CreateNative, _CreateDart>(
          'violin_processor_create',
        );

    _start = library
        .lookupFunction<_StartNative, _StartDart>(
          'violin_processor_start',
        );

    _stop = library
        .lookupFunction<_StopNative, _StopDart>(
          'violin_processor_stop',
        );

    _destroy = library
        .lookupFunction<_DestroyNative, _DestroyDart>(
          'violin_processor_destroy',
        );

    _pushSamples = library
        .lookupFunction<
            _PushSamplesNative,
            _PushSamplesDart>(
          'violin_processor_push_samples',
        );
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isIOS) {
      // For iOS the native symbols are typically linked into the app.
      return DynamicLibrary.process();
    }

    if (Platform.isAndroid) {
      return DynamicLibrary.open(
        'libviolin_engine.so',
      );
    }

    throw UnsupportedError(
      'Unsupported platform',
    );
  }
}

/// -------------------------------------------------------------------------
/// Worker-isolate messages
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
        library = _openWorkerLibrary();

        final create =
            library!.lookupFunction<
                _CreateNative,
                _CreateDart>(
              'violin_processor_create',
            );

        nativeStart =
            library!.lookupFunction<
                _StartNative,
                _StartDart>(
              'violin_processor_start',
            );

        nativeStop =
            library!.lookupFunction<
                _StopNative,
                _StopDart>(
              'violin_processor_stop',
            );

        nativeDestroy =
            library!.lookupFunction<
                _DestroyNative,
                _DestroyDart>(
              'violin_processor_destroy',
            );

        nativeSetCallback =
            library!.lookupFunction<
                _SetCallbackNative,
                _SetCallbackDart>(
              'violin_processor_set_callback',
            );

        handle = create(44100.0);

        if (handle == null ||
            handle!.address == 0) {
          message.replyPort.send(0);
          return;
        }

        /**
         * NativeCallable.listener is the correct callback mode here:
         *
         * C++ DSP worker
         *       |
         *       v
         * NativeCallable listener trampoline
         *       |
         *       v
         * Dart worker isolate
         *       |
         *       v
         * ReceivePort in UI isolate
         *
         * The native worker is not calling an isolate-local Dart function
         * directly.
         */
        callback = NativeCallable<
            _PitchCallbackNative>.listener(
          (PitchResultNative nativeResult) {
            final port = resultPort;

            if (port == null) {
              return;
            }

            /**
             * This is deliberately the first place where we construct
             * a Dart object. It is therefore OUTSIDE the native realtime
             * DSP code.
             *
             * The native worker has already completed its calculation.
             */
            port.send(
              PitchResult(
                frequencyHz:
                    nativeResult.frequencyHz,
                confidence:
                    nativeResult.confidence,
                isScratching:
                    nativeResult.isScratching != 0,
              ),
            );
          },
        );

        nativeSetCallback!(
          handle!,
          callback!.nativeFunction,
        );

        started =
            nativeStart!(handle!) != 0;

        if (!started) {
          callback?.close();
          callback = null;

          nativeDestroy!(handle!);

          handle = null;

          message.replyPort.send(0);
          return;
        }

        /**
         * OLTW INTEGRATION POINT
         * ----------------------------------------
         * Do NOT execute OLTW here synchronously from the native callback.
         *
         * Preferred pipeline:
         *
         * C++:
         *    PCM -> MPM -> timbre -> PitchResult
         *
         * Dart worker isolate:
         *    PitchResult -> temporal smoothing
         *                -> OLTW
         *                -> note alignment
         *
         * UI isolate:
         *    note alignment -> rendering
         *
         * This keeps OLTW's potentially expensive dynamic-programming
         * work outside the hard realtime DSP path.
         */

        message.replyPort.send(
          handle!.address,
        );
      } catch (_) {
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

        /**
         * stop() joins the C++ worker thread.
         * Therefore, after it returns, the callback can safely be closed.
         */
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

DynamicLibrary _openWorkerLibrary() {
  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }

  if (Platform.isAndroid) {
    return DynamicLibrary.open(
      'libviolin_engine.so',
    );
  }

  throw UnsupportedError(
    'Unsupported platform',
  );
}