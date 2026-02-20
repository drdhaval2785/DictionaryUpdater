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

  DictionaryItem({
    required this.url,
    required this.name,
    required this.status,
    this.isSelected = false,
    this.isDownloading = false,
    this.downloadProgress = 0,
    this.isDownloaded = false,
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
  (_, __) => const DownloadBatchState(),
);

class SourceItemsNotifier extends AutoDisposeFamilyAsyncNotifier<
    List<DictionaryItem>, DictionarySource> {
  @override
  Future<List<DictionaryItem>> build(DictionarySource arg) async {
    final client = ref.watch(dictionaryClientProvider);
    final isar = ref.watch(isarProvider);

    final urls = await client.parseSourceList(arg.url);
    final items = <DictionaryItem>[];
    for (final url in urls) {
      final status = await client.getDictionaryStatus(url, isar);
      items.add(DictionaryItem(
        url: url,
        name: p.basename(url),
        status: status,
        // Only auto-select files that need action (new or update available)
        isSelected: status == DictionaryStatus.newFile ||
            status == DictionaryStatus.updateAvailable,
        isDownloaded: status == DictionaryStatus.upToDate,
      ));
    }
    return items;
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
  Future<void> downloadSelected() async {
    final items = state.valueOrNull;
    if (items == null) return;

    final selected =
        items.asMap().entries.where((e) => e.value.isSelected).toList();
    if (selected.isEmpty) return;

    final client = ref.read(dictionaryClientProvider);
    final isar = ref.read(isarProvider);

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
          onProgress: (progress) {
            _patch(listIndex,
                item.copyWith(isDownloading: true, downloadProgress: progress));
            _setDownloadState(
                ref.read(downloadStateProvider(arg)).copyWith(fileProgress: progress));
          },
        );

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
      } catch (_) {
        _patch(listIndex, item.copyWith(isDownloading: false));
      }
    }

    _setDownloadState(
        ref.read(downloadStateProvider(arg)).copyWith(
              active: false,
              done: selected.length,
              currentFile: '',
            ));
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
    final selectedCount = asyncItems.valueOrNull
            ?.where((i) => i.isSelected)
            .length ??
        0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.source, color: theme.colorScheme.primary),
        title: Row(
          children: [
            Expanded(
              child: Text(widget.source.label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (selectedCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$selectedCount selected',
                  style: TextStyle(
                      color: theme.colorScheme.onPrimary, fontSize: 11),
                ),
              ),
          ],
        ),
        subtitle: Text(
          widget.source.url.startsWith('data:')
              ? '(Pasted list)'
              : widget.source.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
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

        final selectedCount = items.where((i) => i.isSelected).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Download progress banner ─────────────────────────────────
            if (dlState.active) _DownloadBanner(state: dlState),

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
                          .downloadSelected(),
                      icon: const Icon(Icons.download, size: 16),
                      label: Text('Download $selectedCount'),
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

class _DownloadBanner extends StatelessWidget {
  final DownloadBatchState state;
  const _DownloadBanner({required this.state});

  @override
  Widget build(BuildContext context) {
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
      title: Text(item.name, style: const TextStyle(fontSize: 14)),
      subtitle: item.isDownloading
          ? LinearProgressIndicator(
              value: item.downloadProgress > 0 ? item.downloadProgress : null,
              minHeight: 3)
          : _statusChip(item.status),
      trailing: item.isDownloading ? null : _statusIcon(item.status),
      onTap: isLocked
          ? null
          : () =>
              ref.read(sourceItemsProvider(source).notifier).toggle(index),
    );
  }

  Widget _statusChip(DictionaryStatus status) {
    final (text, color) = switch (status) {
      DictionaryStatus.newFile => ('New', Colors.green),
      DictionaryStatus.updateAvailable => ('Update available', Colors.orange),
      DictionaryStatus.upToDate => ('Up to date', Colors.grey),
    };
    return Text(text,
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 11));
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
