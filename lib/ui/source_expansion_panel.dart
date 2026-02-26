import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/dictionary_models.dart';
import '../providers/providers.dart';
import '../services/dictionary_client.dart';

// ─── ViewModel ────────────────────────────────────────────────────────────────

class DictionaryItem {
  final String url;
  final String name;
  DictionaryStatus status;
  bool isSelected;
  bool isDownloading;
  double downloadProgress;
  bool isDownloaded;
  final DateTime? remoteLastModified;
  final DateTime? lastChecked;
  final double? sizeMb;

  DictionaryItem({
    required this.url,
    required this.name,
    required this.status,
    this.isSelected = false,
    this.isDownloading = false,
    this.downloadProgress = 0,
    this.isDownloaded = false,
    this.remoteLastModified,
    this.lastChecked,
    this.sizeMb,
  });

  DictionaryItem copyWith({
    DictionaryStatus? status,
    bool? isSelected,
    bool? isDownloading,
    double? downloadProgress,
    bool? isDownloaded,
  }) =>
      DictionaryItem(
        url: url,
        name: name,
        status: status ?? this.status,
        isSelected: isSelected ?? this.isSelected,
        isDownloading: isDownloading ?? this.isDownloading,
        downloadProgress: downloadProgress ?? this.downloadProgress,
        isDownloaded: isDownloaded ?? this.isDownloaded,
        remoteLastModified: remoteLastModified,
        lastChecked: lastChecked,
        sizeMb: sizeMb,
      );
}

// ─── Download state ───────────────────────────────────────────────────────────

class DownloadBatchState {
  final bool active;
  final int done;
  final int total;
  final String currentFile;
  final double fileProgress;

  const DownloadBatchState({
    this.active = false,
    this.done = 0,
    this.total = 0,
    this.currentFile = '',
    this.fileProgress = 0,
  });

  DownloadBatchState copyWith({
    bool? active,
    int? done,
    int? total,
    String? currentFile,
    double? fileProgress,
  }) =>
      DownloadBatchState(
        active: active ?? this.active,
        done: done ?? this.done,
        total: total ?? this.total,
        currentFile: currentFile ?? this.currentFile,
        fileProgress: fileProgress ?? this.fileProgress,
      );
}

// ─── Providers ────────────────────────────────────────────────────────────────

final sourceItemsProvider = AutoDisposeAsyncNotifierProviderFamily<
    SourceItemsNotifier, List<DictionaryItem>, DictionarySource>(
  SourceItemsNotifier.new,
);

final downloadStateProvider = StateProvider.autoDispose
    .family<DownloadBatchState, DictionarySource>(
  (ref, arg) => const DownloadBatchState(),
);

