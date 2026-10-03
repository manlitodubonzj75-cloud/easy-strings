import "dart:typed_data";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "../../models/song_model.dart";
import "../../services/audio_transcriber.dart";
import "../../services/url_audio_downloader.dart";
import "../../theme/apple_violin_theme.dart";

/// Modal bottom sheet for uploading audio files, downloading via yt-dlp, or recording.
class AudioTranscribeSheet extends StatefulWidget {
  final void Function(Song song, String report) onSongTranscribed;
  final VoidCallback onClose;

  const AudioTranscribeSheet({
    super.key,
    required this.onSongTranscribed,
    required this.onClose,
  });

  @override
  State<AudioTranscribeSheet> createState() => _AudioTranscribeSheetState();
}

class _AudioTranscribeSheetState extends State<AudioTranscribeSheet> {
  final TextEditingController _urlController = TextEditingController();
  bool _isProcessing = false;
  bool _isUrlInputOpen = false;
  double _progress = 0.0;
  String _statusMessage = "";
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: "Выберите аудиозапись для транскрибации",
        type: FileType.custom,
        allowedExtensions: ["wav", "mp3", "m4a", "aac", "flac", "ogg"],
      );

      if (result.isEmpty) return;

      final file = result.first;
      final bytes = await file.readAsBytes();
      final title = file.name.replaceAll(RegExp(r"\.[a-zA-Z0-9]+$"), "");

      await _runTranscription(bytes, title);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = "Ошибка выбора файла: $e";
      });
    }
  }

  Future<void> _downloadUrlAndTranscribe() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _errorMessage = "Пожалуйста, вставьте ссылку на YouTube, SoundCloud или аудиофайл";
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.05;
      _statusMessage = "Подключение к источнику через yt-dlp...";
      _errorMessage = null;
    });

    try {
      final downloaded = await UrlAudioDownloader.downloadFromUrl(
        url,
        onProgress: (status, p) {
          if (mounted) {
            setState(() {
              _statusMessage = status;
              _progress = p;
            });
          }
        },
      );

      await _runTranscription(downloaded.bytes, downloaded.title, startProgress: 0.52);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = "Ошибка загрузки по ссылке: $e";
      });
    }
  }

  Future<void> _runTranscription(Uint8List bytes, String title, {double startProgress = 0.05}) async {
    setState(() {
      _isProcessing = true;
      _progress = startProgress;
      _statusMessage = "Загрузка аудиозаписи в анализатор...";
      _errorMessage = null;
    });

    try {
      final res = await AudioTranscriber.transcribeAudioBytes(
        bytes,
        title: title.isEmpty ? "Транскрибированное аудио" : title,
        onProgress: (p, status) {
          if (mounted) {
            setState(() {
              _progress = startProgress + (p * (1.0 - startProgress));
              _statusMessage = status;
            });
          }
        },
      );

      if (mounted) {
        widget.onSongTranscribed(res.song, res.report);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = "Ошибка транскрибации: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppleViolinTheme.cardDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppleViolinTheme.borderSubtle),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppleViolinTheme.appleBlue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.graphic_eq_rounded,
                          color: AppleViolinTheme.appleBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "AUDIO -> NOTES (AI AMT)",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "Spotify Basic Pitch • Встроенный YouTube парсер",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppleViolinTheme.appleRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppleViolinTheme.appleRed.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppleViolinTheme.appleRed, fontSize: 13),
                  ),
                ),

              if (_isProcessing) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _progress < 0.52 ? "ЭТАП 1/2: ЗАГРУЗКА АУДИО" : "ЭТАП 2/2: НЕЙРО-АНАЛИЗ НОТ",
                            style: const TextStyle(
                              fontFamily: AppleViolinTheme.fontMono,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: AppleViolinTheme.hyperEmerald,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppleViolinTheme.appleBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "${(_progress * 100).toInt()}%",
                              style: const TextStyle(
                                fontFamily: AppleViolinTheme.fontMono,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppleViolinTheme.appleBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _progress > 0 ? _progress.clamp(0.0, 1.0) : null,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(AppleViolinTheme.appleBlue),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _progress < 0.52
                            ? "Скачивание медиапотока на высокой скорости без ограничений..."
                            : "Выделение полифонических мелодических контуров и расчет аппликатуры...",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Option 1: File
                _buildOptionCard(
                  icon: Icons.audio_file_rounded,
                  title: "Локальный аудиофайл",
                  subtitle: "WAV, MP3, M4A, FLAC — скрипка, инструмент или вокал",
                  color: AppleViolinTheme.appleBlue,
                  onTap: _pickAudioFile,
                ),
                const SizedBox(height: 12),

                // Option 2: yt-dlp URL
                _buildUrlOptionCard(),
                const SizedBox(height: 12),

                // Option 3: Mic
                _buildOptionCard(
                  icon: Icons.mic_external_on_rounded,
                  title: "Спеть или напеть мелодию",
                  subtitle: "Используйте микрофон для записи голоса или инструмента",
                  color: AppleViolinTheme.appleGreen,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: AppleViolinTheme.appleBlue,
                        content: Text("🎤 Для быстрой записи выберите WAV/M4A аудио или включите микрофон во вкладке Тренажер."),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrlOptionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isUrlInputOpen
              ? AppleViolinTheme.solarAmber.withValues(alpha: 0.5)
              : Colors.white10,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isUrlInputOpen = !_isUrlInputOpen;
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppleViolinTheme.solarAmber.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_download_rounded,
                        color: AppleViolinTheme.solarAmber,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Загрузить по ссылке (YouTube / Сеть)",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "YouTube (видео / Shorts), SoundCloud, прямые MP3",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isUrlInputOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white38,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isUrlInputOpen) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "https://www.youtube.com/watch?v=...",
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppleViolinTheme.solarAmber),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white38),
                        onPressed: () => _urlController.clear(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _downloadUrlAndTranscribe,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppleViolinTheme.solarAmber, Color(0xFFD97706)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_rounded, color: Colors.black, size: 18),
                          SizedBox(width: 8),
                          Text(
                            "СКАЧАТЬ И ТРАНСКРИБИРОВАТЬ",
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
