import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../providers/providers.dart';
import '../services/storage_service.dart';

// ─── Data model ────────────────────────────────────────────────────────────────

/// A tars.MD source — a leaf node in the dictionaryIndices.md hierarchy.
class _TarsSource {
  _TarsSource({
    required this.tarsUrl,
    required this.displayPath, // e.g. "sa-head/sa-entries"
    required this.breadcrumb,  // e.g. ["sa - संस्कृतम्", "Basic"]
    required this.folderPath,  // sanitized nested folder for storage
  });

  final String tarsUrl;
  final String displayPath;
  final List<String> breadcrumb;
  final String folderPath;

  // Fetched dictionaries (null = not yet fetched, empty = fetch failed/empty)
  List<_DictEntry>? entries;
  bool isFetching = false;
  bool fetchFailed = false;

  // Whether this group is selected (tri-state via entries)
  bool get allSelected =>
      entries != null && entries!.isNotEmpty && entries!.every((e) => e.isSelected);
  bool get anySelected => entries != null && entries!.any((e) => e.isSelected);
}

enum _DictStatus { newFile, updateAvailable, upToDate }

/// A single dictionary archive inside a tars.MD.
class _DictEntry {
  _DictEntry({
    required this.url,
    required this.name,
    required this.date,
    required this.sizeMb,
    required this.folderPath,
    required this.status,
  });

  final String url;
  final String name;
  final String date;
  double sizeMb;
  final String folderPath;
  final _DictStatus status;

  bool isSelected = false;
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

/// Extracts the interesting path from a tars.MD URL, e.g.:
///   https://raw.githubusercontent.com/.../gh-pages/sa-head/sa-entries/tars/tars.MD
///   → "sa-head/sa-entries"
String _displayPath(String url) {
  final ghIdx = url.indexOf('/gh-pages/');
  if (ghIdx == -1) {
    // fallback: last two segments before tars/tars.MD
    final segs = Uri.parse(url).pathSegments;
    final tarsIdx = segs.lastIndexOf('tars');
    if (tarsIdx >= 2) {
      return segs.sublist(tarsIdx - 2, tarsIdx).join('/');
    }
    return segs.take(segs.length - 2).lastOrNull ?? url;
  }
  final afterGhPages = url.substring(ghIdx + '/gh-pages/'.length);
  // remove trailing /tars/tars.MD or /tars/tars_external.MD
  final cleaned = afterGhPages.replaceAll(RegExp(r'/tars/tars.*\.MD$', caseSensitive: false), '');
  return cleaned.isEmpty ? 'tars' : cleaned;
}


/// Parses dictionaryIndices.md into a flat list of _TarsSource objects.
List<_TarsSource> _parseIndices(String markdown, StorageService storage) {
  final lines = markdown.split('\n');
  String h2 = '', h3 = '', h4 = '';
  final sources = <_TarsSource>[];

  final urlRe = RegExp(r'<(https?://\S+\.MD)>', caseSensitive: false);

  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('#### ')) {
      h4 = line.substring(5).trim();
    } else if (line.startsWith('### ')) {
      h3 = line.substring(4).trim();
      h4 = '';
    } else if (line.startsWith('## ')) {
      h2 = line.substring(3).trim();
      h3 = h4 = '';
    } else if (!line.startsWith('Disabled:')) {
      final m = urlRe.firstMatch(line);
      if (m != null && h2.isNotEmpty) {
        final url = m.group(1)!;
        final crumbs = [h2, if (h3.isNotEmpty) h3, if (h4.isNotEmpty) h4];
        // Build storage folder identifier: Indic-dict/h2/h3/h4
        final folderPath = ['Indic-dict', ...crumbs].join('/');
        sources.add(_TarsSource(
          tarsUrl: url,
          displayPath: _displayPath(url),
          breadcrumb: crumbs,
          folderPath: folderPath,
        ));
      }
    }
  }
  return sources;
}

/// Parses a tars.MD content into archive URLs.
List<String> _parseTarsMd(String content) {
  const archiveExt =
      r'\.(?:tar\.gz|tgz|tar\.bz2|tbz2|tar\.xz|txz|tar\.lzma|tlz|tar\.zst|tzst|zip|7z|rar|bz2|xz|lzma|zst|dz)';
  final re = RegExp(r'https?://\S+?' + archiveExt, caseSensitive: false);
  return re.allMatches(content).map((m) => m.group(0)!).toList();
}