class SourceItemsNotifier extends AutoDisposeFamilyAsyncNotifier<
    List<DictionaryItem>, DictionarySource> {
  CancelToken? _cancelToken;

  @override
  Future<List<DictionaryItem>> build(DictionarySource arg) async {
    final client = ref.watch(dictionaryClientProvider);
    final isar = ref.watch(isarProvider);

    List<String> urls = [];
    try {
      urls = await client.parseSourceList(arg.url);
    } catch (e) {
      debugPrint('Failed to parse source list for ${arg.label}: $e');
      _reportFailure(arg.label);
      return [];
    }

    final items = <DictionaryItem>[];
    for (final url in urls) {
      try {
        final status = await client.getDictionaryStatus(url, isar, sourceName: arg.label);
        // Load stored metadata for timestamps
        final meta = await client.getMetadata(url, isar, sourceName: arg.label);

        // Parse sizeMb from filename if available
        double? sizeMb;
        final fileName = p.basename(url);
        final sizeRe = RegExp(r'_([\d.]+)MB\.', caseSensitive: false);
        final m = sizeRe.firstMatch(fileName);
        if (m != null) {
          sizeMb = double.tryParse(m.group(1)!);
        }

        items.add(DictionaryItem(
          url: url,
          name: fileName,
          status: status,
          isSelected: status == DictionaryStatus.newFile ||
              status == DictionaryStatus.updateAvailable,
          isDownloaded: status == DictionaryStatus.upToDate,
          remoteLastModified: meta?.remoteLastModified,
          lastChecked: meta?.lastChecked,
          sizeMb: sizeMb ?? meta?.sizeMb,
        ));
      } catch (e) {
        debugPrint('Failed to check status for $url: $e');
        _reportFailure(p.basename(url));
      }
    }
    return items;
  }

  void _reportFailure(String resource) {
    final list = ref.read(failedResourcesProvider);
    if (!list.contains(resource)) {
      ref.read(failedResourcesProvider.notifier).state = [...list, resource];
    }
  }

  void toggle(int index) {
    final items = state.valueOrNull;
    if (items == null) return;
    final updated = List<DictionaryItem>.from(items);
    updated[index] = updated[index].copyWith(isSelected: !updated[index].isSelected);
    state = AsyncData(updated);
  }

  void selectAll(bool value) {
    final items = state.valueOrNull;
    if (items == null) return;
    state = AsyncData(items.map((e) => e.copyWith(isSelected: value)).toList());
  }

  /// Download all selected items and persist metadata to Isar.
  Future<void> downloadSelected(BuildContext context) async {
    final items = state.valueOrNull;
    if (items == null) return;

    final selected =
        items.asMap().entries.where((e) => e.value.isSelected).toList();
    if (selected.isEmpty) return;

    final totalSizeMb = selected.fold<double>(0, (sum, e) => sum + (e.value.sizeMb ?? 0));
    if (totalSizeMb > 50) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large Download'),
          content: Text(
              'You are about to download ${totalSizeMb.toStringAsFixed(1)} MB from this source. Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Download'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final client = ref.read(dictionaryClientProvider);
    final isar = ref.read(isarProvider);

    _cancelToken = CancelToken();

    ref.read(downloadStateProvider(arg).notifier).state = DownloadBatchState(
      active: true,
      done: 0,
      total: selected.length,
    );

    for (var i = 0; i < selected.length; i++) {
      final MapEntry<int, DictionaryItem> entry = selected[i];
      final int listIndex = entry.key;
      final DictionaryItem item = entry.value;

      _patch(listIndex, item.copyWith(isDownloading: true, downloadProgress: 0));
      if (!context.mounted) return;
      _setDownloadState(
          ref.read(downloadStateProvider(arg)).copyWith(
                done: i,
                currentFile: item.name,
                fileProgress: 0,
              ));

      try {
        await client.downloadDictionary(
          item.url,
          isar,
          sourceName: arg.label,
          cancelToken: _cancelToken,
          onProgress: (progress) {
            if (context.mounted) {
              _patch(listIndex,
                  item.copyWith(isDownloading: true, downloadProgress: progress));
              _setDownloadState(
                  ref.read(downloadStateProvider(arg)).copyWith(fileProgress: progress));
            }
          },
        );

        if (!context.mounted) return;

        _patch(
          listIndex,
          item.copyWith(
            isDownloading: false,
            isDownloaded: true,
            downloadProgress: 1,
            status: DictionaryStatus.upToDate,
            isSelected: false,
          ),
        );
      } catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) {
          debugPrint('Download cancelled for ${item.name}');
          if (context.mounted) {
            _patch(listIndex, item.copyWith(isDownloading: false));
          }
          break; // Stop the whole batch loop
        }
        if (context.mounted) {
          _patch(listIndex, item.copyWith(isDownloading: false));
        }
      }
    }

    _cancelToken = null;

    if (context.mounted) {
      _setDownloadState(
          ref.read(downloadStateProvider(arg)).copyWith(
                active: false,
                done: selected.length,
                currentFile: '',
              ));
    }
  }

  void cancelDownloads() {
    _cancelToken?.cancel('User stopped the download');
    _cancelToken = null;
  }

  void _patch(int index, DictionaryItem item) {
    final items = state.valueOrNull;
    if (items == null) return;
    final updated = List<DictionaryItem>.from(items);
    updated[index] = item;
    state = AsyncData(updated);
  }

  void _setDownloadState(DownloadBatchState s) =>
      ref.read(downloadStateProvider(arg).notifier).state = s;
}

