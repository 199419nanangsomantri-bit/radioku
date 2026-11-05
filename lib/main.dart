
    }
  }

  // ----        _player.processingState == ProcessingState.ready;
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
      final first =
          active.isNotEmpty ? active.first : (_statuses.isNotEmpty ? _statuses.first : null);
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

  // ---------------- UI ----------------
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeCount =
        _statuses.where((s) => s.state == ScanState.active).length;

    if (!_dataLoaded || (_statuses.isEmpty && _fetchingFromApi)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: cs.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child:                           ? Icons.hourglass_top
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
                      style: Theme.of(context).textTheme.bodySmall),
                  Text('${_statuses.length} stasiun',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: _statuses.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Daftar stasiun kosong.\nTekan tombol refresh di atas untuk memuat dari internet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _statuses.length,
                      itemBuilder: (context, i) {
                        final s = 