/// Extracts display metadata from a structured filename.
_DictEntry _parseEntry(String url, String folderPath, Set<String> localFiles, StorageService storage) {
  final rawFilename = url.split('/').last;
  final filename = storage.sanitizeFileName(rawFilename);

  // 1. Try to find size (e.g. _12.5MB.) anywhere in the filename
  final sizeRe = RegExp(r'_([\d.]+)MB\.', caseSensitive: false);
  final sm = sizeRe.firstMatch(filename);
  final sizeMb = sm != null ? (double.tryParse(sm.group(1)!) ?? 0.0) : 0.0;

  // 2. Try to parse structured name/date
  final fullRe = RegExp(
    r'^(.+?)_(\d{8})_(\d{6})_([\d.]+)MB\.(.+)$',
    caseSensitive: false,
  );
  final m = fullRe.firstMatch(filename);

  String name = filename;
  String date = '';
  String baseName = filename;

  if (m != null) {
    baseName = m.group(1)!;
    name = baseName.replaceAll('_', ' ');
    final rawDate = m.group(2)!;
    date =
        '${rawDate.substring(0, 4)}-${rawDate.substring(4, 6)}-${rawDate.substring(6, 8)}';
  }

  // 3. Determine status
  _DictStatus status = _DictStatus.newFile;
  if (localFiles.contains(filename)) {
    status = _DictStatus.upToDate;
  } else {
    // Look for any file starting with the same base name
    final matchingBase = localFiles.where((f) => f.startsWith('${baseName}_'));
    if (matchingBase.isNotEmpty) {
      status = _DictStatus.updateAvailable;
    }
  }

  final entry = _DictEntry(
    url: url,
    name: name,
    date: date,
    sizeMb: sizeMb,
    folderPath: folderPath,
    status: status,
  );

  // Auto-select if new or update available
  entry.isSelected = status != _DictStatus.upToDate;

  return entry;
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class IndicDictBrowserScreen extends StatefulWidget {
  const IndicDictBrowserScreen({super.key, required this.ref});
  final WidgetRef ref;

  @override
  State<IndicDictBrowserScreen> createState() => _IndicDictBrowserScreenState();
}

class _IndicDictBrowserScreenState extends State<IndicDictBrowserScreen> {
  static const _indicesUrl =
      'https://github.com/indic-dict/stardict-index/releases/download/current/dictionaryIndices.md';

  bool _loadingIndex = true;
  String? _indexError;
  List<_TarsSource> _sources = [];
  final List<String> _failedResources = [];

  // Counts for the bottom bar
  int get _fetchedCount => _sources.where((s) => s.entries != null).length;
  int get _totalCount => _sources.length;
  bool get _allFetched => _fetchedCount == _totalCount;

  List<_DictEntry> get _selectedDicts =>
      _sources.expand<_DictEntry>((s) => s.entries ?? []).where((e) => e.isSelected).toList();

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    try {
      // GitHub raw sometimes rejects requests that don’t supply a browser-like
      // User-Agent; use a simple UA string to avoid 401 responses.
      final dio = Dio(BaseOptions(headers: {
        'User-Agent': 'Mozilla/5.0 (Flutter)'
      }));
      final resp = await dio.get<String>(_indicesUrl);
      final storage = widget.ref.read(storageServiceProvider);
      final sources = _parseIndices(resp.data ?? '', storage);
      if (mounted) {
        setState(() {
          _sources = sources;
          _loadingIndex = false;
        });
      }
      // Auto-fetch all tars.MD files in parallel
      await _fetchAll(sources);
    } catch (e) {
      if (mounted) {
        setState(() {
          _indexError = e.toString();
          _loadingIndex = false;
        });
      }
    }
  }

  Future<void> _fetchAll(List<_TarsSource> sources) async {
    // Use same UA for all subsequent network requests as well.
    final dio = Dio(BaseOptions(headers: {
      'User-Agent': 'Mozilla/5.0 (Flutter)'
    }));
    // Fetch in batches of 5 to avoid overloading UI/Isolates
    const batchSize = 5;
    for (var i = 0; i < sources.length; i += batchSize) {
      final end = (i + batchSize < sources.length) ? i + batchSize : sources.length;
      final batch = sources.sublist(i, end);
      await Future.wait(batch.map((src) => _fetchOne(dio, src)));
    }

    // All sources have now completed; show a single dialog if any failures
    if (_failedResources.isNotEmpty) {
      final uniqueFailures = _failedResources.toSet().toList();
      setState(() {
        _failedResources
          ..clear()
          ..addAll(uniqueFailures);
      });
      _showFailureDialog();
    }
  }

  Future<void> _fetchOne(Dio dio, _TarsSource src) async {
    if (mounted) setState(() => src.isFetching = true);
    try {
      final storage = widget.ref.read(storageServiceProvider);
      // Get the correct directory where this source's dictionaries are stored.
      // StorageService will flatten the folderPath (sourceName) into a filesystem-safe name.
      Directory dir;
      try {
        dir = await storage.getStorageDirectory(sourceName: src.folderPath);
      } on PathAccessException catch (e) {
        debugPrint('Cannot create/access storage directory for ${src.folderPath}: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Cannot access storage for "${src.folderPath}".\n'
                  'Check Downloads permissions or change storage location.'),
            ),
          );
          setState(() {
            src.isFetching = false;
            src.fetchFailed = true;
          });
        }
        // Skip this source rather than treating it as a network failure. The
        // failure dialog isn't helpful in this case because it's a local
        // permission problem, and the snackbar above already alerts the user.
        return;
      }

      // Attempt to gather already-downloaded files so we can mark them as
      // up-to-date.  On macOS the Downloads folder is protected by privacy
      // restrictions; if the user has denied access to this particular
      // directory we may get a PathAccessException.  That should not prevent us
      // from fetching the listing from the network, so treat failures here as
      // an empty directory and report a log entry.
      final localFiles = <String>{};
      if (await dir.exists()) {
        try {
          final list = await dir.list().toList();
          for (final f in list) {
            if (f is File) {
              localFiles.add(p.basename(f.path));
            }
          }
        } on PathAccessException catch (e) {
          debugPrint(
              'Permission denied accessing local storage for ${src.folderPath}: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Cannot access storage for "${src.folderPath}".\n'
                    'Check Downloads permissions or change storage location.'),
              ),
            );
          }
          // Continue with empty `localFiles` rather than aborting the whole
          // fetch; the user may need to grant filesystem permission or
          // choose a different storage directory via settings.
        }
      }

      // Fetch the tars listing.  GitHub raw content can occasionally return
      // 401 if the User-Agent is missing or unrecognized; we already configured
      // the dio client above with a browser-like UA, but log any errors that
      // occur so they can be inspected in the console.
      final resp = await dio.get<String>(src.tarsUrl);
      final archiveUrls = _parseTarsMd(resp.data ?? '');
      final entries = archiveUrls.map((u) => _parseEntry(u, src.folderPath, localFiles, storage)).toList();

      // 1. Initially show entries (some might have 0.0 MB)
      if (mounted) {
        setState(() {
          src.entries = entries;
        });
      }

      // 2. Fetch missing sizes for external indices via HEAD requests
      final missingSizeEntries = entries.where((e) => e.sizeMb == 0.0).toList();
      if (missingSizeEntries.isNotEmpty) {
        // Fetch in smaller batches of 10 to avoid hitting rate limits or hanging
        const headBatchSize = 10;
        for (var i = 0; i < missingSizeEntries.length; i += headBatchSize) {
          if (!mounted) break;
          final batch = missingSizeEntries.sublist(
              i, (i + headBatchSize > missingSizeEntries.length) ? missingSizeEntries.length : i + headBatchSize);
          
          await Future.wait(batch.map((entry) async {
            try {
              final headResp = await dio.head<dynamic>(entry.url);
              final contentLength = headResp.headers.value('content-length');
              if (contentLength != null) {
                final bytes = int.tryParse(contentLength) ?? 0;
                if (mounted) {
                  setState(() {
                    entry.sizeMb = bytes / (1024 * 1024);
                  });
                }
              }
            } catch (e) {
              // HEAD requests sometimes return 401/403 for GitHub-hosted files; we
              // don't care about the exact size, so just log and move on.  Do **not**
              // add the entry to `_failedResources`, since the download itself may
              // still succeed.
              debugPrint('Size query failed for ${entry.url}: $e');
            }
          }));
        }
      }

      if (mounted) {
        setState(() {
          src.isFetching = false;
        });
      }
    } catch (e) {
      // Report the failure to fetch the tars.MD itself; include URL so it's
      // easier to debug which link is problematic.
      debugPrint('Failed to fetch tars for ${src.folderPath}: $e (url ${src.tarsUrl})');
      if (mounted) {
        setState(() {
          src.entries = [];
          src.isFetching = false;
          src.fetchFailed = true;
          final failLabel = '${src.folderPath} → ${src.tarsUrl}';
          if (!_failedResources.contains(failLabel)) _failedResources.add(failLabel);
        });
      }
    }

    // Dialog will be shown once all sources have been processed.  Removing
    // this check prevents multiple simultaneous `_fetchOne` completions from
    // each spawning their own alert.
    //
    // (The check is now performed from `_fetchAll` after all batches finish.)
  }

  void _showFailureDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection Issues'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Could not connect to the following resources while updating:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _failedResources.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${_failedResources[index]}', style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The user is requested to manually verify whether the required resource is available for download or not.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _failedResources.clear();
              });
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToQueue() async {
    final selected = _selectedDicts;
    if (selected.isEmpty) return;

    // Group by folderPath so dicts from the same source become one entry
    final groups = <String, List<_DictEntry>>{};
    for (final e in selected) {
      groups.putIfAbsent(e.folderPath, () => []).add(e);
    }

    final notifier = widget.ref.read(sourcesProvider.notifier);
    for (final entry in groups.entries) {
      final folderPath = entry.key;
      final dicts = entry.value.where((d) => d.status != _DictStatus.upToDate).toList();
      if (dicts.isEmpty) continue;

      // Encode all URLs as a newline-separated data: URI (same as Paste tab)
      final raw = dicts.map((d) => d.url).join('\n');
      final url = 'data:text/plain;charset=utf-8,${Uri.encodeComponent(raw)}';
      await notifier.addSource(url, folderPath);
    }

    if (mounted) {
      final groupCount = groups.length;
      final dictCount = selected.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added $dictCount dictionar${dictCount == 1 ? 'y' : 'ies'} '
            'in $groupCount source group${groupCount == 1 ? '' : 's'}',
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Indic-dicts'),
        actions: [
          if (!_loadingIndex && !_allFetched)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Loading $_fetchedCount/$_totalCount…',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    if (_loadingIndex) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading Indic-dict index…'),
        ]),
      );
    }
    if (_indexError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_indexError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loadingIndex = true;
                  _indexError = null;
                });
                _loadIndex();
              },
              child: const Text('Retry'),
            ),
          ]),
        ),
      );
    }

    // Group sources by h2 → h3
    final byH2 = <String, Map<String, List<_TarsSource>>>{};
    for (final src in _sources) {
      final h2 = src.breadcrumb[0];
      final h3 = src.breadcrumb.length > 1 ? src.breadcrumb[1] : '';
      byH2.putIfAbsent(h2, () => {})[h3] = (byH2[h2]?[h3] ?? [])..add(src);
    }

    return Column(children: [
      // Info bar with loading progress
      if (!_allFetched)
        LinearProgressIndicator(value: _totalCount == 0 ? null : _fetchedCount / _totalCount),
      Container(
        color: Colors.indigo.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 15, color: Colors.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _allFetched
                  ? 'Select dictionary groups or individual dictionaries, then tap "Add to Queue".'
                  : 'Fetching dictionary lists… ($_fetchedCount / $_totalCount)',
              style: const TextStyle(fontSize: 12, color: Colors.indigo),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          children: byH2.entries.map((h2Entry) {
            return _H2Group(
              h2: h2Entry.key,
              byH3: h2Entry.value,
              onChanged: () => setState(() {}),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildBottomBar() {
    if (_loadingIndex) return const SizedBox.shrink();
    final selected = _selectedDicts;
    final count = selected.length;
    final totalSizeMb = selected.fold<double>(0.0, (sum, e) => sum + e.sizeMb);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ElevatedButton.icon(
          onPressed: count > 0 ? _addToQueue : null,
          icon: const Icon(Icons.add_task),
          label: Text(count > 0
              ? 'Add $count (${totalSizeMb.toStringAsFixed(1)} MB) to Queue'
              : 'Select dictionaries above'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─── Group widgets ─────────────────────────────────────────────────────────────

class _H2Group extends StatelessWidget {
  const _H2Group({required this.h2, required this.byH3, required this.onChanged});
  final String h2;
  final Map<String, List<_TarsSource>> byH3;
  final VoidCallback onChanged;

  List<_TarsSource> get _allSources => byH3.values.expand((v) => v).toList();
  List<_DictEntry> get _allEntries =>
      _allSources.expand<_DictEntry>((s) => s.entries ?? []).toList();

  bool get _allSelected =>
      _allEntries.isNotEmpty && _allEntries.every((e) => e.isSelected);
  bool get _anySelected => _allEntries.any((e) => e.isSelected);

  void _toggleAll(bool val) {
    for (final e in _allEntries) { e.isSelected = val; }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final triState = _allSelected ? true : (_anySelected ? null : false);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      elevation: 1,
      child: ExpansionTile(
        leading: Checkbox(
          tristate: true,
          value: triState,
          onChanged: (v) => _toggleAll(v ?? false),
        ),
        title: Text(h2,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        childrenPadding: const EdgeInsets.only(left: 12),
        children: byH3.entries.map((h3Entry) {
          final h3 = h3Entry.key;
          final sources = h3Entry.value;
          if (h3.isEmpty) {
            // Direct sources under h2 (no h3 heading)
            return Column(
              children: sources.map((src) => _SourceGroup(
                src: src,
                onChanged: onChanged,
                showHeader: false,
              )).toList(),
            );
          }
          return _H3Group(h3: h3, sources: sources, onChanged: onChanged);
        }).toList(),
      ),
    );
  }
}

class _H3Group extends StatelessWidget {
  const _H3Group({required this.h3, required this.sources, required this.onChanged});
  final String h3;
  final List<_TarsSource> sources;
  final VoidCallback onChanged;

  List<_DictEntry> get _allEntries =>
      sources.expand<_DictEntry>((s) => s.entries ?? []).toList();

  bool get _allSelected =>
      _allEntries.isNotEmpty && _allEntries.every((e) => e.isSelected);
  bool get _anySelected => _allEntries.any((e) => e.isSelected);

  void _toggleAll(bool val) {
    for (final e in _allEntries) { e.isSelected = val; }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final triState = _allSelected ? true : (_anySelected ? null : false);
    return ExpansionTile(
      leading: Checkbox(
        tristate: true,
        value: triState,
        onChanged: (v) => _toggleAll(v ?? false),
      ),
      title: Text(h3,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: sources.map((src) => _SourceGroup(src: src, onChanged: onChanged)).toList(),
    );
  }
}

/// Represents a single tars.MD source with its dictionaries listed inside.
class _SourceGroup extends StatelessWidget {
  const _SourceGroup({required this.src, required this.onChanged, this.showHeader = true});
  final _TarsSource src;
  final VoidCallback onChanged;
  final bool showHeader;

  List<_DictEntry> get _entries => src.entries ?? [];
  bool get _allSelected => _entries.isNotEmpty && _entries.every((e) => e.isSelected);
  bool get _anySelected => _entries.any((e) => e.isSelected);

  void _toggleAll(bool val) {
    for (final e in _entries) { e.isSelected = val; }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (src.isFetching) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text(src.displayPath, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ]),
      );
    }
    if (src.fetchFailed || _entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Icon(src.fetchFailed ? Icons.error_outline : Icons.inbox_outlined,
              size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            '${src.displayPath} — ${src.fetchFailed ? 'fetch failed' : 'no dictionaries'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ]),
      );
    }

    final triState = _allSelected ? true : (_anySelected ? null : false);
    return ExpansionTile(
      leading: Checkbox(
        tristate: true,
        value: triState,
        onChanged: (v) => _toggleAll(v ?? false),
      ),
      title: Text(
        src.displayPath,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      ),
      subtitle: Text(
        '${_entries.length} dictionar${_entries.length == 1 ? 'y' : 'ies'}',
        style: const TextStyle(fontSize: 11),
      ),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: _entries.map((entry) => CheckboxListTile(
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        value: entry.isSelected,
        title: Row(
          children: [
            Expanded(child: Text(entry.name, style: const TextStyle(fontSize: 13))),
            if (entry.status == _DictStatus.upToDate)
              const Text(' (Up to date)',
                  style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold))
            else if (entry.status == _DictStatus.updateAvailable)
              const Text(' (Update available)',
                  style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
            if (entry.sizeMb > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('(${entry.sizeMb.toStringAsFixed(1)} MB)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
          ],
        ),
        subtitle: entry.date.isNotEmpty
            ? Text(entry.date, style: const TextStyle(fontSize: 11))
            : null,
        onChanged: (v) {
          entry.isSelected = v ?? false;
          onChanged();
        },
      )).toList(),
    );
  }
}
