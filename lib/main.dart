import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// DAFTAR KANDIDAT STASIUN
// ============================================================
class Station {
  final String name;
  final String url;
  const Station(this.name, this.url);
}

const List<Station> candidateStations = [
  Station('Sunda Radio (Wayang Golek)', 'https://sundaradio.com/stream'),
  Station('RRI Pro 3', 'https://streaming.rri.go.id/pro3.mp3'),
  Station('RRI Net', 'https://streaming.rri.go.id/rrinet.mp3'),
  Station('SITI (RRI)', 'https://streaming.rri.go.id/siti.mp3'),
  Station('RRI Pro 1 Banda Aceh', 'https://stream-node2.rri.co.id/streaming/14/9214/rribandaacehpro1.mp3'),
  Station('Elshinta Bandung', 'https://stream-ssl.arenastreaming.com:8005/bandung'),
  Station('Cosmopolitan Radio', 'https://stream.radiojar.com/u7d8heq3bnzuv'),
  Station('Brava Radio', 'https://stream.radiojar.com/5k7t0rq3bnzuv'),
  Station('Hard Rock FM', 'http://n09.radiojar.com/7csmg90fuqruv.mp3'),
  Station('DMI Radio', 'https://stream.radiojar.com/7csmg90fuqruv'),
  Station('Dahlia FM Bandung', 'https://svara-stream.radioddns.net:8443/bandung_dahliafm'),
  Station('Suara Surabaya FM', 'https://ssfm.siar.us/ssfm/live/playlist.m3u8'),
  Station('EBS FM', 'http://streaming.suzanafm.com:8100/;stream.nsv'),
  Station('Radio Maria Indonesia', 'https://dreamsiteradiocp2.com/proxy/rmindonesia2?mp=/stream'),
  Station('Bahtera Yudha FM', 'http://streaming.bahterayudhafm.com:8050/;stream.nsv'),
  Station('Kharisma FM', 'https://ssg.streamingmurah.com:8342/;'),
  Station('Bali United FM', 'https://c1.siar.us:10690/stream'),
  Station('Baiturrahman FM', 'https://s7.alhastream.com/radio/8060/radio'),
  Station('Hitz FM', 'https://s2.radio.co/s6929cb202/listen'),
];
// ============================================================

// Kunci penyimpanan
const String _prefsKey = 'scan_results_v1';

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
      title: 'Radio Indonesia',
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

enum ScanState { unknown, testing, active, dead }

class StationStatus {
  final Station station;
  ScanState state;
  StationStatus(this.station, {this.state = ScanState.unknown});
}

class RadioPage extends StatefulWidget {
  const RadioPage({super.key});

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  final List<StationStatus> _statuses =
      candidateStations.map((s) => StationStatus(s)).toList();

  String? _currentPlayingUrl;
  String? _playingStationName;
  String? _error;
  bool _loading = false;
  int _loadToken = 0;
  DateTime? _pausedAt;

  bool _isScanning = false;
  bool _stopScan = false;
  bool _dataLoaded = false;

