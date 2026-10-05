import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'audio_engine.dart';
import 'music_theory.dart';
import 'theme/apple_violin_theme.dart';
import 'services/settings_service.dart';
import 'ui/song_practice_screen.dart';
import 'ui/synth_test_panel.dart';
import 'ui/trainer_screen.dart';
import 'ui/tuner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EasyViolinApp());
}

class EasyViolinApp extends StatelessWidget {
  const EasyViolinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'easy violin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppleViolinTheme.darkBg,
        colorScheme: const ColorScheme.dark(
          primary: AppleViolinTheme.appleBlue,
          secondary: AppleViolinTheme.appleGreen,
          surface: AppleViolinTheme.cardDark,
        ),
        fontFamily: '-apple-system',
      ),
      home: const MainViolinScreen(),
    );
  }
}

class MainViolinScreen extends StatefulWidget {
  const MainViolinScreen({super.key});

  @override
  State<MainViolinScreen> createState() => _MainViolinScreenState();
}

class _MainViolinScreenState extends State<MainViolinScreen> {
  final AudioEngine _audioEngine = AudioEngine();
  StreamSubscription<PitchResult>? _pitchSub;
  final ValueNotifier<DetectedNoteInfo?> _noteNotifier = ValueNotifier<DetectedNoteInfo?>(null);
  SettingsService? _settings;

  int _selectedTabIndex = 0;
  ViolinString? _selectedTunerString;
  double _concertA4Hz = 440.0;
  bool _isMicActive = false;
  final bool _isMobileFrame = false;
  final bool _showDebugSynth = false;

  DetectedNoteInfo? _currentNote;
  double _smoothedHz = 0.0;
  DateTime _lastNoteTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initAudio();
  }

  Future<void> _loadSettings() async {
    final s = await SettingsService.init();
    if (mounted) {
      setState(() {
        _settings = s;
        _concertA4Hz = s.concertA4Hz;
        _selectedTabIndex = s.lastTab.clamp(0, 2);
      });
    }
  }

  Future<void> _initAudio() async {
    try {
      final stream = await _audioEngine.start();
      _pitchSub = stream.listen(_onPitchResult);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await AudioEngine.ensureRecordAudioPermission();
      }

      final micStarted = _audioEngine.startMic();
      if (mounted) {
        setState(() {
          _isMicActive = micStarted;
        });
      }
    } catch (_) {
      // Audio engine error
    }
  }

  void _onPitchResult(PitchResult result) {
    if (_audioEngine.isTonePlaying) {
      // Do not evaluate speaker output as student playing
      return;
    }
    final now = DateTime.now();
    // Filter faint phantom sounds, background noise & room hum
    if (result.frequencyHz <= 0 || result.confidence < 0.35) {
      if (now.difference(_lastNoteTime).inMilliseconds > 450) {
        if (_currentNote != null || _noteNotifier.value != null) {
          _noteNotifier.value = null;
          _smoothedHz = 0.0;
          if (mounted) {
            setState(() {
              _currentNote = null;
            });
          }
        }
      }
      return;
    }

    _lastNoteTime = now;

    // Logarithmic cents distance filter for pitch stabilization:
    // Avoids resetting on small intervals in high registers, while immediately
    // responding to distinct note changes (> 75 cents) or initial onsets.
    double deltaCents = 999.0;
    if (_smoothedHz > 0.0 && result.frequencyHz > 0.0) {
      deltaCents = (1200.0 * (math.log(result.frequencyHz / _smoothedHz) / math.ln2)).abs();
    }

    if (_smoothedHz == 0.0 || deltaCents > 75.0) {
      _smoothedHz = result.frequencyHz;
    } else {
      // Smooth micro-pitch variations (vibrato and bow jitter) within the same note
      _smoothedHz = _smoothedHz * 0.30 + result.frequencyHz * 0.70;
    }

    final note = MusicTheory.analyzePitch(
      _smoothedHz,
      result.confidence,
      result.isScratching,
      targetString: _selectedTabIndex == 0 ? _selectedTunerString : null,
      concertA4Hz: _concertA4Hz,
    );

    _noteNotifier.value = note;
    if (mounted) {
      setState(() {
        _currentNote = note;
      });
    }
  }

  void _toggleMic(bool enable) async {
    if (enable) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final hasPermission = await AudioEngine.ensureRecordAudioPermission();
        if (!hasPermission) {
          if (mounted) {
            setState(() {
              _isMicActive = false;
            });
          }
          return;
        }
      }
      final ok = _audioEngine.startMic();
      if (mounted) {
        setState(() {
          _isMicActive = ok;
        });
      }
    } else {
      _audioEngine.stopMic();
      if (mounted) {
        setState(() {
          _isMicActive = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pitchSub?.cancel();
    _noteNotifier.dispose();
    _audioEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = mediaQuery.size.width >= 560;

    Widget coreApp = Scaffold(
      backgroundColor: AppleViolinTheme.darkBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Main Body by Tab (3 Tabs: Тюнер, Гаммы, Пьесы)
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: [
                  TunerScreen(
                    audioEngine: _audioEngine,
                    currentNote: _currentNote,
                    selectedString: _selectedTunerString,
                    concertA4Hz: _concertA4Hz,
                    isMobileMode: true,
                    onConcertPitchChanged: (pitch) {
                      setState(() {
                        _concertA4Hz = pitch;
                      });
                      _settings?.setConcertA4Hz(pitch);
                    },
                    onStringSelected: (str) {
                      setState(() {
                        _selectedTunerString = str;
                      });
                    },
                  ),
                  TrainerScreen(
                    audioEngine: _audioEngine,
                    currentNote: _currentNote,
                    noteNotifier: _noteNotifier,
                  ),
                  SongPracticeScreen(
                    audioEngine: _audioEngine,
                    currentNote: _currentNote,
                    noteNotifier: _noteNotifier,
                    isMobileMode: true,
                  ),
                ],
              ),
            ),

            // Collapsible Debug Synth Panel (if toggled)
            if (_showDebugSynth)
              SynthTestPanel(
                audioEngine: _audioEngine,
                isMicActive: _isMicActive,
                isMobileMode: true,
                onMicToggle: _toggleMic,
              ),

            // Apple HIG Bottom Navigation Bar & Home Bar Indicator
            _buildAppleTabBar(),
          ],
        ),
      ),
    );

    if (isDesktop && !_isMobileFrame) {
      // Center in a realistic iPhone chassis frame on desktop screens
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0E),
        body: Center(
          child: Container(
            width: 420,
            height: math.min(mediaQuery.size.height, 880.0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppleViolinTheme.darkBg,
              borderRadius: BorderRadius.circular(48),
              border: Border.all(color: const Color(0xFF2C2C2E), width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: coreApp,
          ),
        ),
      );
    }

    return coreApp;
  }

  Widget _buildAppleTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6161618),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTabItem(0, Icons.adjust_rounded, 'Тюнер'),
                _buildTabItem(1, Icons.queue_music_rounded, 'Гаммы'),
                _buildTabItem(2, Icons.music_note_rounded, 'Пьесы'),
              ],
            ),
          ),
          // iOS Home Bar Indicator
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Container(
              width: 134,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
        _settings?.setLastTab(index);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: isSelected ? AppleViolinTheme.appleBlue : AppleViolinTheme.subtext,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppleViolinTheme.appleBlue : AppleViolinTheme.subtext,
            ),
          ),
        ],
      ),
    );
  }
}
