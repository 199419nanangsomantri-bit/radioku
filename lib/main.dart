import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zeba_academy_waveforms/zeba_academy_waveforms.dart';

// ============================================================
// MODEL & KONFIGURASI
// ============================================================
class Station {
  final String name;
  final String url;
  final String? favicon;
  final String? tags;
  const Station(this.name, this.url, {this.favicon, this.tags});
}

const String _userAgent = 'RadioSaya/1.0';

const String _prefsKeyStations = 'cached_stations_v2';
const String _prefsKeyScan = 'scan_results_v2';
const String _prefsKeyFavorites = 'favorite_urls_v1';
const String _prefsKeyBackground = 'background_image_path_v1';

// ============================================================
// MAIN
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

// ============================================================
// HALAMAN UTAMA
// ============================================================
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

class _RadioPageState extends State<RadioPage>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  List<StationStatus> _statuses = [];
  Set<String> _favoriteUrls = {};

  String? _currentPlayingUrl;
  String? _playingStationName;
  String? _error;
  bool _loading = false;
  int _loadToken = 0;
  DateTime? _pausedAt;

  bool _isScanning = false;
  bool _stopScan = false;
  bool _dataLoaded = false;
  bool _fetchingFromApi = false;

  final AudioPlayer _scanner = AudioPlayer();
  final ImagePicker _imagePicker = ImagePicker();

  String? _backgroundPath;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

    await _loadBackground();
    await _loadFavorites();
    await _loadCachedStations();
    if (_statuses.isEmpty) {
      await _fetchStationsFromApi();
    }
  }

  // ---------------- BACKGROUND ----------------
  Future<void> _loadBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_prefsKeyBackground);
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          if (mounted) setState(() => _backgroundPath = path);
        } else {
          await prefs.remove(_prefsKeyBackground);
        }
      }
    } catch (_) {}
  }

  Future<void> _pickBackground() async {
    try {
      final XFile? picked =
          await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last;
      final destPath = '${dir.path}/background_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(picked.path).copy(destPath);

      final prefs = await SharedPreferences.getInstance();
      final oldPath = prefs.getString(_prefsKeyBackground);
      if (oldPath != null && oldPath.isNotEmpty) {
        try {
          final oldFile = File(oldPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (_) {}
      }
      await prefs.setString(_prefsKeyBackground, destPath);

      if (mounted) {
        setState(() => _backgroundPath = destPath);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Background diganti.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memilih gambar: $e')),
        );
      }
    }
  }

  Future<void> _resetBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_prefsKeyBackground);
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      await prefs.remove(_prefsKeyBackground);
      if (mounted) {
        setState(() => _backgroundPath = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Background dikembalikan ke default.')),
        );
      }
    } catch (_) {}
  }

  // ---------------- FAVORIT ----------------
  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKeyFavorites);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        if (mounted) {
          setState(() {
            _favoriteUrls = list.map((e) => e as String).toSet();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKeyFavorites, jsonEncode(_favoriteUrls.toList()));
    } catch (_) {}
  }

  void _toggleFavorite(String url) {
    setState(() {
      if (_favoriteUrls.contains(url)) {
        _favoriteUrls.remove(url);
      } else {
        _favoriteUrls.add(url);
      }
    });
    _saveFavorites();
  }

  bool _isFavorite(String url) => _favoriteUrls.contains(url);

  // ---------------- FETCH & PERSISTENCE ----------------
  Future<void> _loadCachedStations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawStations = prefs.getString(_prefsKeyStations);
      final rawScan = prefs.getString(_prefsKeyScan);

      Map<String, dynamic> scanData = {};
      if (rawScan != null) {
        scanData = jsonDecode(rawScan) as Map<String, dynamic>;
      }

      List<StationStatus> loaded = [];
      if (rawStations != null && rawStations.isNotEmpty) {
        final List<dynamic> list = jsonDecode(rawStations);
        loaded = list.map((e) {
          final map = e as Map<String, dynamic>;
          final url = map['url'] as String;
          final stateStr = scanData[url] as String?;
          ScanState state = ScanState.unknown;
          if (stateStr == 'active') state = ScanState.active;
          if (stateStr == 'dead') state = ScanState.dead;
          return StationStatus(
            Station(
              map['name'] as String,
              url,
              favicon: map['favicon'] as String?,
              tags: map['tags'] as String?,
            ),
            state: state,
          );
        }).toList();
      }

      if (mounted) {
        setState(() {
          _statuses = loaded;
          _dataLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _dataLoaded = true);
    }
  }

  Future<void> _saveStations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stationsJson = jsonEncode(_statuses.map((s) => {
            'name': s.station.name,
            'url': s.station.url,
            'favicon': s.station.favicon,
            'tags': s.station.tags,
          }).toList());
      await prefs.setString(_prefsKeyStations, stationsJson);

      final Map<String, String> scanMap = {};
      for (final s in _statuses) {
        if (s.state == ScanState.active) scanMap[s.station.url] = 'active';
        if (s.state == ScanState.dead) scanMap[s.station.url] = 'dead';
      }
      await prefs.setString(_prefsKeyScan, jsonEncode(scanMap));
    } catch (_) {}
  }

  Future<void> _fetchStationsFromApi() async {
    if (_fetchingFromApi) return;
    setState(() {
      _fetchingFromApi = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
          'https://de1.api.radio-browser.info/json/stations/search?countrycode=ID&hidebroken=true&limit=200&order=votes&reverse=true');
      final response = await http.get(
        uri,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<StationStatus> newList = data.map((e) {
          final map = e as Map<String, dynamic>;
          return StationStatus(
            Station(
              map['name'] as String? ?? 'Tanpa Nama',
              map['url_resolved'] as String? ?? '',
              favicon: map['favicon'] as String?,
              tags: map['tags'] as String?,
            ),
          );
        }).where((s) => s.station.url.isNotEmpty).toList();

        if (mounted) {
          setState(() {
            _statuses = newList;
            _fetchingFromApi = false;
          });
          await _saveStations();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${newList.length} stasiun berhasil dimuat.')),
          );
        }
      } else {
        throw Exception('Gagal memuat: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchingFromApi = false;
          _error = 'Gagal mengambil daftar stasiun. Periksa koneksi internet.';
        });
        if (_statuses.isEmpty) {
          setState(() {
            _statuses =
                _fallbackStations.map((s) => StationStatus(s)).toList();
          });
        }
      }
    }
  }

  List<Station> get _fallbackStations => [
        Station('RRI Pro 3', 'https://streaming.rri.go.id/pro3.mp3'),
        Station('Sunda Radio', 'https://sundaradio.com/stream'),
      ];

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
                  id: s.url, title: s.name, artist: 'Radio Indonesia'),
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
      final active =
          _statuses.where((s) => s.state == ScanState.active).toList();
      final first = active.isNotEmpty
          ? active.first
          : (_statuses.isNotEmpty ? _statuses.first : null);
      if (first != null) _playStation(first.station);
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
    if (_isScanning || _statuses.isEmpty) return;
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
    await _saveStations();

    final activeCount =
        _statuses.where((s) => s.state == ScanState.active).length;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Scan selesai. $activeCount aktif. Hasil disimpan.')),
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

  @override
  void dispose() {
    _tabController.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _scanner.dispose();
    super.dispose();
  }

  // ---------------- UI HELPERS ----------------
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
        return 'Aktif';
      case ScanState.dead:
        return 'Tidak tersedia';
    }
  }

  Widget _buildStationTile(StationStatus s, ColorScheme cs) {
    final isCurrent = s.station.url == _currentPlayingUrl;
    final isFav = _isFavorite(s.station.url);
    return ListTile(
      leading: Icon(
        _statusIcon(s.state),
        color: _statusColor(s.state, cs),
      ),
      title: Text(
        s.station.name,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        _subtitle(s.state),
        style: TextStyle(
          color: _statusColor(s.state, cs),
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: isFav ? 'Hapus favorit' : 'Tambah favorit',
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Colors.red : cs.onSurfaceVariant,
            ),
            onPressed: () => _toggleFavorite(s.station.url),
          ),
          Icon(
            isCurrent && _isPlaying ? Icons.graphic_eq : Icons.play_arrow,
          ),
        ],
      ),
      onTap: () => _playStation(s.station),
    );
  }

  Widget _buildStationList(List<StationStatus> list, ColorScheme cs) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Belum ada stasiun di sini.\nTekan ikon hati pada stasiun untuk menambah favorit.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) => _buildStationTile(list[i], cs),
    );
  }

  // ---------------- BACKGROUND WRAPPER ----------------
  Widget _buildBackground(Widget child) {
    if (_backgroundPath == null) {
      return child;
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(
            File(_backgroundPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(),
          ),
        ),
        // Overlay gelap transparan supaya teks & tombol tetap jelas
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.55),
          ),
        ),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeCount =
        _statuses.where((s) => s.state == ScanState.active).length;
    final favoriteList =
        _statuses.where((s) => _isFavorite(s.station.url)).toList();

    if (!_dataLoaded || (_statuses.isEmpty && _fetchingFromApi)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasBackground = _backgroundPath != null;

    return Scaffold(
      extendBodyBehindAppBar: hasBackground,
      appBar: AppBar(
        title: const Text('Radio Indonesia'),
        centerTitle: true,
        backgroundColor:
            hasBackground ? Colors.transparent : null,
        elevation: hasBackground ? 0 : null,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.wallpaper),
            tooltip: 'Background',
            onSelected: (v) {
              if (v == 'pick') _pickBackground();
              if (v == 'reset') _resetBackground();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'pick',
                child: Row(
                  children: [
                    Icon(Icons.image),
                    SizedBox(width: 8),
                    Text('Pilih dari galeri'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt),
                    SizedBox(width: 8),
                    Text('Reset ke default'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Refresh dari internet',
            icon: _fetchingFromApi
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _fetchingFromApi ? null : _fetchStationsFromApi,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.list),
              text: 'Semua (${_statuses.length})',
            ),
            Tab(
              icon: const Icon(Icons.favorite),
              text: 'Favorit (${favoriteList.length})',
            ),
          ],
        ),
      ),
      body: _buildBackground(
        SafeArea(
          child: Column(
            children: [
              // Player header
              Container(
                width: double.infinity,
                color: hasBackground
                    ? Colors.black.withOpacity(0.35)
                    : cs.surfaceContainerHighest,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: _isPlaying
                              ? const ZebaEqualizer(
                                  color: Colors.amber,
                                )
                              : Icon(
                                  _isBuffering
                                      ? Icons.hourglass_top
                                      : Icons.radio,
                                  size: 36,
                                  color: hasBackground
                                      ? Colors.amber
                                      : cs.primary,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _playingStationName ?? 'Pilih stasiun',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: hasBackground
                                          ? Colors.white
                                          : null,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _isBuffering
                                    ? 'Memuat...'
                                    : (_isPlaying
                                        ? 'Sedang diputar'
                                        : (_currentPlayingUrl == null
                                            ? 'Siap'
                                            : 'Dijeda')),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: hasBackground
                                          ? Colors.white70
                                          : null,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          iconSize: 22,
                          tooltip: 'Stop',
                          onPressed:
                              _currentPlayingUrl == null ? null : _stop,
                          icon: const Icon(Icons.stop),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              IconButton.filled(
                                iconSize: 28,
                                onPressed: _togglePlayPause,
                                icon: Icon(_isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow),
                              ),
                              if (_isBuffering)
                                IgnorePointer(
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: cs.onPrimary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: hasBackground ? Colors.amber : cs.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Tombol scan
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _isScanning || _statuses.isEmpty
                            ? null
                            : _startScan,
                        icon: Icon(_isScanning
                            ? Icons.hourglass_top
                            : Icons.wifi_find),
                        label: Text(_isScanning
                            ? 'Scanning...'
                            : 'Scan stasiun aktif'),
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
                    Text('$activeCount aktif',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasBackground
                              ? Colors.white70
                              : cs.onSurfaceVariant,
                        )),
                    Text('${_statuses.length} stasiun',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasBackground
                              ? Colors.white70
                              : cs.onSurfaceVariant,
                        )),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              // Konten tab
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStationListWithBg(_statuses, cs, hasBackground),
                    _buildStationListWithBg(
                        favoriteList, cs, hasBackground),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationListWithBg(
      List<StationStatus> list, ColorScheme cs, bool hasBackground) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Belum ada stasiun di sini.\nTekan ikon hati pada stasiun untuk menambah favorit.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hasBackground ? Colors.white70 : cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final s = list[i];
        final isCurrent = s.station.url == _currentPlayingUrl;
        final isFav = _isFavorite(s.station.url);
        final textColor = hasBackground ? Colors.white : null;
        final subColor = hasBackground
            ? _statusColor(s.state, cs).withOpacity(0.95)
            : _statusColor(s.state, cs);
        return ListTile(
          leading: Icon(
            _statusIcon(s.state),
            color: hasBackground
                ? _statusColor(s.state, cs).withOpacity(0.95)
                : _statusColor(s.state, cs),
          ),
          title: Text(
            s.station.name,
            style: TextStyle(
              color: textColor,
              fontWeight:
                  isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            _subtitle(s.state),
            style: TextStyle(color: subColor, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: isFav ? 'Hapus favorit' : 'Tambah favorit',
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav
                      ? Colors.red
                      : (hasBackground
                          ? Colors.white70
                          : cs.onSurfaceVariant),
                ),
                onPressed: () => _toggleFavorite(s.station.url),
              ),
              Icon(
                isCurrent && _isPlaying
                    ? Icons.graphic_eq
                    : Icons.play_arrow,
                color: textColor,
              ),
            ],
          ),
          onTap: () => _playStation(s.station),
        );
      },
    );
  }
}
