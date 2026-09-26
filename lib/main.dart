import 'dart:async';
import 'package:flutter/material.dart';
import 'audio_engine.dart';
import 'music_theory.dart';
import 'ui/fingerboard_screen.dart';
import 'ui/song_practice_screen.dart';
import 'ui/synth_test_panel.dart';
import 'ui/tuner_screen.dart';
import 'ui/trainer_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EasyViolinApp());
}

class EasyViolinApp extends StatelessWidget {
  const EasyViolinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Violin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0F17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF181B26),
        ),
        fontFamily: 'sans-serif',
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

  int _selectedTabIndex = 0;
  ViolinString? _selectedTunerString;
  double _concertA4Hz = 440.0;
  bool _isMicActive = false;
  bool _isMobileMode = false;
  String _statusMessage = 'Инициализация DSP движка...';

  DetectedNoteInfo? _currentNote;
  double _smoothedHz = 0.0;
  DateTime _lastNoteTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      final stream = await _audioEngine.start();
      _pitchSub = stream.listen(_onPitchResult);

      final micStarted = _audioEngine.startMic();
      setState(() {
        _isMicActive = micStarted;
        _statusMessage = micStarted
            ? 'Микрофон активен (44.1 kHz, CoreAudio)'
            : 'DSP движок готов (микрофон ожидает разрешения)';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Ошибка: $e';
      });
    }
  }

  void _onPitchResult(PitchResult result) {
    final now = DateTime.now();
    if (result.frequencyHz <= 0 || result.confidence < 0.45) {
      if (now.difference(_lastNoteTime).inMilliseconds > 400) {
        if (_currentNote != null) {
          setState(() {
            _currentNote = null;
          });
        }
      }
      return;
    }

    _lastNoteTime = now;

    // Exponential moving average filter for subtle pitch stabilization
    if (_smoothedHz == 0.0 || (result.frequencyHz - _smoothedHz).abs() > 40.0) {
      _smoothedHz = result.frequencyHz;
    } else {
      _smoothedHz = _smoothedHz * 0.4 + result.frequencyHz * 0.6;
    }

    final note = MusicTheory.analyzePitch(
      _smoothedHz,
      result.confidence,
      result.isScratching,
      targetString: _selectedTunerString,
      concertA4Hz: _concertA4Hz,
    );

    if (mounted) {
      setState(() {
        _currentNote = note;
      });
    }
  }

  void _toggleMic(bool enable) {
    if (enable) {
      final ok = _audioEngine.startMic();
      setState(() {
        _isMicActive = ok;
        _statusMessage = ok ? 'Микрофон включен' : 'Не удалось включить микрофон';
      });
    } else {
      _audioEngine.stopMic();
      setState(() {
        _isMicActive = false;
        _statusMessage = 'Микрофон отключен';
      });
    }
  }

  @override
  void dispose() {
    _pitchSub?.cancel();
    _audioEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final autoMobile = mediaQuery.size.width < 500;
    final effectiveMobile = _isMobileMode || autoMobile;

    final appContent = Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF141722),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.music_note, color: Color(0xFF6366F1), size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Easy Violin',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  _statusMessage,
                  style: const TextStyle(fontSize: 9, color: Colors.white38),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Mobile Mode Switcher Toggle
          IconButton(
            onPressed: () {
              setState(() {
                _isMobileMode = !_isMobileMode;
              });
            },
            icon: Icon(
              effectiveMobile ? Icons.phone_android : Icons.desktop_mac,
              color: effectiveMobile ? const Color(0xFF6366F1) : Colors.white60,
              size: 20,
            ),
            tooltip: effectiveMobile ? 'Включить десктопный вид' : 'Включить мобильный вид',
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isMicActive ? const Color(0xFF10B981) : Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isMicActive ? 'DSP' : 'Idle',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Main Body Screen by Tab
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [
                TunerScreen(
                  audioEngine: _audioEngine,
                  currentNote: _currentNote,
                  selectedString: _selectedTunerString,
                  concertA4Hz: _concertA4Hz,
                  isMobileMode: effectiveMobile,
                  onConcertPitchChanged: (pitch) {
                    setState(() {
                      _concertA4Hz = pitch;
                    });
                  },
                  onStringSelected: (str) {
                    setState(() {
                      _selectedTunerString = str;
                    });
                  },
                ),
                SongPracticeScreen(
                  audioEngine: _audioEngine,
                  currentNote: _currentNote,
                  isMobileMode: effectiveMobile,
                ),
                FingerboardScreen(
                  audioEngine: _audioEngine,
                  currentNote: _currentNote,
                ),
                TrainerScreen(
                  audioEngine: _audioEngine,
                  currentNote: _currentNote,
                ),
              ],
            ),
          ),

          // Bottom Test Synth / Mic Control Panel
          SynthTestPanel(
            audioEngine: _audioEngine,
            isMicActive: _isMicActive,
            isMobileMode: effectiveMobile,
            onMicToggle: _toggleMic,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141722),
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedTabIndex,
          onTap: (index) {
            setState(() {
              _selectedTabIndex = index;
            });
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF6366F1),
          unselectedItemColor: Colors.white38,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.tune),
              label: 'Тюнер',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.library_music_rounded),
              label: 'Пьесы',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.line_weight_sharp),
              label: 'Гриф',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.school_rounded),
              label: 'Уроки',
            ),
          ],
        ),
      ),
    );

    // If mobile preview requested on wide display, frame it like a mobile device
    if (_isMobileMode && mediaQuery.size.width > 550) {
      return Container(
        color: const Color(0xFF07090E),
        child: Center(
          child: Container(
            width: 410,
            height: 840,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white24, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 30,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: appContent,
            ),
          ),
        ),
      );
    }

    return appContent;
  }
}
