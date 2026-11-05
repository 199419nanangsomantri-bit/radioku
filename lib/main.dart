import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

// ============================================================
// DAFTAR STASIUN INDONESIA - EDIT DI SINI
// ============================================================
class Station {
  final String name;
  final String url;
  const Station(this.name, this.url);
}

const List<Station> stations = [
  // --- Nasional / Berita ---
  Station('Elshinta FM Jakarta', 'https://stream-ssl.arenastreaming.com:8005/jakarta'),
  Station('CNN Indonesia', 'https://stream-ssl.arenastreaming.com:8005/cnnindonesia'),
  Station('RRI Pro 3', 'https://streaming.rri.go.id/pro3.mp3'),
  Station('RRI Voice of Indonesia', 'https://streaming.rri.go.id/voi.mp3'),
  Station('Sonora FM Jakarta', 'https://stream-ssl.arenastreaming.com:8005/sonora'),

  // --- Musik / Hiburan ---
  Station('Prambors FM Jakarta', 'https://stream-ssl.arenastreaming.com:8005/prambors'),
  Station('Gen FM Jakarta', 'https://stream-ssl.arenastreaming.com:8005/genfm'),
  Station('I-Radio Jakarta', 'https://stream-ssl.arenastreaming.com:8005/iradio'),
  Station('Trax FM Jakarta', 'https://stream-ssl.arenastreaming.com:8005/traxfm'),
  Station('Hard Rock FM Jakarta', 'https://stream-ssl.arenastreaming.com:8005/hardrockfm'),
  Station('Cosmopolitan FM', 'https://stream-ssl.arenastreaming.com:8005/cosmopolitan'),
  Station('Jak FM', 'https://stream-ssl.arenastreaming.com:8005/jakfm'),
  Station('V Radio', 'https://stream-ssl.arenastreaming.com:8005/vradio'),
  Station('Delta FM Jakarta', 'https://stream-ssl.arenastreaming.com:8005/deltafm'),
  Station('FeMale Radio', 'https://stream-ssl.arenastreaming.com:8005/femaleradio'),

  // --- Daerah ---
  Station('Suara Surabaya FM', 'https://stream-ssl.arenastreaming.com:8005/suarasurabaya'),
  Station('Radio Cakra Bandung', 'https://stream-ssl.arenastreaming.com:8005/radiocakra'),
  Station('Ardan FM Bandung', 'https://stream-ssl.arenastreaming.com:8005/ardanfm'),
  Station('Dahlia Bandung', 'https://stream-ssl.arenastreaming.com:8005/dahliafm'),
  Station('Rama FM Bandung', 'https://stream-ssl.arenastreaming.com:8005/ramafm'),
  Station('Gajahmada FM Semarang', 'https://stream-ssl.arenastreaming.com:8005/gajahmadafm'),

  // --- Dangdut / Campursari ---
  Station('Radio Dangdut 97.1 FM', 'https://stream-ssl.arenastreaming.com:8005/dangdut'),
  Station('Campursari FM Jakarta', 'https://stream-ssl.arenastreaming.com:8005/campursari'),
  Station('Mettaswara Koplo', 'https://stream-ssl.arenastreaming.com:8005/mettaswarakoplo'),
  Station('Radio Campursari Yogyakarta', 'https://stream-ssl.arenastreaming.com:8005/campursarijogja'),

  // --- Religi ---
  Station('Radio Rodja 756 AM', 'https://stream-ssl.arenastreaming.com:8005/rodja'),
  Station('Radio Sholawat Surabaya', 'https://stream-ssl.arenastreaming.com:8005/sholawat'),
  Station('Tarbiyah Sunnah', 'https://stream-ssl.arenastreaming.com:8005/tarbiyah'),
];
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.radiosaya.channel.audio',
    androidNotificationChannelName: 'Radio Saya',
    androidNotificationOngoing: true,
  );

  runApp(const RadioApp());
}

class RadioApp extends StatelessWidget {
  const RadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radio Saya',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.amber,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.amber,
        brightness: Brightness.dark,
      ),
      home: const RadioPage(),
    );
  }
}

enum RadioStatus { idle, buffering, playing, paused, error }

class RadioPage extends StatefulWidget {
  const RadioPage({super.key});

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  int _index = 0;
  double _volume = 1.0;
  String? _error;
  bool _loading = false;
  int _loadToken = 0;
  DateTime? _pausedAt;

  // Untuk tuning dial
  double _dialAngle = 0.0;
  double _dragStartAngle = 0.0;
  bool _isDragging = false;

