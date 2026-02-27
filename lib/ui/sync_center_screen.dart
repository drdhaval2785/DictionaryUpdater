import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/providers.dart';
import '../models/dictionary_models.dart';
import 'source_expansion_panel.dart';
import 'add_dictionary_dialog.dart';

class SyncCenterScreen extends ConsumerStatefulWidget {
  const SyncCenterScreen({super.key});

  @override
  ConsumerState<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends ConsumerState<SyncCenterScreen> {
  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourcesProvider);

    // Collect total selected across all sources for the global FAB
    final allSources = sourcesAsync.valueOrNull ?? [];
    int totalSelected = 0;
    double totalSizeMb = 0;
    bool isAnyDownloading = false;
    for (final source in allSources) {
      final items = ref.watch(sourceItemsProvider(source)).valueOrNull ?? [];
      final selectedItems = items.where((i) => i.isSelected).toList();
      totalSelected += selectedItems.length;
      for (final item in selectedItems) {
        totalSizeMb += item.sizeMb ?? 0;
      }
      final downloadState = ref.watch(downloadStateProvider(source));
      if (downloadState.active) {
        isAnyDownloading = true;
      }
    }


    return Stack(
      children: [
        sourcesAsync.when(
          data: (sources) => sources.isEmpty
              ? _buildEmptyState(context)
              : Column(
                  children: [
                    if (totalSelected > 0)
                      Container(
                        width: double.infinity,
                        color: Theme.of(context).colorScheme.primaryContainer,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          'Total Selection: $totalSelected dictionaries (${totalSizeMb.toStringAsFixed(1)} MB)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: sources.length,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemBuilder: (_, i) =>
                            SourceExpansionPanel(source: sources[i]),
                      ),
                    ),
                  ],
                ),
          loading: () => _buildShimmer(),
          error: (err, _) => _buildError(err.toString()),
        ),
        if (totalSelected > 0 || isAnyDownloading)
          Positioned(
            right: 16,
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAnyDownloading)
                  FloatingActionButton.extended(
                    heroTag: 'global_stop',
                    onPressed: () {
                      for (final source in allSources) {
                        ref.read(sourceItemsProvider(source).notifier).cancelDownloads();
                      }
                    },
                    backgroundColor: Theme.of(context).colorScheme.errorContainer,
                    foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop All'),
                  ),
                if (totalSelected > 0 && !isAnyDownloading)
                  FloatingActionButton.extended(
                    heroTag: 'global_download',
                    icon: const Icon(Icons.download_rounded),
                    label: Text(totalSizeMb > 0
                        ? 'Download $totalSelected (${totalSizeMb.toStringAsFixed(1)} MB)'
                        : 'Download $totalSelected'),
                    onPressed: () => _downloadAll(context, allSources, totalSizeMb),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Global download ────────────────────────────────────────────────────────

  Future<void> _downloadAll(BuildContext context,
      List<DictionarySource> sources, double totalSizeMb) async {
    // capture early to avoid analyzer complaint about using `context` after
    // awaits (even though we check `mounted` later).
    final ctx = context;

    final storageService = ref.read(storageServiceProvider);
    final storagePath = await storageService.getStoragePathDisplay();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx2) => AlertDialog(
        title: Text(totalSizeMb > 50 ? 'Large Download' : 'Confirm Download'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are about to download ${totalSizeMb.toStringAsFixed(1)} MB of data. Are you sure?'),
            const SizedBox(height: 16),
            const Text('Storage Location:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(storagePath, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx2, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx2, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;

    for (final DictionarySource source in sources) {
      if (!mounted) return;

      final items = ref.read(sourceItemsProvider(source)).valueOrNull ?? [];
      final hasSelected = items.any((i) => i.isSelected);

      if (hasSelected) {
        if (!mounted) return;
        final notifier = ref.read(sourceItemsProvider(source).notifier);
        // ignore: use_build_context_synchronously
        await notifier.downloadSelected(ctx);
        if (!mounted) return;
      }
    }
  }

  // ─── Empty state ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Add Dictionaries by clicking Add Dictionary symbol above',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => showAddDictionaryDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add Dictionary'),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      itemCount: 4,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: Container(width: 40, height: 40, color: Colors.white),
            title: Container(height: 16, color: Colors.white),
            subtitle: Container(width: 200, height: 12, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildError(String err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(err, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
