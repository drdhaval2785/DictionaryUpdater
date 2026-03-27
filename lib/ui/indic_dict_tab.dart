import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'download_info_widget.dart';
import 'package:path/path.dart' as p;
import '../providers/providers.dart';
import '../services/storage_service.dart';

// ─── Data model ────────────────────────────────────────────────────────────────

class _TarsSource {
  _TarsSource({
    required this.tarsUrl,
    required this.displayPath,
    required this.breadcrumb,
    required this.folderPath,
  });

  final String tarsUrl;
  final String displayPath;
  final List<String> breadcrumb;
  final String folderPath;

  List<_DictEntry>? entries;
  bool isFetching = false;
  bool fetchFailed = false;

  bool get allSelected =>
      entries != null &&
      entries!.isNotEmpty &&
      entries!.every((_DictEntry e) => e.isSelected);
  bool get anySelected =>
      entries != null && entries!.any((_DictEntry e) => e.isSelected);
}

enum _DictStatus { newFile, updateAvailable, upToDate }

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
  bool isDownloading = false;
  double downloadProgress = 0;
}

// ─── Component ────────────────────────────────────────────────────────────────

class IndicDictTab extends ConsumerStatefulWidget {
  const IndicDictTab({super.key});

  @override
  ConsumerState<IndicDictTab> createState() => _IndicDictTabState();
}