  Station get _station => stations[_index];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    _subs.add(_player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    }));

    _subs.add(_player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Stream terputus atau gagal diputar. Coba stasiun lain.';
        });
        unawaited(_player.stop());
      },
    ));
  }

  RadioStatus get _status {
    if (_error != null) return RadioStatus.error;
    if (_loading) return RadioStatus.buffering;
    final s = _player.playerState;
    switch (s.processingState) {
      case ProcessingState.idle:
        return RadioStatus.idle;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        return RadioStatus.buffering;
      case ProcessingState.ready:
        return s.playing ? RadioStatus.playing : RadioStatus.paused;
      case ProcessingState.completed:
        return RadioStatus.idle;
    }
  }

  Future<void> _startStation(int index) async {
    final token = ++_loadToken;
    setState(() {
      _index = index;
      _error = null;
      _loading = true;
    });

    try {
      await _player
          .setAudioSource(
            AudioSource.uri(
              Uri.parse(stations[index].url),
              tag: MediaItem(
                id: stations[index].url,
                title: stations[index].name,
                artist: 'Radio Indonesia',
              ),
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (token != _loadToken || !mounted) return;
      setState(() => _loading = false);
      unawaited(_player.play());
    } on PlayerInterruptedException {
      return;
    } on TimeoutException {
      await _fail(token, 'Koneksi terlalu lama. Cek internet atau coba stasiun lain.');
    } on PlayerException catch (e) {
      await _fail(token, 'Stream tidak bisa diputar (${e.message ?? e.code}).');
    } catch (e) {
      await _fail(token, 'Terjadi kesalahan: $e');
    }
  }

  Future<void> _fail(int token, String message) async {
    if (token != _loadToken || !mounted) return;
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Future<void> _stop() async {
    _loadToken++;
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = null;
    });
  }

  void _onPlayPressed() {
    switch (_status) {
      case RadioStatus.playing:
        _pausedAt = DateTime.now();
        unawaited(_player.pause());
        break;
      case RadioStatus.paused:
        final p = _pausedAt;
        if (p != null &&
            DateTime.now().difference(p) > const Duration(seconds: 30)) {
          _startStation(_index);
        } else {
          unawaited(_player.play());
        }
        break;
      case RadioStatus.buffering:
        _stop();
        break;
      case RadioStatus.idle:
      case RadioStatus.error:
        _startStation(_index);
        break;
    }
  }

  // --- Logika tuning dial ---
  void _onDialPanStart(DragStartDetails details) {
    _isDragging = true;
    final center = _getDialCenter();
    _dragStartAngle = _angleFromCenter(details.localPosition, center);
  }

  void _onDialPanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final center = _getDialCenter();
    final currentAngle = _angleFromCenter(details.localPosition, center);
    var delta = currentAngle - _dragStartAngle;

    // Normalisasi delta ke -pi..pi
    while (delta > math.pi) delta -= 2 * math.pi;
    while (delta < -math.pi) delta += 2 * math.pi;

    setState(() {
      _dialAngle += delta;
      _dialAngle = _dialAngle.clamp(-math.pi, math.pi);
    });
    _dragStartAngle = currentAngle;

    // Konversi sudut ke index stasiun
    final progress = (_dialAngle + math.pi) / (2 * math.pi);
    final newIndex = (progress * (stations.length - 1)).round().clamp(0, stations.length - 1);
    if (newIndex != _index) {
      _startStation(newIndex);
    }
  }

  void _onDialPanEnd(DragEndDetails details) {
    _isDragging = false;
  }

  Offset _getDialCenter() {
    final size = MediaQuery.of(context).size;
    return Offset(size.width / 2, 220);
  }

  double _angleFromCenter(Offset point, Offset center) {
    return math.atan2(point.dy - center.dy, point.dx - center.dx);
  }

  double get _dialProgress => (_dialAngle + math.pi) / (2 * math.pi);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  String _statusText(RadioStatus s) {
    switch (s) {
      case RadioStatus.idle:
        return 'Siap';
      case RadioStatus.buffering:
        return 'Memuat...';
      case RadioStatus.playing:
        return 'Sedang diputar';
      case RadioStatus.paused:
        return 'Dijeda';
      case RadioStatus.error:
        return 'Error';
    }
  }

  IconData _statusIcon(RadioStatus s) {
    switch (s) {
      case RadioStatus.idle:
        return Icons.radio;
      case RadioStatus.buffering:
        return Icons.hourglass_top;
      case RadioStatus.playing:
        return Icons.graphic_eq;
      case RadioStatus.paused:
        return Icons.pause_circle_outline;
      case RadioStatus.error:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = _status;
    final isBuffering = status == RadioStatus.buffering;
    final isPlaying = status == RadioStatus.playing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radio Indonesia'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // --- TUNING DIAL ANALOG ---
              SizedBox(
                height: 280,
                child: GestureDetector(
                  onPanStart: _onDialPanStart,
                  onPanUpdate: _onDialPanUpdate,
                  onPanEnd: _onDialPanEnd,
                  child: CustomPaint(
                    size: const Size(double.infinity, 280),
                    painter: _DialPainter(
                      angle: _dialAngle,
                      progress: _dialProgress,
                      colorScheme: cs,
                      stationCount: stations.length,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Frekuensi / nama stasiun di bawah dial
              Text(
                _station.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Stasiun ${_index + 1} dari ${stations.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Chip(
                avatar: Icon(_statusIcon(status), size: 18),
                label: Text(_statusText(status)),
              ),
              const SizedBox(height: 16),

              // Pesan error
              if (_error != null) ...[
                Card(
                  elevation: 0,
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: cs.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _startStation(_index),
                          child: const Text('Coba'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Tombol kontrol
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    iconSize: 32,
                    tooltip: 'Stop',
                    onPressed: status == RadioStatus.idle ? null : _stop,
                    icon: const Icon(Icons.stop),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton.filled(
                          iconSize: 40,
                          tooltip: isPlaying ? 'Pause' : 'Play',
                          onPressed: _onPlayPressed,
                          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                        if (isBuffering)
                          IgnorePointer(
                            child: SizedBox(
                              width: 68,
                              height: 68,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: cs.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
              const SizedBox(height: 16),

              // Volume
              Row(
                children: [
                  const Icon(Icons.volume_down),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      min: 0,
                      max: 1,
                      onChanged: (v) {
                        setState(() => _volume = v);
                        _player.setVolume(v);
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up),
                ],
              ),

              // Petunjuk
              const SizedBox(height: 8),
              Text(
                'Geser jarum dial untuk memilih stasiun',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PAINTER UNTUK DIAL ANALOG
// ============================================================
class _DialPainter extends CustomPainter {
  final double angle;
  final double progress;
  final ColorScheme colorScheme;
  final int stationCount;

  _DialPainter({
    required this.angle,
    required this.progress,
    required this.colorScheme,
    required this.stationCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    final radius = math.min(size.width / 2 - 20, size.height / 2 - 20);

    // Background lingkaran
    final bgPaint = Paint()
      ..color = colorScheme.surfaceContainerHighest
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius + 8, bgPaint);

    // Border
    final borderPaint = Paint()
      ..color = colorScheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius + 8, borderPaint);

    // Garis-garis frekuensi (tick marks)
    final tickPaint = Paint()
      ..color = colorScheme.onSurfaceVariant
      ..strokeWidth = 1.5;

    for (int i = 0; i <= 40; i++) {
      final tickAngle = (i / 40) * 2 * math.pi - math.pi;
      final isMajor = i % 5 == 0;
      final innerR = radius - (isMajor ? 14 : 8);
      final outerR = radius - 2;

      final start = Offset(
        center.dx + innerR * math.cos(tickAngle),
        center.dy + innerR * math.sin(tickAngle),
      );
      final end = Offset(
        center.dx + outerR * math.cos(tickAngle),
        center.dy + outerR * math.sin(tickAngle),
      );
      canvas.drawLine(start, end, tickPaint..strokeWidth = isMajor ? 2 : 1);
    }

    // Label stasiun di sepanjang dial (hanya beberapa)
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final labelCount = math.min(stationCount, 8);
    for (int i = 0; i < labelCount; i++) {
      final labelAngle = (i / (labelCount - 1)) * 2 * math.pi - math.pi;
      final labelR = radius - 24;
      final pos = Offset(
        center.dx + labelR * math.cos(labelAngle),
        center.dy + labelR * math.sin(labelAngle),
      );
      textPainter.text = TextSpan(
        text: '${i + 1}',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
      );
    }

    // Jarum dial
    final needleLength = radius - 20;
    final needleEnd = Offset(
      center.dx + needleLength * math.cos(angle - math.pi / 2),
      center.dy + needleLength * math.sin(angle - math.pi / 2),
    );
    final needlePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needlePaint);

    // Titik tengah
    final centerPaint = Paint()
      ..color = colorScheme.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, centerPaint);

    // Indikator progress (busur)
    final arcPaint = Paint()
      ..color = colorScheme.primary.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 4),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.progress != progress;
  }
}
