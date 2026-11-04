import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

// ============================================================
// DAFTAR STASIUN - EDIT DI SINI
// Format: Station('Nama Tampil', 'URL stream')
// ============================================================
class Station {
  final String name;
  final String url;
  const Station(this.name, this.url);
}

const List<Station> stations = [
  Station('SomaFM - Groove Salad', 'https://ice1.somafm.com/groovesalad-128-mp3'),
  Station('SomaFM - Drone Zone', 'https://ice1.somafm.com/dronezone-128-mp3'),
  Station('Radio Paradise - Main Mix', 'https://stream.radioparadise.com/mp3-128'),
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
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
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
    } catch (_) {
      // Abaikan: audio tetap bisa jalan tanpa konfigurasi sesi.
    }

    _subs.add(_player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    }));

    _subs.add(_player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Stream terputus atau gagal diputar. Coba lagi.';
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
                artist: 'Radio Saya',
              ),
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (token != _loadToken || !mounted) return;
      setState(() => _loading = false);
      unawaited(_player.play());
    } on PlayerInterruptedException {
      // Dibatalkan karena user ganti stasiun/stop. Abaikan.
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
        // Radio itu siaran langsung: jika jeda lama, muat ulang agar tidak basi.
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
        title: const Text('Radio Saya'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kartu stasiun + status
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                  child: Column(
                    children: [
                      Icon(_statusIcon(status), size: 72, color: cs.primary),
                      const SizedBox(height: 16),
                      Text(
                        _station.name,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Chip(label: Text(_statusText(status))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Pesan error
              if (_error != null)
                Card(
                  elevation: 0,
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: cs.onErrorContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: cs.onErrorContainer),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _startStation(_index),
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error != null) const SizedBox(height: 16),

              // Pilih stasiun
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Stasiun',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _index,
                    items: [
                      for (int i = 0; i < stations.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(stations[i].name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) _startStation(v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 28),

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
                    width: 84,
                    height: 84,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton.filled(
                          iconSize: 44,
                          tooltip: isPlaying ? 'Pause' : 'Play',
                          onPressed: _onPlayPressed,
                          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                        if (isBuffering)
                          IgnorePointer(
                            child: SizedBox(
                              width: 80,
                              height: 80,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: cs.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 56), // penyeimbang agar tombol play di tengah
                ],
              ),
              const SizedBox(height: 28),

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
            ],
          ),
        ),
      ),
    );
  }
}