class _IndicDictTabState extends ConsumerState<IndicDictTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingIndex = true;
  String? _indexError;
  List<_TarsSource> _sources = [];
  final List<String> _failedResources = [];
  final Set<String> _rootFiles = {}; // Files in the root DictionaryData folder
  CancelToken? _downloadCancelToken;
  int _batchTotal = 0;
  int _batchCurrent = 0;
  String _currentFileName = '';

  int get _fetchedCount => _sources.where((s) => s.entries != null).length;
  int get _totalCount => _sources.length;
  bool get _allFetched => _fetchedCount == _totalCount;

  List<_DictEntry> get _selectedDicts => _sources
      .expand<_DictEntry>((s) => s.entries ?? [])
      .where((e) => e.isSelected)
      .toList();

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    try {
      final storage = ref.read(storageServiceProvider);

      // 1. Fetch decompressed dictionary files in root DictionaryData folder once
      _rootFiles.clear();
      try {
        final rootDir = await storage.getStorageDirectory();
        if (await rootDir.exists()) {
          final list = await rootDir.list().toList();
          for (final f in list) {
            if (f is File) {
              // Get base name from decompressed dictionary file
              final baseName = storage.getBaseNameFromDictFile(
                p.basename(f.path),
              );
              if (baseName != null) {
                _rootFiles.add(baseName);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error listing root DictionaryData: $e');
      }

      final markdown = await ref.read(repoIndexProvider.future);
      final sources = _parseIndices(markdown, storage);
      if (mounted) {
        setState(() {
          _sources = sources;
          _loadingIndex = false;
        });
      }
      await _fetchAll(sources);
      await ref.read(lastCheckedAllProvider.notifier).updateTimestamp();
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
    final dio = ref.read(dioProvider);
    const batchSize = 5;
    for (var i = 0; i < sources.length; i += batchSize) {
      if (!mounted) break;
      final end = (i + batchSize < sources.length)
          ? i + batchSize
          : sources.length;
      final batch = sources.sublist(i, end);
      await Future.wait(batch.map((src) => _fetchOne(dio, src)));
    }

    if (_failedResources.isNotEmpty && mounted) {
      final uniqueFailures = _failedResources.toSet().toList();
      _failedResources.clear();
      _failedResources.addAll(uniqueFailures);
      _showFailureDialog();
    }
  }

  Future<void> _fetchOne(Dio dio, _TarsSource src) async {
    if (mounted) setState(() => src.isFetching = true);
    try {
      final storage = ref.read(storageServiceProvider);
      Directory dir;
      try {
        dir = await storage.getStorageDirectory(sourceName: src.folderPath);
      } catch (e) {
        if (mounted) {
          setState(() {
            src.isFetching = false;
            src.fetchFailed = true;
          });
        }
        return;
      }

      final localFiles = Set<String>.from(_rootFiles);
      if (await dir.exists()) {
        try {
          final list = await dir.list().toList();
          for (final f in list) {
            if (f is File) {
              // Get base name from decompressed dictionary file
              final baseName = storage.getBaseNameFromDictFile(
                p.basename(f.path),
              );
              if (baseName != null) {
                localFiles.add(baseName);
              }
            }
          }
        } catch (_) {}
      }

      final resp = await dio.get<String>(src.tarsUrl);
      final archiveUrls = _parseTarsMd(resp.data ?? '');
      final entries = archiveUrls
          .map((u) => _parseEntry(u, src.folderPath, localFiles, storage))
          .toList();

      if (mounted) {
        setState(() {
          src.entries = entries;
        });
      }

      final missingSizeEntries = entries.where((e) => e.sizeMb == 0.0).toList();
      if (missingSizeEntries.isNotEmpty) {
        const headBatchSize = 10;
        for (var i = 0; i < missingSizeEntries.length; i += headBatchSize) {
          if (!mounted) break;
          final batch = missingSizeEntries.sublist(
            i,
            (i + headBatchSize > missingSizeEntries.length)
                ? missingSizeEntries.length
                : i + headBatchSize,
          );

          await Future.wait(
            batch.map((entry) async {
              try {
                final headResp = await dio.head<dynamic>(entry.url);
                final contentLength = headResp.headers.value('content-length');
                if (contentLength != null && mounted) {
                  final bytes = int.tryParse(contentLength) ?? 0;
                  setState(() {
                    entry.sizeMb = bytes / (1024 * 1024);
                  });
                }
              } catch (_) {}
            }),
          );
        }
      }

      if (mounted) setState(() => src.isFetching = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          src.entries = [];
          src.isFetching = false;
          src.fetchFailed = true;
          final failLabel = '${src.folderPath} → ${src.tarsUrl}';
          if (!_failedResources.contains(failLabel))
            _failedResources.add(failLabel);
        });
      }
    }
  }

  Future<void> _downloadSelected() async {
    final selected = _selectedDicts;
    if (selected.isEmpty) return;

    final client = ref.read(dictionaryClientProvider);
    final isar = ref.read(isarProvider);

    _downloadCancelToken = CancelToken();
    ref.read(indicDownloadingProvider.notifier).state = true;

    setState(() {
      _batchTotal = selected.length;
      _batchCurrent = 0;
      _currentFileName = '';
    });

    for (final entry in selected) {
      if (!mounted) break;
      if (entry.status == _DictStatus.upToDate) continue;

      setState(() {
        entry.isDownloading = true;
        _currentFileName = entry.name;
      });
      try {
        await client.downloadDictionary(
          entry.url,
          isar,
          sourceName: entry.folderPath,
          cancelToken: _downloadCancelToken,
          onProgress: (double progress) {
            if (mounted) {
              setState(() => entry.downloadProgress = progress);
            }
          },
        );
        if (mounted) {
          setState(() {
            entry.isSelected = false;
          });
        }
        if (mounted) {
          setState(() {
            _batchCurrent++;
          });
        }
      } catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) {
          debugPrint('Download cancelled: ${entry.name}');
          break;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download ${entry.name}: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            entry.isDownloading = false;
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _currentFileName = '';
      });
    }

    _downloadCancelToken = null;
    ref.read(indicDownloadingProvider.notifier).state = false;
    await _loadIndex();
  }

  void _cancelDownloads() {
    _downloadCancelToken?.cancel('User cancelled');
    _downloadCancelToken = null;
  }

  void _showFailureDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection Issues'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Could not connect to some resources. Check your internet connection.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              width: double.maxFinite,
              child: ListView.builder(
                itemCount: _failedResources.length,
                itemBuilder: (context, index) => Text(
                  '• ${_failedResources[index]}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen(refreshTriggerProvider, (prev, next) {
      if (next > 0) {
        _loadIndex();
      }
    });

    ref.listen(indicCancelTriggerProvider, (prev, next) {
      if (next > 0) {
        _cancelDownloads();
      }
    });

    if (_loadingIndex) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading repository…'),
          ],
        ),
      );
    }
    if (_indexError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_indexError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadIndex, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final byH2 = <String, Map<String, List<_TarsSource>>>{};
    for (final src in _sources) {
      final h2 = src.breadcrumb[0];
      final h3 = src.breadcrumb.length > 1 ? src.breadcrumb[1] : '';
      byH2.putIfAbsent(h2, () => {})[h3] = (byH2[h2]?[h3] ?? [])..add(src);
    }

    final selectedCount = _selectedDicts.length;
    final totalSizeMb = _selectedDicts.fold<double>(
      0.0,
      (sum, e) => sum + e.sizeMb,
    );

    final allEntries = _sources
        .expand<_DictEntry>((s) => s.entries ?? <_DictEntry>[])
        .toList();
    final totalAvailable = allEntries.length;
    final totalUpToDate = allEntries
        .where((e) => e.status == _DictStatus.upToDate)
        .length;
    final totalNewer = allEntries
        .where((e) => e.status == _DictStatus.updateAvailable)
        .length;
    final totalDownloaded = totalUpToDate + totalNewer;

    final isDownloading = allEntries.any((e) => e.isDownloading);

    return Column(
      children: [
        if (!_allFetched)
          LinearProgressIndicator(
            value: _totalCount == 0 ? null : _fetchedCount / _totalCount,
          ),
        // Summary Stats Header
        if (_allFetched && totalAvailable > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalAvailable dictionaries available • $totalDownloaded downloaded',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$totalUpToDate up to date • $totalNewer have newer version',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: byH2.entries.map((h2Entry) {
              return _H2Group(
                h2: h2Entry.key,
                byH3: h2Entry.value,
                onChanged: () => setState(() {}),
              );
            }).toList(),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: isDownloading
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _batchTotal > 0
                                      ? _batchCurrent / _batchTotal
                                      : 0,
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$_batchCurrent/$_batchTotal downloaded',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_currentFileName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Downloading: $_currentFileName',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 8),
                      const DownloadInfoWidget(),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _cancelDownloads,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop Downloads'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DownloadInfoWidget(),
                      if (selectedCount > 0) ...[
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _downloadSelected,
                          icon: const Icon(Icons.download),
                          label: Text(
                            'Download $selectedCount (${totalSizeMb.toStringAsFixed(1)} MB)',
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── Group widgets (Simplified from browser) ──────────────────────────────────

class _H2Group extends StatelessWidget {
  const _H2Group({
    required this.h2,
    required this.byH3,
    required this.onChanged,
  });
  final String h2;
  final Map<String, List<_TarsSource>> byH3;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final allEntries = byH3.values
        .expand<_TarsSource>((v) => v)
        .expand<_DictEntry>((s) => s.entries ?? [])
        .toList();
    final allSelected =
        allEntries.isNotEmpty &&
        allEntries.every((_DictEntry e) => e.isSelected);
    final anySelected = allEntries.any((_DictEntry e) => e.isSelected);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      elevation: 1,
      child: ExpansionTile(
        leading: Checkbox(
          tristate: true,
          value: allSelected ? true : (anySelected ? null : false),
          onChanged: (v) {
            for (final e in allEntries) {
              e.isSelected = v ?? false;
            }
            onChanged();
          },
        ),
        title: Text(
          h2,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        children: byH3.entries.map((h3Entry) {
          final h3 = h3Entry.key;
          final sources = h3Entry.value;
          if (h3.isEmpty) {
            return Column(
              children: sources
                  .map(
                    (src) => _SourceGroup(
                      src: src,
                      onChanged: onChanged,
                      showHeader: false,
                    ),
                  )
                  .toList(),
            );
          }
          return _H3Group(h3: h3, sources: sources, onChanged: onChanged);
        }).toList(),
      ),
    );
  }
}

class _H3Group extends StatelessWidget {
  const _H3Group({
    required this.h3,
    required this.sources,
    required this.onChanged,
  });
  final String h3;
  final List<_TarsSource> sources;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final allEntries = sources
        .expand<_DictEntry>((s) => s.entries ?? [])
        .toList();
    final allSelected =
        allEntries.isNotEmpty &&
        allEntries.every((_DictEntry e) => e.isSelected);
    final anySelected = allEntries.any((_DictEntry e) => e.isSelected);

    return ExpansionTile(
      leading: Checkbox(
        tristate: true,
        value: allSelected ? true : (anySelected ? null : false),
        onChanged: (v) {
          for (final e in allEntries) {
            e.isSelected = v ?? false;
          }
          onChanged();
        },
      ),
      title: Text(
        h3,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: sources
          .map((src) => _SourceGroup(src: src, onChanged: onChanged))
          .toList(),
    );
  }
}

class _SourceGroup extends StatelessWidget {
  const _SourceGroup({
    required this.src,
    required this.onChanged,
    this.showHeader = true,
  });
  final _TarsSource src;
  final VoidCallback onChanged;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    if (src.isFetching) {
      return const ListTile(
        dense: true,
        leading: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Loading...', style: TextStyle(fontSize: 12)),
      );
    }
    final entries = src.entries ?? [];
    if (src.fetchFailed || entries.isEmpty) {
      return ListTile(
        dense: true,
        leading: Icon(
          src.fetchFailed ? Icons.error_outline : Icons.inbox_outlined,
          size: 16,
          color: Colors.grey,
        ),
        title: Text(
          src.displayPath,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    final allSelected = entries.every((_DictEntry e) => e.isSelected);
    final anySelected = entries.any((_DictEntry e) => e.isSelected);

    return ExpansionTile(
      leading: Checkbox(
        tristate: true,
        value: allSelected ? true : (anySelected ? null : false),
        onChanged: (v) {
          for (final e in entries) {
            e.isSelected = v ?? false;
          }
          onChanged();
        },
      ),
      title: Text(
        src.displayPath,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      ),
      subtitle: Text(
        '${entries.length} items',
        style: const TextStyle(fontSize: 11),
      ),
      children: entries
          .map(
            (entry) => CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: entry.isSelected,
              title: Text(entry.name, style: const TextStyle(fontSize: 13)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.date} • ${entry.sizeMb.toStringAsFixed(1)} MB',
                    style: const TextStyle(fontSize: 11),
                  ),
                  if (entry.status == _DictStatus.upToDate)
                    const Text(
                      'Up to date',
                      style: TextStyle(fontSize: 11, color: Colors.green),
                    )
                  else if (entry.status == _DictStatus.updateAvailable)
                    const Text(
                      'Update available',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  if (entry.isDownloading)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(
                        value: entry.downloadProgress,
                      ),
                    ),
                ],
              ),
              onChanged: (v) {
                entry.isSelected = v ?? false;
                onChanged();
              },
            ),
          )
          .toList(),
    );
  }
}

// ─── Shared Parsing Logic ──────────────────────────────────────────────────────

String _displayPath(String url) {
  final ghIdx = url.indexOf('/gh-pages/');
  if (ghIdx == -1) {
    final segs = Uri.parse(url).pathSegments;
    final tarsIdx = segs.lastIndexOf('tars');
    if (tarsIdx >= 2) return segs.sublist(tarsIdx - 2, tarsIdx).join('/');
    return segs.take(segs.length - 2).lastOrNull ?? url;
  }
  final afterGhPages = url.substring(ghIdx + '/gh-pages/'.length);
  return afterGhPages
          .replaceAll(RegExp(r'/tars/tars.*\.MD$', caseSensitive: false), '')
          .isEmpty
      ? 'tars'
      : afterGhPages.replaceAll(
          RegExp(r'/tars/tars.*\.MD$', caseSensitive: false),
          '',
        );
}

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
        final folderPath = ['Indic-dict', ...crumbs].join('/');
        sources.add(
          _TarsSource(
            tarsUrl: url,
            displayPath: _displayPath(url),
            breadcrumb: crumbs,
            folderPath: folderPath,
          ),
        );
      }
    }
  }
  return sources;
}