  final AudioPlayer _scanner = AudioPlayer();

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
          _error = 'Stream terputus. Coba lagi atau pilih stasiun lain.';
        });
        unawaited(_player.stop());
      },
    ));

    await _loadScanResults();
  }

  // ---------------- PERSISTENCE ----------------
  Future<void> _loadScanResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> decoded =
            jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            for (final s in _statuses) {
              final value = decoded[s.station.url];
              if (value == 'active') {
                s.state = ScanState.active;
              } else if (value == 'dead') {
                s.state = ScanState.dead;
              } else {
                s.state = ScanState.unknown;
              }
            }
            _dataLoaded = true;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _dataLoaded = true);
  }

  Future<void> _saveScanResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, String> data = {};
      for (final s in _statuses) {
        if (s.state == ScanState.active) {
          data[s.station.url] = 'active';
        } else if (s.state == ScanState.dead) {
          data[s.station.url] = 'dead';
        }
      }
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _clearScanResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      for (final s in _statuses) {
        s.state = ScanState.unknown;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hasil scan dihapus.')),
    );
  }

  // ---------------- PLAYER ----------------
  bool get _isPlaying {
    return _player.playerState.playing &&
        _player.processingState == ProcessingState.ready;
  }

  bool get _isBuffering {
    return _loading ||
        _player.processingState == ProcessingState.loading ||
        _player.processingState == ProcessingState.buffering;
  }

  Future<void> _playStation(Station s) async {
    final token = ++_loadToken;
    setState(() {
      _currentPlayingUrl = s.url;
      _playingStationName = s.name;
      _error = null;
      _loading = true;
    });

    try {
      await _player
          .setAudioSource(
            AudioSource.uri(
              Uri.parse(s.url),
              tag: MediaItem(
                id: s.url,
                title: s.name,
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
      await _fail(token, 'Koneksi terlalu lama. Cek internet.');
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
      _currentPlayingUrl = null;
      _playingStationName = null;
    });
  }

  void _togglePlayPause() {
    if (_currentPlayingUrl == null) {
      final active = _statuses.where((s) => s.state == ScanState.active).toList();
      final first = active.isNotEmpty ? active.first : _statuses.first;
      _playStation(first.station);
      return;
    }
    if (_isPlaying) {
      _pausedAt = DateTime.now();
      unawaited(_player.pause());
    } else {
      final p = _pausedAt;
      if (p != null &&
          DateTime.now().difference(p) > const Duration(seconds: 30)) {
        final st = _statuses.firstWhere(
          (s) => s.station.url == _currentPlayingUrl,
          orElse: () => _statuses.first,
        );
        _playStation(st.station);
      } else {
        unawaited(_player.play());
      }
    }
  }

  // ---------------- SCAN ----------------
  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _stopScan = false;
      for (final s in _statuses) {
        s.state = ScanState.unknown;
      }
    });

    for (final status in _statuses) {
      if (_stopScan || !mounted) break;
      setState(() => status.state = ScanState.testing);
      final ok = await _testUrl(status.station.url);
      if (!mounted) return;
      setState(() => status.state = ok ? ScanState.active : ScanState.dead);
    }

    if (!mounted) return;
    setState(() => _isScanning = false);

    await _saveScanResults();

    final activeCount =
        _statuses.where((s) => s.state == ScanState.active).length;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Scan selesai. $activeCount aktif. Hasil disimpan.'),
        ),
      );
    }
  }

  Future<bool> _testUrl(String url) async {
    try {
      await _scanner.stop();
      await _scanner.setUrl(url).timeout(const Duration(seconds: 12));
      await _scanner.play().timeout(const Duration(seconds: 3));
      await _scanner.stop();
      return true;
    } catch (_) {
      try {
        await _scanner.stop();
      } catch (_) {}
      return false;
    }
  }

  void _stopScanning() {
    setState(() => _stopScan = true);
  }

  void _copyActiveToClipboard() {
    final active =
        _statuses.where((s) => s.state == ScanState.active).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada stasiun aktif.')),
      );
      return;
    }
    final buf = StringBuffer('const List<Station> stations = [\n');
    for (final s in active) {
      buf.writeln("  Station('${s.station.name}', '${s.station.url}'),");
    }
    buf.writeln('];');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '${active.length} stasiun aktif disalin ke clipboard.')),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _scanner.dispose();
    super.dispose();
  }

  IconData _statusIcon(ScanState s) {
    switch (s) {
      case ScanState.unknown:
        return Icons.help_outline;
      case ScanState.testing:
        return Icons.hourglass_top;
      case ScanState.active:
        return Icons.check_circle;
      case ScanState.dead:
        return Icons.cancel;
    }
  }

  Color _statusColor(ScanState s, ColorScheme cs) {
    switch (s) {
      case ScanState.unknown:
        return cs.onSurfaceVariant;
      case ScanState.testing:
        return cs.primary;
      case ScanState.active:
        return Colors.green;
      case ScanState.dead:
        return cs.error;
    }
  }

  String _subtitle(ScanState s) {
    switch (s) {
      case ScanState.unknown:
        return 'Belum diuji';
      case ScanState.testing:
        return 'Menguji...';
      case ScanState.active:
        return 'Aktif (tersimpan)';
      case ScanState.dead:
        return 'Tidak tersedia (tersimpan)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeCount =
        _statuses.where((s) => s.state == ScanState.active).length;

    if (!_dataLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Radio Indonesia'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Salin stasiun aktif',
            icon: const Icon(Icons.copy),
            onPressed: _copyActiveToClipboard,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'clear') _clearScanResults();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'clear',
                child: Text('Hapus hasil scan'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: cs.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                children: [
                  Icon(
                    _isBuffering
                        ? Icons.hourglass_top
                        : (_isPlaying ? Icons.graphic_eq : Icons.radio),
                    size: 48,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _playingStationName ?? 'Pilih stasiun',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isBuffering
                        ? 'Memuat...'
                        : (_isPlaying
                            ? 'Sedang diputar'
                            : (_currentPlayingUrl == null
                                ? 'Siap'
                                : 'Dijeda')),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        iconSize: 28,
                        tooltip: 'Stop',
                        onPressed:
                            _currentPlayingUrl == null ? null : _stop,
                        icon: const Icon(Icons.stop),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            IconButton.filled(
                              iconSize: 34,
                              onPressed: _togglePlayPause,
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                              ),
                            ),
                            if (_isBuffering)
                              IgnorePointer(
                                child: SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: cs.onPrimary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.error, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _isScanning ? null : _startScan,
                      icon: Icon(_isScanning
                          ? Icons.hourglass_top
                          : Icons.wifi_find),
                      label: Text(_isScanning
                          ? 'Scanning...'
                          : 'Scan ulang stasiun'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isScanning)
                    IconButton.filled(
                      tooltip: 'Hentikan scan',
                      icon: const Icon(Icons.stop_circle),
                      onPressed: _stopScanning,
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$activeCount aktif',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${_statuses.length} stasiun',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView.builder(
                itemCount: _statuses.length,
                itemBuilder: (context, i) {
                  final s = _statuses[i];
                  final isCurrent = s.station.url == _currentPlayingUrl;
                  return ListTile(
                    leading: Icon(
                      _statusIcon(s.state),
                      color: _statusColor(s.state, cs),
                    ),
                    title: Text(
                      s.station.name,
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      _subtitle(s.state),
                      style: TextStyle(
                        color: _statusColor(s.state, cs),
                        fontSize: 12,
                      ),
                    ),
                    trailing: isCurrent && _isPlaying
                        ? const Icon(Icons.graphic_eq)
                        : const Icon(Icons.play_arrow),
                    onTap: () => _playStation(s.station),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