// ─── SourceExpansionPanel ─────────────────────────────────────────────────────

class SourceExpansionPanel extends ConsumerStatefulWidget {
  final DictionarySource source;
  const SourceExpansionPanel({super.key, required this.source});

  @override
  ConsumerState<SourceExpansionPanel> createState() =>
      _SourceExpansionPanelState();
}

class _SourceExpansionPanelState extends ConsumerState<SourceExpansionPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Watch item count & selection for badge
    final asyncItems = ref.watch(sourceItemsProvider(widget.source));
    final items = asyncItems.valueOrNull ?? [];
    final selectedItems = items.where((i) => i.isSelected).toList();
    final selectedCount = selectedItems.length;
    final selectedSize = selectedItems.fold<double>(
        0.0, (double sum, i) => sum + (i.sizeMb ?? 0.0));
    final totalFiles = items.length;
    final totalSize =
        items.fold<double>(0.0, (double sum, i) => sum + (i.sizeMb ?? 0.0));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.source, color: theme.colorScheme.primary),
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.source.label,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.visible,
              ),
            ),
            if (selectedCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary.withAlpha(100)),
                  ),
                  child: Text(
                    '$selectedCount (${selectedSize.toStringAsFixed(1)} MB)',
                    style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          _sourceSubtitle(widget.source, totalFiles, totalSize),
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Remove source',
              onPressed: () => _confirmDelete(context),
            ),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
        onExpansionChanged: (v) => setState(() => _expanded = v),
        children: [if (_expanded) _DictionaryList(source: widget.source)],
      ),
    );
  }

  String _sourceSubtitle(
      DictionarySource source, int totalFiles, double totalSize) {
    final base = (!source.url.startsWith('data:'))
        ? source.url
        : ((source.label.startsWith('Indic-dict'))
            ? 'Indic-dict'
            : '(Pasted list)');
    return '$base • $totalFiles files (${totalSize.toStringAsFixed(1)} MB)';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Source?'),
        content: Text('Remove "${widget.source.label}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(sourcesProvider.notifier).removeSource(widget.source.id);
    }
  }
}

// ─── Dictionary list (inside accordion) ──────────────────────────────────────

class _DictionaryList extends ConsumerWidget {
  final DictionarySource source;
  const _DictionaryList({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(sourceItemsProvider(source));
    final dlState = ref.watch(downloadStateProvider(source));
    final theme = Theme.of(context);

    return asyncItems.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(height: 8),
          Text(err.toString(),
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center),
          TextButton.icon(
            onPressed: () => ref.invalidate(sourceItemsProvider(source)),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ]),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No dictionary files found in this source.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
          );
        }

        final selectedItems = items.where((i) => i.isSelected).toList();
        final selectedCount = selectedItems.length;
        final totalSizeMb = selectedItems.fold<double>(0, (sum, i) => sum + (i.sizeMb ?? 0));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Download progress banner ─────────────────────────────────
            if (dlState.active) _DownloadBanner(state: dlState, source: source),

            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    tristate: true,
                    value: selectedCount == items.length
                        ? true
                        : selectedCount == 0
                            ? false
                            : null,
                    onChanged: dlState.active
                        ? null
                        : (val) => ref
                            .read(sourceItemsProvider(source).notifier)
                            .selectAll(val ?? false),
                  ),
                  Text('${items.length} files',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (selectedCount > 0 && !dlState.active)
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(sourceItemsProvider(source).notifier)
                          .downloadSelected(context),
                      icon: const Icon(Icons.download, size: 16),
                      label: Text(totalSizeMb > 0
                          ? 'Download $selectedCount (${totalSizeMb.toStringAsFixed(1)} MB)'
                          : 'Download $selectedCount'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── File rows ─────────────────────────────────────────────────
            ...items.asMap().entries.map((entry) => _DictionaryTile(
                  item: entry.value,
                  index: entry.key,
                  source: source,
                  isLocked: dlState.active,
                  theme: theme,
                )),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─── Download progress banner ─────────────────────────────────────────────────

class _DownloadBanner extends ConsumerWidget {
  final DownloadBatchState state;
  final DictionarySource source;
  const _DownloadBanner({required this.state, required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final overall = state.total > 0 ? state.done / state.total : 0.0;

    return Container(
      color: cs.primaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
            Text(
              '${state.done} / ${state.total} downloaded',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => ref.read(sourceItemsProvider(source).notifier).cancelDownloads(),
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Stop', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: cs.error,
              ),
            ),
          ]),
        if (state.currentFile.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Downloading: ${state.currentFile}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: overall,
            minHeight: 6,
            backgroundColor: cs.onPrimaryContainer.withAlpha(40),
          ),
        ),
        if (state.fileProgress > 0 && state.fileProgress < 1) ...[
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: state.fileProgress,
                  minHeight: 4,
                  color: cs.secondary,
                  backgroundColor: cs.onPrimaryContainer.withAlpha(30),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${(state.fileProgress * 100).round()}%',
                style: const TextStyle(fontSize: 11)),
          ]),
        ],
      ]),
    );
  }
}

