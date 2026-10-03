import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../music_theory.dart';
import '../theme/apple_violin_theme.dart';
import 'widgets/circle_of_fifths_picker.dart';

class TrainerScreen extends StatefulWidget {
  final AudioEngine audioEngine;
  final DetectedNoteInfo? currentNote;
  final ValueNotifier<DetectedNoteInfo?>? noteNotifier;

  const TrainerScreen({
    super.key,
    required this.audioEngine,
    this.currentNote,
    this.noteNotifier,
  });

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen>
    with SingleTickerProviderStateMixin {
  /// All 24 algorithmic violin scales generated from solfège rules
  static final List<ViolinScaleDef> _scales = ScaleGenerator.all24Scales;

  /// Train-mode pill row — ♩ Фикс · Ускорение · Лигатура · Дробление · Пропуск · Случайно
  static const List<(String, String)> _trainModes = [
    ('fixed', '♩ Фикс'),
    ('accel', '♩+ Ускорение'),
    ('slur', '🎵 Лигатура'),
    ('split', '✂ Дробление'),
    ('skip', '? Пропуск'),
    ('random', '🌀 Случайно'),
  ];

  TonalityDef _selectedTonality = const TonalityDef(
    position: CirclePosition.pos2, // D Major (Ре мажор) - standard beginner scale
    mode: TonalityMode.major,
  );
  late ViolinScaleDef _currentScale;
  bool _showCircleOfFifths = false;
  int _selectedScaleIndex = 2; // Index of D Major
  int _currentStepIndex = 0;
  int _streak = 7;
  double _holdProgress = 0.0;
  Timer? _ticker;
  String _trainMode = 'fixed';
  late final AnimationController _pulse;

  bool _isReferencePlaying = false;
  Timer? _referenceTimer;
  bool _isFullScalePlaying = false;
  Timer? _fullScaleTimer;

  ViolinScaleDef get currentScale => _currentScale;
  ScaleNoteStep get currentStep => currentScale.steps[_currentStepIndex];

  @override
  void initState() {
    super.initState();
    _currentScale = ScaleGenerator.generateScale(_selectedTonality);
    _selectedScaleIndex = _scales.indexWhere((s) => s.tonality == _selectedTonality);
    if (_selectedScaleIndex < 0) _selectedScaleIndex = 0;

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _ticker = Timer.periodic(const Duration(milliseconds: 50), _onTick);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ticker?.cancel();
    _referenceTimer?.cancel();
    _fullScaleTimer?.cancel();
    super.dispose();
  }

  void _onTick(Timer _) {
    if (_isReferencePlaying || _isFullScalePlaying) {
      return;
    }
    final note = widget.noteNotifier?.value ?? widget.currentNote;
    if (note == null) {
      if (_holdProgress > 0) {
        setState(() {
          _holdProgress = math.max(0.0, _holdProgress - 0.04);
        });
      }
      return;
    }

    final isCorrectNote = note.midiNote == currentStep.midiNote;
    final isCleanBowing = !note.isScratching && note.isInTune;

    if (isCorrectNote && isCleanBowing) {
      setState(() {
        _holdProgress = math.min(1.0, _holdProgress + 0.08);
        if (_holdProgress >= 1.0) {
          _holdProgress = 0.0;
          _streak++;
          _nextStep();
        }
      });
    } else {
      if (_holdProgress > 0) {
        setState(() {
          _holdProgress = math.max(0.0, _holdProgress - 0.03);
        });
      }
    }
  }

  void _nextStep() {
    _stopFullScale();
    _referenceTimer?.cancel();
    _isReferencePlaying = false;
    setState(() {
      _currentStepIndex = (_currentStepIndex + 1) % currentScale.steps.length;
    });
  }

  void _playSingleReference() {
    _stopFullScale();
    _referenceTimer?.cancel();
    setState(() {
      _isReferencePlaying = true;
      _holdProgress = 0.0;
    });
    widget.audioEngine.playTone(currentStep.targetHz, 1.2);
    _referenceTimer = Timer(const Duration(milliseconds: 1350), () {
      if (mounted) {
        setState(() {
          _isReferencePlaying = false;
        });
      }
    });
  }

  void _playFullScale() {
    if (_isFullScalePlaying) {
      _stopFullScale();
      return;
    }

    _referenceTimer?.cancel();
    setState(() {
      _isReferencePlaying = false;
      _isFullScalePlaying = true;
      _currentStepIndex = 0;
      _holdProgress = 0.0;
    });

    int step = 0;
    const noteDurationMs = 650;

    void playStep() {
      if (!mounted || !_isFullScalePlaying) return;
      if (step >= currentScale.steps.length) {
        _stopFullScale();
        return;
      }
      setState(() {
        _currentStepIndex = step;
      });
      final note = currentScale.steps[step];
      widget.audioEngine.playTone(note.targetHz, 0.60);

      step++;
      _fullScaleTimer = Timer(const Duration(milliseconds: noteDurationMs), playStep);
    }

    playStep();
  }

  void _stopFullScale() {
    _fullScaleTimer?.cancel();
    if (mounted && _isFullScalePlaying) {
      setState(() {
        _isFullScalePlaying = false;
      });
    }
  }

  void _selectTonality(TonalityDef tonality) {
    _stopFullScale();
    _referenceTimer?.cancel();
    _isReferencePlaying = false;
    setState(() {
      _selectedTonality = tonality;
      _currentScale = ScaleGenerator.generateScale(tonality);
      _selectedScaleIndex = _scales.indexWhere((s) => s.tonality == tonality);
      if (_selectedScaleIndex < 0) _selectedScaleIndex = 0;
      _currentStepIndex = 0;
      _holdProgress = 0.0;
    });
  }

  void _selectScale(int index) {
    _stopFullScale();
    _referenceTimer?.cancel();
    _isReferencePlaying = false;
    final scale = _scales[index];
    if (scale.tonality != null) {
      _selectTonality(scale.tonality!);
    } else {
      setState(() {
        _selectedScaleIndex = index;
        _currentScale = scale;
        _currentStepIndex = 0;
        _holdProgress = 0.0;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  Widget _micro(String text, {required Color color, double size = 10}) {
    return Text(
      text,
      style: AppleViolinTheme.telemetry.copyWith(color: color, fontSize: size),
    );
  }

  Color _stringColor(ViolinString s) => switch (s) {
        ViolinString.g => AppleViolinTheme.stringG,
        ViolinString.d => AppleViolinTheme.stringD,
        ViolinString.a => AppleViolinTheme.stringA,
        ViolinString.e => AppleViolinTheme.stringE,
      };

  int _accidentalCount(String sig) {
    if (currentScale.tonality != null) {
      return currentScale.tonality!.accidentalCount.abs();
    }
    return '#'.allMatches(sig).length + '♭'.allMatches(sig).length;
  }

  String _scaleChipLabel(ViolinScaleDef s) {
    if (s.tonality != null) {
      return s.tonality!.shortName;
    }
    final base = s.name.split(' (').first;
    return base.replaceFirst('мажор', 'маж').replaceFirst('минор', 'мин');
  }

  String _scaleBadge(ViolinScaleDef s) {
    if (s.tonality != null) {
      return '${s.tonality!.shortName.toUpperCase()} · ${s.tonality!.position.shortKeySignature}';
    }
    final base = s.name.split(' (').first.toUpperCase();
    final n = _accidentalCount(s.keySignature);
    return '$base · ${n > 0 ? '$n#' : '0'}';
  }

  /// Russian feedback line + its accent colour (derived, not stateful).
  (String, Color) _hint(DetectedNoteInfo? note, bool isInTune) {
    if (_isReferencePlaying || _isFullScalePlaying) {
      return (
        '🔊 Звучит эталон (${currentStep.targetHz.toStringAsFixed(1)} Гц) · Послушайте интонацию',
        AppleViolinTheme.highVoltageLime,
      );
    }
    if (note == null || note.midiNote != currentStep.midiNote) {
      return ('Сыграйте ноту смычком: ${currentStep.fingerLabel}', AppleViolinTheme.subtext);
    }
    if (note.isScratching) {
      return ('Скрип: ослабьте нажим смычка', AppleViolinTheme.crimsonScratch);
    }
    if (isInTune) {
      return ('Чистая интонация! Удерживайте смычок...', AppleViolinTheme.hyperEmerald);
    }
    final cents = note.cents;
    if (cents < 0) {
      return ('Низит на ${cents.abs().toStringAsFixed(0)}¢: сдвиньте палец к подставке', AppleViolinTheme.solarAmber);
    }
    return ('Высит на +${cents.toStringAsFixed(0)}¢: сдвиньте палец к колкам', AppleViolinTheme.solarAmber);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.currentNote ?? widget.noteNotifier?.value;
    final isCorrectNote = note != null && note.midiNote == currentStep.midiNote;
    final isInTune = isCorrectNote && note.isInTune && !note.isScratching;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 22),
          _buildScaleSelectorCard(),
          const SizedBox(height: 20),
          _buildHeroCard(isInTune, note),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Editorial header + status pill
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _micro('ТРЕНИРОВКА', color: AppleViolinTheme.subtext),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Гаммы ',
                      style: TextStyle(
                        fontFamily: AppleViolinTheme.fontDisplay,
                        fontSize: 34,
                        height: 0.98,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        color: AppleViolinTheme.headline,
                      ),
                    ),
                    TextSpan(
                      text: 'и техника',
                      style: TextStyle(
                        fontFamily: AppleViolinTheme.fontEditorial,
                        fontSize: 34,
                        height: 0.98,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.6,
                        color: AppleViolinTheme.subtext,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _buildStreakPill(),
      ],
    );
  }

  Widget _buildStreakPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: AppleViolinTheme.pillRadius,
        border: Border.all(color: AppleViolinTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppleViolinTheme.highVoltageLime
                      .withValues(alpha: 0.35 + 0.55 * _pulse.value),
                  boxShadow: [
                    BoxShadow(
                      color: AppleViolinTheme.highVoltageLime
                          .withValues(alpha: 0.35 * _pulse.value),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            'СЕРИЯ · $_streak НОТ',
            style: AppleViolinTheme.telemetry.copyWith(
              fontSize: 10,
              letterSpacing: 1.1,
              color: const Color(0xFFD4D4D8),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tonality selector card with Circle of Fifths Toggle
  // ---------------------------------------------------------------------------

  Widget _buildScaleSelectorCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: AppleViolinTheme.glassDecoration(radius: AppleViolinTheme.bentoRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _micro('ТОНАЛЬНОСТЬ', color: AppleViolinTheme.subtext),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showCircleOfFifths = !_showCircleOfFifths);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _showCircleOfFifths
                        ? AppleViolinTheme.highVoltageLime.withValues(alpha: 0.15)
                        : const Color(0x0EFFFFFF),
                    borderRadius: AppleViolinTheme.pillRadius,
                    border: Border.all(
                      color: _showCircleOfFifths
                          ? AppleViolinTheme.highVoltageLime
                          : AppleViolinTheme.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showCircleOfFifths
                            ? Icons.view_list_rounded
                            : Icons.pie_chart_outline_rounded,
                        size: 13,
                        color: _showCircleOfFifths
                            ? AppleViolinTheme.highVoltageLime
                            : AppleViolinTheme.headline,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _showCircleOfFifths ? 'Список' : 'Квинтовый круг',
                        style: AppleViolinTheme.telemetry.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _showCircleOfFifths
                              ? AppleViolinTheme.highVoltageLime
                              : AppleViolinTheme.headline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _scaleBadge(currentScale),
                textAlign: TextAlign.right,
                style: AppleViolinTheme.telemetry.copyWith(
                  fontSize: 10,
                  fontFamily: AppleViolinTheme.fontMono,
                  fontWeight: FontWeight.w700,
                  color: AppleViolinTheme.highVoltageLime,
                ),
              ),
            ],
          ),
          if (_showCircleOfFifths) ...[
            const SizedBox(height: 16),
            CircleOfFifthsPicker(
              size: 270,
              selectedTonality: _selectedTonality,
              onTonalityChanged: _selectTonality,
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${currentScale.name} · ${currentScale.keySignature}',
                textAlign: TextAlign.center,
                style: AppleViolinTheme.telemetry.copyWith(
                  fontSize: 11,
                  color: AppleViolinTheme.subtext,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _scales.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final scale = _scales[index];
                  final isSelected = scale.tonality == _selectedTonality ||
                      (scale.tonality == null && index == _selectedScaleIndex);
                  return GestureDetector(
                    onTap: () => _selectScale(index),
                    child: AnimatedContainer(
                      duration: AppleViolinTheme.motionFast,
                      curve: AppleViolinTheme.easeOutExpo,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppleViolinTheme.highVoltageLime
                            : const Color(0x08FFFFFF),
                        borderRadius: AppleViolinTheme.pillRadius,
                        border: Border.all(
                          color: isSelected
                              ? AppleViolinTheme.highVoltageLime
                              : AppleViolinTheme.borderSubtle,
                        ),
                        boxShadow: isSelected ? const [AppleViolinTheme.limeGlow] : null,
                      ),
                      child: Center(
                        child: Text(
                          _scaleChipLabel(scale),
                          style: AppleViolinTheme.telemetry.copyWith(
                            fontSize: 11,
                            letterSpacing: 0.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? AppleViolinTheme.voidBg
                                : AppleViolinTheme.subtext,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Scale hero card
  // ---------------------------------------------------------------------------

  Widget _buildHeroCard(bool isInTune, DetectedNoteInfo? note) {
    final bowDown = _currentStepIndex.isEven;

    return Stack(
      children: [
        // Faint radial lime glow behind the hero card.
        Positioned(
          top: -90,
          left: -70,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x24D4FF00), Color(0x00D4FF00)],
                  stops: [0.0, 0.68],
                ),
              ),
            ),
          ),
        ),
        AnimatedContainer(
          duration: AppleViolinTheme.motion,
          curve: AppleViolinTheme.easeOutExpo,
          padding: const EdgeInsets.all(20),
          decoration: AppleViolinTheme.glassDecoration(
            highlighted: isInTune,
            radius: AppleViolinTheme.bentoRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroTopRow(bowDown),
              const SizedBox(height: 16),
              _buildStaff(note, isInTune),
              const SizedBox(height: 16),
              _buildSpecBento(),
              const SizedBox(height: 18),
              _buildStepTrail(),
              const SizedBox(height: 18),
              _buildPurityRow(note, isInTune, bowDown),
              const SizedBox(height: 18),
              _buildTrainModes(),
              const SizedBox(height: 18),
              _buildActions(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroTopRow(bool bowDown) {
    final step = currentStep;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _micro('СЫГРАЙТЕ НОТУ', color: AppleViolinTheme.subtext),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    step.russianNote,
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontDisplay,
                      fontSize: 48,
                      height: 0.95,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.8,
                      color: AppleViolinTheme.headline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${step.octave}',
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppleViolinTheme.highVoltageLime,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '(${step.fullTitle})',
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppleViolinTheme.subtext,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildBowBadge(bowDown),
      ],
    );
  }

  Widget _buildBowBadge(bool bowDown) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: AppleViolinTheme.pillRadius,
        border: Border.all(color: AppleViolinTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            bowDown ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            size: 15,
            color: AppleViolinTheme.highVoltageLime,
          ),
          const SizedBox(width: 6),
          Text(
            bowDown ? 'ВНИЗ' : 'ВВЕРХ',
            style: AppleViolinTheme.telemetry.copyWith(
              fontSize: 10,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
              color: AppleViolinTheme.headline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaff(DetectedNoteInfo? note, bool isInTune) {
    final accidentalCount = _accidentalCount(currentScale.keySignature);
    final isFlat = currentScale.tonality?.accidentalCount != null &&
        currentScale.tonality!.accidentalCount < 0;

    final isRefActive = _isReferencePlaying || _isFullScalePlaying;
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0x05FFFFFF),
        borderRadius: AppleViolinTheme.btnRadius,
        border: Border.all(color: AppleViolinTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _ScaleStaffPainter(
          targetMidi: currentStep.midiNote,
          playedMidi: isRefActive ? null : note?.midiNote,
          isScratching: isRefActive ? false : (note?.isScratching ?? false),
          isInTune: isRefActive ? true : isInTune,
          accidentalCount: accidentalCount,
          isFlat: isFlat,
          targetLabel: currentStep.fullTitle,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildSpecBento() {
    final step = currentStep;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _specTile(
            'ПАЛЕЦ',
            step.fingerLabel,
            color: AppleViolinTheme.headline,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _specTile(
            'СТРУНА',
            '${step.string.solfegeName} (${step.string.name})',
            color: _stringColor(step.string),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _specTile(
            'ЧАСТОТА',
            '${step.targetHz.toStringAsFixed(2)} Hz',
            color: AppleViolinTheme.highVoltageLime,
          ),
        ),
      ],
    );
  }

  Widget _specTile(String label, String value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x05FFFFFF),
        borderRadius: AppleViolinTheme.btnRadius,
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _micro(label, color: const Color(0xFF52525B), size: 9),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppleViolinTheme.fontMono,
              fontSize: 10,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTrail() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: currentScale.steps.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final step = currentScale.steps[index];
          final isCurrent = index == _currentStepIndex;
          final isDone = index < _currentStepIndex;

          final bg = isCurrent
              ? AppleViolinTheme.highVoltageLime
              : isDone
                  ? AppleViolinTheme.hyperEmerald.withValues(alpha: 0.16)
                  : const Color(0x08FFFFFF);

          final borderCol = isCurrent
              ? AppleViolinTheme.highVoltageLime
              : isDone
                  ? AppleViolinTheme.hyperEmerald.withValues(alpha: 0.4)
                  : AppleViolinTheme.borderSubtle;

          final textCol = isCurrent
              ? AppleViolinTheme.voidBg
              : isDone
                  ? AppleViolinTheme.hyperEmerald
                  : AppleViolinTheme.subtext;

          return GestureDetector(
            onTap: () {
              setState(() {
                _currentStepIndex = index;
                _holdProgress = 0.0;
              });
            },
            child: AnimatedContainer(
              duration: AppleViolinTheme.motionFast,
              curve: AppleViolinTheme.easeOutExpo,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppleViolinTheme.pillRadius,
                border: Border.all(color: borderCol),
                boxShadow: isCurrent ? const [AppleViolinTheme.limeGlow] : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${index + 1}.',
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: textCol.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    step.fullTitle,
                    style: TextStyle(
                      fontFamily: AppleViolinTheme.fontMono,
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: textCol,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPurityRow(DetectedNoteInfo? note, bool isInTune, bool bowDown) {
    final pct = (_holdProgress * 100).round();
    final (hintText, hintColor) = _hint(note, isInTune);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _micro('ЧИСТОТА', color: const Color(0xFF52525B), size: 9),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: AppleViolinTheme.pillRadius,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: _holdProgress),
                  duration: AppleViolinTheme.motion,
                  curve: AppleViolinTheme.easeOutExpo,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: const Color(0x12FFFFFF),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppleViolinTheme.highVoltageLime,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$pct%',
              style: AppleViolinTheme.telemetry.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppleViolinTheme.highVoltageLime,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              bowDown ? '↓ Вниз' : '↑ Вверх',
              style: AppleViolinTheme.telemetry.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFE4E4E7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          hintText,
          style: TextStyle(
            fontFamily: AppleViolinTheme.fontEditorial,
            fontStyle: FontStyle.italic,
            fontSize: 12,
            color: hintColor,
          ),
        ),
      ],
    );
  }

  Widget _buildTrainModes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _micro('РЕЖИМ ТРЕНИРОВКИ', color: AppleViolinTheme.subtext),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _trainModes.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (id, label) = _trainModes[index];
              final isActive = id == _trainMode;
              return GestureDetector(
                onTap: () => setState(() => _trainMode = id),
                child: AnimatedContainer(
                  duration: AppleViolinTheme.motionFast,
                  curve: AppleViolinTheme.easeOutExpo,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppleViolinTheme.highVoltageLime
                        : const Color(0x08FFFFFF),
                    borderRadius: AppleViolinTheme.pillRadius,
                    border: Border.all(
                      color: isActive
                          ? AppleViolinTheme.highVoltageLime
                          : AppleViolinTheme.borderSubtle,
                    ),
                    boxShadow: isActive ? const [AppleViolinTheme.limeGlow] : null,
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: AppleViolinTheme.telemetry.copyWith(
                        fontSize: 9,
                        letterSpacing: 0.4,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? AppleViolinTheme.voidBg
                            : AppleViolinTheme.subtext,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: GestureDetector(
            onTap: _playSingleReference,
            child: AnimatedContainer(
              duration: AppleViolinTheme.motionFast,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _isReferencePlaying
                    ? AppleViolinTheme.highVoltageLime.withValues(alpha: 0.18)
                    : const Color(0x0CFFFFFF),
                borderRadius: AppleViolinTheme.pillRadius,
                border: Border.all(
                  color: _isReferencePlaying
                      ? AppleViolinTheme.highVoltageLime
                      : AppleViolinTheme.borderSubtle,
                ),
                boxShadow: _isReferencePlaying ? const [AppleViolinTheme.limeGlow] : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isReferencePlaying ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
                    size: 16,
                    color: AppleViolinTheme.highVoltageLime,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isReferencePlaying ? 'ЗВУЧИТ...' : 'ЭТАЛОН',
                    style: AppleViolinTheme.telemetry.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _isReferencePlaying
                          ? AppleViolinTheme.highVoltageLime
                          : const Color(0xFFE4E4E7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: GestureDetector(
            onTap: _playFullScale,
            child: AnimatedContainer(
              duration: AppleViolinTheme.motionFast,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _isFullScalePlaying
                    ? const Color(0xFF38BDF8).withValues(alpha: 0.18)
                    : const Color(0x0CFFFFFF),
                borderRadius: AppleViolinTheme.pillRadius,
                border: Border.all(
                  color: _isFullScalePlaying
                      ? const Color(0xFF38BDF8)
                      : AppleViolinTheme.borderSubtle,
                ),
                boxShadow: _isFullScalePlaying
                    ? [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isFullScalePlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    size: 17,
                    color: _isFullScalePlaying
                        ? const Color(0xFF38BDF8)
                        : const Color(0xFFE4E4E7),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isFullScalePlaying ? 'СТОП' : 'ВСЯ ГАММА',
                    style: AppleViolinTheme.telemetry.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _isFullScalePlaying
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFFE4E4E7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: GestureDetector(
            onTap: _nextStep,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: AppleViolinTheme.primaryCtaDecoration(
                radius: AppleViolinTheme.pillRadius,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: AppleViolinTheme.voidBg,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'ДАЛЕЕ',
                    style: AppleViolinTheme.telemetry.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppleViolinTheme.voidBg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Interactive scale staff renderer
// -----------------------------------------------------------------------------

class _ScaleStaffPainter extends CustomPainter {
  final int targetMidi;
  final int? playedMidi;
  final bool isScratching;
  final bool isInTune;
  final int accidentalCount;
  final bool isFlat;
  final String targetLabel;

  _ScaleStaffPainter({
    required this.targetMidi,
    required this.playedMidi,
    required this.isScratching,
    required this.isInTune,
    required this.accidentalCount,
    this.isFlat = false,
    required this.targetLabel,
  });

  static const List<(int diatonicBase, bool isSharp)> _semis = [
    (0, false), // C
    (0, true),  // C#
    (1, false), // D
    (1, true),  // D#
    (2, false), // E
    (3, false), // F
    (3, true),  // F#
    (4, false), // G
    (4, true),  // G#
    (5, false), // A
    (5, true),  // A#
    (6, false), // B
  ];

  static (int step, bool isSharp) _diatonic(int midi) {
    final noteInOct = midi % 12;
    final octave = (midi ~/ 12) - 1;
    final (base, sharp) = _semis[noteInOct];
    return ((octave - 4) * 7 + base, sharp);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const spacing = 8.0;
    final line1Y = h * 0.55; // bottom staff line
    final line3Y = line1Y - 2 * spacing;

    final staffPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..strokeWidth = 1.0;
    final startX = w * 0.05;
    final endX = w - 8;

    for (int i = 0; i < 5; i++) {
      final y = line1Y - i * spacing;
      canvas.drawLine(Offset(startX, y), Offset(endX, y), staffPaint);
    }

    _drawClef(canvas, line3Y, spacing, w * 0.08);

    if (accidentalCount > 0) {
      _drawKeySignature(
        canvas: canvas,
        startX: w * 0.14,
        line1Y: line1Y,
        spacing: spacing,
        count: accidentalCount,
        isFlat: isFlat,
      );
    }

    // Target note — high-voltage lime.
    final (tStep, tSharp) = _diatonic(targetMidi);
    final targetY = line1Y - (tStep - 2) * (spacing / 2);
    final targetX = accidentalCount > 2 ? w * 0.50 : w * 0.44;
    _drawNote(
      canvas,
      x: targetX,
      y: targetY,
      isSharp: tSharp,
      step: tStep,
      spacing: spacing,
      line1Y: line1Y,
      color: AppleViolinTheme.highVoltageLime,
      alpha: 0.9,
      label: targetLabel,
    );

    // Detected / previous note — solar amber, emerald when locked in tune.
    final played = playedMidi;
    if (played != null) {
      final (pStep, pSharp) = _diatonic(played);
      final playedY = line1Y - (pStep - 2) * (spacing / 2);
      final isMatch = played == targetMidi;
      Color color;
      if (isScratching) {
        color = AppleViolinTheme.crimsonScratch;
      } else if (isMatch && isInTune) {
        color = AppleViolinTheme.hyperEmerald;
      } else if (isMatch) {
        color = AppleViolinTheme.highVoltageLime;
      } else {
        color = AppleViolinTheme.solarAmber;
      }
      _drawNote(
        canvas,
        x: w * 0.76,
        y: playedY,
        isSharp: pSharp,
        step: pStep,
        spacing: spacing,
        line1Y: line1Y,
        color: color,
        alpha: 0.85,
        label: 'ВЫ',
      );
    }
  }

  void _drawClef(Canvas canvas, double line3Y, double spacing, double cx) {
    final clefPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.70)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(cx, line3Y + spacing * 2.8)
      ..lineTo(cx, line3Y - spacing * 3.0)
      ..quadraticBezierTo(cx + spacing * 1.6, line3Y - spacing * 1.8, cx, line3Y - spacing * 0.6)
      ..quadraticBezierTo(cx - spacing * 2.0, line3Y + spacing * 0.8, cx, line3Y + spacing * 1.8)
      ..quadraticBezierTo(cx + spacing * 1.8, line3Y + spacing * 1.6, cx, line3Y + spacing * 0.6);

    canvas.drawPath(path, clefPaint);

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.70)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 3, line3Y + spacing * 3.0), 3.0, dotPaint);
  }

  void _drawKeySignature({
    required Canvas canvas,
    required double startX,
    required double line1Y,
    required double spacing,
    required int count,
    required bool isFlat,
  }) {
    // Standard solfège positions in treble clef:
    // line1Y is bottom line (E4).
    // line 1 (E4): line1Y
    // line 2 (G4): line1Y - 1.0 * spacing
    // line 3 (B4): line1Y - 2.0 * spacing
    // line 4 (D5): line1Y - 3.0 * spacing
    // line 5 (F5): line1Y - 4.0 * spacing
    //
    // Sharps sequence: F#5 (line 5), C#5 (space 3), G#5 (above line 5), D#5 (line 4), A#4 (space 2), E#5 (space 4), B#4 (line 3)
    const sharpOffsets = [4.0, 2.5, 4.5, 3.0, 1.5, 3.5, 2.0];

    // Flats sequence: Bb4 (line 3), Eb5 (space 4), Ab4 (space 2), Db5 (line 4), Gb4 (line 2), Cb5 (space 3), Fb4 (space 1)
    const flatOffsets = [2.0, 3.5, 1.5, 3.0, 1.0, 2.5, 0.5];

    final offsets = isFlat ? flatOffsets : sharpOffsets;
    final stepX = math.min(10.0, spacing * 1.15);
    final clampedCount = count.clamp(0, 7);

    for (int i = 0; i < clampedCount; i++) {
      final x = startX + i * stepX;
      final y = line1Y - offsets[i] * spacing;

      if (isFlat) {
        _drawFlatGlyph(canvas, x, y, spacing, AppleViolinTheme.highVoltageLime);
      } else {
        _drawSharpGlyph(canvas, x, y, spacing, AppleViolinTheme.highVoltageLime);
      }
    }
  }

  void _drawSharpGlyph(Canvas canvas, double cx, double cy, double spacing, Color color) {
    final vPaint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    final sh = spacing * 1.5;
    // Two vertical bars
    canvas.drawLine(Offset(cx - 2.2, cy - sh * 0.45), Offset(cx - 2.2, cy + sh * 0.45), vPaint);
    canvas.drawLine(Offset(cx + 2.2, cy - sh * 0.45), Offset(cx + 2.2, cy + sh * 0.45), vPaint);

    // Two tilted horizontal bars
    final hPaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - 4.5, cy - 1.5), Offset(cx + 4.5, cy - 3.5), hPaint);
    canvas.drawLine(Offset(cx - 4.5, cy + 2.5), Offset(cx + 4.5, cy + 0.5), hPaint);
  }

  void _drawFlatGlyph(Canvas canvas, double cx, double cy, double spacing, Color color) {
    final stemPaint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Vertical stem on the left
    canvas.drawLine(Offset(cx - 2.2, cy - spacing * 1.2), Offset(cx - 2.2, cy + spacing * 0.35), stemPaint);

    // Round curved belly on the right
    final belly = Path()
      ..moveTo(cx - 2.2, cy - spacing * 0.35)
      ..cubicTo(
        cx + 3.2, cy - spacing * 0.5,
        cx + 3.6, cy + spacing * 0.25,
        cx - 2.2, cy + spacing * 0.35,
      );

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawPath(belly, fillPaint);
    canvas.drawPath(belly, stemPaint);
  }

  void _drawNote(
    Canvas canvas, {
    required double x,
    required double y,
    required bool isSharp,
    required int step,
    required double spacing,
    required double line1Y,
    required Color color,
    required double alpha,
    required String label,
  }) {
    // Ledger lines
    final ledgerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..strokeWidth = 1.0;
    final ledgerWidth = spacing * 2.3;
    if (step <= 0) {
      for (int s = 0; s >= step; s -= 2) {
        final ly = line1Y - (s - 2) * (spacing / 2);
        canvas.drawLine(Offset(x - ledgerWidth / 2, ly), Offset(x + ledgerWidth / 2, ly), ledgerPaint);
      }
    } else if (step >= 12) {
      for (int s = 12; s <= step; s += 2) {
        final ly = line1Y - (s - 2) * (spacing / 2);
        canvas.drawLine(Offset(x - ledgerWidth / 2, ly), Offset(x + ledgerWidth / 2, ly), ledgerPaint);
      }
    }

    // Sharp sign
    if (isSharp) {
      final sharpPaint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      final sx = x - spacing * 1.5;
      final sh = spacing * 1.4;
      canvas.drawLine(Offset(sx - 2.5, y - sh / 2), Offset(sx - 2.5, y + sh / 2), sharpPaint);
      canvas.drawLine(Offset(sx + 2.5, y - sh / 2), Offset(sx + 2.5, y + sh / 2), sharpPaint);
      canvas.drawLine(Offset(sx - 5, y - 1.5), Offset(sx + 5, y - 4), sharpPaint);
      canvas.drawLine(Offset(sx - 5, y + 3), Offset(sx + 5, y + 0.5), sharpPaint);
    }

    // Note head (tilted ellipse)
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-20 * math.pi / 180);
    final headFill = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: spacing * 1.5, height: spacing * 1.05),
      headFill,
    );
    final headStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: spacing * 1.5, height: spacing * 1.05),
      headStroke,
    );
    canvas.restore();

    // Label below the note head (always below, never clipped at the top)
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: AppleViolinTheme.fontMono,
          fontSize: 8,
          height: 1.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, y + spacing * 1.9));
  }

  @override
  bool shouldRepaint(covariant _ScaleStaffPainter old) {
    return old.targetMidi != targetMidi ||
        old.playedMidi != playedMidi ||
        old.isScratching != isScratching ||
        old.isInTune != isInTune ||
        old.accidentalCount != accidentalCount ||
        old.isFlat != isFlat ||
        old.targetLabel != targetLabel;
  }
}