List<String> _parseTarsMd(String content) {
  final re = RegExp(
    r'https?://\S+?\.(?:tar\.gz|tgz|tar\.bz2|tbz2|tar\.xz|txz|tar\.lzma|tlz|tar\.zst|tzst|zip|7z|rar|bz2|xz|lzma|zst|dz)',
    caseSensitive: false,
  );
  return re.allMatches(content).map((m) => m.group(0)!).toList();
}

_DictEntry _parseEntry(
  String url,
  String folderPath,
  Set<String> localFiles,
  StorageService storage,
) {
  // 1. Decode URL components (e.g. %20 -> ' ') before sanitizing
  final rawFilename = Uri.decodeComponent(url.split('/').last);
  final filename = storage.sanitizeFileName(rawFilename);

  final sizeRe = RegExp(r'_([\d.]+)MB\.', caseSensitive: false);
  final sm = sizeRe.firstMatch(filename);
  final sizeMb = sm != null ? (double.tryParse(sm.group(1)!) ?? 0.0) : 0.0;

  final fullRe = RegExp(
    r'^(.+?)_(\d{8})_(\d{6})_([\d.]+)MB\.(.+)$',
    caseSensitive: false,
  );
  final m = fullRe.firstMatch(filename);

  String name = filename;
  String date = '';
  String? baseName;

  if (m != null) {
    baseName = m.group(1)!;
    name = baseName.replaceAll('_', ' ');
    final rd = m.group(2)!;
    date = '${rd.substring(0, 4)}-${rd.substring(4, 6)}-${rd.substring(6, 8)}';
  } else {
    // Fallback to extractBaseName from storage service if regex fails
    baseName = storage.extractBaseName(filename);
    if (baseName != null) {
      name = baseName.replaceAll('_', ' ');
    }
  }

  _DictStatus status = _DictStatus.newFile;

  // Check if we have decompressed files for this dictionary
  // localFiles now contains base names of decompressed dictionary files
  if (baseName != null && localFiles.contains(baseName)) {
    status = _DictStatus.upToDate;
  } else if (baseName != null) {
    // Check for any file with the same base name to see if it's an update
    final existingFile = localFiles.firstWhere(
      (f) => f.startsWith(baseName!) || f == baseName,
      orElse: () => '',
    );

    if (existingFile.isNotEmpty) {
      // We have a file with same base name - check timestamps
      final remoteTs = storage.extractTimestamp(filename);

      // For local timestamp, we need to look at the checksum metadata
      // This would require async call, so for now use simple comparison
      if (remoteTs != null) {
        // If we have remote timestamp but no local match, it's an update
        status = _DictStatus.updateAvailable;
      } else {
        // No timestamp - assume update available
        status = _DictStatus.updateAvailable;
      }
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

  // Only auto-select if a new file or an update is available
  entry.isSelected = (status != _DictStatus.upToDate);

  return entry;
}