// ─── Single dictionary tile ───────────────────────────────────────────────────

class _DictionaryTile extends ConsumerWidget {
  final DictionaryItem item;
  final int index;
  final DictionarySource source;
  final bool isLocked;
  final ThemeData theme;

  const _DictionaryTile({
    required this.item,
    required this.index,
    required this.source,
    required this.isLocked,
    required this.theme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      enabled: !isLocked,
      leading: item.isDownloading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: item.downloadProgress > 0 ? item.downloadProgress : null,
                strokeWidth: 2.5,
              ))
          : Icon(
              item.isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: item.isSelected ? theme.colorScheme.primary : Colors.grey,
            ),
      title: Row(
        children: [
          Expanded(child: Text(item.name, style: const TextStyle(fontSize: 14))),
          if (item.sizeMb != null)
            Text('(${item.sizeMb!.toStringAsFixed(1)} MB)',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      subtitle: item.isDownloading
          ? LinearProgressIndicator(
              value: item.downloadProgress > 0 ? item.downloadProgress : null,
              minHeight: 3)
          : _buildSubtitle(item),
      trailing: item.isDownloading ? null : _statusIcon(item.status),
      onTap: isLocked
          ? null
          : () =>
              ref.read(sourceItemsProvider(source).notifier).toggle(index),
    );
  }

  Widget _buildSubtitle(DictionaryItem item) {
    final lines = <String>[];
    // Status label
    final statusText = switch (item.status) {
      DictionaryStatus.newFile => 'New',
      DictionaryStatus.updateAvailable => 'Update available',
      DictionaryStatus.upToDate => 'Up to date',
    };
    lines.add(statusText);
    // URL
    lines.add('(${item.url})');
    // Upstream last-modified
    if (item.remoteLastModified != null) {
      lines.add('Last changed upstream on ${_fmtDt(item.remoteLastModified!)}');
    }
    // Machine last checked
    if (item.lastChecked != null) {
      lines.add('Machine checked upstream on ${_fmtDt(item.lastChecked!)}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .map((l) => Text(l,
              style: TextStyle(
                fontSize: 11,
                color: l.startsWith('New')
                    ? Colors.green
                    : l.startsWith('Update')
                        ? Colors.orange
                        : Colors.grey,
                fontWeight: l.startsWith('New') || l.startsWith('Update')
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis))
          .toList(),
    );
  }

  String _fmtDt(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _statusIcon(DictionaryStatus status) {
    return Icon(
      status == DictionaryStatus.upToDate
          ? Icons.check_circle_outline
          : Icons.download_for_offline_outlined,
      color: switch (status) {
        DictionaryStatus.newFile => Colors.green,
        DictionaryStatus.updateAvailable => Colors.orange,
        DictionaryStatus.upToDate => Colors.grey,
      },
      size: 20,
    );
  }
}
